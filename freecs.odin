package freecs

import "core:mem"
import "core:slice"
import "core:fmt"

Entity :: struct {
    id:         u32,
    generation: u32,
}

Entity_Location :: struct {
    generation:      u32,
    archetype_index: u32,
    row:             u32,
    alive:           bool,
}

Component_Column :: struct {
    data:      [dynamic]byte,
    elem_size: int,
    tid:       typeid,
}

Archetype :: struct {
    mask:     u64,
    entities: [dynamic]Entity,
    columns:  [dynamic]Component_Column,
    type_map: map[typeid]int,
}

World :: struct {
    locations:       [dynamic]Entity_Location,
    archetypes:      [dynamic]Archetype,
    archetype_index: map[u64]int,
    type_bits:       map[typeid]u64,
    next_entity_id:  u32,
    free_entities:   [dynamic]Entity,
    next_bit:        u64,
}

create_world :: proc() -> World {
    return World{
        locations       = make([dynamic]Entity_Location),
        archetypes      = make([dynamic]Archetype),
        archetype_index = make(map[u64]int),
        type_bits       = make(map[typeid]u64),
        free_entities   = make([dynamic]Entity),
        next_bit        = 1,
    }
}

destroy_world :: proc(world: ^World) {
    for &arch in world.archetypes {
        for &col in arch.columns {
            delete(col.data)
        }
        delete(arch.columns)
        delete(arch.entities)
        delete(arch.type_map)
    }
    delete(world.archetypes)
    delete(world.locations)
    delete(world.archetype_index)
    delete(world.type_bits)
    delete(world.free_entities)
}

register :: proc(world: ^World, $T: typeid) -> u64 {
    tid := typeid_of(T)
    if bit, ok := world.type_bits[tid]; ok {
        return bit
    }
    bit := world.next_bit
    world.next_bit <<= 1
    world.type_bits[tid] = bit
    return bit
}

Type_Info_Entry :: struct {
    tid:  typeid,
    size: int,
    data: rawptr,
}

find_or_create_archetype :: proc(world: ^World, mask: u64, type_info: []Type_Info_Entry) -> int {
    if idx, ok := world.archetype_index[mask]; ok {
        return idx
    }

    arch_idx := len(world.archetypes)
    arch := Archetype{
        mask     = mask,
        entities = make([dynamic]Entity),
        columns  = make([dynamic]Component_Column),
        type_map = make(map[typeid]int),
    }

    for entry in type_info {
        col_idx := len(arch.columns)
        arch.type_map[entry.tid] = col_idx
        append(&arch.columns, Component_Column{
            data      = make([dynamic]byte),
            elem_size = entry.size,
            tid       = entry.tid,
        })
    }

    append(&world.archetypes, arch)
    world.archetype_index[mask] = arch_idx
    return arch_idx
}

alloc_entity :: proc(world: ^World) -> Entity {
    if len(world.free_entities) > 0 {
        e := pop(&world.free_entities)
        return e
    }

    id := world.next_entity_id
    world.next_entity_id += 1

    for len(world.locations) <= int(id) {
        append(&world.locations, Entity_Location{})
    }

    return Entity{id = id, generation = 0}
}

spawn :: proc(world: ^World, components: ..any) -> Entity {
    if len(components) == 0 {
        return Entity{}
    }

    mask: u64 = 0
    type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)

    for comp in components {
        tid := comp.id
        if bit, ok := world.type_bits[tid]; ok {
            mask |= bit
            append(&type_info, Type_Info_Entry{
                tid  = tid,
                size = type_info_of(tid).size,
                data = comp.data,
            })
        }
    }

    if mask == 0 {
        return Entity{}
    }

    arch_idx := find_or_create_archetype(world, mask, type_info[:])
    arch := &world.archetypes[arch_idx]

    entity := alloc_entity(world)
    row := len(arch.entities)
    append(&arch.entities, entity)

    for entry in type_info {
        if col_idx, ok := arch.type_map[entry.tid]; ok {
            col := &arch.columns[col_idx]
            old_len := len(col.data)
            resize(&col.data, old_len + entry.size)
            if entry.data != nil && entry.size > 0 {
                mem.copy(&col.data[old_len], entry.data, entry.size)
            }
        }
    }

    world.locations[entity.id] = Entity_Location{
        generation      = entity.generation,
        archetype_index = u32(arch_idx),
        row             = u32(row),
        alive           = true,
    }

    return entity
}

despawn :: proc(world: ^World, entity: Entity) -> bool {
    if int(entity.id) >= len(world.locations) {
        return false
    }

    loc := &world.locations[entity.id]
    if !loc.alive || loc.generation != entity.generation {
        return false
    }

    arch := &world.archetypes[loc.archetype_index]
    row := int(loc.row)
    last_row := len(arch.entities) - 1

    if row < last_row {
        last_entity := arch.entities[last_row]
        arch.entities[row] = last_entity
        world.locations[last_entity.id].row = u32(row)

        for &col in arch.columns {
            if col.elem_size > 0 {
                src_start := last_row * col.elem_size
                dst_start := row * col.elem_size
                mem.copy(&col.data[dst_start], &col.data[src_start], col.elem_size)
            }
        }
    }

    pop(&arch.entities)
    for &col in arch.columns {
        if col.elem_size > 0 {
            resize(&col.data, len(col.data) - col.elem_size)
        }
    }

    loc.alive = false
    loc.generation += 1
    append(&world.free_entities, Entity{id = entity.id, generation = loc.generation})

    return true
}

is_alive :: proc(world: ^World, entity: Entity) -> bool {
    if int(entity.id) >= len(world.locations) {
        return false
    }
    loc := world.locations[entity.id]
    return loc.alive && loc.generation == entity.generation
}

get :: proc(world: ^World, entity: Entity, $T: typeid) -> ^T {
    if int(entity.id) >= len(world.locations) {
        return nil
    }

    loc := world.locations[entity.id]
    if !loc.alive || loc.generation != entity.generation {
        return nil
    }

    arch := &world.archetypes[loc.archetype_index]

    col_idx, ok := arch.type_map[typeid_of(T)]
    if !ok {
        return nil
    }

    col := &arch.columns[col_idx]
    offset := int(loc.row) * col.elem_size
    return cast(^T)&col.data[offset]
}

set :: proc(world: ^World, entity: Entity, value: $T) -> bool {
    ptr := get(world, entity, T)
    if ptr == nil {
        return false
    }
    ptr^ = value
    return true
}

has :: proc(world: ^World, entity: Entity, $T: typeid) -> bool {
    if int(entity.id) >= len(world.locations) {
        return false
    }

    loc := world.locations[entity.id]
    if !loc.alive || loc.generation != entity.generation {
        return false
    }

    bit, ok := world.type_bits[typeid_of(T)]
    if !ok {
        return false
    }

    arch := &world.archetypes[loc.archetype_index]
    return arch.mask & bit != 0
}

column :: proc(arch: ^Archetype, $T: typeid) -> []T {
    col_idx, ok := arch.type_map[typeid_of(T)]
    if !ok {
        return nil
    }

    col := &arch.columns[col_idx]
    count := len(arch.entities)
    if count == 0 || len(col.data) == 0 {
        return nil
    }

    return slice.reinterpret([]T, col.data[:count * size_of(T)])
}

entity_count :: proc(world: ^World) -> int {
    count := 0
    for &arch in world.archetypes {
        count += len(arch.entities)
    }
    return count
}

query_count :: proc(world: ^World, mask: u64) -> int {
    count := 0
    for &arch in world.archetypes {
        if arch.mask & mask == mask {
            count += len(arch.entities)
        }
    }
    return count
}
