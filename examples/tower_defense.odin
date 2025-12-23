package main

import ecs ".."
import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "core:fmt"
import "core:strings"

GRID_SIZE :: 12
TILE_SIZE :: 40.0
BASE_WIDTH :: 1024.0
BASE_HEIGHT :: 768.0

Tower_Type :: enum {
    Basic,
    Frost,
    Cannon,
    Sniper,
    Poison,
}

Game_State :: enum {
    Waiting_For_Wave,
    Wave_In_Progress,
    Game_Over,
    Victory,
    Paused,
}

Enemy_Type :: enum {
    Normal,
    Fast,
    Tank,
    Flying,
    Shielded,
    Healer,
    Boss,
}

Effect_Type :: enum {
    Explosion,
    Poison_Bubble,
    Death_Particle,
}

Position :: struct {
    x, y: f32,
}

Velocity :: struct {
    x, y: f32,
}

Tower :: struct {
    tower_type:    Tower_Type,
    level:         u32,
    cooldown:      f32,
    target:        ecs.Entity,
    has_target:    bool,
    fire_animation: f32,
    tracking_time: f32,
}

Enemy :: struct {
    health:          f32,
    max_health:      f32,
    shield_health:   f32,
    max_shield:      f32,
    speed:           f32,
    path_index:      int,
    path_progress:   f32,
    value:           u32,
    enemy_type:      Enemy_Type,
    slow_duration:   f32,
    poison_duration: f32,
    poison_damage:   f32,
    is_flying:       bool,
}

Projectile :: struct {
    damage:          f32,
    target:          ecs.Entity,
    speed:           f32,
    tower_type:      Tower_Type,
    start_position:  [2]f32,
    arc_height:      f32,
    flight_progress: f32,
}

Grid_Cell :: struct {
    x, y:     i32,
    occupied: bool,
    is_path:  bool,
}

Grid_Position :: struct {
    x, y: i32,
}

Health_Bar :: struct {
    enemy_entity: ecs.Entity,
}

Visual_Effect :: struct {
    effect_type: Effect_Type,
    lifetime:    f32,
    age:         f32,
    velocity:    [2]f32,
}

Range_Indicator :: struct {
    tower_entity: ecs.Entity,
    visible:      bool,
}

Money_Popup :: struct {
    lifetime: f32,
    amount:   i32,
}

Enemy_Spawn_Info :: struct {
    enemy_type: Enemy_Type,
    spawn_time: f32,
}

Enemy_Spawned_Event :: struct {
    entity:     ecs.Entity,
    enemy_type: Enemy_Type,
}

Enemy_Died_Event :: struct {
    entity:     ecs.Entity,
    position:   [2]f32,
    reward:     u32,
    enemy_type: Enemy_Type,
}

Enemy_Reached_End_Event :: struct {
    entity: ecs.Entity,
    damage: u32,
}

Projectile_Hit_Event :: struct {
    projectile: ecs.Entity,
    target:     ecs.Entity,
    position:   [2]f32,
    damage:     f32,
    tower_type: Tower_Type,
}

Tower_Placed_Event :: struct {
    entity:     ecs.Entity,
    tower_type: Tower_Type,
    grid_x:     i32,
    grid_y:     i32,
    cost:       u32,
}

Tower_Sold_Event :: struct {
    entity:     ecs.Entity,
    tower_type: Tower_Type,
    grid_x:     i32,
    grid_y:     i32,
    refund:     u32,
}

Tower_Upgraded_Event :: struct {
    entity:     ecs.Entity,
    tower_type: Tower_Type,
    old_level:  u32,
    new_level:  u32,
    cost:       u32,
}

Wave_Completed_Event :: struct {
    wave: u32,
}

Wave_Started_Event :: struct {
    wave:        u32,
    enemy_count: int,
}

Game_Resources :: struct {
    money:               u32,
    lives:               u32,
    wave:                u32,
    game_state:          Game_State,
    selected_tower_type: Tower_Type,
    spawn_timer:         f32,
    enemies_to_spawn:    [dynamic]Enemy_Spawn_Info,
    mouse_grid_pos:      [2]i32,
    has_mouse_grid_pos:  bool,
    path:                [dynamic][2]f32,
    wave_announce_timer: f32,
    game_speed:          f32,
    current_hp:          u32,
    max_hp:              u32,
}

Game_World :: struct {
    world:                  ecs.World,
    tags:                   ecs.Tags,
    resources:              Game_Resources,
    cmd_buffer:             ecs.Command_Buffer,
    enemy_spawned_events:   ecs.Event_Queue(Enemy_Spawned_Event),
    enemy_died_events:      ecs.Event_Queue(Enemy_Died_Event),
    enemy_reached_events:   ecs.Event_Queue(Enemy_Reached_End_Event),
    projectile_hit_events:  ecs.Event_Queue(Projectile_Hit_Event),
    tower_placed_events:    ecs.Event_Queue(Tower_Placed_Event),
    tower_sold_events:      ecs.Event_Queue(Tower_Sold_Event),
    tower_upgraded_events:  ecs.Event_Queue(Tower_Upgraded_Event),
    wave_completed_events:  ecs.Event_Queue(Wave_Completed_Event),
    wave_started_events:    ecs.Event_Queue(Wave_Started_Event),
}

POSITION:         u64
VELOCITY:         u64
TOWER:            u64
ENEMY:            u64
PROJECTILE:       u64
GRID_CELL:        u64
GRID_POSITION:    u64
HEALTH_BAR:       u64
VISUAL_EFFECT:    u64
RANGE_INDICATOR:  u64
MONEY_POPUP:      u64

TAG_BASIC_ENEMY:  int
TAG_TANK_ENEMY:   int
TAG_FAST_ENEMY:   int
TAG_FLYING_ENEMY: int
TAG_HEALER_ENEMY: int
TAG_BASIC_TOWER:  int
TAG_FROST_TOWER:  int
TAG_CANNON_TOWER: int
TAG_SNIPER_TOWER: int
TAG_POISON_TOWER: int
TAG_PATH_CELL:    int

create_game_world :: proc() -> Game_World {
    game: Game_World
    game.world = ecs.create_world()
    game.tags = ecs.create_tags()
    game.cmd_buffer = ecs.create_command_buffer(&game.world)
    game.enemy_spawned_events = ecs.create_event_queue(Enemy_Spawned_Event)
    game.enemy_died_events = ecs.create_event_queue(Enemy_Died_Event)
    game.enemy_reached_events = ecs.create_event_queue(Enemy_Reached_End_Event)
    game.projectile_hit_events = ecs.create_event_queue(Projectile_Hit_Event)
    game.tower_placed_events = ecs.create_event_queue(Tower_Placed_Event)
    game.tower_sold_events = ecs.create_event_queue(Tower_Sold_Event)
    game.tower_upgraded_events = ecs.create_event_queue(Tower_Upgraded_Event)
    game.wave_completed_events = ecs.create_event_queue(Wave_Completed_Event)
    game.wave_started_events = ecs.create_event_queue(Wave_Started_Event)
    game.resources.enemies_to_spawn = make([dynamic]Enemy_Spawn_Info)
    game.resources.path = make([dynamic][2]f32)
    return game
}

destroy_game_world :: proc(game: ^Game_World) {
    ecs.destroy_world(&game.world)
    ecs.destroy_tags(&game.tags)
    ecs.destroy_command_buffer(&game.cmd_buffer)
    ecs.destroy_event_queue(&game.enemy_spawned_events)
    ecs.destroy_event_queue(&game.enemy_died_events)
    ecs.destroy_event_queue(&game.enemy_reached_events)
    ecs.destroy_event_queue(&game.projectile_hit_events)
    ecs.destroy_event_queue(&game.tower_placed_events)
    ecs.destroy_event_queue(&game.tower_sold_events)
    ecs.destroy_event_queue(&game.tower_upgraded_events)
    ecs.destroy_event_queue(&game.wave_completed_events)
    ecs.destroy_event_queue(&game.wave_started_events)
    delete(game.resources.enemies_to_spawn)
    delete(game.resources.path)
}

step_events :: proc(game: ^Game_World) {
    ecs.update_event_queue(&game.enemy_spawned_events)
    ecs.update_event_queue(&game.enemy_died_events)
    ecs.update_event_queue(&game.enemy_reached_events)
    ecs.update_event_queue(&game.projectile_hit_events)
    ecs.update_event_queue(&game.tower_placed_events)
    ecs.update_event_queue(&game.tower_sold_events)
    ecs.update_event_queue(&game.tower_upgraded_events)
    ecs.update_event_queue(&game.wave_completed_events)
    ecs.update_event_queue(&game.wave_started_events)
}

tower_cost :: proc(tower_type: Tower_Type) -> u32 {
    switch tower_type {
    case .Basic:  return 60
    case .Frost:  return 120
    case .Cannon: return 200
    case .Sniper: return 180
    case .Poison: return 150
    }
    return 0
}

tower_upgrade_cost :: proc(tower_type: Tower_Type, current_level: u32) -> u32 {
    return u32(f32(tower_cost(tower_type)) * 0.5 * f32(current_level))
}

tower_damage :: proc(tower_type: Tower_Type, level: u32) -> f32 {
    base: f32
    switch tower_type {
    case .Basic:  base = 15.0
    case .Frost:  base = 8.0
    case .Cannon: base = 50.0
    case .Sniper: base = 80.0
    case .Poison: base = 5.0
    }
    return base * (1.0 + 0.25 * f32(level - 1))
}

