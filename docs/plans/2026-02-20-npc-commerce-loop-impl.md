# NPC Commerce Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give NPCs purposeful commerce behavior — hauling cargo, mining resources, and running delivery contracts — using a coordinator-level task planner with shared transaction logic.

**Architecture:** NpcTaskPlanner ticks every 60s, maintains per-NPC task queues, issues NpcCommands to existing NpcControllers via coordinator facades. TransactionService extracted from DataController handles buy/sell/load for both players and NPCs. Three archetype strategy classes (CargoBarge, Miner, UnionPilot) generate task sequences.

**Tech Stack:** C# / .NET 9, fleet-inertia.Shared (types, archetypes), Services (planner, transactions), existing NpcController/SimulationCoordinator.

---

## Task 93: NPC Commerce Types & Constants (XS)

**Files:**
- Create: `fleet-inertia.Shared/NpcTask.cs`
- Modify: `fleet-inertia.Shared/GameConstants.cs:114` (after DefaultFractalMinDistance)

**Step 1: Add constants to GameConstants.cs**

After line 114 (`DefaultFractalMinDistance`), add:

```csharp
// NPC commerce system
public const int NpcDockIdleSeconds = 3600;          // 60min station idle
public const int NpcPlannerTickSeconds = 60;          // planner tick rate
public const int NpcPatrolDurationSeconds = 600;      // 10min patrol duration
public const int NpcTaskTimeoutSeconds = 300;          // 5min stuck timeout
```

**Step 2: Create NpcTask.cs**

Read these files first to understand referenced types:
- `fleet-inertia.Shared/NpcCommand.cs` — NpcCommandType enum, Vector2 usage
- `fleet-inertia.Shared/Lot.cs` — LotType enum
- `fleet-inertia.Shared/NpcBehaviorConfig.cs` — PatrolPattern enum
- `Models/Database/FleetLocation.cs` — LocType enum

```csharp
using Microsoft.Xna.Framework;

namespace fleetinertia.Shared;

public enum NpcTaskType
{
    TravelTo,
    DockAt,
    Undock,
    BuyLot,
    SellLot,
    LoadLot,
    TakeContract,
    CompleteContract,
    BeginExtraction,
    WaitForExtraction,
    Wait,
    Patrol
}

public enum NpcArchetypeType
{
    CargoBarge,
    Miner,
    UnionPilot
}

public record NpcTask
{
    public NpcTaskType Type { get; init; }

    // TravelTo / DockAt / Patrol
    public Vector2? TargetPosition { get; init; }
    public Guid? LocationId { get; init; }

    // BuyLot / SellLot / LoadLot / TakeContract / CompleteContract
    public Guid? LotId { get; init; }
    public int? ItemIndex { get; init; }
    public int? MaxPrice { get; init; }

    // BeginExtraction
    public Guid? NodeId { get; init; }
    public int? ExtractorType { get; init; }

    // Wait / Patrol
    public float DurationSeconds { get; init; }

    // Patrol
    public PatrolPattern? PatrolPattern { get; init; }
    public short? PatrolRadius { get; init; }

    // Tracking
    public DateTime? StartedAt { get; set; }

    // Factory methods
    public static NpcTask Travel(Vector2 position, Guid? locationId = null)
        => new() { Type = NpcTaskType.TravelTo, TargetPosition = position, LocationId = locationId };

    public static NpcTask Dock(Guid locationId, Vector2 position)
        => new() { Type = NpcTaskType.DockAt, LocationId = locationId, TargetPosition = position };

    public static NpcTask UndockTask()
        => new() { Type = NpcTaskType.Undock };

    public static NpcTask Buy(int itemIndex, int maxPrice)
        => new() { Type = NpcTaskType.BuyLot, ItemIndex = itemIndex, MaxPrice = maxPrice };

    public static NpcTask Sell(Guid lotId)
        => new() { Type = NpcTaskType.SellLot, LotId = lotId };

    public static NpcTask Load(Guid lotId)
        => new() { Type = NpcTaskType.LoadLot, LotId = lotId };

    public static NpcTask Take(Guid lotId)
        => new() { Type = NpcTaskType.TakeContract, LotId = lotId };

    public static NpcTask Complete(Guid lotId)
        => new() { Type = NpcTaskType.CompleteContract, LotId = lotId };

    public static NpcTask Extract(Guid nodeId, int extractorType)
        => new() { Type = NpcTaskType.BeginExtraction, NodeId = nodeId, ExtractorType = extractorType };

    public static NpcTask WaitExtraction()
        => new() { Type = NpcTaskType.WaitForExtraction };

    public static NpcTask Idle(float seconds)
        => new() { Type = NpcTaskType.Wait, DurationSeconds = seconds };

    public static NpcTask PatrolArea(Vector2 center, PatrolPattern pattern, short radius, float durationSeconds)
        => new() { Type = NpcTaskType.Patrol, TargetPosition = center, PatrolPattern = pattern, PatrolRadius = radius, DurationSeconds = durationSeconds };
}

/// <summary>
/// Context passed to archetype Plan() methods with everything needed for decision-making.
/// </summary>
public record NpcPlanContext(
    Guid ShipId,
    Guid PilotId,
    Guid HomeSectorId,
    Guid? HomeLocationId,
    Vector2 CurrentPosition,
    Guid? DockedAtLocationId,
    int PilotCoins,
    int ShipPlan,
    float RemainingCargoMass,
    Lot[] ShipCargo,
    Lot[] StationMarket,
    List<FleetLocation> SectorLocations,
    short[] SectorRgba,
    Random Rng);

/// <summary>
/// Archetype strategy interface — generates a task queue for an NPC.
/// </summary>
public interface INpcArchetype
{
    Queue<NpcTask> Plan(NpcPlanContext context);
}
```

