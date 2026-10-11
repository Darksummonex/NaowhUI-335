local NUI = unpack(NaowhUI)
local W = NaowhUI.Wrath

local commands = {}

NUI.forever = false
NUI.localizedClass, NUI.class = UnitClass("player")
NUI.name = UnitName("player")
NUI.retail = false
NUI.title = GetAddOnMetadata("NaowhUI", "Title")
NUI.version = tonumber(GetAddOnMetadata("NaowhUI", "Version"))

function NUI:RunInstaller()
    local I = self:GetModule("Installer")

    if InCombatLockdown() then

        return
    end

    I:Queue(I.installer)
end

function commands.install()
    NUI:RunInstaller()
end

function NUI:HandleChatCommand(input)
    local command = commands[input]

    if not command then
        self:Print("Command does not exist")

        return
    end

    command()
end

function NUI:IsAddOnEnabled(addon)

    return W.IsAddOnEnabled(addon)
end
