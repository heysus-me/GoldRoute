-- GoldLedger native minimap button (no LibDataBroker/LibDBIcon dependency)
local addonName, ns = ...

local minimapButton
local RADIUS = 80

---
-- Persist the button's angle around the minimap circumference
---
local function SaveMinimapButtonAngle(angle)
	GoldLedgerDB.minimap = GoldLedgerDB.minimap or {}
	GoldLedgerDB.minimap.angle = angle
end

---
-- Reposition the button on the minimap edge using the saved angle
-- x = cos(angle) * radius, y = sin(angle) * radius (standard polar placement)
---
local function UpdateMinimapButtonPosition()
	if not minimapButton then
		return
	end

	local angle = (GoldLedgerDB and GoldLedgerDB.minimap and GoldLedgerDB.minimap.angle) or 220
	local radians = math.rad(angle)
	local x = math.cos(radians) * RADIUS
	local y = math.sin(radians) * RADIUS

	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

---
-- Determine the angle (degrees) of the cursor relative to the minimap center
---
local function GetAngleFromCursor()
	local minimapX, minimapY = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale

	return math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX))
end

---
-- Create the circular minimap button (native frames only)
---
local function CreateMinimapButton()
	if minimapButton then
		return minimapButton
	end

	minimapButton = CreateFrame("Button", "GoldLedgerMinimapButton", Minimap)
	minimapButton:SetSize(31, 31)
	minimapButton:SetFrameStrata("MEDIUM")
	minimapButton:SetFrameLevel(8)
	minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapButton:RegisterForDrag("LeftButton")

	-- Coin icon cropped so the border overlay reads as a circular button
	local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	minimapButton.icon = icon

	local border = minimapButton:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

	minimapButton:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", function()
			SaveMinimapButtonAngle(GetAngleFromCursor())
			UpdateMinimapButtonPosition()
		end)
	end)

	minimapButton:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		-- Deferred so a click that immediately follows the drag release is still ignored
		C_Timer.After(0, function() self.dragging = false end)
	end)

	minimapButton:SetScript("OnClick", function(self, button)
		-- Ignore the click that immediately follows a drag release
		if self.dragging then
			return
		end

		if button == "LeftButton" then
			if ns.ToggleSessionFrame then
				ns.ToggleSessionFrame()
			end
		elseif button == "RightButton" then
			if ns.ToggleHistoryFrame then
				ns.ToggleHistoryFrame()
			end
		end
	end)

	minimapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("GoldLedger")
		GameTooltip:AddLine("Left-click: Toggle tracker", 1, 1, 1)
		GameTooltip:AddLine("Right-click: Toggle history", 1, 1, 1)
		GameTooltip:Show()
	end)
	minimapButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return minimapButton
end

---
-- Create (if needed) and position the minimap button
-- Called from Core.lua once GoldLedgerDB.minimap has been initialized
---
function ns.InitializeMinimapButton()
	if not Minimap then
		return
	end

	CreateMinimapButton()
	UpdateMinimapButtonPosition()
	minimapButton:Show()
end
