--[[
    EqManagerUI.lua
    Builds the main graphical interface matching the original EqManager design.
]]

EqManagerUI = {}
EqManager:RegisterModule("UI", EqManagerUI)

function EqManagerUI:Init()
    self:CreateMainFrame()
    self:InstallRepositionHooks()
end

function EqManagerUI:CreateMainFrame()
    local frame = CreateFrame("Frame", "EqManagerMainFrame", PaperDollFrame, "BasicFrameTemplateWithInset")
    frame:SetSize(340, 265)
    frame:SetFrameStrata("LOW")
    frame:Hide()
    
    if frame.CloseButton then
        frame.CloseButton:HookScript("OnClick", function()
            EM_OPTIONS.ShowUI = false
        end)
    end
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("EqManager")
    
    self.frame = frame

    frame:SetScript("OnShow", function()
        self:SetDynamicPosition()
        if self.currentMode == "EVENTS" then
            self:RefreshEventsList()
        else
            self:RefreshSetsList()
        end
    end)
    
    self.currentMode = "SETS"
    local modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    modeBtn:SetSize(80, 22)
    modeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -32)
    modeBtn:SetText("Events >")
    
    local setsContainer = CreateFrame("Frame", nil, frame)
    setsContainer:SetAllPoints()
    self.setsContainer = setsContainer
    
    local eventsContainer = CreateFrame("Frame", nil, frame)
    eventsContainer:SetAllPoints()
    eventsContainer:Hide()
    self.eventsContainer = eventsContainer
    
    modeBtn:SetScript("OnClick", function(self)
        if EqManager.UI.currentMode == "SETS" then
            EqManager.UI.currentMode = "EVENTS"
            self:SetText("< Sets")
            setsContainer:Hide()
            eventsContainer:Show()
            EqManager.UI:RefreshEventsList()
        else
            EqManager.UI.currentMode = "SETS"
            self:SetText("Events >")
            eventsContainer:Hide()
            setsContainer:Show()
            EqManager.UI:RefreshSetsList()
        end
    end)
    
    local border = CreateFrame("Frame", nil, setsContainer, "BackdropTemplate")
    border:SetSize(307, 140)
    border:SetPoint("TOPLEFT", 10, -60)
    border:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    border:SetBackdropColor(0, 0, 0, 0.5)

    self.scrollFrame = CreateFrame("ScrollFrame", "EqManagerMainScrollFrame", border, "UIPanelScrollFrameTemplate")
    self.scrollFrame:SetPoint("TOPLEFT", 5, -5)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    self.content = CreateFrame("Frame", nil, self.scrollFrame)
    self.content:SetSize(270, 10)
    self.scrollFrame:SetScrollChild(self.content)
    
    -- Removed the legacy floating infoFrame -> moved to event/settings frame below

    
    local addBtn = CreateFrame("Button", nil, setsContainer, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
    addBtn:SetText("Add set...")
    addBtn:SetScript("OnClick", function()
        EqManager.PaperDoll:PromptSaveSet(false) 
    end)

    local addPartialBtn = CreateFrame("Button", nil, setsContainer, "UIPanelButtonTemplate")
    addPartialBtn:SetSize(90, 22)
    addPartialBtn:SetPoint("BOTTOMLEFT", addBtn, "BOTTOMRIGHT", 5, 0)
    addPartialBtn:SetText("Add partial...")
    addPartialBtn:SetScript("OnClick", function()
        EqManager.PaperDoll:PromptSaveSet(true) 
    end)
    
    local saveBtn = CreateFrame("Button", nil, setsContainer, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
    saveBtn:SetText("Save set")
    -- In older UI, 'Save Set' updated the actively targeted set with current gear.
    saveBtn:SetScript("OnClick", function()
        local current = EqManager.Data.db.CurrentSet
        if current then
            EqManager.PaperDoll:SaveCurrentEquipmentAsSet(current)
        end
    end)
    
    local removeBtn = CreateFrame("Button", nil, setsContainer, "UIPanelButtonTemplate")
    removeBtn:SetSize(90, 22)
    removeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 10)
    removeBtn:SetText("Remove set")
    removeBtn:SetScript("OnClick", function()
        local current = EqManager.Data.db.CurrentSet
        if current then
            local isActive = false
            for _, name in ipairs(EqManager.Data:GetActivePartialSets()) do
                if name == current then isActive = true break end
            end
            if isActive then
                EqManager.Engine:UnequipPartialSet(current)
            end
            EqManager.Data:RemoveSet(current)
            EqManager.UI:RefreshSetsList()
        end
    end)
    
    self.setEntries = {}

    -- Set Settings Lower Frame
    local setSettingsFrame = CreateFrame("Frame", "EqManagerSetSettingsFrame", setsContainer, "BasicFrameTemplateWithInset")
    setSettingsFrame:SetSize(340, 252)
    setSettingsFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 5)
    if setSettingsFrame.CloseButton then setSettingsFrame.CloseButton:Hide() end
    setSettingsFrame:Hide()
    
    setSettingsFrame.title = setSettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    setSettingsFrame.title:SetPoint("CENTER", setSettingsFrame.TitleBg, "CENTER", 0, 0)
    setSettingsFrame.title:SetText("Settings")

    -- Section: Set Settings
    local setHeader = setSettingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    setHeader:SetPoint("TOPLEFT", 15, -30)
    setHeader:SetText("SET-SPECIFIC")
    setHeader:SetTextColor(0.7, 0.7, 0.7)

    local cbInfoPartial = CreateFrame("CheckButton", nil, setSettingsFrame, "ChatConfigCheckButtonTemplate")
    cbInfoPartial:SetPoint("TOPLEFT", 15, -45)
    cbInfoPartial.text = cbInfoPartial:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cbInfoPartial.text:SetPoint("LEFT", cbInfoPartial, "RIGHT", 5, 0)
    cbInfoPartial.text:SetText("Partial Set")

    cbInfoPartial:SetScript("OnClick", function(self)
        local current = EqManager.Data.db.CurrentSet
        if current then
            local set = EqManager.Data:GetSet(current)
            if set then
                set.isPartial = self:GetChecked()
                if set.isPartial then
                    EqManager.PaperDoll:AutoDetectPartialSlots(current)
                    EqManager.PaperDoll:ShowSlotStateBoxes()
                else
                    local isActive = false
                    for _, name in ipairs(EqManager.Data:GetActivePartialSets()) do
                        if name == current then isActive = true break end
                    end
                    if isActive then
                        EqManager.Engine:UnequipPartialSet(current)
                    end
                    EqManager.PaperDoll:HideSlotStateBoxes()
                end
                EqManager.UI:RefreshSetsList()
            end
        end
    end)

    local cbKeepOnBaseSwap = CreateFrame("CheckButton", nil, setSettingsFrame, "ChatConfigCheckButtonTemplate")
    cbKeepOnBaseSwap:SetPoint("TOPLEFT", 15, -65)
    cbKeepOnBaseSwap.text = cbKeepOnBaseSwap:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cbKeepOnBaseSwap.text:SetPoint("LEFT", cbKeepOnBaseSwap, "RIGHT", 5, 0)
    cbKeepOnBaseSwap.text:SetText("Keep Equipped on Base Swap")

    cbKeepOnBaseSwap:SetScript("OnClick", function(self)
        local current = EqManager.Data.db.CurrentSet
        if current then
            local set = EqManager.Data:GetSet(current)
            if set then
                set.keepOnBaseSwap = self:GetChecked()
            end
        end
    end)

    local cbAutoDetect = CreateFrame("CheckButton", nil, setSettingsFrame, "ChatConfigCheckButtonTemplate")
    cbAutoDetect:SetPoint("TOPLEFT", 15, -85)
    cbAutoDetect.text = cbAutoDetect:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cbAutoDetect.text:SetPoint("LEFT", cbAutoDetect, "RIGHT", 5, 0)
    cbAutoDetect.text:SetText("Auto-Detect Equipped")

    cbAutoDetect:SetScript("OnClick", function(self)
        local current = EqManager.Data.db.CurrentSet
        if current then
            local set = EqManager.Data:GetSet(current)
            if set then
                set.autoDetect = self:GetChecked()
                -- If they just toggled this on, we should trigger a detection pass immediately
                if set.autoDetect and EqManager.Engine.CheckAutoDetectSets then
                    EqManager.Engine:CheckAutoDetectSets()
                end
            end
        end
    end)

    cbInfoPartial:HookScript("OnClick", function(self)
        if self:GetChecked() then
            cbKeepOnBaseSwap:Show()
            cbKeepOnBaseSwap.text:Show()
            cbAutoDetect:Show()
            cbAutoDetect.text:Show()
        else
            cbKeepOnBaseSwap:Hide()
            cbKeepOnBaseSwap.text:Hide()
            cbAutoDetect:Hide()
            cbAutoDetect.text:Hide()
        end
    end)

    -- Separator
    local line = setSettingsFrame:CreateTexture(nil, "ARTWORK")
    line:SetSize(310, 1)
    line:SetPoint("TOPLEFT", 15, -140)
    line:SetColorTexture(1, 1, 1, 0.2)

    -- Section: Global Settings
    local globalHeader = setSettingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    globalHeader:SetPoint("TOPLEFT", 15, -150)
    globalHeader:SetText("GLOBAL SETTINGS")
    globalHeader:SetTextColor(0.7, 0.7, 0.7)

    local updateLabel = setSettingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    updateLabel:SetPoint("TOPLEFT", 15, -165)
    updateLabel:SetText("Auto-update gear:")

    local updateDropdown = CreateFrame("Frame", "EqManagerUpdateDropdown", setSettingsFrame, "UIDropDownMenuTemplate")
    updateDropdown:SetPoint("LEFT", updateLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(updateDropdown, 140)
    self.updateDropdown = updateDropdown

    local delayLabel = setSettingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    delayLabel:SetPoint("TOPLEFT", 15, -190)
    delayLabel:SetText("Swap delay (sec):")

    local delayEdit = CreateFrame("EditBox", nil, setSettingsFrame, "InputBoxTemplate")
    delayEdit:SetSize(45, 20)
    delayEdit:SetPoint("LEFT", delayLabel, "RIGHT", 10, 0)
    delayEdit:SetAutoFocus(false)
    -- We'll use a standard editbox since decimals are needed
    delayEdit:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            EM_OPTIONS.SwapDelay = val
            print("|cFF00FFFFEqManager|r: Swap delay set to " .. val .. "s")
        end
        self:ClearFocus()
    end)
    delayEdit:SetScript("OnShow", function(self)
        self:SetText(tostring(EM_OPTIONS.SwapDelay or 0.1))
    end)
    self.delayEdit = delayEdit
    
    local cbBagDimming = CreateFrame("CheckButton", nil, setSettingsFrame, "ChatConfigCheckButtonTemplate")
    cbBagDimming:SetPoint("TOPLEFT", 15, -215)
    cbBagDimming.text = cbBagDimming:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cbBagDimming.text:SetPoint("LEFT", cbBagDimming, "RIGHT", 5, 0)
    cbBagDimming.text:SetText("Enable Bag Dimming")

    cbBagDimming:SetScript("OnClick", function(self)
        EqManager.Bags:ToggleDimming(self:GetChecked())
    end)
    self.cbBagDimming = cbBagDimming

    self.setSettingsFrame = setSettingsFrame
    self.cbInfoPartial = cbInfoPartial
    self.cbKeepOnBaseSwap = cbKeepOnBaseSwap
    self.cbAutoDetect = cbAutoDetect
    self.setHeader = setHeader
    
    -- === EVENTS TAB UI ===
    local evBorder = CreateFrame("Frame", nil, eventsContainer, "BackdropTemplate")
    evBorder:SetSize(307, 140)
    evBorder:SetPoint("TOPLEFT", 10, -60)
    evBorder:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    evBorder:SetBackdropColor(0, 0, 0, 0.5)

    self.evScrollFrame = CreateFrame("ScrollFrame", "EqManagerEventsScrollFrame", evBorder, "UIPanelScrollFrameTemplate")
    self.evScrollFrame:SetPoint("TOPLEFT", 5, -5)
    self.evScrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    self.evContent = CreateFrame("Frame", nil, self.evScrollFrame)
    self.evContent:SetSize(270, 10)
    self.evScrollFrame:SetScrollChild(self.evContent)
    
    self.masterEventEntries = {}
    
    local evAddBtn = CreateFrame("Button", nil, eventsContainer, "UIPanelButtonTemplate")
    evAddBtn:SetSize(120, 22)
    evAddBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
    evAddBtn:SetText("Add Event...")
    evAddBtn:SetScript("OnClick", function()
        if EqManager.EventDialog then
            EqManager.EventDialog.creatingAction = false
            EqManager.EventDialog:ShowDialog()
        end
    end)
    
    local evRemoveBtn = CreateFrame("Button", nil, eventsContainer, "UIPanelButtonTemplate")
    evRemoveBtn:SetSize(90, 22)
    evRemoveBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 10)
    evRemoveBtn:SetText("Remove Event")
    evRemoveBtn:SetScript("OnClick", function()
        if EqManager.Data.db.CurrentEventIndex then
            EqManager.Data:RemoveEvent(EqManager.Data.db.CurrentEventIndex)
            EqManager.Data.db.CurrentEventIndex = nil
            EqManager.UI:RefreshEventsList()
        end
    end)
    
    -- Event Actions Lower Frame
    local actionSettingsFrame = CreateFrame("Frame", "EqManagerActionFrame", eventsContainer, "BasicFrameTemplateWithInset")
    actionSettingsFrame:SetSize(340, 212)
    actionSettingsFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 5)
    if actionSettingsFrame.CloseButton then actionSettingsFrame.CloseButton:Hide() end
    actionSettingsFrame:Hide()
    
    actionSettingsFrame.title = actionSettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    actionSettingsFrame.title:SetPoint("CENTER", actionSettingsFrame.TitleBg, "CENTER", 0, 0)
    actionSettingsFrame.title:SetText("Event Actions")

    local actBorder = CreateFrame("Frame", nil, actionSettingsFrame, "BackdropTemplate")
    actBorder:SetSize(307, 85)
    actBorder:SetPoint("TOPLEFT", 10, -35)
    actBorder:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    actBorder:SetBackdropColor(0, 0, 0, 0.5)

    self.actScrollFrame = CreateFrame("ScrollFrame", "EqManagerActionsScrollFrame", actBorder, "UIPanelScrollFrameTemplate")
    self.actScrollFrame:SetPoint("TOPLEFT", 5, -5)
    self.actScrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    self.actContent = CreateFrame("Frame", nil, self.actScrollFrame)
    self.actContent:SetSize(270, 10)
    self.actScrollFrame:SetScrollChild(self.actContent)
    
    self.actionEntries = {}

    -- Details Panel
    local details = CreateFrame("Frame", nil, actionSettingsFrame)
    details:SetSize(320, 80)
    details:SetPoint("TOPLEFT", actBorder, "BOTTOMLEFT", 0, -5)
    self.actionDetailsPanel = details
    details:Hide()

    local targetLabel = details:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabel:SetPoint("TOPLEFT", 5, -5)
    targetLabel:SetText("Target Set:")

    local targetDropdown = CreateFrame("Frame", "EqManagerActionTargetDropdown", details, "UIDropDownMenuTemplate")
    targetDropdown:SetPoint("TOPLEFT", -15, -15)
    UIDropDownMenu_SetWidth(targetDropdown, 160)
    self.actionTargetDropdown = targetDropdown

    local pvpLabel = details:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pvpLabel:SetPoint("TOPLEFT", 190, -5)
    pvpLabel:SetText("PvP Filter:")

    local pvpBtn = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
    pvpBtn:SetSize(90, 22)
    pvpBtn:SetPoint("TOPLEFT", 195, -20)
    self.actionPvpBtn = pvpBtn

    pvpBtn:SetScript("OnClick", function()
        local eIdx = EqManager.Data.db.CurrentEventIndex
        local aIdx = EqManager.Data.db.CurrentActionIndex
        if eIdx and aIdx then
            local ev = EqManager.Data:GetEvents()[eIdx]
            local act = ev.actions[aIdx]
            local nextState = "ANY"
            if act.pvp == "ANY" then nextState = "ENABLED"
            elseif act.pvp == "ENABLED" then nextState = "DISABLED"
            end
            EqManager.Data:UpdateEventAction(eIdx, aIdx, { pvp = nextState })
            EqManager.UI:RefreshEventActionsList()
        end
    end)
    
    local addActionBtn = CreateFrame("Button", nil, actionSettingsFrame, "UIPanelButtonTemplate")
    addActionBtn:SetSize(90, 22)
    addActionBtn:SetPoint("BOTTOMRIGHT", actionSettingsFrame, "BOTTOMRIGHT", -15, 10)
    addActionBtn:SetText("Add action...")
    addActionBtn:SetScript("OnClick", function()
        if EqManager.EventDialog and EqManager.Data.db.CurrentEventIndex then
            EqManager.EventDialog.creatingAction = true
            EqManager.EventDialog:ShowDialog()
        end
    end)
    
    self.actionSettingsFrame = actionSettingsFrame
    
    local disableEvtsBtn = CreateFrame("CheckButton", nil, eventsContainer, "ChatConfigCheckButtonTemplate")
    disableEvtsBtn:SetPoint("TOPLEFT", eventsContainer, "TOPLEFT", 15, -27)
    disableEvtsBtn.text = disableEvtsBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    disableEvtsBtn.text:SetPoint("LEFT", disableEvtsBtn, "RIGHT", 5, 0)
    disableEvtsBtn.text:SetText("Disable events")
    disableEvtsBtn:SetScript("OnClick", function(self)
        EM_OPTIONS.DisableEvents = self:GetChecked()
    end)
