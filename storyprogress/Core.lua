local addonName, addonTable = ...

--luacheck: globals BtWQuestsDatabase BtWQuestsCharacters SLASH_STORYPROGRESS1 SlashCmdList

-- Initialize addon
local StoryProgress = {}
addonTable.StoryProgress = StoryProgress

-- Debug flag - set to true to enable detailed logging
StoryProgress.DEBUG = true

local function DebugLog(message)
    if StoryProgress.DEBUG then
        print("|cFF00FF00[" .. addonName .. " DEBUG]|r " .. message)
    end
end

local function Log(message)
    print("|cFFFFD700[" .. addonName .. "]|r " .. message)
end

local function CountQuestsRecursive(item, character, database, depth, visited)
    depth = depth or 0
    visited = visited or {}
    local indent = string.rep("  ", depth)
    local completed = 0
    local total = 0

    -- Prevent infinite recursion with depth limit
    if depth > 20 then
        DebugLog(indent .. "WARNING: Max recursion depth reached")
        return 0, 0
    end

    if not item or not item.type then
        DebugLog(indent .. "WARNING: Invalid item (no type)")
        return 0, 0
    end

    if item.type == "quest" then
        if not item.id then
            DebugLog(indent .. "WARNING: Quest item has no id")
            return 0, 0
        end
        total = 1
        if character:IsQuestCompleted(item.id) then
            completed = 1
            DebugLog(indent .. "Quest " .. item.id .. ": COMPLETED")
        else
            DebugLog(indent .. "Quest " .. item.id .. ": pending")
        end
    elseif item.type == "chain" then
        if not item.id then
            DebugLog(indent .. "WARNING: Chain item has no id")
            return 0, 0
        end
        -- Check for circular reference
        local key = "chain:" .. item.id
        if visited[key] then
            DebugLog(indent .. "WARNING: Circular reference detected for chain " .. item.id)
            return 0, 0
        end
        visited[key] = true

        local chain = database:GetChainByID(item.id)
        DebugLog(indent .. "Chain " .. item.id .. ": starting")
        if chain and chain.items then
            for _, subItem in ipairs(chain.items) do
                local c, t = CountQuestsRecursive(subItem, character, database, depth + 1, visited)
                completed = completed + c
                total = total + t
            end
        else
            DebugLog(indent .. "  WARNING: Chain " .. item.id .. " has no items or doesn't exist")
        end
    elseif item.type == "category" then
        if not item.id then
            DebugLog(indent .. "WARNING: Category item has no id")
            return 0, 0
        end
        -- Check for circular reference
        local key = "category:" .. item.id
        if visited[key] then
            DebugLog(indent .. "WARNING: Circular reference detected for category " .. item.id)
            return 0, 0
        end
        visited[key] = true

        local category = database:GetCategoryByID(item.id)
        DebugLog(indent .. "Category " .. item.id .. ": starting")
        if category and category.items then
            for _, subItem in ipairs(category.items) do
                local c, t = CountQuestsRecursive(subItem, character, database, depth + 1, visited)
                completed = completed + c
                total = total + t
            end
        else
            DebugLog(indent .. "  WARNING: Category " .. item.id .. " has no items or doesn't exist")
        end
    else
        DebugLog(indent .. "UNKNOWN item type: " .. tostring(item.type))
    end

    return completed, total
end

local function LoadExpansionAddon(expansionID)
    DebugLog("Loading expansion addon for ID " .. expansionID)

    if not BtWQuestsDatabase then
        DebugLog("ERROR: BtWQuestsDatabase not available")
        return false
    end

    local expansion = BtWQuestsDatabase:GetExpansionByID(expansionID)
    if not expansion then
        DebugLog("Expansion ID " .. expansionID .. " not found in database")
        return false
    end

    DebugLog("Checking if expansion is loaded...")
    if not expansion:IsLoaded() then
        DebugLog("Expansion not loaded, attempting to load...")
        expansion:Load()
    else
        DebugLog("Expansion already loaded")
    end

    local finalCheck = expansion:IsLoaded()
    DebugLog("Final check - expansion loaded: " .. tostring(finalCheck))
    return finalCheck
