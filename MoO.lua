-----------------------------------------------------------------------------------------------
-- Client Lua Script for MoO
-- Created by Caleb. All rights reserved
-----------------------------------------------------------------------------------------------

--[[-------------------------------------------------------------------------------------------
TODO:
	let others know when someone in the group changes LAS in a way that he/she looses/gains an interrupt ability

	ability to save and load group setups
	have a one button setup for like 5 man dungeons

	hook into bossmods
]]---------------------------------------------------------------------------------------------

require "ActionSetLib"
require "GameLib"
require "GroupLib"
require "ICCommLib"
require "CColor"

local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local table = table
local type = type
local string = string
local tonumber = tonumber
local Apollo = Apollo
local ActionSetLib = ActionSetLib
local GameLib = GameLib
local GroupLib = GroupLib
local ICCommLib = ICCommLib
local CColor = CColor
local _ = _


local MoO = {}
local addon = MoO


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
	self.wAbility = nil
	self.uPlayer = nil
	self.sChannelName = nil


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

	self.wAbility = Apollo.LoadForm("MoO.xml", "TempAbilityWindow", nil, self)

	--Apollo.CreateTimer("UpdateBarTimer", self.nBarTimeIncrement, true)
	--Apollo.StartTimer("UpdateBarTimer")
	--Apollo.RegisterTimerHandler("UpdateBarTimer", "BarUpdater", self)
	Apollo.RegisterTimerHandler("OneSecTimer", "OnOneSecTimer", self)

	Apollo.RegisterTimerHandler("DelayedInit", "DelayedInit", self)
	Apollo.CreateTimer("DelayedInit", 1, false)

	self.CommChannel = nil
	self.wOptions = nil

	-- XXX debug
	self:OnSlashCommand(_, "config")

end

function addon:DelayedInit()
	self.uPlayer = GameLib.GetPlayerUnit()
	self.tCurrLAS = ActionSetLib.GetCurrentActionSet() -- this should be only done on LAS update
	testmoo()
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
	for k, v in ipairs(addon.tGroups[sGroupName].BarContainers) do
		if v.name == sMemberName then
			return k
		end
	end
	return false
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


	addon:ShowShiftButtons(true)
end

function addon:ShowShiftButtons(bShow)
	for sGroupName, _ in pairs(self.tGroups) do
		for indexOfMember, _ in ipairs(self.tGroups[sGroupName].BarContainers) do
			self.tGroups[sGroupName].BarContainers[indexOfMember].frame:FindChild("ShiftUp"):Show(indexOfMember ~= 1 and bShow or false)
			self.tGroups[sGroupName].BarContainers[indexOfMember].frame:FindChild("ShiftDown"):Show(indexOfMember ~= #self.tGroups[sGroupName].BarContainers and bShow or false)
		end
	end
end

function addon:AddGroup(sGroupName, sMemberName, name, nMax)
	self:NewGroup(sGroupName)
	self:AddMemberToGroup(sGroupName, sMemberName)
	self:AddBarToMemberInGroup(sGroupName, sMemberName, name, nMax)


end

function addon:NewGroup(sGroupName)
	if self.tGroups[sGroupName] then return end -- that group already exists
	self.tGroups[sGroupName] = {}
	self.tGroups[sGroupName].GroupContainer = Apollo.LoadForm("MoO.xml", "GroupContainer", nil, self)
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

		--self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBarColor(hexToCColor("EEEEEE", 0.5))    -- XXX fix these colors
		--self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBGColor(hexToCColor("FFFFFF", 0.5))     -- XXX fix these colors

		self.tGroups[sGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].nSpellId = nSpellId -- this can be a spellId or just a text
		if not nMax then nMax = GameLib.GetSpell(nSpellId):GetCooldownTime() end
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

function addon:RedrawGroup(sGroupName)
	local l,t,r,b = self.tGroups[sGroupName].GroupContainer:GetAnchorOffsets()
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
	addon:ShowShiftButtons(true)
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
			if sSourceGroupName == "No groups added yet" then return end -- retard check
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

					--self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBarColor(hexToCColor("EEEEEE", 0.5))    -- XXX fix these colors
					--self.tGroups[sNewGroupName].BarContainers[nMemberIndexInGroup].bars[nNumOfBars].frame:SetBGColor(hexToCColor("FFFFFF", 0.5))     -- XXX fix these colors

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

	Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("DeleteGroupSelectorContainer"), self)
	Apollo.LoadForm("MoO.xml", "DropDownWidget", self.wOptions:FindChild("CopyGroupSelectorContainer"), self)
end

function addon:OnSlashCommand(_, input)
	if input then
		if input == "config" then
			self:Options()
		end
	end
	--testmoo()
end

