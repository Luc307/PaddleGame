local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BoatConfig = require(ReplicatedStorage.Modules.BoatConfig) :: ModuleScript
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics) :: ModuleScript
local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry) :: ModuleScript

local BoatCharacterFollower = require(ReplicatedStorage.Modules.BoatCharacterFollower)
local BoatVisualService = require(ReplicatedStorage.Modules.BoatVisualService)

local player = Players.LocalPlayer

local BoatPaddleEvent = Remotes.Events.BoatPaddle
local BoatDriverStrokeEvent = Remotes.Events.BoatDriverStroke
local BoatControlEvent = Remotes.Events.BoatControl
local BoatCheckpointEvent = Remotes.Events.BoatCheckpoint
local RequestGameModeEvent = Remotes.Events.RequestGameMode
local RaceVisualsEvent = Remotes.Events.RaceVisuals
local QueueStatusEvent = Remotes.Events.QueueStatus

local PADDLE_LEFT_ANIM_ID: string? = nil
local PADDLE_RIGHT_ANIM_ID: string? = nil
local STROKE_DURATION = BoatConfig.STROKE_DURATION
local PHYSICS_RENDER_STEP = "BoatFreeRoamPhysics"

local controlActive = false
local allowedPaddleSide: string? = nil
local activeBoatId: string? = nil
local isDriver = false
local useVisualBoat = false
local attachOffset = CFrame.new(0, 3, 0)
local seatLocalOffset = CFrame.new(0, 3, 0)
local seatName: string? = nil

local physicsPart: BasePart? = nil
local strokes: { BoatPhysics.Stroke } = {}

local inputConnection: RBXScriptConnection? = nil
local visualConnection: RBXScriptConnection? = nil
local physicsConnection: RBXScriptConnection? = nil
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
		track:Play(0)
		track:AdjustSpeed(track.Length / STROKE_DURATION)
	else
		track:Play(0)
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

local function applyFreeRoamStroke(side: string, startTime: number)
	local part = physicsPart
	if not part then
		return
	end

	table.insert(strokes, { side = side :: BoatPhysics.PaddleSide, startTime = startTime })
	strokes = BoatPhysics.apply(part, strokes, getStrokeTime(), 1 / 60, BoatConfig)
end

local function updateFreeRoamPhysics(dt: number)
	local part = physicsPart
	if not part or not controlActive or useVisualBoat then
		return
	end

	strokes = BoatVisualService.updateFreeRoam(dt, part, strokes)
end

local function sendCheckpointToServer(force: boolean)
	if not useVisualBoat or not isDriver or not activeBoatId then
		return
	end

	if not force and not BoatVisualService.shouldSendCheckpoint(activeBoatId) then
		return
	end

	local payload = BoatVisualService.getCheckpoint(activeBoatId)
	if payload then
		BoatCheckpointEvent:FireServer(payload, force)
	end
end

local function trySendCheckpoint()
	if not activeBoatId then
		return
	end
	if not BoatVisualService.shouldSendCheckpoint(activeBoatId) then
		return
	end
	sendCheckpointToServer(true)
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

	if useVisualBoat and isDriver then
		sendCheckpointToServer(true)
	end

	if useVisualBoat and activeBoatId then
		BoatVisualService.applyStroke(activeBoatId, side, startTime)
	else
		applyFreeRoamStroke(side, startTime)
	end

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
	visualBoat: boolean?,
	offset: CFrame?,
	seatPartName: string?,
	seatOffset: CFrame?
)
	if controlActive then
		deactivateControl()
	end

	if not boatId then
		return
	end

	useVisualBoat = visualBoat == true
	isDriver = driver == true
	attachOffset = if typeof(offset) == "CFrame" then offset else CFrame.new(0, 3, 0)
	seatLocalOffset = if typeof(seatOffset) == "CFrame" then seatOffset else CFrame.new(0, 3, 0)
	seatName = if typeof(seatPartName) == "string" then seatPartName else nil

	if useVisualBoat then
		if not BoatVisualService.start(boatId, attachOffset, seatName, seatLocalOffset) then
			return
		end

		BoatCharacterFollower.start(function()
			return BoatVisualService.getCharacterCFrame(boatId)
		end)

		local character = player.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if rootPart then
			pcall(function()
				rootPart:SetNetworkOwner(player)
			end)
		end

		if isDriver then
			sendCheckpointToServer(true)
		end
	else
		physicsPart = resolvePhysicsPart(boatId)
		if not physicsPart then
			return
		end
		strokes = {}
		RunService:BindToRenderStep(PHYSICS_RENDER_STEP, Enum.RenderPriority.Input.Value, updateFreeRoamPhysics)
	end

	controlActive = true
	allowedPaddleSide = paddleSide
	activeBoatId = boatId

	loadAnimTracks(humanoid)
	inputConnection = UserInputService.InputBegan:Connect(onInputBegan)

	if useVisualBoat then
		if not physicsConnection then
			physicsConnection = RunService.Heartbeat:Connect(trySendCheckpoint)
		end
	end

	print(if useVisualBoat
		then if isDriver then "steuerung aktiviert (visual, driver)" else `steuerung aktiviert (visual, team, {paddleSide})`
		else "steuerung aktiviert (free roam)")
