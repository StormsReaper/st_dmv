Framework = {}

local function detect()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

Framework.name = detect()
Framework.QBCore = Framework.name == 'qbcore' and exports['qb-core']:GetCoreObject() or nil
Framework.ESX = Framework.name == 'esx' and exports['es_extended']:getSharedObject() or nil

function Framework.GetPlayer(source)
    if Framework.name == 'qbox' then return exports.qbx_core:GetPlayer(source) end
    if Framework.name == 'qbcore' then return Framework.QBCore.Functions.GetPlayer(source) end
    if Framework.name == 'esx' then return Framework.ESX.GetPlayerFromId(source) end
end

function Framework.GetIdentifier(player)
    if not player then return nil end
    if Framework.name == 'qbox' then return player.PlayerData and (player.PlayerData.citizenid or player.PlayerData.citizenId) end
    if Framework.name == 'qbcore' then return player.PlayerData.citizenid end
    if Framework.name == 'esx' then return player.identifier end
end

function Framework.GetName(player)
    if not player then return 'Unknown Driver' end
    if Framework.name == 'esx' then
        return ((player.get and player.get('firstName')) or player.firstName or 'Unknown') .. ' ' .. ((player.get and player.get('lastName')) or player.lastName or '')
    end
    local c = player.PlayerData.charinfo or {}
    return (c.firstname or '') .. ' ' .. (c.lastname or '')
end

function Framework.GetMoney(player, account)
    account = account == 'cash' and 'cash' or 'bank'
    if Framework.name == 'esx' then return player.getAccount(account).money end
    return player.PlayerData.money[account] or 0
end

function Framework.RemoveMoney(player, account, amount, reason)
    account = account == 'cash' and 'cash' or 'bank'
    if Framework.name == 'esx' then
        return player.removeAccountMoney(account, amount, reason or 'dmv-registration') ~= false
    end
    return player.Functions.RemoveMoney(account, amount, reason or 'dmv-registration')
end

function Framework.AddItem(source, item, metadata)
    if Config.Inventory == 'ox_inventory' or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') == 'started') then
        return exports.ox_inventory:AddItem(source, item, 1, metadata)
    end
    local player = Framework.GetPlayer(source)
    if not player then return false end
    if player.Functions and player.Functions.AddItem then
        return player.Functions.AddItem(item, 1, false, metadata, 'st_dmvsystem')
    end
    return false
end

function Framework.RemoveItem(source, item, metadata)
    if Config.Inventory == 'ox_inventory' or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') == 'started') then
        return exports.ox_inventory:RemoveItem(source, item, 1, metadata)
    end
    local player = Framework.GetPlayer(source)
    return player and player.Functions and player.Functions.RemoveItem(item, 1, false, metadata, 'st_dmvsystem') or false
end

function Framework.HasAdmin(source)
    if source == 0 then return true end
    if IsPlayerAceAllowed(source, Config.AdminAce) then return true end
    local player = Framework.GetPlayer(source)
    if not player then return false end
    if Framework.name == 'esx' then
        local group = player.getGroup and player.getGroup() or ''
        for _, allowed in ipairs(Config.AdminGroups) do if group == allowed then return true end end
        return false
    end
    local group = player.PlayerData.permission or (player.PlayerData.job and player.PlayerData.job.name)
    for _, allowed in ipairs(Config.AdminGroups) do if group == allowed then return true end end
    return false
end
