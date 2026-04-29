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

        -- Disable GearQuipper if it's loaded alongside us
        if EqManagerGQImport and EqManagerGQImport:IsGQAvailable() then
            EqManagerGQImport:DisableGearQuipper()
        end

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Fallback: disable GQ after both addons and saved variables are fully loaded
        if EqManagerGQImport and not EqManagerGQImport.gqDisabled and EqManagerGQImport:IsGQAvailable() then
            EqManagerGQImport:DisableGearQuipper()
        end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
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
        EqManager.Options.Debug = not EqManager.Options.Debug
        print("|cFF00FFFFEqManager|r: debug mode " .. (EqManager.Options.Debug and "enabled." or "disabled."))
    else
        print("|cFF00FFFFEqManager|r: /em debug")
    end
end
