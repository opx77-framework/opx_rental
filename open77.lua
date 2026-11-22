resource "opx_rental"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- OPX//77 vehicle rental: at a rental desk a player rents a car for a limited time. He pays the price plus a
-- deposit; the deposit comes back when he returns the car at a desk. Money and cars are opx_core's (HasMoney,
-- RemoveMoney, AddMoney, SpawnVehicle, DeleteVehicle); running rentals live in memory only (no table).
-- opx_menu is a dependency because require('@...') only loads a declared, running one.
dependencies {
    "opx_core",
    "opx_menu",
}

permissions {
    "network.events",    -- both: requests to the server, answers to the client
    "world.vehicles",    -- server: Open77.vehicles.nearby (free bay, return spot) and .get (occupants)
    "players.life.read", -- server: Open77.players.isDead (a dead player does not rent)
    "input.actions",     -- client: RegisterKeyMapping / Open77.input.keyFor (the desk key)
    "ui.vanilla.map",    -- client: Open77.blips (the desks on the map, Config.blips)
}

shared_script "config.lua"

-- No `require` on the server: the files share the `Rental` table, loaded in this order.
server_scripts {
    "server/rental.lua",
    "server/main.lua",
}

client_script "client/main.lua"

files {
    "client/modules/*.lua",
    "locales/*.json",
}