tower_range :: proc(tower_type: Tower_Type, level: u32) -> f32 {
    base: f32
    switch tower_type {
    case .Basic:  base = 100.0
    case .Frost:  base = 80.0
    case .Cannon: base = 120.0
    case .Sniper: base = 180.0
    case .Poison: base = 90.0
    }
    return base * (1.0 + 0.15 * f32(level - 1))
}

tower_fire_rate :: proc(tower_type: Tower_Type, level: u32) -> f32 {
    base: f32
    switch tower_type {
    case .Basic:  base = 0.5
    case .Frost:  base = 1.0
    case .Cannon: base = 2.0
    case .Sniper: base = 3.0
    case .Poison: base = 0.8
    }
    return base * max(0.2, 1.0 - 0.1 * f32(level - 1))
}

tower_color :: proc(tower_type: Tower_Type) -> rl.Color {
    switch tower_type {
    case .Basic:  return rl.GREEN
    case .Frost:  return rl.Color{51, 153, 255, 255}
    case .Cannon: return rl.RED
    case .Sniper: return rl.DARKGRAY
    case .Poison: return rl.Color{153, 51, 204, 255}
    }
    return rl.WHITE
}

tower_projectile_speed :: proc(tower_type: Tower_Type) -> f32 {
    switch tower_type {
    case .Basic:  return 300.0
    case .Frost:  return 200.0
    case .Cannon: return 250.0
    case .Sniper: return 500.0
    case .Poison: return 250.0
    }
    return 300.0
}

enemy_base_health :: proc(enemy_type: Enemy_Type) -> f32 {
    switch enemy_type {
    case .Normal:   return 50.0
    case .Fast:     return 30.0
    case .Tank:     return 150.0
    case .Flying:   return 40.0
    case .Shielded: return 80.0
    case .Healer:   return 60.0
    case .Boss:     return 500.0
    }
    return 50.0
}

enemy_health :: proc(enemy_type: Enemy_Type, wave: u32) -> f32 {
    health_multiplier := 1.0 + (f32(wave) - 1.0) * 0.5
    return enemy_base_health(enemy_type) * health_multiplier
}

enemy_speed :: proc(enemy_type: Enemy_Type) -> f32 {
    switch enemy_type {
    case .Normal:   return 40.0
    case .Fast:     return 80.0
    case .Tank:     return 20.0
    case .Flying:   return 60.0
    case .Shielded: return 30.0
    case .Healer:   return 35.0
    case .Boss:     return 15.0
    }
    return 40.0
}

enemy_value :: proc(enemy_type: Enemy_Type, wave: u32) -> u32 {
    base: u32
    switch enemy_type {
    case .Normal:   base = 10
    case .Fast:     base = 15
    case .Tank:     base = 30
    case .Flying:   base = 20
    case .Shielded: base = 25
    case .Healer:   base = 40
    case .Boss:     base = 100
    }
    return base + wave * 2
}

enemy_shield :: proc(enemy_type: Enemy_Type) -> f32 {
    switch enemy_type {
    case .Shielded: return 50.0
    case .Boss:     return 100.0
    case .Normal, .Fast, .Tank, .Flying, .Healer: return 0.0
    }
    return 0.0
}

enemy_color :: proc(enemy_type: Enemy_Type) -> rl.Color {
    switch enemy_type {
    case .Normal:   return rl.RED
    case .Fast:     return rl.ORANGE
    case .Tank:     return rl.DARKGRAY
    case .Flying:   return rl.SKYBLUE
    case .Shielded: return rl.Color{128, 0, 204, 255}
    case .Healer:   return rl.Color{51, 204, 77, 255}
    case .Boss:     return rl.Color{153, 0, 153, 255}
    }
    return rl.RED
}

enemy_size :: proc(enemy_type: Enemy_Type) -> f32 {
    switch enemy_type {
    case .Normal:   return 15.0
    case .Fast:     return 12.0
    case .Tank:     return 20.0
    case .Flying:   return 15.0
    case .Shielded: return 18.0
    case .Healer:   return 16.0
    case .Boss:     return 30.0
    }
    return 15.0
}

get_scale :: proc() -> f32 {
    return min(f32(rl.GetScreenWidth()) / BASE_WIDTH, f32(rl.GetScreenHeight()) / BASE_HEIGHT)
}

get_offset :: proc() -> [2]f32 {
    scale := get_scale()
    scaled_width := BASE_WIDTH * scale
    scaled_height := BASE_HEIGHT * scale
    return {
        (f32(rl.GetScreenWidth()) - scaled_width) / 2.0,
        (f32(rl.GetScreenHeight()) - scaled_height) / 2.0,
    }
}

grid_to_base :: proc(grid_x, grid_y: i32) -> [2]f32 {
    num_cells := f32(GRID_SIZE + 1)
    grid_width := num_cells * TILE_SIZE
    grid_height := num_cells * TILE_SIZE
    grid_offset_x := (BASE_WIDTH - grid_width) / 2.0
    grid_offset_y := (BASE_HEIGHT - grid_height) / 2.0

    tile_x := f32(grid_x + GRID_SIZE / 2)
    tile_y := f32(grid_y + GRID_SIZE / 2)

    return {
        grid_offset_x + (tile_x + 0.5) * TILE_SIZE,
        grid_offset_y + (tile_y + 0.5) * TILE_SIZE,
    }
}

grid_to_screen :: proc(grid_x, grid_y: i32) -> [2]f32 {
    base_pos := grid_to_base(grid_x, grid_y)
    scale := get_scale()
    offset := get_offset()
    return {offset[0] + base_pos[0] * scale, offset[1] + base_pos[1] * scale}
}

screen_to_grid :: proc(screen_pos: [2]f32) -> ([2]i32, bool) {
    scale := get_scale()
    offset := get_offset()

    num_cells := f32(GRID_SIZE + 1)
    grid_width := num_cells * TILE_SIZE
    grid_height := num_cells * TILE_SIZE
    grid_offset_x := (BASE_WIDTH - grid_width) / 2.0
    grid_offset_y := (BASE_HEIGHT - grid_height) / 2.0

    local_x := (screen_pos[0] - offset[0]) / scale
    local_y := (screen_pos[1] - offset[1]) / scale

    rel_x := local_x - grid_offset_x
    rel_y := local_y - grid_offset_y

    if rel_x < 0 || rel_y < 0 || rel_x >= grid_width || rel_y >= grid_height {
        return {0, 0}, false
    }

    tile_x := i32(rel_x / TILE_SIZE)
    tile_y := i32(rel_y / TILE_SIZE)

    grid_x := tile_x - GRID_SIZE / 2
    grid_y := tile_y - GRID_SIZE / 2

    return {grid_x, grid_y}, true
}

initialize_grid :: proc(game: ^Game_World) {
    for x in -GRID_SIZE / 2 ..= GRID_SIZE / 2 {
        for y in -GRID_SIZE / 2 ..= GRID_SIZE / 2 {
            entity := ecs.spawn(&game.world, Grid_Cell{x = i32(x), y = i32(y), occupied = false, is_path = false})
            _ = entity
        }
    }
}

create_path :: proc(game: ^Game_World) {
    path_points := [][2]f32{
        {-6.0, 0.0},
        {-3.0, 0.0},
        {-3.0, -4.0},
        {3.0, -4.0},
        {3.0, 2.0},
        {-1.0, 2.0},
        {-1.0, 5.0},
        {6.0, 5.0},
    }

    num_cells := f32(GRID_SIZE + 1)
    grid_width := num_cells * TILE_SIZE
    grid_height := num_cells * TILE_SIZE
    grid_offset_x := (BASE_WIDTH - grid_width) / 2.0
    grid_offset_y := (BASE_HEIGHT - grid_height) / 2.0

    clear(&game.resources.path)
    for p in path_points {
        screen_p := [2]f32{
            grid_offset_x + (p[0] + f32(GRID_SIZE) / 2.0 + 0.5) * TILE_SIZE,
            grid_offset_y + (p[1] + f32(GRID_SIZE) / 2.0 + 0.5) * TILE_SIZE,
        }
        append(&game.resources.path, screen_p)
    }

    cells_to_mark := make([dynamic][2]i32, context.temp_allocator)

    for index in 0 ..< len(path_points) - 1 {
        start := path_points[index]
        end := path_points[index + 1]
        steps := 20

        for step in 0 ..= steps {
            t := f32(step) / f32(steps)
            pos_x := start[0] + (end[0] - start[0]) * t
            pos_y := start[1] + (end[1] - start[1]) * t
            grid_x := i32(math.round(pos_x))
            grid_y := i32(math.round(pos_y))
            append(&cells_to_mark, [2]i32{grid_x, grid_y})
        }
    }

    matching := ecs.get_matching_archetypes(&game.world, GRID_CELL)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        cells := ecs.column_unchecked(arch, Grid_Cell, GRID_CELL)
        for index in 0 ..< len(arch.entities) {
            cell := &cells[index]
            for mark in cells_to_mark {
                if cell.x == mark[0] && cell.y == mark[1] {
                    cell.is_path = true
                    cell.occupied = true
                    ecs.add_tag(&game.tags, TAG_PATH_CELL, arch.entities[index])
                    break
                }
            }
        }
    }
}

