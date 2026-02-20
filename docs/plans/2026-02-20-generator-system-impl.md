# Generator System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build composable generators for dynamic world expansion — sectors, locations, and NPCs — driven by RGBA sector personality.

**Architecture:** Individual pure-function generators (SectorGenerator, LocationGenerator, NpcGenerator) return data objects. Admin API endpoints handle persistence and cache warming. RGBA channels (R=danger, G=resources, B=commerce, A=density) weight generation distributions.

**Tech Stack:** C# / .NET 9, fleet-inertia.Shared (generators), DevController (admin endpoints), existing FractalPlacer, Translator.NameOrator, GameFactory helpers.

---

## Task 85: Generator Types & Constants (XS)

**Files:**
- Create: `fleet-inertia.Shared/GeneratorTypes.cs`
- Modify: `fleet-inertia.Shared/GameConstants.cs:108` (after GlobalStartSeed)

**Step 1: Add constants to GameConstants.cs**

After line 108 (`GlobalStartSeed`), add:

```csharp
// Generator system
public const int CentralStationCommerceThreshold = 50; // B >= this → station at 0,0
public const int DefaultSectorRadius = 2000;
public const int DefaultFractalCellSize = 200;
public const int DefaultFractalMinDistance = 150;
```

**Step 2: Create GeneratorTypes.cs**

Define all config and result types:

```csharp
namespace fleetinertia.Shared;

// -- Configs --

public record SectorGenConfig(
    Guid NeighborOf,              // existing sector to connect to
    short[]? Rgba = null,          // optional override, else derived from neighbor
    int? Seed = null);

public record LocationGenConfig(
    Guid SectorId,
    short[] SectorRgba,
    List<(long x, long y)>? ExistingPositions = null,  // for Sector0 compat
    int? Count = null,             // override slot count
    int? Seed = null);

public record NpcGenConfig(
    Guid SectorId,
    short[] SectorRgba,
    List<SeedLocationEntry> Locations,  // anchor NPCs to these
    int? Count = null,
    int? Seed = null);

// -- Results --

public record SectorGenResult(
    string LanguageKey,
    string[] LanguageDefault,      // [name, shortDesc, longDesc]
    long DescribableId,
    Guid SectorId,
    short[] Rgba,
    NeighborUpdate NeighborLink);

public record NeighborUpdate(
    Guid ExistingSectorId,
    int SlotOnExisting,            // 1-8
    int SlotOnNew);                // 1-8 (reverse link)

public record NpcEntry(
    // Pilot chain
    string PilotLanguageKey,
    string[] PilotLanguageDefault,
    long PilotDescribableId,
    Pilot Pilot,
    // Ship chain
    string ShipLanguageKey,
    string[] ShipLanguageDefault,
    long ShipDescribableId,
    ShipRegistry Ship,
    // Behavior
    short Faction,
    short BehaviorType,
    Guid? HomeLocation,
    Guid HomeSector,
    short Aggression,
    // Lots
    List<Lot> WeaponLots);

public record NpcGenResult(List<NpcEntry> Npcs);

// LocationGenResult reuses List<SeedLocationEntry> (already defined in GameFactory.cs)
```

**Step 3: Build**

Run: `dotnet build fleet-inertia.Shared`
Expected: 0 errors

**Step 4: Commit**

```bash
git add fleet-inertia.Shared/GeneratorTypes.cs fleet-inertia.Shared/GameConstants.cs
git commit -m "feat: add generator types and constants"
```

---

## Task 86: SectorGenerator (S)

**Depends on: 85**

**Files:**
- Create: `fleet-inertia.Shared/SectorGenerator.cs`
- Test: `fleet-inertia.Tests/Shared/SectorGeneratorTests.cs`

**Step 1: Write failing tests**

