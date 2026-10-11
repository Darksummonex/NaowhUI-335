local NUI = unpack(NaowhUI)
local SE = NUI:GetModule("Setup")
local W = NaowhUI.Wrath

-- Naowh's WeakAuras ship as WeakAuras 5 "!WA:2!" strings (TBC Classic exports in
-- NaowhUI_Data). Only WeakAuras builds that decode that format (LibSerialize) can
-- import them; older 3.3.5 WeakAuras would fail on the string.
function SE.CanImportWeakAuras()
    return WeakAuras ~= nil and type(WeakAuras.Import) == "function"
        and LibStub ~= nil and LibStub("LibSerialize", true) ~= nil
end

function SE.LoadData()
    if not IsAddOnLoaded("NaowhUI_Data") then
        if not W.CanLoadAddOn("NaowhUI_Data") then

            return false
        end

        LoadAddOn("NaowhUI_Data")
    end

    return IsAddOnLoaded("NaowhUI_Data") and true or false
end

function SE.WeakAuras(_, weakaura)
    local D = NUI:GetModule("Data")

    if not SE.CanImportWeakAuras() or not SE.LoadData() or not D[weakaura] then

        return
    end

    NaowhUIInstallFrame:SetFrameStrata("HIGH")
    WeakAuras.Import(D[weakaura])
end
