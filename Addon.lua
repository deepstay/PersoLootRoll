local Name, Addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(Name)
local Comm, GUI, Inspect, Item, Options, Session, Roll, Trade, Unit, Util = Addon.Comm, Addon.GUI, Addon.Inspect, Addon.Item, Addon.Options, Addon.Session, Addon.Roll, Addon.Trade, Addon.Unit, Addon.Util

-- Logging
Addon.ECHO_NONE = 0
Addon.ECHO_ERROR = 1
Addon.ECHO_INFO = 2
Addon.ECHO_VERBOSE = 3
Addon.ECHO_DEBUG = 4
Addon.ECHO_LEVELS = {"ERROR", "INFO", "VERBOSE", "DEBUG"}

Addon.LOG_MAX_ENTRIES = 1000

Addon.log = {}

-- Versioning
Addon.CHANNEL_ALPHA = "alpha"
Addon.CHANNEL_BETA = "beta"
Addon.CHANNEL_STABLE = "stable"
Addon.CHANNELS = Util.TblFlip({Addon.CHANNEL_ALPHA, Addon.CHANNEL_BETA, Addon.CHANNEL_STABLE})

Addon.versions = {}
Addon.versionNoticeShown = false
Addon.disabled = {}
Addon.plhUsers = {}

-- Other
Addon.rolls = Util.TblCounter()
Addon.timers = {}

-------------------------------------------------------
--                    Addon stuff                    --
-------------------------------------------------------

-- Called when the addon is loaded
function Addon:OnInitialize()
    self:ToggleDebug(PersoLootRollDebug or self.DEBUG)
    
    self.db = LibStub("AceDB-3.0"):New(Name .. "DB", {
        -- VERSION 6
        profile = {
            -- General
            enabled = true,
            onlyMasterloot = false,
            dontShare = false,
            awardSelf = false,
            bidPublic = false,
            ui = {showRollFrames = true, showActionsWindow = true, showRollsWindow = false},
            
            -- Item filter
            ilvlThreshold = 30,
            ilvlThresholdTrinkets = true,
            ilvlThresholdRings = false,
            pawn = false,
            transmog = false,

            -- Messages
            messages = {
                echo = Addon.ECHO_INFO,
                group = {
                    announce = true,
                    groupType = {lfd = true, party = true, lfr = true, raid = true, guild = true, community = true},
                    roll = true
                },
                whisper = {
                    ask = false,
                    groupType = {lfd = true, party = true, lfr = true, raid = true, guild = false, community = false},
                    target = {friend = false, guild = false, community = false, other = true},
                    answer = true,
                    suppress = false,
                },
                lines = {}
            },

            -- Masterloot
            masterloot = {
                allow = {friend = true, community = true, guild = true, raidleader = false, raidassistant = false, guildgroup = true},
                accept = {friend = false, guildmaster = false, guildofficer = false},
                allowAll = false,
                whitelists = {},
                rules = {
                    timeoutBase = Roll.TIMEOUT,
                    timeoutPerItem = Roll.TIMEOUT_PER_ITEM,
                    bidPublic = false,
                    votePublic = false,
                    needAnswers = {},
                    greedAnswers = {},
                    disenchanter = {},
                    autoAward = false,
                    autoAwardTimeout = Roll.TIMEOUT,
                    autoAwardTimeoutPerItem = Roll.TIMEOUT_PER_ITEM,
                },
                council = {
                    roles = {raidleader = false, raidassistant = false},
                    clubs = {},
                    whitelists = {}
                }
            },

            -- GUI status
            gui = {
                actions = {anchor = "LEFT", v = 10, h = 0}
            }
        },
        -- VERSION 4
        factionrealm = {},
        -- VERSION 4
        char = {
            specs = {true, true, true, true},
            masterloot = {
                council = {
                    clubId = nil
                }
            }
        }
    }, true)
    
    -- Migrate options
    Options.Migrate()

    -- Register chat commands
    self:RegisterChatCommand(Name, "HandleChatCommand")
    self:RegisterChatCommand("plr", "HandleChatCommand")

    -- Minimap icon
    Options.RegisterMinimapIcon()
