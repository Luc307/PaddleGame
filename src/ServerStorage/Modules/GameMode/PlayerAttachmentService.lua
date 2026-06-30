local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)
local PaddleGripUtil = require(ReplicatedStorage.Modules.PaddleGripUtil)

export type PaddleSide = PaddleGripUtil.PaddleSide

local GRIP_SIDE_ATTRIBUTE = "PaddleGripSide"

local DISABLED_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Seated,
}

export type AttachmentRecord = {
	weld: WeldConstraint?,
	attachPart: BasePart,
	localOffset: CFrame,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoJumpEnabled: boolean,
	disabledStates: { [Enum.HumanoidStateType]: boolean },
	animateWasEnabled: boolean?,
	paddleModel: Model?,
	lastStrokeSide: PaddleSide?,
}

local PlayerAttachmentService = {}

local attachments: { [Player]: AttachmentRecord } = {}

local function preparePaddleParts(paddleModel: Model)
	for _, descendant in paddleModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
end

local function weldPaddleAssembly(paddleModel: Model, gripPart: BasePart)
	for _, descendant in paddleModel:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= gripPart then
			local weld = Instance.new("WeldConstraint")
			weld.Name = `PaddleWeld_{descendant.Name}`
			weld.Part0 = gripPart
			weld.Part1 = descendant
			weld.Parent = gripPart
		end
	end
end

local function setGripSideAttribute(character: Model, side: PaddleSide)
	character:SetAttribute(GRIP_SIDE_ATTRIBUTE, side)
end

local function attachPaddleModel(character: Model): Model?
	local modelName = PaddleConfig.PADDLE_MODEL_NAME
	if not modelName then
		return nil
	end

	local replications = ReplicatedStorage:FindFirstChild("Replications")
	if not replications then
		warn("[PlayerAttachment] ReplicatedStorage.Replications fehlt")
		return nil
	end

	local template = replications:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then
		warn(`[PlayerAttachment] Paddel-Modell "{modelName}" nicht in Replications`)
		return nil
	end

	if not PaddleGripUtil.getRightHand(character) then
		warn("[PlayerAttachment] RightHand / Right Arm fehlt am Character")
		return nil
	end

	local paddleClone = template:Clone()
	local assemblyRoot = PaddleGripUtil.findPaddleAssemblyRoot(paddleClone)
	if not assemblyRoot then
		paddleClone:Destroy()
		warn(`[PlayerAttachment] Paddel "{modelName}" hat keinen Griff-Part`)
		return nil
	end

	paddleClone.PrimaryPart = assemblyRoot
	preparePaddleParts(paddleClone)
	weldPaddleAssembly(paddleClone, assemblyRoot)
	paddleClone.Parent = character

	local defaultSide = PaddleConfig.PADDLE_DEFAULT_SIDE :: PaddleSide
	setGripSideAttribute(character, defaultSide)

	return paddleClone
end

function PlayerAttachmentService.beginStroke(player: Player, side: PaddleSide)
	local record = attachments[player]
	if not record then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	record.lastStrokeSide = side
	setGripSideAttribute(character, side)
end

local function getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		return nil, nil, nil
	end

	return character, humanoid, rootPart
end

local function lockCharacterForBoat(character: Model, humanoid: Humanoid): (boolean?, { [Enum.HumanoidStateType]: boolean })
	local disabledStates = {}
	for _, state in DISABLED_STATES do
		disabledStates[state] = humanoid:GetStateEnabled(state)
		humanoid:SetStateEnabled(state, false)
	end

	local animate = character:FindFirstChild("Animate")
	local animateWasEnabled: boolean? = nil
	if animate and animate:IsA("Script") then
		animateWasEnabled = not animate.Disabled
		animate.Disabled = true
	end

	humanoid.Sit = false
	humanoid.PlatformStand = true
	humanoid.AutoJumpEnabled = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end

	return animateWasEnabled, disabledStates
end

function PlayerAttachmentService.isAttached(player: Player): boolean
	return attachments[player] ~= nil
end

