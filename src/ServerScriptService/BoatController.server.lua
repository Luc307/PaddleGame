local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BoatService = require(ServerStorage.Modules.BoatService)
local BoatStateSync = require(ServerStorage.Modules.BoatStateSync)
local GameModeService = require(ServerStorage.Modules.GameMode.GameModeService)
local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry)

local BoatPaddleEvent = Remotes.Events.BoatPaddle
local BoatDriverStrokeEvent = Remotes.Events.BoatDriverStroke
local BoatControlEvent = Remotes.Events.BoatControl
local BoatCheckpointEvent = Remotes.Events.BoatCheckpoint
local RequestGameModeEvent = Remotes.Events.RequestGameMode

GameModeService.init({
	BoatControl = BoatControlEvent,
	RaceVisuals = Remotes.Events.RaceVisuals,
	QueueStatus = Remotes.Events.QueueStatus,
})

local function notifyControl(
	player: Player,
	active: boolean,
	boatId: string?,
	paddleSide: string?,
	isDriver: boolean?,
	useVisualBoat: boolean?,
	attachOffset: CFrame?,
	seatName: string?,
	seatLocalOffset: CFrame?
)
	BoatControlEvent:FireClient(player, active, boatId, paddleSide, isDriver, useVisualBoat, attachOffset, seatName, seatLocalOffset)
end

local function onSeated(player: Player, humanoid: Humanoid, active: boolean, seatPart: BasePart?)
	if active and seatPart then
		local boat = BoatService.getBoatForSeat(seatPart)
		if not boat then
			return
		end

		local binding = BoatService.addOccupant(player, boat, seatPart)
		if binding then
			notifyControl(player, true, boat.id, binding.paddleSide, true, false, CFrame.new(0, 3, 0), binding.part.Name, CFrame.new(0, 3, 0))
			print(`[Boat] {player.Name} steuerung aktiviert ({boat.id})`)
		end
	else
		if GameModeService.isPlayerLocked(player) then
			return
		end

		if BoatService.getPlayerBoat(player) then
			BoatService.removeOccupant(player)
			notifyControl(player, false, nil, nil, nil, nil, nil, nil, nil)
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

local function broadcastStroke(sourcePlayer: Player, boat: BoatService.BoatRecord, side: BoatService.PaddleSide, strokeTime: number)
	for _, occupant in BoatService.getOccupants(boat) do
		if occupant ~= sourcePlayer then
			BoatDriverStrokeEvent:FireClient(occupant, boat.id, side, strokeTime)
		end
	end
end

BoatPaddleEvent.OnServerEvent:Connect(function(player: Player, side: string, startTime: number?)
	if side ~= "left" and side ~= "right" then
		return
	end

	local ok, boat, strokeTime = BoatService.addStroke(player, side :: BoatService.PaddleSide, startTime)
	if not ok or not boat then
		return
	end

	if strokeTime then
		broadcastStroke(player, boat, side :: BoatService.PaddleSide, strokeTime)
	end
end)

BoatCheckpointEvent.OnServerEvent:Connect(function(player: Player, payload, force: boolean?)
	BoatStateSync.tryApply(player, payload, force == true)
end)

RequestGameModeEvent.OnServerEvent:Connect(function(player: Player, modeId: number)
	GameModeService.requestMode(player, modeId)
end)

local boatModel = workspace:WaitForChild("Boat Model", 30)
if boatModel and boatModel:IsA("Model") then
	BoatService.registerBoat(boatModel, { serverAuthority = false })
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
