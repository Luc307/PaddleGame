local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BoatService = require(ServerStorage.Modules.BoatService)
local GameModeService = require(ServerStorage.Modules.GameMode.GameModeService)

local function getOrCreateRemote(parent: Instance, name: string, isUnreliable: boolean): Instance
	local child = parent:FindFirstChild(name)
	local expectedClass = if isUnreliable then "UnreliableRemoteEvent" else "RemoteEvent"

	if child and not child:IsA(expectedClass) then
		child:Destroy()
		child = nil
	end

	if not child then
		child = if isUnreliable then Instance.new("UnreliableRemoteEvent") else Instance.new("RemoteEvent")
		child.Name = name
		child.Parent = parent
	end
	return child
end

local function getOrCreateRemoteEvent(...: string): RemoteEvent
	local names = { ... }
	local current: Instance = ReplicatedStorage:WaitForChild("Remotes")
	for i, name in names do
		local isLeaf = i == #names
		current = getOrCreateRemote(current, name, false)
		if not isLeaf and not current:IsA("Folder") then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = current.Parent
			current:Destroy()
			current = folder
		end
	end
	return current :: RemoteEvent
end

local function getOrCreateUnreliableRemoteEvent(...: string): UnreliableRemoteEvent
	local names = { ... }
	local current: Instance = ReplicatedStorage:WaitForChild("Remotes")
	for i, name in names do
		local isLeaf = i == #names
		current = getOrCreateRemote(current, name, isLeaf)
		if not isLeaf and not current:IsA("Folder") then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = current.Parent
			current:Destroy()
			current = folder
		end
	end
	return current :: UnreliableRemoteEvent
end

local BoatPaddleEvent = getOrCreateUnreliableRemoteEvent("Events", "BoatPaddle")
local BoatControlEvent = getOrCreateRemoteEvent("Events", "BoatControl")
local RequestGameModeEvent = getOrCreateRemoteEvent("Events", "RequestGameMode")
local RaceVisualsEvent = getOrCreateRemoteEvent("Events", "RaceVisuals")
local QueueStatusEvent = getOrCreateRemoteEvent("Events", "QueueStatus")

GameModeService.init({
	BoatControl = BoatControlEvent,
	RaceVisuals = RaceVisualsEvent,
	QueueStatus = QueueStatusEvent,
})

local function notifyControl(
	player: Player,
	active: boolean,
	boatId: string?,
	paddleSide: string?,
	isDriver: boolean?,
	serverAuthority: boolean?
)
	BoatControlEvent:FireClient(player, active, boatId, paddleSide, isDriver, serverAuthority)
end

local function onSeated(player: Player, humanoid: Humanoid, active: boolean, seatPart: BasePart?)
	if active and seatPart then
		local boat = BoatService.getBoatForSeat(seatPart)
		if not boat then
			return
		end

		local binding = BoatService.addOccupant(player, boat, seatPart)
		if binding then
			notifyControl(player, true, boat.id, binding.paddleSide, true, boat.serverAuthority)
			print(`[Boat] {player.Name} steuerung aktiviert ({boat.id})`)
		end
	else
		if GameModeService.isPlayerLocked(player) then
			return
		end

		if BoatService.getPlayerBoat(player) then
			BoatService.removeOccupant(player)
			notifyControl(player, false, nil, nil, nil, nil)
			print(`[Boat] {player.Name} steuerung deaktiviert`)
		end
	end
end

local function bindCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.Seated:Connect(function(active, seatPart)
		onSeated(player, humanoid, active, seatPart)
	end)

	if humanoid.SeatPart then
		onSeated(player, humanoid, true, humanoid.SeatPart)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)

	if player.Character then
		bindCharacter(player, player.Character)
	end
end

BoatPaddleEvent.OnServerEvent:Connect(function(player: Player, side: string, startTime: number?)
	if side ~= "left" and side ~= "right" then
		return
	end

	local strokeTime = if typeof(startTime) == "number" then startTime else nil
	BoatService.tryPaddle(player, side :: BoatService.PaddleSide, strokeTime)
end)

RequestGameModeEvent.OnServerEvent:Connect(function(player: Player, modeId: number)
	GameModeService.requestMode(player, modeId)
end)

local boatModel = workspace:WaitForChild("Boat Model", 30)
if boatModel and boatModel:IsA("Model") then
	BoatService.registerBoat(boatModel)
else
	warn("[BoatController] workspace['Boat Model'] nicht gefunden")
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	BoatService.onPlayerRemoving(player)
end)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
