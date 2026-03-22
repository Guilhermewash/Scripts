script_bot = script_bot or {}

local tabName = nil
if ragnarokBot then
  setDefaultTab("HP")
  tabName = getTab("HP") or setDefaultTab("HP")
else
  setDefaultTab("Main")
  tabName = getTab("Main") or setDefaultTab("Main")
end

local actualVersion = 1
local storageDir = "/KAIZEN/ScriptsT"
local storageFile = storageDir .. "/" .. (player and player:getName() or "global") .. ".json"
local scriptListUrl = "https://raw.githubusercontent.com/Guilhermewash/Scripts/refs/heads/master/script_list.lua"

local function ensureStorage()
  if not g_resources.directoryExists(storageDir) then
    g_resources.makeDir(storageDir)
  end
end

local function saveScripts()
  local payload = json.encode(script_manager, 2)
  local ok, err = pcall(function()
    g_resources.writeFileContents(storageFile, payload)
  end)

  if not ok then
    warn("Scripts T: erro ao salvar state - " .. tostring(err))
  end
end

local function readScripts()
  local data = script_manager

  if g_resources.fileExists(storageFile) then
    local content = g_resources.readFileContents(storageFile)
    local ok, decoded = pcall(json.decode, content)
    if ok and type(decoded) == "table" then
      data = decoded
    end
  else
    saveScripts()
  end

  script_manager = data
end

