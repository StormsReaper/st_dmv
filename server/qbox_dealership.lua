-- QBox / qbx_vehicleshop integration.
-- Uses the qbx_vehicles createPlayerVehicle hook, but only consumes creations
-- explicitly announced by qbx_vehicleshop purchase events. This prevents garages,
-- imports, scripts and admin vehicle creation from becoming DMV dealership sales.

local registeredHook = false
local hookId
local expectedSales = {}

local function resourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function key(cid, model)
    return ('%s:%s'):format(STDMV.Trim(cid), tostring(model or ''):lower())
end

local function markExpected(src, citizenid, model)
    if not citizenid or not model then return end
    expectedSales[key(citizenid, model)] = {
        source = src,
        citizenid = STDMV.Trim(citizenid),
        model = tostring(model):lower(),
        expires = GetGameTimer() + 10000
    }
end

local function isExpected(cid, model)
    local k = key(cid, model)
    local sale = expectedSales[k]
    if not sale then return nil end
    if sale.expires < GetGameTimer() then
        expectedSales[k] = nil
        return nil
    end
    return sale
end

-- Standard QBox showroom purchase.
AddEventHandler('qbx_vehicleshop:server:buyShowroomVehicle', function(model)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if player then
        markExpected(src, player.PlayerData.citizenid, model)
    end
end)

-- Managed/private dealership sale to a target player.
AddEventHandler('qbx_vehicleshop:server:sellShowroomVehicle', function(model, playerId)
    local target = exports.qbx_core:GetPlayer(tonumber(playerId))
    if target then
        markExpected(source, target.PlayerData.citizenid, model)
    end
end)

local function registerQBoxDealershipHook()
    if registeredHook then return true end
    if Framework.name ~= 'qbox' then return false end
    if not resourceStarted('qbx_core') or not resourceStarted('qbx_vehicles') or not resourceStarted('qbx_vehicleshop') then return false end

    local ok, result = pcall(function()
        -- registerHook belongs to qbx_vehicles, not qbx_core.
        return exports.qbx_vehicles:registerHook('createPlayerVehicle', function(payload)
            if type(payload) ~= 'table' or not payload.citizenid or type(payload.props) ~= 'table' then return end

            local props = payload.props
            local model = props.modelName or props.vehicle
            local sale = isExpected(payload.citizenid, model)
            if not sale then return end
            expectedSales[key(payload.citizenid, model)] = nil

            local plate = STDMV.NormalizePlate(props.plate)
            if plate == '' then return end

            CreateThread(function()
                local found
                for _ = 1, 20 do
                    Wait(250)
                    found = MySQL.single.await([[SELECT id,citizenid,vehicle,plate,mods FROM player_vehicles WHERE citizenid=? AND plate=? LIMIT 1]], {
                        payload.citizenid,
                        props.plate
                    })
                    if found then break end
                end

                if not found then
                    print(('[st_dmvsystem] QBox vehicle was created but DMV could not find player_vehicles row for %s.'):format(plate))
                    return
                end

                local existing = MySQL.scalar.await('SELECT id FROM dmv_vehicle_ledger WHERE vin=? OR temporary_plate=? LIMIT 1', {
                    ('QBX-' .. tostring(found.id)),
                    found.plate
                })
                if existing then return end

                local vehicleModel = found.vehicle or model or ''
                local displayName = vehicleModel
                local make = ''
                local okCatalog, catalog = pcall(function()
                    return exports.qbx_core:GetVehiclesByName()
                end)
                if okCatalog and type(catalog) == 'table' and catalog[vehicleModel] then
                    local data = catalog[vehicleModel]
                    displayName = data.name or data.label or vehicleModel
                    make = data.make or data.brand or ''
                end

                local vin = 'QBX-' .. tostring(found.id)
                local salePrice = 0
                local mods = found.mods
                if type(mods) == 'string' and mods ~= '' then
                    local okMods, decoded = pcall(json.decode, mods)
                    if okMods and type(decoded) == 'table' then
                        salePrice = tonumber(decoded.price) or 0
                    end
                end

                MySQL.insert.await([[INSERT INTO dmv_vehicle_ledger
                    (vin,buyer_citizenid,model,make,vehicle_name,sale_price,temporary_plate,current_plate,state)
                    VALUES (?,?,?,?,?,?,?,?,'AWAITING_REGISTRATION')]], {
                    vin,
                    found.citizenid,
                    vehicleModel,
                    make,
                    displayName,
                    salePrice,
                    found.plate,
                    found.plate
                })

                TriggerEvent('st_dmv:qboxVehicleRegistered', found.id, vin, found.plate, found.citizenid)
            end)
        end)
    end)

    if not ok or not result then
        print('[st_dmvsystem] WARNING: Failed to register qbx_vehicles createPlayerVehicle hook.')
        return false
    end

    hookId = result
    registeredHook = true
    print('[st_dmvsystem] QBox dealership integration enabled (qbx_vehicleshop -> qbx_vehicles -> DMV).')
    return true
end

CreateThread(function()
    for _ = 1, 60 do
        if registerQBoxDealershipHook() then return end
        Wait(1000)
    end
    if Framework.name == 'qbox' then
        print('[st_dmvsystem] WARNING: QBox dealership integration could not initialize. Ensure qbx_core, qbx_vehicles and qbx_vehicleshop are started before st_dmvsystem.')
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'qbx_vehicleshop' or resource == 'qbx_vehicles' or resource == 'qbx_core' then
        SetTimeout(500, registerQBoxDealershipHook)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= 'st_dmvsystem' then return end
    if hookId and resourceStarted('qbx_vehicles') then
        pcall(function() exports.qbx_vehicles:removeHooks(hookId) end)
    end
end)

exports('IsQBoxDealershipIntegrationActive', function()
    return registeredHook
end)
