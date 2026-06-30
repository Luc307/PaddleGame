local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)
local PaddleGripUtil = require(ReplicatedStorage.Modules.PaddleGripUtil)

export type PaddleSide = PaddleGripUtil.PaddleSide

local GRIP_SIDE_ATTRIBUTE = "PaddleGripSide"

local PaddleGripController = {}

local activeCharacter: Model? = nil
local lastStrokeSide: PaddleSide? = nil
local renderConnection: RBXScriptConnection? = nil
local paddleAddedConnection: RBXScriptConnection? = nil

local function getDefaultSide(): PaddleSide
	local configured = PaddleConfig.PADDLE_DEFAULT_SIDE
	if configured == "left" or configured == "right" then
		return configured
	end
	return "right"
end

local function resolveSide(character: Model): PaddleSide
	local attributeSide = character:GetAttribute(GRIP_SIDE_ATTRIBUTE)
	if attributeSide == "left" or attributeSide == "right" then
		return attributeSide
	end
	return lastStrokeSide or getDefaultSide()
end

local function syncPaddle()
	local character = activeCharacter
	if not character then
		return
	end

	local paddleModel = PaddleGripUtil.findPaddleModel(character)
	if not paddleModel then
		return
	end

	local side = resolveSide(character)
	PaddleGripUtil.syncPaddleForSide(character, paddleModel, side)
	lastStrokeSide = side
end

local function bindPaddleWatcher(character: Model)
	if paddleAddedConnection then
		paddleAddedConnection:Disconnect()
		paddleAddedConnection = nil
	end

	local modelName = PaddleConfig.PADDLE_MODEL_NAME
	if not modelName then
		return
	end

	if character:FindFirstChild(modelName) then
		task.defer(syncPaddle)
	end

	paddleAddedConnection = character.ChildAdded:Connect(function(child)
		if child.Name == modelName and child:IsA("Model") then
			PaddleGripUtil.releaseAllPaddleGrips(character, child)
			task.defer(syncPaddle)
		end
	end)
end

function PaddleGripController.start(character: Model)
	PaddleGripController.stop()

	activeCharacter = character
	lastStrokeSide = resolveSide(character)

	bindPaddleWatcher(character)
	task.defer(syncPaddle)

	renderConnection = RunService.RenderStepped:Connect(syncPaddle)
end

function PaddleGripController.stop()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if paddleAddedConnection then
		paddleAddedConnection:Disconnect()
		paddleAddedConnection = nil
	end

	if activeCharacter then
		local paddleModel = PaddleGripUtil.findPaddleModel(activeCharacter)
		PaddleGripUtil.releaseAllPaddleGrips(activeCharacter, paddleModel)
		activeCharacter:SetAttribute(GRIP_SIDE_ATTRIBUTE, nil)
	end

	activeCharacter = nil
	lastStrokeSide = nil
end

function PaddleGripController.beginStroke(side: PaddleSide)
	local character = activeCharacter
	if not character then
		return
	end

	character:SetAttribute(GRIP_SIDE_ATTRIBUTE, side)
	lastStrokeSide = side
end

return PaddleGripController
