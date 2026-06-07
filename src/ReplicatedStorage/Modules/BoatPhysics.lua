local BoatConfig = require(script.Parent.BoatConfig)

export type PaddleSide = "left" | "right"

export type Stroke = {
	side: PaddleSide,
	startTime: number,
}

export type KinematicState = {
	cframe: CFrame,
	linearVelocity: Vector3,
	angularVelocity: Vector3,
}

local ENVELOPE_POWER = 0.65

local function computeEnvelopeIntegral(): number
	local sum = 0
	local steps = 200
	for i = 0, steps - 1 do
		local t = (i + 0.5) / steps
		sum += math.sin(math.pi * t) ^ ENVELOPE_POWER / steps
	end
	return sum
end

local ENVELOPE_INTEGRAL = computeEnvelopeIntegral()

local BoatPhysics = {}

function BoatPhysics.getForwardVector(seat: BasePart): Vector3
	local look = seat.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.zero
	end
	return flat.Unit
end

function BoatPhysics.strokeEnvelope(progress: number): number
	return math.sin(math.pi * math.clamp(progress, 0, 1)) ^ ENVELOPE_POWER
end

function BoatPhysics.apply(
	seat: BasePart,
	strokes: { Stroke },
	now: number,
	dt: number,
	config: typeof(BoatConfig)
): { Stroke }
	local forward = BoatPhysics.getForwardVector(seat)
	local addLinear = Vector3.zero
	local addYaw = 0

	local stillActive: { Stroke } = {}
	for _, stroke in strokes do
		local elapsed = now - stroke.startTime
		local progress = elapsed / config.STROKE_DURATION
		if progress < 1 then
			table.insert(stillActive, stroke)

			local envelope = BoatPhysics.strokeEnvelope(progress)
			local rate = envelope / (ENVELOPE_INTEGRAL * config.STROKE_DURATION)
			local frameSpeed = config.STROKE_FORWARD_SPEED * rate * dt
			local frameTurn = config.STROKE_TURN_SPEED * rate * dt

			addLinear += forward * frameSpeed

			if stroke.side == "right" then
				addYaw += frameTurn
			else
				addYaw -= frameTurn
			end
		end
	end

	local v = seat.AssemblyLinearVelocity
	local horiz = Vector3.new(v.X, 0, v.Z)
	horiz *= math.clamp(1 - config.LINEAR_DRAG * dt, 0, 1)
	horiz += addLinear
	seat.AssemblyLinearVelocity = Vector3.new(horiz.X, v.Y, horiz.Z)

	local w = seat.AssemblyAngularVelocity
	local yaw = w.Y * math.clamp(1 - config.ANGULAR_DRAG * dt, 0, 1)
	yaw += addYaw
	seat.AssemblyAngularVelocity = Vector3.new(w.X, yaw, w.Z)

	return stillActive
end

function BoatPhysics.applyKinematic(
	state: KinematicState,
	strokes: { Stroke },
	now: number,
	dt: number,
	config: typeof(BoatConfig)
): { Stroke }
	local look = state.cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = if flat.Magnitude < 1e-3 then Vector3.zero else flat.Unit

	local addLinear = Vector3.zero
	local addYaw = 0

	local stillActive: { Stroke } = {}
	for _, stroke in strokes do
		local elapsed = now - stroke.startTime
		local progress = elapsed / config.STROKE_DURATION
		if progress < 1 then
			table.insert(stillActive, stroke)

			local envelope = BoatPhysics.strokeEnvelope(progress)
			local rate = envelope / (ENVELOPE_INTEGRAL * config.STROKE_DURATION)
			local frameSpeed = config.STROKE_FORWARD_SPEED * rate * dt
			local frameTurn = config.STROKE_TURN_SPEED * rate * dt

			addLinear += forward * frameSpeed

			if stroke.side == "right" then
				addYaw += frameTurn
			else
				addYaw -= frameTurn
			end
		end
	end

	local hasActiveStroke = #stillActive > 0
	local linearDrag = if hasActiveStroke then config.LINEAR_DRAG else config.COAST_LINEAR_DRAG
	local angularDrag = if hasActiveStroke then config.ANGULAR_DRAG else config.COAST_ANGULAR_DRAG

	local horiz = Vector3.new(state.linearVelocity.X, 0, state.linearVelocity.Z)
	horiz *= math.clamp(1 - linearDrag * dt, 0, 1)
	horiz += addLinear

	local yaw = state.angularVelocity.Y * math.clamp(1 - angularDrag * dt, 0, 1)
	yaw += addYaw

	state.linearVelocity = Vector3.new(horiz.X, 0, horiz.Z)
	state.angularVelocity = Vector3.new(0, yaw, 0)

	if not hasActiveStroke then
		if state.linearVelocity.Magnitude < config.VELOCITY_STOP_THRESHOLD then
			state.linearVelocity = Vector3.zero
		end
		if math.abs(state.angularVelocity.Y) < math.rad(2) then
			state.angularVelocity = Vector3.zero
		end
	end

	local step = state.linearVelocity * dt
	state.cframe = (state.cframe + step) * CFrame.Angles(0, state.angularVelocity.Y * dt, 0)

	return stillActive
end

return BoatPhysics
