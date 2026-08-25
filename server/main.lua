local function q(query, params) return MySQL.query.await(query, params or {}) end
local function one(query, params) return MySQL.single.await(query, params or {}) end
local function scalar(query, params) return MySQL.scalar.await(query, params or {}) end
local function update(query, params) return MySQL.update.await(query, params or {}) end

local function setting(key, fallback)
    local value = scalar('SELECT setting_value FROM dmv_settings WHERE setting_key=?', {key})
    if value == nil then return fallback end
    return value
end

local function numSetting(key, fallback) return tonumber(setting(key, fallback)) or fallback end
local function boolSetting(key, fallback) return tostring(setting(key, fallback and '1' or '0')) == '1' end
local function textSetting(key, fallback) return tostring(setting(key, fallback)) end

local function saveSetting(key, value)
    MySQL.insert.await('INSERT INTO dmv_settings (setting_key,setting_value) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)', {key,tostring(value)})
end

local function sanitizePlate(value)
    value=tostring(value or ''):upper():gsub('[^A-Z0-9%-]','')
    return value
end

local function plateFromFormat(format)
    local out=''
    for i=1,#format do
        local c=format:sub(i,i)
        if c=='#' then out=out..STDMV.RandomPlate('',1) else out=out..c end
    end
    return out
end

local function uniqueAssignedPlate()
    local format=textSetting('plate_format',Config.PlateFormat)
    local plate
    repeat plate=plateFromFormat(format) until not scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE assigned_plate=? LIMIT 1',{plate})
    return plate
end

local function ensureDriver(cid,name)
    MySQL.insert.await([[INSERT INTO dmv_drivers (citizenid,name) VALUES (?,?) ON DUPLICATE KEY UPDATE name=VALUES(name)]],{cid,name})
end

local function getDriver(cid)
    local d=one('SELECT * FROM dmv_drivers WHERE citizenid=?',{cid})
    if not d then return nil end
    d.violations=q('SELECT id,violation,points,notes,created_at FROM dmv_violations WHERE citizenid=? ORDER BY created_at DESC LIMIT 10',{cid})
    d.licenses=q('SELECT license_type,license_number,status,expires_at FROM dmv_licenses WHERE citizenid=? ORDER BY license_type',{cid})
    return d
end

local function issueLicense(src,cid,name,licenseType)
    local prefix=({standard='C',cdl='CDL',taxi='TX'})[licenseType]; if not prefix then return nil end
    local number=prefix..'-'..STDMV.RandomDigits(8)
    MySQL.insert.await([[INSERT INTO dmv_licenses (citizenid,license_type,license_number,status) VALUES (?,?,?,'ACTIVE') ON DUPLICATE KEY UPDATE license_number=VALUES(license_number),status='ACTIVE',issued_at=CURRENT_TIMESTAMP]],{cid,licenseType,number})
    local item=licenseType=='cdl' and 'dmv_cdl_license' or licenseType=='taxi' and 'dmv_taxi_license' or 'dmv_driver_license'
    if not Framework.AddItem(src,item,{license_number=number,citizenid=cid,holder=name,license_type=licenseType,issued_at=STDMV.Now()}) then
        update('UPDATE dmv_licenses SET status="REVOKED" WHERE citizenid=? AND license_type=?',{cid,licenseType}); return nil
    end
    return number
end

