--[[
    EqManagerQuickslot.lua
    Implements dynamic item selection bars next to PaperDoll slots.
]]

EqManagerQuickslot = {}
EqManager:RegisterModule("Quickslot", EqManagerQuickslot)

function EqManagerQuickslot:Init()
    self.activeQuickbars = {}
    self.INVSLOTS = EqManager.INVSLOTS
    
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            self:HookPaperDollSlots()
        end)
        PaperDollFrame:HookScript("OnHide", function()
            self:CloseAll()
        end)
    end
end

function EqManagerQuickslot:HookPaperDollSlots()
    if self.slotsHooked then return end
    self.slotsHooked = true
    
    for _, slotData in ipairs(self.INVSLOTS) do
        local slotName = slotData[1]
        local slotId = slotData[2]
        
        local parentSlot = _G[slotName]
        if parentSlot then
            parentSlot:HookScript("OnEnter", function()
                self:OpenQuickBar(slotId, parentSlot)
            end)
        end
    end
end

function EqManagerQuickslot:CloseAll()
    for _, bar in pairs(self.activeQuickbars) do
        bar:Hide()
    end
end

function EqManagerQuickslot:OpenQuickBar(slotId, parentSlot)
    self:CloseAll()
    local items = self:GetItemsForSlot(slotId)
    if #items == 0 then return end
    
    local bar = self.activeQuickbars[slotId]
    if not bar then
        bar = CreateFrame("Frame", "EqManagerQuickBar_"..slotId, parentSlot)
        bar.parentSlot = parentSlot
        bar:SetFrameStrata("HIGH")
        
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(0, 0, 0, 0.8)
        
        bar:SetScript("OnUpdate", function(self, elapsed)
            local isHovering = self:IsMouseOver() or self.parentSlot:IsMouseOver()
            if isHovering then
                self.hideTimer = nil
            else
                self.hideTimer = (self.hideTimer or 0) + elapsed
                if self.hideTimer > 0.15 then
                    self:Hide()
                    self.hideTimer = nil
                end
            end
        end)
        
        self.activeQuickbars[slotId] = bar
    end
    
    local buttonSize = 36
    local padding = 4
    
    bar.buttons = bar.buttons or {}
    for _, btn in ipairs(bar.buttons) do btn:Hide() end
    
    if slotId == 16 or slotId == 17 or slotId == 18 then
        bar:SetPoint("TOPLEFT", parentSlot, "TOPLEFT", -20, -(buttonSize + padding))
        bar:SetSize(buttonSize + padding*2, (#items * (buttonSize + padding)) + padding*2)
        
        for i, itemLink in ipairs(items) do
            local btn = self:GetOrCreateButton(bar, i, buttonSize)
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", padding, -((i-1)*(buttonSize+padding)) - padding)
            self:SetupButton(btn, itemLink, slotId)
        end
    else
        bar:SetPoint("TOPLEFT", parentSlot, "TOPLEFT", buttonSize + padding + 5, 0)
        bar:SetSize((#items * (buttonSize + padding)) + padding*2, buttonSize + padding*2)
        
        for i, itemLink in ipairs(items) do
            local btn = self:GetOrCreateButton(bar, i, buttonSize)
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", ((i-1)*(buttonSize+padding)) + padding, -padding)
            self:SetupButton(btn, itemLink, slotId)
        end
    end
    
    bar:Show()
end

function EqManagerQuickslot:GetOrCreateButton(parentBar, index, size)
    parentBar.buttons[index] = parentBar.buttons[index] or CreateFrame("Button", nil, parentBar, "ItemButtonTemplate")
    local btn = parentBar.buttons[index]
    btn:SetSize(size, size)
    btn:Show()
    return btn
end

function EqManagerQuickslot:SetupButton(btn, itemLink, targetSlotId)
    local itemName, _, quality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink)
    if not itemIcon then return end
    
    SetItemButtonTexture(btn, itemIcon)
    SetItemButtonQuality(btn, quality, itemLink)
    
    btn:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(itemLink)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    
    btn:SetScript("OnClick", function()
        EquipItemByName(itemName, targetSlotId)
        EqManagerQuickslot:CloseAll()
    end)
end

function EqManagerQuickslot:GetItemsForSlot(slotId)
    local results = {}
    -- Search in modern C_Container
    if not C_Container then return results end
    
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            if itemLink then
                local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
                if itemEquipLoc then
                    local equipSlot = self:MapEquipLocToSlot(itemEquipLoc)
                    if equipSlot == slotId or
                       (equipSlot == 11 and slotId == 12) or
                       (equipSlot == 13 and slotId == 14) or
                       (equipSlot == 16 and slotId == 17) then
                        table.insert(results, itemLink)
                    end
                end
            end
        end
    end
    return results
end

function EqManagerQuickslot:MapEquipLocToSlot(loc)
    local map = {
        ["INVTYPE_HEAD"] = 1, ["INVTYPE_NECK"] = 2, ["INVTYPE_SHOULDER"] = 3,
        ["INVTYPE_BODY"] = 4, ["INVTYPE_CHEST"] = 5, ["INVTYPE_ROBE"] = 5,
        ["INVTYPE_WAIST"] = 6, ["INVTYPE_LEGS"] = 7, ["INVTYPE_FEET"] = 8,
        ["INVTYPE_WRIST"] = 9, ["INVTYPE_HAND"] = 10, ["INVTYPE_FINGER"] = 11,
        ["INVTYPE_TRINKET"] = 13, ["INVTYPE_CLOAK"] = 15, ["INVTYPE_WEAPON"] = 16,
        ["INVTYPE_SHIELD"] = 17, ["INVTYPE_2HWEAPON"] = 16, ["INVTYPE_WEAPONMAINHAND"] = 16,
        ["INVTYPE_WEAPONOFFHAND"] = 17, ["INVTYPE_HOLDABLE"] = 17, ["INVTYPE_RANGED"] = 18,
        ["INVTYPE_THROWN"] = 18, ["INVTYPE_RANGEDRIGHT"] = 18, ["INVTYPE_RELIC"] = 18,
        ["INVTYPE_TABARD"] = 19,
    }
    return map[loc]
end
