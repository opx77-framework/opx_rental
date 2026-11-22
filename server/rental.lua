-- Rental logic: who the player is, where he stands, renting, returning, the timer loop. Decides everything.
-- Money and cars are opx_core's; every call below is synchronous (no Wait, no await), so a rental is one step.
-- Running rentals live in memory only: a restart of opx_rental removes the cars (deposits lost, README).

Rental = {}

local CORE = 'opx_core'
local busy = {}     -- [source] = true while one of his money moves runs (guards re-entry)
local lastCall = {} -- [source] = GetGameTimer() of his last accepted request

-- [citizenId] = { citizenId, source|nil, vehicleId, plate, slot, record, label, price, deposit, account,
--                 endsAt (ms), warned, awayUntil (ms)|nil }
local rentals = {}
local byVehicle = {} -- [vehicleId] = citizenId

Rental.points = {}    -- validated Config.points
Rental.catalogue = {} -- validated Config.vehicles rows: { index, record, label, price, minutes }

local MAX_SLOTS = 99

-- Helpers ----------------------------------------------------------------------------------------

function Rental.int(v) return type(v) == 'number' and math.tointeger(v) or nil end

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

-- A player id from anything (positive integer within uint32), or nil. Natives abort on anything else.
function Rental.toSource(value)
	local id = tonumber(value)
	if not id or id ~= id or id < 1 or id > 0xFFFFFFFF or id % 1 ~= 0 then return nil end
	return math.tointeger(id)
end

-- Open77 vehicle ids are 64-bit positive integers (generation in the high bits, e.g. 4294967297); 0 or negative aborts the server.
-- Accepted: an integer (or integral float, JSON) 1..2^53-1, exact in JSON and in Lua numbers, or a string of digits
-- (host events: tostring(seat.vehicleId)). nil for anything else (0, negative, 1.5, NaN, inf, larger).
local MAX_VEHICLE_ID = 9007199254740991
local function vehicleId(value)
	if type(value) == 'string' then
		if not value:match('^%d+$') then return nil end
		value = tonumber(value) -- a float when the digits do not fit an integer: refused below
		if math.type(value) ~= 'integer' then return nil end
	end
	if math.type(value) == 'float' then value = math.tointeger(value) end
	if math.type(value) ~= 'integer' or value < 1 or value > MAX_VEHICLE_ID then return nil end
	return value
end
Rental.toVehicleId = vehicleId

-- An opx_core export under pcall: its results, or nil, 'core_unavailable'.
function Rental.core(name, ...)
	local ok, a, b = pcall(Open77.exports.callSync, CORE, name, ...)
	if not ok then return nil, 'core_unavailable' end
	return a, b
end
local core = Rental.core

-- The loaded character of a player (opx_core PlayerData), or nil.
function Rental.player(source)
	local data = core('GetPlayer', source)
	if type(data) ~= 'table' or type(data.citizenId) ~= 'string' then return nil end
	return data
end

-- Rate limit: false when the player asked again too soon.
function Rental.allow(source)
	local now = GetGameTimer()
	local last = lastCall[source]
	if last and now - last < Config.rateLimitMs then return false end
	lastCall[source] = now
	return true
end

function Rental.forget(source)
	busy[source], lastCall[source] = nil, nil
end

-- A locale key + params for the player's client, which translates it and shows it through opx_core Notify.
function Rental.notify(source, key, kind, params)
	if not Rental.toSource(source) then return end
	pcall(TriggerClientEvent, 'opx_rental:notify', source, key, kind or 'info', params or {})
end

-- Config ------------------------------------------------------------------------------------------

local function position(t)
	if type(t) ~= 'table' or not finite(t.x) or not finite(t.y) or not finite(t.z) then return nil end
	return { x = t.x + 0.0, y = t.y + 0.0, z = t.z + 0.0 }
end

