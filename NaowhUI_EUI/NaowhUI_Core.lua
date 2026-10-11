-------------------------------------------------------------------------------
--  NaowhUI_Core.lua -- companion addon for EllesmereUI; never edits it (external injection).
--  Owns: NaowhUIEUIDB, the sidebar category + options module, GetProfile, the theme accent.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- Must match the addon folder: the sidebar's IsAddonLoaded(folder) check keys off it.
local MODULE_KEY = "NaowhUI_EUI"

local NAOWH_BLUE = { r = 0x00 / 255, g = 0xCF / 255, b = 0xFF / 255 }

local NaowhUI = {}
_G.NaowhUIEUI = NaowhUI
NaowhUI.BLUE = NAOWH_BLUE
NaowhUI.MODULE_KEY = MODULE_KEY

-- pairs(profile) also walks non-unit keys, so callers iterate this rather than guess by type.
NaowhUI.UF_UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

-- Unit-frame text slots that can carry a unit's name.
NaowhUI.UF_SLOTS = { "leftText", "rightText", "centerText", "extraText", "btbLeft", "btbRight", "btbCenter" }

-- A missing key means "use the module default", so absence has to be recorded and restored.
NaowhUI.ABSENT = "__naowh_absent__"
local ABSENT = NaowhUI.ABSENT

-- Resource bars are a dark-mode provider too, but deliberately left out.
NaowhUI.DARK_IDS = { "unitFrames", "raidFrames" }

-------------------------------------------------------------------------------
--  SavedVariables
-------------------------------------------------------------------------------
-- applied: opted in. setupDone: first-run prompt answered, either way.
local DEFAULTS = { themeApplied = false, applied = false, setupDone = false }

local function InitDB()
    if type(_G.NaowhUIEUIDB) ~= "table" then _G.NaowhUIEUIDB = {} end
    local d = _G.NaowhUIEUIDB
    for k, v in pairs(DEFAULTS) do
        if d[k] == nil then d[k] = v end
    end
    return d
end

local function db()
    return _G.NaowhUIEUIDB or InitDB()
end

local function Print(msg)
    print("|cff00cfffNaowhUI|r " .. tostring(msg))
end
NaowhUI.Print = Print

-- 3.3.5 regions have no SetShown until EllesmereUIOptions loads its shims.
function NaowhUI.Shown(region, show)
    if not region then return end
    if show then region:Show() else region:Hide() end
end

function NaowhUI.IsApplied()
    return db().applied == true
end

-------------------------------------------------------------------------------
--  Settings: per EllesmereUI profile
-------------------------------------------------------------------------------
-- NewDB lands us in profiles[name].addons[MODULE_KEY], so our settings switch, export and import
-- alongside EllesmereUI's own.
local _settingsDB
function NaowhUI.SettingsRoot()
    if _settingsDB and type(_settingsDB.profile) == "table" then
        return _settingsDB.profile
    end
    local L = _G.EllesmereUI and _G.EllesmereUI.Lite
    if L and L.NewDB then
        -- svName minus the trailing "DB" is the folder, so this lands under MODULE_KEY.
        _settingsDB = L.NewDB(MODULE_KEY .. "DB", { profile = {} })
        if _settingsDB and type(_settingsDB.profile) == "table" then
            return _settingsDB.profile
        end
    end
    return InitDB()   -- EllesmereUI absent: degrade to the account table rather than error
end