```csharp
[Fact] Generate_ReturnsValidSectorWithLanguageChain
  - Call SectorGenerator.Generate(config)
  - Assert result has non-empty LanguageKey, 3-element LanguageDefault
  - Assert result.DescribableId is within MinLocation..MaxLocation range
  - Assert result.SectorId is non-empty Guid
  - Assert result.Rgba has 4 elements

[Fact] Generate_WithRgbaOverride_UsesProvidedRgba
  - Pass Rgba = [180, 60, 20, 80]
  - Assert result.Rgba matches exactly

[Fact] Generate_WithoutRgba_DerivesFromNeighbor
  - Pass NeighborOf with known RGBA, no override
  - Assert result.Rgba is within variance range of neighbor RGBA

[Fact] Generate_NeighborLink_SetsBidirectionalSlots
  - Assert result.NeighborLink has valid ExistingSectorId, SlotOnExisting 1-8, SlotOnNew 1-8

[Fact] Generate_SameSeed_ProducesSameResult
  - Call twice with same seed
  - Assert both results are identical

[Fact] Generate_DifferentSeed_ProducesDifferentResult
  - Call with seed 1 and seed 2
  - Assert results differ
```

**Step 2: Run tests to verify they fail**

Run: `dotnet test --filter "SectorGenerator"`
Expected: FAIL (class not found)

**Step 3: Implement SectorGenerator**

```csharp
public static class SectorGenerator
{
    public static SectorGenResult Generate(SectorGenConfig config, short[]? neighborRgba = null)
    {
        int seed = config.Seed ?? Random.Shared.Next();
        var rng = new Random(seed);

        // RGBA: use override or derive from neighbor with ±30 variance
        short[] rgba = config.Rgba ?? DeriveRgba(neighborRgba, rng);

        // Describable chain
        long describableId = GameConstants.MinLocation + rng.Next(0, 100000);
        string name = Translator.NameOrator(rng: rng);
        string key = $"sector{describableId}";
        string shortDesc = $"Sector {name}";
        string longDesc = $"The {name} sector.";

        // Neighbor linking: pick opposing slots (1↔5, 2↔6, 3↔7, 4↔8)
        int slotOnExisting = rng.Next(1, 9);  // caller validates it's empty
        int slotOnNew = ((slotOnExisting - 1 + 4) % 8) + 1;  // opposing slot

        return new SectorGenResult(
            key,
            new[] { name, shortDesc, longDesc },
            describableId,
            Guid.NewGuid(),
            rgba,
            new NeighborUpdate(config.NeighborOf, slotOnExisting, slotOnNew));
    }

    private static short[] DeriveRgba(short[]? neighborRgba, Random rng)
    {
        if (neighborRgba == null) return new short[] { 100, 100, 100, 100 };
        var result = new short[4];
        for (int i = 0; i < 4; i++)
        {
            int val = neighborRgba[i] + rng.Next(-30, 31);
            result[i] = (short)Math.Clamp(val, 0, 255);
        }
        return result;
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `dotnet test --filter "SectorGenerator"`
Expected: PASS

**Step 5: Commit**

---

## Task 87: LocationGenerator (M)

**Depends on: 85**

**Files:**
- Create: `fleet-inertia.Shared/LocationGenerator.cs`
- Test: `fleet-inertia.Tests/Shared/LocationGeneratorTests.cs`

**Step 1: Write failing tests**

```csharp
[Fact] Generate_HighCommerce_PlacesCentralStation
  - Config with B=120 (above threshold)
  - Assert first location is at approximately (0,0) with LocType hint "station"

[Fact] Generate_LowCommerce_NoCentralStation
  - Config with B=20 (below threshold)
  - Assert no location at (0,0)

[Fact] Generate_HighResources_MoreResourceNodes
  - Config with G=220
  - Count locations with LocType resource-related > locations with B=20 config

[Fact] Generate_HighDanger_MoreMinesAndBeacons
  - Config with R=200
  - Count mine/beacon locations > count with R=20 config

[Fact] Generate_DensityScalesCount
  - Config with A=200 produces more locations than A=50

[Fact] Generate_ExistingPositions_SkipsOccupied
  - Pass existing positions list
  - Assert no generated location overlaps with existing (within minDistance)

