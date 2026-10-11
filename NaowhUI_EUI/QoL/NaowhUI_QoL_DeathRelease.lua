-------------------------------------------------------------------------------
--  NaowhUI_QoL_DeathRelease.lua -- hold-to-release guard over Blizzard's release button.​‌​‌‌‌​‌‌‌​‌‌‌‌‌​​​‌‌‌​‌‌‌‌​‌‌​​‌​‌‌
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end
local QoL = NaowhUI.QoL
if not QoL then return end

local SECTION = "deathRelease"

local DEFAULTS = {
    enabled  = false,
    holdTime = 1.0,
}

local function DB() return QoL.DB(SECTION, DEFAULTS) end

-------------------------------------------------------------------------------
--  The blocker
-------------------------------------------------------------------------------
-- Parented to the release button and sized to it, so it covers the click target exactly.
local blocker, timerLabel
local pressStart, isReady = 0, false

-- Forward-declared: BuildBlocker wires the modifier handler, which is defined below it alongside
-- the tick it starts and stops.
local OnModifier

local function BuildBlocker(releaseBtn)
    if blocker then
        -- Blizzard recycles StaticPopup buttons, so the release button moves. Re-parent rather
        -- than build a second blocker, or they stack up one per death.
        if blocker:GetParent() ~= releaseBtn then
            blocker:SetParent(releaseBtn)
            blocker:ClearAllPoints()   -- the old points still name the previous button
            blocker:SetAllPoints()
        end
        return blocker
    end

    blocker = CreateFrame("Button", nil, releaseBtn)
    blocker:SetAllPoints()
    blocker:SetFrameStrata("DIALOG")
    blocker:EnableMouse(true)
    blocker:RegisterForClicks("AnyUp", "AnyDown")

    local bg = blocker:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.1, 0.1, 0.1, 0.85)

    timerLabel = blocker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerLabel:SetPoint("CENTER", 0, 0)
    timerLabel:SetTextColor(1, 0.65, 0)
    local fontFile, fontSize, fontFlags = timerLabel:GetFont()
    timerLabel:SetFont(fontFile, fontSize * 0.7, fontFlags)

    -- Swallows the click. Without this the button underneath still fires.
    blocker:SetScript("OnClick", function() end)
    blocker:SetScript("OnEvent", function(_, event, key, down) OnModifier(event, key, down) end)

    return blocker
end

local function Label(seconds)
    return ("Hold ALT %.1fs to release"):format(seconds)
end

-- Read once when the blocker arms, not per frame: it cannot change mid-hold.
local armedHold = 1.0

-- The label shows tenths, so the string is only rebuilt when the tenth moves.
local shownTenth

local function StopTick()
    if blocker then blocker:SetScript("OnUpdate", nil) end
end

-- Letting go restarts the hold; a half-finished hold must not carry over.
local function ResetHold()
    StopTick()
    pressStart = 0
    shownTenth = nil
    if timerLabel then timerLabel:SetText(Label(armedHold)) end
end

local function TickTimer()
    if isReady then
        blocker:Hide()
        return
    end

    -- Alt-tabbing takes the keyboard without a key-up arriving; a countdown that kept running
    -- would hand out a free release.
    if not IsAltKeyDown() then
        ResetHold()
        return
    end

    local left = armedHold - (GetTime() - pressStart)
    if left <= 0 then
        isReady = true
        StopTick()
        blocker:Hide()
        return
    end

    local tenth = math.floor(left * 10)
    if tenth ~= shownTenth then
        shownTenth = tenth
        timerLabel:SetText(Label(tenth / 10))
    end
end

local function StartTick()
    if pressStart ~= 0 then return end
    pressStart = GetTime()
    blocker:SetScript("OnUpdate", TickTimer)
end

-- The countdown only runs while ALT is down; otherwise the blocker polls every frame for as long
-- as the prompt is up.
function OnModifier(event, key, down)
    if event ~= "MODIFIER_STATE_CHANGED" then return end
    if key ~= "LALT" and key ~= "RALT" then return end
    if down == 1 then
        StartTick()
    elseif not IsAltKeyDown() then   -- the other ALT may still be held
        ResetHold()
    end
end

local function ClearState()
    pressStart, isReady = 0, false
    shownTenth = nil
    if blocker then
        blocker:SetScript("OnUpdate", nil)
        blocker:UnregisterEvent("MODIFIER_STATE_CHANGED")
        blocker:Hide()
    end
end

-------------------------------------------------------------------------------
--  Arming
-------------------------------------------------------------------------------
local function ActivateProtection()
    local t = DB()
    if not t.enabled or QoL.HasNaowhQOL() then return end

    -- Dungeons and raids only: releasing in the open world costs nothing.
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return end

    local visible, popup = StaticPopup_Visible("DEATH")
    if not visible or not popup then return end

    -- 3.3.5 popups have no GetButton; the buttons are named globals.
    local btn = popup.GetName and popup:GetName() and _G[popup:GetName() .. "Button1"]
    if not btn then return end

    BuildBlocker(btn)
    ClearState()
    armedHold = t.holdTime or 1.0
    timerLabel:SetText(Label(armedHold))
    blocker:Show()
    blocker:RegisterEvent("MODIFIER_STATE_CHANGED")

    -- Already holding ALT as you died: no key-down is coming, so start the count now.
    if IsAltKeyDown() then StartTick() end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
-- ActivateProtection re-checks every condition itself and no-ops unless the popup is up, so
-- this also covers switching the feature on while already dead.
local function Apply()
    if DB().enabled then ActivateProtection() else ClearState() end
end

NaowhUI.RegisterOwned(SECTION, {
    Apply    = Apply,
    Teardown = ClearState,
    Reset    = function()
        ClearState()
        QoL.ClearDB(SECTION)
    end,
})

QoL.RegisterRefresh(SECTION, Apply)

function NaowhUI.QoLDeathReleaseDB() return DB() end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
-- The popup is built during PLAYER_DEAD, not before it, so the button only exists a frame later.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("PLAYER_ALIVE")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_DEAD" then
        C_Timer.After(0.05, ActivateProtection)
    else
        ClearState()
    end
end)
