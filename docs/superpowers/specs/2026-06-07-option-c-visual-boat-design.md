# Option C: Visual-Boot + Authority-Boot — Design Spec

**Datum:** 2026-06-07  
**Status:** Entwurf zur Freigabe vor Implementierung  
**Ziel:** Input fühlt sich instant an, kein sichtbares Zurückziehen, Server bleibt fair für Finish/Kollision/Gegner.

---

## Problem (Ist-Zustand)

Aktuell simulieren Client und Server dasselbe `PhysicsPart` parallel. `reconcileSnapshot()` zieht die Client-Position regelmäßig Richtung Server → sichtbares Rubber-Banding nach jedem Input.

**Ursache:** Zwei Simulatoren + Korrektur auf dem sichtbaren Part.  
**Nicht die Ursache:** Zu viele Module.

---

## Lösung: Zwei Repräsentationen pro Boot

| Repräsentation | Sichtbar für | Bewegt von | Zweck |
|----------------|--------------|------------|-------|
| **Authority-Boot** | Gegner, Server | Server (`BoatPhysics` auf `physicsPart`) | Kollision, Finish-Line, faire Gegner-Sicht |
| **Visual-Boot** | Eigenes Team (lokal) | Client (`BoatPhysics` + CFrame-Integration) | Sofortiges Input-Feedback, nie zurückziehen |

```
Input
  ├─► Visual-Boot (Client)     → sofort, final für Spieler-Feel
  └─► BoatPaddle → Server      → Authority-Boot parallel
                                        ↓
                                  Gegner + Finish nutzen das
```

### Harte Regeln

1. **Visual-Boot wird nie Richtung Server zurückgezogen.**
2. **Authority-Boot wird nie vom Client direkt teleportiert** (außer validierte Checkpoint-Nudge, siehe unten).
3. **Spieler-Charakter folgt dem Visual-Boot** (clientseitig), nicht dem Authority-Boot.
4. **Eigenes Authority-Boot ist für das eigene Team unsichtbar** (Transparency 1 oder LocalTransparencyModifier).

---

## Architektur-Komponenten

### Neu

| Modul | Ort | Verantwortung |
|-------|-----|---------------|
| `BoatVisualService` | `StarterPlayerScripts` (client) | Visual-Klon erstellen/zerstören, Stroke-Sim, RenderStep |
| `BoatCharacterFollower` | `StarterPlayerScripts` (client) | Charakter-Offset relativ zu Visual-Root pro Frame |
| `BoatCheckpoint` | `ReplicatedStorage/Modules` (shared) | Typen + Toleranzen für Server-Abgleich |
| `BoatStateSync` | `ServerStorage/Modules` | Server-seitige Checkpoint-Validierung |

### Geändert

| Modul | Änderung |
|-------|----------|
| `BoatController.client.lua` | Nur Input/Anim/Remotes; Visual-Logik auslagern |
| `BoatController.server.lua` | Snapshots an Client entfernen; Checkpoint-Handler hinzu |
| `BoatService.lua` | `applyCheckpoint()`, Stroke-Queue klar trennen |
| `GameModeService.lua` | Race-Boote `serverAuthority = true`; Visual-Flag an Client |
| `RemoteRegistry.lua` | `BoatCheckpoint` RemoteEvent |
| `PlayerAttachmentService` | Server-Weld bleibt für Init-Position; Client übernimmt Follow |

### Entfernt (nach Migration)

- `reconcileSnapshot()` auf Client
- Server → Client Position-Snapshots (`message == "snapshot"`)
- `integratePredictedCFrame` auf Authority-Part (nur noch auf Visual)

---

## Datenfluss

### Stroke (alle Modi)

1. Client: `sendStroke(side)` → Anim + Visual `applyStroke` sofort
2. Client: `BoatPaddle:FireServer(side, startTime)`
3. Server: validiert → `BoatService.addStroke()` auf Authority-Boot
4. Server: `BoatTeamStroke:FireClient(teammates)` (bestehendes `BoatDriverStroke` umbenennen/semantisch nutzen)
5. Teammate-Client: Stroke auf **Visual-Boot** anwenden (nicht Authority)

### Charakter-Sync (kritisch)

Server-Weld an `physicsPart` bleibt für Spawn/Init. Ab Aktivierung:

