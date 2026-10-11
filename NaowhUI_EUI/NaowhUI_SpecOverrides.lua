-------------------------------------------------------------------------------
--  NaowhUI_SpecOverrides.lua -- makes a NaowhUI setting hold on EVERY spec. An override swaps its
--  stored value into the live profile on each spec change, so ours is banked into its maps instead:
--  WriteSpecValues then finds live equal and does nothing.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

local ABSENT = NaowhUI.ABSENT

-- EllesmereUI's encoding: fkey is folder .. FS .. path, segments joined by PS. NIL_SENT is its
-- "key not present" marker -- a nil would instead mean "fall back to default".
local FS, PS   = "\31", "\30"
local NIL_SENT = "__SPECOV_NIL__"

-------------------------------------------------------------------------------
--  fkeys
-------------------------------------------------------------------------------
local function FKey(folder, ...)
    return folder .. FS .. table.concat({ ... }, PS)
end

-- The second return separates "key is absent" from "path isn't there at all"; only the first may
-- be banked as NIL_SENT.
local function ReadLive(fkey)
    local folder, path = fkey:match("^([^\31]+)\31(.*)$")
    local t = folder and NaowhUI.GetProfile(folder)
    if type(t) ~= "table" then return nil, false end

    local segs = { strsplit(PS, path) }
    for i = 1, #segs - 1 do
        t = t[segs[i]]
        if type(t) ~= "table" then return nil, false end
    end
    return t[segs[#segs]], true
end

-------------------------------------------------------------------------------
--  What we are currently forcing
-------------------------------------------------------------------------------
-- A module snapshot exists exactly while its override is in force, so the snapshots ARE the list
-- of what we hold down. KEEP IN STEP WITH THE MODULES.
--
-- Absent on purpose: the CDM (EllesmereUI blacklists it from Spec Overrides), frames/bg (the
-- dark-mode palette is on the profile root, not an addon blob, so no fkey reaches it) and
-- frames/dmFree, which is the keys we have STOPPED forcing.
-- 3.3.5: the damage meter keeps its look per window in an array, which an fkey path cannot
-- index, so meter keys are never banked.
local UF_ICON_KEYS = { "buffCropIcons", "debuffCropIcons", "buffIconZoom", "debuffIconZoom" }

local FORCED = {
    root = {
        accent = function(saved, add)
            for _, m in ipairs(NaowhUI.ACCENT_OPTOUT) do
                for _, key in ipairs(m.keys) do
                    if saved[m.folder .. "." .. key] ~= nil then add(m.folder, key) end
                end
            end
        end,
    },

    icons = {
        uf = function(saved, add)
            for unit in pairs(saved) do
                for _, k in ipairs(UF_ICON_KEYS) do add("EllesmereUIUnitFrames", unit, k) end
            end
        end,
    },

    frames = {
        uf = function(saved, add)
            for id in pairs(saved) do
                local unit, slot = id:match("^(.-)|(.+)$")
                if unit then add("EllesmereUIUnitFrames", unit, slot .. "ClassColor") end
            end
        end,
        rf = function(saved, add)
            if saved.mode ~= nil        then add("EllesmereUIRaidFrames", "raid", "nameColorMode") end
            if saved.partyMode ~= nil   then add("EllesmereUIRaidFrames", "party", "nameColorMode") end
            if saved.previewMode ~= nil then add("EllesmereUIRaidFrames", "previewMode") end
        end,
        dark = function(saved, add)
            if saved.unitFrames ~= nil then add("EllesmereUIUnitFrames", "darkTheme") end
            if saved.raidFrames ~= nil then
                add("EllesmereUIRaidFrames", "raid", "healthColorMode")
                add("EllesmereUIRaidFrames", "party", "healthColorMode")
            end
        end,
        combat = function(saved, add)
            for k in pairs(saved) do add("EllesmereUIUnitFrames", "player", k) end
        end,
        combatTarget = function(saved, add)
            for k in pairs(saved) do add("EllesmereUIUnitFrames", "target", k) end
        end,
    },

    cdm = {
        ab = function(saved, add)
            for key in pairs(saved) do add("EllesmereUIActionBars", "bars", key, "hideKeybind") end
        end,
        -- visibilityModes is a table, which Bank leaves alone; barVisibility carries the mode.
        vis = function(saved, add)
            for key in pairs(saved) do add("EllesmereUIActionBars", "bars", key, "barVisibility") end
        end,
    },

    nameplates = {
        euiArrows = function(saved, add)
            if saved.prev ~= nil then add("EllesmereUINameplates", "showTargetArrows") end
        end,
    },

    topBar = {
        euiFps = function(saved, add)
            if saved.prev ~= nil then add("EllesmereUIQoL", "fps") end
        end,
    },
}

local function ForcedFKeys()
    local out = {}
    local function add(folder, ...) out[FKey(folder, ...)] = true end

    for section, byName in pairs(FORCED) do
        for name, collect in pairs(byName) do
            local saved = NaowhUI.PeekSnap(section, name)
            if saved and next(saved) then pcall(collect, saved, add) end
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  The store
-------------------------------------------------------------------------------
local function Store(profileName)
    local root = NaowhUI.ProfileRoot(profileName)
    local s = root and root.specOverrides
    return type(s) == "table" and s or nil
end

-- entry.values is `default` plus one map per spec. default doubles as the fkey index, so nothing
-- below removes its keys -- only their values are swapped.
local function MapSnap() return NaowhUI.Snap("specov", "maps") end

-- Snapshot every map's prior value once, then put ours in all of them.
local function Bank(values, fkey, saved)
    local v, reachable = ReadLive(fkey)
    if not reachable or type(v) == "table" then return end   -- unreadable or structural: leave it

    if saved[fkey] == nil then
        local rec = {}
        for mapKey, map in pairs(values) do
            if type(map) == "table" then
                local prev = map[fkey]
                if prev == nil then rec[mapKey] = ABSENT else rec[mapKey] = prev end
            end
        end
        saved[fkey] = rec
    end

    if v == nil then v = NIL_SENT end
    for _, map in pairs(values) do
        if type(map) == "table" then map[fkey] = v end
    end
end

-- Put the user's per-spec values back and forget the snapshot.
local function HandBack(values, fkey, saved)
    local rec = saved[fkey]
    if type(rec) == "table" then
        for mapKey, map in pairs(values) do
            if type(map) == "table" then
                -- No record: a Harvest built this map while we were forcing, so it never held
                -- theirs. Drop the key and let it fall back to the restored default.
                local prev = rec[mapKey]
                if prev == nil or prev == ABSENT then map[fkey] = nil else map[fkey] = prev end
            end
        end
    end
    saved[fkey] = nil
end

local function ForEachEntry(store, fn)
    for i = #store, 1, -1 do
        local entry   = store[i]
        local values  = type(entry) == "table" and entry.values
        local default = type(values) == "table" and values.default
        if type(default) == "table" then fn(i, values, default) end
    end
end

-------------------------------------------------------------------------------
--  Sync
-------------------------------------------------------------------------------
-- Bank what we force, hand back what we no longer do. Only captured settings are visited.
function NaowhUI.SyncSpecOverrides()
    if NaowhUI.IsUninstalled and NaowhUI.IsUninstalled() then return end
    local store = Store(NaowhUI.ActiveProfile())
    if not store then return end

    local forced = ForcedFKeys()
    local saved  = NaowhUI.PeekSnap("specov", "maps")

    ForEachEntry(store, function(_, values, default)
        for fkey in pairs(default) do
            if forced[fkey] then
                saved = saved or MapSnap()   -- built on the first bank, not on being looked at
                Bank(values, fkey, saved)
            elseif saved and saved[fkey] ~= nil then
                HandBack(values, fkey, saved)
            end
        end
    end)
end

-- Debounced: one options toggle can drive several module writes.
local _queued = false
function NaowhUI.QueueSpecSync()
    if _queued then return end
    _queued = true
    C_Timer.After(0, function()
        _queued = false
        NaowhUI.SyncSpecOverrides()
    end)
end

-------------------------------------------------------------------------------
--  Reset / Uninstall
-------------------------------------------------------------------------------
-- Hand back every map we ever banked, whether or not we still force it.
function NaowhUI.RestoreSpecOverrides(profileName)
    profileName = profileName or NaowhUI.ActiveProfile()
    local saved = NaowhUI.PeekSnap("specov", "maps", profileName)
    if not saved or not next(saved) then return 0 end

    local store = Store(profileName)
    local n = 0
    if store then
        ForEachEntry(store, function(_, values, default)
            for fkey in pairs(default) do
                if saved[fkey] ~= nil then
                    HandBack(values, fkey, saved)
                    n = n + 1
                end
            end
        end)
    end

    wipe(saved)   -- anything left was banked against a row the user has since removed
    return n
end

-- Uninstall only: a capture of OUR settings becomes a dead row pointing at a folder that will
-- never load again.
function NaowhUI.DropOwnSpecOverrides(profileName)
    local store = Store(profileName)
    if not store then return 0 end

    local prefix, n = NaowhUI.MODULE_KEY .. FS, 0
    ForEachEntry(store, function(i, values, default)
        for fkey in pairs(default) do
            if fkey:sub(1, #prefix) == prefix then
                for _, map in pairs(values) do
                    if type(map) == "table" then map[fkey] = nil end
                end
                n = n + 1
            end
        end
        if not next(default) then table.remove(store, i) end
    end)

    if #store == 0 then
        local root = NaowhUI.ProfileRoot(profileName)
        if root then root.specOverrides = nil end
    end
    return n
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        -- EllesmereUI is our dependency, so it registered first and its logout Harvest has already
        -- run. This settles the maps that Harvest does not reach.
        if not (NaowhUI.IsUninstalled and NaowhUI.IsUninstalled()) then
            pcall(NaowhUI.SyncSpecOverrides)
        end
        return
    end

    self:UnregisterEvent("PLAYER_LOGIN")

    local EUI = _G.EllesmereUI
    if EUI and EUI.SpecOverrides_OnSpecChanged then
        -- Fires after the outgoing spec is harvested and BEFORE the incoming spec's values are
        -- written, which is the one window where banking ours makes WriteSpecValues a no-op.
        hooksecurefunc(EUI, "SpecOverrides_OnSpecChanged", function()
            NaowhUI.SyncSpecOverrides()
        end)
    end

    C_Timer.After(1.5, NaowhUI.SyncSpecOverrides)   -- once every module has applied
end)
