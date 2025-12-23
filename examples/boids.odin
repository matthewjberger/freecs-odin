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
    visual_range_sq:         f32,
    min_speed:               f32,
    max_speed:               f32,
    paused:                  bool,
    mouse_attraction_weight: f32,
    mouse_repulsion_weight:  f32,
    mouse_influence_range:   f32,
}

Boid_Data :: struct {
    x, y:   f32,
    vx, vy: f32,
}

Spatial_Grid :: struct {
    cells:      [][]Boid_Data,
    cell_counts: []int,
    cell_size:  f32,
    width:      int,
    height:     int,
    inv_cell:   f32,
}

create_grid :: proc(screen_width, screen_height, cell_size: f32, max_per_cell: int) -> Spatial_Grid {
    width := int(math.ceil(screen_width / cell_size))
    height := int(math.ceil(screen_height / cell_size))
    total := width * height

    cells := make([][]Boid_Data, total)
    cell_counts := make([]int, total)
    for i in 0..<total {
        cells[i] = make([]Boid_Data, max_per_cell)
    }

    return Spatial_Grid{
        cells       = cells,
        cell_counts = cell_counts,
        cell_size   = cell_size,
        width       = width,
        height      = height,
        inv_cell    = 1.0 / cell_size,
    }
}

destroy_grid :: proc(grid: ^Spatial_Grid) {
    for &cell in grid.cells {
        delete(cell)
    }
    delete(grid.cells)
    delete(grid.cell_counts)
}

grid_clear :: #force_inline proc(grid: ^Spatial_Grid) {
    for i in 0..<len(grid.cell_counts) {
        grid.cell_counts[i] = 0
    }
}

grid_insert :: #force_inline proc(grid: ^Spatial_Grid, x, y, vx, vy: f32) #no_bounds_check {
    cell_x := clamp(int(x * grid.inv_cell), 0, grid.width - 1)
    cell_y := clamp(int(y * grid.inv_cell), 0, grid.height - 1)
    idx := cell_x + cell_y * grid.width
    count := grid.cell_counts[idx]
    if count < len(grid.cells[idx]) {
        grid.cells[idx][count] = Boid_Data{x, y, vx, vy}
        grid.cell_counts[idx] = count + 1
    }
}

fast_inv_sqrt :: #force_inline proc(x: f32) -> f32 {
    xhalf := 0.5 * x
    i := transmute(i32)x
    i = 0x5f3759df - (i >> 1)
    y := transmute(f32)i
    y = y * (1.5 - xhalf * y * y)
    return y
}

Boid_Cache :: struct {
    positions:  []Position,
    velocities: []Velocity,
    capacity:   int,
}

create_cache :: proc(capacity: int) -> Boid_Cache {
    return Boid_Cache{
        positions  = make([]Position, capacity),
        velocities = make([]Velocity, capacity),
        capacity   = capacity,
    }
}

destroy_cache :: proc(cache: ^Boid_Cache) {
    delete(cache.positions)
    delete(cache.velocities)
}

