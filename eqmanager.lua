--[[
    EqManager: Main Entrypoint
    Provides the global AddOn object and initializes modules.
]]

EqManager = CreateFrame("Frame", "EqManagerFrame", UIParent)
EqManager.modules = {}

EqManager.SPELL_TO_FORM_ID = {
    [768]   = 1,   -- Cat Form
    [33891] = 2,   -- Tree of Life
    [783]   = 3,   -- Travel Form
    [1066]  = 4,   -- Aquatic Form
    [5487]  = 5,   -- Bear Form
    [9634]  = 5,   -- Dire Bear Form
    [40120] = 27,  -- Swift Flight Form
    [33943] = 29,  -- Flight Form
    [24858] = 31,  -- Moonkin Form
    [15473] = 28,  -- Shadowform
    [2457]  = 17,  -- Battle Stance
    [71]    = 18,  -- Defensive Stance
    [2458]  = 19,  -- Berserker Stance
    [2645]  = 16,  -- Ghost Wolf
    [1784]  = 30,  -- Stealth
}

EqManager.FORM_ID_NAMES = {
    ["1"]  = "Cat Form",
    ["2"]  = "Tree of Life",
    ["3"]  = "Travel Form",
    ["4"]  = "Aquatic Form",
    ["5"]  = "Bear Form",
    ["16"] = "Ghost Wolf",
    ["17"] = "Battle Stance",
    ["18"] = "Defensive Stance",
    ["19"] = "Berserker Stance",
    ["22"] = "Metamorphosis",
    ["27"] = "Swift Flight Form",
    ["28"] = "Shadowform",
    ["29"] = "Flight Form",
    ["30"] = "Stealth",
    ["31"] = "Moonkin Form",
    ["32"] = "Moonkin Form",
    ["33"] = "Moonkin Form",
    ["34"] = "Moonkin Form",
    ["35"] = "Moonkin Form",
    ["36"] = "Treant Form",
}

EqManager.CLASS_STANCES = {
    WARRIOR = {
        { id = 17, name = "Battle Stance" },
        { id = 18, name = "Defensive Stance" },
        { id = 19, name = "Berserker Stance" },
    },
    DRUID = {
        { id = 5,  name = "Bear Form" },
        { id = 1,  name = "Cat Form" },
        { id = 3,  name = "Travel Form" },
        { id = 4,  name = "Aquatic Form" },
        { id = 29, name = "Flight Form" },
        { id = 27, name = "Swift Flight Form" },
        { id = 31, name = "Moonkin Form" },
        { id = 2,  name = "Tree of Life" },
    },
    PRIEST = {
        { id = 28, name = "Shadowform" },
    },
    ROGUE = {
        { id = 30, name = "Stealth" },
    },
    SHAMAN = {
        { id = 16, name = "Ghost Wolf" },
    },
    WARLOCK = {
        { id = 22, name = "Metamorphosis" },
    }
}

function EqManager:GetFormIDFromStanceInfo(name, texture, spellID)
    -- 1. Try by corrected spellID
    if spellID and self.SPELL_TO_FORM_ID[spellID] then
        return self.SPELL_TO_FORM_ID[spellID]
    end

    -- 2. Try by texture (case-insensitive substring match)
    if texture and type(texture) == "string" then
        local texLower = string.lower(texture)
        if string.find(texLower, "bearform") then return 5
        elseif string.find(texLower, "catform") then return 1
        elseif string.find(texLower, "travelform") then return 3
        elseif string.find(texLower, "aquaticform") then return 4
        elseif string.find(texLower, "flightformstormobsidian") or string.find(texLower, "swiftflightform") then return 27
        elseif string.find(texLower, "flightform") then return 29
        elseif string.find(texLower, "treeoflife") then return 2
        elseif string.find(texLower, "forceofnature") then return 31
        elseif string.find(texLower, "shadowform") then return 28
        elseif string.find(texLower, "stealth") then return 30
        elseif string.find(texLower, "spiritwolf") or string.find(texLower, "ghostwolf") then return 16
        elseif string.find(texLower, "offensivestance") then return 17
        elseif string.find(texLower, "defensivestance") then return 18
        elseif string.find(texLower, "innerrage") or string.find(texLower, "berserkerstance") then return 19
        end
    end

    -- 3. Try by name (case-insensitive substring match)
    if name and type(name) == "string" then
        local nameLower = string.lower(name)
        if string.find(nameLower, "bear") then return 5
        elseif string.find(nameLower, "cat") then return 1
        elseif string.find(nameLower, "swift flight") then return 27
        elseif string.find(nameLower, "flight") then return 29
        elseif string.find(nameLower, "travel") then return 3
        elseif string.find(nameLower, "aquatic") then return 4
        elseif string.find(nameLower, "tree of life") then return 2
        elseif string.find(nameLower, "moonkin") then return 31
        elseif string.find(nameLower, "shadowform") then return 28
        elseif string.find(nameLower, "stealth") then return 30
        elseif string.find(nameLower, "ghost wolf") then return 16
        elseif string.find(nameLower, "battle stance") then return 17
        elseif string.find(nameLower, "defensive stance") then return 18
        elseif string.find(nameLower, "berserker stance") then return 19
        end
    end

    return nil
end

function EqManager:GetFormNameByID(formID)
    if not formID then return nil end
    local idStr = tostring(formID)
    -- 1. Try static list
    if self.FORM_ID_NAMES[idStr] then
        return self.FORM_ID_NAMES[idStr]
    end
    -- 2. Try dynamic search on player's learned stances
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        local numStances = GetNumShapeshiftForms()
        for i = 1, numStances do
            local texture, name, _, _, spellID = GetShapeshiftFormInfo(i)
            if name then
                local mappedID = self:GetFormIDFromStanceInfo(name, texture, spellID)
                if mappedID and tostring(mappedID) == idStr then
                    return name
                end
            end
        end
    end
    return "Form " .. idStr
end

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