end

-- Finds the rightmost visible frame within the CharacterFrame subtree
-- (e.g. Extended Character Stats, DejaCharacterStats, ElvUI panels, or even
-- Blizzard's own CharacterStatsPane).  Returns the right-edge pixel position
-- so EqManager can position itself just past it.
function EqManagerUI:FindRightmostCharacterPanel()
    if not CharacterFrame then return nil end

    local bestRight = CharacterFrame:GetRight() or 0

    -- Recursively walk every descendant of CharacterFrame.
    -- We skip our own frame subtree and quickslot bars.
    local function scanDescendants(parent)
        if not parent or not parent.GetChildren then return end
        local children = { parent:GetChildren() }
        for _, child in ipairs(children) do
            -- Skip the EqManager main frame subtree
            if child == self.frame then
                -- skip entirely, don't recurse
            else
                -- Skip EqManager quickslot bars
                local name = child.GetName and child:GetName()
                local isQuickbar = name and name:find("^EqManagerQuickBar_")

                if not isQuickbar
                   and child.IsVisible and child:IsVisible()
                   and child.GetRight then
                    local right = child:GetRight()
                    if right and right > bestRight then
                        bestRight = right
                    end
                end

                scanDescendants(child)  -- always recurse (even into hidden parents with visible children)
            end
        end
    end

    scanDescendants(CharacterFrame)
    return bestRight
end

function EqManagerUI:SetDynamicPosition()
    if not self.frame then return end

    local rightEdge = self:FindRightmostCharacterPanel()

    self.frame:ClearAllPoints()

    if rightEdge then
        -- Anchor top to PaperDollFrame's top, horizontal position to the
        -- rightmost edge of whatever panels are open.
        local scale = self.frame:GetEffectiveScale()
        local pdLeft = PaperDollFrame:GetLeft() or 0
        local xOffset = (rightEdge - pdLeft) * (PaperDollFrame:GetEffectiveScale() / scale)
        self.frame:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", xOffset, -14)
    else
        self.frame:SetPoint("TOPLEFT", PaperDollFrame, "TOPRIGHT", 0, -14)
    end
end

-- Install hooks on CharacterFrame's descendants so we reposition whenever
-- another side-panel addon shows or hides.  Called once during Init.
function EqManagerUI:InstallRepositionHooks()
    if self._hooksInstalled then return end
    self._hooksInstalled = true
    self._hookedFrames   = {}

    local function onChildVisibilityChanged()
        if self.frame and self.frame:IsVisible() then
            self:SetDynamicPosition()
        end
    end

    local function hookFrame(frame)
        if frame and not self._hookedFrames[frame] and frame ~= self.frame then
            self._hookedFrames[frame] = true
            if frame.HookScript then
                frame:HookScript("OnShow", onChildVisibilityChanged)
                frame:HookScript("OnHide", onChildVisibilityChanged)
            end
        end
    end

    -- Recursively hook all descendants of CharacterFrame, skipping
    -- our own frame subtree.
    local function hookDescendants(parent)
        if not parent or not parent.GetChildren then return end
        local children = { parent:GetChildren() }
        for _, child in ipairs(children) do
            if child ~= self.frame then
                hookFrame(child)
                hookDescendants(child)
            end
        end
    end

    -- Run the scan now.
    if CharacterFrame then
        hookDescendants(CharacterFrame)

        -- Re-scan every time CharacterFrame is shown, in case a lazily-loaded
        -- addon added new frames since the last scan.
        CharacterFrame:HookScript("OnShow", function()
            hookDescendants(CharacterFrame)
        end)
    end
end

function EqManagerUI:RefreshSetsList()
    for _, btn in ipairs(self.setEntries) do btn:Hide() end
    
    local setNames = EqManager.Data:GetSetNames()
    local yOffset = 0
    
    local currentFound = false
    
    for i, setName in ipairs(setNames) do
        local entry = self.setEntries[i]
        if not entry then
            entry = self:CreateSetEntry(i)
            self.setEntries[i] = entry
        end
        
        entry.setName = setName
        
        local set = EqManager.Data:GetSet(setName)
        if set and set.isPartial then
            entry.nameText:SetText(setName .. " (P)")
        else
            entry.nameText:SetText(setName)
        end
        
        if set then
            local isChecked = false
            if EqManager.Data.db.BaseFullSet == setName then
                isChecked = true
            end
            for _, partialName in ipairs(EqManager.Data:GetActivePartialSets()) do
                if partialName == setName then
                    isChecked = true
                    break
                end
            end
            entry.cbSelection:SetChecked(isChecked)
            
            if EqManager.Data.db.CurrentSet == setName then 
                currentFound = true 
                if entry.selectedTex then entry.selectedTex:Show() end
            else
                if entry.selectedTex then entry.selectedTex:Hide() end
            end
        end
        
        entry:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, yOffset)
        entry:Show()
        yOffset = yOffset - 30
    end
    
    self.content:SetHeight(math.abs(yOffset))
    
    if currentFound then
        local set = EqManager.Data:GetSet(EqManager.Data.db.CurrentSet)
        self.cbInfoPartial:SetChecked(set and set.isPartial)
        self.cbInfoPartial:Show()
        self.cbInfoPartial.text:Show()
        self.setHeader:Show()
        
        if set and set.isPartial then
            EqManager.PaperDoll:ShowSlotStateBoxes()
            self.cbKeepOnBaseSwap:SetChecked(set.keepOnBaseSwap)
            self.cbKeepOnBaseSwap:Show()
            self.cbKeepOnBaseSwap.text:Show()
            self.cbAutoDetect:SetChecked(set.autoDetect)
            self.cbAutoDetect:Show()
            self.cbAutoDetect.text:Show()
        else
            EqManager.PaperDoll:HideSlotStateBoxes()
            self.cbKeepOnBaseSwap:Hide()
            self.cbKeepOnBaseSwap.text:Hide()
            self.cbAutoDetect:Hide()
            self.cbAutoDetect.text:Hide()
        end
    else
        self.cbInfoPartial:Hide()
        self.cbInfoPartial.text:Hide()
        self.setHeader:Hide()
        self.cbKeepOnBaseSwap:Hide()
        self.cbKeepOnBaseSwap.text:Hide()
        self.cbAutoDetect:Hide()
        self.cbAutoDetect.text:Hide()
        EqManager.PaperDoll:HideSlotStateBoxes()
    end
    
    local updateConditions = {
        { text = "Disabled", value = "DISABLED" },
        { text = "Character Frame", value = "CHARACTER" },
        { text = "Sets Frame", value = "SETS" },
        { text = "Either Frame", value = "BOTH" },
        { text = "Always", value = "ALWAYS" },
    }

    local currentCond = EM_OPTIONS.AutoUpdateCondition or "CHARACTER"
    local currentText = "Character Frame"
    for _, opt in ipairs(updateConditions) do
        if opt.value == currentCond then
            currentText = opt.text
            break
        end
    end

    UIDropDownMenu_SetText(self.updateDropdown, currentText)
    UIDropDownMenu_Initialize(self.updateDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs(updateConditions) do
            info.text = opt.text
            info.arg1 = opt.value
            info.func = function(self, arg1)
                EM_OPTIONS.AutoUpdateCondition = arg1
                UIDropDownMenu_SetText(EqManagerUI.updateDropdown, self:GetText())
                print("|cFF00FFFFEqManager|r: Auto-update gear set to |cFFFFFF00" .. self:GetText() .. "|r.")
            end
            info.checked = (opt.value == EM_OPTIONS.AutoUpdateCondition)
            UIDropDownMenu_AddButton(info)
        end
    end)
    self.cbBagDimming:SetChecked(EM_OPTIONS.EnableBagDimming)
    self.setSettingsFrame:Show()
