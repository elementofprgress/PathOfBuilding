-- Path of Building
--
-- Module: Skills Tab
-- Skills tab for the current build.
--
local launch, main = ...

local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max

local groupSlotDropList = {
	{ label = "None" },
	{ label = "Weapon 1", slotName = "Weapon 1" },
	{ label = "Weapon 2", slotName = "Weapon 2" },
	{ label = "Weapon 1 (Swap)", slotName = "Weapon 1 Swap" },
	{ label = "Weapon 2 (Swap)", slotName = "Weapon 2 Swap" },
	{ label = "Helmet", slotName = "Helmet" },
	{ label = "Body Armour", slotName = "Body Armour" },
	{ label = "Gloves", slotName = "Gloves" },
	{ label = "Boots", slotName = "Boots" }, 
	{ label = "Amulet", slotName = "Amulet" },
	{ label = "Ring 1", slotName = "Ring 1" },
	{ label = "Ring 2", slotName = "Ring 2" },
}

local SkillsTabClass = common.NewClass("SkillsTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	self.socketGroupList = { }

	self.sortGemsByDPS = true

	-- Socket group list
	self.controls.groupList = common.New("SkillList", {"TOPLEFT",self,"TOPLEFT"}, 20, 24, 360, 300, self)
	self.controls.groupTip = common.New("LabelControl", {"TOPLEFT",self.controls.groupList,"BOTTOMLEFT"}, 0, 8, 0, 14, "^7Tip: You can copy/paste socket groups using Ctrl+C and Ctrl+V.")

	-- Gem options
	self.controls.optionSection = common.New("SectionControl", {"TOPLEFT",self.controls.groupList,"BOTTOMLEFT"}, 0, 50, 250, 100, "Gem Options")
	self.controls.sortGemsByDPS = common.New("CheckBoxControl", {"TOPLEFT",self.controls.groupList,"BOTTOMLEFT"}, 150, 70, 20, "Sort gems by DPS:", function(state)
		self.sortGemsByDPS = state
	end)
	self.controls.sortGemsByDPS.state = true
	self.controls.defaultLevel = common.New("EditControl", {"TOPLEFT",self.controls.groupList,"BOTTOMLEFT"}, 150, 94, 60, 20, nil, nil, "%D", 2, function(buf)
		self.defaultGemLevel = tonumber(buf)
	end)
	self.controls.defaultLevelLabel = common.New("LabelControl", {"RIGHT",self.controls.defaultLevel,"LEFT"}, -4, 0, 0, 16, "^7Default gem level:")
	self.controls.defaultQuality = common.New("EditControl", {"TOPLEFT",self.controls.groupList,"BOTTOMLEFT"}, 150, 118, 60, 20, nil, nil, "%D", 2, function(buf)
		self.defaultGemQuality = tonumber(buf)
	end)
	self.controls.defaultQualityLabel = common.New("LabelControl", {"RIGHT",self.controls.defaultQuality,"LEFT"}, -4, 0, 0, 16, "^7Default gem quality:")

	-- Socket group details
	self.anchorGroupDetail = common.New("Control", {"TOPLEFT",self.controls.groupList,"TOPRIGHT"}, 20, 0, 0, 0)
	self.anchorGroupDetail.shown = function()
		return self.displayGroup ~= nil
	end
	self.controls.groupLabel = common.New("EditControl", {"TOPLEFT",self.anchorGroupDetail,"TOPLEFT"}, 0, 0, 380, 20, nil, "Label", "%c", 50, function(buf)
		self.displayGroup.label = buf
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlotLabel = common.New("LabelControl", {"TOPLEFT",self.anchorGroupDetail,"TOPLEFT"}, 0, 30, 0, 16, "^7Socketed in:")
	self.controls.groupSlot = common.New("DropDownControl", {"TOPLEFT",self.anchorGroupDetail,"TOPLEFT"}, 85, 28, 130, 20, groupSlotDropList, function(index, value)
		self.displayGroup.slot = value.slotName
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlot.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode == "OUT" or index == 1 then
			tooltip:AddLine(16, "Select the item in which this skill is socketed.")
			tooltip:AddLine(16, "This will allow the skill to benefit from modifiers on the item that affect socketed gems.")
		else
			local slot = self.build.itemsTab.slots[value.slotName]
			local ttItem = self.build.itemsTab.items[slot.selItemId]
			if ttItem then
				self.build.itemsTab:AddItemTooltip(tooltip, ttItem, slot)
			else
				tooltip:AddLine(16, "No item is equipped in this slot.")
			end
		end
	end
	self.controls.groupSlot.enabled = function()
		return self.displayGroup.source == nil
	end
	self.controls.groupEnabled = common.New("CheckBoxControl", {"LEFT",self.controls.groupSlot,"RIGHT"}, 70, 0, 20, "Enabled:", function(state)
		self.displayGroup.enabled = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.sourceNote = common.New("LabelControl", {"TOPLEFT",self.controls.groupSlotLabel,"TOPLEFT"}, 0, 30, 0, 16)
	self.controls.sourceNote.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.sourceNote.label = function()
		local item = self.displayGroup.sourceItem or { rarity = "NORMAL", name = "?" }
		local itemName = colorCodes[item.rarity]..item.name.."^7"
		local activeGem = self.displayGroup.gemList[1]
		local label = [[^7This is a special group created for the ']]..activeGem.color..(activeGem.grantedEffect and activeGem.grantedEffect.name or activeGem.nameSpec)..[[^7' skill,
which is being provided by ']]..itemName..[['.
You cannot delete this group, but it will disappear if you un-equip the item.]]
		if not self.displayGroup.noSupports then
			label = label .. "\n\n" .. [[You cannot add support gems to this group, but support gems in
any other group socketed into ']]..itemName..[['
will automatically apply to the skill.]]
		end
		return label
	end

	-- Skill gem slots
	self.gemSlots = { }
	self:CreateGemSlot(1)
	self.controls.gemNameHeader = common.New("LabelControl", {"BOTTOMLEFT",self.gemSlots[1].nameSpec,"TOPLEFT"}, 0, -2, 0, 16, "^7Gem name:")
	self.controls.gemLevelHeader = common.New("LabelControl", {"BOTTOMLEFT",self.gemSlots[1].level,"TOPLEFT"}, 0, -2, 0, 16, "^7Level:")
	self.controls.gemQualityHeader = common.New("LabelControl", {"BOTTOMLEFT",self.gemSlots[1].quality,"TOPLEFT"}, 0, -2, 0, 16, "^7Quality:")
	self.controls.gemEnableHeader = common.New("LabelControl", {"BOTTOMLEFT",self.gemSlots[1].enabled,"TOPLEFT"}, -16, -2, 0, 16, "^7Enabled:")
end)

function SkillsTabClass:Load(xml, fileName)
	self.defaultGemLevel = tonumber(xml.attrib.defaultGemLevel)
	self.defaultGemQuality = tonumber(xml.attrib.defaultGemQuality)
	self.controls.defaultLevel:SetText(self.defaultGemLevel or "")
	self.controls.defaultQuality:SetText(self.defaultGemQuality or "")
	if xml.attrib.sortGemsByDPS then
		self.sortGemsByDPS = xml.attrib.sortGemsByDPS == "true"
	end
	self.controls.sortGemsByDPS.state = self.sortGemsByDPS
	for _, node in ipairs(xml) do
		if node.elem == "Skill" then
			local socketGroup = { }
			socketGroup.enabled = node.attrib.active == "true" or node.attrib.enabled == "true"
			socketGroup.label = node.attrib.label
			socketGroup.slot = node.attrib.slot
			socketGroup.source = node.attrib.source
			socketGroup.mainActiveSkill = tonumber(node.attrib.mainActiveSkill) or 1
			socketGroup.mainActiveSkillCalcs = tonumber(node.attrib.mainActiveSkillCalcs) or 1
			socketGroup.gemList = { }
			for _, child in ipairs(node) do
				local gem = { }
				gem.nameSpec = child.attrib.nameSpec or ""
				if child.attrib.skillId then
					local skill = self.build.data.skills[child.attrib.skillId]
					if skill and self.build.data.gems[skill.name] then
						gem.nameSpec = skill.name
					end
				end
				gem.level = tonumber(child.attrib.level)
				gem.quality = tonumber(child.attrib.quality)
				gem.enabled = not child.attrib.enabled and true or child.attrib.enabled == "true"
				gem.skillPart = tonumber(child.attrib.skillPart)
				gem.skillPartCalcs = tonumber(child.attrib.skillPartCalcs)
				gem.skillMinion = child.attrib.skillMinion
				gem.skillMinionCalcs = child.attrib.skillMinionCalcs
				gem.skillMinionItemSet = tonumber(child.attrib.skillMinionItemSet)
				gem.skillMinionItemSetCalcs = tonumber(child.attrib.skillMinionItemSetCalcs)
				gem.skillMinionSkill = tonumber(child.attrib.skillMinionSkill)
				gem.skillMinionSkillCalcs = tonumber(child.attrib.skillMinionSkillCalcs)
				t_insert(socketGroup.gemList, gem)
			end
			if node.attrib.skillPart and socketGroup.gemList[1] then
				socketGroup.gemList[1].skillPart = tonumber(node.attrib.skillPart)
			end
			self:ProcessSocketGroup(socketGroup)
			t_insert(self.socketGroupList, socketGroup)
		end
	end
	self:SetDisplayGroup(self.socketGroupList[1])
	self:ResetUndo()
end

function SkillsTabClass:Save(xml)
	xml.attrib = {
		defaultGemLevel = tostring(self.defaultGemLevel),
		defaultGemQuality = tostring(self.defaultGemQuality),
		sortGemsByDPS = tostring(self.sortGemsByDPS),
	}
	for _, socketGroup in ipairs(self.socketGroupList) do
		local node = { elem = "Skill", attrib = {
			enabled = tostring(socketGroup.enabled),
			label = socketGroup.label,
			slot = socketGroup.slot,
			source = socketGroup.source,
			mainActiveSkill = tostring(socketGroup.mainActiveSkill),
			mainActiveSkillCalcs = tostring(socketGroup.mainActiveSkillCalcs),
		} }
		for _, gem in ipairs(socketGroup.gemList) do
			t_insert(node, { elem = "Gem", attrib = {
				nameSpec = gem.nameSpec,
				skillId = gem.skillId,
				level = tostring(gem.level),
				quality = tostring(gem.quality),
				enabled = tostring(gem.enabled),
				skillPart = gem.skillPart and tostring(gem.skillPart),
				skillPartCalcs = gem.skillPartCalcs and tostring(gem.skillPartCalcs),
				skillMinion = gem.skillMinion,
				skillMinionCalcs = gem.skillMinionCalcs,
				skillMinionItemSet = gem.skillMinionItemSet and tostring(gem.skillMinionItemSet),
				skillMinionItemSetCalcs = gem.skillMinionItemSetCalcs and tostring(gem.skillMinionItemSetCalcs),
				skillMinionSkill = gem.skillMinionSkill and tostring(gem.skillMinionSkill),
				skillMinionSkillCalcs = gem.skillMinionSkillCalcs and tostring(gem.skillMinionSkillCalcs),
			} })
		end
		t_insert(xml, node)
	end
	self.modFlag = false
end

function SkillsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then	
			if event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			elseif event.key == "v" and IsKeyDown("CTRL") then
				self:PasteSocketGroup()
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)

	main:DrawBackground(viewPort)

	self:UpdateGemSlots()

	self:DrawControls(viewPort)
end

function SkillsTabClass:CopySocketGroup(socketGroup)
	local skillText = ""
	if socketGroup.label:match("%S") then
		skillText = skillText .. "Label: "..socketGroup.label.."\r\n"
	end
	if socketGroup.slot then
		skillText = skillText .. "Slot: "..socketGroup.slot.."\r\n"
	end
	for _, gem in ipairs(socketGroup.gemList) do
		skillText = skillText .. string.format("%s %d/%d %s\r\n", gem.nameSpec, gem.level, gem.quality, gem.enabled and "" or "DISABLED")
	end
	Copy(skillText)
end

function SkillsTabClass:PasteSocketGroup()
	local skillText = Paste()
	if skillText then
		local newGroup = { label = "", enabled = true, gemList = { } }
		local label = skillText:match("Label: (%C+)")
		if label then
			newGroup.label = label
		end
		local slot = skillText:match("Slot: (%C+)")
		if slot then
			newGroup.slot = slot
		end
		for nameSpec, level, quality, state in skillText:gmatch("([ %a']+) (%d+)/(%d+) ?(%a*)") do
			t_insert(newGroup.gemList, { nameSpec = nameSpec, level = tonumber(level) or 20, quality = tonumber(quality) or 0, enabled = state ~= "DISABLED" })
		end
		if #newGroup.gemList > 0 then
			t_insert(self.socketGroupList, newGroup)
			self.controls.groupList.selIndex = #self.socketGroupList
			self.controls.groupList.selValue = newGroup
			self:SetDisplayGroup(newGroup)
			self:AddUndoState()
			self.build.buildFlag = true
		end
	end
end

-- Create the controls for editing the gem at a given index
function SkillsTabClass:CreateGemSlot(index)
	local slot = { }
	self.gemSlots[index] = slot

	-- Delete gem
	slot.delete = common.New("ButtonControl", {"TOPLEFT",self.anchorGroupDetail,"TOPLEFT"}, 0, 28 + 28 + 16 + 22 * (index - 1), 20, 20, "x", function()
		t_remove(self.displayGroup.gemList, index)
		for index2 = index, #self.displayGroup.gemList do
			-- Update the other gem slot controls
			local gem = self.displayGroup.gemList[index2]
			self.gemSlots[index2].nameSpec:SetText(gem.nameSpec)
			self.gemSlots[index2].level:SetText(gem.level)
			self.gemSlots[index2].quality:SetText(gem.quality)
			self.gemSlots[index2].enabled.state = gem.enabled
		end
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.delete.shown = function()
		return index <= #self.displayGroup.gemList + 1 and self.displayGroup.source == nil
	end
	slot.delete.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	slot.delete.tooltipText = "Remove this gem."
	self.controls["gemSlotDelete"..index] = slot.delete

	-- Gem name specification
	slot.nameSpec = common.New("GemSelectControl", {"LEFT",slot.delete,"RIGHT"}, 2, 0, 300, 20, self, index, function(buf, addUndo)
		if not self.displayGroup then
			return
		end
		local gem = self.displayGroup.gemList[index]
		if not gem then
			if not buf:match("%S") then
				return
			end
			gem = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true }
			self.displayGroup.gemList[index] = gem
			slot.level:SetText(self.displayGroup.gemList[index].level)
			slot.quality:SetText(self.displayGroup.gemList[index].quality)
			slot.enabled.state = true
		elseif buf == gem.nameSpec then
			return
		end
		gem.nameSpec = buf
		self:ProcessSocketGroup(self.displayGroup)
		slot.level:SetText(tostring(gem.level))
		if addUndo then
			self:AddUndoState()
		end
		self.build.buildFlag = true
	end)
	slot.nameSpec:AddToTabGroup(self.controls.groupLabel)
	self.controls["gemSlotName"..index] = slot.nameSpec

	-- Gem level
	slot.level = common.New("EditControl", {"LEFT",slot.nameSpec,"RIGHT"}, 2, 0, 60, 20, nil, nil, "%D", 2, function(buf)
		local gem = self.displayGroup.gemList[index]
		if not gem then
			gem = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true }
			self.displayGroup.gemList[index] = gem
			slot.quality:SetText(self.displayGroup.gemList[index].quality)
			slot.enabled.state = true
		end
		gem.level = tonumber(buf) or self.displayGroup.gemList[index].defaultLevel or self.defaultGemLevel or 20
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.level:AddToTabGroup(self.controls.groupLabel)
	self.controls["gemSlotLevel"..index] = slot.level

	-- Gem quality
	slot.quality = common.New("EditControl", {"LEFT",slot.level,"RIGHT"}, 2, 0, 60, 20, nil, nil, "%D", 2, function(buf)
		local gem = self.displayGroup.gemList[index]
		if not gem then
			gem = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true }
			self.displayGroup.gemList[index] = gem
			slot.level:SetText(self.displayGroup.gemList[index].level)
			slot.enabled.state = true
		end
		gem.quality = tonumber(buf) or self.defaultGemQuality or 0
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.quality:AddToTabGroup(self.controls.groupLabel)
	self.controls["gemSlotQuality"..index] = slot.quality

	-- Enable gem
	slot.enabled = common.New("CheckBoxControl", {"LEFT",slot.quality,"RIGHT"}, 18, 0, 20, nil, function(state)
		local gem = self.displayGroup.gemList[index]
		if not gem then
			gem = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true }
			self.displayGroup.gemList[index] = gem
			slot.level:SetText(gem.level)
			slot.quality:SetText(gem.quality)
		end
		gem.enabled = state
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enabled.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			if self.displayGroup.gemList[index] then
				local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
				if calcFunc then
					self.displayGroup.gemList[index].enabled = not self.displayGroup.gemList[index].enabled
					local output = calcFunc()
					self.displayGroup.gemList[index].enabled = not self.displayGroup.gemList[index].enabled
					self.build:AddStatComparesToTooltip(tooltip, calcBase, output, self.displayGroup.gemList[index].enabled and "^7Disabling this gem will give you:" or "^7Enabling this gem will give you:")
				end
			end
		end
	end
	self.controls["gemSlotEnable"..index] = slot.enabled

	-- Parser/calculator error message
	slot.errMsg = common.New("LabelControl", {"LEFT",slot.enabled,"RIGHT"}, 2, 2, 0, 16, function()
		local gem = self.displayGroup.gemList[index]
		return "^1"..(gem and gem.errMsg or "")
	end)
	self.controls["gemSlotErrMsg"..index] = slot.errMsg
end

-- Update the gem slot controls to reflect the currently displayed socket group
function SkillsTabClass:UpdateGemSlots()
	if not self.displayGroup then
		return
	end
	for slotIndex = 1, #self.displayGroup.gemList + 1 do
		if not self.gemSlots[slotIndex] then
			self:CreateGemSlot(slotIndex)
		end
		local slot = self.gemSlots[slotIndex]
		if slotIndex == #self.displayGroup.gemList + 1 then
			slot.nameSpec:SetText("")
			slot.level:SetText("")
			slot.quality:SetText("")
			slot.enabled.state = false
		else
			slot.nameSpec.inactiveCol = self.displayGroup.gemList[slotIndex].color
		end
	end
end

-- Find the skill gem matching the given specification
function SkillsTabClass:FindSkillGem(nameSpec)
	-- Search for gem name using increasingly broad search patterns
	local patternList = {
		"^ "..nameSpec:gsub("%a", function(a) return "["..a:upper()..a:lower().."]" end).."$", -- Exact match (case-insensitive)
		"^"..nameSpec:gsub("%a", " %0%%l+").."$", -- Simple abbreviation ("CtF" -> "Cold to Fire")
		"^ "..nameSpec:gsub(" ",""):gsub("%l", "%%l*%0").."%l+$", -- Abbreviated words ("CldFr" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", ".*%0"), -- Global abbreviation ("CtoF" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", function(a) return ".*".."["..a:upper()..a:lower().."]" end), -- Case insensitive global abbreviation ("ctof" -> "Cold to Fire")
	}
	for i, pattern in ipairs(patternList) do
		local gemData
		for gemName, grantedEffect in pairs(self.build.data.gems) do
			if (" "..gemName):match(pattern) then
				if gemData then
					return "Ambiguous gem name '"..nameSpec.."': matches '"..gemData.name.."', '"..gemName.."'"
				end
				gemData = grantedEffect
			end
		end
		if gemData then
			return nil, gemData
		end
	end
	return "Unrecognised gem name '"..nameSpec.."'"
end

-- Processes the given socket group, filling in information that will be used for display or calculations
function SkillsTabClass:ProcessSocketGroup(socketGroup)
	-- Loop through the skill gem list
	for _, gem in ipairs(socketGroup.gemList) do
		gem.color = "^8"
		gem.nameSpec = gem.nameSpec or ""
		local prevDefaultLevel = gem.grantedEffect and gem.grantedEffect.defaultLevel
		if gem.nameSpec:match("%S") then
			-- Gem name has been specified, try to find the matching skill
			if self.build.data.gems[gem.nameSpec] then
				gem.errMsg = nil
				gem.grantedEffect = self.build.data.gems[gem.nameSpec]
			elseif self.build.data.skills[gem.nameSpec] then
				gem.errMsg = nil
				gem.grantedEffect = self.build.data.skills[gem.nameSpec]
			else
				gem.errMsg, gem.grantedEffect = self:FindSkillGem(gem.nameSpec)
				if gem.grantedEffect then
					gem.nameSpec = gem.grantedEffect.name
				end
			end
			gem.skillId = gem.grantedEffect and gem.grantedEffect.id
			if gem.grantedEffect and gem.grantedEffect.unsupported then
				gem.errMsg = gem.nameSpec.." is not supported yet"
				gem.grantedEffect = nil
			end
			if gem.grantedEffect then
				if gem.grantedEffect.color == 1 then
					gem.color = colorCodes.STRENGTH
				elseif gem.grantedEffect.color == 2 then
					gem.color = colorCodes.DEXTERITY
				elseif gem.grantedEffect.color == 3 then
					gem.color = colorCodes.INTELLIGENCE
				else
					gem.color = colorCodes.NORMAL
				end
				if prevDefaultLevel and gem.grantedEffect.defaultLevel ~= prevDefaultLevel then
					gem.level = (gem.grantedEffect.defaultLevel == 20) and self.defaultGemLevel or gem.grantedEffect.defaultLevel
					gem.defaultLevel = gem.level
				end
				calcLib.validateGemLevel(gem)
				if gem.grantedEffect.gemTags then
					gem.reqLevel = gem.grantedEffect.levels[gem.level][1]
					gem.reqStr = calcLib.gemStatRequirement(gem.reqLevel, gem.grantedEffect.support, gem.grantedEffect.gemStr)
					gem.reqDex = calcLib.gemStatRequirement(gem.reqLevel, gem.grantedEffect.support, gem.grantedEffect.gemDex)
					gem.reqInt = calcLib.gemStatRequirement(gem.reqLevel, gem.grantedEffect.support, gem.grantedEffect.gemInt)
				end
			end
		else
			gem.errMsg, gem.grantedEffect, gem.skillId = nil
		end
	end
end

-- Set the skill to be displayed/edited
function SkillsTabClass:SetDisplayGroup(socketGroup)
	self.displayGroup = socketGroup
	if socketGroup then
		self:ProcessSocketGroup(socketGroup)

		-- Update the main controls
		self.controls.groupLabel:SetText(socketGroup.label)
		self.controls.groupSlot:SelByValue(socketGroup.slot, "slotName")
		self.controls.groupEnabled.state = socketGroup.enabled

		-- Update the gem slot controls
		self:UpdateGemSlots()
		for index, gem in pairs(socketGroup.gemList) do
			self.gemSlots[index].nameSpec:SetText(gem.nameSpec)
			self.gemSlots[index].level:SetText(gem.level)
			self.gemSlots[index].quality:SetText(gem.quality)
			self.gemSlots[index].enabled.state = gem.enabled
		end
	end
end

function SkillsTabClass:AddSocketGroupTooltip(tooltip, socketGroup)
	if socketGroup.enabled and not socketGroup.slotEnabled then
		tooltip:AddLine(16, "^7Note: this group is disabled because it is socketed in the inactive weapon set.")
	end
	if socketGroup.sourceItem then
		tooltip:AddLine(18, "^7Source: "..colorCodes[socketGroup.sourceItem.rarity]..socketGroup.sourceItem.name)
		tooltip:AddSeparator(10)
	end
	local gemShown = { }
	for index, activeSkill in ipairs(socketGroup.displaySkillList) do
		if index > 1 then
			tooltip:AddSeparator(10)
		end
		tooltip:AddLine(16, "^7Active Skill #"..index..":")
		for _, gem in ipairs(activeSkill.gemList) do
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s", 
				data.skillColorMap[gem.grantedEffect.color], 
				gem.grantedEffect.name,
				gem.level, 
				(gem.srcGem and gem.level > gem.srcGem.level) and colorCodes.MAGIC.."+"..(gem.level - gem.srcGem.level).."^7" or "",
				gem.quality,
				(gem.srcGem and gem.quality > gem.srcGem.quality) and colorCodes.MAGIC.."+"..(gem.quality - gem.srcGem.quality).."^7" or ""
			))
			if gem.srcGem then
				gemShown[gem.srcGem] = true
			end
		end
		if activeSkill.minion then
			tooltip:AddSeparator(10)
			tooltip:AddLine(16, "^7Active Skill #"..index.."'s Main Minion Skill:")
			local gem = activeSkill.minion.mainSkill.gemList[1]
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s", 
				data.skillColorMap[gem.grantedEffect.color], 
				gem.grantedEffect.name, 
				gem.level, 
				(gem.srcGem and gem.level > gem.srcGem.level) and colorCodes.MAGIC.."+"..(gem.level - gem.srcGem.level).."^7" or "",
				gem.quality,
				(gem.srcGem and gem.quality > gem.srcGem.quality) and colorCodes.MAGIC.."+"..(gem.quality - gem.srcGem.quality).."^7" or ""
			))
			if gem.srcGem then
				gemShown[gem.srcGem] = true
			end
		end
	end
	local showOtherHeader = true
	for _, gem in ipairs(socketGroup.gemList) do
		if not gemShown[gem] then
			if showOtherHeader then
				showOtherHeader = false
				tooltip:AddSeparator(10)
				tooltip:AddLine(16, "^7Inactive Gems:")
			end
			local reason = ""
			local displayGem = gem.displayGem or gem
			if not gem.grantedEffect then
				reason = "(Unsupported)"
			elseif not gem.enabled then
				reason = "(Disabled)"
			elseif not socketGroup.enabled or not socketGroup.slotEnabled then
			elseif gem.grantedEffect.support then
				if displayGem.superseded then
					reason = "(Superseded)"
				elseif (not displayGem.isSupporting or not next(displayGem.isSupporting)) and #socketGroup.displaySkillList > 0 then
					reason = "(Cannot apply to any of the active skills)"
				end
			end
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s %s", 
				gem.color, 
				gem.grantedEffect and gem.grantedEffect.name or gem.nameSpec, 
				displayGem.level, 
				displayGem.level > gem.level and colorCodes.MAGIC.."+"..(displayGem.level - gem.level).."^7" or "",
				displayGem.quality,
				displayGem.quality > gem.quality and colorCodes.MAGIC.."+"..(displayGem.quality - gem.quality).."^7" or "",
				reason
			))
		end
	end
end

function SkillsTabClass:CreateUndoState()
	local state = { }
	state.socketGroupList = { }
	for _, socketGroup in ipairs(self.socketGroupList) do
		local newGroup = copyTable(socketGroup, true)
		newGroup.gemList = { }
		for index, gem in pairs(socketGroup.gemList) do
			newGroup.gemList[index] = copyTable(gem, true)
		end
		t_insert(state.socketGroupList, newGroup)
	end
	return state
end

function SkillsTabClass:RestoreUndoState(state)
	local displayId = isValueInArray(self.socketGroupList, self.displayGroup)
	wipeTable(self.socketGroupList)
	for k, v in pairs(state.socketGroupList) do
		self.socketGroupList[k] = v
	end
	self:SetDisplayGroup(displayId and self.socketGroupList[displayId])
	if self.controls.groupList.selValue then
		self.controls.groupList.selValue = self.socketGroupList[self.controls.groupList.selIndex]
	end
end
