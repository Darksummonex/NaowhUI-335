-------------------------------------------------------------------------------
--  NaowhUI_TopBar.lua -- [friends guild] [clock] [hearth]. A companion bar that sits alongside
--  EllesmereUI's DataBars. The hearth is a secure macro; friends and guild open the 3.3.5 Social
--  window (guild is a tab there, with no micro button of its own).
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

local BLUE = NaowhUI.BLUE

-------------------------------------------------------------------------------
--  Defaults / DB
-------------------------------------------------------------------------------
-- enabled defaults off; hideEUIFps is gated on it, so it stays inert until the bar is on.
local BAR_DEFAULTS = {
    enabled           = false,
    iconSize          = 18,
    buttonGap         = 4,
    edgeInset         = 14,
    use24h            = true,
    hideInCombat      = false,
    hideEUIFps        = true,
    bgAlpha           = 0.85,
    showSystem        = true,
    showSystemTooltip = true,
    sysSize           = 11,
    clockFont         = "__default",   -- sentinel: follow EllesmereUI's global font
    clockSize         = 20,
    baseHearthOnly    = false,
    -- hearthPool = { [key] = true } once curated in the picker; nil = every owned stone rolls.
    -- Flat keys, not a nested table: TDB's default-fill would hand out a live reference to
    -- BAR_DEFAULTS itself.
    iconR             = 1,
    iconG             = 1,
    iconB             = 1,
    -- pos = { point, relPoint, x, y } once moved in Unlock Mode; nil = default top-centre.
}

local function TDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.topBar) ~= "table" then root.topBar = {} end
    local t = root.topBar
    for k, v in pairs(BAR_DEFAULTS) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

local function IconRGB()
    local t = TDB()
    return t.iconR or 1, t.iconG or 1, t.iconB or 1
end

local CLOCK_PAD = 6   -- room above/below the clock inside its pill
local BTN_PAD   = 8   -- button footprint around the icon

local function BtnSize()
    return (TDB().iconSize or 18) + BTN_PAD
end

local function BarHeight()
    local t = TDB()
    return math.max((t.clockSize or 20) + CLOCK_PAD, BtnSize() + 2)
end

-------------------------------------------------------------------------------
--  Hearthstones:  left = the random rotation  |  right = the plain Hearthstone
-------------------------------------------------------------------------------
local BASE_HEARTH = 6948     -- plain Hearthstone, the universal fallback
local HEARTH_ICON = "Interface\\Icons\\INV_Misc_Rune_01"

-- Wrath has no toy box: these are bag items that return you to your bind point.
local HEARTH_POOL = {
    6948,    -- Hearthstone
    28585,   -- Ruby Slippers
    54452,   -- Ethereal Portal
    37118,   -- Scroll of Recall
    44314,   -- Scroll of Recall II
    44315,   -- Scroll of Recall III
}

-- Hearth-equivalents granted by a class rather than carried, so they only ever appear for the
-- characters that know them.
local HEARTH_SPELLS = {
    556,      -- Astral Recall (Shaman)
}

local _hearthId   -- the stone the left click will use; the tooltip reads its cooldown

local function UseMacro(id)
    return "/use item:" .. id
end

local function ItemName(id, fallback)
    local name = GetItemInfo(id)
    return name or fallback
end

local function ItemIcon(id)
    return (GetItemIcon and GetItemIcon(id)) or HEARTH_ICON
end

local function OwnsHearth(id)
    return (GetItemCount(id) or 0) > 0
end

-- Everything this character can hearth with. Spells carry a separate key prefix so an item and
-- an ability can never collide in the stored set. Unordered: only the picker cares, and this also
-- runs behind the tooltip's half-second refresh.
local function OwnedHearths()
    local out = {}
    for _, id in ipairs(HEARTH_POOL) do
        if OwnsHearth(id) then
            out[#out + 1] = {
                key = "i" .. id, id = id,
                name = ItemName(id, "Item " .. id), icon = ItemIcon(id),
            }
        end
    end
    for _, id in ipairs(HEARTH_SPELLS) do
        if IsPlayerSpell(id) then
            local name, _, icon = GetSpellInfo(id)
            out[#out + 1] = {
                key = "s" .. id, id = id, spell = true,
                name = name or ("Spell " .. id),
                icon = icon or HEARTH_ICON,
            }
        end
    end
    return out
end

-- No stored set means every owned stone rolls, so a new one joins without a visit to the picker.
-- A stored set is an explicit curation and is used as written.
local function InRotation(key)
    local pool = TDB().hearthPool
    if type(pool) ~= "table" then return true end
    return pool[key] == true
end

