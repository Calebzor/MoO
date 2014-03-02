-----------------------------------------------------------------------------------------------
-- Client Lua Script for MoO
-- Created by Caleb. All rights reserved
-----------------------------------------------------------------------------------------------

--[[-------------------------------------------------------------------------------------------
TODO:
	track and display if an interrupt hit during a cast

	when syncing groups, the group containers should be resized and repositioned to an already saved place if possible
		-- possibly by only allowing saved setups to be synced
		-- and then using that offsetdata to restore position

	let others know when someone in the group changes LAS in a way that he/she looses/gains an interrupt ability

	have a one button setup for raids for class based groups
	have a one button setup for like 5 man dungeons
	only show my group option

	notification window when receiving group sync so people know the windows are on top of each other in case of multiple groups

	hook into bossmods
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
local floor = math.floor
local Apollo = Apollo
local ActionSetLib = ActionSetLib
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

local nVersionNumber = "1"


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
	self.uPlayer = nil
	self.sChannelName = nil

	self.tColors = {
		cBG = {r=1,g=1,b=1,a=1},
		cProgress = {r=1,g=1,b=1,a=1},
		cFull = {r=1,g=1,b=1,a=1}
	}

	self.bAllGroupsLocked = nil
	self.tVersionData = {}
	self.bVersionCheckAllowed = true
	self.bAcceptGroupSync = true
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
	Apollo.RegisterSlashCommand("moo", "OnSlashCommand", self)

	Apollo.RegisterEventHandler("Group_Join", "OnGroupJoin", self)
	Apollo.RegisterEventHandler("Group_Left", "OnGroupLeft", self)
	Apollo.RegisterEventHandler("Group_Updated", "OnGroupUpdated", self)
	Apollo.RegisterEventHandler("SpecChanged", "OnSpecChanged", self)

	--self.wAbility = Apollo.LoadForm("MoO.xml", "TempAbilityWindow", nil, self)

	--Apollo.CreateTimer("UpdateBarTimer", self.nBarTimeIncrement, true)
	--Apollo.StartTimer("UpdateBarTimer")
	--Apollo.RegisterTimerHandler("UpdateBarTimer", "BarUpdater", self)
	Apollo.RegisterTimerHandler("OneSecTimer", "OnOneSecTimer", self)

	Apollo.RegisterTimerHandler("DelayedInit", "DelayedInit", self)
	Apollo.CreateTimer("DelayedInit", 1, false)

	self.CommChannel = nil
	self.wOptions = nil

	-- XXX debug


end

function addon:DelayedInit()
	self.uPlayer = GameLib.GetPlayerUnit()

	if self.tActiveGroupData and GroupLib.InGroup() then
		self:LoadSavedGroups(self.tActiveGroupData)
	end

--	self.tCurrLAS = ActionSetLib.GetCurrentActionSet() -- this should be only done on LAS change
	--testmoo()

	--self:AddToGroup("Group1", "Caleb", 32812, 35)
	--self:AddToGroup("Group1", "RaidSlinger", 46160, 20)
	--self:AddToGroup("Group1", "RaidSlinger", 34355, 30)
	--self:ShowMemberButtons(nil, true, true)

	if not self.uPlayer then
		Apollo.CreateTimer("DelayedInit", 1, false)
	end
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
	ColorPicker.AdjustCColor(color, true, colorCallback, {cColor = color, sName = wHandler:GetName()})
end

-----------------------------------------------------------------------------------------------
-- MoO Functions
-----------------------------------------------------------------------------------------------



function testmoo()


	addon:AddGroup("Group1", "Caleb", 32812, 35)
	addon:AddGroup("Group1", "RaidSlinger", 46160, 20)
	addon:AddGroup("Group1", "RaidSlinger", 34355, 30)

	--addon:AddGroup("Group2", "Caleb", 32812, 35)
	--addon:AddGroup("Group2", "RaidSlinger", 46160, 20)
	--addon:AddGroup("Group2", "RaidSlinger", 34355, 30)
    --
    --
	--addon:AddGroup("Group3", "Caleb", 32812, 35)
	--addon:AddGroup("Group3", "RaidSlinger", 46160, 20)
	--addon:AddGroup("Group3", "RaidSlinger", 34355, 30)
    --
    --
	--addon:AddGroup("Group4", "Caleb", 32812, 35)
	--addon:AddGroup("Group4", "RaidSlinger", 46160, 20)
	--addon:AddGroup("Group4", "RaidSlinger", 34355, 30)

	--addon:AddGroup("Group1", "ASDASF", 46160, 20)
	--addon:AddBarToMemberInGroup("Group1", "ASDASF", 34355)
	--addon:StartBar("Group1", "ASDASF", 46160, addon.nTimer)

	--addon:RequestPartyLASInterrupts()

	addon:ShowMemberButtons(nil, true, true)
end

function addon:OnSpecChanged(newSpecIndex, specError)
	if specError == AbilityBook.CodeEnumSpecError.Ok then
		-- warns others that I have changed my LAS (obviously only if interrupt is added/removed)

	end
end

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


function addon:OnLockGroupButton(wHandler)
	if wHandler:GetName() == "LockUnlockAllGroupsButton" then
		for _, v in pairs(self.tGroups) do
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
		if not nMax then nMax = floor(GameLib.GetSpell(nSpellId):GetCooldownTime()) end -- floor because sometimes you get values like 40.00000000000001 which is not so nice
		self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].nMax = nMax
		self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetMax(nMax)

		self:FitBarsToMember(sGroupName, sMemberName)
	end
end

function addon:StartBar(sGroupName, sMemberName, nSpellId, nStartTime)
	local nMemberIndexInGroup = getMemberOfGroupIndex(sGroupName, sMemberName)
	if nMemberIndexInGroup then
		for k, tBar in ipairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
			if tBar.nSpellId == nSpellId then
				self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[k].nStartTime = nStartTime
			end
		end
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
	if wControl:GetData() and wControl:GetData().sGroupName then
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
	wControl:SetTextColor(tColor.orange)
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

function addon:Options()
	if not self.wOptions then self.wOptions = Apollo.LoadForm("MoO.xml", "OptionsContainer", nil, self) end

	local wDeleteGroupSelectorContainer = Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("DeleteGroupSelectorContainer"), self)
	local wCopyGroupSelectorContainer = Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("CopyGroupSelectorContainer"), self)
	wDeleteGroupSelectorContainer:FindChild("MainButton"):SetText("Click to select a group")
	wCopyGroupSelectorContainer:FindChild("MainButton"):SetText("Click to select a group")

	local wSetupSelectorContainer = Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("SetupSelectorContainer"), self)
	wSetupSelectorContainer:FindChild("MainButton"):SetText("Click to select a setup")

	self.wOptions:FindChild("AllowGroupSync"):SetCheck(self.bAcceptGroupSync)
