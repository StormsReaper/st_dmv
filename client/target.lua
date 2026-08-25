local targetReady = false

function SetupDMVTargets()
    if targetReady then return end
    local mode = Config.Target
    if mode == 'auto' then
        if GetResourceState('ox_target') == 'started' then mode = 'ox_target'
        elseif GetResourceState('qb-target') == 'started' then mode = 'qb-target'
        else mode = 'none' end
    end
    Config.Target = mode
    if mode == 'ox_target' then
        for _, loc in ipairs(dmvLocations or {}) do
            exports.ox_target:addSphereZone({
                coords = loc.coords,
                radius = loc.radius or 1.8,
                debug = Config.Debug,
                options = {
                    { name = 'st_dmv_open', icon = 'fa-solid fa-id-card', label = 'Open DMV', onSelect = function() OpenDMVMenu() end },
                    { name = 'st_dmv_install', icon = 'fa-solid fa-car', label = 'Install DMV License Plate', onSelect = function() TriggerEvent('st_dmv:client:installPlate') end }
                }
            })
        end
    elseif mode == 'qb-target' then
        for _, loc in ipairs(dmvLocations or {}) do
            exports['qb-target']:AddCircleZone(('st_dmv_%s'):format(loc.id or math.random(10000,99999)), loc.coords, loc.radius or 1.8, { useZ = true, debugPoly = Config.Debug }, {
                options = {
                    { type = 'client', event = 'st_dmv:client:open', icon = 'fas fa-id-card', label = 'Open DMV' },
                    { type = 'client', event = 'st_dmv:client:installPlate', icon = 'fas fa-car', label = 'Install DMV License Plate' }
                }, distance = Config.TargetDistance
            })
        end
    end
    targetReady = true
end

RegisterNetEvent('st_dmv:client:open', function() OpenDMVMenu() end)
