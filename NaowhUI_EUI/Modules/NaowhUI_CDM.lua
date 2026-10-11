-------------------------------------------------------------------------------
--  NaowhUI_CDM.lua ("Gameplay") -- Beginner Mode + hide-tooltips-in-combat.
--  Every write is snapshotted in NaowhUIEUIDB and restored on toggle-off.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

local AB_KEYS = { "bar1", "bar2" }

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
local DEFAULTS = { beginnerMode = false }

local function CDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.cdm) ~= "table" then root.cdm = {} end
    local t = root.cdm
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

local function KbSnap()     return NaowhUI.Snap("cdm", "kb")     end  -- barKey -> showKeybind
local function TipSnap()    return NaowhUI.Snap("cdm", "tip")    end  -- barKey -> showTooltip
local function MirrorSnap() return NaowhUI.Snap("cdm", "mirror") end  -- barKey -> pressMirror
local function KbTextSnap() return NaowhUI.Snap("cdm", "kbText") end  -- "barKey|dbKey" -> value
local function AbSnap()     return NaowhUI.Snap("cdm", "ab")     end  -- abKey  -> hideKeybind
local function VisSnap()    return NaowhUI.Snap("cdm", "vis")    end  -- abKey  -> { scalar, modes }

local function Profile(folder)
    return NaowhUI.GetProfile and NaowhUI.GetProfile(folder) or nil
end

local ABSENT = NaowhUI.ABSENT

-- Stores the raw prior value: coercing to boolean would flatten the numeric keybind settings.
local function SetValue(s, saved, id, dbKey, on, value)
    if on then
        if saved[id] == nil then
            if s[dbKey] == nil then saved[id] = ABSENT else saved[id] = s[dbKey] end
        end
        s[dbKey] = value
    elseif saved[id] ~= nil then
        if saved[id] == ABSENT then s[dbKey] = nil else s[dbKey] = saved[id] end
        saved[id] = nil
    end
end

-------------------------------------------------------------------------------
--  Cooldown Manager
-------------------------------------------------------------------------------
-- The 3.3.5 CDM seeds its default bars lazily; ns.Bars() seeds and fills them, so a fresh
-- profile still has bars to write into.
local function CDMBars()
    local cns = _G.EllesmereUI and _G.EllesmereUI._ModuleNS and _G.EllesmereUI._ModuleNS.EllesmereUICooldownManager
    if cns and cns.Bars then
        local ok, bars = pcall(cns.Bars)
        if ok and type(bars) == "table" and bars[1] then return bars end
    end
    local prof = Profile("EllesmereUICooldownManager")
    local cb = prof and prof.cdmBars
    return cb and cb.bars
end
NaowhUI.CDMBars = CDMBars

-- barType is the authority, with the key as a legacy fallback.
local function IsBuffBar(bd)
    return (bd.barType or bd.key) == "buffs"
end

local function IsTrackingBar(bd)
    return (bd.barType or bd.key) == "tracking"
end

-- How the keybind text sits on the icon. EllesmereUI's own defaults are 10 / 2 / -2.
local KEYBIND_TEXT = {
    keybindSize    = 12,
    keybindOffsetX = -1,
    keybindOffsetY = 0,
}

-- Keybinds and mirrored presses go on non-buff bars only, since auras aren't cast.
local function DoApplyCDMBeginner(on)
    local bars = CDMBars()
    if not bars then return end

    for i, bd in ipairs(bars) do
        local key = bd.key or ("#" .. i)
        if not IsTrackingBar(bd) then SetValue(bd, TipSnap(), key, "showTooltip", on, true) end
        if not IsBuffBar(bd) and not IsTrackingBar(bd) then
            SetValue(bd, KbSnap(),     key, "showKeybind", on, true)
            SetValue(bd, MirrorSnap(), key, "pressMirror", on, true)

            local kbText = KbTextSnap()
            for dbKey, v in pairs(KEYBIND_TEXT) do
                SetValue(bd, kbText, key .. "|" .. dbKey, dbKey, on, v)
            end
        end
    end

    if _G._ECME_Apply then pcall(_G._ECME_Apply) end
end

-------------------------------------------------------------------------------
--  Action Bars 1 & 2
-------------------------------------------------------------------------------
-- 3.3.5 bars keep the mode in barVisibility plus the visibilityModes set (mouseover, combat, ...);
-- "always" with an empty set is the plain always-visible bar. Both are recorded as a pair.
local function CopyModes(m)
    if type(m) ~= "table" then return m end
    local c = {}
    for k, v in pairs(m) do c[k] = v end
    return c
end