IMPORTANT: Check the actual `FleetLocation` import — it may be in a `Models.Database` namespace. Add the appropriate `using` if needed. Also check that `Lot` and `PatrolPattern` are accessible from `fleetinertia.Shared`.

**Step 3: Build**

Run: `dotnet build fleet-inertia.Shared`
Expected: 0 errors

**Step 4: Commit**

```bash
git add fleet-inertia.Shared/NpcTask.cs fleet-inertia.Shared/GameConstants.cs
git commit -m "feat: add NPC commerce task types and constants"
```

---

## Task 94: Fix BehaviorType 3 Bug (XS)

**Files:**
- Modify: `Services/CacheWarmingHostedService.cs:130-134`
- Test: `fleet-inertia.Tests/Shared/CacheWarmingBehaviorTypeTests.cs`

**Step 1: Write failing test**

```csharp
[Fact]
public void BehaviorType3_ShouldMapToMerchant()
{
    // Test the mapping logic — BehaviorType 3 should produce Merchant config
    var config = MapBehaviorType(3);
    Assert.Equal("merchant", config.TypeId);
}

[Fact]
public void BehaviorType2_ShouldMapToAggressive()
{
    var config = MapBehaviorType(2);
    Assert.Equal("aggressive", config.TypeId);
}

// Helper that replicates the switch logic
private static NpcBehaviorConfig MapBehaviorType(short behaviorType) => behaviorType switch
{
    1 => NpcBehaviorConfig.Scout,
    2 => NpcBehaviorConfig.Aggressive,
    3 => NpcBehaviorConfig.Merchant,
    _ => NpcBehaviorConfig.Patrol
};
```

**Step 2: Fix CacheWarmingHostedService.cs**

At line ~130, change the switch from:
```csharp
var config = info.BehaviorType switch
{
    1 => fleetinertia.Shared.NpcBehaviorConfig.Scout,
    2 => fleetinertia.Shared.NpcBehaviorConfig.Aggressive,
    _ => fleetinertia.Shared.NpcBehaviorConfig.Patrol
};
```

To:
```csharp
var config = info.BehaviorType switch
{
    1 => fleetinertia.Shared.NpcBehaviorConfig.Scout,
    2 => fleetinertia.Shared.NpcBehaviorConfig.Aggressive,
    3 => fleetinertia.Shared.NpcBehaviorConfig.Merchant,
    _ => fleetinertia.Shared.NpcBehaviorConfig.Patrol
};
```

**Step 3: Run tests, verify pass**

Run: `dotnet test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add Services/CacheWarmingHostedService.cs fleet-inertia.Tests/Shared/CacheWarmingBehaviorTypeTests.cs
git commit -m "fix: map BehaviorType 3 to Merchant config instead of Patrol"
```

---

## Task 95: NpcCommand Facades (S)

**Depends on: 93**

