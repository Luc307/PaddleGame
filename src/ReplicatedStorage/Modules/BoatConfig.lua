-- Shared tuning (client prediction + server validation). Werte nicht aendern ohne Absicht.
local BoatConfig = {
	STROKE_DURATION = 0.28,
	STROKE_FORWARD_SPEED = 58,
	STROKE_TURN_SPEED = math.rad(125),
	LINEAR_DRAG = 0.1,
	ANGULAR_DRAG = 0.7,
	STROKE_COOLDOWN = 0,
}

return BoatConfig
