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
}

local PlayerAttachmentService = {}

local attachments: { [Player]: AttachmentRecord } = {}

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

function PlayerAttachmentService.isAttached(player: Player): boolean
	return attachments[player] ~= nil
end

function PlayerAttachmentService.snapWithoutWeld(player: Player, attachPart: BasePart, localOffset: CFrame)
	PlayerAttachmentService.detach(player)

	local character, humanoid, rootPart = getCharacterParts(player)
	if not character or not humanoid or not rootPart then
		return
	end

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
	}

	humanoid.Sit = false
	humanoid.PlatformStand = true
	humanoid.AutoJumpEnabled = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	rootPart.Anchored = true
	rootPart.CFrame = attachPart.CFrame * localOffset
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
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
	}

	humanoid.Sit = false
	humanoid.PlatformStand = true
	humanoid.AutoJumpEnabled = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	rootPart.Anchored = false
	rootPart.CFrame = attachPart.CFrame * localOffset

	record.weld.Part0 = attachPart
	record.weld.Part1 = rootPart
	record.weld.Parent = rootPart

	attachments[player] = record
end

function PlayerAttachmentService.detach(player: Player)
	local record = attachments[player]
	if not record then
		return
	end

	if record.weld then
		record.weld:Destroy()
	end

	local character, humanoid = getCharacterParts(player)
	if character and humanoid then
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
