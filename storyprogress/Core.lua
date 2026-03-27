local addonName, addonTable = ...

--luacheck: globals BtWQuestsDatabase BtWQuestsCharacters SLASH_STORYPROGRESS1 SlashCmdList

-- Initialize addon
local StoryProgress = {}
addonTable.StoryProgress = StoryProgress

-- Per-function debug flags - set to true to enable logging for a specific function
local debugFlags = {}

local function DebugLog(functionName, message)
    if debugFlags[functionName] then
        print("|cFF00FF00[" .. addonName .. " DEBUG:" .. functionName .. "]|r " .. message)
    end
end

-- Helper to enable/disable debug for a specific function
function StoryProgress:SetDebug(functionName, enabled)
    debugFlags[functionName] = enabled or false
end

local function Log(message)
    print("|cFFFFD700[" .. addonName .. "]|r " .. message)
end

local function CountQuestsRecursive(item, character, database, depth, visited)
    local funcName = "CountQuestsRecursive"
    depth = depth or 0
    visited = visited or {}
    local indent = string.rep("  ", depth)
    local completed = 0
    local total = 0

    -- Prevent infinite recursion with depth limit
    if depth > 20 then
        DebugLog(funcName, indent .. "WARNING: Max recursion depth reached")
        return 0, 0
    end

    if not item or not item.type then
        DebugLog(funcName, indent .. "WARNING: Invalid item (no type)")
        return 0, 0
    end

    if item.type == "quest" then
        if not item.id then
            DebugLog(funcName, indent .. "WARNING: Quest item has no id")
            return 0, 0
        end
        total = 1
        if character:IsQuestCompleted(item.id) then
            completed = 1
            DebugLog(funcName, indent .. "Quest " .. item.id .. ": COMPLETED")
        else
            DebugLog(funcName, indent .. "Quest " .. item.id .. ": pending")
        end
    elseif item.type == "chain" then
        if not item.id then
            DebugLog(funcName, indent .. "WARNING: Chain item has no id")
            return 0, 0
        end
        -- Check for circular reference
        local key = "chain:" .. item.id
        if visited[key] then
            DebugLog(funcName, indent .. "WARNING: Circular reference detected for chain " .. item.id)
            return 0, 0
        end
        visited[key] = true

        local chain = database:GetChainByID(item.id)
        DebugLog(funcName, indent .. "Chain " .. item.id .. ": starting")
        if chain and chain.items then
            for _, subItem in ipairs(chain.items) do
                local c, t = CountQuestsRecursive(subItem, character, database, depth + 1, visited)
                completed = completed + c
                total = total + t
            end
        else
            DebugLog(funcName, indent .. "  WARNING: Chain " .. item.id .. " has no items or doesn't exist")
        end
    elseif item.type == "category" then
        if not item.id then
            DebugLog(funcName, indent .. "WARNING: Category item has no id")
            return 0, 0
        end
        -- Check for circular reference
        local key = "category:" .. item.id
        if visited[key] then
            DebugLog(funcName, indent .. "WARNING: Circular reference detected for category " .. item.id)
            return 0, 0
        end
        visited[key] = true

        local category = database:GetCategoryByID(item.id)
        DebugLog(funcName, indent .. "Category " .. item.id .. ": starting")
        if category and category.items then
            for _, subItem in ipairs(category.items) do
                local c, t = CountQuestsRecursive(subItem, character, database, depth + 1, visited)
                completed = completed + c
                total = total + t
            end
        else
            DebugLog(funcName, indent .. "  WARNING: Category " .. item.id .. " has no items or doesn't exist")
        end
    else
        DebugLog(funcName, indent .. "UNKNOWN item type: " .. tostring(item.type))
    end

    return completed, total
end

local function LoadExpansionAddon(expansionID)
    local funcName = "LoadExpansionAddon"
    DebugLog(funcName, "Loading expansion addon for ID " .. expansionID)

    if not BtWQuestsDatabase then
        DebugLog(funcName, "ERROR: BtWQuestsDatabase not available")
        return false
    end

    local expansion = BtWQuestsDatabase:GetExpansionByID(expansionID)
    if not expansion then
        DebugLog(funcName, "Expansion ID " .. expansionID .. " not found in database")
        return false
    end

    DebugLog(funcName, "Checking if expansion is loaded...")
    if not expansion:IsLoaded() then
        DebugLog(funcName, "Expansion not loaded, attempting to load...")
        expansion:Load()
    else
        DebugLog(funcName, "Expansion already loaded")
    end

    local finalCheck = expansion:IsLoaded()
    DebugLog(funcName, "Final check - expansion loaded: " .. tostring(finalCheck))
    return finalCheck
end