- Client löst effektives Mitfahren über `BoatCharacterFollower`
- Jeden RenderStep: `rootPart.CFrame = visualRoot.CFrame * localOffset`
- Server-Weld bleibt, wird aber durch clientseitige CFrame-Setzung überstimmt (PlatformStand bleibt an)

Alternative falls CFrame-Kampf mit Replication: Server-Weld bei Race-Start temporär deaktivieren, nur Client-Follow.

---

## Server-Boot-Korrektur: Bewertung der Ideen

Die Frage: *Soll das Server-Boot periodisch korrigiert werden — nachdem beide gepaddelt haben oder vor dem nächsten Puls?*

### Option 1: Nach jedem Heartbeat-Puls (alle 0.1s) → Server ← Client-Position

| Pro | Contra |
|-----|--------|
| Server bleibt nah am Spieler-Erlebnis | Gegner-Boot kann für andere Spieler ruckeln |
| Einfach zu implementieren | Hohes Cheat-Risiko wenn blind übernommen |
| | Würde alten Snapshot-Bug nur auf Authority verlagern |

**Bewertung: ❌ Nicht empfohlen** als direkte Positionsübernahme.

---

### Option 2: Nachdem „beide Teammitglieder gepaddelt haben“

| Pro | Contra |
|-----|--------|
| Klingt fair für 2v2 | Triggert nie in Modus 1/2 (Solo) |
| | Ein Spieler paddelt dauerhaft → nie Sync |
| | Schwer zu definieren („beide“ = ein Stroke je? gleichzeitig?) |
| | Modus 4: 2 Spieler, aber asymmetrisches Paddeln |

**Bewertung: ❌ Nicht als Haupt-Trigger.** Höchstens als Zusatz-Signal in Team-Modi.

---

### Option 3: Stroke-Event-Sync only (Server simuliert dieselben Strokes)

| Pro | Contra |
|-----|--------|
| Deterministisch, kein Positions-Cheat | Client nutzt extra CFrame-Integration → leichter Drift |
| Gegner sehen glatte Authority-Bewegung | Finish kann leicht hinter Visual liegen |

**Bewertung: ✅ Pflicht-Basis.** Immer zuerst.

---

### Option 4: Checkpoint nur an Stroke-Grenzen (empfohlen)

**Trigger:** Wenn auf dem Client **keine aktiven Strokes mehr** (`progress >= 1` für alle), sendet der **Driver** einen Checkpoint:

```lua
{
  boatId: string,
  serverTime: number,
  cframe: CFrame,
  linearVelocity: Vector3,
  angularVelocity: Vector3,
  strokeCount: number,  -- wie viele Strokes seit Session-Start
}
```

**Server-Verhalten:**

1. Berechne erwartete Position aus Server-Stroke-History (`BoatPhysics` replay oder aktueller Server-State).
2. `delta = |clientPos - serverPos|`
3. Wenn `delta <= CHECKPOINT_SOFT_LIMIT` (z. B. 4 Studs): Server nudged sanft (Lerp 30 %), **nur Authority-Boot**.
4. Wenn `delta <= CHECKPOINT_HARD_LIMIT` (z. B. 12 Studs): Server übernimmt Position einmalig.
5. Wenn `delta > CHECKPOINT_HARD_LIMIT`: Ignorieren + warnen (Anti-Cheat).

**Wichtig:** Checkpoint beeinflusst **niemals** das Visual-Boot.

| Pro | Contra |
|-----|--------|
| Kein Rubber-Banding für Spieler | Etwas mehr Netzwerk |
| Server/Finish näher am Erlebten | Braucht Tuning |
| Nur an ruhigen Momenten → kein Mid-Stroke-Ruckler für Gegner | Driver muss Checkpoint senden |

**Bewertung: ✅ Empfohlen** als sekundärer Sync neben Stroke-Events.

---

### Option 5: Vor nächstem Server-Puls Authority intern konsolidieren

**Trigger:** Am Ende jedes Server-Heartbeat-Ticks, **bevor** neue Strokes reinkommen:

- Server beendet `BoatPhysics.apply` für alle aktiven Strokes
- Wenn **keine aktiven Strokes**: optional wartende Checkpoints verarbeiten
- Kein Client-Snapshot ohne Checkpoint-Event

