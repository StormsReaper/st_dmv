-- Custom plate workflow for registered vehicles.
-- This is intentionally separate from the legacy registration custom-plate handler.
-- The client never supplies citizenid, owner, vehicle VIN, or price; the server resolves all of them.

local function cpOne(query, params)
    return MySQL.single.await(query, params or {})
end

local function cpScalar(query, params)
    return MySQL.scalar.await(query, params or {})
end

local function cpUpdate(query, params)
    return MySQL.update.await(query, params or {})
end

local function cpSetting(key, fallback)
    local value = cpScalar('SELECT setting_value FROM dmv_settings WHERE setting_key=?', {key})
    return value == nil and fallback or value
end

local function cpSanitizePlate(value)
    return tostring(value or ''):upper():gsub('[^A-Z0-9%-]', '')
end

local function cpIsValidPlate(plate)
    plate = cpSanitizePlate(plate)
    local max = tonumber(Config.CustomPlateMaxLength) or 8
    local min = tonumber(Config.CustomPlateMinLength) or 1
    if #plate < min or #plate > max then return false end
    return plate:match('^[A-Z0-9%-]+$') ~= nil
end

-- Player action: request a custom plate only after the vehicle has been registered.
RegisterNetEvent('st_dmv:server:requestRegisteredCustomPlate', function(vehicleLedgerId, requestedPlate)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end
    if tostring(cpSetting('custom_plate_enabled', '1')) ~= '1' then
        return TriggerClientEvent('st_dmv:client:notify', src, 'Custom plates are currently unavailable.', 'error')
    end

    local citizenid = Framework.GetIdentifier(player)
    local plate = cpSanitizePlate(requestedPlate)
    if not cpIsValidPlate(plate) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'Custom plates must be 8 characters or fewer and may only contain letters, numbers, or hyphens.', 'error')
    end

    -- The ledger is authoritative. A player cannot submit a plate for someone else's vehicle.
    local vehicle = cpOne([[SELECT id,vin,vehicle_name,assigned_plate,current_plate,state,buyer_citizenid
        FROM dmv_vehicle_ledger
        WHERE id=? AND buyer_citizenid=? AND state IN ('READY_FOR_PLATE','REGISTERED')]], {tonumber(vehicleLedgerId), citizenid})
    if not vehicle then
        return TriggerClientEvent('st_dmv:client:notify', src, 'That vehicle is not registered to you.', 'error')
    end

    -- Only one active request per vehicle. Rejected requests may be resubmitted.
    if cpScalar([[SELECT 1 FROM dmv_custom_plate_requests
        WHERE vehicle_ledger_id=? AND citizenid=? AND status IN ('PENDING','APPROVED') LIMIT 1]], {vehicle.id, citizenid}) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'You already have a custom plate request for this vehicle.', 'error')
    end

    if cpScalar([[SELECT 1 FROM dmv_vehicle_ledger
        WHERE (assigned_plate=? OR current_plate=?) AND vin<>? LIMIT 1]], {plate, plate, vehicle.vin}) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'That custom plate is already assigned.', 'error')
    end

    if cpScalar([[SELECT 1 FROM dmv_custom_plate_requests
        WHERE requested_plate=? AND status IN ('PENDING','APPROVED','PURCHASED') LIMIT 1]], {plate}) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'That custom plate is already requested or assigned.', 'error')
    end

    local requestId = MySQL.insert.await([[INSERT INTO dmv_custom_plate_requests
        (citizenid,vehicle_ledger_id,requested_plate,status)
        VALUES (?,?,?,'PENDING')]], {citizenid, vehicle.id, plate})

    TriggerClientEvent('st_dmv:client:notify', src, 'Custom plate request submitted for DMV approval.', 'success')
    TriggerClientEvent('st_dmv:client:refresh', src)
end)

