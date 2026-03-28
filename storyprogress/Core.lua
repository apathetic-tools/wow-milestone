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

-- GUI state and constants
local serverCollapsed = {}  -- tracks collapsed state: serverCollapsed[realm] = true/false

local EXPANSION_ACRONYMS = {
    [0]="Vanilla", [1]="TBC", [2]="WotLK", [3]="Cata", [4]="MoP",
    [5]="WoD", [6]="Legion", [7]="BfA", [8]="SL", [9]="DF",
    [10]="TWW", [11]="Mid",
}

local ROW_HEIGHT = 20
local COL_TOGGLE = 20
local COL_NAME   = 140
local COL_LEVEL  = 40
local COL_EXP    = 50   -- per expansion column
local PADDING    = 20   -- left/right padding

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

function StoryProgress:CollectData()
    local data = {
        expansions = {},
        servers = {},
    }

    -- Get expansions
    for _, expansion in ipairs(BtWQuestsDatabase:GetExpansionList()) do
        local id = expansion:GetID()
        local name = expansion:GetName()
        local acronym = EXPANSION_ACRONYMS[id] or name
        table.insert(data.expansions, {id=id, name=name, acronym=acronym})
    end

    -- Get player character
    local player = BtWQuestsCharacters:GetPlayer()
    if not player then
        return data
    end

    local realm = player:GetRealm()
    if not data.servers[realm] then
        data.servers[realm] = {characters = {}}
    end

    -- Build character data
    local char = {
        name = player:GetName(),
        level = player:GetLevel(),
        classFile = player:GetClassString(),
        classColor = RAID_CLASS_COLORS[player:GetClassString()],
        expansionData = {},
    }

    -- Get expansion progress for this character
    for _, expInfo in ipairs(data.expansions) do
        local completed, total = GetExpansionProgress(expInfo.id, expInfo.name)
        char.expansionData[expInfo.id] = {
            completed = completed or 0,
            total = total or 0,
            pct = (total and total > 0) and math.floor((completed / total) * 100) or 0,
        }
    end

    table.insert(data.servers[realm].characters, char)
    return data
end

