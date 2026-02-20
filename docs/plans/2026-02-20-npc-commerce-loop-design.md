# NPC Commerce Loop Design — Task 91

## Overview
Automated NPC behavior loops that give haulers, miners, and contract pilots purposeful activity: fly, dock, trade, extract, deliver, wait, repeat. NPCs use the same transaction pipeline as players, ensuring consistent game mechanics.

**Hard constraint:** Core 3 archetypes only (CargoBarge, Miner, UnionPilot). Escort and Hostile Resupply are follow-up tasks. In-memory task state only — no database persistence for NPC plans.

## Architecture

Three layers:

### 1. NpcTaskPlanner (new)
A coordinator-level service that decides WHAT each NPC should do. Maintains an in-memory `Queue<NpcTask>` per NPC. Ticks every 60 seconds (configurable via `GameConstants.NpcPlannerTickSeconds`). When the current task completes, dequeues the next. When the queue is empty, calls the archetype's `Plan()` method to generate a new batch.

### 2. SimulationCoordinator (existing)
Bridges planner commands to sector simulations. The planner issues `NpcCommand`s through the coordinator to reach the correct `SectorSimulation`.

### 3. NpcController (existing)
Executes navigation commands (Travel, Dock, Wait, etc.) at the physics level. No changes needed.

## NPC Task Types

Each `NpcTask` represents one atomic step in a behavior chain:

| Task Type | Parameters | Execution | Completion Signal |
|-----------|-----------|-----------|-------------------|
| TravelTo | position, locationId? | Issue Travel NpcCommand | NpcController reports Idle (arrived) |
| DockAt | locationId | Trigger dock mechanics (internal) | Ship location set in cache |
| Undock | — | Clear ship location (internal) | Ship location cleared |
| BuyLot | itemIndex, maxPrice | TransactionService.BuyLoad() | Instant — lot moved to ship |
| SellLot | lotId | TransactionService.Sell() | Instant — lot moved to location |
| LoadLot | lotId | TransactionService.Load() | Instant |
| TakeContract | lotId | TransactionService.BuyLoad() | Instant — contract lot loaded |
| CompleteContract | lotId | TransactionService.CompleteDelivery() | Instant — coins credited |
| BeginExtraction | nodeId, extractorType | Call extraction pipeline | Instant — extraction started |
| WaitForExtraction | — | Poll extraction state | Processing complete |
| Wait | seconds | Track expiry timestamp | DateTime.UtcNow >= expiry |
| Patrol | center, pattern, radius, duration | Issue Patrol NpcCommand | Elapsed time >= duration |

Transaction tasks (Buy, Sell, Load, TakeContract, CompleteContract) execute instantly via TransactionService during the planner tick — no NpcCommand needed since the ship is already docked.

## Archetype Behavior Plans

### INpcArchetype Interface

```csharp
public interface INpcArchetype
{
    Queue<NpcTask> Plan(NpcPlanContext context);
}
```

`NpcPlanContext` contains: NPC's current position, home location, home sector, ship cargo/capacity, pilot coins, nearby locations with their markets, sector RGBA.

### CargoBarge (faction=1, hauler ships)

1. Scan current station market for profitable lots (buy here, sell at another station)
2. BuyLot x N (fill cargo capacity)
3. Undock
4. TravelTo destination station
5. DockAt destination
6. SellLot x N
7. Wait(NpcDockIdleSeconds)
8. Re-plan at new station

**Fallback:** If no profitable trades, travel to a random connected station and re-plan.

### Miner (faction=0, ships with extractors)

1. Undock from home station
2. TravelTo nearest resource node matching extractor type
3. BeginExtraction
4. WaitForExtraction
5. TravelTo home station (return for safety)
6. DockAt home station
7. SellLot x N (sell extracted resources)
8. Wait(NpcDockIdleSeconds)
9. Re-plan

### UnionPilot (faction=0 or 1, small ships)

1. Scan station for delivery contracts within same sector
2. TakeContract (highest value that fits in cargo)
3. Undock
4. TravelTo contract destination
5. DockAt destination
6. CompleteContract
7. Wait(NpcDockIdleSeconds)
8. Re-plan at new station

**Fallback:** If no contracts, travel to a random station in sector and try there.

## TransactionService

Extract core lot-movement and coin-transfer logic from `DataController.ExecuteTransaction()` into a shared `Services/TransactionService.cs`. Both player HTTP endpoints and NPC planner call the same code.

### Methods
- `BuyLoad(pilotId, lotId, shipId)` — deduct coins, move lot to ship
- `Sell(pilotId, lotId, locationId)` — credit coins, move lot to location
- `Load(pilotId, lotId, shipId)` — move owned lot to ship (free)
- `Unload(pilotId, lotId, locationId)` — move lot from ship to location (free)
- `CompleteDelivery(pilotId, lotId, locationId)` — validate destination, credit contract value, remove lot

