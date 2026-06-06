--!strict
--[[
	LeaderboardService
	A cross-server, global leaderboard built on an OrderedDataStore — the right tool
	for "top N players by X", because OrderedDataStore can return sorted pages directly
	(a regular DataStore cannot sort).

	Two layers of "leaderboard" exist in Roblox and people conflate them:
	  - leaderstats: the per-server player-list panel (handled in EconomyMain)
	  - global board: persistent, cross-server ranking (this file)

	Location: ServerScriptService
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("EconomyConfig"))

local LeaderboardService = {}

local orderedStore = DataStoreService:GetOrderedDataStore(Config.LEADERBOARD_STORE_NAME)

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local attempt = 0
	while attempt < Config.MAX_RETRIES do
		attempt += 1
		local ok, result = pcall(fn)
		if ok then return true, result end
		warn(string.format("[LeaderboardService] %s failed (%d/%d): %s",
			label, attempt, Config.MAX_RETRIES, tostring(result)))
		if attempt < Config.MAX_RETRIES then
			task.wait(Config.RETRY_BASE_DELAY * (2 ^ (attempt - 1)))
		end
	end
	return false, nil
end

-- Push a player's score to the global board. OrderedDataStore values must be integers.
function LeaderboardService.submit(userId: number, score: number)
	score = math.floor(score)
	retry("submit:" .. userId, function()
		orderedStore:SetAsync("player_" .. userId, score)
		return true
	end)
end

-- Fetch the top N. Returns an array of { userId, name, score }, rank by array order.
function LeaderboardService.getTop(count: number): { { userId: number, name: string, score: number } }
	count = math.clamp(count, 1, 100)
	local results = {}

	local ok, page = retry("getTop", function()
		-- ascending=false -> highest first; pageSize capped at 100 by the API.
		return orderedStore:GetSortedAsync(false, count)
	end)
	if not ok or not page then
		return results
	end

	local entries = page:GetCurrentPage()
	for _, entry in ipairs(entries) do
		-- gsub returns (string, count); wrap in parens so only the string reaches tonumber
		-- (otherwise the count is misread as tonumber's base argument).
		local idString = ((entry.key :: string):gsub("player_", ""))
		local userId = tonumber(idString) or 0
		local name = "Unknown"
		-- GetNameFromUserIdAsync can throw; never let a name lookup crash the board.
		pcall(function()
			name = game.Players:GetNameFromUserIdAsync(userId)
		end)
		table.insert(results, {
			userId = userId,
			name = name,
			score = entry.value,
		})
	end
	return results
end

return LeaderboardService
