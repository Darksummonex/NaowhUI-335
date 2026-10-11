-------------------------------------------------------------------------------
--  NaowhUI_Uninstall.lua -- dead man's switch. Once disabled we never load again, so the restore
--  has to run in the last session we are alive for: PLAYER_LOGOUT, before the SavedVariables flush.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

local Print  = NaowhUI.Print
local ABSENT = NaowhUI.ABSENT

local function Put(t, k, prev)
    if prev == ABSENT then t[k] = nil else t[k] = prev end
end

-------------------------------------------------------------------------------
--  Reaching one profile's stored settings
-------------------------------------------------------------------------------
local function CdmBarsByKey(B)
    local blob = B("EllesmereUICooldownManager")
    local bars = blob and blob.cdmBars and blob.cdmBars.bars
    if type(bars) ~= "table" then return nil end
    local byKey = {}
    for i, bd in ipairs(bars) do byKey[bd.key or ("#" .. i)] = bd end
    return byKey
end

local function ActionBars(B)
    local blob = B("EllesmereUIActionBars")
    local bars = blob and blob.bars
    return type(bars) == "table" and bars or nil
end

local function DMWindows(B)
    local blob = B("EllesmereUIDamageMeters")
    local w = blob and blob.windows
    return type(w) == "table" and w or nil
end

-- Snapshot shape is barKey -> prior value.
local function CdmBarSetting(dbKey)
    return function(saved, B)
        local byKey = CdmBarsByKey(B)
        if not byKey then return end
        for key, prev in pairs(saved) do
            local bd = byKey[key]
            if bd then Put(bd, dbKey, prev) end
        end
    end
end

