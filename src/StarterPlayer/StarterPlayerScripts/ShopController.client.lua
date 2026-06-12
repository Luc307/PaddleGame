--[[
	Expected StarterGui hierarchy:
	ShopGui (ScreenGui, Enabled=false)
	  MainFrame (Frame)
	    BoatList (Frame, UIListLayout recommended)
	      small (TextButton/ImageButton)
	      mid
	      big
	      huge
	    BoatPreview (ViewportFrame, optional)
	    CloseButton (TextButton, optional)
	Selected state: script sets Attribute "Selected" = true/false on each boat button.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry)
local BoatShopConfig = require(ReplicatedStorage.Modules.BoatShopConfig)

local ShopSelectEvent = Remotes.Events.ShopSelect
local ShopGetStateFunction = Remotes.Functions.ShopGetState

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SHOP_KEY = Enum.KeyCode.U

local shopGui = playerGui:WaitForChild("ShopGui") :: ScreenGui
local mainFrame = shopGui:WaitForChild("MainFrame") :: Frame
local boatList = mainFrame:WaitForChild("BoatList") :: Frame
local closeButton = mainFrame:FindFirstChild("CloseButton")

local isQueued = false
local boatButtons: { [string]: GuiButton } = {}
local previewModel: Model? = nil

local function isInFight(): boolean
	if player:GetAttribute("RaceSessionId") ~= nil then
		return true
	end

	if isQueued then
		return true
	end

	return false
end

local function updateSelectionHighlight(selectedBoatId: string)
	for boatId, button in boatButtons do
		button:SetAttribute("Selected", boatId == selectedBoatId)
	end
end

local function clearPreviewModel()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
end

local function syncFromServer()
	local state = ShopGetStateFunction:InvokeServer()
	if typeof(state) ~= "table" then
		return nil
	end

	local selectedBoat = if typeof(state.selectedBoat) == "string"
		then state.selectedBoat
		else BoatShopConfig.DEFAULT_BOAT_ID

	updateSelectionHighlight(selectedBoat)
	return state
end

local function setShopVisible(visible: boolean)
	shopGui.Enabled = visible

	if visible then
		syncFromServer()
	else
		clearPreviewModel()
	end
end

local function toggleShop()
	if shopGui.Enabled then
		setShopVisible(false)
		return
	end

	if isInFight() then
		return
	end

	local state = syncFromServer()
	if not state or state.canOpen ~= true then
		return
	end

	setShopVisible(true)
end

local function onBoatSelected(boatId: string)
	if isInFight() then
		return
	end

	ShopSelectEvent:FireServer(boatId)
	updateSelectionHighlight(boatId)
end

for _, boatId in BoatShopConfig.BOAT_IDS do
	local button = boatList:WaitForChild(boatId)
	if button:IsA("GuiButton") then
		boatButtons[boatId] = button
		button.Activated:Connect(function()
			onBoatSelected(boatId)
		end)
	end
end

player:GetAttributeChangedSignal(BoatShopConfig.SELECTED_ATTRIBUTE):Connect(function()
	local selectedBoat = player:GetAttribute(BoatShopConfig.SELECTED_ATTRIBUTE)
	if typeof(selectedBoat) == "string" and shopGui.Enabled then
		updateSelectionHighlight(selectedBoat)
	end
end)

Remotes.Events.QueueStatus.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end

	if data.action == "joined" or data.action == "started" then
		isQueued = true
	elseif data.action == "left" or data.action == "error" then
		isQueued = false
	end

	if isInFight() and shopGui.Enabled then
		setShopVisible(false)
	end
end)

player:GetAttributeChangedSignal("RaceSessionId"):Connect(function()
	if isInFight() and shopGui.Enabled then
		setShopVisible(false)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == SHOP_KEY then
		toggleShop()
	end
end)

if closeButton and closeButton:IsA("GuiButton") then
	closeButton.Activated:Connect(function()
		setShopVisible(false)
	end)
end

shopGui.Enabled = false
updateSelectionHighlight(BoatShopConfig.DEFAULT_BOAT_ID)
