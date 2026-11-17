--[[
    EqManagerHooks.lua
    Handles third-party API hooks and standard Blizzard UI injections for Bag Dimming.
]]

EqManagerHooks = {}
EqManager:RegisterModule("Hooks", EqManagerHooks)

local baganatorButtons = setmetatable({}, { __mode = "k" })

local function ApplyBaganatorDimming(btn)
    if not btn or not btn.BGR then return end
    baganatorButtons[btn] = true

    local mode = EqManager.Options.BagDimmingMode or "DISABLED"
    if mode == "DISABLED" then
        if btn.emDimmed then
            btn:SetAlpha(1.0)
            btn.emDimmed = false
        end
        return
    end

    if btn.BGR.itemLink then
        local inSet = EqManager.Bags:IsItemInAnySet(btn.BGR.itemLink)
        local shouldDim = (mode == "NON_SET" and not inSet) or (mode == "SET" and inSet)

        if shouldDim then
            btn:SetAlpha(0.3)
            btn.emDimmed = true
        else
            btn:SetAlpha(1.0)
            btn.emDimmed = false
        end
    elseif btn.emDimmed then
        btn:SetAlpha(1.0)
        btn.emDimmed = false
    end
end

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
        
        local mode = EqManager.Options.BagDimmingMode or "DISABLED"
        
        -- Check if it's a Baganator button
        if btn.BGR then
            ApplyBaganatorDimming(btn)
            return
        end

        -- Check if it's a Blizzard/Standard button
        local bag = btn:GetParent() and btn:GetParent():GetID()
        local slot = btn:GetID()
        if bag and slot and type(bag) == "number" and type(slot) == "number" then
            local getLink = EqManager.API.GetContainerItemLink
            local link = getLink and getLink(bag, slot)
            
            if mode == "DISABLED" then
                if btn.emDimmed then btn:SetAlpha(1.0); btn.emDimmed = false end
            elseif link then
                local inSet = EqManager.Bags:IsItemInAnySet(link)
                local shouldDim = (mode == "NON_SET" and not inSet) or (mode == "SET" and inSet)
                
                if shouldDim then
                    btn:SetAlpha(0.3); btn.emDimmed = true
                else
                    btn:SetAlpha(1.0); btn.emDimmed = false
                end
            else
                if btn.emDimmed then btn:SetAlpha(1.0); btn.emDimmed = false end
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

    -- 2. Iterate Baganator Buttons
    -- Retail and Classic Forever use unnamed CreateFramePool buttons, so iterate tracked instances
    -- in addition to the named BGR* buttons used on non-Forever Classic clients.
    local bgrCount, bgrDimmed = 0, 0
    for btn in pairs(baganatorButtons) do
        bgrCount = bgrCount + 1
        applyToButton(btn)
        if btn.emDimmed then bgrDimmed = bgrDimmed + 1 end
    end
    for i = 1, 1000 do
        local btn = _G["BGRCachedItemButton"..i]
        if btn then
            if not baganatorButtons[btn] and btn:IsVisible() then
                bgrCount = bgrCount + 1
                applyToButton(btn)
                if btn.emDimmed then bgrDimmed = bgrDimmed + 1 end
            end
        else
            break
        end
    end
    for i = 1, 1000 do
        local btn = _G["BGRLiveItemButton"..i]
        if btn then
            if not baganatorButtons[btn] and btn:IsVisible() then
                bgrCount = bgrCount + 1
                applyToButton(btn)
                if btn.emDimmed then bgrDimmed = bgrDimmed + 1 end
            end
        else
            break
        end
    end
    if EqManager.Options.Debug then
        print(string.format("|cFF00FFFFEqManager DEBUG|r: RefreshBags mode=%s, BaganatorButtons=%d, Dimmed=%d, HooksInstalled=%s",
            tostring(EqManager.Options.BagDimmingMode), bgrCount, bgrDimmed, tostring(self.baganatorHooksInstalled)))
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
        local mode = EqManager.Options.BagDimmingMode or "DISABLED"
        if mode == "DISABLED" then 
            if self.emDimmed then
                self:SetAlpha(1.0)
                self.emDimmed = false
            end
            return 
        end
        
        local bag = self:GetParent():GetID()
        local slot = self:GetID()
        
        -- Compatibility wrapper for GetContainerItemLink
        local getLink = EqManager.API.GetContainerItemLink
        local link = getLink and getLink(bag, slot)
        
        local inSet = link and EqManager.Bags:IsItemInAnySet(link)
        local shouldDim = (mode == "NON_SET" and not inSet) or (mode == "SET" and inSet)
        
        if shouldDim then
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
        if itemButtonClass and itemButtonClass.prototype and itemButtonClass.prototype.UpdateAlpha then
            hooksecurefunc(itemButtonClass.prototype, "UpdateAlpha", function(self)
            local mode = EqManager.Options.BagDimmingMode or "DISABLED"
            if mode == "DISABLED" then 
                if self.emDimmed then
                    self:SetAlpha(1.0)
                    self.emDimmed = false
                end
                return 
            end
            
            local inSet = self.hasItem and EqManager.Bags:IsItemInAnySet(self.itemLink)
            local shouldDim = (mode == "NON_SET" and not inSet) or (mode == "SET" and inSet)
            
            if shouldDim then
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
    if self.baganatorHooksInstalled then return end

    local function isContainerBagTag(tags)
        if not tags then return false end
        for _, tag in ipairs(tags) do
            if tag == "containerBag" then return true end
        end
        return false
    end

    local function hookItemButton(details)
        if not details or details.regionType ~= "ItemButton" then return end
        if isContainerBagTag(details.tags) then return end

        local button = details.region
        if not button or button.emBaganatorHooked or not button.SetItemDetails then return end

        button.emBaganatorHooked = true
        baganatorButtons[button] = true
        hooksecurefunc(button, "SetItemDetails", ApplyBaganatorDimming)
        if button.BGR then
            ApplyBaganatorDimming(button)
        end
    end

    local function safeHookMixin(mixin, methodName, hookFunc)
        if mixin and mixin[methodName] then
            local isFrozen = table.isfrozen and table.isfrozen(mixin)
            if not isFrozen then
                hooksecurefunc(mixin, methodName, hookFunc)
                return true
            end
        end
        return false
    end

    local function installHooks()
        if self.baganatorHooksInstalled then return end

        if Baganator and Baganator.API and Baganator.API.Skins and Baganator.API.Skins.RegisterListener then
            Baganator.API.Skins.RegisterListener(hookItemButton)
            if Baganator.API.Skins.GetAllFrames then
                for _, details in ipairs(Baganator.API.Skins.GetAllFrames()) do
                    hookItemButton(details)
                end
            end
            self.baganatorHooksInstalled = true
            return
        end

        -- Fallback for older Baganator versions without Skins.RegisterListener
        local hooked = false
        local mixinNames = {
            "BaganatorClassicLiveContainerItemButtonMixin",
            "BaganatorClassicCachedItemButtonMixin",
            "BaganatorClassicLiveGuildItemButtonMixin",
            "BaganatorRetailLiveContainerItemButtonMixin",
            "BaganatorRetailCachedItemButtonMixin",
            "BaganatorRetailLiveGuildItemButtonMixin",
        }
        for _, name in ipairs(mixinNames) do
            if safeHookMixin(_G[name], "SetItemDetails", ApplyBaganatorDimming) then
                hooked = true
            end
        end
        if hooked then
            self.baganatorHooksInstalled = true
        end
    end

    installHooks()

    if not self.baganatorHooksInstalled then
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(f, event, name)
            if name == "Baganator" then
                installHooks()
                if self.baganatorHooksInstalled then
                    f:UnregisterEvent("ADDON_LOADED")
                end
            end
        end)
    end
end

function EqManagerHooks:InstallTooltipHooks()
    if self.tooltipHooksInstalled then return end
    self.tooltipHooksInstalled = true
    local function onTooltipSetItem(tooltip)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        if not EqManager.Options or not EqManager.Options.ShowTooltips then return end
        
        local name, link = tooltip:GetItem()
        if not link then return end
        
        -- Ensure it's an equippable item
        if not EqManager.API.IsEquippableItem(link) then return end
        
        local _, _, _, _, _, _, _, _, itemEquipLoc = EqManager.API.GetItemInfo(link)
        -- Exclude non-character slots (Bags, Quivers) and empty locs
        if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_BAG" or itemEquipLoc == "INVTYPE_QUIVER" then return end
        
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

    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltipSetItem)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tooltip:HasScript("OnTooltipSetItem") then
                tooltip:HookScript("OnTooltipSetItem", onTooltipSetItem)
            end
        end
    end
end
