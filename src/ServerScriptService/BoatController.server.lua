local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BoatService = require(ServerStorage.Modules.BoatService)

local function getOrCreateRemoteEvent(...: string): RemoteEvent
	local names = { ... }
	local current: Instance = ReplicatedStorage:WaitForChild("Remotes")
	for i, name in names do
		local child = current:FindFirstChild(name)
		if not child then
			if i == #names then
				child = Instance.new("RemoteEvent")
			else
				child = Instance.new("Folder")
			end
			child.Name = name
			child.Parent = current
		end
		current = child
	end
	return current :: RemoteEvent
end

local BoatPaddleEvent = getOrCreateRemoteEvent("Events", "BoatPaddle")
local BoatControlEvent = getOrCreateRemoteEvent("Events", "BoatControl")

local function notifyControl(player: Player, active: boolean, boatId: string?, paddleSide: string?)
	BoatControlEvent:FireClient(player, active, boatId, paddleSide)
end

local function onSeated(player: Player, humanoid: Humanoid, active: boolean, seatPart: BasePart?)
	if active and seatPart then
		local boat = BoatService.getBoatForSeat(seatPart)
		if not boat then
			return
		end

		local binding = BoatService.addOccupant(player, boat, seatPart)
		if binding then
			notifyControl(player, true, boat.id, binding.paddleSide)
			print(`[Boat] {player.Name} steuerung aktiviert ({boat.id})`)
		end
	else
		if BoatService.getPlayerBoat(player) then
			BoatService.removeOccupant(player)
			notifyControl(player, false, nil, nil)
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

BoatPaddleEvent.OnServerEvent:Connect(function(player: Player, side: string)
	BoatService.tryPaddle(player, side :: BoatService.PaddleSide)
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
