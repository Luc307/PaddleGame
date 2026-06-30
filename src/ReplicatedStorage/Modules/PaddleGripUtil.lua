local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaddleConfig = require(ReplicatedStorage.Modules.PaddleConfig)

export type PaddleSide = "left" | "right"

export type GripAnchor = {
	part: BasePart,
	attachment: Attachment?,
}

export type GripMapping = {
	topHand: BasePart,
	pivotHand: BasePart,
	topAnchor: GripAnchor,
	pivotAnchor: GripAnchor,
}

local MOTOR_PIVOT = "PaddlePivotGrip"
local MOTOR_TOP = "PaddleTopGrip"

local PaddleGripUtil = {
	MOTOR_PIVOT = MOTOR_PIVOT,
	MOTOR_TOP = MOTOR_TOP,
}

function PaddleGripUtil.getRightHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

function PaddleGripUtil.getLeftHand(character: Model): BasePart?
	return (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")) :: BasePart?
end

function PaddleGripUtil.findPaddleModel(character: Model): Model?
	local modelName = PaddleConfig.PADDLE_MODEL_NAME
	if not modelName then
		return nil
	end

	local paddle = character:FindFirstChild(modelName)
	if paddle and paddle:IsA("Model") then
		return paddle
	end

	return nil
end

function PaddleGripUtil.getAttachmentC1(anchorPart: BasePart, attachment: Attachment): CFrame
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return attachment.CFrame
	end

	return anchorPart.CFrame:ToObjectSpace(attachment.WorldCFrame)
end

function PaddleGripUtil.findGripAnchor(paddleModel: Model, name: string?, fallbackPart: BasePart?): GripAnchor?
	if not name then
		return nil
	end

	local inst = paddleModel:FindFirstChild(name, true)
	if not inst then
		return nil
	end

	if inst:IsA("Attachment") then
		local parent = inst.Parent
		if parent and parent:IsA("BasePart") then
			return { part = parent, attachment = inst }
		end

		local hostPart = fallbackPart
			or paddleModel.PrimaryPart
			or paddleModel:FindFirstChildWhichIsA("BasePart", true)
		if hostPart and hostPart:IsA("BasePart") then
			return { part = hostPart, attachment = inst }
		end

		warn(`[PaddleGrip] Attachment "{name}" ohne Part-Parent`)
		return nil
	end

	if inst:IsA("BasePart") then
		local childAttachment = inst:FindFirstChildWhichIsA("Attachment")
		return { part = inst, attachment = childAttachment }
	end

	return nil
end

function PaddleGripUtil.findPaddleAssemblyRoot(paddleModel: Model): BasePart?
	local topAnchor = PaddleGripUtil.findGripAnchor(paddleModel, PaddleConfig.PADDLE_TOP_GRIP_PART_NAME)
	if topAnchor then
		return topAnchor.part
	end

	if paddleModel.PrimaryPart and paddleModel.PrimaryPart:IsA("BasePart") then
		return paddleModel.PrimaryPart
	end

	local pivotAnchor = PaddleGripUtil.findGripAnchor(paddleModel, PaddleConfig.PADDLE_PIVOT_GRIP_PART_NAME)
	if pivotAnchor then
		return pivotAnchor.part
	end

	return paddleModel:FindFirstChildWhichIsA("BasePart", true)
end

function PaddleGripUtil.getGripMapping(character: Model, paddleModel: Model, side: PaddleSide): GripMapping?
	local rightHand = PaddleGripUtil.getRightHand(character)
	local leftHand = PaddleGripUtil.getLeftHand(character)
	local assemblyRoot = PaddleGripUtil.findPaddleAssemblyRoot(paddleModel)
	if not rightHand or not leftHand or not assemblyRoot then
		return nil
	end

	local topAnchor = PaddleGripUtil.findGripAnchor(paddleModel, PaddleConfig.PADDLE_TOP_GRIP_PART_NAME, assemblyRoot)
	local pivotAnchor = PaddleGripUtil.findGripAnchor(paddleModel, PaddleConfig.PADDLE_PIVOT_GRIP_PART_NAME, assemblyRoot)
	if not topAnchor or not pivotAnchor then
		warn("[PaddleGrip] HandleStart oder MainHandle nicht gefunden")
		return nil
	end

	if side == "right" then
		return {
			topHand = leftHand,
			pivotHand = rightHand,
			topAnchor = topAnchor,
			pivotAnchor = pivotAnchor,
		}
	end

	return {
		topHand = rightHand,
		pivotHand = leftHand,
		topAnchor = topAnchor,
		pivotAnchor = pivotAnchor,
	}
end

function PaddleGripUtil.getHandAttachmentName(hand: BasePart, character: Model): string
	return if hand == PaddleGripUtil.getRightHand(character) then "RightGripAttachment" else "LeftGripAttachment"
end

function PaddleGripUtil.getHandGripCFrame(hand: BasePart, attachmentName: string): CFrame
	local handAttachment = hand:FindFirstChild(attachmentName) :: Attachment?
	return if handAttachment then handAttachment.WorldCFrame else hand.CFrame
end

function PaddleGripUtil.getPaddleGripCFrame(anchor: GripAnchor): CFrame
	if anchor.attachment then
		return anchor.part.CFrame * PaddleGripUtil.getAttachmentC1(anchor.part, anchor.attachment)
	end
	return anchor.part.CFrame
end

function PaddleGripUtil.releaseMotorOnHand(hand: BasePart, motorName: string)
	local motor = hand:FindFirstChild(motorName)
	if motor then
		motor:Destroy()
	end
end

function PaddleGripUtil.releaseAllPaddleGrips(character: Model, paddleModel: Model?)
	local rightHand = PaddleGripUtil.getRightHand(character)
	local leftHand = PaddleGripUtil.getLeftHand(character)

	if rightHand then
		PaddleGripUtil.releaseMotorOnHand(rightHand, MOTOR_PIVOT)
		PaddleGripUtil.releaseMotorOnHand(rightHand, MOTOR_TOP)
	end

	if leftHand then
		PaddleGripUtil.releaseMotorOnHand(leftHand, MOTOR_PIVOT)
		PaddleGripUtil.releaseMotorOnHand(leftHand, MOTOR_TOP)
	end

	if paddleModel then
		for _, descendant in paddleModel:GetDescendants() do
			if descendant:IsA("Motor6D") then
				descendant:Destroy()
			end
		end
	end
end

-- Zwei Griffpunkte (Pivot + Top) -> Paddel-Pivot. Kein Motor6D, keine Physik-Kraefte.
function PaddleGripUtil.alignPaddleToHands(
	character: Model,
	paddleModel: Model,
	mapping: GripMapping
): boolean
	local pivotAttachment = PaddleGripUtil.getHandAttachmentName(mapping.pivotHand, character)
	local topAttachment = PaddleGripUtil.getHandAttachmentName(mapping.topHand, character)

	local pivotWorld = PaddleGripUtil.getHandGripCFrame(mapping.pivotHand, pivotAttachment)
	local topWorld = PaddleGripUtil.getHandGripCFrame(mapping.topHand, topAttachment)

	local pivotOnPaddle = PaddleGripUtil.getPaddleGripCFrame(mapping.pivotAnchor)
	local topOnPaddle = PaddleGripUtil.getPaddleGripCFrame(mapping.topAnchor)

	local modelPivot = paddleModel:GetPivot()
	local pivotLocal = modelPivot:ToObjectSpace(pivotOnPaddle)
	local topLocal = modelPivot:ToObjectSpace(topOnPaddle)

	local worldShaft = topWorld.Position - pivotWorld.Position
	local localShaft = topLocal.Position - pivotLocal.Position

	if worldShaft.Magnitude < 1e-4 or localShaft.Magnitude < 1e-4 then
		paddleModel:PivotTo(pivotWorld * pivotLocal:Inverse())
		return true
	end

	local worldDir = worldShaft.Unit
	local localDir = localShaft.Unit

	local worldFrame = CFrame.lookAt(Vector3.zero, worldDir)
	local localFrame = CFrame.lookAt(Vector3.zero, localDir)
	local shaftAlign = worldFrame * localFrame:Inverse()

	paddleModel:PivotTo(CFrame.new(pivotWorld.Position) * shaftAlign * pivotLocal:Inverse())
	return true
end

function PaddleGripUtil.syncPaddleForSide(character: Model, paddleModel: Model, side: PaddleSide): boolean
	local mapping = PaddleGripUtil.getGripMapping(character, paddleModel, side)
	if not mapping then
		return false
	end

	return PaddleGripUtil.alignPaddleToHands(character, paddleModel, mapping)
end

return PaddleGripUtil
