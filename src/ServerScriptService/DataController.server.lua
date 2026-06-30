local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")

local Remotes = require(RS.Modules.RemoteRegistry)
local SettingsConfig = require(RS.Modules.SettingsConfig)

local DataEvent = Remotes.Events.Data
local LoadingEvent = Remotes.Events.Loading
local DataFunction = Remotes.Functions.Data

local PDM = require(SS.Modules.PlayerDataManager)
local Help = require(SS.Modules.Help)

local DanceAnimationId = "rbxassetid://126553137453494"
local FADE_DURATION = 1
local FADE_SETTLE_BUFFER = 0.15
local SLOT_SPACING = 50
local DANCE_LOAD_TIMEOUT = 5
local DANCE_FALLBACK_DURATION = 4
local SPAWN_DROP_HEIGHT = 10
local LANDING_TIMEOUT = 4
local INTRO_READY_WAIT = 0.35
local TESTING = false

local takenSlots: { [number]: boolean } = {}
local slotByPlayer: { [number]: number } = {}

local function acquireSlot(player: Player): number
	local existing = slotByPlayer[player.UserId]
	if existing then
		return existing
	end

	local slot = 0
	while takenSlots[slot] do
		slot += 1
	end

	takenSlots[slot] = true
	slotByPlayer[player.UserId] = slot
	return slot
end

local function releaseSlot(player: Player)
	local slot = slotByPlayer[player.UserId]
	if slot == nil then
		return
	end

	takenSlots[slot] = nil
	slotByPlayer[player.UserId] = nil
end

local function getSpawnCFrame(): CFrame
	local spawnLocation = workspace:FindFirstChild("SpawnLocation", true)
	if spawnLocation and spawnLocation:IsA("SpawnLocation") then
		return spawnLocation.CFrame + Vector3.new(0, 3, 0)
	end

	local spawnPoint = workspace:FindFirstChild("SpawnPoint", true)
	if spawnPoint and spawnPoint:IsA("BasePart") then
		return spawnPoint.CFrame + Vector3.new(0, 3, 0)
	end

	return CFrame.new(0, 5, 0)
end

local function getLoadingStageCFrame(): (CFrame, BasePart?)
	local loadingStage = workspace:FindFirstChild("LoadingStage")
	if loadingStage and loadingStage:IsA("BasePart") then
		return loadingStage.CFrame, loadingStage
	end

	return CFrame.new(0, 10, 0), nil
end

local function getLoadingCFrame(player: Player): (CFrame, Vector3)
	local stageCFrame, loadingStage = getLoadingStageCFrame()
	local slot = acquireSlot(player)
	local slotOffset = stageCFrame.RightVector * (slot * SLOT_SPACING)
	local heightOffset = if loadingStage then loadingStage.Size.Y / 2 + 3 else 3
	local position = stageCFrame.Position + slotOffset + Vector3.new(0, heightOffset, 0)

	local stageForward = stageCFrame.LookVector
	local playerCFrame = CFrame.lookAt(position, position - stageForward)

	return playerCFrame, stageForward
end

local function setAnimateEnabled(character: Model, enabled: boolean)
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("Script") then
		animate.Disabled = not enabled
	end
end

local function freezeCharacter(humanoid: Humanoid, rootPart: BasePart, holdCFrame: CFrame?)
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
	rootPart.Anchored = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	if holdCFrame then
		rootPart.CFrame = holdCFrame
	end
end

local function unfreezeCharacter(humanoid: Humanoid, rootPart: BasePart)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	humanoid.PlatformStand = false
	rootPart.Anchored = false
end

local function playDance(humanoid: Humanoid): AnimationTrack
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	for _, playingTrack in animator:GetPlayingAnimationTracks() do
		playingTrack:Stop(0)
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	task.wait()

	local animation = Instance.new("Animation")
	animation.AnimationId = DanceAnimationId

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false

	local deadline = os.clock() + DANCE_LOAD_TIMEOUT
	while track.Length == 0 and os.clock() < deadline do
		task.wait()
	end

	track:Play(0, 1, 1.5)

	deadline = os.clock() + DANCE_LOAD_TIMEOUT
	while not track.IsPlaying and os.clock() < deadline do
		task.wait()
	end

	return track
end

