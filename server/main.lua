local function q(query, params) return MySQL.query.await(query, params or {}) end
local function one(query, params) return MySQL.single.await(query, params or {}) end
local function scalar(query, params) return MySQL.scalar.await(query, params or {}) end
local function update(query, params) return MySQL.update.await(query, params or {}) end

local function uniquePlate(prefix, length, column)
    local plate
    repeat plate = STDMV.RandomPlate(prefix, length) until not scalar(('SELECT 1 FROM dmv_vehicle_ledger WHERE `%s` = ? LIMIT 1'):format(column), { plate })
    return plate
end

local function ensureDriver(cid, name)
    MySQL.insert.await([[INSERT INTO dmv_drivers (citizenid,name) VALUES (?,?) ON DUPLICATE KEY UPDATE name=VALUES(name)]], {cid,name})
end

local function getDriver(cid)
    local d = one('SELECT * FROM dmv_drivers WHERE citizenid=?', {cid})
    if not d then return nil end
    d.violations = q('SELECT id,violation,points,notes,created_at FROM dmv_violations WHERE citizenid=? ORDER BY created_at DESC LIMIT 10',{cid})
    d.licenses = q('SELECT license_type,license_number,status,expires_at FROM dmv_licenses WHERE citizenid=? ORDER BY license_type',{cid})
    return d
end

local function issueLicense(src, cid, name, licenseType)
    local prefix = ({standard='C',cdl='CDL',taxi='TX'})[licenseType]
    if not prefix then return nil end
    local number = prefix..'-'..STDMV.RandomDigits(8)
    MySQL.insert.await([[INSERT INTO dmv_licenses (citizenid,license_type,license_number,status) VALUES (?,?,?,'ACTIVE')
        ON DUPLICATE KEY UPDATE license_number=VALUES(license_number),status='ACTIVE',issued_at=CURRENT_TIMESTAMP]], {cid,licenseType,number})
    local item = licenseType=='cdl' and 'dmv_cdl_license' or licenseType=='taxi' and 'dmv_taxi_license' or 'dmv_driver_license'
    if not Framework.AddItem(src,item,{license_number=number,citizenid=cid,holder=name,license_type=licenseType,issued_at=STDMV.Now()}) then
        MySQL.update.await('UPDATE dmv_licenses SET status="REVOKED" WHERE citizenid=? AND license_type=?',{cid,licenseType})
        return nil
    end
    return number
end

local function persistVehiclePlate(cid, vin, oldPlate, newPlate)
    if Framework.name=='qbox' or Framework.name=='qbcore' then
        local tableName=Config.VehicleTables[Framework.name]
        local cols=MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName)) or {}
        local hasPlate,hasCid=false,false
        for _,c in ipairs(cols) do hasPlate=hasPlate or c.Field=='plate'; hasCid=hasCid or c.Field=='citizenid' end
        if hasPlate and hasCid then update(('UPDATE `%s` SET plate=? WHERE citizenid=? AND plate=?'):format(tableName),{newPlate,cid,oldPlate}) end
    elseif Framework.name=='esx' then
        for _,row in ipairs(q('SELECT id,vehicle FROM owned_vehicles WHERE owner=?',{cid})) do
            local props=STDMV.SafeJsonDecode(row.vehicle,{})
            if STDMV.NormalizePlate(props.plate)==STDMV.NormalizePlate(oldPlate) or (vin and STDMV.NormalizeVin(props.vin)==STDMV.NormalizeVin(vin)) then
                props.plate=newPlate
                update('UPDATE owned_vehicles SET plate=?,vehicle=? WHERE id=?',{newPlate,STDMV.SafeJsonEncode(props),row.id})
            end
        end
    end
end

exports('RegisterNewVehicleSale',function(data)
    if type(data)~='table' then return false,nil end
    local buyer=STDMV.Trim(data.buyer); local vin=STDMV.NormalizeVin(data.vin)
    if buyer=='' or vin=='' then return false,nil end
    local old=one('SELECT temporary_plate FROM dmv_vehicle_ledger WHERE vin=?',{vin})
    if old then return true,old.temporary_plate end
    local temp=uniquePlate(Config.TemporaryPlatePrefix,8,'temporary_plate')
    MySQL.insert.await([[INSERT INTO dmv_vehicle_ledger (vin,buyer_citizenid,model,make,vehicle_name,sale_price,temporary_plate,current_plate,state)
        VALUES (?,?,?,?,?,?,?,?,'AWAITING_REGISTRATION')]],{vin,buyer,data.model or '',data.make or '',data.vehicleName or '',tonumber(data.price) or 0,temp,temp})
    return true,temp
end)

