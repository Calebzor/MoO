-----------------------------------------------------------------------------------------------
-- Client Lua Script for MoO
-- Created by Caleb calebzor@gmail.com
-----------------------------------------------------------------------------------------------

--[[-------------------------------------------------------------------------------------------
TODO:
    the one button should use some kind if saved group setup to fix positions for the group container

    add a help that describes how majority of the addon works

    fix arcane shock tracking since no event fires for it because it is not a CC and ModifyInterruptArmor still does not fire for other units

    have a one button setup for raids for class based groups
    have a one button setup for like 5 man dungeons
    only show my group option

    notification window when receiving group sync so people know the windows are on top of each other in case of multiple groups

    hook into bossmods

    request sync button that only goes to that one guy

    I think there might be a combatlog event now for LAS changes, might want to look into that so if we can track others LAS change
    maybe it fires what they changed to so we can track abilities from that, or if that data is not there at least we can wipe what we tracked
    from them so far from the combat log, that way making sure, abilities not used by them are not tracked anymore.

<23:51:00> "Trasgress": Engineer bot, the LAS name is called Bruiser bot
<23:51:15> "Trasgress": After you use it it summons a bot and gives you a reactive abilkity that has a 30s cd
<23:51:41> "Trasgress": that ability name is [Bot Ability] Blitz
<23:51:45> "Trasgress": interrupts and taunts
<23:52:14> "Trasgress": http://i.imgur.com/7Pm82bW.png
<23:52:19> "Trasgress": screenshot of the ability name

Apollo.SetConsoleVariable("cmbtlog.disableOtherPlayers", false)


]]---------------------------------------------------------------------------------------------

require "ActionSetLib"
require "GameLib"
require "GroupLib"
require "ICCommLib"
require "CColor"
require "AbilityBook"
require "Tooltip"

local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local table = table
local type = type
local string = string
local tonumber = tonumber
local os = os
local floor = math.floor
local Apollo = Apollo
local ActionSetLib = ActionSetLib
local CombatFloater = CombatFloater
local GameLib = GameLib
local GroupLib = GroupLib
local ICCommLib = ICCommLib
local AbilityBook = AbilityBook
local CColor = CColor
local Tooltip = Tooltip
local Print = Print
local Event_FireGenericEvent = Event_FireGenericEvent
local _ = _

local MoO = {}
local addon = MoO

local sVersion = "9.1.1.8"

local function hexToCColor(color, a)
    if not a then a = 1 end
    local r = tonumber(string.sub(color,1,2), 16) / 255
    local g = tonumber(string.sub(color,3,4), 16) / 255
    local b = tonumber(string.sub(color,5,6), 16) / 255
    return CColor.new(r,g,b,a)
end

local tColor = {
    yellow = hexToCColor("fff600"),
    orange = hexToCColor("feb408"),
    red = hexToCColor("c6002a"),
    green = hexToCColor("01a825"),
    blue = hexToCColor("00b0d8"),
}

-- we keep track of ignored spells instead of looking at what we want to track because it is faster to do a table lookup than to call GameLib.GetSpell twice for every combatlog event
local ignoredSpellIds = {
    -- dashes
    [25293] = true,
    [25294] = true,
    [25295] = true,
    [25296] = true,

    [42683] = true, -- pounce

    [44602] = true, -- razor storm
    [59941] = true, -- reaver
    [39941] = true, -- reaver

    [1316] = true, -- sprint

    [54071] = true, -- slow it down - whatever that is
}

local tPartyLASInterrupts = {} -- for some reason this has to be here and not inside our addons metatable, else the widget does no update for groups created by OnRestore -- should probably figure out why at some point

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function addon:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.nTimer = 0
    self.nBarTimeIncrement = 0.033
    self.tGroups = {}
    self.tCurrLAS = nil
    self.tLastLASInterrupts = nil
    self.bAllowLASInterruptCheck = false
    self.uPlayer = nil
    self.sChannelName = nil
    self.tCooldowns = {}

    self.tColors = {
        cBG = {r=1,g=0,b=0,a=0.5},
        cProgress = {r=0,g=1,b=1,a=0.5},
        cFull = {r=0,g=1,b=0.041,a=0.5}
    }

    self.bAllGroupsLocked = nil
    self.tVersionData = {}
    self.bVersionCheckAllowed = true
    self.bAcceptGroupSync = true
    self.bAlwaysBroadcastCooldowns = true
    self.tSavedGroups = {}

    return o
end

function addon:Init()
    Apollo.RegisterAddon(self)
end


-----------------------------------------------------------------------------------------------
-- MoO OnLoad
-----------------------------------------------------------------------------------------------
function addon:OnLoad()
    Apollo.RegisterEventHandler("MoO_OnSlashCommand", "MoO_OnSlashCommand", self)
    Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
    Apollo.RegisterSlashCommand("moo", "MoO_OnSlashCommand", self)

    Apollo.RegisterEventHandler("Group_Join", "OnGroupJoin", self)
    Apollo.RegisterEventHandler("Group_Left", "OnGroupLeft", self)
    Apollo.RegisterEventHandler("Group_Updated", "OnGroupUpdated", self)

    Apollo.RegisterEventHandler("CombatLogCCState", "OnCombatLogCCState", self)
    Apollo.RegisterEventHandler("CombatLogInterrupted", "OnCombatLogInterrupted", self)

    Apollo.RegisterEventHandler("AbilityBookChange", "OnAbilityBookChange", self)
    Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", "OnCombatLogModifyInterruptArmor", self)

    Apollo.RegisterTimerHandler("OneSecTimer", "OnOneSecTimer", self)

    Apollo.RegisterTimerHandler("DelayedInit", "DelayedInit", self)
    Apollo.CreateTimer("DelayedInit", 1, false)

    self.CommChannel = nil
    self.wOptions = nil
    self.wHelp = nil
    self.wOneButton = nil
end

function addon:DelayedInit()
    self.uPlayer = GameLib.GetPlayerUnit()

    if self.uPlayer then -- bit hacky, but let's say if the player unit is present we can start working
        if self.tActiveGroupData and GroupLib.InGroup() then
            self:LoadSavedGroups(self.tActiveGroupData)
        end
        self.tLastLASInterrupts = self:MyLASInterrupts(true)
        self.bAllowLASInterruptCheck = true
    else
        Apollo.CreateTimer("DelayedInit", 1, false)
    end
end

function addon:OnInterfaceMenuListHasLoaded()
    Event_FireGenericEvent("InterfaceMenuList_NewAddOn", "MoO", { "MoO_OnSlashCommand", "", ""})
end

local function getFirstIndexOfIndexedTablqe(t)
    for k, v in ipairs(t) do
        if not v then
            return k
        end
    end
    return false
end

local function getMemberOfGroupIndex(sGroupName, sMemberName)
    if not addon.tGroups[sGroupName] then return false end
    for k, v in ipairs(addon.tGroups[sGroupName].BarContainers) do
        if v.name == sMemberName then
            return k
        end
    end
    return false
end

-----------------------------------------------------------------------------------------------
-- Color stuff
-----------------------------------------------------------------------------------------------

local function CColorToTable(tColor)
    return { r = tColor.r, g = tColor.g, b = tColor.b, a = tColor.a }
end

local function TableToCColor(tColor)
    return CColor.new(tColor.r, tColor.g, tColor.b, tColor.a)
end