| Pro | Contra |
|-----|--------|
| Deterministische Server-Simulation | Allein löst Drift-Problem nicht |
| Guter Ort um Checkpoints zu verarbeiten | |

**Bewertung: ✅ Empfohlen** als Zeitpunkt zur Verarbeitung, nicht als Korrektur-Quelle.

---

## Gewählte Sync-Strategie (Finale Empfehlung)

```
Primär:   Stroke-Events mit GetServerTimeNow() → Server + Visual parallel
Sekundär: Checkpoint vom Driver an Stroke-Grenzen (idle)
Zeitpunkt: Server verarbeitet Checkpoints am Heartbeat, nur wenn idle
Niemals:  Visual ← Server
Niemals:  Blindes Server ← Client jeden Puls
```

### Warum nicht „beide gepaddelt“?

Team-Stroke-Broadcast deckt Teammate-Input bereits ab. Der Server hat alle Strokes. Ein extra Trigger „beide waren aktiv“ ist redundant und unvollständig für Solo-Modi.

### Warum Checkpoint an Stroke-Grenzen?

- Mid-Stroke: Server und Visual sind **absichtlich** an verschiedenen Phasen → Sync wäre falsch
- Stroke-Ende: natürlicher Ruhepunkt, Gegner sehen höchstens kleinen Authority-Nudge
- Finish-Line: Authority ist näher am, was Spieler auf Visual erlebt haben

---

## Modus-Verhalten

| Modus | Visual | Authority | Checkpoint-Sender |
|-------|--------|-----------|---------------------|
| 1 Solo | 1 Spieler | Server | Der Spieler |
| 2 1v1 | je Spieler eigenes Visual | je Boot Server | jeweiliger Spieler |
| 3 2v2 | je Team gemeinsames Visual-Konzept pro Boot | Server | Driver (Index 1) |
| 4 2er Team | wie 3 | Server | Driver |

Teammates: erhalten Strokes per Broadcast, wenden auf **dasselbe** Visual-Boot an (gleiche `boatId`).

---

## Gegner-Sicht

- Gegner sehen **Authority-Boot** (normale Replication).
- Leichte Verzögerung akzeptiert.
- Checkpoint-Nudges auf Authority sollten klein sein (< 4 Studs typisch) → für Gegner kaum sichtbar.

---

## Finish & Kollision

- **Finish:** `Touched` auf Authority-Parts (bestehend).
- **UX-Regel:** Wenn Visual Ziel visuell erreicht, Authority aber noch nicht: kein Fake-Finish. Optional UI-Hinweis „Ziel wird registriert…“ wenn `delta > 0`.
- **Kollision:** Authority entscheidet. Visual darf kurz in Wand clippen; bei Server-Kollision Stroke-Cancel oder Visual-Stop **ohne** Zurückspringen.

---

## Risiken & Mitigation

| Risiko | Mitigation |
|--------|------------|
| Charakter löst sich vom Boot | `BoatCharacterFollower` RenderStep, hohe Priorität |
| Visual weit vor Authority | Checkpoint an Stroke-Grenzen + Hard-Limit |
| Cheat (falsche Checkpoint-Pos) | Delta-Validierung gegen Server-Stroke-State |
| Doppelte Boot-Models teuer | Visual nur für aktives Team, Cleanup bei Session-Ende |
| Remote-Chaos | `BoatDriverStroke` → Team-Strokes; neues `BoatCheckpoint` für Sync |

---

## Erfolgskriterien

1. Eigener Input: Boot bewegt sich **im selben Frame** sichtbar.
2. **Kein** sichtbares Zurückziehen nach Input.
3. Teammate-Stroke: auf eigenem Screen < 1 Frame + Netzwerk zum Teammate.
4. Gegner-Boot: flüssig, leicht verzögert OK.
5. Finish löst aus, wenn Authority-Boot Ziel berührt (max. ~4 Studs hinter Visual).
6. Modus 1–4 ohne separate Sonderpfade pro Modus.

---

## Nicht im Scope (YAGNI)

- Vollständiges Anti-Cheat-System
- Replay/rollback netcode
- Separate Ghost-Boote pro Spieler im selben Team (ein Visual pro Boot reicht)

---

## Freigabe

Nach Review dieser Spec → Implementierung gemäß Plan in `docs/superpowers/plans/2026-06-07-option-c-visual-boat.md`.
