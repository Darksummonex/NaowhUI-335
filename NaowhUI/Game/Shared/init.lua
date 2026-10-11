local _G = _G

local addon, ns = ...
local W = ns.Wrath
local NUI = W.NewAddon(addon)

ns[1] = NUI
ns[2] = {}
_G.NaowhUI = ns

NUI:NewModule("Data")
NUI:NewModule("Installer")
NUI:NewModule("Setup")

function NUI:OnInitialize()
    local defaults = {
        profile = {
            addons = {}
        }
    }

    self.db = W.NewDB("NaowhUIDB", defaults, true)

    if self.forever or (self.db.global.version and self.db.global.version <= 20261005) then
        self.db:ResetDB()
    end

    self:RegisterChatCommand("nui", "HandleChatCommand")
end
