--[[
    EqManager: Main Entrypoint
    Provides the global AddOn object and initializes modules.
]]

EqManager = CreateFrame("Frame", "EqManagerFrame", UIParent)
EqManager.modules = {}

EqManager.INVSLOTS = {
    { "CharacterHeadSlot",  1 }, { "CharacterNeckSlot", 2 }, { "CharacterShoulderSlot", 3 }, { "CharacterShirtSlot", 4 },
    { "CharacterChestSlot", 5 }, { "CharacterWaistSlot", 6 }, { "CharacterLegsSlot", 7 }, { "CharacterFeetSlot", 8 },
    { "CharacterWristSlot",    9 }, { "CharacterHandsSlot", 10 }, { "CharacterFinger0Slot", 11 }, { "CharacterFinger1Slot", 12 },
    { "CharacterTrinket0Slot", 13 }, { "CharacterTrinket1Slot", 14 }, { "CharacterBackSlot", 15 }, { "CharacterMainHandSlot", 16 },
    { "CharacterSecondaryHandSlot", 17 }, { "CharacterRangedSlot", 18 }, { "CharacterTabardSlot", 19 }
}

-- Module registration helper
function EqManager:RegisterModule(name, module)
    self.modules[name] = module
    -- Copy simple reference to EqManager definition frame
    self[name] = module
end

-- Initialize DB and modules
local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "EqManager" then
        -- Initialize SavedVariables schema
        EM_DATA = EM_DATA or {}
        EM_OPTIONS = EM_OPTIONS or {}
        EM_OPTIONS.AutoUpdateBaseSet = (EM_OPTIONS.AutoUpdateBaseSet == nil) and true or EM_OPTIONS.AutoUpdateBaseSet
        if EM_OPTIONS.AutoUpdateCondition == nil then
            if EM_OPTIONS.AutoUpdateBaseSet == false then
                EM_OPTIONS.AutoUpdateCondition = "DISABLED"
            else
                EM_OPTIONS.AutoUpdateCondition = "CHARACTER"
            end
        end
        EM_OPTIONS.ShowUI = (EM_OPTIONS.ShowUI == nil) and false or EM_OPTIONS.ShowUI
        EM_OPTIONS.SwapDelay = (EM_OPTIONS.SwapDelay == nil) and 0.1 or EM_OPTIONS.SwapDelay
        EM_OPTIONS.EnableBagDimming = (EM_OPTIONS.EnableBagDimming == nil) and false or EM_OPTIONS.EnableBagDimming
        EM_OPTIONS.ShowTooltips = (EM_OPTIONS.ShowTooltips == nil) and true or EM_OPTIONS.ShowTooltips
        EM_AUX = EM_AUX or {}

        -- Call internal Init on Data first
        if self.modules["Data"] and type(self.modules["Data"].Init) == "function" then
            self.modules["Data"]:Init()
        end

        -- Initialize remaining modules
        for name, module in pairs(self.modules) do
            if name ~= "Data" and type(module.Init) == "function" then
                module:Init()
            end
        end

        print("|cFF00FFFFEqManager|r loaded.")
        self:UnregisterEvent("ADDON_LOADED")
    end
end

EqManager:RegisterEvent("ADDON_LOADED")
EqManager:SetScript("OnEvent", OnEvent)

-- Slash Commands
SLASH_EQMANAGER1 = "/em"
SlashCmdList["EQMANAGER"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do table.insert(args, word) end

    if args[1] == "debug" then
        EM_OPTIONS.Debug = not EM_OPTIONS.Debug
        print("|cFF00FFFFEqManager|r: debug mode " .. (EM_OPTIONS.Debug and "enabled." or "disabled."))
    else
        print("|cFF00FFFFEqManager|r: /em debug")
    end
end
