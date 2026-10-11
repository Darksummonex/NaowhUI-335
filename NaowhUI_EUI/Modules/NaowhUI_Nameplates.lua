-------------------------------------------------------------------------------
--  NaowhUI_Nameplates.lua -- target arrows: a left/right pair bracketing the target's plate,
--  pointing inward. While active they reversibly suppress EllesmereUI's own target arrows.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

local ARROW_TEX = "Interface\\AddOns\\NaowhUI_EUI\\media\\NaowhTarget.tga"

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
-- enabled defaults off: until the user opts in, showTargetArrows is left alone.
local DEFAULTS = {
    enabled   = false,
    size      = 32,
    offsetX   = 6,      -- gap to the plate; NEGATIVE pulls the arrows in over it
    tint      = false,  -- tint with the NaowhUI blue accent
    castNudge = true,   -- step outward while the target casts (like Blizzard's marker)
    castKick  = 8,      -- how far, added to offsetX
}

local function NDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.nameplates) ~= "table" then root.nameplates = {} end
    local t = root.nameplates
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

-------------------------------------------------------------------------------
--  Suppress EllesmereUI's own target arrows
-------------------------------------------------------------------------------
local function ApplyEUIArrowSuppression()
    local prof = NaowhUI.GetProfile and NaowhUI.GetProfile("EllesmereUINameplates")
    if not prof then return end
    local on = NDB().enabled

    -- Peek on the off path: Snap() would seed a record for a user who never turns the arrows on.
    local saved = on and NaowhUI.Snap("nameplates", "euiArrows")
                      or NaowhUI.PeekSnap("nameplates", "euiArrows")
    if not saved then return end

    if on then
        if saved.prev == nil then
            saved.prev = prof.showTargetArrows and true or false
        end
        if prof.showTargetArrows ~= false then
            prof.showTargetArrows = false
            if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
        end
    elseif saved.prev ~= nil then
        prof.showTargetArrows = saved.prev
        saved.prev = nil
        if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    end
end

-------------------------------------------------------------------------------
--  Arrows
-------------------------------------------------------------------------------
local arrow, texL, texR

-- The art is a chevron pointing right, so the left copy is used as-is and the right is mirrored,
-- giving  >  plate  <
local function EnsureArrow()
    if arrow then return arrow end
    arrow = CreateFrame("Frame", "NaowhUITargetArrow", UIParent)
    arrow:SetFrameStrata("HIGH")
    arrow:Hide()
    texL = arrow:CreateTexture(nil, "OVERLAY")
    texL:SetTexture(ARROW_TEX)
    texL:SetTexCoord(0, 1, 0, 1)
    texR = arrow:CreateTexture(nil, "OVERLAY")
    texR:SetTexture(ARROW_TEX)
    texR:SetTexCoord(1, 0, 0, 1)
    return arrow
end

local function TargetIsCasting()
    if not UnitExists("target") then return false end
    return (UnitCastingInfo("target") or UnitChannelInfo("target")) and true or false
end

-- Only the left arrow takes the cast kick; the right holds position, mirroring the base UI.
local function CurrentGaps(t)
    local base = t.offsetX or 0
    local left = base
    if t.castNudge and TargetIsCasting() then left = base + (t.castKick or 8) end
    return left, base
end

-- Early-outs on an unchanged gap: UNIT_SPELLCAST_SUCCEEDED fires on every instant cast.
local lastL, lastR
local function AnchorArrows(gapL, gapR)
    if gapL == lastL and gapR == lastR then return end
    lastL, lastR = gapL, gapR
    texL:ClearAllPoints()
    texR:ClearAllPoints()
    texL:SetPoint("RIGHT", arrow, "LEFT",  -gapL, 0)
    texR:SetPoint("LEFT",  arrow, "RIGHT",  gapR, 0)
end

local function LayoutArrows(t)
    texL:SetWidth(t.size); texL:SetHeight(t.size)
    texR:SetWidth(t.size); texR:SetHeight(t.size)
    AnchorArrows(CurrentGaps(t))
    local r, g, b = 1, 1, 1
    if t.tint then
        local c = NaowhUI.BLUE
        r, g, b = c.r, c.g, c.b
    end
    texL:SetVertexColor(r, g, b)
    texR:SetVertexColor(r, g, b)
end

local function RefreshArrowGap()
    if not (arrow and arrow:IsShown()) then return end
    AnchorArrows(CurrentGaps(NDB()))
end

-- 3.3.5 plates carry no unit: EllesmereUI Nameplates binds the target to one plate state (isTarget)
-- on its own update pass, so the arrow follows that state's styled bar.
local function TargetPlateState()
    local ns = _G.EllesmereNameplates_NS
    local states = ns and ns.plates
    if type(states) ~= "table" then return nil end
    for plate, s in pairs(states) do
        if type(s) == "table" and s.isTarget and not s.nameOnly and plate.IsShown and plate:IsShown()
            and s.root and s.root:IsShown() then
            return s
        end
    end
    return nil
end