local function RotationEntries()
    local out = {}
    for _, e in ipairs(OwnedHearths()) do
        if InRotation(e.key) then out[#out + 1] = e end
    end
    return out
end

local function HearthMacro(id)
    _hearthId = id
    return UseMacro(id)
end

-- Left click: the plain stone when Base Hearthstone Only is on, else a roll of the rotation. An
-- empty rotation -- everything unchecked, or a character with nothing yet -- falls back to it too.
local function HearthResolve()
    if TDB().baseHearthOnly then return HearthMacro(BASE_HEARTH) end

    local pool = RotationEntries()
    if #pool == 0 then return HearthMacro(BASE_HEARTH) end

    local pick = pool[math.random(#pool)]
    if pick.spell then
        _hearthId = nil
        return "/cast " .. pick.name
    end
    return HearthMacro(pick.id)
end

-------------------------------------------------------------------------------
--  Elements
-------------------------------------------------------------------------------
-- White art with the detail cut out of the alpha, which is what makes it tintable.
local MEDIA = "Interface\\AddOns\\NaowhUI_EUI\\media\\"
local ICON = {
    friends = MEDIA .. "icon-friends.tga",
    guild   = MEDIA .. "icon-guild.tga",
    hearth  = MEDIA .. "icon-hearth.tga",
}

local TIP = {
    friends = "Friends",
    guild   = "Guild",
    hearth  = "Hearthstone",
}

-- Social window tab per element. FriendsFrame is not protected, so a plain button opens it.
local SOCIAL_TAB = {
    friends = 1,
    guild   = 3,
}

local LEFT_ORDER  = { "friends", "guild" }
local RIGHT_ORDER = { "hearth" }

-------------------------------------------------------------------------------
--  Bar
-------------------------------------------------------------------------------
local TopBar = {}

local bar, clockText, leftGroup, rightGroup
local buttons = {}

local FALLBACK_FONT = NaowhUI.FALLBACK_FONT

local function GetFont()
    return NaowhUI.FontPath()
end

-- Takes precedence over the saved setting, so hovering a dropdown entry previews it.
local _clockFontPreview

local function ClockFontPath()
    return NaowhUI.FontPath(_clockFontPreview or TDB().clockFont)
end

-- A FontString needs a valid font before SetText, or WoW throws "Font not set".
local function SetClockFont(size)
    if not clockText then return end
    if not clockText:SetFont(ClockFontPath(), size, "") then
        clockText:SetFont(FALLBACK_FONT, size, "")
    end
end

-- The client's own resting glyph (the player portrait's "zzz").
local REST_TEX = "Interface\\CharacterFrame\\UI-StateIcon"

-- Set when a fit is skipped for combat, so the ticker retries once it ends.
local _fitPending = false

-- Resizing re-anchors the secure children, which is protected in combat.
local function FitBarWidth()
    if not (bar and leftGroup and rightGroup and clockText) then return end
    if InCombatLockdown() then _fitPending = true; return end
    _fitPending = false
    local t = TDB()
    local gap = 22
    local clockW = math.max(24, (clockText:GetStringWidth() or 0) + 8)
    bar:SetWidth(math.max(120,
        t.edgeInset + leftGroup:GetWidth() + gap + clockW + gap + rightGroup:GetWidth() + t.edgeInset))
end

-- The bar parents secure buttons, so Hide() in combat is protected. A visibility state driver
-- does it from inside the secure environment instead. Called out of combat only.
local function ApplyBarVisibility()
    if not bar or InCombatLockdown() then return end
    local t = TDB()
    if t.enabled and t.hideInCombat then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        if t.enabled then bar:Show() else bar:Hide() end
    end
end

-- SetPoint re-anchors the secure children, so it is protected in combat.
local function ApplyBarPosition()
    if not bar or InCombatLockdown() then return end
    local p = TDB().pos
    bar:ClearAllPoints()
    if p then
        bar:SetPoint(p.point or "TOP", UIParent, p.relPoint or "TOP", p.x or 0, p.y or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, 0)
    end
end

-- Returns whether the time changed, so callers skip the re-fit on the other 59 ticks.
local function PaintClock()
    if not clockText then return false end
    local use24h = TDB().use24h
    local txt = date(use24h and "%H:%M" or "%I:%M %p")
    if not use24h then txt = txt:gsub("^0", "") end
    if txt == clockText._last then return false end
    clockText._last = txt
    clockText:SetText(txt)
    return true
end

-- Re-fits too: a different typeface changes the string width.
local function PreviewClockFont(name)
    if _clockFontPreview == name then return end
    _clockFontPreview = name
    SetClockFont(TDB().clockSize or 20)
    FitBarWidth()
end

local function UpdateResting()
    local rf = bar and bar._restFrame
    if not rf then return end
    if TDB().enabled and IsResting and IsResting() then rf:Show() else rf:Hide() end
end

-------------------------------------------------------------------------------
--  Live info
-------------------------------------------------------------------------------
local function BNetOnline()
    if not BNGetNumFriends then return 0 end
    local ok, _, online = pcall(BNGetNumFriends)
    return ok and tonumber(online) or 0
end

local function FriendsOnline()
    local _, wow = GetNumFriends()
    return BNetOnline() + (wow or 0)
end

-- 3.3.5 GetNumGuildMembers(true) counts the whole roster; online members are counted off it.
local function GuildOnline()
    if not IsInGuild() then return nil end
    local online = 0
    for i = 1, (GetNumGuildMembers(true) or 0) do
        if select(9, GetGuildRosterInfo(i)) then online = online + 1 end
    end
    return online
end

local function HearthCooldown()
    local id = _hearthId
    if not id then return nil end
    local start, dur = GetItemCooldown(id)
    if type(start) == "number" and type(dur) == "number" and dur > 0 then
        local rem = start + dur - GetTime()
        if rem > 0 then return rem end
    end
    return nil
end

local function FmtCD(sec)
    sec = math.floor(sec + 0.5)
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
    end
    return string.format("%d:%02d", sec / 60, sec % 60)
end

local function FpsRGB(fps)
    if fps >= 100 then return 0.25, 1, 0.25
    elseif fps >= 60 then return 0.55, 1, 0.25
    elseif fps >= 30 then return 1, 1, 0.25 end
    return 1, 0.35, 0.25
end

local function MsRGB(ms)
    if ms < 75 then return 0.25, 1, 0.25
    elseif ms < 150 then return 1, 1, 0.25 end
    return 1, 0.35, 0.25
end

-- Includes the "ff" alpha prefix, so the escape below is |c%s (not |cff%s).
local function Hex(r, g, b)
    return string.format("ff%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function AccentRGB()
    local EUI = _G.EllesmereUI
    if EUI and EUI.GetAccentColor then return EUI.GetAccentColor() end
    return BLUE.r, BLUE.g, BLUE.b
end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
-- Rosters read values that turn secret in combat / protected content; skip them there (the online
-- count still shows). InProtectedInstance is EllesmereUI's public helper -- absent means no gate.
local function RosterReadable()
    if InCombatLockdown() then return false end
    local EUI = _G.EllesmereUI
    return not (EUI and EUI.InProtectedInstance and EUI.InProtectedInstance())
end

local ROSTER_CAP = 40   -- keep a big guild's tooltip from running off the screen

-- 3.3.5 class tokens come back localized from the roster APIs; map them to RAID_CLASS_COLORS keys.
local CLASS_TOKEN
local function ClassColorByName(className)
    if not className then return nil end
    if not CLASS_TOKEN then
        CLASS_TOKEN = {}
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do CLASS_TOKEN[loc] = token end
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do CLASS_TOKEN[loc] = token end
    end
    local token = CLASS_TOKEN[className] or className:upper():gsub("%s", "")
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
end

-- Online WoW friends. GameTooltip rows are not clickable, so there is no whisper or invite here.
local function AddFriendsRoster()
    local shown, hidden = 0, 0
    for i = 1, (GetNumFriends() or 0) do
        local name, level, class, area, connected = GetFriendInfo(i)
        if connected then
            if shown < ROSTER_CAP then
                local cc = ClassColorByName(class)
                local r, g, b = 1, 1, 1
                if cc then r, g, b = cc.r, cc.g, cc.b end
                local left = name or "?"
                if level and level > 0 then left = left .. "  " .. level end
                GameTooltip:AddDoubleLine(left, area or "", r, g, b, 0.7, 0.7, 0.7)
            else hidden = hidden + 1 end
            shown = shown + 1
        end
    end
    if hidden > 0 then GameTooltip:AddLine(("... and %d more"):format(hidden), 0.5, 0.5, 0.5) end
    return shown
end

-- Guild name + online members, class-coloured. GuildRoster() answers async and is rate-limited.
local _lastGuildTipRoster = 0
local function AddGuildRoster()
    local now = GetTime()
    if GuildRoster and now - _lastGuildTipRoster >= 10 then _lastGuildTipRoster = now; GuildRoster() end
    local gname = GetGuildInfo("player")
    if gname then GameTooltip:AddLine(gname, 0.1, 1, 0.1) end
    local shown, hidden = 0, 0
    for i = 1, (GetNumGuildMembers(true) or 0) do
        local name, _, _, level, class, zone, _, _, isOnline, status, token = GetGuildRosterInfo(i)
        if isOnline then
            if shown < ROSTER_CAP then
                local cc = (token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]) or ClassColorByName(class)
                local r, g, b = 1, 1, 1
                if cc then r, g, b = cc.r, cc.g, cc.b end
                local cn = name and name:match("[^%-]+") or "?"
                local st = (status == "<AFK>" or status == 1) and "  |cff808080<AFK>|r"
                    or ((status == "<DND>" or status == 2) and "  |cff808080<DND>|r") or ""
                GameTooltip:AddDoubleLine((level and (level .. "  ") or "") .. cn .. st, zone or "", r, g, b, 0.7, 0.7, 0.7)
            else hidden = hidden + 1 end
            shown = shown + 1
        end
    end
    if hidden > 0 then GameTooltip:AddLine(("... and %d more"):format(hidden), 0.5, 0.5, 0.5) end
end

local function ShowElementTooltip(self)
    local key = self._key
    local ar, ag, ab = AccentRGB()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")

    if key == "friends" then
        GameTooltip:AddLine("Friends", 1, 1, 1)
        GameTooltip:AddDoubleLine("Online", tostring(FriendsOnline()), 0.7, 0.7, 0.7, 0.3, 1, 0.3)
        if RosterReadable() then
            GameTooltip:AddLine(" ")
            local ok, count = pcall(AddFriendsRoster)
            if ok and count == 0 then GameTooltip:AddLine("No friends online", 0.6, 0.6, 0.6) end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: open Friends", ar, ag, ab)
    elseif key == "guild" then
        GameTooltip:AddLine("Guild", 1, 1, 1)
        local n = GuildOnline()
        if n then
            GameTooltip:AddDoubleLine("Online", tostring(n), 0.7, 0.7, 0.7, 1, 0.6, 0.1)
            if RosterReadable() then
                GameTooltip:AddLine(" ")
                pcall(AddGuildRoster)
            end
        else
            GameTooltip:AddLine("Not in a guild", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: open Guild", ar, ag, ab)
    elseif key == "hearth" then
        GameTooltip:AddLine("Hearthstone", 1, 1, 1)
        local loc = GetBindLocation and GetBindLocation()
        if loc then GameTooltip:AddDoubleLine("Bind", loc, 0.7, 0.7, 0.7, 1, 1, 1) end
        local cd = HearthCooldown()
        if cd then GameTooltip:AddDoubleLine("Cooldown", FmtCD(cd), 0.7, 0.7, 0.7, 1, 0.3, 0.3)
        else GameTooltip:AddDoubleLine("Cooldown", "Ready", 0.7, 0.7, 0.7, 0.3, 1, 0.3) end
        GameTooltip:AddLine(" ")
        -- A rotation of one is a pin, so name it rather than calling it random.
        local pool = not TDB().baseHearthOnly and RotationEntries()
        if not pool or #pool == 0 then
            GameTooltip:AddLine("Left-click: " .. ItemName(BASE_HEARTH, "Hearthstone"), ar, ag, ab)
        elseif #pool == 1 then
            GameTooltip:AddLine("Left-click: " .. pool[1].name, ar, ag, ab)
        else
            GameTooltip:AddLine("Left-click: random Hearthstone", ar, ag, ab)
        end
        GameTooltip:AddLine("Right-click: " .. ItemName(BASE_HEARTH, "Hearthstone"), ar, ag, ab)
    else
        GameTooltip:AddLine(self._tipText or "", 1, 1, 1)
    end
    GameTooltip:Show()
end

-- The table is reused and the comparator hoisted, so a rescan allocates nothing.
local _memTable, _lastMemScan = {}, 0
local function ByMemDesc(a, b) return a.mem > b.mem end
local function ShowSystemTooltip(owner)
    local ar, ag, ab = AccentRGB()
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    local fps = math.floor(GetFramerate() + 0.5)
    -- 3.3.5 reports one latency (in, out, latency); there is no home/world split.
    local _, _, home = GetNetStats()
    home = home or 0
    GameTooltip:AddDoubleLine("FPS", fps .. " fps", 0.7, 0.7, 0.7, FpsRGB(fps))
    GameTooltip:AddDoubleLine("Latency", math.floor(home) .. " ms", 0.7, 0.7, 0.7, MsRGB(home))

    -- The memory scan is a frame spike, so rescan at most every 30s.
    local now = GetTime()
    if (now - _lastMemScan) >= 30 then
        _lastMemScan = now
        UpdateAddOnMemoryUsage()
        local count = 0
        for i = 1, C_AddOns.GetNumAddOns() do
            local mem = GetAddOnMemoryUsage(i)
            if mem and mem > 0 then
                count = count + 1
                local e = _memTable[count]
                if not e then e = {}; _memTable[count] = e end
                e.name = select(2, C_AddOns.GetAddOnInfo(i))
                e.mem  = mem
            end
        end
        for i = count + 1, #_memTable do _memTable[i] = nil end
        table.sort(_memTable, ByMemDesc)
    end
    if #_memTable > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Addon Memory", ar, ag, ab)
        for i = 1, math.min(10, #_memTable) do
            local e = _memTable[i]
            local ms = e.mem > 1024 and string.format("%.2f MB", e.mem / 1024) or string.format("%.0f KB", e.mem)
            GameTooltip:AddDoubleLine(e.name, ms, 1, 1, 1, ar, ag, ab)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: refresh    Shift+Left-click: collect garbage", ar, ag, ab)
    GameTooltip:Show()
end

-- `live` re-shows the tooltip while hovered (the hearth, so its cooldown ticks).
local function AttachTooltip(b, live)
    b:SetScript("OnEnter", function(self)
        -- OnLeave restores the configured tint, not white, or it would wipe the chosen colour.
        if self._icon then self._icon:SetVertexColor(AccentRGB()) end
        ShowElementTooltip(self)
        if live then
            self._ttT = 0
            self:SetScript("OnUpdate", function(s, e)
                s._ttT = s._ttT + e
                if s._ttT >= 0.5 then s._ttT = 0; ShowElementTooltip(s) end
            end)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self._icon then self._icon:SetVertexColor(IconRGB()) end
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
--  Updates
-------------------------------------------------------------------------------
local _lastRoster = 0
local function UpdateBadges()
    if not bar then return end   -- bar never built: don't even poll the guild roster
    local fb = buttons.friends
    if fb and fb._badge then
        local n = FriendsOnline()
        fb._badge:SetText((n and n > 0) and tostring(n) or "")
    end
    local gb = buttons.guild
    if gb and gb._badge then
        local n = GuildOnline()
        gb._badge:SetText((n and n > 0) and tostring(n) or "")
    end
    -- Request a fresh roster; it answers via GUILD_ROSTER_UPDATE, so throttle hard.
    if IsInGuild() and GuildRoster and not InCombatLockdown() then
        local now = GetTime()
        if (now - _lastRoster) >= 15 then _lastRoster = now; GuildRoster() end
    end
end

-- Below the bar while it is up; centred on it once it hides, which is where the clock sat.
-- SetPoint on sysBtn is unprotected (it parents nothing secure), so this is combat-safe.
local function AnchorSystem()
    local sysBtn = bar and bar._sysBtn
    if not sysBtn then return end
    sysBtn:ClearAllPoints()
    if bar:IsShown() then
        sysBtn:SetPoint("TOP", bar, "BOTTOM", 0, -2)
    else
        sysBtn:SetPoint("CENTER", bar, "CENTER", 0, 0)
    end
end

-- Runs while the bar is hidden in combat too: sysBtn is a sibling of the bar, not a child.
local _lastFps, _lastMs
local function UpdateSystemText()
    local sysBtn = bar and bar._sysBtn
    if not sysBtn then return end
    local t = TDB()
    if not (t.enabled and t.showSystem) then sysBtn:Hide(); return end

    local fps  = math.floor(GetFramerate() + 0.5)
    local home = math.floor(select(3, GetNetStats()) or 0)
    if fps == _lastFps and home == _lastMs and sysBtn:IsShown() then return end
    _lastFps, _lastMs = fps, home

    bar._sysText:SetText(string.format("FPS: |c%s%d|r  MS: |c%s%d|r",
        Hex(FpsRGB(fps)), fps, Hex(MsRGB(home)), home))
    sysBtn:Show()
    sysBtn:SetWidth(math.max(40, bar._sysText:GetStringWidth() + 10))
end

local function ApplyIconColor()
    local r, g, b = IconRGB()
    for _, btn in pairs(buttons) do
        if btn._icon then btn._icon:SetVertexColor(r, g, b) end
    end
end

-------------------------------------------------------------------------------
--  Element construction
-------------------------------------------------------------------------------
-- Parented straight to its final group: SetParent on a secure frame is blocked in combat, so
-- these can never be re-parented later.
local function CreateElement(key, container)
    local b = CreateFrame("Button", "NaowhUITopBar_" .. key, container,
        key == "hearth" and "SecureActionButtonTemplate" or nil)
    b:RegisterForClicks("AnyUp")

    -- No SetTexCoord trim: these glyphs are full-bleed, so it would clip them.
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON[key])
    icon:SetVertexColor(IconRGB())
    b._icon    = icon
    b._tipText = TIP[key]
    b._key     = key

    -- Centred on the icon, not the button: the button is padded, so it would drift off the glyph.
    if key == "friends" or key == "guild" then
        local badge = b:CreateFontString(nil, "OVERLAY")
        badge:SetFont(GetFont(), 10, "OUTLINE")
        badge:SetJustifyH("CENTER")
        badge:SetPoint("CENTER", icon, "BOTTOM", 0, 1)
        if key == "guild" then badge:SetTextColor(1, 0.62, 0.10) else badge:SetTextColor(0.30, 1, 0.30) end
        b._badge = badge
    end

    AttachTooltip(b, key == "hearth")
    buttons[key] = b
    return b
end

-- Out of combat only.
local function WireElement(key)
    local b = buttons[key]
    if not b then return end

    if key == "hearth" then
        -- Button-scoped attributes, so each click is separate.
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", HearthResolve())          -- left: random owned stone
        b:SetAttribute("*type2", "macro")
        b:SetAttribute("*macrotext2", UseMacro(BASE_HEARTH))   -- right: the plain Hearthstone
        b:EnableMouse(true)
        -- Re-resolve per click: the left re-rolls, and item names may not be cached at login.
        b:SetScript("PreClick", function(self)
            if InCombatLockdown() then return end
            self:SetAttribute("macrotext", HearthResolve())
        end)
        return
    end

    local tab = SOCIAL_TAB[key]
    if key == "guild" and not IsInGuild() then
        b:SetAlpha(0.35)
        b._tipText = TIP[key] .. " (not in a guild)"
    else
        b:SetAlpha(1)
        b._tipText = TIP[key]
    end
    b:EnableMouse(true)
    b:SetScript("OnClick", function()
        if ToggleFriendsFrame then ToggleFriendsFrame(tab) end
    end)
end

-- Out of combat only.
local function LayoutGroup(container, order, btnSize, gap, iconSize)
    if not container then return end
    local x = 0
    for _, key in ipairs(order) do
        local b = buttons[key]
        if b then
            b:SetSize(btnSize, btnSize)
            b:ClearAllPoints()
            b:SetPoint("LEFT", container, "LEFT", x, 0)
            b._icon:SetSize(iconSize, iconSize)
            x = x + btnSize + gap
        end
    end
    container:SetSize(math.max(1, x - gap), btnSize)
end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
function TopBar.Create()
    if bar then return bar end
    local t = TDB()

    bar = CreateFrame("Frame", "NaowhUITopBar", UIParent)
    bar:SetSize(360, BarHeight())
    bar:SetFrameStrata("MEDIUM")
    -- A saved pos is a raw pixel offset, so a UI-scale change can push the bar out of bounds,
    -- where Unlock Mode cannot grab it back.
    bar:SetClampedToScreen(true)
    ApplyBarPosition()

    -- Three dark pills with transparent gaps; the bar frame itself has no background.
    bar._segs, bar._segLines = {}, {}
    for i = 1, 3 do
        local seg = bar:CreateTexture(nil, "BACKGROUND")
        seg:SetColorTexture(0.03, 0.03, 0.04, t.bgAlpha)
        bar._segs[i] = seg
        local line = bar:CreateTexture(nil, "BORDER")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT",  seg, "BOTTOMLEFT",  0, 0)
        line:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 0, 0)
        bar._segLines[i] = line
    end
    bar._segL, bar._segC, bar._segR = bar._segs[1], bar._segs[2], bar._segs[3]

    local function ApplyAccent(r, g, b)
        r = r or BLUE.r; g = g or BLUE.g; b = b or BLUE.b
        for _, line in ipairs(bar._segLines) do line:SetColorTexture(r, g, b, 0.55) end
    end
    ApplyAccent(AccentRGB())
    local EUI = _G.EllesmereUI
    if EUI and EUI.RegAccent then
        EUI.RegAccent({ type = "callback", fn = ApplyAccent })
    end

    clockText = bar:CreateFontString(nil, "OVERLAY")
    SetClockFont(t.clockSize or 20)   -- must precede SetText
    clockText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    clockText:SetTextColor(1, 1, 1, 1)
    clockText:SetText("--:--")

    local clockBtn = CreateFrame("Button", nil, bar)
    clockBtn:SetSize(80, BarHeight())
    clockBtn:SetPoint("CENTER", clockText, "CENTER", 0, 0)
    clockBtn:SetScript("OnEnter", function(self)
        clockText:SetTextColor(AccentRGB())
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(date("%A, %B %d"), 1, 1, 1)
        GameTooltip:Show()
    end)
    clockBtn:SetScript("OnLeave", function()
        clockText:SetTextColor(1, 1, 1)
        GameTooltip:Hide()
    end)
    clockBtn:SetScript("OnClick", function()
        if ToggleCalendar then ToggleCalendar() end
    end)
    bar._clockBtn = clockBtn

    -- Resting "zzz", overlaid on the clock so it never affects width. Retail's animated flipbook
    -- is a Retail-only BLP; this is the client's static resting glyph.
    local restFrame = CreateFrame("Frame", nil, bar)
    restFrame:SetSize(14, 14)
    restFrame:SetPoint("CENTER", clockText, "TOPRIGHT", 5, 2)
    restFrame:Hide()
    local restIcon = restFrame:CreateTexture(nil, "OVERLAY")
    restIcon:SetAllPoints()
    restIcon:SetTexture(REST_TEX)
    restIcon:SetTexCoord(0, 0.5, 0, 0.421875)
    bar._restFrame = restFrame

    -- Parented to UIParent rather than the bar: Hide In Combat hides the bar, and a child would
    -- go with it. It still anchors to the bar -- an anchor resolves against a hidden frame fine.
    local sysBtn = CreateFrame("Button", nil, UIParent)
    sysBtn:SetSize(120, 14)
    sysBtn:RegisterForClicks("AnyUp")
    local sysText = sysBtn:CreateFontString(nil, "OVERLAY")
    sysText:SetPoint("CENTER")
    sysText:SetFont(GetFont(), TDB().sysSize or 11, "OUTLINE")
    bar._sysBtn, bar._sysText = sysBtn, sysText

    -- Hooked, so the readout follows whatever hides the bar, including the combat state driver.
    AnchorSystem()
    bar:HookScript("OnShow", AnchorSystem)
    bar:HookScript("OnHide", AnchorSystem)
    sysBtn:SetScript("OnEnter", function(self)
        if not TDB().showSystemTooltip then return end
        ShowSystemTooltip(self)
        self._ttT = 0
        self:SetScript("OnUpdate", function(s, e)
            s._ttT = s._ttT + e
            if s._ttT >= 1 then s._ttT = 0; ShowSystemTooltip(s) end
        end)
    end)
    sysBtn:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
    sysBtn:SetScript("OnClick", function(self)
        if IsShiftKeyDown() then collectgarbage("collect") end
        _lastMemScan = 0
        if TDB().showSystemTooltip and MouseIsOver(self) then ShowSystemTooltip(self) end
    end)

    leftGroup  = CreateFrame("Frame", nil, bar)
    rightGroup = CreateFrame("Frame", nil, bar)
    leftGroup:SetHeight(BtnSize())
    rightGroup:SetHeight(BtnSize())

    for _, key in ipairs(LEFT_ORDER)  do CreateElement(key, leftGroup)  end
    for _, key in ipairs(RIGHT_ORDER) do CreateElement(key, rightGroup) end

    -- Unlock Mode can build the bar while it is switched off, and that path never calls Apply.
    -- sysBtn is a sibling, so it needs hiding separately.
    if not t.enabled and not InCombatLockdown() then
        bar:Hide()
        bar._sysBtn:Hide()
    end

    return bar
end

-- Tied to `enabled`, not to the frame: Unlock Mode can construct a bar the user has switched off.
local ticker, badgeT = nil, 0
local function StartTicker()
    if ticker then return end
    badgeT = 0
    -- FPS/MS runs even while the bar is hidden in combat, hence before the IsShown gate.
    ticker = C_Timer.NewTicker(1, function()
        if not bar then return end
        UpdateSystemText()
        if not bar:IsShown() then return end
        if PaintClock() or _fitPending then FitBarWidth() end
        badgeT = badgeT + 1
        if badgeT >= 10 then badgeT = 0; UpdateBadges() end
    end)
end

local function StopTicker()
    if not ticker then return end
    ticker:Cancel()
    ticker = nil
end

function TopBar.Apply()
    if not bar then return end
    local t = TDB()

    -- Combat-safe first (textures / fontstrings / non-secure frames only).
    for _, seg in ipairs(bar._segs) do
        seg:SetColorTexture(0.03, 0.03, 0.04, t.bgAlpha)
    end
    SetClockFont(t.clockSize or 20)
    clockText._last = nil   -- force a repaint at the new font/size
    PaintClock()

    local sysSize = t.sysSize or 11
    bar._sysText:SetFont(GetFont(), sysSize, "OUTLINE")
    bar._sysBtn:SetHeight(sysSize + 3)
    _lastFps = nil   -- force a re-measure: the string width moved with the font
    AnchorSystem()
    UpdateSystemText()

    UpdateBadges()
    ApplyIconColor()

    if t.enabled then StartTicker() else StopTicker() end

    -- Everything below moves secure children or writes secure attributes: protected in combat.
    if InCombatLockdown() then
        if not TopBar._pendingApply then
            TopBar._pendingApply = true
            NaowhUI.RunOutOfCombat(function()
                TopBar._pendingApply = false
                TopBar.Apply()
            end)
        end
        return
    end

    local h = BarHeight()
    bar:SetHeight(h)
    bar._clockBtn:SetHeight(h)
    ApplyBarPosition()   -- re-asserts after a combat-deferred Apply
    ApplyBarVisibility()

    TopBar.ApplyEUIFpsSuppression()   -- via the table: defined below Apply

    for _, key in ipairs(LEFT_ORDER)  do WireElement(key) end
    for _, key in ipairs(RIGHT_ORDER) do WireElement(key) end

    local btnSize = BtnSize()
    LayoutGroup(leftGroup,  LEFT_ORDER,  btnSize, t.buttonGap, t.iconSize)
    LayoutGroup(rightGroup, RIGHT_ORDER, btnSize, t.buttonGap, t.iconSize)

    leftGroup:ClearAllPoints()
    leftGroup:SetPoint("LEFT", bar, "LEFT", t.edgeInset, 0)
    rightGroup:ClearAllPoints()
    rightGroup:SetPoint("RIGHT", bar, "RIGHT", -t.edgeInset, 0)

    -- Side pills hug their button groups; the centre pill spans the bar height.
    local SEG_PAD = 6
    bar._segL:ClearAllPoints()
    bar._segL:SetPoint("TOPLEFT",     leftGroup, "TOPLEFT",     -SEG_PAD, 0)
    bar._segL:SetPoint("BOTTOMRIGHT", leftGroup, "BOTTOMRIGHT",  SEG_PAD, 0)
    bar._segR:ClearAllPoints()
    bar._segR:SetPoint("TOPLEFT",     rightGroup, "TOPLEFT",     -SEG_PAD, 0)
    bar._segR:SetPoint("BOTTOMRIGHT", rightGroup, "BOTTOMRIGHT",  SEG_PAD, 0)
    bar._segC:ClearAllPoints()
    bar._segC:SetPoint("LEFT",   clockText, "LEFT",  -(SEG_PAD + 4), 0)
    bar._segC:SetPoint("RIGHT",  clockText, "RIGHT",  (SEG_PAD + 4), 0)
    bar._segC:SetPoint("TOP",    bar, "TOP",    0, 0)
    bar._segC:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

    bar._restFrame:SetSize(math.max(12, math.floor(h * 0.55 + 0.5)),
                           math.max(12, math.floor(h * 0.55 + 0.5)))

    FitBarWidth()
    UpdateResting()
end

-------------------------------------------------------------------------------
--  EllesmereUI FPS suppression
-------------------------------------------------------------------------------
-- EllesmereUI's QoL module has its own FPS/latency counter and the bar already shows one. The
-- 3.3.5 QoL keeps it in its profile as `fps`; QoLExtrasSet writes it and re-applies the module.
local function ApplyEUIFpsSuppression()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.QoLExtrasGet and EUI.QoLExtrasSet) then return end
    local t = TDB()
    local on = t.enabled and t.hideEUIFps

    -- Peek on the off path: Snap() would seed a record for a user who never turns the bar on.
    local saved = on and NaowhUI.Snap("topBar", "euiFps") or NaowhUI.PeekSnap("topBar", "euiFps")
    if not saved then return end

    if on then
        if saved.prev == nil then
            saved.prev = EUI.QoLExtrasGet("fps") and true or false
        end
        if EUI.QoLExtrasGet("fps") then
            pcall(EUI.QoLExtrasSet, "fps", false)
        end
    elseif saved.prev ~= nil then
        pcall(EUI.QoLExtrasSet, "fps", saved.prev)
        saved.prev = nil
    end

    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end
TopBar.ApplyEUIFpsSuppression = ApplyEUIFpsSuppression

if NaowhUI.RegisterReapply then
    -- A profile switch repoints our settings. The bar is lazy, so create it if the incoming
    -- profile turns it on.
    NaowhUI.RegisterReapply(function()
        if TDB().enabled and not bar then TopBar.Create() end
        if bar then TopBar.Apply() end
    end)
end

function TopBar.SetEnabled(v)
    TDB().enabled = v and true or false
    if TDB().enabled and not bar then TopBar.Create() end   -- built lazily; see Boot
    TopBar.Apply()
end

if NaowhUI.RegisterPreset then
    NaowhUI.RegisterPreset(function()
        local t = TDB()
        t.enabled, t.hideEUIFps = true, true
        if not bar then TopBar.Create() end
        TopBar.Apply()
    end)
end

-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
-- Unlock Mode accepts elements from any addon. Every hook is called with the KEY as its first
-- argument, not the element.
local function RegisterUnlock()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end

    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key   = "NaowhUI_TopBar",
            label = "NaowhUI Top Bar",
            group = "NaowhUI",
            order = 1,
            -- The bar auto-fits, so a resize handle would be overwritten by the next Apply.
            noResize = true,
            isHidden = function() return not TDB().enabled end,
            getFrame = function() return bar or TopBar.Create() end,
            getSize  = function()
                if not bar then return 360, BarHeight() end
                return bar:GetWidth(), bar:GetHeight()
            end,
            savePos = function(_, point, relPoint, x, y)
                TDB().pos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            -- Hand back a copy: unlock mode is free to keep or mutate what it is given.
            loadPos = function()
                local p = TDB().pos
                if not p then return nil end
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function() TDB().pos = nil end,
            applyPos = ApplyBarPosition,
        }),
    }, "NaowhUI_EUI")
