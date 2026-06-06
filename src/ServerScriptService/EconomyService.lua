--!strict
--[[
	EconomyService
	The gameplay-facing API. Everything that touches currency or inventory goes
	through here, so validation lives in exactly one place and the rest of the
	codebase can't accidentally create or destroy value.

	Every mutation:
	  - validates inputs against EconomyConfig (no unknown currencies/items, no negatives)
	  - mutates the in-memory profile (DataStoreManager owns persistence)
	  - returns (ok, reason) so callers can react to failure instead of guessing

	Location: ServerScriptService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local DataStoreManager = require(script.Parent:WaitForChild("DataStoreManager"))

local EconomyService = {}

----------------------------------------------------------------------
-- Currency
----------------------------------------------------------------------
function EconomyService.getBalance(userId: number, currency: string): number
	local data = DataStoreManager.get(userId)
	if not data then return 0 end
	return data.currencies[currency] or 0
end

function EconomyService.addCurrency(userId: number, currency: string, amount: number): (boolean, string?)
	if not Config.Currencies[currency] then
		return false, "unknown_currency"
	end
	if type(amount) ~= "number" or amount ~= amount then -- NaN guard
		return false, "invalid_amount"
	end
	if amount <= 0 then
		return false, "amount_must_be_positive"
	end
	local data = DataStoreManager.get(userId)
	if not data then return false, "profile_not_loaded" end

	data.currencies[currency] = (data.currencies[currency] or 0) + math.floor(amount)
	return true
end

-- Spend currency. Refuses if the player can't afford it — the single most
-- important check in any economy. No negative balances, ever.
function EconomyService.spendCurrency(userId: number, currency: string, amount: number): (boolean, string?)
	if not Config.Currencies[currency] then
		return false, "unknown_currency"
	end
	if type(amount) ~= "number" or amount <= 0 then
		return false, "invalid_amount"
	end
	local data = DataStoreManager.get(userId)
	if not data then return false, "profile_not_loaded" end

	amount = math.floor(amount)
	local balance = data.currencies[currency] or 0
	if balance < amount then
		return false, "insufficient_funds"
	end
	data.currencies[currency] = balance - amount
	return true
end

----------------------------------------------------------------------
-- Inventory
----------------------------------------------------------------------
function EconomyService.getInventory(userId: number): { [string]: number }
	local data = DataStoreManager.get(userId)
	if not data then return {} end
	return data.inventory
end

function EconomyService.grantItem(userId: number, itemId: string, count: number?): (boolean, string?)
	local itemDef = Config.Items[itemId]
	if not itemDef then
		return false, "unknown_item"
	end
	count = math.floor(count or 1)
	if count <= 0 then
		return false, "invalid_count"
	end
	local data = DataStoreManager.get(userId)
	if not data then return false, "profile_not_loaded" end

	local current = data.inventory[itemId] or 0
	local newCount = math.min(current + count, itemDef.maxStack)
	if newCount == current then
		return false, "stack_full"
	end
	data.inventory[itemId] = newCount
	return true
end

function EconomyService.consumeItem(userId: number, itemId: string, count: number?): (boolean, string?)
	if not Config.Items[itemId] then
		return false, "unknown_item"
	end
	count = math.floor(count or 1)
	if count <= 0 then
		return false, "invalid_count"
	end
	local data = DataStoreManager.get(userId)
	if not data then return false, "profile_not_loaded" end

	local current = data.inventory[itemId] or 0
	if current < count then
		return false, "not_enough_items"
	end
	local remaining = current - count
	if remaining == 0 then
		data.inventory[itemId] = nil
	else
		data.inventory[itemId] = remaining
	end
	return true
end

-- Atomic "buy": spend currency AND grant item, or do neither. Prevents the classic
-- exploit where a player is charged but the item grant fails (or vice versa).
function EconomyService.purchaseItem(userId: number, itemId: string, currency: string, price: number): (boolean, string?)
	local data = DataStoreManager.get(userId)
	if not data then return false, "profile_not_loaded" end
	if not Config.Items[itemId] then return false, "unknown_item" end

	-- Pre-check affordability before mutating anything.
	if (data.currencies[currency] or 0) < price then
		return false, "insufficient_funds"
	end

	local spent = EconomyService.spendCurrency(userId, currency, price)
	if not spent then
		return false, "spend_failed"
	end
	local granted, reason = EconomyService.grantItem(userId, itemId, 1)
	if not granted then
		-- Roll back the spend so the player isn't charged for nothing.
		EconomyService.addCurrency(userId, currency, price)
		return false, reason
	end
	return true
end

return EconomyService
