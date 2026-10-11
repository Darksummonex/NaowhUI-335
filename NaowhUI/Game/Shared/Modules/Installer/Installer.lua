--[[--------------------------------------------------------------------
    Standalone profile installer frame.

    Accepts the same installerTable format as ElvUI's PluginInstaller:

    installerTable = {
        Title = "Your Own Title",
        Name = "AddOnName",
        tutorialImage = "TexturePath",
        tutorialImageSize = {x, y},
        tutorialImagePoint = {xOffset, yOffset},
        tutorialImageVertexColor = {r, g, b},
        tutorialImage2 = "TexturePath",
        tutorialImage2Size = {x, y},
        tutorialImage2Point = {xOffset, yOffset},
        tutorialImage2VertexColor = {r, g, b},
        Pages = {function1, function2, ...},
        StepTitles = {"Title 1", "Title 2", ...},
        StepTitlesColor = {r, g, b},
        StepTitlesColorSelected = {r, g, b},
        StepTitleWidth = 140,
        StepTitleButtonWidth = 130,
        StepTitleTextJustification = "CENTER"
    }

    I:Queue(installerTable)

    The frame exposes the same fields the page functions use with
    ElvUI's installer (SubTitle, Desc1-4, Option1-4, Next, Prev, Status,
    side, pending, ...) and is reachable via I.frame.
--------------------------------------------------------------------]]--

local NUI = unpack(NaowhUI)
local I = NUI:GetModule("Installer")
local W = NaowhUI.Wrath

local abs, min = math.abs, math.min
local pairs, type, unpack = pairs, type, unpack
local tinsert, tremove, format = tinsert, tremove, format

local CreateFont = CreateFont
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local PlaySoundFile = PlaySoundFile
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local ColorTexture = W.ColorTexture

local LSM = LibStub("LibSharedMedia-3.0")

-- EllesmereUI style: dark panel, thin white borders at low alpha, green accent
local FONT = LSM:Fetch(LSM.MediaType.FONT, "Naowh")
local BLANK = "Interface\\Buttons\\WHITE8X8"
local ACCENT_R, ACCENT_G, ACCENT_B = 12/255, 210/255, 157/255
local BG_R, BG_G, BG_B = 0.06, 0.08, 0.10
local FRAME_BRD_A = 0.15
local WIDGET_BRD_A = 0.25
local TEXT_DIM_A = 0.65

local BUTTON_HEIGHT = 20
local f

local titleColor = {1, 1, 1}
local titleSelectedColor = {ACCENT_R, ACCENT_G, ACCENT_B}

I.Installs = {}

local function CreateBorder(parent, thickness, r, g, b, a)
    local edges = {}

    for i = 1, 4 do
        local edge = parent:CreateTexture(nil, "BORDER", nil, 7)

        if edge.SetSnapToPixelGrid then
            edge:SetSnapToPixelGrid(false)
            edge:SetTexelSnappingBias(0)
        end

        ColorTexture(edge, r, g, b, a)
        edges[i] = edge
    end

    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]

    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    right:SetWidth(thickness)

    return {
        SetColor = function(_, cr, cg, cb, ca)
            for _, edge in pairs(edges) do
                ColorTexture(edge, cr, cg, cb, ca or 1)
            end
        end
    }
end

local function UpdateButtonState(button)
    if button:IsEnabled() then
        button.border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    else
        button.border:SetColor(1, 1, 1, FRAME_BRD_A)
    end
end

local function Button_OnEnter(button)
    if button:IsEnabled() then
        button.border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        ColorTexture(button.bg, BG_R + 0.03, BG_G + 0.03, BG_B + 0.03, 0.98)
    end
end

local function Button_OnLeave(button)
    ColorTexture(button.bg, BG_R, BG_G, BG_B, 0.92)
    UpdateButtonState(button)
end