end

-- Hand the FPS counter back first: its snapshot lives in the table being wiped.
function NaowhUI.ResetTopBar()
    local saved = NaowhUI.PeekSnap("topBar", "euiFps")
    if saved and saved.prev ~= nil then
        TDB().hideEUIFps = false
        ApplyEUIFpsSuppression()
    end
    NaowhUI.SettingsRoot().topBar = nil
    TopBar.Apply()   -- defaults put `enabled` back to false, hiding the bar
end

function NaowhUI.HideTopBar()
    StopTicker()
    if not bar then return end
    if InCombatLockdown() then return end   -- the bar parents secure buttons
    UnregisterStateDriver(bar, "visibility")
    bar:Hide()
    if bar._sysBtn then bar._sysBtn:Hide() end
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
-- values._menuOpts.onItemHover/.onItemLeave give a live font preview on hover. The menu is
-- built from `order` alone, so _menuOpts and _noLoc on `values` can't become phantom rows.
local function BuildClockFontDropdown()
    local values, order = NaowhUI.BuildFontValues()
    values._menuOpts = {
        onItemHover = function(key) PreviewClockFont(key) end,
        onItemLeave = function() PreviewClockFont(nil) end,
    }
    return values, order
end

-------------------------------------------------------------------------------
--  Hearthstone picker
-------------------------------------------------------------------------------
-- Our own panel in EllesmereUI's popup chrome. Its own list modals are spell-keyed all the way
-- down to the name lookups and the Add Spell ID box, and a hearthstone is mostly a toy.
local picker, pickerEntries

