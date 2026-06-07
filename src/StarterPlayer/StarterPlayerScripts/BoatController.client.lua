local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BoatConfig = require(ReplicatedStorage.Modules.BoatConfig) :: ModuleScript
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics) :: ModuleScript

local player = Players.LocalPlayer

local BoatPaddleEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("BoatPaddle") :: UnreliableRemoteEvent
local BoatControlEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("BoatControl") :: RemoteEvent
local RequestGameModeEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("RequestGameMode") :: RemoteEvent
local RaceVisualsEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("RaceVisuals") :: RemoteEvent
local QueueStatusEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("QueueStatus") :: RemoteEvent

local PADDLE_LEFT_ANIM_ID: string? = nil
local PADDLE_RIGHT_ANIM_ID: string? = nil
local STROKE_DURATION = BoatConfig.STROKE_DURATION
local PREDICT_DT = 1 / 60
local PHYSICS_RENDER_STEP = "BoatPhysics"

local controlActive = false
local allowedPaddleSide: string? = nil
local activeBoatId: string? = nil
local isDriver = false
local serverAuthoritative = false

local physicsPart: BasePart? = nil
local strokes: { BoatPhysics.Stroke } = {}

local inputConnection: RBXScriptConnection? = nil
local visualConnection: RBXScriptConnection? = nil
local animator: Animator? = nil
local animTracks: { [string]: AnimationTrack } = {}
local transparentBoatIds: { [string]: boolean } = {}
local transparentUserIds: { [number]: boolean } = {}

local function getStrokeAnimId(side: string): string?
	if side == "right" then
		return PADDLE_RIGHT_ANIM_ID
	end
	return PADDLE_LEFT_ANIM_ID
end

local function loadAnimTracks(humanoid: Humanoid)
	animTracks = {}

	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		if animator then
			animator.Parent = humanoid
		end
	end

	for _, side in { "left", "right" } do
		local animId = getStrokeAnimId(side)
		if animId then
			local animation = Instance.new("Animation")
			animation.AnimationId = animId
			animTracks[side] = (animator :: Animator):LoadAnimation(animation)
		end
	end
end

local function playStrokeAnim(side: string)
	local track = animTracks[side]
	if not track then
		return
	end

	if track.Length > 0 then
		track:Play(0.1)
		track:AdjustSpeed(track.Length / STROKE_DURATION)
	else
		track:Play(0.1)
	end
end

local function resolvePhysicsPart(boatId: string?): BasePart?
	if not boatId then
		return nil
	end

	local boatModel = workspace:FindFirstChild(boatId, true)
	if not boatModel or not boatModel:IsA("Model") then
		return nil
	end

	local part = boatModel:FindFirstChild("PhysicsPart", true)
	if part and part:IsA("BasePart") then
		return part
	end

	part = boatModel:FindFirstChild("Seat")
	if part and part:IsA("BasePart") then
		return part
	end

	part = boatModel:FindFirstChild("SeatRight", true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function getStrokeTime(): number
	return Workspace:GetServerTimeNow()
end

local function applyStrokeNow(side: string, startTime: number)
	local part = physicsPart
	if not part then
		return
	end

	if serverAuthoritative then
		BoatPhysics.applyInstantKick(part, side :: BoatPhysics.PaddleSide, BoatConfig)
		return
	end

	table.insert(strokes, { side = side :: BoatPhysics.PaddleSide, startTime = startTime })
	strokes = BoatPhysics.apply(part, strokes, getStrokeTime(), PREDICT_DT, BoatConfig)
end

local function updatePhysics(dt: number)
	local part = physicsPart
	if not part or not controlActive or serverAuthoritative then
		return
	end

	strokes = BoatPhysics.apply(part, strokes, getStrokeTime(), dt, BoatConfig)
end

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

	local startTime = getStrokeTime()
	playStrokeAnim(side)
	applyStrokeNow(side, startTime)
	BoatPaddleEvent:FireServer(side, startTime)
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
	driver: boolean?,
	authoritative: boolean?
)
	if controlActive then
		return
	end

	physicsPart = resolvePhysicsPart(boatId)
	if not physicsPart then
		return
	end

	controlActive = true
	allowedPaddleSide = paddleSide
	activeBoatId = boatId
	isDriver = driver == true
	serverAuthoritative = authoritative == true
	strokes = {}

	loadAnimTracks(humanoid)
	inputConnection = UserInputService.InputBegan:Connect(onInputBegan)
	RunService:BindToRenderStep(PHYSICS_RENDER_STEP, Enum.RenderPriority.Input.Value, updatePhysics)

	print(if isDriver then "steuerung aktiviert (driver)" else "steuerung aktiviert (team)")
end

local function deactivateControl()
	if not controlActive then
		return
	end

	controlActive = false
	allowedPaddleSide = nil
	activeBoatId = nil
	isDriver = false
	serverAuthoritative = false
	physicsPart = nil
	strokes = {}

	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	RunService:UnbindFromRenderStep(PHYSICS_RENDER_STEP)

	for _, track in animTracks do
		track:Stop(0.1)
	end
	animTracks = {}
	animator = nil

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

BoatControlEvent.OnClientEvent:Connect(function(
	active: boolean,
	boatId: string?,
	paddleSide: string?,
	driver: boolean?,
	authoritative: boolean?
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
		activateControl(humanoid, boatId, paddleSide, driver, authoritative)
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

	for _, boatId in data.transparentBoatIds or {} do
		transparentBoatIds[boatId] = true
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
