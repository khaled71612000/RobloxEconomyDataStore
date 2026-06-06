# Persistent Economy System for Roblox — Currency, Inventory & Leaderboard

A production-shaped player economy for Roblox, built on `DataStoreService` with the
three things that actually prevent data loss in shipped games: **retries with backoff,
atomic `UpdateAsync` writes, and session locking.** Drop-in, configurable, and
documented so another developer can read it

---

## What it does

- **Multi-currency wallets** (Coins, Gems — add more in one line of config)
- **Inventory** with per-item stack caps and validation
- **Atomic purchases** — spend currency *and* grant item, or neither (no "charged but got nothing" exploit)
- **In-game leaderstats** (the player-list panel) kept in sync with saved data
- **Global cross-server leaderboard** via `OrderedDataStore` (real top-N ranking)
- **Crash- and shutdown-safe saving** via `BindToClose` and an autosave loop
- **Session locking** so the same player can't be loaded on two servers at once (the cause of rollbacks and item duplication)

---

## Architecture

```
ReplicatedStorage/
  EconomyConfig          -- all tunables: currencies, items, save intervals (designer-facing)

ServerScriptService/
  DataStoreManager       -- session-locked, retrying wrapper over DataStoreService
  EconomyService         -- gameplay API: getBalance/add/spend, grant/consume, purchase
  LeaderboardService     -- OrderedDataStore global top-N board
  EconomyMain (Script)   -- lifecycle: load on join, autosave, save+release on leave/shutdown
  EconomyDemo (Script)   -- Studio-only smoke test (delete before publishing)
```

The split is deliberate: **persistence** (DataStoreManager) never knows about gameplay,
and **gameplay** (EconomyService) never touches `DataStoreService` directly. One place to
change how data is stored, one place to change the economy rules.

---

## Setup

### Prerequisite (required for any DataStore to work)
In Studio: **Home → Game Settings → Security → enable "Enable Studio Access to API Services"**, and publish the place once (`File → Publish to Roblox`). DataStores only work in a published place.

### Option A — Rojo (recommended)
This repo ships a `default.project.json`.

```bash
# install Rojo (https://rojo.space) once
rojo serve
```
Then connect from the Rojo Studio plugin. Source files sync into the right services automatically.

### Option B — Manual paste (no tooling)
1. In Studio, create a **ModuleScript** named `EconomyConfig` in `ReplicatedStorage`, paste `src/ReplicatedStorage/EconomyConfig.lua`.
2. In `ServerScriptService`, create **ModuleScripts** named `DataStoreManager`, `EconomyService`, `LeaderboardService` and paste the matching files.
3. In `ServerScriptService`, create **Scripts** named `EconomyMain` and `EconomyDemo`, paste the `.server.lua` files.

> Names matter — the modules find each other with `:WaitForChild("...")`, so the Instance names must match the filenames (without extensions).

### Verify it works
With API access enabled, press **Play**. The Output window should print:

```
[Economy] Server economy system online — store: PlayerEconomy_v1
[DEMO] profile loaded ... PASS
...
[DEMO] All economy checks passed ✅
```
---

## Using the API

```lua
local EconomyService = require(game.ServerScriptService.EconomyService)

-- Currency
EconomyService.addCurrency(player.UserId, "Coins", 250)
local ok, why = EconomyService.spendCurrency(player.UserId, "Coins", 100)
if not ok then print("couldn't spend:", why) end   -- e.g. "insufficient_funds"
local balance = EconomyService.getBalance(player.UserId, "Coins")

-- Inventory
EconomyService.grantItem(player.UserId, "health_potion", 3)
EconomyService.consumeItem(player.UserId, "health_potion", 1)

-- Atomic shop purchase (spend + grant, or neither)
local bought, reason = EconomyService.purchaseItem(player.UserId, "gold_key", "Coins", 500)
```

Every mutation returns `(ok: boolean, reason: string?)` so callers handle failure
explicitly instead of trusting it worked.

Add a currency or item by editing **`EconomyConfig`** only:

```lua
EconomyConfig.Currencies.Tickets = { default = 0, displayName = "Tickets" }
EconomyConfig.Items.golden_hat   = { displayName = "Golden Hat", maxStack = 1 }
```

Existing players' saves are migrated forward automatically on next load (missing keys are backfilled from the template).

---

## How the data-loss protection works

| Risk | Mitigation in this code |
|---|---|
| DataStore request fails (they do, regularly) | `retry()` wraps every call in `pcall` + exponential backoff, up to `MAX_RETRIES` |
| Two reads race a write (lost update) | All writes use `UpdateAsync` (atomic read-modify-write), never `SetAsync` |
| Same player loaded on two servers → duplication / rollback | Session lock stamped on load, verified on every save, released on leave; stale locks (dead servers) are stolen after `SESSION_LOCK_STALE_AFTER` |
| Server shuts down before saving | `BindToClose` saves every loaded profile inside the shutdown window |
| Load fails and we overwrite good data with defaults | On hard load failure the player is **kicked**, not given a blank profile — refusing to destroy data is better than silently losing it |

## License
MIT