# freECS-Odin

A high-performance, archetype-based Entity Component System (ECS) for Odin

**Key Features**:

- Archetype-based storage with bitmask queries
- Generational entity handles (prevents ABA problem)
- Contiguous component storage for cache-friendly iteration
- O(1) bit indexing via `count_trailing_zeros` intrinsic
- Query caching for repeated iteration patterns
- `column_unchecked` for zero-overhead inner loops
- Batch spawning with pre-allocated capacity
- Simple, data-oriented API

This is an Odin port of [freecs](https://github.com/matthewjberger/freecs), a Rust ECS library.

## Quick Start

Copy `freecs.odin` into your project or import it as a package:

```odin
package main

import ecs "freecs-odin"
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

    // Register component types (returns bitmask for queries)
    POSITION := ecs.register(&world, Position)
    VELOCITY := ecs.register(&world, Velocity)

    // Spawn entities with components
    entity := ecs.spawn(&world, Position{1, 2}, Velocity{3, 4})

    // Get components
    if pos := ecs.get(&world, entity, Position); pos != nil {
        fmt.println("Position:", pos^)
    }

    // Set components
    ecs.set(&world, entity, Position{10, 20})

    // Check if entity has a component
    if ecs.has(&world, entity, Position) {
        fmt.println("Entity has position")
    }

    // Despawn entities
    ecs.despawn(&world, entity)
}
```

## Systems

Systems iterate over archetypes and process entities with matching components:

```odin
update_positions :: proc(world: ^ecs.World, dt: f32) {
    for &arch in world.archetypes {
        // Skip archetypes that don't have required components
        if arch.mask & (POSITION | VELOCITY) != (POSITION | VELOCITY) {
            continue
        }

        // Get typed slices - pass bit for O(1) lookup (fast path)
        positions := ecs.column(&arch, Position, POSITION)
        velocities := ecs.column(&arch, Velocity, VELOCITY)
        if positions == nil || velocities == nil { continue }

        // Process all entities in this archetype
        for i in 0..<len(arch.entities) {
            positions[i].x += velocities[i].x * dt
            positions[i].y += velocities[i].y * dt
        }
    }
}
```

### Column Access

Two overloads are available:

```odin
// Fast path - O(1) via bit index array lookup
positions := ecs.column(&arch, Position, POSITION)

// Convenience path - O(n) linear scan by typeid
positions := ecs.column(&arch, Position)
```

Use the bit-based version in performance-critical code.

### Batch Spawning

Spawn many entities efficiently with pre-allocated capacity:

```odin
// Spawns 1000 entities with same components
entities := ecs.spawn_batch(&world, 1000, Position{0, 0}, Velocity{1, 1})
```

### High-Performance Iteration

For maximum performance, use cached queries and unchecked column access:

```odin
update_positions :: proc(world: ^ecs.World, dt: f32) {
    move_mask := POSITION | VELOCITY

    // Cached query - archetypes matching this mask are remembered
    matching := ecs.get_matching_archetypes(world, move_mask)

    for arch_idx in matching {
        arch := &world.archetypes[arch_idx]

        // Zero-overhead column access (no nil checks, no bounds checks)
        positions := ecs.column_unchecked(arch, Position, POSITION)
        velocities := ecs.column_unchecked(arch, Velocity, VELOCITY)
        count := len(arch.entities)

        // Unchecked inner loop for SIMD-friendly iteration
        #no_bounds_check for i in 0..<count {
            positions[i].x += velocities[i].x * dt
            positions[i].y += velocities[i].y * dt
        }
    }
}
```

## API Reference

### World Management

```odin
world := ecs.create_world()      // Create a new world
ecs.destroy_world(&world)        // Clean up world resources
count := ecs.entity_count(&world) // Get total entity count
```

### Component Registration

```odin
// Register returns a bitmask for the component type
POSITION := ecs.register(&world, Position)
VELOCITY := ecs.register(&world, Velocity)

// Use masks for queries
MOVABLE := POSITION | VELOCITY
```

### Entity Operations

```odin
// Spawn with any number of components
entity := ecs.spawn(&world, Position{0, 0}, Velocity{1, 1})

// Check if entity is alive
if ecs.is_alive(&world, entity) { ... }

// Despawn entity (slot reused with new generation)
ecs.despawn(&world, entity)
```

### Component Access

```odin
// Get component (returns nil if not present)
pos := ecs.get(&world, entity, Position)

// Set component value
ecs.set(&world, entity, Position{10, 20})

// Check if entity has component
if ecs.has(&world, entity, Position) { ... }
```

### Archetype Iteration

```odin
for &arch in world.archetypes {
    // Check component mask
    if arch.mask & REQUIRED_MASK != REQUIRED_MASK {
        continue
    }

    // Get typed component slices
    positions := ecs.column(&arch, Position)
    velocities := ecs.column(&arch, Velocity)

    // Iterate entities
    for i in 0..<len(arch.entities) {
        pos := positions[i]
        vel := velocities[i]
        // ...
    }
}
```

## Example: Boids Simulation

See `examples/boids.odin` for a complete boids flocking simulation using raylib:

```
just run
```

Controls:
- **Space**: Pause/unpause
- **+/-**: Add/remove 1000 boids
- **Arrow keys**: Adjust alignment/cohesion weights
- **Left mouse**: Attract boids
- **Right mouse**: Repel boids

## Running Tests

```
just test
```

All 13 tests verify:
- Entity spawn/despawn
- Component get/set/has
- Generational indices
- Archetype management
- Query iteration

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.