-- Storing an all-ticked set as no set at all keeps the default in place, and with it a toy bought
-- later, without another visit here.
local function SetHearthPool(pool)
    for _, e in ipairs(pickerEntries) do
        if not pool[e.key] then TDB().hearthPool = pool; return end
    end
    TDB().hearthPool = nil
end

local function BuildPicker()
    local EUI  = _G.EllesmereUI
    local font = GetFont()
    local PW, PH = 620, 430
    local ar, ag, ab = AccentRGB()

    -- Three cells across, filling left to right and growing down.
    local COLS, CELL_GAP, CELL_H, CELL_VGAP = 3, 8, 28, 4
    local CELL_W = math.floor((PW - 24 - (COLS - 1) * CELL_GAP) / COLS)

    local dimmer = CreateFrame("Frame", "NaowhUIHearthPicker", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)
    local dim = dimmer:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.25)

    local panel = CreateFrame("Frame", nil, dimmer)
    panel:SetSize(PW, PH)
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    panel:SetFrameLevel(dimmer:GetFrameLevel() + 2)
    if EUI.GetPopupScale then panel:SetScale(EUI.GetPopupScale()) end
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 0.98)
    if EUI.MakeBorder then EUI.MakeBorder(panel, 1, 1, 1, 0.22) end

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(font, 14, "")
    title:SetPoint("TOP", panel, "TOP", 0, -12)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText("Hearthstone Rotation")

    local hint = panel:CreateFontString(nil, "OVERLAY")
    hint:SetFont(font, 11, "")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -5)
    hint:SetWidth(PW - 32)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetText("Ticked hearthstones are rolled at random by the hearth button.")

    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -10)
    local closeTex = closeBtn:CreateTexture(nil, "OVERLAY")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons_335\\eui-close.tga")
    closeBtn:SetAlpha(0.5)
    closeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
    closeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    closeBtn:SetScript("OnClick", function() dimmer:Hide() end)

    local Refresh

    local function TextButton(w, h, text, onClick)
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(w, h)
        local bbg = b:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
        local brd = EUI.MakeBorder and EUI.MakeBorder(b, ar, ag, ab, 0.35)
        local lbl = b:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(font, 12, "")
        lbl:SetPoint("CENTER")
        lbl:SetTextColor(ar, ag, ab, 0.7)
        lbl:SetText(text)
        b:SetScript("OnEnter", function()
            lbl:SetTextColor(ar, ag, ab, 1)
            if brd then brd:SetColor(ar, ag, ab, 0.8) end
        end)
        b:SetScript("OnLeave", function()
            lbl:SetTextColor(ar, ag, ab, 0.7)
            if brd then brd:SetColor(ar, ag, ab, 0.35) end
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    local allBtn = TextButton(96, 24, "Tick All", function()
        TDB().hearthPool = nil
        Refresh()
    end)
    allBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -66)

    local noneBtn = TextButton(96, 24, "Untick All", function()
        TDB().hearthPool = {}
        Refresh()
    end)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -100)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 54)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(PW - 24)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxS = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxS, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)

    local doneBtn = TextButton(120, 30, "Done", function() dimmer:Hide() end)
    doneBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)

    local emptyLbl = child:CreateFontString(nil, "OVERLAY")
    emptyLbl:SetFont(font, 12, "")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -12)
    emptyLbl:SetTextColor(1, 1, 1, 0.35)
    emptyLbl:SetText("No hearthstones found.")

    local rows = {}

    Refresh = function()
        for i = 1, #rows do rows[i]:Hide() end
        NaowhUI.Shown(emptyLbl, #pickerEntries == 0)

        for i = 1, #pickerEntries do
            local entry = pickerEntries[i]
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, child)
                row:SetSize(CELL_W, CELL_H)
                row:SetPoint("TOPLEFT", child, "TOPLEFT",
                    ((i - 1) % COLS) * (CELL_W + CELL_GAP),
                    -math.floor((i - 1) / COLS) * (CELL_H + CELL_VGAP))
                row.hl = row:CreateTexture(nil, "BACKGROUND")
                row.hl:SetAllPoints()
                row.hl:SetColorTexture(1, 1, 1, 0)
                row.box = CreateFrame("Frame", nil, row)
                row.box:SetSize(16, 16)
                row.box:SetPoint("LEFT", row, "LEFT", 2, 0)
                local boxBg = row.box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                row.boxBrd = EUI.MakeBorder and EUI.MakeBorder(row.box, 0.4, 0.4, 0.4, 0.6)
                row.chk = row.box:CreateTexture(nil, "ARTWORK")
                row.chk:SetPoint("TOPLEFT", row.box, "TOPLEFT", 2, -2)
                row.chk:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -2, 2)
                row.chk:SetColorTexture(ar, ag, ab, 1)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.name = row:CreateFontString(nil, "OVERLAY")
                row.name:SetFont(font, 12, "")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.name:SetJustifyH("LEFT")
                if row.name.SetWordWrap then row.name:SetWordWrap(false) end
                -- The cell is too narrow for the longest stone names, so the real tooltip carries
                -- the full name and its cooldown.
                row:SetScript("OnEnter", function(self)
                    self.hl:SetColorTexture(1, 1, 1, 0.04)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink((self._spell and "spell:" or "item:") .. self._id)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.hl:SetColorTexture(1, 1, 1, 0)
                    GameTooltip:Hide()
                end)
                rows[i] = row
            end

            local on = InRotation(entry.key)
            row._id, row._spell = entry.id, entry.spell
            row.icon:SetTexture(entry.icon)
            row.icon:SetDesaturated(not on)
            row.icon:SetAlpha(on and 1 or 0.45)
            row.name:SetText(entry.name)
            row.name:SetTextColor(1, 1, 1, on and 0.9 or 0.45)
            NaowhUI.Shown(row.chk, on)
            if row.boxBrd then
                if on then row.boxBrd:SetColor(ar, ag, ab, 0.8)
                else row.boxBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
            end
            -- Written as the whole set: the stored table may not exist yet, and a row toggle has
            -- to leave every other stone where it was.
            row:SetScript("OnClick", function()
                local pool = {}
                for _, e in ipairs(pickerEntries) do pool[e.key] = InRotation(e.key) or nil end
                pool[entry.key] = (not on) or nil
                SetHearthPool(pool)
                Refresh()
            end)
            row:Show()
        end
        child:SetHeight(math.max(1, math.ceil(#pickerEntries / COLS) * (CELL_H + CELL_VGAP)))
    end

    if EUI.RegisterEscapeClose then EUI.RegisterEscapeClose(dimmer) end

    picker = dimmer
    picker._refresh = Refresh
    return picker
end

-- Rescanned on every open: cheap, and the toy names are often uncached on the first login.
local function ShowHearthPicker()
    if not _G.EllesmereUI then return end
    pickerEntries = OwnedHearths()
    table.sort(pickerEntries, function(a, b) return a.name < b.name end)
    local p = picker or BuildPicker()
    p._refresh()
    p:Show()
end

function NaowhUI.BuildTopBarOptions(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h, row

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    _, h = W:SectionHeader(parent, "NAOWHUI TOP BAR", y); y = y - h

    _, h = W:Toggle(parent, "Enable Top Bar", y,
        function() return TDB().enabled end,
        function(v) TopBar.SetEnabled(v); EUI:RefreshPage() end)
    y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "24-Hour Clock",
          getValue = function() return TDB().use24h end,
          setValue = function(v) TDB().use24h = v; TopBar.Apply() end },
        { type = "slider", text = "Bar Opacity (%)", min = 0, max = 100, step = 5,
          getValue = function() return math.floor((TDB().bgAlpha or 0.85) * 100 + 0.5) end,
          setValue = function(v) TDB().bgAlpha = v / 100; TopBar.Apply() end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Icon Size", min = 12, max = 32, step = 1,
          tooltip = "Size of the icons either side of the clock.",
          getValue = function() return TDB().iconSize end,
          setValue = function(v) TDB().iconSize = v; TopBar.Apply() end },
        { type = "slider", text = "Clock Size", min = 10, max = 36, step = 1,
          tooltip = "Size of the clock text.",
          getValue = function() return TDB().clockSize or 20 end,
          setValue = function(v) TDB().clockSize = v; TopBar.Apply() end }
    ); y = y - h

    local fontValues, fontOrder = BuildClockFontDropdown()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Clock Font",
          values = fontValues, order = fontOrder,
          getValue = function() return TDB().clockFont or "__default" end,
          -- The menu hides on click, so onItemLeave may never fire and would override the save.
          setValue = function(v)
              TDB().clockFont = v
              PreviewClockFont(nil)
              TopBar.Apply()
          end },
        { type = "colorpicker", text = "Icon Colour",
          getValue = function() local r, g, b = IconRGB(); return r, g, b, 1 end,
          setValue = function(r, g, b)
              local t = TDB()
              t.iconR, t.iconG, t.iconB = r, g, b
              ApplyIconColor()
          end }
    ); y = y - h

    _, h = W:Toggle(parent, "Hide Bar In Combat", y,
        function() return TDB().hideInCombat end,
        function(v) TDB().hideInCombat = v; TopBar.Apply() end,
        "Hides the bar while you are in combat. The FPS / MS readout stays visible.")
    y = y - h

    -- Escape hatch: a UI-scale change can strand a moved bar off-screen, out of Unlock Mode's reach.
    _, h = W:Button(parent, "Reset Bar Position", y, function()
        TDB().pos = nil
        NaowhUI.RunOutOfCombat(ApplyBarPosition)
    end)
    y = y - h

    _, h = W:SectionHeader(parent, "HEARTHSTONE", y); y = y - h

    local function baseOnly() return TDB().baseHearthOnly == true end

    row, h = W:DualRow(parent, y,
        -- No control of its own: the stones are ticked in the picker behind the gear.
        { type = "label", text = "Random Rotation",
          tooltip = "Which of your hearthstones the hearth button rolls between on a left click. Class abilities that hearth for you (Astral Recall) are listed alongside the items in your bags.",
          disabled = baseOnly,
          disabledTooltip = "Turn off Base Hearthstone Only to pick a stone." },
        { type = "toggle", text = "Base Hearthstone Only",
          tooltip = "Always use the plain Hearthstone, ignoring the other hearth items.",
          getValue = baseOnly,
          setValue = function(v)
              TDB().baseHearthOnly = v
              TopBar.Apply()
              EUI:RefreshPage()
          end }
    ); y = y - h

    NaowhUI.AttachPicker(row._leftRegion, ShowHearthPicker, baseOnly,
        "Base Hearthstone Only", "disabled")

    _, h = W:SectionHeader(parent, "FPS / MS", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show FPS / MS",
          getValue = function() return TDB().showSystem end,
          setValue = function(v) TDB().showSystem = v; TopBar.Apply() end },
        { type = "slider", text = "FPS / MS Size", min = 6, max = 24, step = 1,
          tooltip = "Size of the FPS / MS text.",
          getValue = function() return TDB().sysSize or 11 end,
          setValue = function(v) TDB().sysSize = v; TopBar.Apply() end }
    ); y = y - h

    _, h = W:Toggle(parent, "Show FPS / MS Tooltip", y,
        function() return TDB().showSystemTooltip end,
        function(v) TDB().showSystemTooltip = v end,
        "Shows FPS, latency and addon memory details when you hover the FPS / MS readout.")
    y = y - h

    _, h = W:Toggle(parent, "Hide EllesmereUI FPS / MS Counter", y,
        function() return TDB().hideEUIFps end,
        function(v) TDB().hideEUIFps = v; TopBar.Apply() end,
        "Hides EllesmereUI's own FPS counter so you don't see it twice.")
    y = y - h

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_UPDATE_RESTING")
boot:RegisterEvent("FRIENDLIST_UPDATE")
boot:RegisterEvent("GUILD_ROSTER_UPDATE")
boot:RegisterEvent("PLAYER_GUILD_UPDATE")
boot:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_UPDATE_RESTING" then
        UpdateResting()
        return
    end
    if event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        UpdateBadges()
        return
    end
    if event == "PLAYER_GUILD_UPDATE" then
        if bar then NaowhUI.RunOutOfCombat(function() WireElement("guild") end) end
        UpdateBadges()
        return
    end

    -- Lazy: an unused bar costs no frames, no secure buttons and no ticker.
    if bar or TDB().enabled then
        if not bar then TopBar.Create() end
        TopBar.Apply()
    end

    -- Registered even while the bar is off; the hooks cope with a bar that doesn't exist yet.
    if event == "PLAYER_LOGIN" then
        RegisterUnlock()
        -- Backstop: the menu can vanish without the cursor ever leaving an item.
        local EUI = _G.EllesmereUI
        if EUI and EUI.RegisterOnHide then
            EUI:RegisterOnHide(function() PreviewClockFont(nil) end)
        end
    end
end)
