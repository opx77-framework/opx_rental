Config = {}

-- Default key that opens the rental menu at a desk (players can rebind it: Settings > Key bindings).
Config.key = 'E'

-- Rental desks. The client shows the help line inside `radius`; the server checks the same point (position +
-- routing bucket) for every action. `spawns`: bays where a rented car appears (the first free one is used).
-- name: internal id (letters, digits, _). radius in metres (horizontal), bucket = routing bucket.
Config.points = {
	-- PLACEHOLDER coordinates beside the default spawn: measure them in game with /coords (opx_admin).
	{ name = 'arrivals', label = 'Vehicle rental - Arrivals', x = -1596.0, y = -2340.8, z = 43.25, radius = 2.5, bucket = 0,
		spawns = { { x = -1590.0, y = -2340.8, z = 43.25, heading = 140.0 } } },
}

-- What can be rented: record (Vehicle.*), label shown in the menu, price (integer) and minutes of rental.
-- Rows whose record the platform catalogue does not know are dropped at start (logged).
Config.vehicles = {
	{ record = 'Vehicle.v_sportbike2_arch_player', label = 'Arch Nazare', price = 150, minutes = 30 },
	{ record = 'Vehicle.v_standard2_makigai_maimai_player', label = 'Makigai MaiMai', price = 250, minutes = 30 },
}

-- Deposit taken with the price and given back (to the same account) when the car is returned. 0 = none.
Config.deposit = 200

-- Accounts tried in order: the first that holds price + deposit pays both.
Config.payFrom = { 'money', 'bank' }

-- The car must stand this close (metres) to the desk where the player returns it.
Config.returnRadius = 15.0

-- A bay is free when no vehicle stands within this many metres of it.
Config.spawnClearRadius = 3.0

-- Seconds before the end when the renter is warned.
Config.warnSeconds = 300

-- The renter left (disconnect or character switch): his car is removed after this many seconds and the
-- deposit is lost, unless the same character comes back before.
Config.disconnectGraceSeconds = 120

-- Plate prefix (a number is added: 'RENT 1', 'RENT 2'...). Also used at start to remove the cars a previous
-- run left behind. A-Z 0-9 -, at most 7 characters.
Config.plate = 'RENT'

-- true: the desks are shown on the map (sprite 'vehicle') while a character is loaded.
Config.blips = true

-- Vertical tolerance (metres) at a desk: the configured z is approximate.
Config.heightTolerance = 4.0

-- Extra metres the server accepts on top of a desk radius (its position snapshot can lag a tick).
Config.serverSlack = 2.5

-- Minimum milliseconds between two requests of one player (anything faster is ignored).
Config.rateLimitMs = 750

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
