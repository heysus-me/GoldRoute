-- GoldRoute - Core addon initialization
-- Standard WoW addon namespace pattern: (addonName, namespace_table)
-- https://wowpedia.fandom.com/wiki/Using_shared_data_across_addons
local addonName, ns = ...

-- Addon metadata
local ADDON_VERSION = "1.0.0"

---
-- Initialize the SavedVariable database
-- SavedVariable 'GoldRouteDB' is declared in the .toc file.
-- It persists across game sessions and is account-wide.
-- https://wowpedia.fandom.com/wiki/SavedVariables
---
local function InitializeDatabase()
	-- Check if GoldRouteDB exists (it will be auto-created by WoW as empty table if not)
	if not GoldRouteDB then
		GoldRouteDB = {}
	end

	-- Initialize db structure on first load
	if not GoldRouteDB.initialized then
		GoldRouteDB.initialized = true
	end

	GoldRouteDB.routes = GoldRouteDB.routes or {}
	GoldRouteDB.sessions = GoldRouteDB.sessions or {}
end

---
-- Slash command handler - toggles session frame, prints addon info, or shows debug
-- Called when user types /goldroute or /goldroute debug
-- https://wowpedia.fandom.com/wiki/SlashCmdList
---
local function OnSlashCommand(msg)
	-- Trim whitespace and convert to lowercase for case-insensitive comparison
	msg = msg and msg:match("^%s*(.-)%s*$"):lower() or ""
	
	-- Handle debug command
	if msg == "debug" then
		if ns.InventoryDebugPrint then
			ns.InventoryDebugPrint()
		end
		if ns.GetSessionHistory then
			print("Saved sessions: " .. #ns.GetSessionHistory())
		end
		local activeSession = ns.GetActiveSession and ns.GetActiveSession()
		if activeSession then
			print("Route: " .. (activeSession.routeName or "(none)"))
			print("Zone: " .. (activeSession.zone or "(none)"))
			print("Subzone: " .. (activeSession.subzone or "(none)"))
			print("Map ID: " .. (activeSession.mapID and tostring(activeSession.mapID) or "(none)"))
		end
		return
	end
	
	-- Default behavior: print version and toggle session frame
	-- print() writes to the default chat frame
	-- https://wowpedia.fandom.com/wiki/API_print
	print(addonName .. " v" .. ADDON_VERSION)
	-- Toggle session frame from SessionFrame.lua
	if ns.ToggleSessionFrame then
		ns.ToggleSessionFrame()
	end
end

---
-- Register the slash command
-- SLASH_<COMMAND>N where N is 1, 2, 3... for multiple slash commands
-- SlashCmdList.<COMMAND> = function to call when slash command is used
-- https://wowpedia.fandom.com/wiki/SlashCmdList
---
SLASH_GOLDROUTE1 = "/goldroute"
SlashCmdList.GOLDROUTE = OnSlashCommand

---
-- Event frame setup
-- CreateFrame() creates an invisible frame for event handling
-- https://wowpedia.fandom.com/wiki/API_CreateFrame
---
local eventFrame = CreateFrame("Frame")

---
-- Register for ADDON_LOADED event
-- ADDON_LOADED fires when an addon finishes loading
-- https://wowpedia.fandom.com/wiki/ADDON_LOADED
---
eventFrame:RegisterEvent("ADDON_LOADED")

---
-- Set the event handler script
-- SetScript("OnEvent", func) runs func(self, event, ...) when event fires
-- https://wowpedia.fandom.com/wiki/API_Frame_SetScript
---
eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
	-- Verify this event is ADDON_LOADED and it's loading our addon
	if event == "ADDON_LOADED" and loadedAddon == addonName then
		-- Initialize the SavedVariable database
		InitializeDatabase()
		
		-- Unregister this event since we only need it once
		-- https://wowpedia.fandom.com/wiki/API_Frame_UnregisterEvent
		eventFrame:UnregisterEvent("ADDON_LOADED")
	end
end)
