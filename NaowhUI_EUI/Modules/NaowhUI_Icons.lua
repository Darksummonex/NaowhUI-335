-------------------------------------------------------------------------------
--  NaowhUI_Icons.lua (ICONS section, General page) -- squares off the Cooldown Manager
--  bars + the unit-frame auras, with one zoom slider.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

-- EllesmereUI's "None" shape IS the plain square icon; "cropped" squashes it to 80% width. Their
-- "Square" is a custom MASK, costing a 10px button expansion and locking the bar to Shape Glow.
local SHAPE_SQUARE = "none"

-- Off by default: until the user asks for it, the icon shape is left at whatever they had.
local DEFAULTS = { square = false, zoom = 4 }

local function IDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.icons) ~= "table" then root.icons = {} end
    local t = root.icons
    t.cropped = nil   -- superseded by `square`; the snapshot hands the old shapes back
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

-- cdm: barKey -> { shape, zoom }.  uf: unitKey -> { bCrop, dCrop, bZoom, dZoom }.
local function CdmSnap() return NaowhUI.Snap("icons", "cdm") end
local function UfSnap()  return NaowhUI.Snap("icons", "uf")  end

local function Profile(folder)
    return NaowhUI.GetProfile and NaowhUI.GetProfile(folder) or nil
end

local UF_UNITS = NaowhUI.UF_UNITS

-------------------------------------------------------------------------------
--  Cooldown Manager
-------------------------------------------------------------------------------
-- The runtime holds these bars by reference (barDataByKey[key] = barData), so writes land.
-- _ECME_Apply is a full CDM rebuild, hence the check for a real change before firing it.
local function ApplyCDM(square, z)
    local bars = NaowhUI.CDMBars and NaowhUI.CDMBars()
    if not bars then return end

    -- Peek on the off path: Snap() would seed a record for a user who never turns this on.
    local saved = square and CdmSnap() or NaowhUI.PeekSnap("icons", "cdm")
    if not saved then return end
    local changed = false

    for i, bd in ipairs(bars) do
        local key = bd.key or ("#" .. i)
        local shape, zoom, touch
        if square then
            if saved[key] == nil then
                saved[key] = { shape = bd.iconShape, zoom = bd.iconZoom }
            end
            shape, zoom, touch = SHAPE_SQUARE, z, true
        elseif saved[key] ~= nil then
            shape, zoom, touch = saved[key].shape, saved[key].zoom, true
            saved[key] = nil
        end
        if touch and (bd.iconShape ~= shape or bd.iconZoom ~= zoom) then
            bd.iconShape, bd.iconZoom = shape, zoom
            changed = true
        end
    end

    if changed and _G._ECME_Apply then pcall(_G._ECME_Apply) end
end

local function RestoreCDM()
    local saved = NaowhUI.PeekSnap("icons", "cdm")
    if not saved then return end
    local bars = NaowhUI.CDMBars and NaowhUI.CDMBars()
    if bars then
        for i, bd in ipairs(bars) do
            local s = saved[bd.key or ("#" .. i)]
            if type(s) == "table" then bd.iconShape, bd.iconZoom = s.shape, s.zoom end
        end
    end
    wipe(saved)
    if _G._ECME_Apply then pcall(_G._ECME_Apply) end
end

-------------------------------------------------------------------------------
--  Unit-frame auras
-------------------------------------------------------------------------------
-- The auras have no shape enum: buff/debuffCropIcons off IS square (crop makes the icon 80% as tall
-- as it is wide). EllesmereUI defaults buff/debuffIconZoom to 0.07.
local function ApplyUF(square, z)
    local prof = Profile("EllesmereUIUnitFrames")
    if not prof then return end
    local saved = square and UfSnap() or NaowhUI.PeekSnap("icons", "uf")
    if not saved then return end
    local changed = false

    for _, unitKey in ipairs(UF_UNITS) do
        local u = prof[unitKey]
        if type(u) == "table" and (square or saved[unitKey] ~= nil) then
            local s = saved[unitKey]
            if s == nil then
                -- Raw values: the 3.3.5 unit frames ship no crop default, so absence must survive.
                s = { bCrop = u.buffCropIcons,
                      dCrop = u.debuffCropIcons,
                      bZoom = u.buffIconZoom, dZoom = u.debuffIconZoom }
                saved[unitKey] = s
            end
            local bC, dC, bZ, dZ
            if square then
                bC, dC, bZ, dZ = false, false, z, z
            else
                bC, dC, bZ, dZ = s.bCrop, s.dCrop, s.bZoom, s.dZoom
                saved[unitKey] = nil
            end
            if u.buffCropIcons ~= bC or u.debuffCropIcons ~= dC
               or u.buffIconZoom ~= bZ or u.debuffIconZoom ~= dZ then
                u.buffCropIcons, u.debuffCropIcons = bC, dC
                u.buffIconZoom,  u.debuffIconZoom  = bZ, dZ
                changed = true
            end
        end
    end

    if changed and _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
end

local function RestoreUF()
    local saved = NaowhUI.PeekSnap("icons", "uf")
    if not saved then return end
    local prof = Profile("EllesmereUIUnitFrames")
    if prof then
        for _, unitKey in ipairs(UF_UNITS) do
            local u, s = prof[unitKey], saved[unitKey]
            if type(u) == "table" and type(s) == "table" then
                u.buffCropIcons, u.debuffCropIcons = s.bCrop, s.dCrop
                u.buffIconZoom,  u.debuffIconZoom  = s.bZoom, s.dZoom
            end
        end
    end
    wipe(saved)
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
function NaowhUI.ApplyIconStyle()
    local t = IDB()
    local z = (t.zoom or 4) / 100
    ApplyCDM(t.square, z)
    ApplyUF(t.square, z)
    if NaowhUI.QueueSpecSync then NaowhUI.QueueSpecSync() end
end

-- Not in the preset: the NaowhUI look leaves whatever icon shape the user already had.
if NaowhUI.RegisterReapply then
    NaowhUI.RegisterReapply(NaowhUI.ApplyIconStyle)
end

-- Hand the shapes back before wiping the snapshots they come from.
function NaowhUI.ResetIcons()
    RestoreCDM()
    RestoreUF()
    NaowhUI.SettingsRoot().icons = nil
end

-------------------------------------------------------------------------------
--  Options section (rendered on the General page by NaowhUI_Core)
-------------------------------------------------------------------------------
function NaowhUI.BuildIconSection(parent, y)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "ICONS", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Square Icons",
          tooltip = "Gives the Cooldown Manager icons and unit frame buffs/debuffs a clean square shape. Turn off to restore their previous look.",
          getValue = function() return IDB().square end,
          setValue = function(v) IDB().square = v; NaowhUI.ApplyIconStyle() end },
        { type = "slider", text = "Icon Zoom", min = 0, max = 20, step = 1,
          tooltip = "Zooms into the icon artwork to trim off its built-in border.",
          getValue = function() return IDB().zoom or 4 end,
          setValue = function(v) IDB().zoom = v; NaowhUI.ApplyIconStyle() end }
    ); y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(1, NaowhUI.ApplyIconStyle)   -- once the CDM and unit frames have built
end)
