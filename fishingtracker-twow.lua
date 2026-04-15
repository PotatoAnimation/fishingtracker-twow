local addonName = "fishingtracker-twow"

local frame = CreateFrame("Frame", "TatoFishingFrame")
frame:SetScript("OnEvent", function()
  if frame[event] then
    frame[event](frame, arg1)
  end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("ITEM_ENCHANT_CHANGED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("CHAT_MSG_LOOT")

local scannerTooltip = nil
local lureUI = nil
local statsUI = nil
local lastUpdate = 0

local MODE_SESSION = 1
local MODE_WEEK = 2
local MODE_OVERALL = 3
local currentMode = MODE_SESSION

local sessionStats = {}

local lureDataByItemID = {
  [6529] = { bonus = 25, name = "Shiny Bauble" },
  [6530] = { bonus = 50, name = "Nightcrawlers" },
  [6532] = { bonus = 75, name = "Bright Baubles" },
  [6811] = { bonus = 100, name = "Aquadynamic Fish Attractor" },
  [7307] = { bonus = 100, name = "Flesh Eating Worm" },
  [34861] = { bonus = 100, name = "Sharpened Fish Hook" },
}

-- Track only known fish item IDs.
-- Send more IDs and we can extend this list quickly.
local trackedFishIDs = {
  [787] = true,    -- Raw Slitherskin Mackerel
  [6362] = true,   -- Raw Rockscale Cod
  [7973] = true,   -- Big-mouth Clam
  [7974] = true,   -- Raw Bristle Whisker Catfish
  [7975] = true,   -- Raw Rockscale Cod
  [7976] = true,   -- Raw Spotted Yellowtail
  [7977] = true,   -- Raw Rainbow Fin Albacore
  [8604] = true,   -- Raw Redgill
  [8605] = true,   -- Raw Mithril Head Trout
  [8606] = true,   -- Raw Loch Frenzy
  [8607] = true,   -- Raw Blackmouth Oil
  [8608] = true,   -- Raw Diamond Fish
  [8609] = true,   -- Raw Golden Sansam
  [4592] = true,   -- Longjaw Mud Snapper
  [4593] = true,   -- Bristle Whisker Catfish
  [4594] = true,   -- Rockscale Cod
  [4603] = true,   -- Raw Spotted Yellowtail
  [5095] = true,   -- Rainbow Fin Albacore
  [6289] = true,   -- Raw Longjaw Mud Snapper
  [6290] = true,   -- Brilliant Smallfish
  [6291] = true,   -- Raw Brilliant Smallfish
  [6308] = true,   -- Raw Bristle Whisker Catfish
  [6317] = true,   -- Raw Loch Frenzy
  [6358] = true,   -- Oily Blackmouth
  [6361] = true,   -- Raw Rainbow Fin Albacore
  [6522] = true,   -- Deviate Fish
  [13422] = true,  -- Stonescale Eel
  [13754] = true,  -- Raw Glossy Mightfish
  [13755] = true,  -- Winter Squid
  [13756] = true,  -- Raw Summer Bass
  [13758] = true,  -- Raw Redgill
  [13759] = true,  -- Raw Nightfin Snapper
  [13760] = true,  -- Raw Sunscale Salmon
  [13888] = true,  -- Darkclaw Lobster
  [13889] = true,  -- Raw Whitescale Salmon
}

local function EnsureDB()
  if not TatoFishingDB then TatoFishingDB = {} end
  if not TatoFishingDB.point then TatoFishingDB.point = "CENTER" end
  if not TatoFishingDB.relativePoint then TatoFishingDB.relativePoint = "CENTER" end
  if TatoFishingDB.x == nil then TatoFishingDB.x = 0 end
  if TatoFishingDB.y == nil then TatoFishingDB.y = -180 end
  if not TatoFishingDB.stats then TatoFishingDB.stats = {} end
  if not TatoFishingDB.stats.lifetime then TatoFishingDB.stats.lifetime = {} end
  if not TatoFishingDB.stats.daily then TatoFishingDB.stats.daily = {} end
  if not TatoFishingDB.stats.meta then TatoFishingDB.stats.meta = {} end
end

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffTatoFishing|r: " .. msg)
  end
end

local function GetTodayStamp()
  return tostring(math.floor(time() / 86400))
end

local function PruneDailyBuckets()
  local today = math.floor(time() / 86400)
  for stamp, _ in pairs(TatoFishingDB.stats.daily) do
    local n = tonumber(stamp)
    if not n or n < (today - 6) then
      TatoFishingDB.stats.daily[stamp] = nil
    end
  end
end

local function GetMainHandItemID()
  local link = GetInventoryItemLink("player", 16)
  if not link then return nil end
  local _, _, itemID = string.find(link, "item:(%d+)")
  return tonumber(itemID)
end

local function IsFishingPoleEquipped()
  local itemID = GetMainHandItemID()
  if not itemID then return false end

  local _, _, _, _, _, itemType, itemSubType, _, invType = GetItemInfo(itemID)
  if invType == "INVTYPE_FISHINGPOLE" then
    return true
  end
  if itemSubType and string.find(string.lower(itemSubType), "fishing") then
    return true
  end
  if itemType and string.find(string.lower(itemType), "weapon") and itemSubType and string.find(string.lower(itemSubType), "fish") then
    return true
  end

  local texture = GetInventoryItemTexture("player", 16)
  if texture and string.find(string.lower(texture), "fishingpole") then
    return true
  end

  if not scannerTooltip then
    scannerTooltip = CreateFrame("GameTooltip", "TatoFishingScannerTooltip", nil, "GameTooltipTemplate")
    scannerTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
  end

  scannerTooltip:ClearLines()
  scannerTooltip:SetInventoryItem("player", 16)
  for i = 1, 10 do
    local leftLine = _G["TatoFishingScannerTooltipTextLeft" .. i]
    local text = leftLine and leftLine:GetText()
    if text and string.find(string.lower(text), "fishing") then
      return true
    end
  end

  return false
end

local function HasLureAndTimeLeft()
  if type(GetWeaponEnchantInfo) ~= "function" then
    return false, 0
  end
  local hasMainHandEnchant, mainHandExpiration = GetWeaponEnchantInfo()
  if not hasMainHandEnchant then return false, 0 end
  local seconds = math.floor((mainHandExpiration or 0) / 1000)
  if seconds < 0 then seconds = 0 end
  return true, seconds
end

local function FormatDuration(seconds)
  local m = math.floor(seconds / 60)
  local s = math.mod(seconds, 60)
  return string.format("%d:%02d", m, s)
end

local function FindBestLureInBags()
  local bestBag, bestSlot, bestData
  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, _, itemID = string.find(link, "item:(%d+)")
          itemID = tonumber(itemID)
          local lure = itemID and lureDataByItemID[itemID] or nil
          if lure and (not bestData or lure.bonus > bestData.bonus) then
            bestBag, bestSlot, bestData = bag, slot, lure
          end
        end
      end
    end
  end
  return bestBag, bestSlot, bestData
end

local function ApplyBestLure()
  if not IsFishingPoleEquipped() then
    Print("Equip a fishing pole first.")
    return
  end

  local bag, slot, lure = FindBestLureInBags()
  if not bag or not slot then
    Print("No known fishing lure found in bags.")
    return
  end

  UseContainerItem(bag, slot)
  if type(SpellIsTargeting) == "function" and SpellIsTargeting() then
    PickupInventoryItem(16)
  elseif CursorHasItem() then
    PickupInventoryItem(16)
  end

  if type(SpellIsTargeting) == "function" and SpellIsTargeting() then
    SpellStopTargeting()
  end
  if CursorHasItem() then
    ClearCursor()
  end

  Print("Applied " .. lure.name .. " (+" .. lure.bonus .. ").")
end

local function AddFishCount(itemID, itemName, amount)
  if amount < 1 then return end

  local key = itemID and tostring(itemID) or ("name:" .. itemName)
  sessionStats[key] = (sessionStats[key] or 0) + amount

  TatoFishingDB.stats.meta[key] = { name = itemName, itemID = itemID }
  TatoFishingDB.stats.lifetime[key] = (TatoFishingDB.stats.lifetime[key] or 0) + amount

  local today = GetTodayStamp()
  if not TatoFishingDB.stats.daily[today] then
    TatoFishingDB.stats.daily[today] = {}
  end
  local dayBucket = TatoFishingDB.stats.daily[today]
  dayBucket[key] = (dayBucket[key] or 0) + amount
end

local function ResetFishData()
  sessionStats = {}
  Print("Session fish data reset.")
end

local function BuildViewData(mode)
  local view = {}

  if mode == MODE_SESSION then
    for key, count in pairs(sessionStats) do
      view[key] = count
    end
  elseif mode == MODE_OVERALL then
    for key, count in pairs(TatoFishingDB.stats.lifetime) do
      view[key] = count
    end
  else
    local today = math.floor(time() / 86400)
    for stamp, bucket in pairs(TatoFishingDB.stats.daily) do
      local s = tonumber(stamp)
      if s and s >= (today - 6) then
        for key, count in pairs(bucket) do
          view[key] = (view[key] or 0) + count
        end
      end
    end
  end

  return view
end

local function GetSortedEntries(mode)
  local view = BuildViewData(mode)
  local entries = {}
  for key, count in pairs(view) do
    if count > 0 then
      table.insert(entries, { key = key, count = count })
    end
  end
  table.sort(entries, function(a, b) return a.count > b.count end)
  return entries
end

local function GetModeLabel(mode)
  if mode == MODE_SESSION then return "Session" end
  if mode == MODE_WEEK then return "Last 7 Days" end
  return "Overall"
end

local function CreateLureUI()
  if lureUI then return end

  lureUI = CreateFrame("Frame", "TatoFishingLurePanel", UIParent)
  lureUI:SetWidth(210)
  lureUI:SetHeight(96)
  lureUI:SetPoint(TatoFishingDB.point, UIParent, TatoFishingDB.relativePoint, TatoFishingDB.x, TatoFishingDB.y)
  lureUI:SetMovable(true)
  lureUI:EnableMouse(true)
  lureUI:RegisterForDrag("LeftButton")
  lureUI:SetClampedToScreen(true)
  lureUI:SetFrameStrata("MEDIUM")

  lureUI:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  lureUI:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
  lureUI:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

  lureUI:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then
      this:StartMoving()
    end
  end)
  lureUI:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local p, _, rp, x, y = this:GetPoint()
    TatoFishingDB.point = p
    TatoFishingDB.relativePoint = rp
    TatoFishingDB.x = x
    TatoFishingDB.y = y
    if statsUI then
      statsUI:ClearAllPoints()
      statsUI:SetPoint("TOPLEFT", lureUI, "BOTTOMLEFT", 0, -6)
    end
  end)

  lureUI.icon = lureUI:CreateTexture(nil, "ARTWORK")
  lureUI.icon:SetTexture("Interface\\Icons\\Trade_Fishing")
  lureUI.icon:SetWidth(30)
  lureUI.icon:SetHeight(30)
  lureUI.icon:SetPoint("TOPLEFT", 8, -8)

  lureUI.title = lureUI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lureUI.title:SetPoint("TOPLEFT", lureUI.icon, "TOPRIGHT", 8, -1)
  lureUI.title:SetText("TatoFishing Lure")

  lureUI.status = lureUI:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lureUI.status:SetPoint("TOPLEFT", lureUI.title, "BOTTOMLEFT", 0, -4)
  lureUI.status:SetText("Checking lure...")

  lureUI.timer = lureUI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lureUI.timer:SetPoint("TOPLEFT", lureUI.status, "BOTTOMLEFT", 0, -2)
  lureUI.timer:SetText("")

  lureUI.applyButton = CreateFrame("Button", "TatoFishingApplyButton", lureUI, "UIPanelButtonTemplate")
  lureUI.applyButton:SetWidth(96)
  lureUI.applyButton:SetHeight(22)
  lureUI.applyButton:SetPoint("BOTTOMRIGHT", -8, 8)
  lureUI.applyButton:SetText("Apply Lure")
  lureUI.applyButton:SetScript("OnClick", function()
    ApplyBestLure()
  end)

  lureUI:Hide()
