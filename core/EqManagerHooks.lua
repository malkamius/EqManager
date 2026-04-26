--[[
    EqManagerHooks.lua
    Handles third-party API hooks and standard Blizzard UI injections for Bag Dimming.
]]

EqManagerHooks = {}
EqManager:RegisterModule("Hooks", EqManagerHooks)

function EqManagerHooks:Init()
    self:InstallBlizzardHooks()
    self:InstallAdiBagsHooks()
    self:InstallBaganatorHooks()
    self:InstallTooltipHooks()
end

function EqManagerHooks:RefreshBags()
    -- Universal refresh function that re-applies or clears dimming for a specific button
    local function applyToButton(btn)
        if not btn or not btn:IsObjectType("Button") then return end
        
        -- We need to determine if this button has the dimming logic applied
        -- For Baganator, we use applyDimming (re-using the logic)
        -- For Blizzard/AdiBags, we do the same.
        
        -- Check if it's a Baganator button
        if btn.BGR then
            if not EM_OPTIONS.EnableBagDimming then
                if btn.emDimmed then btn:SetAlpha(1.0); btn.emDimmed = false end
            elseif btn.BGR.itemLink then
                if not EqManager.Bags:IsItemInAnySet(btn.BGR.itemLink) then
                    btn:SetAlpha(0.3); btn.emDimmed = true
                else
                    btn:SetAlpha(1.0); btn.emDimmed = false
                end
            else
                if btn.emDimmed then btn:SetAlpha(1.0); btn.emDimmed = false end
            end
            return
        end

        -- Check if it's a Blizzard/Standard button
        local bag = btn:GetParent() and btn:GetParent():GetID()
        local slot = btn:GetID()
        if bag and slot and type(bag) == "number" and type(slot) == "number" then
            local getLink = GetContainerItemLink or (C_Container and C_Container.GetContainerItemLink)
            local link = getLink and getLink(bag, slot)
            
            if not EM_OPTIONS.EnableBagDimming then
                if btn.emDimmed then btn:SetAlpha(1.0); btn.emDimmed = false end
            elseif link and not EqManager.Bags:IsItemInAnySet(link) then
                btn:SetAlpha(0.3); btn.emDimmed = true
            else
                btn:SetAlpha(1.0); btn.emDimmed = false
            end
        end
    end

    -- 1. Iterate Blizzard Bags (Standard and Combined)
    local numBags = NUM_CONTAINER_FRAMES or 13
    for i = 1, numBags do
        local frame = _G["ContainerFrame"..i]
        if frame and frame:IsVisible() then
            -- Iterate children of the frame to find slots
            local name = frame:GetName()
            for j = 1, 36 do -- Max slots usually 36
                local btn = _G[name .. "Item" .. j]
                if btn then applyToButton(btn) end
            end
        end
    end
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsVisible() then
         -- Modern combined containers often have a different child naming or Use EnumerateValidItems
         if ContainerFrameCombinedBags.EnumerateValidItems then
             for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
                 applyToButton(itemButton)
             end
         else
             -- Fallback to child iteration
             local name = ContainerFrameCombinedBags:GetName()
             for j = 1, 200 do -- Higher limit for combined
                 local btn = _G[name .. "Item" .. j]
                 if btn then applyToButton(btn) end
             end
         end
    end

    -- 2. Iterate Baganator Buttons (Brute force via naming pattern in Pools.lua)
    -- Baganator uses "BGRCachedItemButton" and "BGRLiveItemButton" + Counter
    for i = 1, 1000 do
        local btn = _G["BGRCachedItemButton"..i]
        if btn then if btn:IsVisible() then applyToButton(btn) end else break end
    end
    for i = 1, 1000 do
        local btn = _G["BGRLiveItemButton"..i]
        if btn then if btn:IsVisible() then applyToButton(btn) end else break end
    end

    -- 3. AdiBags Refresh (Messages are usually enough here as it rebuilds)
    if AdiBags then
        local addon = LibStub("AceAddon-3.0"):GetAddon("AdiBags", true)
        if addon then addon:SendMessage("AdiBags_UpdateAllButtons") end
    end
    
    -- 4. Native refresh as fallback
    if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
        Baganator.API.RequestItemButtonsRefresh({2, 4, 32})
    end
end