local function getAllScripts()
  local list = {}

  for categoryName, categoryList in pairs(script_manager._cache or {}) do
    for scriptName, scriptData in pairs(categoryList) do
      table.insert(list, {
        category = categoryName,
        name = scriptName,
        data = scriptData,
      })
    end
  end

  table.sort(list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  return list
end

local function getEntryFiles(entry)
  if type(entry.data.files) == "table" and #entry.data.files > 0 then
    return entry.data.files
  end

  return {
    {
      path = entry.data.url,
      type = "lua",
      localName = entry.data.localName or entry.data.fileName,
    }
  }
end

local function getDownloadPath(fileInfo)
  local localName = fileInfo.localName or fileInfo.fileName or fileInfo.name
  if not localName or localName == "" then
    localName = fileInfo.path and fileInfo.path:match("/([^/%?]+)$") or "script.lua"
  end
  return "/Scripts/downloads/" .. localName
end

local function importEntryOtuis(entry)
  for _, fileInfo in ipairs(getEntryFiles(entry)) do
    local localPath = getDownloadPath(fileInfo)
    local fileType = (fileInfo.type or localPath:match("%.([^.]+)$") or ""):lower()
    if (fileType == "otui" or fileType == "ui") and g_resources.fileExists(localPath) then
      g_ui.importStyle(localPath)
    end
  end
end

local function loadEntryLua(entry)
  for _, fileInfo in ipairs(getEntryFiles(entry)) do
    local localPath = getDownloadPath(fileInfo)
    local fileType = (fileInfo.type or localPath:match("%.([^.]+)$") or ""):lower()
    if fileType == "lua" and g_resources.fileExists(localPath) then
      local script = g_resources.readFileContents(localPath)
      if script and script ~= "" then
        assert(loadstring(script, "@" .. localPath))()
      end
    end
  end
end

local function downloadEntryFiles(entry, callback)
  local files = getEntryFiles(entry)
  local total = #files
  local index = 1

  local function nextFile()
    local fileInfo = files[index]
    if not fileInfo then
      if callback then
        callback(true)
      end
      return
    end

    local remotePath = fileInfo.path or fileInfo.url
    if not remotePath or remotePath == "" then
      if callback then
        callback(false, "arquivo remoto vazio")
      end
      return
    end

    modules.corelib.HTTP.get(remotePath, function(content, err)
      if err or not content or content == "" then
        if callback then
          callback(false, err or "resposta vazia")
        end
        return
      end

      g_resources.writeFileContents(getDownloadPath(fileInfo), content)
      index = index + 1
      nextFile()
    end)
  end

  nextFile()
end

local function loadEnabledScripts()
  for _, entry in ipairs(getAllScripts()) do
    if entry.data.enabled then
      downloadEntryFiles(entry, function(success)
        if success then
          importEntryOtuis(entry)
          loadEntryLua(entry)
        end
      end)
    end
  end
end

local rowTemplate = [[
UIWidget
  background-color: alpha
  focusable: true
  height: 34

  $focus:
    background-color: #00000055

  Label
    id: textToSet
    font: terminus-14px-bold
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    margin-left: 8
]]

local function updateRow(entry, row)
  row.textToSet:setText(entry.name)
  row.textToSet:setColor(entry.data.enabled and "green" or "#bdbdbd")
  row:setTooltip("Descricao: " .. (entry.data.description or "") .. "\nAutor: " .. (entry.data.author or "") .. "\nCategoria: " .. (entry.category or ""))
  row:setId(entry.name)
end

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

local function refreshList()
  if not script_bot.widget then
    return
  end

  script_bot.widget.scriptList:destroyChildren()

  for _, entry in ipairs(getAllScripts()) do
    local row = setupUI(rowTemplate, script_bot.widget.scriptList)
    updateRow(entry, row)

    row.onClick = function()
      entry.data.enabled = not entry.data.enabled
      saveScripts()
      updateRow(entry, row)

      if entry.data.enabled then
        downloadEntryFiles(entry, function(success, err)
          if not success then
            warn("Scripts T: falha ao baixar " .. entry.name .. " - " .. tostring(err))
            return
          end
          importEntryOtuis(entry)
          loadEntryLua(entry)
        end)
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
  size: 320 400

  ScrollablePanel
    id: scriptList
    layout:
      type: verticalBox
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: searchBar.top
    margin-top: 8
    margin-left: 2
    margin-right: 15
    margin-bottom: 8
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
    anchors.right: closeButton.left
    anchors.bottom: parent.bottom
    margin-left: 5
    margin-right: 5
    margin-bottom: 2
    height: 21

  Button
    id: closeButton
    !text: tr('Close')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 55 21
    margin-bottom: 1
    margin-right: 5
]], g_ui.getRootWidget())

  script_bot.widget:hide()
  script_bot.widget:setText("Scripts T - " .. actualVersion)

  script_bot.widget.closeButton.onClick = function()
    script_bot.widget:hide()
  end

  script_bot.widget.searchBar:setTooltip("Pesquisar macro.")
  script_bot.widget.searchBar.onTextChange = function(widget, text)
    filterScripts(text)
  end

  script_bot.buttonWidget = UI.Button("Scripts T", function()
    if script_bot.widget:isVisible() then
      script_bot.widget:hide()
    else
      script_bot.widget:show()
      script_bot.widget:raise()
      script_bot.widget:focus()
      refreshList()
    end
  end, tabName)
  script_bot.buttonWidget:setColor("#d2cac5")

  script_bot.buttonRemoveJson = UI.Button("Reset Scripts T", function()
    if g_resources.fileExists(storageFile) then
      g_resources.deleteFile(storageFile)
    end
    reload()
  end, tabName)
  script_bot.buttonRemoveJson:setColor("#d2cac5")
  script_bot.buttonRemoveJson:setTooltip("Limpa o estado salvo do manager.")
end

ensureStorage()

modules.corelib.HTTP.get(scriptListUrl, function(content, err)
  if err or not content or content == "" then
    warn("Scripts T: erro ao baixar script_list.lua")
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

  readScripts()
  buildWindow()
  refreshList()
  loadEnabledScripts()

  if script_manager.actualVersion and script_manager.actualVersion ~= actualVersion then
    script_bot.buttonRemoveJson:show()
  else
    script_bot.buttonRemoveJson:hide()
  end
end)