local function persistVehiclePlate(cid,vin,oldPlate,newPlate)
    local tableName=Config.VehicleTables[Framework.name]
    if not tableName then return false end
    if Framework.name=='qbox' or Framework.name=='qbcore' then
        local cols=q(('SHOW COLUMNS FROM `%s`'):format(tableName)); local hasPlate,hasCid=false,false
        for _,c in ipairs(cols or {}) do hasPlate=hasPlate or c.Field=='plate'; hasCid=hasCid or c.Field=='citizenid' end
        if hasPlate and hasCid then update(('UPDATE `%s` SET plate=? WHERE citizenid=? AND plate=?'):format(tableName),{newPlate,cid,oldPlate}); return true end
    elseif Framework.name=='esx' then
        local rows=q('SELECT id,vehicle,plate FROM owned_vehicles WHERE owner=?',{cid}) or {}
        for _,row in ipairs(rows) do
            local props=STDMV.SafeJsonDecode(row.vehicle,{})
            if STDMV.NormalizePlate(props.plate)==STDMV.NormalizePlate(oldPlate) or STDMV.NormalizeVin(props.vin)==STDMV.NormalizeVin(vin) then
                props.plate=newPlate; update('UPDATE owned_vehicles SET plate=?,vehicle=? WHERE id=?',{newPlate,STDMV.SafeJsonEncode(props),row.id}); return true
            end
        end
    end
    return false
end

exports('RegisterNewVehicleSale',function(data)
    if type(data)~='table' then return false,nil end
    local buyer=STDMV.Trim(data.buyer); local vin=STDMV.NormalizeVin(data.vin)
    if buyer=='' or vin=='' then return false,nil end
    local old=one('SELECT temporary_plate FROM dmv_vehicle_ledger WHERE vin=?',{vin})
    if old then return true,old.temporary_plate end
    local temp=STDMV.RandomPlate(Config.TemporaryPlatePrefix,8)
    MySQL.insert.await([[INSERT INTO dmv_vehicle_ledger (vin,buyer_citizenid,model,make,vehicle_name,sale_price,temporary_plate,current_plate,state) VALUES (?,?,?,?,?,?,?,?,'AWAITING_REGISTRATION')]],{vin,buyer,data.model or '',data.make or '',data.vehicleName or '',tonumber(data.price) or 0,temp,temp})
    return true,temp
end)

RegisterNetEvent('st_dmv:server:requestDashboard',function()
    local src=source; local p=Framework.GetPlayer(src); if not p then return end
    local cid=Framework.GetIdentifier(p); ensureDriver(cid,Framework.GetName(p))
    local registrations=q("SELECT * FROM dmv_vehicle_ledger WHERE buyer_citizenid=? AND state IN ('READY_FOR_PLATE','REGISTERED') ORDER BY registered_at DESC",{cid})
    local pending=q("SELECT v.*, (SELECT status FROM dmv_custom_plate_requests r WHERE r.vehicle_ledger_id=v.id ORDER BY r.id DESC LIMIT 1) custom_status, (SELECT requested_plate FROM dmv_custom_plate_requests r WHERE r.vehicle_ledger_id=v.id ORDER BY r.id DESC LIMIT 1) custom_plate FROM dmv_vehicle_ledger v WHERE v.buyer_citizenid=? AND v.state='AWAITING_REGISTRATION' ORDER BY v.created_at DESC",{cid})
    local approved=q("SELECT r.*,v.vehicle_name,v.vin FROM dmv_custom_plate_requests r JOIN dmv_vehicle_ledger v ON v.id=r.vehicle_ledger_id WHERE r.citizenid=? AND r.status='APPROVED' ORDER BY r.id DESC",{cid})
    local questions=q('SELECT id,license_type,question,options FROM dmv_exam_questions WHERE active=1 ORDER BY license_type,id')
    for _,x in ipairs(questions) do x.options=STDMV.SafeJsonDecode(x.options,{}) end
    TriggerClientEvent('st_dmv:client:dashboard',src,{registrations=registrations,pending=pending,approvedCustom=approved,driver=getDriver(cid),questions=questions,settings={customEnabled=boolSetting('custom_plate_enabled',true),customPrice=numSetting('custom_plate_price',750),registrationFee=numSetting('registration_fee',350),coverageDays=numSetting('registration_coverage_days',365)}})
end)

