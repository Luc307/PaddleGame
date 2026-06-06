local MAP_TEMPLATE_NAME = "GameMap"
local INSTANCES_FOLDER_NAME = "RaceInstances"
local INSTANCE_SPACING = 400

export type MapInstance = {
	id: number,
	root: Folder,
	slot: number,
	offset: Vector3,
}

local MapInstanceService = {}

local usedSlots: { [number]: boolean } = {}
local activeInstances: { [number]: MapInstance } = {}

local function getInstancesFolder(): Folder
	local folder = workspace:FindFirstChild(INSTANCES_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = INSTANCES_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function allocateSlot(): number
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

local function offsetInstance(root: Instance, offset: Vector3)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame += offset
		end
	end
end

function MapInstanceService.acquire(sessionId: number): MapInstance?
	local template = workspace:FindFirstChild(MAP_TEMPLATE_NAME)
	if not template then
		warn(`[MapInstance] Workspace.{MAP_TEMPLATE_NAME} fehlt`)
		return nil
	end

	local slot = allocateSlot()
	local offset = Vector3.new(slot * INSTANCE_SPACING, 0, 0)
	local clone = template:Clone()
	clone.Name = `Session_{sessionId}`
	offsetInstance(clone, offset)
	clone.Parent = getInstancesFolder()

	local instance = {
		id = sessionId,
		root = clone,
		slot = slot,
		offset = offset,
	}

	activeInstances[sessionId] = instance
	return instance
end

function MapInstanceService.release(sessionId: number)
	local instance = activeInstances[sessionId]
	if not instance then
		return
	end

	usedSlots[instance.slot] = nil
	activeInstances[sessionId] = nil
	instance.root:Destroy()
end

function MapInstanceService.getModePart(instance: MapInstance, folderName: string, modeId: number): BasePart?
	local folder = instance.root:FindFirstChild(folderName)
	if not folder then
		return nil
	end

	local part = folder:FindFirstChild(`Mode{modeId}`)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

return MapInstanceService
