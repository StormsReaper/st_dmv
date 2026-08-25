fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'st_dmvsystem'
author 'StormsReaper'
description 'Centralized DMV system for FiveM - QBCore/QBox/ESX'
version '1.0.0'

ui_page 'web/index.html'

shared_scripts {
    'config.lua',
    'shared/utils.lua'
}

client_scripts {
    'client/framework.lua',
    'client/main.lua',
    'client/target.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/inventory.lua',
    'server/main.lua',
    'server/custom_plates.lua',
    'server/mdt_api.lua'
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

dependencies {
    'oxmysql'
}
