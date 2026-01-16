-- Broker: Slash Commands
-- LDB plugin that displays all registered slash commands by addon
-- Uses LibQTip for scrollable tooltip with collapsible sections
-- Hooks SlashCmdList to capture registration source via debugstack()

local addonName = "!Broker_SlashCommands"

--============================================================================
-- EARLY HOOK: Must run before other addons load
-- Capture the source addon when slash commands are registered
--============================================================================

-- Storage for captured registration sources (command name -> addon name)
local registrationSources = {}

-- Libraries/frameworks to skip when walking the stack (these register on behalf of other addons)
local libraryFolders = {
    ["Ace3"] = true,
    ["AceConsole-3.0"] = true,
    ["AceAddon-3.0"] = true,
    ["LibStub"] = true,
    ["CallbackHandler-1.0"] = true,
    ["libs"] = true,
    ["Libs"] = true,
}

-- Extract addon name from a stack line, skipping library folders
local function GetAddonNameFromStackLine(line)
    if not line then return nil end
    -- Match pattern like "Interface/AddOns/AddonName/..." or "Interface\AddOns\AddonName\..."
    local addonFolder = line:match("Interface[/\\]AddOns[/\\]([^/\\]+)")
    if addonFolder and not libraryFolders[addonFolder] then
        return addonFolder
    end
    return nil
end

-- Walk the full stack to find the first non-library addon
local function GetAddonFromFullStack()
    -- Get a larger stack trace to find the real caller
    local stack = debugstack(3, 20, 0)
    if not stack then return nil end

    -- Check each line of the stack for a non-library addon
    for line in stack:gmatch("[^\n]+") do
        local addonFolder = line:match("Interface[/\\]AddOns[/\\]([^/\\]+)")
        if addonFolder and not libraryFolders[addonFolder] then
            -- Also skip if it's inside a libs subfolder
            local isLibSubfolder = line:match("Interface[/\\]AddOns[/\\][^/\\]+[/\\][Ll]ibs?[/\\]")
            if not isLibSubfolder then
                return addonFolder
            end
        end
    end
    return nil
end

-- Store reference to original SlashCmdList table
local originalSlashCmdList = SlashCmdList

-- Hook the original table's metatable instead of replacing the table
-- This way the game's internal reference to SlashCmdList still works
local originalMeta = getmetatable(originalSlashCmdList)
local hookedMeta = {
    __newindex = function(t, key, value)
        -- Walk the stack to find the real addon (not a library)
        local sourceAddon = GetAddonFromFullStack()

        if sourceAddon then
            registrationSources[key] = sourceAddon
        end

        -- Store in the actual table
        rawset(t, key, value)
    end,
}

-- Copy any existing metatable methods
if originalMeta then
    for k, v in pairs(originalMeta) do
        if hookedMeta[k] == nil then
            hookedMeta[k] = v
        end
    end
end

-- Apply our hooked metatable to the original SlashCmdList
setmetatable(originalSlashCmdList, hookedMeta)

--============================================================================
-- MAIN ADDON CODE
--============================================================================

-- Libraries (loaded after our hook is in place)
local LibStub = LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LibQTip = LibStub and LibStub("LibQTip-1.0", true)

if not LDB then
    print("|cffff0000Broker_SlashCommands: LibDataBroker-1.1 not found!|r")
    return
end

if not LibQTip then
    print("|cffff0000Broker_SlashCommands: LibQTip-1.0 not found!|r")
    return
end

-- Saved variables (will be initialized after ADDON_LOADED)
Broker_SlashCommands_CollapsedAddons = Broker_SlashCommands_CollapsedAddons or {}

-- Cache for slash commands organized by addon
local slashCommandCache = {}
local addonList = {}
local cacheBuilt = false
local collapsedAddons = {}
local tooltip = nil

-- Colors
local COLOR_ADDON = {0.2, 1, 0.2, 1}
local COLOR_BLIZZARD = {0.5, 0.5, 1, 1}
local COLOR_UNKNOWN = {0.5, 0.5, 0.5, 1}
local COLOR_COMMAND = {0.8, 0.8, 0.8, 1}
local COLOR_HEADER = {1, 0.82, 0, 1}
local COLOR_HINT = {0.5, 0.5, 0.5, 1}

