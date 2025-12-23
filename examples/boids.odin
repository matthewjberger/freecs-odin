package main

import ecs ".."
import rl "vendor:raylib"
import "core:math"
import "core:math/rand"

Position :: struct {
    x, y: f32,
}

Velocity :: struct {
    x, y: f32,
}

Boid :: struct {
    _: u8,
}

Boid_Color :: struct {
    r, g, b: f32,
}

Boid_Params :: struct {
    alignment_weight:        f32,
    cohesion_weight:         f32,
    separation_weight:       f32,
    visual_range:            f32,
    min_speed:               f32,
    max_speed:               f32,
    paused:                  bool,
    mouse_attraction_weight: f32,
    mouse_repulsion_weight:  f32,
    mouse_influence_range:   f32,
}

Boid_Data :: struct {
    pos: Position,
    vel: Velocity,
}

Spatial_Grid :: struct {
    cells:           [dynamic][dynamic]Boid_Data,
    neighbor_buffer: [dynamic]Boid_Data,
    cell_size:       f32,
    width:           int,
    height:          int,
}

create_grid :: proc(screen_width, screen_height, cell_size: f32) -> Spatial_Grid {
    width := int(math.ceil(screen_width / cell_size))
    height := int(math.ceil(screen_height / cell_size))

    cells := make([dynamic][dynamic]Boid_Data, width * height)
    for &cell in cells {
        cell = make([dynamic]Boid_Data)
    }

    return Spatial_Grid{
        cells           = cells,
        neighbor_buffer = make([dynamic]Boid_Data),
        cell_size       = cell_size,
        width           = width,
        height          = height,
    }
}

destroy_grid :: proc(grid: ^Spatial_Grid) {
    for &cell in grid.cells {
        delete(cell)
    }
    delete(grid.cells)
    delete(grid.neighbor_buffer)
}

grid_clear :: proc(grid: ^Spatial_Grid) {
    for &cell in grid.cells {
        clear(&cell)
    }
}

grid_insert :: proc(grid: ^Spatial_Grid, pos: Position, vel: Velocity) {
    index := grid_cell_index(grid, pos.x, pos.y)
    if index >= 0 && index < len(grid.cells) {
        append(&grid.cells[index], Boid_Data{pos, vel})
    }
}

grid_cell_index :: proc(grid: ^Spatial_Grid, x, y: f32) -> int {
    cell_x := clamp(int(math.floor(x / grid.cell_size)), 0, grid.width - 1)
    cell_y := clamp(int(math.floor(y / grid.cell_size)), 0, grid.height - 1)
    return cell_x + cell_y * grid.width
}

grid_get_nearby :: proc(grid: ^Spatial_Grid, pos: Position, range: f32) -> []Boid_Data {
    clear(&grid.neighbor_buffer)

    range_cells := int(math.ceil(range / grid.cell_size))
    cell_x := int(math.floor(pos.x / grid.cell_size))
    cell_y := int(math.floor(pos.y / grid.cell_size))

    for dy in -range_cells..=range_cells {
        for dx in -range_cells..=range_cells {
            x := cell_x + dx
            y := cell_y + dy

            if x >= 0 && x < grid.width && y >= 0 && y < grid.height {
                index := x + y * grid.width
                for boid in grid.cells[index] {
                    append(&grid.neighbor_buffer, boid)
                }
            }
        }
    }

    return grid.neighbor_buffer[:]
}

Boid_Cache :: struct {
    velocity_updates:   [dynamic]Velocity,
    positions_snapshot: [dynamic]Position,
}

POSITION: u64
VELOCITY: u64
BOID:     u64
COLOR:    u64

spawn_boids :: proc(world: ^ecs.World, count: int, screen_w, screen_h: f32) {
    for _ in 0..<count {
        angle := rand.float32() * math.PI * 2
        speed := rand.float32_range(100, 200)

        ecs.spawn(world,
            Position{rand.float32_range(0, screen_w), rand.float32_range(0, screen_h)},
            Velocity{math.cos(angle) * speed, math.sin(angle) * speed},
            Boid{},
            Boid_Color{rand.float32_range(0.5, 1.0), rand.float32_range(0.5, 1.0), rand.float32_range(0.5, 1.0)},
        )
    }
}