-- Player action: pay for an approved custom plate and receive the physical plate item.
RegisterNetEvent('st_dmv:server:purchaseRegisteredCustomPlate', function(requestId, account)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end

    local citizenid = Framework.GetIdentifier(player)
    account = account == 'cash' and 'cash' or 'bank'
    local price = math.max(0, math.floor(tonumber(cpSetting('custom_plate_price', '750')) or 750))

    local request = cpOne([[SELECT r.*, v.vin, v.vehicle_name, v.assigned_plate AS registered_plate,
        v.current_plate, v.state, v.buyer_citizenid
        FROM dmv_custom_plate_requests r
        JOIN dmv_vehicle_ledger v ON v.id=r.vehicle_ledger_id
        WHERE r.id=? AND r.citizenid=? AND r.status='APPROVED'
        FOR UPDATE]], {tonumber(requestId), citizenid})

    if not request then
        return TriggerClientEvent('st_dmv:client:notify', src, 'That custom plate approval is no longer available.', 'error')
    end

    if request.state ~= 'READY_FOR_PLATE' and request.state ~= 'REGISTERED' then
        return TriggerClientEvent('st_dmv:client:notify', src, 'This vehicle is not currently eligible for a custom plate.', 'error')
    end

    local plate = cpSanitizePlate(request.requested_plate)
    if not cpIsValidPlate(plate) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'The approved custom plate is invalid.', 'error')
    end

    if cpScalar('SELECT 1 FROM dmv_vehicle_ledger WHERE assigned_plate=? AND vin<>? LIMIT 1', {plate, request.vin}) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'That custom plate is already assigned.', 'error')
    end

    if not Framework.RemoveMoney(player, account, price, 'dmv-custom-plate') then
        return TriggerClientEvent('st_dmv:client:notify', src, ('Custom plate cost: $%s. Insufficient funds.'):format(price), 'error')
    end

    -- Once purchased, the ledger becomes READY_FOR_PLATE with the new plate assigned.
    -- current_plate remains the physical plate currently on the vehicle until installation.
    local changed = cpUpdate([[UPDATE dmv_vehicle_ledger
        SET assigned_plate=?, state='READY_FOR_PLATE', plate_installed_at=NULL
        WHERE id=? AND buyer_citizenid=? AND state IN ('READY_FOR_PLATE','REGISTERED')]],
        {plate, request.vehicle_ledger_id, citizenid})

    if changed ~= 1 then
        Framework.AddMoney(player, account, price, 'dmv-custom-plate-refund')
        return TriggerClientEvent('st_dmv:client:notify', src, 'The vehicle changed while processing the custom plate. Your payment was refunded.', 'error')
    end

    local metadata = {
        vin = request.vin,
        owner = citizenid,
        citizenid = citizenid,
        assigned_plate = plate,
        previous_plate = request.current_plate,
        vehicle_name = request.vehicle_name,
        custom = true,
        request_id = request.id
    }

    if not Framework.AddItem(src, 'dmv_license_plate', metadata) then
        cpUpdate([[UPDATE dmv_vehicle_ledger SET assigned_plate=?, state=?, plate_installed_at=NULL WHERE id=? AND buyer_citizenid=?]],
            {request.registered_plate, request.state, request.vehicle_ledger_id, citizenid})
        Framework.AddMoney(player, account, price, 'dmv-custom-plate-refund')
        return TriggerClientEvent('st_dmv:client:notify', src, 'Your inventory could not receive the custom plate. Payment refunded.', 'error')
    end

    cpUpdate([[UPDATE dmv_custom_plate_requests
        SET status='PURCHASED', reviewed_at=COALESCE(reviewed_at,CURRENT_TIMESTAMP)
        WHERE id=? AND citizenid=? AND status='APPROVED']], {request.id, citizenid})

    TriggerClientEvent('st_dmv:client:notify', src, ('Custom plate %s purchased. Install it on the registered vehicle.'):format(plate), 'success')
    TriggerClientEvent('st_dmv:client:refresh', src)
end)