local anchoredTo
local function UpdateTargetArrow()
    local t = NDB()
    if not t.enabled then
        if arrow then arrow:Hide() end
        anchoredTo = nil
        return
    end
    EnsureArrow()

    -- Unfriendly targets only: no arrows on friendly players/NPCs.
    local s = UnitExists("target") and UnitCanAttack("player", "target") and TargetPlateState()
    if not s then
        arrow:Hide()
        anchoredTo = nil
        return
    end

    local bar = s.health or s.root
    if anchoredTo ~= bar then
        anchoredTo = bar
        arrow:SetParent(s.root)
        arrow:SetFrameStrata("HIGH")
        arrow:ClearAllPoints()
        arrow:SetAllPoints(bar)
    end
    LayoutArrows(t)
    arrow:Show()
end

function NaowhUI.RefreshTargetArrow()
    ApplyEUIArrowSuppression()
    if arrow then LayoutArrows(NDB()) end
    UpdateTargetArrow()
    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end

if NaowhUI.RegisterPreset then
    NaowhUI.RegisterPreset(function()
        NDB().enabled = true
        NaowhUI.RefreshTargetArrow()
    end)
end

if NaowhUI.RegisterReapply then
    NaowhUI.RegisterReapply(NaowhUI.RefreshTargetArrow)
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
function NaowhUI.BuildNameplatesOptions(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    _, h = W:SectionHeader(parent, "TARGET ARROW", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Naowh Target Arrows",
          tooltip = "Marks your target with arrows either side of its nameplate. Replaces EllesmereUI's own target arrows; turn off to restore them.",
          getValue = function() return NDB().enabled end,
          setValue = function(v) NDB().enabled = v; NaowhUI.RefreshTargetArrow() end },
        { type = "toggle", text = "Tint with Accent (blue)",
          getValue = function() return NDB().tint end,
          setValue = function(v) NDB().tint = v; NaowhUI.RefreshTargetArrow() end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Arrow Size", min = 8, max = 32, step = 1,
          getValue = function() return NDB().size end,
          setValue = function(v) NDB().size = v; NaowhUI.RefreshTargetArrow() end },
        { type = "slider", text = "Side Gap", min = -30, max = 40, step = 1,
          tooltip = "How far the arrows sit from the nameplate. Negative values move them in over it.",
          getValue = function() return NDB().offsetX end,
          setValue = function(v) NDB().offsetX = v; NaowhUI.RefreshTargetArrow() end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Kick Out While Casting",
          tooltip = "Moves the left arrow out of the way of the cast bar while your target is casting.",
          getValue = function() return NDB().castNudge end,
          setValue = function(v) NDB().castNudge = v; NaowhUI.RefreshTargetArrow() end },
        { type = "slider", text = "Cast Kick", min = 0, max = 30, step = 1,
          tooltip = "How far the left arrow moves out while your target is casting.",
          getValue = function() return NDB().castKick or 8 end,
          setValue = function(v) NDB().castKick = v; NaowhUI.RefreshTargetArrow() end }
    ); y = y - h

    return math.abs(y)
end

-- Hand the arrows back before the wipe: the snapshot is the only record of showTargetArrows.
function NaowhUI.ResetNameplates()
    local saved = NaowhUI.PeekSnap("nameplates", "euiArrows")
    if saved and saved.prev ~= nil then
        NDB().enabled = false
        ApplyEUIArrowSuppression()
    end
    if arrow then arrow:Hide() end
    NaowhUI.SettingsRoot().nameplates = nil
    NaowhUI.RefreshTargetArrow()
end

function NaowhUI.HideTargetArrow()
    if arrow then arrow:Hide() end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
-- Cast events only change the GAP, so they take the cheap anchor-only path. 3.3.5 has no
-- RegisterUnitEvent, so the unit is filtered here.
local CAST_EVENTS = {
    UNIT_SPELLCAST_START         = true,
    UNIT_SPELLCAST_STOP          = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP  = true,
    UNIT_SPELLCAST_INTERRUPTED   = true,
    UNIT_SPELLCAST_FAILED        = true,
    UNIT_SPELLCAST_SUCCEEDED     = true,
}

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
for e in pairs(CAST_EVENTS) do ev:RegisterEvent(e) end
ev:RegisterEvent("UNIT_FACTION")   -- target flips friendly/hostile mid-fight

ev:SetScript("OnEvent", function(_, event, unit)
    if CAST_EVENTS[event] then
        if unit == "target" then RefreshArrowGap() end
        return
    end
    if event == "UNIT_FACTION" and unit ~= "target" then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ApplyEUIArrowSuppression()   -- EllesmereUINameplates has loaded by now
    end
    UpdateTargetArrow()
end)

-- No NAME_PLATE_UNIT_ADDED on 3.3.5: plates appear and the target binding settles on the
-- nameplate module's own pass, so the arrow is re-checked on a short poll while a target exists.
local POLL = 0.1
local elapsed = 0
ev:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL then return end
    elapsed = 0
    if not NDB().enabled then return end
    if UnitExists("target") or (arrow and arrow:IsShown()) then UpdateTargetArrow() end
end)
