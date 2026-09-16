-- GoldRoute Pricing - Auctionator integration for item valuation
local addonName, ns = ...

-- Per-runtime price cache
-- Lightweight cache to avoid repeated lookups for the same item
local priceCache = {}
local priceCacheKnown = {}

---
-- Feature-detect Auctionator v1 API availability
-- Safely checks if the supported external API is available
---
local function IsAuctionatorAvailable()
	return type(Auctionator) == "table" and
		type(Auctionator.API) == "table" and
		type(Auctionator.API.v1) == "table" and
		type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

---
-- Look up an item's market price from Auctionator
-- Protected by pcall to safely handle any external API errors
-- Returns unit price in copper, or nil if unavailable
---
local function LookupAuctionatorPrice(itemID)
	if not IsAuctionatorAvailable() then
		return nil
	end

	-- Only protect the external API call, not our logic
	local ok, price = pcall(
		Auctionator.API.v1.GetAuctionPriceByItemID,
		"GoldLedger",
		itemID
	)

	-- Validate the returned value
	if not ok or type(price) ~= "number" then
		return nil
	end

	return price
end

---
-- Get the market price for an item (unit price in copper)
-- Checks cache first; if not cached, queries Auctionator and caches the result
-- Returns unit price in copper, or nil if unavailable
---
function ns.GetItemMarketPrice(itemID)
	if type(itemID) ~= "number" then
		return nil
	end

	-- Return cached price if available
	if priceCacheKnown[itemID] then
		return priceCache[itemID]
	end

	-- Look up from Auctionator
	local price = LookupAuctionatorPrice(itemID)

	-- Cache the result (including nil) to avoid repeated lookups
	priceCache[itemID] = price
	priceCacheKnown[itemID] = true

	return price
end

---
-- Get estimated total value of acquired items
-- Input: { itemID = quantity, ... }
-- Returns: (totalValue, pricedCount, unpricedCount)
-- Treats Auctionator unit prices as estimated auction house value
-- Only includes items with positive numeric quantities
---
function ns.GetEstimatedItemValue(items)
	if not items or type(items) ~= "table" then
		return 0, 0, 0
	end

	local totalValue = 0
	local pricedCount = 0
	local unpricedCount = 0

	for itemID, quantity in pairs(items) do
		-- Only count valid positive numeric quantities
		if type(itemID) == "number" and type(quantity) == "number" and quantity > 0 then
			local unitPrice = ns.GetItemMarketPrice(itemID)

			if unitPrice then
				-- Item has a price: include in total
				totalValue = totalValue + (unitPrice * quantity)
				pricedCount = pricedCount + 1
			else
				-- Item has no price: track as unpriced
				unpricedCount = unpricedCount + 1
			end
		end
	end

	return totalValue, pricedCount, unpricedCount
end

---
-- Check if Auctionator is available for UI feedback
---
function ns.IsAuctionatorAvailable()
	return IsAuctionatorAvailable()
end
