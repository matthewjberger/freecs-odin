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

Table_Edges :: struct {
    add_edges:    [MAX_COMPONENTS]int,
    remove_edges: [MAX_COMPONENTS]int,
}

Archetype :: struct {
    mask:        u64,
    entities:    [dynamic]Entity,
    columns:     [dynamic]Component_Column,
    column_bits: [MAX_COMPONENTS]int,
    edges:       Table_Edges,
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

    for index in 0 ..< MAX_COMPONENTS {
        arch.column_bits[index] = -1
        arch.edges.add_edges[index] = -1
        arch.edges.remove_edges[index] = -1
    }

    for entry in type_info {
        col_idx := len(arch.columns)
        arch.column_bits[bit_index(entry.bit)] = col_idx
        append(
            &arch.columns,
            Component_Column{data = make([dynamic]byte), elem_size = entry.size, bit = entry.bit, tid = entry.tid},
        )
    }

    append(&world.archetypes, arch)
    world.archetype_index[mask] = arch_idx

    for query_mask, &cached_indices in world.query_cache {
        if mask & query_mask == query_mask {
            append(&cached_indices, arch_idx)
        }
    }

    for comp_bit_index in 0 ..< MAX_COMPONENTS {
        comp_mask := u64(1) << u64(comp_bit_index)
        if world.type_sizes[comp_bit_index] == 0 {
            continue
        }

        for existing_idx in 0 ..< len(world.archetypes) {
            existing := &world.archetypes[existing_idx]
            if existing.mask | comp_mask == mask {
                existing.edges.add_edges[comp_bit_index] = arch_idx
            }
            if existing.mask & ~comp_mask == mask {
                existing.edges.remove_edges[comp_bit_index] = arch_idx
            }
        }
    }

    return arch_idx
}

get_matching_archetypes :: proc(world: ^World, mask: u64, exclude: u64 = 0) -> []int {
    cache_key := mask | (exclude << 32)
    if cached, ok := world.query_cache[cache_key]; ok {
        return cached[:]
    }

    matching := make([dynamic]int)
    for arch, idx in world.archetypes {
        if arch.mask & mask == mask && (exclude == 0 || arch.mask & exclude == 0) {
            append(&matching, idx)
        }
    }
    world.query_cache[cache_key] = matching
    return matching[:]
}

MIN_ENTITY_CAPACITY :: 64

@(private)
ensure_entity_slot :: proc(world: ^World, id: u32) {
    current_len := len(world.locations)
    if current_len > int(id) {
        return
    }

    new_cap := max(MIN_ENTITY_CAPACITY, current_len * 2)
    for new_cap <= int(id) {
        new_cap *= 2
    }

    reserve(&world.locations, new_cap)
    for len(world.locations) <= int(id) {
        append(&world.locations, Entity_Location{})
    }
}

