--[[
	Studio manual setup:
	- ReplicatedStorage/BoatTemplates/ -> Models: small, mid, big, huge
	  Each needs PhysicsPart + Seat (solo) or SeatRight/SeatLeft (team)
	- StarterGui/ShopGui -> see ShopController.client.lua hierarchy comments
]]
local BoatShopConfig = {}

BoatShopConfig.TEMPLATE_FOLDER_NAME = "BoatTemplates"

BoatShopConfig.BOAT_IDS = { "small", "mid", "big", "huge" }

BoatShopConfig.DEFAULT_BOAT_ID = BoatShopConfig.BOAT_IDS[1]

BoatShopConfig.SELECTED_ATTRIBUTE = "SelectedBoat"

-- Per-template yaw fix. small/big were authored facing opposite to mid/huge.
BoatShopConfig.MODEL_CORRECTIONS = {
	small = CFrame.Angles(0, math.pi, 0),
	big = CFrame.Angles(0, math.pi, 0),
} :: { [string]: CFrame }

function BoatShopConfig.applyModelCorrection(model: Model, boatId: string)
	local correction = BoatShopConfig.MODEL_CORRECTIONS[boatId]
	if not correction then
		return
	end

	model:PivotTo(model:GetPivot() * correction)
end

function BoatShopConfig.isValidBoatId(boatId: string): boolean
	for _, id in BoatShopConfig.BOAT_IDS do
		if id == boatId then
			return true
		end
	end
	return false
end

return BoatShopConfig
