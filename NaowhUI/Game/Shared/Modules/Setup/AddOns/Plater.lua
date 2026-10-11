local NUI = unpack(NaowhUI)
local SE = NUI:GetModule("Setup")

local PROFILE = "Naowh"

local function GetPlater()
    return Plater or (PLATER335_ENV and PLATER335_ENV.Plater)
end

function SE.CanSetupPlater()
    local plater = GetPlater()

    return plater ~= nil and plater.db ~= nil and type(plater.db.SetProfile) == "function" and PlaterDB ~= nil
end

local function copy(src)
    local out = {}

    for k, v in pairs(src) do
        out[k] = type(v) == "table" and copy(v) or v
    end

    return out
end

function SE.Plater(addon)
    local D = NUI:GetModule("Data")

    if not SE.CanSetupPlater() or not SE.LoadData() or not D[addon] then

        return
    end

    if InCombatLockdown() then
        NUI:Print("Leave combat to set up Plater")

        return
    end

    if not PlaterDB.profiles then
        PlaterDB.profiles = {}
    end

    PlaterDB.profiles[PROFILE] = copy(D[addon])

    GetPlater().db:SetProfile(PROFILE)

    SE.CompleteSetup(addon)
end
