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
local statusText
local elapsedTimeText
local rawGoldText
local goldPerHourText
local itemsHeaderText
local itemDisplayStrings

-- Session timer state
local sessionState = STATE_IDLE
local accumulatedElapsed = 0
local segmentStartTime = nil
local activeTicker = nil

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
-- Clear all session summary display elements
---
local function ClearSessionSummary()
	rawGoldText:SetText("")
	goldPerHourText:SetText("")
	ClearAcquiredItems()
end

---
-- Display session summary after stop
---
local function DisplaySessionSummary(session)
	if not session then
		rawGoldText:SetText("Raw Gold: --")
		goldPerHourText:SetText("Gold / Hour: --")
		ClearAcquiredItems()
		return
	end
	
	local rawGoldStr = FormatCopper(session.rawGoldDelta)
	rawGoldText:SetText("Raw Gold: " .. rawGoldStr)
	
	if session.activeDuration > 0 then
		local goldPerHour = session.rawGoldDelta / session.activeDuration * 3600
		goldPerHourText:SetText("Gold / Hour: " .. FormatCopper(goldPerHour))
	else
		goldPerHourText:SetText("Gold / Hour: --")
	end
	
	DisplayAcquiredItems(session)
end

---
-- Display acquired items from session
-- Shows top 8 items sorted by quantity descending
---
local function DisplayAcquiredItems(session)
	-- Clear all item display strings
	if itemDisplayStrings then
		for i, fontString in ipairs(itemDisplayStrings) do
			fontString:SetText("")
		end
	end
	
	if not session or not session.items then
		itemsHeaderText:SetText("")
		return
	end
	
	-- Collect items into a table for sorting
	local items = {}
	for itemID, quantity in pairs(session.items) do
		table.insert(items, { itemID = itemID, quantity = quantity })
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
		
		local nameA = ns.GetItemName(a.itemID) or "Item " .. a.itemID
		local nameB = ns.GetItemName(b.itemID) or "Item " .. b.itemID
		
		if nameA ~= nameB then
			return nameA < nameB
		end
		
		return a.itemID < b.itemID
	end)
	
	itemsHeaderText:SetText("Items Acquired")
	
	-- Display up to 8 items
	local displayCount = math.min(#items, 8)
	for i = 1, displayCount do
		local item = items[i]
		local itemName = ns.GetItemName(item.itemID) or "Item " .. item.itemID
		local displayText = string.format("%-25s %d", itemName, item.quantity)
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
	UpdateElapsedDisplay()
	UpdateButtonState()
	ClearSessionSummary()
	
	-- Start session in data module
	if ns.SessionStart then
		ns.SessionStart()
	end
	
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
		DisplaySessionSummary(completedSession)
	end
end

---
-- Create the session UI frame
-- Frame is 300x440 to accommodate items display
---
local function CreateSessionFrame()
	sessionFrame = CreateFrame("Frame", "GoldRouteSessionFrame", UIParent, "BackdropTemplate")

	-- Set frame size and position
	sessionFrame:SetSize(300, 440)
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

	-- Title text
	local titleText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("TOP", sessionFrame, "TOP", 0, -10)
	titleText:SetText("GoldRoute")

	-- Status text: Idle, Running, Paused, or Stopped
	statusText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	statusText:SetPoint("TOP", sessionFrame, "TOP", 0, -35)
	statusText:SetText("Idle")

	-- Elapsed time display
	elapsedTimeText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	elapsedTimeText:SetPoint("TOP", sessionFrame, "TOP", 0, -60)
	elapsedTimeText:SetText("00:00:00")

	-- Raw Gold text
	rawGoldText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rawGoldText:SetPoint("TOP", sessionFrame, "TOP", 0, -85)
	rawGoldText:SetText("")

	-- Gold / Hour text
	goldPerHourText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	goldPerHourText:SetPoint("TOP", sessionFrame, "TOP", 0, -105)
	goldPerHourText:SetText("")

	-- Items Acquired header
	itemsHeaderText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	itemsHeaderText:SetPoint("TOP", sessionFrame, "TOP", 0, -130)
	itemsHeaderText:SetText("")

	-- Item display strings (up to 8 items + 1 "more" line)
	itemDisplayStrings = {}
	for i = 1, 9 do
		local itemText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		itemText:SetFont("Fonts\\FRIZQT__.TTF", 10)
		itemText:SetJustifyH("LEFT")
		local yOffset = -150 - ((i - 1) * 16)
		itemText:SetPoint("TOP", sessionFrame, "TOP", -130, yOffset)
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

