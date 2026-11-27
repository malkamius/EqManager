--[[
    EqManagerData.lua
    Manages DB schema initialization and interactions with SavedVariables.
]]

EqManagerData = {}
EqManager:RegisterModule("Data", EqManagerData)

local function DeepCopy(val, seen)
    if type(val) ~= "table" then return val end
    seen = seen or {}
    if seen[val] then return seen[val] end
    local copy = {}
    seen[val] = copy
    for k, v in pairs(val) do
        copy[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return copy
end

local function ExtractItemId(link)
    if not link or link == "" or link == "EMPTY" or link == "VALUE_NONE" or link == "$NONE" then
        return nil
    end
    local id = tonumber(link)
    if id then return id end
    if type(link) == "string" then
        local itemId = link:match("item:(%d+)")
        if itemId then return tonumber(itemId) end
    end
    return nil
end

local function GetCurrentInventoryItemIds()
    local equippedIds = {}
    local ownedIds = {}
    for slotId = 1, 19 do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slotId)
        local id = ExtractItemId(link)
        if id then
            equippedIds[id] = true
            ownedIds[id] = true
        end
    end

    local getNumSlots = EqManager.API and EqManager.API.GetContainerNumSlots
    local getLink = EqManager.API and EqManager.API.GetContainerItemLink
    if getNumSlots and getLink then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local numSlots = getNumSlots(bag)
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local link = getLink(bag, slot)
                    local id = ExtractItemId(link)
                    if id then
                        ownedIds[id] = true
                    end
                end
            end
        end
    end
    return equippedIds, ownedIds
end

local function ScoreLegacyStoreMatch(legacyStore, equippedIds, ownedIds)
    if type(legacyStore) ~= "table" then return false, 0, 0 end
    local sets = legacyStore.Sets or legacyStore["FIELD_SETS"]
    if type(sets) ~= "table" or next(sets) == nil then
        return false, 0, 0
    end

    local uniqueItems = {}
    local totalUnique = 0
    local totalOwned = 0
    local totalEquipped = 0
    local bestSetRatio = 0

    for _, setData in pairs(sets) do
        if type(setData) == "table" then
            local slots = setData.slots or setData["FIELD_SLOTS"]
            if type(slots) == "table" then
                local setUnique = {}
                local setTotal = 0
                local setOwned = 0
                for _, itemString in pairs(slots) do
                    local id = ExtractItemId(itemString)
                    if id then
                        if not setUnique[id] then
                            setUnique[id] = true
                            setTotal = setTotal + 1
                            if ownedIds[id] then setOwned = setOwned + 1 end
                        end
                        if not uniqueItems[id] then
                            uniqueItems[id] = true
                            totalUnique = totalUnique + 1
                            if ownedIds[id] then totalOwned = totalOwned + 1 end
                            if equippedIds[id] then totalEquipped = totalEquipped + 1 end
                        end
                    end
                end
                if setTotal > 0 then
                    local ratio = setOwned / setTotal
                    if ratio > bestSetRatio then bestSetRatio = ratio end
                end
            end
        end
    end

    if totalUnique == 0 then
        return false, 0, 0
    end

    local isMatch = (totalEquipped >= 2)
        or (totalUnique == 1 and totalOwned == 1)
        or (totalOwned >= 3 and bestSetRatio >= 0.3)

    return isMatch, totalOwned, totalEquipped
end

function EqManagerData:Init()
    EM_CHAR_DATA = EM_CHAR_DATA or {}

    local charStore = EM_CHAR_DATA
    self.db = charStore

    charStore.Options = charStore.Options or {}
    self:MigrateOptions()

    self:PerformMigrations()

    charStore.Sets = charStore.Sets or {}
    charStore.Events = charStore.Events or {}
    charStore.InventoryCache = charStore.InventoryCache or {}

    charStore.CurrentSet = charStore.CurrentSet or nil
    charStore.BaseFullSet = charStore.BaseFullSet or nil
    charStore.ActivePartialSets = charStore.ActivePartialSets or {}
    charStore.SetOrder = charStore.SetOrder or nil
    charStore.PendingTasks = charStore.PendingTasks or {}
    charStore.LastAFKState = charStore.LastAFKState or false

    -- Expose character-specific options as EqManager.Options for easy access
    EqManager.Options = charStore.Options
end