function StoryProgress:RefreshRows(data)
    if not self.scrollFrame or not self.contentFrame then
        return
    end

    -- Clear existing rows
    for i = #(self.rows or {}), 1, -1 do
        self.rows[i]:Hide()
    end
    self.rows = {}

    local y = 0
    local contentFrame = self.contentFrame
    data = data or self:CollectData()

    -- Build rows for each server
    for realm, serverData in pairs(data.servers) do
        local isCollapsed = serverCollapsed[realm]

        -- Server header row
        do
            local serverRow = CreateFrame("Frame", nil, contentFrame)
            serverRow:SetSize(contentFrame:GetWidth(), ROW_HEIGHT)
            serverRow:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -y)

            -- Toggle button
            local toggleBtn = CreateFrame("Button", nil, serverRow)
            toggleBtn:SetSize(16, 16)
            toggleBtn:SetPoint("TOPLEFT", serverRow, "TOPLEFT", PADDING, -2)
            toggleBtn:SetNormalTexture(isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
            toggleBtn:SetScript("OnClick", function()
                serverCollapsed[realm] = not serverCollapsed[realm]
                self:RefreshRows(data)
            end)

            -- Server name label
            local serverLabel = serverRow:CreateFontString(nil, "OVERLAY")
            serverLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
            serverLabel:SetPoint("TOPLEFT", serverRow, "TOPLEFT", PADDING + COL_TOGGLE + 5, -2)
            serverLabel:SetText(realm)
            serverLabel:SetTextColor(1, 1, 0, 1)  -- yellow

            table.insert(self.rows, serverRow)
        end

        y = y + ROW_HEIGHT

        -- Character rows
        if not isCollapsed then
            for _, char in ipairs(serverData.characters) do
                local charRow = CreateFrame("Frame", nil, contentFrame)
                charRow:SetSize(contentFrame:GetWidth(), ROW_HEIGHT)
                charRow:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -y)

                -- Name column (class-colored)
                local className = LOCALIZED_CLASS_NAMES_MALE[char.classFile] or char.classFile
                local nameLabel = charRow:CreateFontString(nil, "OVERLAY")
                nameLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
                nameLabel:SetPoint("TOPLEFT", charRow, "TOPLEFT", PADDING + COL_TOGGLE, -2)
                nameLabel:SetWidth(COL_NAME - 5)
                nameLabel:SetText(char.name .. " (" .. className .. ")")
                if char.classColor then
                    nameLabel:SetTextColor(char.classColor.r, char.classColor.g, char.classColor.b)
                end

                -- Level column
                local levelLabel = charRow:CreateFontString(nil, "OVERLAY")
                levelLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
                levelLabel:SetPoint("TOPLEFT", charRow, "TOPLEFT", PADDING + COL_TOGGLE + COL_NAME, -2)
                levelLabel:SetWidth(COL_LEVEL)
                levelLabel:SetJustifyH("CENTER")
                levelLabel:SetText(tostring(char.level))

                -- Expansion columns
                for idx, expInfo in ipairs(data.expansions) do
                    -- Capture values in local scope to avoid closure issues
                    local completed = char.expansionData[expInfo.id].completed
                    local total = char.expansionData[expInfo.id].total
                    local pct = char.expansionData[expInfo.id].pct
                    local xPos = PADDING + COL_TOGGLE + COL_NAME + COL_LEVEL + ((idx - 1) * COL_EXP)

                    local expLabel = charRow:CreateFontString(nil, "OVERLAY")
                    expLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
                    expLabel:SetPoint("TOPLEFT", charRow, "TOPLEFT", xPos, -2)
                    expLabel:SetWidth(COL_EXP)
                    expLabel:SetJustifyH("CENTER")
                    expLabel:SetText(pct .. "%")

                    -- Create a button frame for tooltip interaction
                    local tooltipBtn = CreateFrame("Button", nil, charRow)
                    tooltipBtn:SetPoint("TOPLEFT", charRow, "TOPLEFT", xPos, 0)
                    tooltipBtn:SetSize(COL_EXP, ROW_HEIGHT)
                    tooltipBtn:SetScript("OnEnter", function()
                        local charNameWithClass = char.name .. " (" .. className .. ")"
                        local classColor = char.classColor
                        GameTooltip:SetOwner(tooltipBtn, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(expInfo.name)
                        if classColor then
                            GameTooltip:AddLine(charNameWithClass, classColor.r, classColor.g, classColor.b)
                        else
                            GameTooltip:AddLine(charNameWithClass)
                        end
                        GameTooltip:AddLine(completed .. " of " .. total .. " quests", 1, 1, 1)
                        GameTooltip:Show()
                    end)
                    tooltipBtn:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                table.insert(self.rows, charRow)
                y = y + ROW_HEIGHT
            end
        end
    end

    -- Update content frame height
    self.contentFrame:SetHeight(y)
    self.scrollFrame:UpdateScrollChildRect()

    -- Position totals row
    self:RefreshTotalsRow(data)
end

function StoryProgress:RefreshTotalsRow(data)
    if not self.totalsRow then
        return
    end

    data = data or self:CollectData()

    -- Clear existing totals labels
    for i = 1, 12 do
        if self.totalsLabels and self.totalsLabels[i] then
            self.totalsLabels[i]:SetText("")
        end
    end

    -- Calculate totals (max % per expansion across all characters)
    local totals = {}
    for _, serverData in pairs(data.servers) do
        for _, char in ipairs(serverData.characters) do
            for expId, expData in pairs(char.expansionData) do
                if not totals[expId] or expData.pct > totals[expId].pct then
                    totals[expId] = {pct = expData.pct, completed = expData.completed, total = expData.total}
                end
            end
        end
    end

    -- Clear old labels
    if self.totalsLabelFrame then
        self.totalsLabelFrame:Hide()
        self.totalsLabelFrame = nil
    end

    -- Create new totals labels
    local labelFrame = CreateFrame("Frame", nil, self.totalsRow)
    labelFrame:SetSize(self.totalsRow:GetWidth(), ROW_HEIGHT)
    labelFrame:SetPoint("TOPLEFT", self.totalsRow, "TOPLEFT", 0, 0)
    self.totalsLabelFrame = labelFrame

    -- "Totals" label
    local totalsLabel = labelFrame:CreateFontString(nil, "OVERLAY")
    totalsLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    totalsLabel:SetPoint("TOPLEFT", labelFrame, "TOPLEFT", PADDING + COL_TOGGLE, -2)
    totalsLabel:SetText("Totals")
    totalsLabel:SetTextColor(1, 1, 0, 1)  -- yellow

    -- Expansion totals
    self.totalsLabels = {}
    for idx, expInfo in ipairs(data.expansions) do
        local totalData = totals[expInfo.id]
        local pctStr = totalData and (totalData.pct .. "%") or "0%"
        local xPos = PADDING + COL_TOGGLE + COL_NAME + COL_LEVEL + ((idx - 1) * COL_EXP)

        local totalExpLabel = labelFrame:CreateFontString(nil, "OVERLAY")
        totalExpLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
        totalExpLabel:SetPoint("TOPLEFT", labelFrame, "TOPLEFT", xPos, -2)
        totalExpLabel:SetWidth(COL_EXP)
        totalExpLabel:SetJustifyH("CENTER")
        totalExpLabel:SetText(pctStr)
        self.totalsLabels[idx] = totalExpLabel

        -- Tooltip button for totals
        local totalTooltipBtn = CreateFrame("Button", nil, labelFrame)
        totalTooltipBtn:SetPoint("TOPLEFT", labelFrame, "TOPLEFT", xPos, 0)
        totalTooltipBtn:SetSize(COL_EXP, ROW_HEIGHT)
        if totalData then
            -- Capture values to avoid closure issues
            local fullName = expInfo.name
            local completedVal = totalData.completed
            local totalVal = totalData.total
            totalTooltipBtn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(totalTooltipBtn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(fullName)
                GameTooltip:AddLine(completedVal .. " of " .. totalVal .. " quests", 1, 1, 1)
                GameTooltip:Show()
            end)
        end
        totalTooltipBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    self.totalsLabelFrame:Show()
end

function StoryProgress:CreateGUI()
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        return
    end

    if self.mainFrame and not self.mainFrame:IsShown() then
        -- Frame exists but is hidden, just show it and refresh
        self.mainFrame:Show()
        local data = self:CollectData()
        self:RefreshRows(data)
        return
    end

    -- Collect data to determine window width
    local data = self:CollectData()
    local windowWidth = PADDING + COL_TOGGLE + COL_NAME + COL_LEVEL + (#data.expansions * COL_EXP) + PADDING
    windowWidth = max(500, windowWidth)  -- minimum width

    -- Create main window
    local mainFrame = CreateFrame("Frame", "StoryProgressMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(windowWidth, 400)
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

    -- Create header row (column labels)
    local headerRow = CreateFrame("Frame", nil, mainFrame)
    headerRow:SetSize(windowWidth - 20, ROW_HEIGHT)
    headerRow:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -35)

    -- Column headers
    local nameHeader = headerRow:CreateFontString(nil, "OVERLAY")
    nameHeader:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    nameHeader:SetPoint("TOPLEFT", headerRow, "TOPLEFT", PADDING + COL_TOGGLE, -2)
    nameHeader:SetText("Name")
    nameHeader:SetTextColor(1, 1, 1, 1)  -- white

    local levelHeader = headerRow:CreateFontString(nil, "OVERLAY")
    levelHeader:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    levelHeader:SetPoint("TOPLEFT", headerRow, "TOPLEFT", PADDING + COL_TOGGLE + COL_NAME, -2)
    levelHeader:SetWidth(COL_LEVEL)
    levelHeader:SetJustifyH("CENTER")
    levelHeader:SetText("Level")
    levelHeader:SetTextColor(1, 1, 1, 1)  -- white

    -- Expansion headers with tooltips
    for idx, expInfo in ipairs(data.expansions) do
        -- Capture values to avoid closure issues
        local fullName = expInfo.name
        local xPos = PADDING + COL_TOGGLE + COL_NAME + COL_LEVEL + ((idx - 1) * COL_EXP)

        -- Get total quests for this expansion from any character
        local totalQuests = 0
        for _, serverData in pairs(data.servers) do
            for _, char in ipairs(serverData.characters) do
                if char.expansionData[expInfo.id] then
                    totalQuests = char.expansionData[expInfo.id].total
                    break
                end
            end
            if totalQuests > 0 then break end
        end

        local expHeader = headerRow:CreateFontString(nil, "OVERLAY")
        expHeader:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
        expHeader:SetPoint("TOPLEFT", headerRow, "TOPLEFT", xPos, -2)
        expHeader:SetWidth(COL_EXP)
        expHeader:SetJustifyH("CENTER")
        expHeader:SetText(expInfo.acronym)
        expHeader:SetTextColor(1, 1, 1, 1)  -- white

        -- Create a button for tooltip interaction
        local headerBtn = CreateFrame("Button", nil, headerRow)
        headerBtn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", xPos, 0)
        headerBtn:SetSize(COL_EXP, ROW_HEIGHT)
        headerBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(headerBtn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(fullName)
            GameTooltip:AddLine(totalQuests .. " total quests", 1, 1, 1)
            GameTooltip:Show()
        end)
        headerBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 30)
    scrollFrame:SetScript("OnMouseWheel", function(scrollSelf, delta)
        local newValue = scrollSelf:GetVerticalScroll() - delta * 20
        scrollSelf:SetVerticalScroll(max(0, min(newValue, scrollSelf.scrollChild:GetHeight() - scrollSelf:GetHeight())))
    end)
    scrollFrame:EnableMouseWheel(true)

    -- Create content frame for scrolling
    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(windowWidth - 20, 1)
    scrollFrame:SetScrollChild(contentFrame)

    -- Create totals row (fixed at bottom)
    local totalsRow = CreateFrame("Frame", nil, mainFrame)
    totalsRow:SetSize(windowWidth - 20, ROW_HEIGHT)
    totalsRow:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 10, 10)

    -- Store references for refresh
    self.mainFrame = mainFrame
    self.scrollFrame = scrollFrame
    self.contentFrame = contentFrame
    self.totalsRow = totalsRow
    self.rows = {}
    self.totalsLabels = {}

    -- Build the rows and totals
    self:RefreshRows(data)
    self:RefreshTotalsRow(data)

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