end

-- Called when the addon is enabled
function Addon:OnEnable()
    -- Register options table
    if not Options.registered then
        Options.Register()
    end

    -- Enable hooks
    self.Hooks.EnableGroupLootRoll()
    self.Hooks.EnableChatLinks()
    self.Hooks.EnableUnitMenus()

    -- Register events
    self.Events.RegisterEvents()

    -- Periodically clear old rolls
    self.timers.clearRolls = self:ScheduleRepeatingTimer(Roll.Clear, Roll.CLEAR)

    -- Start inspecting
    Inspect.Start()
    if not Inspect.timer then
        -- IsInGroup doesn't work right after logging in, so check again after waiting a bit.
        self.timers.inspectStart = self:ScheduleTimer(Inspect.Start, 10)
    end

    -- Update state
    if IsInGroup() then
        self.Events.GROUP_JOINED()
    end
end

-- Called when the addon is disabled
function Addon:OnDisable()
    -- Disable hooks
    self.Hooks.DisableGroupLootRoll()
    self.Hooks.DisableChatLinks()
    self.Hooks.DisableUnitMenus()

    -- Unregister events
    self.Events.UnregisterEvents()

    -- Stop clear timer
    if self.timers.clearRolls then
        self:CancelTimer(self.timers.clearRolls)
    end
    self.timers.clearRolls = nil

    -- Stop inspecting
    if self.timers.inspectStart then
        self:CancelTimer(self.timers.inspectStart)
        self.timers.inspectStart = nil
    end

    -- Update state
    if IsInGroup() then
        self.Events.GROUP_LEFT()
    else
        self:OnTrackingChanged(true)
    end
end

function Addon:ToggleDebug(debug)
    if debug ~= nil then
        self.DEBUG = debug
    else
        self.DEBUG = not self.DEBUG
    end

    PersoLootRollDebug = self.DEBUG

    if self.db then
        self:Info("Debugging " .. (self.DEBUG and "en" or "dis") .. "abled")
    end
end

-------------------------------------------------------
--                   Chat command                    --
-------------------------------------------------------

-- Chat command handling
function Addon:HandleChatCommand(msg)
    local args = {Addon:GetArgs(msg, 10)}
    local cmd = args[1]

    -- Help
    if cmd == "help" then
        self:Help()
    -- Options
    elseif cmd == "options" then
        Options.Show()
    -- Config
    elseif cmd == "config" then
        local name, pre, line = Name, "plr config", msg:sub(cmd:len() + 2)

        -- Handle submenus
        local subs = Util.Tbl("messages", "masterloot", "profiles")
        if Util.In(args[2], subs) then
            name, pre, line = name .. " " .. Util.StrUcFirst(args[2]), pre .. " " .. args[2], line:sub(args[2]:len() + 2)
        end

        LibStub("AceConfigCmd-3.0").HandleCommand(Addon, pre, name, line)

        -- Add submenus as additional options
        if Util.StrIsEmpty(args[2]) then
            for i,v in pairs(subs) do
                local name = Util.StrUcFirst(v)
                local getter = LibStub("AceConfigRegistry-3.0"):GetOptionsTable(Name .. " " .. name)
                print("  |cffffff78" .. v .. "|r - " .. (getter("cmd", "AceConfigCmd-3.0").name or name))
            end
        end

        Util.TblRelease(subs)
    -- Roll
    elseif cmd == "roll" then
        local items, i, item = {}, 1

        while i do
            i, item = next(args, i)
            if i and Item.IsLink(item) then
                tinsert(items, item)
            end
        end

        if not next(items) then
            self:Print(L["USAGE_ROLL"])
        else
            i = table.getn(items) + 2
            local timeout, owner = tonumber(args[i]), args[i+1]
            
            for i,item in pairs(items) do
                item = Item.FromLink(item, owner or "player")
                local roll = Roll.Add(item, owner or Session.GetMasterlooter() or "player", timeout)
                if roll.isOwner then
                    roll:Start()
                else
                    roll:SendStatus(true)
                end
            end
        end
    -- Bid
    elseif cmd == "bid" then
        local owner, item, bid = select(2, unpack(args))
        
        if Util.StrIsEmpty(owner) or Item.IsLink(owner)            -- owner
        or item and not Item.IsLink(item)                          -- item
        or bid and not Util.TblFind(Roll.BIDS, tonumber(bid)) then -- answer
            self:Print(L["USAGE_BID"])
        else
            local roll = Roll.Find(nil, owner, item)
            if roll then
                roll:Bid(bid)
            end
        end
    -- Trade
    elseif cmd == "trade" then
        Trade.Initiate(args[2] or "target")
    -- Rolls/None
    elseif cmd == "rolls" or not cmd then
        GUI.Rolls.Show()
    -- Toggle debug mode
    elseif cmd == "debug" then
        self:ToggleDebug()
    -- Export debug log
    elseif cmd == "log" then
        self:LogExport()
    -- Update and export trinket list
    elseif cmd == "trinkets" and Item.UpdateTrinkets then
        Item.UpdateTrinkets()
    -- Update and export instance list
    elseif cmd == "instances" and Util.ExportInstances then
        Util.ExportInstances()
    -- Unknown
    else
        self:Err(L["ERROR_CMD_UNKNOWN"], cmd)
    end