**Files:**
- Modify: `Services/SectorSimulation.cs` (add SetNpcCommand, GetNpcCommandType)
- Modify: `Services/SimulationCoordinator.cs` (add facade methods)
- Modify: `fleet-inertia.Contracts/ISectorProxy.cs` (add interface methods)
- Modify: `fleet-inertia.Contracts/LocalSectorProxy.cs` (add implementations)
- Test: `fleet-inertia.Tests/Shared/NpcCommandFacadeTests.cs`

**Step 1: Read existing files**

Read these to understand the facade pattern:
- `Services/SimulationCoordinator.cs` — existing facade methods (GetShipState, SetShipDocked, etc.)
- `Services/SectorSimulation.cs` — `_npcControllers` dictionary, how NpcController is accessed
- `fleet-inertia.Contracts/ISectorProxy.cs` — interface pattern
- `fleet-inertia.Contracts/LocalSectorProxy.cs` — local implementation pattern

**Step 2: Write failing tests**

```csharp
[Fact] SetNpcCommand_UpdatesControllerCommand
  - Register an NPC, call SetNpcCommand with Travel command
  - Assert NpcController.CurrentCommand.Type == Travel

[Fact] GetNpcCommandType_ReturnsCurrentType
  - Register an NPC (starts with Patrol command)
  - Assert GetNpcCommandType returns Patrol

[Fact] GetNpcCommandType_UnknownShip_ReturnsNull
  - Call with non-existent shipId
  - Assert returns null
```

**Step 3: Add methods to SectorSimulation**

```csharp
public void SetNpcCommand(Guid shipId, NpcCommand command)
{
    if (_npcControllers.TryGetValue(shipId, out var controller))
        controller.SetCommand(command);
}

public NpcCommandType? GetNpcCommandType(Guid shipId)
{
    if (_npcControllers.TryGetValue(shipId, out var controller))
        return controller.CurrentCommand.Type;
    return null;
}
```

**Step 4: Add to ISectorProxy interface**

```csharp
Task SetNpcCommandAsync(Guid shipId, NpcCommand command);
Task<NpcCommandType?> GetNpcCommandTypeAsync(Guid shipId);
```

**Step 5: Add to LocalSectorProxy**

```csharp
public Task SetNpcCommandAsync(Guid shipId, NpcCommand command)
{
    _simulation.SetNpcCommand(shipId, command);
    return Task.CompletedTask;
}

public Task<NpcCommandType?> GetNpcCommandTypeAsync(Guid shipId)
    => Task.FromResult(_simulation.GetNpcCommandType(shipId));
```

**Step 6: Add coordinator facades**

```csharp
public async Task SetNpcCommand(Guid shipId, NpcCommand command)
{
    if (_shipToSector.TryGetValue(shipId, out var sectorId)
        && _sectors.TryGetValue(sectorId, out var sector))
        await sector.SetNpcCommandAsync(shipId, command);
}

public async Task<NpcCommandType?> GetNpcCommandType(Guid shipId)
{
    if (_shipToSector.TryGetValue(shipId, out var sectorId)
        && _sectors.TryGetValue(sectorId, out var sector))
        return await sector.GetNpcCommandTypeAsync(shipId);
    return null;
}
```

**Step 7: Build, test, commit**

Run: `dotnet build && dotnet test`

```bash
git commit -m "feat: add SetNpcCommand and GetNpcCommandType facades"
```

---

## Task 96: TransactionService Extraction (M)

**Depends on: 93**

**Files:**
- Create: `Services/TransactionService.cs`
- Modify: `Controllers/DataController.cs` (delegate to TransactionService)
- Test: `fleet-inertia.Tests/Shared/TransactionServiceTests.cs`

**Step 1: Read DataController.cs thoroughly**

Focus on `ExecuteTransaction()` (lines 243-368), `ExecuteDock()` (lines 390-448), `ExecuteUndock()` (lines 470-489). Understand every dependency: `_gameCache`, `_supabaseService`, `_coordinator`, `MarketFilter`, `LotManager`.

**Step 2: Write failing tests**

