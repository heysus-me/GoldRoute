-- GoldLedger Session Data Management
local addonName, ns = ...

local activeSession = nil
local lastSession = nil
local sessionCounter = 0

---
-- Create a new session object with default values
-- New sessions include generic activity metadata for future expansion beyond gathering
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
		-- Activity classification (gathering, crafting, etc.)
		activityType = "gathering",
		-- Generic activity metadata (will expand as more activity types are supported)
		activity = {
			profession = nil,
			zone = nil,
			subzone = nil,
			mapID = nil,
		},
		-- Unique human-readable session identifier
		sessionName = nil,
		-- Legacy fields (preserved for backward compatibility during migration)
		routeName = nil,
		zone = nil,
		subzone = nil,
		mapID = nil,
	}
end

---
-- Generate an automatic session name from zone and timestamp
-- Format: Zone-Activity-YYYY-MM-DDTHH-MM-SS (ISO-like, filename-safe)
-- Example: Isle of Dorn-Gathering-2026-09-16T21-42-31
---
local function GenerateSessionName(zone, activityType)
	local timestamp = os.date("!%Y-%m-%dT%H-%M-%S")
	local activity = activityType or "Gathering"
	local location = zone or "Unknown"
	return location .. "-" .. activity .. "-" .. timestamp
end

---
-- Normalize a user-entered route label: trim whitespace, cap length, and
-- collapse an empty result to nil so blank labels never get stored as "".
---
local ROUTE_NAME_MAX_LENGTH = 50
local function NormalizeRouteName(routeName)
	if type(routeName) ~= "string" then
		return nil
	end

	routeName = routeName:match("^%s*(.-)%s*$")
	if routeName == "" then
		return nil
	end

	if #routeName > ROUTE_NAME_MAX_LENGTH then
		routeName = routeName:sub(1, ROUTE_NAME_MAX_LENGTH)
	end

	return routeName
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
-- Accepts optional metadata as a plain routeName string or a table such as { routeName = "..." }.
-- Zone/subzone/mapID are captured once here and are not refreshed as the player travels.
-- Populates both legacy fields and new activity model for backward compatibility.
---
function ns.SessionStart(metadata)
	if activeSession then
		-- Safety: don't overwrite active session without stopping it
		return activeSession
	end

	local routeName
	if type(metadata) == "string" then
		routeName = metadata
	elseif type(metadata) == "table" then
		routeName = metadata.routeName
	end

	activeSession = CreateSessionObject()
	activeSession.id = GenerateSessionID()
	activeSession.character = UnitName("player")
	activeSession.realm = GetRealmName()
	activeSession.startedAt = time()
	activeSession.startingMoney = GetMoney() or 0
	activeSession.routeName = NormalizeRouteName(routeName)

	-- Starting-location snapshot only; empty strings collapse to nil.
	local zoneText = GetZoneText and GetZoneText() or nil
	local subzoneText = GetSubZoneText and GetSubZoneText() or nil
	activeSession.zone = (zoneText and zoneText ~= "") and zoneText or nil
	activeSession.subzone = (subzoneText and subzoneText ~= "") and subzoneText or nil
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
		activeSession.mapID = (ok and type(mapID) == "number") and mapID or nil
	end

	-- Populate activity metadata (mirrors legacy fields during this migration phase)
	if activeSession.activity then
		activeSession.activity.zone = activeSession.zone
		activeSession.activity.subzone = activeSession.subzone
		activeSession.activity.mapID = activeSession.mapID
	end

	-- Generate automatic session name from location and timestamp
	activeSession.sessionName = GenerateSessionName(activeSession.zone, "Gathering")

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