process_boids :: proc(world: ^ecs.World, grid: ^Spatial_Grid, cache: ^Boid_Cache, params: ^Boid_Params, mouse_pos: [2]f32, mouse_attract, mouse_repel: bool) {
    MAX_NEIGHBORS :: 7

    grid_clear(grid)
    clear(&cache.positions_snapshot)

    for &arch in world.archetypes {
        if arch.mask & (POSITION | VELOCITY | BOID) != (POSITION | VELOCITY | BOID) {
            continue
        }
        positions := ecs.column(&arch, Position)
        velocities := ecs.column(&arch, Velocity)
        if positions == nil || velocities == nil {
            continue
        }
        for i in 0..<len(arch.entities) {
            append(&cache.positions_snapshot, positions[i])
            grid_insert(grid, positions[i], velocities[i])
        }
    }

    clear(&cache.velocity_updates)

    boid_idx := 0
    for &arch in world.archetypes {
        if arch.mask & (POSITION | VELOCITY | BOID) != (POSITION | VELOCITY | BOID) {
            continue
        }
        velocities := ecs.column(&arch, Velocity)
        if velocities == nil {
            continue
        }

        for i in 0..<len(arch.entities) {
            pos := cache.positions_snapshot[boid_idx]
            vel := velocities[i]

            alignment := Velocity{}
            cohesion := Position{}
            separation := Velocity{}
            neighbors := 0

            nearby := grid_get_nearby(grid, pos, params.visual_range)
            for boid_data in nearby {
                dx := boid_data.pos.x - pos.x
                dy := boid_data.pos.y - pos.y
                dist_sq := dx * dx + dy * dy

                if dist_sq > 0 && dist_sq < params.visual_range * params.visual_range {
                    alignment.x += boid_data.vel.x
                    alignment.y += boid_data.vel.y
                    cohesion.x += boid_data.pos.x
                    cohesion.y += boid_data.pos.y
                    factor := 1.0 / math.sqrt(dist_sq)
                    separation.x -= dx * factor
                    separation.y -= dy * factor
                    neighbors += 1
                    if neighbors >= MAX_NEIGHBORS { break }
                }
            }

            mouse_dx := mouse_pos[0] - pos.x
            mouse_dy := mouse_pos[1] - pos.y
            mouse_dist_sq := mouse_dx * mouse_dx + mouse_dy * mouse_dy
            mouse_range_sq := params.mouse_influence_range * params.mouse_influence_range

            if mouse_dist_sq < mouse_range_sq {
                mouse_influence := 1.0 - math.sqrt(mouse_dist_sq / mouse_range_sq)
                if mouse_attract {
                    vel.x += mouse_dx * mouse_influence * params.mouse_attraction_weight
                    vel.y += mouse_dy * mouse_influence * params.mouse_attraction_weight
                }
                if mouse_repel {
                    vel.x -= mouse_dx * mouse_influence * params.mouse_repulsion_weight
                    vel.y -= mouse_dy * mouse_influence * params.mouse_repulsion_weight
                }
            }

            if neighbors > 0 {
                inv := 1.0 / f32(neighbors)
                alignment.x *= inv * params.alignment_weight
                alignment.y *= inv * params.alignment_weight
                cohesion.x = (cohesion.x * inv - pos.x) * params.cohesion_weight
                cohesion.y = (cohesion.y * inv - pos.y) * params.cohesion_weight
                vel.x += alignment.x + cohesion.x + separation.x * params.separation_weight
                vel.y += alignment.y + cohesion.y + separation.y * params.separation_weight
            }

            speed := math.sqrt(vel.x * vel.x + vel.y * vel.y)
            if speed > params.max_speed {
                f := params.max_speed / speed
                vel.x *= f
                vel.y *= f
            } else if speed < params.min_speed && speed > 0 {
                f := params.min_speed / speed
                vel.x *= f
                vel.y *= f
            }

            append(&cache.velocity_updates, vel)
            boid_idx += 1
        }
    }

    update_idx := 0
    for &arch in world.archetypes {
        if arch.mask & (POSITION | VELOCITY | BOID) != (POSITION | VELOCITY | BOID) {
            continue
        }
        velocities := ecs.column(&arch, Velocity)
        if velocities == nil { continue }
        for i in 0..<len(arch.entities) {
            velocities[i] = cache.velocity_updates[update_idx]
            update_idx += 1
        }
    }
}