-------------------------------------------------------------------------------
--  The address map
-------------------------------------------------------------------------------
-- A snapshot records WHAT the value was; this records WHERE it lives. KEEP IN STEP WITH THE
-- MODULES: a write with no entry here cannot be undone for any profile but the active one.
local RESTORE = {
    root = {
        accent = function(saved, B)
            for _, m in ipairs(NaowhUI.ACCENT_OPTOUT) do
                local t = B(m.folder)
                if type(t) == "table" then
                    for _, key in ipairs(m.keys) do
                        local prev = saved[m.folder .. "." .. key]
                        -- Put, not a plain assign: these can hold ABSENT.
                        if prev ~= nil then Put(t, key, prev) end
                    end
                end
            end
            local windows = DMWindows(B)
            if windows then
                for id, prev in pairs(saved) do
                    local i, key = tostring(id):match("^dm%.(%d+)%.(.+)$")
                    local w = i and windows[tonumber(i)]
                    if type(w) == "table" then Put(w, key, prev) end
                end
            end
        end,
    },

    icons = {
        cdm = function(saved, B)
            local byKey = CdmBarsByKey(B)
            if not byKey then return end
            for key, s in pairs(saved) do
                local bd = byKey[key]
                if bd and type(s) == "table" then bd.iconShape, bd.iconZoom = s.shape, s.zoom end
            end
        end,
        uf = function(saved, B)
            local blob = B("EllesmereUIUnitFrames")
            if not blob then return end
            for unitKey, s in pairs(saved) do
                local u = blob[unitKey]
                if type(u) == "table" and type(s) == "table" then
                    u.buffCropIcons, u.debuffCropIcons = s.bCrop, s.dCrop
                    u.buffIconZoom,  u.debuffIconZoom  = s.bZoom, s.dZoom
                end
            end
        end,
    },

    frames = {
        uf = function(saved, B)
            local blob = B("EllesmereUIUnitFrames")
            if not blob then return end
            for id, prev in pairs(saved) do
                local unitKey, slot = id:match("^(.-)|(.+)$")
                local u = unitKey and blob[unitKey]
                if type(u) == "table" then u[slot .. "ClassColor"] = prev and true or false end
            end
        end,
        rf = function(saved, B)
            local blob = B("EllesmereUIRaidFrames")
            if not blob then return end
            if saved.mode ~= nil and type(blob.raid) == "table" then Put(blob.raid, "nameColorMode", saved.mode) end
            if saved.partyMode ~= nil and type(blob.party) == "table" then Put(blob.party, "nameColorMode", saved.partyMode) end
            if saved.previewMode ~= nil then Put(blob, "previewMode", saved.previewMode) end
        end,
        -- id is "<window index>|<key>".
        dm = function(saved, B)
            local windows = DMWindows(B)
            if not windows then return end
            for id, prev in pairs(saved) do
                local i, key = tostring(id):match("^(%d+)|(.+)$")
                local w = i and windows[tonumber(i)]
                if type(w) == "table" then Put(w, key, prev) end
            end
        end,
        -- The dark-mode palette hangs off the profile root, not off any addon's blob.
        bg = function(saved, _, root)
            local pal = root.darkMode
            if type(pal) ~= "table" then return end
            for k, prev in pairs(saved) do Put(pal, k, prev) end
        end,
        combat = function(saved, B)
            local blob = B("EllesmereUIUnitFrames")
            local p = blob and blob.player
            if type(p) ~= "table" then return end
            for k, prev in pairs(saved) do Put(p, k, prev) end
        end,
        combatTarget = function(saved, B)
            local blob = B("EllesmereUIUnitFrames")
            local t = blob and blob.target
            if type(t) ~= "table" then return end
            for k, prev in pairs(saved) do Put(t, k, prev) end
        end,
        -- Only providers recorded as OFF need undoing. Dark mode the user already had on is theirs.
        dark = function(saved, B)
            if saved.unitFrames == false then
                local blob = B("EllesmereUIUnitFrames")
                if blob then blob.darkTheme = false end
            end
            if saved.raidFrames == false then
                local blob = B("EllesmereUIRaidFrames")
                local prev = type(saved.rfPrev) == "table" and saved.rfPrev or {}
                for _, group in ipairs({ "raid", "party" }) do
                    local c = blob and blob[group]
                    if type(c) == "table" and c.healthColorMode == "dark" then
                        local p = prev[group]
                        c.healthColorMode = (p and p ~= ABSENT and p ~= "dark") and p or "class"
                    end
                end
            end
        end,
    },

    cdm = {
        tip    = CdmBarSetting("showTooltip"),
        kb     = CdmBarSetting("showKeybind"),
        mirror = CdmBarSetting("pressMirror"),
        kbText = function(saved, B)
            local byKey = CdmBarsByKey(B)
            if not byKey then return end
            for id, prev in pairs(saved) do
                local key, dbKey = id:match("^(.-)|(.+)$")
                local bd = key and byKey[key]
                if bd then Put(bd, dbKey, prev) end
            end
        end,
        ab = function(saved, B)
            local bars = ActionBars(B)
            if not bars then return end
            for key, prev in pairs(saved) do
                if type(bars[key]) == "table" then Put(bars[key], "hideKeybind", prev) end
            end
        end,
        -- Written and read as a pair, so both keys are handed back in one go.
        vis = function(saved, B)
            local bars = ActionBars(B)
            if not bars then return end
            for key, rec in pairs(saved) do
                local bar = bars[key]
                if type(bar) == "table" and type(rec) == "table" then
                    Put(bar, "barVisibility", rec.scalar)
                    Put(bar, "visibilityModes", rec.modes)
                end
            end
        end,
    },

    nameplates = {
        euiArrows = function(saved, B)
            local blob = B("EllesmereUINameplates")
            if blob and saved.prev ~= nil then Put(blob, "showTargetArrows", saved.prev) end
        end,
    },

    topBar = {
        euiFps = function(saved, B)
            local blob = B("EllesmereUIQoL")
            if blob and saved.prev ~= nil then Put(blob, "fps", saved.prev) end
        end,
    },
}

-------------------------------------------------------------------------------
--  Replay
-------------------------------------------------------------------------------
local function RestoreProfile(profileName)
    local root = NaowhUI.ProfileRoot(profileName)
    if not root then return end

    local function B(folder) return NaowhUI.ProfileBlob(profileName, folder) end

    for section, byName in pairs(RESTORE) do
        for name, restore in pairs(byName) do
            local saved = NaowhUI.PeekSnap(section, name, profileName)
            if saved and next(saved) then
                local ok, err = pcall(restore, saved, B, root)
                if not ok then
                    Print(("restore failed (%s/%s): %s"):format(section, name, tostring(err)))
                end
            end
        end
    end
end

