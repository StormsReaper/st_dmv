-- Call this from your dealership server-side after the sale is finalized but before handing the vehicle over.
local ok, temporaryPlate = exports['st_dmvsystem']:RegisterNewVehicleSale({
    vin = vin,
    model = vehicleModel,
    make = vehicleMake,
    vehicleName = vehicleDisplayName,
    buyer = buyerCitizenId,
    price = salePrice
})

if not ok then
    -- Do not finalize vehicle delivery if the DMV ledger could not be created.
    return false, 'DMV registration failed'
end

-- temporaryPlate is the DMV ledger's pre-registration identifier.
-- Give this plate to the vehicle before delivery.
return true, temporaryPlate

-- Server-side compatibility hook for custom garages/dealerships:
AddEventHandler('dmv:plateInstalled', function(vin, newPlate, citizenid, persistedByDmv)
    -- Update your custom vehicle record here if your garage does not use
    -- player_vehicles / owned_vehicles.
end)
