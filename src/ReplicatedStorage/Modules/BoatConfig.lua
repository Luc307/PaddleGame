-- Shared tuning (client prediction + server validation). Werte nicht aendern ohne Absicht.
local BoatConfig = {
	FIXED_TIMESTEP = 1 / 60,
	STROKE_DURATION = 0.28,
	STROKE_FORWARD_SPEED = 58,
	STROKE_TURN_SPEED = math.rad(125),
	LINEAR_DRAG = 0.1,
	ANGULAR_DRAG = 0.7,
	COAST_LINEAR_DRAG = 7,
	COAST_ANGULAR_DRAG = 9,
	VELOCITY_STOP_THRESHOLD = 0.4,
	STROKE_COOLDOWN = 0,
	-- Seat wird auf Starts/ModeX ausgerichtet (nicht Modell-Pivot). X/Z bei Bedarf tunen.
	RACE_SPAWN_SEAT_OFFSET = CFrame.new(0, 2, 0),
	RACE_SPAWN_YAW = math.pi,
	RACE_SPAWN_TEAM_Y_STEP = 0.2,
	-- true = Authority-Boot sichtbar (Debug), false = nur Visual-Boot
	TEST = false,
	SYNC_MAX_DELTA = 4,
	REJECT_DELTA = 12,
	RETARGET_POSITION_EPSILON = 0.15,
	RETARGET_MIN_UPDATE_DELTA = 0.08,
	RETARGET_IDLE_NUDGE_BLEND = 0.2,
}

return BoatConfig