local function DoApplyABBeginner(on)
    local prof = Profile("EllesmereUIActionBars")
    if not prof or not prof.bars then return end

    for _, key in ipairs(AB_KEYS) do
        local s = prof.bars[key]
        if type(s) == "table" then
            local vis = VisSnap()
            if on then
                if vis[key] == nil then
                    vis[key] = {
                        scalar = (s.barVisibility == nil) and ABSENT or s.barVisibility,
                        modes  = (s.visibilityModes == nil) and ABSENT or CopyModes(s.visibilityModes),
                    }
                end
                s.barVisibility   = "always"
                s.visibilityModes = nil
            else
                local rec = vis[key]
                if type(rec) == "table" then
                    if rec.scalar == ABSENT then s.barVisibility = nil else s.barVisibility = rec.scalar end
                    if rec.modes == ABSENT then s.visibilityModes = nil else s.visibilityModes = CopyModes(rec.modes) end
                end
                vis[key] = nil
            end
            SetValue(s, AbSnap(), key, "hideKeybind", on, false)
        end
    end

    if _G._EAB_Apply then pcall(_G._EAB_Apply) end
end

-- Deferred out of combat: the action bars are secure, and the CDM rebuild skips its protected
-- mouse pass in combat.
function NaowhUI.SetBeginnerMode(on)
    CDB().beginnerMode = on and true or false
    NaowhUI.RunOutOfCombat(function() DoApplyCDMBeginner(on) end)
    NaowhUI.RunOutOfCombat(function()
        DoApplyABBeginner(on)
        if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end   -- the action bars are capturable
    end)
end

if NaowhUI.RegisterReapply then
    NaowhUI.RegisterReapply(function()
        if CDB().beginnerMode then NaowhUI.SetBeginnerMode(true) end
    end)
end

-------------------------------------------------------------------------------
--  Hide tooltips in combat -- blanket, and/or Cooldown Manager only
-------------------------------------------------------------------------------
local GAMEPLAY_DEFAULTS = {
    hideTooltipsInCombat    = false,   -- everything
    hideCDMTooltipsInCombat = false,   -- just the Cooldown Manager icons
}

local function GDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.gameplay) ~= "table" then root.gameplay = {} end
    local t = root.gameplay
    for k, v in pairs(GAMEPLAY_DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

-- The 3.3.5 CDM parents every icon under a bar frame named EUI335Cooldown_<key>.
local CDM_PREFIX = "EUI335Cooldown_"
local function IsCDMFrame(frame)
    for _ = 1, 8 do
        if not frame then return false end
        local name = frame.GetName and frame:GetName()
        if name and name:sub(1, #CDM_PREFIX) == CDM_PREFIX then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

-- Hide() is unprotected, so this is safe in combat.
local tooltipHooked = false
local function InstallCombatTooltipHook()
    if tooltipHooked or not _G.GameTooltip then return end
    tooltipHooked = true
    GameTooltip:HookScript("OnShow", function(self)
        if not InCombatLockdown() then return end
        local g = GDB()
        if g.hideTooltipsInCombat then self:Hide(); return end
        if g.hideCDMTooltipsInCombat and IsCDMFrame(self:GetOwner()) then self:Hide() end
    end)
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
function NaowhUI.BuildGameplayOptions(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    _, h = W:SectionHeader(parent, "BEGINNER MODE", y); y = y - h

    _, h = W:Toggle(parent, "Beginner Mode", y,
        function() return CDB().beginnerMode end,
        function(v) NaowhUI.SetBeginnerMode(v) end,
        "A friendly setup for new players: keeps Action Bars 1 & 2 always visible, and shows "
        .. "keybinds, tooltips and key-press highlights on your bars and the Cooldown Manager. "
        .. "Turn off to restore your previous settings.")
    y = y - h

    _, h = W:SectionHeader(parent, "TOOLTIPS", y); y = y - h

    -- "All" is a superset, but the CDM toggle stays clickable so turning "All" off leaves it be.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hide All Tooltips in Combat",
          tooltip = "Hides all tooltips while you are in combat.",
          getValue = function() return GDB().hideTooltipsInCombat end,
          setValue = function(v)
              GDB().hideTooltipsInCombat = v
              InstallCombatTooltipHook()
          end },
        { type = "toggle", text = "Hide CDM Tooltips in Combat",
          tooltip = "Hides only the Cooldown Manager tooltips while you are in combat.",
          getValue = function() return GDB().hideCDMTooltipsInCombat end,
          setValue = function(v)
              GDB().hideCDMTooltipsInCombat = v
              InstallCombatTooltipHook()
          end }
    ); y = y - h

    return math.abs(y)
end

-- SetBeginnerMode(false) clears its own snapshots, but its action-bar half DEFERS in combat, so
-- wiping now would destroy them before it reads them.
function NaowhUI.ResetCDM()
    if CDB().beginnerMode then NaowhUI.SetBeginnerMode(false) end
    if not InCombatLockdown() then NaowhUI.SettingsRoot().cdm = nil end
    NaowhUI.SettingsRoot().gameplay = nil   -- writes nothing into EllesmereUI; nothing to sequence
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Inert while the option is off, so the toggle stays a pure DB write.
    InstallCombatTooltipHook()
    C_Timer.After(1, function()   -- once the CDM and action bars have initialised
        if CDB().beginnerMode then NaowhUI.SetBeginnerMode(true) end
    end)
end)