spawn_tower :: proc(game: ^Game_World, grid_x, grid_y: i32, tower_type: Tower_Type) -> ecs.Entity {
    position := grid_to_base(grid_x, grid_y)

    entity := ecs.spawn(
        &game.world,
        Position{position[0], position[1]},
        Grid_Position{grid_x, grid_y},
        Tower{
            tower_type     = tower_type,
            level          = 1,
            cooldown       = 0,
            has_target     = false,
            fire_animation = 0,
            tracking_time  = 0,
        },
    )

    switch tower_type {
    case .Basic:  ecs.add_tag(&game.tags, TAG_BASIC_TOWER, entity)
    case .Frost:  ecs.add_tag(&game.tags, TAG_FROST_TOWER, entity)
    case .Cannon: ecs.add_tag(&game.tags, TAG_CANNON_TOWER, entity)
    case .Sniper: ecs.add_tag(&game.tags, TAG_SNIPER_TOWER, entity)
    case .Poison: ecs.add_tag(&game.tags, TAG_POISON_TOWER, entity)
    }

    cost := tower_cost(tower_type)
    game.resources.money -= cost

    ecs.send_event(&game.tower_placed_events, Tower_Placed_Event{
        entity     = entity,
        tower_type = tower_type,
        grid_x     = grid_x,
        grid_y     = grid_y,
        cost       = cost,
    })

    spawn_range_indicator(game, entity)

    return entity
}

spawn_range_indicator :: proc(game: ^Game_World, tower_entity: ecs.Entity) {
    ecs.spawn(&game.world, Range_Indicator{tower_entity = tower_entity, visible = false})
}

spawn_enemy :: proc(game: ^Game_World, enemy_type: Enemy_Type) -> ecs.Entity {
    start_pos := game.resources.path[0]
    health := enemy_health(enemy_type, game.resources.wave)
    shield := enemy_shield(enemy_type)

    entity := ecs.spawn(
        &game.world,
        Position{start_pos[0], start_pos[1]},
        Velocity{0, 0},
        Enemy{
            health          = health,
            max_health      = health,
            shield_health   = shield,
            max_shield      = shield,
            speed           = enemy_speed(enemy_type),
            path_index      = 0,
            path_progress   = 0,
            value           = enemy_value(enemy_type, game.resources.wave),
            enemy_type      = enemy_type,
            slow_duration   = 0,
            poison_duration = 0,
            poison_damage   = 0,
            is_flying       = enemy_type == .Flying,
        },
    )
    ecs.add_component(&game.world, entity, Health_Bar{enemy_entity = entity})

    switch enemy_type {
    case .Normal:   ecs.add_tag(&game.tags, TAG_BASIC_ENEMY, entity)
    case .Tank:     ecs.add_tag(&game.tags, TAG_TANK_ENEMY, entity)
    case .Fast:     ecs.add_tag(&game.tags, TAG_FAST_ENEMY, entity)
    case .Flying:   ecs.add_tag(&game.tags, TAG_FLYING_ENEMY, entity)
    case .Healer:   ecs.add_tag(&game.tags, TAG_HEALER_ENEMY, entity)
    case .Shielded: ecs.add_tag(&game.tags, TAG_BASIC_ENEMY, entity)
    case .Boss:     ecs.add_tag(&game.tags, TAG_BASIC_ENEMY, entity)
    }

    ecs.send_event(&game.enemy_spawned_events, Enemy_Spawned_Event{entity = entity, enemy_type = enemy_type})

    return entity
}

spawn_projectile :: proc(game: ^Game_World, from: [2]f32, target: ecs.Entity, tower_type: Tower_Type, level: u32) -> ecs.Entity {
    arc_height: f32 = 0
    if tower_type == .Cannon {
        arc_height = 50.0
    }

    return ecs.spawn(
        &game.world,
        Position{from[0], from[1]},
        Velocity{0, 0},
        Projectile{
            damage          = tower_damage(tower_type, level),
            target          = target,
            speed           = tower_projectile_speed(tower_type),
            tower_type      = tower_type,
            start_position  = from,
            arc_height      = arc_height,
            flight_progress = 0,
        },
    )
}

spawn_visual_effect :: proc(game: ^Game_World, position: [2]f32, effect_type: Effect_Type, velocity: [2]f32, lifetime: f32) {
    ecs.spawn(
        &game.world,
        Position{position[0], position[1]},
        Visual_Effect{
            effect_type = effect_type,
            lifetime    = lifetime,
            age         = 0,
            velocity    = velocity,
        },
    )
}

spawn_money_popup :: proc(game: ^Game_World, position: [2]f32, amount: i32) {
    ecs.spawn(&game.world, Position{position[0], position[1]}, Money_Popup{lifetime = 0, amount = amount})
}

can_place_tower_at :: proc(game: ^Game_World, x, y: i32) -> bool {
    matching := ecs.get_matching_archetypes(&game.world, TOWER | GRID_POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        grid_positions := ecs.column_unchecked(arch, Grid_Position, GRID_POSITION)
        for index in 0 ..< len(arch.entities) {
            if grid_positions[index].x == x && grid_positions[index].y == y {
                return false
            }
        }
    }

    matching = ecs.get_matching_archetypes(&game.world, GRID_CELL)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        cells := ecs.column_unchecked(arch, Grid_Cell, GRID_CELL)
        for index in 0 ..< len(arch.entities) {
            if cells[index].x == x && cells[index].y == y && !cells[index].occupied {
                return true
            }
        }
    }

    return false
}

mark_cell_occupied :: proc(game: ^Game_World, x, y: i32) {
    matching := ecs.get_matching_archetypes(&game.world, GRID_CELL)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        cells := ecs.column_unchecked(arch, Grid_Cell, GRID_CELL)
        for index in 0 ..< len(arch.entities) {
            if cells[index].x == x && cells[index].y == y {
                cells[index].occupied = true
            }
        }
    }
}

plan_wave :: proc(game: ^Game_World) {
    game.resources.wave += 1
    wave := game.resources.wave

    enemy_count := 5 + wave * 2

    Enemy_Prob :: struct {
        enemy_type:  Enemy_Type,
        probability: f32,
    }

    enemy_types: []Enemy_Prob
    switch {
    case wave <= 2:
        enemy_types = {{.Normal, 1.0}}
    case wave <= 4:
        enemy_types = {{.Normal, 0.7}, {.Fast, 0.3}}
    case wave <= 6:
        enemy_types = {{.Normal, 0.5}, {.Fast, 0.3}, {.Tank, 0.2}}
    case wave <= 8:
        enemy_types = {{.Normal, 0.3}, {.Fast, 0.3}, {.Tank, 0.2}, {.Flying, 0.2}}
    case wave <= 10:
        enemy_types = {{.Normal, 0.2}, {.Fast, 0.2}, {.Tank, 0.2}, {.Flying, 0.2}, {.Shielded, 0.2}}
    case wave <= 12:
        enemy_types = {{.Fast, 0.2}, {.Tank, 0.2}, {.Flying, 0.2}, {.Shielded, 0.2}, {.Healer, 0.2}}
    case wave <= 14:
        enemy_types = {{.Tank, 0.2}, {.Flying, 0.2}, {.Shielded, 0.2}, {.Healer, 0.2}, {.Boss, 0.2}}
    case:
        enemy_types = {{.Tank, 0.15}, {.Flying, 0.2}, {.Shielded, 0.2}, {.Healer, 0.2}, {.Boss, 0.25}}
    }

    spawn_interval: f32
    switch {
    case wave <= 3:  spawn_interval = 1.0
    case wave <= 6:  spawn_interval = 0.8
    case wave <= 9:  spawn_interval = 0.6
    case:            spawn_interval = 0.5
    }

    clear(&game.resources.enemies_to_spawn)
    spawn_time: f32 = 0

    for _ in 0 ..< enemy_count {
        roll := rand.float32()
        cumulative: f32 = 0
        selected_type := Enemy_Type.Normal

        for ep in enemy_types {
            cumulative += ep.probability
            if roll < cumulative {
                selected_type = ep.enemy_type
                break
            }
        }

        append(&game.resources.enemies_to_spawn, Enemy_Spawn_Info{enemy_type = selected_type, spawn_time = spawn_time})
        spawn_time += spawn_interval
    }

    game.resources.spawn_timer = 0
    game.resources.game_state = .Wave_In_Progress
    game.resources.wave_announce_timer = 3.0

    ecs.send_event(&game.wave_started_events, Wave_Started_Event{wave = wave, enemy_count = int(enemy_count)})
}

