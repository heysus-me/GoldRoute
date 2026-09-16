-- GoldLedger - Core addon initialization
-- Standard WoW addon namespace pattern: (addonName, namespace_table)
-- https://wowpedia.fandom.com/wiki/Using_shared_data_across_addons
local addonName, ns = ...

-- Addon metadata
local ADDON_VERSION = "1.0.0"

---
-- Migrate legacy GoldRouteDB data to GoldLedgerDB
-- Preserves all session history and settings
-- GoldLedgerDB takes precedence; only missing fields are populated from GoldRouteDB
---
local function MigrateLegacyDatabase()
	-- Ensure GoldLedgerDB exists
	if not GoldLedgerDB then
		GoldLedgerDB = {}
	end

	-- If GoldRouteDB exists and has data, migrate it
	if GoldRouteDB and type(GoldRouteDB) == "table" then
		-- Migrate basic fields if missing
		if not GoldLedgerDB.initialized and GoldRouteDB.initialized then
			GoldLedgerDB.initialized = GoldRouteDB.initialized
		end

		-- Migrate routes if missing
		if not GoldLedgerDB.routes and GoldRouteDB.routes then
			GoldLedgerDB.routes = GoldRouteDB.routes
		end

		-- Migrate sessions if missing (most important for history preservation)
		if not GoldLedgerDB.sessions and GoldRouteDB.sessions then
			GoldLedgerDB.sessions = GoldRouteDB.sessions
		end

		-- Migrate minimap settings if missing
		if not GoldLedgerDB.minimap and GoldRouteDB.minimap then
			GoldLedgerDB.minimap = GoldRouteDB.minimap
		end

		-- Mark migration as complete (one-time operation)
		GoldLedgerDB.schemaVersion = 1
		GoldLedgerDB.migratedFromGoldRoute = true
	end
end

---
-- Initialize the SavedVariable database
-- SavedVariables 'GoldLedgerDB' and 'GoldRouteDB' are declared in the .toc file.
-- They persist across game sessions and are account-wide.
-- https://wowpedia.fandom.com/wiki/SavedVariables
---
local function InitializeDatabase()
	-- Migrate legacy GoldRouteDB if present
	MigrateLegacyDatabase()

	-- Ensure GoldLedgerDB is properly initialized
	if not GoldLedgerDB then
		GoldLedgerDB = {}
	end

	-- Initialize db structure on first load
	if not GoldLedgerDB.initialized then
		GoldLedgerDB.initialized = true
	end

	GoldLedgerDB.routes = GoldLedgerDB.routes or {}
	GoldLedgerDB.sessions = GoldLedgerDB.sessions or {}

	-- Minimap button position (angle in degrees around the minimap circumference)
	GoldLedgerDB.minimap = GoldLedgerDB.minimap or {}
	if type(GoldLedgerDB.minimap.angle) ~= "number" then
		GoldLedgerDB.minimap.angle = 220
	end

	-- Initialize schema version if not present
	if not GoldLedgerDB.schemaVersion then
		GoldLedgerDB.schemaVersion = 1
	end
end

---
-- Slash command handler - toggles session frame, prints addon info, or shows debug
-- Called when user types /goldledger, /goldroute, or either variant with debug argument
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
-- Register the slash commands
-- SLASH_<COMMAND>N where N is 1, 2, 3... for multiple slash commands
-- SlashCmdList.<COMMAND> = function to call when slash command is used
-- https://wowpedia.fandom.com/wiki/SlashCmdList
-- Primary command is /goldledger; /goldroute is a legacy alias
---
SLASH_GOLDLEDGER1 = "/goldledger"
SLASH_GOLDLEDGER2 = "/goldroute"
SlashCmdList.GOLDLEDGER = OnSlashCommand

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

		-- Create/position the minimap button now that GoldLedgerDB.minimap is ready
		if ns.InitializeMinimapButton then
			ns.InitializeMinimapButton()
		end

		-- Unregister this event since we only need it once
		-- https://wowpedia.fandom.com/wiki/API_Frame_UnregisterEvent
		eventFrame:UnregisterEvent("ADDON_LOADED")
	end
end)
