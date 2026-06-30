local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry)

local PaddleAnimationController = require(script.Parent.PaddleAnimationController)

local player = Players.LocalPlayer

local BoatPaddleEvent = Remotes.Events.BoatPaddle
local BoatStrokePlayEvent = Remotes.Events.BoatStrokePlay
local BoatControlEvent = Remotes.Events.BoatControl
local RequestGameModeEvent = Remotes.Events.RequestGameMode
local RaceVisualsEvent = Remotes.Events.RaceVisuals
local QueueStatusEvent = Remotes.Events.QueueStatus

local controlActive = false
local allowedPaddleSide: string? = nil
local activeBoatId: string? = nil
local teamControls = false

local inputConnection: RBXScriptConnection? = nil
local visualConnection: RBXScriptConnection? = nil
local transparentBoatIds: { [string]: boolean } = {}
local transparentUserIds: { [number]: boolean } = {}

local function canSendStroke(side: string): boolean
	if not controlActive then
		return false
	end
	if allowedPaddleSide and allowedPaddleSide ~= side then
		return false
	end
	return true
end

local function sendStroke(side: string)
	if not canSendStroke(side) then
		return
	end

	PaddleAnimationController.handleInput(side :: "left" | "right")
	BoatPaddleEvent:FireServer(side)
end

local function requestMode(modeId: number)
	RequestGameModeEvent:FireServer(modeId)
end

local function onModeInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		requestMode(1)
	elseif input.KeyCode == Enum.KeyCode.Two then
		requestMode(2)
	elseif input.KeyCode == Enum.KeyCode.Three then
		requestMode(3)
	elseif input.KeyCode == Enum.KeyCode.Four then
		requestMode(4)
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Space and allowedPaddleSide then
		sendStroke(allowedPaddleSide)
	elseif input.KeyCode == Enum.KeyCode.D and not allowedPaddleSide then
		sendStroke("right")
	elseif input.KeyCode == Enum.KeyCode.A and not allowedPaddleSide then
		sendStroke("left")
	end
end

local function activateControl(
	humanoid: Humanoid,
	boatId: string?,
	paddleSide: string?,
	isTeamMode: boolean?
)
	if controlActive then
		deactivateControl()
	end

	if not boatId then
		return
	end

	controlActive = true
	allowedPaddleSide = paddleSide
	activeBoatId = boatId
	teamControls = isTeamMode == true

	PaddleAnimationController.init(humanoid, teamControls)
	inputConnection = UserInputService.InputBegan:Connect(onInputBegan)

	print(if teamControls
		then `steuerung aktiviert (team, {paddleSide or "both"})`
		else "steuerung aktiviert (solo)")
end

local function deactivateControl()
	if not controlActive then
		return
	end

	controlActive = false
	allowedPaddleSide = nil
	activeBoatId = nil
	teamControls = false

	PaddleAnimationController.stop()

	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end

	print("steuerung deaktiviert")
end

local function applyLocalTransparency()
	for _, model in workspace:GetDescendants() do
		if not model:IsA("Model") then
			continue
		end

		local shouldFadeBoat = transparentBoatIds[model.Name] == true
		local playerFromCharacter = Players:GetPlayerFromCharacter(model)
		local shouldFadeCharacter = playerFromCharacter and transparentUserIds[playerFromCharacter.UserId] == true

		if shouldFadeBoat or shouldFadeCharacter then
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.LocalTransparencyModifier = 0.5
				end
			end
		end
	end
end

local function clearLocalTransparency()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 0
		end
	end
end

BoatStrokePlayEvent.OnClientEvent:Connect(function(boatId: string, side: string, speedMultiplier: number?)
	if not controlActive or activeBoatId ~= boatId then
		return
	end

	if side ~= "left" and side ~= "right" then
		return
	end

	local multiplier = if typeof(speedMultiplier) == "number" then speedMultiplier else 1
	PaddleAnimationController.playRemoteStroke(side :: "left" | "right", multiplier)
end)

BoatControlEvent.OnClientEvent:Connect(function(
	active: boolean,
	boatId: string?,
	paddleSide: string?,
	isTeamMode: boolean?
)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if active then
		activateControl(humanoid, boatId, paddleSide, isTeamMode)
	else
		deactivateControl()
	end
end)

QueueStatusEvent.OnClientEvent:Connect(function(data)
	if data and data.message then
		print(`[Queue] {data.message}`)
	end
end)

RaceVisualsEvent.OnClientEvent:Connect(function(data)
	clearLocalTransparency()
	transparentBoatIds = {}
	transparentUserIds = {}

	if not data or data.active == false then
		if visualConnection then
			visualConnection:Disconnect()
			visualConnection = nil
		end
		return
	end

	for _, transparentBoatId in data.transparentBoatIds or {} do
		transparentBoatIds[transparentBoatId] = true
	end
	for _, userId in data.transparentUserIds or {} do
		transparentUserIds[userId] = true
	end

	applyLocalTransparency()
	if visualConnection then
		visualConnection:Disconnect()
	end
	visualConnection = RunService.RenderStepped:Connect(applyLocalTransparency)
end)

UserInputService.InputBegan:Connect(onModeInputBegan)
player.CharacterAdded:Connect(deactivateControl)
deactivateControl()
