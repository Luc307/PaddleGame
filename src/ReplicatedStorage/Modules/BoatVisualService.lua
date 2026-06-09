local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BoatAuthoritySync = require(script.Parent.BoatAuthoritySync)
local BoatCheckpoint = require(script.Parent.BoatCheckpoint)
local BoatConfig = require(script.Parent.BoatConfig)
local BoatPhysics = require(script.Parent.BoatPhysics)

local RENDER_STEP = "BoatVisualPhysics"

type VisualRecord = {
	boatId: string,
	model: Model,
	root: BasePart,
	seatPart: BasePart,
	authorityModel: Model,
	attachOffset: CFrame,
	seatLocalOffset: CFrame,
	modelSeatOnPhysics: CFrame,
	strokes: { BoatPhysics.Stroke },
	strokeCount: number,
	checkpointSentForIdle: boolean,
	hiddenAuthorityParts: { BasePart },
	simState: BoatPhysics.KinematicState,
	displayState: BoatPhysics.KinematicState,
	timeAccumulator: number,
}

local BoatVisualService = {}

local visuals: { [string]: VisualRecord } = {}
local renderBound = false

local function getStrokeTime(): number
	return Workspace:GetServerTimeNow()
end

local function isRecordIdle(record: VisualRecord): boolean
	return BoatCheckpoint.isIdle(record.strokes, getStrokeTime())
end

local function resolveAuthorityModel(boatId: string): Model?
	local model = Workspace:FindFirstChild(boatId, true)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

