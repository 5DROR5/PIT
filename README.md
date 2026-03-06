# PIT Economy System

A BeamMP server mod for police chase roleplay — wanted system, economy, ranks, missions, a parts shop, and a performance limiter.

## Features

- **Police / Civilian roles** — detected automatically by vehicle skin
- **Wanted system** — speeding and zigzag violations, bust mechanic, escape system
- **Economy** — per-second income during chases, markers, money transfers
- **Rank progression** — 5 ranks with task-based advancement for both roles
- **Repair system** — limited repairs earned through gameplay
- **Parts shop** — parts purchase system with free/banned vehicle series enforcement
- **Minimap** — real-time wanted/police tracking
- **Air Polluter** — hidden special mission with fog effects
- **Multi-language** — Hebrew, English, Arabic, German, Italian, French, Spanish, Russian
- **Performance limiter** — server-enforced vehicle rating cap with admin commands and optional community voting
- **Multi-map** — West Coast USA, East Coast USA, Small Grid

## Requirements

- [BeamMP Server](https://github.com/BeamMP/BeamMP-Server)
- MySQL / MariaDB
- `luasql.mysql` Lua library

## Installation

1. Copy the `EconomyTest` folder to `Resources/Server/`
2. Copy the `PartsShop` folder to `Resources/Server/`
3. Copy the `PerformanceLimiter` folder to `Resources/Server/`
4. In both `EconomyTest/` and `PartsShop/`, copy `db.example.json` → `db.json` and fill in your database credentials
5. Run the SQL schema to create the required tables (see `schema.sql`)
6. Edit `EconomyTest/config.json` — set your `admins` and `moderators`
7. Edit `PerformanceLimiter/config.json` — set your `admins` and desired rating limit
8. Start your BeamMP server

## Configuration

### EconomyTest

| File | Purpose |
|------|---------|
| `config.json` | Gameplay settings, timers, admins |
| `db.json` | Database credentials **(never commit this file)** |
| `SpawnLocations.lua` | Spawn points and marker locations per map |
| `PoliceSkins.lua` | Vehicle skins that grant the police role |
| `RanksConfig.lua` | Rank names, task targets, and rewards |

### PerformanceLimiter

| File | Purpose |
|------|---------|
| `config.json` | Rating cap, display offset, admins, vote settings |

### PartsShop

| File | Purpose |
|------|---------|
| `db.json` | Database credentials **(never commit this file)** |
| `parts_config.lua` | All parts with their prices (`0` = free, `>0` = purchasable, `-1` = banned) |
| `free_vehicles.lua` | Vehicle series that bypass the purchase system |
| `banned_vehicle_series.lua` | Vehicle series that are completely prohibited |

## Adding a Map

In `SpawnLocations.lua`, add an entry with the exact BeamNG map folder name:

```lua
["your_map_name"] = {
    vehicles = { ... },
    markers = { ... },
    optional_spawns = { ... },
    air_polluter_marker = { x = 0, y = 0, z = 0 },
}
```

## License

[AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html)