update_positions :: proc(world: ^ecs.World, dt: f32) {
    for &arch in world.archetypes {
        if arch.mask & (POSITION | VELOCITY) != (POSITION | VELOCITY) {
            continue
        }
        positions := ecs.column(&arch, Position)
        velocities := ecs.column(&arch, Velocity)
        if positions == nil || velocities == nil { continue }
        for i in 0..<len(arch.entities) {
            positions[i].x += velocities[i].x * dt
            positions[i].y += velocities[i].y * dt
        }
    }
}

wrap_positions :: proc(world: ^ecs.World, screen_w, screen_h: f32) {
    for &arch in world.archetypes {
        if arch.mask & POSITION == 0 { continue }
        positions := ecs.column(&arch, Position)
        if positions == nil { continue }
        for i in 0..<len(arch.entities) {
            if positions[i].x < 0 { positions[i].x += screen_w }
            if positions[i].x > screen_w { positions[i].x -= screen_w }
            if positions[i].y < 0 { positions[i].y += screen_h }
            if positions[i].y > screen_h { positions[i].y -= screen_h }
        }
    }
}

render_boids :: proc(world: ^ecs.World) {
    for &arch in world.archetypes {
        if arch.mask & (POSITION | VELOCITY | COLOR) != (POSITION | VELOCITY | COLOR) {
            continue
        }
        positions := ecs.column(&arch, Position)
        velocities := ecs.column(&arch, Velocity)
        colors := ecs.column(&arch, Boid_Color)
        if positions == nil || velocities == nil || colors == nil { continue }

        for i in 0..<len(arch.entities) {
            pos := positions[i]
            vel := velocities[i]
            col := colors[i]

            angle := math.atan2(vel.y, vel.x)
            p1 := rl.Vector2{pos.x, pos.y}
            p2 := rl.Vector2{pos.x - 8 * math.cos(angle + 2), pos.y - 8 * math.sin(angle + 2)}
            p3 := rl.Vector2{pos.x - 8 * math.cos(angle - 2), pos.y - 8 * math.sin(angle - 2)}
            color := rl.Color{u8(col.r * 255), u8(col.g * 255), u8(col.b * 255), 255}
            rl.DrawTriangle(p1, p3, p2, color)
        }
    }
}

