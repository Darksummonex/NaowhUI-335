-- LibSharedMedia 12.x checks paths with C_UIFileAsset.IsKnownFile, which 3.3.5 lacks;
-- SetFont/SetTexture/PlaySoundFile do the real file lookup there.
if not C_UIFileAsset then C_UIFileAsset = {} end
if not C_UIFileAsset.IsKnownFile then
    C_UIFileAsset.IsKnownFile = function(path) return type(path) == "string" and path ~= "" end
end