function EqManagerData:TryMigrateFromGlobal()
    local charStore = self.db
    if not charStore or charStore.MigratedFromGlobal then return false end

    -- If this character already has per-character sets or events, do not overwrite them
    if (charStore.Sets and next(charStore.Sets) ~= nil) or (charStore.Events and next(charStore.Events) ~= nil) then
        charStore.MigratedFromGlobal = true
        return false
    end

    if type(EM_DATA) ~= "table" then
        charStore.MigratedFromGlobal = true
        return false
    end

    local realm = GetRealmName and GetRealmName() or ""
    local char = UnitName and UnitName("player") or ""
    if char == "" then return false end

    local playerGUID = UnitGUID and UnitGUID("player") or nil

    -- Collect candidate legacy buckets for this character name:
    -- exact realm, empty-string realm (from early ADDON_LOADED), and "Unknown" fallback.
    local candidates = {}
    local seenStores = {}
    local function addCandidate(realmKey, priority)
        if realmKey ~= nil and type(EM_DATA[realmKey]) == "table" and type(EM_DATA[realmKey][char]) == "table" then
            local store = EM_DATA[realmKey][char]
            if not seenStores[store] then
                seenStores[store] = true
                if not store._migratedToGUID or store._migratedToGUID == playerGUID then
                    table.insert(candidates, { store = store, priority = priority })
                end
            end
        end
    end

    if realm ~= "" then addCandidate(realm, 2) end
    addCandidate("", 1)
    addCandidate("Unknown", 0)

    if #candidates == 0 then
        charStore.MigratedFromGlobal = true
        return false
    end

    -- Verify ownership against currently equipped/bag items so characters that share
    -- a UnitName("player") never inherit another character's sets.
    local equippedIds, ownedIds = GetCurrentInventoryItemIds()
    if next(ownedIds) == nil then
        -- Inventory not yet populated; wait for a future login/reload rather than misclassifying
        return false
    end

    local bestCandidate = nil
    local bestScore = -1
    local bestPriority = -1

    for _, cand in ipairs(candidates) do
        local isMatch, totalOwned, totalEquipped = ScoreLegacyStoreMatch(cand.store, equippedIds, ownedIds)
        if isMatch then
            local score = totalOwned * 10 + totalEquipped
            if score > bestScore or (score == bestScore and cand.priority > bestPriority) then
                bestCandidate = cand.store
                bestScore = score
                bestPriority = cand.priority
            end
        end
    end

    if not bestCandidate then
        charStore.MigratedFromGlobal = true
        return false
    end

    -- Deep-copy legacy character data into per-character storage
    if type(bestCandidate.Sets) == "table" then
        charStore.Sets = DeepCopy(bestCandidate.Sets)
    end
    if type(bestCandidate["FIELD_SETS"]) == "table" then
        charStore["FIELD_SETS"] = DeepCopy(bestCandidate["FIELD_SETS"])
    end
    if type(bestCandidate.Events) == "table" then
        charStore.Events = DeepCopy(bestCandidate.Events)
    end
    if type(bestCandidate["FIELD_EVENTS"]) == "table" then
        charStore["FIELD_EVENTS"] = DeepCopy(bestCandidate["FIELD_EVENTS"])
    end
    if type(bestCandidate.SetOrder) == "table" then
        charStore.SetOrder = DeepCopy(bestCandidate.SetOrder)
    end
    if type(bestCandidate.ActivePartialSets) == "table" then
        charStore.ActivePartialSets = DeepCopy(bestCandidate.ActivePartialSets)
    end
    if bestCandidate.CurrentSet ~= nil then
        charStore.CurrentSet = bestCandidate.CurrentSet
    end
    if bestCandidate.BaseFullSet ~= nil then
        charStore.BaseFullSet = bestCandidate.BaseFullSet
    end
    if bestCandidate.LastAFKState ~= nil then
        charStore.LastAFKState = bestCandidate.LastAFKState
    end
    if type(bestCandidate.Options) == "table" then
        charStore.Options = charStore.Options or {}
        for k, v in pairs(bestCandidate.Options) do
            charStore.Options[k] = DeepCopy(v)
        end
        EqManager.Options = charStore.Options
    end

    self:MigrateOptions()
    self:PerformMigrations()

    if playerGUID then
        bestCandidate._migratedToGUID = playerGUID
    end
    charStore.MigratedFromGlobal = true

    print("|cFF00FFFFEqManager|r: Migrated character sets to per-character storage.")

    if EqManager.Bags then
        EqManager.Bags:RefreshCache()
        if EqManager.Hooks then EqManager.Hooks:RefreshBags() end
    end
    if EqManager.UI and EqManager.UI.frame and EqManager.UI.frame:IsVisible() then
        EqManager.UI:RefreshSetsList()
    end
    if EqManager.PaperDoll then
        EqManager.PaperDoll:UpdateHighlights()
    end

    return true