RegisterNetEvent('st_dmv:server:registerVehicle',function(id,account,useCustom)
    local src=source; local p=Framework.GetPlayer(src); if not p then return end
    local cid=Framework.GetIdentifier(p); account=account=='cash' and 'cash' or 'bank'
    local row=one("SELECT * FROM dmv_vehicle_ledger WHERE id=? AND buyer_citizenid=? AND state='AWAITING_REGISTRATION'",{tonumber(id),cid})
    if not row then return TriggerClientEvent('st_dmv:client:notify',src,'Vehicle is not eligible for registration.','error') end
    -- Never trust client ownership/price/plate data. The ledger is the source of truth.
    local fee=numSetting('registration_fee',350); local assigned=uniqueAssignedPlate()
    if useCustom then
        local req=one("SELECT * FROM dmv_custom_plate_requests WHERE vehicle_ledger_id=? AND citizenid=? AND status='APPROVED' ORDER BY id DESC LIMIT 1",{row.id,cid})
        if not req then return TriggerClientEvent('st_dmv:client:notify',src,'No approved custom plate exists for this vehicle.','error') end
        assigned=sanitizePlate(req.requested_plate)
        if not assigned:match(Config.CustomPlatePattern) or #assigned<Config.CustomPlateMinLength or #assigned>Config.CustomPlateMaxLength then return TriggerClientEvent('st_dmv:client:notify',src,'The approved custom plate is invalid.','error') end
        if scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE assigned_plate=? LIMIT 1',{assigned}) then return TriggerClientEvent('st_dmv:client:notify',src,'That plate is already assigned.','error') end
        fee=fee+numSetting('custom_plate_price',750)
    end
    if not Framework.RemoveMoney(p,account,fee,'dmv-registration') then return TriggerClientEvent('st_dmv:client:notify',src,'Insufficient funds.','error') end
    local coverage=math.max(1,numSetting('registration_coverage_days',365)); local expires=os.date('%Y-%m-%d %H:%M:%S',os.time()+coverage*86400)
    if update("UPDATE dmv_vehicle_ledger SET assigned_plate=?,current_plate=?,state='READY_FOR_PLATE',registration_expires_at=?,registered_at=CURRENT_TIMESTAMP WHERE id=? AND buyer_citizenid=? AND state='AWAITING_REGISTRATION'",{assigned,assigned,expires,row.id,cid})~=1 then
        Framework.AddMoney(p,account,fee,'dmv-registration-refund'); return TriggerClientEvent('st_dmv:client:notify',src,'Registration changed before payment completed.','error')
    end
    local meta={vin=row.vin,owner=cid,citizenid=cid,assigned_plate=assigned,temporary_plate=row.temporary_plate,model=row.model,make=row.make,vehicle_name=row.vehicle_name}
    local plateOk=Framework.AddItem(src,'dmv_license_plate',meta)
    local docOk=Framework.AddItem(src,'dmv_registration_doc',{vin=row.vin,owner=cid,citizenid=cid,plate=assigned,vehicle_name=row.vehicle_name,expires_at=expires,status='READY_FOR_PLATE'})
    if not plateOk or not docOk then
        update("UPDATE dmv_vehicle_ledger SET state='AWAITING_REGISTRATION',assigned_plate=NULL,current_plate=?,registration_expires_at=NULL,registered_at=NULL WHERE id=?",{row.temporary_plate,row.id})
        Framework.AddMoney(p,account,fee,'dmv-registration-refund')
        return TriggerClientEvent('st_dmv:client:notify',src,'Inventory could not receive the DMV documents; payment was refunded.','error')
    end
    local req=one("SELECT id FROM dmv_custom_plate_requests WHERE vehicle_ledger_id=? AND citizenid=? AND status='APPROVED' ORDER BY id DESC LIMIT 1",{row.id,cid})
    if req and useCustom then update("UPDATE dmv_custom_plate_requests SET status='PURCHASED' WHERE id=?",{req.id}) end
    TriggerClientEvent('st_dmv:client:notify',src,('Registration paid. Plate %s issued. Install it on the vehicle.'):format(assigned),'success')
    TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:requestCustomPlate',function(vehicleId,plate)
    local src=source; local p=Framework.GetPlayer(src); if not p or not boolSetting('custom_plate_enabled',true) then return end
    local cid=Framework.GetIdentifier(p); plate=sanitizePlate(plate)
    if #plate<Config.CustomPlateMinLength or #plate>Config.CustomPlateMaxLength or not plate:match(Config.CustomPlatePattern) then return TriggerClientEvent('st_dmv:client:notify',src,'Custom plates may only contain letters and numbers.','error') end
    local row=one("SELECT id FROM dmv_vehicle_ledger WHERE id=? AND buyer_citizenid=? AND state='AWAITING_REGISTRATION'",{tonumber(vehicleId),cid})
    if not row then return TriggerClientEvent('st_dmv:client:notify',src,'That vehicle is not yours or is not awaiting registration.','error') end
    if scalar("SELECT 1 FROM dmv_custom_plate_requests WHERE vehicle_ledger_id=? AND status IN ('PENDING','APPROVED') LIMIT 1",{row.id}) then return TriggerClientEvent('st_dmv:client:notify',src,'A custom plate request already exists for this vehicle.','error') end
    if scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE assigned_plate=? OR current_plate=? LIMIT 1',{plate,plate}) then return TriggerClientEvent('st_dmv:client:notify',src,'That plate is already in use.','error') end
    MySQL.insert.await('INSERT INTO dmv_custom_plate_requests (citizenid,vehicle_ledger_id,requested_plate) VALUES (?,?,?)',{cid,row.id,plate})
    TriggerClientEvent('st_dmv:client:notify',src,'Custom plate request submitted for DMV review.','success'); TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:purchaseApprovedCustom',function(requestId,account)
    local src=source; local p=Framework.GetPlayer(src); if not p then return end
    local cid=Framework.GetIdentifier(p); account=account=='cash' and 'cash' or 'bank'
    local req=one("SELECT r.*,v.vehicle_name FROM dmv_custom_plate_requests r JOIN dmv_vehicle_ledger v ON v.id=r.vehicle_ledger_id WHERE r.id=? AND r.citizenid=? AND r.status='APPROVED'",{tonumber(requestId),cid})
    if not req then return TriggerClientEvent('st_dmv:client:notify',src,'Custom plate approval is no longer valid.','error') end
    local price=numSetting('custom_plate_price',750)
    if not Framework.RemoveMoney(p,account,price,'dmv-custom-plate') then return TriggerClientEvent('st_dmv:client:notify',src,'Insufficient funds.','error') end
    local plate=sanitizePlate(req.requested_plate)
    if scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE assigned_plate=? LIMIT 1',{plate}) then Framework.AddMoney(p,account,price,'dmv-custom-plate-refund'); return TriggerClientEvent('st_dmv:client:notify',src,'That custom plate is already assigned.','error') end
    local itemMeta={vin=scalar('SELECT vin FROM dmv_vehicle_ledger WHERE id=?',{req.vehicle_ledger_id}),owner=cid,citizenid=cid,assigned_plate=plate,custom=true,request_id=req.id,vehicle_name=req.vehicle_name}
    if not Framework.AddItem(src,'dmv_license_plate',itemMeta) then Framework.AddMoney(p,account,price,'dmv-custom-plate-refund'); return TriggerClientEvent('st_dmv:client:notify',src,'Inventory could not receive the custom plate; payment refunded.','error') end
    update("UPDATE dmv_custom_plate_requests SET status='PURCHASED' WHERE id=? AND status='APPROVED'",{req.id})
    TriggerClientEvent('st_dmv:client:notify',src,('Congrats! Your custom plate %s has been approved and paid for.'):format(plate),'success'); TriggerClientEvent('st_dmv:client:refresh',src)
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
    local ped=GetPlayerPed(src); local vehicleCoords=GetEntityCoords(vehicle); local playerCoords=GetEntityCoords(ped)
    if #(playerCoords-vehicleCoords)>8.0 then return TriggerClientEvent('st_dmv:client:notify',src,'Move closer to the vehicle.','error') end
    if update("UPDATE dmv_vehicle_ledger SET current_plate=?,state='REGISTERED',plate_installed_at=CURRENT_TIMESTAMP WHERE id=? AND state='READY_FOR_PLATE'",{assigned,row.id})~=1 then return end
    SetVehicleNumberPlateText(vehicle,assigned); persistVehiclePlate(cid,vin,current,assigned)
    if not Inventory.TakeDocument(src,'dmv_license_plate',meta) then
        update("UPDATE dmv_vehicle_ledger SET current_plate=?,state='READY_FOR_PLATE',plate_installed_at=NULL WHERE id=?",{current,row.id}); SetVehicleNumberPlateText(vehicle,current)
        return TriggerClientEvent('st_dmv:client:notify',src,'Plate could not be removed from inventory; no changes were saved.','error')
    end
    TriggerEvent('dmv:plateInstalled',row.vin,assigned,cid,true); TriggerClientEvent('st_dmv:client:notify',src,('DMV plate %s installed successfully.'):format(assigned),'success'); TriggerClientEvent('st_dmv:client:refresh',src)
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
    local number=issueLicense(src,cid,Framework.GetName(p),licenseType); if not number then return TriggerClientEvent('st_dmv:client:notify',src,'License could not be issued to inventory.','error') end
    TriggerClientEvent('st_dmv:client:notify',src,('Exam passed. License %s issued.'):format(number),'success'); TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:addViolation',function(cid,violation,points,notes)
    local src=source; if not Framework.HasAdmin(src) then return end; points=math.max(0,tonumber(points) or 0)
    MySQL.insert.await('INSERT INTO dmv_violations (citizenid,violation,points,notes,issued_by) VALUES (?,?,?,?,?)',{cid,violation,points,notes or '',src})
    update("UPDATE dmv_drivers SET points=points+?,status=CASE WHEN points+?>=? THEN 'SUSPENDED' ELSE status END WHERE citizenid=?",{points,points,Config.PointsSuspension,cid})
end)

