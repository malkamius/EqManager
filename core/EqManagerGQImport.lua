--[[
    EqManagerGQImport.lua
    Handles detection, import of GearQuipper sets/events, and runtime disablement of GQ.
]]

EqManagerGQImport = {}
EqManager:RegisterModule("GQImport", EqManagerGQImport)

-- GQ event type -> EqManager event type mapping
local GQ_EVENT_MAP = {
    EVENT_MOUNT         = "MOUNT",
    EVENT_DISMOUNT      = "DISMOUNT",
    EVENT_STEALTH       = "STEALTH_ENTER",
    EVENT_UNSTEALTH     = "STEALTH_LEAVE",
    EVENT_COMBAT_ENTER  = "COMBAT_ENTER",
    EVENT_COMBAT_LEAVE  = "COMBAT_LEAVE",
    EVENT_ZONE_ENTER    = "ZONE_ENTER",
    EVENT_ZONE_LEAVE    = "ZONE_ENTER",  -- EqManager doesn't have ZONE_LEAVE; best-effort
    EVENT_PVP_ENABLE    = "PVP_ENTER",
    EVENT_PVP_DISABLE   = "PVP_LEAVE",
    EVENT_AFK_ENABLE    = "AFK_ENTER",
    EVENT_AFK_DISABLE   = "AFK_LEAVE",
    EVENT_SHAPESHIFT_IN = "SHAPESHIFT",
    EVENT_SHAPESHIFT_OUT = "SHAPESHIFT_OUT",
    EVENT_TALENTS_CHANGED = "SPEC_CHANGED",
    EVENT_SUBMERGE      = "SUBMERGE",
    EVENT_EMERGE        = "EMERGE",
    EVENT_PARTY_JOIN    = "PARTY_JOIN",
    EVENT_PARTY_LEAVE   = "PARTY_LEAVE",
    EVENT_RAID_JOIN     = "RAID_JOIN",
    EVENT_RAID_LEAVE    = "RAID_LEAVE",
    EVENT_BG_ENTER      = "BG_ENTER",
    EVENT_BG_LEAVE      = "BG_LEAVE",
    EVENT_STANCE_CHANGED = "SHAPESHIFT",
    EVENT_AURA_CHANGED  = "SHAPESHIFT",
    EVENT_PRESENCE_CHANGED = "SHAPESHIFT",
}

function EqManagerGQImport:Init()
    -- nothing to do here; import is user-triggered
end

-- Returns true if GearQuipper is loaded and has data for the current character
function EqManagerGQImport:IsGQAvailable()
    if not _G["gearquipper"] or not _G["GQ_DATA"] then return false end
    local realm = GetRealmName() or "Unknown"
    local char = UnitName("player") or "Unknown"
    if GQ_DATA[realm] and GQ_DATA[realm][char] then
        return true
    end
    return false
end

-- Main entry point: imports sets and events, then disables GQ
function EqManagerGQImport:Import()
    if not self:IsGQAvailable() then
        print("|cFF00FFFFEqManager|r: GearQuipper data not found for this character.")
        return
    end

    local setsImported = self:ImportSets()
    local eventsImported, eventsSkipped = self:ImportEvents()
    self:DisableGearQuipper()

    -- Rebuild set order to pick up new sets (append missing)
    EqManager.Data:GetSetNames()

    print("|cFF00FFFFEqManager|r: GearQuipper import complete!")
    print(string.format("|cFF00FFFFEqManager|r:   Sets imported: |cFFFFFF00%d|r", setsImported))
    print(string.format("|cFF00FFFFEqManager|r:   Events imported: |cFFFFFF00%d|r", eventsImported))
    if eventsSkipped > 0 then
        print(string.format("|cFF00FFFFEqManager|r:   Events skipped (unsupported): |cFFFF8800%d|r", eventsSkipped))
    end

    if EqManager.UI then
        if EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
            EqManager.UI:RefreshSetsList()
        end
    end

    if EqManager.Bags then
        EqManager.Bags:RefreshCache()
        if EqManager.Hooks then EqManager.Hooks:RefreshBags() end
    end
end

