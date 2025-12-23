package main

import rl "vendor:raylib"
import "core:math"

main :: proc() {
    rl.InitWindow(800, 600, "Triangle Test")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        pos := rl.Vector2{400, 300}
        vel := rl.Vector2{100, 0}
        angle := math.atan2(vel.y, vel.x)

        p1 := rl.Vector2{pos.x, pos.y}
        p2 := rl.Vector2{pos.x - 8 * math.cos(angle + 2), pos.y - 8 * math.sin(angle + 2)}
        p3 := rl.Vector2{pos.x - 8 * math.cos(angle - 2), pos.y - 8 * math.sin(angle - 2)}

        rl.DrawTriangle(p1, p2, p3, rl.RED)
        rl.DrawTriangle(p1, p3, p2, rl.GREEN)

        rl.DrawText("Red = original order, Green = reversed", 10, 10, 20, rl.WHITE)
        rl.DrawText(rl.TextFormat("p1: %.1f, %.1f", p1.x, p1.y), 10, 40, 16, rl.WHITE)
        rl.DrawText(rl.TextFormat("p2: %.1f, %.1f", p2.x, p2.y), 10, 60, 16, rl.WHITE)
        rl.DrawText(rl.TextFormat("p3: %.1f, %.1f", p3.x, p3.y), 10, 80, 16, rl.WHITE)

        rl.EndDrawing()
    }
}