ensure_cache_capacity :: proc(cache: ^Boid_Cache, needed: int) {
    if needed > cache.capacity {
        new_cap := needed * 2
        delete(cache.positions)
        delete(cache.velocities)
        cache.positions = make([]Position, new_cap)
        cache.velocities = make([]Velocity, new_cap)
        cache.capacity = new_cap
    }
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
    boid_mask := POSITION | VELOCITY | BOID

    entity_total := ecs.entity_count(world)
    ensure_cache_capacity(cache, entity_total)

    grid_clear(grid)

    matching := ecs.get_matching_archetypes(world, boid_mask)
    boid_count := 0

    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        velocities := ecs.column_unchecked(arch, Velocity, VELOCITY)
        count := len(arch.entities)

        #no_bounds_check for i in 0..<count {
            p := positions[i]
            v := velocities[i]
            cache.positions[boid_count] = p
            cache.velocities[boid_count] = v
            grid_insert(grid, p.x, p.y, v.x, v.y)
            boid_count += 1
        }
    }

    visual_range_sq := params.visual_range_sq
    range_cells := int(math.ceil(params.visual_range * grid.inv_cell))
    mouse_range_sq := params.mouse_influence_range * params.mouse_influence_range

    boid_idx := 0
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        velocities := ecs.column_unchecked(arch, Velocity, VELOCITY)
        count := len(arch.entities)

        #no_bounds_check for i in 0..<count {
            pos := cache.positions[boid_idx]
            vel := cache.velocities[boid_idx]

            align_x, align_y: f32 = 0, 0
            cohesion_x, cohesion_y: f32 = 0, 0
            sep_x, sep_y: f32 = 0, 0
            neighbors := 0

            cell_x := int(pos.x * grid.inv_cell)
            cell_y := int(pos.y * grid.inv_cell)

            for dy in -range_cells..=range_cells {
                cy := cell_y + dy
                if cy < 0 || cy >= grid.height { continue }

                for dx in -range_cells..=range_cells {
                    cx := cell_x + dx
                    if cx < 0 || cx >= grid.width { continue }

                    cell_idx := cx + cy * grid.width
                    cell_count := grid.cell_counts[cell_idx]
                    cell := grid.cells[cell_idx]

                    for j in 0..<cell_count {
                        boid := cell[j]
                        bx := boid.x - pos.x
                        by := boid.y - pos.y
                        dist_sq := bx * bx + by * by

                        if dist_sq > 0 && dist_sq < visual_range_sq {
                            align_x += boid.vx
                            align_y += boid.vy
                            cohesion_x += boid.x
                            cohesion_y += boid.y
                            inv_dist := fast_inv_sqrt(dist_sq)
                            sep_x -= bx * inv_dist
                            sep_y -= by * inv_dist
                            neighbors += 1
                            if neighbors >= MAX_NEIGHBORS { break }
                        }
                    }
                    if neighbors >= MAX_NEIGHBORS { break }
                }
                if neighbors >= MAX_NEIGHBORS { break }
            }

            mouse_dx := mouse_pos[0] - pos.x
            mouse_dy := mouse_pos[1] - pos.y
            mouse_dist_sq := mouse_dx * mouse_dx + mouse_dy * mouse_dy

            if mouse_dist_sq < mouse_range_sq {
                mouse_inv := fast_inv_sqrt(mouse_range_sq)
                mouse_influence := 1.0 - math.sqrt(mouse_dist_sq) * mouse_inv
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
                vel.x += (align_x * inv) * params.alignment_weight
                vel.y += (align_y * inv) * params.alignment_weight
                vel.x += (cohesion_x * inv - pos.x) * params.cohesion_weight
                vel.y += (cohesion_y * inv - pos.y) * params.cohesion_weight
                vel.x += sep_x * params.separation_weight
                vel.y += sep_y * params.separation_weight
            }

            speed_sq := vel.x * vel.x + vel.y * vel.y
            max_sq := params.max_speed * params.max_speed
            min_sq := params.min_speed * params.min_speed

            if speed_sq > max_sq {
                f := params.max_speed * fast_inv_sqrt(speed_sq)
                vel.x *= f
                vel.y *= f
            } else if speed_sq < min_sq && speed_sq > 0 {
                f := params.min_speed * fast_inv_sqrt(speed_sq)
                vel.x *= f
                vel.y *= f
            }

            velocities[i] = vel
            boid_idx += 1
        }
    }
}

update_positions :: proc(world: ^ecs.World, dt: f32) {
    move_mask := POSITION | VELOCITY
    matching := ecs.get_matching_archetypes(world, move_mask)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        velocities := ecs.column_unchecked(arch, Velocity, VELOCITY)
        count := len(arch.entities)
        #no_bounds_check for i in 0..<count {
            positions[i].x += velocities[i].x * dt
            positions[i].y += velocities[i].y * dt
        }
    }
}

wrap_positions :: proc(world: ^ecs.World, screen_w, screen_h: f32) {
    matching := ecs.get_matching_archetypes(world, POSITION)
    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        count := len(arch.entities)
        #no_bounds_check for i in 0..<count {
            p := &positions[i]
            if p.x < 0 { p.x += screen_w }
            else if p.x > screen_w { p.x -= screen_w }
            if p.y < 0 { p.y += screen_h }
            else if p.y > screen_h { p.y -= screen_h }
        }
    }
}

render_boids :: proc(world: ^ecs.World) {
    render_mask := POSITION | VELOCITY | COLOR
    matching := ecs.get_matching_archetypes(world, render_mask)

    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        velocities := ecs.column_unchecked(arch, Velocity, VELOCITY)
        colors := ecs.column_unchecked(arch, Boid_Color, COLOR)
        count := len(arch.entities)

        #no_bounds_check for i in 0..<count {
            pos := positions[i]
            vel := velocities[i]
            col := colors[i]

            speed_sq := vel.x * vel.x + vel.y * vel.y
            if speed_sq < 0.01 { continue }

            inv_speed := fast_inv_sqrt(speed_sq)
            dx := vel.x * inv_speed
            dy := vel.y * inv_speed

            px := -dy * 4
            py := dx * 4

            p1 := rl.Vector2{pos.x + dx * 6, pos.y + dy * 6}
            p2 := rl.Vector2{pos.x - dx * 4 + px, pos.y - dy * 4 + py}
            p3 := rl.Vector2{pos.x - dx * 4 - px, pos.y - dy * 4 - py}

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

    visual_range: f32 = 50.0
    params := Boid_Params{
        alignment_weight        = 0.5,
        cohesion_weight         = 0.3,
        separation_weight       = 0.4,
        visual_range            = visual_range,
        visual_range_sq         = visual_range * visual_range,
        min_speed               = 100.0,
        max_speed               = 300.0,
        mouse_attraction_weight = 0.96,
        mouse_repulsion_weight  = 1.2,
        mouse_influence_range   = 150.0,
    }

    grid := create_grid(f32(screen_w), f32(screen_h), visual_range / 2, 64)
    defer destroy_grid(&grid)

    cache := create_cache(2000)
    defer destroy_cache(&cache)

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
