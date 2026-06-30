local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)

export type BuoyancyRecord = {
	attachment: Attachment,
	vectorForce: VectorForce,
	mass: number,
}

local BuoyancyService = {}

local records: { [BasePart]: BuoyancyRecord } = {}

function BuoyancyService.attach(physicsPart: BasePart): BuoyancyRecord?
	if records[physicsPart] then
		return records[physicsPart]
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "BuoyancyAttachment"
	attachment.Parent = physicsPart

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "BuoyancyForce"
	vectorForce.Attachment0 = attachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Parent = physicsPart

	local mass = physicsPart.AssemblyMass
	if mass < 1 then
		mass = 50
	end

	local record: BuoyancyRecord = {
		attachment = attachment,
		vectorForce = vectorForce,
		mass = mass,
	}
	records[physicsPart] = record
	return record
end

function BuoyancyService.detach(physicsPart: BasePart)
	local record = records[physicsPart]
	if not record then
		return
	end

	record.vectorForce:Destroy()
	record.attachment:Destroy()
	records[physicsPart] = nil
end

function BuoyancyService.update(physicsPart: BasePart, config: typeof(PaddleConfig))
	local record = records[physicsPart]
	if not record then
		return
	end

	local waterY = config.WATER_SURFACE_Y
	local waterSurface = workspace:FindFirstChild("WaterSurface", true)
	if waterSurface and waterSurface:IsA("BasePart") then
		waterY = waterSurface.Position.Y + waterSurface.Size.Y * 0.5
	end

	record.vectorForce.Force = BoatPhysics.computeBuoyancyForce(
		physicsPart,
		waterY,
		config.BUOYANCY_STRENGTH,
		record.mass
	)
end

function BuoyancyService.updateAll(config: typeof(PaddleConfig))
	for part in records do
		BuoyancyService.update(part, config)
	end
end

return BuoyancyService
