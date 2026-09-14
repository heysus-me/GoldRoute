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
	local hasPositiveDelta = false
	for itemID, currentCount in pairs(currentSnapshot) do
		local previousCount = previousSnapshot[itemID] or 0
		
		if currentCount > previousCount then
			local gain = currentCount - previousCount
			acquiredItems[itemID] = (acquiredItems[itemID] or 0) + gain
			hasPositiveDelta = true
		end
	end
	
	-- Check for items that disappeared (no negative acquisition)
	-- No special handling needed; only positive deltas are tracked
	
	-- Update snapshot for next comparison
	previousSnapshot = currentSnapshot
	
	-- Notify UI of live item updates if any positive delta detected
	if hasPositiveDelta and ns.RefreshLiveItems then
		ns.RefreshLiveItems()
	end
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
-- C_Item.GetItemInfo returns multiple values; first return is the item name string
-- May return nil if item info is not cached; caller should handle gracefully
---
function ns.GetItemName(itemID)
	if not itemID then
		return nil
	end
	
	-- C_Item.GetItemInfo returns (itemName, itemLink, itemRarity, itemLevel, ...)
	-- We only need the first return value
	local itemName = C_Item.GetItemInfo(itemID)
	
	-- Return the name if available, otherwise nil (caller will use fallback)
	return itemName
end

---
-- Debug print: show current inventory tracking state
-- Called by Core.lua when user runs /goldroute debug
---
function ns.InventoryDebugPrint()
	print("GoldRoute inventory tracking: " .. tostring(isTracking))
	
	local itemList = {}
	for itemID, quantity in pairs(acquiredItems) do
		table.insert(itemList, {id = itemID, qty = quantity})
	end
	table.sort(itemList, function(a, b) return a.id < b.id end)
	print("Acquired item types: " .. #itemList)

	local totalItemValue = 0
	for _, item in ipairs(itemList) do
		local itemName = ns.GetItemName(item.id)
		local unitPrice = ns.GetItemMarketPrice and ns.GetItemMarketPrice(item.id) or nil
		local priceDisplay = "(no price)"
		
		if unitPrice then
			local gold = math.floor(unitPrice / 10000)
			local silver = math.floor((unitPrice % 10000) / 100)
			local copperRemain = unitPrice % 100
			local parts = {}
			if gold > 0 then table.insert(parts, gold .. "g") end
			if silver > 0 then table.insert(parts, silver .. "s") end
			if copperRemain > 0 or #parts == 0 then table.insert(parts, copperRemain .. "c") end
			priceDisplay = table.concat(parts, " ")
			totalItemValue = totalItemValue + (unitPrice * item.qty)
		end

		local itemLabel = itemName or ("Item " .. item.id)
		print(itemLabel .. " (" .. item.id .. "): " .. item.qty .. " @ " .. priceDisplay .. " each")
	end

	local hasAuctionator = ns.IsAuctionatorAvailable and ns.IsAuctionatorAvailable() or false
	print("Auctionator available: " .. tostring(hasAuctionator))

	local gold = math.floor(totalItemValue / 10000)
	local silver = math.floor((totalItemValue % 10000) / 100)
	local copperRemain = totalItemValue % 100
	local parts = {}
	if gold > 0 then table.insert(parts, gold .. "g") end
	if silver > 0 then table.insert(parts, silver .. "s") end
	if copperRemain > 0 or #parts == 0 then table.insert(parts, copperRemain .. "c") end
	print("Estimated item value: " .. table.concat(parts, " "))
end

-- Set up event handler for the module-local event frame
eventFrame:SetScript("OnEvent", OnBagUpdate)
