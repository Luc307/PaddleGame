local BoatConfig = require(script.Parent.BoatConfig)

export type PaddleSide = "left" | "right"

export type Stroke = {
	side: PaddleSide,
	startTime: number,
}

local ENVELOPE_POWER = 0.65
local INSTANT_KICK_FRACTION = 0.4

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

function BoatPhysics.applyInstantKick(seat: BasePart, side: PaddleSide, config: typeof(BoatConfig))
	local forward = BoatPhysics.getForwardVector(seat)
	local kickSpeed = config.STROKE_FORWARD_SPEED * INSTANT_KICK_FRACTION
	local kickTurn = config.STROKE_TURN_SPEED * INSTANT_KICK_FRACTION

	local velocity = seat.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z) + forward * kickSpeed
	seat.AssemblyLinearVelocity = Vector3.new(horizontal.X, velocity.Y, horizontal.Z)

	local angularVelocity = seat.AssemblyAngularVelocity
	local yaw = angularVelocity.Y + (if side == "right" then kickTurn else -kickTurn)
	seat.AssemblyAngularVelocity = Vector3.new(angularVelocity.X, yaw, angularVelocity.Z)
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

			if elapsed < dt then
				frameSpeed += config.STROKE_FORWARD_SPEED * INSTANT_KICK_FRACTION
				frameTurn += config.STROKE_TURN_SPEED * INSTANT_KICK_FRACTION
			end

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

return BoatPhysics
