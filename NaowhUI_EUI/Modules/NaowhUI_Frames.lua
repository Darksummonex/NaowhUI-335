-------------------------------------------------------------------------------
--  NaowhUI_Frames.lua ("Frames") -- dark mode, class-coloured names, background, combat indicator.
--  Every write into EllesmereUI is snapshotted and reversible.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
local DEFAULTS = {
    darkAll           = false,
    darkDM            = false,
    lightBg           = false,
    classNamesRaid    = false,
    classNamesUnit    = false,
    combatArcadeWhite = false,
}

local function FDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.frames) ~= "table" then root.frames = {} end
    local t = root.frames
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

local function UfSnap()     return NaowhUI.Snap("frames", "uf")     end  -- "unit|slot" -> *ClassColor
local function RfSnap()     return NaowhUI.Snap("frames", "rf")     end  -- nameColorMode + previewMode
local function DmSnap()     return NaowhUI.Snap("frames", "dm")     end  -- Damage Meters keys
local function DmFreeSnap() return NaowhUI.Snap("frames", "dmFree") end  -- DM keys handed back
local function BgSnap()     return NaowhUI.Snap("frames", "bg")     end  -- dark-mode palette bg*
local function DarkSnap()   return NaowhUI.Snap("frames", "dark")   end  -- providerId -> prior on/off
-- The combat-indicator snaps are per unit and named in COMBAT_UNITS ("combat", "combatTarget").

local function Profile(folder)
    return NaowhUI.GetProfile and NaowhUI.GetProfile(folder) or nil
end

-------------------------------------------------------------------------------
--  Non-destructive override helpers
-------------------------------------------------------------------------------
local ABSENT = NaowhUI.ABSENT

-- Returns true only if the value actually moved, so callers can skip EllesmereUI's refreshes.
local function Override(t, saved, k, v)
    if saved[k] == nil then
        if t[k] == nil then saved[k] = ABSENT else saved[k] = t[k] end
    end
    if t[k] == v then return false end
    t[k] = v
    return true
end

-- Not `(prev == ABSENT) and nil or prev`: that collapses to `prev` and writes the marker string
-- back into the table.
local function Restore(t, saved, k)
    local prev = saved[k]
    if prev == nil then return false end
    saved[k] = nil
    if prev == ABSENT then
        if t[k] == nil then return false end
        t[k] = nil
    else
        if t[k] == prev then return false end
        t[k] = prev
    end
    return true
end

-------------------------------------------------------------------------------
--  Raid-frame preview suppression
-------------------------------------------------------------------------------
-- The raid preview is only torn down when the options window closes, so it follows you onto every
-- page and masks the real frames. ns.HidePreview is private, so previewMode is pinned instead.
local function SuppressRaidPreview()
    if not (NaowhUI.IsApplied and NaowhUI.IsApplied()) then return end
    local prof = Profile("EllesmereUIRaidFrames")
    if not prof then return end
    local saved = RfSnap()
    if saved.previewMode == nil then saved.previewMode = prof.previewMode or "overlay" end
    prof.previewMode = "none"
end

local function RestoreRaidPreview()
    local saved = NaowhUI.PeekSnap("frames", "rf")
    if not (saved and saved.previewMode ~= nil) then return end
    local prof = Profile("EllesmereUIRaidFrames")
    if prof then prof.previewMode = saved.previewMode end
    saved.previewMode = nil
end

-------------------------------------------------------------------------------
--  Dark Mode
-------------------------------------------------------------------------------
-- 3.3.5: the damage meter keeps its look per window (profile.windows[i]), with colours as
-- {r,g,b[,a]} tables and the background opacity in `alpha`. "thin-line-bottom" is one of its
-- barTexture keys.
local DM_DARK_VALUES = {
    bgColor     = { r = 0, g = 0, b = 0 },
    alpha       = 0,
    barBgColor  = { r = 0, g = 0, b = 0, a = 0.7 },
    borderSize  = 0,
    barTexture  = "thin-line-bottom",
}

local function Same(a, b)
    if type(a) == "table" and type(b) == "table" then
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
    end
    return a == b
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = x end
    return c
end

-- Table-aware twins of Override/Restore for the meter's colour tables.
local function OverrideDM(t, saved, id, k, v)
    if saved[id] == nil then
        if t[k] == nil then saved[id] = ABSENT else saved[id] = Copy(t[k]) end
    end
    if Same(t[k], v) then return false end
    t[k] = Copy(v)
    return true