local function colorCallback(tData)
    addon.tColors[tData.sName] = CColorToTable(tData.cColor)
    for sGroupName, tGroupData in pairs(addon.tGroups) do
        for nMemberIndexInGroup, tMemberData in pairs(addon.tGroups[sGroupName].BarContainers) do
            for nBarIndex, tBar in pairs(addon.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                if tData.sName == "cBG" then
                    tBar.frame:SetBGColor(tData.cColor)
                elseif tData.sName == "cFull" then
                    tBar.frame:SetBarColor(tData.cColor)
                end
            end
        end
    end
end

function addon:OnChangeColor(wHandler)
    local color = TableToCColor(self.tColors[wHandler:GetName()])
    if ColorPicker then
        ColorPicker.AdjustCColor(color, true, colorCallback, {cColor = color, sName = wHandler:GetName()})
    else
        local wPopUp = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
        wPopUp:SetStyle("Escapable", true)
        wPopUp:SetData({ type = "PopUp"})
        wPopUp:FindChild("Title"):SetText("Notification")
        wPopUp:FindChild("HelpText"):SetText("You don't have the ColorPicker addon enabled. This features is not available without it. Search for 'ColorPicker' on wildstar.curseforge.com if you don't have it already.")
        wPopUp:FindChild("Yes"):SetText("OK")
        wPopUp:FindChild("No"):SetText("Close")
    end
end

-----------------------------------------------------------------------------------------------
-- MoO Functions
-----------------------------------------------------------------------------------------------

function addon:TrackCooldown(unitCaster, splCallingSpell)
    if not unitCaster:IsInYourGroup() or ignoredSpellIds[splCallingSpell:GetId()] then return end
    local sPlayerName = unitCaster:GetName()
    local nSpellId = splCallingSpell:GetId()
    if not self.tCooldowns[sPlayerName] then self.tCooldowns[sPlayerName] = {} end
    if sPlayerName and nSpellId then
        self.tCooldowns[sPlayerName][nSpellId] = os.time()
    end
end

-----------------------------------------------------------------------------------------------
-- Cast Info stuff
-----------------------------------------------------------------------------------------------

function addon:UpdateCastInfoForAbility(sMemberName, sSpellName, sText)
    for sGroupName, tGroupData in pairs(self.tGroups) do
        for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
            if tMemberData.name == sMemberName then
                for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                    if GameLib.GetSpell(tBar.nSpellId):GetName() == sSpellName then
                        tBar.frame:FindChild("CastInfo"):SetText(sText)
                    end
                end
            end
        end
    end
end

--[[
  CombatFloater = <20>{
    AddDigitSpriteSet = <function 202>,
    AddTextBGSprite = <function 203>,
    CodeEnumCCStateApplyRulesResult = {
      DiminishingReturns_TriggerCap = 9,
      InvalidCCState = 1,
      NoTargetSpecified = 2,
      Ok = 0,
      Stacking_DoesNotStack = 7,
      Stacking_ShorterDuration = 8,
      Target_Immune = 3,
      Target_InfiniteInterruptArmor = 4,
      Target_InterruptArmorBlocked = 6,
      Target_InterruptArmorReduced = 5
    },
]]--

local function updatePartyLASInterruptsFromCombatLogEvent(unitCaster, splCallingSpell)
    if not unitCaster:IsInYourGroup() then return end -- not a group member -> we don't care
    if ignoredSpellIds[splCallingSpell:GetId()] then return end -- that spellId is something we don't want to track
    local sSourceName = unitCaster:GetName()
    if tPartyLASInterrupts[sSourceName] then
        for nIndex, nSpellId in ipairs(tPartyLASInterrupts[sSourceName]) do
            if nSpellId == splCallingSpell:GetId() then return end  --don't do anything else if that exact spellId was already in the database -- XXX note: think about switching the database into table where keys are spellIds so it is just a lookup
        end
    end

    if tPartyLASInterrupts[sSourceName] and #tPartyLASInterrupts[sSourceName] > 0 then -- this player already has data so we gonna remove old spellId so we can use the one we just saw in case it didn't match
        for nIndex, nSpellId in ipairs(tPartyLASInterrupts[sSourceName]) do
            if GameLib.GetSpell(nSpellId):GetName() == splCallingSpell:GetName() then
                tPartyLASInterrupts[sSourceName][nIndex] = nil
            end
        end
    else
        tPartyLASInterrupts[sSourceName] = {} -- initialize the table so we don't error when we try to add it
    end
    table.insert(tPartyLASInterrupts[sSourceName], splCallingSpell:GetId())
end

function addon:OnCombatLogCCState(tEventArgs)
    if tEventArgs.unitCaster then
        self:TrackCooldown(tEventArgs.unitCaster, tEventArgs.splCallingSpell)
        if tEventArgs.eResult == CombatFloater.CodeEnumCCStateApplyRulesResult.Target_InterruptArmorReduced then -- CombatFloater.CodeEnumCCStateApplyRulesResult.Target_InterruptArmorReduced is 5 -- interrupt armor reduced while a cast was ongoing

            if tEventArgs.unitTarget and tEventArgs.unitTarget:IsCasting() then
                local perc = floor(tEventArgs.unitTarget:GetCastElapsed()*100/tEventArgs.unitTarget:GetCastDuration())
                self:UpdateCastInfoForAbility(tEventArgs.unitCaster:GetName(), tEventArgs.splCallingSpell:GetName(), ("-%d IA during %s%% %s cast"):format(tEventArgs.nInterruptArmorHit, perc, tEventArgs.unitTarget:GetCastName()))
            elseif tEventArgs.unitTarget and not tEventArgs.unitTarget:IsCasting() then
                self:UpdateCastInfoForAbility(tEventArgs.unitCaster:GetName(), tEventArgs.splCallingSpell:GetName(), ("-%d IA"):format(tEventArgs.nInterruptArmorHit))
            end
            --self:SendCommMessage({type = "CCState", nSpellId = tEventArgs.splCallingSpell:GetId(), nInterruptArmorHit = tEventArgs.nInterruptArmorHit, perc = perc, cast = tEventArgs.unitTarget:GetCastName()}) -- we send spellId due to future localization concerns, this adds extra work but will help in the future, -- XXX except for CastName cuz there is not CastId yet :S

        end
        updatePartyLASInterruptsFromCombatLogEvent(tEventArgs.unitCaster, tEventArgs.splCallingSpell)
    end
end

-- /eval Apollo.SetConsoleVariable("cmbtlog.disableModifyInterruptArmor", true)
function addon:OnCombatLogModifyInterruptArmor(tEventArgs)
    -- this does not fire for other units as of UI patch 2 so we sync
end

function addon:OnCombatLogInterrupted(tEventArgs)
    if tEventArgs.unitCaster then
        self:TrackCooldown(tEventArgs.unitCaster, tEventArgs.splInterruptingSpell)
        self:UpdateCastInfoForAbility(tEventArgs.unitCaster:GetName(), tEventArgs.splInterruptingSpell:GetName(), ("Interrupted: %s"):format(tEventArgs.splCallingSpell:GetName()))
        updatePartyLASInterruptsFromCombatLogEvent(tEventArgs.unitCaster, tEventArgs.splInterruptingSpell)
    end
    --self:SendCommMessage({type = "Interrupt", nSpellId = tEventArgs.splInterruptingSpell:GetId(), cast = tEventArgs.splCallingSpell:GetId()})
end

-----------------------------------------------------------------------------------------------
-- Event and button handlers
-----------------------------------------------------------------------------------------------

function addon:OnEditMemberButton(wHandler)
    local sMemberName = wHandler:GetParent():GetData() and wHandler:GetParent():GetData().sMemberName
    self:OpenEditMember(wHandler:GetParent():GetParent():GetData().sGroupName, sMemberName)
end

function addon:OpenEditMember(sGroupName, sMemberName)
    local wEditMember = Apollo.LoadForm("MoO.xml", "EditMemberContainer", nil, self)
    wEditMember:FindChild("GroupName"):SetText(sGroupName)
    local wMemberSelector = Apollo.LoadForm("MoO.xml", "DropDownWidget", wEditMember:FindChild("MemberSelectorContainer"), self)
    wMemberSelector:FindChild("MainButton"):SetText(sMemberName and sMemberName or "Click to select a member")
    if sMemberName then
        self:MemberSelectedPopulateAbilityList(wEditMember, sMemberName)
    end
end

function addon:OnGenerateSpellTooltip(wndHandler, wndControl, eToolTipType, x, y)
    if wndControl == wndHandler then
        Tooltip.GetSpellTooltipForm(self, wndHandler, wndHandler:GetData())
    end
end

function addon:MemberSelectedPopulateAbilityList(wContainer, sMemberName)
    local nNumOfSpells
    local bHaveLASAbilitiesForMember
    for sMemberNames, tSpells in pairs(tPartyLASInterrupts) do
        if sMemberNames == sMemberName then
            nNumOfSpells = #tSpells
            if nNumOfSpells > 0 then
                bHaveLASAbilitiesForMember = true
            end
            wContainer:FindChild("SpellSelectorContainer"):SetText("")
            wContainer:FindChild("SpellSelectorContainer"):DestroyChildren()
            for _, nSpellId in ipairs(tSpells) do
                local wCurrSpell = Apollo.LoadForm("MoO.xml", "SpellbookItem", wContainer:FindChild("SpellSelectorContainer"), self)
                local spell = GameLib.GetSpell(nSpellId)

                wCurrSpell:FindChild("SpellbookItemName"):SetText(spell:GetName() or "Unknown")
                wCurrSpell:FindChild("SpellbookItemAbilityIcon"):SetSprite(spell:GetIcon() or "")
                wCurrSpell:FindChild("SpellbookItemAbilityIcon"):SetData(spell)


                local sGroupName = wContainer:FindChild("GroupName"):GetText()
                for _, BarContainers in ipairs(self.tGroups[sGroupName].BarContainers) do
                    if BarContainers.name == sMemberNames then
                        for _, tBar in ipairs(BarContainers.bars) do
                            if tBar.nSpellId == nSpellId then
                                wCurrSpell:FindChild("TickBox"):SetCheck(true)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if not bHaveLASAbilitiesForMember then
        wContainer:FindChild("SpellSelectorContainer"):SetText("Mouse over here for more info")
        wContainer:FindChild("SpellSelectorContainer"):SetTooltip([[No LAS data available

        If you know this member has the addon, but no LAS data show up,
        then press the "Request Party LAS Interrupts" button in the options,
        then select the members name again from the dropout menu
        just above the "Mouse over here for more info" red text.]])
    end
    if nNumOfSpells then
        local l,t,r,b = wContainer:GetAnchorOffsets()
        wContainer:SetAnchorOffsets(l, t, r, t+140+32*(nNumOfSpells-1))
    end

    wContainer:FindChild("SpellSelectorContainer"):ArrangeChildrenVert(0)
end

function addon:OnMemberContainerClose(wHandler)
    if wHandler:GetName() == "Discard" then
        wHandler:GetParent():Destroy()
    else -- Accept
        -- destroy our bars if we had any we'll recreat them (or not if none is ticked in the spell selector)
        local sGroupName, sMemberName = wHandler:GetParent():FindChild("GroupName"):GetText(), wHandler:GetParent():FindChild("MainButton"):GetText()
        for indexOfMember, BarContainers in ipairs(self.tGroups[sGroupName].BarContainers) do
            if BarContainers.name == sMemberName then
                BarContainers.frame:Destroy()
                table.remove(self.tGroups[sGroupName].BarContainers, indexOfMember)
            end
        end

        --wHandler:GetParent():FindChild("TickBox"):IsChecked()
        for nIndex, wSpellBookItem in ipairs(wHandler:GetParent():FindChild("SpellSelectorContainer"):GetChildren()) do
            if wSpellBookItem:FindChild("TickBox"):IsChecked() then
                local nSpellId = wSpellBookItem:FindChild("SpellbookItemAbilityIcon"):GetData():GetId()
                self:AddMemberToGroup(sGroupName, sMemberName)
                self:AddBarToMemberInGroup(sGroupName, sMemberName, nSpellId)
            end
        end
        self:RedrawGroup(sGroupName)
        self:ShowMemberButtons(sGroupName, true)
        wHandler:GetParent():Destroy()
    end
end

function addon:IsPlayerMemberOfGroup(sGroupNameToCheck)
    local bMember
    for sGroupName, tGroupData in pairs(self.tGroups) do
        if sGroupName == sGroupNameToCheck then
            for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
                if self.uPlayer:GetName() == tMemberData.name then
                    bMember = true
                end
            end
        end
    end
    return bMember
end

function addon:HideGroupContainer(wHandler)
    if self:IsPlayerMemberOfGroup(wHandler:GetParent():FindChild("GroupName"):GetText()) then
        local wPopUp = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
        wPopUp:SetStyle("Escapable", true)
        wPopUp:SetData({ type = "PopUp"})
        wPopUp:FindChild("Title"):SetText("Warning")
        wPopUp:FindChild("HelpText"):SetText("You can't hide a group that you are a member of!")
        wPopUp:FindChild("Yes"):SetText("OK")
        wPopUp:FindChild("No"):SetText("Close")
    else
        wHandler:GetParent():GetParent():Show(false)
    end
end

function addon:DestroyAllGroups()
    for sGroupName, tGroupData in pairs(self.tGroups) do
        if self.tGroups[sGroupName] then
            self.tGroups[sGroupName].GroupContainer:Destroy()
            self.tGroups[sGroupName] = nil
        end
    end
end

function addon:OnLockGroupButton(wHandler)
    if wHandler:GetName() == "LockUnlockAllGroupsButton" then
        for _, v in pairs(self.tGroups) do
            if not self.bAllGroupsLocked then
                v.GroupContainer:Show(true)
            end
            v.GroupContainer:GetData().bLocked = self.bAllGroupsLocked
            v.GroupContainer:FindChild("GroupConfigContainer"):Show(not self.bAllGroupsLocked)
            v.GroupContainer:SetStyle("Moveable", not v.GroupContainer:GetData().bLocked)
            v.GroupContainer:SetStyle("Sizable", not v.GroupContainer:GetData().bLocked)
        end
        self:ShowMemberButtons(nil, not self.bAllGroupsLocked, true)
        self.bAllGroupsLocked = not self.bAllGroupsLocked
        wHandler:SetText(self.bAllGroupsLocked and "Lock all groups" or "Unlock all groups")
    else
        local wGroupContainer = wHandler:GetParent():GetParent()
        local tData = wGroupContainer:GetData()
        self:ShowMemberButtons(tData.sGroupName, tData.bLocked)
        wHandler:GetParent():Show(tData.bLocked)
        wGroupContainer:SetStyle("Moveable", tData.bLocked)
        wGroupContainer:SetStyle("Sizable", tData.bLocked)
        tData.bLocked = not tData.bLocked
    end
end

function addon:ShowMemberButtons(sTheActualGroupsName, bShow, bAllGroups)
    for sGroupName, _ in pairs(self.tGroups) do
        if sGroupName == sTheActualGroupsName or bAllGroups then
            for indexOfMember, BarContainers in ipairs(self.tGroups[sGroupName].BarContainers) do
                BarContainers.frame:FindChild("EditMember"):Show(bShow)
                BarContainers.frame:FindChild("ShiftUp"):Show(indexOfMember ~= 1 and bShow or false)
                BarContainers.frame:FindChild("ShiftDown"):Show(indexOfMember ~= #self.tGroups[sGroupName].BarContainers and bShow or false)
            end
        end
    end
end

-----------------------------------------------------------------------------------------------
-- Group GUI builders
-----------------------------------------------------------------------------------------------

function addon:AddToGroup(sGroupName, sMemberName, name, nMax, bLocked)
    self:NewGroup(sGroupName, bLocked)
    self:AddMemberToGroup(sGroupName, sMemberName)
    self:AddBarToMemberInGroup(sGroupName, sMemberName, name, nMax)
end

function addon:NewGroup(sGroupName, bLocked)
    if self.tGroups[sGroupName] then return end -- that group already exists
    self.tGroups[sGroupName] = {}
    self.tGroups[sGroupName].GroupContainer = Apollo.LoadForm("MoO.xml", "GroupContainer", nil, self)
    self.tGroups[sGroupName].GroupContainer:FindChild("GroupName"):SetText(sGroupName)
    self.tGroups[sGroupName].GroupContainer:SetData({sGroupName = sGroupName, bLocked = bLocked})
    self.tGroups[sGroupName].BarContainers = {}
end

function addon:AddMemberToGroup(sGroupName, sMemberName)
    for k, v in pairs(self.tGroups[sGroupName].BarContainers) do
        if v.name and v.name == sMemberName then
            return -- names inside a bar have to be unique, hopefully cross server names won't mess this up
        end
    end
    local nNumOfMembers = #self.tGroups[sGroupName].BarContainers+1
    self.tGroups[sGroupName].BarContainers[nNumOfMembers] = {}
    self.tGroups[sGroupName].BarContainers[nNumOfMembers].bars = {}
    self.tGroups[sGroupName].BarContainers[nNumOfMembers].frame = Apollo.LoadForm("MoO.xml", "BarContainer", self.tGroups[sGroupName].GroupContainer, self)
    self.tGroups[sGroupName].BarContainers[nNumOfMembers].frame:SetData({sGroupName = sGroupName, sMemberName = sMemberName})
    self.tGroups[sGroupName].BarContainers[nNumOfMembers].frame:FindChild("Text"):SetText(sMemberName)
    self.tGroups[sGroupName].BarContainers[nNumOfMembers].name = sMemberName

    self:RedrawGroup(sGroupName)
end

function addon:AddBarToMemberInGroup(sGroupName, sMemberName, nSpellId, nMax)
    local nMemberIndexInGroup = getMemberOfGroupIndex(sGroupName, sMemberName)
    if nMemberIndexInGroup then
        for k, v in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
            if v.nSpellId and v.nSpellId == nSpellId then
                return -- abilities have to be unique
            end
        end
        local nNumOfBars = #self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars+1
        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars] = {}
        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame = Apollo.LoadForm("MoO.xml", "Bar", self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].frame, self)

        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBarColor(TableToCColor(self.tColors.cFull))
        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBGColor(TableToCColor(self.tColors.cBG))

        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].nSpellId = nSpellId -- this can be a spellId or just a text
        if not nMax then nMax = self:GetCooldown(nSpellId) end -- floor because sometimes you get values like 40.00000000000001 which is not so nice
        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].nMax = nMax
        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetMax(nMax)

        self:FitBarsToMember(sGroupName, sMemberName)
    end
