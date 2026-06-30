-- Eine Config fuer Boot, Paddel und Rennen. Server nutzt nur Bewegung/Auftrieb/Spawn.
local PaddleConfig = {

	-- === Client: Paddel-Animationen ===

	-- Sitzen im Boot (Loop, Beine/Torso)
	PADDLE_SIT_IDLE_ANIM_ID = "rbxassetid://73154682552358",

	-- Paddel halten (Loop, Arme — laeuft unter Schlag-Animationen weiter)
	PADDLE_STATIC_ANIM_ID = "rbxassetid://77595711680956",

	PADDLE_LEFT_ANIM_ID = "rbxassetid://86777586594876",
	PADDLE_RIGHT_ANIM_ID = "rbxassetid://90913049827987",

	-- Schlag-Animation: 1 = Originalgeschwindigkeit. Nur Spam nutzt SPAM_ANIM_SPEED_MULTIPLIER.
	STROKE_ANIM_SPEED = 1,

	-- Fallback-Dauer falls Animationslaenge noch unbekannt (Sekunden)
	STROKE_ANIM_DURATION = 1.0,

	-- Anim-Speed beim Spam-Paddeln im Solo-Modus (1.5 = 50 % schneller)
	SPAM_ANIM_SPEED_MULTIPLIER = 1.5,

	-- === Paddel-Modell ===

	-- Name des Paddel-Modells in ReplicatedStorage.Replications
	PADDLE_MODEL_NAME = "Paddle",

	-- Oberer Griff (HandleStart) — haelt die Oberhand je nach Schlagseite
	PADDLE_TOP_GRIP_PART_NAME = "HandleStart",

	-- Mitte des Schafts (MainHandle) — haelt die untere Hand / Pivot
	PADDLE_PIVOT_GRIP_PART_NAME = "MainHandle",

	-- Motor6D C0 nach GripAttachment
	PADDLE_TOP_GRIP_OFFSET = CFrame.new(0, 0, 0),
	PADDLE_PIVOT_GRIP_OFFSET = CFrame.new(0, 0, 0),

	-- Initial-Griff beim Einsteigen (right: RH oben, LH Mitte)
	PADDLE_DEFAULT_SIDE = "right",

	-- === Character-Anker am Boot ===

	-- Offset vom Seat-Anker zum HumanoidRootPart (sitzend, nicht stehend)
	-- Seat-Part im Boot = Position wo HRP beim Sitzen sein soll
	SEAT_CHARACTER_OFFSET = CFrame.new(0, 0, 0),

	-- === Server: Bewegung pro Paddelschlag ===

	STROKE_FORWARD_SPEED = 175,
	STROKE_TURN_SPEED = math.rad(120),
	MAX_HORIZONTAL_SPEED = 230,
	STROKE_COOLDOWN = 0.1,
	COAST_DRAG = 1.2,

	-- Anteil der Schlag-Anim bis Vorwaerts-Impuls (0.45 = Wasserphase, Anim startet sofort)
	STROKE_IMPULSE_DELAY_FRACTION = 0.45,

	-- === Server: Wasser ===

	WATER_SURFACE_Y = 0,
	BUOYANCY_STRENGTH = 6000,

	-- === Rennen: Spawn ===

	RACE_SPAWN_SEAT_OFFSET = CFrame.new(0, 2, 0),
	RACE_SPAWN_YAW = math.pi,
	RACE_SPAWN_TEAM_Y_STEP = 0.2,
}

return PaddleConfig