```csharp
[Fact] BuyLoad_DeductsCoinsMoveToShip
  - Set up pilot with 1000 coins, lot at location with contract=100
  - Call BuyLoad(pilotId, lotId, shipId)
  - Assert pilot.Coins == 900, lot.location == shipId, lot.locationType == Ship

[Fact] BuyLoad_InsufficientCoins_ReturnsFalse
  - Pilot has 50 coins, lot contract=100
  - Assert BuyLoad returns false, lot unmoved

[Fact] BuyLoad_CargoFull_ReturnsFalse
  - Ship cargo at capacity
  - Assert BuyLoad returns false

[Fact] Sell_CreditsCoinsMoveToLocation
  - Lot on ship, contract=200
  - Call Sell(pilotId, lotId, locationId)
  - Assert pilot.Coins increased by 200, lot at location

[Fact] Load_MovesOwnedLotToShip
  - Lot at location, owned by pilot
  - Call Load(pilotId, lotId, shipId)
  - Assert lot on ship, no coin change

[Fact] CompleteDelivery_CorrectDestination_Succeeds
  - Delivery lot with destination=locationA, pilot docked at locationA
  - Call CompleteDelivery(pilotId, lotId, locationId)
  - Assert coins credited, lot consumed

[Fact] CompleteDelivery_WrongDestination_Fails
  - Delivery lot with destination=locationA, pilot at locationB
  - Assert returns false

[Fact] DockShip_InRange_SetsDocked
  - Ship within 50u of station
  - Call DockShip(shipId, locationId)
  - Assert ship.Location set

[Fact] DockShip_OutOfRange_Fails
  - Ship 200u from station
  - Assert DockShip returns false

[Fact] UndockShip_ClearsLocation
  - Docked ship
  - Call UndockShip(shipId)
  - Assert ship.Location == null
```

**Step 3: Create TransactionService.cs**

Extract the core logic from DataController. Key difference: TransactionService methods take entity IDs directly (no userId validation — that stays in DataController). The service operates on GameCache directly.

```csharp
public class TransactionService
{
    private readonly GameCacheService _gameCache;
    private readonly SupabaseService _supabaseService;
    private readonly SimulationCoordinator _coordinator;

    // BuyLoad: deduct coins, move lot to ship
    public bool BuyLoad(Guid pilotId, Guid lotId, Guid shipId, Guid sourceLocationId) { ... }

    // Sell: credit coins, move lot to location
    public bool Sell(Guid pilotId, Guid lotId, Guid locationId) { ... }

    // Load: move owned lot to ship (free)
    public bool Load(Guid pilotId, Guid lotId, Guid shipId, Guid sourceLocationId) { ... }

    // Unload: move lot from ship to location (free)
    public bool Unload(Guid pilotId, Guid lotId, Guid locationId) { ... }

    // CompleteDelivery: validate destination, credit contract value, remove lot
    public bool CompleteDelivery(Guid pilotId, Guid lotId, Guid locationId) { ... }

    // DockShip: range check, set location, zero velocity
    public bool DockShip(Guid shipId, Guid locationId) { ... }

    // UndockShip: clear location
    public bool UndockShip(Guid shipId) { ... }
}
```

IMPORTANT: Read DataController's `ExecuteTransaction` carefully and replicate the EXACT lot mutation logic: remove from source, update fields, add to destination. Use `_gameCache.MutateLots()` for thread-safe mutations. Replicate the cargo capacity check using `MarketFilter.RemainingMass()`.

**Step 4: Refactor DataController to delegate**

`DataController.ExecuteTransaction()` should call `TransactionService` methods instead of inlining the logic. Keep the HTTP validation (userId checks, request parsing) in DataController.

**Step 5: Build, test, commit**

Run: `dotnet build && dotnet test`
All existing tests must still pass (no behavioral changes).

```bash
git commit -m "refactor: extract TransactionService from DataController"
```

---

## Task 97: NpcTaskPlanner Core (M)

**Depends on: 96**

**Files:**
- Create: `Services/NpcTaskPlanner.cs`
- Test: `fleet-inertia.Tests/Shared/NpcTaskPlannerTests.cs`

**Step 1: Read existing code**

- `Services/SimulationCoordinator.cs` — injection pattern, NPC registration, StartAsync
- `Services/GameCacheService.cs` — lot queries, ship state, pilot data
- `fleet-inertia.Shared/NpcCommand.cs` — command factory methods
- `fleet-inertia.Shared/NpcTask.cs` — task types (created in task 93)

**Step 2: Write failing tests**

