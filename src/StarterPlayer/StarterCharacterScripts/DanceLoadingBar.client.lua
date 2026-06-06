local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

local DANCE_ANIMATION_ID = "rbxassetid://126553137453494"
local GUI_NAME = "DanceLoadingBar"
local WORLD_OFFSET = Vector3.new(0, -3.6, 0)
local SCREEN_OFFSET_Y = 48
local REFERENCE_WIDTH = 1920
local REFERENCE_HEIGHT = 1080
local BASE_BAR_WIDTH = 200
local BASE_BAR_HEIGHT = 24
local BASE_FILL_INSET = 2
local BASE_SPARK_WIDTH = 8
local BASE_SPARK_HEIGHT = 22
local MIN_SCALE = 0.55
local MAX_SCALE = 1.35
local FALLBACK_DURATION = 4

type LoadingUi = {
	gui: ScreenGui,
	container: Frame,
	fillMask: Frame,
	fill: Frame,
	spark: Frame,
	pulse: UIStroke,
}

-- Teil 1: Referenzen auf vorbereitete UI aus StarterGui / PlayerGui.
local function resolveLoadingUi(gui: ScreenGui): LoadingUi
	local container = gui:WaitForChild("Container") :: Frame
	local fillMask = container:WaitForChild("FillMask") :: Frame
	local fill = fillMask:WaitForChild("Fill") :: Frame
	local spark = container:WaitForChild("Spark") :: Frame
	local pulse = container:WaitForChild("UIStroke") :: UIStroke

	return {
		gui = gui,
		container = container,
		fillMask = fillMask,
		fill = fill,
		spark = spark,
		pulse = pulse,
	}
end

local function acquireLoadingUi(): LoadingUi
	local gui = playerGui:FindFirstChild(GUI_NAME)

	if not gui then
		local template = StarterGui:WaitForChild(GUI_NAME)
		gui = template:Clone()
		gui.Parent = playerGui
	end

	gui.Enabled = false
	return resolveLoadingUi(gui :: ScreenGui)
end

-- Teil 2: Verwaltung der Elemente und Animation.
local ui: LoadingUi? = nil
local renderConnection: RBXScriptConnection? = nil
local activeTrack: AnimationTrack? = nil
local activeToken = 0

local function getAnimationId(track: AnimationTrack): string?
	local animation = track.Animation
	if not animation then
		return nil
	end

	return animation.AnimationId
end

local function getViewportScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end

	local viewport = camera.ViewportSize
	local scaleX = viewport.X / REFERENCE_WIDTH
	local scaleY = viewport.Y / REFERENCE_HEIGHT

	return math.clamp(math.min(scaleX, scaleY), MIN_SCALE, MAX_SCALE)
end

local function getFillInset(): number
	return math.max(1, math.round(BASE_FILL_INSET * getViewportScale()))
end

local function getBarSize(): (number, number)
	if not ui then
		local scale = getViewportScale()
		return math.round(BASE_BAR_WIDTH * scale), math.round(BASE_BAR_HEIGHT * scale)
	end

	return ui.container.AbsoluteSize.X, ui.container.AbsoluteSize.Y
end

local function applyResponsiveLayout()
	if not ui then
		return
	end

	local scale = getViewportScale()
	local barWidth = math.round(BASE_BAR_WIDTH * scale)
	local barHeight = math.round(BASE_BAR_HEIGHT * scale)
	local fillInset = getFillInset()

	ui.container.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.container.Size = UDim2.fromOffset(barWidth, barHeight)

	ui.fillMask.Position = UDim2.fromOffset(fillInset, fillInset)
	ui.fill.Size = UDim2.fromOffset(barWidth - fillInset * 2, barHeight - fillInset * 2)

	ui.spark.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.spark.Size = UDim2.fromOffset(math.round(BASE_SPARK_WIDTH * scale), math.round(BASE_SPARK_HEIGHT * scale))

	ui.pulse.Thickness = math.max(1, scale)
end

local function destroyUi()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if ui then
		ui.gui:Destroy()
		ui = nil
	end
end

local function updateScreenPosition()
	if not ui then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	applyResponsiveLayout()

	local viewport = camera.ViewportSize
	local barWidth, barHeight = getBarSize()
	local screenOffsetY = math.round(SCREEN_OFFSET_Y * getViewportScale())
	local screenPosition, isVisible = camera:WorldToViewportPoint(rootPart.Position + WORLD_OFFSET)

	local x = math.clamp(screenPosition.X, barWidth / 2, viewport.X - barWidth / 2)
	local y = math.clamp(screenPosition.Y + screenOffsetY, barHeight / 2, viewport.Y - barHeight / 2)

	ui.gui.Enabled = isVisible and activeTrack ~= nil
	ui.container.Position = UDim2.fromOffset(x, y)
end

local function stopLoading(track: AnimationTrack?)
	if track and activeTrack ~= track then
		return
	end

	activeTrack = nil
	activeToken += 1
	destroyUi()
end

local function getTrackProgress(track: AnimationTrack, startTime: number): number
	if track.Length > 0 and track.Length / 2 > 0 then
		return math.clamp(track.TimePosition / track.Length / 1.5, 0, 1)
	end

	return math.clamp((os.clock() - startTime) / FALLBACK_DURATION, 0, 1)
end

local function updateLoadingProgress(rawProgress: number)
	if not ui then
		return
	end

	local barWidth, barHeight = getBarSize()
	local fillInset = getFillInset()
	local easedProgress = 1 - (1 - rawProgress) ^ 3
	local usableWidth = barWidth - fillInset * 2
	local fillWidth = math.max(0, usableWidth * easedProgress)
	local shimmer = 0.5 + math.sin(os.clock() * 8) * 0.5

	ui.fillMask.Size = UDim2.fromOffset(fillWidth, barHeight - fillInset * 2)
	ui.spark.Position = UDim2.fromOffset(fillInset + fillWidth, barHeight / 2)
	ui.spark.BackgroundTransparency = 0.08 + shimmer * 0.24
	ui.pulse.Transparency = 0.18 + shimmer * 0.28
end

local function finishLoading(token: number)
	if token ~= activeToken or not ui then
		return
	end

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	updateLoadingProgress(1)

	local finishTween = TweenService:Create(
		ui.spark,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	finishTween:Play()
	finishTween.Completed:Wait()

	if token == activeToken then
		stopLoading(activeTrack)
	end
end

local function startLoading(track: AnimationTrack)
	stopLoading(nil)

	ui = acquireLoadingUi()

	activeToken += 1
	local token = activeToken
	activeTrack = track
	local startTime = os.clock()

	if ui then
		ui.gui.Enabled = true
	end
	updateScreenPosition()
	updateLoadingProgress(getTrackProgress(track, startTime))

	renderConnection = RunService.RenderStepped:Connect(function()
		if activeTrack ~= track or not ui then
			stopLoading(track)
			return
		end

		updateScreenPosition()
		updateLoadingProgress(getTrackProgress(track, startTime))
	end)

	track.Stopped:Once(function()
		finishLoading(token)
	end)
end

local function onAnimationPlayed(track: AnimationTrack)
	if getAnimationId(track) ~= DANCE_ANIMATION_ID then
		return
	end

	startLoading(track)
end

humanoid.Destroying:Once(function()
	stopLoading(nil)
end)

local animator = humanoid:WaitForChild("Animator") :: Animator
animator.AnimationPlayed:Connect(onAnimationPlayed)