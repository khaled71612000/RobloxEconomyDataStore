--!strict
--[[
	EconomyConfig
	Single source of truth for the economy system. Designers can tune everything
	here without touching gameplay code — same principle as the self-service
	designer tooling I built at Limbic: put the knobs where the non-engineers are.

	Location: ReplicatedStorage  (shared so client UI can read display config too)
]]

local EconomyConfig = {}

-- DataStore identity. BUMP THE VERSION SUFFIX to start from a clean schema in prod.
EconomyConfig.STORE_NAME = "PlayerEconomy_v1"
EconomyConfig.LEADERBOARD_STORE_NAME = "EconomyLeaderboard_v1"

-- Currencies. Add a new currency by adding a line here — nothing else changes.
EconomyConfig.Currencies = {
	Coins = { default = 100, displayName = "Coins" },
	Gems  = { default = 0,   displayName = "Gems" },
}

-- The currency that drives the public/global leaderboard.
EconomyConfig.LEADERBOARD_CURRENCY = "Coins"

-- Inventory: which item ids are valid, so a malformed/exploited grant is rejected.
EconomyConfig.Items = {
	wooden_sword = { displayName = "Wooden Sword", maxStack = 1 },
	health_potion = { displayName = "Health Potion", maxStack = 99 },
	gold_key      = { displayName = "Gold Key", maxStack = 10 },
}

-- Persistence tuning.
EconomyConfig.AUTOSAVE_INTERVAL = 120     -- seconds between background saves (per ProfileStore guidance, longer = fewer DataStore calls)
EconomyConfig.MAX_RETRIES = 5             -- retries for any DataStore call before giving up
EconomyConfig.RETRY_BASE_DELAY = 1        -- seconds; doubles each retry (exponential backoff)
EconomyConfig.SESSION_LOCK_STALE_AFTER = 1800 -- seconds; a lock older than this is assumed dead and stolen

-- Default profile shape. Anything missing on load is backfilled from here (schema migration).
function EconomyConfig.buildDefaultProfile(): { [string]: any }
	local currencies = {}
	for name, def in pairs(EconomyConfig.Currencies) do
		currencies[name] = def.default
	end
	return {
		currencies = currencies,
		inventory = {},        -- { [itemId] = count }
		stats = {
			joinCount = 0,
			lastSeen = 0,
		},
	}
end

return EconomyConfig
