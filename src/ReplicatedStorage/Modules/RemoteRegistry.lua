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

local function getOrCreateFunction(name: string): Instance
	local existing = functionsFolder:FindFirstChild(name)
	if existing then
		return existing
	end

	if RunService:IsServer() then
		local remoteFunction = Instance.new("RemoteFunction")
		remoteFunction.Name = name
		remoteFunction.Parent = functionsFolder
		return remoteFunction
	end

	return functionsFolder:WaitForChild(name, 30)
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
		BoatStrokePlay = getOrCreateUnreliableEvent("BoatStrokePlay") :: UnreliableRemoteEvent,
		BoatControl = eventsFolder:WaitForChild("BoatControl") :: RemoteEvent,
		RequestGameMode = eventsFolder:WaitForChild("RequestGameMode") :: RemoteEvent,
		RaceVisuals = eventsFolder:WaitForChild("RaceVisuals") :: RemoteEvent,
		QueueStatus = eventsFolder:WaitForChild("QueueStatus") :: RemoteEvent,
		Loading = eventsFolder:WaitForChild("Loading") :: RemoteEvent,
		Data = eventsFolder:WaitForChild("Data") :: RemoteEvent,
		ShopSelect = getOrCreateEvent("ShopSelect") :: RemoteEvent,
	},
	Functions = {
		Data = functionsFolder:WaitForChild("Data") :: RemoteFunction,
		ShopGetState = getOrCreateFunction("ShopGetState") :: RemoteFunction,
	},
}
