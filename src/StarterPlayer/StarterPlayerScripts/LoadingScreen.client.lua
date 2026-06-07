local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry) :: ModuleScript
local LoadingEvent = Remotes.Events.Loading

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FADE_DURATION = 1
local CANVAS_SIZE = Vector3.new(120, 80, 0.2)
local FLOOR_SIZE = Vector3.new(120, 0.3, 120)
local CANVAS_DISTANCE = 9
local CAMERA_DISTANCE = 14
local CAMERA_HEIGHT = 2.5
local FALL_CAMERA_BACK = 14
local FALL_CAMERA_HEIGHT = 5
local FALL_CAMERA_SMOOTHING = 0.18
local CUSTOM_CAMERA_TRANSITION = 0.6

local whiteCanvas: BasePart? = nil
local whiteFloor: BasePart? = nil
local fadeFrame: Frame? = nil
local activeFadeTween: Tween? = nil
local fadeQueue: { () -> () } = {}
local fadeQueueRunning = false
local cameraConnection: RBXScriptConnection? = nil
local savedCameraType: Enum.CameraType? = nil
local stageForward: Vector3? = nil
local smoothedFallCFrame: CFrame? = nil

local function ensureFadeGui(): Frame
	if fadeFrame and fadeFrame.Parent then
		return fadeFrame
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:FindFirstChild("LoadingFade")

	if not screenGui or not screenGui:IsA("ScreenGui") then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "LoadingFade"
		screenGui.Parent = playerGui
	end

	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = true

	local frame = screenGui:FindFirstChild("Fade")
	if not frame or not frame:IsA("GuiObject") then
		if frame then
			frame:Destroy()
		end

		frame = Instance.new("Frame")
		frame.Name = "Fade"
		frame.Parent = screenGui
	end

	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0, 0)
	frame.ZIndex = 1

	fadeFrame = frame :: Frame
	return fadeFrame :: Frame
end

local function runFadeQueue()
	if fadeQueueRunning then
		return
	end

	fadeQueueRunning = true
	while #fadeQueue > 0 do
		local job = table.remove(fadeQueue, 1)
		job()
	end
	fadeQueueRunning = false
end

local function enqueueFade(job: () -> ())
	table.insert(fadeQueue, job)
	runFadeQueue()
end

local function tweenFadeTransparency(targetTransparency: number)
	local frame = ensureFadeGui()
	frame.BackgroundColor3 = Color3.new(0, 0, 0)

	if activeFadeTween then
		activeFadeTween:Cancel()
		activeFadeTween = nil
	end

	local tween = TweenService:Create(
		frame,
		TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = targetTransparency }
	)
	activeFadeTween = tween
	tween:Play()
	tween.Completed:Wait()
	activeFadeTween = nil
end

local function setBlackScreen()
	local frame = ensureFadeGui()
	frame.BackgroundTransparency = 0
end

local function createWhitePart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = workspace
	return part
end