local function CreateInstallerButton(name, parent, width, height)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(width, height)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    ColorTexture(button.bg, BG_R, BG_G, BG_B, 0.92)
    button.border = CreateBorder(button, 1, ACCENT_R, ACCENT_G, ACCENT_B, 0.9)

    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetFontObject(I.fontNormal)
    button:SetFontString(text)
    button:SetNormalFontObject(I.fontNormal)
    button:SetHighlightFontObject(I.fontHighlight)
    button:SetDisabledFontObject(I.fontDisabled)

    button:SetScript("OnEnter", Button_OnEnter)
    button:SetScript("OnLeave", Button_OnLeave)
    hooksecurefunc(button, "Enable", UpdateButtonState)
    hooksecurefunc(button, "Disable", UpdateButtonState)

    return button
end

local function CreateDesc(anchor, offset)
    local desc = f:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, TEXT_DIM_A)

    if anchor then
        desc:SetPoint("TOP", anchor, "BOTTOM", 0, -20)
    else
        desc:SetPoint("TOPLEFT", 20, offset)
    end

    desc:SetWidth(f:GetWidth() - 40)

    return desc
end

function I:SetupReset()
    f.Next:Disable()
    f.Prev:Disable()
    f.Option1:Hide()
    f.Option1:SetScript("OnClick", nil)
    f.Option1:SetText("")
    f.Option1:ClearAllPoints()
    f.Option1:SetPoint("BOTTOM", 0, 45)
    f.Option2:Hide()
    f.Option2:SetScript("OnClick", nil)
    f.Option2:SetText("")
    f.Option2:ClearAllPoints()
    f.Option2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 45)
    f.Option3:Hide()
    f.Option3:SetScript("OnClick", nil)
    f.Option3:SetText("")
    f.Option3:ClearAllPoints()
    f.Option3:SetPoint("LEFT", f.Option2, "RIGHT", 4, 0)
    f.Option4:Hide()
    f.Option4:SetScript("OnClick", nil)
    f.Option4:SetText("")
    f.Option4:ClearAllPoints()
    f.Option4:SetPoint("LEFT", f.Option3, "RIGHT", 4, 0)
    f.SubTitle:SetText("")
    f.Desc1:SetText("")
    f.Desc2:SetText("")
    f.Desc3:SetText("")
    f.Desc4:SetText("")

    f:SetSize(550, 400)

    if f.StepTitles then
        for i = 1, #f.side.Lines do
            f.side.Lines[i].text:SetText("")
        end
    end
end

function I:SetPage(PageNum, PrevPage)
    I:SetupReset()

    f.Status.targetValue = PageNum
    f.CurrentPage = PageNum
    f.PrevPage = PrevPage

    W.SetEnabled(f.Next, PageNum ~= f.MaxPage)
    W.SetEnabled(f.Prev, PageNum ~= 1)

    f.Pages[f.CurrentPage]()
    f.Status.text:SetFormattedText("%d / %d", f.CurrentPage, f.MaxPage)

    if f.StepTitles then
        for i = 1, #f.side.Lines do
            local line, color = f.side.Lines[i]

            if i == f.CurrentPage then
                color = f.StepTitlesColorSelected or titleSelectedColor
                line.indicator:Show()
            else
                color = f.StepTitlesColor or titleColor
                line.indicator:Hide()
            end

            local StepTitleText

            if type(f.StepTitles[i]) == "function" then
                StepTitleText = f.StepTitles[i]()
            else
                StepTitleText = f.StepTitles[i]
            end

            line.text:SetText(StepTitleText)
            line.text:SetTextColor(color[1] or color.r, color[2] or color.g, color[3] or color.b)
        end
    end
end

function I:NextPage()
    if f.CurrentPage ~= f.MaxPage then
        f.CurrentPage = f.CurrentPage + 1
        I:SetPage(f.CurrentPage, f.CurrentPage - 1)
    end
end