local function resolveRoot(model: Model): BasePart?
	local part = model:FindFirstChild("PhysicsPart", true)
	if part and part:IsA("BasePart") then
		return part
	end

	part = model:FindFirstChild("Seat")
	if part and part:IsA("BasePart") then
		return part
	end

	part = model:FindFirstChild("SeatRight", true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function prepareVisualClone(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function setAuthorityVisibility(authorityModel: Model, hiddenParts: { BasePart }, visible: boolean)
	local modifier = if visible then 0 else 1
	for _, part in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = modifier
		end
	end
	for _, descendant in authorityModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = modifier
		end
	end
end

local function hideAuthorityModel(authorityModel: Model): { BasePart }
	if BoatConfig.TEST then
		return {}
	end

	local hidden: { BasePart } = {}
	for _, descendant in authorityModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
			table.insert(hidden, descendant)
		end
	end
	return hidden
end

local function restoreAuthorityModel(authorityModel: Model, hiddenParts: { BasePart })
	for _, part in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	setAuthorityVisibility(authorityModel, hiddenParts, true)
end

local function syncVisualTransform(record: VisualRecord)
	local target = record.displayState.cframe
	local current = record.root.CFrame
	local delta = target * current:Inverse()

	for _, part in record.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
		end
	end
end

local function stepVisual(record: VisualRecord, dt: number)
	local now = getStrokeTime()
	record.strokes = BoatPhysics.applyKinematic(record.simState, record.strokes, now, dt, BoatConfig)
	BoatAuthoritySync.alignState(record.displayState, record.simState)
	syncVisualTransform(record)
end

local function updateVisuals(dt: number)
	local fixedDt = BoatConfig.FIXED_TIMESTEP

	for _, record in visuals do
		if not record.model.Parent then
			continue
		end

		record.timeAccumulator += dt
		while record.timeAccumulator >= fixedDt do
			stepVisual(record, fixedDt)
			record.timeAccumulator -= fixedDt
		end
	end
end

local function ensureRenderStep()
	if renderBound then
		return
	end

	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Input.Value, updateVisuals)
	renderBound = true
end

local function releaseRenderStepIfEmpty()
	if next(visuals) ~= nil or not renderBound then
		return
	end

	RunService:UnbindFromRenderStep(RENDER_STEP)
	renderBound = false
end

local function resolveSeatPart(model: Model, seatName: string?): BasePart?
	if seatName then
		local seat = model:FindFirstChild(seatName, true)
		if seat and seat:IsA("BasePart") then
			return seat
		end
	end

	for _, name in { "Seat", "SeatRight", "SeatLeft" } do
		local seat = model:FindFirstChild(name, true)
		if seat and seat:IsA("BasePart") then
			return seat
		end
	end

	return nil
end

local function resolveSpawnCFrame(record: VisualRecord, authorityRoot: BasePart): CFrame
	local character = Players.LocalPlayer.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil

	if rootPart and record.seatPart.Parent then
		local targetSeat = rootPart.CFrame * record.seatLocalOffset:Inverse()
		return targetSeat * record.modelSeatOnPhysics:Inverse()
	end

	return authorityRoot.CFrame
end

local function alignVisual(record: VisualRecord)
	local authorityRoot = resolveRoot(record.authorityModel)
	if not authorityRoot then
		return
	end

	local spawnCFrame = resolveSpawnCFrame(record, authorityRoot)
	record.simState.cframe = spawnCFrame
	record.simState.linearVelocity = Vector3.zero
	record.simState.angularVelocity = Vector3.zero
	BoatAuthoritySync.alignState(record.displayState, record.simState)
	syncVisualTransform(record)
	setAuthorityVisibility(record.authorityModel, record.hiddenAuthorityParts, BoatConfig.TEST)
end

function BoatVisualService.start(
	boatId: string,
	attachOffset: CFrame?,
	seatName: string?,
	seatLocalOffset: CFrame?
): boolean
	if visuals[boatId] then
		return true
	end

	local authorityModel = resolveAuthorityModel(boatId)
	if not authorityModel then
		return false
	end

	local authorityRoot = resolveRoot(authorityModel)
	if not authorityRoot then
		return false
	end

	local authoritySeat = resolveSeatPart(authorityModel, seatName)
	if not authoritySeat then
		return false
	end

	local visualModel = authorityModel:Clone()
	visualModel.Name = `Visual_{boatId}`
	local visualRoot = resolveRoot(visualModel)
	if not visualRoot then
		visualModel:Destroy()
		return false
	end

	prepareVisualClone(visualModel)
	visualModel.PrimaryPart = visualRoot

	local folder = Workspace:FindFirstChild("ClientVisualBoats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientVisualBoats"
		folder.Parent = Workspace
	end

	local offset = if typeof(attachOffset) == "CFrame" then attachOffset else CFrame.new(0, 3, 0)
	local seatOffset = if typeof(seatLocalOffset) == "CFrame" then seatLocalOffset else CFrame.new(0, 3, 0)
	local visualSeat = resolveSeatPart(visualModel, seatName)
	if not visualSeat then
		visualModel:Destroy()
		return false
	end

	local hiddenParts = hideAuthorityModel(authorityModel)
	local initialState = {
		cframe = authorityRoot.CFrame,
		linearVelocity = Vector3.zero,
		angularVelocity = Vector3.zero,
	}

	visuals[boatId] = {
		boatId = boatId,
		model = visualModel,
		root = visualRoot,
		seatPart = visualSeat,
		authorityModel = authorityModel,
		attachOffset = offset,
		seatLocalOffset = seatOffset,
		modelSeatOnPhysics = authorityRoot.CFrame:ToObjectSpace(authoritySeat.CFrame),
		strokes = {},
		strokeCount = 0,
		checkpointSentForIdle = false,
		hiddenAuthorityParts = hiddenParts,
		simState = BoatAuthoritySync.copyState(initialState),
		displayState = BoatAuthoritySync.copyState(initialState),
		timeAccumulator = 0,
	}

	visualModel.Parent = folder
	alignVisual(visuals[boatId])
	ensureRenderStep()

	task.spawn(function()
		for _ = 1, 5 do
			RunService.Heartbeat:Wait()
			local record = visuals[boatId]
			if not record then
				break
			end
			alignVisual(record)
		end
	end)

	return true
end

function BoatVisualService.stop(boatId: string?)
	if boatId then
		local record = visuals[boatId]
		if record then
			restoreAuthorityModel(record.authorityModel, record.hiddenAuthorityParts)
			record.model:Destroy()
			visuals[boatId] = nil
		end
	else
		for id, record in visuals do
			restoreAuthorityModel(record.authorityModel, record.hiddenAuthorityParts)
			record.model:Destroy()
			visuals[id] = nil
		end
	end

	releaseRenderStepIfEmpty()
end

function BoatVisualService.applyStroke(boatId: string, side: string, startTime: number)
	local record = visuals[boatId]
	if not record then
		return
	end

	table.insert(record.strokes, { side = side :: BoatPhysics.PaddleSide, startTime = startTime })
	record.strokeCount += 1
	record.checkpointSentForIdle = false
end

function BoatVisualService.beginRetarget(_boatId: string, _payload: BoatAuthoritySync.AuthorityStatePayload)
end

function BoatVisualService.getCharacterCFrame(boatId: string): CFrame?
	local record = visuals[boatId]
	if record and record.seatPart.Parent then
		return record.seatPart.CFrame * record.seatLocalOffset
	end
	return nil
end

function BoatVisualService.getTeamMemberCFrame(boatId: string, seatName: string, seatLocalOffset: CFrame): CFrame?
	local record = visuals[boatId]
	if not record or not record.model.Parent then
		return nil
	end

	local seat = resolveSeatPart(record.model, seatName)
	if not seat then
		return nil
	end

	return seat.CFrame * seatLocalOffset
end

function BoatVisualService.isIdle(boatId: string): boolean
	local record = visuals[boatId]
	if not record then
		return false
	end
	return isRecordIdle(record)
end

function BoatVisualService.shouldSendCheckpoint(boatId: string): boolean
	local record = visuals[boatId]
	if not record then
		return false
	end

	if not isRecordIdle(record) or record.checkpointSentForIdle then
		return false
	end

	record.checkpointSentForIdle = true
	return true
end

function BoatVisualService.getCheckpoint(boatId: string): BoatCheckpoint.CheckpointPayload?
	local record = visuals[boatId]
	if not record then
		return nil
	end

	return {
		boatId = boatId,
		serverTime = getStrokeTime(),
		cframe = record.simState.cframe,
		linearVelocity = record.simState.linearVelocity,
		angularVelocity = record.simState.angularVelocity,
		strokeCount = record.strokeCount,
	}
end

function BoatVisualService.updateFreeRoam(dt: number, root: BasePart, strokes: { BoatPhysics.Stroke }): { BoatPhysics.Stroke }
	local now = getStrokeTime()
	local updated = BoatPhysics.apply(root, strokes, now, dt, BoatConfig)

	local velocity = root.AssemblyLinearVelocity
	local angularVelocity = root.AssemblyAngularVelocity
	local step = Vector3.new(velocity.X, 0, velocity.Z) * dt
	root.CFrame = (root.CFrame + step) * CFrame.Angles(0, angularVelocity.Y * dt, 0)
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)

	return updated
end

return BoatVisualService
