# Generator System Design — Task 44

## Overview
Composable generator framework for dynamic world expansion. Individual generators produce data objects; the caller handles persistence and cache warming. Admin API endpoints expose each generator independently plus a chained "full sector" endpoint.

**Hard constraint:** DO NOT add new resources or components. Use existing item indices and names only. Use `Translator.NameOrator()` for procedural naming.

## RGBA Personality System

The existing sector `rgba` field (short[4]) drives generation weights:

| Channel | Meaning | Range 0-255 | Effect |
|---------|---------|-------------|--------|
| R (Red) | Danger | 0=safe, 255=hostile | More mines, hostile NPCs, salvage |
| G (Green) | Resources | 0=barren, 255=rich | More resource nodes, higher purity |
| B (Blue) | Commerce | 0=remote, 255=trade hub | More stations, merchants, higher grades |
| A (Alpha) | Density | 0=sparse, 255=packed | Multiplier on total location count |

### Central Station Rule
A station at 0,0 is placed only if `B >= 50`. Frontier/empty sectors with low B get no central station — just scattered POIs or nothing.

### Sector Profiles

| Profile | R | G | B | A | Character |
|---------|---|---|---|---|-----------|
| Settled mining (Sector0) | 20 | 180 | 120 | 180 | Rich mining, moderate trade, safe, dense |
| Mining colony | 40 | 220 | 80 | 150 | Heavy resources, some stations, low danger |
| Frontier | 180 | 60 | 20 | 80 | Dangerous, sparse, no central station |
| Empty | 30 | 10 | 5 | 20 | Nearly nothing — a few beacons or mines |

## Generators

### 1. SectorGenerator
**Input:** `SectorGenConfig` — neighbor sector ID to connect to, optional RGBA override, seed
**Output:** `SectorGenResult` — Language + Describable + FleetSector + neighbor slot assignments

- New sectors need only 1 neighbor connection to the existing map
- RGBA defaults: derived from neighbor's RGBA with random variance if not specified
- Picks an empty neighbor slot (01-08) on the existing sector, sets bidirectional links
- Produces the full Language → Describable → FleetSector chain

### 2. LocationGenerator
**Input:** `LocationGenConfig` — sector ID, sector RGBA, existing locations (for Sector0 compatibility), count override, seed
**Output:** `LocationGenResult` — list of `SeedLocationEntry` (existing GameFactory type)

- Uses `FractalPlacer` for positions (cellSize=200, minDistance=150, sectorRadius=2000)
- Skips grid slots already occupied by existing locations
- RGBA drives LocType distribution:
  - B >= 50: place Station at 0,0 (central station)
  - G weight → ResourceNode count (Ore/H2/Ice/He3 sub-distributed)
  - R weight → Mine + Beacon count
  - A weight → total slot fill percentage (what fraction of FractalPlacer slots to use)
- Grade derived from distance to center (existing formula: closer = higher grade)
- Location names via `Translator.NameOrator()`, descriptions from existing `loc.type.*` and `loc.feature.*` templates

#### Sector0 Prerequisite: RelocateExistingLocations
Before running LocationGenerator on Sector0, relocate existing locations to FractalPlacer-compatible grid positions:
- Generate a FractalPlacer grid
- Assign each existing location to the nearest unoccupied grid slot (preserve relative ordering — central stays near 0,0)
- Update LocX/LocY
- Return updated locations + remaining empty slots for the generator to fill

### 3. NpcGenerator
**Input:** `NpcGenConfig` — sector ID, sector RGBA, location list (for anchoring), NPC count override, seed
**Output:** `NpcGenResult` — list of NPC entries (pilot + ship + behavior + weapon lots + home location)

NPC population by RGBA:

| RGBA Driver | NPC Type | Ship Profile | Faction |
|-------------|----------|-------------|---------|
| R (danger) | Hostile raiders | Crow/Viper/Hawk/Raptor | -1 (hostile) |
| B (commerce) | Indie haulers | Hauler/Barge/Caravan/Clipper | 1 (merchant) |
| G (resources) | Indie miners | Small ships + extractors | 0 (neutral) |

No patrol/scout types. Civilian NPCs (haulers, miners) are independent operators like a starting PC. They get merchant-style behavior config (non-aggressive, flee from threats). Hostile NPCs get aggressive config. Dedicated mining/hauling behavior routines are a future task.

NPCs are anchored to locations: haulers near stations, miners near resource nodes, hostiles patrol outer areas.