end

local function CreateStatsUI()
  if statsUI then return end

  statsUI = CreateFrame("Frame", "TatoFishingStatsPanel", UIParent)
  statsUI:SetWidth(210)
  statsUI:SetHeight(180)
  statsUI:SetPoint("TOPLEFT", lureUI, "BOTTOMLEFT", 0, -6)
  statsUI:SetFrameStrata("MEDIUM")
  statsUI:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  statsUI:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
  statsUI:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

  statsUI.title = statsUI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  statsUI.title:SetPoint("TOPLEFT", 10, -8)
  statsUI.title:SetText("Fish Meter")

  statsUI.mode = CreateFrame("Frame", "TatoFishingModeDropDown", statsUI, "UIDropDownMenuTemplate")
  statsUI.mode:SetPoint("TOPRIGHT", -18, 8)
  UIDropDownMenu_SetWidth(84, statsUI.mode)
  UIDropDownMenu_Initialize(statsUI.mode, function()
    local info = {}
    info.func = function()
      currentMode = this.value
      UIDropDownMenu_SetSelectedValue(statsUI.mode, currentMode)
    end

    info.text = "Session"
    info.value = MODE_SESSION
    info.checked = currentMode == MODE_SESSION
    UIDropDownMenu_AddButton(info)

    info = {}
    info.func = function()
      currentMode = this.value
      UIDropDownMenu_SetSelectedValue(statsUI.mode, currentMode)
    end
    info.text = "Last 7 Days"
    info.value = MODE_WEEK
    info.checked = currentMode == MODE_WEEK
    UIDropDownMenu_AddButton(info)

    info = {}
    info.func = function()
      currentMode = this.value
      UIDropDownMenu_SetSelectedValue(statsUI.mode, currentMode)
    end
    info.text = "Overall"
    info.value = MODE_OVERALL
    info.checked = currentMode == MODE_OVERALL
    UIDropDownMenu_AddButton(info)
  end)
  UIDropDownMenu_SetSelectedValue(statsUI.mode, currentMode)
  UIDropDownMenu_SetText(GetModeLabel(currentMode), statsUI.mode)

  statsUI.resetButton = CreateFrame("Button", "TatoFishingResetButton", statsUI, "UIPanelButtonTemplate")
  statsUI.resetButton:SetWidth(18)
  statsUI.resetButton:SetHeight(18)
  statsUI.resetButton:SetPoint("TOPRIGHT", -8, -8)
  statsUI.resetButton:SetText("X")
  statsUI.resetButton:SetScript("OnClick", function()
    ResetFishData()
    if statsUI and statsUI.total then
      statsUI.total:SetText("Total: 0")
    end
  end)
  statsUI.resetButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("Reset Session Data")
    GameTooltip:AddLine("Clears only Session totals.", 1, 1, 1)
    GameTooltip:Show()
  end)
  statsUI.resetButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  statsUI.total = statsUI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statsUI.total:SetPoint("TOPLEFT", 10, -30)
  statsUI.total:SetText("Total: 0")

  statsUI.rows = {}
  for i = 1, 8 do
    local row = CreateFrame("StatusBar", nil, statsUI)
    row:SetWidth(190)
    row:SetHeight(14)
    row:SetPoint("TOPLEFT", 10, -34 - (i * 16))
    row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row:SetMinMaxValues(0, 1)
    row:SetValue(0)
    row:SetStatusBarColor(0.2, 0.55, 0.9, 0.8)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(0.1, 0.1, 0.1, 0.6)

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.left:SetPoint("LEFT", 3, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetText("")

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", -3, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetText("")

    statsUI.rows[i] = row
  end

  statsUI:Hide()
end

local function UpdateLureUI()
  local hasRod = IsFishingPoleEquipped()
  if not hasRod then
    lureUI:Hide()
    return
  end

  lureUI:Show()

  local hasLure, secondsLeft = HasLureAndTimeLeft()
  local bag, slot, bestLure = FindBestLureInBags()

  if hasLure then
    lureUI.status:SetText("|cff66ff66Lure Active|r")
    lureUI.timer:SetText("Time left: " .. FormatDuration(secondsLeft))
    lureUI.applyButton:Disable()
    lureUI.applyButton:SetText("Active")
  else
    lureUI.status:SetText("|cffff6666No Lure Active|r")
    lureUI.timer:SetText("Best available: " .. (bestLure and (bestLure.name .. " (+" .. bestLure.bonus .. ")") or "None"))
    lureUI.applyButton:Enable()
    lureUI.applyButton:SetText("Apply Lure")
    if not bag or not slot then
      lureUI.applyButton:Disable()
      lureUI.applyButton:SetText("No Lure")
    end
  end
end

local function UpdateStatsUI()
  local hasRod = IsFishingPoleEquipped()
  if not hasRod then
    statsUI:Hide()
    return
  end

  statsUI:Show()
  UIDropDownMenu_SetText(GetModeLabel(currentMode), statsUI.mode)

  local entries = GetSortedEntries(currentMode)
  local total = 0
  local maxCount = 1
  for _, entry in ipairs(entries) do
    total = total + entry.count
    if entry.count > maxCount then
      maxCount = entry.count
    end
  end
  statsUI.total:SetText("Total: " .. total)

  for i = 1, 8 do
    local row = statsUI.rows[i]
    local entry = entries[i]
    if entry then
      local meta = TatoFishingDB.stats.meta[entry.key]
      local name = (meta and meta.name) or entry.key
      row.left:SetText(name)
      row.right:SetText(entry.count)
      row:SetMinMaxValues(0, maxCount)
      row:SetValue(entry.count)
      row:Show()
    else
      row.left:SetText("")
      row.right:SetText("")
      row:SetMinMaxValues(0, 1)
      row:SetValue(0)
      row:Hide()
    end
  end
end

local function UpdateAllUI()
  if not lureUI or not statsUI then return end
  UpdateLureUI()
  UpdateStatsUI()
end

function frame:CHAT_MSG_LOOT(msg)
  if not msg or not IsFishingPoleEquipped() then return end

  local selfLoot = string.find(msg, "You receive loot:") or string.find(msg, "You loot")
  if not selfLoot then return end

  local _, _, itemID, itemName = string.find(msg, "|Hitem:(%d+).-|h%[(.-)%]|h")
  itemID = tonumber(itemID)
  if not itemName then return end
  if not trackedFishIDs[itemID] then return end

  local amount = 1
  local _, _, qty = string.find(msg, "x(%d+)")
  if qty then amount = tonumber(qty) or 1 end

  AddFishCount(itemID, itemName, amount)
  UpdateStatsUI()
end

function frame:ADDON_LOADED(loadedName)
  if loadedName ~= addonName then return end
  EnsureDB()
  PruneDailyBuckets()
  CreateLureUI()
  CreateStatsUI()
  UpdateAllUI()
  self:UnregisterEvent("ADDON_LOADED")
end

function frame:PLAYER_ENTERING_WORLD()
  PruneDailyBuckets()
  UpdateAllUI()
end

function frame:PLAYER_EQUIPMENT_CHANGED(slotID)
  if slotID == 16 then
    UpdateAllUI()
  end
end

function frame:UNIT_INVENTORY_CHANGED()
  UpdateAllUI()
end

function frame:ITEM_ENCHANT_CHANGED()
  UpdateAllUI()
end

function frame:BAG_UPDATE()
  UpdateAllUI()
end

frame:SetScript("OnUpdate", function()
  lastUpdate = lastUpdate + arg1
  if lastUpdate < 0.5 then return end
  lastUpdate = 0
  UpdateAllUI()
end)
