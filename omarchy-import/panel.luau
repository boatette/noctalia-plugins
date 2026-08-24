--!nonstrict

local HELPER_DEFAULT = "omarchy-import"
local SWATCH_W = 16
local SWATCH_H = 22
local THUMB_W = 420
local THUMB_H = 236
local LIST_W = 320

local themes = {}
local byId = {}
local previews = {}
local filter = ""
local selected = nil
local inflight = nil
local catalogState = "cold" -- cold | ready | refreshing
local mode = "list" -- list | install | confirmRemove | busy
local form = { palette = 1, nvim = 1, wallpapers = true }
local plan = nil -- the remove --dry-run answer, while confirming
local busy = nil
local notice = nil

local NVIM_MODES = { "auto", "palette", "plugin" }

local render

local function tr(key, args)
  return noctalia.tr(key, args)
end


local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function helper()
  local configured = noctalia.getConfig("helper_command")
  if type(configured) == "string" and configured ~= "" then
    return configured
  end
  return HELPER_DEFAULT
end

local function environment()
  local parts = {}
  local repo = noctalia.getConfig("nix_repo")
  if type(repo) == "string" and repo ~= "" then
    table.insert(parts, "OMARCHY_IMPORT_REPO=" .. quote(noctalia.expandPath(repo)))
  end
  local walls = noctalia.getConfig("wallpaper_root")
  if type(walls) == "string" and walls ~= "" then
    table.insert(parts, "WALLPAPER_DIR=" .. quote(noctalia.expandPath(walls)))
  end
  return parts
end

local function command(args)
  local parts = environment()
  table.insert(parts, helper())
  for _, arg in ipairs(args) do
    table.insert(parts, arg)
  end
  return table.concat(parts, " ")
end

local function consume(text, onProgress)
  local terminal = nil
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local ok, record = pcall(noctalia.json.decode, line)
    if ok and type(record) == "table" then
      if record.event == "progress" then
        if onProgress then
          onProgress(record)
        end
      elseif record.event == "done" or record.event == "error" then
        terminal = record
      end
    else
      noctalia.log("omarchy-import: unparsed line: " .. tostring(line))
    end
  end
  return terminal
end

local function finish(record, onDone)
  inflight = nil
  if record == nil then
    record = {
      event = "error",
      kind = "crash",
      message = tr("error.no_result"),
    }
  end
  onDone(record)
end

local function callOnce(args, onDone)
  local cmd = command(args)
  local started = noctalia.runAsync(cmd, function(result)
    finish(consume(result and result.stdout, nil), onDone)
  end)
  if not started then
    finish(nil, onDone)
  end
end

local function callStreaming(args, onProgress, onDone)
  local settled = false
  local started = noctalia.runStream(command(args), function(line)
    local record = consume(line, onProgress)
    if record ~= nil and not settled then
      settled = true
      finish(record, onDone)
    end
  end)
  if not started then
    finish(nil, onDone)
  end
end

local function matchesFilter(theme)
  if filter == "" then
    return true
  end
  local needle = filter:lower()
  return theme.name:lower():find(needle, 1, true) ~= nil
    or theme.source:lower():find(needle, 1, true) ~= nil
end

local function rows()
  local out = {}
  for _, theme in ipairs(themes) do
    if matchesFilter(theme) then
      table.insert(out, theme)
    end
  end
  return out
end

local function current()
  return selected ~= nil and byId[selected] or nil
end

local function currentPreview()
  return selected ~= nil and previews[selected] or nil
end

local function fetchPreview(source, force)
  if source == nil or inflight ~= nil then
    return
  end
  if previews[source] ~= nil and not force then
    return
  end
  previews[source] = { loading = true }
  inflight = source
  local args = { "preview", quote(source) }
  if force then
    table.insert(args, "--refresh")
  end
  callOnce(args, function(record)
    if record.event == "done" then
      previews[source] = record.data
    else
      previews[source] = { error = record.message }
    end
    render()
  end)
end

