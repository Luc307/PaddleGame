local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BoatCheckpoint = require(ReplicatedStorage.Modules.BoatCheckpoint)
local BoatConfig = require(ReplicatedStorage.Modules.BoatConfig)
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics)
local PlayerAttachmentService = require(script.Parent.GameMode.PlayerAttachmentService)

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
	serverAuthority: boolean,
	driver: Player?,
	strokeCount: number,
	kinematicState: BoatPhysics.KinematicState?,
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
local heartbeatAccumulator = 0

function BoatService.moveModelByAnchor(model: Model, anchorPart: BasePart, targetCFrame: CFrame)
	local delta = targetCFrame * anchorPart.CFrame:Inverse()

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
end

local function syncServerKinematic(boat: BoatRecord)
	local state = boat.kinematicState
	if not state then
		return
	end

	BoatService.moveModelByAnchor(boat.model, boat.physicsPart, state.cframe)
	boat.physicsPart.AssemblyLinearVelocity = state.linearVelocity
	boat.physicsPart.AssemblyAngularVelocity = state.angularVelocity
	PlayerAttachmentService.syncPositions()
end

local function stepServerKinematic(boat: BoatRecord, now: number, dt: number)
	if not boat.kinematicState then
		return
	end

	if #boat.strokes > 0 then
		boat.strokes = BoatPhysics.applyKinematic(boat.kinematicState, boat.strokes, now, dt, BoatConfig)
	end

	syncServerKinematic(boat)
end

local function ensureHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		heartbeatAccumulator += dt
		local fixedDt = BoatConfig.FIXED_TIMESTEP

		while heartbeatAccumulator >= fixedDt do
			local now = Workspace:GetServerTimeNow()
			for _, boat in boats do
				if not next(boat.occupants) or not boat.serverAuthority or not boat.kinematicState then
					continue
				end

				boat.strokes = BoatPhysics.applyKinematic(boat.kinematicState, boat.strokes, now, fixedDt, BoatConfig)
				syncServerKinematic(boat)
			end

			heartbeatAccumulator -= fixedDt
		end
	end)
end

local function canSetNetworkOwner(part: BasePart): boolean
	local root = part.AssemblyRootPart
	return root ~= nil and not root.Anchored
end

local function setDriverOwnership(player: Player, part: BasePart)
	if not canSetNetworkOwner(part) then
		return
	end

	local root = part.AssemblyRootPart
	if root then
		pcall(function()
			root:SetNetworkOwnershipAuto(false)
			root:SetNetworkOwner(player)
		end)
	end
end

local function setServerOwnership(part: BasePart)
	if not canSetNetworkOwner(part) then
		return
	end

	local root = part.AssemblyRootPart
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
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
		serverAuthority: boolean?,
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

	local record: BoatRecord = {
		id = id,
		model = model,
		physicsPart = physicsPart,
		seatBindings = seatBindings,
		strokes = {},
		occupants = {},
		lastStrokeAt = {},
		serverAuthority = if options and options.serverAuthority ~= nil then options.serverAuthority else true,
		driver = nil,
		strokeCount = 0,
		kinematicState = nil,
	}

	if record.serverAuthority then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		record.kinematicState = {
			cframe = physicsPart.CFrame,
			linearVelocity = Vector3.zero,
			angularVelocity = Vector3.zero,
		}
		syncServerKinematic(record)
		setServerOwnership(record.physicsPart)
	end

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

local function countOccupants(boat: BoatRecord): number
	local total = 0
	for _ in boat.occupants do
		total += 1
	end
	return total
end

local function getFirstOccupant(boat: BoatRecord): Player?
	for occupant in boat.occupants do
		return occupant
	end
	return nil
end

local function attachOccupant(player: Player, boat: BoatRecord, binding: SeatBinding, asDriver: boolean?): SeatBinding
	local isFirstOccupant = countOccupants(boat) == 0
	local shouldDrive = asDriver == true or (asDriver == nil and isFirstOccupant)

	boat.occupants[player] = binding
	playerBoatId[player] = boat.id

	if shouldDrive then
		boat.driver = player
		boat.strokes = {}
	end

	if boat.serverAuthority and boat.kinematicState then
		boat.kinematicState.cframe = boat.physicsPart.CFrame
		boat.kinematicState.linearVelocity = Vector3.zero
		boat.kinematicState.angularVelocity = Vector3.zero
		syncServerKinematic(boat)
	end

	if boat.serverAuthority then
		setServerOwnership(boat.physicsPart)
	elseif shouldDrive then
		setDriverOwnership(player, boat.physicsPart)
	end

	return binding
end

function BoatService.addOccupant(player: Player, boat: BoatRecord, seatPart: BasePart): SeatBinding?
	for _, binding in boat.seatBindings do
		if binding.part == seatPart then
			return attachOccupant(player, boat, binding)
		end
	end
	return nil
end