RegisterNetEvent('st_dmv:server:requestDashboard',function()
    local src=source; local p=Framework.GetPlayer(src); if not p then return end
    local cid=Framework.GetIdentifier(p); ensureDriver(cid,Framework.GetName(p))
    local registrations=q("SELECT * FROM dmv_vehicle_ledger WHERE buyer_citizenid=? AND state IN ('READY_FOR_PLATE','REGISTERED') ORDER BY registered_at DESC",{cid})
    local pending=q("SELECT * FROM dmv_vehicle_ledger WHERE buyer_citizenid=? AND state='AWAITING_REGISTRATION' ORDER BY created_at DESC",{cid})
    local questions=q('SELECT id,license_type,question,options FROM dmv_exam_questions WHERE active=1 ORDER BY license_type,id')
    for _,x in ipairs(questions) do x.options=STDMV.SafeJsonDecode(x.options,{}) end
    TriggerClientEvent('st_dmv:client:dashboard',src,{registrations=registrations,pending=pending,driver=getDriver(cid),questions=questions})
end)

RegisterNetEvent('st_dmv:server:registerVehicle',function(id,account)
    local src=source; local p=Framework.GetPlayer(src); if not p then return end
    account=account=='cash' and 'cash' or 'bank'; local cid=Framework.GetIdentifier(p)
    local row=one("SELECT * FROM dmv_vehicle_ledger WHERE id=? AND buyer_citizenid=? AND state='AWAITING_REGISTRATION'",{tonumber(id),cid})
    if not row then return TriggerClientEvent('st_dmv:client:notify',src,'Vehicle is not eligible for registration.','error') end
    local fee=Config.RegistrationFee
    if not Framework.RemoveMoney(p,account,fee,'dmv-registration') then return TriggerClientEvent('st_dmv:client:notify',src,'Insufficient funds.','error') end
    local plate=uniquePlate(Config.PlatePrefix,Config.PlateLength,'assigned_plate')
    if update("UPDATE dmv_vehicle_ledger SET assigned_plate=?,current_plate=?,state='READY_FOR_PLATE',registered_at=CURRENT_TIMESTAMP WHERE id=? AND buyer_citizenid=? AND state='AWAITING_REGISTRATION'",{plate,plate,row.id,cid})~=1 then
        if Framework.name=='esx' then p.addAccountMoney(account,fee,'dmv-registration-refund') else p.Functions.AddMoney(account,fee,'dmv-registration-refund') end
        return TriggerClientEvent('st_dmv:client:notify',src,'Registration changed before payment completed.','error')
    end
    local meta={vin=row.vin,owner=cid,citizenid=cid,assigned_plate=plate,temporary_plate=row.temporary_plate,model=row.model,make=row.make,vehicle_name=row.vehicle_name}
    if not Framework.AddItem(src,'dmv_license_plate',meta) or not Framework.AddItem(src,'dmv_registration_doc',{vin=row.vin,owner=cid,citizenid=cid,plate=plate,vehicle_name=row.vehicle_name,status='READY_FOR_PLATE'}) then
        update("UPDATE dmv_vehicle_ledger SET state='AWAITING_REGISTRATION',assigned_plate=NULL,current_plate=?,registered_at=NULL WHERE id=?",{row.temporary_plate,row.id})
        if Framework.name=='esx' then p.addAccountMoney(account,fee,'dmv-registration-refund') else p.Functions.AddMoney(account,fee,'dmv-registration-refund') end
        return TriggerClientEvent('st_dmv:client:notify',src,'Inventory could not receive the DMV documents; payment was refunded.','error')
    end
    TriggerClientEvent('st_dmv:client:notify',src,('Registration paid. Plate %s issued. Install it on the vehicle.'):format(plate),'success')
    TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:installPlate',function(netId,meta)
    local src=source; local p=Framework.GetPlayer(src); if not p then return end
    local cid=Framework.GetIdentifier(p); local vehicle=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle==0 or not DoesEntityExist(vehicle) then return TriggerClientEvent('st_dmv:client:notify',src,'Vehicle could not be verified.','error') end
    local current=STDMV.NormalizePlate(GetVehicleNumberPlateText(vehicle)); local vin=STDMV.NormalizeVin(meta and (meta.vin or meta.dmv_vin)); local assigned=STDMV.NormalizePlate(meta and (meta.assigned_plate or meta.dmv_plate)); local owner=meta and (meta.owner or meta.citizenid or meta.dmv_owner)
    if vin=='' or assigned=='' or owner~=cid then return TriggerClientEvent('st_dmv:client:notify',src,'This physical plate is not yours.','error') end
    local row=one("SELECT * FROM dmv_vehicle_ledger WHERE vin=? AND buyer_citizenid=? AND assigned_plate=? AND state='READY_FOR_PLATE'",{vin,cid,assigned})
    if not row then return TriggerClientEvent('st_dmv:client:notify',src,'DMV could not validate this plate for this vehicle.','error') end
    if current~=STDMV.NormalizePlate(row.current_plate) and current~=STDMV.NormalizePlate(row.temporary_plate) then return TriggerClientEvent('st_dmv:client:notify',src,'The vehicle plate does not match the DMV ledger.','error') end
    if update("UPDATE dmv_vehicle_ledger SET current_plate=?,state='REGISTERED',plate_installed_at=CURRENT_TIMESTAMP WHERE id=? AND state='READY_FOR_PLATE'",{assigned,row.id})~=1 then return end
    SetVehicleNumberPlateText(vehicle,assigned); persistVehiclePlate(cid,vin,current,assigned)
    if not Inventory.TakeDocument(src,'dmv_license_plate',meta) then
        update("UPDATE dmv_vehicle_ledger SET current_plate=?,state='READY_FOR_PLATE',plate_installed_at=NULL WHERE id=?",{current,row.id}); SetVehicleNumberPlateText(vehicle,current)
        return TriggerClientEvent('st_dmv:client:notify',src,'Plate could not be removed from inventory; no changes were saved.','error')
    end
    TriggerEvent('dmv:plateInstalled',row.vin,assigned,cid,true)
    TriggerClientEvent('st_dmv:client:notify',src,('DMV plate %s installed successfully.'):format(assigned),'success')
    TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:submitExam',function(licenseType,answers)
    local src=source; local p=Framework.GetPlayer(src); if not p or type(answers)~='table' then return end
    local cid=Framework.GetIdentifier(p); local last=scalar('SELECT UNIX_TIMESTAMP(created_at) FROM dmv_exam_attempts WHERE citizenid=? ORDER BY id DESC LIMIT 1',{cid})
    if last and os.time()-tonumber(last)<Config.ExamCooldownSeconds then return TriggerClientEvent('st_dmv:client:notify',src,'Please wait before taking another exam.','error') end
    local qs=q('SELECT id,correct_index FROM dmv_exam_questions WHERE active=1 AND license_type=?',{licenseType}); if #qs==0 then return end
    local correct=0; for _,x in ipairs(qs) do if tonumber(answers[tostring(x.id)] or answers[x.id])==tonumber(x.correct_index) then correct=correct+1 end end
    local score=math.floor(correct/#qs*100+0.5); local passed=score>=Config.ExamPassPercent
    MySQL.insert.await('INSERT INTO dmv_exam_attempts (citizenid,license_type,score,passed) VALUES (?,?,?,?)',{cid,licenseType,score,passed and 1 or 0})
    if not passed then return TriggerClientEvent('st_dmv:client:notify',src,('Exam failed: %s%%. Passing score is %s%%.'):format(score,Config.ExamPassPercent),'error') end
    local number=issueLicense(src,cid,Framework.GetName(p),licenseType)
    if not number then return TriggerClientEvent('st_dmv:client:notify',src,'License could not be issued to inventory.','error') end
    TriggerClientEvent('st_dmv:client:notify',src,('Exam passed. License %s issued.'):format(number),'success'); TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:addViolation',function(cid,violation,points,notes)
    local src=source; if not Framework.HasAdmin(src) then return end; points=math.max(0,tonumber(points) or 0)
    MySQL.insert.await('INSERT INTO dmv_violations (citizenid,violation,points,notes,issued_by) VALUES (?,?,?,?,?)',{cid,violation,points,notes or '',src})
    MySQL.update.await('UPDATE dmv_drivers SET points=points+?,status=CASE WHEN points+?>=? THEN \'SUSPENDED\' ELSE status END WHERE citizenid=?',{points,points,Config.PointsSuspension,cid})
end)

RegisterCommand(Config.Command,function(src,args)
    if not Framework.HasAdmin(src) then return TriggerClientEvent('st_dmv:client:notify',src,'You are not authorized.','error') end
    local x,y,z=tonumber(args[1]),tonumber(args[2]),tonumber(args[3]); if not x or not y or not z then if src==0 then print('Usage: /createdmv x y z [label]') end return end
    local label=table.concat(args,' ',4); if label=='' then label='Department of Motor Vehicles' end
    local id=MySQL.insert.await('INSERT INTO dmv_locations (label,x,y,z) VALUES (?,?,?,?)',{label,x,y,z})
    TriggerClientEvent('st_dmv:client:locationAdded',-1,{id=id,label=label,coords={x=x,y=y,z=z}})
end,false)

RegisterNetEvent('st_dmv:server:getLocations',function()
    local src=source; local rows=q('SELECT id,label,x,y,z FROM dmv_locations WHERE active=1 ORDER BY id'); TriggerClientEvent('st_dmv:client:setLocations',src,rows)
end)