end

function addon:FitBarsToMember(sGroupName, sMemberName)
    local nMemberIndexInGroup = type(sMemberName) == "number" and sMemberName or getMemberOfGroupIndex(sGroupName, sMemberName) -- if it is an index then use that if not then get the index from the name
    local nTotalMax = 0
    if nMemberIndexInGroup then
        for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
            nTotalMax = nTotalMax + tBar.nMax
        end
        local l,t,r,b = self.tGroups[sGroupName].GroupContainer:GetAnchorOffsets()
        local nGroupContainerWidth = r-l
        local nLeftEdge, nRightEdge = 0, 0
        for nBarIndex, tBar in ipairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
            nRightEdge = nRightEdge + nGroupContainerWidth*tBar.nMax/nTotalMax
            self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].frame:SetAnchorOffsets(nLeftEdge, 0, nRightEdge, 0)
            nLeftEdge = nRightEdge
        end
    end
end

function addon:RedrawGroup(sGroupName, tAnchorOffsets)
    local l,t,r,b
    if tAnchorOffsets then
        l,t,r,b = tAnchorOffsets.l, tAnchorOffsets.t, tAnchorOffsets.r, tAnchorOffsets.b
        self.tGroups[sGroupName].GroupContainer:SetAnchorOffsets(l,t,r,b)
    else
        l,t,r,b = self.tGroups[sGroupName].GroupContainer:GetAnchorOffsets()
    end
    local nGroupWidth, nGroupHeight = r-l, b-t
    local nMemberHeight = nGroupHeight/#self.tGroups[sGroupName].BarContainers
    for index, bars in ipairs(self.tGroups[sGroupName].BarContainers) do
        bars.frame:SetAnchorOffsets(0, (index-1)*nMemberHeight, 0, index*nMemberHeight)
        self:FitBarsToMember(sGroupName, index)
    end
end

function addon:OnGroupResize(wHandler, wControl)
    if wHandler == wControl and wControl:GetData() and wControl:GetData().sGroupName then
        self:RedrawGroup(wControl:GetData().sGroupName)
    end
end

function addon:ShiftMember(wHandler, wControl)
    local direction = wControl:GetName():find("Up") and true
    local sGroupName, sMemberName = wControl:GetParent():GetData().sGroupName, wControl:GetParent():GetData().sMemberName
    local nControlIndex = getMemberOfGroupIndex(sGroupName, sMemberName)

    local tTemp = {}
    for k, v in pairs(self.tGroups[sGroupName].BarContainers[nControlIndex]) do
        tTemp[k] = v
    end

    if direction then
        if nControlIndex-1 > 0 then -- don't try to up shift top member
            self.tGroups[sGroupName].BarContainers[nControlIndex] = self.tGroups[sGroupName].BarContainers[nControlIndex-1]
            self.tGroups[sGroupName].BarContainers[nControlIndex-1] = tTemp
        end
    else
        if nControlIndex+1 <= #self.tGroups[sGroupName].BarContainers then -- don't try to down shift bottom member
            self.tGroups[sGroupName].BarContainers[nControlIndex] = self.tGroups[sGroupName].BarContainers[nControlIndex+1]
            self.tGroups[sGroupName].BarContainers[nControlIndex+1] = tTemp
        end
    end
    addon:RedrawGroup(sGroupName)
    addon:ShowMemberButtons(sGroupName, true)
end

function addon:OnEditBoxChanged(wHandler, wControl, input)
    if wHandler:GetParent():GetName():find("OneButtonSetup") then -- OneButtonSetup window input box
        if input:find("([^0-9]+)") then
            wControl:SetTextColor(tColor.red)
        else
            wControl:SetTextColor(tColor.green)
        end
    else -- all the other input boxes
        wControl:SetTextColor(tColor.orange)
    end
end

function addon:AddGroupButton()
    local wEditbox = self.wOptions:FindChild("GroupCreatorContainer"):FindChild("AddGroupEditBox")
    local sNewGroupName = wEditbox:GetText()
    if self.tGroups[sNewGroupName] then -- group already exists
        wEditbox:SetText("") -- clear the text box
        wEditbox:InsertText("That group name is already in use.") -- add in text, this way it is not hightlighted so red text color is readable
        wEditbox:SetTextColor(tColor.red)
        wEditbox:SetFocus()
    else
        if wEditbox:GetText() ~= "That group name is already in use." then
            self:NewGroup(sNewGroupName)
            wEditbox:SetTextColor(tColor.green)
        end
    end
end

