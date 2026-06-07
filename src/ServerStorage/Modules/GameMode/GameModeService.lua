local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BoatConfig = require(ReplicatedStorage.Modules.BoatConfig)
local GameModeConfig = require(ReplicatedStorage.Modules.GameModeConfig)
local BoatService = require(script.Parent.Parent.BoatService)
local MapInstanceService = require(script.Parent.MapInstanceService)
local PlayerAttachmentService = require(script.Parent.PlayerAttachmentService)
local QueueService = require(script.Parent.QueueService)

type ModeDefinition = GameModeConfig.ModeDefinition
type MapInstance = MapInstanceService.MapInstance

type Remotes = {
	BoatControl: RemoteEvent,
	RaceVisuals: RemoteEvent,
	QueueStatus: RemoteEvent,
}

type TeamRecord = {
	id: number,
	players: { Player },
	boat: BoatService.BoatRecord,
	boatModel: Model,
	finished: boolean,
	finishTime: number?,
}

type SessionRecord = {
	id: number,
	mode: ModeDefinition,
	startedAt: number,
	mapInstance: MapInstance,
	teams: { TeamRecord },
	finishPart: BasePart?,
	finishConnection: RBXScriptConnection?,
	collisionGroups: { string },
}

local GameModeService = {}

local BOAT_TEMPLATE_NAME = "Boat Model"
local GROUP_PREFIX = "RaceS"
local FINISH_ZONE_MARGIN = Vector3.new(4, 6, 4)

local remotes: Remotes? = nil
local sessions: { [number]: SessionRecord } = {}
local playerSessionId: { [Player]: number } = {}
local sessionCounter = 0

local function formatTime(seconds: number): string
	return string.format("%.3f", seconds)
end

local function getPlayerList(players: { Player }): string
	local names = {}
	for _, player in players do
		table.insert(names, player.Name)
	end
	return table.concat(names, " + ")
end

local function getSessionPlayers(session: SessionRecord): { Player }
	local players = {}
	for _, team in session.teams do
		for _, player in team.players do
			table.insert(players, player)
		end
	end
	return players
end

local function isPlayerAvailable(player: Player): boolean
	return playerSessionId[player] == nil and not QueueService.isQueued(player)
end

local function validateParticipants(mode: ModeDefinition, participants: { Player }): boolean
	if #participants ~= mode.requiredPlayers then
		warn(`[GameMode] Falsche Spieleranzahl fuer {mode.name}: {#participants}/{mode.requiredPlayers}`)
		return false
	end

	for _, player in participants do
		if not isPlayerAvailable(player) then
			warn(`[GameMode] {player.Name} ist nicht verfuegbar`)
			return false
		end
	end

	return true
end

local function getBoatTemplate(): Model?
	local template = workspace:FindFirstChild(BOAT_TEMPLATE_NAME)
	if template and template:IsA("Model") then
		return template
	end

	warn(`[GameMode] Workspace["{BOAT_TEMPLATE_NAME}"] fehlt`)
	return nil
end

