-------------------------------------------------------------------------------
--  NaowhUI_QoL_Stealth.lua -- two independent reminders sharing one settings table: restealth
--  (rogue, opted-in druid specs) and wrong form/stance/aura (druid, warrior, priest, paladin).
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end
local QoL = NaowhUI.QoL
if not QoL then return end

local SECTION = "stealth"

local DEFAULTS = {
    -- Stealth reminder
    enabled = false, font = NaowhUI.FONT_DEFAULT,
    stealthText = "STEALTH", warningText = "RESTEALTH",
    stealthR = 0, stealthG = 1, stealthB = 0, stealthUseClassColor = false,
    warningR = 1, warningG = 0, warningB = 0, warningUseClassColor = false,
    showStealthed = true, showNotStealthed = true,
    disableWhenRested = false, groupOnly = false,
    point = "CENTER", x = 0, y = 150, width = 200, height = 40,
    textScale = 1,   -- multiplies the box-derived size; 1 is the long-standing behaviour
    enableBalance = false, enableResto = false,

    -- Stance reminder
    stanceEnabled = false, stanceFont = NaowhUI.FONT_DEFAULT,
    stanceWarnText = "",   -- empty means "use the class default label"
    stanceWarnR = 1, stanceWarnG = 0.4, stanceWarnB = 0, stanceWarnUseClassColor = false,
    stancePoint = "CENTER", stanceX = 0, stanceY = 100, stanceWidth = 200, stanceHeight = 40,
    stanceTextScale = 1,
    stanceCombatOnly = false, stanceDisableWhenRested = false, stanceInstanceOnly = false,
    stanceSoundEnabled = false, stanceSound = "none", stanceSoundInterval = 3,
}

local function DB() return QoL.DB(SECTION, DEFAULTS) end
function NaowhUI.QoLStealthDB() return DB() end

-- Live state, refreshed from events rather than polled.
local inCombat, stealthed, isResting, inInstance = false, false, false, false
-- Never cached: a cached form goes stale the moment a shift happens while UPDATE_SHAPESHIFT_FORM
-- is unregistered, which it is whenever the stance half is switched off.
local function CurrentForm() return GetShapeshiftForm() or 0 end

-- 3.3.5 form indices depend on which forms the character has learned, so forms are matched by
-- spell name instead of slot.
local function SpellName(id) return (GetSpellInfo(id)) end

local function ActiveFormName()
    local form = CurrentForm()
    if form == 0 then return nil end
    local _, name = GetShapeshiftFormInfo(form)
    return name
end

-- IsStealthed is not in every 3.3.5 client; the aura names cover Stealth, Prowl, Shadowmeld and
-- Vanish's lingering stealth.
local STEALTH_SPELLS = { 1784, 5215, 58984, 11327 }
local function IsStealthedNow()
    if IsStealthed then return IsStealthed() and true or false end
    for i = 1, #STEALTH_SPELLS do
        local n = SpellName(STEALTH_SPELLS[i])
        if n and UnitBuff("player", n) then return true end
    end
    return false
end