function BoatService.addOccupantBinding(player: Player, boat: BoatRecord, binding: SeatBinding, asDriver: boolean?): SeatBinding
	return attachOccupant(player, boat, binding, asDriver)
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

		if boat.driver == player then
			boat.driver = getFirstOccupant(boat)
		end

		local nextDriver = boat.driver
		if boat.serverAuthority then
			setServerOwnership(boat.physicsPart)
		elseif nextDriver then
			setDriverOwnership(nextDriver, boat.physicsPart)
		else
			boat.driver = nil
			setServerOwnership(boat.physicsPart)
		end
	end

	playerBoatId[player] = nil
end

function BoatService.getOccupantCount(boat: BoatRecord): number
	return countOccupants(boat)
end

function BoatService.getOtherOccupants(boat: BoatRecord, player: Player): { Player }
	local others = {}
	for occupant in boat.occupants do
		if occupant ~= player then
			table.insert(others, occupant)
		end
	end
	return others
end

function BoatService.getOccupants(boat: BoatRecord): { Player }
	local occupants = {}
	for occupant in boat.occupants do
		table.insert(occupants, occupant)
	end
	return occupants
end

function BoatService.forEachActiveServerBoat(callback: (BoatRecord) -> ())
	for _, boat in boats do
		if boat.serverAuthority and next(boat.occupants) then
			callback(boat)
		end
	end
end

function BoatService.addStroke(player: Player, side: PaddleSide, startTime: number?): (boolean, BoatRecord?, number?)
	if not BoatService.tryPaddle(player, side) then
		return false, nil, nil
	end

	local boat = BoatService.getPlayerBoat(player)
	if not boat then
		return false, nil, nil
	end

	local strokeTime = if typeof(startTime) == "number" then startTime else Workspace:GetServerTimeNow()

	if boat.serverAuthority and boat.kinematicState then
		table.insert(boat.strokes, {
			side = side,
			startTime = strokeTime,
		})
		boat.strokeCount += 1
	end

	return true, boat, strokeTime
end

function BoatService.getStrokeCount(boat: BoatRecord): number
	return boat.strokeCount
end

function BoatService.applyCheckpoint(
	boat: BoatRecord,
	payload: BoatCheckpoint.CheckpointPayload,
	force: boolean?
): (boolean, string?)
	if typeof(payload.cframe) ~= "CFrame" then
		return false, "invalid_cframe"
	end

	if typeof(payload.linearVelocity) ~= "Vector3" or typeof(payload.angularVelocity) ~= "Vector3" then
		return false, "invalid_velocity"
	end

	local state = boat.kinematicState
	if not state then
		return false, "no_kinematic_state"
	end

	if typeof(payload.strokeCount) == "number" and payload.strokeCount >= boat.strokeCount then
		boat.strokeCount = payload.strokeCount
	end

	if force == true then
		state.cframe = payload.cframe
		state.linearVelocity = payload.linearVelocity
		state.angularVelocity = payload.angularVelocity
		syncServerKinematic(boat)
		return true, "forced"
	end

	if typeof(payload.strokeCount) ~= "number" or payload.strokeCount < boat.strokeCount then
		return false, "stale_stroke_count"
	end

	local delta = (state.cframe.Position - payload.cframe.Position).Magnitude

	if delta > BoatCheckpoint.HARD_LIMIT then
		return false, "delta_too_large"
	end

	if delta <= BoatCheckpoint.SOFT_LIMIT then
		state.cframe = state.cframe:Lerp(payload.cframe, BoatCheckpoint.SOFT_BLEND)
		state.linearVelocity = state.linearVelocity:Lerp(payload.linearVelocity, BoatCheckpoint.SOFT_BLEND)
		state.angularVelocity = state.angularVelocity:Lerp(payload.angularVelocity, BoatCheckpoint.SOFT_BLEND)
	else
		state.cframe = payload.cframe
		state.linearVelocity = payload.linearVelocity
		state.angularVelocity = payload.angularVelocity
	end

	syncServerKinematic(boat)
	return true, "applied"
end

function BoatService.tryPaddle(player: Player, side: PaddleSide): (boolean, number?)
	if side ~= "left" and side ~= "right" then
		return false
	end

	local boat = BoatService.getPlayerBoat(player)
	if not boat then
		return false, nil
	end

	if not paddleValidator(player, boat, side) then
		return false, nil
	end

	local now = os.clock()
	local lastAt = boat.lastStrokeAt[player] or 0
	if now - lastAt < BoatConfig.STROKE_COOLDOWN then
		return false, nil
	end

	boat.lastStrokeAt[player] = now

	return true, now
end

function BoatService.getDriver(boat: BoatRecord): Player?
	return boat.driver
end

function BoatService.isTeamBoat(boat: BoatRecord): boolean
	return countOccupants(boat) > 1
end

function BoatService.onPlayerRemoving(player: Player)
	BoatService.removeOccupant(player)
end

return BoatService
