local PaddleConfig = require(script.Parent.PaddleConfig)

export type PaddleSide = "left" | "right"

local BoatPhysics = {}

function BoatPhysics.getForwardVector(part: BasePart): Vector3
	local look = part.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.zero
	end
	return flat.Unit
end

function BoatPhysics.applyStroke(
	physicsPart: BasePart,
	side: PaddleSide,
	config: typeof(PaddleConfig)
)
	local forward = BoatPhysics.getForwardVector(physicsPart)
	if forward.Magnitude < 1e-3 then
		return
	end

	local linear = physicsPart.AssemblyLinearVelocity
	local horiz = Vector3.new(linear.X, 0, linear.Z) + forward * config.STROKE_FORWARD_SPEED

	if horiz.Magnitude > config.MAX_HORIZONTAL_SPEED then
		horiz = horiz.Unit * config.MAX_HORIZONTAL_SPEED
	end

	physicsPart.AssemblyLinearVelocity = Vector3.new(horiz.X, linear.Y, horiz.Z)

	local turnSign = if side == "right" then 1 else -1
	local angular = physicsPart.AssemblyAngularVelocity
	physicsPart.AssemblyAngularVelocity = Vector3.new(0, angular.Y + turnSign * config.STROKE_TURN_SPEED, 0)
end

function BoatPhysics.stabilize(physicsPart: BasePart)
	local angular = physicsPart.AssemblyAngularVelocity
	if math.abs(angular.X) > 1e-3 or math.abs(angular.Z) > 1e-3 then
		physicsPart.AssemblyAngularVelocity = Vector3.new(0, angular.Y, 0)
	end
end

function BoatPhysics.applyCoastDrag(physicsPart: BasePart, dt: number, config: typeof(PaddleConfig))
	local linear = physicsPart.AssemblyLinearVelocity
	local horiz = Vector3.new(linear.X, 0, linear.Z)
	horiz *= math.clamp(1 - config.COAST_DRAG * dt, 0, 1)
	physicsPart.AssemblyLinearVelocity = Vector3.new(horiz.X, linear.Y, horiz.Z)

	local angular = physicsPart.AssemblyAngularVelocity
	local yaw = angular.Y * math.clamp(1 - config.COAST_DRAG * 0.5 * dt, 0, 1)
	physicsPart.AssemblyAngularVelocity = Vector3.new(0, yaw, 0)
end

function BoatPhysics.computeBuoyancyForce(
	part: BasePart,
	waterY: number,
	strength: number,
	mass: number
): Vector3
	local gravity = workspace.Gravity
	local submerge = waterY - part.Position.Y
	local spring = submerge * strength
	local gravityComp = mass * gravity
	return Vector3.new(0, spring - gravityComp, 0)
end

return BoatPhysics