function addon:CopyGroupButton()
    local wEditbox = self.wOptions:FindChild("GroupCopyContainer"):FindChild("AddGroupEditBox")
    local sNewGroupName = wEditbox:GetText()
    if self.tGroups[sNewGroupName] then -- group already exists
        wEditbox:SetText("") -- clear the text box
        wEditbox:InsertText("That group name is already in use.") -- add in text, this way it is not hightlighted so red text color is readable
        wEditbox:SetTextColor(tColor.red)
        wEditbox:SetFocus()
    else
        if wEditbox:GetText() ~= "That group name is already in use." then
            local sSourceGroupName = self.wOptions:FindChild("GroupCopyContainer"):FindChild("CopyGroupSelectorContainer"):FindChild("DropDownWidget"):FindChild("MainButton"):GetText()
            if sSourceGroupName == "No entry added yet" then return end -- retard check
            self:NewGroup(sNewGroupName)
            for nMemberIndexInGroup, tMemberData in ipairs(self.tGroups[sSourceGroupName].BarContainers) do
                local nNumOfMembers = #self.tGroups[sNewGroupName].BarContainers+1
                self.tGroups[sNewGroupName].BarContainers[nNumOfMembers] = {}
                self.tGroups[sNewGroupName].BarContainers[nNumOfMembers].bars = {}
                self.tGroups[sNewGroupName].BarContainers[nNumOfMembers].frame = Apollo.LoadForm("MoO.xml", "BarContainer", self.tGroups[sNewGroupName].GroupContainer, self)
                self.tGroups[sNewGroupName].BarContainers[nNumOfMembers].frame:SetData({sGroupName = sNewGroupName, sMemberName = tMemberData.name})
                self.tGroups[sNewGroupName].BarContainers[nNumOfMembers].frame:FindChild("Text"):SetText(tMemberData.name)
                self.tGroups[sNewGroupName].BarContainers[nNumOfMembers].name = tMemberData.name
                for nBarIndex, tBar in pairs(self.tGroups[sSourceGroupName].BarContainers[nMemberIndexInGroup].bars) do
                    local nNumOfBars = #self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars+1
                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars] = {}
                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame = Apollo.LoadForm("MoO.xml", "Bar", self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].frame, self)

                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBarColor(TableToCColor(self.tColors.cFull))
                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBGColor(TableToCColor(self.tColors.cBG))

                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].nSpellId = tBar.nSpellId -- this can be a spellId or just a text
                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].nMax = tBar.nMax
                    self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetMax(tBar.nMax)

                    self:FitBarsToMember(sNewGroupName, tMemberData.name)
                end
            end
            self:RedrawGroup(sNewGroupName)
            wEditbox:SetTextColor(tColor.green)
        end
    end
end

function addon:DeleteGroupButton(wHandler)
    local sGroupName = wHandler:GetParent():FindChild("DeleteGroupSelectorContainer"):FindChild("DropDownWidget"):FindChild("MainButton"):GetText()
    if self.tGroups[sGroupName] then
        self.tGroups[sGroupName].GroupContainer:Destroy()
        self.tGroups[sGroupName] = nil
        wHandler:GetParent():FindChild("DeleteGroupSelectorContainer"):FindChild("DropDownWidget"):FindChild("MainButton"):SetText("Click to select a group")
    end
end

function addon:OnCloseButton(wHandler)
    wHandler:GetParent():Show(false)
end

function addon:OnHelpButton(wHandler)
    if not self.wHelp then
        self.wHelp = Apollo.LoadForm("MoO.xml", "HelpFrame", nil, self)
    end
    local wTextContainer = self.wHelp:FindChild("TextContainerML")

    -- colors is FF < full alpha then FF0000 < red
    local sHelp = "\
    <T Font='CRB_InterfaceSmall' TextColor='FFC0C0C0'>Note: this is a resizeable and moveable window! (Scroll wheel to scroll inside it works too)\n</T> \
    <T Font='CRB_InterfaceLarge_B' TextColor='FFFF0000'>Known issues, caveats, features:</T> \
        <T Font='CRB_InterfaceMedium_B' TextColor='FFFFFFFF'> \
            ● \"One\" button setup group always gets created small, so you always have to resize it.\
            ● Some abilities don't get picked up because events don't fire for them (Carbine has to fix it) for example Arcane Shock (spellslingers).\
            ● There might be interrupts I missed, if you think something should be tracked and is not tracked, please report it on curse.\
            ● Or there might be abilities that the addon pick up from the combatlog and are not really interrupts. Please report these to me so they can be added to a filter to ignore them.\
            ● Reloading the UI wipes all the interrupt data that was gathered from the combatlog. This is working as intended! \
            ● Group windows disappear after reloadui if you are not in a group. This is working as intended!\
            ● Tracking the cooldown of interrupt abilities from the combat log is not the best way, because there are AMPs or other abilities that might reduce the cooldown of an ability, and there is no way to track that from the combat log. So if you want the most accurate timers you need to have others use the addon too, so the addon can sync the data.\
            ● There are some rounding errors with the ability cooldowns that I need to track down making some of the abilities never appear to be off cooldown.\
            ● The info text on an interrupt bar can show more than 100% percentage when tracking when an interrupt hit (or interrupt armore reduce occured) during a cast. This issue is due to how the Carbine API return longer elapsed time for casts than the max duration of the cast.\
            ● You see someone's interrupt on cooldown but no info text if they interrupted during a cast. This means they did NOT interrupt during a cast. At least not according to the combat log / Carbine API.\
    \
    <T Font='CRB_InterfaceLarge_B' TextColor='FF00FF00'>Easiest way to use the addon:</T> \
        Once you have been in combat for a while ( meaning your group members used their interrupts and actually hit something with it ) you can open up the options with /moo . Then click the \"One\" button setup. This will allow you to create ad hock groups really fast. If your intent is to just track the cooldowns of others not really organize them into groups you can just enter the total amount of interrupts the addon tracked (this info is in the \"One\" button setup dialog window) this will create one group with everyone in it. Remember even tho the layout of a group window gets saved when reloading UI, if you want to use the same group setup again later you might want to save the group setup in the options window.\
    \
    <T Font='CRB_InterfaceLarge_B' TextColor='FF00FF00'>Additional usage examples / HowTo:</T> \
        The way to unlock or show an already locked or hidden group is to unlock all groups from the MoO options with the 'Lock/Unlock all groups' button inside the Miscellaneous options category.\
            <T Font='CRB_InterfaceLarge_B' TextColor='FF00FFFF'>Moving players up or down the list inside a group:</T> \
                If the little arrows at the right side of the bar don't show up, make sure you hit the Lock/Unlock all groups button in the main options till they do.\
            <T Font='CRB_InterfaceLarge_B' TextColor='FF00FFFF'>Adding players to a group:</T> \
                Once you have created a group ( or made sure the group you want to add players to is unlocked ) then you can click the 3rd icon from the top left inside the groups window. This will bring up the 'Add member to group' popup where you first need to select the player you want to add to the group, then tick in the abilities you want them to have on the bar inside the group. If you are missing players from the list please make sure that they either have used their interrupts in combat ( they actually hit something with it ) or if they are using the addon then you need to use the 'Request party LAS interrupts' button inside the main MoO options at the 'Miscellaneous options' category. \
            <T Font='CRB_InterfaceLarge_B' TextColor='FF00FFFF'>Removing players or abilities from a group:</T> \
                Again make sure the group is unlocked. Click the little cogwheel button on the players bar. This will bring up the 'Add member to group:' popup. If you untick all abilities the player will be removed from the list. Obviously you can remove just one or two ability as well.\
            <T Font='CRB_InterfaceLarge_B' TextColor='FF00FFFF'>Hiding a group:</T> \
                Again make sure the group is unlocked. The top left most button inside the group window will hide the group window. Remember groups you are part of can't be hidden for your own good. \
                \
                However you can still press the 'Delete all groups' button inside the MoO options window inside the 'Delete group' category. However in this case I recommend you tick in the 'Always broadcast cooldowns' check-box in the MoO options window inside the 'Miscellaneous options' category. If you don't tick this in then your group members won't receive cooldown data from you (if you are not in any visible groups on your end).\
                \
                Remember to unhide a group you need to click the 'Lock/Unlock all groups' button in the MoO options window inside the 'Miscellaneous options' category. (you might need to click it multiple times till it becomes unhidden/unlocked).\
            <T Font='CRB_InterfaceLarge_B' TextColor='FF00FFFF'>Locking/Unlocking groups:</T> \
                You can either lock/unlock all groups at once with the 'Lock/Unlock all groups' button in the MoO options window inside the 'Miscelleneous options' category. Or you can lock a single gorup by clicking the 2nd top left most icon in the group window, assuming the window is unlocked at that moment. \
                \
                Remember to unhide a group you need to click the 'Lock/Unlock all groups' button in the MoO options window inside the 'Miscellaneous options' category. (you might need to click it multiple times till it becomes unhidden/unlocked).\
            <T Font='CRB_InterfaceLarge_B' TextColor='FF00FFFF'>Sending group setups:</T> \
                You can send your own group setup to your party members (group/raid) with the 'Send groups to party' button in the MoO options window inside the 'Miscellaneous options' category. You might want to let them know you are doing this and that they should save the group setup to the database once they are done repositioning and resizing the groups so in case you have to send an adjusted group setup to them the groups will pop up at the saved positions not at the default positions, allowing them to lot quicker adjust to the potential changes.\
            <T Font='CRB_InterfaceLarge_B' TextColor='FFFFFF00'>The group setup database and receiving setups:</T> \
                When you receive a group setup sync the first time all the groups will be on top of each other and you need to move / resize them the way you want them to be. Now if you were to receive another sync without saving this setup, the newly synced setup would be at the default position again and you'd have to set it all up again. To avoid this make sure to save the group setup right after you are done setting it up ( with the same name it was synced to you ), this way when you receive a changed group setup with that name the addon will try to load the group window positions the best it can from the database, making your life that much easier when it comes to adjusting for the changes made to the setup.\
                \
                Worth mentioning that groups need to be saved in the main MoO options inside the 'Save/Load group setup to database' category. There is no automatic naming and saving, you have to do it yourself if you want to use a group setup later or you want to make sure that the positions of the group windows will be at the same place again when you receive the same sync again.\
                \
        <T Font='CRB_InterfaceSmall' TextColor='FFC0C0C0'>Note: this is a resizeable and moveable window! (Scroll wheel to scroll inside it works too)\n</T> \
        </T>"
    wTextContainer:SetText(sHelp)
    self.wHelp:Show(true)
end

function addon:Options()
    if not self.wOptions then
        self.wOptions = Apollo.LoadForm("MoO.xml", "OptionsContainer", nil, self)

        self.wOptions:FindChild("VersionNumberDisplay"):SetText(("%s: %s"):format("Version", sVersion))

        local wDeleteGroupSelectorContainer = Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("DeleteGroupSelectorContainer"), self)
        local wCopyGroupSelectorContainer = Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("CopyGroupSelectorContainer"), self)
        wDeleteGroupSelectorContainer:FindChild("MainButton"):SetText("Click to select a group")
        wCopyGroupSelectorContainer:FindChild("MainButton"):SetText("Click to select a group")

        local wSetupSelectorContainer = Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("SetupSelectorContainer"), self)
        wSetupSelectorContainer:FindChild("MainButton"):SetText("Click to select a setup")

        self.wOptions:FindChild("AllowGroupSync"):SetCheck(self.bAcceptGroupSync)
        self.wOptions:FindChild("AlwaysBroadcastCooldowns"):SetCheck(self.bAlwaysBroadcastCooldowns)
    end

    self.wOptions:Show(true)
