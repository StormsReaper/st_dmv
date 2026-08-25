local function usingOx()
    return Config.Inventory == 'ox_inventory' or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') == 'started')
end

local function usingQb()
    return Config.Inventory == 'qb-inventory' or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') ~= 'started')
end

local function findMetadata(source, item, predicate)
    if usingOx() then
        local slots = exports.ox_inventory:Search(source, 'slots', item) or {}
        for _, entry in pairs(slots) do
            if entry and entry.metadata and (not predicate or predicate(entry.metadata)) then return entry end
        end
    elseif usingQb() then
        local player = Framework.GetPlayer(source)
        local items = player and player.PlayerData.items or {}
        for slot, entry in pairs(items) do
            if entry and entry.name == item then
                local info = entry.info or entry.metadata or {}
                if not predicate or predicate(info) then return { slot = slot, metadata = info, info = info, item = entry } end
            end
        end
    end
end

function Inventory.GetDocument(source, item)
    return findMetadata(source, item)
end

function Inventory.TakeDocument(source, item, metadata)
    if usingOx() then
        return exports.ox_inventory:RemoveItem(source, item, 1, metadata)
    end
    local player = Framework.GetPlayer(source)
    if not player then return false end
    return player.Functions.RemoveItem(item, 1, false, metadata, 'st_dmvsystem')
end

function Inventory.RegisterUsables()
    if usingOx() then return end
    if Framework.name == 'qbcore' or Framework.name == 'qbox' then
        local core = Framework.QBCore
        if core and core.Functions and core.Functions.CreateUseableItem then
            for _, item in ipairs({ 'dmv_driver_license', 'dmv_cdl_license', 'dmv_taxi_license', 'dmv_registration_doc' }) do
                core.Functions.CreateUseableItem(item, function(source, itemData)
                    TriggerClientEvent('st_dmv:client:showDocument', source, itemData)
                end)
            end
        end
    end
end

CreateThread(function()
    Wait(1000)
    Inventory = Inventory or {}
    Inventory.RegisterUsables()
end)
