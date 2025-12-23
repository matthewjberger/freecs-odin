package freecs

import "core:mem"
import "core:slice"
import "base:intrinsics"

MAX_COMPONENTS :: 64

Entity :: struct {
    id:         u32,
    generation: u32,
}

Entity_Location :: struct {
    archetype_index: u32,
    row:             u32,
    generation:      u32,
    alive:           bool,
}

Component_Column :: struct {
    data:      [dynamic]byte,
    elem_size: int,
    bit:       u64,
    tid:       typeid,
}

Archetype :: struct {
    mask:        u64,
    entities:    [dynamic]Entity,
    columns:     [dynamic]Component_Column,
    column_bits: [MAX_COMPONENTS]int,
}

World :: struct {
    locations:       [dynamic]Entity_Location,
    archetypes:      [dynamic]Archetype,
    archetype_index: map[u64]int,
    type_bits:       map[typeid]u64,
    type_sizes:      [MAX_COMPONENTS]int,
    next_entity_id:  u32,
    free_entities:   [dynamic]Entity,
    next_bit:        u64,
    query_cache:     map[u64][dynamic]int,
}

create_world :: proc() -> World {
    return World{
        locations       = make([dynamic]Entity_Location),
        archetypes      = make([dynamic]Archetype),
        archetype_index = make(map[u64]int),
        type_bits       = make(map[typeid]u64),
        free_entities   = make([dynamic]Entity),
        next_bit        = 1,
        query_cache     = make(map[u64][dynamic]int),
    }
}

destroy_world :: proc(world: ^World) {
    for &arch in world.archetypes {
        for &col in arch.columns {
            delete(col.data)
        }
        delete(arch.columns)
        delete(arch.entities)
    }
    delete(world.archetypes)
    delete(world.locations)
    delete(world.archetype_index)
    delete(world.type_bits)
    delete(world.free_entities)
    for _, &cached in world.query_cache {
        delete(cached)
    }
    delete(world.query_cache)
}

@(private)
bit_index :: #force_inline proc(bit: u64) -> int {
    return int(intrinsics.count_trailing_zeros(bit))
}

register :: proc(world: ^World, $T: typeid) -> u64 {
    tid := typeid_of(T)
    if bit, ok := world.type_bits[tid]; ok {
        return bit
    }
    bit := world.next_bit
    world.next_bit <<= 1
    world.type_bits[tid] = bit
    world.type_sizes[bit_index(bit)] = size_of(T)
    return bit
}

Type_Info_Entry :: struct {
    bit:  u64,
    size: int,
    data: rawptr,
    tid:  typeid,
}

@(private)
find_or_create_archetype :: proc(world: ^World, mask: u64, type_info: []Type_Info_Entry) -> int {
    if idx, ok := world.archetype_index[mask]; ok {
        return idx
    }

    arch_idx := len(world.archetypes)
    arch := Archetype{
        mask     = mask,
        entities = make([dynamic]Entity),
        columns  = make([dynamic]Component_Column),
    }

    for index in 0..<MAX_COMPONENTS {
        arch.column_bits[index] = -1
    }

    for entry in type_info {
        col_idx := len(arch.columns)
        arch.column_bits[bit_index(entry.bit)] = col_idx
        append(&arch.columns, Component_Column{
            data      = make([dynamic]byte),
            elem_size = entry.size,
            bit       = entry.bit,
            tid       = entry.tid,
        })
    }

    append(&world.archetypes, arch)
    world.archetype_index[mask] = arch_idx

    for query_mask, &cached_indices in world.query_cache {
        if mask & query_mask == query_mask {
            append(&cached_indices, arch_idx)
        }
    }

    return arch_idx
}

get_matching_archetypes :: proc(world: ^World, mask: u64) -> []int {
    if cached, ok := world.query_cache[mask]; ok {
        return cached[:]
    }

    matching := make([dynamic]int)
    for arch, idx in world.archetypes {
        if arch.mask & mask == mask {
            append(&matching, idx)
        }
    }
    world.query_cache[mask] = matching
    return matching[:]
}