local function loadCatalog(refresh)
  catalogState = refresh and "refreshing" or catalogState
  local args = { "catalog" }
  if refresh then
    table.insert(args, "--refresh")
  end

  local function absorb(record)
    if record.event ~= "done" then
      catalogState = "ready"
      notice = record.message
      render()
      return
    end
    themes = record.data.themes or {}
    byId = {}
    for _, theme in ipairs(themes) do
      byId[theme.source] = theme
    end
    if selected == nil and themes[1] ~= nil then
      selected = themes[1].source
    end
    catalogState = "ready"
    render()
    fetchPreview(selected, false)
  end

  if refresh then
    callStreaming(args, function(progress)
      busy = progress
      render()
    end, function(record)
      busy = nil
      absorb(record)
    end)
  else
    callOnce(args, absorb)
  end
end

local function loadWarmPreviews()
  callOnce({ "previews" }, function(record)
    if record.event == "done" then
      for source, blob in pairs(record.data.previews or {}) do
        previews[source] = blob
      end
      render()
    end
  end)
end

local function paletteOptions(blob)
  local options = { { value = "new", label = tr("install.register", { name = blob.name or "" }) } }
  for _, match in ipairs(blob.matches or {}) do
    table.insert(options, {
      value = match[3],
      label = tr("install.join", { name = match[3], source = match[2], score = tostring(match[1]) }),
    })
  end
  return options
end

local function themeRow(theme)
  local isSelected = theme.source == selected
  return ui.row({
    key = theme.source,
    gap = 6,
    align = "center",
    paddingH = 8,
    paddingV = 5,
    radius = 6,
    fill = isSelected and "surface_variant" or nil,
    onClick = function()
      selected = theme.source
      render()
      fetchPreview(theme.source, false)
    end,
  }, {
    ui.glyph({
      name = theme.imported and "check" or (theme.kind == "official" and "star" or "point"),
      size = 12,
      color = theme.imported and "primary" or "outline",
    }),
    ui.label({
      text = theme.name,
      color = isSelected and "on_surface" or "on_surface_variant",
      maxLines = 1,
      flexGrow = 1,
    }),
  })
end

local function themeList()
  local visible = rows()
  if catalogState == "cold" then
    return { ui.label({ text = tr("loading"), color = "on_surface_variant" }) }
  end
  if #visible == 0 then
    return { ui.label({ text = tr("empty"), color = "on_surface_variant" }) }
  end
  local out = {}
  for _, theme in ipairs(visible) do
    table.insert(out, themeRow(theme))
  end
  return out
end

local function swatches(ansi)
  local out = {}
  for index, colour in ipairs(ansi or {}) do
    table.insert(out, ui.box({
      key = "ansi" .. index,
      width = SWATCH_W,
      height = SWATCH_H,
      fill = colour,
      radius = 3,
    }))
  end
  return ui.row({ gap = 2 }, out)
end

local function wouldSentence(blob)
  local would = blob.would
  if would == nil then
    return ""
  end
  if would.action == "join" then
    return tr("would.join", { name = would.palette })
  end
  return tr("would.new", { name = would.palette })
end

