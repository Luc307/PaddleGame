local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BoatConfig = require(ReplicatedStorage.Modules.BoatConfig)
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)

export type PaddleSide = BoatPhysics.PaddleSide

export type SeatBinding = {
	part: BasePart,
	paddleSide: PaddleSide?,
}

export type BoatRecord = {
	id: string,
	model: Model,
	physicsPart: BasePart,
	seatBindings: { SeatBinding },
	strokes: { BoatPhysics.Stroke },
	occupants: { [Player]: SeatBinding },
	lastStrokeAt: { [Player]: number },
}

export type PaddleValidator = (player: Player, boat: BoatRecord, side: PaddleSide) -> boolean

local BoatService = {}

local boats: { [string]: BoatRecord } = {}
local seatToBoatId: { [BasePart]: string } = {}
local playerBoatId: { [Player]: string } = {}
local paddleValidator: PaddleValidator = function(player, boat, side)
	local binding = boat.occupants[player]
	if not binding then
		return false
	end
	if binding.paddleSide and binding.paddleSide ~= side then
		return false
	end
	return true
end

local heartbeatConnection: RBXScriptConnection? = nil

local function ensureHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, boat in boats do
			-- Boot mit Fahrer: Client simuliert lokal (NetworkOwner). Server nur fuer leere Boote.
			if next(boat.occupants) then
				continue
			end
			if #boat.strokes > 0 then
				boat.strokes = BoatPhysics.apply(boat.physicsPart, boat.strokes, now, dt, BoatConfig)
			end
		end
	end)
end

local function setDriverOwnership(player: Player, part: BasePart)
	local root = part.AssemblyRootPart
	if root then
		root:SetNetworkOwner(player)
	end
end

function BoatService.setPaddleValidator(validator: PaddleValidator)
	paddleValidator = validator
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
	}?
)
	local id = if options and options.id then options.id else model.Name
	if boats[id] then
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

	local record: BoatRecord = {
		id = id,
		model = model,
		physicsPart = physicsPart,
		seatBindings = seatBindings,
		strokes = {},
		occupants = {},
		lastStrokeAt = {},
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

	boats[id] = nil
end

function BoatService.addOccupant(player: Player, boat: BoatRecord, seatPart: BasePart): SeatBinding?
	for _, binding in boat.seatBindings do
		if binding.part == seatPart then
			boat.occupants[player] = binding
			playerBoatId[player] = boat.id
			boat.strokes = {}
			setDriverOwnership(player, boat.physicsPart)
			return binding
		end
	end
	return nil
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
		boat.strokes = {}

		local root = boat.physicsPart.AssemblyRootPart
		if root then
			root:SetNetworkOwner(nil)
		end
	end

	playerBoatId[player] = nil
end

function BoatService.tryPaddle(player: Player, side: PaddleSide): boolean
	if side ~= "left" and side ~= "right" then
		return false
	end

	local boat = BoatService.getPlayerBoat(player)
	if not boat then
		return false
	end

	if not paddleValidator(player, boat, side) then
		return false
	end

	local now = os.clock()
	local lastAt = boat.lastStrokeAt[player] or 0
	if now - lastAt < BoatConfig.STROKE_COOLDOWN then
		return false
	end

	boat.lastStrokeAt[player] = now
	-- Physik laeuft auf Fahrer-Client. Server validiert nur (spaeter: Anti-Cheat / 1v1 authority).
	return true
end

function BoatService.onPlayerRemoving(player: Player)
	BoatService.removeOccupant(player)
end

return BoatService
