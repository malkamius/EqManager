--[[
    EqManagerEvents.lua
    Listens to standard WoW events (Combat, Casts) and passes signals to the Queue/Engine.
]]

EqManagerEvents = CreateFrame("Frame")
EqManager:RegisterModule("Events", EqManagerEvents)

function EqManagerEvents:Init()
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("UNIT_SPELLCAST_START")
    self:RegisterEvent("UNIT_SPELLCAST_STOP")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("ZONE_CHANGED")
    self:RegisterEvent("ZONE_CHANGED_INDOORS")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    self:RegisterEvent("UPDATE_STEALTH")
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    self:RegisterEvent("PLAYER_FLAGS_CHANGED")
    
    self.lastMountState = IsMounted() and not UnitOnTaxi("player")
    self.lastPvPState = UnitIsPVP("player")
    self.lastAFKState = EqManager.Data.db.LastAFKState or false

    -- Initial state check on login/reload
    local currentAFK = UnitIsAFK("player")
    if currentAFK ~= self.lastAFKState then
        self.lastAFKState = currentAFK
        EqManager.Data.db.LastAFKState = currentAFK
        if currentAFK then
            self:EvaluateBindings("AFK_ENTER")
        else
            self:EvaluateBindings("AFK_LEAVE")
        end
    end
    
    self:SetScript("OnEvent", self.OnSystemEvent)
end

function EqManagerEvents:EvaluateBindings(eventType, eventSubType)
    if EqManager.Options.DisableEvents then return end
    
    local eventSources = {
        COMBAT_ENTER = "Entering Combat",
        COMBAT_LEAVE = "Leaving Combat",
        ZONE_ENTER = "Zone Change",
        SHAPESHIFT = "Shapeshift",
        SHAPESHIFT_OUT = "Canceled Shapeshift",
        STEALTH_ENTER = "Entering Stealth",
        STEALTH_LEAVE = "Leaving Stealth",
        MOUNT = "Mounting",
        DISMOUNT = "Dismounting",
        SPEC_CHANGED = "Spec Change",
        PVP_ENTER = "Entering PvP",
        PVP_LEAVE = "Leaving PvP",
        AFK_ENTER = "Entering AFK",
        AFK_LEAVE = "Leaving AFK",
    }

    local sourceStr = eventSources[eventType] or eventType
    if eventSubType and eventSubType ~= "" then
        -- Avoid redundant info like "Zone Change (Orgrimmar)" if we can just say "Entering Orgrimmar"
        if eventType == "ZONE_ENTER" then
            sourceStr = "Entering " .. eventSubType
        elseif eventType == "SHAPESHIFT" then
            sourceStr = "Shapeshift: " .. eventSubType
        elseif eventType == "SPEC_CHANGED" then
            sourceStr = "Spec Change: " .. eventSubType
        else
            sourceStr = sourceStr .. " (" .. eventSubType .. ")"
        end
    end

    local events = EqManager.Data:GetEvents()
    for _, ev in ipairs(events) do
        if ev.type == eventType then
            local match = true
            if ev.subType and ev.subType ~= "" then
                if eventSubType and not string.find(string.lower(eventSubType), string.lower(ev.subType), 1, true) then
                    match = false
                end
            end
            
            if match and ev.actions then
                local isPvP = UnitIsPVP("player")
                for _, action in ipairs(ev.actions) do
                    local pvpMatch = true
                    if action.pvp == "ENABLED" and not isPvP then pvpMatch = false end
                    if action.pvp == "DISABLED" and isPvP then pvpMatch = false end
                    
                    if pvpMatch then
                        EqManager.Queue:QueueSet(action.setName, sourceStr)
                    end
                end
            end
        end
    end
end

function EqManagerEvents:OnSystemEvent(event, arg1, ...)
    if EqManager.Options.Debug then
        print("|cFF00FFFFEqManager|r: Debug Event:", event, arg1)
    end
    
    if event == "PLAYER_REGEN_DISABLED" then
        EqManager.Queue:SetCombatLockdown(true)
        self:EvaluateBindings("COMBAT_ENTER")
    elseif event == "PLAYER_REGEN_ENABLED" then
        EqManager.Queue:SetCombatLockdown(false)
        self:EvaluateBindings("COMBAT_LEAVE")
    elseif event == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then EqManager.Queue:SetCastingLockdown(true) end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if arg1 == "player" then EqManager.Queue:SetCastingLockdown(false) end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "PLAYER_ENTERING_WORLD" then
        local zone = GetRealZoneText()
        local subZone = GetSubZoneText()
        local area = (subZone and subZone ~= "") and subZone or zone
        if area then
            self:EvaluateBindings("ZONE_ENTER", area)
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        local form = GetShapeshiftFormID()
        if form then
            -- Note: For simplicity, passing string representation. Users can map specific IDs or Names.
            self:EvaluateBindings("SHAPESHIFT", tostring(form))
        else
            self:EvaluateBindings("SHAPESHIFT_OUT")
        end
    elseif event == "UPDATE_STEALTH" then
        local isStealthed = IsStealthed()
        if isStealthed then
            self:EvaluateBindings("STEALTH_ENTER")
        else
            self:EvaluateBindings("STEALTH_LEAVE")
        end
    elseif event == "UNIT_AURA" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        if event == "UNIT_AURA" and arg1 ~= "player" then return end
        
        local isMounted = IsMounted() and not UnitOnTaxi("player")
        if isMounted ~= self.lastMountState then
            self.lastMountState = isMounted
            if isMounted then
                self:EvaluateBindings("MOUNT")
            else
                self:EvaluateBindings("DISMOUNT")
            end
        end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        local currentSpec
        if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
            currentSpec = C_SpecializationInfo.GetActiveSpecGroup()
        elseif GetActiveTalentGroup then
            currentSpec = GetActiveTalentGroup()
        end
        
        if currentSpec then
            self:EvaluateBindings("SPEC_CHANGED", tostring(currentSpec))
        end
    elseif event == "PLAYER_FLAGS_CHANGED" then
        local isPvP = UnitIsPVP("player")
        if isPvP ~= self.lastPvPState then
            self.lastPvPState = isPvP
            if isPvP then
                self:EvaluateBindings("PVP_ENTER")
            else
                self:EvaluateBindings("PVP_LEAVE")
            end
        end

        local isAFK = UnitIsAFK("player")
        if isAFK ~= self.lastAFKState then
            self.lastAFKState = isAFK
            EqManager.Data.db.LastAFKState = isAFK
            if isAFK then
                self:EvaluateBindings("AFK_ENTER")
            else
                self:EvaluateBindings("AFK_LEAVE")
            end
        end
    end
end
