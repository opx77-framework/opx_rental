# opx_rental

Car rental at a desk: the player pays the price plus a deposit, drives the car for a limited time and gets the deposit back when he returns it to any desk.

## Install
- Needs: `opx_core`, `opx_menu`. Load after both. A `vehiclekeys` provider is optional (gives the renter a temporary key).
- No database: running rentals live in memory.
- The shipped desk is a placeholder: measure the desk and its parking bay in game (`/coords`) and put them in `Config.points`.
- A restart of opx_rental ends the running rentals without refunding the deposits: avoid it while rentals run.

## In game
- `E` (rebindable) at a desk: pick a car, confirm, it appears on the bay, locked for everybody but you.
- `E` at any desk, car parked close and empty: Return the vehicle, the deposit comes back.
- One rental at a time. At the end the car is taken back once empty and the deposit is lost; after a disconnect it waits `disconnectGraceSeconds`.

## Config
`config.lua`: `points` (desks and bays), `vehicles` (record, price, minutes), `deposit`, `payFrom`. Everything else is commented in the file.

## For developers
- `GetRental(source)` → `{ vehicleId, plate, record, secondsLeft, deposit }` or nil
- `EndRental(source, refund?)` → `true` | `false, reason` (removes the car wherever it is)
- Events: `opx:rental:rented (source, vehicleId, record, price)`, `opx:rental:returned (source, vehicleId, refunded)`, `opx:rental:expired (citizenId, vehicleId)`.
- Full contract: `types.lua`.
