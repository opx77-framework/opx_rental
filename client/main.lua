-- opx_rental client: the help line and the key at the desks, the map pins, the server's answers. It only
-- asks; the server decides (and checks the desk again for every action).

local OPX = assert(require('@opx_core'))
local Ui = assert(require('client.modules.ui'))

local MAPPING = 'opx_rental.open'
local inside = false -- the player stands at a desk (help line shown)
local blips = {}

-- Calls the HUD provider (opx_core Config.providers.hud) under pcall: it may be absent or lack ShowHelp.
local function hud(name, ...)
	local provider = OPX.GetProvider('hud')
	if not provider then return end
	pcall(Open77.exports.callSync, provider, name, ...)
end

local function nearDesk()
	local x, y, z = Open77.character.position()
	if type(x) ~= 'number' then return false end
	for _, point in ipairs(Config.points or {}) do
		if type(point) == 'table' and type(point.x) == 'number' and type(point.y) == 'number' and type(point.z) == 'number' then
			local dx, dy, r = x - point.x, y - point.y, tonumber(point.radius) or 2.5
			if dx * dx + dy * dy <= r * r and math.abs(z - point.z) <= (tonumber(Config.heightTolerance) or 4.0) then
				return true
			end
		end
	end
	return false
end

-- Map pins ----------------------------------------------------------------------------------------

local function removeBlips()
	for _, id in ipairs(blips) do pcall(Open77.blips.remove, id) end
	blips = {}
end

local function createBlips()
	if Config.blips ~= true or #blips > 0 then return end
	for _, point in ipairs(Config.points or {}) do
		if type(point) == 'table' and type(point.x) == 'number' and type(point.y) == 'number' and type(point.z) == 'number' then
			local ok, id, reason = pcall(Open77.blips.create, {
				position = { x = point.x, y = point.y, z = point.z }, sprite = 'vehicle',
				title = type(point.label) == 'string' and point.label or Ui.text('title'),
				description = Ui.text('blip_description'),
			})
			if ok and id then
				blips[#blips + 1] = id
			else
				print(('[opx_rental] map pin refused: %s'):format(tostring(ok and reason or id)))
			end
		end
	end
end

OPX.OnPlayerLoaded(function() createBlips() end)
OPX.OnPlayerUnloaded(function()
	removeBlips()
	Ui.close()
end)

-- Desk ----------------------------------------------------------------------------------------------

CreateThread(function()
	-- Hot reload with a character already loaded: the pins come back.
	if OPX.IsLoaded() then createBlips() end

	local ok, reason = RegisterKeyMapping(MAPPING, Ui.text('key_name'), Config.key or 'E', function()
		if inside and OPX.IsLoaded() and not Ui.isOpen() then TriggerServerEvent('opx_rental:open') end
	end)
	if not ok then print(('[opx_rental] key mapping refused: %s'):format(tostring(reason))) end

	while true do
		local now = OPX.IsLoaded() and nearDesk()
		if now and not inside then
			hud('ShowHelp', Ui.text('help'), Open77.input.keyFor(MAPPING) or Config.key)
		elseif inside and not now then
			hud('HideHelp')
			Ui.close() -- walked away: the server would refuse the actions anyway
		end
		inside = now
		Wait(inside and 250 or 750)
	end
end)

RegisterNetEvent('opx_rental:open', function(state) Ui.open(state) end)
RegisterNetEvent('opx_rental:notify', function(key, kind, params) Ui.notify(key, kind, params) end)
