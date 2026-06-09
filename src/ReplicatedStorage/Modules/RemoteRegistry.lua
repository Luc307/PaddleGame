local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local eventsFolder = remotesFolder:WaitForChild("Events")
local functionsFolder = remotesFolder:WaitForChild("Functions")

local function getOrCreateEvent(name: string): Instance
	local existing = eventsFolder:FindFirstChild(name)
	if existing then
		return existing
	end

	if RunService:IsServer() then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = eventsFolder
		return event
	end

	return eventsFolder:WaitForChild(name, 30)
end

local function getOrCreateUnreliableEvent(name: string): Instance
	local existing = eventsFolder:FindFirstChild(name)
	if existing then
		return existing
	end

	if RunService:IsServer() then
		local event = Instance.new("UnreliableRemoteEvent")
		event.Name = name
		event.Parent = eventsFolder
		return event
	end

	return eventsFolder:WaitForChild(name, 30)
end

return {
	Events = {
		BoatPaddle = eventsFolder:WaitForChild("BoatPaddle") :: UnreliableRemoteEvent,
		BoatDriverStroke = eventsFolder:WaitForChild("BoatDriverStroke") :: UnreliableRemoteEvent,
		BoatControl = eventsFolder:WaitForChild("BoatControl") :: RemoteEvent,
		BoatCheckpoint = getOrCreateEvent("BoatCheckpoint") :: RemoteEvent,
		BoatAuthorityState = getOrCreateUnreliableEvent("BoatAuthorityState") :: UnreliableRemoteEvent,
		RequestGameMode = eventsFolder:WaitForChild("RequestGameMode") :: RemoteEvent,
		RaceVisuals = eventsFolder:WaitForChild("RaceVisuals") :: RemoteEvent,
		QueueStatus = eventsFolder:WaitForChild("QueueStatus") :: RemoteEvent,
		Loading = eventsFolder:WaitForChild("Loading") :: RemoteEvent,
		Data = eventsFolder:WaitForChild("Data") :: RemoteEvent,
	},
	Functions = {
		Data = functionsFolder:WaitForChild("Data") :: RemoteFunction,
	},
}
