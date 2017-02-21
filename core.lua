local _, SimcTrinketComparison = ...

SimcTrinketComparison = LibStub("AceAddon-3.0"):NewAddon(SimcTrinketComparison, "SimcTrinketComparison", "AceConsole-3.0", "AceEvent-3.0")

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
local OFFSET_GEM_ID_2 = 4
local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_SUFFIX_ID = 7
local OFFSET_FLAGS = 11
local OFFSET_BONUS_ID = 13
local OFFSET_UPGRADE_ID = 14 -- Flags = 0x4

-- Artifact stuff (adapted from LibArtifactData [https://www.wowace.com/addons/libartifactdata-1-0/], thanks!)
local ArtifactUI          = _G.C_ArtifactUI
local HasArtifactEquipped = _G.HasArtifactEquipped
local SocketInventoryItem = _G.SocketInventoryItem
local Timer               = _G.C_Timer

-- load stuff from extras.lua
local upgradeTable  = SimcTrinketComparison.upgradeTable
local slotNames     = SimcTrinketComparison.slotNames
local simcSlotNames = SimcTrinketComparison.simcSlotNames
local specNames     = SimcTrinketComparison.SpecNames
local profNames     = SimcTrinketComparison.ProfNames
local regionString  = SimcTrinketComparison.RegionString
local artifactTable = SimcTrinketComparison.ArtifactTable

-- TODO: this is quick and dirty, do it 
local RING_MODE = false

-- Most of the guts of this addon were based on a variety of other ones, including
-- Statslog, AskMrRobot, and BonusScanner. And a bunch of hacking around with AceGUI.
-- Many thanks to the authors of those addons, and to reia for fixing my awful amateur
-- coding mistakes regarding objects and namespaces.

function SimcTrinketComparison:OnInitialize()
  SimcTrinketComparison:RegisterChatCommand('simct', 'PrintTrinketComparison')
  SimcTrinketComparison:RegisterChatCommand('simcr', 'PrintRingComparison')
end

function SimcTrinketComparison:OnEnable()
  SimcTrinketComparisonTooltip:SetOwner(_G["UIParent"],"ANCHOR_NONE")
end

function SimcTrinketComparison:OnDisable()

end

-- SimC tokenize function
local function tokenize(str)
  str = str or ""
  -- convert to lowercase and remove spaces
  str = string.lower(str)
  str = string.gsub(str, ' ', '_')

  -- keep stuff we want, dumpster everything else
  local s = ""
  for i=1,str:len() do
    -- keep digits 0-9
    if str:byte(i) >= 48 and str:byte(i) <= 57 then
      s = s .. str:sub(i,i)
      -- keep lowercase letters
    elseif str:byte(i) >= 97 and str:byte(i) <= 122 then
      s = s .. str:sub(i,i)
      -- keep %, +, ., _
    elseif str:byte(i)==37 or str:byte(i)==43 or str:byte(i)==46 or str:byte(i)==95 then
      s = s .. str:sub(i,i)
    end
  end
  -- strip trailing spaces
  if string.sub(s, s:len())=='_' then
    s = string.sub(s, 0, s:len()-1)
  end
  return s
end

-- method for constructing the talent string
local function CreateSimcTalentString()
  local talentInfo = {}
  local maxTiers = 7
  local maxColumns = 3
  for tier = 1, maxTiers do
    for column = 1, maxColumns do
      local talentID, name, iconTexture, selected, available = GetTalentInfo(tier, column, GetActiveSpecGroup())
      if selected then
        talentInfo[tier] = column
      end
    end
  end

  local str = 'talents='
  for i = 1, maxTiers do
    if talentInfo[i] then
      str = str .. talentInfo[i]
    else
      str = str .. '0'
    end
  end

  return str
end

-- function that translates between the game's role values and ours
local function translateRole(str)
  if str == 'TANK' then
    return tokenize(str)
  elseif str == 'DAMAGER' then
    return 'attack'
  elseif str == 'HEALER' then
    return 'healer'
  else
    return ''
  end
end

-- ================= Artifact Information =======================

local function IsArtifactFrameOpen()
  local ArtifactFrame = _G.ArtifactFrame
  return ArtifactFrame and ArtifactFrame:IsShown() or false
end

function SimcTrinketComparison:GetArtifactString()
  if not HasArtifactEquipped() then
    return nil
  end

  if not IsArtifactFrameOpen() then
    SocketInventoryItem(INVSLOT_MAINHAND)
  end

  local item_id = select(1, ArtifactUI.GetArtifactInfo())
  if item_id == nil or item_id == 0 then
    return nil
  end

  local artifact_id = self.ArtifactTable[item_id]
  if artifact_id == nil then
    return nil
  end

  -- Note, relics are handled by the item string
  local str = 'artifact=' .. artifact_id .. ':0:0:0:0'

  local powers = ArtifactUI.GetPowers()
  for i = 1, #powers do
    local power_id = powers[i]
    local _, _, currentRank, _, bonusRanks = ArtifactUI.GetPowerInfo(power_id)
    if currentRank > 0 and currentRank - bonusRanks > 0 then
      str = str .. ':' .. power_id .. ':' .. (currentRank - bonusRanks)
    end
  end

  return str
end

-- =================== Item Information =========================

function SimcTrinketComparison:GetItemStrings()
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      local itemString = string.match(itemLink, "item:([%-?%d:]+)")
      local itemSplit = {}
      local simcItemOptions = {}

      -- Split data into a table
      for v in string.gmatch(itemString, "(%d*:?)") do
        if v == ":" then
          itemSplit[#itemSplit + 1] = 0
        else
          itemSplit[#itemSplit + 1] = string.gsub(v, ':', '')
        end
      end

      -- Item id
      local itemId = itemSplit[OFFSET_ITEM_ID]
      simcItemOptions[#simcItemOptions + 1] = ',id=' .. itemId

      -- Enchant
      if tonumber(itemSplit[OFFSET_ENCHANT_ID]) > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'enchant_id=' .. itemSplit[OFFSET_ENCHANT_ID]
      end

      -- New style item suffix, old suffix style not supported
      if tonumber(itemSplit[OFFSET_SUFFIX_ID]) ~= 0 then
        simcItemOptions[#simcItemOptions + 1] = 'suffix=' .. itemSplit[OFFSET_SUFFIX_ID]
      end

      local flags = tonumber(itemSplit[OFFSET_FLAGS])

      local bonuses = {}

      for index=1, tonumber(itemSplit[OFFSET_BONUS_ID]) do
        bonuses[#bonuses + 1] = itemSplit[OFFSET_BONUS_ID + index]
      end

      if #bonuses > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
      end

      local rest_offset = OFFSET_BONUS_ID + #bonuses + 1

      -- Upgrade level
      if bit.band(flags, 4) == 4 then
        local upgrade_id = tonumber(itemSplit[rest_offset])
        if self.upgradeTable[upgrade_id] ~= nil and self.upgradeTable[upgrade_id] > 0 then
          simcItemOptions[#simcItemOptions + 1] = 'upgrade=' .. self.upgradeTable[upgrade_id]
        end
        rest_offset = rest_offset + 1
      end

      -- Artifacts use this
      if bit.band(flags, 256) == 256 then
        rest_offset = rest_offset + 1 -- An unknown field
        local relic_str = ''
        while rest_offset < #itemSplit do
          local n_bonus_ids = tonumber(itemSplit[rest_offset])
          rest_offset = rest_offset + 1

          if n_bonus_ids == 0 then
            relic_str = relic_str .. 0
          else
            for rbid = 1, n_bonus_ids do
              relic_str = relic_str .. itemSplit[rest_offset]
              if rbid < n_bonus_ids then
                relic_str = relic_str .. ':'
              end
              rest_offset = rest_offset + 1
            end
          end

          if rest_offset < #itemSplit then
            relic_str = relic_str .. '/'
          end
        end

        if relic_str ~= '' then
          simcItemOptions[#simcItemOptions + 1] = 'relic_id=' .. relic_str
        end
      end

      -- Some leveling quest items seem to use this, it'll include the drop level of the item
      if bit.band(flags, 512) == 512 then
        simcItemOptions[#simcItemOptions + 1] = 'drop_level=' .. itemSplit[rest_offset]
        rest_offset = rest_offset + 1
      end

      -- Gems
      local gems = {}
      for i=1, 4 do -- hardcoded here to just grab all 4 sockets
        local _,gemLink = GetItemGem(itemLink, i)
        if gemLink then
          local gemDetail = string.match(gemLink, "item[%-?%d:]+")
          gems[#gems + 1] = string.match(gemDetail, "item:(%d+):" )
        elseif flags == 256 then
          gems[#gems + 1] = "0"
        end
      end
      if #gems > 0 then
        simcItemOptions[#simcItemOptions + 1] = 'gem_id=' .. table.concat(gems, '/')
      end

      items[slotNum] = simcSlotNames[slotNum] .. "=" .. table.concat(simcItemOptions, ',')
    end
  end

  return items
end

function SimcTrinketComparison:PrintTrinketComparison()
  SimcTrinketComparison:PrintSimcProfile('Trinket', 'trinket', 'INVTYPE_TRINKET')
end

function SimcTrinketComparison:PrintRingComparison()
  SimcTrinketComparison:PrintSimcProfile('Finger', 'finger', 'INVTYPE_FINGER')
end

function SimcTrinketComparison:GetItemInfo(itemId, itemLink, equipSlotFilter, iLevelFilter, indexOut, itemsOut, itemNamesOut, itemsUsedOut)
  if (itemLink) then
    local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)
    
    if equipSlot == equipSlotFilter and iLevel >= iLevelFilter then
      itemsOut[indexOut] = '=,id=' .. itemId
      itemNamesOut[indexOut] = string.gsub(name, ' ', '') .. iLevel
      itemsUsedOut[indexOut] = {}

      local itemString = string.match(itemlink, "item:([%-?%d:]+)")
      local itemSplit = {}
      local simcItemOptions = {}

      -- Split data into a table
      for v in string.gmatch(itemString, "(%d*:?)") do
        if v == ":" then
          itemSplit[#itemSplit + 1] = 0
        else
          itemSplit[#itemSplit + 1] = string.gsub(v, ':', '')
        end
      end

      local bonuses = {}

      for index=1, tonumber(itemSplit[OFFSET_BONUS_ID]) do
        bonuses[#bonuses + 1] = itemSplit[OFFSET_BONUS_ID + index]
      end

      if #bonuses > 0 then
        itemsOut[indexOut] = itemsOut[indexOut] .. ',bonus_id=' .. table.concat(bonuses, '/')
      end

      -- Gems
      local gems = {}
      for i=1, 4 do -- hardcoded here to just grab all 4 sockets
        local _,gemLink = GetItemGem(itemlink, i)
        if gemLink then
          local gemDetail = string.match(gemLink, "item[%-?%d:]+")
          gems[#gems + 1] = string.match(gemDetail, "item:(%d+):" )
        elseif flags == 256 then
          gems[#gems + 1] = "0"
        end
      end
      if #gems > 0 then
        itemsOut[indexOut] = itemsOut[indexOut] .. ',gem_id=' .. table.concat(gems, '/')
      end
      return indexOut + 1
    end
  else
    return indexOut
  end --close if exists
end

-- This is the workhorse function that constructs the profile
function SimcTrinketComparison:PrintSimcProfile(slotName, simcSlotName, equipFilter)
  -- Basic player info
  local playerName = UnitName('player')
  local _, playerClass = UnitClass('player')
  local playerLevel = UnitLevel('player')
  local playerRealm = GetRealmName()
  local playerRegion = regionString[GetCurrentRegion()]

  -- Race info
  local _, playerRace = UnitRace('player')
  -- fix some races to match SimC format
  if playerRace == 'BloodElf' then
    playerRace = 'Blood Elf'
  elseif playerRace == 'NightElf' then
    playerRace = 'Night Elf'
  elseif playerRace == 'Scourge' then --lulz
    playerRace = 'Undead'
  end

  -- Spec info
  local role, globalSpecID
  local specId = GetSpecialization()
  if specId then
    globalSpecID,_,_,_,_,role = GetSpecializationInfo(specId)
  end
  local playerSpec = specNames[ globalSpecID ]

  -- Professions
  local pid1, pid2 = GetProfessions()
  local firstProf, firstProfRank, secondProf, secondProfRank, profOneId, profTwoId
  if pid1 then
    _,_,firstProfRank,_,_,_,profOneId = GetProfessionInfo(pid1)
  end
  if pid2 then
    secondProf,_,secondProfRank,_,_,_,profTwoId = GetProfessionInfo(pid2)
  end

  firstProf = profNames[ profOneId ]
  secondProf = profNames[ profTwoId ]

  local playerProfessions = ''
  if pid1 or pid2 then
    playerProfessions = 'professions='
    if pid1 then
      playerProfessions = playerProfessions..tokenize(firstProf)..'='..tostring(firstProfRank)..'/'
    end
    if pid2 then
      playerProfessions = playerProfessions..tokenize(secondProf)..'='..tostring(secondProfRank)
    end
  else
    playerProfessions = ''
  end

  -- Construct SimC-compatible strings from the basic information
  local player = tokenize(playerClass) .. '="' .. playerName .. '"'
  playerLevel = 'level=' .. playerLevel
  playerRace = 'race=' .. tokenize(playerRace)
  playerRole = 'role=' .. translateRole(role)
  playerSpec = 'spec=' .. tokenize(playerSpec)
  playerRealm = 'server=' .. tokenize(playerRealm)
  playerRegion = 'region=' .. tokenize(playerRegion)

  -- Talents are more involved - method to handle them
  local playerTalents = CreateSimcTalentString()
  local playerArtifact = self:GetArtifactString()

  -- Build the output string for the player (not including gear)
  local simulationcraftProfile = '###########################################################################################\n'
  simulationcraftProfile = simulationcraftProfile .. '# ATTENTION:\n'
  simulationcraftProfile = simulationcraftProfile .. '# In order to increase performance the following line disables calculating scaling factors.\n'
  simulationcraftProfile = simulationcraftProfile .. '# If you wish to calculate them, remove this line.\n'
  simulationcraftProfile = simulationcraftProfile .. '###########################################################################################\n'
  simulationcraftProfile = simulationcraftProfile .. 'calculate_scale_factors=0\n'
  simulationcraftProfile = simulationcraftProfile .. '###########################################################################################\n\n'
  
  simulationcraftProfile = simulationcraftProfile .. player .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerLevel .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRace .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRegion .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRealm .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerRole .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerProfessions .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerTalents .. '\n'
  simulationcraftProfile = simulationcraftProfile .. playerSpec .. '\n'
  if playerArtifact ~= nil then
    simulationcraftProfile = simulationcraftProfile .. playerArtifact .. '\n'
  end
  simulationcraftProfile = simulationcraftProfile .. '\n'

  -- Method that gets gear information
  local items = SimcTrinketComparison:GetItemStrings()

  -- output gear
  for slotNum=1, #slotNames do
    if items[slotNum] then
      simulationcraftProfile = simulationcraftProfile .. items[slotNum] .. '\n'
    end
  end

-- Item Comparison
local items = {}
local itemNames = {}
local itemsUsed = {}
local a = 1

simulationcraftProfile = string.gsub(simulationcraftProfile, UnitName('player'), 'CurrentlyEquipped') -- replace name of the player with CurrentlyEquipped

for bag=0, NUM_BAG_SLOTS do
  for bagSlots=1, GetContainerNumSlots(bag) do
    local itemlink = GetContainerItemLink(bag, bagSlots)
    local itemId = GetContainerItemID(bag, bagSlots)
    a = SimcTrinketComparison:GetItemInfo(itemId, itemLink, equipFilter, 800, a, items, itemNames, itemsUsed)
  end -- close bagslots loop
end --close bags loop

for i=0,1 do
  local itemlink = GetInventoryItemLink("player", GetInventorySlotInfo(slotName..i.."Slot"))
  local itemId = GetInventoryItemID("player", GetInventorySlotInfo(slotName..i.."Slot"))
  a = SimcTrinketComparison:GetItemInfo(itemId, itemLink, equipFilter, 800, a, items, itemNames, itemsUsed)
end

if a > 2 then
	for b=1, a do
		for c=1, a do
			if itemsUsed[b][c] ~= true then
				itemsUsed[b][c] = false
			end
		end
	end

	for b=1, a do
		for c=1, a do
			if itemsUsed[b][c] == false and itemsUsed[c][b] == false and itemNames[c] ~= itemNames[b] then
				simulationcraftProfile = simulationcraftProfile .. '\n'
				simulationcraftProfile = simulationcraftProfile .. 'copy=' .. itemNames[b] .. '_' .. itemNames[c] .. '\n'
			  simulationcraftProfile = simulationcraftProfile .. simcSlotName .. '1' .. items[b] .. '\n'
			  simulationcraftProfile = simulationcraftProfile .. simcSlotName .. '2' .. items[c] .. '\n'
				itemsUsed[b][c] = true
				itemsUsed[c][b] = true
			end
		end
	end
end

  -- sanity checks - if there's anything that makes the output completely invalid, punt!
  if specId == nil then
    simulationcraftProfile = "Error: You need to pick a spec!"
  end

  -- show the appropriate frames
  SimcCopyFrame:Show()
  SimcCopyFrameScroll:Show()
  SimcCopyFrameScrollText:Show()
  SimcCopyFrameScrollText:SetText(simulationcraftProfile)
  SimcCopyFrameScrollText:HighlightText()
end
