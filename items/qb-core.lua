-- Add these entries to qb-core/shared/items.lua.
return {
    ['dmv_driver_license'] = {
        name = 'dmv_driver_license', label = 'Driver License', weight = 10, type = 'item', image = 'dmv_driver_license.png', unique = true, useable = true, shouldClose = true, description = 'An official government-issued driver license card.'
    },
    ['dmv_cdl_license'] = {
        name = 'dmv_cdl_license', label = 'CDL Commercial License', weight = 10, type = 'item', image = 'dmv_cdl_license.png', unique = true, useable = true, shouldClose = true, description = 'Commercial driver permit issued by the DMV.'
    },
    ['dmv_taxi_license'] = {
        name = 'dmv_taxi_license', label = 'Taxi Driver License', weight = 10, type = 'item', image = 'dmv_taxi_license.png', unique = true, useable = true, shouldClose = true, description = 'Permit authorizing municipal taxi driver services.'
    },
    ['dmv_registration_doc'] = {
        name = 'dmv_registration_doc', label = 'Vehicle Registration Document', weight = 50, type = 'item', image = 'dmv_registration_doc.png', unique = true, useable = true, shouldClose = true, description = 'Official proof of vehicle ownership and active registration status.'
    },
    ['dmv_license_plate'] = {
        name = 'dmv_license_plate', label = 'DMV License Plate', weight = 2500, type = 'item', image = 'dmv_license_plate.png', unique = true, useable = false, shouldClose = true, description = 'A physical state-issued license plate. Install it through the DMV vehicle target.'
    }
}