local function detail()
  local theme = current()
  if theme == nil then
    return ui.column({ flexGrow = 1 }, { ui.label({ text = tr("pick"), color = "on_surface_variant" }) })
  end

  local head = {
    ui.label({ text = theme.name, fontSize = 16, fontWeight = "bold", color = "on_surface" }),
    ui.label({ text = theme.source, fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
  }
  if theme.info ~= nil and theme.info ~= "" then
    table.insert(head, ui.label({ text = theme.info, fontSize = 11, color = "outline", maxLines = 2 }))
  end

  local blob = currentPreview()
  local body
  if blob == nil or blob.loading then
    body = { ui.label({ text = tr("loading"), color = "on_surface_variant" }) }
  elseif blob.error then
    body = { ui.label({ text = blob.error, color = "error", maxLines = 3 }) }
  else
    local matchRows = {}
    for _, match in ipairs(blob.matches or {}) do
      table.insert(matchRows, ui.row({ key = match[3], gap = 8 }, {
        ui.label({ text = match[2], fontSize = 11, color = "outline", minWidth = 74 }),
        ui.label({ text = match[3], fontSize = 11, color = "on_surface_variant", flexGrow = 1, maxLines = 1 }),
        ui.label({ text = tostring(match[1]), fontSize = 11, color = "outline" }),
      }))
    end

    body = {
      ui.row({ gap = 16, align = "center" }, {
        ui.label({ text = tr("mode." .. (blob.mode or "dark")), fontSize = 11, color = "on_surface_variant" }),
        ui.box({ width = SWATCH_W, height = SWATCH_H, fill = blob.variant.mSurface, radius = 3 }),
        ui.label({ text = blob.variant.mSurface, fontSize = 11, color = "outline" }),
        ui.box({ width = SWATCH_W, height = SWATCH_H, fill = blob.variant.mPrimary, radius = 3 }),
        ui.label({ text = blob.variant.mPrimary, fontSize = 11, color = "outline" }),
      }),
      swatches(blob.ansi),
      ui.separator({ spacing = 4 }),
      ui.label({ text = tr("closest"), fontSize = 11, fontWeight = "bold", color = "on_surface" }),
      ui.column({ gap = 2 }, matchRows),
      ui.label({ text = wouldSentence(blob), fontSize = 11, color = "primary", maxLines = 2 }),
    }

    local image = blob.image
    if image ~= nil and image.thumb ~= nil and noctalia.fileExists(image.thumb) then
      table.insert(body, ui.image({
        path = image.thumb,
        width = THUMB_W,
        height = THUMB_H,
        fit = "cover",
        radius = 8,
      }))
    end
  end

  local actions = {}
  local ready = blob ~= nil and not blob.loading and not blob.error
  table.insert(actions, ui.button({
    text = tr("action.install"),
    variant = "primary",
    enabled = ready and inflight == nil,
    onClick = "onInstallClicked",
  }))
  if theme.imported then
    table.insert(actions, ui.button({
      text = tr("action.remove"),
      variant = "destructive",
      enabled = inflight == nil,
      onClick = "onRemoveClicked",
    }))
    if ready and blob.image ~= nil and blob.image.full ~= nil then
      table.insert(actions, ui.button({
        text = tr("action.wallpaper"),
        variant = "outline",
        onClick = "onWallpaperClicked",
      }))
    end
  end
  table.insert(actions, ui.spacer({ flexGrow = 1 }))
  table.insert(actions, ui.button({
    glyph = "refresh",
    variant = "ghost",
    tooltip = tr("action.refresh_preview"),
    enabled = inflight == nil,
    onClick = "onRefreshPreview",
  }))

  local column = { ui.column({ gap = 2 }, head), ui.separator({ spacing = 4 }) }
  for _, node in ipairs(body) do
    table.insert(column, node)
  end
  table.insert(column, ui.spacer({ flexGrow = 1 }))
  table.insert(column, ui.row({ gap = 8, align = "center" }, actions))

  return ui.scroll({ flexGrow = 1, gap = 8 }, { ui.column({ gap = 8, align = "stretch" }, column) })
end

local function listView()
  return ui.row({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.column({ gap = 8, minWidth = LIST_W, align = "stretch" }, {
      ui.scroll({ flexGrow = 1, gap = 1 }, themeList()),
    }),
    ui.separator({ orientation = "vertical" }),
    detail(),
  })
end

local function installView()
  local blob = currentPreview()
  local options = paletteOptions(blob)
  local labels = {}
  for _, option in ipairs(options) do
    table.insert(labels, option.label)
  end

  local nvimButtons = {}
  for index, name in ipairs(NVIM_MODES) do
    table.insert(nvimButtons, ui.button({
      key = name,
      text = tr("nvim." .. name),
      controlSize = "sm",
      variant = form.nvim == index and "primary" or "outline",
      onClick = function()
        form.nvim = index
        render()
      end,
    }))
  end

  return ui.column({ flexGrow = 1, gap = 14, align = "stretch" }, {
    ui.label({ text = tr("install.title", { name = current().name }), fontSize = 15, fontWeight = "bold" }),
    ui.column({ gap = 4 }, {
      ui.label({ text = tr("install.palette"), fontSize = 11, color = "on_surface_variant" }),
      ui.select({
        options = labels,
        selectedIndex = form.palette - 1,
        onChange = function(index)
          form.palette = tonumber(index) + 1
          render()
        end,
      }),
    }),
    ui.column({ gap = 4 }, {
      ui.label({ text = tr("install.nvim"), fontSize = 11, color = "on_surface_variant" }),
      ui.row({ gap = 6 }, nvimButtons),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.toggle({
        checked = form.wallpapers,
        onChange = function(value)
          form.wallpapers = value == "true"
          render()
        end,
      }),
      ui.label({ text = tr("install.wallpapers"), fontSize = 12 }),
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.row({ gap = 8, justify = "end" }, {
      ui.button({ text = tr("action.cancel"), variant = "ghost", onClick = "onCancel" }),
      ui.button({ text = tr("action.install"), variant = "primary", onClick = "onInstallConfirmed" }),
    }),
  })
end

local function confirmRemoveView()
  local lines = {}
  for _, path in ipairs(plan.files or {}) do
    table.insert(lines, ui.label({ key = path, text = path, fontSize = 11, color = "on_surface_variant", maxLines = 1 }))
  end
  for _, folder in ipairs(plan.wallpaperFolders or {}) do
    table.insert(lines, ui.label({
      key = folder.path,
      text = tr("remove.folder", { path = folder.path, count = tostring(folder.count) }),
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 1,
    }))
  end
  if plan.registryEntry then
    table.insert(lines, ui.label({ text = tr("remove.registry"), fontSize = 11, color = "on_surface_variant" }))
  end
  for _, orphan in ipairs(plan.orphanPlugins or {}) do
    table.insert(lines, ui.label({
      key = "orphan-" .. orphan,
      text = tr("remove.plugin", { name = orphan }),
      fontSize = 11,
      color = "on_surface_variant",
    }))
  end
  if plan.live then
    table.insert(lines, ui.label({ text = tr("remove.live"), fontSize = 11, color = "error", maxLines = 2 }))
  end

  return ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.label({ text = tr("remove.title", { name = plan.name }), fontSize = 15, fontWeight = "bold" }),
    ui.scroll({ flexGrow = 1, gap = 3 }, lines),
    ui.row({ gap = 8, justify = "end" }, {
      ui.button({ text = tr("action.cancel"), variant = "ghost", onClick = "onCancel" }),
      ui.button({ text = tr("action.remove"), variant = "destructive", onClick = "onRemoveConfirmed" }),
    }),
  })
end

local function busyView()
  local step = busy ~= nil and busy.step or ""
  local message = busy ~= nil and busy.message or ""
  local progress = 0
  if busy ~= nil and busy.total and busy.total > 0 then
    progress = (busy.index or 0) / busy.total
  end
  return ui.column({ flexGrow = 1, gap = 10, align = "center", justify = "center" }, {
    ui.label({ text = step ~= "" and tr("step." .. step) or tr("working"), fontSize = 14, fontWeight = "bold" }),
    ui.label({ text = message, fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
    ui.progress({ progress = progress, width = 320, height = 6, radius = 3 }),
  })
end

render = function()
  local header = {
    ui.input({
      key = "filter",
      placeholder = tr("filter"),
      value = filter,
      flexGrow = 1,
      onChange = "onFilterChange",
    }),
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      tooltip = tr("action.refresh_catalog"),
      enabled = catalogState ~= "refreshing" and inflight == nil,
      onClick = "onRefreshCatalog",
    }),
    ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
  }

  local content
  if mode == "install" then
    content = installView()
  elseif mode == "confirmRemove" then
    content = confirmRemoveView()
  elseif mode == "busy" then
    content = busyView()
  else
    content = listView()
  end

  local tree = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = tr("title"), fontSize = 15, fontWeight = "bold", color = "on_surface" }),
      ui.spacer({ flexGrow = 1 }),
    }),
    ui.row({ gap = 8, align = "center" }, header),
  }
  if notice ~= nil then
    table.insert(tree, ui.label({ text = notice, fontSize = 11, color = "error", maxLines = 3 }))
  end
  table.insert(tree, content)

  panel.render(ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, tree))