-----------------------------------------------------------------------
-- SET IMPORT
-----------------------------------------------------------------------
function EqManagerGQImport:ImportSets()
    local realm = GetRealmName()
    local char = UnitName("player")
    local gqCharData = GQ_DATA[realm][char]
    local gqSets = gqCharData["FIELD_SETS"]
    if not gqSets then return 0 end

    local count = 0
    for setName, setData in pairs(gqSets) do
        -- Skip GQ's internal previous-equipment pseudo-set
        if setName ~= "$PREVIOUSEQUIPMENT" and type(setData) == "table" then
            local isPartial = setData["FIELD_OPT_PARTIAL"] or false
            local slots = {}
            local gqSlots = setData["FIELD_SLOTS"] or {}
            local gqStates = setData["FIELD_SLOTSTATES"] or {}

            for slotId, itemString in pairs(gqSlots) do
                local numSlot = tonumber(slotId)
                if numSlot and numSlot >= 1 and numSlot <= 19 then
                    -- For partial sets, only import slots that are explicitly active
                    local isActive = gqStates[slotId] == true or gqStates[numSlot] == true or gqStates[tostring(numSlot)] == true
                    if not isPartial or isActive then
                        -- GQ uses "VALUE_NONE" for empty slots
                        if itemString ~= "VALUE_NONE" then
                            slots[numSlot] = itemString
                        end
                    end
                end
            end

            -- Determine helmet/cloak affects
            -- GQ defaults to true (affects) unless explicitly set to false
            local affectsHelmet = true
            if setData["FIELD_AFFECTS_HELMET"] == false then
                affectsHelmet = false
            end
            local affectsCloak = true
            if setData["FIELD_AFFECTS_CLOAK"] == false then
                affectsCloak = false
            end

            EqManager.Data:SaveSet(setName, slots, {
                isPartial = isPartial,
                affectsHelmet = affectsHelmet,
                affectsCloak = affectsCloak,
                keepOnBaseSwap = false,
                autoDetect = false,
            })
            count = count + 1
        end
    end

    return count
end

-----------------------------------------------------------------------
-- EVENT IMPORT
-----------------------------------------------------------------------
function EqManagerGQImport:ImportEvents()
    local realm = GetRealmName()
    local char = UnitName("player")
    local gqCharData = GQ_DATA[realm][char]
    local gqEvents = gqCharData["FIELD_EVENTS"]
    if not gqEvents then return 0, 0 end

    local imported = 0
    local skipped = 0

    for _, binding in ipairs(gqEvents) do
        if type(binding) == "table" then
            local gqType = binding["FIELD_TYPE"]
            local emType = GQ_EVENT_MAP[gqType]

            if emType then
                -- Resolve subType
                local subType = nil
                local gqSubType = binding["FIELD_SUBTYPE"]
                if gqSubType and type(gqSubType) == "table" then
                    if gqSubType["mapID"] then
                        -- Zone event: resolve mapID to zone name
                        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(gqSubType["mapID"])
                        if mapInfo and mapInfo.name then
                            subType = mapInfo.name
                        else
                            subType = tostring(gqSubType["mapID"])
                        end
                    elseif gqSubType["spellId"] then
                        -- Shapeshift/stance/aura: use the form name if available, else spell ID
                        if gqSubType["name"] then
                            subType = gqSubType["name"]
                        else
                            subType = tostring(gqSubType["spellId"])
                        end
                    elseif gqSubType["FIELD_NAME"] then
                        -- Script events
                        subType = gqSubType["FIELD_NAME"]
                    end
                elseif gqSubType and type(gqSubType) == "string" then
                    subType = gqSubType
                elseif gqSubType and type(gqSubType) == "number" then
                    subType = tostring(gqSubType)
                end

                -- Map PvP filter
                local pvpFilter = "ANY"
                local hasPVE = binding["FIELD_PVE"]
                local hasPVP = binding["FIELD_PVP"]
                if hasPVE and hasPVP then
                    pvpFilter = "ANY"
                elseif hasPVP and not hasPVE then
                    pvpFilter = "ENABLED"
                elseif hasPVE and not hasPVP then
                    pvpFilter = "DISABLED"
                end

                -- Get the target set name
                local targetSet = binding["FIELD_NAME"]
                if targetSet == "$PREVIOUS" or targetSet == "$PREVIOUSEQUIPMENT" then
                    -- Skip previous-set references (no equivalent in EM)
                    skipped = skipped + 1
                elseif targetSet then
                    -- Check if this event already exists (avoid exact duplicates)
                    local eventExists = false
                    local eventIndex = nil
                    local events = EqManager.Data:GetEvents()
                    for i, ev in ipairs(events) do
                        if ev.type == emType and (ev.subType or "") == (subType or "") then
                            eventExists = true
                            eventIndex = i
                            break
                        end
                    end

                    if not eventExists then
                        EqManager.Data:AddEvent(emType, subType)
                        eventIndex = #EqManager.Data.db.Events
                    end

                    -- Add the action to this event
                    if eventIndex then
                        local ev = EqManager.Data.db.Events[eventIndex]
                        if ev then
                            ev.actions = ev.actions or {}
                            -- Check for duplicate action
                            local actionExists = false
                            for _, act in ipairs(ev.actions) do
                                if type(act) == "table" and act.setName == targetSet then
                                    actionExists = true
                                    break
                                end
                            end
                            if not actionExists then
                                table.insert(ev.actions, { setName = targetSet, pvp = pvpFilter })
                            end
                        end
                    end

                    imported = imported + 1
                else
                    skipped = skipped + 1
                end
            else
                -- Unmappable event type
                if gqType then
                    print(string.format("|cFF00FFFFEqManager|r: Skipped unsupported GQ event type: |cFFFF8800%s|r", gqType))
                end
                skipped = skipped + 1
            end
        end
    end

    return imported, skipped
