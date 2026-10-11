-------------------------------------------------------------------------------
--  NaowhUI_QoLShim.lua -- shared helpers for the four QoL features: settings, refresh callbacks,
--  spec and zone state, fonts, sounds, colours and mover registration. Loads before its users.
--  Frames register with EllesmereUI's Unlock Mode rather than carrying their own drag handling.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

local QoL = {}
NaowhUI.QoL = QoL

-------------------------------------------------------------------------------
--  Conflict guard
-------------------------------------------------------------------------------
-- Both addons run these four features off separate DBs; ours is the half that stands down.
local function IsAddOnLoadedSafe(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        return ok and loaded and true or false
    end
    local legacy = _G.IsAddOnLoaded
    if legacy then
        local ok, loaded = pcall(legacy, name)
        return ok and loaded and true or false
    end
    return false
end
QoL.IsAddOnLoaded = IsAddOnLoadedSafe

-- Resolved once per session, on first ask. NaowhQOL is a hard load-order peer, not a dependency,
-- so this is only reliable from PLAYER_LOGIN onward -- which is when every caller asks.
local _conflict
function QoL.HasNaowhQOL()
    if _conflict == nil then _conflict = IsAddOnLoadedSafe("NaowhQOL") end
    return _conflict
end

-- Printed once, not once per feature.
local _conflictWarned = false
function QoL.WarnConflict()
    if _conflictWarned or not QoL.HasNaowhQOL() then return end
    _conflictWarned = true
    NaowhUI.Print("|cffffcc00NaowhQOL is installed|r, so the NaowhUI QoL features it already provides "
        .. "(death release, co-tank frame, stealth reminder) are switched off here to "
        .. "avoid running them twice. Configure them in NaowhQOL, or disable NaowhQOL to use these.")
end

-- At login, not only on opening the page.
local conflictBoot = CreateFrame("Frame")
conflictBoot:RegisterEvent("PLAYER_LOGIN")
conflictBoot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    QoL.WarnConflict()
end)

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
-- One table per feature under SettingsRoot().qol, so the set switches and exports with EllesmereUI
-- profiles. Table defaults are COPIED: shared by reference, every profile would get the same one.
local function CopyDefault(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, inner in pairs(v) do out[k] = CopyDefault(inner) end
    return out
end

-- Cached per section: seeding walks every default key, and DB() sits under the display updates.
-- Keyed on the settings root, so a profile switch (which repoints it) drops the lot.
local dbCache, dbRoot = {}, nil

function QoL.DB(section, defaults)
    local root = NaowhUI.SettingsRoot()
    if root ~= dbRoot then
        wipe(dbCache)
        dbRoot = root
    end

    -- Verified against the live table too: a profile IMPORT replaces the inner table while the
    -- root stays put, and a stale handle would silently swallow writes.
    local all = root.qol
    local t = dbCache[section]
    if t and all and all[section] == t then return t end

    if type(all) ~= "table" then all = {}; root.qol = all end
    if type(all[section]) ~= "table" then all[section] = {} end
    t = all[section]
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = CopyDefault(v) end
    end

    dbCache[section] = t
    return t
end

-- Reset drops the table outright; the next DB() call rebuilds it from defaults.
function QoL.ClearDB(section)
    dbCache[section] = nil
    local root = NaowhUI.SettingsRoot()
    if type(root.qol) == "table" then root.qol[section] = nil end
end

-------------------------------------------------------------------------------
--  Refresh registry
-------------------------------------------------------------------------------
-- Options rows call Refresh(section) after a write and the feature redraws itself.
local refreshers = {}
function QoL.RegisterRefresh(section, fn)
    if type(section) ~= "string" or type(fn) ~= "function" then return end
    local list = refreshers[section]
    if not list then list = {}; refreshers[section] = list end
    list[#list + 1] = fn
end

function QoL.Refresh(section)
    local list = refreshers[section]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then NaowhUI.Print(("QoL refresh failed (%s): %s"):format(section, tostring(err))) end
    end
end

-------------------------------------------------------------------------------
--  Spec
-------------------------------------------------------------------------------
-- Cached: the stealth gates ask several times per update, and the answers change at most once per
-- spec change. Class never changes at all.
local _classFile, _specIndex, _specID

function QoL.ClassFile()
    if not _classFile then
        local _, classFile = UnitClass("player")
        _classFile = classFile or ""
    end
    return _classFile
end

-- 3.3.5 has talent trees, not specializations: the "spec" is the tree holding the most points
-- (EllesmereUI's compat exposes it as C_SpecializationInfo.GetSpecialization).
local function DominantTree()
    local get = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
    local idx = get and get()
    return tonumber(idx) or 0
end

function QoL.SpecIndex()
    if _specIndex then return _specIndex end
    local idx = DominantTree()
    -- 0 is "not known yet", which happens for a beat at login. Caching it would stick.
    if idx > 0 then
        -- No points spent at all reads as tree 1; keep asking until talents arrive.
        local _, _, points = GetTalentTabInfo(idx)
        if (tonumber(points) or 0) > 0 then _specIndex = idx end
    end
    return idx
end

-- "<CLASS>:<tree>" -- stable for the session and readable in the per-spec tables.
function QoL.SpecID()
    if _specID then return _specID end
    local idx = QoL.SpecIndex()
    if idx == 0 then return nil end
    local id = QoL.ClassFile() .. ":" .. idx
    if _specIndex then _specID = id end
    return id
end

local specCallbacks = {}
function QoL.OnSpecChanged(fn)
    if type(fn) == "function" then specCallbacks[#specCallbacks + 1] = fn end
end

-------------------------------------------------------------------------------
--  Zone
-------------------------------------------------------------------------------
-- GetInstanceInfo answers this directly, and instanceType is correct immediately on a zone-in
-- (unlike difficultyID, which lags).
function QoL.InDungeonOrRaid()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party" or instanceType == "raid"
end

local zoneCallbacks = {}
function QoL.OnZoneChanged(fn)
    if type(fn) == "function" then zoneCallbacks[#zoneCallbacks + 1] = fn end
end

local function Fire(list, label)
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then NaowhUI.Print(("QoL %s callback failed: %s"):format(label, tostring(err))) end
    end
end

-- 3.3.5: a dual-spec swap fires ACTIVE_TALENT_GROUP_CHANGED; spending or resetting points fires
-- PLAYER_TALENT_UPDATE / CHARACTER_POINTS_CHANGED. All of them can move the dominant tree.
local SPEC_EVENTS = {
    ACTIVE_TALENT_GROUP_CHANGED = true,
    PLAYER_TALENT_UPDATE        = true,
    CHARACTER_POINTS_CHANGED    = true,
}

local watcher = CreateFrame("Frame")
for e in pairs(SPEC_EVENTS) do watcher:RegisterEvent(e) end
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, event)
    if SPEC_EVENTS[event] then
        local before = _specIndex
        -- Dropped before the callbacks run: they ask for the spec, and the cache is now stale.
        _specIndex, _specID = nil, nil
        -- PLAYER_TALENT_UPDATE is chatty; only a moved tree is a spec change.
        if event ~= "ACTIVE_TALENT_GROUP_CHANGED" and before and QoL.SpecIndex() == before then return end
        Fire(specCallbacks, "spec")
    else
        Fire(zoneCallbacks, "zone")
    end
end)

-------------------------------------------------------------------------------
--  Fonts
-------------------------------------------------------------------------------
-- NaowhUI.FontPath never returns nil. The sentinel means "follow EllesmereUI's global font".
QoL.FONT_DEFAULT = NaowhUI.FONT_DEFAULT

function QoL.FontPath(name)
    return NaowhUI.FontPath(name)
end

function QoL.FontValues()
    return NaowhUI.BuildFontValues("Default (EllesmereUI)")
end

-------------------------------------------------------------------------------
--  Bar textures
-------------------------------------------------------------------------------
-- EllesmereUI's own catalogue plus every LibSharedMedia statusbar, so our picker offers the same
-- list the rest of the suite does. Built once, unlike the font and sound lists: EllesmereUI keeps
-- every registered table current through its own callback, and each build registers a consumer
-- against it that lasts the session.
local barTex, barNames, barOrder

local function BuildBarTextures()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.BuildBarTextureTables) then
        barTex, barNames, barOrder = {}, { none = "None" }, { "none" }
        return
    end
    barTex, barNames, barOrder = EUI.BuildBarTextureTables(true)
    if EUI.AppendSharedMediaTextures then
        pcall(EUI.AppendSharedMediaTextures, barNames, barOrder, nil, barTex)
    end
end

function QoL.BarTextureValues()
    if not barNames then BuildBarTextures() end
    return barNames, barOrder
end

-- Never nil. "none" carries no file by design, so it and an unresolvable key both flat-fill.
function QoL.BarTexturePath(key)
    if not barTex then BuildBarTextures() end
    return (key and barTex[key]) or [[Interface\Buttons\WHITE8X8]]
end

-------------------------------------------------------------------------------
--  Sounds
-------------------------------------------------------------------------------
-- Reusing EllesmereUI's runtime sound table keeps our picker on the same list and the same keys.
QoL.SOUND_NONE = "none"

-- EllesmereUI's sound tables live in EllesmereUIQoL and only get their LibSharedMedia entries from
-- that module's login handler, so with it disabled the list is bundled sounds or nothing. Seeded
-- from their table when present, so the keys match.
local sndPaths, sndNames, sndOrder

local function BuildSoundTables()
    sndPaths, sndNames, sndOrder = {}, { none = "None" }, { "none" }

    local EUI = _G.EllesmereUI
    if not EUI then return end
    -- The port builds the catalogue on demand rather than at QoL login.
    if EUI.GetAlertSoundCatalogue then pcall(EUI.GetAlertSoundCatalogue) end

    if type(EUI._groupDeathSoundPaths) == "table" then
        for k, v in pairs(EUI._groupDeathSoundPaths) do sndPaths[k] = v end
    end
    if type(EUI._groupDeathSoundNames) == "table" then
        for k, v in pairs(EUI._groupDeathSoundNames) do sndNames[k] = v end
    end
    if type(EUI._groupDeathSoundOrder) == "table" and #EUI._groupDeathSoundOrder > 0 then
        wipe(sndOrder)
        for _, k in ipairs(EUI._groupDeathSoundOrder) do sndOrder[#sndOrder + 1] = k end
    end

    if EUI.AppendSharedMediaSounds then
        pcall(EUI.AppendSharedMediaSounds, sndPaths, sndNames, sndOrder)
    end
end

-- Shared by both pickers below. `paths` is only read, never stored.
local function Decorate(names, order, paths)
    local EUI = _G.EllesmereUI
    -- Shallow copy: _menuOpts is ours to attach and must not land on EllesmereUI's shared table.
    local values = {}
    for k, v in pairs(names) do values[k] = v end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function(key)
            if key == QoL.SOUND_NONE or not paths[key] then return nil end
            return EUI and EUI.SOUND_ICON_ATLAS or "common-icon-sound"
        end,
        iconPressedAtlas = function(key)
            if key == QoL.SOUND_NONE or not paths[key] then return nil end
            return EUI and (EUI.SOUND_ICON_PRESSED_ATLAS or EUI.SOUND_ICON_ATLAS) or "common-icon-sound-pressed"
        end,
        -- An explicit preview click is the one place worth reporting a dud.
        iconOnClick = function(key)
            local ok, path = QoL.PlaySound(key, paths)
            if not ok then
                NaowhUI.Print(("|cffff6060that sound did not play|r -- %s. Its media addon may be "
                    .. "missing the file, or it is in a format the client will not load."):format(
                    path and ("|cffffffff" .. tostring(path) .. "|r") or "no file registered"))
            end
        end,
        iconTooltip = function() return "Preview Sound" end,
    }
    return values, order
end

-- For our own settings. Every LibSharedMedia sound, whether or not EllesmereUIQoL is enabled.
function QoL.SoundValues()
    BuildSoundTables()
    return Decorate(sndNames, sndOrder, sndPaths)
end

-- For PROXYING an EllesmereUI sound setting: the key we store is one THEY have to resolve, so
-- offering a sound their table lacks would save a setting that silently plays nothing.
function QoL.EUISoundValues()
    local EUI = _G.EllesmereUI
    if EUI and EUI.GetAlertSoundCatalogue then pcall(EUI.GetAlertSoundCatalogue) end
    local names = (EUI and type(EUI._groupDeathSoundNames) == "table") and EUI._groupDeathSoundNames or { none = "None" }
    local order = (EUI and type(EUI._groupDeathSoundOrder) == "table") and EUI._groupDeathSoundOrder or { "none" }
    local paths = (EUI and type(EUI._groupDeathSoundPaths) == "table") and EUI._groupDeathSoundPaths or {}
    return Decorate(names, order, paths)
end

-- Returns ok, path. 3.3.5's PlaySoundFile reports nothing, so a registered file that is missing
-- cannot be told apart from one that played; only a missing key reports false.
function QoL.PlaySound(key, paths)
    if not key or key == QoL.SOUND_NONE then return true end
    if not paths then
        if not sndPaths then BuildSoundTables() end
        paths = sndPaths
    end

    local path = paths and paths[key]
    if not path then return false, nil end

    if type(path) == "number" then
        if path ~= 1 then pcall(PlaySound, path, "Master") end
        return true, path
    end

    local ok = pcall(PlaySoundFile, path, "Master")
    if not ok then
        pcall(PlaySound, "RaidWarning")
        return false, path
    end
    return true, path
end

-------------------------------------------------------------------------------
--  Colours
-------------------------------------------------------------------------------
function QoL.PlayerClassColor()
    local color = RAID_CLASS_COLORS[QoL.ClassFile()]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

-- Resolves a stored r/g/b triple against its "use class colour" companion flag.
function QoL.EffectiveColor(db, rKey, gKey, bKey, classColorKey)
    if classColorKey and db[classColorKey] then return QoL.PlayerClassColor() end
    return db[rKey] or 1, db[gKey] or 1, db[bKey] or 1
end

-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
-- EllesmereUI has one Unlock Mode for the whole suite and takes registrations from any addon --
-- `folder` only attributes layout exports, it gates nothing. Position stays in OUR settings table.
local movers = {}

-- spec: key, label, order, db (fn), getFrame, apply, pointKey/xKey/yKey/relKey, isHidden,
-- and widthKey/heightKey/minW/minH -- omit the width pair for a fixed-size element.
function QoL.RegisterMover(spec)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.MakeUnlockElement and EUI.RegisterUnlockElements) then return end
    if movers[spec.key] then return end
    movers[spec.key] = spec

    local resizable = spec.widthKey and spec.heightKey
    local function DB() return spec.db() end

    local elem = {
        key      = spec.key,
        label    = spec.label,
        group    = "NaowhUI",
        order    = spec.order,
        getFrame = spec.getFrame,
        isHidden = spec.isHidden,
        noResize = not resizable,

        getSize = function()
            local f = spec.getFrame()
            if f then return f:GetWidth(), f:GetHeight() end
            local t = DB()
            return (resizable and t[spec.widthKey]) or 200, (resizable and t[spec.heightKey]) or 40
        end,

        -- Written into our own settings table, so a drag survives a profile export like a slider.
        savePos = function(_, point, relPoint, x, y)
            if not point then return end
            local t = DB()
            t[spec.pointKey] = point
            if spec.relKey then t[spec.relKey] = relPoint end
            t[spec.xKey] = math.floor((x or 0) + 0.5)
            t[spec.yKey] = math.floor((y or 0) + 0.5)
        end,

        loadPos = function()
            local t = DB()
            if not t[spec.pointKey] then return nil end
            return {
                point    = t[spec.pointKey],
                relPoint = (spec.relKey and t[spec.relKey]) or t[spec.pointKey],
                x        = t[spec.xKey] or 0,
                y        = t[spec.yKey] or 0,
            }
        end,

        clearPos = function()
            local t = DB()
            t[spec.pointKey], t[spec.xKey], t[spec.yKey] = nil, nil, nil
            if spec.relKey then t[spec.relKey] = nil end
            if spec.apply then spec.apply() end
        end,

        applyPos = spec.apply,
    }

    if resizable then
        elem.setWidth = function(_, w)
            DB()[spec.widthKey] = math.max(spec.minW or 60, math.floor(w + 0.5))
            if spec.apply then spec.apply() end
        end
        elem.setHeight = function(_, h)
            DB()[spec.heightKey] = math.max(spec.minH or 20, math.floor(h + 0.5))
            if spec.apply then spec.apply() end
        end
    end

    EUI:RegisterUnlockElements({ EUI.MakeUnlockElement(elem) }, NaowhUI.MODULE_KEY)
end

-- Uninstall only: a mover for a frame that will never exist again is a dead entry.
function QoL.UnregisterMovers()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.UnregisterUnlockElement) then return end
    for key in pairs(movers) do pcall(EUI.UnregisterUnlockElement, EUI, key) end
    wipe(movers)
end

-- Frames must show regardless of their gating while positioning; a co-tank bar is raid-only.
local unlockWatchers = {}
QoL.unlockActive = false

function QoL.OnUnlockModeChanged(fn)
    if type(fn) == "function" then unlockWatchers[#unlockWatchers + 1] = fn end
end

do
    local EUI = _G.EllesmereUI
    if EUI and EUI.RegisterUnlockModeListener then
        EUI:RegisterUnlockModeListener("NaowhUI_QoL", function(active)
            QoL.unlockActive = active and true or false
            for i = 1, #unlockWatchers do
                local ok, err = pcall(unlockWatchers[i], QoL.unlockActive)
                if not ok then NaowhUI.Print("unlock callback failed: " .. tostring(err)) end
            end
        end)
    end
end

