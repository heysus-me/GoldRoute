-- GoldRoute Session Frame - UI and session timer management
local addonName, ns = ...

local sessionFrame
local sessionActive = false
local sessionStartTime = nil

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
-- Update the elapsed time display once per second
-- Uses C_Timer.After to schedule next update
-- https://wowpedia.fandom.com/wiki/C_Timer.After
---
local function UpdateElapsedTime()
	if not sessionActive or not sessionStartTime then
		return
	end

	local elapsed = GetTime() - sessionStartTime
	ns.elapsedTimeText:SetText(FormatTime(elapsed))

	-- Schedule next update in 1 second
	C_Timer.After(1, UpdateElapsedTime)
end

---
-- Start session button handler
-- Stores current time, enables stop button, begins timer updates
---
local function StartSession()
	sessionActive = true
	sessionStartTime = GetTime()
	ns.statusText:SetText("Running")
	ns.elapsedTimeText:SetText("00:00:00")
	ns.startButton:Disable()
	ns.stopButton:Enable()
	UpdateElapsedTime()
end

---
-- Stop session button handler
-- Stops timer, preserves elapsed time on screen
---
local function StopSession()
	sessionActive = false
	ns.statusText:SetText("Stopped")
	ns.startButton:Enable()
	ns.stopButton:Disable()
end

---
-- Create the session UI frame
-- Frame is 300x180, movable, clamped to screen
-- https://wowpedia.fandom.com/wiki/API_CreateFrame
---
local function CreateSessionFrame()
	-- BackdropTemplate provides standard Retail frame styling
	sessionFrame = CreateFrame("Frame", "GoldRouteSessionFrame", UIParent, "BackdropTemplate")

	-- Set frame size and position
	sessionFrame:SetSize(300, 180)
	sessionFrame:SetPoint("CENTER", UIParent, "CENTER")

	-- Make frame movable by left-click drag
	-- https://wowpedia.fandom.com/wiki/API_Frame_SetMovable
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

	-- Status text: Idle, Running, or Stopped
	-- https://wowpedia.fandom.com/wiki/API_Frame_CreateFontString
	ns.statusText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ns.statusText:SetPoint("TOP", sessionFrame, "TOP", 0, -35)
	ns.statusText:SetText("Idle")

	-- Elapsed time display
	ns.elapsedTimeText = sessionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ns.elapsedTimeText:SetPoint("TOP", sessionFrame, "TOP", 0, -60)
	ns.elapsedTimeText:SetText("00:00:00")

	-- Start Session button
	-- GameMenuButtonTemplate provides standard WoW button styling
	ns.startButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	ns.startButton:SetSize(120, 25)
	ns.startButton:SetPoint("BOTTOMLEFT", sessionFrame, "BOTTOMLEFT", 10, 10)
	ns.startButton:SetText("Start Session")
	ns.startButton:SetScript("OnClick", StartSession)

	-- Stop Session button (disabled until session starts)
	ns.stopButton = CreateFrame("Button", nil, sessionFrame, "GameMenuButtonTemplate")
	ns.stopButton:SetSize(120, 25)
	ns.stopButton:SetPoint("BOTTOMRIGHT", sessionFrame, "BOTTOMRIGHT", -10, 10)
	ns.stopButton:SetText("Stop Session")
	ns.stopButton:SetScript("OnClick", StopSession)
	ns.stopButton:Disable()

	-- Start hidden when player logs in
	-- https://wowpedia.fandom.com/wiki/API_Frame_Hide
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
	-- SetShown() shows/hides based on boolean argument
	-- https://wowpedia.fandom.com/wiki/API_Frame_SetShown
	sessionFrame:SetShown(not sessionFrame:IsShown())
end

-- Create frame when SessionFrame.lua loads
CreateSessionFrame()
