# Option C: Visual-Boot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spieler sehen ein sofort reagierendes Visual-Boot ohne Rubber-Banding; Server-Authority-Boot bleibt für Finish, Kollision und Gegner-Sicht fair.

**Architecture:** Client klont ein lokales Visual-Boot und simuliert dort alle Strokes. Server simuliert parallel das echte Boot nur aus Stroke-Events. Checkpoints an Stroke-Grenzen dürfen das Server-Boot leicht nachjustieren — niemals das Visual-Boot. Charakter folgt clientseitig dem Visual-Root.

**Tech Stack:** Roblox Luau, RunService RenderStep/Heartbeat, bestehende `BoatPhysics`/`BoatConfig`, RemoteEvents.

**Design-Spec:** `docs/superpowers/specs/2026-06-07-option-c-visual-boat-design.md`

---

## Datei-Übersicht

| Aktion | Datei |
|--------|-------|
| Create | `src/ReplicatedStorage/Modules/BoatCheckpoint.lua` |
| Create | `src/StarterPlayer/StarterPlayerScripts/BoatVisualService.client.lua` |
| Create | `src/StarterPlayer/StarterPlayerScripts/BoatCharacterFollower.client.lua` |
| Create | `src/ServerStorage/Modules/BoatStateSync.lua` |
| Modify | `src/ReplicatedStorage/Modules/RemoteRegistry.lua` |
| Modify | `src/StarterPlayer/StarterPlayerScripts/BoatController.client.lua` |
| Modify | `src/ServerScriptService/BoatController.server.lua` |
| Modify | `src/ServerStorage/Modules/BoatService.lua` |
| Modify | `src/ServerStorage/Modules/GameMode/GameModeService.lua` |
| Studio | `ReplicatedStorage/Remotes/Events/BoatCheckpoint` (RemoteEvent) |

---

## Phase 0: Aufräumen des fehlerhaften Hybrid-Systems

### Task 0: Alte Reconciliation entfernen

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/BoatController.client.lua`
- Modify: `src/ServerScriptService/BoatController.server.lua`

- [ ] **Step 1:** In `BoatController.client.lua` entfernen:
  - `SNAPSHOT_*` Konstanten
  - `BoatSnapshot` type
  - `latestSnapshot`
  - `getProjectedSnapshot`, `reconcileSnapshot`
  - `integratePredictedCFrame` auf `physicsPart`
  - Handler-Zweig `message == "snapshot"`

- [ ] **Step 2:** In `BoatController.server.lua` entfernen:
  - `SNAPSHOT_INTERVAL`, `snapshotAccumulator`
  - `sendBoatSnapshot`, `broadcastSnapshots`
  - Heartbeat-Snapshot-Loop

- [ ] **Step 3:** Manuell in Studio testen — Boot soll sich noch bewegen (auch wenn noch nicht optimal), aber **kein** Zurückziehen mehr durch Snapshots.

---

## Phase 1: Shared Checkpoint-Kontrakt

### Task 1: `BoatCheckpoint` Modul

**Files:**
- Create: `src/ReplicatedStorage/Modules/BoatCheckpoint.lua`

- [ ] **Step 1:** Modul mit Konstanten und Payload-Typ anlegen:

```lua
export type CheckpointPayload = {
	boatId: string,
	serverTime: number,
	cframe: CFrame,
	linearVelocity: Vector3,
	angularVelocity: Vector3,
	strokeCount: number,
}

local BoatCheckpoint = {
	SOFT_LIMIT = 4,
	HARD_LIMIT = 12,
	SOFT_BLEND = 0.3,
}

function BoatCheckpoint.isIdle(strokes, now, strokeDuration): boolean
	-- true wenn keine Stroke progress < 1
end