input_system :: proc(game: ^Game_World) {
    mouse := rl.GetMousePosition()
    mouse_pos := [2]f32{mouse.x, mouse.y}
    grid_pos, has_grid := screen_to_grid(mouse_pos)
    game.resources.mouse_grid_pos = grid_pos
    game.resources.has_mouse_grid_pos = has_grid

    left_clicked := rl.IsMouseButtonPressed(.LEFT)
    right_clicked := rl.IsMouseButtonPressed(.RIGHT)

    if left_clicked && has_grid && can_place_tower_at(game, grid_pos[0], grid_pos[1]) {
        tower_type := game.resources.selected_tower_type
        if game.resources.money >= tower_cost(tower_type) {
            cost := tower_cost(tower_type)
            spawn_tower(game, grid_pos[0], grid_pos[1], tower_type)
            mark_cell_occupied(game, grid_pos[0], grid_pos[1])
            pos := grid_to_base(grid_pos[0], grid_pos[1])
            spawn_money_popup(game, pos, -i32(cost))
        }
    }

    if right_clicked && has_grid {
        tower_entity: ecs.Entity
        found := false
        matching := ecs.get_matching_archetypes(&game.world, TOWER | GRID_POSITION)
        for arch_idx in matching {
            arch := &game.world.archetypes[arch_idx]
            grid_positions := ecs.column_unchecked(arch, Grid_Position, GRID_POSITION)
            for index in 0 ..< len(arch.entities) {
                if grid_positions[index].x == grid_pos[0] && grid_positions[index].y == grid_pos[1] {
                    tower_entity = arch.entities[index]
                    found = true
                    break
                }
            }
            if found { break }
        }
        if found {
            sell_tower(game, tower_entity, grid_pos[0], grid_pos[1])
        }
    }

    if (rl.IsKeyPressed(.U) || rl.IsMouseButtonPressed(.MIDDLE)) && has_grid {
        tower_entity: ecs.Entity
        found := false
        matching := ecs.get_matching_archetypes(&game.world, TOWER | GRID_POSITION)
        for arch_idx in matching {
            arch := &game.world.archetypes[arch_idx]
            grid_positions := ecs.column_unchecked(arch, Grid_Position, GRID_POSITION)
            for index in 0 ..< len(arch.entities) {
                if grid_positions[index].x == grid_pos[0] && grid_positions[index].y == grid_pos[1] {
                    tower_entity = arch.entities[index]
                    found = true
                    break
                }
            }
            if found { break }
        }
        if found {
            upgrade_tower(game, tower_entity, grid_pos[0], grid_pos[1])
        }
    }

    if rl.IsKeyPressed(.ONE)   { game.resources.selected_tower_type = .Basic }
    if rl.IsKeyPressed(.TWO)   { game.resources.selected_tower_type = .Frost }
    if rl.IsKeyPressed(.THREE) { game.resources.selected_tower_type = .Cannon }
    if rl.IsKeyPressed(.FOUR)  { game.resources.selected_tower_type = .Sniper }
    if rl.IsKeyPressed(.FIVE)  { game.resources.selected_tower_type = .Poison }

    if rl.IsKeyPressed(.LEFT_BRACKET)  { game.resources.game_speed = max(game.resources.game_speed - 0.5, 0.5) }
    if rl.IsKeyPressed(.RIGHT_BRACKET) { game.resources.game_speed = min(game.resources.game_speed + 0.5, 3.0) }
    if rl.IsKeyPressed(.BACKSLASH)     { game.resources.game_speed = 1.0 }

    if rl.IsKeyPressed(.P) {
        switch game.resources.game_state {
        case .Wave_In_Progress: game.resources.game_state = .Paused
        case .Paused:           game.resources.game_state = .Wave_In_Progress
        case .Waiting_For_Wave, .Game_Over, .Victory:
        }
    }

    if rl.IsKeyPressed(.R) && (game.resources.game_state == .Game_Over || game.resources.game_state == .Victory) {
        restart_game(game)
    }
}

wave_spawning_system :: proc(game: ^Game_World, delta_time: f32) {
    if game.resources.game_state != .Wave_In_Progress {
        return
    }

    game.resources.spawn_timer += delta_time

    current_time := game.resources.spawn_timer
    spawns_to_process := make([dynamic]Enemy_Type, context.temp_allocator)
    indices_to_remove := make([dynamic]int, context.temp_allocator)

    for index in 0 ..< len(game.resources.enemies_to_spawn) {
        spawn_info := game.resources.enemies_to_spawn[index]
        if spawn_info.spawn_time <= current_time {
            append(&spawns_to_process, spawn_info.enemy_type)
            append(&indices_to_remove, index)
        }
    }

    for enemy_type in spawns_to_process {
        spawn_enemy(game, enemy_type)
    }

    #reverse for idx in indices_to_remove {
        ordered_remove(&game.resources.enemies_to_spawn, idx)
    }

    enemy_count := ecs.query_count(&game.world, ENEMY)

    if len(game.resources.enemies_to_spawn) == 0 && enemy_count == 0 {
        ecs.send_event(&game.wave_completed_events, Wave_Completed_Event{wave = game.resources.wave})

        if game.resources.wave >= 20 {
            game.resources.game_state = .Victory
        } else {
            plan_wave(game)
        }
    }
}

enemy_movement_system :: proc(game: ^Game_World, delta_time: f32) {
    path := game.resources.path[:]
    enemies_to_remove := make([dynamic]ecs.Entity, context.temp_allocator)
    hp_damage: u32 = 0

    Enemy_Data :: struct {
        entity:     ecs.Entity,
        pos:        [2]f32,
        enemy_type: Enemy_Type,
    }
    enemy_positions := make([dynamic]Enemy_Data, context.temp_allocator)

    matching := ecs.get_matching_archetypes(&game.world, ENEMY | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        enemies := ecs.column_unchecked(arch, Enemy, ENEMY)
        for index in 0 ..< len(arch.entities) {
            append(&enemy_positions, Enemy_Data{
                entity     = arch.entities[index],
                pos        = {positions[index].x, positions[index].y},
                enemy_type = enemies[index].enemy_type,
            })
        }
    }

    for healer in enemy_positions {
        if healer.enemy_type == .Healer {
            for other in enemy_positions {
                if healer.entity.id != other.entity.id {
                    dx := other.pos[0] - healer.pos[0]
                    dy := other.pos[1] - healer.pos[1]
                    distance := math.sqrt(dx * dx + dy * dy)
                    if distance < 60.0 {
                        enemy := ecs.get(&game.world, other.entity, Enemy)
                        if enemy != nil {
                            enemy.health = min(enemy.health + 10.0 * delta_time, enemy.max_health)
                        }
                    }
                }
            }
        }
    }

    enemy_entities := ecs.query_entities(&game.world, ENEMY | POSITION)
    for entity in enemy_entities {
        enemy := ecs.get(&game.world, entity, Enemy)
        if enemy == nil { continue }

        path_index := enemy.path_index
        path_progress := enemy.path_progress

        speed_multiplier: f32 = 1.0
        if enemy.slow_duration > 0 { speed_multiplier = 0.5 }
        speed := enemy.speed * speed_multiplier

        path_progress += speed * delta_time

        if path_index < len(path) - 1 {
            current := path[path_index]
            next := path[path_index + 1]
            dx := next[0] - current[0]
            dy := next[1] - current[1]
            segment_length := math.sqrt(dx * dx + dy * dy)

            if path_progress >= segment_length {
                path_progress -= segment_length
                path_index += 1

                if path_index >= len(path) - 1 {
                    append(&enemies_to_remove, entity)
                    hp_damage += 1
                    ecs.send_event(&game.enemy_reached_events, Enemy_Reached_End_Event{entity = entity, damage = 1})
                    continue
                }
            }

            current = path[path_index]
            next = path[path_index + 1]
            dir_x := next[0] - current[0]
            dir_y := next[1] - current[1]
            dir_len := math.sqrt(dir_x * dir_x + dir_y * dir_y)
            if dir_len > 0 {
                dir_x /= dir_len
                dir_y /= dir_len
            }
            base_position := [2]f32{current[0] + dir_x * path_progress, current[1] + dir_y * path_progress}

            poison_death := false

            enemy.path_index = path_index
            enemy.path_progress = path_progress

            if enemy.slow_duration > 0 {
                enemy.slow_duration -= delta_time
            }

            if enemy.poison_duration > 0 {
                enemy.poison_duration -= delta_time
                enemy.health -= enemy.poison_damage * delta_time
                if enemy.health <= 0 {
                    poison_death = true
                }
            }

            if poison_death {
                append(&enemies_to_remove, entity)
            } else {
                pos := ecs.get(&game.world, entity, Position)
                if pos != nil {
                    pos.x = base_position[0]
                    pos.y = base_position[1]
                }
            }
        }
    }

    if hp_damage > 0 {
        if game.resources.current_hp >= hp_damage {
            game.resources.current_hp -= hp_damage
        } else {
            game.resources.current_hp = 0
        }

        if game.resources.current_hp == 0 {
            game.resources.current_hp = game.resources.max_hp
            if game.resources.lives > 0 {
                game.resources.lives -= 1
            }
            if game.resources.lives == 0 {
                game.resources.game_state = .Game_Over
            }
        }
    }

    for entity in enemies_to_remove {
        enemy := ecs.get(&game.world, entity, Enemy)
        if enemy != nil {
            game.resources.money += enemy.value
        }
        ecs.queue_despawn(&game.cmd_buffer, entity)
    }

    ecs.apply_commands(&game.cmd_buffer)
}

tower_targeting_system :: proc(game: ^Game_World) {
    Enemy_Target_Data :: struct {
        entity:    ecs.Entity,
        pos:       [2]f32,
        is_flying: bool,
    }
    enemy_data := make([dynamic]Enemy_Target_Data, context.temp_allocator)

    matching := ecs.get_matching_archetypes(&game.world, ENEMY | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        enemies := ecs.column_unchecked(arch, Enemy, ENEMY)
        for index in 0 ..< len(arch.entities) {
            append(&enemy_data, Enemy_Target_Data{
                entity    = arch.entities[index],
                pos       = {positions[index].x, positions[index].y},
                is_flying = enemies[index].is_flying,
            })
        }
    }

    tower_entities := ecs.query_entities(&game.world, TOWER | POSITION)
    for tower_entity in tower_entities {
        tower := ecs.get(&game.world, tower_entity, Tower)
        tower_pos := ecs.get(&game.world, tower_entity, Position)
        if tower == nil || tower_pos == nil { continue }

        range_val := tower_range(tower.tower_type, tower.level)
        range_squared := range_val * range_val

        closest_enemy: ecs.Entity
        closest_distance := max(f32)
        found := false

        for ed in enemy_data {
            dx := ed.pos[0] - tower_pos.x
            dy := ed.pos[1] - tower_pos.y
            distance_squared := dx * dx + dy * dy
            if distance_squared <= range_squared && distance_squared < closest_distance {
                closest_distance = distance_squared
                closest_enemy = ed.entity
                found = true
            }
        }

        tower.target = closest_enemy
        tower.has_target = found
        if found {
            tower.tracking_time += rl.GetFrameTime()
        } else {
            tower.tracking_time = 0
        }
    }
}

