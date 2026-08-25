-- Add these entries to ox_inventory/data/items.lua, or merge them into your existing items table.
return {
    ['dmv_driver_license'] = {
        label = 'Driver License', weight = 10, stack = false, close = true,
        description = 'An official government-issued driver license card.',
        client = { export = 'st_dmvsystem.UseDocument' }
    },
    ['dmv_cdl_license'] = {
        label = 'CDL Commercial License', weight = 10, stack = false, close = true,
        description = 'Commercial driver permit issued by the DMV.',
        client = { export = 'st_dmvsystem.UseDocument' }
    },
    ['dmv_taxi_license'] = {
        label = 'Taxi Driver License', weight = 10, stack = false, close = true,
        description = 'Permit authorizing municipal taxi driver services.',
        client = { export = 'st_dmvsystem.UseDocument' }
    },
    ['dmv_registration_doc'] = {
        label = 'Vehicle Registration Document', weight = 50, stack = false, close = true,
        description = 'Official proof of vehicle ownership and active registration status.',
        client = { export = 'st_dmvsystem.UseDocument' }
    },
    ['dmv_license_plate'] = {
        label = 'DMV License Plate', weight = 2500, stack = false, close = true,
        description = 'A physical state-issued license plate. It must be installed on the assigned vehicle.'
    }
}