```csharp
[Fact] RegisterNpc_CreatesEmptyQueue
  - Register an NPC
  - Assert task queue exists and is empty

[Fact] Tick_EmptyQueue_CallsPlan
  - Register NPC with mock archetype that returns [Travel, DockAt, Wait]
  - Call Tick()
  - Assert queue has 3 tasks, first task issued as NpcCommand

[Fact] Tick_TravelComplete_DequeuesNext
  - Register NPC, set queue to [TravelTo, DockAt]
  - Mock GetNpcCommandType returns Idle (travel complete)
  - Call Tick()
  - Assert TravelTo dequeued, DockAt now current

[Fact] Tick_DockTask_ExecutesDock
  - NPC at station position, current task is DockAt
  - Call Tick()
  - Assert TransactionService.DockShip called

[Fact] Tick_BuyTask_ExecutesBuy
  - NPC docked, current task is BuyLot
  - Call Tick()
  - Assert TransactionService.BuyLoad called, task dequeued immediately

[Fact] Tick_WaitTask_TracksExpiry
  - Current task is Wait(3600)
  - First tick: task not complete (just started)
  - After 3600s: task complete, dequeued

[Fact] Tick_StuckTask_AbandonedAfterTimeout
  - Travel task started 6 minutes ago
  - Call Tick()
  - Assert queue cleared, archetype.Plan() called for fresh plan

[Fact] Tick_PatrolTask_ExpiresAfterDuration
  - Patrol task with duration 600s
  - After 600s: task complete, dequeued
```

**Step 3: Implement NpcTaskPlanner**

```csharp
public class NpcTaskPlanner
{
    private readonly SimulationCoordinator _coordinator;
    private readonly TransactionService _transactionService;
    private readonly GameCacheService _gameCache;

    // Per-NPC state
    private readonly ConcurrentDictionary<Guid, NpcPlannerState> _npcStates = new();

    private record NpcPlannerState(
        Guid ShipId,
        Guid PilotId,
        Guid HomeSectorId,
        Guid? HomeLocationId,
        INpcArchetype Archetype,
        Queue<NpcTask> TaskQueue,
        NpcTask? CurrentTask,
        DateTime? CurrentTaskStarted);

    public void RegisterNpc(Guid shipId, Guid pilotId, Guid sectorId,
        Guid? homeLocationId, NpcArchetypeType archetypeType, short faction) { ... }

    public void Tick() { ... }  // Called every NpcPlannerTickSeconds

    private void ProcessNpc(NpcPlannerState state) { ... }
    private bool IsCurrentTaskComplete(NpcPlannerState state) { ... }
    private void ExecuteInstantTask(NpcPlannerState state, NpcTask task) { ... }
    private void IssueNpcCommand(NpcPlannerState state, NpcTask task) { ... }
    private NpcPlanContext BuildPlanContext(NpcPlannerState state) { ... }
}
```

Key logic:
- `Tick()`: iterates all registered NPCs, calls `ProcessNpc()` for each
- `ProcessNpc()`: if no current task → dequeue or re-plan. If current task → check completion. If complete → advance. If stuck (timeout) → clear and re-plan.
- `IsCurrentTaskComplete()`: dispatches based on task type — checks NpcController state for navigation, timestamps for Wait/Patrol, etc.
- `ExecuteInstantTask()`: for Buy/Sell/Load/Complete tasks, calls TransactionService immediately
- `IssueNpcCommand()`: translates NpcTask → NpcCommand, calls `_coordinator.SetNpcCommand()`

**Step 4: Build, test, commit**

Run: `dotnet build && dotnet test`

```bash
git commit -m "feat: implement NpcTaskPlanner core with task queue"
```

---

## Task 98: CargoBarge Archetype (S)

**Depends on: 97**

**Files:**
- Create: `fleet-inertia.Shared/Archetypes/CargoBarge.cs`
- Test: `fleet-inertia.Tests/Shared/Archetypes/CargoBargeTests.cs`

**Step 1: Write failing tests**

```csharp
[Fact] Plan_WithProfitableLots_GeneratesBuySellSequence
  - Station market has cargo lots with contract > 0
  - Another station exists in sector
  - Assert plan: BuyLot x N → Undock → TravelTo(destination) → DockAt → SellLot x N → Wait

[Fact] Plan_NoProfitableLots_TravelsToRandomStation
  - Empty station market
  - Assert plan: Undock → TravelTo(random station) → DockAt → (re-plan will trigger)

[Fact] Plan_FillsCargoToCapacity
  - Station has 10 lots, ship capacity fits 3
  - Assert exactly 3 BuyLot tasks

[Fact] Plan_PrefersHighValueLots
  - Station has lots with contract values 10, 50, 100
  - Ship fits 2
  - Assert buys the 100 and 50 value lots

[Fact] Plan_NotDocked_TravelsToNearestStation
  - NPC not currently docked, station exists
  - Assert plan starts with TravelTo(station) → DockAt
```

