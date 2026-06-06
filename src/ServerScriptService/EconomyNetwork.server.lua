--!strict
--[[
	EconomyNetwork  (Script) — server-authoritative bridge for the client UI.

	The client UI can only *request* actions; the SERVER decides what actually happens
	and validates everything through EconomyService. The client never changes its own
	data directly — that's the rule that keeps an economy exploit-proof.

	Creates a Folder of Remotes in ReplicatedStorage so the client can find them:
	  GetState        (RemoteFunction)  client asks for its balances + inventory
	  GetLeaderboard  (RemoteFunction)  client asks for the global top 10
	  Action          (RemoteEvent)     client requests an action by name
	  StateChanged    (RemoteEvent)     server pushes fresh state to the client

	Location: ServerScriptService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

-- Build the Remotes container.
local remotes = Instance.new("Folder")
remotes.Name = "EconomyRemotes"

local getState = Instance.new("RemoteFunction")
getState.Name = "GetState"
getState.Parent = remotes

local getLeaderboard = Instance.new("RemoteFunction")
getLeaderboard.Name = "GetLeaderboard"
getLeaderboard.Parent = remotes

local actionEvent = Instance.new("RemoteEvent")
actionEvent.Name = "Action"
actionEvent.Parent = remotes

local stateChanged = Instance.new("RemoteEvent")
stateChanged.Name = "StateChanged"
stateChanged.Parent = remotes

remotes.Parent = ReplicatedStorage

-- Build a snapshot of a player's economy state to send to the client.
local function snapshot(userId: number)
	local currencies = {}
	for name in pairs(Config.Currencies) do
		currencies[name] = EconomyService.getBalance(userId, name)
	end
	return { currencies = currencies, inventory = EconomyService.getInventory(userId) }
end

local function pushState(player: Player)
	stateChanged:FireClient(player, snapshot(player.UserId))
end

-- Client asks for its current state (on UI load).
getState.OnServerInvoke = function(player: Player)
	return snapshot(player.UserId)
end

-- Client asks for the global leaderboard.
getLeaderboard.OnServerInvoke = function(player: Player)
	return LeaderboardService.getTop(10)
end

-- Client requests an action. The SERVER decides the rules — the client only names the intent.
actionEvent.OnServerEvent:Connect(function(player: Player, actionName: any)
	local uid = player.UserId

	if actionName == "claimReward" then
		-- Demo reward: the SERVER chooses the amount. In production this would be gated
		-- behind a real condition (quest complete, timer, etc.) — never client-specified.
		EconomyService.addCurrency(uid, "Coins", 50)

	elseif actionName == "buyGoldKey" then
		EconomyService.purchaseItem(uid, "gold_key", "Coins", 30)

	elseif actionName == "grantPotion" then
		EconomyService.grantItem(uid, "health_potion", 1)

	elseif actionName == "usePotion" then
		EconomyService.consumeItem(uid, "health_potion", 1)
	end

	-- Reflect the result on the global board quickly (nice for a live demo) and push state back.
	LeaderboardService.submit(uid, EconomyService.getBalance(uid, Config.LEADERBOARD_CURRENCY))
	pushState(player)
end)

print("[Economy] Network/UI bridge online")
