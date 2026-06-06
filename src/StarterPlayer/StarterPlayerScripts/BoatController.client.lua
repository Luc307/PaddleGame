local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BoatConfig = require(ReplicatedStorage.Modules.BoatConfig) :: ModuleScript
local BoatPhysics = require(ReplicatedStorage.Modules.BoatPhysics) :: ModuleScript

local player = Players.LocalPlayer

local BoatPaddleEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("BoatPaddle") :: RemoteEvent
local BoatControlEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("BoatControl") :: RemoteEvent

local PADDLE_LEFT_ANIM_ID: string? = nil
local PADDLE_RIGHT_ANIM_ID: string? = nil
local STROKE_DURATION = BoatConfig.STROKE_DURATION

local controlActive = false
local allowedPaddleSide: string? = nil

local physicsPart: BasePart? = nil
local strokes: { BoatPhysics.Stroke } = {}

local inputConnection: RBXScriptConnection? = nil
local physicsConnection: RBXScriptConnection? = nil
local animator: Animator? = nil
local animTracks: { [string]: AnimationTrack } = {}

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

	local boatModel = workspace:FindFirstChild(boatId)
	if not boatModel or not boatModel:IsA("Model") then
		return nil
	end

	local seat = boatModel:FindFirstChild("Seat")
	if seat and seat:IsA("BasePart") then
		return seat
	end

	return nil
end

local function updatePhysics(dt: number)
	local part = physicsPart
	if not part or not controlActive then
		return
	end

	strokes = BoatPhysics.apply(part, strokes, os.clock(), dt, BoatConfig)
end

local function canSendStroke(side: string): boolean
	if not controlActive or not physicsPart then
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

	local now = os.clock()
	table.insert(strokes, { side = side, startTime = now })

	playStrokeAnim(side)
	BoatPaddleEvent:FireServer(side)

	-- Sofort ein Physik-Tick, nicht auf naechsten RenderStepped warten.
	updatePhysics(1 / 60)
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.D then
		sendStroke("right")
	elseif input.KeyCode == Enum.KeyCode.A then
		sendStroke("left")
	end
end

local function activateControl(humanoid: Humanoid, boatId: string?, paddleSide: string?)
	if controlActive then
		return
	end

	physicsPart = resolvePhysicsPart(boatId)
	if not physicsPart then
		return
	end

	controlActive = true
	allowedPaddleSide = paddleSide
	strokes = {}

	loadAnimTracks(humanoid)
	inputConnection = UserInputService.InputBegan:Connect(onInputBegan)
	physicsConnection = RunService.RenderStepped:Connect(updatePhysics)

	print("steuerung aktiviert")
end

local function deactivateControl()
	if not controlActive then
		return
	end

	controlActive = false
	allowedPaddleSide = nil
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

BoatControlEvent.OnClientEvent:Connect(function(active: boolean, boatId: string?, paddleSide: string?)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if active then
		activateControl(humanoid, boatId, paddleSide)
	else
		deactivateControl()
	end
end)

player.CharacterAdded:Connect(deactivateControl)
deactivateControl()
