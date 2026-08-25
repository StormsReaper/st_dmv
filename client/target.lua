local createdTargets = {}

local function keyFor(loc, index)
    return tostring(loc.id or (('%s:%s:%s'):format(loc.coords.x,loc.coords.y,loc.coords.z))) .. ':' .. tostring(index or '')
end

function SetupDMVTargets()
    local mode = Config.Target
    if mode == 'auto' then
        if GetResourceState('ox_target') == 'started' then mode='ox_target'
        elseif GetResourceState('qb-target') == 'started' then mode='qb-target'
        else mode='none' end
        Config.Target=mode
    end
    if mode=='ox_target' then
        for i,loc in ipairs(dmvLocations or {}) do
            local key=keyFor(loc,i)
            if not createdTargets[key] then
                exports.ox_target:addSphereZone({coords=loc.coords,radius=loc.radius or 1.8,debug=Config.Debug,options={
                    {name='st_dmv_open_'..key,icon='fa-solid fa-id-card',label='Open DMV',onSelect=function() OpenDMVMenu() end},
                    {name='st_dmv_install_'..key,icon='fa-solid fa-car',label='Install DMV License Plate',onSelect=function() TriggerEvent('st_dmv:client:installPlate') end}
                }})
                createdTargets[key]=true
            end
        end
    elseif mode=='qb-target' then
        for i,loc in ipairs(dmvLocations or {}) do
            local key=keyFor(loc,i)
            if not createdTargets[key] then
                exports['qb-target']:AddCircleZone('st_dmv_'..key,loc.coords,loc.radius or 1.8,{useZ=true,debugPoly=Config.Debug},{options={
                    {type='client',event='st_dmv:client:open',icon='fas fa-id-card',label='Open DMV'},
                    {type='client',event='st_dmv:client:installPlate',icon='fas fa-car',label='Install DMV License Plate'}
                },distance=Config.TargetDistance})
                createdTargets[key]=true
            end
        end
    end
end

RegisterNetEvent('st_dmv:client:open',function() OpenDMVMenu() end)
