-- GoldRoute Inventory Tracking
local addonName, ns = ...

local isTracking = false
local baselineSnapshot = {}
local previousSnapshot = {}
local acquiredItems = {}

---
-- Capture the current state of all bags
-- Returns a table: { [itemID] = quantity, ... }
---
local function SnapshotBags()
	local snapshot = {}
	
	-- Scan all bag slots (0 = backpack, 1-4 = main bags)
	for bagID = 0, 4 do
		-- C_Container.GetContainerNumSlots returns number of slots in a bag
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		
		for slotID = 1, numSlots do
			-- C_Container.GetContainerItemInfo returns info about a container item
			local info = C_Container.GetContainerItemInfo(bagID, slotID)
			
			if info then
				local itemID = info.itemID
				local quantity = info.stackCount or 1
				
				if itemID then
					snapshot[itemID] = (snapshot[itemID] or 0) + quantity
				end
			end
		end
	end
	
	return snapshot
end

---
-- Compare current snapshot against previous snapshot
-- Update acquired items with positive deltas
---
local function ProcessAcquisitionDelta()
	local currentSnapshot = SnapshotBags()
	
	-- Check all items in current snapshot
	for itemID, currentCount in pairs(currentSnapshot) do
		local previousCount = previousSnapshot[itemID] or 0
		
		if currentCount > previousCount then
			local gain = currentCount - previousCount
			acquiredItems[itemID] = (acquiredItems[itemID] or 0) + gain
		end
	end
	
	-- Check for items that disappeared (no negative acquisition)
	-- No special handling needed; only positive deltas are tracked
	
	-- Update snapshot for next comparison
	previousSnapshot = currentSnapshot
end

---
-- Event handler for bag updates
---
local function OnBagUpdate()
	if not isTracking then
		return
	end
	
	ProcessAcquisitionDelta()
end

---
-- Start tracking inventory changes for an active session
-- Clear prior state and take initial snapshot
---
function ns.InventoryStartTracking()
	isTracking = true
	acquiredItems = {}
	baselineSnapshot = SnapshotBags()
	previousSnapshot = {}
	
	-- Copy baseline to previous for initial comparison
	for itemID, quantity in pairs(baselineSnapshot) do
		previousSnapshot[itemID] = quantity
	end
	
	-- Register for bag update events
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	eventFrame:SetScript("OnEvent", OnBagUpdate)
	
	-- Store frame reference so we can unregister later
	_G.GoldRouteInventoryEventFrame = eventFrame
end

---
-- Stop tracking inventory and finalize acquired items
-- Return the acquired items table
---
function ns.InventoryStopTracking()
	if isTracking then
		-- Process final bag state before stopping
		ProcessAcquisitionDelta()
	end
	
	isTracking = false
	
	-- Unregister events
	if _G.GoldRouteInventoryEventFrame then
		_G.GoldRouteInventoryEventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
		_G.GoldRouteInventoryEventFrame = nil
	end
	
	-- Return a copy of acquired items
	local result = {}
	for itemID, quantity in pairs(acquiredItems) do
		result[itemID] = quantity
	end
	
	return result
end

---
-- Get currently tracked acquired items
---
function ns.GetAcquiredItems()
	local result = {}
	for itemID, quantity in pairs(acquiredItems) do
		result[itemID] = quantity
	end
	return result
end

---
-- Get item name from itemID
-- Returns item name or a fallback string if info is not available
---
function ns.GetItemName(itemID)
	if not itemID then
		return "Unknown Item"
	end
	
	-- C_Item.GetItemInfo returns cached item information
	local itemInfo = C_Item.GetItemInfo(itemID)
	if itemInfo then
		return itemInfo.itemName or ("Item " .. itemID)
	end
	
	-- If item info is not cached, return fallback
	return "Item " .. itemID
end