end

local function GetExpansionProgress(expansionID, expansionName)
    DebugLog("Getting progress for expansion " .. tostring(expansionID) .. " (" .. (expansionName or "unknown") .. ")")

    -- Load the expansion addon if needed
    if not LoadExpansionAddon(expansionID) then
        DebugLog("Failed to load expansion addon")
        return nil
    end

    DebugLog("Checking if BtWQuestsDatabase is available...")
    if not BtWQuestsDatabase then
        DebugLog("  ERROR: BtWQuestsDatabase not available")
        return nil
    end
    DebugLog("  BtWQuestsDatabase found")

    local database = BtWQuestsDatabase
    local expansion = database:GetExpansionByID(expansionID)

    if not expansion then
        DebugLog("Expansion ID " .. expansionID .. " not found in database")
        return nil
    end
    DebugLog("Expansion found in database")

    DebugLog("Getting player character...")
    local character = BtWQuestsCharacters:GetPlayer()
    if not character then
        DebugLog("  ERROR: Could not get player character")
        return nil
    end
    DebugLog("  Player character obtained")

    local completed = 0
    local total = 0

    if expansion.items then
        DebugLog("Expansion has " .. #expansion.items .. " top-level items")
        for idx, item in ipairs(expansion.items) do
            DebugLog("Processing expansion item " .. idx .. " (type: " .. (item.type or "unknown") .. ", id: " .. (item.id or "?") .. ")")
            local c, t = CountQuestsRecursive(item, character, database)
            completed = completed + c
            total = total + t
            DebugLog("  Subtotal: " .. c .. "/" .. t .. " (running total: " .. completed .. "/" .. total .. ")")
        end
    else
        DebugLog("WARNING: Expansion has no items")
    end

    DebugLog("GetExpansionProgress about to return: completed=" .. completed .. ", total=" .. total)
    return completed, total
end

function StoryProgress:PrintProgress(expansionName, expansionID)
    DebugLog("PrintProgress called for: " .. expansionName .. " (ID: " .. expansionID .. ")")
    Log("Querying progress for " .. expansionName .. "...")

    local completed, total = GetExpansionProgress(expansionID, expansionName)
    DebugLog("GetExpansionProgress returned: completed=" .. tostring(completed) .. ", total=" .. tostring(total))

    if not completed or not total then
        Log("Could not retrieve data for " .. expansionName)
        return
    end

    DebugLog("About to format and print summary line...")
    local percentage = (total > 0) and math.floor((completed / total) * 100) or 0
    DebugLog("Calculated percentage: " .. tostring(percentage))

    local success, err = pcall(function()
        local line = string.format("%s: %d of %d quests (%d%%)", expansionName, completed, total, percentage)
        DebugLog("Formatted line: " .. line)
        Log(line)
    end)

    if not success then
        DebugLog("ERROR formatting/printing summary: " .. tostring(err))
    end
    DebugLog("PrintProgress completed")
end

function StoryProgress:PrintAllExpansions()
    local expansions = {
        { name = "Shadowlands", id = 8 },
        { name = "Battle for Azeroth", id = 7 },
        { name = "Dragonflight", id = 10 },
        { name = "The War Within", id = 9 },
    }

    Log("=== Story Progress Summary ===")
    for _, expansion in ipairs(expansions) do
        self:PrintProgress(expansion.name, expansion.id)
    end
    Log("==============================")
end

function StoryProgress:OnLoad()
    Log("Addon loaded!")
    self:PrintAllExpansions()
end

-- Slash command handler
SLASH_STORYPROGRESS1 = "/storyprogress"

SlashCmdList["STORYPROGRESS"] = function(msg)
    if msg == "debug" then
        StoryProgress.DEBUG = not StoryProgress.DEBUG
        Log("Debug mode: " .. (StoryProgress.DEBUG and "ON" or "OFF"))
    else
        StoryProgress:PrintAllExpansions()
    end
end

-- Register for addon load event
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        StoryProgress:OnLoad()
    end
end)
