--[[
    EqManagerPaperDoll.lua
    Hooks into the Blizzard PaperDollFrame to add the EqManager Sets Button
    and the individual Slot State Checkboxes for Partial Sets.
]]

EqManagerPaperDoll = {}
EqManager:RegisterModule("PaperDoll", EqManagerPaperDoll)

function EqManagerPaperDoll:Init()
    self.INVSLOTS = EqManager.INVSLOTS
    self.slotBoxes = {}

    -- Hook the main frame
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            self:InjectButton()
            self:UpdateHighlights()
        end)
    end

    EqManager:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    EqManager:RegisterEvent("BAG_UPDATE")
    EqManager:HookScript("OnEvent", function(f, event, ...)
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE" then
            if PaperDollFrame and PaperDollFrame:IsVisible() then
                self:UpdateHighlights()
            end
        end
    end)
end

function EqManagerPaperDoll:InjectButton()
    if not self.btn then
        self.btn = CreateFrame("Button", "EM_NewPaperDollButton", PaperDollFrame, "UIPanelButtonTemplate")
        self.btn:SetWidth(40)
        self.btn:SetHeight(20)
        self.btn:SetText("SETS")
        
        self.btn:SetPoint("TOPRIGHT", PaperDollFrame, "TOPRIGHT", -45, -40)
        
        self.btn:SetScript("OnClick", function()
            local uiFrame = EqManager.UI.frame
            if uiFrame and uiFrame:IsVisible() then
                uiFrame:Hide()
                EM_OPTIONS.ShowUI = false
            elseif uiFrame then
                uiFrame:Show()
                EM_OPTIONS.ShowUI = true
            end
        end)
    end
    self.btn:Show()

    if EM_OPTIONS.ShowUI and EqManager.UI.frame and not EqManager.UI.frame:IsVisible() then
        EqManager.UI.frame:Show()
    end
end

function EqManagerPaperDoll:CreateSlotStateBoxes()
    if #self.slotBoxes > 0 then return end
    
    for _, slotData in ipairs(self.INVSLOTS) do
        local slotFrameName = slotData[1]
        local slotId = slotData[2]
        
        local parentSlot = _G[slotFrameName]
        if parentSlot then
            local cb = CreateFrame("CheckButton", nil, parentSlot, "UICheckButtonTemplate")
            cb:SetSize(20, 20)
            cb:SetPoint("TOPLEFT", parentSlot, "TOPLEFT", -2, 2)
            cb:SetFrameLevel(parentSlot:GetFrameLevel() + 5)
            cb:SetHitRectInsets(0, 0, 0, 0)
            cb.slotId = slotId
            
            -- Hook selection
            cb:SetScript("OnClick", function(self)
                local currentSet = EqManager.Data.db.CurrentSet
                if currentSet then
                     local set = EqManager.Data:GetSet(currentSet)
                     if set then
                         if not self:GetChecked() then
                             set.slots[slotId] = nil
                         else
                             set.slots[slotId] = GetInventoryItemLink("player", slotId) or "EMPTY"
                         end
                     end
                end
            end)
            
            table.insert(self.slotBoxes, cb)
        end
    end
end

function EqManagerPaperDoll:ShowSlotStateBoxes()
    self:CreateSlotStateBoxes()
    for _, cb in ipairs(self.slotBoxes) do
        cb:Show()
        -- Sync visual
        local currentSet = EqManager.Data.db.CurrentSet
        if currentSet then
             local set = EqManager.Data:GetSet(currentSet)
             if set then
                 cb:SetChecked(set.slots[cb.slotId] ~= nil)
             end
        end
    end
end

function EqManagerPaperDoll:HideSlotStateBoxes()
    for _, cb in ipairs(self.slotBoxes) do
        cb:Hide()
    end
end

function EqManagerPaperDoll:PromptSaveSet()
    if not StaticPopupDialogs["EQMANAGER_SAVESET"] then
        StaticPopupDialogs["EQMANAGER_SAVESET"] = {
            text = "Enter a name for the new set:",
            button1 = "Save",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(dialog)
                local editBox = dialog.editBox or _G[dialog:GetName().."EditBox"]
                local text = editBox and editBox:GetText()
                if text and text ~= "" then
                    self:SaveCurrentEquipmentAsSet(text)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3
        }
    end
    StaticPopup_Show("EQMANAGER_SAVESET")
end

