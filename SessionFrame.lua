-- GoldRoute Session Frame - UI and session timer management
local addonName, ns = ...

-- Session states
local STATE_IDLE = "IDLE"
local STATE_RUNNING = "RUNNING"
local STATE_PAUSED = "PAUSED"
local STATE_STOPPED = "STOPPED"

-- UI elements
local sessionFrame
local startButton
local pauseButton
local stopButton
local historyButton
local statusText
local routeLabel
local routeEditBox
local zoneContextText
local elapsedTimeText
local rawGoldMetricsText
local rawGoldPerHourText
local itemValueText
local estimatedGoldPerHourText
local itemsHeaderText
local itemDisplayStrings
local metricEventFrame

-- Session timer state
local sessionState = STATE_IDLE
local accumulatedElapsed = 0
local segmentStartTime = nil
local activeTicker = nil
local routeEditBoxLocked = false

---
-- Format elapsed seconds as HH:MM:SS
---
local function FormatTime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

---
-- Format copper into readable WoW currency
-- Rounds to nearest whole copper before decomposing
-- Examples: 12g 34s 56c, -5g 40s, 123c
---
local function FormatCopper(copper)
	if not copper then
		return "0g"
	end

	local isNegative = copper < 0
	copper = math.abs(copper)

	-- Round to nearest whole copper
	copper = math.floor(copper + 0.5)

	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local copperRemain = copper % 100

	local parts = {}
	if gold > 0 then
		table.insert(parts, gold .. "g")
	end
	if silver > 0 then
		table.insert(parts, silver .. "s")
	end
	if copperRemain > 0 or #parts == 0 then
		table.insert(parts, copperRemain .. "c")
	end

	local result = table.concat(parts, " ")

	if isNegative then
		result = "-" .. result
	end

	return result
end

---
-- Build the "Zone: X" / "Zone: X — Y" contextual line from session data
-- Returns "" when no zone was captured (e.g. very old sessions)
---
local function BuildZoneContextText(session)
	if not session or not session.zone then
		return ""
	end

	if session.subzone and session.subzone ~= session.zone then
		return "Zone: " .. session.zone .. " \226\128\148 " .. session.subzone
	end

	return "Zone: " .. session.zone
end

---
-- Lock/unlock the route-name EditBox
-- Editable only while IDLE or STOPPED; locked while RUNNING or PAUSED
---
local function SetRouteEditBoxLocked(locked)
	routeEditBoxLocked = locked
	routeEditBox:EnableMouse(not locked)
	if locked then
		routeEditBox:ClearFocus()
		routeEditBox:SetTextColor(0.6, 0.6, 0.6)
	else
		routeEditBox:SetTextColor(1, 1, 1)
	end
end

---
-- Get the current displayed elapsed time
-- When RUNNING: accumulated + current segment duration
-- When PAUSED/STOPPED: accumulated only
---
local function GetElapsedTime()
	if sessionState == STATE_RUNNING and segmentStartTime then
		return accumulatedElapsed + (GetTime() - segmentStartTime)
	else
		return accumulatedElapsed
	end
end

---
-- Update the elapsed time display text
-- Called once per second by ticker and immediately on state changes
---
local function UpdateElapsedDisplay()
	elapsedTimeText:SetText(FormatTime(GetElapsedTime()))
end