local function GetExpansionProgress(expansionID, expansionName)
    local funcName = "GetExpansionProgress"
    DebugLog(funcName, "Getting progress for expansion " .. tostring(expansionID) .. " (" .. (expansionName or "unknown") .. ")")

    -- Load the expansion addon if needed
    if not LoadExpansionAddon(expansionID) then
        DebugLog(funcName, "Failed to load expansion addon")
        return nil
    end

    DebugLog(funcName, "Checking if BtWQuestsDatabase is available...")
    if not BtWQuestsDatabase then
        DebugLog(funcName, "  ERROR: BtWQuestsDatabase not available")
        return nil
    end
    DebugLog(funcName, "  BtWQuestsDatabase found")

    local database = BtWQuestsDatabase
    local expansion = database:GetExpansionByID(expansionID)

    if not expansion then
        DebugLog(funcName, "Expansion ID " .. expansionID .. " not found in database")
        return nil
    end
    DebugLog(funcName, "Expansion found in database")

    DebugLog(funcName, "Getting player character...")
    local character = BtWQuestsCharacters:GetPlayer()
    if not character then
        DebugLog(funcName, "  ERROR: Could not get player character")
        return nil
    end
    DebugLog(funcName, "  Player character obtained")

    local completed = 0
    local total = 0

    if expansion.items then
        DebugLog(funcName, "Expansion has " .. #expansion.items .. " top-level items")
        for idx, item in ipairs(expansion.items) do
            DebugLog(funcName, "Processing expansion item " .. idx .. " (type: " .. (item.type or "unknown") .. ", id: " .. (item.id or "?") .. ")")
            local c, t = CountQuestsRecursive(item, character, database)
            completed = completed + c
            total = total + t
            DebugLog(funcName, "  Subtotal: " .. c .. "/" .. t .. " (running total: " .. completed .. "/" .. total .. ")")
        end
    else
        DebugLog(funcName, "WARNING: Expansion has no items")
    end

    DebugLog(funcName, "GetExpansionProgress about to return: completed=" .. completed .. ", total=" .. total)
    return completed, total
end

function StoryProgress:GetProgressText(expansionName, expansionID)
    local funcName = "GetProgressText"
    DebugLog(funcName, "GetProgressText called for: " .. expansionName .. " (ID: " .. expansionID .. ")")

    local completed, total = GetExpansionProgress(expansionID, expansionName)
    DebugLog(funcName, "GetExpansionProgress returned: completed=" .. tostring(completed) .. ", total=" .. tostring(total))

    if not completed or not total then
        return "Could not retrieve data for " .. expansionName .. "\n"
    end

    DebugLog(funcName, "About to format summary line...")
    local percentage = (total > 0) and math.floor((completed / total) * 100) or 0
    DebugLog(funcName, "Calculated percentage: " .. tostring(percentage))

    local success, result, err
    success, result, err = pcall(function()
        return string.format("%s: %d%% (%d of %d quests)\n", expansionName, percentage, completed, total)
    end)

    if not success then
        DebugLog(funcName, "ERROR formatting summary: " .. tostring(err))
        return ""
    end
    return result
end

function StoryProgress:PrintProgress(expansionName, expansionID)
    Log(string.gsub(self:GetProgressText(expansionName, expansionID), "\n", ""))
end

function StoryProgress:CalculateAllExpansions()
    for _, expansion in ipairs(BtWQuestsDatabase:GetExpansionList()) do
        GetExpansionProgress(expansion:GetID(), expansion:GetName())
    end
end

function StoryProgress:GetAllExpansionsText()
    local text = "=== Story Progress Summary ===\n"
    for _, expansion in ipairs(BtWQuestsDatabase:GetExpansionList()) do
        text = text .. self:GetProgressText(expansion:GetName(), expansion:GetID())
    end
    text = text .. "==============================\n"
    return text
end

function StoryProgress:PrintAllExpansions()
    Log("=== Story Progress Summary ===")
    for _, expansion in ipairs(BtWQuestsDatabase:GetExpansionList()) do
        self:PrintProgress(expansion:GetName(), expansion:GetID())
    end
    Log("==============================")
end

function StoryProgress:CreateGUI()
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        return
    end

    -- Create main window
    local mainFrame = CreateFrame("Frame", "StoryProgressMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(500, 400)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.8)
    mainFrame:SetBackdropBorderColor(1, 1, 1, 0.3)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    -- Create title bar
    local titleBar = mainFrame:CreateFontString(nil, "OVERLAY")
    titleBar:SetFont("Fonts/FRIZQT__.TTF", 14, "OUTLINE")
    titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -10)
    titleBar:SetText("Story Progress")
    titleBar:SetTextColor(1, 1, 0, 1)

    -- Create close button
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 10)
    scrollFrame:SetScript("OnMouseWheel", function(scrollSelf, delta)
        local newValue = scrollSelf:GetVerticalScroll() - delta * 20
        scrollSelf:SetVerticalScroll(max(0, min(newValue, scrollSelf.scrollChild:GetHeight() - scrollSelf:GetHeight())))
    end)
    scrollFrame:EnableMouseWheel(true)

    -- Create text frame for scrolling content
    local textFrame = CreateFrame("Frame", nil, scrollFrame)
    textFrame:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(textFrame)

    -- Create the text display
    local textDisplay = textFrame:CreateFontString(nil, "OVERLAY")
    textDisplay:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    textDisplay:SetPoint("TOPLEFT", textFrame, "TOPLEFT", 5, -5)
    textDisplay:SetPoint("RIGHT", textFrame, "RIGHT", -10, 0)
    textDisplay:SetJustifyH("LEFT")
    textDisplay:SetJustifyV("TOP")
    textDisplay:SetTextColor(1, 1, 1, 1)

    -- Set the progress text
    local progressText = self:GetAllExpansionsText()
    textDisplay:SetText(progressText)
    textFrame:SetHeight(textDisplay:GetHeight() + 10)
    scrollFrame:UpdateScrollChildRect()

    self.mainFrame = mainFrame
    mainFrame:Show()
end

function StoryProgress:OnLoad()
    Log("Addon loaded!")
    self:CalculateAllExpansions()
end

-- Slash command handler
SLASH_STORYPROGRESS1 = "/storyprogress"

SlashCmdList["STORYPROGRESS"] = function()
    StoryProgress:CreateGUI()
end

-- Register for addon load event
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        StoryProgress:OnLoad()
    end
end)
