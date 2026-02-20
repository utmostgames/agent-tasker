# Process Isolation Phase 2a — Coordinator Facade

## Overview
Eliminate all direct `SectorSimulation` access from controllers and services. After this refactoring, only `SimulationCoordinator` touches `SectorSimulation` instances. Pure refactoring — no behavioral changes.

## Problem
7 call sites bypass the coordinator and call `SectorSimulation` methods directly via `_coordinator.GetSector(id).Method()`:

| File | Method | Sector Method | New Facade Method |
|------|--------|---------------|-------------------|
| DataController.cs:700 | ExecuteExtract | `StartExtraction()` | `coordinator.StartExtraction(shipId, nodeId, type, capacity)` |
| DataController.cs:760 | ExecuteHyJump | `GetShipJump()` | `coordinator.GetShipJump(shipId)` — already exists but unused here |
| DataController.cs:834 | ExecuteMultiJump | `GetShipJump()` | Same as above |
| SalvageController.cs:59 | Pickup | `GetSalvageEntry()` | `coordinator.GetSalvageEntry(sectorId, salvageId)` |
| SalvageController.cs | Pickup | `UnregisterSalvage()` | `coordinator.UnregisterSalvage(sectorId, salvageId)` |
| NetworkService.cs:363 | HandlePlayerRegistration | `SpatialMap.UpdateConnectionId()` | `coordinator.UpdateShipConnectionId(sectorId, shipId, connId)` |
| NetworkService.cs:419 | OnSectorTickCompleted | `GetBroadcastSnapshot()` | `coordinator.GetBroadcastSnapshot(sectorId)` |
| NetworkService.cs:179 | GetConnectionDiagnostics | `GetShipState()` | Already available via `coordinator.GetShipState()` |

## New Coordinator Methods

### 1. `StartExtraction(Guid shipId, Guid nodeId, ExtractorType extractorType, int capacity) → bool`
- Look up sector from `_shipToSector[shipId]`
- Delegate to `sector.StartExtraction(shipId, nodeId, extractorType, capacity)`

### 2. `GetShipJump(Guid shipId) → int?`
- Already exists but may not be used consistently
- Look up sector, delegate to `sector.GetShipJump(shipId)`

### 3. `GetSalvageEntry(Guid sectorId, Guid salvageId) → SalvageEntry?`
- Look up sector from `_sectors[sectorId]`
- Delegate to `sector.GetSalvageEntry(salvageId)`

### 4. `UnregisterSalvage(Guid sectorId, Guid salvageId)`
- Look up sector, delegate to `sector.UnregisterSalvage(salvageId)`

### 5. `UpdateShipConnectionId(Guid sectorId, Guid shipId, string connectionId)`
- Look up sector, delegate to `sector.SpatialMap.UpdateConnectionId(shipId, connectionId)`

### 6. `GetBroadcastSnapshot(Guid sectorId) → SectorSnapshot?`
- Look up sector, delegate to `sector.GetBroadcastSnapshot()`

## Files Modified
- `Services/SimulationCoordinator.cs` — add 6 new facade methods
- `Controllers/DataController.cs` — replace 3 direct accesses with coordinator calls
- `Controllers/SalvageController.cs` — replace 2 direct accesses with coordinator calls
- `Services/NetworkService.cs` — replace 2 direct accesses with coordinator calls

## Verification
- All existing tests must pass (954 tests, 0 regressions)
- No controller or service imports `SectorSimulation` type directly (except coordinator)
- Grep for `GetSector(` in controllers/services should return 0 hits after refactoring