---
-- Update all live session metrics
-- Called every second by ticker and immediately on state changes
-- Calculates and displays: Raw Gold, Raw Gold/Hour, Item Value, Estimated Gold/Hour
---
local function UpdateLiveMetrics()
	-- Get current elapsed time (already handles RUNNING vs PAUSED correctly)
	local elapsedTime = GetElapsedTime()

	-- Get live raw gold delta
	local liveRawGold = nil
	if ns.GetLiveRawGoldDelta then
		liveRawGold = ns.GetLiveRawGoldDelta()
	end

	-- Get acquired items
	local items = ns.GetAcquiredItems and ns.GetAcquiredItems() or {}

	-- Get estimated item value
	local itemValue = 0
	local pricedCount = 0
	local unpricedCount = 0
	if ns.GetEstimatedItemValue then
		itemValue, pricedCount, unpricedCount = ns.GetEstimatedItemValue(items)
	end

	-- Auctionator availability
	local hasAuctionator = ns.IsAuctionatorAvailable and ns.IsAuctionatorAvailable() or false

	-- Update Raw Gold
	if liveRawGold then
		rawGoldMetricsText:SetText("Raw Gold: " .. FormatCopper(liveRawGold))
	else
		rawGoldMetricsText:SetText("Raw Gold: 0c")
	end

	-- Calculate Raw Gold / Hour (avoid division by zero)
	if liveRawGold and elapsedTime > 0 then
		local rawGoldPerHour = liveRawGold / elapsedTime * 3600
		rawGoldPerHourText:SetText("Raw Gold / Hour: " .. FormatCopper(rawGoldPerHour))
	else
		rawGoldPerHourText:SetText("Raw Gold / Hour: --")
	end

	-- Update Item Value (show -- if Auctionator unavailable)
	if hasAuctionator then
		local displayValue = itemValue
		local valueStr = FormatCopper(displayValue)

		-- Add unpriced indicator if needed
		if unpricedCount > 0 then
			valueStr = valueStr .. " (" .. unpricedCount .. " unpriced)"
		end

		itemValueText:SetText("Item Value: " .. valueStr)
	else
		itemValueText:SetText("Item Value: --")
	end

	-- Update Estimated Gold / Hour
	if hasAuctionator and elapsedTime > 0 then
		local liveRawGoldVal = liveRawGold or 0
		local estimatedTotalValue = liveRawGoldVal + itemValue
		local estimatedGoldPerHour = estimatedTotalValue / elapsedTime * 3600
		estimatedGoldPerHourText:SetText("Estimated Gold / Hour: " .. FormatCopper(estimatedGoldPerHour))
	else
		estimatedGoldPerHourText:SetText("Estimated Gold / Hour: --")
	end
end

local function OnMetricEvent(_, event)
	if event == "PLAYER_MONEY" and (sessionState == STATE_RUNNING or sessionState == STATE_PAUSED) then
		UpdateLiveMetrics()
	end
end

---
-- Clear acquired items display
---
local function ClearAcquiredItems()
	itemsHeaderText:SetText("")
	if itemDisplayStrings then
		for i, fontString in ipairs(itemDisplayStrings) do
			fontString:SetText("")
		end
	end
end

