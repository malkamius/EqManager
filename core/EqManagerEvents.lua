--[[
    EqManagerEvents.lua
    Listens to standard WoW events (Combat, Casts) and passes signals to the Queue/Engine.
]]

EqManagerEvents = CreateFrame("Frame")
EqManager:RegisterModule("Events", EqManagerEvents)

function EqManagerEvents:Init()
    EqManager.API.RegisterEvent(self, "PLAYER_REGEN_DISABLED")
    EqManager.API.RegisterEvent(self, "PLAYER_REGEN_ENABLED")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_START")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_STOP")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_FAILED")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_INTERRUPTED")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_START")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_STOP")
    EqManager.API.RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_UPDATE")
    EqManager.API.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA")
    EqManager.API.RegisterEvent(self, "ZONE_CHANGED")
    EqManager.API.RegisterEvent(self, "ZONE_CHANGED_INDOORS")
    EqManager.API.RegisterEvent(self, "PLAYER_ENTERING_WORLD")
    EqManager.API.RegisterEvent(self, "UPDATE_SHAPESHIFT_FORM")
    EqManager.API.RegisterEvent(self, "UPDATE_STEALTH")
    EqManager.API.RegisterEvent(self, "ACTIVE_TALENT_GROUP_CHANGED")
    EqManager.API.RegisterEvent(self, "UNIT_AURA")
    EqManager.API.RegisterEvent(self, "PLAYER_MOUNT_DISPLAY_CHANGED")
    EqManager.API.RegisterEvent(self, "PLAYER_FLAGS_CHANGED")
    EqManager.API.RegisterEvent(self, "SPELL_UPDATE_USABLE")
    EqManager.API.RegisterEvent(self, "MIRROR_TIMER_START")
    EqManager.API.RegisterEvent(self, "MIRROR_TIMER_STOP")
    EqManager.API.RegisterEvent(self, "GROUP_ROSTER_UPDATE")
    EqManager.API.RegisterEvent(self, "RAID_ROSTER_UPDATE")
    
    EqManager.API.RegisterEvent(self, "PLAYER_SPECIALIZATION_CHANGED")
    self.lastMountState = IsMounted() and not UnitOnTaxi("player")
    self.lastFormID = GetShapeshiftFormID()
    self.lastPvPState = UnitIsPVP("player")
    self.lastAFKState = EqManager.Data.db.LastAFKState or false
    self.lastSubmergedState = IsSwimming()
    self.lastPartyState = IsInGroup()
    self.lastRaidState = IsInRaid()

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

