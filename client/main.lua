DMVLocations = DMVLocations or {}
local menuOpen=false
local adminOpen=false
local raycastMode=false
local blips={}

local function openDMV()
    if menuOpen then return end
    menuOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}); TriggerServerEvent('st_dmv:server:requestDashboard')
end
local function closeUI()
    menuOpen=false; adminOpen=false; raycastMode=false; SetNuiFocus(false,false); SendNUIMessage({action='close'})
end

RegisterNUICallback('close',function(_,cb) closeUI(); cb({ok=true}) end)
RegisterNUICallback('register',function(data,cb) TriggerServerEvent('st_dmv:server:registerVehicle',data.id,data.account,data.useCustom==true); cb({ok=true}) end)
RegisterNUICallback('customRequest',function(data,cb) TriggerServerEvent('st_dmv:server:requestCustomPlate',data.id,data.plate); cb({ok=true}) end)
RegisterNUICallback('purchaseCustom',function(data,cb) TriggerServerEvent('st_dmv:server:purchaseApprovedCustom',data.id,data.account); cb({ok=true}) end)
RegisterNUICallback('exam',function(data,cb) TriggerServerEvent('st_dmv:server:submitExam',data.licenseType,data.answers); cb({ok=true}) end)
RegisterNUICallback('refresh',function(_,cb) TriggerServerEvent('st_dmv:server:requestDashboard'); cb({ok=true}) end)
RegisterNUICallback('adminRefresh',function(_,cb) TriggerServerEvent('st_dmv:server:getAdminPanel'); cb({ok=true}) end)
RegisterNUICallback('adminSetting',function(data,cb) TriggerServerEvent('st_dmv:server:adminSetting',data.key,data.value); cb({ok=true}) end)
RegisterNUICallback('createLocation',function(data,cb)
    local c=GetEntityCoords(PlayerPedId()); TriggerServerEvent('st_dmv:server:createLocation',data.label,{x=c.x,y=c.y,z=c.z}); cb({ok=true})
end)
RegisterNUICallback('updateLocation',function(data,cb) TriggerServerEvent('st_dmv:server:updateLocation',data.id,data); cb({ok=true}) end)
RegisterNUICallback('setMenuLocation',function(data,cb)
    local id=tonumber(data.id); if not id then cb({ok=false}); return end
    raycastMode=true; SetNuiFocus(false,false); SendNUIMessage({action='raycastStart'})
    CreateThread(function()
        while raycastMode do
            Wait(0); DisableControlAction(0,24,true); DisableControlAction(0,25,true)
            local hit,coords=CameraRaycast(80.0)
            if hit then DrawMarker(2,coords.x,coords.y,coords.z+0.15,0,0,0,0,0,0,0.18,0.18,0.18,255,255,255,180,false,true,2,false,nil,nil,false) end
            if IsDisabledControlJustReleased(0,24) and hit then
                raycastMode=false; TriggerServerEvent('st_dmv:server:updateLocation',id,{menu_x=coords.x,menu_y=coords.y,menu_z=coords.z,x=GetEntityCoords(PlayerPedId()).x,y=GetEntityCoords(PlayerPedId()).y,z=GetEntityCoords(PlayerPedId()).z}); SetNuiFocus(true,true); SendNUIMessage({action='raycastEnd',coords={x=coords.x,y=coords.y,z=coords.z}})
            elseif IsDisabledControlJustReleased(0,25) then
                raycastMode=false; SetNuiFocus(true,true); SendNUIMessage({action='raycastEnd',cancelled=true})
            end
        end
    end)
    cb({ok=true})
end)

RegisterNetEvent('st_dmv:client:dashboard',function(data) SendNUIMessage({action='dashboard',data=data}) end)
RegisterNetEvent('st_dmv:client:refresh',function() if menuOpen then TriggerServerEvent('st_dmv:server:requestDashboard') end end)
RegisterNetEvent('st_dmv:client:adminRefresh',function() if adminOpen then TriggerServerEvent('st_dmv:server:getAdminPanel') end end)
RegisterNetEvent('st_dmv:client:adminData',function(data) SendNUIMessage({action='adminData',data=data}) end)
RegisterNetEvent('st_dmv:client:openAdmin',function() adminOpen=true; menuOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='openAdmin'}); TriggerServerEvent('st_dmv:server:getAdminPanel') end)
RegisterNetEvent('st_dmv:client:notify',function(message,typ) ClientFramework.Notify(message,typ) end)