end

function addon:MoO_OnSlashCommand(_, input)
    self:Options() -- well no other input for now so might as well just open the config on /moo
    --if input then
    --  if input:find("config") then
    --      self:Options()
    --  end
    --end
end

-----------------------------------------------------------------------------------------------
-- Party LAS Interrupts
-----------------------------------------------------------------------------------------------

-- don't forget to add the interrupt armour remover gadgets to the list too
-- keys are AbilityIds not spellIds!
-- values are base tier spellIds
local tInterrupts = {
    -- Spellslinger
    [20325] = 34355, -- Gate
    [30160] = 46160, -- Arcane Shock
    [16454] = 30006, -- Spatial Shift
    -- Esper
    [19022] = 32812, -- Crush
    [19029] = 32819, -- Shockwave
    [19355] = 33359, -- Incapacitate
    -- Stalker
    [23173] = 38791, -- Stagger
    [23705] = 39372, -- Collapse
    [23587] = 39246, -- False retreat
    -- Engineer
    [25635] = 41438, -- Zap
    [34176] = 51605, -- Obstruct Vision
    -- Warrior
    [38017] = 58591, -- kick
    [18363] = 32132, -- Grapple
    [18547] = 32320, -- Flash Bang
    -- Medic
    [26543] = 42352, -- paralytic surge

}

-- so basically nAbilityId is just the nId from the last tier of a spell in the ability book AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[#AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers].nId

function getAbilityAndSpellIdFromAbilityName(sAbilityName)
    for nAbilityIndex, tData in pairs(AbilityBook.GetAbilitiesList()) do
        if AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[1].strName:lower() == sAbilityName:lower() then
            return ("AbilityId: %d SpellId: %d"):format(AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[#AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers].nId, AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[1].splObject:GetId())
        end
    end
    return "not found"
end

-- utility function that gets the spellId from abilityId
function addon:GetTieredSpellIdFromLasAbilityId(nAbilityId)
    -- this only works for abilities the player can cast
    local wAbility = Apollo.LoadForm("MoO.xml", "TempAbilityWindow", nil, self)
    wAbility:SetAbilityId(nAbilityId)
    local sSpellId = wAbility:GetAbilityTierId()
    wAbility:Destroy()
    return sSpellId
end

function addon:RequestPartyLASInterrupts()
    if self.wOneButton then self.wOneButton:Show(false) end -- this is the easy way: we hide that window so the user has to click the "one" button again and that we will recalculate data for the new window there
    tPartyLASInterrupts = {} -- wipe the cache
    --add our own LAS interrupts
    tPartyLASInterrupts[self.uPlayer:GetName()] = self:MyLASInterrupts(true)
    -- request party LAS interrupts
    self:SendCommMessage({type = "RequestPartyLASInterrupts"})
end

function addon:OnDebugButton()
    D(self.tLastLASInterrupts)
    --local tData = {}
    --for sGroupName, tGroupData in pairs(self.tGroups) do
    --  tData[sGroupName] = {}
    --  local l,t,r,b = tGroupData.GroupContainer:GetAnchorOffsets()
    --  tData[sGroupName].tAnchorOffsets = { l = l, t = t, r = r, b = b }
    --  tData[sGroupName].bLocked = tGroupData.GroupContainer:GetData().bLocked
    --  for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
    --      tData[sGroupName][nMemberIndexInGroup] = {}
    --      tData[sGroupName][nMemberIndexInGroup].name = tMemberData.name
    --      tData[sGroupName][nMemberIndexInGroup].tBars = {}
    --      for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
    --          tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex] = {}
    --          tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex].nSpellId = tBar.nSpellId
    --          tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex].nMax = tBar.nMax
    --      end
    --  end
    --end
    --D(tData)
end