end

local function RestoreDM(t, saved, id, k)
    local prev = saved[id]
    if prev == nil then return false end
    saved[id] = nil
    if prev == ABSENT then prev = nil end
    if Same(t[k], prev) then return false end
    t[k] = Copy(prev)
    return true
end

-- The refresh rebuilds every meter window, hence the check for a real change. On the reassert pass
-- a value that no longer matches ours is the user's own edit, so our claim on that key is dropped.
-- The drop is recorded, or the next pass reads the key as unclaimed and re-forces the dark value.
-- Snapshot ids are "<window index>|<key>".
local function ApplyDMDark(on, reassert)
    local windows = NaowhUI.DMWindows and NaowhUI.DMWindows()
    if not windows then return end
    local saved = DmSnap()
    local freed = NaowhUI.PeekSnap("frames", "dmFree")
    local changed = false
    -- Only the reassert pass carries the drops forward; an explicit toggle re-claims the lot.
    if not reassert and freed then wipe(freed) end
    for i, w in ipairs(windows) do
        if type(w) == "table" then
            for k, v in pairs(DM_DARK_VALUES) do
                local id = i .. "|" .. k
                if on then
                    if reassert and ((freed and freed[id]) or (saved[id] ~= nil and not Same(w[k], v))) then
                        freed = freed or DmFreeSnap()
                        freed[id], saved[id] = true, nil
                    elseif OverrideDM(w, saved, id, k, v) then
                        changed = true
                    end
                elseif RestoreDM(w, saved, id, k) then
                    changed = true
                end
            end
        end
    end
    if changed then NaowhUI.RefreshDamageMeter() end
end

-- Unit frames are a registered EllesmereUI dark-mode provider; the 3.3.5 raid frames are not, but
-- they have a "dark" health colour mode per group (raid / party) that reads the same palette.
local providerFilters = {}
local function ProviderFilter(id)
    local f = providerFilters[id]
    if not f then
        f = function(p) return p.id == id end
        providerFilters[id] = f
    end
    return f
end

local RF_GROUPS = { "raid", "party" }

local function RaidFramesDarkOn()
    local prof = Profile("EllesmereUIRaidFrames")
    if not prof then return false end
    local any = false
    for _, g in ipairs(RF_GROUPS) do
        local c = prof[g]
        if type(c) == "table" then
            if c.healthColorMode ~= "dark" then return false end
            any = true
        end
    end
    return any
end

-- The mode each group had before dark is parked in the "dark" snapshot as rfPrev.
local function SetRaidFramesDark(on)
    local prof = Profile("EllesmereUIRaidFrames")
    if not prof then return end
    local saved = DarkSnap()
    if type(saved.rfPrev) ~= "table" then saved.rfPrev = {} end
    local prev = saved.rfPrev
    local changed = false
    for _, g in ipairs(RF_GROUPS) do
        local c = prof[g]
        if type(c) == "table" then
            if on and c.healthColorMode ~= "dark" then
                if c.healthColorMode == nil then prev[g] = ABSENT else prev[g] = c.healthColorMode end
                c.healthColorMode = "dark"
                changed = true
            elseif not on and c.healthColorMode == "dark" then
                local p = prev[g]
                c.healthColorMode = (p and p ~= ABSENT and p ~= "dark") and p or "class"
                prev[g] = nil
                changed = true
            end
        end
    end
    if not next(prev) then saved.rfPrev = nil end
    if changed and _G._ERF_RefreshAll then pcall(_G._ERF_RefreshAll) end
end

function NaowhUI.IsDarkModeOn(id)
    if id == "raidFrames" then return RaidFramesDarkOn() end
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.IsDarkModeAllOn) then return false end
    return EUI.IsDarkModeAllOn(ProviderFilter(id)) and true or false
end

function NaowhUI.SetDarkMode(id, on)
    if id == "raidFrames" then
        SetRaidFramesDark(on)
        local EUI = _G.EllesmereUI
        if EUI and EUI.RefreshDarkMode then pcall(EUI.RefreshDarkMode) end
        return
    end
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.SetDarkModeAll) then return end
    EUI.SetDarkModeAll(on and true or false, ProviderFilter(id))
end