**Step 2: Implement CargoBarge**

```csharp
namespace fleetinertia.Shared.Archetypes;

public class CargoBarge : INpcArchetype
{
    public Queue<NpcTask> Plan(NpcPlanContext context)
    {
        var queue = new Queue<NpcTask>();

        // If not docked, travel to nearest station first
        if (context.DockedAtLocationId == null)
        {
            var nearestStation = FindNearestStation(context);
            if (nearestStation == null) return queue; // no stations, empty plan
            queue.Enqueue(NpcTask.Travel(StationPosition(nearestStation), nearestStation.Id));
            queue.Enqueue(NpcTask.Dock(nearestStation.Id, StationPosition(nearestStation)));
            return queue; // will re-plan once docked
        }

        // Docked: find profitable cargo to buy
        var affordableLots = context.StationMarket
            .Where(l => l.lotType == LotType.Cargo && l.ShowContract() > 0
                && l.ShowContract() <= context.PilotCoins)
            .OrderByDescending(l => l.ShowContract())
            .ToList();

        // Buy lots that fit in cargo
        float remainingMass = context.RemainingCargoMass;
        var toBuy = new List<Lot>();
        foreach (var lot in affordableLots)
        {
            if (lot.LoadedMass <= remainingMass)
            {
                toBuy.Add(lot);
                remainingMass -= lot.LoadedMass;
            }
        }

        if (toBuy.Count == 0)
        {
            // Nothing to buy — travel to random other station
            var otherStation = FindRandomOtherStation(context);
            if (otherStation != null)
            {
                queue.Enqueue(NpcTask.UndockTask());
                queue.Enqueue(NpcTask.Travel(StationPosition(otherStation), otherStation.Id));
                queue.Enqueue(NpcTask.Dock(otherStation.Id, StationPosition(otherStation)));
            }
            return queue;
        }

        // Buy all selected lots
        foreach (var lot in toBuy)
            queue.Enqueue(NpcTask.Buy(lot.itemIndex, lot.ShowContract()));

        // Find destination station (different from current)
        var destStation = FindRandomOtherStation(context);
        if (destStation == null) return queue;

        queue.Enqueue(NpcTask.UndockTask());
        queue.Enqueue(NpcTask.Travel(StationPosition(destStation), destStation.Id));
        queue.Enqueue(NpcTask.Dock(destStation.Id, StationPosition(destStation)));

        // Sell all cargo at destination
        foreach (var lot in toBuy)
            queue.Enqueue(NpcTask.Sell(lot.Id));

        // Wait at station
        queue.Enqueue(NpcTask.Idle(GameConstants.NpcDockIdleSeconds));

        return queue;
    }
}
```

IMPORTANT: Read `FleetLocation` to understand how to get position (LocX, LocY) and LocType. Filter stations by LocType. Adapt the `FindNearestStation` and `FindRandomOtherStation` helpers to use actual FleetLocation fields.

**Step 3: Build, test, commit**

```bash
git commit -m "feat: implement CargoBarge archetype"
```

---

## Task 99: Miner Archetype (S)

**Depends on: 97**

**Files:**
- Create: `fleet-inertia.Shared/Archetypes/Miner.cs`
- Test: `fleet-inertia.Tests/Shared/Archetypes/MinerTests.cs`

**Step 1: Write failing tests**

```csharp
[Fact] Plan_Docked_WithResourceNode_GeneratesExtractLoop
  - Sector has ResourceNode location
  - Assert: Undock → TravelTo(node) → BeginExtraction → WaitForExtraction → TravelTo(home station) → DockAt → SellLot x N → Wait

[Fact] Plan_NotDocked_TravelsToHomeStation
  - Miner not docked
  - Assert starts with TravelTo(home) → DockAt

[Fact] Plan_NoResourceNodes_IdlesAtStation
  - No resource nodes in sector
  - Assert just Wait(NpcDockIdleSeconds)

[Fact] Plan_PrefersNearestResourceNode
  - Multiple resource nodes, one closer
  - Assert TravelTo targets the nearest node

[Fact] Plan_SellsAllCargoAfterReturn
  - Ship has 3 cargo lots after extraction
  - Assert 3 SellLot tasks after DockAt
```