tower_shooting_system :: proc(game: ^Game_World, delta_time: f32) {
    Projectile_Spawn :: struct {
        from:       [2]f32,
        target:     ecs.Entity,
        tower_type: Tower_Type,
        level:      u32,
    }
    projectiles_to_spawn := make([dynamic]Projectile_Spawn, context.temp_allocator)

    tower_entities := ecs.query_entities(&game.world, TOWER | POSITION)
    for entity in tower_entities {
        tower := ecs.get(&game.world, entity, Tower)
        tower_pos := ecs.get(&game.world, entity, Position)
        if tower == nil || tower_pos == nil { continue }

        tower.cooldown -= delta_time

        if tower.fire_animation > 0 {
            tower.fire_animation -= delta_time * 3.0
        }

        if tower.cooldown <= 0 && tower.has_target {
            can_fire := true
            if tower.tower_type == .Sniper {
                can_fire = tower.tracking_time >= 2.0
            }

            if can_fire {
                append(&projectiles_to_spawn, Projectile_Spawn{
                    from       = {tower_pos.x, tower_pos.y},
                    target     = tower.target,
                    tower_type = tower.tower_type,
                    level      = tower.level,
                })
                tower.cooldown = tower_fire_rate(tower.tower_type, tower.level)
                tower.fire_animation = 1.0
                tower.tracking_time = 0
            }
        }
    }

    for spawn in projectiles_to_spawn {
        spawn_projectile(game, spawn.from, spawn.target, spawn.tower_type, spawn.level)

        if spawn.tower_type == .Cannon {
            for _ in 0 ..< 6 {
                offset := [2]f32{rand.float32_range(-5, 5), rand.float32_range(-5, 5)}
                spawn_visual_effect(game, {spawn.from[0] + offset[0], spawn.from[1] + offset[1]}, .Explosion, {0, 0}, 0.3)
            }
        }
    }
}

projectile_movement_system :: proc(game: ^Game_World, delta_time: f32) {
    projectiles_to_remove := make([dynamic]ecs.Entity, context.temp_allocator)

    Hit_Info :: struct {
        enemy_entity: ecs.Entity,
        damage:       f32,
        tower_type:   Tower_Type,
        hit_pos:      [2]f32,
    }
    hits := make([dynamic]Hit_Info, context.temp_allocator)

    enemy_positions := make(map[u32][2]f32, context.temp_allocator)
    matching := ecs.get_matching_archetypes(&game.world, ENEMY | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            enemy_positions[arch.entities[index].id] = {positions[index].x, positions[index].y}
        }
    }

    projectile_entities := ecs.query_entities(&game.world, PROJECTILE | POSITION)
    for projectile_entity in projectile_entities {
        proj := ecs.get(&game.world, projectile_entity, Projectile)
        pos := ecs.get(&game.world, projectile_entity, Position)
        if proj == nil || pos == nil { continue }

        old_pos := [2]f32{pos.x, pos.y}

        target_pos, has_target := enemy_positions[proj.target.id]
        if !has_target {
            append(&projectiles_to_remove, projectile_entity)
            continue
        }

        dx := target_pos[0] - proj.start_position[0]
        dy := target_pos[1] - proj.start_position[1]
        total_distance := math.sqrt(dx * dx + dy * dy)

        dx2 := target_pos[0] - old_pos[0]
        dy2 := target_pos[1] - old_pos[1]
        distance_to_target := math.sqrt(dx2 * dx2 + dy2 * dy2)

        new_pos: [2]f32
        if proj.arc_height > 0 {
            if total_distance > 0 {
                proj.flight_progress += (proj.speed * delta_time) / total_distance
            }
            proj.flight_progress = min(proj.flight_progress, 1.0)

            new_pos[0] = proj.start_position[0] + (target_pos[0] - proj.start_position[0]) * proj.flight_progress
            new_pos[1] = proj.start_position[1] + (target_pos[1] - proj.start_position[1]) * proj.flight_progress
        } else {
            dir_len := distance_to_target
            if dir_len > 0 {
                dir_x := dx2 / dir_len
                dir_y := dy2 / dir_len
                new_pos = {old_pos[0] + dir_x * proj.speed * delta_time, old_pos[1] + dir_y * proj.speed * delta_time}
            } else {
                new_pos = old_pos
            }
        }

        if distance_to_target < 10.0 || proj.flight_progress >= 1.0 {
            append(&hits, Hit_Info{
                enemy_entity = proj.target,
                damage       = proj.damage,
                tower_type   = proj.tower_type,
                hit_pos      = target_pos,
            })
            append(&projectiles_to_remove, projectile_entity)
            ecs.send_event(&game.projectile_hit_events, Projectile_Hit_Event{
                projectile = projectile_entity,
                target     = proj.target,
                position   = target_pos,
                damage     = proj.damage,
                tower_type = proj.tower_type,
            })
        } else {
            pos.x = new_pos[0]
            pos.y = new_pos[1]
        }
    }

    for hit in hits {
        switch hit.tower_type {
        case .Frost:
            enemy := ecs.get(&game.world, hit.enemy_entity, Enemy)
            if enemy != nil {
                enemy.slow_duration = 2.0
            }
            apply_damage_to_enemy(game, hit.enemy_entity, hit.damage)
        case .Poison:
            enemy := ecs.get(&game.world, hit.enemy_entity, Enemy)
            if enemy != nil {
                enemy.poison_duration = 3.0
                enemy.poison_damage = 5.0
            }
            apply_damage_to_enemy(game, hit.enemy_entity, hit.damage)
            for _ in 0 ..< 3 {
                velocity := [2]f32{rand.float32_range(-20, 20), rand.float32_range(-20, 20)}
                spawn_visual_effect(game, hit.hit_pos, .Poison_Bubble, velocity, 2.0)
            }
        case .Cannon:
            for _ in 0 ..< 8 {
                velocity := [2]f32{rand.float32_range(-30, 30), rand.float32_range(-30, 30)}
                spawn_visual_effect(game, hit.hit_pos, .Explosion, velocity, 0.5)
            }
            for enemy_id, enemy_pos in enemy_positions {
                dx := enemy_pos[0] - hit.hit_pos[0]
                dy := enemy_pos[1] - hit.hit_pos[1]
                distance := math.sqrt(dx * dx + dy * dy)
                if distance < 60.0 {
                    damage_falloff := 1.0 - (distance / 60.0)
                    apply_damage_to_enemy(game, ecs.Entity{id = enemy_id, generation = 0}, hit.damage * damage_falloff)
                }
            }
        case .Basic, .Sniper:
            apply_damage_to_enemy(game, hit.enemy_entity, hit.damage)
        }
    }

    for entity in projectiles_to_remove {
        ecs.queue_despawn(&game.cmd_buffer, entity)
    }
    ecs.apply_commands(&game.cmd_buffer)
}

apply_damage_to_enemy :: proc(game: ^Game_World, enemy_entity: ecs.Entity, damage: f32) {
    enemy := ecs.get(&game.world, enemy_entity, Enemy)
    if enemy == nil { return }

    was_alive := enemy.health > 0

    if enemy.shield_health > 0 {
        shield_damage := min(damage, enemy.shield_health)
        enemy.shield_health -= shield_damage
        remaining_damage := damage - shield_damage
        if remaining_damage > 0 {
            enemy.health -= remaining_damage
        }
    } else {
        enemy.health -= damage
    }

    if was_alive && enemy.health <= 0 {
        pos := ecs.get(&game.world, enemy_entity, Position)
        death_pos: [2]f32
        if pos != nil {
            death_pos = {pos.x, pos.y}
        }

        ecs.send_event(&game.enemy_died_events, Enemy_Died_Event{
            entity     = enemy_entity,
            position   = death_pos,
            reward     = enemy.value,
            enemy_type = enemy.enemy_type,
        })

        ecs.queue_despawn(&game.cmd_buffer, enemy_entity)
    }
}

visual_effects_system :: proc(game: ^Game_World, delta_time: f32) {
    effects_to_remove := make([dynamic]ecs.Entity, context.temp_allocator)

    matching := ecs.get_matching_archetypes(&game.world, VISUAL_EFFECT | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        effects := ecs.column_unchecked(arch, Visual_Effect, VISUAL_EFFECT)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            effects[index].age += delta_time

            if effects[index].age >= effects[index].lifetime {
                append(&effects_to_remove, arch.entities[index])
            } else {
                positions[index].x += effects[index].velocity[0] * delta_time
                positions[index].y += effects[index].velocity[1] * delta_time
            }
        }
    }

    for entity in effects_to_remove {
        ecs.queue_despawn(&game.cmd_buffer, entity)
    }
    ecs.apply_commands(&game.cmd_buffer)
}