end


function onOpen(_context)
  notice = nil
  mode = "list"
  render()
  loadCatalog(false)
  loadWarmPreviews()
end

function onFilterChange(value)
  filter = tostring(value or "")
  local visible = rows()
  if selected ~= nil and byId[selected] ~= nil and not matchesFilter(byId[selected]) then
    selected = visible[1] ~= nil and visible[1].source or nil
  end
  render()
end

function onRefreshCatalog()
  mode = "busy"
  render()
  loadCatalog(true)
  mode = "list"
end

function onRefreshPreview()
  fetchPreview(selected, true)
  render()
end

function onCloseClicked()
  panel.close()
end

function onCancel()
  mode = "list"
  plan = nil
  render()
end

function onInstallClicked()
  local blob = currentPreview()
  if blob == nil or blob.error then
    return
  end
  form.palette = 1
  if blob.would ~= nil and blob.would.action == "join" then
    for index, option in ipairs(paletteOptions(blob)) do
      if option.value == blob.would.palette then
        form.palette = index
        break
      end
    end
  end
  form.nvim = 1
  form.wallpapers = true
  mode = "install"
  render()
end

function onInstallConfirmed()
  local theme = current()
  local blob = currentPreview()
  local option = paletteOptions(blob)[form.palette]

  local args = { "import", quote(theme.source) }
  if option.value == "new" then
    table.insert(args, "--new")
  else
    table.insert(args, "--reuse")
    table.insert(args, quote(option.value))
  end
  table.insert(args, "--nvim")
  table.insert(args, NVIM_MODES[form.nvim])
  if not form.wallpapers then
    table.insert(args, "--no-wallpapers")
  end
  table.insert(args, "--apply")

  mode = "busy"
  busy = nil
  notice = nil
  render()

  callStreaming(args, function(progress)
    busy = progress
    render()
  end, function(record)
    busy = nil
    mode = "list"
    if record.event ~= "done" then
      notice = record.message
      noctalia.notifyError(tr("title"), record.message)
      render()
      return
    end

    local data = record.data
    theme.imported = true
    previews[theme.source] = nil

    local body = tr("notify.imported", { name = data.name, palette = data.palette.name })
    if data.rebuild ~= nil and data.rebuild.needed then
      body = body .. "\n" .. tr("notify.rebuild", { command = data.rebuild.command })
      notice = tr("notify.rebuild", { command = data.rebuild.command })
    end
    noctalia.notify(tr("title"), body)
    render()
    fetchPreview(theme.source, false)
  end)