return BoatCheckpoint
```

- [ ] **Step 2:** `isIdle` implementieren — true nur wenn alle Strokes abgelaufen.

---

### Task 2: Remote registrieren

**Files:**
- Modify: `src/ReplicatedStorage/Modules/RemoteRegistry.lua`
- Studio: neues `BoatCheckpoint` RemoteEvent unter `Remotes/Events`

- [ ] **Step 1:** In Studio `BoatCheckpoint` RemoteEvent erstellen (Reliable).

- [ ] **Step 2:** In `RemoteRegistry.lua` eintragen:

```lua
BoatCheckpoint = eventsFolder:WaitForChild("BoatCheckpoint") :: RemoteEvent,
```

---

## Phase 2: Server Authority + Checkpoint-Verarbeitung

### Task 3: `BoatStateSync` Server-Modul

**Files:**
- Create: `src/ServerStorage/Modules/BoatStateSync.lua`
- Modify: `src/ServerStorage/Modules/BoatService.lua`

- [ ] **Step 1:** `BoatService` erweitern:

```lua
function BoatService.getStrokeCount(boat): number
function BoatService.applyCheckpoint(boat, payload): (applied: boolean, reason: string?)
```

- [ ] **Step 2:** `applyCheckpoint` Logik:
  1. `expected` = aktueller Server-State nach `BoatPhysics`
  2. `delta` = Position-Distanz
  3. `delta <= SOFT_LIMIT` → Lerp Authority-Part mit `SOFT_BLEND`
  4. `delta <= HARD_LIMIT` → Authority-Part hart setzen
  5. `delta > HARD_LIMIT` → reject

- [ ] **Step 3:** `BoatStateSync.lua` — dünner Wrapper, ruft `BoatService.applyCheckpoint` auf, prüft ob Spieler Occupant + Driver ist.

---

### Task 4: Server Controller anbinden

**Files:**
- Modify: `src/ServerScriptService/BoatController.server.lua`

- [ ] **Step 1:** `BoatCheckpoint.OnServerEvent` Handler:

```lua
BoatCheckpointEvent.OnServerEvent:Connect(function(player, payload)
	-- validate types, boat, driver-only, idle optional
	BoatStateSync.tryApply(player, payload)
end)
```

- [ ] **Step 2:** Stroke-Broadcast behalten (`BoatDriverStroke` an Teammates), aber **keine** Position-Snapshots mehr.

- [ ] **Step 3:** Server-Heartbeat in `BoatService` bleibt für Authority-Physik (`serverAuthority = true` für Race-Boote).

---

### Task 5: GameMode Race-Boote

**Files:**
- Modify: `src/ServerStorage/Modules/GameMode/GameModeService.lua`

- [ ] **Step 1:** Sicherstellen `serverAuthority = true` in `createTeams`.

- [ ] **Step 2:** `BoatControl:FireClient` erweitern um Flag `useVisualBoat = true` für Race-Sessions (5. Parameter oder Tabelle).

---

## Phase 3: Client Visual-Boot

### Task 6: `BoatVisualService`

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/BoatVisualService.client.lua`

- [ ] **Step 1:** API definieren:

```lua
BoatVisualService.start(boatId: string, sourceModel: Model): VisualHandle?
BoatVisualService.stop(boatId: string)
BoatVisualService.applyStroke(boatId: string, side: string, startTime: number)
BoatVisualService.getRoot(boatId: string): BasePart?
BoatVisualService.isIdle(boatId: string): boolean
BoatVisualService.getCheckpoint(boatId: string): CheckpointPayload?
```

- [ ] **Step 2:** `start()` — Boot klonen:
  - Parent: `workspace.CurrentCamera` oder `player.PlayerScripts` Folder
  - Alle Parts: `CanCollide = false`, `CanQuery = false`, `Anchored = true` (rein kinematic)
  - Echtes Boot (Authority) für eigenes Team: `LocalTransparencyModifier = 1` auf alle BaseParts

- [ ] **Step 3:** RenderStep-Loop pro aktives Visual:
  - `BoatPhysics.apply(visualRoot, strokes, GetServerTimeNow(), dt, BoatConfig)`
  - `visualModel:PivotTo(...)` aus Root-CFrame + Integration
  - **Kein** Server-Snapshot-Lerp

- [ ] **Step 4:** `stop()` — Visual destroy, Transparency reset.

---

### Task 7: `BoatCharacterFollower`

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/BoatCharacterFollower.client.lua`
- Modify: `src/ServerStorage/Modules/GameMode/GameModeService.lua` (Offset-Info an Client senden)

- [ ] **Step 1:** Beim `BoatControl`-Activate Offset speichern (aus `getAttachmentOffset` Logik — Werte als Remote-Payload oder fest aus `teamControls` + `index` ableiten).

- [ ] **Step 2:** RenderStep (nach Visual-Update):

```lua
rootPart.CFrame = visualRoot.CFrame * localOffset
```

- [ ] **Step 3:** Bei Deactivate Follow stoppen.

- [ ] **Step 4:** Falls Server-Weld Replication kämpft: `PlatformStand = true` beibehalten, Weld auf Server ignorieren (client CFrame setzt durch).

---

### Task 8: `BoatController.client` umbauen

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/BoatController.client.lua`

