--[[
    EqManagerData.lua
    Manages DB schema initialization and interactions with SavedVariables.
]]

EqManagerData = {}
EqManager:RegisterModule("Data", EqManagerData)

function EqManagerData:Init()
    local realm = GetRealmName() or "Unknown"
    local char = UnitName("player") or "Unknown"

    EM_DATA = EM_DATA or {}
    EM_DATA[realm] = EM_DATA[realm] or {}
    EM_DATA[realm][char] = EM_DATA[realm][char] or {}
    
    local charStore = EM_DATA[realm][char]

    self.db = charStore
    
    self:PerformMigrations(realm, char)

    charStore.Sets = charStore.Sets or {}
    charStore.Events = charStore.Events or {}
    charStore.InventoryCache = charStore.InventoryCache or {}
    
    charStore.CurrentSet = charStore.CurrentSet or nil
    charStore.BaseFullSet = charStore.BaseFullSet or nil
    charStore.ActivePartialSets = charStore.ActivePartialSets or {}
    charStore.SetOrder = charStore.SetOrder or nil
    charStore.PendingTasks = charStore.PendingTasks or {}
    charStore.LastAFKState = charStore.LastAFKState or false
end

function EqManagerData:PerformMigrations(realm, char)
    local charStore = EM_DATA[realm][char]

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
    if _G["gearquipper_sets"] then
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
    if _G["GQ_DATA"] and _G["GQ_DATA"][realm] and _G["GQ_DATA"][realm][char] then
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
    if charStore.Sets then
        for _, setData in pairs(charStore.Sets) do
            if setData.slots then
                local norm = {}
                for k, v in pairs(setData.slots) do
                    local numKey = tonumber(k)
                    if numKey then
                        norm[numKey] = v
                    end
                end
                setData.slots = norm
            end
        end
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
                table.insert(ev.actions, { setName = ev.setName, pvp = "ANY" })
                ev.setName = nil
            end
        else
            for i, action in ipairs(ev.actions) do
                if type(action) == "string" then
                    ev.actions[i] = { setName = action, pvp = "ANY" }
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

function EqManagerData:AddEventAction(eventIndex, targetSet)
    local ev = self.db.Events[eventIndex]
    if ev then
        ev.actions = ev.actions or {}
        for _, act in ipairs(ev.actions) do
            if (type(act) == "table" and act.setName == targetSet) or (act == targetSet) then 
                return false 
            end
        end
        table.insert(ev.actions, { setName = targetSet, pvp = "ANY" })
        return true
    end
    return false
end

function EqManagerData:UpdateEventAction(eventIndex, actionIndex, actionData)
    local ev = self.db.Events[eventIndex]
    if ev and ev.actions and ev.actions[actionIndex] then
        ev.actions[actionIndex].setName = actionData.setName or ev.actions[actionIndex].setName
        ev.actions[actionIndex].pvp = actionData.pvp or ev.actions[actionIndex].pvp
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