local function updateLoadingView(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local forward = stageForward
	if not root or not forward or not whiteCanvas or not whiteCanvas.Parent then
		return
	end

	local focusPosition = root.Position + Vector3.new(0, CAMERA_HEIGHT, 0)
	local cameraPosition = focusPosition - forward * CAMERA_DISTANCE

	camera.CFrame = CFrame.lookAt(cameraPosition, focusPosition)

	local awayFromCamera = (focusPosition - cameraPosition).Unit
	local canvasPosition = focusPosition + awayFromCamera * CANVAS_DISTANCE
	whiteCanvas.CFrame = CFrame.lookAt(canvasPosition, focusPosition)

	if whiteFloor then
		whiteFloor.CFrame = CFrame.new(root.Position - Vector3.new(0, 3, 0))
	end
end

local function getFallCameraCFrame(root: BasePart): CFrame
	local focusPosition = root.Position + Vector3.new(0, 2, 0)
	local backDirection = -root.CFrame.LookVector
	local cameraPosition = focusPosition + backDirection * FALL_CAMERA_BACK + Vector3.new(0, FALL_CAMERA_HEIGHT, 0)

	return CFrame.lookAt(cameraPosition, focusPosition)
end

local function updateFallCamera(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local targetCFrame = getFallCameraCFrame(root)

	if smoothedFallCFrame then
		smoothedFallCFrame = smoothedFallCFrame:Lerp(targetCFrame, FALL_CAMERA_SMOOTHING)
	else
		smoothedFallCFrame = targetCFrame
	end

	camera.CFrame = smoothedFallCFrame
end

local function stopCameraUpdates()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	RunService:UnbindFromRenderStep("LoadingFallCamera")
end

local function hideCanvas()
	stopCameraUpdates()

	if whiteCanvas then
		whiteCanvas:Destroy()
		whiteCanvas = nil
	end

	if whiteFloor then
		whiteFloor:Destroy()
		whiteFloor = nil
	end
end

local function skipIntro()
	table.clear(fadeQueue)
	fadeQueueRunning = false

	if activeFadeTween then
		activeFadeTween:Cancel()
		activeFadeTween = nil
	end

	hideCanvas()
	stopCameraUpdates()
	RunService:UnbindFromRenderStep("LoadingFallCamera")

	local screenGui = fadeFrame and fadeFrame.Parent
	fadeFrame = nil
	if screenGui then
		screenGui:Destroy()
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end

	camera.CameraType = savedCameraType or Enum.CameraType.Custom
	savedCameraType = nil
	stageForward = nil
	smoothedFallCFrame = nil
end

local function startLoading(character: Model, forward: Vector3)
	setBlackScreen()

	stageForward = forward
	smoothedFallCFrame = nil

	if not savedCameraType then
		savedCameraType = camera.CameraType
	end
	camera.CameraType = Enum.CameraType.Scriptable

	whiteCanvas = createWhitePart("LoadingWhiteCanvas", CANVAS_SIZE)
	whiteFloor = createWhitePart("LoadingWhiteFloor", FLOOR_SIZE)

	stopCameraUpdates()
	cameraConnection = RunService.RenderStepped:Connect(function()
		updateLoadingView(character)
	end)

	for _ = 1, 2 do
		RunService.RenderStepped:Wait()
		updateLoadingView(character)
	end

	enqueueFade(function()
		tweenFadeTransparency(1)
	end)
end

local function fadeToBlack()
	tweenFadeTransparency(0)
	hideCanvas()
end

local function startFallCamera(character: Model)
	if not savedCameraType then
		savedCameraType = camera.CameraType
	end

	camera.CameraType = Enum.CameraType.Scriptable
	stopCameraUpdates()
	smoothedFallCFrame = nil

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		smoothedFallCFrame = getFallCameraCFrame(root)
		camera.CFrame = smoothedFallCFrame
	end

	RunService:BindToRenderStep("LoadingFallCamera", Enum.RenderPriority.Camera.Value, function()
		updateFallCamera(character)
	end)
end

local function fadeFromBlack(character: Model)
	startFallCamera(character)
	tweenFadeTransparency(1)
end

local function getCustomCameraCFrame(root: BasePart): CFrame
	local focusPosition = root.Position + Vector3.new(0, 2, 0)
	local backDirection = -root.CFrame.LookVector

	return CFrame.lookAt(focusPosition + backDirection * 12 + Vector3.new(0, 2, 0), focusPosition)
end

local function finishIntro(character: Model)
	RunService:UnbindFromRenderStep("LoadingFallCamera")
	stopCameraUpdates()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		savedCameraType = nil
		stageForward = nil
		smoothedFallCFrame = nil
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local startCFrame = camera.CFrame
	local startTime = os.clock()

	local transitionConnection: RBXScriptConnection
	transitionConnection = RunService.RenderStepped:Connect(function()
		local currentRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not currentRoot then
			transitionConnection:Disconnect()
			return
		end

		local alpha = math.clamp((os.clock() - startTime) / CUSTOM_CAMERA_TRANSITION, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		local targetCFrame = getCustomCameraCFrame(currentRoot)

		camera.CFrame = startCFrame:Lerp(targetCFrame, eased)

		if alpha >= 1 then
			transitionConnection:Disconnect()
			camera.CameraSubject = humanoid
			camera.CameraType = Enum.CameraType.Custom
			savedCameraType = nil
			stageForward = nil
			smoothedFallCFrame = nil
		end
	end)

	local screenGui = fadeFrame and fadeFrame.Parent
	fadeFrame = nil
	if screenGui then
		screenGui:Destroy()
	end
end

LoadingEvent.OnClientEvent:Connect(function(action: string, forward: Vector3?)
	local character = player.Character
	if not character then
		return
	end

	if action == "Start" and forward then
		startLoading(character, forward)
	elseif action == "FadeOut" then
		enqueueFade(fadeToBlack)
	elseif action == "FadeIn" then
		enqueueFade(function()
			fadeFromBlack(character)
		end)
	elseif action == "End" then
		finishIntro(character)
	elseif action == "Skip" then
		skipIntro()
	end
end)
