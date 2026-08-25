ClientFramework = {}

local function detect()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

ClientFramework.name = detect()
ClientFramework.QBCore = ClientFramework.name == 'qbcore' and exports['qb-core']:GetCoreObject() or nil
ClientFramework.ESX = ClientFramework.name == 'esx' and exports['es_extended']:getSharedObject() or nil

function ClientFramework.Notify(message, typ)
    if ClientFramework.name == 'qbox' then
        exports.qbx_core:Notify(message, typ or 'inform')
    elseif ClientFramework.name == 'qbcore' then
        ClientFramework.QBCore.Functions.Notify(message, typ or 'primary')
    elseif ClientFramework.name == 'esx' then
        ClientFramework.ESX.ShowNotification(message)
    else
        BeginTextCommandThefeedPost('STRING'); AddTextComponentSubstringPlayerName(message); EndTextCommandThefeedPostTicker(false, false)
    end
end
