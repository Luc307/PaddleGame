-- Eine Config fuer Boot, Paddel und Rennen. Server nutzt nur Bewegung/Auftrieb/Spawn.
local PaddleConfig = {

	-- === Client: Paddel-Animation ===

	-- rbxassetid der linken Paddel-Animation (nil = kein Track)
	PADDLE_LEFT_ANIM_ID = nil :: string?,

	-- rbxassetid der rechten Paddel-Animation (nil = kein Track)
	PADDLE_RIGHT_ANIM_ID = nil :: string?,

	-- Dauer einer Paddel-Animation in Sekunden (nur Client-Anzeige)
	STROKE_ANIM_DURATION = 0.5,

	-- Anim-Speed beim Spam-Paddeln im Solo-Modus (1.5 = 50 % schneller)
	SPAM_ANIM_SPEED_MULTIPLIER = 1.5,

	-- === Server: Bewegung pro Paddelschlag ===

	-- Horizontale Geschwindigkeit die pro Schlag addiert wird (studs/s)
	STROKE_FORWARD_SPEED = 100,

	-- Drehgeschwindigkeit pro Schlag um Y-Achse (Radiant/s; links = negativ)
	STROKE_TURN_SPEED = math.rad(105),

	-- Max horizontale Geschwindigkeit (studs/s)
	MAX_HORIZONTAL_SPEED = 150,

	-- Mindestabstand zwischen zwei Schlägen pro Spieler (Sekunden; niedrig = fluessiger Spam)
	STROKE_COOLDOWN = 0.1,

	-- Horizontale Abbremsung pro Sekunde wenn nicht gepaddelt wird (hoeher = stoppt schneller)
	COAST_DRAG = 1.2,

	-- === Server: Wasser ===

	-- Y-Hoehe der Wasseroberflaeche (wird von Part "WaterSurface" ueberschrieben falls vorhanden)
	WATER_SURFACE_Y = 0,

	-- Staerke des Auftriebs (zu niedrig = sinkt, zu hoch = hüpft)
	BUOYANCY_STRENGTH = 6000,

	-- === Rennen: Spawn ===

	-- Offset vom Start-Part bis Boot-Spawn
	RACE_SPAWN_SEAT_OFFSET = CFrame.new(0, 2, 0),

	-- Boot beim Spawn um 180 Grad drehen (math.pi)
	RACE_SPAWN_YAW = math.pi,

	-- Vertikaler Abstand zwischen Team-Spawns (studs)
	RACE_SPAWN_TEAM_Y_STEP = 0.2,
}

return PaddleConfig