RegisterNetEvent('st_dmv:server:getAdminPanel',function()
    local src=source; if not Framework.HasAdmin(src) then return end
    local locations=q('SELECT * FROM dmv_locations ORDER BY id')
    local requests=q("SELECT r.*,v.vehicle_name,v.vin FROM dmv_custom_plate_requests r JOIN dmv_vehicle_ledger v ON v.id=r.vehicle_ledger_id WHERE r.status='PENDING' ORDER BY r.created_at")
    TriggerClientEvent('st_dmv:client:adminData',src,{locations=locations,requests=requests,settings={registrationFee=numSetting('registration_fee',350),coverageDays=numSetting('registration_coverage_days',365),plateFormat=textSetting('plate_format',Config.PlateFormat),customEnabled=boolSetting('custom_plate_enabled',true),customPrice=numSetting('custom_plate_price',750)}})
end)

RegisterNetEvent('st_dmv:server:adminSetting',function(key,value)
    local src=source; if not Framework.HasAdmin(src) then return end
    local allowed={registration_fee=true,registration_coverage_days=true,plate_format=true,custom_plate_enabled=true,custom_plate_price=true}; if not allowed[key] then return end
    if key=='registration_fee' or key=='custom_plate_price' or key=='registration_coverage_days' then value=math.max(0,math.floor(tonumber(value) or 0))
    elseif key=='custom_plate_enabled' then value=(value==true or value=='true' or value==1) and '1' or '0'
    elseif key=='plate_format' then value=tostring(value):upper():gsub('[^A-Z0-9#%-]',''); if not value:find('#') then return end end
    saveSetting(key,value); TriggerClientEvent('st_dmv:client:notify',src,'DMV setting saved.','success')
end)

