local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)

export type PaddleSide = "left" | "right"

local PaddleAnimationController = {}

local teamControls = false
local animator: Animator? = nil
local animTracks: { [string]: AnimationTrack } = {}

local soloActiveSide: PaddleSide? = nil
local soloPendingSide: PaddleSide? = nil
local soloSpamming = false
local soloStoppedConnection: RBXScriptConnection? = nil

local function strokeDuration(speedMultiplier: number): number
	return math.max(PaddleConfig.STROKE_ANIM_DURATION, 0.1) / speedMultiplier
end

local function getAnimId(side: PaddleSide): string?
	if side == "right" then
		return PaddleConfig.PADDLE_RIGHT_ANIM_ID
	end
	return PaddleConfig.PADDLE_LEFT_ANIM_ID
end

local function playSpeed(track: AnimationTrack, speedMultiplier: number)
	local duration = strokeDuration(speedMultiplier)
	if track.Length > 0 then
		track:AdjustSpeed(track.Length / duration)
	else
		track:AdjustSpeed(speedMultiplier)
	end
end

local function playTrack(side: PaddleSide, speedMultiplier: number)
	local track = animTracks[side]
	if not track then
		return
	end

	track:Play(0)
	playSpeed(track, speedMultiplier)
end

local function disconnectSoloStopped()
	if soloStoppedConnection then
		soloStoppedConnection:Disconnect()
		soloStoppedConnection = nil
	end
end

local function bindSoloStopped(track: AnimationTrack)
	disconnectSoloStopped()
	soloStoppedConnection = track.Stopped:Connect(function()
		soloActiveSide = nil
		soloSpamming = false
		disconnectSoloStopped()

		if soloPendingSide then
			local pending = soloPendingSide
			soloPendingSide = nil
			soloSpamming = true
			PaddleAnimationController._startSoloStroke(pending)
		end
	end)
end

function PaddleAnimationController._startSoloStroke(side: PaddleSide)
	local multiplier = if soloSpamming then PaddleConfig.SPAM_ANIM_SPEED_MULTIPLIER else 1
	soloActiveSide = side

	local track = animTracks[side]
	if not track then
		task.delay(strokeDuration(multiplier), function()
			if soloActiveSide ~= side then
				return
			end
			soloActiveSide = nil
			soloSpamming = false
			if soloPendingSide then
				local pending = soloPendingSide
				soloPendingSide = nil
				soloSpamming = true
				PaddleAnimationController._startSoloStroke(pending)
			end
		end)
		return
	end

	playTrack(side, multiplier)
	bindSoloStopped(track)
end

function PaddleAnimationController.init(humanoid: Humanoid, isTeamMode: boolean)
	PaddleAnimationController.stop()
	teamControls = isTeamMode

	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	animTracks = {}
	for _, side in { "left", "right" } do
		local animId = getAnimId(side :: PaddleSide)
		if animId then
			local animation = Instance.new("Animation")
			animation.AnimationId = animId
			animTracks[side] = (animator :: Animator):LoadAnimation(animation)
		end
	end
end

function PaddleAnimationController.stop()
	disconnectSoloStopped()
	for _, track in animTracks do
		track:Stop(0.1)
	end

	animTracks = {}
	animator = nil
	soloActiveSide = nil
	soloPendingSide = nil
	soloSpamming = false
	teamControls = false
end

function PaddleAnimationController.handleInput(side: PaddleSide)
	if teamControls then
		playTrack(side, 1)
		return
	end

	if not soloActiveSide then
		soloSpamming = false
		PaddleAnimationController._startSoloStroke(side)
		return
	end

	soloSpamming = true
	soloPendingSide = side

	local activeTrack = if soloActiveSide then animTracks[soloActiveSide] else nil
	if activeTrack and activeTrack.IsPlaying then
		playSpeed(activeTrack, PaddleConfig.SPAM_ANIM_SPEED_MULTIPLIER)
	end
end

function PaddleAnimationController.playRemoteStroke(side: PaddleSide, _speedMultiplier: number)
	if not teamControls then
		return
	end

	playTrack(side, 1)
end

return PaddleAnimationController