end

function EqManagerUI:RefreshEventsList()
    for _, btn in ipairs(self.masterEventEntries) do btn:Hide() end
    
    local events = EqManager.Data:GetEvents()
    local yOffset = 0
    local currentFound = false
    
    for i, ev in ipairs(events) do
        local entry = self.masterEventEntries[i]
        if not entry then
            entry = self:CreateEventEntry()
            self.masterEventEntries[i] = entry
        end
        
        entry.dbIndex = i
        local label = ev.type
        if ev.subType and ev.subType ~= "" then
            label = label .. " (" .. ev.subType .. ")"
        end
        entry.nameText:SetText(label)
        
        if EqManager.Data.db.CurrentEventIndex == i then
            currentFound = true
            if entry.selectedTex then entry.selectedTex:Show() end
        else
            if entry.selectedTex then entry.selectedTex:Hide() end
        end
        
        entry:SetPoint("TOPLEFT", self.evContent, "TOPLEFT", 0, yOffset)
        entry:Show()
        yOffset = yOffset - 30
    end
    
    self.evContent:SetHeight(math.abs(yOffset))
    
    if currentFound then
        self.actionSettingsFrame:Show()
        self:RefreshEventActionsList()
    else
        self.actionSettingsFrame:Hide()
    end
end

function EqManagerUI:CreateEventEntry()
    local entry = CreateFrame("Button", nil, self.evContent)
    entry:SetSize(260, 25)
    
    entry:SetScript("OnClick", function(self)
        EqManager.Data.db.CurrentEventIndex = self.dbIndex
        EqManager.UI:RefreshEventsList()
    end)
    
    local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    local selected = entry:CreateTexture(nil, "ARTWORK")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.8, 0, 0.3)
    entry.selectedTex = selected
    
    entry.nameText = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    entry.nameText:SetPoint("LEFT", 5, 0)
    
    return entry