function addon:MyLASInterrupts(bReturnNotSend)
    local sMemberName = self.uPlayer and self.uPlayer:GetName()
    self.tCurrLAS = ActionSetLib.GetCurrentActionSet()
    -- We sync spellIds because you can't get description from an abilityId if it is not for your class
    local tSpellIds = {}
    if self.tCurrLAS then
        for nIndex, nAbilityId in ipairs(self.tCurrLAS) do
            if tInterrupts[nAbilityId] then
                tSpellIds[#tSpellIds+1] = self:GetTieredSpellIdFromLasAbilityId(nAbilityId)
            end
        end

        -- do a bunch of nil checks here so we don't send data that is nil, doh
        if sMemberName and #tSpellIds > 0 then
            if bReturnNotSend then
                return tSpellIds
            else
                self:SendCommMessage({type = "LASInterrupts", sMemberName = sMemberName, tSpellIds = tSpellIds })
            end
        end
    end
end

--- Try and get a spells cooldown even if the calling spellIds spellObject returns 0 for :GetCooldowntime()
-- @return number for the cooldown matching the associated spellName
function addon:GetCooldown(nSpellId)
    local spellObject = GameLib.GetSpell(nSpellId)
    local sSpellName = spellObject:GetName()
    if spellObject:GetCooldownTime() and spellObject:GetCooldownTime() > 0 then return floor(spellObject:GetCooldownTime()) end -- this spellId provides cooldown, return with that nothing else to do -- we floor because else you get some weird decimal numbers, rather loose some accuraccy than have some wonky display

    -- life is not always that easy lets try to get spell cooldown from our known interrupt abilities by name matching
    for nAbilityId, nSpellIdForBaseTier in pairs(tInterrupts) do
        local splTempSpellObject = GameLib.GetSpell(nSpellIdForBaseTier)
        if splTempSpellObject:GetName() == sSpellName then
            return floor(splTempSpellObject:GetCooldownTime()) -- we floor because else you get some weird decimal numbers, rather loose some accuraccy than have some wonky display
        end
    end
end

-----------------------------------------------------------------------------------------------
-- Dropdown Widget
-----------------------------------------------------------------------------------------------

function addon:OnDropDownMainButton(wHandler)
    local tEntries = {}
    local tData = {}
    if wHandler:GetParent():GetParent():GetName():find("Group") then -- it is a group dropdown
        tData = self.tGroups
    elseif wHandler:GetParent():GetParent():GetName():find("Member") then -- it is a member dropdown
        -- clean tPartyLASInterrupts up so non group member data gets removed in case we tracked someone who is no longer in the group
        local nMemberCount = GroupLib.GetMemberCount()
        if nMemberCount > 1 then -- only do cleanup if there are actually people in the group
            for sMemberName, tInterrupts in pairs(tPartyLASInterrupts) do
                local bFound
                for i=1, nMemberCount do
                    if sMemberName == GroupLib.GetGroupMember(i).strCharacterName then
                        bFound = true
                        break
                    end
                end
                if not bFound then --not in the group right now
                    tPartyLASInterrupts[sMemberName] = nil
                end
            end
        end

        tData = tPartyLASInterrupts
    elseif wHandler:GetParent():GetParent():GetName():find("Setup") then -- it is a setup dropdown
        tData = self.tSavedGroups
    end
    local choiceContainer = wHandler:FindChild("ChoiceContainer")
    choiceContainer:DestroyChildren() -- clear the container, we populate it every time it opens
    choiceContainer:SetData({})
    local nCounter = 0
    local wEntry
    for sNewName, _ in pairs(tData) do
        wEntry = Apollo.LoadForm("MoO.xml", "DropDownWidgetEntryButton", choiceContainer, self)
        wEntry:SetText(sNewName)
        wEntry:Show(true)
        nCounter = nCounter + 1
    end
    choiceContainer:ArrangeChildrenVert(0)
    if nCounter == 0 then -- no entry added yet add an entry that says that
        wEntry = Apollo.LoadForm("MoO.xml", "DropDownWidgetEntryButton", choiceContainer, self)
        wEntry:SetText("No entry added yet")
        wEntry:Show(true)
        nCounter = nCounter + 1
    end

    local l,t,r,b = choiceContainer:GetAnchorOffsets()
    choiceContainer:SetAnchorOffsets(l, t, r, t+nCounter*wEntry:GetHeight())
    choiceContainer:Show(true)
    l,t,r,b = wHandler:FindChild("ChoiceContainerBG"):GetAnchorOffsets()
    wHandler:FindChild("ChoiceContainerBG"):SetAnchorOffsets(l, t, r, t+nCounter*wEntry:GetHeight()+30)
    wHandler:FindChild("ChoiceContainerBG"):Show(true)
end

function addon:OnDropDownEntrySelect(wHandler)
    wHandler:GetParent():GetParent():SetText(wHandler:GetText())
    wHandler:GetParent():Show(false)
    wHandler:GetParent():GetParent():FindChild("ChoiceContainerBG"):Show(false)

    local wContainer =  wHandler:GetParent():GetParent():GetParent():GetParent():GetParent()
    if wContainer:GetName():find("Member") then
        self:MemberSelectedPopulateAbilityList(wContainer, wHandler:GetText())
    end
end

function addon:OnDropDownChoiceContainerHide(wHandler)
    wHandler:GetParent():FindChild("ChoiceContainer"):Show(false)
end

-----------------------------------------------------------------------------------------------
-- LAS Change tracking and related utility functions
-----------------------------------------------------------------------------------------------

do
    local function isEntryInTable(e, t)
        for k, v in pairs(t) do
            if GameLib.GetSpell(v) and GameLib.GetSpell(e) and GameLib.GetSpell(v):GetName() == GameLib.GetSpell(e):GetName() then
                return true
            end
        end
        return false
    end
    -- this returns false when the two tables match
    -- and returns an indexed table with the not matching values if they don't match
    local function tablesDontMatch(a, b)
        if not a then return b end
        if not b then return a end

        local notMatching = {}
        for _, v in pairs(a) do
            if not isEntryInTable(v, b) and not isEntryInTable(v, notMatching) then
                notMatching[#notMatching+1] = v
            end
        end
        for _, v in pairs(b) do
            if not isEntryInTable(v, a) and not isEntryInTable(v, notMatching) then
                notMatching[#notMatching+1] = v
            end
        end

        return #notMatching > 0 and notMatching
    end

    function addon:DelayedAbilityBookCheck()
        local tCurrLASInterrupts = self:MyLASInterrupts(true)
        local tLost, tGained = {}, {}
        if self.tLastLASInterrupts then
            if (tCurrLASInterrupts and #tCurrLASInterrupts > 0) and #self.tLastLASInterrupts > 0 then
                if tablesDontMatch(tCurrLASInterrupts, self.tLastLASInterrupts) then
                    local tChanges = tablesDontMatch(tCurrLASInterrupts, self.tLastLASInterrupts)
                    for _, v in pairs(tChanges) do
                        if isEntryInTable(v, tCurrLASInterrupts) then
                            tGained[#tGained+1] = v
                        else
                            tLost[#tLost+1] = v
                        end
                    end
                    self:SendCommMessage({type = "LASInterruptsChanged", sPlayerName = self.uPlayer:GetName(), tLASInterrupts = tCurrLASInterrupts, tLost = tLost, tGained = tGained})
                    --self:OnLASInterruptChanged(self.uPlayer:GetName(), tLost, tGained)
                end
            elseif #self.tLastLASInterrupts > 0 and not tCurrLASInterrupts then
                tLost = tablesDontMatch(tCurrLASInterrupts, self.tLastLASInterrupts)
                self:SendCommMessage({type = "LASInterruptsChanged", sPlayerName = self.uPlayer:GetName(), tLASInterrupts = tCurrLASInterrupts, tLost = tLost, tGained = tGained})
                --self:OnLASInterruptChanged(self.uPlayer:GetName(), tLost, tGained)
            end
        elseif (tCurrLASInterrupts and #tCurrLASInterrupts > 0) and not self.tLastLASInterrupts then
            tGained = tablesDontMatch(tCurrLASInterrupts, self.tLastLASInterrupts)
            self:SendCommMessage({type = "LASInterruptsChanged", sPlayerName = self.uPlayer:GetName(), tLASInterrupts = tCurrLASInterrupts, tLost = tLost, tGained = tGained})
            --self:OnLASInterruptChanged(self.uPlayer:GetName(), tLost, tGained)
        end
        self.tLastLASInterrupts = self:MyLASInterrupts(true)
    end

    function addon:OnAbilityBookChange()
        self.tLastLASInterrupts = self:MyLASInterrupts(true)
        if not self.bAllowLASInterruptCheck then return end
        -- have to do this because if you get ability list at this event then it will return what you had not what you have right now.
        Apollo.RegisterTimerHandler("DelayedAbilityBookCheck", "DelayedAbilityBookCheck", self)
        Apollo.CreateTimer("DelayedAbilityBookCheck", 0.2, false)
    end

    function addon:OnLASInterruptChanged(sPlayerName, tLost, tGained)
        local sLostAbilities = ""
        local bLost
        local tOldLASInterrupts = {}

        for sGroupName, tGroupData in pairs(self.tGroups) do
            for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
                if self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].name == sPlayerName then
                    for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                        local bSpellFound
                        for nIndex, nSpellId in ipairs(tOldLASInterrupts) do
                            if self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].nSpellId == nSpellId then
                                bSpellFound = true
                                break
                            end
                        end
                        if not bSpellFound then
                            tOldLASInterrupts[#tOldLASInterrupts+1] = self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].nSpellId
                        end
                    end
                end
            end
        end

        if tLost then
            for _, v in pairs(tLost) do
                if isEntryInTable(v, tOldLASInterrupts) then
                    bLost = true
                    sLostAbilities = ((sLostAbilities == "") and ("%s%s") or ("%s, %s")):format(sLostAbilities, GameLib.GetSpell(v):GetName())
                end
            end
        end
        if bLost then
            local wPopUp = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
            wPopUp:SetStyle("Escapable", true)
            wPopUp:SetData({ type = "PopUp"})
            wPopUp:FindChild("Title"):SetText("Notification")
            wPopUp:FindChild("HelpText"):SetText(("%s changed LAS setup and lost %s. This/These were used in your current interrupt setup so you might want to do something about this."):format(sPlayerName, sLostAbilities))
            wPopUp:FindChild("Yes"):SetText("OK")
            wPopUp:FindChild("No"):SetText("Close")
        end

    end
end

-----------------------------------------------------------------------------------------------
-- Bar updating
-----------------------------------------------------------------------------------------------

function addon:OnOneSecTimer()
    --self:OnAbilityBookChange() -- this probably should be only done outside of combat however due to unitObjects missing :InCombat() check (should come Winter beta 3.5) we can live with this till now
    local tBarData = {}
    for sGroupName, tGroupData in pairs(self.tGroups) do
        for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
            if self.uPlayer and tMemberData.name == self.uPlayer:GetName() then
                for nBarIndex, tBar in ipairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                    -- need to make sure the spellId is the actual spell we have on our bars because if an ability is added to the bars from the combatlog then that spellIds spellObject may not provide a cooldown
                    local bCorrectSpellId
                    if self.tLastLASInterrupts then
                        for nIndex, nSpellId in ipairs(self.tLastLASInterrupts) do
                            if nSpellId == tBar.nSpellId then
                                bCorrectSpellId = true
                            end
                            if not bCorrectSpellId then
                                if GameLib.GetSpell(nSpellId):GetName() == GameLib.GetSpell(tBar.nSpellId):GetName() then
                                    tBar.nSpellId = nSpellId
                                    break
                                end
                            end
                        end
                    end

                    local spellObject = GameLib.GetSpell(tBar.nSpellId)
                    local nCD, nRemainingCD = floor(spellObject:GetCooldownTime()), floor(spellObject:GetCooldownRemaining())
                    if nRemainingCD and nRemainingCD > 0 then
                        tBar.frame:SetBarColor(TableToCColor(self.tColors.cProgress))
                        tBar.frame:SetProgress(nRemainingCD)
                        if not tBarData[tBar.nSpellId] then -- no need to overwrite ability data
                            tBarData[tBar.nSpellId] = {tMemberData.name, nRemainingCD}
                        end
                    else
                        tBar.frame:FindChild("CastInfo"):SetText("")
                        tBar.frame:SetBarColor(TableToCColor(self.tColors.cFull))
                        tBar.frame:SetProgress(nCD)
                        if not tBarData[tBar.nSpellId] then -- no need to overwrite ability data
                            tBarData[tBar.nSpellId] = {tMemberData.name, nCD}
                        end
                    end
                end
            elseif self.uPlayer and tMemberData.name ~= self.uPlayer:GetName() then -- not the player
                -- do some clean up here: if the whole group is out of combat and everything in the cooldown database is on cooldown then purge the database
                for nBarIndex, tBar in ipairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                    local spellObject = GameLib.GetSpell(tBar.nSpellId)
                    local nCD = self:GetCooldown(tBar.nSpellId)
                    if self.tCooldowns[tMemberData.name] and self.tCooldowns[tMemberData.name][tBar.nSpellId] and type(self.tCooldowns[tMemberData.name][tBar.nSpellId]) == "number" and nCD then
                        local nRemainingCD = floor(nCD - (os.time() - self.tCooldowns[tMemberData.name][tBar.nSpellId]))
                        if nRemainingCD and nRemainingCD > 0 then
                            tBar.frame:SetBarColor(TableToCColor(self.tColors.cProgress))
                            tBar.frame:SetProgress(nRemainingCD)
                        else
                            tBar.frame:FindChild("CastInfo"):SetText("")
                            tBar.frame:SetBarColor(TableToCColor(self.tColors.cFull))
                            tBar.frame:SetProgress(nCD)
                        end
                    end
                end
            end
        end
    end
    if self.bAlwaysBroadcastCooldowns then
        if self.tLastLASInterrupts then
            for nIndex, nSpellId in ipairs(self.tLastLASInterrupts) do
                if not tBarData[nSpellId] then -- no need to overwrite ability data
                    local spellObject = GameLib.GetSpell(nSpellId)
                    if spellObject then
                        local nCD, nRemainingCD = floor(spellObject:GetCooldownTime()), floor(spellObject:GetCooldownRemaining())
                        if nRemainingCD and nRemainingCD > 0 then
                            if not tBarData[nSpellId] then -- no need to overwrite ability data
                                tBarData[nSpellId] = {self.uPlayer:GetName(), nRemainingCD}
                            end
                        else
                            if not tBarData[nSpellId] then -- no need to overwrite ability data
                                tBarData[nSpellId] = {self.uPlayer:GetName(), nCD}
                            end
                        end
                    end
                end
            end
        end
    end
    self:SendCommMessage(tBarData) -- use a single message to transmit all player bar data
end

-----------------------------------------------------------------------------------------------
-- Addon communication
-----------------------------------------------------------------------------------------------

function addon:SetGroupChannel(sGroupLeader)
    if not sGroupLeader then return end
    local sNewChannel = string.format("Moo_%s%s", sGroupLeader, string.reverse(sGroupLeader))

    if self.sChannelName ~= sNewChannel then
        self.sChannelName = sNewChannel
        self.CommChannel = ICCommLib.JoinChannel(self.sChannelName, "OnCommMessage", self)
    end
end

function addon:LeaveGroupChannel()
    self.sChannelName = ""
end

function addon:OnAllowGroupSyncButton(wHandler)
    self.bAcceptGroupSync = wHandler:IsChecked()
end

function addon:OnAlwaysBroadcastCooldowns(wHandler)
    self.bAlwaysBroadcastCooldowns = wHandler:IsChecked()
end


function addon:OnCommMessage(channel, tMsg)
    if channel ~= self.CommChannel then return nil end

    if not tMsg.type then -- bar update
        -- all for performance and reduce network traffic so every other comm message has to have a type
        for nSpellId, tAbilityData in pairs(tMsg) do
            if type(nSpellId) == "number" and type(tAbilityData[1]) == "string" and type(tAbilityData[2]) == "number" then -- do some type checking at least to try and prevent some errors in case a typeless message (malformed) one gets through somehow

                for sGroupName, tGroupData in pairs(self.tGroups) do
                    for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
                        if self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].name == tAbilityData[1] then
                            -- wipe cooldown data for this spellId since we use sync which should be more reliable due to abilities that reduce cooldown
                            if not self.tCooldowns[tAbilityData[1]] then self.tCooldowns[tAbilityData[1]] = {} end
                            self.tCooldowns[tAbilityData[1]][nSpellId] = "syncing"
                            for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                                if self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].nSpellId == nSpellId then
                                    if tAbilityData[2] == self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].nMax then
                                        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].frame:FindChild("CastInfo"):SetText("")
                                        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].frame:SetBarColor(TableToCColor(self.tColors.cFull))
                                    else
                                        self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].frame:SetBarColor(TableToCColor(self.tColors.cProgress))
                                    end
                                    self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].frame:SetProgress(tAbilityData[2])
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif tMsg.type == "RequestPartyLASInterrupts" then
        self:MyLASInterrupts()
    elseif tMsg.type == "LASInterrupts" then
        tPartyLASInterrupts[tMsg.sMemberName] = tMsg.tSpellIds
    elseif tMsg.type == "LASInterruptsChanged" then
        self:OnLASInterruptChanged(tMsg.sPlayerName, tMsg.tLost, tMsg.tGained)
    elseif tMsg.type == "RequestVersionCheck" then
        self:SendCommMessage({type = "VersionCheckData", sMemberName = self.uPlayer:GetName(), sVersion = sVersion})
    elseif tMsg.type == "VersionCheckData" then
        self.tVersionData[#self.tVersionData+1] = { sName = tMsg.sMemberName, sVersion = tMsg.sVersion }
    elseif tMsg.type == "GroupSync" and self.bAcceptGroupSync then
        -- destroy what we have so we can start fresh
        --D(tMsg.tGroupData)
        local bSavedSetupFound
        for sSetupName, _ in pairs(self.tSavedGroups) do
            if sSetupName == tMsg.sName then
                bSavedSetupFound = true
            end
        end
        if bSavedSetupFound then
            local wPopUp = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
            wPopUp:SetStyle("Escapable", true)
            wPopUp:SetData({ type = "PopUp"})
            wPopUp:FindChild("Title"):SetText("Notification")
            wPopUp:FindChild("HelpText"):SetText(("You've just received a group setup named: <%s> from %s. We've found a setup with that name in the databas so loaded the layout as far as we could, but don't forget to overwrite this save once you are done setting up the group window positions so the latest layout gets saved. Also, the group frames might be on top of each other, drag them around (or resize them) to see all."):format(tMsg.sName, tMsg.sSender))
            wPopUp:FindChild("Yes"):SetText("OK")
            wPopUp:FindChild("No"):SetText("Close")

            for sGroupName, _  in pairs(self.tGroups) do
                self.tGroups[sGroupName].GroupContainer:Destroy()
                self.tGroups[sGroupName] = nil
            end
            for sGroupName, tGroupData in pairs(tMsg.tGroupData) do
                for nMemberIndexInGroup, tMemberData in ipairs(tGroupData) do
                    for nBarIndex, tBar in ipairs(tMemberData.tBars) do
                        local bLocked
                        if self.tSavedGroups[tMsg.sName][sGroupName] and self.tSavedGroups[tMsg.sName][sGroupName].bLocked then
                            bLocked = true
                        end
                        self:AddToGroup(sGroupName, tMemberData.name, tBar.nSpellId, tBar.nMax, not bLocked)
                    end
                    if #tGroupData > 0 then -- not an empty group (retard check?)
                        if self.tSavedGroups[tMsg.sName][sGroupName] and self.tSavedGroups[tMsg.sName][sGroupName].tAnchorOffsets then
                            self:RedrawGroup(sGroupName, self.tSavedGroups[tMsg.sName][sGroupName].tAnchorOffsets)
                        end
                    end
                end
                self:OnLockGroupButton(self.tGroups[sGroupName].GroupContainer:FindChild("Lock"))
                if not self.tSavedGroups[tMsg.sName][sGroupName].bIsShown and not self:IsPlayerMemberOfGroup(sGroupName) then
                    self.tGroups[sGroupName].GroupContainer:Show(self.tSavedGroups[tMsg.sName][sGroupName].bIsShown)
                end
            end
        else
            local wPopUp = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
            wPopUp:SetStyle("Escapable", true)
            wPopUp:SetData({ type = "PopUp"})
            wPopUp:FindChild("Title"):SetText("Notification")
            wPopUp:FindChild("HelpText"):SetText(("You've just received a group setup named: <%s> from %s. Couldn't find a setup with that name in the database so we made an initial save. Don't forget to overwrite this save once you are done setting up the group window positions. Also, the group frames are on top of each other, drag them around (or resize them) to see all."):format(tMsg.sName, tMsg.sSender))
            wPopUp:FindChild("Yes"):SetText("OK")
            wPopUp:FindChild("No"):SetText("Close")

            for sGroupName, _  in pairs(self.tGroups) do
                self.tGroups[sGroupName].GroupContainer:Destroy()
                self.tGroups[sGroupName] = nil
            end
            for sGroupName, tGroupData in pairs(tMsg.tGroupData) do
                for nMemberIndexInGroup, tMemberData in ipairs(tGroupData) do
                    for nBarIndex, tBar in ipairs(tMemberData.tBars) do
                        self:AddToGroup(sGroupName, tMemberData.name, tBar.nSpellId, tBar.nMax)
                    end
                end
            end
            self:SaveGroups(tMsg.sName)
        end
    -- deprecated since we read this from the combatlog now
    --elseif tMsg.type == "Interrupt" then
    --  if tMsg.nSpellId and tMsg.cast and GameLib.GetSpell(tMsg.nSpellId) and GameLib.GetSpell(tMsg.cast) then
    --      self:UpdateCastInfoForAbility(GameLib.GetSpell(tMsg.nSpellId):GetName(), ("Interrupted: %s"):format(GameLib.GetSpell(tMsg.cast):GetName()))
    --  end
    --elseif tMsg.type == "CCState" and tMsg.perc then
    --  self:UpdateCastInfoForAbility(GameLib.GetSpell(tMsg.nSpellId):GetName(), ("-%d IA during %s%% %s cast"):format(tMsg.nInterruptArmorHit, tMsg.perc, tMsg.cast))
    end
end

function addon:SendCommMessage(message)
    if self.CommChannel then
        self.CommChannel:SendMessage(message)
    end
end

function addon:OnGroupJoin()
    local MemberCount = GroupLib.GetMemberCount()
    if MemberCount == 1 then return end

    local GroupLeader
    for i=1, MemberCount do
        local MemberInfo = GroupLib.GetGroupMember(i)
        if MemberInfo.bIsLeader then
            GroupLeader = MemberInfo.strCharacterName
            break
        end
    end

    self:SetGroupChannel(GroupLeader)
end

function addon:OnGroupLeft()
    self:LeaveGroupChannel()
end

function addon:OnGroupUpdated()
    self:OnGroupJoin()
end

do
    local bTimerExists
    function addon:VersionCheck()
        if not self.bVersionCheckAllowed then return end -- lets not allow spamming
        self.bVersionCheckAllowed = false
        self.tVersionData = {}
        self:SendCommMessage({type = "RequestVersionCheck"})
        self.tVersionData[#self.tVersionData+1] = { sName = self.uPlayer:GetName(), sVersion = sVersion}
        if not bTimerExists then
            Apollo.RegisterTimerHandler("DelayedPrint", "DelayedPrint", self)
            Apollo.CreateTimer("DelayedPrint", 4, false)
            bTimerExists = true
        else
            Apollo.StartTimer("DelayedPrint")
        end
    end
    function addon:DelayedPrint()
        table.sort(self.tVersionData, function( a,b ) return a.sName > b.sName end)
        local sString = ""
        for k, v in ipairs(self.tVersionData) do
            if k == 1 then
                sString = ("(%s: %s)."):format(v.sName, v.sVersion, sString)
            else
                sString = ("(%s: %s), %s "):format(v.sName, v.sVersion, sString)
            end
        end
        Print(("MoO version info: %s"):format(sString))
        self.bVersionCheckAllowed = true
    end
end

function addon:SendGroups(sName)
    local tData = {}
    for sGroupName, tGroupData in pairs(self.tGroups) do
        tData[sGroupName] = {}
        for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
            tData[sGroupName][nMemberIndexInGroup] = {}
            tData[sGroupName][nMemberIndexInGroup].name = tMemberData.name
            tData[sGroupName][nMemberIndexInGroup].tBars = {}
            for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex] = {}
                tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex].nSpellId = tBar.nSpellId
                tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex].nMax = tBar.nMax
            end
        end
    end

    self:SendCommMessage({type = "GroupSync", tGroupData = tData, sName = sName, sSender = self.uPlayer:GetName()})
