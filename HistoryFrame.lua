-- GoldLedger recent session history view
local addonName, ns = ...

local historyFrame
local historyRows = {}

local function FormatCopper(copper)
	if type(copper) ~= "number" then
		return "--"
	end

	copper = math.floor(copper + (copper >= 0 and 0.5 or -0.5))
	local isNegative = copper < 0
	copper = math.abs(copper)
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local copperRemain = copper % 100
	local parts = {}
	if gold > 0 then table.insert(parts, gold .. "g") end
	if silver > 0 then table.insert(parts, silver .. "s") end
	if copperRemain > 0 or #parts == 0 then table.insert(parts, copperRemain .. "c") end
	local result = table.concat(parts, " ")
	return isNegative and "-" .. result or result
end

local function FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60
	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
	end
	return string.format("%02dm %02ds", minutes, remainingSeconds)
end

local function FormatDate(timestamp)
	if type(timestamp) ~= "number" then
		return "Unknown date"
	end
	return date("%m/%d %H:%M", timestamp)
end

---
-- Combine zone + subzone into one line; subzone supplements the zone, never replaces it
---
local function FormatZoneLine(zone, subzone)
	if type(zone) ~= "string" or zone == "" then
		return nil
	end
	if type(subzone) == "string" and subzone ~= "" and subzone ~= zone then
		return zone .. " \226\128\148 " .. subzone
	end
	return zone
end

---
-- Resolve the primary/secondary context lines for a saved session.
-- Fallback order: routeName, then zone, then a generic placeholder.
-- Older saved sessions may be missing these fields entirely; treat them as optional.
---
local function GetSessionContextLines(session)
	local routeName = type(session.routeName) == "string" and session.routeName ~= "" and session.routeName or nil
	local zoneLine = FormatZoneLine(session.zone, session.subzone)

	if routeName then
		return routeName, zoneLine
	elseif zoneLine then
		return zoneLine, nil
	end
	return "Unlabeled Session", nil
end

local function UpdateRows()
	if not historyFrame then
		return
	end

	for _, row in ipairs(historyRows) do
		row:SetText("")
	end

	local sessions = ns.GetRecentSessions and ns.GetRecentSessions(10) or {}
	if #sessions == 0 then
		historyRows[1]:SetText("No completed sessions yet.")
		return
	end

	for index, session in ipairs(sessions) do
		local character = session.character or "Unknown"
		local value = FormatCopper(session.estimatedTotalValue)
		local gph = FormatCopper(session.estimatedGoldPerHour)
		local primaryContext, secondaryContext = GetSessionContextLines(session)

		local lines = {
			string.format("%s  %s", FormatDate(session.endedAt or session.startedAt), character),
			primaryContext,
		}
		if secondaryContext then
			table.insert(lines, secondaryContext)
		end
		table.insert(lines, string.format("%s    Value: %s    GPH: %s", FormatDuration(session.activeDuration), value, gph))

		historyRows[index]:SetText(table.concat(lines, "\n"))
	end
end

function ns.RefreshHistoryFrame()
	if historyFrame and historyFrame:IsShown() then
		UpdateRows()
	end
end

function ns.ToggleHistoryFrame()
	if not historyFrame then
		return
	end

	if historyFrame:IsShown() then
		historyFrame:Hide()
	else
		UpdateRows()
		historyFrame:Show()
	end
end

local function CreateHistoryFrame()
	historyFrame = CreateFrame("Frame", "GoldLedgerHistoryFrame", UIParent, "BackdropTemplate")
	historyFrame:SetSize(340, 560)
	historyFrame:SetPoint("CENTER", UIParent, "CENTER", 380, 0)
	historyFrame:SetMovable(true)
	historyFrame:SetClampedToScreen(true)
	historyFrame:EnableMouse(true)
	historyFrame:RegisterForDrag("LeftButton")
	historyFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	historyFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	historyFrame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	historyFrame:SetBackdropColor(0, 0, 0, 0.8)
	historyFrame:SetBackdropBorderColor(1, 1, 1, 1)

	local title = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", historyFrame, "TOP", 0, -12)
	title:SetText("Recent Sessions")

	local closeButton = CreateFrame("Button", nil, historyFrame, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", historyFrame, "TOPRIGHT", -2, -2)

	for index = 1, 10 do
		local row = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row:SetFont("Fonts\\FRIZQT__.TTF", 10)
		row:SetJustifyH("LEFT")
		row:SetWordWrap(true)
		row:SetPoint("TOPLEFT", historyFrame, "TOPLEFT", 18, -38 - ((index - 1) * 50))
		row:SetPoint("TOPRIGHT", historyFrame, "TOPRIGHT", -18, -38 - ((index - 1) * 50))
		table.insert(historyRows, row)
	end

	historyFrame:Hide()
	UpdateRows()
end

CreateHistoryFrame()