main :: proc() {
    screen_w: i32 = 1280
    screen_h: i32 = 720

    rl.InitWindow(screen_w, screen_h, "Boids - Odin ECS")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    world := ecs.create_world()
    defer ecs.destroy_world(&world)

    POSITION = ecs.register(&world, Position)
    VELOCITY = ecs.register(&world, Velocity)
    BOID     = ecs.register(&world, Boid)
    COLOR    = ecs.register(&world, Boid_Color)

    params := Boid_Params{
        alignment_weight        = 0.5,
        cohesion_weight         = 0.3,
        separation_weight       = 0.4,
        visual_range            = 50.0,
        min_speed               = 100.0,
        max_speed               = 300.0,
        mouse_attraction_weight = 0.96,
        mouse_repulsion_weight  = 1.2,
        mouse_influence_range   = 150.0,
    }

    grid := create_grid(f32(screen_w), f32(screen_h), params.visual_range / 2)
    defer destroy_grid(&grid)

    cache := Boid_Cache{
        velocity_updates   = make([dynamic]Velocity),
        positions_snapshot = make([dynamic]Position),
    }
    defer delete(cache.velocity_updates)
    defer delete(cache.positions_snapshot)

    spawn_boids(&world, 1000, f32(screen_w), f32(screen_h))

    for !rl.WindowShouldClose() {
        dt := params.paused ? f32(0) : rl.GetFrameTime()

        mouse := rl.GetMousePosition()
        mouse_pos := [2]f32{mouse.x, mouse.y}
        mouse_attract := rl.IsMouseButtonDown(.LEFT)
        mouse_repel := rl.IsMouseButtonDown(.RIGHT)

        if rl.IsKeyPressed(.SPACE) { params.paused = !params.paused }

        if rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD) {
            spawn_boids(&world, 1000, f32(screen_w), f32(screen_h))
        }
        if rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT) {
            to_despawn := make([dynamic]ecs.Entity, context.temp_allocator)
            count := 0
            outer: for &arch in world.archetypes {
                for entity in arch.entities {
                    if count >= 1000 { break outer }
                    append(&to_despawn, entity)
                    count += 1
                }
            }
            for entity in to_despawn {
                ecs.despawn(&world, entity)
            }
        }

        speed: f32 = rl.IsKeyDown(.LEFT_SHIFT) ? 0.01 : 0.001
        if rl.IsKeyDown(.LEFT) { params.alignment_weight = max(params.alignment_weight - speed, 0) }
        if rl.IsKeyDown(.RIGHT) { params.alignment_weight = min(params.alignment_weight + speed, 1) }
        if rl.IsKeyDown(.DOWN) { params.cohesion_weight = max(params.cohesion_weight - speed, 0) }
        if rl.IsKeyDown(.UP) { params.cohesion_weight = min(params.cohesion_weight + speed, 1) }

        process_boids(&world, &grid, &cache, &params, mouse_pos, mouse_attract, mouse_repel)
        update_positions(&world, dt)
        wrap_positions(&world, f32(screen_w), f32(screen_h))

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        render_boids(&world)

        if mouse_attract || mouse_repel {
            color := mouse_attract ? rl.Color{0, 255, 0, 50} : rl.Color{255, 0, 0, 50}
            rl.DrawCircleLines(i32(mouse.x), i32(mouse.y), params.mouse_influence_range, color)
        }

        entity_count := ecs.entity_count(&world)
        rl.DrawRectangle(screen_w - 260, 0, 260, 280, rl.Color{0, 0, 0, 180})

        y: i32 = 20
        rl.DrawText(rl.TextFormat("Entities: %d", entity_count), screen_w - 250, y, 20, rl.WHITE); y += 25
        rl.DrawText(rl.TextFormat("FPS: %d", rl.GetFPS()), screen_w - 250, y, 20, rl.WHITE); y += 35
        rl.DrawText("[Space] Pause", screen_w - 250, y, 18, rl.WHITE); y += 22
        rl.DrawText("[+/-] Add/Remove 1000", screen_w - 250, y, 18, rl.WHITE); y += 22
        rl.DrawText("[Arrows] Adjust params", screen_w - 250, y, 18, rl.WHITE); y += 35
        rl.DrawText(rl.TextFormat("Alignment: %.2f", params.alignment_weight), screen_w - 250, y, 18, rl.WHITE); y += 22
        rl.DrawText(rl.TextFormat("Cohesion: %.2f", params.cohesion_weight), screen_w - 250, y, 18, rl.WHITE); y += 22
        rl.DrawText(rl.TextFormat("Separation: %.2f", params.separation_weight), screen_w - 250, y, 18, rl.WHITE); y += 35
        rl.DrawText("[Left Mouse] Attract", screen_w - 250, y, 18, rl.WHITE); y += 22
        rl.DrawText("[Right Mouse] Repel", screen_w - 250, y, 18, rl.WHITE)

        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}