function I:PreviousPage()
    if f.CurrentPage ~= 1 then
        f.CurrentPage = f.CurrentPage - 1
        I:SetPage(f.CurrentPage, f.CurrentPage + 1)
    end
end

function I:Button_OnClick()
    local id = self:GetID()

    if id and id <= f.MaxPage then
        I:SetPage(id, f.CurrentPage)
    end
end

function I:Pending_OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", -7)
    GameTooltip:AddLine("List of installations in queue:", 1, 1, 1)
    GameTooltip:AddLine(" ")

    for i = 1, #I.Installs do
        GameTooltip:AddDoubleLine(format("%d. %s", i, I.Installs[i].Name or UNKNOWN), i == 1 and format("|cff00FF00%s|r", "In Progress") or format("|cffFF0000%s|r", "Pending"))
    end

    GameTooltip:Show()
end

function I:Pending_OnLeave()
    GameTooltip:Hide()
end

function I:Frame_OnShow()
    if f.CurrentPage == 0 then
        I:NextPage()
    else
        f.Pages[f.CurrentPage]()
    end
end

function I:Frame_OnHide() end

function I:CreateStepComplete()
    local imsg = CreateFrame("Frame", "NaowhUIInstallStepComplete", UIParent)
    imsg:SetSize(418, 60)
    imsg:SetPoint("TOP", 0, -190)
    imsg:SetFrameStrata("TOOLTIP")
    imsg:Hide()

    imsg.bg = imsg:CreateTexture(nil, "BACKGROUND")
    imsg.bg:SetAllPoints()
    ColorTexture(imsg.bg, BG_R, BG_G, BG_B, 0.92)
    imsg.border = CreateBorder(imsg, 2, ACCENT_R, ACCENT_G, ACCENT_B, 0.9)

    imsg.text = imsg:CreateFontString(nil, "ARTWORK")
    imsg.text:SetFont(FONT, 18, "")
    imsg.text:SetPoint("CENTER")
    imsg.text:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    imsg.text:SetJustifyH("CENTER")

    imsg.anim = imsg:CreateAnimationGroup()
    imsg.anim.fade = imsg.anim:CreateAnimation("Alpha")
    imsg.anim.fade:SetChange(-1)
    imsg.anim.fade:SetStartDelay(2.5)
    imsg.anim.fade:SetDuration(1.5)
    imsg.anim:SetScript("OnFinished", function(anim)
        anim:GetParent():Hide()
    end)

    imsg:SetScript("OnShow", function(frame)
        if frame.message then
            PlaySoundFile([[Sound\Interface\LevelUp.wav]])
            frame.text:SetText(frame.message)
            frame:SetAlpha(1)
            frame.anim:Play()
            frame.message = nil
        else
            frame:Hide()
        end
    end)

    I.StepComplete = imsg
end

