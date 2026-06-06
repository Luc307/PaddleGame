local module = {}

local DisabledPlayers = {}

function module.DisableControl(player, time)
	if not player then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if not DisabledPlayers[player] then
		DisabledPlayers[player] = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			AutoRotate = humanoid.AutoRotate
		}
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	if time and time > 0 then
		task.delay(time, function()
			module.EnableControl(player)
		end)
	end
end

function module.EnableControl(player)
	if not player then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local data = DisabledPlayers[player]
	if not data then return end

	humanoid.WalkSpeed = data.WalkSpeed
	humanoid.JumpPower = data.JumpPower
	humanoid.AutoRotate = data.AutoRotate

	DisabledPlayers[player] = nil
end

return module