-- Snapshots are keyed by profile, so they are the record of which profiles we ever wrote into.
local function RestoreAllProfiles()
    local d = _G.NaowhUIEUIDB
    local snaps = type(d) == "table" and d._snap
    if type(snaps) ~= "table" then return end

    local touched = {}
    for _, bySection in pairs(snaps) do
        if type(bySection) == "table" then
            for profileName in pairs(bySection) do touched[profileName] = true end
        end
    end
    for profileName in pairs(touched) do RestoreProfile(profileName) end
end

-------------------------------------------------------------------------------
--  Spec Overrides
-------------------------------------------------------------------------------
-- Values banked into the override maps (NaowhUI_SpecOverrides.lua) would otherwise keep driving
-- the setting on every spec change long after we are gone.
local function RestoreAllSpecOverrides()
    local restored = 0
    NaowhUI.ForEachProfile(function(name)
        if NaowhUI.RestoreSpecOverrides then restored = restored + NaowhUI.RestoreSpecOverrides(name) end
        if NaowhUI.DropOwnSpecOverrides then NaowhUI.DropOwnSpecOverrides(name) end
    end)
    return restored
end

-- The values on the EllesmereUIDB root rather than inside a profile.
local function RestoreGlobals()
    local d = _G.NaowhUIEUIDB

    if NaowhUI.RestoreCharSheetGlobals then pcall(NaowhUI.RestoreCharSheetGlobals) end

    -- CVars are not in SavedVariables, so the snapshot restore above cannot reach them.
    if NaowhUI.RestoreQoLCVars then pcall(NaowhUI.RestoreQoLCVars) end

    if type(d) == "table" and d.themeApplied then
        local EUI = _G.EllesmereUI
        if EUI and EUI.ResetAccentColor then pcall(EUI.ResetAccentColor) end
    end
end

-------------------------------------------------------------------------------
--  Erasing ourselves
-------------------------------------------------------------------------------
-- The live blob is emptied, not removed: SettingsRoot() holds a handle to that exact table, and
-- dropping it would leave the options page writing into an orphan.
local function WipeSettings(live)
    local active = NaowhUI.ActiveProfile()
    NaowhUI.ForEachProfile(function(name, root)
        local addons = root.addons
        if type(addons) ~= "table" then return end
        local blob = addons[NaowhUI.MODULE_KEY]
        if type(blob) ~= "table" then return end
        if live and name == active then wipe(blob) else addons[NaowhUI.MODULE_KEY] = nil end
    end)
end

local function WipeDB()
    local d = _G.NaowhUIEUIDB
    if type(d) ~= "table" then return end
    local schema = d.schema
    wipe(d)
    d.schema      = schema   -- the migrations already ran; re-running them on an empty DB is noise
    d.setupDone   = true     -- coming back in must not re-open the first-run prompt
    d.applied     = false
    d.themeApplied = false
    d.uninstalled = true
end

function NaowhUI.IsUninstalled()
    local d = _G.NaowhUIEUIDB
    return type(d) == "table" and d.uninstalled == true
end

-------------------------------------------------------------------------------
--  Repaint (live only)
-------------------------------------------------------------------------------
-- By name, not by value: an unloaded module leaves a nil, which would cut ipairs short.
local REFRESHERS = {
    "_ECME_Apply", "_EDM_Apply", "_EUF_ReloadFrames", "_ERF_RefreshAll",
    "_ENP_RefreshAllSettings", "_EQT_RefreshAll", "_EQOL_RefreshAll",
}

local function RefreshEverything()
    for _, name in ipairs(REFRESHERS) do
        local fn = _G[name]
        if type(fn) == "function" then pcall(fn) end
    end

    local EUI = _G.EllesmereUI
    if EUI and EUI.RefreshDarkMode then pcall(EUI.RefreshDarkMode) end

    -- Action bars are secure.
    if type(_G._EAB_Apply) == "function" and not InCombatLockdown() then pcall(_G._EAB_Apply) end
end

local function HideOurFrames()
    if NaowhUI.HideTopBar then pcall(NaowhUI.HideTopBar) end
    if NaowhUI.HideTargetArrow then pcall(NaowhUI.HideTargetArrow) end
    if NaowhUI.TeardownOwned then pcall(NaowhUI.TeardownOwned) end
    -- Left registered, our movers would be dead entries in the next Unlock Mode session.
    if NaowhUI.QoL and NaowhUI.QoL.UnregisterMovers then pcall(NaowhUI.QoL.UnregisterMovers) end
