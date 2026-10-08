-- Run from the repository root. No WoW client required.
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
SlashCmdList = {}
InCombatLockdown = function() return false end
dofile("eqmanager.lua")
local API = EqManager.API
local equipped
GetItemInfo = function(item) return "legacy", item end
GetContainerNumSlots = function() return 16 end
EquipItemByName = function(item, slot) equipped = {item, slot} end
assert(API.GetItemInfo(42) == "legacy")
assert(API.GetContainerNumSlots(0) == 16)
assert(API.EquipItemByName("item:42", 1))
assert(equipped[1] == "item:42")
C_Item = { GetItemInfo = function() return "modern" end,
    EquipItemByName = function() error("must not equip in combat") end }
assert(API.GetItemInfo(42) == "modern")
InCombatLockdown = function() return true end
assert(not API.EquipItemByName("item:42", 1))
API.ShowHelm(false)
API.ShowCloak(false)
GetShapeshiftFormInfo = function() return 123, "Cat", true, true, 768 end
local _, name, active, _, spellID = API.GetShapeshiftFormInfo(1)
assert(name == "Cat" and active and spellID == 768)
GetShapeshiftFormInfo = function() return 123, true, true, 768 end
C_Spell = { GetSpellInfo = function() return {name = "Cat"} end }
local _, name, active, _, spellID = API.GetShapeshiftFormInfo(1)
assert(name == "Cat" and active and spellID == 768)
local registrations = 0
local frame = {RegisterEvent = function() registrations = registrations + 1 end}
C_EventUtils = {IsEventValid = function(event) return event == "VALID" end}
API.RegisterEvent(frame, "REMOVED")
API.RegisterEvent(frame, "VALID")
assert(registrations == 1)
print("Compatibility checks passed")