RegisterNetEvent('st_dmv:server:createLocation',function(label,coords)
    local src=source; if not Framework.HasAdmin(src) or type(coords)~='table' then return end
    local x,y,z=tonumber(coords.x),tonumber(coords.y),tonumber(coords.z); if not x or not y or not z then return end
    label=tostring(label or 'Department of Motor Vehicles'):sub(1,100)
    local id=MySQL.insert.await('INSERT INTO dmv_locations (label,x,y,z) VALUES (?,?,?,?)',{label,x,y,z})
    TriggerClientEvent('st_dmv:client:locationAdded',-1,{id=id,label=label,coords={x=x,y=y,z=z}}); TriggerClientEvent('st_dmv:client:notify',src,'DMV location created.','success')
end)

RegisterNetEvent('st_dmv:server:updateLocation',function(id,data)
    local src=source; if not Framework.HasAdmin(src) or type(data)~='table' then return end
    local row=one('SELECT id FROM dmv_locations WHERE id=?',{tonumber(id)}); if not row then return end
    if data.delete then update('DELETE FROM dmv_locations WHERE id=?',{row.id})
    else
        local x,y,z=tonumber(data.x),tonumber(data.y),tonumber(data.z); local mx,my,mz=tonumber(data.menu_x),tonumber(data.menu_y),tonumber(data.menu_z)
        if not x or not y or not z then return end
        update('UPDATE dmv_locations SET label=?,x=?,y=?,z=?,menu_x=?,menu_y=?,menu_z=?,active=? WHERE id=?',{tostring(data.label or 'DMV'):sub(1,100),x,y,z,mx,my,mz,data.active==false and 0 or 1,row.id})
    end
    TriggerClientEvent('st_dmv:client:reloadLocations',-1); TriggerClientEvent('st_dmv:client:notify',src,data.delete and 'DMV location deleted.' or 'DMV location updated.','success')
end)