end

-----------------------------------------------------------------------------------------------
-- Saving/Loading/Deleting Groups
-----------------------------------------------------------------------------------------------

function addon:OnSetupButton(wHandler)
    local sButtonName = wHandler:GetName()
    if sButtonName:find("Save") then
        if self.wSaveGroups then self.wSaveGroups:Destroy() end -- start over
        self.wSaveGroups = Apollo.LoadForm("MoO.xml", "SaveGroupSetup", nil, self)
        self.wSaveGroups:Show(true)
    elseif sButtonName:find("Load") then
        local sSetupNameToLoad = wHandler:GetParent():FindChild("MainButton"):GetText()
        local wConfirm = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
        wConfirm:SetData({ type = "ConfirmSetupLoad", sName = sSetupNameToLoad})
        wConfirm:FindChild("Title"):SetText("Setup load warning")
        wConfirm:FindChild("HelpText"):SetText(("Loading a group setup discards the current group setup. If the current group setup is not saved already then it'll be lost. Load <%s> anyways?"):format(sSetupNameToLoad))
    elseif sButtonName:find("Delete") then
        self.tSavedGroups[wHandler:GetParent():FindChild("MainButton"):GetText()] = nil
        wHandler:GetParent():FindChild("MainButton"):SetText("Click to select a setup")
    elseif sButtonName:find("SendGroups") then
        if self.wSaveGroups then self.wSaveGroups:Destroy() end -- start over
        self.wSaveGroups = Apollo.LoadForm("MoO.xml", "SaveGroupSetup", nil, self)
        self.wSaveGroups:SetData({bSend = true})
        self.wSaveGroups:FindChild("Title"):SetText("Save and send groups")
        self.wSaveGroups:FindChild("HelpText"):SetText("Before you can send the group you have to save it first. Name of the group setup for the database")
        self.wSaveGroups:Show(true)
    end
end

function addon:OnSaveGroupsCloseButtons(wHandler)
    if wHandler:GetName() == "Discard" then wHandler:GetParent():Destroy() return end -- close

    local sName = wHandler:GetParent():FindChild("EditBox"):GetText()
    local tData = wHandler:GetParent():GetData()
    local bSend
    if tData and tData.bSend then bSend = true end

    if not self.tSavedGroups[sName] then
        self:SaveGroups(sName)
        if bSend then
            self:SendGroups(sName)
        end
        wHandler:GetParent():Destroy()
    else
        local wConfirm = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
        wConfirm:SetData({ type = "ConfirmSetupOverwrite", sName = sName, bSend = bSend})
        wConfirm:FindChild("Title"):SetText("Confirm overwrite")
        wConfirm:FindChild("HelpText"):SetText("That name already exists in the database. Do you want to overwrite it?")
    end
end