**Step 2: Implement Miner**

```csharp
namespace fleetinertia.Shared.Archetypes;

public class Miner : INpcArchetype
{
    public Queue<NpcTask> Plan(NpcPlanContext context)
    {
        var queue = new Queue<NpcTask>();

        // If not docked, go home
        if (context.DockedAtLocationId == null)
        {
            var home = FindHomeStation(context);
            if (home != null)
            {
                queue.Enqueue(NpcTask.Travel(LocationPosition(home), home.Id));
                queue.Enqueue(NpcTask.Dock(home.Id, LocationPosition(home)));
            }
            return queue;
        }

        // Sell any cargo first
        foreach (var lot in context.ShipCargo.Where(l => l.lotType == LotType.Cargo))
            queue.Enqueue(NpcTask.Sell(lot.Id));

        // Find nearest resource node
        var node = FindNearestResourceNode(context);
        if (node == null)
        {
            queue.Enqueue(NpcTask.Idle(GameConstants.NpcDockIdleSeconds));
            return queue;
        }

        // Undock, travel to node, extract, return, sell
        queue.Enqueue(NpcTask.UndockTask());
        queue.Enqueue(NpcTask.Travel(LocationPosition(node), node.Id));
        queue.Enqueue(NpcTask.Extract(node.Id, FindExtractorType(context)));
        queue.Enqueue(NpcTask.WaitExtraction());

        // Return to home station
        var homeStation = FindHomeStation(context);
        if (homeStation != null)
        {
            queue.Enqueue(NpcTask.Travel(LocationPosition(homeStation), homeStation.Id));
            queue.Enqueue(NpcTask.Dock(homeStation.Id, LocationPosition(homeStation)));
        }

        // Wait
        queue.Enqueue(NpcTask.Idle(GameConstants.NpcDockIdleSeconds));

        return queue;
    }
}
```

Read `fleet-inertia.Shared/GameConstants.cs` for extractor component ID ranges (MinExtractor..MaxExtractor). The `FindExtractorType` helper should check the NPC's weapon/component lots for an extractor item.

**Step 3: Build, test, commit**

```bash
git commit -m "feat: implement Miner archetype"
```

---

## Task 100: UnionPilot Archetype (S)

**Depends on: 97**

**Files:**
- Create: `fleet-inertia.Shared/Archetypes/UnionPilot.cs`
- Test: `fleet-inertia.Tests/Shared/Archetypes/UnionPilotTests.cs`

**Step 1: Write failing tests**

```csharp
[Fact] Plan_WithDeliveryContracts_TakesHighestValue
  - Station has delivery lots with contract values 50, 100, 200
  - Ship has cargo capacity
  - Assert: TakeContract(200-value lot) → Undock → TravelTo(destination) → DockAt → CompleteContract → Wait

[Fact] Plan_NoContracts_TravelsToRandomStation
  - No delivery lots at current station
  - Assert: Undock → TravelTo(random station) → DockAt

[Fact] Plan_ContractTooHeavy_SkipsToNext
  - Delivery lot mass=100, ship remaining mass=5
  - Next lot mass=3
  - Assert takes the lighter lot

[Fact] Plan_NotDocked_TravelsToNearestStation
  - Not docked
  - Assert: TravelTo → DockAt

[Fact] Plan_PrefersInSectorDestinations
  - Contracts with destination in-sector and out-of-sector
  - Assert takes in-sector contract
```

**Step 2: Implement UnionPilot**

