local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Modules.RemoteRegistry)
local SettingsConfig = require(ReplicatedStorage.Modules.SettingsConfig)

local BoatControlEvent = Remotes.Events.BoatControl
local RaceVisualsEvent = Remotes.Events.RaceVisuals

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local RENDER_STEP_NAME = "BoatCameraFollow"
local CAMERA_DISTANCE = 14
local FOCUS_HEIGHT = 2
local CAMERA_HEIGHT = 4
local SMOOTHING = 0.15

local controlActive = false
local raceActive = false
local savedCameraType: Enum.CameraType? = nil
local smoothedCFrame: CFrame? = nil

local function getFlatBackDirection(root: BasePart): Vector3
	local lookVector = root.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.001 then
		return Vector3.new(0, 0, 1)
	end
	return -flatLook.Unit
end

local function getTargetCFrame(root: BasePart): CFrame
	local focusPosition = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
	local backDirection = getFlatBackDirection(root)
	local cameraPosition = focusPosition + backDirection * CAMERA_DISTANCE + Vector3.new(0, CAMERA_HEIGHT, 0)

	return CFrame.lookAt(cameraPosition, focusPosition)
end

local function updateCamera(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local targetCFrame = getTargetCFrame(root)
	if smoothedCFrame then
		smoothedCFrame = smoothedCFrame:Lerp(targetCFrame, SMOOTHING)
	else
		smoothedCFrame = targetCFrame
	end

	camera.CFrame = smoothedCFrame
end

local function stopCamera()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)

	if savedCameraType then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = savedCameraType
		savedCameraType = nil
	end

	smoothedCFrame = nil
end

local function startCamera(character: Model)
	if savedCameraType == nil then
		savedCameraType = camera.CameraType
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		smoothedCFrame = getTargetCFrame(root)
		camera.CFrame = smoothedCFrame
	end

	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value, function()
		local currentCharacter = player.Character
		if not currentCharacter or not controlActive or not raceActive then
			return
		end
		updateCamera(currentCharacter)
	end)
end

local function syncCameraState()
	if not SettingsConfig.BOAT_CAMERA_FOLLOW_ENABLED then
		stopCamera()
		return
	end

	local shouldFollow = controlActive and raceActive
	local isFollowing = savedCameraType ~= nil

	if shouldFollow and not isFollowing then
		local character = player.Character
		if character then
			startCamera(character)
		end
	elseif not shouldFollow and isFollowing then
		stopCamera()
	end
end

BoatControlEvent.OnClientEvent:Connect(function(active: boolean)
	controlActive = active
	syncCameraState()
end)

RaceVisualsEvent.OnClientEvent:Connect(function(data)
	raceActive = data ~= nil and data.active ~= false
	syncCameraState()
end)

player.CharacterAdded:Connect(function()
	controlActive = false
	raceActive = false
	stopCamera()
end)
