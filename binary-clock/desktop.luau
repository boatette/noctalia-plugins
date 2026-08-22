--!nonstrict

local ROW_WEIGHTS = { 8, 4, 2, 1 }

local cfg = {}

local function readConfig()
  cfg = {
    showSeconds = noctalia.getConfig("show_seconds"),
    hourFormat = noctalia.getConfig("hour_format"),
    showHeaders = noctalia.getConfig("show_headers"),
    showLabels = noctalia.getConfig("show_labels"),
    showDigits = noctalia.getConfig("show_digits"),
    showSeparators = noctalia.getConfig("show_separators"),
    ledSize = noctalia.getConfig("led_size"),
    ledGap = noctalia.getConfig("led_gap"),
    groupGap = noctalia.getConfig("group_gap"),
    fontSize = noctalia.getConfig("font_size"),
    onColor = noctalia.getConfig("on_color"),
    offColor = noctalia.getConfig("off_color"),
    textColor = noctalia.getConfig("text_color"),
    glow = noctalia.getConfig("glow"),
  }
end

local function gridHeight()
  return 4 * cfg.ledSize + 3 * cfg.ledGap
end

local function stackGap()
  return math.max(2, math.floor(cfg.ledGap / 2))
end

local function ledColumn(key, value, bits)
  local cells = {}
  for row = 1, 4 do
    local props = {
      key = key .. "-" .. row,
      width = cfg.ledSize,
      height = cfg.ledSize,
      radius = cfg.ledSize / 2,
    }
    if row > 4 - bits then
      local lit = math.floor(value / ROW_WEIGHTS[row]) % 2 == 1
      props.fill = lit and cfg.onColor or cfg.offColor
      if lit and cfg.glow > 0 then
        props.softness = cfg.glow
      end
    end
    cells[row] = ui.box(props)
  end
  return ui.column({ key = key, gap = cfg.ledGap, align = "center" }, cells)
end

local function digitLabel(key, value)
  return ui.label({
    key = key,
    text = string.format("%d", value),
    width = cfg.ledSize,
    textAlign = "center",
    fontSize = cfg.fontSize,
    color = cfg.textColor,
  })
end

local function group(key, headerKey, tens, tensBits, units)
  local parts = {}

  if cfg.showHeaders then
    parts[#parts + 1] = ui.label({
      key = key .. "-header",
      text = noctalia.tr(headerKey),
      fontSize = cfg.fontSize,
      color = cfg.textColor,
    })
  end

  parts[#parts + 1] = ui.row({ key = key .. "-grid", gap = cfg.ledGap, align = "center" }, {
    ledColumn(key .. "-tens", tens, tensBits),
    ledColumn(key .. "-units", units, 4),
  })

  if cfg.showDigits then
    parts[#parts + 1] = ui.row({ key = key .. "-readout", gap = cfg.ledGap, align = "center" }, {
      digitLabel(key .. "-d0", tens),
      digitLabel(key .. "-d1", units),
    })
  end

  return ui.column({ key = key, gap = stackGap(), align = "center" }, parts)
end

local function divider(key)
  local parts = {}

  if cfg.showHeaders then
    parts[#parts + 1] = ui.label({ key = key .. "-header", text = " ", fontSize = cfg.fontSize })
  end

  if cfg.showSeparators then
    parts[#parts + 1] = ui.separator({
      key = key .. "-rule",
      orientation = "vertical",
      thickness = 1,
      spacing = 0,
      color = cfg.offColor,
      height = gridHeight(),
    })
  else
    parts[#parts + 1] = ui.box({ key = key .. "-rule", width = 1, height = gridHeight() })
  end

  if cfg.showDigits then
    parts[#parts + 1] = ui.label({
      key = key .. "-colon",
      text = ":",
      fontSize = cfg.fontSize,
      color = cfg.textColor,
    })
  end

  return ui.column({ key = key, gap = stackGap(), align = "center" }, parts)
end

local function legend()
  local rows = {}
  for row = 1, 4 do
    rows[row] = ui.row({ key = "legend-" .. row, height = cfg.ledSize, align = "center" }, {
      ui.label({
        text = string.format("%d", ROW_WEIGHTS[row]),
        fontSize = cfg.fontSize,
        color = cfg.textColor,
      }),
    })
  end

  local parts = {}
  if cfg.showHeaders then
    parts[#parts + 1] = ui.label({ key = "legend-header", text = " ", fontSize = cfg.fontSize })
  end
  parts[#parts + 1] = ui.column({ key = "legend-grid", gap = cfg.ledGap, align = "center" }, rows)
  if cfg.showDigits then
    parts[#parts + 1] = ui.label({ key = "legend-readout", text = " ", fontSize = cfg.fontSize })
  end

  return ui.column({ key = "legend", gap = stackGap(), align = "center" }, parts)
end

local function displayHour(hour24)
  if cfg.hourFormat ~= "12" then
    return hour24
  end
  local hour = hour24 % 12
  return hour == 0 and 12 or hour
end

local function render(now)
  local hour = displayHour(now.hour)

  local children = {
    group("hours", "label.hours", math.floor(hour / 10), 2, hour % 10),
    divider("div-1"),
    group("minutes", "label.minutes", math.floor(now.min / 10), 3, now.min % 10),
  }

  if cfg.showSeconds then
    children[#children + 1] = divider("div-2")
    children[#children + 1] = group("seconds", "label.seconds", math.floor(now.sec / 10), 3, now.sec % 10)
  end

  if cfg.showLabels then
    children[#children + 1] = legend()
  end

  desktopWidget.render(ui.row({ gap = cfg.groupGap, align = "center" }, children))
end

local lastDrawn = nil

function update()
  local now = os.date("*t")
  local key = string.format("%d:%d:%d", now.hour, now.min, cfg.showSeconds and now.sec or 0)
  if key == lastDrawn then
    return
  end
  lastDrawn = key
  render(now)
end

function onConfigChanged()
  readConfig()
  lastDrawn = nil
  update()
end

readConfig()
desktopWidget.setWantsSecondTicks(true)
update()
