--[[
    EqManagerEngine.lua
    The core executing logic for swapping equipment slots.
]]

EqManagerEngine = {}
EqManager:RegisterModule("Engine", EqManagerEngine)

function EqManagerEngine:Init()
    -- Standard WoW Inventory Slots (Head to Tabard, Mainhand/Offhand, etc)
    self.INVSLOTS = {
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
    }
    self.isInternalSwap = false
    self.lastInternalSwapTime = 0
    self.isPaused = (#(EqManager.Data.db.PendingTasks or {}) > 0)
    self.lastResumedMessageTime = 0

    EqManager:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    EqManager:HookScript("OnEvent", function(f, event, ...)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            self:OnEquipmentChanged(...)
        end
    end)

    -- Resume any pending tasks from a previous session or reload
    C_Timer.After(1.0, function() self:ResumeSwapping() end)
    C_Timer.After(2.0, function() self:CheckAutoDetectSets() end)
end

function EqManagerEngine:CheckAutoDetectSets()
    local activePartials = EqManager.Data:GetActivePartialSets()
    local changedState = false

    for _, setName in ipairs(EqManager.Data:GetSetNames()) do
        local pSet = EqManager.Data:GetSet(setName)
        if pSet and pSet.isPartial and pSet.autoDetect then
            local isFullyEquipped = true
            local hasAnyItems = false
            local failedSlot = nil
            local slotCount = 0

            if EM_OPTIONS.Debug then
                print("|cFF00FFFFEqManager DEBUG|r: AutoDetect checking set: |cFFFFFF00" .. setName .. "|r")
            end

            for slotId, item in pairs(pSet.slots) do
                if item and item ~= "EMPTY" and item ~= "$NONE" then
                    hasAnyItems = true
                    slotCount = slotCount + 1
                    local currentlyEquippedLink = GetInventoryItemLink("player", slotId)
                    
                    local isMatch = false
                    if item == "VALUE_NONE" then
                        if currentlyEquippedLink == nil then
                           isMatch = true
                        end
                    else
                        local targetId = EqManager.Bags:GetItemIdFromLink(item)
                        local targetName = type(item) == "string" and item:match("%[(.-)%]") or nil
                        
                        local currentId = currentlyEquippedLink and EqManager.Bags:GetItemIdFromLink(currentlyEquippedLink)
                        local currentName = currentlyEquippedLink and currentlyEquippedLink:match("%[(.-)%]")
                        
                        if currentId and targetId and currentId == targetId then
                            isMatch = true
                        elseif currentName and targetName and currentName == targetName then
                            isMatch = true
                        end

                        if EM_OPTIONS.Debug then
                            print(string.format("|cFF00FFFFEqManager DEBUG|r:   Slot %d: target=%s (id=%s) vs equipped=%s (id=%s) -> %s",
                                slotId,
                                tostring(targetName or item),
                                tostring(targetId),
                                tostring(currentName or currentlyEquippedLink or "EMPTY"),
                                tostring(currentId),
                                isMatch and "|cFF00FF00MATCH|r" or "|cFFFF0000MISMATCH|r"))
                        end
                    end
                    
                    if not isMatch then
                        isFullyEquipped = false
                        failedSlot = slotId
                        break
                    end
                end
            end

            if EM_OPTIONS.Debug then
                print(string.format("|cFF00FFFFEqManager DEBUG|r:   Result: hasItems=%s, slots=%d, fullyEquipped=%s, failedSlot=%s",
                    tostring(hasAnyItems), slotCount, tostring(isFullyEquipped), tostring(failedSlot)))
            end

            -- Only consider valid partial sets that actually declare items
            if hasAnyItems then
                local isActive = false
                for _, a in ipairs(activePartials) do
                    if a == setName then isActive = true; break end
                end
                
                if isFullyEquipped and not isActive then
                    EqManager.Data:AddActivePartialSet(setName)
                    changedState = true
                    print("|cFF00FFFFEqManager|r: Detected partial set |cFFFFFF00" .. setName .. "|r as equipped.")
                    if EM_OPTIONS.Debug then
                        print("|cFF00FFFFEqManager DEBUG|r:   -> |cFF00FF00ACTIVATING|r set " .. setName)
                    end
                elseif not isFullyEquipped and isActive then
                    if setName ~= EqManager.Data.db.CurrentSet then
                        EqManager.Data:RemoveActivePartialSet(setName)
                        changedState = true
                        print("|cFF00FFFFEqManager|r: Partial set |cFFFFFF00" .. setName .. "|r no longer equipped.")
                        if EM_OPTIONS.Debug then
                            print("|cFF00FFFFEqManager DEBUG|r:   -> |cFFFF0000DEACTIVATING|r set " .. setName)
                        end
                    end
                end
            end
        end
    end

    if changedState and EqManager.UI and EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
        EqManager.UI:RefreshSetsList()
    end
end

function EqManagerEngine:EquipSet(setName, callback, source)
    self.isInternalSwap = true
    local set = EqManager.Data:GetSet(setName)
    if not set then
        print("|cFF00FFFFEqManager|r: Set not found -> " .. tostring(setName))
        self.isInternalSwap = false
        if callback then callback() end
        return false
    end

    if source then
        print("|cFF00FFFFEqManager|r: Equipping |cFFFFFF00" .. setName .. "|r (caused by: |cFF00FF00" .. source .. "|r)")
    end

    local preservedPartials = {}
    if set.isPartial then
        EqManager.Data:AddActivePartialSet(setName)
    else
        local currentPartials = EqManager.Data:GetActivePartialSets()
        for _, pName in ipairs(currentPartials) do
            local pSet = EqManager.Data:GetSet(pName)
            if pSet and pSet.keepOnBaseSwap then
                table.insert(preservedPartials, pName)
            end
        end
        EqManager.Data:ClearActivePartialSets()
        for _, pName in ipairs(preservedPartials) do
             EqManager.Data:AddActivePartialSet(pName)
        end
        EqManager.Data.db.BaseFullSet = setName
    end
    EqManager.Data.db.CurrentSet = setName

    local finalSlots = {}
    local finalHelmValue = nil
    local finalCloakValue = nil

    for _, slotId in ipairs(self.INVSLOTS) do
        local item = set.slots[slotId]
        if item then finalSlots[slotId] = item end
    end
    if set.affectsHelmet then finalHelmValue = true end
    if set.affectsCloak then finalCloakValue = true end

    -- Overlay preserved partials if this is a base set swap
    if not set.isPartial then
        for _, pName in ipairs(preservedPartials) do
            local pSet = EqManager.Data:GetSet(pName)
            if pSet then
                for _, slotId in ipairs(self.INVSLOTS) do
                    local pItem = pSet.slots[slotId]
                    if pItem then finalSlots[slotId] = pItem end
                end
                if pSet.affectsHelmet then finalHelmValue = true end
                if pSet.affectsCloak then finalCloakValue = true end
            end
        end
    end

    if finalHelmValue ~= nil and finalHelmValue then ShowHelm(true) end
    if finalCloakValue ~= nil and finalCloakValue then ShowCloak(true) end

    local itemsToSwap = {}
    for _, slotId in ipairs(self.INVSLOTS) do
        local targetItem = finalSlots[slotId]
        if targetItem and targetItem ~= "$NONE" then
            local currentlyEquippedLink = GetInventoryItemLink("player", slotId)

            if targetItem == "VALUE_NONE" or targetItem == "EMPTY" then
                -- Place in bag logic (not fully implemented in core yet)
            else
                local targetId = EqManager.Bags:GetItemIdFromLink(targetItem)
                local targetName = targetItem:match("%[(.-)%]")

                local currentId = currentlyEquippedLink and EqManager.Bags:GetItemIdFromLink(currentlyEquippedLink)
                local currentName = currentlyEquippedLink and currentlyEquippedLink:match("%[(.-)%]")

                local isMatch = false
                if currentId and targetId and currentId == targetId then
                    isMatch = true
                elseif currentName and targetName and currentName == targetName then
                    isMatch = true
                end

                if not currentlyEquippedLink or not isMatch then
                    table.insert(itemsToSwap, { slotId = slotId, targetItem = targetItem })
                end
            end
        end
    end

    if EqManager.UI and EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
        EqManager.UI:RefreshSetsList()
    end

    self:StartProcessingTasks(itemsToSwap, callback)
    return true
end

function EqManagerEngine:UnequipPartialSet(setName, callback, source)
    local active = EqManager.Data:GetActivePartialSets()
    local wasActive = false
    for _, name in ipairs(active) do
        if name == setName then
            wasActive = true
            break
        end
    end

    if not wasActive then
        if callback then callback() end
        return
    end

    self.isInternalSwap = true
    EqManager.Data:RemoveActivePartialSet(setName)

    local baseSet = EqManager.Data.db.BaseFullSet
    if not baseSet then
        print("|cFF00FFFFEqManager|r: Cannot unequip partial set - no Base Full Set recorded.")
        self.isInternalSwap = false
        if callback then callback() end
        return
    end

    local finalSlots = {}
    local finalHelmValue = nil
    local finalCloakValue = nil

    local bSetData = EqManager.Data:GetSet(baseSet)
    if bSetData then
        for _, slotId in ipairs(self.INVSLOTS) do
            local item = bSetData.slots[slotId]
            if item then finalSlots[slotId] = item end
        end
        if bSetData.affectsHelmet then finalHelmValue = true end
        if bSetData.affectsCloak then finalCloakValue = true end
    end

    local activePartials = EqManager.Data:GetActivePartialSets()
    for _, partialSetName in ipairs(activePartials) do
        local pSetData = EqManager.Data:GetSet(partialSetName)
        if pSetData then
            for _, slotId in ipairs(self.INVSLOTS) do
                local item = pSetData.slots[slotId]
                if item then finalSlots[slotId] = item end
            end
            if pSetData.affectsHelmet then finalHelmValue = true end
            if pSetData.affectsCloak then finalCloakValue = true end
        end
    end

    local msg = "|cFF00FFFFEqManager|r: Unequipping partial set |cFFFFFF00" .. setName .. "|r"
    if source then
        msg = msg .. " (caused by: |cFF00FF00" .. source .. "|r)"
    end
    print(msg .. "...")

    if finalHelmValue ~= nil then ShowHelm(finalHelmValue) end
    if finalCloakValue ~= nil then ShowCloak(finalCloakValue) end

    local itemsToSwap = {}
    for _, slotNum in ipairs(self.INVSLOTS) do
        local targetItem = finalSlots[slotNum]
        if targetItem and targetItem ~= "$NONE" then
            local currentlyEquippedLink = GetInventoryItemLink("player", slotNum)
            if targetItem == "VALUE_NONE" or targetItem == "EMPTY" then
                -- Place in bag logic (not fully implemented)
            else
                local targetId = EqManager.Bags:GetItemIdFromLink(targetItem)
                local targetName = targetItem:match("%[(.-)%]")

                local currentId = currentlyEquippedLink and EqManager.Bags:GetItemIdFromLink(currentlyEquippedLink)
                local currentName = currentlyEquippedLink and currentlyEquippedLink:match("%[(.-)%]")

                local isMatch = false
                if currentId and targetId and currentId == targetId then
                    isMatch = true
                elseif currentName and targetName and currentName == targetName then
                    isMatch = true
                end

                if not currentlyEquippedLink or not isMatch then
                    table.insert(itemsToSwap, { slotId = slotNum, targetItem = targetItem })
                end
            end
        end
    end

    local activePartials = EqManager.Data:GetActivePartialSets()
    if #activePartials > 0 then
        EqManager.Data.db.CurrentSet = activePartials[#activePartials]
    else
        EqManager.Data.db.CurrentSet = baseSet
    end

    if EqManager.UI and EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
        EqManager.UI:RefreshSetsList()
    end

    self:StartProcessingTasks(itemsToSwap, callback)
end

function EqManagerEngine:StartProcessingTasks(items, callback)
    if not items or #items == 0 then
        self.isInternalSwap = false
        self.lastInternalSwapTime = GetTime()
        if callback then callback() end
        return
    end

    EqManager.Data.db.PendingTasks = items
    self.currentCallback = callback
    self:ProcessNextTask()
end

function EqManagerEngine:ProcessNextTask()
    local tasks = EqManager.Data.db.PendingTasks
    if not tasks or #tasks == 0 then
        self.isInternalSwap = false
        self.lastInternalSwapTime = GetTime()
        if self.currentCallback then self.currentCallback() end
        return
    end

    if not EqManager.Queue:CanSwitch() then
        self.isPaused = true
        return
    end

    local task = table.remove(tasks, 1)
    EquipItemByName(task.targetItem, task.slotId)

    local delay = EM_OPTIONS.SwapDelay or 0
    if delay > 0 then
        C_Timer.After(delay, function() self:ProcessNextTask() end)
    else
        self:ProcessNextTask()
    end
end

function EqManagerEngine:ResumeSwapping()
    if #EqManager.Data.db.PendingTasks > 0 and self.isPaused then
        local now = GetTime()
        if now - self.lastResumedMessageTime > 5 then
            print("|cFF00FFFFEqManager|r: Resuming equipment swaps...")
            self.lastResumedMessageTime = now
        end
        self.isInternalSwap = true
        self.isPaused = false
        self:ProcessNextTask()
    end
end

function EqManagerEngine:OnEquipmentChanged(slotId, hasItem)
    if self.isInternalSwap or (GetTime() - self.lastInternalSwapTime < 1.0) then return end
    
    self:CheckAutoDetectSets()
    
    local condition = EM_OPTIONS.AutoUpdateCondition or "CHARACTER"
    if condition == "DISABLED" then return end

    if condition == "CHARACTER" then
        if not PaperDollFrame or not PaperDollFrame:IsVisible() then return end
    elseif condition == "SETS" then
        local frame = EqManager.UI and EqManager.UI.frame
        if not frame or not frame:IsVisible() then return end
    elseif condition == "BOTH" then
        local pdVisible = PaperDollFrame and PaperDollFrame:IsVisible()
        local frame = EqManager.UI and EqManager.UI.frame
        local mainVisible = frame and frame:IsVisible()
        if not pdVisible and not mainVisible then return end
    end
    -- "ALWAYS" falls through to execute update logic

    -- 1. Identify Which Set Should be Updated
    -- Priority: Active Partial Set covering this slot > BaseFullSet
    local targetSet = nil

    local activePartials = EqManager.Data:GetActivePartialSets()
    for _, partialName in ipairs(activePartials) do
        local pSet = EqManager.Data:GetSet(partialName)
        if pSet and pSet.slots[slotId] then
            targetSet = pSet
            targetSetName = partialName
            break
        end
    end

    if not targetSet then
        local currentSetName = EqManager.Data.db.CurrentSet
        if currentSetName then
            local candSet = EqManager.Data:GetSet(currentSetName)
            if candSet and not candSet.isPartial then
                targetSet = candSet
                targetSetName = currentSetName
            end
        end
    end

    if not targetSet then return end

    local link = GetInventoryItemLink("player", slotId)
    local newItem = link or "EMPTY"

    -- 2. Update the target set
    local currentInSet = targetSet.slots[slotId]
    if currentInSet ~= newItem then
        targetSet.slots[slotId] = newItem

        print("|cFF00FFFFEqManager|r: Auto-updated |cFFFFFF00" .. (link or "(Empty)") .. "|r in set |cFFFFFF00" .. targetSetName .. "|r.")

        if EM_OPTIONS.Debug then
            print(string.format("|cFF00FFFFEqManager DEBUG|r: Auto-Updated slot %d in set |cFFFFFF00%s|r to %s",
                slotId, targetSetName, link or "(Empty)"))
        end

        if EqManager.UI and EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
            EqManager.UI:RefreshSetsList()
        end

        -- Trigger highlight refresh immediately
        if EqManager.PaperDoll then
            EqManager.PaperDoll:UpdateHighlights()
        end
    end
end
