local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry)
local BoatShopConfig = require(ReplicatedStorage.Modules.BoatShopConfig)
local BoatShopService = require(ServerStorage.Modules.BoatShopService)
local GameModeService = require(ServerStorage.Modules.GameMode.GameModeService)

local ShopSelectEvent = Remotes.Events.ShopSelect
local ShopGetStateFunction = Remotes.Functions.ShopGetState

local function buildState(player: Player)
	return {
		canOpen = GameModeService.canOpenShop(player),
		selectedBoat = BoatShopService.getSelection(player),
		boatIds = BoatShopConfig.BOAT_IDS,
	}
end

ShopSelectEvent.OnServerEvent:Connect(function(player: Player, boatId: any)
	if typeof(boatId) ~= "string" then
		return
	end

	if not GameModeService.canOpenShop(player) then
		return
	end

	BoatShopService.setSelection(player, boatId)
end)

ShopGetStateFunction.OnServerInvoke = function(player: Player)
	return buildState(player)
end

Players.PlayerAdded:Connect(function(player)
	BoatShopService.initPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	BoatShopService.clearPlayer(player)
end)

for _, player in Players:GetPlayers() do
	BoatShopService.initPlayer(player)
end