end

function EqManagerData:MigrateOptions()
    local options = self.db.Options

    -- If local options are empty but global EM_OPTIONS has data, migrate it
    -- Note: EM_OPTIONS will eventually be removed from .toc, but this handles the transition.
    if EM_OPTIONS and type(EM_OPTIONS) == "table" and not EM_OPTIONS[GetRealmName()] then
        -- This is the legacy flat EM_OPTIONS
        for k, v in pairs(EM_OPTIONS) do
            if options[k] == nil then
                options[k] = v
            end
        end
    end

    if options.ShowTooltips == nil then options.ShowTooltips = true end
    if options.ShowUI == nil then options.ShowUI = false end
    if options.AutoUpdateCondition == nil then
        if options.AutoUpdateBaseSet == false then
            options.AutoUpdateCondition = "DISABLED"
        else
            options.AutoUpdateCondition = "CHARACTER"
        end
    end
    if options.SwapDelay == nil then options.SwapDelay = 0.25 end
    if options.BagDimmingMode == nil then
        if options.EnableBagDimming == true then
            options.BagDimmingMode = "NON_SET"
        else
            options.BagDimmingMode = "DISABLED"
        end
    end
    options.EnableBagDimming = nil -- Cleanup legacy flag
end

function EqManagerData:PerformMigrations(realm, char)
    local charStore = self.db
    if not charStore then return end

    realm = realm or (GetRealmName and GetRealmName()) or ""
    char = char or (UnitName and UnitName("player")) or ""

    -- 1. Import Legacy EqManager / GearEquipper EqManager sets (FIELD_SETS)
    if charStore["FIELD_SETS"] then
        print("|cFF00FFFFEqManager|r: Migrating legacy datasets to clean-room schema...")
        charStore.Sets = charStore.Sets or {}
        for setName, setData in pairs(charStore["FIELD_SETS"]) do
            if setName and setData then
                local newSlots = {}
                local oldSlots = setData["FIELD_SLOTS"] or {}
                local oldStates = setData["FIELD_SLOTSTATES"] or {}
                local isPartial = setData["FIELD_OPT_PARTIAL"] or false

                for slotId, itemString in pairs(oldSlots) do
                    -- For partials, only preserve slots that were explicitly active
                    if not isPartial or oldStates[slotId] == nil or oldStates[slotId] == true then
                        newSlots[slotId] = itemString
                    end
                end

                charStore.Sets[setName] = {
                    slots = newSlots,
                    isPartial = isPartial,
                    affectsHelmet = setData["FIELD_AFFECTS_HELMET"] or false,
                    affectsCloak = setData["FIELD_AFFECTS_CLOAK"] or false,
                }
            end
        end
        charStore["FIELD_SETS"] = nil
    end

    -- Cleanup other legacy EM fields to prevent DB bloat
    if charStore["FIELD_EVENTS"] then
        charStore.Events = charStore["FIELD_EVENTS"]
        charStore["FIELD_EVENTS"] = nil
    end
    charStore["FIELD_INVENTORY"] = nil
    charStore["FIELD_BANK"] = nil
    charStore["FIELD_IGNOREDSLOTS"] = nil
    charStore["FIELD_CURRENTSET"] = nil
    charStore["FIELD_LASTSET"] = nil
    charStore["FIELD_BASEFULLSET"] = nil
    charStore["FIELD_ACTIVEPARTIALSETS"] = nil

    -- 2. Import external GearQuipper sets
    -- Often GearQuipper stores per character directly in gearquipper_sets or GearquipperDB
    if realm ~= "" and char ~= "" and _G["gearquipper_sets"] then
        print("|cFF00FFFFEqManager|r: Importing GearQuipper generic sets...")
        charStore.Sets = charStore.Sets or {}
        -- Detect structure: [realm][char] or flat [setName]
        local gqSets = _G["gearquipper_sets"]
        if _G["gearquipper_sets"][realm] and _G["gearquipper_sets"][realm][char] then
            gqSets = _G["gearquipper_sets"][realm][char]
        end

        for setName, setData in pairs(gqSets) do
            if type(setData) == "table" and not charStore.Sets[setName] then
                charStore.Sets[setName] = {
                    slots = setData or {},
                    isPartial = false,
                    affectsHelmet = false,
                    affectsCloak = false,
                }
            end
        end
        -- We won't nil gearquipper_sets in case the user still tests both mods
    end
    if realm ~= "" and char ~= "" and _G["GQ_DATA"] and _G["GQ_DATA"][realm] and _G["GQ_DATA"][realm][char] then
        print("|cFF00FFFFEqManager|r: Importing GQ_DATA generic sets...")
        charStore.Sets = charStore.Sets or {}
        local gqSets = _G["GQ_DATA"][realm][char]
        for setName, setData in pairs(gqSets) do
            if type(setData) == "table" and not charStore.Sets[setName] then
                charStore.Sets[setName] = {
                    slots = setData or {},
                    isPartial = false,
                    affectsHelmet = false,
                    affectsCloak = false,
                }
            end
        end
    end

    -- 3. Normalize all existing sets to use strictly integer keys for slots
    --    Also strip invalid slot 0 (WoW serializer artifact for sparse tables)
    if charStore.Sets then
        for _, setData in pairs(charStore.Sets) do
            if setData.slots then
                local norm = {}
                for k, v in pairs(setData.slots) do
                    local numKey = tonumber(k)
                    if numKey and numKey >= 1 and numKey <= 19 then
                        norm[numKey] = v
                    end
                end
                setData.slots = norm
            end
        end
    end

    -- 4. Migrate Event-level SHAPESHIFT/SHAPESHIFT_OUT conditions to Action-level conditions,
    --    and merge duplicate SHAPESHIFT/SHAPESHIFT_OUT events.
    if charStore.Events then
        local mergedShapeshift = nil
        local mergedShapeshiftOut = nil
        local newEvents = {}

        for _, ev in ipairs(charStore.Events) do
            if ev.type == "SHAPESHIFT" then
                if not mergedShapeshift then
                    mergedShapeshift = { type = "SHAPESHIFT", actions = {} }
                    table.insert(newEvents, mergedShapeshift)
                end
                local cond = ev.subType or "ANY"
                if ev.actions then
                    for _, act in ipairs(ev.actions) do
                        if type(act) == "table" then
                            act.stance = act.stance or cond
                        elseif type(act) == "string" then
                            act = { setName = act, pvp = "ANY", location = "ANY", stance = cond }
                        end
                        table.insert(mergedShapeshift.actions, act)
                    end
                end
            elseif ev.type == "SHAPESHIFT_OUT" then
                if not mergedShapeshiftOut then
                    mergedShapeshiftOut = { type = "SHAPESHIFT_OUT", actions = {} }
                    table.insert(newEvents, mergedShapeshiftOut)
                end
                local cond = ev.subType or "ANY"
                if ev.actions then
                    for _, act in ipairs(ev.actions) do
                        if type(act) == "table" then
                            act.stance = act.stance or cond
                        elseif type(act) == "string" then
                            act = { setName = act, pvp = "ANY", location = "ANY", stance = cond }
                        end
                        table.insert(mergedShapeshiftOut.actions, act)
                    end
                end
            else
                table.insert(newEvents, ev)
            end
        end
        charStore.Events = newEvents
    end