@(private)
alloc_entity :: proc(world: ^World) -> Entity {
    if len(world.free_entities) > 0 {
        return pop(&world.free_entities)
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
        if bit, ok := world.type_bits[comp.id]; ok {
            mask |= bit
            append(&type_info, Type_Info_Entry{
                bit  = bit,
                size = world.type_sizes[bit_index(bit)],
                data = comp.data,
                tid  = comp.id,
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
        col_idx := arch.column_bits[bit_index(entry.bit)]
        if col_idx >= 0 {
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

spawn_batch :: proc(world: ^World, count: int, components: ..any) -> []Entity {
    if len(components) == 0 || count <= 0 {
        return nil
    }

    mask: u64 = 0
    type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)

    for comp in components {
        if bit, ok := world.type_bits[comp.id]; ok {
            mask |= bit
            append(&type_info, Type_Info_Entry{
                bit  = bit,
                size = world.type_sizes[bit_index(bit)],
                data = comp.data,
                tid  = comp.id,
            })
        }
    }

    if mask == 0 {
        return nil
    }

    arch_idx := find_or_create_archetype(world, mask, type_info[:])
    arch := &world.archetypes[arch_idx]

    start_row := len(arch.entities)
    reserve(&arch.entities, start_row + count)

    for &col in arch.columns {
        reserve(&col.data, len(col.data) + count * col.elem_size)
    }

    entities := make([]Entity, count)

    for index in 0..<count {
        entity := alloc_entity(world)
        entities[index] = entity
        row := start_row + index
        append(&arch.entities, entity)

        for entry in type_info {
            col_idx := arch.column_bits[bit_index(entry.bit)]
            if col_idx >= 0 {
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
    }

    return entities
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

    bit, ok := world.type_bits[typeid_of(T)]
    if !ok {
        return nil
    }

    arch := &world.archetypes[loc.archetype_index]
    col_idx := arch.column_bits[bit_index(bit)]
    if col_idx < 0 {
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

column_with_bit :: #force_inline proc(arch: ^Archetype, $T: typeid, bit: u64) -> []T {
    col_idx := arch.column_bits[bit_index(bit)]
    if col_idx < 0 {
        return nil
    }

    col := &arch.columns[col_idx]
    count := len(arch.entities)
    if count == 0 || len(col.data) == 0 {
        return nil
    }

    return slice.reinterpret([]T, col.data[:count * size_of(T)])
}

column_with_type :: proc(arch: ^Archetype, $T: typeid) -> []T {
    tid := typeid_of(T)
    for &col in arch.columns {
        if col.tid == tid {
            count := len(arch.entities)
            if count == 0 || len(col.data) == 0 {
                return nil
            }
            return slice.reinterpret([]T, col.data[:count * size_of(T)])
        }
    }
    return nil
}

column :: proc {
    column_with_bit,
    column_with_type,
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
    matching := get_matching_archetypes(world, mask)
    for arch_idx in matching {
        count += len(world.archetypes[arch_idx].entities)
    }
    return count
}

for_each :: proc(world: ^World, mask: u64, callback: proc(arch: ^Archetype, index: int)) {
    matching := get_matching_archetypes(world, mask)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        for index in 0..<len(arch.entities) {
            callback(arch, index)
        }
    }
}

query_entities :: proc(world: ^World, mask: u64, allocator := context.temp_allocator) -> []Entity {
    entities := make([dynamic]Entity, allocator)
    matching := get_matching_archetypes(world, mask)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        for entity in arch.entities {
            append(&entities, entity)
        }
    }
    return entities[:]
}

reserve_entities :: proc(world: ^World, count: int) {
    reserve(&world.locations, len(world.locations) + count)
}

Table_Iterator :: struct {
    world:    ^World,
    mask:     u64,
    indices:  []int,
    current:  int,
}

make_table_iterator :: proc(world: ^World, mask: u64) -> Table_Iterator {
    return Table_Iterator{
        world   = world,
        mask    = mask,
        indices = get_matching_archetypes(world, mask),
        current = 0,
    }
}

iterate_tables :: proc(iter: ^Table_Iterator) -> (arch: ^Archetype, idx: int, ok: bool) {
    if iter.current >= len(iter.indices) {
        return nil, 0, false
    }
    arch_idx := iter.indices[iter.current]
    iter.current += 1
    return &iter.world.archetypes[arch_idx], arch_idx, true
}

for_each_table :: proc(world: ^World, mask: u64, callback: proc(arch: ^Archetype)) {
    matching := get_matching_archetypes(world, mask)
    for arch_idx in matching {
        callback(&world.archetypes[arch_idx])
    }
}

column_unchecked :: #force_inline proc(arch: ^Archetype, $T: typeid, bit: u64) -> []T #no_bounds_check {
    col_idx := arch.column_bits[bit_index(bit)]
    col := &arch.columns[col_idx]
    count := len(arch.entities)
    return slice.reinterpret([]T, col.data[:count * size_of(T)])
}
