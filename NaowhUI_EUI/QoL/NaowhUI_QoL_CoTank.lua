-------------------------------------------------------------------------------
--  NaowhUI_QoL_CoTank.lua -- health bar for the OTHER tank: raid only, tank spec, second tank
--  present. Health is event-driven, filtered to the tracked unit in the handler.
--  3.3.5: debuffs are read directly with UnitDebuff into a small pool of our own icons.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end
local QoL = NaowhUI.QoL
if not QoL then return end

local SECTION = "coTank"

local DEFAULTS = {
    enabled = false, font = NaowhUI.FONT_DEFAULT,
    point = "CENTER", x = 200, y = 0,
    width = 150, height = 20,
    -- Stand-in bar outside a raid, for placing and sizing. Live data always wins over it.
    preview = false,
    healthColorR = 0, healthColorG = 0.8, healthColorB = 0.2,
    useClassColor = true,
    bgAlpha = 0.6,
    showName = true,
    nameFormat = "full",
    nameLength = 6,
    nameFontSize = 12,
    nameColorR = 1, nameColorG = 1, nameColorB = 1,
    nameColorUseClassColor = true,

    -- On by default, but still gated behind `enabled` above.
    debuffEnabled = true,
    debuffFilter = "important",      -- important | all | dispellable
    debuffSize = 22,
    debuffCap = 3,
    debuffSpacing = 2,
    debuffPosition = "top",          -- corner of the bar the row hangs off
    debuffGrow = "CENTER",           -- LEFT | RIGHT | UP | DOWN | CENTER
    debuffOffsetX = 0,
    debuffOffsetY = 3,
    debuffShowDuration = true,
    debuffDurSize = 10,
    debuffShowStacks = true,
    debuffStackSize = 10,
    debuffTooltips = false,
}

local function DB() return QoL.DB(SECTION, DEFAULTS) end
function NaowhUI.QoLCoTankDB() return DB() end

local frame, healthBar, healthBg, nameText, healthWatcher
local otherTank, otherTankClass
local trackedUnit                -- the unit the health events are filtered to
local lastW, lastH               -- last applied size; a resize invalidates the bar's fill
local lastFontPath, lastFontSize -- SetFont reloads the font object, so only on a real change

local UpdateDisplay              -- forward

local debuffHost, debuffIcons    -- our icon pool, built on first use
local debuffUnit                 -- the unit the icons read from
local lastDebuffStyleFP          -- restyles walk every icon, so only on a real change

-------------------------------------------------------------------------------
--  Roster
-------------------------------------------------------------------------------
local function IsTankUnit(unit)
    if UnitGroupRolesAssigned then
        local isTank = UnitGroupRolesAssigned(unit)
        if isTank == true or isTank == "TANK" then return true end
    end
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return true end
    return false
end

-- Raid only: "raidN" is only valid inside one.
local function FindOtherTank()
    local n = GetNumRaidMembers()
    if n == 0 then return nil end
    for i = 1, n do
        local unit = "raid" .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and IsTankUnit(unit) then
            return unit
        end
    end
    return nil
end

-- The talent tree that only tanks put most of their points in. Druids and death knights share a
-- tree with a damage build, so for them only the assigned role counts.
local TANK_TREE = { WARRIOR = 3, PALADIN = 2 }

local function IsPlayerTankSpec()
    if IsTankUnit("player") then return true end
    local tree = TANK_TREE[QoL.ClassFile()]
    return tree ~= nil and QoL.SpecIndex() == tree
end

local function RescanRoster()
    otherTank = FindOtherTank()
    if otherTank then
        local _, cls = UnitClass(otherTank)
        otherTankClass = cls
    else
        otherTankClass = nil
    end
end

local function ShouldBeVisible(t)
    if not t.enabled or QoL.HasNaowhQOL() then return false end
    -- Both override the gating: you cannot position a bar that only appears in a raid.
    if QoL.unlockActive or t.preview then return true end
    if GetNumRaidMembers() == 0 then return false end
    if not IsPlayerTankSpec() then return false end
    return otherTank ~= nil
end

-------------------------------------------------------------------------------
--  Health, event-driven
-------------------------------------------------------------------------------
local function WatchHealth(unit)
    if trackedUnit == unit then return end
    trackedUnit = unit
    if not healthWatcher then return end
    healthWatcher:UnregisterAllEvents()
    if unit then
        healthWatcher:RegisterEvent("UNIT_HEALTH")
        healthWatcher:RegisterEvent("UNIT_MAXHEALTH")
        healthWatcher:RegisterEvent("UNIT_AURA")
    end
