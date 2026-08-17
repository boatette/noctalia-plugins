--!nonstrict
-- boatette/auto-theme: theme mode + color scheme, derived from the wallpaper path.
--
--   <root>/Dark/Catppuccin/x.png  -> theme-mode-set dark  + color-scheme-set builtin Catppuccin
--   <root>/Light/Nord/x.png       -> theme-mode-set light + color-scheme-set builtin Nord
--   <root>/Dark/Dynamic/x.png     -> theme-mode-set dark  + color-scheme-set wallpaper <scheme>
--   <root>/Dynamic/x.png          -> mode from image luma + color-scheme-set wallpaper <scheme>

local STATE_HOME = noctalia.getenv("NOCTALIA_STATE_HOME")
if not STATE_HOME or STATE_HOME == "" then
  STATE_HOME = noctalia.expandPath("~/.local/state/noctalia")
end
local SETTINGS_PATH = STATE_HOME .. "/settings.toml"
local COMMUNITY_PALETTE_DIR = STATE_HOME .. "/community-palettes"

-- Custom palette dir isn't advertised by the host, so probe both candidates.
local CUSTOM_PALETTE_DIRS = {
  noctalia.expandPath("~/.config/noctalia/palettes"),
  STATE_HOME .. "/palettes",
}

-- Shipped with the binary; not discoverable at runtime.
local BUILTIN_PALETTES = {
  "Ayu", "Catppuccin", "Dracula", "Gruvbox", "Rosé Pine",
  "Tokyo-Night", "Eldritch", "Kanagawa", "Nord", "Noctalia",
}

-- Ignore our own colors/theme-mode events for this long after we write.
local SUPPRESS_MS = 4000

-- wallpaper_changed fires once per output; collapse duplicates within this window.
local DEDUPE_MS = 1500

local cfg = {}
local memory = nil -- { [wallpaperPath] = { scheme = ..., mode = ... } }
local memoryPath = nil
local suppressUntil = 0
local dispatchedPath = nil
local dispatchedAt = 0

-- Latin-1 accented letters seen in palette names, folded before :lower().
local DIACRITICS = {
  ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a",
  ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Ã"] = "a", ["Å"] = "a",
  ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
  ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
  ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
  ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
  ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o",
  ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Ö"] = "o", ["Õ"] = "o",
  ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
  ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
  ["ñ"] = "n", ["Ñ"] = "n", ["ç"] = "c", ["Ç"] = "c",
}

-- Fold a name to a comparable key: "Rose-Pine" and "Rosé Pine" both -> "rosepine".
local function norm(s)
  if not s or s == "" then return "" end
  for from, to in pairs(DIACRITICS) do
    s = s:gsub(from, to)
  end
  return (s:lower():gsub("[^a-z0-9]", ""))
end

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function trim(s)
  return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
end

local function nameSet(csv)
  local out = {}
  for part in tostring(csv or ""):gmatch("[^,]+") do
    local key = norm(trim(part))
    if key ~= "" then out[key] = true end
  end
  return out
end