function EqManagerPaperDoll:SaveCurrentEquipmentAsSet(name)
    local slotsCount = 19
    local items = {}
    
    local existingSet = EqManager.Data:GetSet(name)
    local partialState = existingSet and existingSet.isPartial or false
    
    for i=1, slotsCount do
        local shouldSave = true
        if partialState then
            for _, cb in ipairs(self.slotBoxes) do
                if cb.slotId == i and not cb:GetChecked() then
                    shouldSave = false
                    break
                end
            end
        end
        
        if shouldSave then
            local link = GetInventoryItemLink("player", i)
            items[i] = link or "EMPTY"
        end
    end
    
    EqManager.Data:SaveSet(name, items, { isPartial = partialState })
    EqManager.Data.db.CurrentSet = name
    
    print("|cFF00FFFFEqManager|r: Saved set " .. name)
    if EqManager.UI and EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
        EqManager.UI:RefreshSetsList()
    end
    self:UpdateHighlights()
end

function EqManagerPaperDoll:CreateHighlightOverlays()
    if self.highlightOverlays then return end
    self.highlightOverlays = {}

    for _, slotData in ipairs(self.INVSLOTS) do
        local slotFrameName = slotData[1]
        local slotId = slotData[2]
        local parentSlot = _G[slotFrameName]
        
        if parentSlot then
            local highlight = parentSlot:CreateTexture(nil, "OVERLAY")
            -- Even smaller dot for a cleaner look
            highlight:SetSize(6, 6)
            highlight:SetPoint("BOTTOMRIGHT", parentSlot, "BOTTOMRIGHT", -2, 2)
            highlight:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") 
            highlight:Hide()
            self.highlightOverlays[slotId] = highlight
        end
    end
end

function EqManagerPaperDoll:UpdateHighlights()
    if not PaperDollFrame or not PaperDollFrame:IsVisible() then return end
    self:CreateHighlightOverlays()

    -- 1. Get Aggregate Desired State
    local desiredItems = {}
    local itemSources = {} -- For telemetry
    local refSet = EqManager.Data.db.CurrentSet
    
    if EM_OPTIONS.Debug then
        print("|cFF00FFFFEqManager DEBUG|r: --- UpdateHighlights ---")
        print("|cFF00FFFFEqManager DEBUG|r: RefSet: " .. (refSet or "None"))
    end

    if refSet then
        local cSet = EqManager.Data:GetSet(refSet)
        if cSet then
            for slotId, item in pairs(cSet.slots) do
                desiredItems[slotId] = item
                itemSources[slotId] = refSet
            end
            
            -- If it's a partial set, we need to fill in the rest from the BaseFullSet
            if cSet.isPartial then
                local baseSetName = EqManager.Data.db.BaseFullSet
                if baseSetName then
                    local bSet = EqManager.Data:GetSet(baseSetName)
                    if bSet then
                        for slotId, item in pairs(bSet.slots) do
                            if not desiredItems[slotId] then
                                desiredItems[slotId] = item
                                itemSources[slotId] = "Base: " .. baseSetName
                            end
                        end
                    end
                end
            end
        end
    else
        -- Fallback to BaseFullSet if no current selection
        local baseSetName = EqManager.Data.db.BaseFullSet
        if baseSetName then
            local bSet = EqManager.Data:GetSet(baseSetName)
            if bSet then
                for slotId, item in pairs(bSet.slots) do
                    desiredItems[slotId] = item
                    itemSources[slotId] = "Base: " .. baseSetName
                end
            end
        end
    end

    -- Layer on active partials if they aren't the primary reference
    local activePartials = EqManager.Data:GetActivePartialSets()
    for _, partialName in ipairs(activePartials) do
        if partialName ~= refSet then
            local pSet = EqManager.Data:GetSet(partialName)
            if pSet then
                for slotId, item in pairs(pSet.slots) do
                    desiredItems[slotId] = item
                    itemSources[slotId] = "ActivePartial: " .. partialName
                end
            end
        end
    end

    -- 2. Update each overlay
    for slotId, highlight in pairs(self.highlightOverlays) do
        local targetItem = desiredItems[slotId]
        if targetItem and targetItem ~= "EMPTY" and targetItem ~= "VALUE_NONE" and targetItem ~= "$NONE" then
            if EM_OPTIONS.Debug then
                local nameStr = targetItem:match("%[(.-)%]") or targetItem
                print(string.format("|cFF00FFFFEqManager DEBUG|r: Slot %d, Source: %s, Looking for: %s", 
                    slotId, itemSources[slotId] or "??", nameStr))
            end

            local location = EqManager.Bags:GetItemLocationForSlot(targetItem, slotId)
            
            if location == "EQUIPPED" then
                highlight:SetVertexColor(0, 1, 0, 1) -- Green
                highlight:Show()
            elseif location == "BAGS" then
                highlight:SetVertexColor(1, 1, 0, 1) -- Yellow
                highlight:Show()
            elseif location == "MISSING" then
                highlight:SetVertexColor(1, 0, 0, 1) -- Red
                highlight:Show()
            else
                highlight:Hide()
            end
        else
            highlight:Hide()
        end
    end
end