-----------------------------------------------------------------------------------------------
-- Dropdown Widget
-----------------------------------------------------------------------------------------------

function addon:OnDropDownMainButton(wHandler)
	local tEntries = {}
	local tData = {}
	if wHandler:GetParent():GetParent():GetName():find("Group") then -- it is a group dropdown
		tData = self.tGroups
	end
	local choiceContainer = wHandler:FindChild("ChoiceContainer")
	choiceContainer:DestroyChildren() -- clear the container, we populate it every time it opens
	choiceContainer:SetData({})
	local nGroupCounter = 0
	local wEntry
	for sNewGroupName, _ in pairs(tData) do
		wEntry = Apollo.LoadForm("MoO.xml", "DropDownWidgetEntryButton", choiceContainer, self)
		wEntry:SetText(sNewGroupName)
		wEntry:Show(true)
		nGroupCounter = nGroupCounter + 1
	end
	choiceContainer:ArrangeChildrenVert(0)
	if nGroupCounter == 0 then -- no groups added yet add an entry that says that
		wEntry = Apollo.LoadForm("MoO.xml", "DropDownWidgetEntryButton", choiceContainer, self)
		wEntry:SetText("No groups added yet")
		wEntry:Show(true)
		nGroupCounter = nGroupCounter + 1
	end

	local l,t,r,b = choiceContainer:GetAnchorOffsets()
	choiceContainer:SetAnchorOffsets(l, t, r, t+nGroupCounter*wEntry:GetHeight())
	choiceContainer:Show(true)
	l,t,r,b = wHandler:FindChild("ChoiceContainerBG"):GetAnchorOffsets()
	wHandler:FindChild("ChoiceContainerBG"):SetAnchorOffsets(l, t, r, t+nGroupCounter*wEntry:GetHeight()+30)
	wHandler:FindChild("ChoiceContainerBG"):Show(true)
end

function addon:OnDropDownEntrySelect(wHandler)
	wHandler:GetParent():GetParent():SetText(wHandler:GetText())
	wHandler:GetParent():Show(false)
	wHandler:GetParent():GetParent():FindChild("ChoiceContainerBG"):Show(false)
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
					local spellObject = GameLib.GetSpell(tBar.nSpellId)
					local nCD, nRemainingCD = spellObject:GetCooldownTime(), spellObject:GetCooldownRemaining()
					if nRemainingCD and nRemainingCD > 0 then
						tBar.frame:SetProgress(nRemainingCD)
						tBarData[nBarIndex] = {sGroupName = sGroupName, sMemberName = tMemberData.name, nBarIndex = nBarIndex, nProgress = nRemainingCD}
					else
						tBar.frame:SetProgress(nCD)
						tBarData[nBarIndex] = {sGroupName = sGroupName, sMemberName = tMemberData.name, nBarIndex = nBarIndex, nProgress = nCD}
					end
				end
				self:SendCommMessage({type = "barupdate", tBarData = tBarData,}) -- use a single message to transmit all player bar data
			end
		end
	end
end

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



	--for k, wndBar in next, self.tBars do
	--	if wndBar then
	--		local nStart, nDuration = unpack(wndBar:GetData())
	--		local nEnd = nStart + nDuration
	--		wndBar:FindChild("ProgressBar"):SetMax(nDuration)
	--		wndBar:FindChild("ProgressBar"):SetProgress(self.nTimer-nStart)
	--		wndBar:FindChild("Time"):SetText(("%.1f"):format(nEnd-self.nTimer))
	--		if self.nTimer > nEnd then -- delete expired bar
	--			wndBar:Destroy()
	--			self.tBars[k] = nil
	--		end
	--	end
	--end
	--self.wndBars:ArrangeChildrenVert(0)
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

function addon:OnCommMessage(channel, tMsg)

	if channel ~= self.CommChannel then return nil end

	--D(tMsg)
	if tMsg.type == "barupdate" then
		for nBarIndex, tBarData in ipairs(tMsg.tBarData) do
			local nMemberIndexInGroup = getMemberOfGroupIndex(tBarData.sGroupName, tBarData.sMemberName)
			if self.tGroups[tBarData.sGroupName] and self.tGroups[tBarData.sGroupName].BarContainers[nMemberIndexInGroup] and self.tGroups[tBarData.sGroupName].BarContainers[nMemberIndexInGroup].bars[tBarData.nBarIndex] then
				self.tGroups[tBarData.sGroupName].BarContainers[nMemberIndexInGroup].bars[tBarData.nBarIndex].frame:SetProgress(tBarData.nProgress)
			end
		end
	end
	--self:UpdateSpell(tMsg)
end

-- Apollo.GetAddon("MoO"):SendCommMessage("poop")
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


local MoOInst = addon:new()
MoOInst:Init()
