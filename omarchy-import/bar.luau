--!nonstrict

local PANEL = "boatette/omarchy-import:browser"

local function render()
  local glyph = noctalia.getConfig("glyph")
  barWidget.setGlyph(glyph ~= nil and glyph ~= "" and glyph or "palette")
  if noctalia.getConfig("show_tooltip") then
    barWidget.setTooltip(noctalia.tr("title"))
  else
    barWidget.clearTooltip()
  end
end

function update()
  render()
end

function onConfigChanged()
  render()
end

function onClick()
  noctalia.togglePanel(PANEL)
end

render()
