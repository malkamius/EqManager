--[[
    EqManagerEventDialog.lua
    A popup dialog to configure and add new Event Bindings.
]]

EqManagerEventDialog = CreateFrame("Frame", "EqManagerEventDialogFrame", UIParent, "BasicFrameTemplateWithInset")
EqManager:RegisterModule("EventDialog", EqManagerEventDialog)

local EVENT_TYPES = {
    { label = "Enter Combat", value = "COMBAT_ENTER" },
    { label = "Leave Combat", value = "COMBAT_LEAVE" },
    { label = "Enter Zone", value = "ZONE_ENTER" },
    { label = "Shapeshift / Stance", value = "SHAPESHIFT" },
    { label = "Enter Stealth", value = "STEALTH_ENTER" },
    { label = "Leave Stealth", value = "STEALTH_LEAVE" },
    { label = "Mount", value = "MOUNT" },
    { label = "Dismount", value = "DISMOUNT" },
    { label = "Spec Change", value = "SPEC_CHANGED" },
    { label = "Enter PvP", value = "PVP_ENTER" },
    { label = "Exit PvP", value = "PVP_LEAVE" },
    { label = "Enter AFK", value = "AFK_ENTER" },
    { label = "Leave AFK", value = "AFK_LEAVE" },
}

function EqManagerEventDialog:Init()
    local frame = self
    frame:SetSize(300, 250)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("Add Event Binding")
    
    -- Event Type Dropdown
    local typeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeLabel:SetPoint("TOPLEFT", 20, -40)
    typeLabel:SetText("Trigger Event:")
    
    local typeDropdown = CreateFrame("Frame", "EqManagerEventTypeDropdown", frame, "UIDropDownMenuTemplate")
    typeDropdown:SetPoint("TOPLEFT", 10, -55)
    UIDropDownMenu_SetWidth(typeDropdown, 200)
    UIDropDownMenu_SetText(typeDropdown, "Select Event")
    
    -- SubType Component (EditBox for easy text entry / flexibility)
    -- In the old addon, zones were map children. For simplicity and reliability across expansions,
    -- allowing text match covers zones, forms, partial names perfectly.
    local subTypeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subTypeLabel:SetPoint("TOPLEFT", 20, -90)
    subTypeLabel:SetText("Condition (Zone name, Form number, etc.):")
    subTypeLabel:Hide()
    
    local subTypeBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    subTypeBox:SetSize(200, 20)
    subTypeBox:SetPoint("TOPLEFT", 25, -105)
    subTypeBox:SetAutoFocus(false)
    subTypeBox:Hide()
    
    local subTypeDropdown = CreateFrame("Frame", "EqManagerEventSubTypeDropdown", frame, "UIDropDownMenuTemplate")
    subTypeDropdown:SetPoint("TOPLEFT", 10, -105)
    UIDropDownMenu_SetWidth(subTypeDropdown, 200)
    subTypeDropdown:Hide()
    
    -- Additional helper text
    local helperText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helperText:SetPoint("TOPLEFT", subTypeBox, "BOTTOMLEFT", 0, -2)
    helperText:SetWidth(200)
    helperText:SetJustifyH("LEFT")
    helperText:Hide()
    
    -- Target Set Dropdown
    local targetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLabel:SetPoint("TOPLEFT", 20, -140)
    targetLabel:SetText("Target Set:")
    
    local targetDropdown = CreateFrame("Frame", "EqManagerEventTargetDropdown", frame, "UIDropDownMenuTemplate")
    targetDropdown:SetPoint("TOPLEFT", 10, -155)
    UIDropDownMenu_SetWidth(targetDropdown, 200)
    UIDropDownMenu_SetText(targetDropdown, "Select Set")
    
    local applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(80, 22)
    applyBtn:SetPoint("BOTTOMLEFT", 20, 15)
    applyBtn:SetText("Apply")
    
    local params = {
        selectedType = nil,
        selectedSubType = nil,
        selectedTarget = nil
    }
    
    -- Zone Loading Logic
    local function GetZoneChildrenSorted()
        local zones = {}
        local parentMapId = 947 -- Azeroth base map in modern APIs, may vary by expansion but covers most bases.
        -- C_Map is the standard Retail/Modern classic API
        if C_Map and C_Map.GetMapChildrenInfo then
            local children = C_Map.GetMapChildrenInfo(parentMapId)
            if children then
                for _, v in ipairs(children) do
                    table.insert(zones, v)
                end
            end
            local outlands = C_Map.GetMapInfo(1945)
            if outlands then table.insert(zones, outlands) end
        end
        table.sort(zones, function(a, b) return (a.name or "") < (b.name or "") end)
        return zones
    end

    -- Dropdown Initializers
    UIDropDownMenu_Initialize(typeDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, ev in ipairs(EVENT_TYPES) do
            info.text = ev.label
            info.value = ev.value
            info.func = function(self)
                UIDropDownMenu_SetSelectedID(typeDropdown, self:GetID())
                UIDropDownMenu_SetText(typeDropdown, ev.label)
                params.selectedType = ev.value
                params.selectedSubType = nil
                
                -- Dynamic hide/show of condition UI
                if ev.value == "ZONE_ENTER" then
                    subTypeLabel:Show()
                    subTypeBox:Hide()
                    subTypeDropdown:Show()
                    UIDropDownMenu_SetText(subTypeDropdown, "Select Zone")
                    helperText:SetText("Current zone: " .. (GetRealZoneText() or ""))
                    helperText:Show()
                elseif ev.value == "SHAPESHIFT" then
                    subTypeLabel:Show()
                    subTypeDropdown:Hide()
                    subTypeBox:Show()
                    subTypeBox:SetText("")
                    helperText:SetText("Enter form ID (e.g., 1, 2, 3...)")
                    helperText:Show()
                elseif ev.value == "SPEC_CHANGED" then
                    subTypeLabel:Show()
                    subTypeDropdown:Hide()
                    subTypeBox:Show()
                    subTypeBox:SetText("")
                    helperText:SetText("Enter Spec Index (1 or 2)")
                    helperText:Show()
                else
                    subTypeLabel:Hide()
                    subTypeBox:Hide()
                    subTypeDropdown:Hide()
                    helperText:Hide()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    UIDropDownMenu_Initialize(subTypeDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local zones = GetZoneChildrenSorted()
        for _, zoneInfo in ipairs(zones) do
            info.text = zoneInfo.name
            info.value = zoneInfo.name
            info.checked = function() return params.selectedSubType == zoneInfo.name end
            info.func = function(self)
                UIDropDownMenu_SetSelectedID(subTypeDropdown, self:GetID())
                UIDropDownMenu_SetText(subTypeDropdown, zoneInfo.name)
                params.selectedSubType = zoneInfo.name
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    UIDropDownMenu_Initialize(targetDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local sets = EqManager.Data:GetSetNames()
        for _, setName in ipairs(sets) do
            local setObj = EqManager.Data:GetSet(setName)
            info.text = setName
            info.value = setName
            info.checked = function() return params.selectedTarget == setName end
            info.func = function(self)
                UIDropDownMenu_SetSelectedID(targetDropdown, self:GetID())
                UIDropDownMenu_SetText(targetDropdown, setName)
                params.selectedTarget = setName
            end
            UIDropDownMenu_AddButton(info)
            
            -- Add unequip target capability only for partial sets
            if setObj and setObj.isPartial then
                local unequipName = "[-] " .. setName
                info.text = unequipName
                info.value = unequipName
                info.checked = function() return params.selectedTarget == unequipName end
                info.func = function(self)
                    UIDropDownMenu_SetSelectedID(targetDropdown, self:GetID())
                    UIDropDownMenu_SetText(targetDropdown, unequipName)
                    params.selectedTarget = unequipName
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    
    applyBtn:SetScript("OnClick", function()
        if EqManagerEventDialog.creatingAction then
            if not params.selectedTarget then
                print("|cFF00FFFFEqManager|r: Please select a Target Set.")
                return
            end
            
            local cIndex = EqManager.Data.db.CurrentEventIndex
            if cIndex then
                local success = EqManager.Data:AddEventAction(cIndex, params.selectedTarget)
                if success then
                    EqManager.UI:RefreshEventActionsList()
                    frame:Hide()
                else
                    print("|cFF00FFFFEqManager|r: This action already exists on this event!")
                end
            end
        else
            if not params.selectedType then
                print("|cFF00FFFFEqManager|r: Please select an Event Type.")
                return
            end
            
            local cond = nil
            if subTypeBox:IsVisible() then
                cond = subTypeBox:GetText()
            elseif subTypeDropdown:IsVisible() then
                cond = params.selectedSubType
            end
            
            local success = EqManager.Data:AddEvent(params.selectedType, cond)
            if success then
                EqManager.Data.db.CurrentEventIndex = #EqManager.Data.db.Events
                EqManager.UI:RefreshEventsList()
                frame:Hide()
            else
                print("|cFF00FFFFEqManager|r: That event already exists!")
            end
        end
    end)
    
    self.params = params
    self.typeDropdown = typeDropdown
    self.targetDropdown = targetDropdown
    self.typeLabel = typeLabel
    self.targetLabel = targetLabel
    self.subTypeLabel = subTypeLabel
    self.subTypeBox = subTypeBox
    self.subTypeDropdown = subTypeDropdown
    self.helperText = helperText
end

function EqManagerEventDialog:ShowDialog()
    -- reset
    self.params.selectedType = nil
    self.params.selectedSubType = nil
    self.params.selectedTarget = nil
    
    UIDropDownMenu_SetText(self.typeDropdown, "Select Event")
    UIDropDownMenu_SetText(self.targetDropdown, "Select Set")
    self.subTypeBox:SetText("")
    
    if self.creatingAction then
        self.title:SetText("Add Action to Event")
        self.typeLabel:Hide()
        self.typeDropdown:Hide()
        self.subTypeLabel:Hide()
        self.subTypeBox:Hide()
        self.subTypeDropdown:Hide()
        self.helperText:Hide()
        
        self.targetLabel:Show()
        self.targetDropdown:Show()
        self.targetLabel:SetPoint("TOPLEFT", 20, -40)
        self.targetDropdown:SetPoint("TOPLEFT", 10, -55)
    else
        self.title:SetText("Create Event Shell")
        self.typeLabel:Show()
        self.typeDropdown:Show()
        
        self.targetLabel:Hide()
        self.targetDropdown:Hide()
        self.subTypeLabel:Hide()
        self.subTypeBox:Hide()
        self.subTypeDropdown:Hide()
        self.helperText:Hide()
    end
    
    self:Show()
end
