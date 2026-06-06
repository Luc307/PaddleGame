local PlayerData = {}
local PlayerDataList = {}

PlayerData.__index = PlayerData

local DDS = game:GetService("DataStoreService")
local PlayerDS = DDS:GetDataStore("PlayerDataStore")
local SaveProperties = {Elo = true, Country = true,}
local AddableProperties = {Trophies = true,}

function PlayerData:LoadSavedPorperties()
    local Data = PlayerDS:GetAsync(self.Player.UserId)
    if not Data then return end
    for key, value in Data do
        self[key] = value
    end
end

function PlayerData.new(Player)
    local self = setmetatable({}, PlayerData)
    
    self.Player = Player
    self.Trophies = 0
    
    self:LoadSavedPorperties()

    PlayerDataList[Player.UserId] = self	
end

function PlayerData.Remove(Player)
    PlayerDataList[Player.UserId] = nil
end	

function PlayerData:Setter(key, value)
    if self[key] == nil then return end
    
    if AddableProperties[key] then
        self[key] += tonumber(value)
    else
        self[key] = value
    end
   
    if SaveProperties[key] then
        PlayerDS:UpdateAsync(self.Player.UserId, function(oldData)
            oldData = oldData or {}
            for saveKey in pairs(SaveProperties) do
                oldData[saveKey] = self[saveKey]
            end
            return oldData
        end)
    end
end

function PlayerData.Set(Player, key, value)
    local Data = PlayerDataList[Player.UserId]
    if not Data then return end
    Data:Setter(key, value)
end

function PlayerData.Get(Player, key)
    local Data = PlayerDataList[Player.UserId]
    if not Data then return end
    return key and Data[key] or Data
end

return PlayerData