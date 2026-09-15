-- GoldRoute Session Frame - UI and session timer management
local addonName, ns = ...

-- Session states
local STATE_IDLE = "IDLE"
local STATE_RUNNING = "RUNNING"
local STATE_PAUSED = "PAUSED"
local STATE_STOPPED = "STOPPED"

-- Compact frame dimensions (see SetItemsExpanded for collapsed/expanded height)
local FRAME_WIDTH = 312
local COLLAPSED_HEIGHT = 248
local ITEMS_ROW_HEIGHT = 12
local ITEMS_ROW_COUNT = 9 -- 8 items + "+X more" line
local ITEMS_LIST_HEIGHT = 6 + (ITEMS_ROW_COUNT * ITEMS_ROW_HEIGHT)
local EXPANDED_HEIGHT = COLLAPSED_HEIGHT + ITEMS_LIST_HEIGHT + 20

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
local timerText
local estGPHLabelText
local estGPHValueText
local itemValueLabelText
local itemValueValueText
local rawGoldLabelText
local rawGoldValueText
local rawGPHLabelText
local rawGPHValueText
local itemsHeaderText
local itemsToggleButton
local itemsListFrame
local itemDisplayStrings
local metricEventFrame

-- Session timer state
local sessionState = STATE_IDLE
local accumulatedElapsed = 0
local segmentStartTime = nil
local activeTicker = nil
local routeEditBoxLocked = false
local itemsExpanded = false

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
-- Build the compact zone/subzone contextual line: "Zone — Subzone"
-- Returns "" when no zone was captured (e.g. very old sessions)
---
local function BuildZoneContextText(session)
	if not session or not session.zone then
		return ""
	end

	if session.subzone and session.subzone ~= session.zone then
		return session.zone .. " \226\128\148 " .. session.subzone
	end

	return session.zone
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
-- Show/hide the acquired-items list and resize the frame to match.
-- Collapsed by default each time the UI loads; not persisted to SavedVariables.
---
local function SetItemsExpanded(expanded)
	itemsExpanded = expanded
	itemsListFrame:SetShown(expanded)
	itemsToggleButton:SetText(expanded and "-" or "+")
	sessionFrame:SetHeight(expanded and EXPANDED_HEIGHT or COLLAPSED_HEIGHT)
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
	timerText:SetText(FormatTime(GetElapsedTime()))
end