RegisterNetEvent('st_dmv:server:reviewCustomPlate',function(id,approve,reason)
    local src=source; if not Framework.HasAdmin(src) then return end
    local status=approve and 'APPROVED' or 'REJECTED'; local req=one("SELECT * FROM dmv_custom_plate_requests WHERE id=? AND status='PENDING'",{tonumber(id)}); if not req then return end
    update('UPDATE dmv_custom_plate_requests SET status=?,reviewed_by=?,reviewed_at=NOW(),rejection_reason=? WHERE id=? AND status=\'PENDING\'',{status,Framework.GetIdentifier(Framework.GetPlayer(src)) or tostring(src),reason or '',req.id})
    local target=0
    for _,idp in ipairs(GetPlayers()) do local p=Framework.GetPlayer(tonumber(idp)); if p and Framework.GetIdentifier(p)==req.citizenid then target=tonumber(idp); break end end
    if target>0 then TriggerClientEvent('st_dmv:client:notify',target,approve and 'Your custom plate request has been approved.' or 'Your custom plate request was rejected.','info'); TriggerClientEvent('st_dmv:client:refresh',target) end
    TriggerClientEvent('st_dmv:client:notify',src,'Custom plate request reviewed.','success'); TriggerClientEvent('st_dmv:client:adminRefresh',src)
end)

RegisterCommand(Config.Command,function(src,args)
    if not Framework.HasAdmin(src) then return TriggerClientEvent('st_dmv:client:notify',src,'You are not authorized to use the DMV administrator panel.','error') end
    TriggerClientEvent('st_dmv:client:openAdmin',src)
end,false)

RegisterNetEvent('st_dmv:server:getLocations',function()
    local src=source; TriggerClientEvent('st_dmv:client:setLocations',src,q('SELECT id,label,x,y,z,menu_x,menu_y,menu_z FROM dmv_locations WHERE active=1 ORDER BY id'))
end)
