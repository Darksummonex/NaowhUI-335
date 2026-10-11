-------------------------------------------------------------------------------
--  NaowhUI_QoL.lua -- the QoL page. Our three ports, then a second view onto EllesmereUI's own QoL
--  settings -- NOT an override: no snapshot, no reapply hook, untouched by reset and uninstall.
--  Proxy rows go through EllesmereUI's QoLExtrasGet/Set, which re-apply the QoL module.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end
local QoL = NaowhUI.QoL
if not QoL then return end

-------------------------------------------------------------------------------
--  Deep links
-------------------------------------------------------------------------------
-- Both steps and the deferral are required: ShowModule lands on the last page used, and SelectPage
-- bails unless activeModule is set. No combat guard needed -- ShowModule refuses.
local function DeepLink(folder, page)
    return function()
        local EUI = _G.EllesmereUI
        if not (EUI and EUI.ShowModule) then return end
        EUI:ShowModule(folder)
        if page and EUI.SelectPage then
            C_Timer.After(0, function() EUI:SelectPage(page) end)
        end
    end
end

-------------------------------------------------------------------------------
--  Shared dropdown data
-------------------------------------------------------------------------------
local NAME_FORMAT_VALUES = { full = "Full", abbreviated = "Abbreviated" }
local NAME_FORMAT_ORDER  = { "full", "abbreviated" }

-- 3.3.5 has no boss/role aura flags: "important" is every debuff not cast by a player.
local DEBUFF_FILTER_VALUES = {
    important   = "Boss & NPC Debuffs",
    all         = "All Debuffs",
    dispellable = "Dispellable by You",
}
local DEBUFF_FILTER_ORDER  = { "important", "all", "dispellable" }

local DEBUFF_POS_VALUES = {
    top = "Above", bottom = "Below", left = "Left", right = "Right",
    topleft = "Top Left", topright = "Top Right",
    bottomleft = "Bottom Left", bottomright = "Bottom Right", center = "Centre",
}
local DEBUFF_POS_ORDER = {
    "top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright", "center",
}