---
-- Render the acquired-items rows and update the "Items (N)" header count.
-- Runs regardless of expand/collapse state so the count/rows stay current;
-- only the container's visibility (see SetItemsExpanded) hides the rows.
---
local function RenderAcquiredItems(itemsTable)
	for _, fontString in ipairs(itemDisplayStrings) do
		fontString:SetText("")
	end

	-- Only include valid items: numeric itemID, numeric quantity > 0
	local items = {}
	if type(itemsTable) == "table" then
		for itemID, quantity in pairs(itemsTable) do
			if type(itemID) == "number" and type(quantity) == "number" and quantity > 0 then
				table.insert(items, { itemID = itemID, quantity = quantity })
			end
		end
	end

	itemsHeaderText:SetText(string.format("Items (%d)", #items))

	if #items == 0 then
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

	-- Display up to 8 items with pricing
	local displayCount = math.min(#items, 8)
	for i = 1, displayCount do
		local item = items[i]
		local itemName = ns.GetItemName(item.itemID) or ("Item " .. item.itemID)

		local unitPrice = ns.GetItemMarketPrice and ns.GetItemMarketPrice(item.itemID) or nil
		local itemTotalValue = unitPrice and (unitPrice * item.quantity) or nil

		local displayText
		if itemTotalValue then
			displayText = itemName .. " x" .. item.quantity .. "   " .. FormatCopper(itemTotalValue)
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
-- Update all live session metrics
-- Called every second by ticker and immediately on state changes
-- Updates: Estimated Gold/Hour, Item Value, Raw Gold, Raw Gold/Hour
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

	-- Raw Gold
	if liveRawGold then
		rawGoldValueText:SetText(FormatCopper(liveRawGold))
	else
		rawGoldValueText:SetText("0c")
	end

	-- Raw Gold / Hour (avoid division by zero)
	if liveRawGold and elapsedTime > 0 then
		rawGPHValueText:SetText(FormatCopper(liveRawGold / elapsedTime * 3600))
	else
		rawGPHValueText:SetText("--")
	end

	-- Item Value (show -- if Auctionator unavailable)
	if hasAuctionator then
		local valueStr = FormatCopper(itemValue)
		if unpricedCount > 0 then
			valueStr = valueStr .. " (" .. unpricedCount .. " unpriced)"
		end
		itemValueValueText:SetText(valueStr)
	else
		itemValueValueText:SetText("--")
	end

	-- Estimated Gold / Hour
	if hasAuctionator and elapsedTime > 0 then
		local liveRawGoldVal = liveRawGold or 0
		local estimatedTotalValue = liveRawGoldVal + itemValue
		estGPHValueText:SetText(FormatCopper(estimatedTotalValue / elapsedTime * 3600))
	else
		estGPHValueText:SetText("--")
	end
end

local function OnMetricEvent(_, event)
	if event == "PLAYER_MONEY" and (sessionState == STATE_RUNNING or sessionState == STATE_PAUSED) then
		UpdateLiveMetrics()
	end
end

---
-- Refresh live acquired items display during active session
-- Called by Inventory.lua when items are acquired during RUNNING or PAUSED state
---
function ns.RefreshLiveItems()
	if sessionState == STATE_RUNNING or sessionState == STATE_PAUSED then
		local items = ns.GetAcquiredItems and ns.GetAcquiredItems() or {}
		RenderAcquiredItems(items)
		UpdateLiveMetrics()
	end
end

---
-- Clear all session summary display elements
---
local function ClearSessionSummary()
	estGPHValueText:SetText("--")
	itemValueValueText:SetText("--")
	rawGoldValueText:SetText("--")
	rawGPHValueText:SetText("--")
	RenderAcquiredItems(nil)
end

---
-- Display session summary after stop
---
local function DisplaySessionSummary(session)
	if not session then
		estGPHValueText:SetText("--")
		itemValueValueText:SetText("--")
		rawGoldValueText:SetText("--")
		rawGPHValueText:SetText("--")
		RenderAcquiredItems(nil)
		return
	end

	-- Display finalized raw gold
	rawGoldValueText:SetText(FormatCopper(session.rawGoldDelta))

	-- Display finalized raw gold per hour
	if session.activeDuration > 0 then
		rawGPHValueText:SetText(FormatCopper(session.rawGoldDelta / session.activeDuration * 3600))
	else
		rawGPHValueText:SetText("--")
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
		itemValueValueText:SetText(valueStr)
	else
		itemValueValueText:SetText("--")
	end

	-- Display estimated gold per hour
	if hasAuctionator and session.activeDuration > 0 then
		local estimatedTotalValue = session.rawGoldDelta + itemValue
		estGPHValueText:SetText(FormatCopper(estimatedTotalValue / session.activeDuration * 3600))
	else
		estGPHValueText:SetText("--")
	end

	-- Display the acquired items from the session
	RenderAcquiredItems(session.items or {})
end

---
-- Update button states based on current session state
---
local function UpdateButtonState()
	if sessionState == STATE_IDLE then
		startButton:Enable()
		pauseButton:Disable()
		stopButton:Disable()
		pauseButton:SetText("Pause")
	elseif sessionState == STATE_RUNNING then
		startButton:Disable()
		pauseButton:Enable()
		stopButton:Enable()
		pauseButton:SetText("Pause")
	elseif sessionState == STATE_PAUSED then
		startButton:Disable()
		pauseButton:Enable()
		stopButton:Enable()
		pauseButton:SetText("Resume")
	elseif sessionState == STATE_STOPPED then
		startButton:Enable()
		pauseButton:Disable()
		stopButton:Disable()
		pauseButton:SetText("Pause")
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
	RenderAcquiredItems(ns.GetAcquiredItems())

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
-- Create the compact session UI frame
---
local function CreateSessionFrame()
	sessionFrame = CreateFrame("Frame", "GoldRouteSessionFrame", UIParent, "BackdropTemplate")

	-- Set frame size and position
	sessionFrame:SetSize(FRAME_WIDTH, COLLAPSED_HEIGHT)
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

	-- Title row: addon name (left) + current state (right)
	local titleText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -10)
	titleText:SetText("GoldRoute")

	statusText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -14, -12)
	statusText:SetText("Idle")

	-- Route label/input: editable only while IDLE or STOPPED (see SetRouteEditBoxLocked)
	routeLabel = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	routeLabel:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -30)
	routeLabel:SetText("Route:")

	routeEditBox = CreateFrame("EditBox", nil, sessionFrame, "InputBoxTemplate")
	routeEditBox:SetAutoFocus(false)
	routeEditBox:SetMaxLetters(50)
	routeEditBox:SetSize(FRAME_WIDTH - 90, 18)
	routeEditBox:SetPoint("LEFT", routeLabel, "RIGHT", 6, -1)
	routeEditBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
	routeEditBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	routeEditBox:SetScript("OnEditFocusGained", function(box)
		if routeEditBoxLocked then
			box:ClearFocus()
		end
	end)

	-- Zone/subzone captured at session start; not refreshed as the player travels
	zoneContextText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	zoneContextText:SetPoint("TOP", sessionFrame, "TOP", 0, -48)
	zoneContextText:SetWidth(FRAME_WIDTH - 28)
	zoneContextText:SetWordWrap(false)
	zoneContextText:SetText("")

	-- Timer: always visible, centered
	timerText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	timerText:SetPoint("TOP", sessionFrame, "TOP", 0, -68)
	timerText:SetText("00:00:00")

	-- Estimated Gold/Hour: the primary metric ("how much gold/hour is this producing?")
	estGPHLabelText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	estGPHLabelText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -92)
	estGPHLabelText:SetText("Est. GPH")
	estGPHLabelText:SetTextColor(1, 0.82, 0)

	estGPHValueText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	estGPHValueText:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -14, -92)
	estGPHValueText:SetText("--")
	estGPHValueText:SetTextColor(1, 0.82, 0)

	-- Secondary metrics: Item Value, Raw Gold, Raw Gold/Hour
	itemValueLabelText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	itemValueLabelText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -114)
	itemValueLabelText:SetText("Item Value")

	itemValueValueText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	itemValueValueText:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -14, -114)
	itemValueValueText:SetText("--")

	rawGoldLabelText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rawGoldLabelText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -130)
	rawGoldLabelText:SetText("Raw Gold")

	rawGoldValueText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rawGoldValueText:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -14, -130)
	rawGoldValueText:SetText("--")

	rawGPHLabelText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rawGPHLabelText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -146)
	rawGPHLabelText:SetText("Raw GPH")

	rawGPHValueText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rawGPHValueText:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -14, -146)
	rawGPHValueText:SetText("--")

	-- Start / Pause / Stop buttons
	startButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	startButton:SetSize(70, 22)
	startButton:SetPoint("TOP", sessionFrame, "TOP", -80, -170)
	startButton:SetText("Start")
	startButton:SetScript("OnClick", OnStartSession)

	pauseButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	pauseButton:SetSize(75, 22)
	pauseButton:SetPoint("TOP", sessionFrame, "TOP", 0, -170)
	pauseButton:SetText("Pause")
	pauseButton:SetScript("OnClick", OnPauseResume)
	pauseButton:Disable()

	stopButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	stopButton:SetSize(70, 22)
	stopButton:SetPoint("TOP", sessionFrame, "TOP", 80, -170)
	stopButton:SetText("Stop")
	stopButton:SetScript("OnClick", OnStopSession)
	stopButton:Disable()

	-- Items header: collapsible acquired-item breakdown (collapsed by default)
	itemsHeaderText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	itemsHeaderText:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -198)
	itemsHeaderText:SetText("Items (0)")

	itemsToggleButton = CreateFrame("Button", nil, sessionFrame, "UIPanelButtonTemplate")
	itemsToggleButton:SetSize(22, 18)
	itemsToggleButton:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -12, -196)
	itemsToggleButton:SetText("+")
	itemsToggleButton:SetScript("OnClick", function() SetItemsExpanded(not itemsExpanded) end)

	itemsListFrame = CreateFrame("Frame", nil, sessionFrame)
	itemsListFrame:SetPoint("TOPLEFT", sessionFrame, "TOPLEFT", 14, -216)
	itemsListFrame:SetPoint("TOPRIGHT", sessionFrame, "TOPRIGHT", -14, -216)
	itemsListFrame:SetHeight(ITEMS_LIST_HEIGHT)

	-- Item display strings (up to 8 items + 1 "more" line), inside the collapsible container
	itemDisplayStrings = {}
	for i = 1, ITEMS_ROW_COUNT do
		local itemText = itemsListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		itemText:SetFont("Fonts\\FRIZQT__.TTF", 10)
		itemText:SetJustifyH("LEFT")
		local yOffset = -((i - 1) * ITEMS_ROW_HEIGHT)
		itemText:SetPoint("TOPLEFT", itemsListFrame, "TOPLEFT", 0, yOffset)
		itemText:SetPoint("TOPRIGHT", itemsListFrame, "TOPRIGHT", 0, yOffset)
		itemText:SetText("")
		table.insert(itemDisplayStrings, itemText)
	end

	-- History opens the separate recent-session view. Anchored to the frame's
	-- bottom edge so it stays in place whether the item list is expanded or not.
	historyButton = CreateFrame("Button", nil, sessionFrame, "UIPanelButtonTemplate")
	historyButton:SetSize(90, 20)
	historyButton:SetPoint("BOTTOM", sessionFrame, "BOTTOM", 0, 8)
	historyButton:SetText("History")
	historyButton:SetScript("OnClick", function()
		if ns.ToggleHistoryFrame then
			ns.ToggleHistoryFrame()
		end
	end)

	-- Collapsed by default each time the frame is created
	SetItemsExpanded(false)

	-- Start hidden when player logs in
	sessionFrame:Hide()
end

---
-- Toggle session frame visibility
-- Called from Core.lua via /goldroute slash command and from the minimap button
---
function ns.ToggleSessionFrame()
	if not sessionFrame then
		CreateSessionFrame()
	end
	sessionFrame:SetShown(not sessionFrame:IsShown())
end

-- Create frame when SessionFrame.lua loads
CreateSessionFrame()

