Config = {}

Config.Framework = 'auto'
Config.Inventory = 'auto'
Config.Target = 'auto'
Config.AdminAce = 'dmv.admin'
Config.AdminGroups = { 'admin', 'god', 'superadmin' }
Config.Command = 'createdmv'

Config.RegistrationFee = 350
Config.RegistrationCoverageDays = 365
Config.PlatePrefix = 'OR'
Config.PlateLength = 6
Config.PlateFormat = 'OR-######' -- # = random alphanumeric character
Config.TemporaryPlatePrefix = 'DMV'
Config.CustomPlateEnabled = true
Config.CustomPlatePrice = 750
Config.CustomPlateMinLength = 2
Config.CustomPlateMaxLength = 8
Config.CustomPlatePattern = '^[A-Z0-9]+$'

Config.Points = { warning = 1, minor = 2, major = 4, felony = 6 }
Config.PointsSuspension = 12
Config.ExamPassPercent = 80
Config.ExamMaxAttempts = 3
Config.ExamCooldownSeconds = 15

Config.TargetDistance = 2.5
Config.Marker = { type = 2, scale = vector3(0.25, 0.25, 0.25) }
Config.Blip = { sprite = 498, color = 3, scale = 0.75, shortRange = true }

Config.VehicleTables = {
    qbox = 'player_vehicles',
    qbcore = 'player_vehicles',
    esx = 'owned_vehicles'
}

Config.Debug = false
