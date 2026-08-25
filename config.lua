Config = {}

Config.Framework = 'auto' -- auto, qbcore, qbox, esx
Config.Inventory = 'auto' -- auto, ox_inventory, qb-inventory
Config.Target = 'auto' -- auto, ox_target, qb-target, none
Config.AdminAce = 'dmv.admin'
Config.AdminGroups = { 'admin', 'god', 'superadmin' }
Config.Command = 'createdmv'

Config.RegistrationFee = 350
Config.PlatePrefix = 'OR'
Config.PlateLength = 6
Config.TemporaryPlatePrefix = 'DMV'
Config.Points = { warning = 1, minor = 2, major = 4, felony = 6 }
Config.PointsSuspension = 12
Config.ExamPassPercent = 80
Config.ExamMaxAttempts = 3
Config.ExamCooldownSeconds = 15

Config.Locations = {
    { label = 'Department of Motor Vehicles', coords = vector3(-546.76, -204.12, 38.22), radius = 1.8 }
}

Config.TargetDistance = 2.5
Config.Marker = { type = 2, scale = vector3(0.25, 0.25, 0.25) }

Config.VehicleTables = {
    qbox = 'player_vehicles',
    qbcore = 'player_vehicles',
    esx = 'owned_vehicles'
}

Config.Debug = false
