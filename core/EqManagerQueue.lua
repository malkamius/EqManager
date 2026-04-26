--[[
    EqManagerQueue.lua
    Manages the queuing of equipment sets when switching is locked.
]]

EqManagerQueue = {}
EqManager:RegisterModule("Queue", EqManagerQueue)

function EqManagerQueue:Init()
    self.pendingQueue = {}
    self.inCombat = InCombatLockdown()
    self.isCasting = false
    self.isBusy = false
end

function EqManagerQueue:SetCombatLockdown(state)
    self.inCombat = state
    if not state then 
        EqManager.Engine:ResumeSwapping()
        self:ProcessQueue() 
    end
end

function EqManagerQueue:SetCastingLockdown(state)
    self.isCasting = state
    if not state then 
        EqManager.Engine:ResumeSwapping()
        self:ProcessQueue() 
    end
end

function EqManagerQueue:CanSwitch()
    return not self.inCombat and not self.isCasting
end

function EqManagerQueue:QueueSet(action, source)
    local isUnequip = string.sub(action, 1, 4) == "[-] "
    local targetSetName = isUnequip and string.sub(action, 5) or action
    local set = EqManager.Data:GetSet(targetSetName)
    local cancelled = false

    if not set then
        -- Fallback for unknown sets or raw commands
        table.insert(self.pendingQueue, { action = action, source = source })
    elseif isUnequip and not set.isPartial then
        -- Base Set Unequip: Prohibited
        if EqManager.Options.Debug then
            print("|cFF00FFFFEqManager DEBUG|r: Ignoring un-equip action for base set: " .. targetSetName)
        end
        return
    elseif not set.isPartial and not isUnequip then
        -- Full Set Equip: Supersedes all previous actions in the queue
        self.pendingQueue = { { action = action, source = source } }
    else
        -- Partial Set (Equip or Unequip): Check for conflicts
        local inverse = isUnequip and targetSetName or ("[-] " .. targetSetName)
        
        for i, entry in ipairs(self.pendingQueue) do
            if entry.action == inverse then
                -- Cancellation: Equip and Unequip nullify each other
                table.remove(self.pendingQueue, i)
                cancelled = true
                break
            elseif entry.action == action then
                -- Redundancy: Duplicate action already in queue
                cancelled = true
                break
            end
        end
        
        if not cancelled then
            table.insert(self.pendingQueue, { action = action, source = source })
        end
    end

    if self:CanSwitch() then
        self:ProcessQueue()
    elseif not cancelled then
        local msg = "|cFF00FFFFEqManager|r: Queued action |cFFFFFF00" .. action .. "|r"
        if source then
            msg = msg .. " (caused by: |cFF00FF00" .. source .. "|r)"
        end
        print(msg .. " |cFFFF0000(locked)|r")
    end
end

function EqManagerQueue:ProcessQueue()
    if self.isBusy then return end
    if #self.pendingQueue == 0 then return end
    if not self:CanSwitch() then return end

    self.isBusy = true
    local entry = table.remove(self.pendingQueue, 1)
    local action = entry.action
    local source = entry.source

    local onDone = function()
        self.isBusy = false
        self:ProcessQueue()
    end

    if string.sub(action, 1, 4) == "[-] " then
        local actualSet = string.sub(action, 5)
        EqManager.Engine:UnequipPartialSet(actualSet, onDone, source)
    else
        EqManager.Engine:EquipSet(action, onDone, source)
    end
end