[Fact] Generate_AllEntriesHaveDescribableChain
  - Assert every SeedLocationEntry has non-empty Key, Name, ShortDesc, LongDesc, valid DescribableId

[Fact] Generate_GradesDistributeByDistance
  - Assert locations near center have grade >= 3, locations near edge have grade <= 2

[Fact] Generate_SameSeed_Reproducible
  - Two calls with same seed produce identical results
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement LocationGenerator**

Key logic:
- Calculate total slot count: `baseSlots = FractalPlacer.GeneratePositions(maxSlots, seed)`, then use `(A / 255.0)` as fill percentage
- Distribute LocTypes across filled slots using RGBA weights:
  - Station count: `max(1, round(B / 255.0 * totalSlots * 0.3))` if B >= 50, else 0
  - ResourceNode count: `round(G / 255.0 * totalSlots * 0.4)`
  - Mine count: `round(R / 255.0 * totalSlots * 0.15)`
  - Beacon count: `round(R / 255.0 * totalSlots * 0.1)`
  - Remaining slots: additional stations (if B >= 50) or beacons
- Each SeedLocationEntry gets a LocType field added to the existing record (or encode in the Symbol field for now, and the admin endpoint reads it during persistence)
- Reuse existing `GameFactory.SeedLocation` pattern for the Language→Describable chain
- Grade formula: existing `5.0 * (1.0 - normalizedDist)` from GameFactory

**Step 4: Run tests, verify pass**

**Step 5: Commit**

---

## Task 88: NpcGenerator (M)

**Depends on: 85**

**Files:**
- Create: `fleet-inertia.Shared/NpcGenerator.cs`
- Test: `fleet-inertia.Tests/Shared/NpcGeneratorTests.cs`

**Step 1: Write failing tests**

