setDefaultTab("Tools")

local panelName = "friendHeal"
storage[panelName] = storage[panelName] or {
  enabled = false,
  spell = "",
  itemId = 11863,
  hp = 99,
  delay = 1,
  distance = 1,
}

local cfg = storage[panelName]
local nextFriendHealAt = 0

local function isHealFriend(creature)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then
    return false
  end

  if isFriend and isFriend(creature:getName()) then
    return true
  end

  local emblem = nil
  local shield = nil
  if creature.getEmblem then
    emblem = creature:getEmblem()
  end
  if creature.getShield then
    shield = creature:getShield()
  end
  if emblem == 1 or shield == 3 then
    return true
  end

  return false
end

local function getHealTarget()
  local maxDistance = tonumber(cfg.distance) or 1
  local maxHp = tonumber(cfg.hp) or 99
  local playerPos = pos()
  local bestTarget = nil
  local bestHealth = 101

  for _, spec in ipairs(getSpectators()) do
    if isHealFriend(spec) then
      local specPos = spec:getPosition()
      if specPos then
        local distanceToSpec = getDistanceBetween(playerPos, specPos)
        local specHealth = spec:getHealthPercent()
        if distanceToSpec <= maxDistance and specHealth <= maxHp and specHealth < bestHealth then
          bestTarget = spec
          bestHealth = specHealth
        end
      end
    end
  end

  return bestTarget
end

local ui = setupUI([[
Panel
  height: 20
  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    text: Friend Heal
  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])

local window = UI.createWindow("FriendHealWindow", g_ui.getRootWidget())
window:hide()
window.closeButton.onClick = function()
  window:hide()
end

window.spellPanel.label:setText("Spell Heal")
window.spellPanel.input:setText(cfg.spell or "")
window.spellPanel.input.onTextChange = function(widget, text)
  cfg.spell = text
end

window.itemPanel.label:setText("Heal Item")
window.itemPanel.item:setItemId(cfg.itemId or 11863)
window.itemPanel.item.onItemChange = function(widget)
  cfg.itemId = widget:getItemId()
end

window.hpPanel.label:setText("Porcentagem para curar: " .. (cfg.hp or 99) .. "%")
window.hpPanel.scroll:setRange(1, 100)
window.hpPanel.scroll:setValue(cfg.hp or 99)
window.hpPanel.scroll.onValueChange = function(scroll, value)
  cfg.hp = value
  window.hpPanel.label:setText("Porcentagem para curar: " .. value .. "%")
end
window.hpPanel.scroll.onValueChange(window.hpPanel.scroll, window.hpPanel.scroll:getValue())

window.delayPanel.label:setText("Delay para curar: " .. (cfg.delay or 1) .. "s")
window.delayPanel.scroll:setRange(1, 120)
window.delayPanel.scroll:setValue(cfg.delay or 1)
window.delayPanel.scroll.onValueChange = function(scroll, value)
  cfg.delay = value
  window.delayPanel.label:setText("Delay para curar: " .. value .. "s")
end
window.delayPanel.scroll.onValueChange(window.delayPanel.scroll, window.delayPanel.scroll:getValue())

window.distancePanel.label:setText("Distancia de heal: " .. (cfg.distance or 1))
window.distancePanel.scroll:setRange(1, 10)
window.distancePanel.scroll:setValue(cfg.distance or 1)
window.distancePanel.scroll.onValueChange = function(scroll, value)
  cfg.distance = value
  window.distancePanel.label:setText("Distancia de heal: " .. value)
end
window.distancePanel.scroll.onValueChange(window.distancePanel.scroll, window.distancePanel.scroll:getValue())

local function syncFriendHealState(isEnabled)
  cfg.enabled = isEnabled
  ui.title:setOn(isEnabled)
end

syncFriendHealState(cfg.enabled == true)

ui.title.onClick = function(widget)
  syncFriendHealState(not cfg.enabled)
end

ui.settings.onClick = function()
  window:show()
  window:raise()
  window:focus()
end

macro(100, "Friend Heal", function()
  if not cfg.enabled then return end
  if now < nextFriendHealAt then return end

  local healTarget = getHealTarget()
  if not healTarget then return end

  local spell = (cfg.spell or ""):trim()
  if spell ~= "" then
    say(spell .. ' "' .. healTarget:getName())
  else
    local itemId = tonumber(cfg.itemId) or 0
    if itemId <= 0 then return end
    useWith(itemId, healTarget)
  end

  nextFriendHealAt = now + ((tonumber(cfg.delay) or 1) * 1000)
end)
