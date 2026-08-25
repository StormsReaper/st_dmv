local function sql(query, params)
    return MySQL.query.await(query, params or {})
end

local function scalar(query, params)
    return MySQL.scalar.await(query, params or {})
end

local function affected(query, params)
    return MySQL.update.await(query, params or {})
end

local function makeTempPlate()
    local plate
    repeat
        plate = STDMV.RandomPlate(Config.TemporaryPlatePrefix, 8)
    until not scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE current_plate = ? OR assigned_plate = ? LIMIT 1', { plate, plate })
    return plate
end

local function makeStatePlate()
    local plate
    repeat
        plate = STDMV.RandomPlate(Config.PlatePrefix, Config.PlateLength)
    until not scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE assigned_plate = ? LIMIT 1', { plate })
    return plate
end

local function ensureDriver(citizenid, name)
    MySQL.insert.await([[INSERT INTO dmv_drivers (citizenid, name) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name)]], { citizenid, name })
end

local function getDriver(citizenid)
    local row = MySQL.single.await('SELECT * FROM dmv_drivers WHERE citizenid = ?', { citizenid })
    if not row then return nil end
    row.violations = sql('SELECT id, violation, points, notes, created_at FROM dmv_violations WHERE citizenid = ? ORDER BY created_at DESC LIMIT 10', { citizenid })
    row.licenses = sql('SELECT license_type, license_number, status, expires_at FROM dmv_licenses WHERE citizenid = ? ORDER BY license_type', { citizenid })
    return row
end

local function issueLicense(citizenid, name, licenseType)
    local prefixes = { standard = 'C', cdl = 'CDL', taxi = 'TX' }
    local number = prefixes[licenseType] .. '-' .. STDMV.RandomDigits(8)
    MySQL.insert.await([[INSERT INTO dmv_licenses (citizenid, license_type, license_number, status)
        VALUES (?, ?, ?, 'ACTIVE')
        ON DUPLICATE KEY UPDATE license_number = VALUES(license_number), status = 'ACTIVE', issued_at = CURRENT_TIMESTAMP]],
        { citizenid, licenseType, number })
    local item = licenseType == 'cdl' and 'dmv_cdl_license' or licenseType == 'taxi' and 'dmv_taxi_license' or 'dmv_driver_license'
    Framework.AddItem(source, item, { license_number = number, citizenid = citizenid, holder = name, license_type = licenseType, issued_at = STDMV.Now() })
    return number
end

local function updateVehicleRecord(citizenid, vin, oldPlate, newPlate)
    local framework = Framework.name
    local tableName = Config.VehicleTables[framework]
    if framework == 'qbox' or framework == 'qbcore' then
        local cols = MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName)) or {}
        local names = {}
        for _, c in ipairs(cols) do names[c.Field] = true end
        if names.plate then
            affected(('UPDATE `%s` SET plate = ? WHERE citizenid = ? AND plate = ?'):format(tableName), { newPlate, citizenid, oldPlate })
        end
    elseif framework == 'esx' then
        local rows = sql('SELECT id, vehicle FROM owned_vehicles WHERE owner = ?', { citizenid })
        for _, row in ipairs(rows) do
            local props = STDMV.SafeJsonDecode(row.vehicle, {})
            if STDMV.NormalizePlate(props.plate) == STDMV.NormalizePlate(oldPlate) or (vin and props.vin == vin) then
                props.plate = newPlate
                affected('UPDATE owned_vehicles SET plate = ?, vehicle = ? WHERE id = ?', { newPlate, STDMV.SafeJsonEncode(props), row.id })
            end
        end
    end
end

exports('RegisterNewVehicleSale', function(data)
    assert(type(data) == 'table', 'RegisterNewVehicleSale expects a table')
    local buyer = STDMV.Trim(data.buyer)
    local vin = STDMV.NormalizeVin(data.vin)
    if buyer == '' or vin == '' then return false, nil end
    local exists = MySQL.single.await('SELECT id, temporary_plate FROM dmv_vehicle_ledger WHERE vin = ?', { vin })
    if exists then return true, exists.temporary_plate end
    local temporary = makeTempPlate()
    MySQL.insert.await([[INSERT INTO dmv_vehicle_ledger
        (vin, buyer_citizenid, model, make, vehicle_name, sale_price, temporary_plate, current_plate, state)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'AWAITING_REGISTRATION')]],
        { vin, buyer, data.model or '', data.make or '', data.vehicleName or '', tonumber(data.price) or 0, temporary, temporary })
    return true, temporary
end)

lib = lib or {}

