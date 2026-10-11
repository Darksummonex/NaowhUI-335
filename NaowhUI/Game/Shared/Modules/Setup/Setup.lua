local NUI = unpack(NaowhUI)
local SE = NUI:GetModule("Setup")

function SE:Setup(addon, ...)
    local D = NUI:GetModule("Data")

    local setup = self[addon]

    setup(addon, ...)
end

function SE.CompleteSetup(addon)
    if NaowhUIInstallStepComplete:IsShown() then
        NaowhUIInstallStepComplete:Hide()
    end

    NaowhUIInstallStepComplete.message = "Success"

    NaowhUIInstallStepComplete:Show()

    if not addon then

        return
    end

    if not NUI.db.profile.addons[addon] then
        NaowhUIDB.char = {}
        NUI.db.char.loaded = true
        NUI.db.profile.addons[addon] = true
    end

    NUI.db.global.version = NUI.version

    if NUI.forever then
        NUI:Print(NUI.db.char.loaded)
        NUI:Print(NUI.db.profile.addons[addon])
        NUI:Print(NUI.db.global.version)
    end
end