update_money_popups :: proc(game: ^Game_World, delta_time: f32) {
    popups_to_remove := make([dynamic]ecs.Entity, context.temp_allocator)

    matching := ecs.get_matching_archetypes(&game.world, MONEY_POPUP | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        popups := ecs.column_unchecked(arch, Money_Popup, MONEY_POPUP)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            popups[index].lifetime += delta_time

            if popups[index].lifetime > 2.0 {
                append(&popups_to_remove, arch.entities[index])
            } else {
                positions[index].y -= delta_time * 30.0
            }
        }
    }

    for entity in popups_to_remove {
        ecs.queue_despawn(&game.cmd_buffer, entity)
    }
    ecs.apply_commands(&game.cmd_buffer)
}

upgrade_tower :: proc(game: ^Game_World, tower_entity: ecs.Entity, grid_x, grid_y: i32) -> bool {
    tower := ecs.get(&game.world, tower_entity, Tower)
    if tower == nil { return false }

    if tower.level >= 4 { return false }

    upgrade_cost := tower_upgrade_cost(tower.tower_type, tower.level)
    if game.resources.money < upgrade_cost { return false }

    tower_type := tower.tower_type
    old_level := tower.level
    game.resources.money -= upgrade_cost
    tower.level += 1

    ecs.send_event(&game.tower_upgraded_events, Tower_Upgraded_Event{
        entity     = tower_entity,
        tower_type = tower_type,
        old_level  = old_level,
        new_level  = tower.level,
        cost       = upgrade_cost,
    })

    position := grid_to_base(grid_x, grid_y)
    spawn_money_popup(game, position, -i32(upgrade_cost))

    return true
}

sell_tower :: proc(game: ^Game_World, tower_entity: ecs.Entity, grid_x, grid_y: i32) {
    tower := ecs.get(&game.world, tower_entity, Tower)
    if tower == nil { return }

    tower_type := tower.tower_type
    refund := u32(f32(tower_cost(tower_type)) * 0.7)
    game.resources.money += refund

    position := grid_to_base(grid_x, grid_y)
    spawn_money_popup(game, position, i32(refund))

    ecs.send_event(&game.tower_sold_events, Tower_Sold_Event{
        entity     = tower_entity,
        tower_type = tower_type,
        grid_x     = grid_x,
        grid_y     = grid_y,
        refund     = refund,
    })

    matching := ecs.get_matching_archetypes(&game.world, GRID_CELL)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        cells := ecs.column_unchecked(arch, Grid_Cell, GRID_CELL)
        for index in 0 ..< len(arch.entities) {
            if cells[index].x == grid_x && cells[index].y == grid_y {
                cells[index].occupied = false
            }
        }
    }

    range_indicators := ecs.query_entities(&game.world, RANGE_INDICATOR)
    for range_entity in range_indicators {
        indicator := ecs.get(&game.world, range_entity, Range_Indicator)
        if indicator != nil && indicator.tower_entity.id == tower_entity.id {
            ecs.queue_despawn(&game.cmd_buffer, range_entity)
        }
    }

    ecs.queue_despawn(&game.cmd_buffer, tower_entity)
    ecs.apply_commands(&game.cmd_buffer)
}

restart_game :: proc(game: ^Game_World) {
    towers := ecs.query_entities(&game.world, TOWER)
    for entity in towers { ecs.queue_despawn(&game.cmd_buffer, entity) }

    enemies := ecs.query_entities(&game.world, ENEMY)
    for entity in enemies { ecs.queue_despawn(&game.cmd_buffer, entity) }

    projectiles := ecs.query_entities(&game.world, PROJECTILE)
    for entity in projectiles { ecs.queue_despawn(&game.cmd_buffer, entity) }

    effects := ecs.query_entities(&game.world, VISUAL_EFFECT)
    for entity in effects { ecs.queue_despawn(&game.cmd_buffer, entity) }

    popups := ecs.query_entities(&game.world, MONEY_POPUP)
    for entity in popups { ecs.queue_despawn(&game.cmd_buffer, entity) }

    indicators := ecs.query_entities(&game.world, RANGE_INDICATOR)
    for entity in indicators { ecs.queue_despawn(&game.cmd_buffer, entity) }

    ecs.apply_commands(&game.cmd_buffer)

    game.resources.money = 200
    game.resources.lives = 1
    game.resources.wave = 0
    game.resources.current_hp = 20
    game.resources.max_hp = 20
    game.resources.game_state = .Waiting_For_Wave
    game.resources.game_speed = 1.0
    game.resources.spawn_timer = 0
    clear(&game.resources.enemies_to_spawn)
    game.resources.wave_announce_timer = 0
}

enemy_died_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.enemy_died_events) {
        game.resources.money += event.reward

        for _ in 0 ..< 6 {
            velocity := [2]f32{rand.float32_range(-40, 40), rand.float32_range(-40, 40)}
            spawn_visual_effect(game, event.position, .Death_Particle, velocity, 0.8)
        }

        if event.reward > 0 {
            spawn_money_popup(game, event.position, i32(event.reward))
        }
    }
}

enemy_spawned_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.enemy_spawned_events) {
        pos := ecs.get(&game.world, event.entity, Position)
        if pos != nil {
            for _ in 0 ..< 4 {
                velocity := [2]f32{rand.float32_range(-30, 30), rand.float32_range(-30, 30)}
                spawn_visual_effect(game, {pos.x, pos.y}, .Death_Particle, velocity, 0.5)
            }
        }
    }
}

enemy_reached_end_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.enemy_reached_events) {
        pos := ecs.get(&game.world, event.entity, Position)
        if pos != nil {
            for _ in 0 ..< 8 {
                velocity := [2]f32{rand.float32_range(-50, 50), rand.float32_range(-50, 50)}
                spawn_visual_effect(game, {pos.x, pos.y}, .Explosion, velocity, 0.6)
            }
        }
    }
}

projectile_hit_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.projectile_hit_events) {
        for _ in 0 ..< 3 {
            velocity := [2]f32{rand.float32_range(-25, 25), rand.float32_range(-25, 25)}
            spawn_visual_effect(game, event.position, .Explosion, velocity, 0.3)
        }
    }
}

tower_placed_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.tower_placed_events) {
        pos := grid_to_base(event.grid_x, event.grid_y)
        for _ in 0 ..< 5 {
            offset := [2]f32{rand.float32_range(-15, 15), rand.float32_range(-15, 15)}
            spawn_visual_effect(game, {pos[0] + offset[0], pos[1] + offset[1]}, .Explosion, {0, 0}, 0.4)
        }
    }
}

tower_sold_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.tower_sold_events) {
        pos := grid_to_base(event.grid_x, event.grid_y)
        for _ in 0 ..< 8 {
            velocity := [2]f32{rand.float32_range(-40, 40), rand.float32_range(-40, 40)}
            spawn_visual_effect(game, pos, .Death_Particle, velocity, 0.7)
        }
    }
}

tower_upgraded_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.tower_upgraded_events) {
        pos := ecs.get(&game.world, event.entity, Position)
        if pos != nil {
            for _ in 0 ..< 12 {
                angle := rand.float32() * math.PI * 2
                speed := rand.float32_range(20, 60)
                velocity := [2]f32{math.cos(angle) * speed, math.sin(angle) * speed}
                spawn_visual_effect(game, {pos.x, pos.y}, .Explosion, velocity, 0.8)
            }
        }
    }
}

wave_started_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.wave_started_events) {
        game.resources.wave_announce_timer = 2.0
        game.resources.wave = event.wave
    }
}

wave_completed_event_handler :: proc(game: ^Game_World) {
    for event in ecs.read_events(&game.wave_completed_events) {
        bonus := 20 + event.wave * 5
        game.resources.money += bonus
    }
}

render_grid :: proc(game: ^Game_World) {
    scale := get_scale()
    offset := get_offset()

    matching := ecs.get_matching_archetypes(&game.world, GRID_CELL)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        cells := ecs.column_unchecked(arch, Grid_Cell, GRID_CELL)
        for index in 0 ..< len(arch.entities) {
            cell := cells[index]
            base_pos := grid_to_base(cell.x, cell.y)
            pos := [2]f32{offset[0] + base_pos[0] * scale, offset[1] + base_pos[1] * scale}

            path_start := [2]f32{
                offset[0] + game.resources.path[0][0] * scale,
                offset[1] + game.resources.path[0][1] * scale,
            }
            path_end := [2]f32{
                offset[0] + game.resources.path[len(game.resources.path) - 1][0] * scale,
                offset[1] + game.resources.path[len(game.resources.path) - 1][1] * scale,
            }

            dx1 := pos[0] - path_start[0]
            dy1 := pos[1] - path_start[1]
            is_start := math.sqrt(dx1 * dx1 + dy1 * dy1) < TILE_SIZE * scale / 2.0

            dx2 := pos[0] - path_end[0]
            dy2 := pos[1] - path_end[1]
            is_end := math.sqrt(dx2 * dx2 + dy2 * dy2) < TILE_SIZE * scale / 2.0

            color: rl.Color
            if is_start {
                color = rl.ORANGE
            } else if is_end {
                color = rl.BLUE
            } else if cell.is_path {
                color = rl.Color{128, 77, 26, 255}
            } else {
                color = rl.Color{26, 77, 26, 255}
            }

            rl.DrawRectangle(
                i32(pos[0] - TILE_SIZE * scale / 2.0 + scale),
                i32(pos[1] - TILE_SIZE * scale / 2.0 + scale),
                i32((TILE_SIZE - 2.0) * scale),
                i32((TILE_SIZE - 2.0) * scale),
                color,
            )
        }
    }

    if game.resources.has_mouse_grid_pos && can_place_tower_at(game, game.resources.mouse_grid_pos[0], game.resources.mouse_grid_pos[1]) {
        tower_type := game.resources.selected_tower_type
        if game.resources.money >= tower_cost(tower_type) {
            pos := grid_to_screen(game.resources.mouse_grid_pos[0], game.resources.mouse_grid_pos[1])
            tc := tower_color(tower_type)
            rl.DrawRectangle(
                i32(pos[0] - TILE_SIZE * scale / 2.0 + scale),
                i32(pos[1] - TILE_SIZE * scale / 2.0 + scale),
                i32((TILE_SIZE - 2.0) * scale),
                i32((TILE_SIZE - 2.0) * scale),
                rl.Color{tc.r, tc.g, tc.b, 77},
            )
            rl.DrawCircleLines(
                i32(pos[0]),
                i32(pos[1]),
                tower_range(tower_type, 1) * scale,
                rl.Color{tc.r, tc.g, tc.b, 128},
            )
        }
    }
}

