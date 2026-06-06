--[[
	EconomyClientUI  (LocalScript) — a simple on-screen panel that shows the player's
	economy live and lets them trigger SERVER-VALIDATED actions. The client only
	requests; the server decides and pushes back fresh state.

	Built entirely in code so there's nothing to lay out by hand.
	Location: StarterGui   (LocalScript)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local getState = remotes:WaitForChild("GetState")
local getLeaderboard = remotes:WaitForChild("GetLeaderboard")
local actionEvent = remotes:WaitForChild("Action")
local stateChanged = remotes:WaitForChild("StateChanged")

----------------------------------------------------------------------
-- tiny UI helpers
----------------------------------------------------------------------
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local DARK = Color3.fromRGB(24, 26, 33)
local ACCENT = Color3.fromRGB(70, 110, 255)
local WHITE = Color3.fromRGB(240, 240, 245)
local MUTED = Color3.fromRGB(170, 175, 185)

local gui = make("ScreenGui", { Name = "EconomyUI", ResetOnSpawn = false }, playerGui)

----------------------------------------------------------------------
-- Left panel: balances + inventory + action buttons
----------------------------------------------------------------------
local panel = make("Frame", {
	Size = UDim2.fromOffset(270, 320),
	Position = UDim2.fromOffset(20, 20),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
}, gui)
corner(panel, 12)
make("UIPadding", {
	PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local function label(text, order, color, size, bold)
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, size and size + 8 or 24),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color or WHITE,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextSize = size or 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = order,
	}, panel)
end

label("💰 Economy", 1, WHITE, 20, true)
local coinsLabel = label("Coins: —", 2, WHITE, 16)
local gemsLabel = label("Gems: —", 3, WHITE, 16)
local invLabel = label("Inventory: —", 4, MUTED, 14)
invLabel.Size = UDim2.new(1, 0, 0, 44)

local function button(text, order)
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = ACCENT,
		AutoButtonColor = true,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		LayoutOrder = order,
	}, panel)
	corner(b, 8)
	return b
end

local claimBtn = button("Claim +50 Coins", 5)
local buyBtn = button("Buy Gold Key (30 Coins)", 6)
local potionBtn = button("+ Health Potion", 7)
local useBtn = button("Use Health Potion", 8)

----------------------------------------------------------------------
-- Right panel: live global leaderboard
----------------------------------------------------------------------
local lb = make("Frame", {
	Size = UDim2.fromOffset(230, 300),
	Position = UDim2.new(1, -250, 0, 20),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
}, gui)
corner(lb, 12)
make("UIPadding", {
	PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, lb)
local lbText = make("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "🏆 Leaderboard\n\nloading…",
	TextColor3 = WHITE,
	Font = Enum.Font.Gotham,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
}, lb)

----------------------------------------------------------------------
-- rendering
----------------------------------------------------------------------
local function render(state)
	if not state then return end
	coinsLabel.Text = "Coins: " .. tostring(state.currencies.Coins or 0)
	gemsLabel.Text = "Gems: " .. tostring(state.currencies.Gems or 0)
	local items = {}
	for itemId, count in pairs(state.inventory) do
		table.insert(items, itemId .. " ×" .. count)
	end
	invLabel.Text = "Inventory: " .. (#items > 0 and table.concat(items, ", ") or "(empty)")
end

local function refreshLeaderboard()
	local ok, top = pcall(function()
		return getLeaderboard:InvokeServer()
	end)
	if not ok or not top then
		lbText.Text = "🏆 Leaderboard\n\n(unavailable)"
		return
	end
	local lines = { "🏆 Top Coins", "" }
	if #top == 0 then
		table.insert(lines, "(no entries yet —")
		table.insert(lines, "click Claim a few times)")
	else
		for i, e in ipairs(top) do
			table.insert(lines, i .. ". " .. e.name .. " — " .. e.score)
		end
	end
	lbText.Text = table.concat(lines, "\n")
end

-- server pushes new state after every action
stateChanged.OnClientEvent:Connect(function(state)
	render(state)
	refreshLeaderboard()
end)

-- wire buttons (client only requests; server validates)
claimBtn.MouseButton1Click:Connect(function() actionEvent:FireServer("claimReward") end)
buyBtn.MouseButton1Click:Connect(function() actionEvent:FireServer("buyGoldKey") end)
potionBtn.MouseButton1Click:Connect(function() actionEvent:FireServer("grantPotion") end)
useBtn.MouseButton1Click:Connect(function() actionEvent:FireServer("usePotion") end)

-- initial load
local ok, state = pcall(function() return getState:InvokeServer() end)
if ok then render(state) end
refreshLeaderboard()

-- keep the leaderboard fresh
task.spawn(function()
	while true do
		task.wait(10)
		refreshLeaderboard()
	end
end)
