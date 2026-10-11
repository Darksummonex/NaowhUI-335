local NUI = unpack(NaowhUI)
local SE = NUI:GetModule("Setup")

function SE.EllesmereUI(addon, resolution)
    local D = NUI:GetModule("Data")

    if not (EllesmereUI and EllesmereUI.ImportProfileInteractive and D[addon] and D[addon][resolution]) then

        return
    end

    local ok, reason = EllesmereUI.ImportProfileInteractive({
        importString = D[addon][resolution],
        profileName = "Naowh",
        source = "NaowhUI",
        callback = function(callback)
            if not callback then

                return
            end

            SE.CompleteSetup()
        end
    })

    if ok == false then
        NUI:Print("EllesmereUI import could not start: " .. tostring(reason))

        return
    end

    NaowhUIInstallFrame:SetFrameStrata("HIGH")
end
