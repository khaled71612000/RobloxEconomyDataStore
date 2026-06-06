--!strict
--[[
	DataStoreManager
	A defensive wrapper around DataStoreService that demonstrates the three things
	that actually cause data loss in production Roblox games:

	  1. Unhandled request failures  -> every call is pcall'd and retried with backoff
	  2. Race conditions on read/modify/write -> all writes go through UpdateAsync, never SetAsync
	  3. Two servers owning one player's data at once (duplication/rollback) -> session locking

	This is intentionally written from primitives (no library) so the mechanics are
	visible. In a shipping game I would reach for ProfileStore, which solves the same
	problems with battle-tested edge-case handling — I note exactly where in the README.

	Location: ServerScriptService
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("EconomyConfig"))

local DataStoreManager = {}

-- A unique id for THIS server instance. Used to claim/verify session locks.
-- JobId is empty in Studio, so fall back to a generated id for local testing.
local SERVER_ID = (RunService:IsStudio() and ("studio-" .. tostring(os.clock()))) or game.JobId

local store = DataStoreService:GetDataStore(Config.STORE_NAME)

-- In-memory cache of profiles this server currently owns: userId -> profile table
local loaded: { [number]: any } = {}

----------------------------------------------------------------------
-- Low-level: retry any DataStore operation with exponential backoff.
----------------------------------------------------------------------
local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local attempt = 0
	while attempt < Config.MAX_RETRIES do
		attempt += 1
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[DataStoreManager] %s failed (attempt %d/%d): %s",
			label, attempt, Config.MAX_RETRIES, tostring(result)))
		if attempt < Config.MAX_RETRIES then
			task.wait(Config.RETRY_BASE_DELAY * (2 ^ (attempt - 1)))
		end
	end
	return false, nil
end

----------------------------------------------------------------------
-- Helpers for the stored envelope: { data = <profile>, lock = { owner, t } }
----------------------------------------------------------------------
local function isLockHeldByOther(envelope: any): boolean
	-- In Studio there is only ever one server instance, so a session lock only creates
	-- friction: a lock left by a previous Play/Stop blocks the next run. Skip it in Studio.
	if RunService:IsStudio() then
		return false
	end
	if not envelope or not envelope.lock then
		return false
	end
	local lock = envelope.lock
	if lock.owner == SERVER_ID then
		return false
	end
	-- A lock older than the stale threshold is treated as a dead session.
	local age = os.time() - (lock.t or 0)
	return age < Config.SESSION_LOCK_STALE_AFTER
end

----------------------------------------------------------------------
-- Public: load a profile, claiming the session lock for this server.
-- Returns the profile data table, or nil on hard failure.
----------------------------------------------------------------------
function DataStoreManager.load(userId: number): any?
	local key = "player_" .. userId

	local ok, envelope = retry("load:" .. key, function()
		-- UpdateAsync gives us atomic read-modify-write: we read the current
		-- envelope, refuse if another live server holds the lock, otherwise
		-- stamp our own lock and write it back in a single transaction.
		return store:UpdateAsync(key, function(current)
			current = current or { data = nil, lock = nil }

			if isLockHeldByOther(current) then
				-- Returning nil cancels the write; we detect the cancel below and back off.
				return nil
			end

			current.data = current.data or Config.buildDefaultProfile()
			current.lock = { owner = SERVER_ID, t = os.time() }
			return current
		end)
	end)

	if not ok then
		return nil
	end

	if envelope == nil then
		-- Lock was held by another server. Caller can retry shortly (player rejoined fast,
		-- or previous server is still shutting down). We surface this as a soft failure.
		warn("[DataStoreManager] load blocked by active session lock for " .. key)
		return nil
	end

	-- Backfill any keys added since this profile was last saved (schema migration).
	local data = envelope.data
	local template = Config.buildDefaultProfile()
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = v
		end
	end
	-- Backfill newly-added currencies specifically.
	for name, def in pairs(Config.Currencies) do
		if data.currencies[name] == nil then
			data.currencies[name] = def.default
		end
	end

	data.stats.joinCount += 1
	loaded[userId] = data
	return data
end

----------------------------------------------------------------------
-- Public: save a profile. If release=true, clears the lock so another
-- server (or this player's next session) can claim it.
----------------------------------------------------------------------
function DataStoreManager.save(userId: number, release: boolean?): boolean
	local data = loaded[userId]
	if not data then
		return false
	end
	local key = "player_" .. userId
	data.stats.lastSeen = os.time()

	local ok = retry("save:" .. key, function()
		return store:UpdateAsync(key, function(current)
			current = current or {}
			-- Only write if we still own the lock, or it's free — never stomp another server.
			if current.lock and current.lock.owner ~= SERVER_ID
				and (os.time() - (current.lock.t or 0)) < Config.SESSION_LOCK_STALE_AFTER then
				return nil
			end
			current.data = data
			current.lock = (release and nil) or { owner = SERVER_ID, t = os.time() }
			return current
		end)
	end)

	if ok and release then
		loaded[userId] = nil
	end
	return ok
end

-- Read-only accessor for systems that need the live in-memory profile.
function DataStoreManager.get(userId: number): any?
	return loaded[userId]
end

function DataStoreManager.getAllLoaded(): { [number]: any }
	return loaded
end

return DataStoreManager