end

function Addon:Help()
    self:Print(L["HELP"])
end

-------------------------------------------------------
--                       State                       --
-------------------------------------------------------

-- Check if we should currently track loot etc.
function Addon:IsTracking(unit, inclCompAddons)
    if not unit or Unit.IsSelf(unit) then
        return self.db.profile.enabled
           and (not self.db.profile.onlyMasterloot or Session.GetMasterlooter())
           and IsInGroup()
           and Util.In(GetLootMethod(), "freeforall", "roundrobin", "personalloot", "group")
    else
        unit = Unit.Name(unit)
        return self.versions[unit] and not self.disabled[unit] or inclCompAddons and self.plhUsers[unit]
    end
end

-- Tracking state potentially changed
function Addon:OnTrackingChanged(sync)
    local isTracking = self:IsTracking()

    -- Let others know
    if not Util.BoolXOR(isTracking, self.disabled[UnitName("player")]) then
        Comm.Send(Comm["EVENT_" .. (isTracking and "ENABLE" or "DISABLE")])
    end

    -- Start/Stop tracking process
    if sync then
        if isTracking then
            Comm.Send(Comm.EVENT_SYNC)
            Inspect.Queue()
        else
            Util.TblIter(self.rolls, Roll.Clear)
            Inspect.Clear()
        end
    end

    Inspect[isTracking and "Start" or "Stop"]()
end

-- Set a unit's version string
function Addon:SetVersion(unit, version)
    self.versions[unit] = version
    self.plhUsers[unit] = nil

    if not version then
        self.disabled[unit] = nil
    elseif not self.versionNoticeShown then
        if self:CompareVersion(version) == 1 then
            self:Info(L["VERSION_NOTICE"])
            self.versionNoticeShown = true
        end
    end
end

-- Get major, channel and minor versions for the given version string or unit
function Addon:GetVersion(versionOrUnit)
    local t = type(versionOrUnit)
    local version = (not versionOrUnit or UnitIsUnit(versionOrUnit, "player")) and self.VERSION
                 or (t == "number" or t == "string" and tonumber(versionOrUnit:sub(1, 1))) and versionOrUnit
                 or self.versions[Unit.Name(versionOrUnit)]

    t = type(version)
    if t == "number" then
        return version, Addon.CHANNEL_STABLE, 0
    elseif t == "string" then
        local version, channel, revision = version:match("([%d.]+)-(%a+)(%d+)")
        return tonumber(version), channel, tonumber(revision)
    end
