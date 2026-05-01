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
    { label = "Submerge (Water)", value = "SUBMERGE" },
    { label = "Emerge (Water)", value = "EMERGE" },
    { label = "Join Party", value = "PARTY_JOIN" },
    { label = "Leave Party", value = "PARTY_LEAVE" },
    { label = "Join Raid", value = "RAID_JOIN" },
    { label = "Leave Raid", value = "RAID_LEAVE" },
    { label = "Enter Battleground", value = "BG_ENTER" },
    { label = "Leave Battleground", value = "BG_LEAVE" },
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

    local zonePickerBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    zonePickerBtn:SetSize(200, 22)
    zonePickerBtn:SetPoint("TOPLEFT", 25, -105)
    zonePickerBtn:SetText("Select Zone...")
    zonePickerBtn:Hide()
    
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
    
    -- PvP Filter (Action mode only)
    local pvpLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pvpLabel:SetPoint("TOPLEFT", 20, -90)
    pvpLabel:SetText("PvP Filter:")
    pvpLabel:Hide()

    local pvpBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pvpBtn:SetSize(200, 22)
    pvpBtn:SetPoint("TOPLEFT", 25, -105)
    pvpBtn:SetText("Any")
    pvpBtn:Hide()

    pvpBtn:SetScript("OnClick", function()
        if params.selectedPvp == "ANY" then 
            params.selectedPvp = "ENABLED"
            pvpBtn:SetText("PvP Only")
        elseif params.selectedPvp == "ENABLED" then 
            params.selectedPvp = "DISABLED"
            pvpBtn:SetText("Non-PvP")
        else 
            params.selectedPvp = "ANY"
            pvpBtn:SetText("Any")
        end
    end)
    
    -- Location Filter (Action mode only, for Mount/Dismount)
    local locationLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    locationLabel:SetPoint("TOPLEFT", 20, -140)
    locationLabel:SetText("Location Filter:")
    locationLabel:Hide()

    local locationBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    locationBtn:SetSize(200, 22)
    locationBtn:SetPoint("TOPLEFT", 25, -155)
    locationBtn:SetText("Any")
    locationBtn:Hide()

    locationBtn:SetScript("OnClick", function()
        if params.selectedLoc == "ANY" then 
            params.selectedLoc = "OUTLAND"
            locationBtn:SetText("Outland Only")
        elseif params.selectedLoc == "OUTLAND" then 
            params.selectedLoc = "NON_OUTLAND"
            locationBtn:SetText("Azeroth (Non-Outland)")
        else 
            params.selectedLoc = "ANY"
            locationBtn:SetText("Any")
        end
    end)

    local applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(80, 22)
    applyBtn:SetPoint("BOTTOMLEFT", 20, 15)
    applyBtn:SetText("Apply")
    
    local params = {
        selectedType = nil,
        selectedSubType = nil,
        selectedTarget = nil,
        selectedPvp = "ANY",
        selectedLoc = "ANY"
    }
    
    -- Zone Loading Logic
    local function GetZoneChildrenSorted()
        local zones = {}
        -- Top-level parent map IDs (World, Outland, Northrend, Pandaria, Draenor, etc.)
        local parents = { 947, 1945, 113, 424, 572, 619, 875, 876, 1550, 1978 }
        
        if C_Map and C_Map.GetMapChildrenInfo then
            local function scan(mapID)
                local children = C_Map.GetMapChildrenInfo(mapID)
                if children then
                    for _, v in ipairs(children) do
                        if v.mapType == 3 then -- MapType 3 is "Zone"
                            table.insert(zones, v)
                        elseif v.mapType == 2 then -- MapType 2 is "Continent"
                            scan(v.mapID) -- Recurse into continents
                        end
                    end
                end
            end
            
            for _, pId in ipairs(parents) do
                scan(pId)
            end
        end

        -- Always ensure current zone is in the list if available
        local currentMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if currentMapId then
            local info = C_Map.GetMapInfo(currentMapId)
            if info then
                local exists = false
                for _, z in ipairs(zones) do
                    if z.mapID == info.mapID then exists = true break end
                end
                if not exists then table.insert(zones, info) end
            end
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
                    subTypeDropdown:Hide()
                    zonePickerBtn:Show()
                    zonePickerBtn:SetText(params.selectedSubType or "Select Zone...")
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
                    subTypeBox:Hide()
                    subTypeDropdown:Show()
                    UIDropDownMenu_SetText(subTypeDropdown, "Select Spec")
                    helperText:Hide()
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
        
        if params.selectedType == "ZONE_ENTER" then
            -- Zone selection moved to ZonePicker
        elseif params.selectedType == "SPEC_CHANGED" then
            local specs = {
                { name = "Primary", value = "1" },
                { name = "Secondary", value = "2" }
            }
            for _, specInfo in ipairs(specs) do
                info.text = specInfo.name
                info.value = specInfo.value
                info.checked = function() return params.selectedSubType == specInfo.value end
                info.func = function(self)
                    UIDropDownMenu_SetSelectedID(subTypeDropdown, self:GetID())
                    UIDropDownMenu_SetText(subTypeDropdown, specInfo.name)
                    params.selectedSubType = specInfo.value
                end
                UIDropDownMenu_AddButton(info)
            end
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
                local success = EqManager.Data:AddEventAction(cIndex, params.selectedTarget, params.selectedPvp, params.selectedLoc)
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
            elseif subTypeDropdown:IsVisible() or zonePickerBtn:IsVisible() then
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
    
    -- Zone Picker Frame Implementation
    local picker = CreateFrame("Frame", "EqManagerZonePicker", UIParent, "BasicFrameTemplateWithInset")
    picker:SetSize(250, 350)
    picker:SetPoint("CENTER")
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:Hide()
    picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    picker.title:SetPoint("CENTER", picker.TitleBg, "CENTER", 0, 0)
    picker.title:SetText("Select Zone")

    local searchBox = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    searchBox:SetSize(210, 20)
    searchBox:SetPoint("TOPLEFT", 20, -35)
    searchBox:SetAutoFocus(false)

    local scrollFrame = CreateFrame("ScrollFrame", "EqManagerZonePickerScroll", picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(210, 1)
    scrollFrame:SetScrollChild(scrollContent)

    local zoneButtons = {}
    local function GetOrCreateZoneButton(index)
        if zoneButtons[index] then return zoneButtons[index] end
        local btn = CreateFrame("Button", nil, scrollContent)
        btn:SetSize(210, 20)
        btn:SetNormalFontObject("GameFontNormal")
        btn:SetHighlightFontObject("GameFontHighlight")
        btn:SetText(" ") -- Ensure FontString is created
        local fs = btn:GetFontString()
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", 5, 0)
        
        local tex = btn:CreateTexture(nil, "HIGHLIGHT")
        tex:SetAllPoints()
        tex:SetColorTexture(1, 1, 1, 0.1)
        
        btn:SetScript("OnClick", function()
            params.selectedSubType = btn.zoneName
            zonePickerBtn:SetText(btn.zoneName)
            picker:Hide()
        end)
        
        zoneButtons[index] = btn
        return btn
    end

    local function RefreshPicker()
        local filter = searchBox:GetText():lower()
        local zones = GetZoneChildrenSorted()
        local yOffset = 0
        local count = 0
        
        for _, btn in ipairs(zoneButtons) do btn:Hide() end
        
        for _, zone in ipairs(zones) do
            if filter == "" or zone.name:lower():find(filter, 1, true) then
                count = count + 1
                local btn = GetOrCreateZoneButton(count)
                btn.zoneName = zone.name
                btn:SetText(zone.name)
                btn:SetPoint("TOPLEFT", 0, yOffset)
                btn:Show()
                yOffset = yOffset - 20
            end
        end
        scrollContent:SetHeight(math.abs(yOffset))
    end

    searchBox:SetScript("OnTextChanged", RefreshPicker)
    zonePickerBtn:SetScript("OnClick", function()
        picker:Show()
        searchBox:SetText("")
        RefreshPicker()
    end)

    frame:HookScript("OnHide", function()
        picker:Hide()
    end)

    self.params = params
    self.typeDropdown = typeDropdown
    self.targetDropdown = targetDropdown
    self.typeLabel = typeLabel
    self.targetLabel = targetLabel
    self.subTypeLabel = subTypeLabel
    self.subTypeBox = subTypeBox
    self.subTypeDropdown = subTypeDropdown
    self.zonePickerBtn = zonePickerBtn
    self.helperText = helperText
    self.picker = picker
    self.pvpLabel = pvpLabel
    self.pvpBtn = pvpBtn
    self.locationLabel = locationLabel
    self.locationBtn = locationBtn
end

function EqManagerEventDialog:ShowDialog()
    -- reset
    self.params.selectedType = nil
    self.params.selectedSubType = nil
    self.params.selectedTarget = nil
    self.params.selectedPvp = "ANY"
    self.params.selectedLoc = "ANY"
    
    UIDropDownMenu_SetText(self.typeDropdown, "Select Event")
    UIDropDownMenu_SetText(self.targetDropdown, "Select Set")
    self.pvpBtn:SetText("Any")
    self.locationBtn:SetText("Any")
    self.subTypeBox:SetText("")
    
    if self.creatingAction then
        self.title:SetText("Add Action to Event")
        local eIdx = EqManager.Data.db.CurrentEventIndex
        local ev = EqManager.Data:GetEvents()[eIdx]

        self.typeLabel:Hide()
        self.typeDropdown:Hide()
        self.subTypeLabel:Hide()
        self.subTypeBox:Hide()
        self.subTypeDropdown:Hide()
        self.zonePickerBtn:Hide()
        self.helperText:Hide()
        
        self.targetLabel:Show()
        self.targetDropdown:Show()
        self.targetLabel:SetPoint("TOPLEFT", 20, -40)
        self.targetDropdown:SetPoint("TOPLEFT", 10, -55)

        self.pvpLabel:Show()
        self.pvpBtn:Show()
        self.pvpLabel:SetPoint("TOPLEFT", 20, -90)
        self.pvpBtn:SetPoint("TOPLEFT", 25, -105)

        if ev and (ev.type == "MOUNT" or ev.type == "DISMOUNT") then
            self.locationLabel:Show()
            self.locationBtn:Show()
            self:SetHeight(250)
        else
            self.locationLabel:Hide()
            self.locationBtn:Hide()
            self:SetHeight(200)
        end
    else
        self.title:SetText("Create Event Shell")
        self:SetHeight(250)
        self.typeLabel:Show()
        self.typeDropdown:Show()
        
        self.targetLabel:Hide()
        self.targetDropdown:Hide()
        self.subTypeLabel:Hide()
        self.subTypeBox:Hide()
        self.subTypeDropdown:Hide()
        self.zonePickerBtn:Hide()
        self.helperText:Hide()

        self.pvpLabel:Hide()
        self.pvpBtn:Hide()
        self.locationLabel:Hide()
        self.locationBtn:Hide()
    end
    
    self:Show()
end