function PlayerAttachmentService.snapWithoutWeld(player: Player, attachPart: BasePart, localOffset: CFrame)
	PlayerAttachmentService.detach(player)

	local character, humanoid, rootPart = getCharacterParts(player)
	if not character or not humanoid or not rootPart then
		return
	end

	local animateWasEnabled, disabledStates = lockCharacterForBoat(character, humanoid)
	local defaultSide = PaddleConfig.PADDLE_DEFAULT_SIDE :: PaddleSide

	attachments[player] = {
		weld = nil,
		attachPart = attachPart,
		localOffset = localOffset,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoJumpEnabled = humanoid.AutoJumpEnabled,
		disabledStates = disabledStates,
		animateWasEnabled = animateWasEnabled,
		paddleModel = attachPaddleModel(character),
		lastStrokeSide = defaultSide,
	}

	rootPart.Anchored = true
	rootPart.CFrame = attachPart.CFrame * localOffset
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
end

function PlayerAttachmentService.weldToBoat(player: Player, attachPart: BasePart, localOffset: CFrame)
	PlayerAttachmentService.attach(player, attachPart, localOffset)
end

function PlayerAttachmentService.syncPositions()
	for player, record in attachments do
		if record.weld then
			continue
		end

		local _, _, rootPart = getCharacterParts(player)
		if not rootPart or not record.attachPart.Parent then
			continue
		end

		rootPart.CFrame = record.attachPart.CFrame * record.localOffset
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function PlayerAttachmentService.attach(player: Player, attachPart: BasePart, localOffset: CFrame)
	PlayerAttachmentService.detach(player)

	local character, humanoid, rootPart = getCharacterParts(player)
	if not character or not humanoid or not rootPart then
		return
	end

	local animateWasEnabled, disabledStates = lockCharacterForBoat(character, humanoid)
	local defaultSide = PaddleConfig.PADDLE_DEFAULT_SIDE :: PaddleSide

	local record: AttachmentRecord = {
		weld = Instance.new("WeldConstraint"),
		attachPart = attachPart,
		localOffset = localOffset,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoJumpEnabled = humanoid.AutoJumpEnabled,
		disabledStates = disabledStates,
		animateWasEnabled = animateWasEnabled,
		paddleModel = nil,
		lastStrokeSide = defaultSide,
	}

	rootPart.Anchored = false
	rootPart.CFrame = attachPart.CFrame * localOffset

	record.weld.Part0 = attachPart
	record.weld.Part1 = rootPart
	record.weld.Parent = rootPart

	attachments[player] = record
	record.paddleModel = attachPaddleModel(character)
end

function PlayerAttachmentService.detach(player: Player)
	local record = attachments[player]
	if not record then
		return
	end

	if record.weld then
		record.weld:Destroy()
	end

	if record.paddleModel then
		record.paddleModel:Destroy()
	end

	local character, humanoid = getCharacterParts(player)
	if character and humanoid then
		local paddleModel = record.paddleModel
		PaddleGripUtil.releaseAllPaddleGrips(character, paddleModel)
		character:SetAttribute(GRIP_SIDE_ATTRIBUTE, nil)

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			rootPart.Anchored = false
			pcall(function()
				rootPart:SetNetworkOwnershipAuto()
			end)
		end

		for state, wasEnabled in record.disabledStates do
			humanoid:SetStateEnabled(state, wasEnabled)
		end

		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid.WalkSpeed = record.walkSpeed
		humanoid.JumpPower = record.jumpPower
		humanoid.JumpHeight = record.jumpHeight
		humanoid.AutoJumpEnabled = record.autoJumpEnabled

		local animate = character:FindFirstChild("Animate")
		if animate and animate:IsA("Script") and record.animateWasEnabled ~= nil then
			animate.Disabled = not record.animateWasEnabled
		end
	end

	attachments[player] = nil
end

function PlayerAttachmentService.detachAll(players: { Player })
	for _, player in players do
		PlayerAttachmentService.detach(player)
	end
end

return PlayerAttachmentService