function EqManagerEvents:CheckMountState()
    local isMounted = IsMounted() and not UnitOnTaxi("player")
    if isMounted ~= self.lastMountState then
        self.lastMountState = isMounted
        if isMounted then
            self:EvaluateBindings("MOUNT")
        else
            self:EvaluateBindings("DISMOUNT")
        end
    end
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
        SUBMERGE = "Submerging",
        EMERGE = "Emerging",
        PARTY_JOIN = "Joining Party",
        PARTY_LEAVE = "Leaving Party",
        RAID_JOIN = "Joining Raid",
        RAID_LEAVE = "Leaving Raid",
        BG_ENTER = "Entering Battleground",
        BG_LEAVE = "Leaving Battleground",
    }

    local sourceStr = eventSources[eventType] or eventType
    if eventSubType and eventSubType ~= "" then
        -- Avoid redundant info like "Zone Change (Orgrimmar)" if we can just say "Entering Orgrimmar"
        if eventType == "ZONE_ENTER" then
            sourceStr = "Entering " .. eventSubType
        elseif eventType == "SHAPESHIFT" then
            sourceStr = "Shapeshift: " .. EqManager:GetFormNameByID(eventSubType)
        elseif eventType == "SHAPESHIFT_OUT" then
            sourceStr = "Leave Shapeshift: " .. EqManager:GetFormNameByID(eventSubType)
        elseif eventType == "SPEC_CHANGED" then
            local specName = (eventSubType == "1") and "Primary" or (eventSubType == "2" and "Secondary" or eventSubType)
            sourceStr = "Spec Change: " .. specName
        else
            sourceStr = sourceStr .. " (" .. eventSubType .. ")"
        end
    end

    local events = EqManager.Data:GetEvents()
    for _, ev in ipairs(events) do
        if ev.type == eventType then
            local match = true
            if ev.subType and ev.subType ~= "" then
                local subMatch = false
                if string.find(string.lower(eventSubType or ""), string.lower(ev.subType), 1, true) then
                    subMatch = true
                elseif eventType == "SPEC_CHANGED" then
                    -- Special case for spec names (Primary/Secondary)
                    local specName = (eventSubType == "1") and "Primary" or (eventSubType == "2" and "Secondary" or eventSubType)
                    if string.lower(ev.subType) == string.lower(specName or "") then
                        subMatch = true
                    end
                end
                
                if not subMatch then
                    match = false
                end
            end
            
            if match and ev.actions then
                local isPvP = UnitIsPVP("player")
                local isOutland = self:IsInOutland()
                for _, action in ipairs(ev.actions) do
                    local pvpMatch = true
                    if action.pvp == "ENABLED" and not isPvP then pvpMatch = false end
                    if action.pvp == "DISABLED" and isPvP then pvpMatch = false end
                    
                    local locMatch = true
                    if action.location == "OUTLAND" and not isOutland then locMatch = false end
                    if action.location == "NON_OUTLAND" and isOutland then locMatch = false end

                    local stanceMatch = true
                    if (eventType == "SHAPESHIFT" or eventType == "SHAPESHIFT_OUT") and action.stance and action.stance ~= "ANY" and action.stance ~= "" then
                        if string.lower(eventSubType or "") ~= string.lower(action.stance) then
                            stanceMatch = false
                        end
                    end

                    if pvpMatch and locMatch and stanceMatch then
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
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if arg1 == "player" then EqManager.Queue:SetCastingLockdown(true) end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or
           event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if arg1 == "player" then EqManager.Queue:SetCastingLockdown(false) end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "PLAYER_ENTERING_WORLD" then
        local zone = GetRealZoneText()
        local subZone = GetSubZoneText()
        local area = (subZone and subZone ~= "") and subZone or zone
        if area then
            self:EvaluateBindings("ZONE_ENTER", area)
        end
        -- Battleground detection
        local inBG = false
        if C_PvP and C_PvP.IsBattleground then
            inBG = C_PvP.IsBattleground()
        else
            local _, instanceType = IsInInstance()
            inBG = (instanceType == "pvp")
        end
        if inBG ~= self.lastBGState then
            self.lastBGState = inBG
            if inBG then
                self:EvaluateBindings("BG_ENTER")
            else
                self:EvaluateBindings("BG_LEAVE")
            end
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        self:CheckMountState() -- Catch dismounts during instant shifts
        local form = GetShapeshiftFormID()
        if form ~= self.lastFormID then
            if form then
                -- Entering a form
                self:EvaluateBindings("SHAPESHIFT", tostring(form))
            elseif self.lastFormID then
                -- Leaving a form to humanoid
                self:EvaluateBindings("SHAPESHIFT_OUT", tostring(self.lastFormID))
            else
                -- Fallback for first-time or unknown state
                self:EvaluateBindings("SHAPESHIFT_OUT")
            end
            self.lastFormID = form
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
        self:CheckMountState()
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then return end
        local currentSpec
        if event == "PLAYER_SPECIALIZATION_CHANGED" and GetSpecialization then
            currentSpec = GetSpecialization()
        elseif C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
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
    elseif event == "SPELL_UPDATE_USABLE" or event == "MIRROR_TIMER_START" or event == "MIRROR_TIMER_STOP" then
        local isSubmerged = IsSwimming()
        if isSubmerged ~= self.lastSubmergedState then
            self.lastSubmergedState = isSubmerged
            if isSubmerged then
                self:EvaluateBindings("SUBMERGE")
            else
                self:EvaluateBindings("EMERGE")
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        local isInParty = IsInGroup()
        if isInParty ~= self.lastPartyState then
            self.lastPartyState = isInParty
            if isInParty then
                self:EvaluateBindings("PARTY_JOIN")
            else
                self:EvaluateBindings("PARTY_LEAVE")
            end
        end

        local isInRaid = IsInRaid()
        if isInRaid ~= self.lastRaidState then
            self.lastRaidState = isInRaid
            if isInRaid then
                self:EvaluateBindings("RAID_JOIN")
            else
                self:EvaluateBindings("RAID_LEAVE")
            end
        end

    end
end

function EqManagerEvents:IsInOutland()
    local _, _, _, _, _, _, _, mapID = GetInstanceInfo()
    return mapID == 530
end