end

function addon:OnSlashCommand(_, input)
	if input then
		if input:find("config") then
			self:Options()
		end
	end
	--testmoo()
end

-----------------------------------------------------------------------------------------------
-- Party LAS Interrupts
-----------------------------------------------------------------------------------------------

-- don't forget to add the interrupt armour remover gadgets to the list too
-- these are AbilityIds not spellIds!
local tInterrupts = {
	-- Spellslinger
	[20325] = true, -- Gate
	[30160] = true, -- Arcane Shock
	[16454] = true, -- Spatial Shift
	-- Esper
	[19022] = true, -- Crush
	[19029] = true, -- Shockwave
	[19355] = true, -- Incapacitate

}

-- so basically nAbilityId is just the nId from the last tier of a spell in the ability book AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[#AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers].nId

function getAbilityIdFromAbilityName(sAbilityName)
	for nAbilityIndex, tData in pairs(AbilityBook.GetAbilitiesList()) do
		if AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[1].strName == sAbilityName then
			return AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers[#AbilityBook.GetAbilitiesList()[nAbilityIndex].tTiers].nId
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
	tPartyLASInterrupts = {} -- wipe the cache
	--add our own LAS interrupts
	tPartyLASInterrupts[self.uPlayer:GetName()] = self:MyLASInterrupts(true)
	-- request party LAS interrupts
	self:SendCommMessage({type = "RequestPartyLASInterrupts"})
end

function addon:OnDebugButton()

	local tData = {}
	for sGroupName, tGroupData in pairs(self.tGroups) do
		tData[sGroupName] = {}
		local l,t,r,b = tGroupData.GroupContainer:GetAnchorOffsets()
		tData[sGroupName].tAnchorOffsets = { l = l, t = t, r = r, b = b }
		tData[sGroupName].bLocked = tGroupData.GroupContainer:GetData().bLocked
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
	D(tData)
end

function addon:MyLASInterrupts(bReturnNotSend)
	local sMemberName = self.uPlayer and self.uPlayer:GetName()
	self.tCurrLAS = ActionSetLib.GetCurrentActionSet()
	-- We sync spellIds because you can't get description from an abilityId if it is not for your class
	local tSpellIds = {}
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

function addon:ParseLASInterrupts(tData)
	-- make sure we got data from everyone in the group if not notify the user
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
-- Bar updating
-----------------------------------------------------------------------------------------------

function addon:OnOneSecTimer()
	for sGroupName, tGroupData in pairs(self.tGroups) do
		for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
			if self.uPlayer and tMemberData.name == self.uPlayer:GetName() then
				local tBarData = {}
				for nBarIndex, tBar in ipairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
					if not tBarData[tBar.nSpellId] then -- no need to overwrite ability data
						local spellObject = GameLib.GetSpell(tBar.nSpellId)
						local nCD, nRemainingCD = floor(spellObject:GetCooldownTime()), floor(spellObject:GetCooldownRemaining())
						if nRemainingCD and nRemainingCD > 0 then
							tBar.frame:SetBarColor(TableToCColor(self.tColors.cProgress))
							tBar.frame:SetProgress(nRemainingCD)
							tBarData[tBar.nSpellId] = {tMemberData.name, nRemainingCD}
						else
							tBar.frame:SetBarColor(TableToCColor(self.tColors.cFull))
							tBar.frame:SetProgress(nCD)
							tBarData[tBar.nSpellId] = {tMemberData.name, nCD}
						end
					end
				end
				self:SendCommMessage(tBarData) -- use a single message to transmit all player bar data
			end
		end
	end
end

-- I know this is the core of the addon, but yeah it needs some cleaning up or rework, cuz this is not ideal
function addon:BarUpdater()
	self.nTimer = self.nTimer + self.nBarTimeIncrement
	for sGroupName, tGroupData in pairs(self.tGroups) do
		for nMemberIndexInGroup, tMemberData in pairs(self.tGroups[sGroupName].BarContainers) do
			for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
			-- XXX there is something wrong with time based bar accuraccy, should probably sync bar progress every couple of sec to make sure it is accurate

				-- for certain abilities just starting a timer is not good enough because there are AMPs for example that make the cooldown complete faster

				if self.uPlayer and tMemberData.name == self.uPlayer:GetName() then
					--for index, nAbilityId in pairs(self.tCurrLAS) do
						--self.wAbility:SetAbilityId(nAbilityId)
						--if nAbilityId and nAbilityId > 0 then -- only check non empty slots

					local spellObject = GameLib.GetSpell(tBar.nSpellId)
					--D(spellObject:GetId() .. " " .. spellObject:GetName())
					--if spellObject:GetId() == tBar.nSpellId then
					local nCD, nRemainingCD = spellObject:GetCooldownTime(), spellObject:GetCooldownRemaining()
					if nRemainingCD and nRemainingCD > 0 then
						--tBar.frame:SetProgress(nRemainingCD)
					else
						--tBar.frame:SetProgress(nCD)
					end
							--end

						--end
					--end
				else -- not a player bar
					if tBar.nStartTime then
						--D(tBar.nMax-self.nTimer-tBar.nStartTime)

						tBar.frame:SetProgress(tBar.nMax - self.nTimer - tBar.nStartTime)
						if self.nTimer > tBar.nStartTime + tBar.nMax then
							tBar.frame:SetProgress(tBar.nMax)
						end
					end
				end
			end
		end
	end
end

function addon:SetGroupChannel(sGroupLeader)
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
	D(self.bAcceptGroupSync)
end

function addon:SendGroups()
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

	self:SendCommMessage({type = "GroupSync", tGroupData = tData})
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
							for nBarIndex, tBar in pairs(self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars) do
								if self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].nSpellId == nSpellId then
									if tAbilityData[2] == self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nBarIndex].nMax then
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
		D("LAS request received")
		self:MyLASInterrupts()
	elseif tMsg.type == "LASInterrupts" then
		tPartyLASInterrupts[tMsg.sMemberName] = tMsg.tSpellIds
	elseif tMsg.type == "RequestVersionCheck" then
		self:SendCommMessage({type = "VersionCheckData", sMemberName = self.uPlayer:GetName(), nVersionNumber = nVersionNumber})
	elseif tMsg.type == "VersionCheckData" then
		self.tVersionData[#self.tVersionData+1] = { sName = tMsg.sMemberName, nVersionNumber = tMsg.nVersionNumber }
	elseif tMsg.type == "GroupSync" and self.bAcceptGroupSync then
		-- destroy what we have so we can start fresh
		--D(tMsg.tGroupData)
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
		self.tVersionData[#self.tVersionData+1] = { sName = self.uPlayer:GetName(), nVersionNumber = nVersionNumber}
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
				sString = ("(%s: %s)."):format(v.sName, v.nVersionNumber, sString)
			else
				sString = ("(%s: %s), %s "):format(v.sName, v.nVersionNumber, sString)
			end
		end
		Print(("MoO version info: %s"):format(sString))
		self.bVersionCheckAllowed = true
	end
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
		wHandler:GetParent():FindChild("MainButton"):SetText("Click ot select a setup")
	end
end

function addon:OnSaveGroupsCloseButtons(wHandler)
	if wHandler:GetName() == "Discard" then wHandler:GetParent():Destroy() return end -- close

	local sName = wHandler:GetParent():FindChild("EditBox"):GetText()

	if not self.tSavedGroups[sName] then
		self:SaveGroups(sName)
		wHandler:GetParent():Destroy()
	else
		local wConfirm = Apollo.LoadForm("MoO.xml", "GenericConfirmationWindow", nil, self)
		wConfirm:SetData({ type = "ConfirmSetupOverwrite", sName = sName})
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
			self.wSaveGroups:Destroy()
		end
		wHandler:GetParent():Destroy()
	elseif tParentData.type == "ConfirmSetupLoad" then
		if wHandler:GetName() == "Yes" and self.tSavedGroups[tParentData.sName] then
			self:LoadSavedGroups(self.tSavedGroups[tParentData.sName])
		end
		wHandler:GetParent():Destroy()
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
		end
	end
end

function addon:OnRestore(eLevel, tDB)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.General then return end

	if tDB.tColors then
		if tDB.tColors.cBG then
			self.tColors.cBG = tDB.tColors.cBG
		end
		if tDB.tColors.cFull then
			self.tColors.cFull = tDB.tColors.cFull
		end
		if tDB.tColors.cProgress then
			self.tColors.cProgress = tDB.tColors.cProgress
		end
	end

	self.bAcceptGroupSync = tDB.bAcceptGroupSync

	self.tActiveGroupData = tDB.tActiveGroupData

	self.tSavedGroups = tDB.tSavedGroups

	Apollo.RegisterTimerHandler("DelayedInit", "DelayedInit", self)

	--D(self.tSavedGroups)
	-- XXX debug


	self:OnSlashCommand(_, "config")
end

function addon:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.General then return end -- save on the widest level so data is accessible across everything
	local tDB = {}

	tDB.tColors = self.tColors

	tDB.bAcceptGroupSync = self.bAcceptGroupSync

	local tData = self:GenerateSavableGroupTable()

	tDB.tSavedGroups = self.tSavedGroups

	tDB.tActiveGroupData = tData

	return tDB
end

local MoOInst = addon:new()
MoOInst:Init()