end

local function RefreshHealthValue()
    local unit = trackedUnit
    if not unit or not UnitExists(unit) then return end
    healthBar:SetMinMaxValues(0, math.max(1, UnitHealthMax(unit) or 1))
    healthBar:SetValue(UnitHealth(unit) or 0)
end

-- Deferred a frame after a resize: in the same pass the fill is recomputed against a size that has
-- not settled, and the bar renders empty.
local function RepushBar()
    if not healthBar then return end
    if trackedUnit then
        RefreshHealthValue()
    else
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(75)
    end
end

local RefreshDebuffs   -- forward: UNIT_AURA lands on the health watcher

-------------------------------------------------------------------------------
--  Frame
-------------------------------------------------------------------------------
-- Built only once the feature is on, and out of combat: SetAttribute on a fresh secure frame is
-- a protected call.
local function BuildFrame()
    if frame then return true end
    if not DB().enabled then return false end
    if InCombatLockdown() then return false end

    frame = CreateFrame("Button", "NaowhUICoTankFrame", UIParent, "SecureUnitButtonTemplate")
    frame:SetWidth(DEFAULTS.width)
    frame:SetHeight(DEFAULTS.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULTS.x, DEFAULTS.y)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("type1", "target")
    frame:Hide()

    local border = CreateFrame("Frame", nil, frame)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)

    healthBg = frame:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    healthBg:SetTexture(0.1, 0.1, 0.1, 0.8)

    healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetAllPoints()
    healthBar:SetStatusBarTexture([[Interface\Buttons\WHITE8X8]])
    healthBar:SetStatusBarColor(0, 0.8, 0.2)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)

    nameText = healthBar:CreateFontString(nil, "OVERLAY")
    lastFontPath, lastFontSize = QoL.FontPath(), 12
    nameText:SetFont(lastFontPath, lastFontSize, "OUTLINE")
    nameText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)

    -- 3.3.5 has no unit-filtered registration, so the filter lives here.
    healthWatcher = CreateFrame("Frame")
    healthWatcher:SetScript("OnEvent", function(_, event, unit)
        if not trackedUnit or unit ~= trackedUnit then return end
        if event == "UNIT_AURA" then
            if RefreshDebuffs then RefreshDebuffs() end
        else
            RefreshHealthValue()
        end
    end)

    -- No drag scripts: Unlock Mode drives a mover over this frame and hands back the position
    -- through savePos (registered at the bottom of the file).
    return true
end

-------------------------------------------------------------------------------
--  Paint
-------------------------------------------------------------------------------
local function ClassColorOr(r, g, b)
    if otherTankClass then
        local c = RAID_CLASS_COLORS[otherTankClass]
        if c then return c.r, c.g, c.b end
    end
    return r, g, b
end

local function SetNameFont(t)
    local path = QoL.FontPath(t.font)
    local size = t.nameFontSize or 12
    if path == lastFontPath and size == lastFontSize then return end
    lastFontPath, lastFontSize = path, size
    nameText:SetFont(path, size, "OUTLINE")
end

local function PaintName(name, t, allowClassColor)
    if not t.showName then
        nameText:Hide()
        return
    end
    if t.nameFormat == "abbreviated" and t.nameLength and type(name) == "string" then
        name = string.sub(name, 1, t.nameLength)
    end
    nameText:SetText(name)
    SetNameFont(t)
    if allowClassColor and t.nameColorUseClassColor then
        nameText:SetTextColor(ClassColorOr(t.nameColorR or 1, t.nameColorG or 1, t.nameColorB or 1))
    else
        nameText:SetTextColor(t.nameColorR or 1, t.nameColorG or 1, t.nameColorB or 1)
    end
    nameText:Show()
end

local function PaintBar(t)
    if t.useClassColor then
        healthBar:SetStatusBarColor(ClassColorOr(t.healthColorR or 0, t.healthColorG or 0.8, t.healthColorB or 0.2))
    else
        healthBar:SetStatusBarColor(t.healthColorR or 0, t.healthColorG or 0.8, t.healthColorB or 0.2)
    end
    if otherTank then PaintName(UnitName(otherTank), t, true) else nameText:Hide() end
end

-------------------------------------------------------------------------------
--  Debuffs
-------------------------------------------------------------------------------
-- Sated / Exhaustion / Deserter style noise nobody needs on a tank bar.
local HIDDEN_DEBUFFS = {
    [57723] = true, [57724] = true,   -- Exhaustion / Sated
    [26013] = true,                   -- Deserter
    [71041] = true,                   -- Dungeon Deserter
    [25771] = true,                   -- Forbearance
}