end

function EqManagerUI:RefreshEventActionsList()
    for _, btn in ipairs(self.actionEntries) do btn:Hide() end
    
    local currentIndex = EqManager.Data.db.CurrentEventIndex
    if not currentIndex then return end
    
    local ev = EqManager.Data:GetEvents()[currentIndex]
    if not ev or not ev.actions then return end
    
    local yOffset = 0
    local selectedFound = false
    
    for i, act in ipairs(ev.actions) do
        local entry = self.actionEntries[i]
        if not entry then
            entry = self:CreateActionEntry()
            self.actionEntries[i] = entry
        end
        
        entry.actionIndex = i
        local label = act.setName
        if act.pvp == "ENABLED" then label = label .. " |cFF00FF00(PvP)|r"
        elseif act.pvp == "DISABLED" then label = label .. " |cFFFF0000(NoPvP)|r"
        end
        entry.nameText:SetText(label)
        
        if EqManager.Data.db.CurrentActionIndex == i then
            selectedFound = true
            entry.selectedTex:Show()
        else
            entry.selectedTex:Hide()
        end
        
        entry:SetPoint("TOPLEFT", self.actContent, "TOPLEFT", 0, yOffset)
        entry:Show()
        yOffset = yOffset - 22
    end
    
    self.actContent:SetHeight(math.abs(yOffset))
    
    if selectedFound then
        self:RefreshActionDetails()
    else
        self.actionDetailsPanel:Hide()
    end