-- Common Blizzard slash commands (fallback detection)
local blizzardCommands = {
    "RELOAD", "CONSOLE", "HELP", "PLAYED", "WHO", "GUILD", "PARTY", "RAID",
    "SAY", "YELL", "EMOTE", "WHISPER", "CHANNEL", "AFK", "DND", "RANDOM",
    "ROLL", "TRADE", "INVITE", "KICK", "LEAVE", "LOGOUT", "QUIT", "EXIT",
    "CAMP", "TARGET", "ASSIST", "FOCUS", "CLEARFOCUS", "CLEARTARGET",
    "SCRIPT", "RUN", "DUMP", "EVENTTRACE", "FRAMESTACK", "TABLEINSPECT",
    "CAST", "USE", "CANCELAURA", "STOPCASTING", "STOPATTACK", "STARTATTACK",
    "EQUIP", "EQUIPSLOT", "EQUIPSET", "PVP", "DUEL", "FOLLOW", "DISMOUNT",
    "MACRO", "CLICK", "PETATTACK", "PETFOLLOW", "PETSTAY", "PETPASSIVE",
    "PETDEFENSIVE", "PETAUTOCAST", "CALENDAR", "SHARE", "UNSHARE",
    "IGNORE", "UNIGNORE", "FRIEND", "REMOVEFRIEND", "NOTE", "MUTE", "UNMUTE",
    "BLOCK", "UNBLOCK", "BN", "BNET", "CHATLOG", "COMBATLOG", "TIME",
    "CHAT_AFK", "CHAT_DND", "INSPECTACHIEVEMENTS", "COMPAREACHIEVEMENTS",
    "LEAVEVEHICLE", "STOPSPELLTARGET", "CANCELFORM", "CANCELQUEUEDSPELL"
}

-- Build a lookup table for faster checking
local blizzardCommandsLookup = {}
for _, cmd in ipairs(blizzardCommands) do
    blizzardCommandsLookup[cmd] = true
end

-- AceConsole prefix detection
local ACECONSOLE_PREFIX = "ACECONSOLE_"

-- Cache addon info for faster lookups
local addonInfoCache = nil
local function GetAddonInfoCache()
    if addonInfoCache then return addonInfoCache end

    addonInfoCache = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title = C_AddOns.GetAddOnInfo(i)
        if name then
            local info = {
                name = name,
                nameUpper = name:upper():gsub("[%s%-_]", ""),
                title = title or name,
                titleUpper = (title or name):upper():gsub("[%s%-_]", ""),
            }
            table.insert(addonInfoCache, info)
        end
    end
    return addonInfoCache
end