function I:CreateFrame()
    f = CreateFrame("Button", "NaowhUIInstallFrame", UIParent)
    f:SetSize(550, 400)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("TOOLTIP")
    f:SetScript("OnShow", I.Frame_OnShow)
    f:SetScript("OnHide", I.Frame_OnHide)
    f:SetPoint("CENTER")

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    ColorTexture(f.bg, BG_R, BG_G, BG_B, 1)
    f.border = CreateBorder(f, 2, 1, 1, 1, FRAME_BRD_A)

    I.fontNormal = CreateFont("NaowhUIInstallerFontNormal")
    I.fontNormal:SetFont(FONT, 15, "")
    I.fontNormal:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    I.fontHighlight = CreateFont("NaowhUIInstallerFontHighlight")
    I.fontHighlight:SetFont(FONT, 15, "")
    I.fontHighlight:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    I.fontDisabled = CreateFont("NaowhUIInstallerFontDisabled")
    I.fontDisabled:SetFont(FONT, 15, "")
    I.fontDisabled:SetTextColor(1, 1, 1, 0.25)

    f.MoveFrame = CreateFrame("Frame", nil, f)
    f.MoveFrame:SetSize(450, 50)
    f.MoveFrame:SetPoint("TOP", f, "TOP")
    f.MoveFrame:EnableMouse(true)
    f.MoveFrame:RegisterForDrag("LeftButton")
    f.MoveFrame:SetScript("OnDragStart", function() f:StartMoving() end)
    f.MoveFrame:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    f.Title = f:CreateFontString(nil, "OVERLAY")
    f.Title:SetFont(FONT, 20, "")
    f.Title:SetTextColor(1, 1, 1, 1)
    f.Title:SetPoint("TOP", 0, -12)

    f.Next = CreateInstallerButton("NaowhUIInstallNextButton", f, 110, 25)
    f.Next:SetPoint("BOTTOMRIGHT", -8, 8)
    f.Next:SetText(CONTINUE)
    f.Next:Disable()
    f.Next:SetScript("OnClick", I.NextPage)

    f.Prev = CreateInstallerButton("NaowhUIInstallPrevButton", f, 110, 25)
    f.Prev:SetPoint("BOTTOMLEFT", 8, 8)
    f.Prev:SetText(PREVIOUS)
    f.Prev:Disable()
    f.Prev:SetScript("OnClick", I.PreviousPage)

    local statusHolder = CreateFrame("Frame", nil, f)
    statusHolder:SetPoint("TOPLEFT", f.Prev, "TOPRIGHT", 6, 0)
    statusHolder:SetPoint("BOTTOMRIGHT", f.Next, "BOTTOMLEFT", -6, 0)
    statusHolder.bg = statusHolder:CreateTexture(nil, "BACKGROUND")
    statusHolder.bg:SetAllPoints()
    ColorTexture(statusHolder.bg, 0.075, 0.113, 0.141, 0.9)
    statusHolder.border = CreateBorder(statusHolder, 1, 1, 1, 1, WIDGET_BRD_A)

    f.Status = CreateFrame("StatusBar", "NaowhUIInstallStatus", statusHolder)
    f.Status:SetPoint("TOPLEFT", 1, -1)
    f.Status:SetPoint("BOTTOMRIGHT", -1, 1)
    f.Status:SetStatusBarTexture(BLANK)
    f.Status:SetStatusBarColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    f.Status.holder = statusHolder
    f.Status:SetScript("OnUpdate", function(bar, elapsed)
        local target = bar.targetValue

        if not target then
            return
        end

        local current = bar:GetValue()
        local diff = target - current

        if abs(diff) < 0.005 then
            bar:SetValue(target)
            bar.targetValue = nil
        else
            bar:SetValue(current + diff * min(elapsed * 10, 1))
        end
    end)

    f.Status.text = f.Status:CreateFontString(nil, "OVERLAY")
    f.Status.text:SetFont(FONT, 13, "")
    f.Status.text:SetTextColor(1, 1, 1, 0.9)
    f.Status.text:SetPoint("CENTER")

    f.Option1 = CreateInstallerButton("NaowhUIInstallOption1Button", f, 160, 30)
    f.Option1:SetPoint("BOTTOM", 0, 45)
    f.Option1:SetText("")
    f.Option1:Hide()

    f.Option2 = CreateInstallerButton("NaowhUIInstallOption2Button", f, 110, 30)
    f.Option2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 45)
    f.Option2:SetText("")
    f.Option2:Hide()
    f.Option2:SetScript("OnShow", function()
        f.Option1:SetWidth(110)
        f.Option1:ClearAllPoints()
        f.Option1:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 45)
    end)
    f.Option2:SetScript("OnHide", function()
        f.Option1:SetWidth(160)
        f.Option1:ClearAllPoints()
        f.Option1:SetPoint("BOTTOM", 0, 45)
    end)

    f.Option3 = CreateInstallerButton("NaowhUIInstallOption3Button", f, 100, 30)
    f.Option3:SetPoint("LEFT", f.Option2, "RIGHT", 4, 0)
    f.Option3:SetText("")
    f.Option3:Hide()
    f.Option3:SetScript("OnShow", function()
        f.Option1:SetWidth(100)
        f.Option1:ClearAllPoints()
        f.Option1:SetPoint("RIGHT", f.Option2, "LEFT", -4, 0)
        f.Option2:SetWidth(100)
        f.Option2:ClearAllPoints()
        f.Option2:SetPoint("BOTTOM", f, "BOTTOM", 0, 45)
    end)
    f.Option3:SetScript("OnHide", function()
        f.Option1:SetWidth(160)
        f.Option1:ClearAllPoints()
        f.Option1:SetPoint("BOTTOM", 0, 45)
        f.Option2:SetWidth(110)
        f.Option2:ClearAllPoints()
        f.Option2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 45)
    end)

    f.Option4 = CreateInstallerButton("NaowhUIInstallOption4Button", f, 100, 30)
    f.Option4:SetPoint("LEFT", f.Option3, "RIGHT", 4, 0)
    f.Option4:SetText("")
    f.Option4:Hide()
    f.Option4:SetScript("OnShow", function()
        f.Option1:SetWidth(100)
        f.Option2:SetWidth(100)
        f.Option1:ClearAllPoints()
        f.Option1:SetPoint("RIGHT", f.Option2, "LEFT", -4, 0)
        f.Option2:ClearAllPoints()
        f.Option2:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 45)
    end)
    f.Option4:SetScript("OnHide", function()
        f.Option1:SetWidth(160)
        f.Option1:ClearAllPoints()
        f.Option1:SetPoint("BOTTOM", 0, 45)
        f.Option2:SetWidth(110)
        f.Option2:ClearAllPoints()
        f.Option2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 45)
    end)

    f.SubTitle = f:CreateFontString(nil, "OVERLAY")
    f.SubTitle:SetFont(FONT, 16, "")
    f.SubTitle:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    f.SubTitle:SetPoint("TOP", 0, -42)

    f.Desc1 = CreateDesc(nil, -75)
    f.Desc2 = CreateDesc(f.Desc1)
    f.Desc3 = CreateDesc(f.Desc2)
    f.Desc4 = CreateDesc(f.Desc3)

    -- EllesmereUI popup close button: borderless top-right icon, alpha 0.4 -> 0.5 on hover
    local close = CreateFrame("Button", "NaowhUIInstallCloseButton", f)
    close:SetSize(25, 25)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -13, -12)
    close:SetFrameLevel(f:GetFrameLevel() + 5)

    close.icon = close:CreateTexture(nil, "ARTWORK")
    close.icon:SetAllPoints()
    close.icon:SetTexture([[Interface\AddOns\NaowhUI_Media\Shared\Textures\close-popup-4.tga]])

    if close.icon.SetSnapToPixelGrid then
        close.icon:SetSnapToPixelGrid(false)
        close.icon:SetTexelSnappingBias(0)
    end

    close.icon:SetAlpha(0.9)
    close:SetScript("OnEnter", function(button)
        button.icon:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B)
        button.icon:SetAlpha(1)
    end)
    close:SetScript("OnLeave", function(button)
        button.icon:SetVertexColor(1, 1, 1)
        button.icon:SetAlpha(0.9)
    end)
    close:SetScript("OnClick", I.CloseInstall)

    f.pending = CreateFrame("Frame", "NaowhUIInstallPendingButton", f)
    f.pending:SetSize(20, 20)
    f.pending:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    f.pending.bg = f.pending:CreateTexture(nil, "BACKGROUND")
    f.pending.bg:SetAllPoints()
    ColorTexture(f.pending.bg, 0.075, 0.113, 0.141, 0.9)
    f.pending.border = CreateBorder(f.pending, 1, 1, 1, 1, WIDGET_BRD_A)
    f.pending.tex = f.pending:CreateTexture(nil, "OVERLAY")
    f.pending.tex:SetPoint("TOPLEFT", f.pending, "TOPLEFT", 2, -2)
    f.pending.tex:SetPoint("BOTTOMRIGHT", f.pending, "BOTTOMRIGHT", -2, 2)
    f.pending.tex:SetTexture([[Interface\OptionsFrame\UI-OptionsFrame-NewFeatureIcon]])
    f.pending:SetScript("OnEnter", I.Pending_OnEnter)
    f.pending:SetScript("OnLeave", I.Pending_OnLeave)
    f.pending.flash = f.pending:CreateAnimationGroup()
    f.pending.flash:SetLooping("BOUNCE")
    f.pending.flash.fade = f.pending.flash:CreateAnimation("Alpha")
    f.pending.flash.fade:SetChange(-0.7)
    f.pending.flash.fade:SetDuration(0.5)

    f.tutorialImage = f:CreateTexture("NaowhUIInstallTutorialImage", "OVERLAY")
    f.tutorialImage2 = f:CreateTexture("NaowhUIInstallTutorialImage2", "OVERLAY")

    f.side = CreateFrame("Frame", "NaowhUIInstallTitleFrame", f)
    f.side:SetPoint("TOPLEFT", f, "TOPRIGHT", 3, 0)
    f.side:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 3, 0)
    f.side:SetWidth(140)
    f.side.bg = f.side:CreateTexture(nil, "BACKGROUND")
    f.side.bg:SetAllPoints()
    ColorTexture(f.side.bg, BG_R, BG_G, BG_B, 1)
    f.side.border = CreateBorder(f.side, 2, 1, 1, 1, FRAME_BRD_A)
    f.side.text = f.side:CreateFontString(nil, "OVERLAY")
    f.side.text:SetPoint("TOP", f.side, "TOP", 0, -8)
    f.side.text:SetFont(FONT, 18, "")
    f.side.text:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    f.side.text:SetText("Steps")
    f.side.Lines = {}
    f.side:Hide()

    for i = 1, 18 do
        local button = CreateFrame("Button", nil, f.side)

        if i == 1 then
            button:SetPoint("TOP", f.side.text, "BOTTOM", 0, -8)
        else
            button:SetPoint("TOP", f.side.Lines[i - 1], "BOTTOM")
        end

        button:SetHighlightTexture(BLANK)
        button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)

        -- EllesmereUI sidebar selection indicator: 3px accent line on the left edge
        button.indicator = button:CreateTexture(nil, "ARTWORK")
        ColorTexture(button.indicator, ACCENT_R, ACCENT_G, ACCENT_B, 1)

        if button.indicator.SetSnapToPixelGrid then
            button.indicator:SetSnapToPixelGrid(false)
            button.indicator:SetTexelSnappingBias(0)
        end

        button.indicator:SetWidth(3)
        button.indicator:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 0)
        button.indicator:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, 0)
        button.indicator:Hide()

        button.text = button:CreateFontString(nil, "OVERLAY")
        button.text:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -2)
        button.text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 2)
        button.text:SetFont(FONT, 13, "")
        button.text:SetText("")

        button:SetScript("OnClick", I.Button_OnClick)
        button:SetSize(130, BUTTON_HEIGHT)
        button:SetID(i)
        button:Hide()

        f.side.Lines[i] = button
    end

    f:Hide()

    I.frame = f