local function InGroup()
    return (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
end

local stealthFrame, stealthLabel
local stanceFrame,  stanceLabel

-- Declared up here because Teardown, further down, unregisters through them.
local ev = CreateFrame("Frame")
local wanted, registered = {}, {}

-- Forward-declared: defined down in Events, but the lifecycle hooks above it call it.
local SyncEvents

-------------------------------------------------------------------------------
--  Gating
-------------------------------------------------------------------------------
-- Rogues always. Druids only where the user opted in; Feral (2) is stealth by trade.
-- Wrath druids have three trees: Balance 1, Feral 2, Restoration 3.
local function IsStealthSpec()
    local cls = QoL.ClassFile()
    if cls == "ROGUE" then return true end
    if cls ~= "DRUID" then return false end

    local t = DB()
    local idx = QoL.SpecIndex()
    if idx == 2 then return true end
    if idx == 1 and t.enableBalance  then return true end
    if idx == 3 and t.enableResto    then return true end
    return false
end

-- Per class and talent tree, the form spells that count as "right". "any" accepts any active
-- form (Paladin auras); nil means the tree has nothing to check.
local EXPECTED_FORMS = {
    DRUID   = { [1] = { 24858 }, [2] = { 5487, 9634, 768 }, [3] = { 33891 } },
    WARRIOR = { [1] = { 2457 }, [2] = { 2458 }, [3] = { 71 } },
    PRIEST  = { [3] = { 15473 } },
    PALADIN = { [1] = "any", [2] = "any", [3] = "any" },
}

local STANCE_LABELS = {
    DRUID   = "CHECK FORM",
    WARRIOR = "CHECK STANCE",
    PRIEST  = "SHADOWFORM",
    PALADIN = "CHECK AURA",
}

-- Travel, Aquatic, Flight and Swift Flight Form.
local DRUID_TRAVEL_FORMS = { 783, 1066, 33943, 40120 }

local function DefaultStanceLabel()
    return STANCE_LABELS[QoL.ClassFile()] or "CHECK STANCE"
end

local function GetExpectedForm()
    local classForms = EXPECTED_FORMS[QoL.ClassFile()]
    if not classForms then return nil end
    return classForms[QoL.SpecIndex()]
end

local function FormIn(list)
    local active = ActiveFormName()
    if not active then return false end
    for i = 1, #list do
        if SpellName(list[i]) == active then return true end
    end
    return false
end

local function IsInExpectedForm(expected)
    if expected == "any" then return CurrentForm() > 0 end
    return FormIn(expected)
end

-- Travel form is a movement choice, not a mistake, so it is treated like being mounted.
local function IsDruidTravelForm()
    return QoL.ClassFile() == "DRUID" and FormIn(DRUID_TRAVEL_FORMS)
end

-------------------------------------------------------------------------------
--  Stance sound
-------------------------------------------------------------------------------
local stanceTicker, lastStanceSound, stanceSoundFired = nil, 0, false
local STANCE_SOUND_COOLDOWN = 0.9

local function StopStanceSound()
    if stanceTicker then
        stanceTicker:Cancel()
        stanceTicker = nil
    end
end

local function PlayStanceSound(key)
    local now = GetTime()
    if now - lastStanceSound < STANCE_SOUND_COOLDOWN then return end
    lastStanceSound = now
    QoL.PlaySound(key)
end

local function StartStanceSound(t)
    StopStanceSound()
    -- Latched before the "none" bail, or every subsequent event re-enters here for a user with
    -- sound on but nothing chosen.
    stanceSoundFired = true

    local key = t.stanceSound or QoL.SOUND_NONE
    if key == QoL.SOUND_NONE then return end
    PlayStanceSound(key)
    local interval = t.stanceSoundInterval or 3
    if interval > 0 then
        stanceTicker = C_Timer.NewTicker(interval, function() PlayStanceSound(key) end)
    end
end

-------------------------------------------------------------------------------
--  Frames
-------------------------------------------------------------------------------
-- Built on first need: most characters never switch either reminder on.
local function BuildFrames()
    if stealthFrame then return true end

    local t = DB()
    if not (t.enabled or t.stanceEnabled) then return false end

    stealthFrame = CreateFrame("Frame", "NaowhUIStealthReminder", UIParent)
    stealthFrame:SetSize(DEFAULTS.width, DEFAULTS.height)
    stealthFrame:SetPoint("CENTER", UIParent, "CENTER", DEFAULTS.x, DEFAULTS.y)
    stealthFrame:Hide()
    stealthLabel = stealthFrame:CreateFontString(nil, "OVERLAY")
    stealthLabel:SetFont(QoL.FontPath(), 24, "OUTLINE")
    stealthLabel:SetPoint("CENTER")

    stanceFrame = CreateFrame("Frame", "NaowhUIStanceReminder", UIParent)
    stanceFrame:SetSize(DEFAULTS.stanceWidth, DEFAULTS.stanceHeight)
    stanceFrame:SetPoint("CENTER", UIParent, "CENTER", DEFAULTS.stanceX, DEFAULTS.stanceY)
    stanceFrame:Hide()
    stanceLabel = stanceFrame:CreateFontString(nil, "OVERLAY")
    stanceLabel:SetFont(QoL.FontPath(), 24, "OUTLINE")
    stanceLabel:SetPoint("CENTER")

    -- No drag or resize handles of our own: both frames are registered with EllesmereUI's Unlock
    -- Mode at the bottom of this file, which supplies the mover, the grip and the nudge keys.
    return true
end

-- Box height drives the base size, so a drag-resize scales the text; the scale multiplies that.
-- SetFont reloads the font object, so it is skipped unless path or size moved.
local function FitLabel(label, frame, fontName, scale)
    local size = math.max(6, math.min(120, math.floor(frame:GetHeight() * 0.55 * (scale or 1))))
    local path = QoL.FontPath(fontName)
    if label._path == path and label._size == size then return end
    label._path, label._size = path, size
    label:SetFont(path, size, "OUTLINE")
    if not label:GetFont() then
        label:SetFont(NaowhUI.FALLBACK_FONT, size, "OUTLINE")
    end
end

local function SetLabel(label, text, r, g, b)
    if label._text ~= text then
        label._text = text
        label:SetText(text)
    end
    if label._r ~= r or label._g ~= g or label._b ~= b then
        label._r, label._g, label._b = r, g, b
        label:SetTextColor(r, g, b)
    end
end

-------------------------------------------------------------------------------
--  Stealth reminder
-------------------------------------------------------------------------------
-- Position and size are read once and then owned by the frame, so a drag or resize is not undone
-- by the next update. `placed` is cleared whenever the settings change.
local placedStealth, placedStance = false, false

function NaowhUI.QoLStealthUpdate()
    if not BuildFrames() then return end
    local t = DB()

    if not placedStealth then
        stealthFrame:ClearAllPoints()
        local point = t.point or "CENTER"
        stealthFrame:SetPoint(point, UIParent, point, t.x or 0, t.y or 150)
        stealthFrame:SetSize(t.width or 200, t.height or 40)
        placedStealth = true
    end

    FitLabel(stealthLabel, stealthFrame, t.font, t.textScale)

    -- Set before the gates below, which all end in a return: Unlock Mode still needs something to
    -- position.
    if stealthed then
        SetLabel(stealthLabel, t.stealthText ~= "" and t.stealthText or "STEALTH",
            QoL.EffectiveColor(t, "stealthR", "stealthG", "stealthB", "stealthUseClassColor"))
    else
        SetLabel(stealthLabel, t.warningText ~= "" and t.warningText or "RESTEALTH",
            QoL.EffectiveColor(t, "warningR", "warningG", "warningB", "warningUseClassColor"))
    end

    if not t.enabled or QoL.HasNaowhQOL() then stealthFrame:Hide(); return end

    -- Ahead of every gate below: any one of them would otherwise leave the frame unpositionable.
    if QoL.unlockActive then
        stealthFrame:Show()
        return
    end

    if not IsStealthSpec() then stealthFrame:Hide(); return end
    if t.disableWhenRested and isResting and not inInstance then stealthFrame:Hide(); return end
    if t.groupOnly and not InGroup() then stealthFrame:Hide(); return end
    if inCombat then stealthFrame:Hide(); return end
    if IsMounted() then stealthFrame:Hide(); return end
    if stealthed and t.showStealthed == false then stealthFrame:Hide(); return end
    if not stealthed and t.showNotStealthed == false then stealthFrame:Hide(); return end

    stealthFrame:Show()
end

-------------------------------------------------------------------------------
--  Stance reminder
-------------------------------------------------------------------------------
function NaowhUI.QoLStanceUpdate()
    if not BuildFrames() then return end
    local t = DB()

    if not placedStance then
        stanceFrame:ClearAllPoints()
        local point = t.stancePoint or "CENTER"
        stanceFrame:SetPoint(point, UIParent, point, t.stanceX or 0, t.stanceY or 100)
        stanceFrame:SetSize(t.stanceWidth or 200, t.stanceHeight or 40)
        placedStance = true
    end

    -- stanceFont falls back to the stealth half's font, not the global default, so the two
    -- reminders match without setting the same font twice.
    FitLabel(stanceLabel, stanceFrame,
        t.stanceFont ~= NaowhUI.FONT_DEFAULT and t.stanceFont or t.font, t.stanceTextScale)

    SetLabel(stanceLabel, t.stanceWarnText ~= "" and t.stanceWarnText or DefaultStanceLabel(),
        QoL.EffectiveColor(t, "stanceWarnR", "stanceWarnG", "stanceWarnB", "stanceWarnUseClassColor"))

    -- Every path out stops the sound as well as hiding the frame: a ticker must never outlive the
    -- warning it belongs to.
    local function Off()
        StopStanceSound()
        stanceFrame:Hide()
    end

    if not t.stanceEnabled or QoL.HasNaowhQOL() then Off(); return end

    -- A static preview while positioning, and silent: dragging it must not beep every few seconds.
    if QoL.unlockActive then
        StopStanceSound()
        stanceSoundFired = false
        stanceFrame:Show()
        return
    end

    if t.stanceCombatOnly and not inCombat then Off(); return end
    if IsMounted() or IsDruidTravelForm() then Off(); return end
    if t.stanceDisableWhenRested and isResting and not inInstance then Off(); return end
    if t.stanceInstanceOnly and not inInstance then Off(); return end

    local expected = GetExpectedForm()
    if not expected then Off(); return end

    if IsInExpectedForm(expected) then
        stanceSoundFired = false   -- armed again for the next time they drop out of form
        Off()
        return
    end

    stanceFrame:Show()

    if t.stanceSoundEnabled then
        if not stanceTicker and not stanceSoundFired then StartStanceSound(t) end
    else
        StopStanceSound()
        stanceSoundFired = false
    end
end

local function UpdateBoth()
    NaowhUI.QoLStealthUpdate()
    NaowhUI.QoLStanceUpdate()
end

-- Re-reads position and size from the DB. Anything that edits them calls this rather than Update.
-- Also the profile-switch entry point, so it re-derives which events the new profile needs.
function NaowhUI.QoLStealthReposition()
    placedStealth, placedStance = false, false
    SyncEvents()
    UpdateBoth()
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
local function Teardown()
    StopStanceSound()
    stanceSoundFired = false
    -- Unregistered directly rather than via SyncEvents: at uninstall this has to hold regardless
    -- of what the settings table says, and the settings table is about to be wiped anyway.
    for e in pairs(registered) do ev:UnregisterEvent(e) end
    wipe(registered)
    if stealthFrame then stealthFrame:Hide() end
    if stanceFrame  then stanceFrame:Hide()  end
end

NaowhUI.RegisterOwned(SECTION, {
    Apply    = NaowhUI.QoLStealthReposition,
    Teardown = Teardown,
    Reset    = function()
        Teardown()
        QoL.ClearDB(SECTION)
    end,
})

QoL.RegisterRefresh(SECTION, function()
    -- A settings change can retune the sound and flip which events are worth listening to.
    StopStanceSound()
    stanceSoundFired = false
    SyncEvents()
    UpdateBoth()
end)

QoL.OnSpecChanged(function()
    StopStanceSound()
    stanceSoundFired = false
    -- Spec-dependent (see WantedEvents), and the stealth flag may have gone stale while
    -- UPDATE_STEALTH was unregistered for the old spec.
    stealthed = IsStealthedNow()
    SyncEvents()
    UpdateBoth()
end)

QoL.OnZoneChanged(function()
    local was = inInstance
    inInstance = QoL.InDungeonOrRaid()
    if was ~= inInstance then UpdateBoth() end
end)

-- Entering or leaving Unlock Mode changes whether either reminder shows at all.
QoL.OnUnlockModeChanged(function() UpdateBoth() end)

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")

-- Registered only while something needs it, and only for the half that needs it. 3.3.5 has no
-- stealth or mount-display events: stealth and mounting both land as a player UNIT_AURA.
local function WantedEvents(t, out)
    wipe(out)
    local stealthOn = t.enabled and true or false
    local stanceOn  = t.stanceEnabled and true or false
    if QoL.HasNaowhQOL() or not (stealthOn or stanceOn) then return out end

    out.PLAYER_REGEN_DISABLED        = true   -- both halves gate on combat
    out.PLAYER_REGEN_ENABLED         = true
    out.UNIT_AURA                    = true   -- stealth, and both halves hide while mounted
    out.COMPANION_UPDATE             = true

    if stealthOn and IsStealthSpec() then out.UPDATE_SHAPESHIFT_FORM = true end
    if stanceOn  then out.UPDATE_SHAPESHIFT_FORM = true end

    if (stealthOn and t.groupOnly) then
        out.PARTY_MEMBERS_CHANGED = true
        out.RAID_ROSTER_UPDATE = true
    end
    if (stealthOn and t.disableWhenRested) or (stanceOn and t.stanceDisableWhenRested) then
        out.PLAYER_UPDATE_RESTING = true
    end
    return out
end

function SyncEvents()
    -- Re-read the world before touching registrations: events are only registered while something
    -- needs them, so anything that changed while a half was switched off was never seen.
    inCombat   = UnitAffectingCombat("player") and true or false
    stealthed  = IsStealthedNow()
    isResting  = IsResting() and true or false
    inInstance = QoL.InDungeonOrRaid()

    WantedEvents(DB(), wanted)
    for e in pairs(wanted) do
        if not registered[e] then registered[e] = true; ev:RegisterEvent(e) end
    end
    for e in pairs(registered) do
        if not wanted[e] then registered[e] = nil; ev:UnregisterEvent(e) end
    end
end

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "PLAYER_LOGOUT" then
        StopStanceSound()
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Reposition runs SyncEvents, which seeds the live state for us.
        NaowhUI.QoLStealthReposition()

        -- Unlock Mode assembles its element list once the suite has finished loading.
        C_Timer.After(2, function()
            QoL.RegisterMover({
                key      = "NaowhUI_StealthReminder",
                label    = "Stealth Reminder",
                order    = 110,
                db       = DB,
                apply    = NaowhUI.QoLStealthReposition,
                getFrame = function() BuildFrames(); return stealthFrame end,
                pointKey = "point", xKey = "x", yKey = "y",
                widthKey = "width", heightKey = "height",
                isHidden = function()
                    local t = DB()
                    return not t.enabled or QoL.HasNaowhQOL()
                end,
            })
            QoL.RegisterMover({
                key      = "NaowhUI_StanceReminder",
                label    = "Stance Reminder",
                order    = 120,
                db       = DB,
                apply    = NaowhUI.QoLStealthReposition,
                getFrame = function() BuildFrames(); return stanceFrame end,
                pointKey = "stancePoint", xKey = "stanceX", yKey = "stanceY",
                widthKey = "stanceWidth", heightKey = "stanceHeight",
                isHidden = function()
                    local t = DB()
                    return not t.stanceEnabled or QoL.HasNaowhQOL()
                end,
            })
        end)
        return
    end

    -- Routed, not broadcast: stealthing cannot change your stance, so running the other half's
    -- gate chain on the two noisiest events has no possible outcome.
    if event == "UPDATE_SHAPESHIFT_FORM" then
        -- A rogue's Stealth is a shapeshift slot on 3.3.5, so both halves listen here.
        stealthed = IsStealthedNow()
        UpdateBoth()
        return
    end

    if event == "UNIT_AURA" or event == "COMPANION_UPDATE" then
        local was = stealthed
        stealthed = IsStealthedNow()
        if was ~= stealthed then NaowhUI.QoLStealthUpdate() end
        -- Mounting is an aura too; both halves hide while mounted.
        local mounted = IsMounted() and true or false
        if mounted ~= (ev._mounted or false) then
            ev._mounted = mounted
            UpdateBoth()
        end
        return
    end

    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        NaowhUI.QoLStealthUpdate()   -- only the stealth half reads the roster
        return
    end

    -- The rest change something both halves gate on.
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_UPDATE_RESTING" then
        isResting = IsResting()
    end

    UpdateBoth()
end)