-------------------------------------------------------------------------------
--  Combat deferral
-------------------------------------------------------------------------------
-- Frames are never garbage collected, so one is shared across deferrals.
local deferFrame, deferQueue
function NaowhUI.RunOutOfCombat(fn)
    if not InCombatLockdown() then return fn() end

    if not deferFrame then
        deferQueue = {}
        deferFrame = CreateFrame("Frame")
        deferFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            -- Swap the queue out first: a deferred call can queue another one.
            local q = deferQueue
            deferQueue = {}
            for i = 1, #q do
                local ok, err = pcall(q[i])
                if not ok then Print("deferred call failed: " .. tostring(err)) end
            end
        end)
    end

    deferQueue[#deferQueue + 1] = fn
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-------------------------------------------------------------------------------
--  Reaching EllesmereUI's stored profiles
-------------------------------------------------------------------------------
-- The active profile's blob IS the table its db.profile points at, so a write here is live.
function NaowhUI.ProfileRoot(name)
    local euidb = _G.EllesmereUIDB
    local profs = euidb and euidb.profiles
    local p = profs and profs[name]
    return type(p) == "table" and p or nil
end

function NaowhUI.ProfileBlob(name, folder)
    local root = NaowhUI.ProfileRoot(name)
    local addons = root and root.addons
    local blob = type(addons) == "table" and addons[folder]
    return type(blob) == "table" and blob or nil
end

function NaowhUI.ForEachProfile(fn)
    local euidb = _G.EllesmereUIDB
    if not (euidb and type(euidb.profiles) == "table") then return end
    for name, root in pairs(euidb.profiles) do
        if type(root) == "table" then fn(name, root) end
    end
end

function NaowhUI.ActiveProfile()
    local EUI = _G.EllesmereUI
    local n = EUI and EUI.GetActiveProfileName and EUI.GetActiveProfileName()
    return n or "Default"
end

-------------------------------------------------------------------------------
--  Profile-scoped snapshots
-------------------------------------------------------------------------------
-- EllesmereUI's values before we overwrote them. Machine-local, so kept out of the profile blob.
-- Keyed by profile (a value from one is invalid in another) and by section (names collide).
function NaowhUI.Snap(section, name)
    local d = _G.NaowhUIEUIDB
    if type(d) ~= "table" then d = {}; _G.NaowhUIEUIDB = d end
    local all = d._snap
    if type(all) ~= "table" then all = {}; d._snap = all end
    local bySection = all[section]
    if type(bySection) ~= "table" then bySection = {}; all[section] = bySection end
    local p = NaowhUI.ActiveProfile()
    local byProf = bySection[p]
    if type(byProf) ~= "table" then byProf = {}; bySection[p] = byProf end
    local s = byProf[name]
    if type(s) ~= "table" then s = {}; byProf[name] = s end
    return s
end

-- Read-only Snap: Snap() builds its tables on the way down, so probing with it would seed a record
-- in every profile visited.
function NaowhUI.PeekSnap(section, name, profileName)
    local d = _G.NaowhUIEUIDB
    local all = type(d) == "table" and d._snap
    local bySection = type(all) == "table" and all[section]
    local byProf = type(bySection) == "table" and bySection[profileName or NaowhUI.ActiveProfile()]
    local s = type(byProf) == "table" and byProf[name]
    return type(s) == "table" and s or nil
end

-- For EllesmereUI values on the EllesmereUIDB root rather than in a profile: char-sheet text
-- sizes, the module-font entry.
function NaowhUI.SnapGlobal(name)
    local d = _G.NaowhUIEUIDB
    if type(d) ~= "table" then d = {}; _G.NaowhUIEUIDB = d end
    local all = d._gsnap
    if type(all) ~= "table" then all = {}; d._gsnap = all end
    local s = all[name]
    if type(s) ~= "table" then s = {}; all[name] = s end
    return s
end

function NaowhUI.PeekSnapGlobal(name)
    local d = _G.NaowhUIEUIDB
    local all = type(d) == "table" and d._gsnap
    local s = type(all) == "table" and all[name]
    return type(s) == "table" and s or nil
end

local function ForEachSnapRoot(fn)
    local d = _G.NaowhUIEUIDB
    if type(d) ~= "table" or type(d._snap) ~= "table" then return end
    for _, bySection in pairs(d._snap) do
        if type(bySection) == "table" then fn(bySection) end
    end
end

-- Snapshots are keyed by profile name, so a rename orphans them and strands what we forced in.
function NaowhUI.OnProfileRenamed(oldName, newName)
    if oldName == newName then return end
    ForEachSnapRoot(function(root)
        if root[oldName] ~= nil and root[newName] == nil then
            root[newName], root[oldName] = root[oldName], nil
        end
    end)
end

-- Drop it, or it would attach itself to a new profile of the same name.
function NaowhUI.OnProfileDeleted(name)
    ForEachSnapRoot(function(root) root[name] = nil end)
end

-------------------------------------------------------------------------------
--  Re-apply on profile switch
-------------------------------------------------------------------------------
-- SwitchProfile repoints every db.profile in place without a reload, so overrides written into the
-- outgoing profile's blob are not in the new one.
local reapplies = {}
function NaowhUI.RegisterReapply(fn)
    reapplies[#reapplies + 1] = fn
end

function NaowhUI.ReapplyAll()
    if NaowhUI.IsUninstalled and NaowhUI.IsUninstalled() then return end
    for i = 1, #reapplies do
        local ok, err = pcall(reapplies[i])
        if not ok then Print("re-apply failed: " .. tostring(err)) end
    end
    -- The Spec Override maps have to follow the moved overrides, or the next spec change writes
    -- the user's stale value back over us.
    if NaowhUI.SyncSpecOverrides then pcall(NaowhUI.SyncSpecOverrides) end
end

-- Deferred: RefreshAllAddons runs off the back of the switch and would overwrite us.
local _reapplyQueued = false
function NaowhUI.QueueReapply()
    if _reapplyQueued then return end
    _reapplyQueued = true
    C_Timer.After(0.1, function()
        _reapplyQueued = false
        NaowhUI.ReapplyAll()
    end)
end

-------------------------------------------------------------------------------
--  Owned features
-------------------------------------------------------------------------------
-- The QoL ports own their settings rather than overriding EllesmereUI's, so there is nothing to
-- hand back: Apply on profile switch, Teardown at uninstall, Reset.
local owned, ownedOrder = {}, {}
function NaowhUI.RegisterOwned(name, handlers)
    if type(name) ~= "string" or type(handlers) ~= "table" then return end
    if not owned[name] then ownedOrder[#ownedOrder + 1] = name end
    owned[name] = handlers
end

local function ForEachOwned(verb)
    for i = 1, #ownedOrder do
        local h = owned[ownedOrder[i]]
        local fn = h and h[verb]
        if type(fn) == "function" then
            local ok, err = pcall(fn)
            if not ok then Print(("owned %s failed (%s): %s"):format(verb, ownedOrder[i], tostring(err))) end
        end
    end
end

function NaowhUI.ApplyOwned()    ForEachOwned("Apply")    end
function NaowhUI.TeardownOwned() ForEachOwned("Teardown") end

-- Reset then Apply: Reset drops the settings table, Apply rebuilds from the defaults it re-seeds.
function NaowhUI.ResetOwned()
    ForEachOwned("Reset")
    ForEachOwned("Apply")
end

-- Owned state lives in the per-profile blob, so a switch repoints it and Apply has to re-run.
NaowhUI.RegisterReapply(function() NaowhUI.ApplyOwned() end)

-------------------------------------------------------------------------------
--  The NaowhUI look (opt-in preset)
-------------------------------------------------------------------------------
-- Registered at load, but nothing runs until the user says yes: a fresh install writes nothing.
local presets = {}
function NaowhUI.RegisterPreset(fn)
    presets[#presets + 1] = fn
end

function NaowhUI.ApplyPreset()
    local d = db()
    d.applied, d.setupDone = true, true
    d.uninstalled = nil
    for i = 1, #presets do
        local ok, err = pcall(presets[i])
        if not ok then Print("preset step failed: " .. tostring(err)) end
    end
    if NaowhUI.SyncSpecOverrides then pcall(NaowhUI.SyncSpecOverrides) end
    local EUI = _G.EllesmereUI
    if EUI and EUI.RefreshPage then EUI:RefreshPage() end
end

-- preferredIndex 3 keeps Blizzard's own dialogs taint-free.
StaticPopupDialogs["NAOWHUI_FIRSTRUN"] = {
    text = "|cff00cfffNaowhUI|r\n\nApply the NaowhUI look?\n\nThis turns on the top bar and the target arrows, and adjusts a few EllesmereUI settings to match.\n\nYou can undo all of it at any time with |cffffffffReset|r in the NaowhUI options.",
    button1 = "Apply",
    button2 = "Not now",
    OnAccept = function() NaowhUI.ApplyPreset() end,
    OnCancel = function() db().setupDone = true end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Reaching an EllesmereUI module's settings
-------------------------------------------------------------------------------
-- Not GetAddon(folder).db.profile: UnitFrames and DamageMeters keep db in a file-local, so that
-- route is nil. Caches the db object, since a switch swaps .profile out from under it.
local dbCache = {}
function NaowhUI.GetProfile(folder)
    local d = dbCache[folder]
    if d then return d.profile end

    local L = _G.EllesmereUI and _G.EllesmereUI.Lite
    if not L then return nil end

    local addon = L.GetAddon and L.GetAddon(folder, true)
    if addon and addon.db and addon.db.profile then
        dbCache[folder] = addon.db
        return addon.db.profile
    end

    local reg = L._dbRegistry
    if type(reg) == "table" then
        for i = 1, #reg do
            local e = reg[i]
            if e and e.folder == folder and e.profile then
                dbCache[folder] = e
                return e.profile
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Fonts
-------------------------------------------------------------------------------
-- A font NAME, never a path: EllesmereUI resolves names through LibSharedMedia-3.0, so any
-- LSM-shared font works with no media path of ours to keep in step.
NaowhUI.FONT_DEFAULT = "__default"   -- sentinel: follow EllesmereUI's global font

local FALLBACK_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
NaowhUI.FALLBACK_FONT = FALLBACK_FONT

-- ResolveFontName never returns nil (an unrecognised name resolves to Expressway, not the global
-- font), so the sentinel has to be filtered out ahead of it.
function NaowhUI.FontPath(name)
    local EUI = _G.EllesmereUI
    if name and name ~= "" and name ~= NaowhUI.FONT_DEFAULT and EUI and EUI.ResolveFontName then
        local ok, p = pcall(EUI.ResolveFontName, name)
        if ok and type(p) == "string" and p ~= "" then return p end
    end
    if EUI and EUI.GetFontPath then
        local ok, p = pcall(EUI.GetFontPath)
        if ok and type(p) == "string" and p ~= "" then return p end
    end
    return FALLBACK_FONT
end

-- The same rows EllesmereUI builds for its own font pickers. Their "__global" row is renamed in
-- place so it keeps its spot at the top of the order.
function NaowhUI.BuildFontValues(defaultLabel)
    local EUI      = _G.EllesmereUI
    local DEFAULT  = NaowhUI.FONT_DEFAULT
    local values, order

    if EUI and EUI.BuildFontDropdownData then
        local ok, v, o = pcall(EUI.BuildFontDropdownData)
        if ok and type(v) == "table" and type(o) == "table" then values, order = v, o end
    end

    if values then
        values["__global"] = nil
        for i = 1, #order do
            if order[i] == "__global" then order[i] = DEFAULT; break end
        end
    else
        -- EllesmereUI too old to expose the picker: fall back to its bundled names alone.
        values, order = {}, { DEFAULT }
        local names = {}
        if EUI and EUI.FONT_FILES then
            for name in pairs(EUI.FONT_FILES) do names[#names + 1] = name end
            table.sort(names)
        end
        for _, name in ipairs(names) do
            values[name] = name
            order[#order + 1] = name
        end
    end

    values[DEFAULT] = { text = defaultLabel or "Default (EllesmereUI)" }
    values._noLoc = true   -- font names are data; never run them through the translator
    return values, order
end

-------------------------------------------------------------------------------
--  Damage meter repaint
-------------------------------------------------------------------------------
-- The 3.3.5 meter keeps its windows in profile.windows and rebuilds them all from _EDM_Apply.
-- Debounced so several setters in one click repaint once.
local _dmRefreshQueued = false

function NaowhUI.DMWindows()
    local prof = NaowhUI.GetProfile("EllesmereUIDamageMeters")
    local w = prof and prof.windows
    return type(w) == "table" and w or nil
end

function NaowhUI.RefreshDamageMeter()
    if _dmRefreshQueued then return end
    _dmRefreshQueued = true
    C_Timer.After(0, function()
        _dmRefreshQueued = false
        if _G._EDM_Apply then
            NaowhUI.RunOutOfCombat(function() pcall(_G._EDM_Apply) end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Accent scope
-------------------------------------------------------------------------------
-- Modules opt into the accent: quest headers, meter bars, Mythic+ titles, Friends tab, reskin.
-- Every key is read as `~= false`, so a MISSING key means ON -- the snapshot records absence.
-- 3.3.5: the quest tracker keeps these at the profile root; the meter's are per window (below).
local ACCENT_OPTOUT = {
    { folder = "EllesmereUIQuestTracker", keys = { "headerUseAccent", "lineUseAccent" } },
}
NaowhUI.ACCENT_OPTOUT = ACCENT_OPTOUT
NaowhUI.DM_ACCENT_KEYS = { "titleUseAccent", "borderUseAccent" }

function NaowhUI.ApplyAccentScope(on)
    local saved = NaowhUI.Snap("root", "accent")
    -- Both refreshes below are full module rebuilds, and this re-runs on every login and switch.
    local changed = false

    -- ABSENT, not false: writing false back at uninstall would leave quest headers un-accented.
    local function Set(t, id, key)
        if on then
            if saved[id] == nil then
                if t[key] == nil then saved[id] = ABSENT else saved[id] = t[key] and true or false end
            end
            if t[key] ~= false then t[key] = false; changed = true end
        elseif saved[id] ~= nil then
            local prev = saved[id]
            if prev == ABSENT then prev = nil end
            if t[key] ~= prev then t[key] = prev; changed = true end
            saved[id] = nil
        end
    end

    for _, m in ipairs(ACCENT_OPTOUT) do
        local prof = NaowhUI.GetProfile(m.folder)
        local t = prof and (m.sub and prof[m.sub] or prof)
        if type(t) == "table" then
            for _, key in ipairs(m.keys) do Set(t, m.folder .. "." .. key, key) end
        end
    end

    local windows = NaowhUI.DMWindows()
    if windows then
        for i, w in ipairs(windows) do
            if type(w) == "table" then
                for _, key in ipairs(NaowhUI.DM_ACCENT_KEYS) do Set(w, "dm." .. i .. "." .. key, key) end
            end
        end
    end

    if changed then
        if _G._EQT_RefreshAll then pcall(_G._EQT_RefreshAll) end
        NaowhUI.RefreshDamageMeter()
    end

    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end

NaowhUI.RegisterReapply(function()
    if db().themeApplied then NaowhUI.ApplyAccentScope(true) end
end)

-------------------------------------------------------------------------------
--  Theme
-------------------------------------------------------------------------------
function NaowhUI.ApplyBlueAccent()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.SetAccentColor) then return false end
    NaowhUI.ApplyAccentScope(true)
    EUI.SetAccentColor(NAOWH_BLUE.r, NAOWH_BLUE.g, NAOWH_BLUE.b)
    db().themeApplied = true
    return true
end

function NaowhUI.ClearBlueAccent()
    local EUI = _G.EllesmereUI
    db().themeApplied = false
    NaowhUI.ApplyAccentScope(false)
    if EUI and EUI.ResetAccentColor then EUI.ResetAccentColor() end
end

-------------------------------------------------------------------------------
--  Options widgets
-------------------------------------------------------------------------------
-- Inline gear on a DualRow half whose click opens a modal of our own. EllesmereUI's own
-- BuildCogPopup covers the rows-in-a-popup case; this is for the pickers it cannot express.
function NaowhUI.AttachPicker(region, onClick, isOff, offLabel, offState)
    local EUI = _G.EllesmereUI
    if not EUI or EUI._prebuilding or not region then return end

    local btn = CreateFrame("Button", nil, region)
    btn:SetSize(26, 26)
    -- A label cell carries no control to sit beside, so fall back to the cell's own right edge.
    local anchorTo = region._lastInline or region._control
    if anchorTo then
        btn:SetPoint("RIGHT", anchorTo, "LEFT", -9, 0)
    else
        btn:SetPoint("RIGHT", region, "RIGHT", -12, 0)
    end
    region._lastInline = btn
    btn:SetFrameLevel(region:GetFrameLevel() + 5)

    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(EUI.COGS_ICON)
    btn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
    btn:SetScript("OnLeave", function(self) self:SetAlpha(isOff() and 0.15 or 0.4) end)
    btn:SetScript("OnClick", onClick)

    local block = CreateFrame("Frame", nil, btn)
    block:SetAllPoints()
    block:SetFrameLevel(btn:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:SetScript("OnEnter", function()
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(btn, EUI.DisabledTooltip(offLabel, offState))
        end
    end)
    block:SetScript("OnLeave", function()
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    local function Sync()
        local off = isOff()
        btn:SetAlpha(off and 0.15 or 0.4)
        NaowhUI.Shown(block, off)
    end
    if EUI.RegisterWidgetRefresh then EUI.RegisterWidgetRefresh(Sync) end
    Sync()
end

-------------------------------------------------------------------------------
--  General page
-------------------------------------------------------------------------------
local function BuildGeneralPage(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    -- The way back in for anyone who answered "Not now".
    if not db().applied then
        _, h = W:SectionHeader(parent, "SETUP", y); y = y - h
        _, h = W:WideButton(parent, "Apply the NaowhUI Look", y, NaowhUI.ApplyPreset)
        y = y - h
    end

    _, h = W:SectionHeader(parent, "NAOWHUI THEME", y); y = y - h

    _, h = W:Toggle(parent, "NaowhUI Blue Accent (#00CFFF)", y,
        function() return db().themeApplied == true end,
        function(v)
            if v then NaowhUI.ApplyBlueAccent() else NaowhUI.ClearBlueAccent() end
            EUI:RefreshPage()
        end,
        "Colours the EllesmereUI settings menu in NaowhUI blue. Your in-game UI keeps its normal colours (a /reload may be needed to fully update).")
    y = y - h

    if NaowhUI.BuildIconSection then
        y = NaowhUI.BuildIconSection(parent, y)
    end

    if NaowhUI.BuildActionBarSection then
        y = NaowhUI.BuildActionBarSection(parent, y)
    end

    if NaowhUI.BuildUninstallSection then
        y = NaowhUI.BuildUninstallSection(parent, y)
    end

    return math.abs(y)
end

-- Resolved at call time: the feature files load after this one.
local PAGES = {
    ["General"]    = BuildGeneralPage,
    ["Top Bar"]    = function(p, y) return NaowhUI.BuildTopBarOptions      and NaowhUI.BuildTopBarOptions(p, y) end,
    ["Gameplay"]   = function(p, y) return NaowhUI.BuildGameplayOptions    and NaowhUI.BuildGameplayOptions(p, y) end,
    ["QoL"]        = function(p, y) return NaowhUI.BuildQoLOptions         and NaowhUI.BuildQoLOptions(p, y) end,
    ["Frames"]     = function(p, y) return NaowhUI.BuildFramesOptions      and NaowhUI.BuildFramesOptions(p, y) end,
    ["Nameplates"] = function(p, y) return NaowhUI.BuildNameplatesOptions  and NaowhUI.BuildNameplatesOptions(p, y) end,
    ["Blizz UI"]   = function(p, y) return NaowhUI.BuildBlizzOptions       and NaowhUI.BuildBlizzOptions(p, y) end,
}
-- BuildTabs lays these in a single non-wrapping row and nothing scrolls, so the bar has a hard
-- width budget: seven short labels fit. An eighth belongs as a section on an existing page.
local PAGE_ORDER = { "General", "Top Bar", "Gameplay", "QoL", "Frames", "Nameplates", "Blizz UI" }

-------------------------------------------------------------------------------
--  Reset
-------------------------------------------------------------------------------
-- Active profile only. Also fired by EllesmereUI's own "Reset ALL EUI Addon Settings".
function NaowhUI.ResetAll()
    local EUI = _G.EllesmereUI
    local d = db()
    d.themeApplied, d.applied = false, false   -- setupDone stays: don't re-open the first-run prompt

    NaowhUI.ApplyAccentScope(false)   -- un-scope before the accent reset; the snapshot is ours
    if EUI and EUI.ResetAccentColor then EUI.ResetAccentColor() end

    if NaowhUI.ResetCDM          then NaowhUI.ResetCDM()          end
    if NaowhUI.ResetSkyriding    then NaowhUI.ResetSkyriding()    end
    if NaowhUI.ResetDragonRiding then NaowhUI.ResetDragonRiding() end
    if NaowhUI.ResetFrames       then NaowhUI.ResetFrames()       end
    if NaowhUI.ResetIcons        then NaowhUI.ResetIcons()        end
    if NaowhUI.ResetBlizz        then NaowhUI.ResetBlizz()        end
    if NaowhUI.ResetPortals      then NaowhUI.ResetPortals()      end
    if NaowhUI.ResetTopBar       then NaowhUI.ResetTopBar()       end
    if NaowhUI.ResetNameplates   then NaowhUI.ResetNameplates()   end
    if NaowhUI.ResetMythicTimer  then NaowhUI.ResetMythicTimer()  end
    if NaowhUI.ResetActionBars   then NaowhUI.ResetActionBars()   end

    -- Owned features clear their own settings; nothing above this line reaches them.
    NaowhUI.ResetOwned()

    -- We bank our values into the Spec Override maps, so those have to be handed back too.
    if NaowhUI.RestoreSpecOverrides then NaowhUI.RestoreSpecOverrides() end

    if EUI and EUI.InvalidatePageCache then EUI:InvalidatePageCache() end
end

-------------------------------------------------------------------------------
--  Registration
-------------------------------------------------------------------------------
-- RegisterModule whitelists callers by their "AddOns/<folder>/" path via debugstack. From a
-- loadstring chunk the caller is `[string ...]`, so the guard falls through.
local function RegisterModule(config)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterModule) then return end

    _G.__NaowhUI_pendingReg = { key = MODULE_KEY, config = config }
    local trampoline = loadstring([[
        local r = _G.__NaowhUI_pendingReg
        if r and EllesmereUI and EllesmereUI.RegisterModule then
            EllesmereUI:RegisterModule(r.key, r.config)
        end
    ]], "NaowhUI-register")
    local ok = trampoline and pcall(trampoline)
    _G.__NaowhUI_pendingReg = nil

    if not ok then
        pcall(function() EUI:RegisterModule(MODULE_KEY, config) end)
    end
end

-- The sidebar is built lazily on first panel open, so mutating these at login is early enough.
local function InjectSidebar()
    local EUI = _G.EllesmereUI
    if not EUI then return end

    -- alwaysLoaded hides the power toggle and marks the row loaded and clickable.
    EUI._addonInfoByFolder = EUI._addonInfoByFolder or {}
    EUI._addonInfoByFolder[MODULE_KEY] = EUI._addonInfoByFolder[MODULE_KEY] or {
        folder       = MODULE_KEY,
        display      = "NaowhUI",
        search_name  = "NaowhUI Naowh",
        alwaysLoaded = true,
    }

    EUI._syncExempt = EUI._syncExempt or {}
    EUI._syncExempt[MODULE_KEY] = true   -- no cross-module profile sync

    -- Guard against double-insertion on reload.
    EUI.ADDON_GROUPS = EUI.ADDON_GROUPS or {}
    for _, group in ipairs(EUI.ADDON_GROUPS) do
        if group.key == "naowhui" then return end
    end
    table.insert(EUI.ADDON_GROUPS, 1, {
        key     = "naowhui",
        label   = "NaowhUI",
        members = { MODULE_KEY },
    })
end

-- Export/import walks _ADDON_DB_MAP rather than the DB registry, so a companion addon is skipped
-- without an entry here. The import/export UI reads the map live and matches entries on `folder`.
local function InjectProfileAddon()
    local EUI = _G.EllesmereUI
    local map = EUI and EUI._ADDON_DB_MAP
    if type(map) ~= "table" then return end
    for _, e in ipairs(map) do
        if e.folder == MODULE_KEY then return end   -- guard against a reload re-inserting us
    end
    -- Only folder + display are read; canon and the loaded check fall back to the folder.
    map[#map + 1] = { folder = MODULE_KEY, display = "NaowhUI" }
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    self:UnregisterEvent("PLAYER_LOGIN")
    InitDB()

    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterModule) then
        Print("|cffff6060EllesmereUI not found.|r NaowhUI requires EllesmereUI to be installed and enabled.")
        return
    end

    InjectSidebar()
    InjectProfileAddon()

    -- Core is first in the toc, so this runs before any module applies anything.
    if NaowhUI.RunMigrations then NaowhUI.RunMigrations() end

    if EUI.SwitchProfile then hooksecurefunc(EUI, "SwitchProfile", NaowhUI.QueueReapply) end
    if EUI.OnSpecSwitchComplete then hooksecurefunc(EUI, "OnSpecSwitchComplete", NaowhUI.QueueReapply) end
    if EUI.ApplyProfileData then hooksecurefunc(EUI, "ApplyProfileData", NaowhUI.QueueReapply) end
    if EUI.OnProfileRenamed then hooksecurefunc(EUI, "OnProfileRenamed", NaowhUI.OnProfileRenamed) end
    if EUI.OnProfileDeleted then hooksecurefunc(EUI, "OnProfileDeleted", NaowhUI.OnProfileDeleted) end

    RegisterModule({
        title       = "NaowhUI",
        description = "Naowh's curated overrides for EllesmereUI.",
        pages       = PAGE_ORDER,
        buildPage   = function(pageName, parent, yOffset)
            local build = PAGES[pageName]
            return (build and build(parent, yOffset)) or math.abs(yOffset)
        end,
        onReset     = NaowhUI.ResetAll,
    })

    -- Delayed so it lands after EllesmereUI's own login chatter, and never mid-pull.
    if not db().setupDone then
        C_Timer.After(4, function()
            NaowhUI.RunOutOfCombat(function()
                if not db().setupDone then StaticPopup_Show("NAOWHUI_FIRSTRUN") end
            end)
        end)
    end
end)