end

function EqManagerUI:RefreshActionDetails()
    local eIdx = EqManager.Data.db.CurrentEventIndex
    local aIdx = EqManager.Data.db.CurrentActionIndex
    if not eIdx or not aIdx then return end
    
    local ev = EqManager.Data:GetEvents()[eIdx]
    local act = ev.actions[aIdx]
    if not act then return end
    
    self.actionDetailsPanel:Show()
    UIDropDownMenu_SetText(self.actionTargetDropdown, act.setName)
    UIDropDownMenu_Initialize(self.actionTargetDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local sets = EqManager.Data:GetSetNames()
        for _, name in ipairs(sets) do
            info.text = name
            info.func = function()
                EqManager.Data:UpdateEventAction(eIdx, aIdx, { setName = name })
                EqManager.UI:RefreshEventActionsList()
            end
            UIDropDownMenu_AddButton(info)
            
            local unequip = "[-] " .. name
            info.text = unequip
            info.func = function()
                EqManager.Data:UpdateEventAction(eIdx, aIdx, { setName = unequip })
                EqManager.UI:RefreshEventActionsList()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    local pvpLabel = "Any"
    if act.pvp == "ENABLED" then pvpLabel = "PvP Only"
    elseif act.pvp == "DISABLED" then pvpLabel = "Non-PvP"
    end
    self.actionPvpBtn:SetText(pvpLabel)
end

function EqManagerUI:CreateActionEntry()
    local entry = CreateFrame("Button", nil, self.actContent)
    entry:SetSize(260, 20)
    
    entry:SetScript("OnClick", function(self)
        EqManager.Data.db.CurrentActionIndex = self.actionIndex
        EqManager.UI:RefreshEventActionsList()
    end)
    
    local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    local selected = entry:CreateTexture(nil, "ARTWORK")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.8, 0, 0.2)
    entry.selectedTex = selected
    
    local removeBtn = CreateFrame("Button", nil, entry, "UIPanelCloseButton")
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("LEFT", 0, 0)
    removeBtn:SetScript("OnClick", function(self)
        local currentIndex = EqManager.Data.db.CurrentEventIndex
        if currentIndex then
            EqManager.Data:RemoveEventAction(currentIndex, entry.actionIndex)
            EqManager.Data.db.CurrentActionIndex = nil
            EqManager.UI:RefreshEventActionsList()
        end
    end)
    entry.removeBtn = removeBtn
    
    entry.nameText = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    entry.nameText:SetPoint("LEFT", removeBtn, "RIGHT", 5, 0)
    
    return entry
