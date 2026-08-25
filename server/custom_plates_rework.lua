local function one(q,p) return MySQL.single.await(q,p or {}) end
local function scalar(q,p) return MySQL.scalar.await(q,p or {}) end
local function upd(q,p) return MySQL.update.await(q,p or {}) end
local function setting(k,f) local v=scalar('SELECT setting_value FROM dmv_settings WHERE setting_key=?',{k}); return v==nil and f or v end
local function plate(v) return tostring(v or ''):upper():gsub('[^A-Z0-9%-]','') end

RegisterNetEvent('st_dmv:server:requestRegisteredCustomPlate',function(vehicleId,requested)
 local src=source; local p=Framework.GetPlayer(src); if not p then return end
 if tostring(setting('custom_plate_enabled','1'))~='1' then return TriggerClientEvent('st_dmv:client:notify',src,'Custom plates are currently disabled.','error') end
 local cid=Framework.GetIdentifier(p); requested=plate(requested)
 if #requested<1 or #requested>8 or not requested:match('^[A-Z0-9%-]+$') then return TriggerClientEvent('st_dmv:client:notify',src,'Custom plates must be 1-8 characters and use only letters, numbers, or hyphens.','error') end
 local v=one("SELECT id,vin,current_plate,assigned_plate,vehicle_name FROM dmv_vehicle_ledger WHERE id=? AND buyer_citizenid=? AND state='REGISTERED'",{tonumber(vehicleId),cid})
 if not v then return TriggerClientEvent('st_dmv:client:notify',src,'Only your fully registered vehicles can request a custom plate.','error') end
 local old=one('SELECT id,status FROM dmv_custom_plate_requests WHERE vehicle_ledger_id=? ORDER BY id DESC LIMIT 1',{v.id})
 if old and (old.status=='PENDING' or old.status=='APPROVED' or old.status=='PURCHASED') then return TriggerClientEvent('st_dmv:client:notify',src,'This vehicle already has an active custom plate request.','error') end
 if scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE (assigned_plate=? OR current_plate=?) AND id<>? LIMIT 1',{requested,requested,v.id}) then return TriggerClientEvent('st_dmv:client:notify',src,'That plate is already assigned.','error') end
 if scalar("SELECT 1 FROM dmv_custom_plate_requests WHERE requested_plate=? AND status IN ('PENDING','APPROVED','PURCHASED') LIMIT 1",{requested}) then return TriggerClientEvent('st_dmv:client:notify',src,'That custom plate already has an active request.','error') end
 MySQL.insert.await('INSERT INTO dmv_custom_plate_requests (citizenid,vehicle_ledger_id,requested_plate) VALUES (?,?,?)',{cid,v.id,requested})
 TriggerClientEvent('st_dmv:client:notify',src,'Custom plate request submitted for DMV approval.','success'); TriggerClientEvent('st_dmv:client:refresh',src)
end)

RegisterNetEvent('st_dmv:server:purchaseRegisteredCustomPlate',function(requestId,account)
 local src=source; local p=Framework.GetPlayer(src); if not p then return end
 local cid=Framework.GetIdentifier(p); account=account=='cash' and 'cash' or 'bank'
 local r=one("SELECT r.*,v.vin,v.vehicle_name,v.current_plate FROM dmv_custom_plate_requests r JOIN dmv_vehicle_ledger v ON v.id=r.vehicle_ledger_id WHERE r.id=? AND r.citizenid=? AND r.status='APPROVED' AND v.state='REGISTERED'",{tonumber(requestId),cid})
 if not r then return TriggerClientEvent('st_dmv:client:notify',src,'That custom plate approval is no longer available.','error') end
 local newPlate=plate(r.requested_plate); local price=tonumber(setting('custom_plate_price',750)) or 750
 if scalar('SELECT 1 FROM dmv_vehicle_ledger WHERE (assigned_plate=? OR current_plate=?) AND id<>? LIMIT 1',{newPlate,newPlate,r.vehicle_ledger_id}) then return TriggerClientEvent('st_dmv:client:notify',src,'That plate is already assigned.','error') end
 if not Framework.RemoveMoney(p,account,price,'dmv-custom-plate') then return TriggerClientEvent('st_dmv:client:notify',src,'Insufficient funds.','error') end
 local meta={vin=r.vin,owner=cid,citizenid=cid,assigned_plate=newPlate,previous_plate=r.current_plate,custom=true,request_id=r.id,vehicle_name=r.vehicle_name}
 if not Framework.AddItem(src,'dmv_license_plate',meta) then Framework.AddMoney(p,account,price,'dmv-custom-plate-refund'); return TriggerClientEvent('st_dmv:client:notify',src,'Inventory could not receive the custom plate; your payment was refunded.','error') end
 if upd("UPDATE dmv_vehicle_ledger SET assigned_plate=?,state='READY_FOR_PLATE' WHERE id=? AND buyer_citizenid=? AND state='REGISTERED'",{newPlate,r.vehicle_ledger_id,cid})~=1 then Inventory.TakeDocument(src,'dmv_license_plate',meta); Framework.AddMoney(p,account,price,'dmv-custom-plate-refund'); return TriggerClientEvent('st_dmv:client:notify',src,'Vehicle changed before purchase completed; payment refunded.','error') end
 upd("UPDATE dmv_custom_plate_requests SET status='PURCHASED' WHERE id=? AND status='APPROVED'",{r.id})
 TriggerClientEvent('st_dmv:client:notify',src,('Congrats! Your custom plate %s has been purchased. Install it on your registered vehicle.'):format(newPlate),'success'); TriggerClientEvent('st_dmv:client:refresh',src)
end)