Each NPC entry includes the full chain: PilotLanguage + PilotDescribable + FleetPilot + ShipLanguage + ShipDescribable + FleetShip + FleetNpcPilotInfo + weapon lots.

### 4. MarketGenerator
Wraps existing `MarketSeeder`. No changes needed. Called after locations exist.

## Data Flow

```
POST /api/admin/generate-full { neighborOf: <sectorId>, rgba: [R,G,B,A] }
  │
  ├─ SectorGenerator.Generate() → SectorGenResult
  │   └─ Persist: INSERT Languages, Describables, fleet_sectors
  │   └─ Update neighbor slots on existing sector (bidirectional)
  │
  ├─ LocationGenerator.Generate(sector, rgba) → LocationGenResult
  │   └─ Persist: INSERT Languages, Describables, fleet_locations
  │   └─ Warm: GameCache, register locations in SectorSimulation
  │
  ├─ NpcGenerator.Generate(sector, rgba, locations) → NpcGenResult
  │   └─ Persist: INSERT Languages, Describables, fleet_pilots, fleet_ships, fleet_lots, fleet_npc_pilot_info
  │   └─ Warm: GameCache.QueueNpcRegistration()
  │
  └─ MarketSeeder.SeedMarket(locations) → lots
      └─ Persist: INSERT fleet_lots
      └─ Warm: GameCache lot caches
```

### FK Insert Order
Every entity follows the three-table chain. Persistence inserts in strict FK order:
1. `Languages` (key, [name, short_desc, long_desc])
2. `Describables` (id, key FK, symbol, grade)
3. Entity table (fleet_sectors, fleet_locations, etc.) with describable FK
4. Dependent records (fleet_lots, fleet_npc_pilot_info)

One transaction per generator call to avoid orphans.

### Generator Output Types

```
SectorGenResult {
  Language (key, default[3])
  Describable (id, key, symbol, grade)
  FleetSector (id, describable, rgba, neighbors)
  NeighborUpdate (existing sector ID, slot, new sector ID)
}

LocationGenResult {
  List<SeedLocationEntry>  // existing type, already has full chain
}

NpcGenResult {
  List<NpcEntry> {
    PilotLanguage + PilotDescribable + FleetPilot
    ShipLanguage + ShipDescribable + FleetShip
    FleetNpcPilotInfo (faction, behavior, home location)
    List<Lot> (weapons + cargo)
  }
}
```

## Admin API Endpoints

| Endpoint | Method | Body | Returns |
|----------|--------|------|---------|
| `/api/admin/generate-sector` | POST | `{ neighborOf, rgba?, seed? }` | SectorGenResult |
| `/api/admin/generate-locations` | POST | `{ sectorId, count?, seed? }` | LocationGenResult |
| `/api/admin/generate-npcs` | POST | `{ sectorId, count?, seed? }` | NpcGenResult |
| `/api/admin/generate-full` | POST | `{ neighborOf, rgba?, seed? }` | All results combined |
| `/api/admin/relocate-locations` | POST | `{ sectorId }` | Updated location positions |

All endpoints handle persistence and cache warming internally after receiving generator output.

## Testing

- **Unit tests per generator:** Validate output counts, RGBA weighting (high G → more resource nodes), naming uniqueness, describable chain completeness (every entity has Language + Describable predecessor)
- **Central station rule:** B >= 50 places station at 0,0; B < 50 does not
- **FractalPlacer collision:** Existing locations in Sector0 are respected, no overlaps
- **Neighbor linking:** Bidirectional links, no slot overflow, works with single neighbor
- **NPC distribution:** R-heavy → more hostiles, G-heavy → more miners, B-heavy → more haulers
- **No new items:** Assert all generated itemIndex values fall within existing GameConstants ranges
- **FK chain:** Every output entry has all three layers (Language, Describable, entity)

Pure function tests only — no Supabase integration tests.

## Key Files

### New
- `fleet-inertia.Shared/SectorGenerator.cs`
- `fleet-inertia.Shared/LocationGenerator.cs`
- `fleet-inertia.Shared/NpcGenerator.cs`
- `fleet-inertia.Shared/GeneratorTypes.cs` (config + result types)
- `Controllers/AdminController.cs` (or extend DevController)
- `fleet-inertia.Tests/Shared/GeneratorTests.cs`

### Modified
- `fleet-inertia.Shared/GameFactory.cs` — extract shared helpers (FractalPlacer access, naming)
- `fleet-inertia.Shared/GameConstants.cs` — add CentralStationCommerceThreshold = 50
