--[[
    EqManagerBags.lua
    Provides logic for identifying items that belong to equipment sets.
]]

EqManagerBags = {}
EqManager:RegisterModule("Bags", EqManagerBags)

function EqManagerBags:Init()
    self.setItems = {} -- Cache for O(1) lookup
    self:RefreshCache()
    
    -- Register events that should trigger a background refresh of the cache
    EqManager:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    EqManager:HookScript("OnEvent", function(f, event, ...)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            -- We typically refresh cache when sets change, but we'll hook SaveSet too
        end
    end)
end

function EqManagerBags:RefreshCache()
    wipe(self.setItems)
    local sets = EqManager.Data.db.Sets
    if not sets then return end
    
    for setName, setData in pairs(sets) do
        if setData.slots then
            -- Pre-calculate display name with partial indicator
            local displayName = setData.isPartial and (setName .. " (P)") or setName
            
            for slotId, itemString in pairs(setData.slots) do
                if itemString and itemString ~= "EMPTY" and itemString ~= "VALUE_NONE" and itemString ~= "$NONE" then
                    -- Extract ItemID from itemString if it's a link or just use as is
                    local itemId = self:GetItemIdFromLink(itemString)
                    if itemId then
                        self.setItems[itemId] = self.setItems[itemId] or {}
                        
                        -- Avoid duplicates if the same item is in multiple slots in one set
                        local found = false
                        for _, existing in ipairs(self.setItems[itemId]) do
                            if existing == displayName then
                                found = true
                                break
                            end
                        end
                        
                        if not found then
                            table.insert(self.setItems[itemId], displayName)
                        end
                    end
                end
            end
        end
    end
end

function EqManagerBags:GetItemIdFromLink(link)
    if not link or link == "" then return nil end
    -- Handle raw IDs
    local id = tonumber(link)
    if id then return id end
    
    -- Handle item links: |Hitem:ID:Enchant:Gem1:Gem2:Gem3:Gem4:SuffixID:UniqueID:Level:FactionID:Special:Extra|h
    -- TBC Classic links can have varying number of segments. The ID is always the first one.
    local itemId = link:match("item:(%d+)")
    if itemId then
        return tonumber(itemId)
    end
    return nil
end

function EqManagerBags:IsItemInAnySet(itemLink)
    if not EqManager.Options.EnableBagDimming then return false end
    local itemId = self:GetItemIdFromLink(itemLink)
    if not itemId then return false end
    
    return self.setItems[itemId] ~= nil
end

function EqManagerBags:GetSetsForItem(itemLink)
    local itemId = self:GetItemIdFromLink(itemLink)
    if not itemId then return nil end
    return self.setItems[itemId]
end

function EqManagerBags:GetItemLocationForSlot(targetLink, slotId)
    if not targetLink or targetLink == "EMPTY" or targetLink == "VALUE_NONE" or targetLink == "$NONE" then
        return nil
    end

    local targetId = self:GetItemIdFromLink(targetLink)
    local targetName = targetLink:match("%[(.-)%]")
    
    if EqManager.Options.Debug then
        print(string.format("|cFF00FFFFEqManager DEBUG|r: Slot %d, Looking for: %s (ID: %s)", 
            slotId, targetName or "Unknown", tostring(targetId) or "nil"))
    end

    if not targetId and not targetName then return "MISSING" end

    -- 1. Check if equipped in THIS SPECIFIC SLOT
    local link = GetInventoryItemLink("player", slotId)
    if link then
        local id = self:GetItemIdFromLink(link)
        local name = link:match("%[(.-)%]")
        
        if EqManager.Options.Debug then
            print(string.format("|cFF00FFFFEqManager DEBUG|r: ...Equipped in slot %d: %s (ID: %s)", 
                slotId, name or "Unknown", tostring(id) or "nil"))
        end

        local match = false
        if targetId and id == targetId then match = true
        elseif targetName and name == targetName then match = true
        end
        
        if match then 
            if EqManager.Options.Debug then print("|cFF00FFFFEqManager DEBUG|r: ...Result: EQUIPPED") end
            return "EQUIPPED" 
        end
    else
        if EqManager.Options.Debug then print("|cFF00FFFFEqManager DEBUG|r: ...Slot is Empty") end
    end

    -- 2. Check player's immediate inventory ONLY (Backpack=0, Bags 1-4)
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    
    for bag = 0, 4 do
        local slots = getNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local bLink = getLink(bag, slot)
                if bLink then
                    local bId = self:GetItemIdFromLink(bLink)
                    local bName = bLink:match("%[(.-)%]")
                    if (targetId and bId == targetId) or (targetName and bName == targetName) then
                        if EqManager.Options.Debug then
                            print(string.format("|cFF00FFFFEqManager DEBUG|r: ...Result: BAGS (Found in Bag %d, Slot %d)", bag, slot))
                        end
                        return "BAGS"
                    end
                end
            end
        end
    end

    if EqManager.Options.Debug then print("|cFF00FFFFEqManager DEBUG|r: ...Result: MISSING") end
    return "MISSING"
end

function EqManagerBags:ToggleDimming(enable)
    EqManager.Options.EnableBagDimming = enable
    if EqManager.Hooks then
        EqManager.Hooks:RefreshBags()
    end
end

function EqManagerBags:GetInventoryMap()
    local invMap = {}
    
    -- 1. Scan equipped items
    for slotId = 1, 19 do
        local link = GetInventoryItemLink("player", slotId)
        if link then
            local itemId = self:GetItemIdFromLink(link)
            if itemId then
                invMap[itemId] = (invMap[itemId] or 0) + 1
            end
        end
    end
    
    -- 2. Scan bags (0-4)
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    
    for bagId = 0, 4 do
        local numSlots = getNumSlots(bagId)
        if numSlots then
            for slotId = 1, numSlots do
                local link = getLink(bagId, slotId)
                if link then
                    local itemId = self:GetItemIdFromLink(link)
                    if itemId then
                        invMap[itemId] = (invMap[itemId] or 0) + 1
                    end
                end
            end
        end
    end
    
    return invMap
end

function EqManagerBags:GetMissingItemsForSet(setName, invMap)
    local setData = EqManager.Data:GetSet(setName)
    if not setData or not setData.slots then return nil end
    
    local missing = {}
    local needed = {}
    
    -- Count how many of each item we need
    for _, itemString in pairs(setData.slots) do
        if itemString and itemString ~= "EMPTY" and itemString ~= "VALUE_NONE" and itemString ~= "$NONE" then
            local itemId = self:GetItemIdFromLink(itemString)
            if itemId then
                needed[itemId] = (needed[itemId] or 0) + 1
            end
        end
    end
    
    -- Compare with inventory map
    local tempInv = {}
    for id, count in pairs(invMap) do tempInv[id] = count end
    
    for _, itemString in pairs(setData.slots) do
        if itemString and itemString ~= "EMPTY" and itemString ~= "VALUE_NONE" and itemString ~= "$NONE" then
            local itemId = self:GetItemIdFromLink(itemString)
            if itemId then
                if not tempInv[itemId] or tempInv[itemId] <= 0 then
                    -- Extract name from link for display
                    local name = itemString:match("%[(.-)%]") or ("Item " .. itemId)
                    -- Check if already in missing list to avoid duplicates
                    local found = false
                    for _, m in ipairs(missing) do
                        if m == name then found = true break end
                    end
                    if not found then
                        table.insert(missing, name)
                    end
                else
                    tempInv[itemId] = tempInv[itemId] - 1
                end
            end
        end
    end
    
    return #missing > 0 and missing or nil
end
