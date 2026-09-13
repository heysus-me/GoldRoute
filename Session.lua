-- GoldRoute Session Data Management
local addonName, ns = ...

local activeSession = nil
local lastSession = nil

---
-- Create a new session object with default values
---
local function CreateSessionObject()
	return {
		id = nil,
		character = nil,
		realm = nil,
		startedAt = nil,
		endedAt = nil,
		activeDuration = 0,
		startingMoney = 0,
		endingMoney = 0,
		rawGoldDelta = 0,
	}
end

---
-- Generate a reasonably unique session ID
-- Format: realm-character-timestamp
---
local function GenerateSessionID()
	local character = UnitName("player") or "Unknown"
	local realm = GetRealmName() or "Unknown"
	local timestamp = time()
	return realm .. "-" .. character .. "-" .. timestamp
end

---
-- Start a new farming session
-- Records character metadata, wall-clock timestamp, and starting money
---
function ns.SessionStart()
	if activeSession then
		-- Safety: don't overwrite active session without stopping it
		return activeSession
	end
	
	activeSession = CreateSessionObject()
	activeSession.id = GenerateSessionID()
	activeSession.character = UnitName("player")
	activeSession.realm = GetRealmName()
	activeSession.startedAt = time()
	activeSession.startingMoney = GetMoney() or 0
	
	return activeSession
end

---
-- Stop the active farming session
-- Records ending money, calculates raw gold delta, and stores session
---
function ns.SessionStop(activeDuration)
	if not activeSession then
		-- No active session to stop
		return nil
	end
	
	activeSession.endedAt = time()
	activeSession.endingMoney = GetMoney() or 0
	activeSession.rawGoldDelta = activeSession.endingMoney - activeSession.startingMoney
	activeSession.activeDuration = activeDuration or 0
	
	-- Move to last session and clear active reference
	lastSession = activeSession
	activeSession = nil
	
	return lastSession
end

---
-- Get the current active session
---
function ns.GetActiveSession()
	return activeSession
end

---
-- Get the most recently completed session
---
function ns.GetLastSession()
	return lastSession
end
