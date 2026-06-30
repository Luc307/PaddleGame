local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)

export type PaddleSide = "left" | "right"

local PRIORITY_SIT = Enum.AnimationPriority.Movement
local PRIORITY_STATIC = Enum.AnimationPriority.Action2
local PRIORITY_STROKE = Enum.AnimationPriority.Action4

local PaddleAnimationController = {}

local teamControls = false
local animator: Animator? = nil

local sitTrack: AnimationTrack? = nil
local staticTrack: AnimationTrack? = nil
local strokeTracks: { [string]: AnimationTrack } = {}

local soloActiveSide: PaddleSide? = nil
local soloPendingSide: PaddleSide? = nil
local soloSpamming = false
local soloStoppedConnection: RBXScriptConnection? = nil

local function formatAnimId(id: string?): string?
	if not id or id == "" then
		return nil
	end
	if string.find(id, "rbxassetid://", 1, true) then
		return id
	end
	return `rbxassetid://{id}`
end

local function loadTrack(animId: string?, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local formattedId = formatAnimId(animId)
	if not formattedId or not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = formattedId
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

local function playStrokeSpeed(track: AnimationTrack, speedMultiplier: number)
	track:AdjustSpeed(PaddleConfig.STROKE_ANIM_SPEED * speedMultiplier)
end

local function startBaseLayers()
	if sitTrack and not sitTrack.IsPlaying then
		sitTrack:Play(0.2)
	end
	if staticTrack and not staticTrack.IsPlaying then
		staticTrack:Play(0.2)
	end
end

local function stopStaticForStroke()
	if staticTrack and staticTrack.IsPlaying then
		staticTrack:Stop(0.1)
	end
end

local function playStroke(side: PaddleSide, speedMultiplier: number)
	local track = strokeTracks[side]
	if not track then
		return
	end

	stopStaticForStroke()
	track:Play(0.1)
	playStrokeSpeed(track, speedMultiplier)
end

local function disconnectSoloStopped()
	if soloStoppedConnection then
		soloStoppedConnection:Disconnect()
		soloStoppedConnection = nil
	end
end

local function onStrokeFinished()
	startBaseLayers()
end

local function onSoloStrokeFinished()
	soloActiveSide = nil
	soloSpamming = false
	disconnectSoloStopped()
	onStrokeFinished()

	if soloPendingSide then
		local pending = soloPendingSide
		soloPendingSide = nil
		soloSpamming = true
		PaddleAnimationController._startSoloStroke(pending)
	end
end

local function bindStrokeStopped(track: AnimationTrack, onFinished: () -> ())
	disconnectSoloStopped()
	soloStoppedConnection = track.Stopped:Connect(onFinished)
end

local function getStrokeFallbackDelay(speedMultiplier: number): number
	local side = soloActiveSide
	local track = if side then strokeTracks[side] else nil
	if track and track.Length > 0 then
		return track.Length / (PaddleConfig.STROKE_ANIM_SPEED * speedMultiplier)
	end
	return PaddleConfig.STROKE_ANIM_DURATION
end

function PaddleAnimationController._startSoloStroke(side: PaddleSide)
	local multiplier = if soloSpamming then PaddleConfig.SPAM_ANIM_SPEED_MULTIPLIER else 1
	soloActiveSide = side

	local track = strokeTracks[side]
	if not track then
		task.delay(getStrokeFallbackDelay(multiplier), function()
			if soloActiveSide ~= side then
				return
			end
			onSoloStrokeFinished()
		end)
		return
	end

	playStroke(side, multiplier)
	bindStrokeStopped(track, onSoloStrokeFinished)
end

function PaddleAnimationController.init(humanoid: Humanoid, isTeamMode: boolean)
	PaddleAnimationController.stop()
	teamControls = isTeamMode

	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	sitTrack = loadTrack(PaddleConfig.PADDLE_SIT_IDLE_ANIM_ID, PRIORITY_SIT, true)
	staticTrack = loadTrack(PaddleConfig.PADDLE_STATIC_ANIM_ID, PRIORITY_STATIC, true)

	strokeTracks = {}
	for _, side in { "left", "right" } do
		local animId = if side == "right"
			then PaddleConfig.PADDLE_RIGHT_ANIM_ID
			else PaddleConfig.PADDLE_LEFT_ANIM_ID
		local track = loadTrack(animId, PRIORITY_STROKE, false)
		if track then
			strokeTracks[side] = track
		end
	end

	startBaseLayers()
end

function PaddleAnimationController.stop()
	disconnectSoloStopped()

	for _, track in strokeTracks do
		track:Stop(0.1)
	end
	if sitTrack then
		sitTrack:Stop(0.1)
	end
	if staticTrack then
		staticTrack:Stop(0.1)
	end

	strokeTracks = {}
	sitTrack = nil
	staticTrack = nil
	animator = nil
	soloActiveSide = nil
	soloPendingSide = nil
	soloSpamming = false
	teamControls = false
end

function PaddleAnimationController.handleInput(side: PaddleSide)
	if teamControls then
		local track = strokeTracks[side]
		playStroke(side, 1)
		if track then
			bindStrokeStopped(track, onStrokeFinished)
		end
		return
	end

	if not soloActiveSide then
		soloSpamming = false
		PaddleAnimationController._startSoloStroke(side)
		return
	end

	soloSpamming = true
	soloPendingSide = side

	local activeTrack = if soloActiveSide then strokeTracks[soloActiveSide] else nil
	if activeTrack and activeTrack.IsPlaying then
		playStrokeSpeed(activeTrack, PaddleConfig.SPAM_ANIM_SPEED_MULTIPLIER)
	end
end

function PaddleAnimationController.playRemoteStroke(side: PaddleSide, _speedMultiplier: number)
	if not teamControls then
		return
	end

	local track = strokeTracks[side]
	playStroke(side, 1)
	if track then
		bindStrokeStopped(track, onStrokeFinished)
	end
end

return PaddleAnimationController
