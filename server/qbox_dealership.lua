-- QBox / qbx_vehicleshop integration.
-- qbx_vehicleshop creates customer vehicles through qbx_vehicles:CreatePlayerVehicle.
-- Qbox exposes that creation point through the qbx_core event-hook system. We use the
-- hook only while qbx_vehicleshop is running so normal vehicle imports are not treated
-- as dealership purchases.

local registeredHook = false
local hookId
local pendingCreates = {}

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
    if not resourceStarted('qbx_core') or not resourceStarted('qbx_vehicles') then return false end
    if not resourceStarted('qbx_vehicleshop') then return false end

    local ok, result = pcall(function()
        return exports.qbx_core:registerHook('createPlayerVehicle', function(payload)
            if type(payload) ~= 'table' then return end
            if not payload.citizenid or type(payload.props) ~= 'table' then return end

            local props = payload.props
            local plate = STDMV.NormalizePlate(props.plate)
            if plate == '' then return end

            -- qbx_vehicles runs the INSERT after this hook returns. Defer until the
            -- player_vehicles row exists, then copy the dealership purchase into the
            -- DMV ledger as AWAITING_REGISTRATION.
            pendingCreates[plate] = {
                citizenid = STDMV.Trim(payload.citizenid),
                model = props.modelName or props.vehicle or '',
                props = props,
                createdAt = os.time()
            }

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

                pendingCreates[plate] = nil
                if not found then return end

                -- Never duplicate an existing DMV ledger record.
                local existing = MySQL.scalar.await('SELECT id FROM dmv_vehicle_ledger WHERE vin=? OR temporary_plate=? LIMIT 1', {
                    ('QBX-' .. tostring(found.id)),
                    found.plate
                })
                if existing then return end

                local vehicleProps = safeDecode(found.mods)
                local vehicleModel = found.vehicle or props.modelName or props.vehicle or ''
                local displayName = vehicleModel
                local make = ''

                -- qbx_core's vehicle catalog is the authoritative source for the
                -- display name. Do not make the DMV dependent on catalog columns.
                if GetResourceState('qbx_core') == 'started' then
                    local okCatalog, catalog = pcall(function()
                        return exports.qbx_core:GetVehiclesByName()
                    end)
                    if okCatalog and type(catalog) == 'table' and catalog[vehicleModel] then
                        local data = catalog[vehicleModel]
                        displayName = data.name or data.label or vehicleModel
                        make = data.make or data.brand or ''
                    end
                end

                local vin = 'QBX-' .. tostring(found.id)
                local salePrice = 0
                if vehicleProps.price then salePrice = tonumber(vehicleProps.price) or 0 end

                -- The qbx_vehicles API does not expose a VIN column. The immutable
                -- qbx vehicle id is therefore used as the DMV VIN/vehicle identity
                -- for QBox-owned vehicles. This remains stable across plate changes.
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
        print('[st_dmvsystem] WARNING: Failed to register the QBox qbx_vehicleshop vehicle hook.')
        return false
    end

    hookId = result
    registeredHook = true
    print('[st_dmvsystem] QBox dealership integration enabled (qbx_vehicleshop -> DMV).')
    return true
end

CreateThread(function()
    for _ = 1, 60 do
        if registerQBoxDealershipHook() then return end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'qbx_vehicleshop' or resource == 'qbx_vehicles' or resource == 'qbx_core' then
        SetTimeout(500, registerQBoxDealershipHook)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= 'st_dmvsystem' then return end
    if hookId and resourceStarted('qbx_core') then
        pcall(function() exports.qbx_core:removeHooks(hookId) end)
    end
end)

exports('IsQBoxDealershipIntegrationActive', function()
    return registeredHook
end)
