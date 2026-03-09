# PIT - 🚗 Cops n Wanted 🚓

An open-source project dedicated to bringing fair, balanced, and cinematic multiplayer police chase gameplay to BeamMP

## Preview

[![PIT Economy System - Gameplay Preview](https://img.youtube.com/vi/eaFKSADzcw8/maxresdefault.jpg)](https://www.youtube.com/watch?v=eaFKSADzcw8)

## Features

- **Police / Civilian roles** — detected automatically by vehicle skin
- **Wanted system** — speeding and zigzag violations, bust mechanic, escape system
- **Economy** — per-second income during chases, markers, money transfers
- **Rank progression** — 5 ranks with task-based advancement for both roles
- **Repair system** — limited repairs earned through gameplay
- **Parts shop** — parts purchase system with free/banned vehicle series enforcement
- **Minimap** — real-time wanted/police tracking
- **Air Polluter** — hidden special mission with fog effects
- **Multi-language** — English, Arabic, French, German, Hebrew, Italian, Russian, Spanish
- **Performance limiter** — server-enforced vehicle rating cap with admin commands and optional community voting
- **Day/Night sync** *(optional)* — server-controlled time cycle, requires a map with night lighting support
- **Multi-map** — West Coast USA, East Coast USA *(expandable to any map)*

## Structure

Each mod consists of a server-side component and a client-side package. The client Lua extensions handle game logic and server communication; UI apps (HTML/JS/CSS) are only present where a visual interface is needed.

| Mod | Server folder | Client package |
|-----|--------------|----------------|
| Economy / Wanted System / Parts Shop | `EconomyTest/` | `UIMPIT.zip` |
| Performance Limiter | `PerformanceLimiter/` | `UIMPI.zip` |
| Day/Night Sync *(optional)* | `DayNightSync/` | `MPDN.zip` |

## File Structure

<details>
<summary>Click to expand</summary>
<pre>
Resources/
├── Client/
│   ├── UIMPIT.zip                          # Economy / Wanted System / Parts Shop
│   │   ├── lua/ge/extensions/
│   │   │   ├── key.lua                     # Core client logic & UI data bridge
│   │   │   ├── minimap.lua                 # Minimap logic & rendering
│   │   │   └── PartsShop.lua               # Parts Shop client logic
│   │   ├── scripts/
│   │   │   ├── EconomyUI/modScript.lua
│   │   │   └── PartsShop/modScript.lua
│   │   ├── settings/ui_apps/layouts/default/pit.uilayout.json
│   │   └── ui/modules/apps/
│   │       ├── BeamMP-PlayerList/
│   │       │   ├── app.html
│   │       │   ├── app.js
│   │       │   ├── app.css
│   │       │   ├── app.json
│   │       │   ├── app.png
│   │       │   └── redesign.css
│   │       ├── EconomyHUD/
│   │       │   ├── app.html
│   │       │   ├── app.js
│   │       │   ├── app.css
│   │       │   ├── app.json
│   │       │   └── app.png
│   │       ├── PoliceWantedList/
│   │       │   ├── app.html
│   │       │   ├── app.js
│   │       │   ├── app.css
│   │       │   ├── app.json
│   │       │   └── app.png
│   │       └── PartsShop/
│   │           ├── app.html
│   │           ├── app.js
│   │           ├── app.css
│   │           ├── app.json
│   │           └── app.png
│   │
│   ├── UIMPI.zip                           # Performance Limiter
│   │   ├── lua/ge/extensions/performanceLimiter.lua
│   │   ├── scripts/perf-ui/modScript.lua
│   │   └── ui/modules/apps/perf/
│   │       ├── app.html
│   │       ├── app.js
│   │       ├── app.css
│   │       ├── app.json
│   │       └── app.png
│   │
│   └── MPDN.zip                            # Day/Night Sync (optional)
│       ├── lua/ge/extensions/mpdn.lua
│       └── scripts/envsync/modScript.lua
│
└── Server/
    ├── EconomyTest/                        # Economy, Wanted System, Parts Shop
    │   ├── main.lua
    │   ├── database.lua
    │   ├── AirPolluter.lua
    │   ├── MinimapSystem.lua
    │   ├── PartsShop.lua
    │   ├── SpawnLocations.lua
    │   ├── PoliceSkins.lua
    │   ├── RanksConfig.lua
    │   ├── parts_config.lua
    │   ├── free_vehicles.lua
    │   ├── banned_vehicle_series.lua
    │   ├── schema.sql
    │   ├── config.json
    │   ├── db.json                         # ⚠️ Never commit
    │   └── lang/{ar,de,en,es,fr,he,it,ru}.json
    │
    ├── PerformanceLimiter/
    │   ├── main.lua
    │   └── config.json
    │
    └── DayNightSync/                       # Day/Night Sync (optional)
        └── main.lua
</pre>
</details>

## Requirements

- [BeamMP Server](https://github.com/BeamMP/BeamMP-Server)
- MySQL / MariaDB + `luasql.mysql` Lua library *(optional — falls back to local JSON storage)*

## Installation

1. Copy the `EconomyTest` and `PerformanceLimiter` folders to `Resources/Server/`
2. Copy `UIMPIT.zip` and `UIMPI.zip` to `Resources/Client/`
3. Run the SQL schema to create the required tables (see `schema.sql`)
4. Edit `EconomyTest/config.json` — set your `admins` and `moderators`
5. Edit `PerformanceLimiter/config.json` — set your `admins` and desired rating limit
6. Start your BeamMP server

> **MySQL setup (optional):** Fill in your database credentials in `db.json` inside `EconomyTest/`. Without this file the server will automatically use local JSON storage instead.

> **Day/Night Sync** (`DayNightSync` + `MPDN.zip`) is optional — only install it if your map supports night lighting. On maps without it, the night cycle will appear completely dark.

## Configuration

### EconomyTest

| File | Purpose |
|------|---------|
| `config.json` | Gameplay settings, timers, admins |
| `db.json` | MySQL credentials **(never commit this file)** |
| `SpawnLocations.lua` | Spawn points and marker locations per map |
| `PoliceSkins.lua` | Vehicle skins that grant the police role |
| `RanksConfig.lua` | Rank names, task targets, and rewards |
| `parts_config.lua` | All parts with their prices (`0` = free, `>0` = purchasable, `-1` = banned) |
| `free_vehicles.lua` | Vehicle series that bypass the purchase system |
| `banned_vehicle_series.lua` | Vehicle series that are completely prohibited |

### PerformanceLimiter

| File | Purpose |
|------|---------|
| `config.json` | Rating cap, display offset, admins, vote settings |

### DayNightSync

| File | Purpose |
|------|---------|
| `main.lua` | Cycle speed, sync interval, initial time preset |

## Storage Backends

| Backend | When active | Use case |
|---------|------------|----------|
| MySQL | `db.json` present and reachable | Multiple servers sharing one economy |
| JSON | `db.json` absent or unreachable | Single-server or offline setup |

The backend is selected automatically at startup with no code changes required.

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

## Community
Have questions about the mods or want to play on the server? [Join the Discord](https://discord.gg/HVKcvAJYpZ)

## Credits

- **Beams of Norway** — speed detection code reference
- **[OfficialLambdax](https://github.com/OfficialLambdax)** — day/night sync implementation (learned from published code)
- **[StanleyDudek](https://github.com/StanleyDudek)** — extensive help and published code examples that shaped much of this project

## License

[AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html)
