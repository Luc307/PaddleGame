local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoatShopConfig = require(ReplicatedStorage.Modules.BoatShopConfig)

local BoatShopService = {}

local selections: { [Player]: string } = {}

local function getTemplatesFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(BoatShopConfig.TEMPLATE_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	warn(`[BoatShop] ReplicatedStorage.{BoatShopConfig.TEMPLATE_FOLDER_NAME} fehlt`)
	return nil
end

function BoatShopService.getSelection(player: Player): string
	return selections[player] or BoatShopConfig.DEFAULT_BOAT_ID
end

function BoatShopService.setSelection(player: Player, boatId: string): boolean
	if not BoatShopConfig.isValidBoatId(boatId) then
		warn(`[BoatShop] Ungueltige Boot-ID: {boatId}`)
		return false
	end

	selections[player] = boatId
	player:SetAttribute(BoatShopConfig.SELECTED_ATTRIBUTE, boatId)
	return true
end

function BoatShopService.initPlayer(player: Player)
	BoatShopService.setSelection(player, BoatShopConfig.DEFAULT_BOAT_ID)
end

function BoatShopService.clearPlayer(player: Player)
	selections[player] = nil
end

function BoatShopService.getTemplate(boatId: string): Model?
	local folder = getTemplatesFolder()
	if not folder then
		return nil
	end

	local template = folder:FindFirstChild(boatId) or folder:FindFirstChild("small")
	if template and template:IsA("Model") then
		return template
	end

	warn(`[BoatShop] Boot-Template "{boatId}" fehlt in {BoatShopConfig.TEMPLATE_FOLDER_NAME}`)
	return nil
end

local function getBoatDisplayName(boatId: string): string
	local template = BoatShopService.getTemplate(boatId)
	if template then
		return template.Name
	end
	return boatId
end

function BoatShopService.resolveBoatForTeam(players: { Player }, teamControls: boolean): (Model?, Player?, string?)
	if #players == 0 then
		return nil, nil, nil
	end

	if not teamControls then
		local player = players[1]
		local boatId = BoatShopService.getSelection(player)
		return BoatShopService.getTemplate(boatId), player, boatId
	end

	local rosterParts = {}
	for _, player in players do
		local boatId = BoatShopService.getSelection(player)
		table.insert(rosterParts, `{player.Name} with {getBoatDisplayName(boatId)}`)
	end

	local chosenIndex = math.random(1, #players)
	local chosenPlayer = players[chosenIndex]
	local chosenBoatId = BoatShopService.getSelection(chosenPlayer)

	print(`{table.concat(rosterParts, " | ")}. Boat from {chosenPlayer.Name} was chosen.`)

	return BoatShopService.getTemplate(chosenBoatId), chosenPlayer, chosenBoatId
end

return BoatShopService
