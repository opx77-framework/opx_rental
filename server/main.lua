-- Entry: client requests (validated + rate-limited), exports for other resources, lifecycle.

local RESOURCE = GetCurrentResourceName()
local TICK_MS = 15000

-- Client requests --------------------------------------------------------------------------------

-- Every client request: a valid source, under the rate limit. Nothing waits, so the handler runs inline.
local function onRequest(name, handler)
	RegisterNetEvent(name, function(...)
		local src = Rental.toSource(source)
		if not src or not Rental.allow(src) then return end
		handler(src, ...)
	end)
end

onRequest('opx_rental:open', function(src) Rental.open(src) end)
onRequest('opx_rental:rent', function(src, index) Rental.rent(src, Rental.int(index)) end)
onRequest('opx_rental:return', function(src) Rental.giveBack(src) end)

-- Exports ----------------------------------------------------------------------------------------

-- SYNC: the running rental of a player: { vehicleId, plate, record, secondsLeft, deposit } | nil.
exports('GetRental', function(source)
	local src = Rental.toSource(source)
	local r = src and Rental.ofSource(src)
	if not r then return nil end
	return { vehicleId = r.vehicleId, plate = r.plate, record = r.record, secondsLeft = Rental.secondsLeft(r), deposit = r.deposit }
end)

-- SYNC: ends a player's rental now, wherever the car is and whoever sits in it (the caller decides).
-- refund = true gives the deposit back. true | false, reason ('invalid_source', 'no_rental').
exports('EndRental', function(source, refund)
	local src = Rental.toSource(source)
	if not src then return false, 'invalid_source' end
	local r = Rental.ofSource(src)
	if not r then return false, 'no_rental' end
	local vehicleId = r.vehicleId
	local refunded = Rental.finish(r, refund == true)
	Rental.notify(src, 'ended', 'info', { label = r.label, deposit = refunded and r.deposit or 0 })
	TriggerEvent('opx:rental:returned', src, vehicleId, refunded)
	return true
end)

-- Lifecycle --------------------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(name)
	if name ~= RESOURCE then return end
	Rental.loadConfig()
	Rental.sweepLeftovers()
end)

CreateThread(function()
	while true do
		Wait(TICK_MS)
		local ok, err = pcall(Rental.tick)
		if not ok then print(('[opx_rental] timer loop error: %s'):format(tostring(err))) end
	end
end)

-- The same character came back (inside the grace): the rental is his again.
AddEventHandler('opx:playerLoaded', function(playerId, data)
	local src = Rental.toSource(playerId)
	local citizenId = type(data) == 'table' and data.citizenId or nil
	if src and type(citizenId) == 'string' then Rental.attach(src, citizenId) end
end)

AddEventHandler('opx:playerUnloaded', function(playerId)
	local src = Rental.toSource(playerId)
	if not src then return end
	Rental.forget(src)
	Rental.detach(src)
end)

AddEventHandler('onPlayerDisconnected', function(playerId)
	local src = Rental.toSource(playerId)
	if not src then return end
	Rental.forget(src)
	Rental.detach(src)
end)

AddEventHandler('onVehicleRemoved', function(vehicleId)
	local id = Rental.toVehicleId(vehicleId)
	if id then Rental.vehicleGone(id) end
end)

-- Our stop: running rentals are lost with this VM (the next start removes their cars). Tell the renters;
-- only TriggerClientEvent works here.
AddEventHandler('onResourceStop', function(name)
	if name ~= RESOURCE then return end
	Rental.notifyStop()
end)