```csharp
namespace fleetinertia.Shared.Archetypes;

public class UnionPilot : INpcArchetype
{
    public Queue<NpcTask> Plan(NpcPlanContext context)
    {
        var queue = new Queue<NpcTask>();

        if (context.DockedAtLocationId == null)
        {
            var nearest = FindNearestStation(context);
            if (nearest != null)
            {
                queue.Enqueue(NpcTask.Travel(LocationPosition(nearest), nearest.Id));
                queue.Enqueue(NpcTask.Dock(nearest.Id, LocationPosition(nearest)));
            }
            return queue;
        }

        // Find best delivery contract
        var sectorLocationIds = context.SectorLocations.Select(l => l.Id).ToHashSet();
        var contracts = context.StationMarket
            .Where(l => l.lotType == LotType.Delivery
                && l.destination.HasValue
                && sectorLocationIds.Contains(l.destination.Value)
                && l.LoadedMass <= context.RemainingCargoMass)
            .OrderByDescending(l => l.ShowContract())
            .ToList();

        if (contracts.Count == 0)
        {
            var otherStation = FindRandomOtherStation(context);
            if (otherStation != null)
            {
                queue.Enqueue(NpcTask.UndockTask());
                queue.Enqueue(NpcTask.Travel(LocationPosition(otherStation), otherStation.Id));
                queue.Enqueue(NpcTask.Dock(otherStation.Id, LocationPosition(otherStation)));
            }
            else
            {
                queue.Enqueue(NpcTask.Idle(GameConstants.NpcDockIdleSeconds));
            }
            return queue;
        }

        var contract = contracts[0];
        var destLocation = context.SectorLocations.First(l => l.Id == contract.destination.Value);

        queue.Enqueue(NpcTask.Take(contract.Id));
        queue.Enqueue(NpcTask.UndockTask());
        queue.Enqueue(NpcTask.Travel(LocationPosition(destLocation), destLocation.Id));
        queue.Enqueue(NpcTask.Dock(destLocation.Id, LocationPosition(destLocation)));
        queue.Enqueue(NpcTask.Complete(contract.Id));
        queue.Enqueue(NpcTask.Idle(GameConstants.NpcDockIdleSeconds));

        return queue;
    }
}
```

**Step 3: Build, test, commit**

```bash
git commit -m "feat: implement UnionPilot archetype"
```

---

## Task 101: Planner Integration (S)

**Depends on: 100**

**Files:**
- Modify: `Services/SimulationCoordinator.cs` (wire NpcTaskPlanner into startup and NPC registration)
- Modify: `Services/NpcTaskPlanner.cs` (add timer start/stop)
- Modify: `Program.cs` or `Startup.cs` (register TransactionService and NpcTaskPlanner in DI)
- Test: existing tests must pass (no regressions)

**Step 1: Read startup code**

- `Program.cs` or `Startup.cs` — how services are registered
- `Services/SimulationCoordinator.cs` — `StartAsync()`, NPC registration loop

**Step 2: Register services in DI**

```csharp
builder.Services.AddSingleton<TransactionService>();
builder.Services.AddSingleton<NpcTaskPlanner>();
```

**Step 3: Inject NpcTaskPlanner into SimulationCoordinator**

Add to constructor:
```csharp
private readonly NpcTaskPlanner _npcPlanner;
```

**Step 4: Wire NPC registration to planner**

After each `RegisterNpcShip()` call in `StartAsync()`, also register with the planner:

```csharp
_npcPlanner.RegisterNpc(
    npc.ShipId, npc.PilotId, npc.SectorId,
    npc.HomeLocationId, DetermineArchetype(npc.Config, npc.Faction), npc.Faction);
```

Where `DetermineArchetype` maps:
- Faction 1 (merchant) + hauler ships → CargoBarge
- Faction 0 (neutral) → Miner
- Faction -1 (hostile) → skip (no commerce archetype yet)
- Default small ships → UnionPilot

**Step 5: Start planner timer**

In `StartAsync()`, after all NPCs are registered:
```csharp
_npcPlanner.Start();  // begins the 60s tick timer
```

In `StopAsync()`:
```csharp
_npcPlanner.Stop();
```

**Step 6: Build, test**

Run: `dotnet build && dotnet test`
All existing tests must pass. Verify no regressions.

**Step 7: Commit**

```bash
git commit -m "feat: integrate NpcTaskPlanner into coordinator startup"
```

---

## Dependency Graph

```
Task 93 (types + constants) ──┬──→ Task 95 (command facades) ──→ Task 96 (TransactionService) ──→ Task 97 (planner core) ──┬──→ Task 98 (CargoBarge)   ──┐
                               │                                                                                             ├──→ Task 99 (Miner)        ──┤──→ Task 101 (integration)
                               │                                                                                             └──→ Task 100 (UnionPilot)  ──┘
Task 94 (BehaviorType fix) ────┘ (independent, can run anytime)
```

Tasks 98, 99, 100 can run in parallel after 97 completes. Task 101 depends on all three archetypes.
