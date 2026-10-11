--[[--------------------------------------------------------------------
    NaowhUI 3.3.5 compatibility layer (personal-use port).

    Retail NaowhUI embeds Ace3 r13xx. Its AceDB (minor 39) calls
    UnitNameUnmodified/GetCurrentRegion*, which 3.3.5 lacks, and LibStub would
    upgrade every other addon's AceDB to it. NaowhUI only needs a few AceAddon,
    AceConsole and AceDB calls, so they live here, private to this addon:
    nothing is registered with LibStub.
--------------------------------------------------------------------]]--

local _, ns = ...

local W = {}
ns.Wrath = W

local pairs, type, tostring, select = pairs, type, tostring, select
local tconcat = table.concat

-- One-shot timers (C_Timer.After)
local timerFrame
local timers = {}

function W.After(delay, func)
    timers[#timers + 1] = { at = GetTime() + (delay or 0), func = func }

    if not timerFrame then
        timerFrame = CreateFrame("Frame")
        timerFrame:SetScript("OnUpdate", function(frame)
            local now = GetTime()
            local i = 1

            while i <= #timers do
                local t = timers[i]

                if now >= t.at then
                    table.remove(timers, i)
                    t.func()
                else
                    i = i + 1
                end
            end

            if #timers == 0 then
                frame:Hide()
            end
        end)
    end

    timerFrame:Show()
end

-- Widget helpers for methods 3.3.5 lacks
function W.SetEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

function W.ColorTexture(texture, r, g, b, a)
    texture:SetTexture(r, g, b, a or 1)
end

function W.ClassHex(class)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]

    if not color then
        return "|cffffffff"
    end

    return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
end

function W.IsAddOnEnabled(addon)
    local name, _, _, enabled = GetAddOnInfo(addon)

    return name ~= nil and enabled ~= nil and enabled ~= 0
end

function W.CanLoadAddOn(addon)
    if IsAddOnLoaded(addon) then
        return true
    end

    local name, _, _, enabled, loadable = GetAddOnInfo(addon)

    return name ~= nil and enabled and loadable and true or false
end

-- AceDB subset: profile/global/char sections in the AceDB SavedVariables layout.
-- Sections are looked up on every access, so code that replaces a section of
-- the SavedVariables table (NaowhUIDB.char = {}) keeps writing to the live one.
local function Section(svName, key, sub, defaults)
    local sv = _G[svName]

    if type(sv) ~= "table" then
        sv = {}
        _G[svName] = sv
    end

    if type(sv[key]) ~= "table" then
        sv[key] = {}
    end

    if not sub then
        return sv[key]
    end

    local t = sv[key][sub]

    if type(t) ~= "table" then
        t = {}
        sv[key][sub] = t
    end

    if defaults then
        for k, v in pairs(defaults) do
            if t[k] == nil then
                if type(v) == "table" then
                    local copy = {}

                    for ck, cv in pairs(v) do
                        copy[ck] = cv
                    end

                    t[k] = copy
                else
                    t[k] = v
                end
            end
        end
    end

    return t
end

function W.NewDB(svName, defaults, defaultProfile)
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    local profileDefaults = defaults and defaults.profile
    local db = {}

    if defaultProfile == true or not defaultProfile then
        defaultProfile = "Default"
    end

    local function ProfileName()
        local keys = Section(svName, "profileKeys")

        if not keys[charKey] then
            keys[charKey] = defaultProfile
        end

        return keys[charKey]
    end

    function db:ResetDB()
        local sv = _G[svName]

        if type(sv) == "table" then
            for k in pairs(sv) do
                sv[k] = nil
            end
        end

        return self.profile
    end

    setmetatable(db, {
        __index = function(_, key)
            if key == "profile" then
                return Section(svName, "profiles", ProfileName(), profileDefaults)
            elseif key == "profiles" then
                Section(svName, "profiles", ProfileName(), profileDefaults)

                return _G[svName].profiles
            elseif key == "global" then
                return Section(svName, "global")
            elseif key == "char" then
                return Section(svName, "char", charKey)
            end
        end
    })

    local _ = db.profile

    return db
end

-- AceAddon + AceConsole subset
local Addon = {}
Addon.__index = Addon

function Addon:NewModule(name)
    local module = { moduleName = name }
    self.modules[name] = module

    return module
end

function Addon:GetModule(name, silent)
    local module = self.modules[name]

    if not module and not silent then
        error(("Cannot find module '%s'."):format(tostring(name)), 2)
    end

    return module
end

function Addon:Print(...)
    local parts = {}

    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. self.addonName .. "|r: " .. tconcat(parts, " "))
end

function Addon:RegisterChatCommand(command, method)
    local key = (self.addonName .. "_" .. command):upper()

    _G["SLASH_" .. key .. "1"] = "/" .. command:lower()
    SlashCmdList[key] = function(input)
        self[method](self, strtrim(input or ""))
    end
end

function W.NewAddon(name)
    -- Not "name": Core.lua stores the player name there.
    local addon = setmetatable({ addonName = name, modules = {} }, Addon)
    local events = CreateFrame("Frame")

    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_LOGIN")
    events:SetScript("OnEvent", function(frame, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 ~= name then
                return
            end

            frame:UnregisterEvent("ADDON_LOADED")

            if addon.OnInitialize then
                addon:OnInitialize()
            end

            if IsLoggedIn() then
                frame:UnregisterEvent("PLAYER_LOGIN")

                if addon.OnEnable then
                    addon:OnEnable()
                end
            end
        elseif event == "PLAYER_LOGIN" then
            frame:UnregisterEvent("PLAYER_LOGIN")

            if addon.OnEnable then
                addon:OnEnable()
            end
        end
    end)

    return addon
end