```csharp
[Fact] Generate_HighDanger_MoreHostiles
  - Config with R=200, G=30, B=30
  - Assert hostile NPCs (faction=-1) > 50% of total

[Fact] Generate_HighCommerce_MoreHaulers
  - Config with R=30, G=30, B=200
  - Assert merchant NPCs (faction=1) > 50% of total

[Fact] Generate_HighResources_MoreMiners
  - Config with R=30, G=200, B=30
  - Assert neutral NPCs (faction=0) > 50% of total

[Fact] Generate_NpcsAnchoredToLocations
  - Assert each NPC has a HomeLocation matching one of the input locations

[Fact] Generate_HaulersNearStations
  - Assert merchant NPCs have HomeLocation that is a Station-type location

[Fact] Generate_MinersNearResourceNodes
  - Assert neutral NPCs have HomeLocation that is a ResourceNode-type location

[Fact] Generate_AllEntriesHaveFullChain
  - Assert every NpcEntry has pilot/ship language keys, describable IDs, valid Pilot/ShipRegistry

[Fact] Generate_WeaponLotsMatchShipPlan
  - Assert weapon lots match GameFactory.DefaultWeapons(ship.plan)

[Fact] Generate_HostilesGetAggressiveConfig
  - Assert faction=-1 NPCs have BehaviorType=2, Aggression=2

[Fact] Generate_CiviliansGetMerchantConfig
  - Assert faction=0 and faction=1 NPCs have BehaviorType=3, Aggression=0

[Fact] Generate_NoNewItemIndices
  - Assert all lot itemIndex values fall within existing GameConstants ranges
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement NpcGenerator**

Key logic:
- Total NPC count: `config.Count ?? round(A / 255.0 * 20)` (density-scaled, max ~20 per sector)
- Distribution by RGBA weight:
  - `hostileRatio = R / (R + G + B + 1.0)`, `haulerRatio = B / (R + G + B + 1.0)`, `minerRatio = G / (R + G + B + 1.0)`
  - Round to integers, assign remainder to largest ratio
- Per NPC:
  - Hostile: `GameFactory.NpcHostilePilot()`, `GameFactory.NpcHostileShip()`, behavior=aggressive, faction=-1
  - Hauler: `GameFactory.NpcMerchantPilot()`, `GameFactory.NpcMerchantShip()`, behavior=merchant, faction=1
  - Miner: `GameFactory.NpcPilot()`, `GameFactory.RandomShip()` (small plan), behavior=merchant, faction=0
- Anchor to locations: haulers → nearest Station, miners → nearest ResourceNode, hostiles → random outer location
- Full describable chain per NPC: Language + Describable for both pilot and ship
- Weapon lots via `GameFactory.CreateShipWeaponLots()`

**Step 4: Run tests, verify pass**

**Step 5: Commit**

---

## Task 89: Admin API Endpoints (M)

**Depends on: 86, 87, 88**

**Files:**
- Modify: `Controllers/DevController.cs` (add admin generate endpoints)
- Test: `fleet-inertia.Tests/Shared/AdminEndpointTests.cs` (optional — generators are already tested)

**Step 1: Read DevController.cs to find the pattern for admin endpoints**

Check existing seed endpoints (`seed-locations`, `seed-npcs`) for the persistence pattern: how they insert Languages, Describables, and entity rows.

**Step 2: Add generate-sector endpoint**

```csharp
// POST /api/admin/generate-sector
// Body: { neighborOf: "guid", rgba: [R,G,B,A]?, seed: int? }
```

Flow:
1. Read existing sector's RGBA from GameCache
2. Read existing sector's neighbor slots to find an empty one
3. Call `SectorGenerator.Generate(config, neighborRgba)`
4. Override the neighbor slot in result with the actual empty slot found
5. INSERT Language, Describable, FleetSector into Supabase (FK order)
6. UPDATE existing sector's neighbor slot in Supabase
7. Return result as JSON

**Step 3: Add generate-locations endpoint**

```csharp
// POST /api/admin/generate-locations
// Body: { sectorId: "guid", count: int?, seed: int? }
```

Flow:
1. Read sector RGBA from GameCache
2. Read existing locations in sector (for collision avoidance)
3. Call `LocationGenerator.Generate(config)`
4. For each SeedLocationEntry: INSERT Language, Describable, FleetLocation (FK order)
5. Warm GameCache with new locations
6. Register locations in SectorSimulation (if sector is active)
7. Return result as JSON

**Step 4: Add generate-npcs endpoint**

```csharp
// POST /api/admin/generate-npcs
// Body: { sectorId: "guid", count: int?, seed: int? }
```

Flow:
1. Read sector RGBA and locations from GameCache
2. Call `NpcGenerator.Generate(config)`
3. For each NpcEntry: INSERT pilot Language+Describable+FleetPilot, ship Language+Describable+FleetShip, FleetNpcPilotInfo, Lots (FK order)
4. Queue NPC registrations via GameCache
5. Return result as JSON

**Step 5: Add generate-full endpoint**

```csharp
// POST /api/admin/generate-full
// Body: { neighborOf: "guid", rgba: [R,G,B,A]?, seed: int? }
```

Chains: generate-sector → generate-locations → generate-npcs → MarketSeeder

**Step 6: Add relocate-locations endpoint**

```csharp
// POST /api/admin/relocate-locations
// Body: { sectorId: "guid" }
```

Flow:
1. Read existing locations for sector
2. Generate FractalPlacer grid
3. Assign each existing location to nearest grid slot
4. UPDATE fleet_locations with new LocX/LocY
5. Return updated positions

**Step 7: Build and test**

Run: `dotnet build && dotnet test`
Expected: All existing + new tests pass

**Step 8: Commit**

---

## Dependency Graph

```
Task 85 (types + constants) ──┬──→ Task 86 (SectorGenerator)   ──┐
                               ├──→ Task 87 (LocationGenerator) ──┤──→ Task 89 (Admin API)
                               └──→ Task 88 (NpcGenerator)     ──┘
```

Tasks 86, 87, 88 can run in parallel after 85 completes. Task 89 depends on all three generators.