RegisterNetEvent('st_dmv:server:requestDashboard', function()
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end
    local citizenid = Framework.GetIdentifier(player)
    ensureDriver(citizenid, Framework.GetName(player))
    local registrations = sql('SELECT * FROM dmv_vehicle_ledger WHERE buyer_citizenid = ? AND state IN (\'READY_FOR_PLATE\', \'REGISTERED\') ORDER BY registered_at DESC', { citizenid })
    local pending = sql('SELECT * FROM dmv_vehicle_ledger WHERE buyer_citizenid = ? AND state = \'AWAITING_REGISTRATION\' ORDER BY created_at DESC', { citizenid })
    local driver = getDriver(citizenid)
    local questions = sql('SELECT id, license_type, question, options FROM dmv_exam_questions WHERE active = 1 ORDER BY license_type, id')
    for _, q in ipairs(questions) do q.options = STDMV.SafeJsonDecode(q.options, {}) end
    TriggerClientEvent('st_dmv:client:dashboard', src, { registrations = registrations, pending = pending, driver = driver, questions = questions, locations = Config.Locations })
end)

RegisterNetEvent('st_dmv:server:registerVehicle', function(id, account)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end
    local citizenid = Framework.GetIdentifier(player)
    local row = MySQL.single.await('SELECT * FROM dmv_vehicle_ledger WHERE id = ? AND buyer_citizenid = ? AND state = \'AWAITING_REGISTRATION\'', { tonumber(id), citizenid })
    if not row then return TriggerClientEvent('st_dmv:client:notify', src, 'Vehicle is not eligible for registration.', 'error') end
    local fee = Config.RegistrationFee
    if not Framework.RemoveMoney(player, account, fee, 'dmv-registration') then
        return TriggerClientEvent('st_dmv:client:notify', src, 'Insufficient funds.', 'error')
    end
    local plate = makeStatePlate()
    local updated = affected([[UPDATE dmv_vehicle_ledger SET assigned_plate = ?, current_plate = ?, state = 'READY_FOR_PLATE', registered_at = CURRENT_TIMESTAMP
        WHERE id = ? AND buyer_citizenid = ? AND state = 'AWAITING_REGISTRATION']], { plate, plate, row.id, citizenid })
    if updated ~= 1 then
        if Framework.name == 'esx' then player.addAccountMoney(account, fee, 'dmv-registration-refund') else player.Functions.AddMoney(account, fee, 'dmv-registration-refund') end
        return TriggerClientEvent('st_dmv:client:notify', src, 'Registration changed before payment completed.', 'error')
    end
    local metadata = { vin = row.vin, owner = citizenid, citizenid = citizenid, assigned_plate = plate, temporary_plate = row.temporary_plate, model = row.model, make = row.make, vehicle_name = row.vehicle_name }
    Framework.AddItem(src, 'dmv_license_plate', metadata)
    Framework.AddItem(src, 'dmv_registration_doc', { vin = row.vin, owner = citizenid, citizenid = citizenid, plate = plate, vehicle_name = row.vehicle_name, status = 'READY_FOR_PLATE' })
    TriggerClientEvent('st_dmv:client:notify', src, ('Registration paid. Plate %s issued. Install it on the vehicle.'):format(plate), 'success')
    TriggerClientEvent('st_dmv:client:refresh', src)
end)

RegisterNetEvent('st_dmv:server:installPlate', function(netId, plateItemMetadata)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player then return end
    local citizenid = Framework.GetIdentifier(player)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return TriggerClientEvent('st_dmv:client:notify', src, 'Vehicle could not be verified.', 'error') end
    local currentPlate = STDMV.NormalizePlate(GetVehicleNumberPlateText(vehicle))
    local vin = STDMV.NormalizeVin(plateItemMetadata and (plateItemMetadata.vin or plateItemMetadata.dmv_vin))
    local assigned = STDMV.NormalizePlate(plateItemMetadata and (plateItemMetadata.assigned_plate or plateItemMetadata.dmv_plate))
    local owner = plateItemMetadata and (plateItemMetadata.owner or plateItemMetadata.citizenid or plateItemMetadata.dmv_owner)
    if vin == '' or assigned == '' or owner ~= citizenid then return TriggerClientEvent('st_dmv:client:notify', src, 'This physical plate is not yours.', 'error') end
    local row = MySQL.single.await([[SELECT * FROM dmv_vehicle_ledger WHERE vin = ? AND buyer_citizenid = ? AND assigned_plate = ? AND state = 'READY_FOR_PLATE' LIMIT 1]], { vin, citizenid, assigned })
    if not row then return TriggerClientEvent('st_dmv:client:notify', src, 'DMV could not validate this plate for this vehicle.', 'error') end
    if currentPlate ~= STDMV.NormalizePlate(row.current_plate) and currentPlate ~= STDMV.NormalizePlate(row.temporary_plate) then
        return TriggerClientEvent('st_dmv:client:notify', src, 'The vehicle plate does not match the DMV ledger.', 'error')
    end
    local updated = affected([[UPDATE dmv_vehicle_ledger SET current_plate = ?, state = 'REGISTERED', plate_installed_at = CURRENT_TIMESTAMP
        WHERE id = ? AND state = 'READY_FOR_PLATE' AND assigned_plate = ?]], { assigned, row.id, assigned })
    if updated ~= 1 then return TriggerClientEvent('st_dmv:client:notify', src, 'Plate installation was already completed.', 'error') end
    SetVehicleNumberPlateText(vehicle, assigned)
    updateVehicleRecord(citizenid, row.vin, currentPlate, assigned)
    local consumed = Inventory.TakeDocument(src, 'dmv_license_plate', plateItemMetadata)
    if not consumed then
        MySQL.update.await("UPDATE dmv_vehicle_ledger SET state = 'READY_FOR_PLATE', current_plate = ?, plate_installed_at = NULL WHERE id = ?", { currentPlate, row.id })
        SetVehicleNumberPlateText(vehicle, currentPlate)
        return TriggerClientEvent('st_dmv:client:notify', src, 'Plate could not be removed from inventory; no changes were saved.', 'error')
    end
    TriggerEvent('dmv:plateInstalled', row.vin, assigned, citizenid, true)
    TriggerClientEvent('st_dmv:client:notify', src, ('DMV plate %s installed successfully.'):format(assigned), 'success')
    TriggerClientEvent('st_dmv:client:refresh', src)
end)

