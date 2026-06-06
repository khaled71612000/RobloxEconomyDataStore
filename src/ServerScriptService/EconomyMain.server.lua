--!strict
--[[
	EconomyMain  (Script, runs on server start)
	Wires the lifecycle together:

	  PlayerAdded     -> load profile (claims session lock), build leaderstats
	  every N seconds -> autosave all loaded profiles + push to global leaderboard
	  PlayerRemoving  -> final save + RELEASE the session lock
	  BindToClose     -> save everyone on shutdown (the save people forget, and the
	                     reason players lose progress when a server crashes/updates)

	Location: ServerScriptService
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local DataStoreManager = require(script.Parent:WaitForChild("DataStoreManager"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

----------------------------------------------------------------------
-- leaderstats: mirror the persisted currency into the in-game player list.
----------------------------------------------------------------------
local function buildLeaderstats(player: Player, data: any)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	for currencyName in pairs(Config.Currencies) do
		local value = Instance.new("IntValue")
		value.Name = Config.Currencies[currencyName].displayName
		value.Value = data.currencies[currencyName] or 0
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
end

-- Keep the player-list numbers in sync with the source-of-truth profile.
local function syncLeaderstats(player: Player)
	local data = DataStoreManager.get(player.UserId)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not data or not leaderstats then return end
	for currencyName, def in pairs(Config.Currencies) do
		local value = leaderstats:FindFirstChild(def.displayName)
		if value and value:IsA("IntValue") then
			value.Value = data.currencies[currencyName] or 0
		end
	end
end

----------------------------------------------------------------------
-- Player join / leave
----------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local data = DataStoreManager.load(player.UserId)

	-- If the lock was held (fast rejoin / prior server still closing), retry briefly.
	local tries = 0
	while not data and tries < 5 and player.Parent do
		tries += 1
		task.wait(2)
		data = DataStoreManager.load(player.UserId)
	end

	if not data then
		-- Don't let the player keep an unsaved/empty session — kick rather than risk
		-- overwriting good data with defaults. Honest failure beats silent data loss.
		player:Kick("Your data couldn't be loaded right now. Please rejoin in a moment.")
		return
	end

	-- First-time grant example: give a starter item once.
	if data.stats.joinCount == 1 then
		EconomyService.grantItem(player.UserId, "wooden_sword", 1)
	end

	buildLeaderstats(player, data)
end

local function onPlayerRemoving(player: Player)
	-- Final save AND release the lock so the next server can claim it immediately.
	DataStoreManager.save(player.UserId, true)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Players already in-game when this script starts (Studio play-solo / hot reload).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

----------------------------------------------------------------------
-- Autosave loop
----------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for userId in pairs(DataStoreManager.getAllLoaded()) do
			DataStoreManager.save(userId, false) -- keep the lock; player is still here
			-- Push the leaderboard currency to the global board.
			local balance = EconomyService.getBalance(userId, Config.LEADERBOARD_CURRENCY)
			LeaderboardService.submit(userId, balance)
		end
		for _, player in ipairs(Players:GetPlayers()) do
			syncLeaderstats(player)
		end
	end
end)

----------------------------------------------------------------------
-- Shutdown: save everyone. Roblox gives BindToClose ~30s before force-close.
----------------------------------------------------------------------
game:BindToClose(function()
	if RunService:IsStudio() then
		-- In Studio, DataStore writes are flaky and BindToClose can hang the stop button.
		task.wait(1)
		return
	end
	local pending = {}
	for userId in pairs(DataStoreManager.getAllLoaded()) do
		table.insert(pending, userId)
	end
	-- Save in parallel so we fit inside the shutdown window even with many players.
	for _, userId in ipairs(pending) do
		task.spawn(function()
			DataStoreManager.save(userId, true)
		end)
	end
	-- Crude barrier: wait until all profiles are released or we run out of time.
	local deadline = os.clock() + 25
	while os.clock() < deadline and next(DataStoreManager.getAllLoaded()) ~= nil do
		task.wait(0.2)
	end
end)

print("[Economy] Server economy system online — store:", Config.STORE_NAME)