local function waitForDance(track: AnimationTrack)
	if track.IsPlaying and track.Length > 0 then
		track.Stopped:Wait()
		return
	end

	if track.Length > 0 then
		task.wait(track.Length)
		return
	end

	task.wait(DANCE_FALLBACK_DURATION)
end

local function waitForLanding(humanoid: Humanoid): boolean
	local deadline = os.clock() + LANDING_TIMEOUT

	while os.clock() < deadline do
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Landed
			or state == Enum.HumanoidStateType.Running
			or state == Enum.HumanoidStateType.RunningNoPhysics
		then
			if humanoid.FloorMaterial ~= Enum.Material.Air then
				return true
			end
		end

		task.wait()
	end

	return false
end

local function finishIntroState(player: Player, character: Model)
	setAnimateEnabled(character, true)
	Help.EnableControl(player)
	releaseSlot(player)

	local health = character:FindFirstChild("Health")
	if health and health:IsA("Script") then
		health.Disabled = false
	end

	player:SetAttribute("IntroComplete", true)
end

local function skipIntro(player: Player, character: Model)
	finishIntroState(player, character)
	LoadingEvent:FireClient(player, "Skip")
end

local function PlayerJoied(player: Player, character: Model, loadingCFrame: CFrame)
	if player:GetAttribute("IntroComplete") then
		return
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	freezeCharacter(humanoid, rootPart, loadingCFrame)

	local track = playDance(humanoid)
	waitForDance(track)
	track:Stop(0.15)

	freezeCharacter(humanoid, rootPart, loadingCFrame)

	LoadingEvent:FireClient(player, "FadeOut")
	task.wait(FADE_DURATION + FADE_SETTLE_BUFFER)

	local spawnCFrame = getSpawnCFrame()
	local dropCFrame = spawnCFrame + Vector3.new(0, SPAWN_DROP_HEIGHT, 0)
	freezeCharacter(humanoid, rootPart, dropCFrame)
	character:PivotTo(dropCFrame)
	unfreezeCharacter(humanoid, rootPart)

	task.wait(0.1)

	LoadingEvent:FireClient(player, "FadeIn")

	local landed = false
	task.spawn(function()
		landed = waitForLanding(humanoid)
	end)

	task.wait(FADE_DURATION + FADE_SETTLE_BUFFER)

	local deadline = os.clock() + LANDING_TIMEOUT
	while not landed and os.clock() < deadline do
		task.wait()
	end

	LoadingEvent:FireClient(player, "End")
	finishIntroState(player, character)
end

local function ApplyBlockyR15(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.RigType = Enum.HumanoidRigType.R15

	local description = humanoid:GetAppliedDescription()

	description.Head = 0
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0

	humanoid:ApplyDescription(description)
end

local function skipIntroToSpawn(player: Player, character: Model)
	ApplyBlockyR15(character)
	character:PivotTo(getSpawnCFrame())
	skipIntro(player, character)
end

local function onCharacterAdded(player: Player, character: Model)
	if TESTING or not SettingsConfig.INTRO_ENABLED then
		skipIntroToSpawn(player, character)
		return
	end

	if player:GetAttribute("IntroComplete") then
		ApplyBlockyR15(character)
		return
	end

	local health = character:FindFirstChild("Health")
	if health and health:IsA("Script") then
		health.Disabled = true
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local loadingCFrame, stageForward = getLoadingCFrame(player)

	Help.DisableControl(player)
	setAnimateEnabled(character, false)
	freezeCharacter(humanoid, rootPart, loadingCFrame)
	character:PivotTo(loadingCFrame)

	ApplyBlockyR15(character)
	task.wait(INTRO_READY_WAIT)

	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	freezeCharacter(humanoid, rootPart, loadingCFrame)
	character:PivotTo(loadingCFrame)

	LoadingEvent:FireClient(player, "Start", stageForward)
	task.spawn(PlayerJoied, player, character, loadingCFrame)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	PDM.new(player)
end)

Players.PlayerRemoving:Connect(function(player)
	releaseSlot(player)
	PDM.Remove(player)
end)

DataEvent.OnServerEvent:Connect(function(player, key, value)
	PDM.Set(player, key, value)
end)

DataFunction.OnServerInvoke = function(player, key)
	return PDM.Get(player, key)
end
