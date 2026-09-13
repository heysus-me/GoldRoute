-- GoldRoute Inventory Tracking
local addonName, ns = ...

local isTracking = false
local baselineSnapshot = {}
local previousSnapshot = {}
local acquiredItems = {}

-- Module-local event frame for bag updates
local eventFrame = CreateFrame("Frame")

-- Bag IDs to track in player inventory
-- 0 = backpack, 1-4 = equipped bags, 5 = reagent bag
local TRACKED_BAGS = {0, 1, 2, 3, 4, 5}

---
-- Capture the current state of all tracked bags
-- Returns a table: { [itemID] = quantity, ... }
---
local function SnapshotBags()
	local snapshot = {}
	
	-- Scan all tracked bags (backpack, main bags, reagent bag)
	for _, bagID in ipairs(TRACKED_BAGS) do
		-- C_Container.GetContainerNumSlots returns number of slots in a bag
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		
		-- Skip bags with zero slots (not available)
		if numSlots and numSlots > 0 then
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
	
	-- Register for bag update events (reuse module-local frame)
	eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
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
	eventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
	
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

---
-- Debug print: show current inventory tracking state
-- Called by Core.lua when user runs /goldroute debug
---
function ns.InventoryDebugPrint()
	print("GoldRoute inventory tracking: " .. tostring(isTracking))
	
	local count = 0
	for _ in pairs(acquiredItems) do
		count = count + 1
	end
	
	print("Acquired item types: " .. count)
	
	if count > 0 then
		-- Sort items by ID for consistent output
		local itemList = {}
		for itemID, quantity in pairs(acquiredItems) do
			table.insert(itemList, {id = itemID, qty = quantity})
		end
		table.sort(itemList, function(a, b) return a.id < b.id end)
		
		for _, item in ipairs(itemList) do
			print("Item " .. item.id .. ": " .. item.qty)
		end
	end
end

-- Set up event handler for the module-local event frame
eventFrame:SetScript("OnEvent", OnBagUpdate)
