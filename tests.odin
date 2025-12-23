package freecs

import "core:testing"
import "core:fmt"

Position :: struct {
    x, y: f32,
}

Velocity :: struct {
    x, y: f32,
}

Health :: struct {
    value: f32,
}

POSITION: u64
VELOCITY: u64
HEALTH:   u64

setup_world :: proc() -> World {
    world := create_world()
    POSITION = register(&world, Position)
    VELOCITY = register(&world, Velocity)
    HEALTH   = register(&world, Health)
    return world
}

@(test)
test_spawn_entity :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entity := spawn(&world, Position{1, 2}, Velocity{3, 4})

    testing.expect(t, entity.id == 0, "First entity should have id 0")
    testing.expect(t, entity.generation == 0, "First entity should have generation 0")
    testing.expect(t, entity_count(&world) == 1, "Should have 1 entity")
}

@(test)
test_get_component :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entity := spawn(&world, Position{1, 2}, Velocity{3, 4})

    pos := get(&world, entity, Position)
    testing.expect(t, pos != nil, "Should get position")
    testing.expect(t, pos.x == 1, "Position x should be 1")
    testing.expect(t, pos.y == 2, "Position y should be 2")

    vel := get(&world, entity, Velocity)
    testing.expect(t, vel != nil, "Should get velocity")
    testing.expect(t, vel.x == 3, "Velocity x should be 3")
    testing.expect(t, vel.y == 4, "Velocity y should be 4")

    health := get(&world, entity, Health)
    testing.expect(t, health == nil, "Should not have health component")
}

@(test)
test_set_component :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entity := spawn(&world, Position{1, 2})

    set(&world, entity, Position{10, 20})

    pos := get(&world, entity, Position)
    testing.expect(t, pos.x == 10, "Position x should be 10")
    testing.expect(t, pos.y == 20, "Position y should be 20")
}

@(test)
test_modify_component :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entity := spawn(&world, Position{1, 2})

    pos := get(&world, entity, Position)
    pos.x = 100
    pos.y = 200

    pos2 := get(&world, entity, Position)
    testing.expect(t, pos2.x == 100, "Position x should be 100")
    testing.expect(t, pos2.y == 200, "Position y should be 200")
}

@(test)
test_despawn_entity :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    e1 := spawn(&world, Position{1, 1})
    e2 := spawn(&world, Position{2, 2})
    e3 := spawn(&world, Position{3, 3})

    testing.expect(t, entity_count(&world) == 3, "Should have 3 entities")

    despawn(&world, e2)

    testing.expect(t, entity_count(&world) == 2, "Should have 2 entities")
    testing.expect(t, is_alive(&world, e1), "e1 should be alive")
    testing.expect(t, !is_alive(&world, e2), "e2 should not be alive")
    testing.expect(t, is_alive(&world, e3), "e3 should be alive")

    testing.expect(t, get(&world, e2, Position) == nil, "Should not get despawned entity's component")
}

@(test)
test_generational_indices :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    e1 := spawn(&world, Position{1, 1})
    testing.expect(t, e1.generation == 0, "First entity should have generation 0")

    id := e1.id
    despawn(&world, e1)

    e2 := spawn(&world, Position{2, 2})
    testing.expect(t, e2.id == id, "Should reuse same id")
    testing.expect(t, e2.generation == 1, "Should have incremented generation")

    testing.expect(t, get(&world, e1, Position) == nil, "Old entity reference should be invalid")

    pos := get(&world, e2, Position)
    testing.expect(t, pos != nil, "New entity should be valid")
    testing.expect(t, pos.x == 2, "Should get new entity's data")
}

@(test)
test_multiple_archetypes :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    e1 := spawn(&world, Position{1, 1})
    e2 := spawn(&world, Position{2, 2}, Velocity{1, 0})
    e3 := spawn(&world, Position{3, 3}, Velocity{0, 1}, Health{100})

    testing.expect(t, len(world.archetypes) == 3, "Should have 3 archetypes")

    testing.expect(t, has(&world, e1, Position), "e1 should have Position")
    testing.expect(t, !has(&world, e1, Velocity), "e1 should not have Velocity")

    testing.expect(t, has(&world, e2, Position), "e2 should have Position")
    testing.expect(t, has(&world, e2, Velocity), "e2 should have Velocity")
    testing.expect(t, !has(&world, e2, Health), "e2 should not have Health")

    testing.expect(t, has(&world, e3, Position), "e3 should have Position")
    testing.expect(t, has(&world, e3, Velocity), "e3 should have Velocity")
    testing.expect(t, has(&world, e3, Health), "e3 should have Health")
}

