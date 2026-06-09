local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BoatVisualService = require(script.Parent.BoatVisualService)

local RENDER_STEP = "BoatTeamCharacterPlacer"

export type TeamRosterEntry = {
	userId: number,
	seatName: string,
	seatLocalOffset: CFrame,
}

local BoatTeamCharacterPlacer = {}

local player = Players.LocalPlayer
local active = false
local boatId: string? = nil
local roster: { TeamRosterEntry } = {}
local bound = false

local function clearWelds(rootPart: BasePart)
	for _, child in rootPart:GetChildren() do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
end

local function updatePlacement()
	if not active or not boatId then
		return
	end

	for _, member in roster do
		if member.userId == player.UserId then
			continue
		end

		local otherPlayer = Players:GetPlayerByUserId(member.userId)
		if not otherPlayer then
			continue
		end

		local character = otherPlayer.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local targetCFrame = BoatVisualService.getTeamMemberCFrame(boatId, member.seatName, member.seatLocalOffset)
		if not targetCFrame then
			continue
		end

		clearWelds(rootPart)
		rootPart.Anchored = true
		rootPart.CFrame = targetCFrame
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function BoatTeamCharacterPlacer.start(activeBoatId: string, teamRoster: { TeamRosterEntry })
	BoatTeamCharacterPlacer.stop()

	boatId = activeBoatId
	roster = teamRoster
	active = true

	if not bound then
		RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Input.Value + 2, updatePlacement)
		bound = true
	end

	updatePlacement()
end

function BoatTeamCharacterPlacer.stop()
	active = false
	boatId = nil
	roster = {}

	if bound then
		RunService:UnbindFromRenderStep(RENDER_STEP)
		bound = false
	end
end

return BoatTeamCharacterPlacer
