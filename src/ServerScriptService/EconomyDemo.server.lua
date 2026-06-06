--!strict
--[[
	EconomyDemo  (Script) — Studio-only smoke test.
	Runs a sequence of economy operations against the first player to join and
	asserts the invariants hold. Lets you verify the whole stack in Play Solo
	without building UI. Delete (or set ENABLED=false) before publishing.

	Requires: Home > Game Settings > Security > "Enable Studio Access to API Services".

	Location: ServerScriptService
]]

local ENABLED = true

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
if not (ENABLED and RunService:IsStudio()) then
	return
end

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local DataStoreManager = require(script.Parent:WaitForChild("DataStoreManager"))

local function check(label: string, cond: boolean)
	print(string.format("[DEMO] %s ... %s", label, cond and "PASS" or "FAIL"))
	assert(cond, "DEMO FAILED: " .. label)
end

Players.PlayerAdded:Connect(function(player)
	local uid = player.UserId
	-- Wait until EconomyMain has loaded the profile.
	local t = 0
	while not DataStoreManager.get(uid) and t < 20 do
		task.wait(0.5); t += 1
	end
	check("profile loaded", DataStoreManager.get(uid) ~= nil)

	-- Currency: add, spend, overdraft protection.
	local start = EconomyService.getBalance(uid, "Coins")
	EconomyService.addCurrency(uid, "Coins", 50)
	check("add currency", EconomyService.getBalance(uid, "Coins") == start + 50)

	local ok = EconomyService.spendCurrency(uid, "Coins", 20)
	check("spend currency", ok and EconomyService.getBalance(uid, "Coins") == start + 30)

	local overdraft = EconomyService.spendCurrency(uid, "Coins", 9_999_999)
	check("overdraft refused", overdraft == false)

	-- Unknown currency rejected.
	local bad = EconomyService.addCurrency(uid, "Doubloons", 10)
	check("unknown currency rejected", bad == false)

	-- Inventory: grant, stack cap, consume.
	EconomyService.grantItem(uid, "health_potion", 5)
	check("grant item", EconomyService.getInventory(uid).health_potion == 5)

	EconomyService.grantItem(uid, "health_potion", 1000)
	check("stack capped at 99", EconomyService.getInventory(uid).health_potion == 99)

	local consumed = EconomyService.consumeItem(uid, "health_potion", 99)
	check("consume clears stack", consumed and EconomyService.getInventory(uid).health_potion == nil)

	-- Atomic purchase: affordable succeeds, unaffordable leaves balance untouched.
	EconomyService.addCurrency(uid, "Coins", 100)
	local before = EconomyService.getBalance(uid, "Coins")
	local bought = EconomyService.purchaseItem(uid, "gold_key", "Coins", 30)
	check("purchase succeeds", bought and EconomyService.getBalance(uid, "Coins") == before - 30)

	local before2 = EconomyService.getBalance(uid, "Coins")
	local broke = EconomyService.purchaseItem(uid, "gold_key", "Coins", 9_999_999)
	check("unaffordable purchase rolls back", broke == false and EconomyService.getBalance(uid, "Coins") == before2)

	print("[DEMO] All economy checks passed ✅")
end)