RegisterNetEvent('st_dmv:client:showDocument',function(item)
    local data=item.info or item.metadata or item; SendNUIMessage({action='document',data=data}); SetNuiFocus(true,true); menuOpen=true
end)
exports('UseDocument',function(data) TriggerEvent('st_dmv:client:showDocument',data) end)

RegisterNetEvent('st_dmv:client:installPlate',function()
    local ped=PlayerPedId(); local coords=GetEntityCoords(ped); local vehicle=GetClosestVehicle(coords.x,coords.y,coords.z,4.0,0,71)
    if vehicle==0 or not DoesEntityExist(vehicle) then return ClientFramework.Notify('No vehicle nearby.','error') end
    local netId=NetworkGetNetworkIdFromEntity(vehicle)
    local usingOx=Config.Inventory=='ox_inventory' or (Config.Inventory=='auto' and GetResourceState('ox_inventory')=='started')
    if usingOx then
        local items=exports.ox_inventory:Search('slots','dmv_license_plate') or {}
        for _,entry in pairs(items) do if entry.metadata then TriggerServerEvent('st_dmv:server:installPlate',netId,entry.metadata); return end end
    else
        local pd=ClientFramework.QBCore and ClientFramework.QBCore.Functions.GetPlayerData() or {}
        for _,entry in pairs(pd.items or {}) do if entry and entry.name=='dmv_license_plate' then TriggerServerEvent('st_dmv:server:installPlate',netId,entry.info or entry.metadata or {}); return end end
    end
    ClientFramework.Notify('You do not have a DMV license plate.','error')
end)

local function rebuildBlips()
    for _,b in pairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end; blips={}
    for _,loc in ipairs(DMVLocations) do
        local b=AddBlipForCoord(loc.coords.x,loc.coords.y,loc.coords.z); SetBlipSprite(b,Config.Blip.sprite); SetBlipColour(b,Config.Blip.color); SetBlipScale(b,Config.Blip.scale); SetBlipAsShortRange(b,Config.Blip.shortRange); BeginTextCommandSetBlipName('STRING'); AddTextComponentString(loc.label); EndTextCommandSetBlipName(b); blips[#blips+1]=b
    end
end

RegisterNetEvent('st_dmv:client:locationAdded',function(location)
    DMVLocations[#DMVLocations+1]={id=location.id,label=location.label,coords=vector3(location.coords.x,location.coords.y,location.coords.z),menu=location.menu}; SetupDMVTargets(); rebuildBlips()
end)
RegisterNetEvent('st_dmv:client:reloadLocations',function() TriggerServerEvent('st_dmv:server:getLocations') end)
RegisterNetEvent('st_dmv:client:setLocations',function(locations)
    DMVLocations={}
    for _,row in ipairs(locations or {}) do
        local menu=nil; if row.menu_x and row.menu_y and row.menu_z then menu=vector3(row.menu_x,row.menu_y,row.menu_z) end
        DMVLocations[#DMVLocations+1]={id=row.id,label=row.label,coords=vector3(row.x,row.y,row.z),menu=menu,radius=1.8}
    end
    SetupDMVTargets(); rebuildBlips()
end)

function CameraRaycast(distance)
    local cam=GetGameplayCamCoord(); local rot=GetGameplayCamRot(2); local pitch=math.rad(rot.x); local yaw=math.rad(rot.z)
    local dir=vector3(-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)); local dest=cam+dir*distance
    local ray=StartShapeTestRay(cam.x,cam.y,cam.z,dest.x,dest.y,dest.z,-1,PlayerPedId(),7); local _,hit,endCoords=GetShapeTestResult(ray); return hit==1,endCoords
end

CreateThread(function()
    Wait(1000); TriggerServerEvent('st_dmv:server:getLocations')
    while true do
        local sleep=1000
        if Config.Target=='none' then
            local ped=PlayerPedId(); local coords=GetEntityCoords(ped)
            for _,loc in ipairs(DMVLocations) do
                local target=loc.menu or loc.coords; local dist=#(coords-target)
                if dist<20.0 then
                    sleep=0; DrawMarker(Config.Marker.type,target.x,target.y,target.z+0.15,0,0,0,0,0,0,Config.Marker.scale.x,Config.Marker.scale.y,Config.Marker.scale.z,255,255,255,150,false,true,2,false,nil,nil,false)
                    if dist<2.0 then BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to access the DMV'); EndTextCommandDisplayHelp(0,false,true,-1); if IsControlJustReleased(0,38) then openDMV() end end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback('closeDocument',function(_,cb) closeUI(); cb({ok=true}) end)
function OpenDMVMenu() openDMV() end
