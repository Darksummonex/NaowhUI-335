-------------------------------------------------------------------------------
--  NaowhUI_BlizzardSkin.lua ("Blizz UI") -- the skin's font and the character sheet's text size.
--
--  EllesmereUI keeps ONE font per module, and EllesmereUIBlizzardSkin reaches well past the
--  character sheet -- inspect sheet, socket panel, tooltips, every reskinned window -- so the font
--  cannot be scoped to a single frame.
--
--  3.3.5: the skin already draws 1px borders, so Retail's "Thin Borders" toggle has nothing to
--  thin, and the sheet has one text-size key (charSheetEnchantSize). The item-level text size
--  here only scales the sheet's title and level text.
-------------------------------------------------------------------------------
local NaowhUI = _G.NaowhUIEUI
if not NaowhUI then return end

-- EllesmereUI's skin only repositions these two, so they keep Blizzard's font unless we set it.
local CHROME = { "CharacterNameText", "CharacterLevelText" }

local ABSENT = NaowhUI.ABSENT

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
local BASE_TEXT_SIZE = 11
local DEFAULTS = { textSize = BASE_TEXT_SIZE }

local function BDB()
    local root = NaowhUI.SettingsRoot()
    if type(root.blizz) ~= "table" then root.blizz = {} end
    local t = root.blizz
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

-- The skin keeps its settings on the EllesmereUIDB global, not in a profile, so these snapshot
-- account-wide.
local function EUIDB()
    if not _G.EllesmereUIDB then _G.EllesmereUIDB = {} end
    return _G.EllesmereUIDB
end

local TEXT_SIZE_KEYS = { "charSheetEnchantSize" }

local function SkinNS()
    local EUI = _G.EllesmereUI
    return EUI and EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
end

-------------------------------------------------------------------------------
--  Font
-------------------------------------------------------------------------------
local FONT_FOLDER = "EllesmereUIBlizzardSkin"

local function CurrentSkinFont()
    local e = EllesmereUI.GetModuleFontEntry and EllesmereUI.GetModuleFontEntry("blizzardSkin")
    if e and e.font and e.font ~= "__global" then return e.font end
    return "__default"
end

-- Blizzard's original size per FontString, captured once before a scaled size is written back:
-- re-reading GetFont() later would compound the scale on every refresh.
local origSize = {}

local function ApplyChromeFont()
    local path  = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin")
    local scale = (BDB().textSize or BASE_TEXT_SIZE) / BASE_TEXT_SIZE

    for _, name in ipairs(CHROME) do
        local fs = _G[name]
        if fs and fs.GetFont then
            local cur, size, flags = fs:GetFont()
            if not origSize[name] then origSize[name] = size or 12 end
            local px = math.max(6, math.floor(origSize[name] * scale + 0.5))
            pcall(fs.SetFont, fs, path or cur, px, flags or "")
        end
    end
end

-- The font cache is keyed on the moduleFonts length, so a changed entry needs the cache flushed
-- and the skin re-run; the skin itself defers while in combat.
local function RefreshSkin()
    EllesmereUI._moduleFontCacheVer = -1
    if EllesmereUI._fontCacheDirty ~= nil then EllesmereUI._fontCacheDirty = true end
    local ns = SkinNS()
    if ns then
        if ns.RequestRefresh then pcall(ns.RequestRefresh) end
        if ns.Apply and not InCombatLockdown() then pcall(ns.Apply) end
    end
end

local function RefreshCharSheet()
    ApplyChromeFont()
end