-- Try to determine which addon a slash command belongs to
-- slashes parameter is optional - used for matching against actual /command text
local function GetAddonForSlashCommand(cmdName, cmdFunc, slashes)
    local cmdUpper = cmdName:upper()

    -- Method 1: Check if we captured the source via hook (most accurate)
    if registrationSources[cmdName] then
        return registrationSources[cmdName], "hook"
    end

    -- Method 2: Check if it's an AceConsole command
    if cmdUpper:sub(1, #ACECONSOLE_PREFIX) == ACECONSOLE_PREFIX then
        local aceAddonPart = cmdUpper:sub(#ACECONSOLE_PREFIX + 1)
        local baseName = aceAddonPart:match("^([^%-]+)")
        if baseName then
            for _, info in ipairs(GetAddonInfoCache()) do
                if baseName == info.nameUpper or baseName:find(info.nameUpper, 1, true) or info.nameUpper:find(baseName, 1, true) then
                    return info.name, "aceconsole"
                end
            end
        end
    end

    -- Method 3: Check common Blizzard commands
    if blizzardCommandsLookup[cmdUpper] then
        return "Blizzard", "pattern"
    end
    for blizCmd, _ in pairs(blizzardCommandsLookup) do
        if cmdUpper:find("^" .. blizCmd) then
            return "Blizzard", "pattern"
        end
    end

    -- Method 4: Check loaded addons by command name matching
    for _, info in ipairs(GetAddonInfoCache()) do
        if cmdUpper:find(info.nameUpper, 1, true) or info.nameUpper:find(cmdUpper, 1, true) then
            return info.name, "name_match"
        end
    end

    -- Method 5: Check against addon titles (e.g., "Deadly Boss Mods" for DBM)
    for _, info in ipairs(GetAddonInfoCache()) do
        if cmdUpper:find(info.titleUpper, 1, true) or info.titleUpper:find(cmdUpper, 1, true) then
            return info.name, "title_match"
        end
    end

    -- Method 6: Match the actual slash text (e.g., "/dbm" against addon names)
    if slashes then
        for _, slash in ipairs(slashes) do
            -- Remove the leading / and convert to upper
            local slashText = slash:gsub("^/", ""):upper()
            if #slashText >= 2 then  -- Minimum 2 chars to avoid false matches
                for _, info in ipairs(GetAddonInfoCache()) do
                    -- Check if slash text matches addon name/title
                    if slashText == info.nameUpper or
                       info.nameUpper:find("^" .. slashText) or
                       slashText:find("^" .. info.nameUpper) or
                       info.titleUpper:find(slashText, 1, true) then
                        return info.name, "slash_match"
                    end
                end
            end
        end
    end

    return "Unknown", "none"
end

-- Build the cache of slash commands
local function BuildSlashCommandCache()
    wipe(slashCommandCache)
    wipe(addonList)
    addonInfoCache = nil  -- Clear addon info cache to refresh

    -- Iterate through SlashCmdList (uses our proxy which delegates to original)
    for cmdName, cmdFunc in pairs(originalSlashCmdList) do
        local slashes = {}

        -- Find all SLASH_CMDNAME1, SLASH_CMDNAME2, etc.
        local i = 1
        while true do
            local slashVar = _G["SLASH_" .. cmdName .. i]
            if slashVar then
                table.insert(slashes, slashVar)
                i = i + 1
            else
                break
            end
        end

        if #slashes > 0 then
            -- Pass slashes to detection function for additional matching
            local addonNameForCmd, detectionMethod = GetAddonForSlashCommand(cmdName, cmdFunc, slashes)

            if not slashCommandCache[addonNameForCmd] then
                slashCommandCache[addonNameForCmd] = {}
                table.insert(addonList, addonNameForCmd)
            end

            table.insert(slashCommandCache[addonNameForCmd], {
                name = cmdName,
                slashes = slashes,
                detectionMethod = detectionMethod
            })
        end
    end

    -- Sort addon list alphabetically
    table.sort(addonList, function(a, b)
        if a == "Blizzard" then return false end
        if b == "Blizzard" then return true end
        if a == "Unknown" then return false end
        if b == "Unknown" then return true end
        return a:lower() < b:lower()
    end)

    -- Sort commands within each addon
    for _, commands in pairs(slashCommandCache) do
        table.sort(commands, function(a, b)
            return a.slashes[1]:lower() < b.slashes[1]:lower()
        end)
    end

    cacheBuilt = true
end

-- Toggle collapsed state for an addon (default is collapsed)
local function ToggleAddonCollapsed(addonNameToToggle)
    local currentState = collapsedAddons[addonNameToToggle] ~= false
    collapsedAddons[addonNameToToggle] = not currentState
    Broker_SlashCommands_CollapsedAddons[addonNameToToggle] = collapsedAddons[addonNameToToggle]
end

-- Update the tooltip content
local function UpdateTooltip(self)
    if not tooltip then return end

    tooltip:Clear()

    -- Header
    local lineNum = tooltip:AddHeader("Slash Commands by Addon")
    tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_HEADER))

    tooltip:AddLine("")

    local totalCommands = 0
    local totalAddons = 0

    for _, currentAddonName in ipairs(addonList) do
        local commands = slashCommandCache[currentAddonName]
        if commands and #commands > 0 then
            totalAddons = totalAddons + 1

            -- Determine addon color
            local color = COLOR_ADDON
            if currentAddonName == "Blizzard" then
                color = COLOR_BLIZZARD
            elseif currentAddonName == "Unknown" then
                color = COLOR_UNKNOWN
            end

            -- Count total slash variants for this addon
            local slashCount = 0
            for _, cmd in ipairs(commands) do
                slashCount = slashCount + #cmd.slashes
            end
            totalCommands = totalCommands + slashCount

            -- Addon header with collapse icon (default to collapsed)
            local isCollapsed = collapsedAddons[currentAddonName] ~= false
            local icon = isCollapsed and "|TInterface\\Buttons\\UI-PlusButton-Up:16|t" or "|TInterface\\Buttons\\UI-MinusButton-Up:16|t"

            lineNum = tooltip:AddLine(icon .. " " .. currentAddonName .. " (" .. slashCount .. ")")
            tooltip:SetCellTextColor(lineNum, 1, unpack(color))

            -- Make the addon header clickable to toggle collapse
            tooltip:SetLineScript(lineNum, "OnMouseUp", function()
                ToggleAddonCollapsed(currentAddonName)
                UpdateTooltip(self)
            end)

            -- Show commands if not collapsed - each slash on its own line
            if not isCollapsed then
                for _, cmd in ipairs(commands) do
                    for _, slash in ipairs(cmd.slashes) do
                        -- For Unknown commands, show the command name in brackets
                        local displayText
                        if currentAddonName == "Unknown" then
                            displayText = "    " .. slash .. " |cff888888(" .. cmd.name .. ")|r"
                        else
                            displayText = "    " .. slash
                        end

                        lineNum = tooltip:AddLine(displayText)
                        tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_COMMAND))

                        -- Make each slash clickable to insert into chat
                        local slashToInsert = slash  -- Capture for closure
                        tooltip:SetLineScript(lineNum, "OnMouseUp", function()
                            ChatFrame_OpenChat(slashToInsert .. " ")
                        end)
                    end
                end
            end
        end
    end

    -- Footer
    tooltip:AddLine("")
    tooltip:AddSeparator(1, 1, 1, 1, 0.5)
    tooltip:AddLine("")

    lineNum = tooltip:AddLine("Total Addons: " .. totalAddons)
    tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_HEADER))

    lineNum = tooltip:AddLine("Total Commands: " .. totalCommands)
    tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_HEADER))

    tooltip:AddLine("")

    lineNum = tooltip:AddLine("Click command to insert in chat")
    tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_HINT))

    lineNum = tooltip:AddLine("Left-click icon to refresh")
    tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_HINT))

    lineNum = tooltip:AddLine("Right-click icon to search")
    tooltip:SetCellTextColor(lineNum, 1, unpack(COLOR_HINT))

    -- Enable scrolling if needed (max height of 600 pixels)
    tooltip:UpdateScrolling(600)
    tooltip:Show()