end

-------------------------------------------------------------------------------
--  Uninstall
-------------------------------------------------------------------------------
-- live=false at logout: restore the data, skip every refresh and frame call.
function NaowhUI.Uninstall(opts)
    opts = opts or {}
    local live = opts.live ~= false

    -- Before ResetAll, which restores the active profile's maps too and would leave the count short.
    local specRestored = RestoreAllSpecOverrides()

    -- The Reset chain knows which EllesmereUI refresh each change needs, so the screen repaints.
    if live then pcall(NaowhUI.ResetAll) end

    -- The only thing that reaches the profiles the user is not standing in.
    RestoreAllProfiles()
    RestoreGlobals()

    WipeSettings(live)
    WipeDB()

    if live then
        HideOurFrames()
        RefreshEverything()
        local EUI = _G.EllesmereUI
        if EUI and EUI.InvalidatePageCache then pcall(function() EUI:InvalidatePageCache() end) end
        if EUI and EUI.RefreshPage then pcall(function() EUI:RefreshPage() end) end
    end

    if not opts.silent then
        Print("uninstalled. Every EllesmereUI setting NaowhUI changed has been handed back. A |cffffffff/reload|r will settle anything still on screen.")
        if specRestored > 0 then
            Print(("handed |cffffffff%d|r Spec Override value(s) back; they were holding NaowhUI's settings and would have come back on your next spec change."):format(specRestored))
        end
    end
end

StaticPopupDialogs["NAOWHUI_UNINSTALL"] = {
    text = "|cff00cfffNaowhUI|r\n\nHand every EllesmereUI setting NaowhUI changed back to what it was, in |cffffffffevery profile|r, and clear all NaowhUI settings?\n\nThis cannot be undone.",
    button1 = "Uninstall",
    button2 = "Cancel",
    OnAccept = function() NaowhUI.Uninstall() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Options section (rendered on the General page by NaowhUI_Core)
-------------------------------------------------------------------------------
function NaowhUI.BuildUninstallSection(parent, y)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "UNINSTALL", y); y = y - h

    _, h = W:WideButton(parent, "Uninstall NaowhUI (Restore EllesmereUI)", y, function()
        if InCombatLockdown() then
            Print("Cannot uninstall during combat.")
            return
        end
        StaticPopup_Show("NAOWHUI_UNINSTALL")
    end)
    y = y - h

    return y
end

-------------------------------------------------------------------------------
--  The switch
-------------------------------------------------------------------------------
-- 3.3.5 has no GetAddOnEnableState: GetAddOnInfo's 4th return is the enable flag the next load
-- will use, and the AddOns list writes it through the global DisableAddOn. The flag is per
-- character, which is the scope a 3.3.5 addon list edits anyway.
local _armed = false

local function EnabledForNextLoad()
    if not GetAddOnInfo then return nil end
    local ok, name, _, _, enabled = pcall(GetAddOnInfo, NaowhUI.MODULE_KEY)
    if not ok or not name then return nil end
    return enabled and true or false
end

-- Arms only when the flag reads "enabled" at login, so a client that reports it oddly never
-- uninstalls a healthy install.
local function ProbeSwitch()
    _armed = EnabledForNextLoad() == true
end

local function IsDisabledForNextLoad()
    return _armed and EnabledForNextLoad() == false
end

-- Cosmetic. The logout check below is the actual trigger.
local function InstallNotice()
    if type(DisableAddOn) ~= "function" then return end
    hooksecurefunc("DisableAddOn", function(nameOrIndex)
        if nameOrIndex ~= NaowhUI.MODULE_KEY or NaowhUI.IsUninstalled() then return end
        Print("disabled. Your EllesmereUI settings will be handed back automatically when you reload.")
    end)
end

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:RegisterEvent("PLAYER_LOGOUT")
watch:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ProbeSwitch()
        InstallNotice()
        return
    end

    -- PLAYER_LOGOUT: the SavedVariables flush follows this, so it is the last instant we can still
    -- reach EllesmereUI's DB.
    if IsDisabledForNextLoad() and not NaowhUI.IsUninstalled() then
        pcall(NaowhUI.Uninstall, { live = false, silent = true })
    end
end)
