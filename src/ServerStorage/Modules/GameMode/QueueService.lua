local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConfig = require(ReplicatedStorage.Modules.GameModeConfig)

export type QueueStatusPayload = {
	action: string,
	modeId: number,
	modeName: string,
	position: number?,
	queueSize: number,
	requiredPlayers: number,
	message: string,
}

type StartMatchFn = (modeId: number, participants: { Player }) -> boolean
type NotifyFn = (player: Player, payload: QueueStatusPayload) -> ()

local QueueService = {}

local queues: { [number]: { Player } } = {
	[2] = {},
	[3] = {},
	[4] = {},
}
local playerQueueMode: { [Player]: number } = {}

local startMatch: StartMatchFn? = nil
local notifyPlayer: NotifyFn? = nil

local function getQueueSize(modeId: number): number
	return #(queues[modeId] or {})
end

local function buildPayload(action: string, player: Player, modeId: number, message: string): QueueStatusPayload
	local mode = GameModeConfig.getMode(modeId)
	local queue = queues[modeId]
	local position: number? = nil

	for index, queuedPlayer in queue do
		if queuedPlayer == player then
			position = index
			break
		end
	end

	return {
		action = action,
		modeId = modeId,
		modeName = if mode then mode.name else `Modus {modeId}`,
		position = position,
		queueSize = getQueueSize(modeId),
		requiredPlayers = if mode then mode.requiredPlayers else 0,
		message = message,
	}
end

local function sendStatus(player: Player, payload: QueueStatusPayload)
	if notifyPlayer then
		notifyPlayer(player, payload)
	end
	print(`[Queue] {player.Name}: {payload.message}`)
end

local function broadcastQueue(modeId: number)
	local mode = GameModeConfig.getMode(modeId)
	if not mode then
		return
	end

	for index, player in queues[modeId] do
		sendStatus(player, buildPayload("joined", player, modeId, `{mode.name}: Platz {index}/{mode.requiredPlayers}`))
	end
end

local function tryStartMatches(modeId: number)
	local mode = GameModeConfig.getMode(modeId)
	local queue = queues[modeId]
	if not mode or not startMatch then
		return
	end

	while #queue >= mode.requiredPlayers do
		local participants: { Player } = {}
		for _ = 1, mode.requiredPlayers do
			local player = table.remove(queue, 1)
			if player then
				playerQueueMode[player] = nil
				table.insert(participants, player)
			end
		end

		if not startMatch(modeId, participants) then
			for index = #participants, 1, -1 do
				local player = participants[index]
				table.insert(queue, 1, player)
				playerQueueMode[player] = modeId
			end
			warn(`[Queue] {mode.name} konnte nicht gestartet werden`)
			break
		end

		for _, player in participants do
			sendStatus(player, buildPayload(
				"started",
				player,
				modeId,
				`{mode.name} startet mit {mode.requiredPlayers} Spielern`
			))
		end

		broadcastQueue(modeId)
	end
end

function QueueService.init(onMatchReady: StartMatchFn, onNotify: NotifyFn)
	startMatch = onMatchReady
	notifyPlayer = onNotify
end

function QueueService.isQueued(player: Player): boolean
	return playerQueueMode[player] ~= nil
end

function QueueService.getQueuedMode(player: Player): number?
	return playerQueueMode[player]
end

function QueueService.leave(player: Player): boolean
	local modeId = playerQueueMode[player]
	if not modeId then
		return false
	end

	for index, queuedPlayer in queues[modeId] do
		if queuedPlayer == player then
			table.remove(queues[modeId], index)
			break
		end
	end

	playerQueueMode[player] = nil

	local mode = GameModeConfig.getMode(modeId)
	sendStatus(player, buildPayload(
		"left",
		player,
		modeId,
		if mode then `{mode.name}: Warteschlange verlassen` else "Warteschlange verlassen"
	))
	broadcastQueue(modeId)
	return true
end

function QueueService.join(player: Player, modeId: number): boolean
	local mode = GameModeConfig.getMode(modeId)
	if not mode or not mode.usesQueue then
		return false
	end

	local currentMode = playerQueueMode[player]
	if currentMode == modeId then
		return QueueService.leave(player)
	end

	if currentMode then
		sendStatus(player, buildPayload(
			"error",
			player,
			modeId,
			`Bereits in Warteschlange fuer Modus {currentMode}`
		))
		return false
	end

	table.insert(queues[modeId], player)
	playerQueueMode[player] = modeId

	sendStatus(player, buildPayload(
		"joined",
		player,
		modeId,
		`{mode.name}: Warteschlange beigetreten ({getQueueSize(modeId)}/{mode.requiredPlayers})`
	))
	broadcastQueue(modeId)
	tryStartMatches(modeId)
	return true
end

function QueueService.removePlayer(player: Player)
	QueueService.leave(player)
end

return QueueService
