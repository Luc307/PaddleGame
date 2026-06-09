local BoatConfig = require(script.Parent.BoatConfig)
local BoatPhysics = require(script.Parent.BoatPhysics)

export type AuthorityStatePayload = {
	boatId: string,
	serverTime: number,
	cframe: CFrame,
	linearVelocity: Vector3,
	angularVelocity: Vector3,
	strokeCount: number,
}

export type AuthorityTarget = {
	cframe: CFrame,
	linearVelocity: Vector3,
	angularVelocity: Vector3,
	strokeCount: number,
}

local BoatAuthoritySync = {}

function BoatAuthoritySync.evaluateDelta(
	serverCFrame: CFrame,
	clientCFrame: CFrame
): (number, boolean, boolean)
	local delta = (serverCFrame.Position - clientCFrame.Position).Magnitude
	local canSync = delta <= BoatConfig.SYNC_MAX_DELTA
	local shouldReject = delta > BoatConfig.REJECT_DELTA
	return delta, canSync, shouldReject
end

function BoatAuthoritySync.payloadToTarget(payload: AuthorityStatePayload): AuthorityTarget
	return {
		cframe = payload.cframe,
		linearVelocity = payload.linearVelocity,
		angularVelocity = payload.angularVelocity,
		strokeCount = payload.strokeCount,
	}
end

function BoatAuthoritySync.copyState(state: BoatPhysics.KinematicState): BoatPhysics.KinematicState
	return {
		cframe = state.cframe,
		linearVelocity = state.linearVelocity,
		angularVelocity = state.angularVelocity,
	}
end

function BoatAuthoritySync.alignState(
	target: BoatPhysics.KinematicState,
	source: BoatPhysics.KinematicState
)
	target.cframe = source.cframe
	target.linearVelocity = source.linearVelocity
	target.angularVelocity = source.angularVelocity
end

function BoatAuthoritySync.applyIdleNudge(
	state: BoatPhysics.KinematicState,
	target: AuthorityTarget
): boolean
	local delta = (state.cframe.Position - target.cframe.Position).Magnitude
	if delta > BoatConfig.SYNC_MAX_DELTA or delta < BoatConfig.RETARGET_MIN_UPDATE_DELTA then
		return false
	end

	local blend = BoatConfig.RETARGET_IDLE_NUDGE_BLEND
	state.cframe = state.cframe:Lerp(target.cframe, blend)
	state.linearVelocity = state.linearVelocity:Lerp(target.linearVelocity, blend)
	state.angularVelocity = state.angularVelocity:Lerp(target.angularVelocity, blend)
	return true
end

return BoatAuthoritySync
