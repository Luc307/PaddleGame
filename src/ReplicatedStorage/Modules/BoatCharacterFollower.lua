local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RENDER_STEP = "BoatCharacterFollow"

local BoatCharacterFollower = {}

local player = Players.LocalPlayer
local active = false
local getCharacterCFrame: (() -> CFrame?)? = nil
local bound = false

local function clearServerWelds(character: Model)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	for _, child in rootPart:GetChildren() do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function updateFollow()
	if not active or not getCharacterCFrame then
		return
	end

	local targetCFrame = getCharacterCFrame()
	if not targetCFrame then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	clearServerWelds(character)

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	rootPart.Anchored = true
	rootPart.CFrame = targetCFrame
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

function BoatCharacterFollower.start(resolveCharacterCFrame: () -> CFrame?)
	BoatCharacterFollower.stop()

	local character = player.Character
	if character then
		clearServerWelds(character)
	end

	getCharacterCFrame = resolveCharacterCFrame
	active = true

	if not bound then
		RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Input.Value + 1, updateFollow)
		bound = true
	end

	updateFollow()
end

function BoatCharacterFollower.stop()
	active = false
	getCharacterCFrame = nil

	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			rootPart.Anchored = false
		end
	end

	if bound then
		RunService:UnbindFromRenderStep(RENDER_STEP)
		bound = false
	end
end

return BoatCharacterFollower
