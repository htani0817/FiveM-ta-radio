fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ta-radio'
description 'Radio item on pma-voice: display name and channel input, member list on the right edge'
author 'Tani'
version '1.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/device-layout.css',
    'html/img/radio-device.png',
    'stream/ta_radio.ytyp'
}

-- 手に持つ無線機のモデル（stream/ の ydr）を読み込ませる
data_file 'DLC_ITYP_REQUEST' 'stream/ta_radio.ytyp'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

-- ここに書いた依存はクライアントでも確かめられる。サーバーだけのリソースは書かない
dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
    'pma-voice'
}
