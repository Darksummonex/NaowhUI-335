local NUI = unpack(NaowhUI)
local SE = NUI:GetModule("Setup")

local PROFILE = "Naowh"

function SE.CanSetupDetails()

    return _detalhes ~= nil and type(_detalhes.ApplyProfile) == "function" and _detalhes_global ~= nil and _detalhes_global.__profiles ~= nil
end

local function copy(src)
    local out = {}

    for k, v in pairs(src) do
        out[k] = type(v) == "table" and copy(v) or v
    end

    return out
end

function SE.Details(addon)
    local D = NUI:GetModule("Data")

    if not SE.CanSetupDetails() or not SE.LoadData() or not D[addon] then

        return
    end

    if InCombatLockdown() then
        NUI:Print("Leave combat to set up Details")

        return
    end

    _detalhes_global.__profiles[PROFILE] = copy(D[addon])

    _detalhes:ApplyProfile(PROFILE)

    SE.CompleteSetup(addon)
end
