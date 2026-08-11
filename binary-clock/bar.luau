--!nonstrict
-- boatette/binary-clock - bar widget: LEDs only, full time goes in the tooltip.
--
-- Side bars transpose the grid instead of rotating it, so bit weights stay in
-- a fixed reading order regardless of dock edge.
--
-- No onClick: left click is bound in plugin.toml instead, so it stays visible
-- and rebindable in the settings editor.

local ROW_WEIGHTS = { 8, 4, 2, 1 } -- top (or leftmost) cell is the 8s bit

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

-- One digit: `bits` lit-capable cells at the end of a four-cell run, so every
-- digit occupies the same extent and rows stay aligned.
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

-- os.date raises on an unknown specifier instead of passing it through, which
-- would kill render() every tick over a typo. Drop the tooltip once instead.
local warnedFormat = nil

-- Uses os.date directly rather than the `now` the LEDs were built from, since
-- os.time() round-trips a table as UTC and would shift the tooltip.
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

-- Re-arm against the wall clock each tick instead of a free-running interval,
-- so the seconds LEDs never visibly drift from other clocks.
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
