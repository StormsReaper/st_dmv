# st_dmv

Centralized DMV, driver-license, vehicle-registration, ownership, exams, driving records, and police/MDT integration for FiveM.

## Supported stacks

- QBox
- QBCore
- ESX
- oxmysql (required)
- ox_inventory or qb-inventory
- ox_target, qb-target, or marker/E fallback

## Install

1. Import `schema.sql` into the same database used by your FiveM server.
2. Copy the resource into your server resources directory.
3. If using ox_inventory, merge `items/ox_inventory.lua` into `ox_inventory/data/items.lua`.
4. If using QBCore/qb-inventory, merge `items/qb-core.lua` into `qb-core/shared/items.lua`.
5. Set `ensure oxmysql` before `ensure st_dmvsystem`.
6. Start `st_dmvsystem` after your framework and inventory resources.
7. Grant the `dmv.admin` ACE or use one of the configured framework admin groups.

Example server.cfg:

```cfg
ensure oxmysql
ensure qbx_core
ensure ox_inventory
ensure st_dmvsystem
add_ace group.admin dmv.admin allow
```

For QBCore replace `qbx_core` with `qb-core`. For ESX use `es_extended`.

## Configuration

Edit `config.lua`:

- `Config.Framework`: `auto`, `qbox`, `qbcore`, `esx`
- `Config.Inventory`: `auto`, `ox_inventory`, `qb-inventory`
- `Config.Target`: `auto`, `ox_target`, `qb-target`, `none`
- `Config.RegistrationFee`: registration price
- `Config.PlatePrefix` and `Config.PlateLength`: state plate format
- `Config.ExamPassPercent`: server-side passing score
- `Config.PointsSuspension`: automatic suspension threshold

## DMV locations

Run as an authorized administrator:

`/createdmv x y z Department of Motor Vehicles`

Locations are stored in `dmv_locations` and are sent to clients automatically after resource startup. `ox_target` creates sphere zones, `qb-target` creates circle zones, and `none` uses a marker plus E-key interaction.

The example location in `config.lua` is only a fallback; database-created locations are loaded automatically.

## Vehicle registration lifecycle

Dealerships should call the server export before handing the vehicle to the buyer:

```lua
local ok, temporaryPlate = exports['st_dmvsystem']:RegisterNewVehicleSale({
    vin = vin,
    model = vehicleModel,
    make = vehicleMake,
    vehicleName = vehicleDisplayName,
    buyer = buyerCitizenId,
    price = salePrice
})
```

The returned temporary plate is not a final registration. The player must:

1. Open the DMV.
2. Select the pending vehicle.
3. Pay from bank or cash.
4. Receive a physical `dmv_license_plate` and registration document.
5. Target the purchased vehicle and choose **Install DMV License Plate**.

The server verifies the buyer, VIN metadata, assigned plate, current vehicle plate, and `READY_FOR_PLATE` ledger state before consuming the physical plate. The entity gets the new plate immediately.

For standard vehicle databases, the resource updates:

- QBox/QBCore: `player_vehicles.plate`
- ESX: `owned_vehicles.plate` and the serialized vehicle properties

Custom garages/dealerships can listen for:

```lua
AddEventHandler('dmv:plateInstalled', function(vin, newPlate, citizenid, persistedByDmv)
    -- persist the plate in your custom vehicle database
end)
```

See `examples/dealership.lua`.

## Driver licenses and exams

The Driver Licenses menu shows the DMV license number, driver status, points, Standard/Class C, CDL, Taxi status, violations, and available exams.

Exam questions live in `dmv_exam_questions`. The client receives question text/options only. The correct answer is kept in `correct_index` and is evaluated server-side, so a client cannot submit its own answer key.

Passing an exam creates/activates the corresponding DMV license and issues a physical document item.

## Inventory

### ox_inventory

Use `items/ox_inventory.lua` as the source definitions for:

- `dmv_driver_license`
- `dmv_cdl_license`
- `dmv_taxi_license`
- `dmv_registration_doc`
- `dmv_license_plate`

The four document items use the `st_dmvsystem.UseDocument` client export. The plate has no usable export and is only installed through the vehicle interaction.

### qb-inventory / QBCore

Use `items/qb-core.lua`. The DMV registers the four document items as QBCore usable items. `dmv_license_plate` is intentionally non-useable.

## Police / MDT API

Server exports are available from `server/mdt_api.lua`:

```lua
local vehicle = exports['st_dmvsystem']:GetVehicleByPlate('OR12345')
local record = exports['st_dmvsystem']:GetDriverRecord(citizenid)
local record = exports['st_dmvsystem']:GetDriverRecordByLicense(licenseNumber)
local vehicles = exports['st_dmvsystem']:GetRegisteredVehicles(citizenid)
local ok, newPoints = exports['st_dmvsystem']:UpdateDrivingPoints(citizenid, 2, 'Speeding', source)
local ok = exports['st_dmvsystem']:SetDriverStatus(citizenid, 'SUSPENDED')
```

These APIs are intended for police/MDT resources and other server-side systems. Keep enforcement decisions server-side.

## Database notes

`dmv_vehicle_ledger` is the DMV source of truth for the sale -> registration -> physical plate installation lifecycle. It contains VIN, buyer, display information, temporary plate, assigned plate, current plate, registration state, and installation timestamp.

If you are upgrading an older DMV ledger, apply the required missing columns from the commented `ALTER TABLE` statements at the bottom of `schema.sql`.

## QBox mechanic compatibility

The resource does not replace mechanic ownership/modification data. It only changes the registration plate in the common vehicle table when that schema is detected. QBox/QBCore vehicle rows remain in `player_vehicles`, so mechanic resources that read the normal plate column continue to see the new plate.

For mechanics/garages with a separate vehicle registry, use `dmv:plateInstalled` to persist the new plate in that registry.

## Security model

- Registration ownership is checked against the server-side DMV ledger.
- Money is removed server-side.
- Plates are generated server-side.
- Exam answers are compared server-side against database `correct_index`.
- Physical plate metadata is validated server-side before consumption.
- Plate installation requires the DMV row to be `READY_FOR_PLATE`.
- Admin-only driving record mutations use framework/ACE authorization.

## Notes

This resource intentionally avoids assuming that every dealership, garage, or mechanic script uses the same database. The DMV ledger is the centralized registry, while the `dmv:plateInstalled` event provides a persistence bridge for custom vehicle systems.