local function ModuleFontEntry(fdb, create)
    fdb.moduleFonts = fdb.moduleFonts or {}
    for i, e in ipairs(fdb.moduleFonts) do
        if e.folder == FONT_FOLDER then return e, i end
    end
    if not create then return nil end
    -- The entry shape has to match EllesmereUI's: { folder, display, font, outline }.
    local e = { folder = FONT_FOLDER, display = "Blizz UI Enhanced", outline = "__global" }
    fdb.moduleFonts[#fdb.moduleFonts + 1] = e
    EllesmereUI._moduleFontCacheVer = -1   -- force the module-font cache to rebuild
    return e, #fdb.moduleFonts
end

-- Record whether the entry pre-existed: on reset ours is removed, theirs only has its font put back.
function NaowhUI.ApplySkinFont(name)
    local fdb = EllesmereUI.GetFontsDB and EllesmereUI.GetFontsDB()
    if not fdb then return end

    local saved = NaowhUI.SnapGlobal("font")
    if saved.had == nil then
        local existing = ModuleFontEntry(fdb, false)
        saved.had  = existing ~= nil
        saved.font = existing and existing.font or ABSENT
    end

    local entry = ModuleFontEntry(fdb, true)
    entry.font = (name == "__default") and "__global" or name

    RefreshSkin()
    RefreshCharSheet()
end

function NaowhUI.ApplyCharSheetTextSize(v)
    local d = EUIDB()
    local saved = NaowhUI.SnapGlobal("charSheet")
    for _, k in ipairs(TEXT_SIZE_KEYS) do
        if saved[k] == nil then
            if d[k] == nil then saved[k] = ABSENT else saved[k] = d[k] end
        end
    end

    BDB().textSize = v
    d.charSheetEnchantSize = math.max(6, math.min(16, v - 2))
    RefreshSkin()
    RefreshCharSheet()
end

-- Account-wide, so this runs once rather than per profile.
function NaowhUI.RestoreCharSheetGlobals()
    local d = EUIDB()

    local sizes = NaowhUI.PeekSnapGlobal("charSheet")
    if sizes then
        for _, k in ipairs(TEXT_SIZE_KEYS) do
            local prev = sizes[k]
            if prev ~= nil then d[k] = (prev ~= ABSENT) and prev or nil end
        end
        wipe(sizes)
    end

    -- `had` is the guard, not `font` itself: a second pass over an emptied snapshot must not read
    -- "we created the entry" and delete EllesmereUI's own.
    local font = NaowhUI.PeekSnapGlobal("font")
    local fdb  = EllesmereUI.GetFontsDB and EllesmereUI.GetFontsDB()
    if font and font.had ~= nil and fdb then
        local entry, idx = ModuleFontEntry(fdb, false)
        if entry then
            if font.had then
                entry.font = (font.font ~= ABSENT) and font.font or nil
            else
                table.remove(fdb.moduleFonts, idx)   -- it was ours; take it back out of their list
            end
            EllesmereUI._moduleFontCacheVer = -1
        end
        wipe(font)
    end
end

-- The sheet rebuilds its labels as it opens, so re-assert a frame later.
local charHooked = false
local function InstallCharSheetHook()
    if charHooked or not _G.CharacterFrame then return end
    charHooked = true
    _G.CharacterFrame:HookScript("OnShow", function()
        C_Timer.After(0, RefreshCharSheet)
    end)
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
function NaowhUI.BuildBlizzOptions(parent, yOffset)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local y   = yOffset
    local _, h

    if EUI.ClearContentHeader then EUI:ClearContentHeader() end

    _, h = W:SectionHeader(parent, "CHARACTER SHEET", y); y = y - h

    _, h = W:Slider(parent, "Text Size", y, 6, 20, 1,
        function() return BDB().textSize or BASE_TEXT_SIZE end,
        function(v) NaowhUI.ApplyCharSheetTextSize(v) end,
        "Size of the character sheet's name and level text, and of the enchant text on your gear.")
    y = y - h

    _, h = W:SectionHeader(parent, "ALL SKINNED FRAMES", y); y = y - h

    -- The NAME, not a path: EllesmereUI's module-font entry resolves it through LSM.
    local fontValues, fontOrder = NaowhUI.BuildFontValues()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font",
          values = fontValues, order = fontOrder,
          tooltip = "Font for every Blizzard frame the skin touches: the character and inspect "
            .. "sheets, the socket panel, the reskinned windows and your tooltips.",
          getValue = CurrentSkinFont,
          setValue = function(v) NaowhUI.ApplySkinFont(v) end },
        nil
    ); y = y - h

    return math.abs(y)
end

function NaowhUI.ResetBlizz()
    NaowhUI.RestoreCharSheetGlobals()
    NaowhUI.SettingsRoot().blizz = nil
    RefreshSkin()
    RefreshCharSheet()
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    InstallCharSheetHook()
    C_Timer.After(1.5, RefreshCharSheet)
end)
