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
	SOFT_LIMIT = BoatConfig.SYNC_MAX_DELTA,
	HARD_LIMIT = BoatConfig.REJECT_DELTA,
	SOFT_BLEND = 0.3,
}

function BoatCheckpoint.evaluateDelta(serverCFrame: CFrame, clientCFrame: CFrame): (number, boolean, boolean)
	local delta = (serverCFrame.Position - clientCFrame.Position).Magnitude
	local canSync = delta <= BoatConfig.SYNC_MAX_DELTA
	local shouldReject = delta > BoatConfig.REJECT_DELTA
	return delta, canSync, shouldReject
end

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
