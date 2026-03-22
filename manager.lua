script_bot = {}

local tabName = nil
if ragnarokBot then
  setDefaultTab("HP")
  tabName = getTab("HP") or setDefaultTab("HP")
else
  setDefaultTab("Main")
  tabName = getTab("Main") or setDefaultTab("Main")
end

local actualVersion = 1
local script_path = "/KAIZEN/ScriptsT"
local script_path_json = script_path .. "/" .. (player and player:getName() or "global") .. ".json"
local script_list_url = "https://raw.githubusercontent.com/Guilhermewash/Scripts/main/script_list.lua"
local downloads_path = "/Scripts/downloads"

local function ensureDir(path)
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end
end

local function saveScripts()
  local res = json.encode(script_manager, 2)
  local status, err = pcall(function()
    g_resources.writeFileContents(script_path_json, res)
  end)

  if not status then
    warn("Scripts T: erro ao salvar state - " .. tostring(err))
  end
end

local function mergeStates(remoteData, localData)
  if type(remoteData) ~= "table" or type(remoteData._cache) ~= "table" then
    return remoteData
  end

  if type(localData) ~= "table" or type(localData._cache) ~= "table" then
    return remoteData
  end

  for categoryName, categoryList in pairs(remoteData._cache) do
    local localCategory = localData._cache[categoryName]
    if type(localCategory) == "table" then
      for scriptName, remoteEntry in pairs(categoryList) do
        local localEntry = localCategory[scriptName]
        if type(localEntry) == "table" then
          remoteEntry.enabled = localEntry.enabled == true
        end
      end
    end
  end

  return remoteData
end

local function readScripts()
  local data = script_manager

  if g_resources.fileExists(script_path_json) then
    local content = g_resources.readFileContents(script_path_json)
    local status, result = pcall(json.decode, content)
    if status and type(result) == "table" then
      data = mergeStates(script_manager, result)
    end
  else
    saveScripts()
  end

  script_manager = data
end

local function getEntryFiles(entry)
  if type(entry.files) == "table" and #entry.files > 0 then
    return entry.files
  end

  if entry.url then
    return {
      { path = entry.url, type = "lua" }
    }
  end

  return {}
end

local function getLocalFilePath(fileInfo)
  local localName = fileInfo.localName or (fileInfo.path and fileInfo.path:match("/([^/%?]+)$")) or "script.lua"
  return downloads_path .. "/" .. localName
end

local function importOtuis(entry)
  for _, fileInfo in ipairs(getEntryFiles(entry)) do
    local fileType = (fileInfo.type or ""):lower()
    local localPath = getLocalFilePath(fileInfo)
    if (fileType == "otui" or fileType == "ui") and g_resources.fileExists(localPath) then
      warn("Scripts T: importando UI -> " .. localPath)
      g_ui.importStyle(localPath)
    end
  end
end

local function runLuaFiles(entry)
  for _, fileInfo in ipairs(getEntryFiles(entry)) do
    local fileType = (fileInfo.type or ""):lower()
    local localPath = getLocalFilePath(fileInfo)
    if fileType == "lua" and g_resources.fileExists(localPath) then
      warn("Scripts T: executando script -> " .. localPath)
      local content = g_resources.readFileContents(localPath)
      if content and content ~= "" then
        assert(loadstring(content, "@" .. localPath))()
      end
    end
  end
end

