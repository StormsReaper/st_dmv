local function lookupDriver(citizenid)
    local driver = MySQL.single.await('SELECT * FROM dmv_drivers WHERE citizenid = ?', { citizenid })
    if not driver then return nil end
    driver.licenses = MySQL.query.await('SELECT license_type, license_number, status, issued_at, expires_at FROM dmv_licenses WHERE citizenid = ?', { citizenid })
    driver.violations = MySQL.query.await('SELECT violation, points, notes, created_at, issued_by FROM dmv_violations WHERE citizenid = ? ORDER BY created_at DESC LIMIT 50', { citizenid })
    return driver
end

exports('GetVehicleByPlate', function(plate)
    plate = STDMV.NormalizePlate(plate)
    return MySQL.single.await([[SELECT * FROM dmv_vehicle_ledger
        WHERE current_plate = ? OR assigned_plate = ? OR temporary_plate = ? LIMIT 1]], { plate, plate, plate })
end)

exports('GetDriverRecord', function(citizenid)
    return lookupDriver(citizenid)
end)

exports('GetDriverRecordByLicense', function(licenseNumber)
    local citizenid = MySQL.scalar.await('SELECT citizenid FROM dmv_licenses WHERE license_number = ? LIMIT 1', { licenseNumber })
    return citizenid and lookupDriver(citizenid) or nil
end)

exports('UpdateDrivingPoints', function(citizenid, delta, reason, issuedBy)
    delta = tonumber(delta) or 0
    if delta == 0 then return false end
    local driver = MySQL.single.await('SELECT points FROM dmv_drivers WHERE citizenid = ?', { citizenid })
    if not driver then return false end
    local newPoints = math.max(0, tonumber(driver.points or 0) + delta)
    local status = newPoints >= Config.PointsSuspension and 'SUSPENDED' or 'ACTIVE'
    MySQL.update.await('UPDATE dmv_drivers SET points = ?, status = ? WHERE citizenid = ?', { newPoints, status, citizenid })
    if delta > 0 then
        MySQL.insert.await('INSERT INTO dmv_violations (citizenid, violation, points, notes, issued_by) VALUES (?, ?, ?, ?, ?)', { citizenid, reason or 'MDT points update', delta, reason or '', issuedBy or 'MDT' })
    end
    return true, newPoints
end)

exports('GetRegisteredVehicles', function(citizenid)
    return MySQL.query.await('SELECT * FROM dmv_vehicle_ledger WHERE buyer_citizenid = ? ORDER BY created_at DESC', { citizenid })
end)

exports('SetDriverStatus', function(citizenid, status)
    local allowed = { ACTIVE = true, SUSPENDED = true, REVOKED = true }
    if not allowed[status] then return false end
    return MySQL.update.await('UPDATE dmv_drivers SET status = ? WHERE citizenid = ?', { status, citizenid }) == 1
end)
