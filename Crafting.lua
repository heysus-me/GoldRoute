-- GoldLedger Crafting Module Foundation
-- This module establishes the foundation for future crafting activity tracking.
-- Crafting profitability analysis and recipe detection are not yet implemented.
local addonName, ns = ...

-- Crafting module state (placeholder for future implementation)
local activeCraftingSession = nil

---
-- Check if the Crafting module is available
-- Returns true; foundation is always available (actual profitability features are stubbed)
---
function ns.IsCraftingModuleAvailable()
	return true
end

---
-- Get current crafting context
-- Returns nil placeholder structure; actual context will be populated when
-- recipe identification and profitability analysis are implemented
-- Future context schema:
-- {
--     profession = nil,              -- Profession name (Mining, Herbalism, etc.)
--     professionID = nil,            -- Profession ID
--     recipeID = nil,                -- Currently crafting recipe ID
--     recipeName = nil,              -- Currently crafting recipe name
--     quantity = 0,                  -- Items to craft
--     reagentCost = 0,               -- Total cost of reagents
--     outputValue = 0,               -- Market value of output
--     estimatedProfit = 0,           -- outputValue - reagentCost
--     concentrationUsed = 0,         -- Concentration spent (if applicable)
-- }
---
function ns.GetCraftingContext()
	-- Foundation: returns nil to indicate no active crafting context yet
	return nil
end

---
-- Check if a specific recipe is supported for profitability tracking
-- Future implementation will validate recipes and return true only for supported recipes
-- For now, returns false to indicate no recipes are tracked yet
---
function ns.IsRecipeSupportedForProfitability(recipeID)
	-- Foundation: no profitability analysis yet
	return false
end

---
-- Get the estimated profit for a recipe
-- Future implementation will calculate:
-- - reagent cost via Auctionator
-- - output value via Auctionator
-- - profit = outputValue - reagentCost
-- For now, returns nil to indicate no data available
---
function ns.GetRecipeProfitEstimate(recipeID, quantity)
	-- Foundation: no profitability analysis yet
	return nil
end

-- Future expansion areas (do not implement yet):
-- - Recipe scanning and identification
-- - Profession UI integration hooks
-- - Reagent cost calculations via Auctionator
-- - Multicraft and resourcefulness modeling
-- - Quality/rank tracking
-- - Concentration valuation
-- - Crafting session lifecycle (integrate with Session.lua)
-- - Profit per craft and profit per hour calculations
-- - Crafting UI display