local function splitPath(p)
  local parts = {}
  for seg in tostring(p):gmatch("[^/]+") do
    parts[#parts + 1] = seg
  end
  return parts
end

local function get(key, fallback)
  local v = noctalia.getConfig(key)
  if v == nil or v == "" then return fallback end
  return v
end

local function loadConfig()
  local root = get("wallpaper_root", nil)
  if not root then
    -- Only a hint: empty whenever [wallpaper].directory is unset.
    local hint = noctalia.wallpaperDirectory()
    root = (hint and hint ~= "" and hint) or "~/Pictures/Wallpapers"
  end

  cfg = {
    enabled = get("enabled", true),
    root = noctalia.expandPath(root):gsub("/+$", ""),
    dark = nameSet(get("dark_dir_names", "Dark")),
    light = nameSet(get("light_dir_names", "Light")),
    dynamic = nameSet(get("dynamic_dir_names", "Dynamic")),
    defaultScheme = get("default_dynamic_scheme", "vibrant"),
    remember = get("remember_dynamic_scheme", true),
    lumaThreshold = tonumber(get("luma_threshold", 45)) or 45,
    aliases = get("aliases", {}) or {},
    notify = get("notify_on_apply", false),
  }
end

-- Read the direct (non-nested) keys of one TOML section.
local function readSection(header)
  local text = noctalia.readFile(SETTINGS_PATH)
  local out = {}
  if not text then return out end
  local inSection = false
  for line in text:gmatch("[^\r\n]+") do
    local t = trim(line)
    if t:sub(1, 1) == "[" then
      inSection = (t == header)
    elseif inSection and t ~= "" and t:sub(1, 1) ~= "#" then
      local k, v = t:match('^([%w_]+)%s*=%s*(.+)$')
      if k then
        out[k] = v:match('^"(.*)"$') or trim(v)
      end
    end
  end
  return out
end

local function readTheme()
  return readSection("[theme]")
end

-- Read fresh from host state; don't cache, or a racing wallpaper switch could
-- misattribute the change.
local function currentWallpaper()
  local last = readSection("[wallpaper.last]")
  return last.path
end

local function selectionOf(theme)
  local source = theme.source
  if source == "builtin" then return theme.builtin end
  if source == "community" then return theme.community_palette end
  if source == "custom" then return theme.custom_palette end
  if source == "wallpaper" then return theme.wallpaper_scheme end
  return nil
end

local function listPalettes(dir)
  local out = {}
  local entries = noctalia.listDir(dir)
  if not entries then return out end
  for _, entry in ipairs(entries) do
    local name = entry:match("[^/]+$") or entry
    local base = name:match("^(.*)%.json$")
    if base then
      -- Community palettes are stored URL-encoded ("Everforest%20Alt.json").
      local decoded = noctalia.string.urlDecode(base)
      out[norm(decoded)] = decoded
    end
  end
  return out
end

-- Resolve a folder name to { source, name }, or nil when nothing matches.
local function resolvePalette(folder)
  local key = norm(folder)
  if key == "" then return nil end

  -- 1. explicit alias: "source:name", or a bare name reusing the normal order
  local alias = cfg.aliases[folder] or cfg.aliases[key]
  if alias and alias ~= "" then
    local source, name = tostring(alias):match("^(%a+):(.*)$")
    if source then
      if source == "skip" then return nil end
      return { source = source, name = trim(name) }
    end
    folder, key = alias, norm(alias)
  end

  -- 2. builtin
  for _, name in ipairs(BUILTIN_PALETTES) do
    if norm(name) == key then
      return { source = "builtin", name = name }
    end
  end

  -- 3. community
  local community = listPalettes(COMMUNITY_PALETTE_DIR)
  if community[key] then
    return { source = "community", name = community[key] }
  end

  -- 4. custom
  for _, dir in ipairs(CUSTOM_PALETTE_DIRS) do
    local entries = noctalia.listDir(dir)
    if entries then
      for _, entry in ipairs(entries) do
        local name = entry:match("[^/]+$") or entry
        if norm(name) == key then
          return { source = "custom", name = name }
        end
      end
    end
  end

  return nil
end

local function loadMemory()
  if memory then return memory end
  memory = {}
  local dir = noctalia.pluginDataDir()
  if not dir then return memory end
  memoryPath = dir .. "/dynamic.json"
  local text = noctalia.readFile(memoryPath)
  if text and text ~= "" then
    local decoded = noctalia.json.decode(text)
    if type(decoded) == "table" then memory = decoded end
  end
  return memory
end

local function saveMemory()
  if not memoryPath then return end
  local encoded = noctalia.json.encode(memory, true)
  if encoded then noctalia.writeFile(memoryPath, encoded) end
end

-- Find the mode segment anywhere in the path, so Dark/Catppuccin/x.png and
-- Catppuccin/Dark/x.png both resolve.
local function mapPath(abs)
  -- Match on a segment boundary, not just a prefix.
  if abs:sub(1, #cfg.root) ~= cfg.root then return nil end
  if abs:sub(#cfg.root + 1, #cfg.root + 1) ~= "/" then return nil end
  local rel = abs:sub(#cfg.root + 1)
  local segs = splitPath(rel)
  table.remove(segs) -- drop the filename
  if #segs == 0 then return { mode = nil, folder = nil } end

  local modeIdx, mode
  for i, seg in ipairs(segs) do
    local key = norm(seg)
    if cfg.dark[key] then
      modeIdx, mode = i, "dark"
      break
    elseif cfg.light[key] then
      modeIdx, mode = i, "light"
      break
    end
  end

  local folder
  if modeIdx then
    -- Prefer the segment below the mode folder, then the one above it.
    folder = segs[modeIdx + 1] or segs[modeIdx - 1]
  else
    folder = segs[#segs]
  end

  return { mode = mode, folder = folder }
end

local function applyResolved(mode, palette, wallpaperPath)
  local theme = readTheme()
  local needMode = mode ~= nil and mode ~= theme.mode
  local needPalette = palette ~= nil
    and (palette.source ~= theme.source or palette.name ~= selectionOf(theme))

  if not needMode and not needPalette then
    noctalia.log("auto-theme: already correct, nothing to do")
    return
  end

  suppressUntil = noctalia.nowMs() + SUPPRESS_MS

  local function setPalette()
    suppressUntil = noctalia.nowMs() + SUPPRESS_MS
    if not needPalette then return end
    noctalia.runAsync(
      "noctalia msg color-scheme-set " .. palette.source .. " " .. shellQuote(palette.name)
    )
  end

  if needMode then
    -- Chained, not parallel: runAsync is unordered, and a wallpaper-generated
    -- palette depends on the mode being set first.
    noctalia.runAsync("noctalia msg theme-mode-set " .. mode, setPalette)
  else
    setPalette()
  end

  if cfg.notify then
    local what = palette and (palette.source .. " " .. palette.name) or "mode only"
    noctalia.notify(noctalia.tr("notify.applied"), (mode or theme.mode) .. " · " .. what)
  end
  noctalia.log(
    ("auto-theme: %s -> mode=%s palette=%s"):format(
      wallpaperPath or "?",
      tostring(mode),
      palette and (palette.source .. " " .. palette.name) or "unchanged"
    )
  )
end

local function applyScheme(mode, scheme, path)
  applyResolved(mode, { source = "wallpaper", name = scheme }, path)
end

local function applyDynamic(mapped, path)
  local remembered = loadMemory()[path]
  local scheme = (remembered and remembered.scheme) or cfg.defaultScheme

  -- mode precedence: path segment > remembered > image luma > leave alone
  local mode = mapped.mode or (remembered and remembered.mode)
  if mode then
    applyScheme(mode, scheme, path)
    return
  end

  if not noctalia.commandExists("magick") then
    noctalia.log("auto-theme: magick not found, leaving theme mode unchanged")
    applyScheme(nil, scheme, path)
    return
  end

  -- CIELAB L*, not -colorspace Gray: IM7's Gray is linear-light and misranks
  -- dark images as lighter than they are.
  noctalia.runAsync(
    "magick " .. shellQuote(path) .. " -colorspace LAB -channel R -separate"
      .. " -resize 1x1! -format '%[fx:mean]' info:",
    function(result)
      local mean = result and tonumber(trim(result.stdout or ""))
      local detected = nil
      if mean then
        detected = (mean * 100 > cfg.lumaThreshold) and "light" or "dark"
        noctalia.log(("auto-theme: luma %.3f -> %s"):format(mean, detected))
      else
        noctalia.log("auto-theme: luma detection failed, leaving theme mode unchanged")
      end
      applyScheme(detected, scheme, path)
    end,
    5000
  )
end

local function applyForPath(path)
  if not cfg.enabled then return end
  if not path or path == "" then return end

  local now = noctalia.nowMs()
  if path == dispatchedPath and now - dispatchedAt < DEDUPE_MS then return end

  local mapped = mapPath(path)
  if not mapped then
    noctalia.log("auto-theme: " .. path .. " is outside the wallpaper root, ignoring")
    return
  end

  dispatchedPath, dispatchedAt = path, now

  local isDynamic = mapped.folder ~= nil and cfg.dynamic[norm(mapped.folder)]
  if isDynamic then
    applyDynamic(mapped, path)
    return
  end

  -- A wallpaper directly in a mode folder names no theme: mode only.
  local namesTheme = mapped.folder ~= nil
    and not cfg.dark[norm(mapped.folder)]
    and not cfg.light[norm(mapped.folder)]

  if not namesTheme then
    applyResolved(mapped.mode, nil, path)
    return
  end

  local palette = resolvePalette(mapped.folder)
  if not palette then
    noctalia.notifyError(
      noctalia.tr("notify.unresolved-title"),
      noctalia.tr("notify.unresolved-body", { name = mapped.folder })
    )
    applyResolved(mapped.mode, nil, path)
    return
  end

  applyResolved(mapped.mode, palette, path)
end

-- Record what the user picked, so returning to this wallpaper restores it.
local function learn()
  if not cfg.enabled or not cfg.remember then return end
  if noctalia.nowMs() < suppressUntil then return end -- our own write

  local theme = readTheme()

  -- Only track host wallpaper schemes; anything else is a deliberate escape
  -- from dynamic theming.
  if theme.source ~= "wallpaper" then return end
  local scheme = theme.wallpaper_scheme

  local path = currentWallpaper()
  if not path or path == "" then return end
  local mapped = mapPath(path)
  if not mapped or not mapped.folder then return end
  if not cfg.dynamic[norm(mapped.folder)] then return end

  local mem = loadMemory()
  local entry = mem[path] or {}
  local mode = theme.mode

  if entry.scheme == scheme and entry.mode == mode then return end
  entry.scheme = scheme
  entry.mode = mode
  mem[path] = entry
  saveMemory()
  noctalia.log(("auto-theme: remembered %s for %s"):format(tostring(scheme), path))
end

loadConfig()

-- No reconcile-on-load: this service restarts on every settings.toml write,
-- and re-applying at startup would revert a palette just picked by hand.

function onIpc(event, payload)
  if event == "wallpaper-changed" then
    -- Prefer the hook's $NOCTALIA_WALLPAPER_PATH; fall back to asking the host.
    if payload and payload ~= "" then
      applyForPath(trim(payload))
    else
      noctalia.runAsync("noctalia msg wallpaper-get", function(result)
        applyForPath(trim((result and result.stdout) or ""))
      end, 5000)
    end
  elseif event == "colors-changed" then
    learn()
  elseif event == "theme-mode-changed" then
    learn()
  end
end

function onConfigChanged()
  loadConfig()
  noctalia.log("auto-theme: settings reloaded")
end
