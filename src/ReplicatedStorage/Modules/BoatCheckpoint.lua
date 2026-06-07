local BoatConfig = require(script.Parent.BoatConfig)
local BoatPhysics = require(script.Parent.BoatPhysics)

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

function BoatCheckpoint.isIdle(strokes: { BoatPhysics.Stroke }, now: number): boolean
	if #strokes == 0 then
		return true
	end

	for _, stroke in strokes do
		local progress = (now - stroke.startTime) / BoatConfig.STROKE_DURATION
		if progress < 1 then
			return false
		end
	end

	return true
end

return BoatCheckpoint
