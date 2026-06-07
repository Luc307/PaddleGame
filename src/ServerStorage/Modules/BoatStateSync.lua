local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoatCheckpoint = require(ReplicatedStorage.Modules.BoatCheckpoint)
local BoatService = require(script.Parent.BoatService)

local BoatStateSync = {}

function BoatStateSync.tryApply(player: Player, payload: BoatCheckpoint.CheckpointPayload, force: boolean?): (boolean, string?)
	if typeof(payload) ~= "table" then
		return false, "invalid_payload"
	end

	if typeof(payload.boatId) ~= "string" then
		return false, "invalid_boat_id"
	end

	local boat = BoatService.getBoat(payload.boatId)
	if not boat or boat.serverAuthority == false then
		return false, "boat_not_found"
	end

	if BoatService.getPlayerBoat(player) ~= boat then
		return false, "not_occupant"
	end

	local driver = BoatService.getDriver(boat)
	if driver ~= player then
		return false, "not_driver"
	end

	return BoatService.applyCheckpoint(boat, payload, force)
end

return BoatStateSync