@(private)
alloc_entity :: proc(world: ^World) -> Entity {
    if len(world.free_entities) > 0 {
        return pop(&world.free_entities)
    }

    id := world.next_entity_id
    world.next_entity_id += 1

    ensure_entity_slot(world, id)

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
            append(
                &type_info,
                Type_Info_Entry{
                    bit = bit,
                    size = world.type_sizes[bit_index(bit)],
                    data = comp.data,
                    tid = comp.id,
                },
            )
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

    for index in 0 ..< count {
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

spawn_with_mask :: proc(world: ^World, mask: u64, count: int) -> []Entity {
    if mask == 0 || count <= 0 {
        return nil
    }

    type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)
    for bit_idx in 0 ..< MAX_COMPONENTS {
        comp_bit := u64(1) << u64(bit_idx)
        if mask & comp_bit != 0 {
            size := world.type_sizes[bit_idx]
            if size > 0 {
                append(
                    &type_info,
                    Type_Info_Entry{bit = comp_bit, size = size, data = nil, tid = nil},
                )
            }
        }
    }

    if len(type_info) == 0 {
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

    for index in 0 ..< count {
        entity := alloc_entity(world)
        entities[index] = entity
        row := start_row + index
        append(&arch.entities, entity)

        for &col in arch.columns {
            old_len := len(col.data)
            resize(&col.data, old_len + col.elem_size)
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

spawn_batch_with_init :: proc(
    world: ^World,
    mask: u64,
    count: int,
    init_callback: proc(arch: ^Archetype, index: int),
) -> []Entity {
    entities := spawn_with_mask(world, mask, count)
    if entities == nil {
        return nil
    }

    arch_idx, ok := world.archetype_index[mask]
    if !ok {
        return entities
    }

    arch := &world.archetypes[arch_idx]
    start_row := len(arch.entities) - count

    for index in 0 ..< count {
        init_callback(arch, start_row + index)
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

get_with_bit :: #force_inline proc(world: ^World, entity: Entity, $T: typeid, bit: u64) -> ^T {
    loc := world.locations[entity.id]
    arch := &world.archetypes[loc.archetype_index]
    col_idx := arch.column_bits[bit_index(bit)]
    col := &arch.columns[col_idx]
    offset := int(loc.row) * col.elem_size
    return cast(^T)&col.data[offset]
}

get_unchecked :: #force_inline proc(world: ^World, entity: Entity, $T: typeid, bit: u64) -> ^T #no_bounds_check {
    loc := world.locations[entity.id]
    arch := &world.archetypes[loc.archetype_index]
    col_idx := arch.column_bits[bit_index(bit)]
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

has_components :: #force_inline proc(world: ^World, entity: Entity, mask: u64) -> bool {
    if int(entity.id) >= len(world.locations) {
        return false
    }

    loc := world.locations[entity.id]
    if !loc.alive || loc.generation != entity.generation {
        return false
    }

    arch := &world.archetypes[loc.archetype_index]
    return arch.mask & mask == mask
}

component_mask :: proc(world: ^World, entity: Entity) -> (u64, bool) {
    if int(entity.id) >= len(world.locations) {
        return 0, false
    }

    loc := world.locations[entity.id]
    if !loc.alive || loc.generation != entity.generation {
        return 0, false
    }

    arch := &world.archetypes[loc.archetype_index]
    return arch.mask, true
}

@(private)
move_entity :: proc(world: ^World, entity: Entity, from_arch_idx: int, from_row: int, to_arch_idx: int) {
    from_arch := &world.archetypes[from_arch_idx]
    to_arch := &world.archetypes[to_arch_idx]

    new_row := len(to_arch.entities)
    append(&to_arch.entities, entity)

    for &to_col in to_arch.columns {
        old_len := len(to_col.data)
        resize(&to_col.data, old_len + to_col.elem_size)

        from_col_idx := from_arch.column_bits[bit_index(to_col.bit)]
        if from_col_idx >= 0 {
            from_col := &from_arch.columns[from_col_idx]
            src_offset := from_row * from_col.elem_size
            mem.copy(&to_col.data[old_len], &from_col.data[src_offset], to_col.elem_size)
        }
    }

    last_row := len(from_arch.entities) - 1
    if from_row < last_row {
        last_entity := from_arch.entities[last_row]
        from_arch.entities[from_row] = last_entity
        world.locations[last_entity.id].row = u32(from_row)

        for &col in from_arch.columns {
            if col.elem_size > 0 {
                src_start := last_row * col.elem_size
                dst_start := from_row * col.elem_size
                mem.copy(&col.data[dst_start], &col.data[src_start], col.elem_size)
            }
        }
    }

    pop(&from_arch.entities)
    for &col in from_arch.columns {
        if col.elem_size > 0 {
            resize(&col.data, len(col.data) - col.elem_size)
        }
    }

    world.locations[entity.id] = Entity_Location{
        generation      = entity.generation,
        archetype_index = u32(to_arch_idx),
        row             = u32(new_row),
        alive           = true,
    }
}

add_component :: proc(world: ^World, entity: Entity, value: $T) -> bool {
    if int(entity.id) >= len(world.locations) {
        return false
    }

    loc := world.locations[entity.id]
    if !loc.alive || loc.generation != entity.generation {
        return false
    }

    bit := register(world, T)
    bit_idx := bit_index(bit)

    arch := &world.archetypes[loc.archetype_index]

    if arch.mask & bit != 0 {
        col_idx := arch.column_bits[bit_idx]
        col := &arch.columns[col_idx]
        offset := int(loc.row) * col.elem_size
        ptr := cast(^T)&col.data[offset]
        ptr^ = value
        return true
    }

    new_mask := arch.mask | bit
    target_arch_idx := arch.edges.add_edges[bit_idx]

    if target_arch_idx < 0 {
        type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)
        for &col in arch.columns {
            append(
                &type_info,
                Type_Info_Entry{bit = col.bit, size = col.elem_size, data = nil, tid = col.tid},
            )
        }
        append(&type_info, Type_Info_Entry{bit = bit, size = size_of(T), data = nil, tid = typeid_of(T)})
        target_arch_idx = find_or_create_archetype(world, new_mask, type_info[:])
        world.archetypes[loc.archetype_index].edges.add_edges[bit_idx] = target_arch_idx
    }

    move_entity(world, entity, int(loc.archetype_index), int(loc.row), target_arch_idx)

    new_loc := world.locations[entity.id]
    to_arch := &world.archetypes[new_loc.archetype_index]
    col_idx := to_arch.column_bits[bit_idx]
    col := &to_arch.columns[col_idx]
    offset := int(new_loc.row) * col.elem_size
    ptr := cast(^T)&col.data[offset]
    ptr^ = value

    return true
}

remove_component :: proc(world: ^World, entity: Entity, $T: typeid) -> bool {
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

    bit_idx := bit_index(bit)
    arch := &world.archetypes[loc.archetype_index]

    if arch.mask & bit == 0 {
        return false
    }

    new_mask := arch.mask & ~bit

    if new_mask == 0 {
        despawn(world, entity)
        return true
    }

    target_arch_idx := arch.edges.remove_edges[bit_idx]

    if target_arch_idx < 0 {
        type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)
        for &col in arch.columns {
            if col.bit != bit {
                append(
                    &type_info,
                    Type_Info_Entry{bit = col.bit, size = col.elem_size, data = nil, tid = col.tid},
                )
            }
        }
        target_arch_idx = find_or_create_archetype(world, new_mask, type_info[:])
        world.archetypes[loc.archetype_index].edges.remove_edges[bit_idx] = target_arch_idx
    }

    move_entity(world, entity, int(loc.archetype_index), int(loc.row), target_arch_idx)
    return true
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

query_count :: proc(world: ^World, mask: u64, exclude: u64 = 0) -> int {
    count := 0
    matching := get_matching_archetypes(world, mask, exclude)
    for arch_idx in matching {
        count += len(world.archetypes[arch_idx].entities)
    }
    return count
}

for_each :: proc(
    world: ^World,
    mask: u64,
    callback: proc(arch: ^Archetype, index: int),
    exclude: u64 = 0,
) {
    matching := get_matching_archetypes(world, mask, exclude)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        for index in 0 ..< len(arch.entities) {
            callback(arch, index)
        }
    }
}

query_entities :: proc(
    world: ^World,
    mask: u64,
    exclude: u64 = 0,
    allocator := context.temp_allocator,
) -> []Entity {
    entities := make([dynamic]Entity, allocator)
    matching := get_matching_archetypes(world, mask, exclude)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        for entity in arch.entities {
            append(&entities, entity)
        }
    }
    return entities[:]
}

query_first :: proc(world: ^World, mask: u64, exclude: u64 = 0) -> (Entity, bool) {
    matching := get_matching_archetypes(world, mask, exclude)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        if len(arch.entities) > 0 {
            return arch.entities[0], true
        }
    }
    return Entity{}, false
}

despawn_batch :: proc(world: ^World, entities: []Entity) -> int {
    count := 0
    for entity in entities {
        if despawn(world, entity) {
            count += 1
        }
    }
    return count
}

reserve_entities :: proc(world: ^World, count: int) {
    reserve(&world.locations, len(world.locations) + count)
}

Table_Iterator :: struct {
    world:   ^World,
    mask:    u64,
    exclude: u64,
    indices: []int,
    current: int,
}

make_table_iterator :: proc(world: ^World, mask: u64, exclude: u64 = 0) -> Table_Iterator {
    return Table_Iterator{
        world   = world,
        mask    = mask,
        exclude = exclude,
        indices = get_matching_archetypes(world, mask, exclude),
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

for_each_table :: proc(world: ^World, mask: u64, callback: proc(arch: ^Archetype), exclude: u64 = 0) {
    matching := get_matching_archetypes(world, mask, exclude)
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

Command_Type :: enum {
    Spawn,
    Despawn,
    Add_Components,
    Remove_Components,
}

Command :: struct {
    command_type:  Command_Type,
    entity:        Entity,
    mask:          u64,
    component_data: [dynamic]byte,
    component_sizes: [dynamic]int,
    component_bits: [dynamic]u64,
}

Command_Buffer :: struct {
    commands: [dynamic]Command,
    world:    ^World,
}

create_command_buffer :: proc(world: ^World) -> Command_Buffer {
    return Command_Buffer{
        commands = make([dynamic]Command),
        world    = world,
    }
}

destroy_command_buffer :: proc(buffer: ^Command_Buffer) {
    for &cmd in buffer.commands {
        delete(cmd.component_data)
        delete(cmd.component_sizes)
        delete(cmd.component_bits)
    }
    delete(buffer.commands)
}

clear_command_buffer :: proc(buffer: ^Command_Buffer) {
    for &cmd in buffer.commands {
        delete(cmd.component_data)
        delete(cmd.component_sizes)
        delete(cmd.component_bits)
    }
    clear(&buffer.commands)
}

queue_spawn :: proc(buffer: ^Command_Buffer, components: ..any) {
    cmd := Command{
        command_type    = .Spawn,
        component_data  = make([dynamic]byte),
        component_sizes = make([dynamic]int),
        component_bits  = make([dynamic]u64),
    }

    for comp in components {
        if bit, ok := buffer.world.type_bits[comp.id]; ok {
            size := buffer.world.type_sizes[bit_index(bit)]
            append(&cmd.component_bits, bit)
            append(&cmd.component_sizes, size)
            old_len := len(cmd.component_data)
            resize(&cmd.component_data, old_len + size)
            if comp.data != nil && size > 0 {
                mem.copy(&cmd.component_data[old_len], comp.data, size)
            }
        }
    }

    append(&buffer.commands, cmd)
}

queue_despawn :: proc(buffer: ^Command_Buffer, entity: Entity) {
    cmd := Command{
        command_type    = .Despawn,
        entity          = entity,
        component_data  = make([dynamic]byte),
        component_sizes = make([dynamic]int),
        component_bits  = make([dynamic]u64),
    }
    append(&buffer.commands, cmd)
}

queue_add_components :: proc(buffer: ^Command_Buffer, entity: Entity, mask: u64) {
    cmd := Command{
        command_type    = .Add_Components,
        entity          = entity,
        mask            = mask,
        component_data  = make([dynamic]byte),
        component_sizes = make([dynamic]int),
        component_bits  = make([dynamic]u64),
    }
    append(&buffer.commands, cmd)
}

queue_remove_components :: proc(buffer: ^Command_Buffer, entity: Entity, mask: u64) {
    cmd := Command{
        command_type    = .Remove_Components,
        entity          = entity,
        mask            = mask,
        component_data  = make([dynamic]byte),
        component_sizes = make([dynamic]int),
        component_bits  = make([dynamic]u64),
    }
    append(&buffer.commands, cmd)
}

apply_commands :: proc(buffer: ^Command_Buffer) {
    for &cmd in buffer.commands {
        switch cmd.command_type {
        case .Spawn:
            mask: u64 = 0
            for bit in cmd.component_bits {
                mask |= bit
            }
            if mask != 0 {
                type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)
                data_offset := 0
                for index in 0 ..< len(cmd.component_bits) {
                    bit := cmd.component_bits[index]
                    size := cmd.component_sizes[index]
                    append(
                        &type_info,
                        Type_Info_Entry{
                            bit  = bit,
                            size = size,
                            data = &cmd.component_data[data_offset] if size > 0 else nil,
                            tid  = nil,
                        },
                    )
                    data_offset += size
                }

                arch_idx := find_or_create_archetype(buffer.world, mask, type_info[:])
                arch := &buffer.world.archetypes[arch_idx]

                entity := alloc_entity(buffer.world)
                row := len(arch.entities)
                append(&arch.entities, entity)

                data_offset = 0
                for index in 0 ..< len(cmd.component_bits) {
                    bit := cmd.component_bits[index]
                    size := cmd.component_sizes[index]
                    col_idx := arch.column_bits[bit_index(bit)]
                    if col_idx >= 0 {
                        col := &arch.columns[col_idx]
                        old_len := len(col.data)
                        resize(&col.data, old_len + size)
                        if size > 0 {
                            mem.copy(&col.data[old_len], &cmd.component_data[data_offset], size)
                        }
                    }
                    data_offset += size
                }

                buffer.world.locations[entity.id] = Entity_Location{
                    generation      = entity.generation,
                    archetype_index = u32(arch_idx),
                    row             = u32(row),
                    alive           = true,
                }
            }

        case .Despawn:
            despawn(buffer.world, cmd.entity)

        case .Add_Components:
            for bit_idx in 0 ..< MAX_COMPONENTS {
                comp_bit := u64(1) << u64(bit_idx)
                if cmd.mask & comp_bit != 0 {
                    loc := buffer.world.locations[cmd.entity.id]
                    if !loc.alive || loc.generation != cmd.entity.generation {
                        continue
                    }

                    arch := &buffer.world.archetypes[loc.archetype_index]
                    if arch.mask & comp_bit != 0 {
                        continue
                    }

                    new_mask := arch.mask | comp_bit
                    target_arch_idx := arch.edges.add_edges[bit_idx]

                    if target_arch_idx < 0 {
                        type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)
                        for &col in arch.columns {
                            append(
                                &type_info,
                                Type_Info_Entry{bit = col.bit, size = col.elem_size, data = nil, tid = col.tid},
                            )
                        }
                        size := buffer.world.type_sizes[bit_idx]
                        append(&type_info, Type_Info_Entry{bit = comp_bit, size = size, data = nil, tid = nil})
                        target_arch_idx = find_or_create_archetype(buffer.world, new_mask, type_info[:])
                        buffer.world.archetypes[loc.archetype_index].edges.add_edges[bit_idx] = target_arch_idx
                    }

                    move_entity(buffer.world, cmd.entity, int(loc.archetype_index), int(loc.row), target_arch_idx)
                }
            }

        case .Remove_Components:
            for bit_idx in 0 ..< MAX_COMPONENTS {
                comp_bit := u64(1) << u64(bit_idx)
                if cmd.mask & comp_bit != 0 {
                    loc := buffer.world.locations[cmd.entity.id]
                    if !loc.alive || loc.generation != cmd.entity.generation {
                        continue
                    }

                    arch := &buffer.world.archetypes[loc.archetype_index]
                    if arch.mask & comp_bit == 0 {
                        continue
                    }

                    new_mask := arch.mask & ~comp_bit

                    if new_mask == 0 {
                        despawn(buffer.world, cmd.entity)
                        continue
                    }

                    target_arch_idx := arch.edges.remove_edges[bit_idx]

                    if target_arch_idx < 0 {
                        type_info := make([dynamic]Type_Info_Entry, context.temp_allocator)
                        for &col in arch.columns {
                            if col.bit != comp_bit {
                                append(
                                    &type_info,
                                    Type_Info_Entry{bit = col.bit, size = col.elem_size, data = nil, tid = col.tid},
                                )
                            }
                        }
                        target_arch_idx = find_or_create_archetype(buffer.world, new_mask, type_info[:])
                        buffer.world.archetypes[loc.archetype_index].edges.remove_edges[bit_idx] = target_arch_idx
                    }

                    move_entity(buffer.world, cmd.entity, int(loc.archetype_index), int(loc.row), target_arch_idx)
                }
            }
        }
    }

    clear_command_buffer(buffer)
}

MAX_TAGS :: 64

Tag_Storage :: struct {
    entities: map[u32]Entity,
}

Tags :: struct {
    storage:  [MAX_TAGS]Tag_Storage,
    next_tag: int,
    tag_names: map[string]int,
}

create_tags :: proc() -> Tags {
    tags: Tags
    tags.tag_names = make(map[string]int)
    for index in 0 ..< MAX_TAGS {
        tags.storage[index].entities = make(map[u32]Entity)
    }
    return tags
}

destroy_tags :: proc(tags: ^Tags) {
    for index in 0 ..< MAX_TAGS {
        delete(tags.storage[index].entities)
    }
    delete(tags.tag_names)
}

register_tag :: proc(tags: ^Tags, name: string) -> int {
    if existing, ok := tags.tag_names[name]; ok {
        return existing
    }
    tag_id := tags.next_tag
    tags.next_tag += 1
    tags.tag_names[name] = tag_id
    return tag_id
}

add_tag :: proc(tags: ^Tags, tag_id: int, entity: Entity) {
    if tag_id >= 0 && tag_id < MAX_TAGS {
        tags.storage[tag_id].entities[entity.id] = entity
    }
}

remove_tag :: proc(tags: ^Tags, tag_id: int, entity: Entity) {
    if tag_id >= 0 && tag_id < MAX_TAGS {
        delete_key(&tags.storage[tag_id].entities, entity.id)
    }
}

has_tag :: proc(tags: ^Tags, tag_id: int, entity: Entity) -> bool {
    if tag_id < 0 || tag_id >= MAX_TAGS {
        return false
    }
    if stored, ok := tags.storage[tag_id].entities[entity.id]; ok {
        return stored.generation == entity.generation
    }
    return false
}

query_tag :: proc(tags: ^Tags, tag_id: int, allocator := context.temp_allocator) -> []Entity {
    if tag_id < 0 || tag_id >= MAX_TAGS {
        return nil
    }
    entities := make([dynamic]Entity, allocator)
    for _, entity in tags.storage[tag_id].entities {
        append(&entities, entity)
    }
    return entities[:]
}

tag_count :: proc(tags: ^Tags, tag_id: int) -> int {
    if tag_id < 0 || tag_id >= MAX_TAGS {
        return 0
    }
    return len(tags.storage[tag_id].entities)
}

clear_entity_tags :: proc(tags: ^Tags, entity: Entity) {
    for index in 0 ..< MAX_TAGS {
        delete_key(&tags.storage[index].entities, entity.id)
    }
}

Event_Queue :: struct($T: typeid) {
    current:  [dynamic]T,
    previous: [dynamic]T,
}

create_event_queue :: proc($T: typeid) -> Event_Queue(T) {
    return Event_Queue(T){
        current  = make([dynamic]T),
        previous = make([dynamic]T),
    }
}

destroy_event_queue :: proc(queue: ^Event_Queue($T)) {
    delete(queue.current)
    delete(queue.previous)
}

send_event :: proc(queue: ^Event_Queue($T), event: T) {
    append(&queue.current, event)
}

read_events :: proc(queue: ^Event_Queue($T)) -> []T {
    return queue.previous[:]
}

collect_events :: proc(queue: ^Event_Queue($T), allocator := context.temp_allocator) -> []T {
    result := make([]T, len(queue.previous), allocator)
    copy(result, queue.previous[:])
    return result
}

drain_events :: proc(queue: ^Event_Queue($T)) -> []T {
    result := queue.previous[:]
    queue.previous = make([dynamic]T)
    return result
}

update_event_queue :: proc(queue: ^Event_Queue($T)) {
    clear(&queue.previous)
    queue.previous, queue.current = queue.current, queue.previous
}

clear_event_queue :: proc(queue: ^Event_Queue($T)) {
    clear(&queue.current)
    clear(&queue.previous)
}

event_count :: proc(queue: ^Event_Queue($T)) -> int {
    return len(queue.previous)
}

peek_events :: proc(queue: ^Event_Queue($T)) -> []T {
    return queue.current[:]
}

System :: struct($World_Type: typeid) {
    run:      proc(world: ^World_Type),
    run_mut:  proc(world: ^World_Type),
    is_mut:   bool,
}

Schedule :: struct($World_Type: typeid) {
    systems: [dynamic]System(World_Type),
}

create_schedule :: proc($World_Type: typeid) -> Schedule(World_Type) {
    return Schedule(World_Type){
        systems = make([dynamic]System(World_Type)),
    }
}

destroy_schedule :: proc(schedule: ^Schedule($World_Type)) {
    delete(schedule.systems)
}

add_system :: proc(schedule: ^Schedule($World_Type), system_proc: proc(world: ^World_Type)) {
    append(&schedule.systems, System(World_Type){
        run    = system_proc,
        is_mut = false,
    })
}

add_system_mut :: proc(schedule: ^Schedule($World_Type), system_proc: proc(world: ^World_Type)) {
    append(&schedule.systems, System(World_Type){
        run_mut = system_proc,
        is_mut  = true,
    })
}

run_schedule :: proc(schedule: ^Schedule($World_Type), world: ^World_Type) {
    for &system in schedule.systems {
        if system.is_mut {
            if system.run_mut != nil {
                system.run_mut(world)
            }
        } else {
            if system.run != nil {
                system.run(world)
            }
        }
    }
}

Query_Builder :: struct {
    world:   ^World,
    include: u64,
    exclude: u64,
}

query :: proc(world: ^World) -> Query_Builder {
    return Query_Builder{
        world   = world,
        include = 0,
        exclude = 0,
    }
}

with :: proc(builder: Query_Builder, mask: u64) -> Query_Builder {
    return Query_Builder{
        world   = builder.world,
        include = builder.include | mask,
        exclude = builder.exclude,
    }
}

without :: proc(builder: Query_Builder, mask: u64) -> Query_Builder {
    return Query_Builder{
        world   = builder.world,
        include = builder.include,
        exclude = builder.exclude | mask,
    }
}

iter :: proc(builder: Query_Builder, callback: proc(entity: Entity, arch: ^Archetype, index: int)) {
    matching := get_matching_archetypes(builder.world, builder.include, builder.exclude)
    for arch_idx in matching {
        arch := &builder.world.archetypes[arch_idx]
        for index in 0 ..< len(arch.entities) {
            callback(arch.entities[index], arch, index)
        }
    }
}

iter_tables :: proc(builder: Query_Builder, callback: proc(arch: ^Archetype)) {
    matching := get_matching_archetypes(builder.world, builder.include, builder.exclude)
    for arch_idx in matching {
        callback(&builder.world.archetypes[arch_idx])
    }
}

query_builder_entities :: proc(builder: Query_Builder, allocator := context.temp_allocator) -> []Entity {
    return query_entities(builder.world, builder.include, builder.exclude, allocator)
}

query_builder_count :: proc(builder: Query_Builder) -> int {
    return query_count(builder.world, builder.include, builder.exclude)
}

query_builder_first :: proc(builder: Query_Builder) -> (Entity, bool) {
    return query_first(builder.world, builder.include, builder.exclude)
}