end

function EqManagerUI:CreateSetEntry(index)
    local entry = CreateFrame("Button", nil, self.content)
    entry:SetSize(260, 25)
    
    entry:SetScript("OnClick", function(self)
        EqManager.Data.db.CurrentSet = self.setName
        EqManager.UI:RefreshSetsList()
    end)
    
    local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    local selected = entry:CreateTexture(nil, "ARTWORK")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.8, 0, 0.3)
    entry.selectedTex = selected
    
    local cbSelection = CreateFrame("CheckButton", nil, entry, "ChatConfigCheckButtonTemplate")
    cbSelection:SetPoint("LEFT", 0, 0)
    cbSelection:SetScript("OnClick", function(self)
        EqManager.Data.db.CurrentSet = entry.setName
        
        if self:GetChecked() then
            EqManager.Queue:QueueSet(entry.setName)
        else
            local set = EqManager.Data:GetSet(entry.setName)
            if set and set.isPartial then
                EqManager.Engine:UnequipPartialSet(entry.setName)
            end
        end
        
        EqManager.UI:RefreshSetsList()
    end)
    entry.cbSelection = cbSelection
    
    entry.nameText = entry:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    entry.nameText:SetPoint("LEFT", cbSelection, "RIGHT", 5, 0)
    
    return entry
end
