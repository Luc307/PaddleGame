local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)
local BuoyancyService = require(ServerStorage.Modules.BuoyancyService)

export type PaddleSide = BoatPhysics.PaddleSide

export type SeatBinding = {
	part: BasePart,
	paddleSide: PaddleSide?,
}

export type StrokePlayBroadcaster = (boat: BoatRecord, side: PaddleSide, sourcePlayer: Player) -> ()

export type BoatRecord = {
	id: string,
	model: Model,
	physicsPart: BasePart,
	seatBindings: { SeatBinding },
	occupants: { [Player]: SeatBinding },
	teamControls: boolean,
	lastStrokeAt: { [Player]: number },
	lastPaddleAt: number,
}

local BoatService = {}

local boats: { [string]: BoatRecord } = {}
local seatToBoatId: { [BasePart]: string } = {}
local playerBoatId: { [Player]: string } = {}
local strokePlayBroadcaster: StrokePlayBroadcaster? = nil
local heartbeatConnection: RBXScriptConnection? = nil

local function weldModelToPhysicsPart(model: Model, physicsPart: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= physicsPart then
			descendant.Anchored = false
			if not descendant:FindFirstChildWhichIsA("WeldConstraint") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = physicsPart
				weld.Part1 = descendant
				weld.Parent = physicsPart
			end
		end
	end

	physicsPart.Anchored = false
	physicsPart.CanCollide = true
end

local function ensureHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()
		for _, boat in boats do
			if not next(boat.occupants) then
				continue
			end

			BoatPhysics.stabilize(boat.physicsPart)

			if now - boat.lastPaddleAt > PaddleConfig.STROKE_COOLDOWN * 2 then
				BoatPhysics.applyCoastDrag(boat.physicsPart, dt, PaddleConfig)
			end
		end

		BuoyancyService.updateAll(PaddleConfig)
	end)
end

function BoatService.moveModelByAnchor(model: Model, anchorPart: BasePart, targetCFrame: CFrame)
	local delta = targetCFrame * anchorPart.CFrame:Inverse()

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
end

function BoatService.setStrokePlayBroadcaster(broadcaster: StrokePlayBroadcaster?)
	strokePlayBroadcaster = broadcaster
end

function BoatService.getBoat(id: string): BoatRecord?
	return boats[id]
end

function BoatService.getBoatForSeat(seatPart: BasePart): BoatRecord?
	local boatId = seatToBoatId[seatPart]
	if not boatId then
		return nil
	end
	return boats[boatId]
end

function BoatService.getPlayerBoat(player: Player): BoatRecord?
	local boatId = playerBoatId[player]
	if not boatId then
		return nil
	end
	return boats[boatId]
end

function BoatService.registerBoat(
	model: Model,
	options: {
		id: string?,
		physicsPart: BasePart?,
		seats: { SeatBinding }?,
		teamControls: boolean?,
	}?
)
	local id = if options and options.id then options.id else model.Name
	if boats[id] then
		if boats[id].model ~= model then
			warn(`[BoatService] Boot-ID "{id}" bereits vergeben, Registrierung abgebrochen`)
			return nil
		end
		return boats[id]
	end

	local seatBindings: { SeatBinding }
	if options and options.seats then
		seatBindings = options.seats
	else
		local seat = model:WaitForChild("Seat", 10)
		if not seat or not seat:IsA("BasePart") then
			warn(`[BoatService] Boot "{id}" hat keinen Seat-Part`)
			return nil
		end
		seatBindings = { { part = seat, paddleSide = nil } }
	end

	local physicsPart = if options and options.physicsPart
		then options.physicsPart
		else seatBindings[1].part

	local teamControls = if options and options.teamControls ~= nil then options.teamControls else false

	weldModelToPhysicsPart(model, physicsPart)
	BuoyancyService.attach(physicsPart)

	local record: BoatRecord = {
		id = id,
		model = model,
		physicsPart = physicsPart,
		seatBindings = seatBindings,
		occupants = {},
		teamControls = teamControls,
		lastStrokeAt = {},
		lastPaddleAt = 0,
	}

	for _, binding in seatBindings do
		seatToBoatId[binding.part] = id
	end

	boats[id] = record
	ensureHeartbeat()

	return record
end

function BoatService.unregisterBoat(id: string)
	local record = boats[id]
	if not record then
		return
	end

	for player in record.occupants do
		playerBoatId[player] = nil
	end

	for _, binding in record.seatBindings do
		seatToBoatId[binding.part] = nil
	end

	BuoyancyService.detach(record.physicsPart)
	boats[id] = nil
end

function BoatService.addOccupant(player: Player, boat: BoatRecord, seatPart: BasePart): SeatBinding?
	for _, binding in boat.seatBindings do
		if binding.part == seatPart then
			boat.occupants[player] = binding
			playerBoatId[player] = boat.id
			return binding
		end
	end
	return nil
end

function BoatService.addOccupantBinding(player: Player, boat: BoatRecord, binding: SeatBinding): SeatBinding
	boat.occupants[player] = binding
	playerBoatId[player] = boat.id
	return binding
end

function BoatService.removeOccupant(player: Player)
	local boatId = playerBoatId[player]
	if not boatId then
		return
	end

	local boat = boats[boatId]
	if boat then
		boat.occupants[player] = nil
		boat.lastStrokeAt[player] = nil
	end

	playerBoatId[player] = nil
end

function BoatService.getOccupants(boat: BoatRecord): { Player }
	local occupants = {}
	for occupant in boat.occupants do
		table.insert(occupants, occupant)
	end
	return occupants
end

function BoatService.tryPaddle(player: Player, side: PaddleSide): boolean
	if side ~= "left" and side ~= "right" then
		return false
	end

	local boat = BoatService.getPlayerBoat(player)
	if not boat then
		return false
	end

	local binding = boat.occupants[player]
	if not binding then
		return false
	end

	if binding.paddleSide and binding.paddleSide ~= side then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	local lastAt = boat.lastStrokeAt[player] or 0
	if now - lastAt < PaddleConfig.STROKE_COOLDOWN then
		return false
	end

	return true
end

function BoatService.addStroke(player: Player, side: PaddleSide): boolean
	if not BoatService.tryPaddle(player, side) then
		return false
	end

	local boat = BoatService.getPlayerBoat(player)
	if not boat then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	boat.lastStrokeAt[player] = now
	boat.lastPaddleAt = now

	BoatPhysics.applyStroke(boat.physicsPart, side, PaddleConfig)

	if strokePlayBroadcaster then
		strokePlayBroadcaster(boat, side, player)
	end

	return true
end

function BoatService.onPlayerRemoving(player: Player)
	BoatService.removeOccupant(player)
end

return BoatService
