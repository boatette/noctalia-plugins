--!nonstrict

local STATE_KEY = "overrides"

local DEFAULT_GLYPH = {
  scrolling = "carousel-horizontal",
  dwindle = "chart-treemap",
}

local cfg = {}

local overrides = {}
local activeByOutput = {}
local ownOutput = ""
local focusedOutput = ""
local rules = {}
local defaultMode = "scrolling"
local pending = false
local watching = false

local function trim(value)
  return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function isMode(value)
  return value == "scrolling" or value == "dwindle"
end

local function otherMode(value)
  return value == "dwindle" and "scrolling" or "dwindle"
end

local function getString(key)
  return trim(noctalia.getConfig(key))
end

local function readConfig()
  cfg = {
    displayMode = getString("display_mode"),
    glyph = {
      scrolling = getString("scrolling_glyph"),
      dwindle = getString("dwindle_glyph"),
    },
    word = {
      scrolling = getString("scrolling_word"),
      dwindle = getString("dwindle_word"),
    },
    letter = {
      scrolling = getString("scrolling_letter"),
      dwindle = getString("dwindle_letter"),
    },
    color = noctalia.getConfig("color"),
    glyphSize = noctalia.getConfig("glyph_size"),
    fontSize = noctalia.getConfig("font_size"),
    gap = noctalia.getConfig("gap"),
    uppercaseLetter = noctalia.getConfig("uppercase_letter"),
    showTooltip = noctalia.getConfig("show_tooltip"),
    notifyOnToggle = noctalia.getConfig("notify_on_toggle"),
    fallbackMode = getString("fallback_mode"),
    configPath = getString("umbriel_config_path"),
    watchCommand = getString("watch_command"),
  }
end

local function tomlString(value)
  return value:match('^"(.-)"') or value:match("^'(.-)'")
end

local function loadUmbrielConfig()
  rules = {}
  defaultMode = "scrolling"

  local path = cfg.configPath
  if path == "" then
    local configHome = noctalia.getenv("XDG_CONFIG_HOME")
    if configHome ~= nil and configHome ~= "" then
      path = configHome .. "/umbriel/config.toml"
    else
      path = noctalia.expandPath("~/.config/umbriel/config.toml")
    end
  else
    path = noctalia.expandPath(path)
  end

  local text = noctalia.readFile(path)
  if text ~= nil and text ~= "" then
    local section = ""
    local rule = nil

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local stripped = trim((line:gsub("#.*$", "")))
      local arrayHeader = stripped:match("^%[%[%s*(.-)%s*%]%]$")
      local tableHeader = stripped:match("^%[%s*(.-)%s*%]$")

      if arrayHeader ~= nil then
        section = arrayHeader
        if arrayHeader == "workspace" then
          rule = {}
          rules[#rules + 1] = rule
        end
      elseif tableHeader ~= nil then
        section = tableHeader
      else
        local key, value = stripped:match("^([%w_%.]+)%s*=%s*(.+)$")
        if key ~= nil then
          if section == "layout" and key == "mode" then
            local mode = tomlString(value)
            if isMode(mode) then
              defaultMode = mode
            end
          elseif rule ~= nil and section == "workspace" then
            if key == "index" then
              rule.index = tonumber(value)
            elseif key == "name" then
              rule.name = tomlString(value)
            elseif key == "output" then
              rule.output = tomlString(value)
            elseif key == "layout.mode" then
              rule.mode = tomlString(value)
            end
          elseif rule ~= nil and section == "workspace.layout" and key == "mode" then
            rule.mode = tomlString(value)
          end
        end
      end
    end
  end

  if isMode(cfg.fallbackMode) then
    defaultMode = cfg.fallbackMode
  end
end

local function configModeFor(output, workspace)
  local mode = defaultMode
  local index = tonumber(workspace)

  for _, scopedPass in ipairs({ false, true }) do
    for _, rule in ipairs(rules) do
      local scoped = rule.output ~= nil and rule.output ~= ""
      if scoped == scopedPass and (not scoped or rule.output == output) then
        local matches = false
        if rule.name ~= nil then
          matches = rule.name == workspace
        elseif rule.index ~= nil then
          matches = index ~= nil and rule.index == index
        end
        if matches and isMode(rule.mode) then
          mode = rule.mode
        end
      end
    end
  end

  return mode
end

local function workspaceKey(output, workspace)
  return output .. "/" .. workspace
end

local function refreshOutputs()
  local own = trim(barWidget.outputName())
  if own ~= "" then
    ownOutput = own
  end
  local focused = trim(noctalia.focusedOutputName())
  if focused ~= "" then
    focusedOutput = focused
  end
end

local function workspaceOn(output)
  if output ~= "" and activeByOutput[output] ~= nil then
    return output, activeByOutput[output]
  end

  local onlyOutput, onlyWorkspace, count = nil, nil, 0
  for candidate, workspace in pairs(activeByOutput) do
    onlyOutput, onlyWorkspace, count = candidate, workspace, count + 1
  end
  if count == 1 then
    return onlyOutput, onlyWorkspace
  end

  return nil, nil
end

local function shownWorkspace()
  return workspaceOn(ownOutput)
end

local function targetWorkspace()
  local output, workspace = workspaceOn(focusedOutput)
  if workspace ~= nil then
    return output, workspace
  end
  return shownWorkspace()
end

local function modeOf(output, workspace)
  if workspace == nil then
    return defaultMode
  end
  local override = overrides[workspaceKey(output, workspace)]
  if isMode(override) then
    return override
  end
  return configModeFor(output, workspace)
end

local function shownMode()
  return modeOf(shownWorkspace())
end

local function targetMode()
  return modeOf(targetWorkspace())
end

local function glyphFor(value)
  local custom = cfg.glyph[value]
  if custom ~= "" then
    return custom
  end
  return DEFAULT_GLYPH[value]
end

local function isLiteralGlyph(value)
  return value:find("[\128-\255]") ~= nil
end

local function wordFor(value)
  local custom = cfg.word[value]
  if custom ~= "" then
    return custom
  end
  return noctalia.tr("layout." .. value)
end

local function firstChar(text)
  local lead = text:byte(1)
  if lead == nil then
    return ""
  end
  local width = 1
  if lead >= 0xF0 then
    width = 4
  elseif lead >= 0xE0 then
    width = 3
  elseif lead >= 0xC0 then
    width = 2
  end
  return text:sub(1, width)
end

local function letterFor(value)
  local custom = cfg.letter[value]
  if custom ~= "" then
    return custom
  end
  local letter = firstChar(wordFor(value))
  return cfg.uppercaseLetter and letter:upper() or letter
end

local function wantsGlyph()
  local display = cfg.displayMode
  return display == "icon" or display == "icon_letter" or display == "icon_word"
end

local function textFor(value)
  local display = cfg.displayMode
  if display == "letter" or display == "icon_letter" then
    return letterFor(value)
  end
  if display == "word" or display == "icon_word" then
    return wordFor(value)
  end
  return ""
end

local function render()
  local mode = shownMode()
  local children = {}

  if wantsGlyph() then
    local glyph = glyphFor(mode)
    if isLiteralGlyph(glyph) then
      children[#children + 1] = ui.label({
        key = "glyph-char",
        text = glyph,
        fontSize = cfg.glyphSize,
        color = cfg.color,
      })
    else
      children[#children + 1] = ui.glyph({
        key = "glyph",
        name = glyph,
        size = cfg.glyphSize,
        color = cfg.color,
      })
    end
  end

  local text = textFor(mode)
  if text ~= "" then
    children[#children + 1] = ui.label({
      key = "label",
      text = text,
      fontSize = cfg.fontSize,
      color = cfg.color,
    })
  end

  if #children == 0 then
    children[1] = ui.label({
      key = "label",
      text = letterFor(mode),
      fontSize = cfg.fontSize,
      color = cfg.color,
    })
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = cfg.gap, align = "center" }, children))

  if cfg.showTooltip then
    local _, workspace = shownWorkspace()
    barWidget.setTooltip(noctalia.tr("tooltip", {
      current = wordFor(mode),
      next = wordFor(otherMode(mode)),
      workspace = workspace or "?",
    }))
  else
    barWidget.clearTooltip()
  end