end

-- Search function (defined before StaticPopupDialogs which references it)
local function SearchSlashCommands(searchText)
    if not cacheBuilt then
        BuildSlashCommandCache()
    end

    searchText = searchText:lower()
    local found = false

    print("|cff00ff00Broker_SlashCommands:|r Searching for '" .. searchText .. "'...")

    for addonNameInCache, commands in pairs(slashCommandCache) do
        local addonMatches = addonNameInCache:lower():find(searchText, 1, true)

        for _, cmd in ipairs(commands) do
            local cmdMatches = false

            if cmd.name:lower():find(searchText, 1, true) then
                cmdMatches = true
            end

            for _, slash in ipairs(cmd.slashes) do
                if slash:lower():find(searchText, 1, true) then
                    cmdMatches = true
                    break
                end
            end

            if addonMatches or cmdMatches then
                found = true
                local slashStr = table.concat(cmd.slashes, ", ")
                print("  |cff00ff00" .. addonNameInCache .. "|r: " .. slashStr)
            end
        end
    end

    if not found then
        print("  No matches found.")
    end
end

-- Static popup for search (defined once, not per-click)
StaticPopupDialogs["BROKER_SLASHCMD_SEARCH"] = {
    text = "Enter slash command or addon name to search:",
    button1 = "Search",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(popup)
        local searchText = popup.editBox:GetText():lower()
        if searchText and searchText ~= "" then
            SearchSlashCommands(searchText)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Create the LDB data object
local dataObject = LDB:NewDataObject("SlashCommands", {
    type = "data source",
    text = "Slash Cmds",
    icon = "Interface\\ICONS\\INV_Misc_Note_01",
    OnEnter = function(self)
        if not cacheBuilt then
            BuildSlashCommandCache()
        end

        -- Acquire or reuse tooltip
        if not LibQTip:IsAcquired(addonName) then
            tooltip = LibQTip:Acquire(addonName, 1, "LEFT")
            tooltip:SetAutoHideDelay(0.1, self)
            tooltip:SmartAnchorTo(self)
            tooltip.OnRelease = function()
                tooltip = nil
            end
        end

        UpdateTooltip(self)
    end,
    OnLeave = function(self)
        -- Auto-hide is handled by LibQTip
    end,
    OnClick = function(self, button)
        if button == "LeftButton" then
            -- Refresh cache
            BuildSlashCommandCache()
            print("|cff00ff00Broker_SlashCommands:|r Cache refreshed. Found " .. #addonList .. " addons with slash commands.")
            if tooltip then
                UpdateTooltip(self)
            end
        elseif button == "RightButton" then
            -- Show search popup (dialog defined at file scope)
            StaticPopup_Show("BROKER_SLASHCMD_SEARCH")
        end
    end,
})

-- Slash command for the addon itself
SLASH_BROKERSLASH1 = "/slashcmds"
SLASH_BROKERSLASH2 = "/bsc"
SlashCmdList["BROKERSLASH"] = function(msg)
    if msg and msg ~= "" then
        if msg == "list" then
            if not cacheBuilt then
                BuildSlashCommandCache()
            end
            for _, addonNameInList in ipairs(addonList) do
                local commands = slashCommandCache[addonNameInList]
                if commands and #commands > 0 then
                    print("|cff00ff00" .. addonNameInList .. "|r:")
                    for _, cmd in ipairs(commands) do
                        for _, slash in ipairs(cmd.slashes) do
                            print("  " .. slash)
                        end
                    end
                end
            end
        elseif msg == "debug" then
            -- Debug: show how many commands were captured by hook
            local hookCount = 0
            for _ in pairs(registrationSources) do
                hookCount = hookCount + 1
            end
            print("|cff00ff00Broker_SlashCommands:|r Hook captured " .. hookCount .. " command registrations.")
        elseif msg == "unknown" then
            -- Show all unknown commands with details
            if not cacheBuilt then
                BuildSlashCommandCache()
            end
            local unknownCmds = slashCommandCache["Unknown"]
            if unknownCmds and #unknownCmds > 0 then
                print("|cff00ff00Broker_SlashCommands:|r Unknown commands (" .. #unknownCmds .. "):")
                for _, cmd in ipairs(unknownCmds) do
                    local slashStr = table.concat(cmd.slashes, ", ")
                    print("  |cffff9900" .. cmd.name .. "|r: " .. slashStr)
                end
            else
                print("|cff00ff00Broker_SlashCommands:|r No unknown commands!")
            end
        elseif msg == "dump" then
            -- Detailed dump of a specific command or all unknowns
            if not cacheBuilt then
                BuildSlashCommandCache()
            end
            print("|cff00ff00Broker_SlashCommands:|r Detailed dump of Unknown commands:")
            local unknownCmds = slashCommandCache["Unknown"]
            if unknownCmds then
                for _, cmd in ipairs(unknownCmds) do
                    print("|cffff9900Command:|r " .. cmd.name)
                    print("  Slashes: " .. table.concat(cmd.slashes, ", "))
                    print("  Hook source: " .. (registrationSources[cmd.name] or "not captured"))
                    -- Show what the slash text looks like stripped
                    for _, slash in ipairs(cmd.slashes) do
                        local stripped = slash:gsub("^/", ""):upper()
                        print("  Slash '" .. slash .. "' -> '" .. stripped .. "'")
                    end
                end
            end
        elseif msg == "hooks" then
            -- Show all captured hook sources
            print("|cff00ff00Broker_SlashCommands:|r All hook captures:")
            for cmdName, addonName in pairs(registrationSources) do
                print("  " .. cmdName .. " -> " .. addonName)
            end
        else
            SearchSlashCommands(msg)
        end
    else
        if not cacheBuilt then
            BuildSlashCommandCache()
        end
        local total = 0
        for _, cmds in pairs(slashCommandCache) do
            for _, cmd in ipairs(cmds) do
                total = total + #cmd.slashes
            end
        end
        print("|cff00ff00Broker_SlashCommands:|r Found " .. #addonList .. " addons with " .. total .. " slash commands.")
        print("  |cffffff00/slashcmds <search>|r - search commands")
        print("  |cffffff00/slashcmds list|r - list all commands")
        print("  |cffffff00/slashcmds unknown|r - show unknown commands")
        print("  |cffffff00/slashcmds dump|r - detailed dump of unknowns")
        print("  |cffffff00/slashcmds hooks|r - show all hook captures")
        print("  |cffffff00/slashcmds debug|r - show hook stats")
    end
end

-- Initialize after ADDON_LOADED
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if event == "ADDON_LOADED" and loadedAddonName == addonName then
        -- Restore collapsed state from saved variables
        if Broker_SlashCommands_CollapsedAddons then
            for k, v in pairs(Broker_SlashCommands_CollapsedAddons) do
                collapsedAddons[k] = v
            end
        end
    elseif event == "PLAYER_LOGIN" then
        -- Delay building cache to ensure all addons have registered their commands
        C_Timer.After(2, function()
            BuildSlashCommandCache()
            dataObject.text = #addonList .. " Addons"
        end)
    end
end)