render_towers :: proc(game: ^Game_World) {
    scale := get_scale()
    offset := get_offset()

    matching := ecs.get_matching_archetypes(&game.world, TOWER | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        towers := ecs.column_unchecked(arch, Tower, TOWER)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            tower := towers[index]
            pos := positions[index]
            screen_pos := [2]f32{offset[0] + pos.x * scale, offset[1] + pos.y * scale}

            base_size := 20.0 + tower.fire_animation * 4.0
            size := base_size * (1.0 + 0.15 * f32(tower.level - 1)) * scale

            color := tower_color(tower.tower_type)
            level_brightness := 1.0 + 0.2 * f32(tower.level - 1)
            upgraded_color := rl.Color{
                u8(min(f32(color.r) * level_brightness, 255)),
                u8(min(f32(color.g) * level_brightness, 255)),
                u8(min(f32(color.b) * level_brightness, 255)),
                color.a,
            }

            rl.DrawCircle(i32(screen_pos[0]), i32(screen_pos[1]), size / 2.0, upgraded_color)
            rl.DrawCircleLines(i32(screen_pos[0]), i32(screen_pos[1]), size / 2.0, rl.BLACK)

            for ring in 1 ..< tower.level {
                ring_radius := size / 2.0 + f32(ring) * 3.0 * scale
                rl.DrawCircleLines(i32(screen_pos[0]), i32(screen_pos[1]), ring_radius, upgraded_color)
            }

            if tower.tower_type == .Sniper && tower.has_target {
                target_pos := ecs.get(&game.world, tower.target, Position)
                if target_pos != nil {
                    target_screen := [2]f32{offset[0] + target_pos.x * scale, offset[1] + target_pos.y * scale}
                    rl.DrawLine(i32(screen_pos[0]), i32(screen_pos[1]), i32(target_screen[0]), i32(target_screen[1]), rl.RED)
                }
            }
        }
    }

    if game.resources.has_mouse_grid_pos {
        grid_x := game.resources.mouse_grid_pos[0]
        grid_y := game.resources.mouse_grid_pos[1]

        matching = ecs.get_matching_archetypes(&game.world, TOWER | GRID_POSITION | POSITION)
        for arch_idx in matching {
            arch := &game.world.archetypes[arch_idx]
            towers := ecs.column_unchecked(arch, Tower, TOWER)
            grid_positions := ecs.column_unchecked(arch, Grid_Position, GRID_POSITION)
            positions := ecs.column_unchecked(arch, Position, POSITION)
            for index in 0 ..< len(arch.entities) {
                if grid_positions[index].x == grid_x && grid_positions[index].y == grid_y {
                    tower := towers[index]
                    pos := positions[index]
                    screen_pos := [2]f32{offset[0] + pos.x * scale, offset[1] + pos.y * scale}

                    range_val := tower_range(tower.tower_type, tower.level)
                    rl.DrawCircleLines(i32(screen_pos[0]), i32(screen_pos[1]), range_val * scale, tower_color(tower.tower_type))

                    if tower.level < 4 {
                        upgrade_cost := tower_upgrade_cost(tower.tower_type, tower.level)
                        text := fmt.ctprintf("U: Upgrade ($%d) Lv%d", upgrade_cost, tower.level)
                        text_color := game.resources.money >= upgrade_cost ? rl.GREEN : rl.RED
                        rl.DrawText(text, i32(screen_pos[0] - 60 * scale), i32(screen_pos[1] - 35 * scale), i32(20 * scale), text_color)
                    } else {
                        rl.DrawText("MAX LEVEL", i32(screen_pos[0] - 40 * scale), i32(screen_pos[1] - 35 * scale), i32(20 * scale), rl.GOLD)
                    }

                    if tower.has_target {
                        target_pos := ecs.get(&game.world, tower.target, Position)
                        if target_pos != nil {
                            target_screen := [2]f32{offset[0] + target_pos.x * scale, offset[1] + target_pos.y * scale}
                            rl.DrawLine(i32(screen_pos[0]), i32(screen_pos[1]), i32(target_screen[0]), i32(target_screen[1]), rl.RED)
                        }
                    }
                }
            }
        }
    }
}

render_enemies :: proc(game: ^Game_World) {
    scale := get_scale()
    offset := get_offset()

    matching := ecs.get_matching_archetypes(&game.world, ENEMY | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        enemies := ecs.column_unchecked(arch, Enemy, ENEMY)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            enemy := enemies[index]
            pos := positions[index]
            screen_pos := [2]f32{offset[0] + pos.x * scale, offset[1] + pos.y * scale}
            size := enemy_size(enemy.enemy_type) * scale

            rl.DrawCircle(i32(screen_pos[0]), i32(screen_pos[1]), size, enemy_color(enemy.enemy_type))
            rl.DrawCircleLines(i32(screen_pos[0]), i32(screen_pos[1]), size, rl.BLACK)

            if enemy.shield_health > 0 {
                shield_alpha := u8(enemy.shield_health / enemy.max_shield * 255)
                rl.DrawCircleLines(i32(screen_pos[0]), i32(screen_pos[1]), size + 3 * scale, rl.Color{128, 128, 255, shield_alpha})
            }

            health_percent := enemy.health / enemy.max_health
            bar_width := size * 2
            bar_height := 4 * scale
            bar_y := screen_pos[1] - size - 10 * scale

            rl.DrawRectangle(i32(screen_pos[0] - bar_width / 2), i32(bar_y), i32(bar_width), i32(bar_height), rl.BLACK)

            health_color: rl.Color
            if health_percent > 0.5 {
                health_color = rl.GREEN
            } else if health_percent > 0.25 {
                health_color = rl.YELLOW
            } else {
                health_color = rl.RED
            }

            rl.DrawRectangle(i32(screen_pos[0] - bar_width / 2), i32(bar_y), i32(bar_width * health_percent), i32(bar_height), health_color)
        }
    }
}

render_projectiles :: proc(game: ^Game_World) {
    scale := get_scale()
    offset := get_offset()

    matching := ecs.get_matching_archetypes(&game.world, PROJECTILE | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        projectiles := ecs.column_unchecked(arch, Projectile, PROJECTILE)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            proj := projectiles[index]
            pos := positions[index]
            screen_pos := [2]f32{offset[0] + pos.x * scale, offset[1] + pos.y * scale}

            color: rl.Color
            switch proj.tower_type {
            case .Basic:  color = rl.YELLOW
            case .Frost:  color = rl.SKYBLUE
            case .Cannon: color = rl.ORANGE
            case .Sniper: color = rl.LIGHTGRAY
            case .Poison: color = rl.Color{128, 0, 204, 255}
            }

            size: f32
            switch proj.tower_type {
            case .Cannon: size = 8.0
            case .Sniper: size = 10.0
            case .Basic, .Frost, .Poison: size = 5.0
            }

            rl.DrawCircle(i32(screen_pos[0]), i32(screen_pos[1]), size * scale, color)
        }
    }
}

render_visual_effects :: proc(game: ^Game_World) {
    scale := get_scale()
    offset := get_offset()

    matching := ecs.get_matching_archetypes(&game.world, VISUAL_EFFECT | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        effects := ecs.column_unchecked(arch, Visual_Effect, VISUAL_EFFECT)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            effect := effects[index]
            pos := positions[index]
            screen_pos := [2]f32{offset[0] + pos.x * scale, offset[1] + pos.y * scale}
            progress := effect.age / effect.lifetime
            alpha := u8((1.0 - progress) * 255)

            switch effect.effect_type {
            case .Explosion:
                size := (1.0 - progress) * 10.0 * scale
                rl.DrawCircle(i32(screen_pos[0]), i32(screen_pos[1]), size, rl.Color{255, 128, 0, alpha})
            case .Poison_Bubble:
                size := 5.0 * (1.0 + progress * 0.5) * scale
                rl.DrawCircle(i32(screen_pos[0]), i32(screen_pos[1]), size, rl.Color{128, 0, 204, u8(f32(alpha) * 0.6)})
            case .Death_Particle:
                size := (1.0 - progress) * 5.0 * scale
                rl.DrawCircle(i32(screen_pos[0]), i32(screen_pos[1]), size, rl.Color{255, 0, 0, alpha})
            }
        }
    }
}