end

local function rememberChoice(output, workspace, value)
  if workspace ~= nil then
    overrides[workspaceKey(output, workspace)] = value
  end
  noctalia.state.set(STATE_KEY, overrides)
  render()
end

local function apply(next)
  if not isMode(next) or pending then
    return
  end
  pending = true

  local output, workspace = targetWorkspace()

  local started = noctalia.runAsync({ "umbriel", "msg", "workspace-set-layout:" .. next }, function(result)
    pending = false
    if result.exitCode ~= 0 then
      local detail = trim(result.stderr)
      if detail == "" then
        detail = trim(result.stdout)
      end
      if detail == "" then
        detail = noctalia.tr("error.exit", { code = tostring(result.exitCode) })
      end
      noctalia.notifyError(noctalia.tr("error.title"), detail)
      return
    end

    rememberChoice(output, workspace, next)
    if cfg.notifyOnToggle then
      noctalia.notify(noctalia.tr("notify.title"), wordFor(next))
    end
  end)

  if not started then
    pending = false
    noctalia.notifyError(noctalia.tr("error.title"), noctalia.tr("error.spawn"))
  end
end

local function startWatch()
  if watching then
    return
  end
  watching = true

  local command = cfg.watchCommand
  if command == "" then
    command = "umbriel-workspace-watch"
  end

  noctalia.runStream("while :; do " .. command .. "; sleep 5; done", function(line)
    local output, workspace = trim(line):match("^(%S+)%s+(.+)$")
    if output == nil then
      return
    end
    activeByOutput[output] = trim(workspace)
    render()
  end)
end

function onClick()
  refreshOutputs()
  apply(otherMode(targetMode()))
end

function onIpc(event, payload)
  refreshOutputs()
  local value = trim(payload)
  if event == "toggle" then
    apply(otherMode(targetMode()))
  elseif event == "set" then
    apply(value)
  elseif event == "sync" then
    if isMode(value) then
      local output, workspace = targetWorkspace()
      rememberChoice(output, workspace, value)
    end
  end
end

function onConfigChanged()
  refreshOutputs()
  readConfig()
  loadUmbrielConfig()
  render()
end

refreshOutputs()
readConfig()
loadUmbrielConfig()

local shared = noctalia.state.get(STATE_KEY)
if type(shared) == "table" then
  overrides = shared
end

noctalia.state.watch(STATE_KEY, function(value)
  if type(value) == "table" then
    overrides = value
    render()
  end
end)

startWatch()
render()
