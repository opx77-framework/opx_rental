-- The rental menu (opx_menu) and its confirm. Shows and asks; the server decides.

local OPX = assert(require('@opx_core'))
local Menu = assert(require('@opx_menu'))

local Ui = {}

local T = OPX.Locale()
local main = nil -- the open rental menu, or nil

-- Translated text; money params formatted the player's way.
local MONEY = { amount = true, price = true, deposit = true, total = true }
function Ui.text(key, params)
	local shown = {}
	for k, v in pairs(type(params) == 'table' and params or {}) do
		shown[k] = (MONEY[k] and type(v) == 'number') and OPX.FormatMoney(v) or v
	end
	return T(key, shown)
end

-- A server answer: locale key + kind + params. An unknown key reads as a generic failure.
function Ui.notify(key, kind, params)
	if type(key) ~= 'string' then return end
	local text = Ui.text(key, params)
	if text == key then text = Ui.text('failed', { reason = key }) end
	OPX.Notify(text, kind, nil, Ui.text('title'))
end

local function integer(value)
	local n = tonumber(value)
	return n and n % 1 == 0 and math.tointeger(n) or nil
end

local function timeLeft(seconds)
	seconds = math.max(0, integer(seconds) or 0)
	return Ui.text('time_left', { minutes = math.floor(seconds / 60), seconds = ('%02d'):format(seconds % 60) })
end

-- The player picked a model: confirm the total, then ask the server.
local function askRent(row, deposit)
	local yes = Menu.confirm({
		title = row.label,
		message = Ui.text('rent_confirm', {
			label = row.label, minutes = row.minutes, price = row.price, deposit = deposit,
		}),
		confirmLabel = Ui.text('rent'), cancelLabel = Ui.text('cancel'), default = true,
	})
	if yes then
		Ui.close()
		TriggerServerEvent('opx_rental:rent', row.index)
	end
end

function Ui.open(state)
	if type(state) ~= 'table' then return end
	local deposit = integer(state.deposit) or 0
	local elements = {}
	local current = type(state.current) == 'table' and state.current or nil
	if current then
		elements[#elements + 1] = {
			label = Ui.text('return'), value = 'return', icon = 'key', rightLabel = timeLeft(current.seconds),
			description = Ui.text('return_desc', {
				label = tostring(current.label or '?'), plate = tostring(current.plate or '?'),
				deposit = integer(current.deposit) or 0,
			}),
		}
	else
		for _, row in ipairs(type(state.catalogue) == 'table' and state.catalogue or {}) do
			if type(row) == 'table' and integer(row.index) and integer(row.price) and integer(row.minutes) then
				local item = {
					index = integer(row.index), label = tostring(row.label or '?'),
					price = integer(row.price), minutes = integer(row.minutes),
				}
				elements[#elements + 1] = {
					label = item.label, value = 'rent', icon = 'car', rightLabel = OPX.FormatMoney(item.price),
					description = Ui.text('rent_desc', { minutes = item.minutes, deposit = deposit }),
					row = item,
				}
			end
		end
		if #elements == 0 then
			elements[1] = { label = Ui.text('catalogue_empty'), value = 'empty', disabled = true }
		end
	end
	elements[#elements + 1] = { label = Ui.text('close'), value = 'close', icon = 'close' }

	Ui.close()
	main = Menu.open({
		id = 'opx_rental', title = Ui.text('title'),
		subtitle = current and Ui.text('subtitle_running') or Ui.text('subtitle', { deposit = deposit }),
		elements = elements,
		onSelect = function(element, menu)
			if element.value == 'rent' and element.row then
				askRent(element.row, deposit)
			elseif element.value == 'return' then
				menu:close()
				TriggerServerEvent('opx_rental:return')
			elseif element.value == 'close' then
				menu:close()
			end
		end,
		onClose = function(menu)
			if main == menu then main = nil end
		end,
	})
end

function Ui.isOpen() return main ~= nil and main:isOpen() end

function Ui.close()
	if main then main:close() end
	main = nil
end

return Ui