end

-- Sets Data API
function EqManagerData:GetSetNames()
    if not self.db.SetOrder then
        -- Initial population: Full sets first (alphabetical), then Partial sets (alphabetical)
        local full = {}
        local partial = {}
        for name, data in pairs(self.db.Sets) do
            if data.isPartial then
                table.insert(partial, name)
            else
                table.insert(full, name)
            end
        end
        table.sort(full)
        table.sort(partial)

        self.db.SetOrder = {}
        for _, name in ipairs(full) do table.insert(self.db.SetOrder, name) end
        for _, name in ipairs(partial) do table.insert(self.db.SetOrder, name) end
    end

    -- Sync check
    local order = self.db.SetOrder
    local exists = {}
    local synced = {}
    for _, name in ipairs(order) do
        if self.db.Sets[name] then
            table.insert(synced, name)
            exists[name] = true
        end
    end

    local missing = {}
    for name, _ in pairs(self.db.Sets) do
        if not exists[name] then
            table.insert(missing, name)
        end
    end
    if #missing > 0 then
        table.sort(missing)
        for _, name in ipairs(missing) do
            table.insert(synced, name)
        end
    end
    self.db.SetOrder = synced
    return self.db.SetOrder
end

function EqManagerData:MoveSet(setName, direction)
    local order = self:GetSetNames() -- ensures synced
    if not order then return end

    local idx
    for i, name in ipairs(order) do
        if name == setName then
            idx = i
            break
        end
    end
    if not idx then return end

    local targetIdx = idx + direction
    if targetIdx < 1 or targetIdx > #order then return end

    order[idx], order[targetIdx] = order[targetIdx], order[idx]