-- Builds Rental.points and Rental.catalogue from the config. Malformed rows are dropped and logged.
function Rental.loadConfig()
	local points = {}
	for i, row in ipairs(type(Config.points) == 'table' and Config.points or {}) do
		local at = position(row)
		local bucket = type(row) == 'table' and Rental.int(row.bucket or 0)
		local spawns = {}
		for _, bay in ipairs(type(row) == 'table' and type(row.spawns) == 'table' and row.spawns or {}) do
			local p = position(bay)
			local heading = type(bay) == 'table' and tonumber(bay.heading) or 0.0
			if p and finite(heading) then
				p.heading = heading + 0.0
				spawns[#spawns + 1] = p
			end
		end
		if at and bucket and bucket >= 0 and bucket <= 0xFFFFFFFF and #spawns > 0 then
			local radius = tonumber(row.radius) or 2.5
			if not finite(radius) or radius <= 0 then radius = 2.5 end
			at.index, at.bucket, at.radius, at.spawns = #points + 1, bucket, radius, spawns
			at.name = type(row.name) == 'string' and row.name:sub(1, 32) or ('point' .. i)
			at.label = type(row.label) == 'string' and row.label:sub(1, 64) or at.name
			points[#points + 1] = at
		else
			print(('[opx_rental] Config.points[%d] dropped: malformed position, bucket or spawns'):format(i))
		end
	end
	Rental.points = points

	local list = {}
	for i, row in ipairs(type(Config.vehicles) == 'table' and Config.vehicles or {}) do
		local record = type(row) == 'table' and row.record
		local price = type(row) == 'table' and Rental.int(row.price)
		local minutes = type(row) == 'table' and Rental.int(row.minutes)
		local valid = type(record) == 'string' and #record <= 255 and record:match('^Vehicle%.[%w_]+$') ~= nil
			and price and price >= 0 and price <= 1000000000 and minutes and minutes >= 1 and minutes <= 1440
		if valid then
			local known, reason = Open77.data.vehicle(record)
			if not known and reason == 'record_unknown' then valid = false end
		end
		if valid then
			list[#list + 1] = {
				index = #list + 1, record = record, price = price, minutes = minutes,
				label = type(row.label) == 'string' and row.label:sub(1, 64) or record,
			}
		else
			print(('[opx_rental] Config.vehicles[%d] dropped: unknown or malformed (%s)'):format(i, tostring(record)))
		end
	end
	Rental.catalogue = list
end

function Rental.deposit()
	local n = Rental.int(Config.deposit) or 0
	return math.max(0, math.min(n, 1000000000))
end

-- Where -------------------------------------------------------------------------------------------

-- The desk the player stands at (server position + routing bucket), or nil.
function Rental.pointOf(source)
	local pos = Open77.players.position(source)
	if type(pos) ~= 'table' or not finite(pos.x) or not finite(pos.y) or not finite(pos.z) then return nil end
	for _, point in ipairs(Rental.points) do
		local dx, dy = pos.x - point.x, pos.y - point.y
		local reach = point.radius + (tonumber(Config.serverSlack) or 2.5)
		if point.bucket == pos.bucket and dx * dx + dy * dy <= reach * reach
			and math.abs(pos.z - point.z) <= (tonumber(Config.heightTolerance) or 4.0) then
			return point
		end
	end
	return nil
end

-- The first bay of a desk with no vehicle on it, or nil.
local function freeBay(point)
	local radius = tonumber(Config.spawnClearRadius) or 3.0
	for _, bay in ipairs(point.spawns) do
		local list = Open77.vehicles.nearby({ x = bay.x, y = bay.y, z = bay.z }, radius, { bucket = point.bucket, limit = 1 })
		if type(list) == 'table' and #list == 0 then return bay end
	end
	return nil
end

-- Whether somebody sits in the car: true / false, nil when the car is gone.
local function occupied(vehicleId)
	local car = Open77.vehicles.get(vehicleId)
	if type(car) ~= 'table' then return nil end
	local occ = car.occupants
	if type(occ) == 'table' then return next(occ) ~= nil end
	if type(occ) == 'number' then return occ > 0 end
	return false
end

-- Whether the car stands within Config.returnRadius of the desk (same bucket).
local function nearPoint(id, point)
	local radius = tonumber(Config.returnRadius) or 15.0
	local list = Open77.vehicles.nearby({ x = point.x, y = point.y, z = point.z }, radius, { bucket = point.bucket, limit = 32 })
	for _, entry in ipairs(type(list) == 'table' and list or {}) do
		if Rental.toVehicleId(entry.id) == id then return true end
	end
	return false
end

-- Keys --------------------------------------------------------------------------------------------

-- The vehiclekeys provider's name when one runs, else nil.
local function keysProvider()
	local name = core('GetProvider', 'vehiclekeys')
	if type(name) == 'string' and GetResourceState(name) == 'running' then return name end
	return nil
end

-- The renter may open and drive his car: opx_core's per-player lock exception always (so a reload of the keys
-- provider never locks him out), plus a temporary key from the vehiclekeys provider when one runs (lock / unlock).
local function grantKey(source, vehicleId)
	core('SetVehicleOwnerAccess', vehicleId, source, true)
	local provider = keysProvider()
	if provider then pcall(Open77.exports.callSync, provider, 'GiveKey', source, vehicleId, { temporary = true }) end
end

-- The renter's session no longer opens the car (character switch, disconnect).
local function revokeKey(source, vehicleId)
	local provider = keysProvider()
	if provider then pcall(Open77.exports.callSync, provider, 'RemoveKey', source, vehicleId) end
	core('SetVehicleOwnerAccess', vehicleId, source, false)
end

-- Plates ------------------------------------------------------------------------------------------

local function prefix()
	local p = type(Config.plate) == 'string' and Config.plate:upper() or 'RENT'
	if not p:match('^[A-Z0-9%-]+$') then p = 'RENT' end
	return p:sub(1, 7)
end

-- 'RENT 3' (at most 10 characters: 7 + space + 2 digits).
function Rental.plate(slot)
	return prefix() .. ' ' .. slot
end

local function usedSlots()
	local used = {}
	for _, r in pairs(rentals) do used[r.slot] = true end
	return used
end

-- Running rentals ----------------------------------------------------------------------------------

function Rental.ofCitizen(citizenId) return rentals[citizenId] end

function Rental.ofSource(source)
	for _, r in pairs(rentals) do
		if r.source == source then return r end
	end
	return nil
end

function Rental.secondsLeft(r)
	return math.max(0, math.floor((r.endsAt - GetGameTimer()) / 1000))
end

-- Forgets a rental and removes its car (when still there). refund: the deposit goes back to the paying
-- account when the renter is loaded. Returns whether the deposit was refunded.
function Rental.finish(r, refund)
	if rentals[r.citizenId] ~= r then return false end
	rentals[r.citizenId] = nil
	byVehicle[r.vehicleId] = nil
	-- Forgotten first: the onVehicleRemoved our own removal raises finds nothing.
	core('DeleteVehicle', r.vehicleId)
	local refunded = false
	if refund and r.deposit > 0 and r.source then
		local ok = core('AddMoney', r.source, r.account, r.deposit, 'rental:deposit ' .. r.record)
		refunded = ok == true
		if not refunded then
			print(('[opx_rental] DEPOSIT NOT REFUNDED: %d to %s of %s'):format(r.deposit, r.account, r.citizenId))
		end
	end
	return refunded
end

-- The car went away by another path (staff, the world, opx_core): the rental ends, deposit lost.
function Rental.vehicleGone(vehicleId)
	local citizenId = byVehicle[vehicleId]
	local r = citizenId and rentals[citizenId]
	if not r then return end
	rentals[citizenId] = nil
	byVehicle[vehicleId] = nil
	if r.source then Rental.notify(r.source, 'vehicle_lost', 'error', { label = r.label }) end
	TriggerEvent('opx:rental:expired', r.citizenId, r.vehicleId)
end

-- Rent --------------------------------------------------------------------------------------------

-- The first Config.payFrom account that holds `amount`, or nil.
local function payingAccount(source, amount)
	for _, account in ipairs(type(Config.payFrom) == 'table' and Config.payFrom or { 'money', 'bank' }) do
		if type(account) == 'string' and core('HasMoney', source, account, amount) == true then return account end
	end
	return nil
end

-- The player rents catalogue row `index` at the desk he stands at.
function Rental.rent(source, index)
	local data = Rental.player(source)
	if not data then return end
	if busy[source] then return Rental.notify(source, 'busy', 'error') end
	if Open77.players.isDead(source) == true then return Rental.notify(source, 'dead', 'error') end
	local point = Rental.pointOf(source)
	if not point then return Rental.notify(source, 'not_at_desk', 'error') end
	if rentals[data.citizenId] then return Rental.notify(source, 'already_renting', 'error') end
	local row = Rental.int(index) and Rental.catalogue[Rental.int(index)]
	if not row then return Rental.notify(source, 'unknown_model', 'error') end
	local bay = freeBay(point)
	if not bay then return Rental.notify(source, 'spawn_blocked', 'error') end
	local deposit = Rental.deposit()
	local total = row.price + deposit
	local account = nil
	if total > 0 then
		account = payingAccount(source, total)
		if not account then return Rental.notify(source, 'insufficient_funds', 'error', { amount = total }) end
	else
		account = 'money'
	end

	busy[source] = true
	if total > 0 then
		local removed, why = core('RemoveMoney', source, account, total, 'rental:' .. row.record)
		if removed ~= true then
			busy[source] = nil
			return Rental.notify(source, 'failed', 'error', { reason = tostring(why or 'payment_failed') })
		end
	end
	-- A free plate: our slots first, then opx_core refuses a plate somebody else wears (next slot).
	local used, id, reason, slot = usedSlots(), nil, nil, nil
	local tries = 0
	for n = 1, MAX_SLOTS do
		if not used[n] then
			slot = n
			id, reason = core('SpawnVehicle', row.record, { x = bay.x, y = bay.y, z = bay.z }, bay.heading, {
				plate = Rental.plate(n), bucket = point.bucket, locked = true,
			})
			id = Rental.toVehicleId(id)
			tries = tries + 1
			if id or (reason ~= 'plate_owned' and reason ~= 'plate_in_use') or tries >= 5 then break end
		end
	end
	if not id then
		if total > 0 and core('AddMoney', source, account, total, 'rental:' .. row.record .. ' (refund)') ~= true then
			print(('[opx_rental] REFUND FAILED: %d to %s of player %d'):format(total, account, source))
		end
		busy[source] = nil
		return Rental.notify(source, 'spawn_failed', 'error', { reason = tostring(reason or 'no_plate') })
	end
	busy[source] = nil

	local r = {
		citizenId = data.citizenId, source = source, vehicleId = id, plate = Rental.plate(slot), slot = slot,
		record = row.record, label = row.label, price = row.price, deposit = deposit, account = account,
		endsAt = GetGameTimer() + row.minutes * 60000, warned = false, awayUntil = nil,
	}
	rentals[r.citizenId] = r
	byVehicle[id] = r.citizenId
	grantKey(source, id)
	Rental.notify(source, 'rented', 'success', {
		label = row.label, plate = r.plate, minutes = row.minutes, price = row.price, deposit = deposit,
	})
	print(('[opx_rental] %s rented %s (%s) for %d + deposit %d from %s'):format(
		r.citizenId, row.record, r.plate, row.price, deposit, account))
	TriggerEvent('opx:rental:rented', source, id, row.record, row.price)
end

-- Return ------------------------------------------------------------------------------------------

-- The renter brings his car back to the desk he stands at.
function Rental.giveBack(source)
	local data = Rental.player(source)
	if not data then return end
	local r = rentals[data.citizenId]
	if not r then return Rental.notify(source, 'no_rental', 'error') end
	local point = Rental.pointOf(source)
	if not point then return Rental.notify(source, 'not_at_desk', 'error') end
	local busyCar = occupied(r.vehicleId)
	if busyCar == nil then return Rental.vehicleGone(r.vehicleId) end
	if not nearPoint(r.vehicleId, point) then return Rental.notify(source, 'too_far', 'error') end
	if busyCar then return Rental.notify(source, 'occupied', 'error') end
	local vehicleId = r.vehicleId
	local refunded = Rental.finish(r, true)
	Rental.notify(source, 'returned', 'success', { label = r.label, deposit = refunded and r.deposit or 0 })
	TriggerEvent('opx:rental:returned', source, vehicleId, refunded)
end

-- Menu state --------------------------------------------------------------------------------------

function Rental.open(source)
	local data = Rental.player(source)
	if not data then return end
	if not Rental.pointOf(source) then return Rental.notify(source, 'not_at_desk', 'error') end
	local list = {}
	for i, row in ipairs(Rental.catalogue) do
		list[i] = { index = row.index, label = row.label, price = row.price, minutes = row.minutes }
	end
	local r = rentals[data.citizenId]
	local current = r and { label = r.label, plate = r.plate, seconds = Rental.secondsLeft(r), deposit = r.deposit } or nil
	pcall(TriggerClientEvent, 'opx_rental:open', source, {
		catalogue = list, deposit = Rental.deposit(), current = current,
	})
end

-- Renter comes and goes ---------------------------------------------------------------------------

-- The renter left (character switch or disconnect): his session loses the car, the grace timer starts.
function Rental.detach(source)
	local r = Rental.ofSource(source)
	if not r then return end
	r.source = nil
	r.awayUntil = GetGameTimer() + math.max(0, tonumber(Config.disconnectGraceSeconds) or 120) * 1000
	revokeKey(source, r.vehicleId)
end

-- The same character is back inside the grace: the rental is his again.
function Rental.attach(source, citizenId)
	local r = rentals[citizenId]
	if not r then return end
	if r.source and r.source ~= source then revokeKey(r.source, r.vehicleId) end
	r.source, r.awayUntil = source, nil
	grantKey(source, r.vehicleId)
	Rental.notify(source, 'rental_back', 'info', { label = r.label, plate = r.plate, minutes = math.ceil(Rental.secondsLeft(r) / 60) })
end

-- Timer loop --------------------------------------------------------------------------------------

local function expire(r, key)
	local source = r.source
	Rental.finish(r, false)
	if source then Rental.notify(source, key, 'warning', { label = r.label }) end
	TriggerEvent('opx:rental:expired', r.citizenId, r.vehicleId)
end

-- One pass over the running rentals (every 15 s): warning, end, abandoned cars.
function Rental.tick()
	local now = GetGameTimer()
	local list = {}
	for _, r in pairs(rentals) do list[#list + 1] = r end
	for _, r in ipairs(list) do
		local seated = occupied(r.vehicleId)
		if seated == nil then
			Rental.vehicleGone(r.vehicleId)
		elseif r.awayUntil and now >= r.awayUntil and not seated then
			expire(r, 'expired')
		elseif now >= r.endsAt then
			if seated then
				if r.source then Rental.notify(r.source, 'expired_occupied', 'warning', { label = r.label }) end
			else
				expire(r, 'expired')
			end
		elseif not r.warned and r.endsAt - now <= (tonumber(Config.warnSeconds) or 300) * 1000 then
			r.warned = true
			if r.source then
				Rental.notify(r.source, 'warning', 'warning', { label = r.label, minutes = math.ceil((r.endsAt - now) / 60000) })
			end
		end
	end
end

-- Cleanup -----------------------------------------------------------------------------------------

-- At our stop: the renters learn their rental ended with this run (deposits are not refunded: exports
-- cannot be called from a stopping VM).
function Rental.notifyStop()
	for _, r in pairs(rentals) do
		if r.source then Rental.notify(r.source, 'stopped', 'error', { label = r.label }) end
	end
end

-- At our start: removes the rental cars a previous VM of this resource left (found by plate).
function Rental.sweepLeftovers()
	local removed = 0
	for n = 1, MAX_SLOTS do
		local plate = Rental.plate(n)
		local id = Rental.toVehicleId(core('GetVehicleByPlate', plate))
		-- Never an owned car (a player's car that happens to wear this plate).
		if id and core('GetOwnedVehicle', plate) == nil then
			core('DeleteVehicle', id)
			removed = removed + 1
		end
	end
	if removed > 0 then print(('[opx_rental] removed %d rental car(s) left by a previous run'):format(removed)) end
end