@(test)
test_query_count :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    spawn(&world, Position{1, 1})
    spawn(&world, Position{2, 2})
    spawn(&world, Position{3, 3}, Velocity{1, 0})
    spawn(&world, Position{4, 4}, Velocity{0, 1}, Health{100})

    testing.expect(t, query_count(&world, POSITION) == 4, "4 entities have Position")
    testing.expect(t, query_count(&world, VELOCITY) == 2, "2 entities have Velocity")
    testing.expect(t, query_count(&world, HEALTH) == 1, "1 entity has Health")
    testing.expect(t, query_count(&world, POSITION | VELOCITY) == 2, "2 entities have Position+Velocity")
}

@(test)
test_column_iteration :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    spawn(&world, Position{1, 0}, Velocity{10, 0})
    spawn(&world, Position{2, 0}, Velocity{20, 0})
    spawn(&world, Position{3, 0}, Velocity{30, 0})

    testing.expect(t, entity_count(&world) == 3, "Should have 3 entities")
    testing.expect(t, len(world.archetypes) == 1, "Should have 1 archetype")

    arch := &world.archetypes[0]
    testing.expect(t, arch.mask == (POSITION | VELOCITY), "Archetype mask should match")
    testing.expect(t, len(arch.entities) == 3, "Archetype should have 3 entities")

    positions := column(arch, Position)
    velocities := column(arch, Velocity)

    testing.expect(t, positions != nil, "Positions column should not be nil")
    testing.expect(t, velocities != nil, "Velocities column should not be nil")
    testing.expect(t, len(positions) == 3, "Positions should have 3 elements")
    testing.expect(t, len(velocities) == 3, "Velocities should have 3 elements")

    testing.expect(t, positions[0].x == 1, "First position x should be 1")
    testing.expect(t, positions[1].x == 2, "Second position x should be 2")
    testing.expect(t, positions[2].x == 3, "Third position x should be 3")

    dt: f32 = 1.0
    for i in 0..<len(arch.entities) {
        positions[i].x += velocities[i].x * dt
    }

    testing.expect(t, positions[0].x == 11, "First position x should be 11 after update")
    testing.expect(t, positions[1].x == 22, "Second position x should be 22 after update")
    testing.expect(t, positions[2].x == 33, "Third position x should be 33 after update")
}

@(test)
test_data_integrity_after_despawn :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    e1 := spawn(&world, Position{1, 1})
    e2 := spawn(&world, Position{2, 2})
    e3 := spawn(&world, Position{3, 3})

    despawn(&world, e2)

    pos1 := get(&world, e1, Position)
    pos3 := get(&world, e3, Position)

    testing.expect(t, pos1 != nil && pos1.x == 1, "e1 data should be intact")
    testing.expect(t, pos3 != nil && pos3.x == 3, "e3 data should be intact")
}

@(test)
test_spawn_many :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entities: [100]Entity
    for i in 0..<100 {
        entities[i] = spawn(&world, Position{f32(i), f32(i)})
    }

    testing.expect(t, entity_count(&world) == 100, "Should have 100 entities")

    for i in 0..<100 {
        pos := get(&world, entities[i], Position)
        testing.expect(t, pos != nil, "Should get position")
        testing.expect(t, pos.x == f32(i), "Position x should match")
    }
}

@(test)
test_despawn_and_respawn :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entities: [10]Entity
    for i in 0..<10 {
        entities[i] = spawn(&world, Position{f32(i), 0})
    }

    for i in 0..<5 {
        despawn(&world, entities[i * 2])
    }

    testing.expect(t, entity_count(&world) == 5, "Should have 5 entities")

    new_entities: [5]Entity
    for i in 0..<5 {
        new_entities[i] = spawn(&world, Position{f32(i + 100), 0})
    }

    testing.expect(t, entity_count(&world) == 10, "Should have 10 entities again")

    for i in 0..<5 {
        testing.expect(t, new_entities[i].generation == 1, "Respawned entities should have generation 1")
    }
}

@(test)
test_has_component :: proc(t: ^testing.T) {
    world := setup_world()
    defer destroy_world(&world)

    entity := spawn(&world, Position{1, 2})

    testing.expect(t, has(&world, entity, Position), "Should have Position")
    testing.expect(t, !has(&world, entity, Velocity), "Should not have Velocity")
    testing.expect(t, !has(&world, entity, Health), "Should not have Health")
}
