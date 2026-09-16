-- GoldLedger completed-session history
local addonName, ns = ...

local MAX_SESSIONS = 100

local function GetSessionsTable()
	GoldLedgerDB = GoldLedgerDB or {}
	GoldLedgerDB.sessions = GoldLedgerDB.sessions or {}
	return GoldLedgerDB.sessions
end

local function CopyItems(items)
	local result = {}
	if type(items) == "table" then
		for itemID, quantity in pairs(items) do
			if type(itemID) == "number" and type(quantity) == "number" then
				result[itemID] = quantity
			end
		end
	end
	return result
end

local function CopySession(session)
	return {
		id = session.id,
		character = session.character,
		realm = session.realm,
		startedAt = session.startedAt,
		endedAt = session.endedAt,
		activeDuration = session.activeDuration,
		startingMoney = session.startingMoney,
		endingMoney = session.endingMoney,
		rawGoldDelta = session.rawGoldDelta,
		items = CopyItems(session.items),
		itemValue = session.itemValue,
		estimatedTotalValue = session.estimatedTotalValue,
		rawGoldPerHour = session.rawGoldPerHour,
		estimatedGoldPerHour = session.estimatedGoldPerHour,
		pricedItemTypes = session.pricedItemTypes,
		unpricedItemTypes = session.unpricedItemTypes,
		routeName = session.routeName,
		zone = session.zone,
		subzone = session.subzone,
		mapID = session.mapID,
	}
end

function ns.SaveCompletedSession(session)
	if type(session) ~= "table" or type(session.id) ~= "string" or session.id == "" or type(session.endedAt) ~= "number" then
		return false
	end

	local sessions = GetSessionsTable()
	for _, savedSession in ipairs(sessions) do
		if savedSession.id == session.id then
			return false
		end
	end

	-- Records are stored oldest first; pruning removes the oldest record.
	table.insert(sessions, CopySession(session))
	while #sessions > MAX_SESSIONS do
		table.remove(sessions, 1)
	end

	if ns.RefreshHistoryFrame then
		ns.RefreshHistoryFrame()
	end
	return true
end

function ns.GetSessionHistory()
	return GetSessionsTable()
end

function ns.GetRecentSessions(limit)
	local sessions = GetSessionsTable()
	local result = {}
	local count = math.min(tonumber(limit) or 10, #sessions)
	for index = #sessions, #sessions - count + 1, -1 do
		table.insert(result, sessions[index])
	end
	return result
end