RegisterNetEvent('st_dmv:server:submitExam', function(licenseType, answers)
    local src = source
    local player = Framework.GetPlayer(src)
    if not player or type(answers) ~= 'table' then return end
    local citizenid = Framework.GetIdentifier(player)
    local last = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(created_at) FROM dmv_exam_attempts WHERE citizenid = ? ORDER BY id DESC LIMIT 1', { citizenid })
    if last and os.time() - tonumber(last) < Config.ExamCooldownSeconds then return TriggerClientEvent('st_dmv:client:notify', src, 'Please wait before taking another exam.', 'error') end
    local questions = sql('SELECT id, correct_index FROM dmv_exam_questions WHERE active = 1 AND license_type = ?', { licenseType })
    if #questions == 0 then return TriggerClientEvent('st_dmv:client:notify', src, 'No exam is configured for this license.', 'error') end
    local correct = 0
    for _, q in ipairs(questions) do if tonumber(answers[tostring(q.id)] or answers[q.id]) == tonumber(q.correct_index) then correct = correct + 1 end end
    local percent = math.floor((correct / #questions) * 100 + 0.5)
    local passed = percent >= Config.ExamPassPercent
    MySQL.insert.await('INSERT INTO dmv_exam_attempts (citizenid, license_type, score, passed) VALUES (?, ?, ?, ?)', { citizenid, licenseType, percent, passed and 1 or 0 })
    if not passed then return TriggerClientEvent('st_dmv:client:notify', src, ('Exam failed: %s%%. Passing score is %s%%.'):format(percent, Config.ExamPassPercent), 'error') end
    local name = Framework.GetName(player)
    local number = issueLicense(citizenid, name, licenseType)
    TriggerClientEvent('st_dmv:client:notify', src, ('Exam passed. License %s issued.'):format(number), 'success')
    TriggerClientEvent('st_dmv:client:refresh', src)
end)

RegisterNetEvent('st_dmv:server:addViolation', function(targetCitizenid, violation, points, notes)
    local src = source
    if not Framework.HasAdmin(src) then return end
    points = math.max(0, tonumber(points) or 0)
    MySQL.insert.await('INSERT INTO dmv_violations (citizenid, violation, points, notes, issued_by) VALUES (?, ?, ?, ?, ?)', { targetCitizenid, violation, points, notes or '', src })
    MySQL.update.await('UPDATE dmv_drivers SET points = points + ?, status = CASE WHEN points + ? >= ? THEN \'SUSPENDED\' ELSE status END WHERE citizenid = ?', { points, points, Config.PointsSuspension, targetCitizenid })
end)

RegisterCommand(Config.Command, function(src, args)
    if not Framework.HasAdmin(src) then return TriggerClientEvent('st_dmv:client:notify', src, 'You are not authorized.', 'error') end
    local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not x or not y or not z then
        if src == 0 then print('Usage: /createdmv x y z') end
        return
    end
    local label = table.concat(args, ' ', 4)
    if label == '' then label = 'Department of Motor Vehicles' end
    local id = MySQL.insert.await('INSERT INTO dmv_locations (label, x, y, z) VALUES (?, ?, ?, ?)', { label, x, y, z })
    TriggerClientEvent('st_dmv:client:locationAdded', -1, { id = id, label = label, coords = { x = x, y = y, z = z } })
end, false)

RegisterNetEvent('st_dmv:server:getLocations', function()
    local src = source
    local rows = sql('SELECT id, label, x, y, z FROM dmv_locations WHERE active = 1 ORDER BY id')
    TriggerClientEvent('st_dmv:client:setLocations', src, rows)
end)