function addon:SaveGroups(sName)
    self.tSavedGroups[sName] = self:GenerateSavableGroupTable()
end

-----------------------------------------------------------------------------------------------
-- Generic confirmation window button handlers
-----------------------------------------------------------------------------------------------

function addon:OnGenericButton(wHandler)
    local tParentData = wHandler:GetParent():GetData()
    if tParentData.type == "ConfirmSetupOverwrite" then
        if wHandler:GetName() == "Yes" then
            self:SaveGroups(tParentData.sName)
            if tParentData.bSend then
                self:SendGroups(tParentData.sName)
            end
            self.wSaveGroups:Destroy()
        end
        wHandler:GetParent():Destroy()
    elseif tParentData.type == "ConfirmSetupLoad" then
        if wHandler:GetName() == "Yes" and self.tSavedGroups[tParentData.sName] then
            self:LoadSavedGroups(self.tSavedGroups[tParentData.sName])
        end
        wHandler:GetParent():Destroy()
    elseif tParentData.type == "ConfirmOneButtonCreation" then
        if wHandler:GetName() == "Yes" then
            self:GenerateGroupsFromOneButtonWindow(tParentData.nMembersPerGroup)
        end
        wHandler:GetParent():Destroy()
    elseif tParentData.type == "PopUp" then
        wHandler:GetParent():Destroy()
    end
end

-----------------------------------------------------------------------------------------------
-- "One" button setup
-----------------------------------------------------------------------------------------------

function addon:GenerateGroupsFromOneButtonWindow(nMembersPerGroup)

    for sGroupName, _  in pairs(self.tGroups) do
        self.tGroups[sGroupName].GroupContainer:Destroy()
        self.tGroups[sGroupName] = nil
    end
    local sGroupName, nGroupMemberCounter, nGroupCounter, nMembers = "Group%d", 0, 1, 0

    for sMemberName, tInterrupts in pairs(tPartyLASInterrupts) do
        nMembers = nMembers + 1
    end

    local nNumberOfFullGroupsWeCanCreate = floor(nMembers/nMembersPerGroup)

    for sMemberName, tInterrupts in pairs(tPartyLASInterrupts) do
        for nIndex, nSpellId in pairs(tInterrupts) do
            if self:GetCooldown(nSpellId) and self:GetCooldown(nSpellId) > 0 then
                self:AddToGroup(sGroupName:format(nGroupCounter), sMemberName, nSpellId, self:GetCooldown(nSpellId), false)
            else
                D("no cooldown for ".. nSpellId.. " " .. GameLib.GetSpell(nSpellId):GetName() .. " - " .. sMemberName)
            end
        end
        nGroupMemberCounter = nGroupMemberCounter + 1
        if nGroupMemberCounter == nMembersPerGroup then
            nGroupCounter = nGroupCounter + 1
        end
        -- might as well create a group for the rest too so we comment this out
        --if nGroupCounter == nNumberOfFullGroupsWeCanCreate then
        --  break
        --end
    end
end

function addon:OnOneButtonSetup()
    if not self.wOneButton then
        self.wOneButton = Apollo.LoadForm("MoO.xml", "OneButtonSetupWindow", nil, self)
    end
    local wDataText = self.wOneButton:FindChild("DataText")
    local nNumberOfInterrupts, nTotalInterruptCD, nMembers = 0,0,0
    for sMemberName, tInterrupts in pairs(tPartyLASInterrupts) do
        nMembers = nMembers + 1
        for nIndex, nSpellId in pairs(tInterrupts) do -- pairs here because I think I'll switch to non indexed table at some point so this makes it future proof
            if self:GetCooldown(nSpellId) and self:GetCooldown(nSpellId) > 0 then
                nNumberOfInterrupts = nNumberOfInterrupts + 1
                nTotalInterruptCD = nTotalInterruptCD + self:GetCooldown(nSpellId)
            else
                D("no cooldown for ".. nSpellId.. " " .. GameLib.GetSpell(nSpellId):GetName() .. " - " .. sMemberName)
            end
        end
    end
    local nAvgInterruptCD = nTotalInterruptCD / nNumberOfInterrupts
    local sText = 'You currently have data from %d group members (A total of %d interrupts with an average cooldown of %.2f seconds). If these numbers seem low and you know that there are more people in the raid using the addon then press the "Request Party LAS Interrupts" button in the main options window. Another way to increase this number is have your raid members use their interrupts so the addon can track them. Rember that only interrupts that hit something can be tracked and that reloading the UI wipes this database.'
    wDataText:SetText(sText:format(nMembers, nNumberOfInterrupts, nAvgInterruptCD))
    self.wOneButton:FindChild("GroupSizeInputField"):SetText("")
    self.wOneButton:FindChild("GroupSizeInputField"):InsertText("Type here the number of members for a group.")
    self.wOneButton:FindChild("GroupSizeInputField"):SetTextColor(tColor.orange)

    self.wOneButton:Show(true)
end

function addon:OnOneButtonSetupCreateGroups(wHandler)
    local wInputBox = wHandler:GetParent():FindChild("GroupSizeInputField")
    local input = wInputBox:GetText()
    if input:find("([^0-9]+)") then
        wInputBox:SetText("") -- clear the text box
        wInputBox:InsertText("That was not whole a number!") -- add in text, this way it is not hightlighted so red text color is readable
        wInputBox:SetTextColor(tColor.red)
        wInputBox:SetFocus()
    else
        local nNumberOfInterrupts, nMembers = 0,0
        for sMemberName, tInterrupts in pairs(tPartyLASInterrupts) do
            nMembers = nMembers + 1
            for nIndex, nSpellId in pairs(tInterrupts) do -- pairs here because I think I'll switch to non indexed table at some point so this makes it future proof
                nNumberOfInterrupts = nNumberOfInterrupts + 1
            end
        end
        local nMembersPerGroup = tonumber(input)
        if nMembers <= 0 then
            wInputBox:SetText("") -- clear the text box
            wInputBox:InsertText("Oops. No member data available. Hint on what to do above.") -- add in text, this way it is not hightlighted so red text color is readable
            wInputBox:SetTextColor(tColor.red)
            wInputBox:SetFocus()
        elseif (nMembers > 0 and nMembersPerGroup > nMembers) or nMembersPerGroup == 0 then -- some retard checks
            wInputBox:SetText("") -- clear the text box
            wInputBox:InsertText("Invalid number.") -- add in text, this way it is not hightlighted so red text color is readable
            wInputBox:SetTextColor(tColor.red)
            wInputBox:SetFocus()
        else
            -- one last confirmation window
            local wConfirm = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
            wConfirm:SetData({ type = "ConfirmOneButtonCreation", nMembersPerGroup = nMembersPerGroup })
            wConfirm:FindChild("Title"):SetText("Setup load warning")
            wConfirm:FindChild("HelpText"):SetText('Generationg a "One" button group setup discards the current group setup. If the current group setup is not saved already then it\'ll be lost. Continue anyways?')

            wHandler:GetParent():Show(false)
        end

    end
end

-----------------------------------------------------------------------------------------------
-- Saved Variables
-----------------------------------------------------------------------------------------------

function addon:GenerateSavableGroupTable()
    local tData = {}
    for sGroupName, tGroupData in pairs(self.tGroups) do
        tData[sGroupName] = {}
        local l,t,r,b = tGroupData.GroupContainer:GetAnchorOffsets()
        tData[sGroupName].tAnchorOffsets = { l = l, t = t, r = r, b = b }
        tData[sGroupName].bLocked = tGroupData.GroupContainer:GetData().bLocked
        tData[sGroupName].bIsShown = tGroupData.GroupContainer:IsShown()
        for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
            tData[sGroupName][nMemberIndexInGroup] = {}
            tData[sGroupName][nMemberIndexInGroup].name = tMemberData.name
            tData[sGroupName][nMemberIndexInGroup].tBars = {}
            for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
                tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex] = {}
                tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex].nSpellId = tBar.nSpellId
                tData[sGroupName][nMemberIndexInGroup].tBars[nBarIndex].nMax = tBar.nMax
            end
        end
    end
    return tData
end

function addon:LoadSavedGroups(tSavedGroupData)
    for sGroupName, _  in pairs(self.tGroups) do
        self.tGroups[sGroupName].GroupContainer:Destroy()
        self.tGroups[sGroupName] = nil
    end
    for sGroupName, tGroupData in pairs(tSavedGroupData) do
        for nMemberIndexInGroup, tMemberData in ipairs(tGroupData) do
            for nBarIndex, tBar in ipairs(tMemberData.tBars) do
                self:AddToGroup(sGroupName, tMemberData.name, tBar.nSpellId, tBar.nMax, not tGroupData.bLocked)
            end
        end
        if #tGroupData > 0 then -- not an empty group (retard check?)
            self:RedrawGroup(sGroupName, tGroupData.tAnchorOffsets)
            self:OnLockGroupButton(self.tGroups[sGroupName].GroupContainer:FindChild("Lock"))
            self.tGroups[sGroupName].GroupContainer:Show(tGroupData.bIsShown)
        end
    end
end

function addon:OnRestore(eLevel, tDB)
    if eLevel ~= GameLib.CodeEnumAddonSaveLevel.General then return end

    if tDB.tColors then
        self.tColors.cBG = tDB.tColors.cBG and tDB.tColors.cBG
        self.tColors.cProgress = tDB.tColors.cProgress and tDB.tColors.cProgress
        self.tColors.cFull = tDB.tColors.cFull and tDB.tColors.cFull
    end

    self.bAcceptGroupSync = tDB.bAcceptGroupSync
    self.bAlwaysBroadcastCooldowns = tDB.bAlwaysBroadcastCooldowns

    self.tActiveGroupData = tDB.tActiveGroupData

    self.tSavedGroups = tDB.tSavedGroups

    Apollo.RegisterTimerHandler("DelayedInit", "DelayedInit", self)

    -- XXX debug
    --self:MoO_OnSlashCommand(_, "config")
end

function addon:OnSave(eLevel)
    if eLevel ~= GameLib.CodeEnumAddonSaveLevel.General then return end -- save on the widest level so data is accessible across everything
    local tDB = {}

    tDB.tColors = self.tColors

    tDB.bAcceptGroupSync = self.bAcceptGroupSync
    tDB.bAlwaysBroadcastCooldowns = self.bAlwaysBroadcastCooldowns

    local tData = self:GenerateSavableGroupTable()

    tDB.tSavedGroups = self.tSavedGroups

    tDB.tActiveGroupData = tData

    return tDB
end

local MoOInst = addon:new()
MoOInst:Init()