function EqManagerHooks:InstallBlizzardHooks()
    local function applyDimming(self)
        if not EM_OPTIONS.EnableBagDimming then 
            if self.emDimmed then
                self:SetAlpha(1.0)
                self.emDimmed = false
            end
            return 
        end
        
        local bag = self:GetParent():GetID()
        local slot = self:GetID()
        
        -- Compatibility wrapper for GetContainerItemLink
        local getLink = GetContainerItemLink or (C_Container and C_Container.GetContainerItemLink)
        local link = getLink and getLink(bag, slot)
        
        if link and not EqManager.Bags:IsItemInAnySet(link) then
            self:SetAlpha(0.3)
            self.emDimmed = true
        else
            self:SetAlpha(1.0)
            self.emDimmed = false
        end
    end

    if _G["ContainerFrameItemButton_Update"] then
        hooksecurefunc("ContainerFrameItemButton_Update", applyDimming)
    elseif ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.Update then
        hooksecurefunc(ContainerFrameItemButtonMixin, "Update", applyDimming)
    end
end

function EqManagerHooks:InstallAdiBagsHooks()
    -- Native WoW API compatibility
    local isLoaded = IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)

    -- AdiBags uses LibStub AceAddon-3.0
    local function checkAdiBags()
        local AdiBags = LibStub("AceAddon-3.0"):GetAddon("AdiBags", true)
        if not AdiBags then return end
        
        local itemButtonClass = AdiBags:GetClass("ItemButton")
        if itemButtonClass and itemButtonClass.prototype then
            hooksecurefunc(itemButtonClass.prototype, "UpdateAlpha", function(self)
            if not EM_OPTIONS.EnableBagDimming then 
                if self.emDimmed then
                    self:SetAlpha(1.0)
                    self.emDimmed = false
                end
                return 
            end
            
            if self.hasItem and not EqManager.Bags:IsItemInAnySet(self.itemLink) then
                self:SetAlpha(0.3)
                self.emDimmed = true
            else
                if self.emDimmed then
                    self:SetAlpha(1.0)
                    self.emDimmed = false
                end
            end
        end)
        end
    end
    
    -- Try immediately and also when addon loads (if not already loaded)
    if isLoaded and isLoaded("AdiBags") then
        checkAdiBags()
    else
        EqManager:RegisterEvent("ADDON_LOADED")
        EqManager:HookScript("OnEvent", function(f, event, name)
            if event == "ADDON_LOADED" and name == "AdiBags" then
                checkAdiBags()
            end
        end)
    end
end

function EqManagerHooks:InstallBaganatorHooks()
    local function applyDimming(self)
        if not EM_OPTIONS.EnableBagDimming then 
            if self.emDimmed then
                self:SetAlpha(1.0)
                self.emDimmed = false
            end
            return 
        end
        
        if self.BGR and self.BGR.itemLink then
            if not EqManager.Bags:IsItemInAnySet(self.BGR.itemLink) then
                self:SetAlpha(0.3)
                self.emDimmed = true
            else
                self:SetAlpha(1.0)
                self.emDimmed = false
            end
        else
            if self.emDimmed then
                self:SetAlpha(1.0)
                self.emDimmed = false
            end
        end
    end

    -- Hook Classic Mixins
    if BaganatorClassicLiveContainerItemButtonMixin then
        hooksecurefunc(BaganatorClassicLiveContainerItemButtonMixin, "SetItemDetails", applyDimming)
    end
    if BaganatorClassicCachedItemButtonMixin then
        hooksecurefunc(BaganatorClassicCachedItemButtonMixin, "SetItemDetails", applyDimming)
    end
    if BaganatorClassicLiveGuildItemButtonMixin then
        hooksecurefunc(BaganatorClassicLiveGuildItemButtonMixin, "SetItemDetails", applyDimming)
    end

    -- Hook Retail Mixins (Modern engine addons often use these)
    if BaganatorRetailLiveContainerItemButtonMixin then
        hooksecurefunc(BaganatorRetailLiveContainerItemButtonMixin, "SetItemDetails", applyDimming)
    end
    if BaganatorRetailCachedItemButtonMixin then
        hooksecurefunc(BaganatorRetailCachedItemButtonMixin, "SetItemDetails", applyDimming)
    end
    if BaganatorRetailLiveGuildItemButtonMixin then
        hooksecurefunc(BaganatorRetailLiveGuildItemButtonMixin, "SetItemDetails", applyDimming)
    end
end

function EqManagerHooks:InstallTooltipHooks()
    local function onTooltipSetItem(tooltip)
        if not EM_OPTIONS or not EM_OPTIONS.ShowTooltips then return end
        
        local name, link = tooltip:GetItem()
        if not link then return end
        
        local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(link)
        if not itemEquipLoc or itemEquipLoc == "" then return end
        
        local sets = EqManager.Bags:GetSetsForItem(link)
        if sets and #sets > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFF00FFFFEqManager|r: Included in |cFFFFD700" .. table.concat(sets, ", ") .. "|r")
        else
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFF00FFFFEqManager|r: |cFFFF0000Not in any sets|r")
        end
        -- No need to call Show() as the engine handles it after the script runs
    end

    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetItem", onTooltipSetItem)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", onTooltipSetItem)
    end
end