-- Each provider is snapshotted and handed back, so dark mode the user already had survives.
function NaowhUI.ApplyDarkModeAll(on)
    local saved = DarkSnap()
    if on then
        for _, id in ipairs(NaowhUI.DARK_IDS) do
            if saved[id] == nil then saved[id] = NaowhUI.IsDarkModeOn(id) end
            NaowhUI.SetDarkMode(id, true)
        end
    else
        for _, id in ipairs(NaowhUI.DARK_IDS) do
            if saved[id] ~= nil then NaowhUI.SetDarkMode(id, saved[id] == true) end
            saved[id] = nil
        end
    end
    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end

-------------------------------------------------------------------------------
--  Lighter background
-------------------------------------------------------------------------------
-- Unit and raid frames don't own background colours: in dark mode both read one shared palette,
-- so a single write plus RefreshDarkMode reaches every frame.
local LIGHT_GREY = { bgR = 0xa2/255, bgG = 0xa2/255, bgB = 0xa2/255 }

local function ApplyLightBackground(on)
    local EUI = _G.EllesmereUI
    local d = EUI and EUI.GetDarkModeDB and EUI.GetDarkModeDB()
    if not d then return end
    local saved = BgSnap()
    local changed = false

    if on then
        for k, v in pairs(LIGHT_GREY) do
            if Override(d, saved, k, v) then changed = true end
        end
    else
        for k in pairs(LIGHT_GREY) do
            if Restore(d, saved, k) then changed = true end
        end
    end
    if changed and EUI.RefreshDarkMode then EUI.RefreshDarkMode() end
end

local UF_SLOTS = NaowhUI.UF_SLOTS
local UF_UNITS = NaowhUI.UF_UNITS

-------------------------------------------------------------------------------
--  Class-coloured names
-------------------------------------------------------------------------------
-- Colour whichever slot is showing the name, not a hardcoded slot per unit: layouts move the name
-- around, so a fixed map colours the wrong text.
local function ApplyUnitFrameNames(on)
    local prof = Profile("EllesmereUIUnitFrames")
    if not prof then return end

    -- Peek on the off path: Snap() would seed a record for users who never turned it on.
    local saved = on and UfSnap() or NaowhUI.PeekSnap("frames", "uf")
    if not saved then return end
    local changed = false

    local function SetCC(u, ccKey, want)
        if (u[ccKey] and true or false) == want then return end
        u[ccKey] = want
        changed = true
    end
    local function RestoreCC(u, ccKey, prev)
        if prev == ABSENT then
            if u[ccKey] ~= nil then u[ccKey] = nil; changed = true end
        else
            SetCC(u, ccKey, prev and true or false)
        end
    end

    for _, unitKey in ipairs(UF_UNITS) do
        local u = prof[unitKey]
        if type(u) == "table" then
            for _, slot in ipairs(UF_SLOTS) do
                if u[slot .. "Content"] == "name" then
                    local ccKey = slot .. "ClassColor"
                    local id    = unitKey .. "|" .. slot
                    if on then
                        if saved[id] == nil then
                            if u[ccKey] == nil then saved[id] = ABSENT else saved[id] = u[ccKey] and true or false end
                        end
                        SetCC(u, ccKey, true)
                    elseif saved[id] ~= nil then
                        RestoreCC(u, ccKey, saved[id])
                        saved[id] = nil
                    end
                end
            end
        end
    end

    -- A slot we coloured that no longer shows the name would stay class-coloured with nothing
    -- left to undo it.
    for id, prev in pairs(saved) do
        local unitKey, slot = id:match("^(.-)|(.+)$")
        local u = unitKey and prof[unitKey]
        if type(u) == "table" and u[slot .. "Content"] ~= "name" then
            RestoreCC(u, slot .. "ClassColor", prev)
            saved[id] = nil
        end
    end

    if changed and _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
end

-- 3.3.5: nameColorMode lives in each group's config (profile.raid / profile.party).
local function ApplyRaidFrameNames(on)
    local prof = Profile("EllesmereUIRaidFrames")
    if not prof then return end
    local raid, party = prof.raid, prof.party
    local want, partyWant
    if on then
        local saved = RfSnap()
        if saved.mode == nil and type(raid) == "table" then saved.mode = raid.nameColorMode or "class" end
        if saved.partyMode == nil and type(party) == "table" then saved.partyMode = party.nameColorMode or "class" end
        want = "class"
        partyWant = "class"
    else
        local saved = NaowhUI.PeekSnap("frames", "rf")
        if not (saved and (saved.mode ~= nil or saved.partyMode ~= nil)) then return end
        want = saved.mode
        partyWant = saved.partyMode
        saved.mode = nil
        saved.partyMode = nil
    end

    local changed = false
    if want ~= nil and type(raid) == "table" and raid.nameColorMode ~= want then
        raid.nameColorMode = want
        changed = true
    end
    if partyWant ~= nil and type(party) == "table" and party.nameColorMode ~= partyWant then
        party.nameColorMode = partyWant
        changed = true
    end
    if changed and _G._ERF_RefreshAll then pcall(_G._ERF_RefreshAll) end
