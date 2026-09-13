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
-- Initializes a new session from scratch
---
local function OnStartSession()
	StopTicker()
	accumulatedElapsed = 0
	segmentStartTime = GetTime()
	sessionState = STATE_RUNNING
	statusText:SetText("Running")
	UpdateElapsedDisplay()
	UpdateButtonState()
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
-- Finalizes the session and returns to idle
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
end

---
-- Create the session UI frame
-- Frame is 300x180, movable, clamped to screen
---
local function CreateSessionFrame()
	sessionFrame = CreateFrame("Frame", "GoldRouteSessionFrame", UIParent, "BackdropTemplate")

	-- Set frame size and position
	sessionFrame:SetSize(300, 180)
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