end

-- Get 1 if the version is higher, -1 if the version is lower or 0 if they are the same or on non-comparable channels
function Addon:CompareVersion(versionOrUnit)
    local version, channel, revision = self:GetVersion(versionOrUnit)
    if version then
        local myVersion, myChannel, myRevision = self:GetVersion()
        local channelNum, myChannelNum = Addon.CHANNELS[channel], Addon.CHANNELS[myChannel]

        if channel == myChannel then
            return version == myVersion and Util.Compare(revision, myRevision) or Util.Compare(version, myVersion)
        elseif channelNum and myChannelNum then
            return version >= myVersion and channelNum > myChannelNum and 1
                or version <= myVersion and channelNum < myChannelNum and -1
                or 0
        else
            return 0
        end
    end
end

-- Get the number of addon users in the group
function Addon:GetNumAddonUsers(inclCompAddons)
    local n = Util.TblCount(self.versions) - Util.TblCount(self.disabled)
    if inclCompAddons then
        n = n + Util.TblCount(Addon.plhUsers)
    end
    return n
end

-------------------------------------------------------
--                      Logging                      --
-------------------------------------------------------

function Addon:Echo(lvl, line, ...)
    if lvl == self.ECHO_DEBUG then
        local args = Util.Tbl(line, ...)
        for i,v in pairs(args) do
            if type(v) ~= "string" then args[i] = Util.ToString(v) end
        end
        line = strjoin(", ", unpack(args))
        Util.TblRelease(args)
    else
        line = line:format(...)
    end

    self:Log(lvl, line)

    if self.db.profile.messages.echo >= lvl then
        self:Print(line)
    end
end

function Addon:Err(...)
    self:Echo(self.ECHO_ERROR, ...)
end

function Addon:Info(...)
    self:Echo(self.ECHO_INFO, ...)
end

function Addon:Verbose(...)
    self:Echo(self.ECHO_VERBOSE, ...)
end

function Addon:Debug(...)
    self:Echo(self.ECHO_DEBUG, ...)
end

function Addon:Assert(cond, ...)
    if not cond and self.db.profile.messages.echo >= self.ECHO_DEBUG then
        if type(...) == "function" then
            self:Echo(self.ECHO_DEBUG, (...)(select(2, ...)))
        else
            self:Echo(self.ECHO_DEBUG, ...)
        end
    end
end

-- Add an entry to the debug log
function Addon:Log(lvl, line)
    tinsert(self.log, ("[%f] %s: %s"):format(GetTime(), self.ECHO_LEVELS[lvl or self.ECHO_INFO], line or "-"))
    while #self.log > self.LOG_MAX_ENTRIES do
        Util.TblShift(self.log)
    end
end

-- Export the debug log
function Addon:LogExport()
    local f = GUI("Frame").SetLayout("Fill").SetTitle(Name .. " - Export log").Show()()
    GUI("MultiLineEditBox").DisableButton(true).SetLabel().SetText(Util.TblConcat(self.log, "\n")).AddTo(f)
end

-------------------------------------------------------
--                       Timer                       --
-------------------------------------------------------

function Addon:ExtendTimerTo(timer, to)
    if not timer.canceled and timer.ends - GetTime() < to then
        Addon:CancelTimer(timer)
        local fn = timer.looping and Addon.ScheduleRepeatingTimer or Addon.ScheduleTimer
        timer = fn(Addon, timer.func, to, unpack(timer, 1, timer.argsCount))
        return timer, true
    else
        return timer, false
    end
end

function Addon:ExtendTimerBy(timer, by)
    return self:ExtendTimerTo(timer, (timer.ends - GetTime()) + by)
end

function Addon:TimerIsRunning(timer)
    return timer and not timer.canceled and timer.ends > GetTime()
end