local MAX_ICONS = 8

local DEBUFF_CORNERS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- The host edge meeting the bar is the MIRROR of the bar corner: a row below puts its TOP on
-- the bar's BOTTOM. CENTER is the deliberate overlap.
local DEBUFF_MIRROR = {
    TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
    BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
    CENTER = "CENTER",
}

local function DebuffFlow(t)
    local corner  = DEBUFF_CORNERS[t.debuffPosition or "top"] or "TOP"
    local grow    = t.debuffGrow or "CENTER"
    local myPoint = DEBUFF_MIRROR[corner] or "BOTTOM"

    local gH, gV = grow, "UP"
    if grow == "CENTER" then
        gH, gV = "RIGHT", myPoint:find("TOP", 1, true) and "DOWN" or "UP"
    elseif grow == "UP" or grow == "DOWN" then
        gH, gV = "RIGHT", grow
    end
    return corner, myPoint, gH, gV, grow
end

local function FormatDuration(left)
    if left >= 60 then return ("%dm"):format(math.ceil(left / 60)) end
    if left >= 10 then return ("%d"):format(math.floor(left)) end
    return ("%.1f"):format(left)
end

local function IconOnUpdate(self, elapsed)
    self._acc = (self._acc or 0) + elapsed
    if self._acc < 0.1 then return end
    self._acc = 0
    local left = (self._expires or 0) - GetTime()
    if left > 0 then self.dur:SetText(FormatDuration(left)) else self.dur:SetText("") end
end

