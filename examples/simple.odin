package main

import ecs ".."
import "core:fmt"

Position :: struct {
    x, y: f32,
}

Velocity :: struct {
    x, y: f32,
}

main :: proc() {
    world := ecs.create_world()
    defer ecs.destroy_world(&world)

    POSITION := ecs.register(&world, Position)
    VELOCITY := ecs.register(&world, Velocity)

    fmt.println("POSITION bit:", POSITION)
    fmt.println("VELOCITY bit:", VELOCITY)

    e1 := ecs.spawn(&world, Position{1, 2}, Velocity{3, 4})
    e2 := ecs.spawn(&world, Position{5, 6}, Velocity{7, 8})
    e3 := ecs.spawn(&world, Position{9, 10}, Velocity{11, 12})

    fmt.println("Entity count:", ecs.entity_count(&world))
    fmt.println("Archetypes:", len(world.archetypes))

    if len(world.archetypes) > 0 {
        arch := &world.archetypes[0]
        fmt.println("Archetype mask:", arch.mask)
        fmt.println("Archetype entities:", len(arch.entities))
        fmt.println("Archetype columns:", len(arch.columns))

        for col_idx in 0..<len(arch.columns) {
            col := &arch.columns[col_idx]
            fmt.println("  Column", col_idx, "tid:", col.tid, "size:", col.elem_size, "data len:", len(col.data))
        }

        fmt.println("type_map entries:", len(arch.type_map))
        for tid, idx in arch.type_map {
            fmt.println("  tid:", tid, "-> col:", idx)
        }

        positions := ecs.column(arch, Position)
        velocities := ecs.column(arch, Velocity)

        fmt.println("positions slice:", positions)
        fmt.println("velocities slice:", velocities)

        if positions != nil {
            fmt.println("Position count:", len(positions))
            for i in 0..<len(positions) {
                fmt.println("  pos[", i, "]:", positions[i])
            }
        } else {
            fmt.println("ERROR: positions is nil!")
        }

        if velocities != nil {
            fmt.println("Velocity count:", len(velocities))
        } else {
            fmt.println("ERROR: velocities is nil!")
        }
    }

    pos := ecs.get(&world, e1, Position)
    if pos != nil {
        fmt.println("e1 position:", pos^)
    } else {
        fmt.println("ERROR: e1 position is nil!")
    }
}