end

function I:Queue(installerTable)
    if not I.frame then
        I:CreateStepComplete()
        I:CreateFrame()
    end

    local addonIsQueued = false

    for _, v in pairs(I.Installs) do
        if v.Name == installerTable.Name then
            addonIsQueued = true
        end
    end

    if not addonIsQueued then
        tinsert(I.Installs, #I.Installs + 1, installerTable)
        I:RunInstall()
    end
end

function I:CloseInstall()
    tremove(I.Installs, 1)

    f:Hide()
    f.side:Hide()

    for i = 1, #f.side.Lines do
        local line = f.side.Lines[i]
        line.text:SetText("")
        line:Hide()
    end

    if #I.Installs > 0 then
        W.After(1, function() I:RunInstall() end)
    end
end

function I:RunInstall()
    local db = I.Installs[1]

    if db and not f:IsShown() then
        f.StepTitles = nil
        f.StepTitlesColor = nil
        f.StepTitlesColorSelected = nil

        f.Pages = db.Pages
        f.MaxPage = #f.Pages
        f.CurrentPage = 0

        f.Title:SetText(db.Title or format("%s Installation", NUI.title))
        f.Status:SetMinMaxValues(0, f.MaxPage)
        f.Status:SetValue(0)
        f.Status.text:SetFormattedText("%d / %d", f.CurrentPage, f.MaxPage)

        local LogoTop = db.tutorialImage or "Interface\\AddOns\\NaowhUI_Media\\Shared\\Textures\\LogoTop.tga"
        f.tutorialImage:SetTexture(LogoTop)
        f.tutorialImage:ClearAllPoints()

        if db.tutorialImageSize then
            f.tutorialImage:SetSize(db.tutorialImageSize[1], db.tutorialImageSize[2])
        else
            f.tutorialImage:SetSize(256, 128)
        end

        if db.tutorialImagePoint then
            f.tutorialImage:SetPoint("BOTTOM", db.tutorialImagePoint[1], 70 + db.tutorialImagePoint[2])
        else
            f.tutorialImage:SetPoint("BOTTOM", 0, 70)
        end

        if db.tutorialImageVertexColor then
            f.tutorialImage:SetVertexColor(unpack(db.tutorialImageVertexColor))
        else
            f.tutorialImage:SetVertexColor(1, 1, 1)
        end

        if db.tutorialImage2 then
            f.tutorialImage2:SetTexture(db.tutorialImage2)
            f.tutorialImage2:ClearAllPoints()

            if db.tutorialImage2Size then
                f.tutorialImage2:SetSize(db.tutorialImage2Size[1], db.tutorialImage2Size[2])
            else
                f.tutorialImage2:SetSize(256, 128)
            end

            if db.tutorialImage2Point then
                f.tutorialImage2:SetPoint("BOTTOM", db.tutorialImage2Point[1], 70 + db.tutorialImage2Point[2])
            else
                f.tutorialImage2:SetPoint("BOTTOM", 0, 70)
            end

            if db.tutorialImage2VertexColor then
                f.tutorialImage2:SetVertexColor(unpack(db.tutorialImage2VertexColor))
            else
                f.tutorialImage2:SetVertexColor(1, 1, 1)
            end

            f.tutorialImage2:Show()
        else
            f.tutorialImage2:Hide()
        end

        f:ClearAllPoints()
        f:SetPoint("CENTER")

        if db.StepTitles and #db.StepTitles == f.MaxPage then
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", -((db.StepTitleWidth or 140) * 0.5), 0)
            f.side:SetWidth(db.StepTitleWidth or 140)
            f.side:Show()

            for i = 1, #f.side.Lines do
                if db.StepTitles[i] then
                    local line = f.side.Lines[i]
                    line.text:SetJustifyH(db.StepTitleTextJustification or "CENTER")
                    line:SetWidth(db.StepTitleButtonWidth or 130)
                    line:Show()
                end
            end

            f.StepTitles = db.StepTitles
            f.StepTitlesColor = db.StepTitlesColor
            f.StepTitlesColorSelected = db.StepTitlesColorSelected
        end

        f:Show()
    end

    if #I.Installs > 1 then
        f.pending:Show()
        f.pending.flash:Play()
    else
        f.pending:Hide()
        f.pending.flash:Stop()
    end
end
