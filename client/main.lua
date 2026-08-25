local dmvLocations = {}
local menuOpen = false

local function openDMV()
    if menuOpen then return end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    TriggerServerEvent('st_dmv:server:requestDashboard')
end

local function closeDMV()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb) closeDMV(); cb({ ok = true }) end)
RegisterNUICallback('register', function(data, cb) TriggerServerEvent('st_dmv:server:registerVehicle', data.id, data.account); cb({ ok = true }) end)
RegisterNUICallback('exam', function(data, cb) TriggerServerEvent('st_dmv:server:submitExam', data.licenseType, data.answers); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb) TriggerServerEvent('st_dmv:server:requestDashboard'); cb({ ok = true }) end)

RegisterNetEvent('st_dmv:client:dashboard', function(data)
    SendNUIMessage({ action = 'dashboard', data = data })
end)

RegisterNetEvent('st_dmv:client:refresh', function()
    if menuOpen then TriggerServerEvent('st_dmv:server:requestDashboard') end
end)

RegisterNetEvent('st_dmv:client:notify', function(message, typ) ClientFramework.Notify(message, typ) end)

RegisterNetEvent('st_dmv:client:showDocument', function(item)
    local data = item.info or item.metadata or item
    SendNUIMessage({ action = 'document', data = data })
    SetNuiFocus(true, true)
    menuOpen = true
end)

exports('UseDocument', function(data)
    TriggerEvent('st_dmv:client:showDocument', data)
end)

local function getNearbyVehicle()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 4.0, 0, 71)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

RegisterNetEvent('st_dmv:client:installPlate', function()
    local vehicle = getNearbyVehicle()
    if not vehicle then return ClientFramework.Notify('No vehicle nearby.', 'error') end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local inventory = Config.Inventory == 'ox_inventory' or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') == 'started')
    if inventory then
        local items = exports.ox_inventory:Search('slots', 'dmv_license_plate') or {}
        for _, entry in pairs(items) do
            if entry.metadata then
                TriggerServerEvent('st_dmv:server:installPlate', netId, entry.metadata)
                return
            end
        end
    else
        local playerData = ClientFramework.QBCore and ClientFramework.QBCore.Functions.GetPlayerData() or {}
        for _, entry in pairs(playerData.items or {}) do
            if entry and entry.name == 'dmv_license_plate' then
                TriggerServerEvent('st_dmv:server:installPlate', netId, entry.info or entry.metadata or {})
                return
            end
        end
    end
    ClientFramework.Notify('You do not have a DMV license plate.', 'error')
end)

RegisterNetEvent('st_dmv:client:locationAdded', function(location)
    dmvLocations[#dmvLocations + 1] = { label = location.label, coords = vector3(location.coords.x, location.coords.y, location.coords.z), radius = 1.8 }
    SetupDMVTargets()
end)

RegisterNetEvent('st_dmv:client:setLocations', function(locations)
    dmvLocations = {}
    for _, row in ipairs(locations or {}) do dmvLocations[#dmvLocations + 1] = { id = row.id, label = row.label, coords = vector3(row.x, row.y, row.z), radius = 1.8 } end
    SetupDMVTargets()
end)

CreateThread(function()
    math.randomseed(GetGameTimer())
    TriggerServerEvent('st_dmv:server:getLocations')
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        for _, loc in ipairs(dmvLocations) do
            local dist = #(coords - loc.coords)
            if dist < 20.0 and Config.Target == 'none' then
                sleep = 0
                DrawMarker(Config.Marker.type, loc.coords.x, loc.coords.y, loc.coords.z + 0.15, 0,0,0,0,0,0, Config.Marker.scale.x,Config.Marker.scale.y,Config.Marker.scale.z, 255,255,255,150, false,true,2,false,nil,nil,false)
                if dist < 2.0 then
                    BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to access the DMV'); EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustReleased(0, 38) then openDMV() end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback('closeDocument', function(_, cb) closeDMV(); cb({ ok = true }) end)

function OpenDMVMenu() openDMV() end