end

function NaowhUI.ApplyClassColorNames()
    local t = FDB()
    ApplyRaidFrameNames(t.classNamesRaid)
    ApplyUnitFrameNames(t.classNamesUnit)
    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end

-------------------------------------------------------------------------------
--  Combat indicator (player + target -- the only units EllesmereUI supports it on)
-------------------------------------------------------------------------------
-- combat0 is EllesmereUI's "Arcade" icon. It draws combat0..5 as-is and disables their colour
-- controls, so a white one has to be our own art.
local COMBAT_ARCADE = "combat0"
local ARCADE_WHITE  = "Interface\\AddOns\\NaowhUI_EUI\\media\\combat-arcade-white.tga"

-- "combat" predates target support and holds player-only data in existing SavedVariables, so the
-- target gets its own snapshot name. KEEP IN STEP with the Uninstall and SpecOverrides maps.
local COMBAT_UNITS = {
    { unit = "player", frame = "EllesmereUIUnitFrames_Player", snap = "combat" },
    { unit = "target", frame = "EllesmereUIUnitFrames_Target", snap = "combatTarget" },
}

-- Hook the TEXTURE, not pf._applyCombatTexture: the texture is reused while that function is
-- reassigned on every rebuild, and SetVertexColor is its last call on every path. Tracked per unit:
-- the target frame may not exist, and one flag would block the target's hook forever.
local _combatHooked = {}
local function HookCombatIndicators()
    for _, def in ipairs(COMBAT_UNITS) do
        if not _combatHooked[def.unit] then
            local pf = _G[def.frame]
            local tex = pf and pf._combatIndicator
            if tex then
                _combatHooked[def.unit] = true
                hooksecurefunc(tex, "SetVertexColor", function(self)
                    if not FDB().combatArcadeWhite then return end
                    -- SetTexture does not re-enter SetVertexColor, so this cannot loop.
                    self:SetTexture(ARCADE_WHITE)
                    self:SetTexCoord(0, 1, 0, 1)
                    self:SetDesaturated(false)
                end)
            end
        end
    end
end

local function ApplyCombatIndicator(on)
    HookCombatIndicators()

    local prof = Profile("EllesmereUIUnitFrames")
    if not prof then return end

    local changed = false
    for _, def in ipairs(COMBAT_UNITS) do
        local u = prof[def.unit]
        if type(u) == "table" then
            local saved = on and NaowhUI.Snap("frames", def.snap)
                             or NaowhUI.PeekSnap("frames", def.snap)
            if saved then
                if on then
                    if Override(u, saved, "combatIndicatorStyle", COMBAT_ARCADE) then changed = true end
                else
                    if Restore(u, saved, "combatIndicatorStyle") then changed = true end
                end
            end
        end
    end

    -- Without a rebuild the textures still need repainting for the desaturation to land or lift.
    if changed and _G._EUF_ReloadFrames then
        _G._EUF_ReloadFrames()
    else
        for _, def in ipairs(COMBAT_UNITS) do
            local pf = _G[def.frame]
            if pf and pf._applyCombatTexture then pf._applyCombatTexture() end
        end
    end

    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