DataController becomes a thin wrapper: validate HTTP request, delegate to TransactionService.

## NPC Dock/Undock Mechanics

When the planner processes a `DockAt` task and the ship is within range (50u), it calls the same dock logic players use:
- Zero velocity
- Set ship location in cache
- Grant market access (lots become queryable)

For `Undock`: clear ship location, resume navigation. These are internal calls via TransactionService or a small DockService, not HTTP.

## Completion Detection (per 60s planner tick)

| Task Type | Detection Method |
|-----------|-----------------|
| TravelTo | NpcController current command is Idle |
| DockAt | Ship location set in GameCache |
| Undock | Ship location cleared in GameCache |
| Buy/Sell/Load/Complete | Instant execution during tick |
| BeginExtraction | Instant — starts pipeline |
| WaitForExtraction | Ship extraction state is complete |
| Wait(seconds) | DateTime.UtcNow >= stored expiry |
| Patrol(duration) | Elapsed time >= configured duration |

## Patrol Duration

Patrol tasks have a configurable duration before expiration. Default 10 minutes (`GameConstants.NpcPatrolDurationSeconds = 600`). Can be scaled by NPC traits — higher aggression NPCs patrol longer between activities.

## Stuck NPC Handling

If a task hasn't completed after a configurable timeout (default 5 minutes for navigation tasks, `GameConstants.NpcTaskTimeoutSeconds = 300`), the planner abandons it, clears the queue, and re-plans. Prevents NPCs from getting permanently stuck on unreachable locations.

## Constants

```
GameConstants.NpcDockIdleSeconds = 3600        // 60min station idle
GameConstants.NpcPlannerTickSeconds = 60        // planner tick rate
GameConstants.NpcPatrolDurationSeconds = 600    // 10min patrol duration
GameConstants.NpcTaskTimeoutSeconds = 300       // 5min stuck timeout
```

## Bug Fix: BehaviorType 3

CacheWarmingHostedService currently maps BehaviorType 3 (Merchant) to the default Patrol config. Fix the switch statement to correctly map 3 → NpcBehaviorConfig.Merchant.

## Planner Lifecycle

1. Registered as singleton, injected into SimulationCoordinator
2. After NPC registration, planner initializes each NPC's archetype based on BehaviorType and Faction
3. Ticks every 60s via timer (not tied to physics loop)
4. In-memory only — on restart, all NPCs re-plan from scratch

## Testing

### Unit tests (pure function, no Supabase)

**Archetype planning:**
- CargoBarge at station with known market → correct Buy-Undock-Travel-Dock-Sell-Wait sequence
- Miner at station with nearby node → correct Undock-Travel-Extract-Wait-Travel-Dock-Sell-Wait sequence
- UnionPilot with contracts → correct TakeContract-Undock-Travel-Dock-Complete-Wait sequence
- No trades/contracts available → fallback to random station travel

**Completion detection:**
- Mock NpcController state, assert each task type detects done/not-done correctly
- Stuck timeout → task abandoned, queue cleared, re-plan triggered

**Patrol duration:**
- Patrol task expires after configured duration

**TransactionService:**
- BuyLoad, Sell, Load, CompleteDelivery with mock cache/lots
- Insufficient coins, cargo full, wrong destination validations

### Integration (manual)
- Generate sector with locations + NPCs via admin endpoints
- Observe NPC behavior via logs or diagnostics
- Verify lots actually move, coins change, dock/undock works

## Key Files

### New
- `fleet-inertia.Shared/NpcTask.cs` — task types and queue
- `fleet-inertia.Shared/INpcArchetype.cs` — archetype interface
- `fleet-inertia.Shared/Archetypes/CargoBarge.cs`
- `fleet-inertia.Shared/Archetypes/Miner.cs`
- `fleet-inertia.Shared/Archetypes/UnionPilot.cs`
- `Services/NpcTaskPlanner.cs` — planner service
- `Services/TransactionService.cs` — extracted transaction logic

### Modified
- `Controllers/DataController.cs` — delegate to TransactionService
- `Services/SimulationCoordinator.cs` — integrate NpcTaskPlanner
- `Services/CacheWarmingHostedService.cs` — fix BehaviorType 3 mapping
- `fleet-inertia.Shared/GameConstants.cs` — new NPC constants

### Tests
- `fleet-inertia.Tests/Shared/NpcTaskPlannerTests.cs`
- `fleet-inertia.Tests/Shared/ArchetypeTests.cs`
- `fleet-inertia.Tests/Shared/TransactionServiceTests.cs`