---
-- Display acquired items from a table of {itemID = quantity, ...}
-- Shows up to 8 item types sorted by quantity descending
-- Includes per-item value from Auctionator if available
---
local function DisplayAcquiredItems(itemsTable)
	-- Clear all item display strings
	if itemDisplayStrings then
		for i, fontString in ipairs(itemDisplayStrings) do
			fontString:SetText("")
		end
	end

	if not itemsTable or type(itemsTable) ~= "table" then
		itemsHeaderText:SetText("")
		return
	end

	-- Collect items into a table for sorting
	-- Only include valid items: numeric itemID, numeric quantity > 0
	local items = {}
	for itemID, quantity in pairs(itemsTable) do
		if type(itemID) == "number" and type(quantity) == "number" and quantity > 0 then
			table.insert(items, { itemID = itemID, quantity = quantity })
		end
	end

	if #items == 0 then
		itemsHeaderText:SetText("")
		return
	end

	-- Sort by quantity descending, then by item name or ID
	table.sort(items, function(a, b)
		if a.quantity ~= b.quantity then
			return a.quantity > b.quantity
		end

		local nameA = ns.GetItemName(a.itemID) or ("Item " .. a.itemID)
		local nameB = ns.GetItemName(b.itemID) or ("Item " .. b.itemID)

		if nameA ~= nameB then
			return nameA < nameB
		end

		return a.itemID < b.itemID
	end)

	itemsHeaderText:SetText("Items Acquired")

	-- Display up to 8 items with pricing
	local displayCount = math.min(#items, 8)
	for i = 1, displayCount do
		local item = items[i]
		local itemName = ns.GetItemName(item.itemID) or ("Item " .. item.itemID)

		-- Get per-item value
		local unitPrice = ns.GetItemMarketPrice and ns.GetItemMarketPrice(item.itemID) or nil
		local itemValue = unitPrice and (unitPrice * item.quantity) or nil

		-- Format display: "Item Name xQuantity   Value"
		local displayText
		if itemValue then
			displayText = itemName .. " x" .. item.quantity .. "   " .. FormatCopper(itemValue)
		else
			displayText = itemName .. " x" .. item.quantity .. "   --"
		end

		itemDisplayStrings[i]:SetText(displayText)
	end

	-- Show "+X more item types" if there are more than 8
	if #items > 8 then
		itemDisplayStrings[9]:SetText("+ " .. (#items - 8) .. " more item types")
	else
		itemDisplayStrings[9]:SetText("")
	end
end

---
-- Refresh live acquired items display during active session
-- Called by Inventory.lua when items are acquired during RUNNING or PAUSED state
---
function ns.RefreshLiveItems()
	if sessionState == STATE_RUNNING or sessionState == STATE_PAUSED then
		local items = ns.GetAcquiredItems and ns.GetAcquiredItems() or {}
		DisplayAcquiredItems(items)
		UpdateLiveMetrics()
	end
end

---
-- Clear all session summary display elements
---
local function ClearSessionSummary()
	rawGoldMetricsText:SetText("")
	rawGoldPerHourText:SetText("")
	itemValueText:SetText("")
	estimatedGoldPerHourText:SetText("")
	ClearAcquiredItems()
end

---
-- Display session summary after stop
---
local function DisplaySessionSummary(session)
	if not session then
		rawGoldMetricsText:SetText("Raw Gold: --")
		rawGoldPerHourText:SetText("Raw Gold / Hour: --")
		itemValueText:SetText("Item Value: --")
		estimatedGoldPerHourText:SetText("Estimated Gold / Hour: --")
		ClearAcquiredItems()
		return
	end

	-- Display finalized raw gold
	local rawGoldStr = FormatCopper(session.rawGoldDelta)
	rawGoldMetricsText:SetText("Raw Gold: " .. rawGoldStr)

	-- Display finalized raw gold per hour
	if session.activeDuration > 0 then
		local goldPerHour = session.rawGoldDelta / session.activeDuration * 3600
		rawGoldPerHourText:SetText("Raw Gold / Hour: " .. FormatCopper(goldPerHour))
	else
		rawGoldPerHourText:SetText("Raw Gold / Hour: --")
	end

	-- Calculate finalized item value
	local itemValue = 0
	local pricedCount = 0
	local unpricedCount = 0
	if ns.GetEstimatedItemValue then
		itemValue, pricedCount, unpricedCount = ns.GetEstimatedItemValue(session.items or {})
	end

	-- Check Auctionator availability
	local hasAuctionator = ns.IsAuctionatorAvailable and ns.IsAuctionatorAvailable() or false

	-- Display item value
	if hasAuctionator then
		local valueStr = FormatCopper(itemValue)
		if unpricedCount > 0 then
			valueStr = valueStr .. " (" .. unpricedCount .. " unpriced)"
		end
		itemValueText:SetText("Item Value: " .. valueStr)
	else
		itemValueText:SetText("Item Value: --")
	end

	-- Display estimated gold per hour
	if hasAuctionator and session.activeDuration > 0 then
		local estimatedTotalValue = session.rawGoldDelta + itemValue
		local estimatedGoldPerHour = estimatedTotalValue / session.activeDuration * 3600
		estimatedGoldPerHourText:SetText("Estimated Gold / Hour: " .. FormatCopper(estimatedGoldPerHour))
	else
		estimatedGoldPerHourText:SetText("Estimated Gold / Hour: --")
	end

	-- Display the acquired items from the session
	DisplayAcquiredItems(session.items or {})
end

---
-- Update button states based on current session state
---
local function UpdateButtonState()
	if sessionState == STATE_IDLE then
		startButton:Enable()
		pauseButton:Disable()
		stopButton:Disable()
		pauseButton:SetText("Pause Session")
	elseif sessionState == STATE_RUNNING then
		startButton:Disable()
		pauseButton:Enable()
		stopButton:Enable()
		pauseButton:SetText("Pause Session")
	elseif sessionState == STATE_PAUSED then
		startButton:Disable()
		pauseButton:Enable()
		stopButton:Enable()
		pauseButton:SetText("Resume Session")
	elseif sessionState == STATE_STOPPED then
		startButton:Enable()
		pauseButton:Disable()
		stopButton:Disable()
		pauseButton:SetText("Pause Session")
	end
end

---
-- Cancel the active ticker if it exists
-- Called before transitions to prevent duplicate timers
---
local function StopTicker()
	if activeTicker then
		activeTicker:Cancel()
		activeTicker = nil
	end
end

---
-- Start a new ticker that updates display once per second
-- Only called when transitioning to RUNNING state
---
local function StartTicker()
	StopTicker()
	activeTicker = C_Timer.NewTicker(1, function()
		UpdateElapsedDisplay()
		UpdateLiveMetrics()
	end)
end

---
-- Start Session button handler
-- Initializes a new session through the session-data API
---
local function OnStartSession()
	StopTicker()
	accumulatedElapsed = 0
	segmentStartTime = GetTime()
	sessionState = STATE_RUNNING
	statusText:SetText("Running")
	ClearSessionSummary()

	-- Start session in data module, passing the user-entered route label
	local newSession
	if ns.SessionStart then
		newSession = ns.SessionStart({ routeName = routeEditBox:GetText() })
	end
	zoneContextText:SetText(BuildZoneContextText(newSession))
	SetRouteEditBoxLocked(true)

	UpdateElapsedDisplay()
	UpdateLiveMetrics()
	UpdateButtonState()

	-- Display empty items list initially (will update as items are acquired)
	DisplayAcquiredItems(ns.GetAcquiredItems())

	StartTicker()
end

---
-- Pause/Resume button handler
-- Toggles between RUNNING and PAUSED states
---
local function OnPauseResume()
	if sessionState == STATE_RUNNING then
		-- Pause: accumulate current segment, stop ticker
		accumulatedElapsed = accumulatedElapsed + (GetTime() - segmentStartTime)
		segmentStartTime = nil
		StopTicker()
		sessionState = STATE_PAUSED
		statusText:SetText("Paused")
	elseif sessionState == STATE_PAUSED then
		-- Resume: start new segment, restart ticker
		segmentStartTime = GetTime()
		sessionState = STATE_RUNNING
		statusText:SetText("Running")
		StartTicker()
	end
	UpdateElapsedDisplay()
	UpdateLiveMetrics()
	UpdateButtonState()
end

---
-- Stop Session button handler
-- Finalizes the timer and persists session data
---
local function OnStopSession()
	-- If currently running, accumulate the final segment
	if sessionState == STATE_RUNNING then
		accumulatedElapsed = accumulatedElapsed + (GetTime() - segmentStartTime)
	end
	-- If paused, accumulated is already final

	StopTicker()
	segmentStartTime = nil
	sessionState = STATE_STOPPED
	statusText:SetText("Stopped")
	UpdateElapsedDisplay()
	UpdateButtonState()

	-- Stop session in data module and display summary
	if ns.SessionStop then
		local completedSession = ns.SessionStop(accumulatedElapsed)
		if completedSession and ns.SaveCompletedSession then
			ns.SaveCompletedSession(completedSession)
		end
		DisplaySessionSummary(completedSession)
		zoneContextText:SetText(BuildZoneContextText(completedSession))
	end

	-- Route text remains for the user to reuse the same label on the next session
	SetRouteEditBoxLocked(false)
end

---
-- Create the session UI frame
-- Frame needs to be tall enough for 4 metrics + items display
---
local function CreateSessionFrame()
	sessionFrame = CreateFrame("Frame", "GoldRouteSessionFrame", UIParent, "BackdropTemplate")

	-- Set frame size and position
	sessionFrame:SetSize(360, 500)
	sessionFrame:SetPoint("CENTER", UIParent, "CENTER")

	-- Make frame movable by left-click drag
	sessionFrame:SetMovable(true)
	sessionFrame:SetClampedToScreen(true)
	sessionFrame:EnableMouse(true)
	sessionFrame:RegisterForDrag("LeftButton")
	sessionFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	sessionFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	-- Set frame backdrop appearance
	sessionFrame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	sessionFrame:SetBackdropColor(0, 0, 0, 0.8)
	sessionFrame:SetBackdropBorderColor(1, 1, 1, 1)

	metricEventFrame = CreateFrame("Frame")
	metricEventFrame:RegisterEvent("PLAYER_MONEY")
	metricEventFrame:SetScript("OnEvent", OnMetricEvent)

	-- Title text
	local titleText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("TOP", sessionFrame, "TOP", 0, -10)
	titleText:SetText("GoldRoute")

	-- Status text: Idle, Running, Paused, or Stopped
	statusText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	statusText:SetPoint("TOP", sessionFrame, "TOP", 0, -35)
	statusText:SetText("Idle")

	-- History opens the separate recent-session view.
	historyButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	historyButton:SetSize(75, 25)
	historyButton:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -8, -8)
	historyButton:SetText("History")
	historyButton:SetScript("OnClick", function()
		if ns.ToggleHistoryFrame then
			ns.ToggleHistoryFrame()
		end
	end)

	-- Route label/input: editable only while IDLE or STOPPED (see SetRouteEditBoxLocked)
	routeLabel = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	routeLabel:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 20, -58)
	routeLabel:SetText("Route:")

	routeEditBox = CreateFrame("EditBox", nil, sessionFrame, "InputBoxTemplate")
	routeEditBox:SetAutoFocus(false)
	routeEditBox:SetMaxLetters(50)
	routeEditBox:SetSize(220, 20)
	routeEditBox:SetPoint("LEFT", routeLabel, "RIGHT", 8, -1)
	routeEditBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
	routeEditBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	routeEditBox:SetScript("OnEditFocusGained", function(box)
		if routeEditBoxLocked then
			box:ClearFocus()
		end
	end)

	-- Zone/subzone captured at session start; not refreshed as the player travels
	zoneContextText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	zoneContextText:SetPoint("TOP", sessionFrame, "TOP", 0, -80)
	zoneContextText:SetText("")

	-- Elapsed time display
	elapsedTimeText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	elapsedTimeText:SetPoint("TOP", sessionFrame, "TOP", 0, -104)
	elapsedTimeText:SetText("00:00:00")

	-- Raw Gold metrics text
	rawGoldMetricsText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rawGoldMetricsText:SetPoint("TOP", sessionFrame, "TOP", 0, -129)
	rawGoldMetricsText:SetText("")

	-- Raw Gold / Hour text
	rawGoldPerHourText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rawGoldPerHourText:SetPoint("TOP", sessionFrame, "TOP", 0, -149)
	rawGoldPerHourText:SetText("")

	-- Item Value text
	itemValueText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	itemValueText:SetPoint("TOP", sessionFrame, "TOP", 0, -169)
	itemValueText:SetText("")

	-- Estimated Gold / Hour text
	estimatedGoldPerHourText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	estimatedGoldPerHourText:SetPoint("TOP", sessionFrame, "TOP", 0, -189)
	estimatedGoldPerHourText:SetText("")

	-- Items Acquired header
	itemsHeaderText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	itemsHeaderText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 20, -214)
	itemsHeaderText:SetText("")

	-- Item display strings (up to 8 items + 1 "more" line)
	itemDisplayStrings = {}
	for i = 1, 9 do
		local itemText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		itemText:SetFont("Fonts\\FRIZQT__.TTF", 10)
		itemText:SetJustifyH("LEFT")
		local yOffset = -234 - ((i - 1) * 16)
		itemText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 20, yOffset)
		itemText:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -20, yOffset)
		itemText:SetText("")
		table.insert(itemDisplayStrings, itemText)
	end

	-- Start Session button (left)
	startButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	startButton:SetSize(90, 25)
	startButton:SetPoint("BOTTOMLEFT", sessionFrame, "BOTTOMLEFT", 8, 10)
	startButton:SetText("Start")
	startButton:SetScript("OnClick", OnStartSession)

	-- Pause/Resume button (center)
	pauseButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	pauseButton:SetSize(100, 25)
	pauseButton:SetPoint("BOTTOM", sessionFrame, "BOTTOM", 0, 10)
	pauseButton:SetText("Pause Session")
	pauseButton:SetScript("OnClick", OnPauseResume)
	pauseButton:Disable()

	-- Stop Session button (right)
	stopButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	stopButton:SetSize(90, 25)
	stopButton:SetPoint("BOTTOMRIGHT", sessionFrame, "BOTTOMRIGHT", -8, 10)
	stopButton:SetText("Stop")
	stopButton:SetScript("OnClick", OnStopSession)
	stopButton:Disable()

	-- Start hidden when player logs in
	sessionFrame:Hide()
end

---
-- Toggle session frame visibility
-- Called from Core.lua via /goldroute slash command
---
function ns.ToggleSessionFrame()
	if not sessionFrame then
		CreateSessionFrame()
	end
	sessionFrame:SetShown(not sessionFrame:IsShown())
end

-- Create frame when SessionFrame.lua loads
CreateSessionFrame()