function NaowhUI.BuildFramesOptions(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    _, h = W:SectionHeader(parent, "DARK MODE", y); y = y - h

    -- ON via this toggle, or by setting all three scopes below (hence `or darkAll`).
    _, h = W:Toggle(parent, "Dark Mode (Frames + Damage Meters)", y,
        function()
            local euiOn = NaowhUI.IsDarkModeOn("unitFrames") and NaowhUI.IsDarkModeOn("raidFrames")
            return ((euiOn and FDB().darkDM) or FDB().darkAll) and true or false
        end,
        function(v)
            FDB().darkAll = v
            FDB().darkDM  = v            -- the damage meter rides the master too
            NaowhUI.ApplyDarkModeAll(v)
            ApplyDMDark(v)
            EUI:RefreshPage()   -- the scope toggles are views over the same state
        end,
        "Gives the unit frames, raid frames and damage meter a dark look. Turn off to restore your previous colours.")
    y = y - h

    -- Pure views over EllesmereUI's providers, so they cannot desync from the master toggle.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Raid Frames Only",
          tooltip = "Dark look for just the raid and party frames.",
          getValue = function() return NaowhUI.IsDarkModeOn("raidFrames") end,
          setValue = function(v) NaowhUI.SetDarkMode("raidFrames", v); EUI:RefreshPage() end },
        { type = "toggle", text = "Unit Frames Only",
          tooltip = "Dark look for just the unit frames.",
          getValue = function() return NaowhUI.IsDarkModeOn("unitFrames") end,
          setValue = function(v) NaowhUI.SetDarkMode("unitFrames", v); EUI:RefreshPage() end }
    ); y = y - h

    -- The master's damage-meter scope. Not a dark-mode provider, so it holds its own darkDM state.
    _, h = W:Toggle(parent, "Damage Meter", y,
        function() return FDB().darkDM end,
        function(v)
            FDB().darkDM = v
            ApplyDMDark(v)
            if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
        end,
        "Dark look for just the EllesmereUI damage meter windows.")
    y = y - h

    _, h = W:SectionHeader(parent, "CLASS-COLOURED NAMES", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Raid Frame Names",
          tooltip = "Colours the names on the raid and party frames by class.",
          getValue = function() return FDB().classNamesRaid end,
          setValue = function(v) FDB().classNamesRaid = v; NaowhUI.ApplyClassColorNames() end },
        { type = "toggle", text = "Unit Frame Names",
          tooltip = "Colours the names on the unit frames by class.",
          getValue = function() return FDB().classNamesUnit end,
          setValue = function(v) FDB().classNamesUnit = v; NaowhUI.ApplyClassColorNames() end }
    ); y = y - h

    _, h = W:SectionHeader(parent, "BACKGROUND", y); y = y - h

    _, h = W:Toggle(parent, "Lighter Background", y,
        function() return FDB().lightBg end,
        function(v) FDB().lightBg = v; ApplyLightBackground(v) end,
        "Brightens the Dark Mode background to a light grey on every frame.")
    y = y - h

    _, h = W:SectionHeader(parent, "COMBAT INDICATOR", y); y = y - h

    _, h = W:Toggle(parent, "Arcade Combat Icon (White)", y,
        function() return FDB().combatArcadeWhite end,
        function(v) FDB().combatArcadeWhite = v; ApplyCombatIndicator(v) end,
        "Shows white crossed swords on the player and target frames while they are in combat. Turn off to restore your previous indicator.")
    y = y - h

    return math.abs(y)
end

-- Only the preview pin: dark mode and class colours stay the user's choice.
if NaowhUI.RegisterPreset then
    NaowhUI.RegisterPreset(SuppressRaidPreview)
end

-- Also the re-apply hook: on a switch this snapshots the new profile's originals, then overwrites.
local function ReassertFrames()
    local t = FDB()
    if t.darkAll then NaowhUI.ApplyDarkModeAll(true) end
    if t.darkDM  then ApplyDMDark(true, true) end
    if t.lightBg then ApplyLightBackground(true) end
    NaowhUI.ApplyClassColorNames()
    ApplyCombatIndicator(t.combatArcadeWhite)   -- installs the texture hooks too
    SuppressRaidPreview()
end

if NaowhUI.RegisterReapply then
    NaowhUI.RegisterReapply(ReassertFrames)
end

-- Every revert reads its snapshot, so they all run before the table is wiped.
function NaowhUI.ResetFrames()
    local t = FDB()
    ApplyRaidFrameNames(false)
    ApplyUnitFrameNames(false)
    if t.darkAll then NaowhUI.ApplyDarkModeAll(false) end
    if t.darkDM  then ApplyDMDark(false) end
    if t.lightBg then ApplyLightBackground(false) end
    t.combatArcadeWhite = false   -- the texture hooks read this; clear it before the repaint
    ApplyCombatIndicator(false)
    RestoreRaidPreview()
    NaowhUI.SettingsRoot().frames = nil
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(1, function()
        ReassertFrames()

        -- Re-pin the preview on each panel open, so a runtime write can't bring it back.
        local EUI = _G.EllesmereUI
        if EUI and EUI.RegisterOnShow then EUI:RegisterOnShow(SuppressRaidPreview) end
    end)
end)
