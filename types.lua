---@meta

-- opx_rental server exports and events. Not loaded by the manifest (LuaLS annotations only).
-- A replacement rental keeps these names and shapes. Running rentals live in memory only (no table).
-- Both exports are SYNCHRONOUS: they answer from memory and never wait. Call them as exports.opx_rental:Name(...)
-- or Open77.exports.callSync('opx_rental', 'Name', ...).

---@class OpxRentalInfo
---@field vehicleId integer live platform vehicle id
---@field plate string 'RENT 1', 'RENT 2'... (Config.plate + a number)
---@field record string Vehicle.* record
---@field secondsLeft integer seconds before the end (0 when over and waiting for the car to be empty)
---@field deposit integer deposit given back on return

---@alias OpxRentalError
---| 'invalid_source' source is not a player id
---| 'no_rental' this player has no rental running (or his character left and the grace timer runs)

---@class OpxRentalExports
local opx_rental = {}

--- SYNC. The running rental of a player, or nil.
---@param source integer
---@return OpxRentalInfo|nil
function opx_rental.GetRental(source) end

--- SYNC. Ends a player's rental now: the car is removed wherever it is, even occupied (the caller decides).
--- refund = true gives the deposit back to the account that paid. Notifies the player, raises opx:rental:returned.
---@param source integer
---@param refund? boolean
---@return boolean ok
---@return OpxRentalError|nil reason
function opx_rental.EndRental(source, refund) end

-- Server host events (AddEventHandler):
-- TriggerEvent('opx:rental:rented', source, vehicleId, record, price)        a car was rented (price without deposit)
-- TriggerEvent('opx:rental:returned', source, vehicleId, refunded)           returned at a desk, or EndRental
-- TriggerEvent('opx:rental:expired', citizenId, vehicleId)                    time over, renter gone too long, or
--                                                                            the car disappeared; deposit lost
---@alias OpxRentalRentedEvent fun(source: integer, vehicleId: integer, record: string, price: integer)
---@alias OpxRentalReturnedEvent fun(source: integer, vehicleId: integer, refunded: boolean)
---@alias OpxRentalExpiredEvent fun(citizenId: string, vehicleId: integer)

-- Payment and spawn are one synchronous step: no free bay = 'spawn_blocked', nothing paid; a failed spawn
-- refunds at once. Money reasons: rental:<record> (price + deposit), rental:<record> (refund), rental:deposit <record>.
-- Access: the renter gets opx_core SetVehicleOwnerAccess and, when a vehiclekeys provider runs,
-- GiveKey(source, vehicleId, { temporary = true }); both taken back on disconnect / character switch and given
-- again when the same character returns within Config.disconnectGraceSeconds.
-- A restart forgets running rentals (renters told, deposits NOT refunded); the new run removes every car with
-- plate '<Config.plate> 1..99' (never an owned car).
-- Internal net events (not a contract): client -> server opx_rental:open, :rent (index), :return;
-- server -> client opx_rental:open (state), :notify (key, kind, params).
