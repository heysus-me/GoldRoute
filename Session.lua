-- GoldRoute Session Data Management
local addonName, ns = ...

local activeSession = nil
local lastSession = nil
local sessionCounter = 0

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
		items = {},
	}
end

---
-- Generate a reliably unique session ID
-- Format: realm-character-timestamp-sequence
-- Sequence ensures no collisions during rapid consecutive sessions
---
local function GenerateSessionID()
	local character = UnitName("player") or "Unknown"
	local realm = GetRealmName() or "Unknown"
	local timestamp = time()
	sessionCounter = sessionCounter + 1
	return realm .. "-" .. character .. "-" .. timestamp .. "-" .. sessionCounter
end

---
-- Start a new farming session
-- Records character metadata, wall-clock timestamp, starting money, and begins inventory tracking
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
	
	-- Begin inventory tracking
	if ns.InventoryStartTracking then
		ns.InventoryStartTracking()
	end
	
	return activeSession
end

---
-- Stop the active farming session
-- Records ending money, calculates raw gold delta, finalizes inventory tracking, and stores session
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
	
	-- Finalize inventory tracking and attach to session
	if ns.InventoryStopTracking then
		local acquiredItems = ns.InventoryStopTracking()
		if acquiredItems then
			activeSession.items = acquiredItems
		end
	end

	-- Capture the pricing snapshot and derived rates at completion.
	local itemValue, pricedItemTypes, unpricedItemTypes = 0, 0, 0
	if ns.GetEstimatedItemValue then
		itemValue, pricedItemTypes, unpricedItemTypes = ns.GetEstimatedItemValue(activeSession.items)
	end
	activeSession.itemValue = math.floor(itemValue + 0.5)
	activeSession.estimatedTotalValue = activeSession.rawGoldDelta + activeSession.itemValue
	activeSession.pricedItemTypes = pricedItemTypes
	activeSession.unpricedItemTypes = unpricedItemTypes
	if activeSession.activeDuration > 0 then
		activeSession.rawGoldPerHour = math.floor((activeSession.rawGoldDelta / activeSession.activeDuration * 3600) + 0.5)
		activeSession.estimatedGoldPerHour = math.floor((activeSession.estimatedTotalValue / activeSession.activeDuration * 3600) + 0.5)
	else
		activeSession.rawGoldPerHour = 0
		activeSession.estimatedGoldPerHour = 0
	end
	
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
-- Get the live raw gold delta for the active session
-- If a session is active: currentMoney - startingMoney
-- If no session is active: nil
-- Does not mutate the session object
---
function ns.GetLiveRawGoldDelta()
	if not activeSession then
		return nil
	end

	return (GetMoney() or 0) - activeSession.startingMoney
end

---
-- Get the most recently completed session
---
function ns.GetLastSession()
	return lastSession
end