local DEBUFF_GROW_VALUES = { CENTER = "Centred", RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
local DEBUFF_GROW_ORDER  = { "CENTER", "RIGHT", "LEFT", "UP", "DOWN" }

-- Not memoised: a late-loading addon's fonts still appear. Two sound lists on purpose -- a proxied
-- setting must only offer keys its owner can resolve.
local fontValues, fontOrder, sndValues, sndOrder, euiSndValues, euiSndOrder
local texValues, texOrder
local glowValues, glowOrder

-- The suite's own glow styles, read from the engine rather than restated here, so a style
-- added there shows up in the picker without this list going stale.
local function BuildGlowData()
    local EUI = _G.EllesmereUI
    local styles = EUI and EUI.Glows and EUI.Glows.STYLES
    -- Empty rather than nil: the dropdown is built either way, and handing it nil tables
    -- moves the failure into the widget instead of showing an empty picker.
    if not styles then return {}, {} end
    local values, order = {}, {}
    for i = 1, #styles do
        values[i] = styles[i].name
        order[i] = i
    end
    return values, order
end

local function BuildDropdownData()
    fontValues, fontOrder       = QoL.FontValues()
    sndValues,  sndOrder        = QoL.SoundValues()
    euiSndValues, euiSndOrder   = QoL.EUISoundValues()
    texValues,  texOrder        = QoL.BarTextureValues()
    glowValues, glowOrder       = BuildGlowData()
end

-------------------------------------------------------------------------------
--  Inline cog
-------------------------------------------------------------------------------
-- EllesmereUI's own pattern for a dense page: the row carries the master toggle, and everything
-- that only matters once it is on lives behind a gear.
local function AttachCog(region, title, rows, isOff, offLabel, minWidth)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.BuildCogPopup) or EUI._prebuilding then return end
    if not (region and (region._lastInline or region._control)) then return end

    local _, show = EUI.BuildCogPopup({
        title = title, rows = rows, captureRegion = region, minWidth = minWidth,
    })

    local btn = CreateFrame("Button", nil, region)
    btn:SetSize(26, 26)
    btn:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -9, 0)
    region._lastInline = btn
    btn:SetFrameLevel(region:GetFrameLevel() + 5)

    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(EUI.COGS_ICON)
    btn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
    btn:SetScript("OnLeave", function(self) self:SetAlpha(isOff() and 0.15 or 0.4) end)
    btn:SetScript("OnClick", function(self) show(self) end)

    -- Swallows the click while the feature is off, and explains why on hover.
    local block = CreateFrame("Frame", nil, btn)
    block:SetAllPoints()
    block:SetFrameLevel(btn:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:SetScript("OnEnter", function()
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(btn, EUI.DisabledTooltip(offLabel)) end
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

-- Colour swatch inline on a row: it belongs with its toggle, not on a line of its own.
local function AttachSwatch(region, get, set, isOff, offLabel, hasAlpha)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.BuildColorSwatch) or EUI._prebuilding then return end
    if not (region and (region._lastInline or region._control)) then return end

    local swatch, update = EUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, get, set, hasAlpha, 20)
    swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -12, 0)
    region._lastInline = swatch

    local block = CreateFrame("Frame", nil, swatch)
    block:SetAllPoints()
    block:SetFrameLevel(swatch:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:SetScript("OnEnter", function()
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(swatch, EUI.DisabledTooltip(offLabel)) end
    end)
    block:SetScript("OnLeave", function()
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    local function Sync()
        local off = isOff()
        swatch:SetAlpha(off and 0.3 or 1)
        NaowhUI.Shown(block, off)
        update()
    end
    if EUI.RegisterWidgetRefresh then EUI.RegisterWidgetRefresh(Sync) end
    Sync()
end

-------------------------------------------------------------------------------
--  Ports
-------------------------------------------------------------------------------
local function Conflicted() return QoL.HasNaowhQOL() end
local CONFLICT_TIP = "NaowhQOL is installed and already provides this. Disable NaowhQOL to use the NaowhUI version."

-- Cog popups are sized off their slider and dropdown rows only, so a popup carrying an input row
-- has to be widened by hand or the box lands on top of its label.
local COG_W  = 300
local INPUT_W = 110

local function BuildPorts(parent, y, W)
    local EUI    = _G.EllesmereUI
    local death  = NaowhUI.QoLDeathReleaseDB
    local tank   = NaowhUI.QoLCoTankDB
    local hide   = NaowhUI.QoLStealthDB
    local _, h, row

    local function deathOff()  return Conflicted() or not death().enabled end
    local function tankOff()   return Conflicted() or not tank().enabled end
    local function tankDebuffOff() return tankOff() or not tank().debuffEnabled end
    local function stealthOff() return Conflicted() or not hide().enabled end
    local function stanceOff()  return Conflicted() or not hide().stanceEnabled end

    local function tankRefresh()   QoL.Refresh("coTank") end
    local function stealthRefresh() QoL.Refresh("stealth") end

    _, h = W:SectionHeader(parent, "NAOWHUI QOL", y); y = y - h

    ---------------------------------------------------------------------------
    --  Death release  |  Co-tank frame
    ---------------------------------------------------------------------------
    row, h = W:DualRow(parent, y,
        { type = "toggle", text = "Death Release Protection",
          tooltip = "Covers the release button when you die in a dungeon or raid, so a panic click cannot release you. Hold ALT to release.",
          disabled = Conflicted, disabledTooltip = CONFLICT_TIP, rawTooltip = true,
          getValue = function() return death().enabled end,
          setValue = function(v)
              death().enabled = v
              QoL.Refresh("deathRelease")
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end },
        { type = "toggle", text = "Co-Tank Frame",
          tooltip = "Shows the other tank's health while you are tanking a raid. Click it to target them. Move and resize it in EllesmereUI's Unlock Mode.",
          disabled = Conflicted, disabledTooltip = CONFLICT_TIP, rawTooltip = true,
          getValue = function() return tank().enabled end,
          setValue = function(v)
              tank().enabled = v
              tankRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end }
    ); y = y - h

    AttachCog(row._leftRegion, "Death Release Settings", {
        { type = "slider", label = "Hold Time (s)", min = 0.5, max = 3, step = 0.1,
          get = function() return death().holdTime end,
          set = function(v) death().holdTime = v end },
    }, deathOff, "Death Release Protection")

    AttachSwatch(row._rightRegion,
        function() local c = tank(); return c.healthColorR, c.healthColorG, c.healthColorB end,
        function(r, g, b)
            local c = tank()
            c.healthColorR, c.healthColorG, c.healthColorB = r, g, b
            tankRefresh()
        end,
        function() return tankOff() or tank().useClassColor end,
        "Health Bar Class Colour")

    AttachCog(row._rightRegion, "Co-Tank Frame Settings", {
        { type = "toggle", label = "Health Bar Class Colour",
          get = function() return tank().useClassColor end,
          -- RefreshPage too: this greys the swatch on the row behind, which the cog's own refresh
          -- does not reach.
          set = function(v)
              tank().useClassColor = v
              tankRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end },
        { type = "slider", label = "Background Opacity", min = 0, max = 100, step = 5,
          get = function() return math.floor((tank().bgAlpha or 0.6) * 100 + 0.5) end,
          set = function(v) tank().bgAlpha = v / 100; tankRefresh() end },
        { type = "dropdown", label = "Font", values = fontValues, order = fontOrder,
          get = function() return tank().font end,
          set = function(v) tank().font = v; tankRefresh() end },
        { type = "toggle", label = "Show Name",
          get = function() return tank().showName end,
          set = function(v) tank().showName = v; tankRefresh() end },
        { type = "dropdown", label = "Name Format", values = NAME_FORMAT_VALUES, order = NAME_FORMAT_ORDER,
          get = function() return tank().nameFormat end,
          set = function(v) tank().nameFormat = v; tankRefresh() end },
        { type = "slider", label = "Name Length", min = 3, max = 12, step = 1,
          get = function() return tank().nameLength end,
          set = function(v) tank().nameLength = v; tankRefresh() end },
        { type = "slider", label = "Name Font Size", min = 8, max = 24, step = 1,
          get = function() return tank().nameFontSize end,
          set = function(v) tank().nameFontSize = v; tankRefresh() end },
        { type = "toggle", label = "Name Class Colour",
          get = function() return tank().nameColorUseClassColor end,
          set = function(v) tank().nameColorUseClassColor = v; tankRefresh() end },
        { type = "colorpicker", label = "Name Colour",
          disabled = function() return tank().nameColorUseClassColor end,
          disabledTooltip = "Turn Name Class Colour off to pick a custom colour.", rawTooltip = true,
          get = function() local c = tank(); return c.nameColorR, c.nameColorG, c.nameColorB end,
          set = function(r, g, b)
              local c = tank()
              c.nameColorR, c.nameColorG, c.nameColorB = r, g, b
              tankRefresh()
          end },
        -- The same keys Unlock Mode's drag-resize writes, so the two stay in step.
        { type = "slider", label = "Width", min = 50, max = 400, step = 5,
          get = function() return tank().width end,
          set = function(v) tank().width = v; tankRefresh() end },
        { type = "slider", label = "Height", min = 10, max = 80, step = 1,
          get = function() return tank().height end,
          set = function(v) tank().height = v; tankRefresh() end },
        -- The frame is raid-and-tank-spec gated, so without this there is nowhere to dial it in.
        { type = "toggle", label = "Preview Outside Raid",
          tooltip = "Shows a stand-in bar so the frame can be placed and sized anywhere. The real co-tank replaces it as soon as there is one.",
          rawTooltip = true,
          get = function() return tank().preview end,
          set = function(v) tank().preview = v; tankRefresh() end },
    }, tankOff, "Co-Tank Frame", COG_W)

    ---------------------------------------------------------------------------
    --  Co-tank debuffs
    ---------------------------------------------------------------------------
    -- Its own row rather than more rows in the cog above: a second display with its own master
    -- toggle, which would be buried behind the frame's gear.
    row, h = W:DualRow(parent, y,
        { type = "toggle", text = "Co-Tank Debuffs",
          tooltip = "Shows the other tank's debuffs above their health bar -- tank-buster stacks, boss debuffs and anything you can dispel.",
          disabled = tankOff,
          disabledTooltip = function()
              if Conflicted() then return CONFLICT_TIP end
              return "Turn the Co-Tank Frame on first -- the debuffs hang off it."
          end, rawTooltip = true,
          getValue = function() return tank().debuffEnabled end,
          setValue = function(v)
              tank().debuffEnabled = v
              tankRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end },
        { type = "spacer" }
    ); y = y - h

    AttachCog(row._leftRegion, "Co-Tank Debuff Settings", {
        { type = "dropdown", label = "Filter", values = DEBUFF_FILTER_VALUES, order = DEBUFF_FILTER_ORDER,
          get = function() return tank().debuffFilter end,
          set = function(v) tank().debuffFilter = v; tankRefresh() end },
        { type = "slider", label = "Max Icons", min = 1, max = 8, step = 1,
          get = function() return tank().debuffCap end,
          set = function(v) tank().debuffCap = v; tankRefresh() end },
        { type = "slider", label = "Icon Size", min = 10, max = 48, step = 1,
          get = function() return tank().debuffSize end,
          set = function(v) tank().debuffSize = v; tankRefresh() end },
        { type = "slider", label = "Spacing", min = 0, max = 12, step = 1,
          get = function() return tank().debuffSpacing end,
          set = function(v) tank().debuffSpacing = v; tankRefresh() end },
        { type = "dropdown", label = "Position", values = DEBUFF_POS_VALUES, order = DEBUFF_POS_ORDER,
          get = function() return tank().debuffPosition end,
          set = function(v) tank().debuffPosition = v; tankRefresh() end },
        { type = "dropdown", label = "Grow", values = DEBUFF_GROW_VALUES, order = DEBUFF_GROW_ORDER,
          get = function() return tank().debuffGrow end,
          set = function(v) tank().debuffGrow = v; tankRefresh() end },
        { type = "slider", label = "Offset X", min = -200, max = 200, step = 1,
          get = function() return tank().debuffOffsetX end,
          set = function(v) tank().debuffOffsetX = v; tankRefresh() end },
        { type = "slider", label = "Offset Y", min = -200, max = 200, step = 1,
          get = function() return tank().debuffOffsetY end,
          set = function(v) tank().debuffOffsetY = v; tankRefresh() end },
        { type = "toggle", label = "Show Time Left",
          get = function() return tank().debuffShowDuration end,
          set = function(v) tank().debuffShowDuration = v; tankRefresh() end },
        { type = "slider", label = "Time Left Size", min = 6, max = 20, step = 1,
          disabled = function() return not tank().debuffShowDuration end,
          get = function() return tank().debuffDurSize end,
          set = function(v) tank().debuffDurSize = v; tankRefresh() end },
        { type = "toggle", label = "Show Stacks",
          get = function() return tank().debuffShowStacks end,
          set = function(v) tank().debuffShowStacks = v; tankRefresh() end },
        { type = "slider", label = "Stacks Size", min = 6, max = 20, step = 1,
          disabled = function() return not tank().debuffShowStacks end,
          get = function() return tank().debuffStackSize end,
          set = function(v) tank().debuffStackSize = v; tankRefresh() end },
        -- Off by default: the bar underneath is click-to-target.
        { type = "toggle", label = "Show Tooltips",
          get = function() return tank().debuffTooltips end,
          set = function(v) tank().debuffTooltips = v; tankRefresh() end },
    }, tankDebuffOff, "Co-Tank Debuffs", COG_W)

    ---------------------------------------------------------------------------
    --  Stealth reminder  |  Stance reminder
    ---------------------------------------------------------------------------
    row, h = W:DualRow(parent, y,
        { type = "toggle", text = "Stealth Reminder",
          tooltip = "A big on-screen reminder when you are not stealthed. Rogues always, druids for the specs you pick in the gear. Move and resize it in EllesmereUI's Unlock Mode.",
          disabled = Conflicted, disabledTooltip = CONFLICT_TIP, rawTooltip = true,
          getValue = function() return hide().enabled end,
          setValue = function(v)
              hide().enabled = v
              stealthRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end },
        { type = "toggle", text = "Stance / Form Reminder",
          tooltip = "Warns when you are in the wrong form, stance or aura -- or out of Shadowform. Move and resize it in EllesmereUI's Unlock Mode.",
          disabled = Conflicted, disabledTooltip = CONFLICT_TIP, rawTooltip = true,
          getValue = function() return hide().stanceEnabled end,
          setValue = function(v)
              hide().stanceEnabled = v
              stealthRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end }
    ); y = y - h

    -- The "not stealthed" colour gets the swatch; the rest live behind the gear.
    AttachSwatch(row._leftRegion,
        function() local c = hide(); return c.warningR, c.warningG, c.warningB end,
        function(r, g, b)
            local c = hide()
            c.warningR, c.warningG, c.warningB = r, g, b
            stealthRefresh()
        end,
        function() return stealthOff() or hide().warningUseClassColor end,
        "Stealth Reminder")

    local stealthRows = {
        { type = "input", label = "Not Stealthed Text", inputWidth = INPUT_W, commitOnBlur = true,
          get = function() return hide().warningText end,
          set = function(v) hide().warningText = v or ""; stealthRefresh() end },
        { type = "toggle", label = "Not Stealthed Class Colour",
          get = function() return hide().warningUseClassColor end,
          set = function(v)
              hide().warningUseClassColor = v
              stealthRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end },
        { type = "input", label = "Stealthed Text", inputWidth = INPUT_W, commitOnBlur = true,
          get = function() return hide().stealthText end,
          set = function(v) hide().stealthText = v or ""; stealthRefresh() end },
        { type = "colorpicker", label = "Stealthed Colour",
          disabled = function() return hide().stealthUseClassColor end,
          disabledTooltip = "Turn Stealthed Class Colour off to pick a custom colour.", rawTooltip = true,
          get = function() local c = hide(); return c.stealthR, c.stealthG, c.stealthB end,
          set = function(r, g, b)
              local c = hide()
              c.stealthR, c.stealthG, c.stealthB = r, g, b
              stealthRefresh()
          end },
        { type = "toggle", label = "Stealthed Class Colour",
          get = function() return hide().stealthUseClassColor end,
          set = function(v) hide().stealthUseClassColor = v; stealthRefresh() end },
        { type = "toggle", label = "Show While Stealthed",
          get = function() return hide().showStealthed end,
          set = function(v) hide().showStealthed = v; stealthRefresh() end },
        { type = "toggle", label = "Show While Not Stealthed",
          get = function() return hide().showNotStealthed end,
          set = function(v) hide().showNotStealthed = v; stealthRefresh() end },
        { type = "toggle", label = "Hide While Rested",
          get = function() return hide().disableWhenRested end,
          set = function(v) hide().disableWhenRested = v; stealthRefresh() end },
        { type = "toggle", label = "Only In a Group",
          get = function() return hide().groupOnly end,
          set = function(v) hide().groupOnly = v; stealthRefresh() end },
        { type = "dropdown", label = "Font", values = fontValues, order = fontOrder,
          get = function() return hide().font end,
          set = function(v) hide().font = v; stealthRefresh() end },
        -- Multiplies the size the box height implies, so a resize in Unlock Mode still scales the
        -- text. Stored 0-1, shown as a percentage.
        { type = "slider", label = "Text Scale", min = 50, max = 200, step = 5,
          get = function() return math.floor((hide().textScale or 1) * 100 + 0.5) end,
          set = function(v) hide().textScale = v / 100; stealthRefresh() end },
    }

    -- Feral is always on; Balance and Restoration are an opt-in. Absent for every other class.
    if QoL.ClassFile() == "DRUID" then
        stealthRows[#stealthRows + 1] = { type = "toggle", label = "Also Warn on Balance",
            get = function() return hide().enableBalance end,
            set = function(v) hide().enableBalance = v; stealthRefresh() end }
        stealthRows[#stealthRows + 1] = { type = "toggle", label = "Also Warn on Restoration",
            get = function() return hide().enableResto end,
            set = function(v) hide().enableResto = v; stealthRefresh() end }
    end

    AttachCog(row._leftRegion, "Stealth Reminder Settings", stealthRows, stealthOff,
        "Stealth Reminder", COG_W)

    AttachSwatch(row._rightRegion,
        function() local c = hide(); return c.stanceWarnR, c.stanceWarnG, c.stanceWarnB end,
        function(r, g, b)
            local c = hide()
            c.stanceWarnR, c.stanceWarnG, c.stanceWarnB = r, g, b
            stealthRefresh()
        end,
        function() return stanceOff() or hide().stanceWarnUseClassColor end,
        "Stance / Form Reminder")

    AttachCog(row._rightRegion, "Stance Reminder Settings", {
        { type = "input", label = "Warning Text", inputWidth = INPUT_W, commitOnBlur = true,
          get = function() return hide().stanceWarnText end,
          set = function(v) hide().stanceWarnText = v or ""; stealthRefresh() end },
        { type = "toggle", label = "Warning Class Colour",
          get = function() return hide().stanceWarnUseClassColor end,
          set = function(v)
              hide().stanceWarnUseClassColor = v
              stealthRefresh()
              if EUI and EUI.RefreshPage then EUI:RefreshPage() end
          end },
        { type = "dropdown", label = "Font", values = fontValues, order = fontOrder,
          get = function() return hide().stanceFont end,
          set = function(v) hide().stanceFont = v; stealthRefresh() end },
        { type = "slider", label = "Text Scale", min = 50, max = 200, step = 5,
          get = function() return math.floor((hide().stanceTextScale or 1) * 100 + 0.5) end,
          set = function(v) hide().stanceTextScale = v / 100; stealthRefresh() end },
        { type = "toggle", label = "Only In Combat",
          get = function() return hide().stanceCombatOnly end,
          set = function(v) hide().stanceCombatOnly = v; stealthRefresh() end },
        { type = "toggle", label = "Only In Dungeons & Raids",
          get = function() return hide().stanceInstanceOnly end,
          set = function(v) hide().stanceInstanceOnly = v; stealthRefresh() end },
        { type = "toggle", label = "Hide While Rested",
          get = function() return hide().stanceDisableWhenRested end,
          set = function(v) hide().stanceDisableWhenRested = v; stealthRefresh() end },
        { type = "toggle", label = "Play a Sound",
          get = function() return hide().stanceSoundEnabled end,
          set = function(v) hide().stanceSoundEnabled = v; stealthRefresh() end },
        { type = "dropdown", label = "Sound", values = sndValues, order = sndOrder,
          disabled = function() return not hide().stanceSoundEnabled end,
          get = function() return hide().stanceSound or QoL.SOUND_NONE end,
          set = function(v) hide().stanceSound = v; QoL.PlaySound(v); stealthRefresh() end },
        { type = "slider", label = "Repeat Every (s)", min = 0, max = 15, step = 1,
          disabled = function() return not hide().stanceSoundEnabled end,
          get = function() return hide().stanceSoundInterval end,
          set = function(v) hide().stanceSoundInterval = v; stealthRefresh() end },
    }, stanceOff, "Stance / Form Reminder", COG_W)


    return y
end

-------------------------------------------------------------------------------
--  Proxies onto EllesmereUI's QoL profile
-------------------------------------------------------------------------------
-- The 3.3.5 QoL module keeps every setting in its own profile and exposes QoLExtrasGet/Set,
-- whose setter re-applies the module. Without the module loaded these rows read as off and
-- write nothing.
local function QGet(k)
    local EUI = _G.EllesmereUI
    if EUI and EUI.QoLExtrasGet then return EUI.QoLExtrasGet(k) end
end

local function QSet(k, v)
    local EUI = _G.EllesmereUI
    if EUI and EUI.QoLExtrasSet then pcall(EUI.QoLExtrasSet, k, v) end
end

local function QoLMissing()
    local EUI = _G.EllesmereUI
    return not (EUI and EUI.QoLExtrasGet)
end
local QOL_MISSING_TIP = "EllesmereUI Quality of Life is not loaded."

local function QToggle(text, key, tooltip, after)
    return { type = "toggle", text = text, tooltip = tooltip,
        disabled = QoLMissing, disabledTooltip = QOL_MISSING_TIP, rawTooltip = true,
        getValue = function() return QGet(key) and true or false end,
        setValue = function(v)
            QSet(key, v)
            if after then after(v) end
        end }
end

local function RefreshPage()
    local EUI = _G.EllesmereUI
    if EUI and EUI.RefreshPage then EUI:RefreshPage() end
end

local function ColorGet(key, dr, dg, db)
    return function()
        local c = QGet(key)
        if type(c) == "table" then return c.r or dr, c.g or dg, c.b or db end
        return dr, dg, db
    end
end

local function ColorSet(key)
    return function(r, g, b) QSet(key, { r = r, g = g, b = b }) end
end

-------------------------------------------------------------------------------
--  Proxy -- loot & items
-------------------------------------------------------------------------------
local function BuildLootAndItems(parent, y, W)
    local _, h

    _, h = W:SectionHeader(parent, "LOOT & ITEMS", y); y = y - h

    _, h = W:DualRow(parent, y,
        QToggle("Quick Loot", "quickLoot",
            "Loots everything without opening the loot window. Hold Shift while looting to do it the normal way."),
        QToggle("Auto-Fill Delete Confirmation", "fillDelete",
            "Types DELETE for you when destroying a valuable item, so you can just press Enter.")
    ); y = y - h

    _, h = W:DualRow(parent, y,
        QToggle("Auto Repair", "autoRepair",
            "Automatically repair all gear when visiting a repair vendor.", RefreshPage),
        QToggle("Auto Sell Junk", "autoSellJunk",
            "Automatically sell all junk items when visiting a vendor.")
    ); y = y - h

    local repairGuild = QToggle("Repair From Guild Bank", "guildRepair",
        "Uses guild bank funds for repairs when they are available.")
    repairGuild.disabled = function() return QoLMissing() or not QGet("autoRepair") end
    repairGuild.disabledTooltip = function()
        if QoLMissing() then return QOL_MISSING_TIP end
        return "Turn Auto Repair on first."
    end
    _, h = W:DualRow(parent, y, repairGuild, { type = "spacer" }); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Proxy -- durability & alerts
-------------------------------------------------------------------------------
local function BuildDurabilityAndAlerts(parent, y, W)
    local _, h, row

    local function durOff() return QoLMissing() or not QGet("durability") end
    local function caOff()  return QoLMissing() or not QGet("combatAlert") end
    local function gdOff()  return QoLMissing() or not QGet("deathAlert") end

    _, h = W:SectionHeader(parent, "DURABILITY & ALERTS", y); y = y - h

    row, h = W:DualRow(parent, y,
        QToggle("Low Durability Warning", "durability",
            "Flashes a warning when a piece of your gear wears down past the level you set.", RefreshPage),
        QToggle("Combat Alert", "combatAlert",
            "Shows big text on screen as you go in and out of combat.", RefreshPage)
    ); y = y - h

    AttachSwatch(row._leftRegion, ColorGet("durabilityColor", 1, 0.27, 0.27), ColorSet("durabilityColor"),
        durOff, "Low Durability Warning")

    AttachCog(row._leftRegion, "Durability Settings", {
        { type = "slider", label = "Warn Below (%)", min = 5, max = 100, step = 1,
          get = function() return QGet("durabilityThreshold") or 40 end,
          set = function(v) QSet("durabilityThreshold", v) end },
        { type = "slider", label = "Text Size", min = 10, max = 50, step = 1,
          get = function() return QGet("durWarnTextSize") or 30 end,
          set = function(v) QSet("durWarnTextSize", v) end },
    }, durOff, "Low Durability Warning")

    AttachCog(row._rightRegion, "Combat Alert Settings", {
        { type = "dropdown", label = "Show On",
          values = { both = "Enter & Leave", enter = "Enter Only", leave = "Leave Only" },
          order = { "both", "enter", "leave" },
          get = function() return QGet("combatAlertMode") or "both" end,
          set = function(v) QSet("combatAlertMode", v) end },
        { type = "slider", label = "Text Size", min = 14, max = 64, step = 1,
          get = function() return QGet("combatAlertTextSize") or 22 end,
          set = function(v) QSet("combatAlertTextSize", v) end },
        { type = "input", label = "Enter Text", inputWidth = INPUT_W, commitOnBlur = true,
          get = function() return QGet("combatEnterText") or "+Combat" end,
          set = function(v) QSet("combatEnterText", v or "") end },
        { type = "colorpicker", label = "Enter Colour",
          disabled = function() return QGet("combatClassColor") end,
          disabledTooltip = "Class Colour is on for the combat alert.", rawTooltip = true,
          get = ColorGet("combatEnterColor", 1, 1, 1), set = ColorSet("combatEnterColor") },
        { type = "input", label = "Leave Text", inputWidth = INPUT_W, commitOnBlur = true,
          get = function() return QGet("combatLeaveText") or "-Combat" end,
          set = function(v) QSet("combatLeaveText", v or "") end },
        { type = "colorpicker", label = "Leave Colour",
          disabled = function() return QGet("combatClassColor") end,
          disabledTooltip = "Class Colour is on for the combat alert.", rawTooltip = true,
          get = ColorGet("combatLeaveColor", 1, 1, 1), set = ColorSet("combatLeaveColor") },
        { type = "toggle", label = "Class Colour",
          get = function() return QGet("combatClassColor") end,
          set = function(v) QSet("combatClassColor", v) end },
    }, caOff, "Combat Alert", COG_W)

    row, h = W:DualRow(parent, y,
        QToggle("Announce Group Deaths", "deathAlert",
            "Shows a big alert on screen whenever someone in your group dies.", RefreshPage),
        { type = "spacer" }
    ); y = y - h

    AttachCog(row._leftRegion, "Group Death Alert Settings", {
        { type = "slider", label = "Text Size", min = 14, max = 64, step = 1,
          get = function() return QGet("groupDeathTextSize") or 26 end,
          set = function(v) QSet("groupDeathTextSize", v) end },
        -- EllesmereUI's list, not ours: this key is theirs to resolve when the alert fires.
        { type = "dropdown", label = "Sound", values = euiSndValues, order = euiSndOrder,
          get = function() return QGet("deathSound") or QoL.SOUND_NONE end,
          set = function(v)
              QSet("deathSound", v)
              if v ~= QoL.SOUND_NONE then QoL.PlaySound(v, _G.EllesmereUI and _G.EllesmereUI._groupDeathSoundPaths) end
          end },
    }, gdOff, "Announce Group Deaths")

    return y
end

-------------------------------------------------------------------------------
--  Proxy -- UI clutter
-------------------------------------------------------------------------------
local function BuildUIClutter(parent, y, W)
    local _, h

    _, h = W:SectionHeader(parent, "UI CLUTTER", y); y = y - h

    _, h = W:DualRow(parent, y,
        QToggle("Hide Error Messages", "hideErrors",
            "Hides most of the red messages in the middle of your screen. Important ones still show."),
        QToggle("Hide Tutorial Pop-ups", "hideTutorials",
            "Hides Blizzard's tutorial popups.")
    ); y = y - h

    _, h = W:DualRow(parent, y,
        QToggle("Hide Screenshot Status", "hideScreenshot",
            "Hides the 'Screenshot saved' notification."),
        QToggle("Skip Cinematics", "skipCinematics",
            "Skips cutscenes and in-game movies wherever the game lets it.")
    ); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Proxy -- on-screen extras
-------------------------------------------------------------------------------
local function BuildScreenExtras(parent, y, W)
    local _, h
    local function fpsOff() return QoLMissing() or not QGet("fps") end
    local function sub(entry, offFn)
        entry.disabled = offFn
        entry.disabledTooltip = function()
            if QoLMissing() then return QOL_MISSING_TIP end
            return "Turn the FPS Counter on first."
        end
        return entry
    end

    _, h = W:SectionHeader(parent, "ON-SCREEN EXTRAS", y); y = y - h

    _, h = W:DualRow(parent, y,
        QToggle("FPS Counter", "fps", nil, RefreshPage),
        sub({ type = "slider", text = "FPS Text Size", min = 8, max = 30, step = 1,
              getValue = function() return QGet("fpsTextSize") or 12 end,
              setValue = function(v) QSet("fpsTextSize", v) end }, fpsOff)
    ); y = y - h

    _, h = W:DualRow(parent, y,
        sub({ type = "toggle", text = "Show Local MS",
              getValue = function() return QGet("fpsLocal") ~= false end,
              setValue = function(v) QSet("fpsLocal", v) end }, fpsOff),
        sub({ type = "toggle", text = "Show World MS",
              getValue = function() return QGet("fpsWorld") or false end,
              setValue = function(v) QSet("fpsWorld", v) end }, fpsOff)
    ); y = y - h

    _, h = W:DualRow(parent, y,
        sub({ type = "toggle", text = "Hide Local/World Label",
              getValue = function() return QGet("fpsLabels") == false end,
              setValue = function(v) QSet("fpsLabels", not v) end }, fpsOff),
        sub({ type = "slider", text = "FPS Update Interval", min = 1, max = 5, step = 1,
              getValue = function() return QGet("fpsInterval") or 1 end,
              setValue = function(v) QSet("fpsInterval", v) end }, fpsOff)
    ); y = y - h

    local extra = QToggle("Extra Stats", "statsExtra", "Adds hit, expertise and armour penetration to the stat display.")
    extra.disabled = function() return QoLMissing() or not QGet("stats") end
    _, h = W:DualRow(parent, y,
        QToggle("Stat Display", "stats", "Shows your crit and haste on screen.", RefreshPage),
        extra
    ); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Proxy -- instances
-------------------------------------------------------------------------------
local function BuildInstances(parent, y, W)
    local _, h

    _, h = W:SectionHeader(parent, "INSTANCES", y); y = y - h

    _, h = W:DualRow(parent, y,
        QToggle("Announce Instance Reset", "resetAnnounce",
            "Tells your group in chat once the instance has reset, so they know they can go back in.", RefreshPage),
        { type = "input", text = "Instance Reset Message", inputStyle = "popup", inputWidth = 240,
          placeholder = "Instances reset",
          disabled = function() return QoLMissing() or not QGet("resetAnnounce") end,
          getValue = function() return QGet("resetMessage") or "" end,
          setValue = function(v) QSet("resetMessage", v or "") end }
    ); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Deep links
-------------------------------------------------------------------------------
-- Anything owning a whole EllesmereUI page gets a button, not a rebuilt page.
local function BuildDeepLinks(parent, y, W)
    local _, h

    _, h = W:SectionHeader(parent, "CONFIGURED IN ELLESMEREUI", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Cursor Circle, GCD Ring & Cast Ring", buttonText = "Open", width = 120,
          onClick = DeepLink("EllesmereUIQoL", "Cursor") },
        { type = "labeledButton", text = "Crosshair", buttonText = "Open", width = 120,
          onClick = DeepLink("EllesmereUIQoL", "Displays") }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Rebirth & Sated Timers", buttonText = "Open", width = 120,
          onClick = DeepLink("EllesmereUIQoL", "Displays") },
        { type = "labeledButton", text = "Movement Cooldown", buttonText = "Open", width = 120,
          onClick = DeepLink("EllesmereUIQoL", "Displays") }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Consumable & Buff Reminders", buttonText = "Open", width = 120,
          onClick = DeepLink("EllesmereUIAuraBuffReminders", "Auras, Buffs & Consumables") },
        { type = "labeledButton", text = "Auto Accept & Turn In Quests", buttonText = "Open", width = 120,
          onClick = DeepLink("EllesmereUIQuestTracker", "Quest Tracker") }
    ); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