local function prepareBoatClone(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
end

local function getSeat(model: Model, name: string): BasePart?
	local seat = model:FindFirstChild(name, true)
	if seat and seat:IsA("BasePart") then
		return seat
	end
	return nil
end

local function getPhysicsPart(model: Model, fallback: BasePart?): BasePart?
	local physicsPart = model:FindFirstChild("PhysicsPart", true)
	if physicsPart and physicsPart:IsA("BasePart") then
		return physicsPart
	end
	return fallback
end

local function buildSeatBindings(model: Model, mode: ModeDefinition): ({ BoatService.SeatBinding }?, BasePart?)
	if mode.teamControls then
		local rightSeat = getSeat(model, "SeatRight")
		local leftSeat = getSeat(model, "SeatLeft")
		if rightSeat and leftSeat then
			return {
				{ part = rightSeat, paddleSide = "right" },
				{ part = leftSeat, paddleSide = "left" },
			}, getPhysicsPart(model, rightSeat)
		end

		local seat = getSeat(model, "Seat")
		if not seat then
			warn(`[GameMode] Boot braucht Seat oder SeatRight/SeatLeft`)
			return nil, nil
		end

		return {
			{ part = seat, paddleSide = "right" },
			{ part = seat, paddleSide = "left" },
		}, getPhysicsPart(model, seat)
	end

	local seat = getSeat(model, "Seat")
	if not seat then
		warn(`[GameMode] Boot braucht Seat`)
		return nil, nil
	end

	return {
		{ part = seat, paddleSide = nil },
	}, getPhysicsPart(model, seat)
end

local function getSeatLocalOffset(index: number, teamControls: boolean): CFrame
	if not teamControls then
		return CFrame.new(0, 3, 0)
	end
	if index == 1 then
		return CFrame.new(0, 3, 0)
	end
	return CFrame.new(if index == 2 then -2.5 else 2.5, 3, 0)
end

local function getAttachmentOffset(physicsPart: BasePart, seatPart: BasePart, index: number, teamControls: boolean): CFrame
	local seatOnPhysics = physicsPart.CFrame:ToObjectSpace(seatPart.CFrame)
	return seatOnPhysics * getSeatLocalOffset(index, teamControls)
end

local function ensureCollisionGroup(name: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

local function getCollisionGroup(sessionId: number, teamId: number): string
	return `{GROUP_PREFIX}{sessionId}T{teamId}`
end

local function setCollisionGroup(instance: Instance, groupName: string)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

local function resetCollisionGroup(instance: Instance?)
	if not instance then
		return
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Default"
		end
	end
end

local function configureSessionCollision(session: SessionRecord)
	session.collisionGroups = {}

	for teamId = 1, session.mode.teamCount do
		local groupName = getCollisionGroup(session.id, teamId)
		ensureCollisionGroup(groupName)
		table.insert(session.collisionGroups, groupName)
	end

	for a, groupA in session.collisionGroups do
		for b, groupB in session.collisionGroups do
			PhysicsService:CollisionGroupSetCollidable(groupA, groupB, a == b)
		end
	end
end

local function applyTeamCollision(session: SessionRecord, team: TeamRecord)
	local groupName = getCollisionGroup(session.id, team.id)
	setCollisionGroup(team.boatModel, groupName)

	for _, player in team.players do
		if player.Character then
			setCollisionGroup(player.Character, groupName)
		end
	end
end

local function activateBoatControl(
	player: Player,
	boat: BoatService.BoatRecord,
	binding: BoatService.SeatBinding,
	isDriver: boolean,
	attachOffset: CFrame,
	seatLocalOffset: CFrame
)
	local activeRemotes = remotes
	if not activeRemotes then
		return
	end

	BoatService.addOccupantBinding(player, boat, binding, isDriver)
	activeRemotes.BoatControl:FireClient(
		player,
		true,
		boat.id,
		binding.paddleSide,
		isDriver,
		true,
		attachOffset,
		binding.part.Name,
		seatLocalOffset
	)
end

local function assignPlayersToBoat(
	players: { Player },
	seatBindings: { BoatService.SeatBinding },
	boat: BoatService.BoatRecord,
	boatModel: Model,
	teamControls: boolean
)
	for index, player in players do
		local binding = seatBindings[index]
		if not binding then
			continue
		end

		local attachPart = boat.physicsPart
		local seatLocalOffset = getSeatLocalOffset(index, teamControls)
		local attachOffset = getAttachmentOffset(attachPart, binding.part, index, teamControls)
		PlayerAttachmentService.snapWithoutWeld(player, attachPart, attachOffset)
		activateBoatControl(player, boat, binding, index == 1, attachOffset, seatLocalOffset)
	end
end

local function sendRaceVisuals(session: SessionRecord)
	local activeRemotes = remotes
	if not activeRemotes then
		return
	end

	for _, viewerTeam in session.teams do
		for _, viewer in viewerTeam.players do
			local transparentBoatIds = {}
			local transparentUserIds = {}

			for _, team in session.teams do
				if team.id ~= viewerTeam.id then
					table.insert(transparentBoatIds, team.boat.id)
					for _, player in team.players do
						table.insert(transparentUserIds, player.UserId)
					end
				end
			end

			activeRemotes.RaceVisuals:FireClient(viewer, {
				active = true,
				transparentBoatIds = transparentBoatIds,
				transparentUserIds = transparentUserIds,
			})
		end
	end
end

local function clearRaceVisuals(session: SessionRecord)
	local activeRemotes = remotes
	if not activeRemotes then
		return
	end

	for _, team in session.teams do
		for _, player in team.players do
			activeRemotes.RaceVisuals:FireClient(player, { active = false })
			activeRemotes.BoatControl:FireClient(player, false, nil, nil, nil, nil, nil, nil, nil)
		end
	end
end

local function destroyTeamBoat(team: TeamRecord)
	BoatService.unregisterBoat(team.boat.id)
	if team.boatModel.Parent then
		team.boatModel:Destroy()
	end
end

local function cleanupSession(session: SessionRecord)
	if session.finishConnection then
		session.finishConnection:Disconnect()
		session.finishConnection = nil
	end

	clearRaceVisuals(session)

	local players = getSessionPlayers(session)
	PlayerAttachmentService.detachAll(players)

	for _, team in session.teams do
		for _, player in team.players do
			BoatService.removeOccupant(player)
			resetCollisionGroup(player.Character)
		end
		resetCollisionGroup(team.boatModel)
		destroyTeamBoat(team)
	end

	for _, player in players do
		playerSessionId[player] = nil
		player:SetAttribute("RaceSessionId", nil)
	end

	MapInstanceService.release(session.id)
	sessions[session.id] = nil
end

local function finishSession(session: SessionRecord)
	if not sessions[session.id] then
		return
	end

	cleanupSession(session)
end

local function handleTeamFinished(session: SessionRecord, team: TeamRecord)
	if team.finished or not sessions[session.id] then
		return
	end

	team.finished = true
	team.finishTime = os.clock() - session.startedAt

	local elapsed = team.finishTime
	local winner = if #team.players == 1 then team.players[1].Name else `Team {team.id} ({getPlayerList(team.players)})`

	if session.mode.teamCount == 1 then
		print(`[GameMode] Ziel erreicht: {winner} | Zeit: {formatTime(elapsed)}s | Modus: {session.mode.name} | Session: {session.id}`)
	else
		print(`[GameMode] Gewinner: {winner} | Zeit: {formatTime(elapsed)}s | Modus: {session.mode.name} | Session: {session.id}`)
	end

	finishSession(session)
end

local function isBoatInFinishZone(boat: BoatService.BoatRecord, finishPart: BasePart): boolean
	local relative = finishPart.CFrame:PointToObjectSpace(boat.physicsPart.Position)
	local half = finishPart.Size * 0.5 + FINISH_ZONE_MARGIN

	return math.abs(relative.X) <= half.X
		and math.abs(relative.Y) <= half.Y
		and math.abs(relative.Z) <= half.Z
end

local function pollFinish(session: SessionRecord)
	local finishPart = session.finishPart
	if not finishPart or not finishPart.Parent then
		return
	end

	for _, team in session.teams do
		if team.finished then
			continue
		end

		if isBoatInFinishZone(team.boat, finishPart) then
			handleTeamFinished(session, team)
			return
		end
	end
end

local function startFinishWatcher(session: SessionRecord, finishPart: BasePart)
	session.finishPart = finishPart
	session.finishConnection = RunService.Heartbeat:Connect(function()
		if not sessions[session.id] then
			return
		end

		pollFinish(session)
	end)
end

local function createTeams(
	mapInstance: MapInstance,
	mode: ModeDefinition,
	participants: { Player },
	startPart: BasePart,
	template: Model
): { TeamRecord }?
	local teams = {}
	local boatsFolder = Instance.new("Folder")
	boatsFolder.Name = "Boats"
	boatsFolder.Parent = mapInstance.root

	for teamId = 1, mode.teamCount do
		local teamPlayers = {}
		for slot = 1, mode.teamSize do
			local participantIndex = (teamId - 1) * mode.teamSize + slot
			local player = participants[participantIndex]
			if player then
				table.insert(teamPlayers, player)
			end
		end

		local boatModel = template:Clone()
		prepareBoatClone(boatModel)
		local boatId = `Session{mapInstance.id}_Mode{mode.id}_Team{teamId}`
		boatModel.Name = boatId

		local seatBindings, physicsPart = buildSeatBindings(boatModel, mode)
		if not seatBindings or not physicsPart then
			boatsFolder:Destroy()
			return nil
		end

		local spawnCFrame = startPart.CFrame
			* BoatConfig.RACE_SPAWN_SEAT_OFFSET
			* CFrame.new(0, teamId * BoatConfig.RACE_SPAWN_TEAM_Y_STEP, 0)
			* CFrame.Angles(0, BoatConfig.RACE_SPAWN_YAW, 0)

		BoatService.moveModelByAnchor(boatModel, seatBindings[1].part, spawnCFrame)
		boatModel.PrimaryPart = physicsPart
		boatModel.Parent = boatsFolder

		local boat = BoatService.registerBoat(boatModel, {
			id = boatId,
			physicsPart = physicsPart,
			seats = seatBindings,
			serverAuthority = true,
		})
		if not boat then
			boatsFolder:Destroy()
			return nil
		end

		local team = {
			id = teamId,
			players = teamPlayers,
			boat = boat,
			boatModel = boatModel,
			finished = false,
			finishTime = nil,
		}
		table.insert(teams, team)
	end

	return teams
end

local function registerPlayers(session: SessionRecord, participants: { Player })
	for _, player in participants do
		playerSessionId[player] = session.id
		player:SetAttribute("RaceSessionId", session.id)
	end
end

function GameModeService.init(remoteEvents: Remotes)
	remotes = remoteEvents

	QueueService.init(function(modeId: number, participants: { Player })
		return GameModeService.startSession(modeId, participants)
	end, function(player: Player, payload)
		if remotes then
			remotes.QueueStatus:FireClient(player, payload)
		end
	end)
end

function GameModeService.isPlayerLocked(player: Player): boolean
	return PlayerAttachmentService.isAttached(player)
end

function GameModeService.getPlayerSession(player: Player): SessionRecord?
	local sessionId = playerSessionId[player]
	if not sessionId then
		return nil
	end
	return sessions[sessionId]
end

function GameModeService.requestMode(player: Player, modeId: number): boolean
	local mode = GameModeConfig.getMode(modeId)
	if not mode then
		warn(`[GameMode] Unbekannter Modus: {modeId}`)
		return false
	end

	if not isPlayerAvailable(player) then
		if playerSessionId[player] then
			warn(`[GameMode] {player.Name} ist bereits in einem Rennen`)
		elseif QueueService.isQueued(player) then
			warn(`[GameMode] {player.Name} ist bereits in einer Warteschlange`)
		end
		return false
	end

	if mode.usesQueue then
		return QueueService.join(player, modeId)
	end

	return GameModeService.startSession(modeId, { player })
end

function GameModeService.startSession(modeId: number, participants: { Player }): boolean
	local mode = GameModeConfig.getMode(modeId)
	if not mode then
		warn(`[GameMode] Unbekannter Modus: {modeId}`)
		return false
	end

	if not validateParticipants(mode, participants) then
		return false
	end

	local template = getBoatTemplate()
	if not template then
		return false
	end

	sessionCounter += 1
	local sessionId = sessionCounter

	local mapInstance = MapInstanceService.acquire(sessionId)
	if not mapInstance then
		return false
	end

	local startPart = MapInstanceService.getModePart(mapInstance, "Starts", mode.id)
	local finishPart = MapInstanceService.getModePart(mapInstance, "Finish", mode.id)
	if not startPart or not finishPart then
		MapInstanceService.release(sessionId)
		warn(`[GameMode] Start oder Ziel fuer Modus {mode.id} fehlt in Map-Instanz`)
		return false
	end

	local teams = createTeams(mapInstance, mode, participants, startPart, template)
	if not teams then
		MapInstanceService.release(sessionId)
		return false
	end

	local session: SessionRecord = {
		id = sessionId,
		mode = mode,
		startedAt = 0,
		mapInstance = mapInstance,
		teams = teams,
		finishPart = finishPart,
		finishConnection = nil,
		collisionGroups = {},
	}

	sessions[sessionId] = session
	registerPlayers(session, participants)
	configureSessionCollision(session)

	for _, team in teams do
		applyTeamCollision(session, team)
		assignPlayersToBoat(team.players, team.boat.seatBindings, team.boat, team.boatModel, mode.teamControls)
	end

	session.startedAt = os.clock()
	sendRaceVisuals(session)
	startFinishWatcher(session, finishPart)

	print(`[GameMode] Session {sessionId} gestartet | {mode.name} | Spieler: {getPlayerList(participants)} | Map-Slot: {mapInstance.slot}`)
	return true
end

function GameModeService.cancelSession(sessionId: number)
	local session = sessions[sessionId]
	if session then
		finishSession(session)
	end
end

function GameModeService.cancelPlayerSession(player: Player)
	local sessionId = playerSessionId[player]
	if sessionId then
		finishSession(sessions[sessionId])
	end
end

Players.PlayerRemoving:Connect(function(player)
	QueueService.removePlayer(player)

	local sessionId = playerSessionId[player]
	if not sessionId then
		return
	end

	local session = sessions[sessionId]
	if not session then
		return
	end

	warn(`[GameMode] {player.Name} verlassen, Session {sessionId} beendet`)
	finishSession(session)
end)

return GameModeService
