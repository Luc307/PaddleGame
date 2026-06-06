export type ModeDefinition = {
	id: number,
	name: string,
	requiredPlayers: number,
	teamSize: number,
	teamCount: number,
	teamControls: boolean,
	usesQueue: boolean,
}

local GameModeConfig = {}

GameModeConfig.MODES = {
	[1] = {
		id = 1,
		name = "1 vs Parkour",
		requiredPlayers = 1,
		teamSize = 1,
		teamCount = 1,
		teamControls = false,
		usesQueue = false,
	},
	[2] = {
		id = 2,
		name = "1 vs 1",
		requiredPlayers = 2,
		teamSize = 1,
		teamCount = 2,
		teamControls = false,
		usesQueue = true,
	},
	[3] = {
		id = 3,
		name = "2 vs 2",
		requiredPlayers = 4,
		teamSize = 2,
		teamCount = 2,
		teamControls = true,
		usesQueue = true,
	},
	[4] = {
		id = 4,
		name = "2 vs Parkour",
		requiredPlayers = 2,
		teamSize = 2,
		teamCount = 1,
		teamControls = true,
		usesQueue = true,
	},
} :: { [number]: ModeDefinition }

function GameModeConfig.getMode(modeId: number): ModeDefinition?
	return GameModeConfig.MODES[modeId]
end

return GameModeConfig