render_money_popups :: proc(game: ^Game_World) {
    scale := get_scale()
    offset := get_offset()

    matching := ecs.get_matching_archetypes(&game.world, MONEY_POPUP | POSITION)
    for arch_idx in matching {
        arch := &game.world.archetypes[arch_idx]
        popups := ecs.column_unchecked(arch, Money_Popup, MONEY_POPUP)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        for index in 0 ..< len(arch.entities) {
            popup := popups[index]
            pos := positions[index]
            screen_pos := [2]f32{offset[0] + pos.x * scale, offset[1] + pos.y * scale}
            progress := popup.lifetime / 2.0
            alpha := u8((1.0 - min(progress, 1.0)) * 255)

            text: cstring
            color: rl.Color
            if popup.amount > 0 {
                text = fmt.ctprintf("+$%d", popup.amount)
                color = rl.Color{0, 255, 0, alpha}
            } else {
                text = fmt.ctprintf("-$%d", -popup.amount)
                color = rl.Color{255, 0, 0, alpha}
            }

            text_scale := 1.0 + progress * 0.5
            rl.DrawText(text, i32(screen_pos[0] - 20 * scale), i32(screen_pos[1]), i32(20 * scale * text_scale), color)
        }
    }
}

render_ui :: proc(game: ^Game_World) {
    screen_w := f32(rl.GetScreenWidth())
    screen_h := f32(rl.GetScreenHeight())

    money_text := fmt.ctprintf("Money: $%d", game.resources.money)
    rl.DrawText(money_text, 10, 30, 30, rl.GREEN)

    lives_text := fmt.ctprintf("Lives: %d", game.resources.lives)
    rl.DrawText(lives_text, 10, 60, 25, rl.RED)

    hp_text := fmt.ctprintf("HP: %d/%d", game.resources.current_hp, game.resources.max_hp)
    rl.DrawText(hp_text, 10, 90, 25, rl.YELLOW)

    wave_text := fmt.ctprintf("Wave: %d", game.resources.wave)
    rl.DrawText(wave_text, i32(screen_w) - 150, 30, 30, rl.SKYBLUE)

    speed_text := fmt.ctprintf("Speed: %.1fx", game.resources.game_speed)
    rl.DrawText(speed_text, i32(screen_w) - 150, 60, 20, rl.WHITE)

    total_hp := (game.resources.lives - 1) * game.resources.max_hp + game.resources.current_hp
    max_total_hp := game.resources.lives * game.resources.max_hp
    health_percentage := f32(total_hp) / f32(max_total_hp) if max_total_hp > 0 else 0

    bar_width: f32 = 200
    bar_height: f32 = 20
    bar_x: f32 = 10
    bar_y: f32 = 100

    rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(bar_width), i32(bar_height), rl.BLACK)

    health_color: rl.Color
    if health_percentage > 0.5 {
        health_color = rl.GREEN
    } else if health_percentage > 0.25 {
        health_color = rl.YELLOW
    } else {
        health_color = rl.RED
    }

    rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(bar_width * health_percentage), i32(bar_height), health_color)

    tower_ui_y: f32 = 140
    tower_types := [?]struct {
        tower_type: Tower_Type,
        key:        cstring,
    }{
        {.Basic, "1"},
        {.Frost, "2"},
        {.Cannon, "3"},
        {.Sniper, "4"},
        {.Poison, "5"},
    }

    for tt, idx in tower_types {
        x := 10 + f32(idx) * 60
        is_selected := game.resources.selected_tower_type == tt.tower_type
        can_afford := game.resources.money >= tower_cost(tt.tower_type)

        tc := tower_color(tt.tower_type)
        color: rl.Color
        if is_selected {
            color = tc
        } else if can_afford {
            color = rl.Color{u8(f32(tc.r) * 0.7), u8(f32(tc.g) * 0.7), u8(f32(tc.b) * 0.7), 255}
        } else {
            color = rl.DARKGRAY
        }

        rl.DrawRectangle(i32(x), i32(tower_ui_y), 50, 50, color)
        rl.DrawRectangleLines(i32(x), i32(tower_ui_y), 50, 50, rl.BLACK)

        rl.DrawText(tt.key, i32(x + 5), i32(tower_ui_y + 5), 20, rl.BLACK)
        cost_text := fmt.ctprintf("$%d", tower_cost(tt.tower_type))
        rl.DrawText(cost_text, i32(x + 5), i32(tower_ui_y + 30), 15, rl.BLACK)
    }

    if game.resources.wave_announce_timer > 0 {
        alpha := u8(min(game.resources.wave_announce_timer, 1.0) * 255)
        text := fmt.ctprintf("WAVE %d", game.resources.wave)
        text_width := rl.MeasureText(text, 60)
        rl.DrawText(text, i32(screen_w / 2) - text_width / 2, i32(screen_h / 2 - 100), 60, rl.Color{255, 204, 0, alpha})
    }

    switch game.resources.game_state {
    case .Waiting_For_Wave:
        text: cstring = "Press SPACE to start wave"
        text_width := rl.MeasureText(text, 40)
        rl.DrawText(text, i32(screen_w / 2) - text_width / 2, i32(screen_h / 2), 40, rl.WHITE)
    case .Paused:
        text: cstring = "PAUSED - Press P to resume"
        text_width := rl.MeasureText(text, 50)
        rl.DrawText(text, i32(screen_w / 2) - text_width / 2, i32(screen_h / 2), 50, rl.YELLOW)
    case .Game_Over:
        text: cstring = "GAME OVER - Press R to restart"
        text_width := rl.MeasureText(text, 50)
        rl.DrawText(text, i32(screen_w / 2) - text_width / 2, i32(screen_h / 2), 50, rl.RED)
    case .Victory:
        text: cstring = "VICTORY! Press R to restart"
        text_width := rl.MeasureText(text, 50)
        rl.DrawText(text, i32(screen_w / 2) - text_width / 2, i32(screen_h / 2), 50, rl.GREEN)
    case .Wave_In_Progress:
    }

    controls: cstring = "Controls: 1-5: Tower | LClick: Place | RClick: Sell | U: Upgrade | [/]: Speed | P: Pause | R: Restart"
    rl.DrawText(controls, 10, i32(screen_h) - 25, 15, rl.LIGHTGRAY)
}

main :: proc() {
    rl.InitWindow(1024, 768, "Tower Defense - Odin ECS")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    game := create_game_world()
    defer destroy_game_world(&game)

    POSITION = ecs.register(&game.world, Position)
    VELOCITY = ecs.register(&game.world, Velocity)
    TOWER = ecs.register(&game.world, Tower)
    ENEMY = ecs.register(&game.world, Enemy)
    PROJECTILE = ecs.register(&game.world, Projectile)
    GRID_CELL = ecs.register(&game.world, Grid_Cell)
    GRID_POSITION = ecs.register(&game.world, Grid_Position)
    HEALTH_BAR = ecs.register(&game.world, Health_Bar)
    VISUAL_EFFECT = ecs.register(&game.world, Visual_Effect)
    RANGE_INDICATOR = ecs.register(&game.world, Range_Indicator)
    MONEY_POPUP = ecs.register(&game.world, Money_Popup)

    TAG_BASIC_ENEMY = ecs.register_tag(&game.tags, "basic_enemy")
    TAG_TANK_ENEMY = ecs.register_tag(&game.tags, "tank_enemy")
    TAG_FAST_ENEMY = ecs.register_tag(&game.tags, "fast_enemy")
    TAG_FLYING_ENEMY = ecs.register_tag(&game.tags, "flying_enemy")
    TAG_HEALER_ENEMY = ecs.register_tag(&game.tags, "healer_enemy")
    TAG_BASIC_TOWER = ecs.register_tag(&game.tags, "basic_tower")
    TAG_FROST_TOWER = ecs.register_tag(&game.tags, "frost_tower")
    TAG_CANNON_TOWER = ecs.register_tag(&game.tags, "cannon_tower")
    TAG_SNIPER_TOWER = ecs.register_tag(&game.tags, "sniper_tower")
    TAG_POISON_TOWER = ecs.register_tag(&game.tags, "poison_tower")
    TAG_PATH_CELL = ecs.register_tag(&game.tags, "path_cell")

    game.resources.money = 200
    game.resources.lives = 1
    game.resources.wave = 0
    game.resources.current_hp = 20
    game.resources.max_hp = 20
    game.resources.game_state = .Waiting_For_Wave
    game.resources.game_speed = 1.0
    game.resources.selected_tower_type = .Basic

    initialize_grid(&game)
    create_path(&game)

    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime() * game.resources.game_speed

        input_system(&game)

        if game.resources.game_state != .Paused {
            wave_spawning_system(&game, dt)
            enemy_movement_system(&game, dt)
            tower_targeting_system(&game)
            tower_shooting_system(&game, dt)
            projectile_movement_system(&game, dt)
            visual_effects_system(&game, dt)
            update_money_popups(&game, dt)

            enemy_died_event_handler(&game)
            enemy_spawned_event_handler(&game)
            enemy_reached_end_event_handler(&game)
            projectile_hit_event_handler(&game)
            tower_placed_event_handler(&game)
            tower_sold_event_handler(&game)
            tower_upgraded_event_handler(&game)
            wave_started_event_handler(&game)
            wave_completed_event_handler(&game)
        }

        if game.resources.wave_announce_timer > 0 {
            game.resources.wave_announce_timer -= rl.GetFrameTime()
        }

        if rl.IsKeyPressed(.SPACE) && game.resources.game_state == .Waiting_For_Wave {
            plan_wave(&game)
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{13, 13, 13, 255})

        render_grid(&game)
        render_towers(&game)
        render_enemies(&game)
        render_projectiles(&game)
        render_visual_effects(&game)
        render_money_popups(&game)
        render_ui(&game)

        rl.EndDrawing()

        step_events(&game)
        free_all(context.temp_allocator)
    }
}