function NaowhUI.BuildQoLOptions(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    BuildDropdownData()   -- one font list and one sound list for the whole page

    -- Labels are single-line and ellipsize, so the long form goes in the hover.
    if Conflicted() then
        QoL.WarnConflict()
        _, h = W:DualRow(parent, y,
            { type = "label",
              text = "|cffffcc00NaowhQOL is installed -- the NaowhUI QoL features below are switched off.|r",
              tooltip = "NaowhQOL already provides death release protection, the co-tank frame and the "
                     .. "stealth reminder. Configure them in NaowhQOL, or disable NaowhQOL to use the "
                     .. "NaowhUI versions instead." }
        ); y = y - h
    end

    -- Gated on the port files having loaded, so a port erroring at load costs its section rather
    -- than the whole page.
    if NaowhUI.QoLDeathReleaseDB and NaowhUI.QoLCoTankDB and NaowhUI.QoLStealthDB then
        y = BuildPorts(parent, y, W)
    end

    y = BuildLootAndItems(parent, y, W)
    y = BuildDurabilityAndAlerts(parent, y, W)
    y = BuildUIClutter(parent, y, W)
    y = BuildScreenExtras(parent, y, W)
    y = BuildInstances(parent, y, W)
    y = BuildDeepLinks(parent, y, W)

    return math.abs(y)
end
