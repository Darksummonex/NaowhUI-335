local NUI = unpack(NaowhUI)
local I = NUI:GetModule("Installer")
local SE = NUI:GetModule("Setup")
local W = NaowhUI.Wrath

-- Classes with a Class WeakAura in NaowhUI_Data (Merfin's WotLK sets, D.<class>1440p / D.<class>1080p).
local WEAKAURA_CLASSES = {
    DEATHKNIGHT = true, DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
    ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true
}

local function WeakAurasBlocked()
    if not NUI:IsAddOnEnabled("WeakAuras") then

        return "Enable WeakAuras to unlock this step"
    elseif not SE.CanImportWeakAuras() then

        return "Your WeakAuras version cannot import Naowh's WeakAuras 5 strings"
    elseif not W.CanLoadAddOn("NaowhUI_Data") then

        return "Enable NaowhUI_Data to unlock this step"
    end
end

I.installer = {
    Title = "NaowhUI Installation",
    Name = "NaowhUI",
    tutorialImage = "Interface\\AddOns\\NaowhUI_Media\\Shared\\Textures\\LogoTop.tga",
    Pages = {
        [1] = function()
            NaowhUIInstallFrame.SubTitle:SetFormattedText("Welcome to %s", NUI.title)
            NaowhUIInstallFrame.Desc2:SetText("To start the installation process, click on 'Continue'")
            NaowhUIInstallFrame.Desc3:SetText("You can skip the steps you do not want")
        end,
        [2] = function()
            NaowhUIInstallFrame.SubTitle:SetText("EllesmereUI")

            if not NUI:IsAddOnEnabled("EllesmereUI") or not (EllesmereUI and EllesmereUI.ImportProfileInteractive) then
                NaowhUIInstallFrame.Desc2:SetText("Enable EllesmereUI to unlock this step")

                return
            end

            NaowhUIInstallFrame.Desc2:SetText("Select a resolution below to setup EllesmereUI")
            NaowhUIInstallFrame.Option1:Show()
            NaowhUIInstallFrame.Option1:SetScript("OnClick", function() SE:Setup("EllesmereUI", "1440p") end)
            NaowhUIInstallFrame.Option1:SetText("1440p")
            NaowhUIInstallFrame.Option2:Show()
            NaowhUIInstallFrame.Option2:SetScript("OnClick", function() SE:Setup("EllesmereUI", "1080p") end)
            NaowhUIInstallFrame.Option2:SetText("1080p")
        end,
        [3] = function()
            NaowhUIInstallFrame.SubTitle:SetText("General WeakAuras")

            local blocked = WeakAurasBlocked()

            if blocked then
                NaowhUIInstallFrame.Desc2:SetText(blocked)

                return
            end

            NaowhUIInstallFrame.Desc2:SetText("Click on the buttons representing the WeakAuras of your choice")
            NaowhUIInstallFrame.Desc3:SetText("These WeakAuras were made for TBC Classic, updated for 3.3.5a")
            NaowhUIInstallFrame.Option1:Show()
            NaowhUIInstallFrame.Option1:SetScript("OnClick", function() SE:Setup("WeakAuras", "core") end)
            NaowhUIInstallFrame.Option1:SetText("Core")
        end,
        [4] = function()
            local class = strlower(NUI.class)

            NaowhUIInstallFrame.SubTitle:SetText("Class WeakAura")

            local blocked = WeakAurasBlocked()

            if blocked then
                NaowhUIInstallFrame.Desc2:SetText(blocked)

                return
            elseif not WEAKAURA_CLASSES[NUI.class] then
                NaowhUIInstallFrame.Desc2:SetFormattedText("There is no Class WeakAura for %s%s|r", W.ClassHex(NUI.class), NUI.localizedClass)

                return
            end

            NaowhUIInstallFrame.Desc2:SetText("Select a resolution below to import your Class WeakAura")
            NaowhUIInstallFrame.Desc3:SetFormattedText("Your class: %s%s%s", W.ClassHex(NUI.class), NUI.localizedClass, "|r")
            NaowhUIInstallFrame.Option1:Show()
            NaowhUIInstallFrame.Option1:SetScript("OnClick", function() SE:Setup("WeakAuras", class .. "1440p") end)
            NaowhUIInstallFrame.Option1:SetText("1440p")
            NaowhUIInstallFrame.Option2:Show()
            NaowhUIInstallFrame.Option2:SetScript("OnClick", function() SE:Setup("WeakAuras", class .. "1080p") end)
            NaowhUIInstallFrame.Option2:SetText("1080p")
        end,
        [5] = function()
            NaowhUIInstallFrame.SubTitle:SetText("Installation Complete")
            NaowhUIInstallFrame.Desc2:SetText("You have completed the installation process")
            NaowhUIInstallFrame.Desc3:SetText("Please click on 'Reload' to reload your UI")
            NaowhUIInstallFrame.Option1:Show()
            NaowhUIInstallFrame.Option1:SetScript("OnClick", function() ReloadUI() end)
            NaowhUIInstallFrame.Option1:SetText("Reload")
        end
    },
    StepTitles = {
        [1] = "Welcome",
        [2] = "EllesmereUI",
        [3] = "General WeakAuras",
        [4] = "Class WeakAura",
        [5] = "Installation Complete"
    },
    StepTitlesColorSelected = {12/255, 210/255, 157/255},
    StepTitleWidth = 200,
    StepTitleButtonWidth = 180,
    StepTitleTextJustification = "RIGHT"
}
