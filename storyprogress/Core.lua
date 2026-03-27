local addonName, addonTable = ...

-- Initialize addon
local StoryProgress = {}
addonTable.StoryProgress = StoryProgress

function StoryProgress:OnLoad()
    print(addonName .. " loaded!")
end

-- Register for addon load event
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        StoryProgress:OnLoad()
    end
end)
