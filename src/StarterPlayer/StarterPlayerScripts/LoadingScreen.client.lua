local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LoadingEvent = ReplicatedStorage.Remotes.Events.Loading

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
local cameraConnection: RBXScriptConnection? = nil
local savedCameraType: Enum.CameraType? = nil
local stageForward: Vector3? = nil
local smoothedFallCFrame: CFrame? = nil

local function getFadeGui(): Frame
	if fadeFrame and fadeFrame.Parent then
		return fadeFrame
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local fadeGui = playerGui:WaitForChild("LoadingFade")
	fadeFrame = fadeGui:WaitForChild("Fade") :: Frame
	return fadeFrame :: Frame
end

local function setBlackScreen()
	getFadeGui().BackgroundTransparency = 0
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

local function startLoading(character: Model, forward: Vector3)
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

	getFadeGui().BackgroundTransparency = 1
end

local function fadeToBlack()
	local frame = getFadeGui()
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	tween:Play()
	tween.Completed:Wait()

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

	local frame = getFadeGui()
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Wait()
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

	local fadeGui = getFadeGui()
	if fadeGui and fadeGui.Parent then
		fadeGui.Parent:Destroy()
	end
end

local function onCharacterAdded()
	setBlackScreen()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded()
end

LoadingEvent.OnClientEvent:Connect(function(action: string, forward: Vector3?)
	local character = player.Character
	if not character then
		return
	end

	if action == "Start" and forward then
		startLoading(character, forward)
	elseif action == "FadeOut" then
		fadeToBlack()
	elseif action == "FadeIn" then
		fadeFromBlack(character)
	elseif action == "End" then
		finishIntro(character)
	end
end)