end

local function deactivateControl()
	if not controlActive then
		return
	end

	controlActive = false
	allowedPaddleSide = nil

	if useVisualBoat and activeBoatId then
		BoatVisualService.stop(activeBoatId)
		BoatCharacterFollower.stop()
	elseif physicsPart then
		RunService:UnbindFromRenderStep(PHYSICS_RENDER_STEP)
	end

	activeBoatId = nil
	isDriver = false
	useVisualBoat = false
	attachOffset = CFrame.new(0, 3, 0)
	seatLocalOffset = CFrame.new(0, 3, 0)
	seatName = nil
	physicsPart = nil
	strokes = {}

	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end

	if physicsConnection then
		physicsConnection:Disconnect()
		physicsConnection = nil
	end

	for _, track in animTracks do
		track:Stop(0.1)
	end
	animTracks = {}
	animator = nil

	print("steuerung deaktiviert")
end

local function resolveOpponentSeat(boatModel: Model): BasePart?
	local seat = boatModel:FindFirstChild("Seat", true)
	if seat and seat:IsA("BasePart") then
		return seat
	end

	seat = boatModel:FindFirstChild("SeatRight", true)
	if seat and seat:IsA("BasePart") then
		return seat
	end

	seat = boatModel:FindFirstChild("SeatLeft", true)
	if seat and seat:IsA("BasePart") then
		return seat
	end

	return nil
end

local function syncOpponentCharactersToAuthority()
	if not next(transparentUserIds) then
		return
	end

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player or transparentUserIds[otherPlayer.UserId] ~= true then
			continue
		end

		local character = otherPlayer.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not rootPart then
			continue
		end

		for boatId in transparentBoatIds do
			local boatModel = workspace:FindFirstChild(boatId, true)
			if not boatModel or not boatModel:IsA("Model") then
				continue
			end

			local seat = resolveOpponentSeat(boatModel)
			if not seat then
				continue
			end

			rootPart.Anchored = true
			rootPart.CFrame = seat.CFrame * CFrame.new(0, 3, 0)
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			break
		end
	end
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

BoatDriverStrokeEvent.OnClientEvent:Connect(function(boatId: string, side: string, startTime: number?)
	if not controlActive or activeBoatId ~= boatId then
		return
	end

	if side ~= "left" and side ~= "right" then
		return
	end

	if useVisualBoat then
		BoatVisualService.applyStroke(
			boatId,
			side,
			if typeof(startTime) == "number" then startTime else getStrokeTime()
		)
	else
		applyFreeRoamStroke(side, if typeof(startTime) == "number" then startTime else getStrokeTime())
	end
end)

BoatControlEvent.OnClientEvent:Connect(function(
	active: boolean,
	boatId: string?,
	paddleSide: string?,
	driver: boolean?,
	visualBoat: boolean?,
	offset: CFrame?,
	seatPartName: string?,
	seatOffset: CFrame?
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
		activateControl(humanoid, boatId, paddleSide, driver, visualBoat, offset, seatPartName, seatOffset)
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
	visualConnection = RunService.RenderStepped:Connect(function()
		syncOpponentCharactersToAuthority()
		applyLocalTransparency()
	end)
end)

UserInputService.InputBegan:Connect(onModeInputBegan)
player.CharacterAdded:Connect(deactivateControl)
deactivateControl()