end

function onRemoveClicked()
  local theme = current()
  callOnce({ "remove", quote(theme.name), "--dry-run" }, function(record)
    if record.event ~= "done" then
      notice = record.message
      render()
      return
    end
    plan = record.data
    mode = "confirmRemove"
    render()
  end)
end

function onRemoveConfirmed()
  local theme = current()
  local name = plan.name
  mode = "busy"
  busy = nil
  plan = nil
  render()

  callStreaming({ "remove", quote(name), "--yes" }, function(progress)
    busy = progress
    render()
  end, function(record)
    busy = nil
    mode = "list"
    if record.event ~= "done" then
      notice = record.message
      noctalia.notifyError(tr("title"), record.message)
      render()
      return
    end
    if theme ~= nil then
      theme.imported = false
      previews[theme.source] = nil
    end
    local data = record.data
    local body = tr("notify.removed", { name = name })
    if data.rebuild ~= nil and data.rebuild.needed then
      body = body .. "\n" .. tr("notify.rebuild", { command = data.rebuild.command })
      notice = tr("notify.rebuild", { command = data.rebuild.command })
    end
    noctalia.notify(tr("title"), body)
    render()
    if theme ~= nil then
      fetchPreview(theme.source, false)
    end
  end)
end

function onWallpaperClicked()
  local blob = currentPreview()
  if blob ~= nil and blob.image ~= nil and blob.image.full ~= nil then
    noctalia.setWallpaper(blob.image.full)
  end
end