end

function EqManagerData:GetSet(setName)
    return self.db.Sets[setName]
end

function EqManagerData:SaveSet(setName, itemStrings, opts)
    self.db.Sets[setName] = {
        slots = itemStrings,
        isPartial = opts and opts.isPartial or false,
        affectsHelmet = opts and opts.affectsHelmet or false,
        affectsCloak = opts and opts.affectsCloak or false,
        keepOnBaseSwap = opts and opts.keepOnBaseSwap or false,
        autoDetect = opts and opts.autoDetect or false
    }
    if EqManager.Bags then
        EqManager.Bags:RefreshCache()
        if EqManager.Hooks then EqManager.Hooks:RefreshBags() end
    end
end

function EqManagerData:RemoveSet(setName)
    self.db.Sets[setName] = nil
    if EqManager.Bags then
        EqManager.Bags:RefreshCache()
        if EqManager.Hooks then EqManager.Hooks:RefreshBags() end
    end
end

-- Active Partial Management
function EqManagerData:GetActivePartialSets()
    return self.db.ActivePartialSets
end

function EqManagerData:ClearActivePartialSets()
    self.db.ActivePartialSets = {}
end

function EqManagerData:AddActivePartialSet(setName)
    for _, name in ipairs(self.db.ActivePartialSets) do
        if name == setName then return end
    end
    table.insert(self.db.ActivePartialSets, setName)
end

function EqManagerData:RemoveActivePartialSet(setName)
    for i, name in ipairs(self.db.ActivePartialSets) do
        if name == setName then
            table.remove(self.db.ActivePartialSets, i)
            break
        end
    end
end

-- Event Bindings Management
function EqManagerData:GetEvents()
    for _, ev in ipairs(self.db.Events) do
        if not ev.actions then
            ev.actions = {}
            if ev.setName then
                table.insert(ev.actions, { setName = ev.setName, pvp = "ANY", location = "ANY", stance = "ANY" })
                ev.setName = nil
            end
        else
            for i, action in ipairs(ev.actions) do
                if type(action) == "string" then
                    ev.actions[i] = { setName = action, pvp = "ANY", location = "ANY", stance = "ANY" }
                else
                    action.location = action.location or "ANY"
                    action.stance = action.stance or "ANY"
                end
            end
        end
    end
    return self.db.Events
end

function EqManagerData:AddEvent(type, subType)
    -- Check for exact duplicate event trigger
    for _, ev in ipairs(self.db.Events) do
        if ev.type == type and ev.subType == subType then return false end
    end
    table.insert(self.db.Events, {
        type = type,
        subType = subType,
        actions = {}
    })
    return true
end

function EqManagerData:RemoveEvent(index)
    if self.db.Events[index] then
        table.remove(self.db.Events, index)
    end
end

function EqManagerData:AddEventAction(eventIndex, targetSet, pvp, location, stance)
    local ev = self.db.Events[eventIndex]
    if ev then
        ev.actions = ev.actions or {}
        for _, act in ipairs(ev.actions) do
            if type(act) == "table" and act.setName == targetSet and act.pvp == (pvp or "ANY") and act.location == (location or "ANY") and act.stance == (stance or "ANY") then
                return false
            end
        end
        table.insert(ev.actions, { 
            setName = targetSet, 
            pvp = pvp or "ANY", 
            location = location or "ANY",
            stance = stance or "ANY"
        })
        return true
    end
    return false
end

function EqManagerData:UpdateEventAction(eventIndex, actionIndex, actionData)
    local ev = self.db.Events[eventIndex]
    if ev and ev.actions and ev.actions[actionIndex] then
        ev.actions[actionIndex].setName = actionData.setName or ev.actions[actionIndex].setName
        ev.actions[actionIndex].pvp = actionData.pvp or ev.actions[actionIndex].pvp
        ev.actions[actionIndex].location = actionData.location or ev.actions[actionIndex].location
        ev.actions[actionIndex].stance = actionData.stance or ev.actions[actionIndex].stance
        return true
    end
    return false
end

function EqManagerData:RemoveEventAction(eventIndex, actionIndex)
    local ev = self.db.Events[eventIndex]
    if ev and ev.actions and ev.actions[actionIndex] then
        table.remove(ev.actions, actionIndex)
    end
end