end

-----------------------------------------------------------------------
-- GQ DISABLEMENT
-----------------------------------------------------------------------
function EqManagerGQImport:DisableGearQuipper()
    if self.gqDisabled then return end
    self.gqDisabled = true

    -- Hide GQ's PaperDoll button
    local gqBtn = _G["GQ_PaperDollButton"]
    if gqBtn then
        gqBtn:Hide()
        gqBtn:SetScript("OnShow", function(self) self:Hide() end)
    end

    -- Hide GQ's PaperDoll label
    local gqLabel = _G["GQ_PaperDollLabel"]
    if gqLabel then
        gqLabel:Hide()
        gqLabel:SetScript("OnShow", function(self) self:Hide() end)
    end

    -- Hide GQ's main frame
    local gqFrame = _G["GqUiFrame"]
    if gqFrame then
        gqFrame:Hide()
        gqFrame:SetScript("OnShow", function(self) self:Hide() end)
    end

    -- Hide GQ's event frame (the options/events lower panel)
    local gqEventFrame = _G["GqUiEventFrame"]
    if gqEventFrame then
        gqEventFrame:Hide()
        gqEventFrame:SetScript("OnShow", function(self) self:Hide() end)
    end

    -- Hide watermark
    local gqWatermark = _G["GQ_Watermark"]
    if gqWatermark then
        gqWatermark:Hide()
        gqWatermark:SetScript("OnShow", function(self) self:Hide() end)
    end

    -- Disable GQ's event processing by unregistering all events from its event frame
    local gq = _G["gearquipper"]
    if gq and gq.eventFrame then
        gq.eventFrame:UnregisterAllEvents()
    end

    -- Prevent GQ from processing slash commands
    if gq then
        gq.initFinished = false
    end

    print("|cFF00FFFFEqManager|r: GearQuipper UI and events disabled.")
end

-----------------------------------------------------------------------
-- CONFIRMATION DIALOG
-----------------------------------------------------------------------
function EqManagerGQImport:ShowImportDialog()
    StaticPopupDialogs["EQMANAGER_GQ_IMPORT"] = StaticPopupDialogs["EQMANAGER_GQ_IMPORT"] or {
        text = "Import all GearQuipper sets and events into EqManager?\n\nSets with the same name will be overwritten.\nGearQuipper will be disabled while EqManager is active.",
        button1 = "Import",
        button2 = "Cancel",
        OnAccept = function()
            EqManagerGQImport:Import()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("EQMANAGER_GQ_IMPORT")
end