local function BuildDebuffIcons()
    if debuffHost or not frame then return end
    debuffHost = CreateFrame("Frame", nil, frame)
    debuffHost:SetFrameLevel(healthBar:GetFrameLevel() + 5)
    debuffHost:SetWidth(1)
    debuffHost:SetHeight(1)
    debuffIcons = {}
    for i = 1, MAX_ICONS do
        local b = CreateFrame("Frame", nil, debuffHost)
        b:SetFrameLevel(debuffHost:GetFrameLevel() + 1)
        local edge = b:CreateTexture(nil, "BACKGROUND")
        edge:SetTexture(0, 0, 0, 1)
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        b.edge = edge
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.icon = tex
        local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetReverse(true)
        b.cd = cd
        local textHolder = CreateFrame("Frame", nil, b)
        textHolder:SetAllPoints()
        textHolder:SetFrameLevel(cd:GetFrameLevel() + 2)
        b.dur = textHolder:CreateFontString(nil, "OVERLAY")
        b.dur:SetPoint("CENTER", 0, 0)
        b.stack = textHolder:CreateFontString(nil, "OVERLAY")
        b.stack:SetPoint("BOTTOMRIGHT", 1, 1)
        b:SetScript("OnEnter", function(self)
            if not DB().debuffTooltips or not self._unit or not self._index then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetUnitDebuff(self._unit, self._index, self._filter)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        debuffIcons[i] = b
    end
end

local function DebuffStyleFP(t)
    return table.concat({
        t.debuffSize or 22, QoL.FontPath(t.font), tostring(t.debuffShowDuration),
        t.debuffDurSize or 10, tostring(t.debuffShowStacks), t.debuffStackSize or 10,
        tostring(t.debuffTooltips), t.debuffSpacing or 2, t.debuffPosition or "top",
        t.debuffGrow or "CENTER", t.debuffOffsetX or 0, t.debuffOffsetY or 0, t.debuffCap or 3,
    }, "|")
end

-- Size, fonts and slot positions. The slots are fixed; RefreshDebuffs only fills them.
local function StyleDebuffs(t, force)
    if not debuffHost then return end
    local fp = DebuffStyleFP(t)
    if fp == lastDebuffStyleFP and not force then return end
    lastDebuffStyleFP = fp

    local corner, myPoint, gH, gV, grow = DebuffFlow(t)
    local size, spacing = t.debuffSize or 22, t.debuffSpacing or 2
    local n = math.min(t.debuffCap or 3, MAX_ICONS)
    local vertical = (grow == "UP" or grow == "DOWN")
    local run = n * size + math.max(0, n - 1) * spacing
    local path = QoL.FontPath(t.font)

    debuffHost:ClearAllPoints()
    debuffHost:SetPoint(myPoint, frame, corner, t.debuffOffsetX or 0, t.debuffOffsetY or 0)
    debuffHost:SetWidth(math.max(1, vertical and size or run))
    debuffHost:SetHeight(math.max(1, vertical and run or size))

    for i = 1, MAX_ICONS do
        local b = debuffIcons[i]
        local off = (i - 1) * (size + spacing)
        b:ClearAllPoints()
        b:SetWidth(size)
        b:SetHeight(size)
        if vertical then
            local from = (gV == "DOWN") and "TOP" or "BOTTOM"
            b:SetPoint(from, debuffHost, from, 0, (gV == "DOWN") and -off or off)
        else
            local from = (gH == "LEFT") and "RIGHT" or "LEFT"
            b:SetPoint(from, debuffHost, from, (gH == "LEFT") and -off or off, 0)
        end
        b.dur:SetFont(path, t.debuffDurSize or 10, "OUTLINE")
        b.stack:SetFont(path, t.debuffStackSize or 10, "OUTLINE")
        NaowhUI.Shown(b.dur, t.debuffShowDuration ~= false)
        b:EnableMouse(t.debuffTooltips and true or false)
    end
end

-- important: anything not cast by a player (boss and trash mechanics). dispellable: what the
-- player can remove ("RAID" on a harmful scan). all: every debuff.
local function Wanted(filter, caster)
    if filter == "important" then
        return not caster or not UnitIsPlayer(caster)
    end
    return true
end

function RefreshDebuffs()
    if not debuffHost or not debuffHost:IsShown() then return end
    local t = DB()
    local unit = debuffUnit
    local cap = math.min(t.debuffCap or 3, MAX_ICONS)
    local filter = t.debuffFilter or "important"
    local scanFilter = (filter == "dispellable") and "RAID" or nil
    local shown = 0
    if unit and UnitExists(unit) then
        for i = 1, 40 do
            local name, _, icon, count, _, duration, expires, caster, _, _, spellId =
                UnitDebuff(unit, i, scanFilter)
            if not name then break end
            if not HIDDEN_DEBUFFS[spellId or 0] and Wanted(filter, caster) then
                shown = shown + 1
                local b = debuffIcons[shown]
                b.icon:SetTexture(icon)
                b._unit, b._index, b._filter = unit, i, scanFilter
                if t.debuffShowStacks ~= false and count and count > 1 then
                    b.stack:SetText(count)
                else
                    b.stack:SetText("")
                end
                if duration and duration > 0 and expires then
                    b.cd:SetCooldown(expires - duration, duration)
                    b.cd:Show()
                    b._expires = expires
                    b:SetScript("OnUpdate", t.debuffShowDuration ~= false and IconOnUpdate or nil)
                else
                    b.cd:Hide()
                    b._expires = nil
                    b.dur:SetText("")
                    b:SetScript("OnUpdate", nil)
                end
                b:Show()
                if shown >= cap then break end
            end
        end
    end
    for i = shown + 1, MAX_ICONS do
        local b = debuffIcons[i]
        b:SetScript("OnUpdate", nil)
        b:Hide()
    end
end

-------------------------------------------------------------------------------
--  Preview row
-------------------------------------------------------------------------------
local PREVIEW_TEX = {
    [[Interface\Icons\Spell_Shadow_ShadowWordPain]],
    [[Interface\Icons\Spell_Fire_Immolation]],
    [[Interface\Icons\Spell_Frost_FrostNova]],
    [[Interface\Icons\Spell_Nature_Earthbind]],
    [[Interface\Icons\Spell_Shadow_CurseOfSargeras]],
    [[Interface\Icons\Spell_Holy_Silence]],
    [[Interface\Icons\Ability_Poisons]],
    [[Interface\Icons\Spell_Shadow_UnholyFrenzy]],
}

local function ShowDebuffIcons(mode)
    -- mode: nil hides, "live" scans the unit, "preview" fills placeholders.
    if not mode then
        if debuffHost then debuffHost:Hide() end
        return
    end
    BuildDebuffIcons()
    if not debuffHost then return end
    local t = DB()
    StyleDebuffs(t)
    debuffHost:Show()
    if mode == "live" then
        RefreshDebuffs()
        return
    end
    local cap = math.min(t.debuffCap or 3, MAX_ICONS)
    for i = 1, MAX_ICONS do
        local b = debuffIcons[i]
        b:SetScript("OnUpdate", nil)
        b._unit, b._index = nil, nil
        if i <= cap then
            b.icon:SetTexture(PREVIEW_TEX[i])
            b.cd:Hide()
            b.dur:SetText("")
            b.stack:SetText("")
            b:Show()
        else
            b:Hide()
        end
    end
end

local function WatchDebuffs(unit)
    debuffUnit = unit
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")

-- Registered only while the feature is on: roster events are noisy in a raid.
local ACTIVE_EVENTS = {
    "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}
local eventsOn = false

local function SyncEvents(want)
    if want == eventsOn then return end
    eventsOn = want
    for i = 1, #ACTIVE_EVENTS do
        if want then
            pcall(ev.RegisterEvent, ev, ACTIVE_EVENTS[i])
        else
            ev:UnregisterEvent(ACTIVE_EVENTS[i])
        end
    end
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
function UpdateDisplay()
    local t = DB()
    local live = t.enabled and not QoL.HasNaowhQOL()
    SyncEvents(live)

    if live then RescanRoster() end

    if not BuildFrame() then return end

    if not InCombatLockdown() then
        frame:EnableMouse(true)
        local w, h = t.width or 150, t.height or 20
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            frame:SetWidth(w)
            frame:SetHeight(h)
            C_Timer.After(0, RepushBar)
        end
    end

    -- Moving a secure frame is protected, so this waits. posInitialized stays false until the
    -- move lands, and PLAYER_REGEN_ENABLED brings us back to finish it.
    if not frame.posInitialized and not InCombatLockdown() then
        frame:ClearAllPoints()
        local point = t.point or "CENTER"
        frame:SetPoint(point, UIParent, point, t.x or 200, t.y or 0)
        frame.posInitialized = true
    end

    healthBg:SetAlpha(t.bgAlpha or 0.6)

    if not ShouldBeVisible(t) then
        WatchHealth(nil)
        WatchDebuffs(nil)
        ShowDebuffIcons(nil)
        if not InCombatLockdown() then
            frame:SetAttribute("unit", nil)
            frame:Hide()
        end
        return
    end

    if not InCombatLockdown() then frame:SetAttribute("unit", otherTank) end

    if (QoL.unlockActive or t.preview) and not otherTank then
        -- Nobody to show: a stand-in bar parked at a fixed 75%.
        WatchHealth(nil)
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(75)
        healthBar:SetStatusBarColor(t.healthColorR or 0, t.healthColorG or 0.8, t.healthColorB or 0.2)
        PaintName("TankName", t, false)
        WatchDebuffs(nil)
        ShowDebuffIcons(t.debuffEnabled and "preview" or nil)
    else
        WatchHealth(otherTank)
        PaintBar(t)
        RefreshHealthValue()
        if t.debuffEnabled then
            WatchDebuffs(otherTank)
            ShowDebuffIcons("live")
        else
            WatchDebuffs(nil)
            ShowDebuffIcons(nil)
        end
    end

    if not InCombatLockdown() then frame:Show() end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
-- Repositions from scratch: the offsets are only re-read once posInitialized is cleared.
function NaowhUI.QoLCoTankReposition()
    if frame then frame.posInitialized = false end
    UpdateDisplay()
end

local function Teardown()
    SyncEvents(false)
    WatchHealth(nil)
    WatchDebuffs(nil)
    ShowDebuffIcons(nil)
    if not frame then return end
    if not InCombatLockdown() then
        frame:SetAttribute("unit", nil)
        frame:Hide()
    end
end

NaowhUI.RegisterOwned(SECTION, {
    Apply    = NaowhUI.QoLCoTankReposition,
    Teardown = Teardown,
    Reset    = function()
        Teardown()
        QoL.ClearDB(SECTION)
    end,
})

QoL.RegisterRefresh(SECTION, function()
    -- A settings change can retune the fonts, so let the style passes see a real change.
    lastFontPath, lastFontSize = nil, nil
    lastDebuffStyleFP = nil
    UpdateDisplay()
end)
QoL.OnSpecChanged(UpdateDisplay)

-- Every path is the same: UpdateDisplay re-scans and repaints.
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Unlock Mode builds its element list after the suite has finished loading, and a
        -- registration landing before it is ready is lost.
        C_Timer.After(2, function()
            QoL.RegisterMover({
                key      = "NaowhUI_CoTank",
                label    = "Co-Tank Frame",
                order    = 100,
                db       = DB,
                apply    = NaowhUI.QoLCoTankReposition,
                getFrame = function() BuildFrame(); return frame end,
                pointKey = "point", xKey = "x", yKey = "y",
                widthKey = "width", heightKey = "height",
                minW = 50, minH = 10,
                isHidden = function()
                    local t = DB()
                    return not t.enabled or QoL.HasNaowhQOL()
                end,
            })
        end)
        UpdateDisplay()
        return
    end
    UpdateDisplay()
end)

-- Entering or leaving Unlock Mode changes whether the bar shows at all (ShouldBeVisible).
QoL.OnUnlockModeChanged(function() UpdateDisplay() end)
