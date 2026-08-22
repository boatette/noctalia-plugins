--!nonstrict

local ROW_WEIGHTS = { 8, 4, 2, 1 }

local cfg = {}

local function readConfig()
  cfg = {
    showSeconds = noctalia.getConfig("show_seconds"),
    hourFormat = noctalia.getConfig("hour_format"),
    ledSize = noctalia.getConfig("led_size"),
    ledGap = noctalia.getConfig("led_gap"),
    groupGap = noctalia.getConfig("group_gap"),
    onColor = noctalia.getConfig("on_color"),
    offColor = noctalia.getConfig("off_color"),
    glow = noctalia.getConfig("glow"),
    tooltipFormat = noctalia.getConfig("tooltip_format"),
  }
end

local function digit(key, value, bits, vertical)
  local cells = {}
  for i = 1, 4 do
    local props = {
      key = key .. "-" .. i,
      width = cfg.ledSize,
      height = cfg.ledSize,
      radius = cfg.ledSize / 2,
    }
    if i > 4 - bits then
      local lit = math.floor(value / ROW_WEIGHTS[i]) % 2 == 1
      props.fill = lit and cfg.onColor or cfg.offColor
      if lit and cfg.glow > 0 then
        props.softness = cfg.glow
      end
    end
    cells[i] = ui.box(props)
  end

  local container = vertical and ui.row or ui.column
  return container({ key = key, gap = cfg.ledGap, align = "center" }, cells)
end

local function group(key, tens, tensBits, units, vertical)
  local container = vertical and ui.column or ui.row
  return container({ key = key, gap = cfg.ledGap, align = "center" }, {
    digit(key .. "-tens", tens, tensBits, vertical),
    digit(key .. "-units", units, 4, vertical),
  })
end

local function displayHour(hour24)
  if cfg.hourFormat ~= "12" then
    return hour24
  end
  local hour = hour24 % 12
  return hour == 0 and 12 or hour
end

local warnedFormat = nil

local function setTooltip()
  if cfg.tooltipFormat == "" then
    barWidget.clearTooltip()
    return
  end

  local ok, text = pcall(os.date, cfg.tooltipFormat)
  if ok then
    barWidget.setTooltip(text)
    return
  end

  barWidget.clearTooltip()
  if warnedFormat ~= cfg.tooltipFormat then
    warnedFormat = cfg.tooltipFormat
    noctalia.log(("binary-clock: tooltip format %q is not a valid strftime pattern: %s")
      :format(cfg.tooltipFormat, tostring(text)))
  end
end

local function render(now)
  local vertical = barWidget.isVertical()
  local hour = displayHour(now.hour)

  local groups = {
    group("hours", math.floor(hour / 10), 2, hour % 10, vertical),
    group("minutes", math.floor(now.min / 10), 3, now.min % 10, vertical),
  }

  if cfg.showSeconds then
    groups[#groups + 1] = group("seconds", math.floor(now.sec / 10), 3, now.sec % 10, vertical)
  end

  local container = vertical and ui.column or ui.row
  barWidget.render(container({ gap = cfg.groupGap, align = "center" }, groups))

  setTooltip()
end

local function scheduleNextTick()
  local period = cfg.showSeconds and 1000 or 60000
  noctalia.setUpdateInterval(math.max(16, period - (noctalia.nowMs() % period)))
end

local lastDrawn = nil

function update()
  scheduleNextTick()

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
update()
