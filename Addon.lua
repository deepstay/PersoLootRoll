--[[
TODO:
- Only specific specs
- Transmog mode: Check appearance, don't cancel rolls for items that some ppl could wear but have a higher ilvl, prompt to answer only when someone asks for the item
- Block all trades and whispers
- Custom messages
]]

local Addon = LibStub("AceAddon-3.0"):GetAddon(PLR_NAME)
local L = LibStub("AceLocale-3.0"):GetLocale(PLR_NAME)
local Util = Addon.Util
local Item = Addon.Item

-------------------------------------------------------
--                     Constants                     --
-------------------------------------------------------

-- Version
Addon.VERSION = 1

-- Enable or disable debug stuff
Addon.DEBUG = true

-- Echo levels
Addon.ECHO_NONE = 0
Addon.ECHO_ERROR = 1
Addon.ECHO_INFO = 2
Addon.ECHO_VERBOSE = 3
Addon.ECHO_DEBUG = 4

Addon.rolls = Util.TblCounter()
Addon.versions = {}
Addon.timers = {}

-- Masterloot
Addon.masterlooter = nil
Addon.masterlooting = {}

-------------------------------------------------------
--                    Addon stuff                    --
-------------------------------------------------------

-- Called when the addon is loaded
function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New(PLR_NAME .. "DB", {
        profile = {
            enabled = true,
            echo = Addon.ECHO_INFO,
            announce = {lfd = true, party = true, lfr = true, raid = true, guild = true},
            roll = true,
            whisper = {
                group = {lfd = true, party = true, lfr = true, raid = true, guild = false},
                target = {friend = false, guild = false, other = true}
            },
            awardSelf = false,
            masterloot = {
                allow = {friend = true, guild = true, guildgroup = true},
                accept = {friend = false, guildmaster = false, guildofficer = false},
                whitelist = {},
                allowAll = false
            },
            answer = true
        }
    }, true)
    
    -- Register options

    local config = LibStub("AceConfig-3.0")
    local dialog = LibStub("AceConfigDialog-3.0")

    -- We need this to be able to define the order of these options
    local groupKeys = {"party", "raid", "guild", "lfd", "lfr"}
    local groupValues = {PARTY, RAID, GUILD_GROUP, LOOKING_FOR_DUNGEON_PVEFRAME, RAID_FINDER_PVEFRAME}

    -- General
    local it = Util.Iter()
    config:RegisterOptionsTable(PLR_NAME, {
        type = "group",
        args = {
            enable = {
                name = L["OPT_ENABLE"],
                desc = L["OPT_ENABLE_DESC"],
                type = "toggle",
                set = function (_, val)
                    self.db.profile.enabled = val
                    self:Print(L[val and "ENABLED" or "DISABLED"])
                end,
                get = function (_) return self.db.profile.enabled end
            },
        }
    })
    self.configFrame = dialog:AddToBlizOptions(PLR_NAME)

    -- Messages
    it = Util.Iter()
    config:RegisterOptionsTable(PLR_NAME .. "_messages", {
        name = L["OPT_MESSAGES"],
        type = "group",
        args = {
            -- Chat
            echo = {
                name = L["OPT_ECHO"],
                desc = L["OPT_ECHO_DESC"],
                type = "select",
                order = it(),
                values = {
                    [Addon.ECHO_NONE] = L["OPT_ECHO_NONE"],
                    [Addon.ECHO_ERROR] = L["OPT_ECHO_ERROR"],
                    [Addon.ECHO_INFO] = L["OPT_ECHO_INFO"],
                    [Addon.ECHO_VERBOSE] = L["OPT_ECHO_VERBOSE"],
                    [Addon.ECHO_DEBUG] = L["OPT_ECHO_DEBUG"]
                },
                set = function (info, val) self.db.profile.echo = val end,
                get = function () return self.db.profile.echo end
            },
            groupchat = {type = "header", order = it(), name = L["OPT_GROUPCHAT"]},
            groupchatDesc = {type = "description", order = it(), name = L["OPT_GROUPCHAT_DESC"] .. "\n"},
            groupchatAnnounce = {
                name = L["OPT_GROUPCHAT_ANNOUNCE"],
                desc = L["OPT_GROUPCHAT_ANNOUNCE_DESC"],
                type = "multiselect",
                order = it(),
                values = groupValues,
                set = function (_, key, val) self.db.profile.announce[groupKeys[key]] = val end,
                get = function (_, key) return self.db.profile.announce[groupKeys[key]] end,
            },
            groupchatRoll = {
                name = L["OPT_GROUPCHAT_ROLL"],
                desc = L["OPT_GROUPCHAT_ROLL_DESC"],
                descStyle = "inline",
                type = "toggle",
                order = it(),
                set = function (_, val) self.db.profile.roll = val end,
                get = function () return self.db.profile.roll end,
                width = "full"
            },
            whisper = {type = "header", order = it(), name = L["OPT_WHISPER"]},
            whisperDesc = {type = "description", order = it(), name = L["OPT_WHISPER_DESC"] .. "\n"},
            whisperGroup = {
                name = L["OPT_WHISPER_GROUP"],
                desc = L["OPT_WHISPER_GROUP_DESC"],
                type = "multiselect",
                order = it(),
                values = groupValues,
                set = function (_, key, val) self.db.profile.whisper.group[groupKeys[key]] = val end,
                get = function (_, key) return self.db.profile.whisper.group[groupKeys[key]] end
            },
            whisperTarget = {
                name = L["OPT_WHISPER_TARGET"],
                desc = L["OPT_WHISPER_TARGET_DESC"],
                type = "multiselect",
                order = it(),
                values = {
                    friend = FRIEND,
                    guild = GUILD,
                    other = OTHER
                },
                set = function (_, key, val) self.db.profile.whisper.target[key] = val end,
                get = function (_, key) return self.db.profile.whisper.target[key] end
            },
            whisperAnswer = {
                name = L["OPT_WHISPER_ANSWER"],
                desc = L["OPT_WHISPER_ANSWER_DESC"],
                descStyle = "inline",
                type = "toggle",
                order = it(),
                set = function (_, val) self.db.profile.answer = val end,
                get = function () return self.db.profile.answer end,
                width = "full"
            }
        }
    })
    dialog:AddToBlizOptions(PLR_NAME .. "_messages", L["OPT_MESSAGES"], PLR_NAME)

    local allowKeys = {"friend", "guild", "guildgroup"}
    local allowValues = {FRIEND, GUILD, GUILD_GROUP}

    local acceptKeys = {"friend", "guildleader", "guildofficer"}
    local acceptValues = {FRIEND, L["GUILD_MASTER"], L["GUILD_OFFICER"]}

    -- Loot method
    it = Util.Iter()
    config:RegisterOptionsTable(PLR_NAME .. "_lootmethod", {
        name = L["OPT_LOOT_METHOD"],
        type = "group",
        args = {
            awardSelf = {
                name = L["OPT_AWARD_SELF"],
                desc = L["OPT_AWARD_SELF_DESC"],
                descStyle = "inline",
                type = "toggle",
                order = it(),
                set = function (_, val) self.db.profile.awardSelf = val end,
                get = function () return self.db.profile.awardSelf end,
                width = "full"
            },
            masterloot = {type = "header", order = it(), name = L["OPT_MASTERLOOT"]},
            masterlootDesc = {type = "description", order = it(), name = L["OPT_MASTERLOOT_DESC"] .. "\n"},
            masterlootStart = {
                name = L["OPT_MASTERLOOT_START"],
                type = "execute",
                order = it(),
                func = function () self:SetMasterlooter("player") end
            },
            masterlootStop = {
                name = L["OPT_MASTERLOOT_STOP"],
                type = "execute",
                order = it(),
                func = function () self:SetMasterlooter(nil) end
            },
            ["space" .. it()] = {type = "description", order = it(0), name = " ", cmdHidden = true, dropdownHidden = true},
            masterlootAllow = {
                name = L["OPT_MASTERLOOT_ALLOW"],
                desc = L["OPT_MASTERLOOT_ALLOW_DESC"],
                type = "multiselect",
                order = it(),
                values = allowValues,
                set = function (_, key, val) self.db.profile.masterloot.allow[allowKeys[key]] = val end,
                get = function (_, key) return self.db.profile.masterloot.allow[allowKeys[key]] end
            },
            masterlootWhitelist = {
                name = L["OPT_MASTERLOOT_WHITELIST"],
                desc = L["OPT_MASTERLOOT_WHITELIST_DESC"],
                type = "input",
                order = it(),
                set = function (_, val)
                    local t = {} for v in val:gmatch("[^%s%d%c,;:_<>|/\\]+") do t[v] = true end
                    self.db.profile.masterloot.whitelist = t
                end,
                get = function () return Util(self.db.profile.masterloot.whitelist).Keys().Sort().Concat(", ")() end,
                width = "full"
            },
            masterlootAllowAll = {
                name = L["OPT_MASTERLOOT_ALLOW_ALL"],
                desc = L["OPT_MASTERLOOT_ALLOW_ALL_DESC"],
                descStyle = "inline",
                type = "toggle",
                order = it(),
                set = function (_, val) self.db.profile.masterloot.allowAll = val end,
                get = function () return self.db.profile.masterloot.allowAll end,
                width = "full"
            },
            ["space" .. it()] = {type = "description", order = it(0), name = " ", cmdHidden = true, dropdownHidden = true},
            masterlootAccept = {
                name = L["OPT_MASTERLOOT_ACCEPT"],
                desc = L["OPT_MASTERLOOT_ACCEPT_DESC"],
                type = "multiselect",
                order = it(),
                values = acceptValues,
                set = function (_, key, val) self.db.profile.masterloot.accept[acceptKeys[key]] = val end,
                get = function (_, key) return self.db.profile.masterloot.accept[acceptKeys[key]] end
            }
        }
    })
    dialog:AddToBlizOptions(PLR_NAME .. "_lootmethod", L["OPT_LOOT_METHOD"], PLR_NAME)

    -- Profiles
    config:RegisterOptionsTable(PLR_NAME .. "_profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
    dialog:AddToBlizOptions(PLR_NAME .. "_profiles", "Profiles", PLR_NAME)
end

-- Called when the addon is enabled
function Addon:OnEnable()
    -- Enable hooks
    self.Hooks.EnableGroupLootRoll()
    self.Hooks.EnableChatLinks()
    self.Hooks.EnableUnitMenus()

    -- Register events
    self.Events.RegisterEvents()

    -- Register chat commands
    self:RegisterChatCommand(PLR_NAME, "HandleChatCommand")
    self:RegisterChatCommand("plr", "HandleChatCommand")

    -- Periodically clear old rolls
    self.timers.clearRolls = self:ScheduleRepeatingTimer(self.Roll.Clear, self.Roll.CLEAR)

    -- Start inspecting
    self.Inspect.Start()
    if not self.Inspect.timer then
        -- IsInGroup doesn't work right after logging in, so check again after waiting a bit.
        self.timers.inspectStart = self:ScheduleTimer(self.Inspect.Start, 10)
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
    self.Inspect.Clear()
    if self.timers.inspectStart then
        self:CancelTimer(self.timers.inspectStart)
        self.timers.inspectStart = nil
    end
end

-- Check if we should currently track loot etc.
function Addon:IsTracking()
    local methods = {freeforall = true, roundrobin = true, personalloot = true}
    return self.db.profile.enabled and IsInGroup() and methods[GetLootMethod()]
end

-------------------------------------------------------
--                   Chat command                    --
-------------------------------------------------------

-- Chat command handling
function Addon:HandleChatCommand (msg)
    local args = {Addon:GetArgs(msg, 10)}
    local cmd = args[1]

    Util.Switch(cmd) {
        ["help"] = function () self:Help() end,
        ["options"] = function () self:ShowOptions() end,
        ["config"] = function () LibStub("AceConfigCmd-3.0").HandleCommand(Addon, "plr config", PLR_NAME, msg:sub(7)) end,
        ["rolls"] = self.GUI.Rolls.Show,
        ["roll"] = function  ()
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
                    self.Roll.Add(item, owner, nil, timeout):Start()
                end
            end
        end,
        ["bid"] = function ()
            local owner, item, answer = select(2, unpack(args))
            
            if Util.StrEmpty(owner) or Item.IsLink(owner)                            -- owner
            or item and not Item.IsLink(item)                                        -- item
            or answer and not Util.TblFind(self.Roll.ANSWERS, tonumber(answer)) then -- answer
                self:Print(L["USAGE_BID"])
            else
                local roll = self.Roll.Find(nil, owner, item)
                if roll then
                    roll:Bid(answer)
                else
                    self.Comm.ChatBid(owner, item)
                end
            end
        end,
        -- TODO
        ["trade"] = function ()
            local target = args[2]
            Addon.Trade.Initiate(target or "target")
        end,
        -- TODO: DEBUG
        ["test"] = function ()
            local link = "|cffa335ee|Hitem:152412::::::::110:105::4:3:3613:1457:3528:::|h[Depraved Machinist's Footpads]|h|r"
            local roll = Addon.Roll.Add(link):Start():Bid(Addon.Roll.ANSWER_PASS):Bid(Addon.Roll.ANSWER_NEED, "Zhael", true)
        end,
        default = self.GUI.Rolls.Show
    }
end

function Addon:ShowOptions()
    -- Have to call it twice because of a blizzard UI bug
    InterfaceOptionsFrame_OpenToCategory(self.configFrame)
    InterfaceOptionsFrame_OpenToCategory(self.configFrame)
end

function Addon:Help()
    self:Print(L["HELP"])
end

-------------------------------------------------------
--                     Masterloot                    --
-------------------------------------------------------

-- Set (or reset) the masterlooter
function Addon:SetMasterlooter(unit, silent)
    if self.masterlooter then
        if unit and UnitIsUnit(self.masterlooter, unit) then
            return
        end

        wipe(self.masterlooting)
        if not silent then
            self.Comm.Send(self.Comm.EVENT_MASTERLOOT_STOP, nil, UnitIsUnit(self.masterlooter, "player") and self.Comm.TYPE_GROUP or self.masterlooter)
        end
    end
    
    self.masterlooter = unit

    if not silent and unit then
        if UnitIsUnit(self.masterlooter, "player") then
            self.Comm.Send(self.Comm.EVENT_MASTERLOOT_ASK)
        else
            self.Comm.Send(self.Comm.EVENT_MASTERLOOT_ACK, nil, unit)
        end
    end

    self.GUI.Rolls.Update()
end

-- Check if the unit (or the player) is our masterlooter
function Addon:IsMasterlooter(unit)
    return self.masterlooter and UnitIsUnit(self.masterlooter, unit or "player")
end

-------------------------------------------------------
--                       Other                       --
-------------------------------------------------------

-- Console output

function Addon:Echo(lvl, ...)
    if self.db.profile.echo >= lvl then
        self:Print(...)
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

-- Timer

function Addon:ExtendTimerTo(timer, to)
    if not timer.canceled and timer.ends - GetTime() < to then
        Addon:CancelTimer(timer)
        local fn = timer.looping and Addon.ScheduleRepeatingTimer or Addon.ScheduleTimer
        timer = fn(Addon, timer.func, to, unpack(timer, 1, timer.argsCount))
    end

    return timer
end

function Addon:ExtendTimerBy(timer, by)
    return self:ExtendTimerTo(timer, (timer.ends - GetTime()) + by)
end

function Addon:TimerIsRunning(timer)
    return timer and not timer.canceled and timer.ends > GetTime()
end