package main

import ecs ".."
import rl "vendor:raylib"
import "core:fmt"

Position :: struct {
    x, y: f32,
}

Color :: struct {
    r, g, b: f32,
}

POSITION: u64
COLOR:    u64

main :: proc() {
    rl.InitWindow(800, 600, "Render Test")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    world := ecs.create_world()
    defer ecs.destroy_world(&world)

    POSITION = ecs.register(&world, Position)
    COLOR    = ecs.register(&world, Color)

    fmt.println("POSITION:", POSITION)
    fmt.println("COLOR:", COLOR)

    ecs.spawn(&world, Position{100, 100}, Color{1, 0, 0})
    ecs.spawn(&world, Position{200, 200}, Color{0, 1, 0})
    ecs.spawn(&world, Position{300, 300}, Color{0, 0, 1})
    ecs.spawn(&world, Position{400, 400}, Color{1, 1, 0})

    fmt.println("Entity count:", ecs.entity_count(&world))
    fmt.println("Archetypes:", len(world.archetypes))

    for &arch, arch_idx in world.archetypes {
        fmt.println("Archetype", arch_idx, "mask:", arch.mask, "entities:", len(arch.entities))
    }

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        rendered := 0
        for &arch in world.archetypes {
            if arch.mask & (POSITION | COLOR) != (POSITION | COLOR) {
                continue
            }

            positions := ecs.column(&arch, Position)
            colors := ecs.column(&arch, Color)

            if positions == nil {
                fmt.println("positions is nil!")
                continue
            }
            if colors == nil {
                fmt.println("colors is nil!")
                continue
            }

            for i in 0..<len(arch.entities) {
                pos := positions[i]
                col := colors[i]
                color := rl.Color{u8(col.r * 255), u8(col.g * 255), u8(col.b * 255), 255}
                rl.DrawCircle(i32(pos.x), i32(pos.y), 20, color)
                rendered += 1
            }
        }

        rl.DrawText(rl.TextFormat("Rendered: %d", rendered), 10, 10, 20, rl.WHITE)
        rl.EndDrawing()
    }
}
