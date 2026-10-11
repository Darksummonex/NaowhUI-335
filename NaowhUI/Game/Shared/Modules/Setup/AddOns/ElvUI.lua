local NUI = unpack(NaowhUI)
local SE = NUI:GetModule("Setup")

local PROFILES = {
    tank = "Naowh Tank/DPS",
    healer = "Naowh Healer"
}

function SE.CanSetupElvUI()
    return ElvUI ~= nil and ElvDB ~= nil and ElvUI[1] ~= nil and ElvUI[1].data ~= nil
end

function SE.ElvUI(addon, layout)
    local D = NUI:GetModule("Data")
    local data = D[addon]
    local name = PROFILES[layout]

    if not (SE.CanSetupElvUI() and data and data[layout] and name) then

        return
    end

    if InCombatLockdown() then
        NUI:Print("Leave combat to set up ElvUI")

        return
    end

    local E = ElvUI[1]

    if not ElvDB.profiles then
        ElvDB.profiles = {}
    end

    ElvDB.profiles[name] = E:CopyTable({}, data[layout])

    for section, values in pairs(data.private) do
        if type(E.private[section]) == "table" then
            for key, value in pairs(values) do
                E.private[section][key] = value
            end
        end
    end

    if not E.private.install_complete then
        E.private.install_complete = E.version
    end

    if data.UIScale then
        E.global.general.UIScale = data.UIScale
    end

    E.data:SetProfile(name)

    NUI.db.global.ElvUI = layout

    SE.CompleteSetup(addon)
end