local function downloadFiles(entry, callback)
  local files = getEntryFiles(entry)
  if #files == 0 then
    warn("Scripts T: nenhum arquivo configurado para download.")
    if callback then callback(false, "nenhum arquivo") end
    return
  end

  warn("Scripts T: iniciando download de " .. tostring(entry.description or "macro") .. " com " .. #files .. " arquivo(s).")
  local index = 1

  local function nextFile()
    local fileInfo = files[index]
    if not fileInfo then
      warn("Scripts T: download concluido.")
      if callback then callback(true) end
      return
    end

    warn("Scripts T: baixando arquivo " .. index .. "/" .. #files .. " -> " .. tostring(fileInfo.path))
    modules.corelib.HTTP.get(fileInfo.path, function(content, err)
      if err or not content or content == "" then
        warn("Scripts T: falha ao baixar -> " .. tostring(fileInfo.path) .. " | erro: " .. tostring(err))
        if callback then
          callback(false, tostring(err or "resposta vazia"))
        end
        return
      end

      local localPath = getLocalFilePath(fileInfo)
      g_resources.writeFileContents(localPath, content)
      warn("Scripts T: arquivo salvo em -> " .. localPath)
      index = index + 1
      nextFile()
    end)
  end

  nextFile()
end

local function getAllEntries()
  local entries = {}

  for categoryName, categoryList in pairs(script_manager._cache or {}) do
    for scriptName, scriptData in pairs(categoryList) do
      table.insert(entries, {
        category = categoryName,
        name = scriptName,
        data = scriptData,
      })
    end
  end

  table.sort(entries, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  return entries
end

local function loadEnabledScripts()
  for _, entry in ipairs(getAllEntries()) do
    if entry.data.enabled then
      warn("Scripts T: autoload de " .. entry.name)
      downloadFiles(entry.data, function(success, err)
  warn("Scripts T: callback do download de " .. entry.name .. " | success=" .. tostring(success) .. " | err=" .. tostring(err))

  if not success then
    warn("Scripts T: falha ao baixar " .. entry.name .. " - " .. tostring(err))
    return
  end

  warn("Scripts T: iniciando execucao do lua")
  local okLua, errLua = pcall(function()
    runLuaFiles(entry.data)
  end)
  warn("Scripts T: fim execucao do lua | ok=" .. tostring(okLua) .. " | err=" .. tostring(errLua))

  warn("Scripts T: iniciando import do otui")
  local okOtui, errOtui = pcall(function()
    importOtuis(entry.data)
  end)
  warn("Scripts T: fim import do otui | ok=" .. tostring(okOtui) .. " | err=" .. tostring(errOtui))
end)

    end
  end
end

local rowTemplate = [[
UIWidget
  background-color: alpha
  focusable: true
  height: 30

  $focus:
    background-color: #00000055

  Label
    id: textToSet
    font: terminus-14px-bold
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
]]

local function filterScripts(filterText)
  if not script_bot.widget then
    return
  end

  local search = (filterText or ""):lower()
  for _, child in pairs(script_bot.widget.scriptList:getChildren()) do
    local scriptName = (child:getId() or ""):lower()
    if search == "" or scriptName:find(search, 1, true) then
      child:show()
    else
      child:hide()
    end
  end
end

local function updateScriptList()
  script_bot.widget.scriptList:destroyChildren()

  for _, entry in ipairs(getAllEntries()) do
    local label = setupUI(rowTemplate, script_bot.widget.scriptList)
    label.textToSet:setText(entry.name)
    label.textToSet:setColor(entry.data.enabled and "green" or "#bdbdbd")
    label:setTooltip("Description: " .. (entry.data.description or "") .. "\nAuthor: " .. (entry.data.author or ""))
    label:setId(entry.name)

    label.onClick = function()
      warn("Scripts T: clique em " .. entry.name)
      entry.data.enabled = not entry.data.enabled
      saveScripts()
      label.textToSet:setColor(entry.data.enabled and "green" or "#bdbdbd")

      if entry.data.enabled then
        downloadFiles(entry.data, function(success, err)
          if not success then
            warn("Scripts T: falha ao baixar " .. entry.name .. " - " .. tostring(err))
            return
          end
          runLuaFiles(entry.data)
          importOtuis(entry.data)
        end)
      else
        warn("Scripts T: " .. entry.name .. " desativado")
      end
    end
  end

  filterScripts(script_bot.widget.searchBar:getText())
end

local function buildWindow()
  if script_bot.widget then
    return
  end

  script_bot.widget = setupUI([[
MainWindow
  !text: tr('Scripts T')
  font: terminus-14px-bold
  color: #d2cac5
  size: 300 400

  ScrollablePanel
    id: scriptList
    layout:
      type: verticalBox
    anchors.fill: parent
    margin-top: 8
    margin-left: 2
    margin-right: 15
    margin-bottom: 30
    vertical-scrollbar: scriptListScrollBar

  VerticalScrollBar
    id: scriptListScrollBar
    anchors.top: scriptList.top
    anchors.bottom: scriptList.bottom
    anchors.right: scriptList.right
    step: 14
    pixels-scroll: true
    margin-right: -10

  TextEdit
    id: searchBar
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    margin-right: 5
    width: 130

  Button
    id: closeButton
    !text: tr('Close')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.left: searchBar.right
    anchors.bottom: parent.bottom
    size: 45 21
    margin-bottom: 1
    margin-right: 5
    margin-left: 5
]], g_ui.getRootWidget())

  script_bot.widget:hide()
  script_bot.widget:setText("Scripts T - " .. actualVersion)

  script_bot.buttonWidget = UI.Button("Scripts T", function()
    if script_bot.widget:isVisible() then
      script_bot.widget:hide()
    else
      script_bot.widget:show()
      updateScriptList()
    end
  end, tabName)
  script_bot.buttonWidget:setColor("#d2cac5")

  script_bot.buttonRemoveJson = UI.Button("Reset Scripts T", function()
    if g_resources.fileExists(script_path_json) then
      g_resources.deleteFile(script_path_json)
    end
    reload()
  end, tabName)
  script_bot.buttonRemoveJson:setColor("#d2cac5")
  script_bot.buttonRemoveJson:setTooltip("Click here only when there is an update.")

  script_bot.widget.closeButton.onClick = function()
    script_bot.widget:hide()
  end

  script_bot.widget.searchBar:setTooltip("Search macros.")
  script_bot.widget.searchBar.onTextChange = function(widget, text)
    filterScripts(text)
  end
end

ensureDir(script_path)
ensureDir(downloads_path)

warn("Scripts T: baixando script_list.lua -> " .. script_list_url)
modules.corelib.HTTP.get(script_list_url, function(content, err)
  if err or not content or content == "" then
    warn("Scripts T: erro ao baixar script_list.lua - " .. tostring(err))
    return
  end

  local chunk, loadErr = loadstring(content, "@script_list.lua")
  if not chunk then
    warn("Scripts T: erro ao ler script_list.lua - " .. tostring(loadErr))
    return
  end

  chunk()

  if not script_manager then
    warn("Scripts T: script_manager nao encontrado.")
    return
  end

  warn("Scripts T: script_list.lua carregado com sucesso")
  readScripts()
  buildWindow()
  updateScriptList()
  loadEnabledScripts()

  if script_manager.actualVersion ~= actualVersion then
    script_bot.buttonRemoveJson:show()
  else
    script_bot.buttonRemoveJson:hide()
  end
end)