- [ ] **Step 1:** `sendStroke` ändern:

```lua
playStrokeAnim(side)
BoatVisualService.applyStroke(activeBoatId, side, startTime)
BoatPaddleEvent:FireServer(side, startTime)
```

- [ ] **Step 2:** `activateControl` — wenn `useVisualBoat`:
  - `BoatVisualService.start(boatId, workspace model)`
  - `BoatCharacterFollower.start(visualRoot, offset)`
  - **Kein** `physicsPart` / RenderStep auf Authority-Part

- [ ] **Step 3:** `deactivateControl` — Visual + Follower stoppen.

- [ ] **Step 4:** `BoatDriverStroke` Handler — Strokes auf `BoatVisualService.applyStroke` (nicht Authority).

- [ ] **Step 5:** Checkpoint-Sender (nur Driver):

```lua
-- am Ende von updateVisual oder eigener Heartbeat:
if isDriver and BoatVisualService.isIdle(boatId) then
	BoatCheckpointEvent:FireServer(BoatVisualService.getCheckpoint(boatId))
end
```

Sende Checkpoint **max. 1× pro Idle-Phase** (Debouncing), nicht spam pro Frame.

---

## Phase 4: Server-Sync-Zeitpunkt (entscheidung aus Spec)

### Task 9: Checkpoint-Timing implementieren

**Files:**
- Modify: `src/ServerStorage/Modules/BoatService.lua`
- Modify: `src/ServerScriptService/BoatController.server.lua`

- [ ] **Step 1:** Server verarbeitet eingehende Checkpoints **sofort** im `OnServerEvent` (nicht batching nötig).

- [ ] **Step 2:** Zusätzlich am Heartbeat-Ende: wenn Authority-Boot idle und Checkpoint in Queue → verarbeiten. (Optional, nur wenn Client-Checkpoint verloren geht.)

- [ ] **Step 3:** **Nicht** implementieren: Sync „wenn beide gepaddelt haben“.

- [ ] **Step 4:** **Nicht** implementieren: blindes Server-Sync jeden Puls ohne Checkpoint-Payload.

---

## Phase 5: Testplan

### Task 10: Manuelle Verifikation in Studio

- [ ] **Modus 1:** Solo paddeln → sofortige Bewegung, kein Zurück, Finish funktioniert.
- [ ] **Modus 2:** 1v1 → beide sehen eigenes Visual instant, Gegner-Boot leicht verzögert.
- [ ] **Modus 3:** 2v2 Team → beide Paddles (Space) bewegen Visual instant; kein Rubber-Band.
- [ ] **Modus 4:** 2er Team vs Parkour → wie Modus 3.
- [ ] **Charakter:** bleibt auf Visual-Boot, kein „Schweben weg“.
- [ ] **Checkpoint:** nach Stroke-Ende Authority max. wenige Studs hinter Visual.
- [ ] **Gegner-Sicht:** kein starkes Ruckeln beim Authority-Nudge.

---

## Implementierungsreihenfolge (empfohlen)

```
Phase 0  → sofort besseres Feel (kein Zurück)
Phase 1  → Checkpoint-Kontrakt
Phase 2  → Server
Phase 3  → Visual + Character
Phase 4  → Sync-Timing
Phase 5  → Test
```

Geschätzter Aufwand: **1 Session** für Phase 0–2, **1 Session** für Phase 3–5.

---

## Entscheidungsmatrix: Server-Boot-Korrektur

| Strategie | Empfehlung | Grund |
|-----------|------------|-------|
| Visual ← Server (aktuell) | ❌ Entfernen | Rubber-Banding |
| Server ← Client jeden Puls | ❌ | Cheat + Gegner-Ruckler |
| Server ← Client wenn „beide gepaddelt“ | ❌ | Lücken in Solo/asymmetrischem Paddeln |
| Nur Stroke-Events | ✅ Basis | Deterministisch |
| Checkpoint an Stroke-Grenzen | ✅ Zusatz | Finish näher am Erlebnis, kein Visual-Einfluss |
| Checkpoint-Verarbeitung am Heartbeat wenn idle | ✅ Optional | Robustheit |

---

## Execution Options

**Plan complete and saved to `docs/superpowers/plans/2026-06-07-option-c-visual-boat.md`.**

1. **Subagent-Driven** — frischer Subagent pro Task, Review zwischen Tasks
2. **Inline Execution** — alles in dieser Session, Phase für Phase

Welche Variante soll als Nächstes starten?
