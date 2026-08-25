-- QBox / qbx_vehicleshop integration.
-- qbx_vehicles exposes the authoritative createPlayerVehicle hook used by
-- qbx_vehicleshop. The hook fires for every new owned QBox vehicle, so the DMV
-- ledger is populated automatically without requiring edits to qbx_vehicleshop.
-- Existing/imported vehicles are de-duplicated by the immutable QBox vehicle id.

local registeredHook = false
local hookId

local function resourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function safeDecode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or {}
end

local function registerQBoxDealershipHook()
    if registeredHook then return true end
    if Framework.name ~= 'qbox' then return false end
    if not resourceStarted('qbx_core') or not resourceStarted('qbx_vehicles') or not resourceStarted('qbx_vehicleshop') then return false end

    local ok, result = pcall(function()
        -- This hook is exported by qbx_vehicles, not qbx_core.
        return exports.qbx_vehicles:registerHook('createPlayerVehicle', function(payload)
            if type(payload) ~= 'table' or not payload.citizenid or type(payload.props) ~= 'table' then return end

            local props = payload.props
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
                    print(('[st_dmvsystem] QBox vehicle created but DMV could not find player_vehicles row for plate %s.'):format(plate))
                    return
                end

                -- The QBox vehicle id is the stable identity for the DMV ledger.
                local vin = 'QBX-' .. tostring(found.id)
                if MySQL.scalar.await('SELECT id FROM dmv_vehicle_ledger WHERE vin=? LIMIT 1', {vin}) then return end

                local vehicleModel = found.vehicle or props.modelName or props.vehicle or ''
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

                local mods = safeDecode(found.mods)
                local salePrice = tonumber(mods.price) or 0

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
