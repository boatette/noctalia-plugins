local input, output = ...

local recorded = { colors_name = nil, highlights = 0, setups = {}, colorscheme = nil, loaded = nil }

local ESCAPES =
	{ ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESCAPES[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function is_array(t)
	local n = 0
	for key in pairs(t) do
		if type(key) ~= "number" then
			return false
		end
		n = n + 1
	end
	return n == #t
end

local function encode(value, seen)
	local kind = type(value)

	if kind == "string" then
		return quote(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		return tostring(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind ~= "table" or seen[value] then
		return "null"
	end

	seen[value] = true
	local parts = {}

	if is_array(value) then
		for _, item in ipairs(value) do
			parts[#parts + 1] = encode(item, seen)
		end
		seen[value] = nil
		return "[" .. table.concat(parts, ",") .. "]"
	end

	local keys = {}
	for key in pairs(value) do
		if type(key) == "string" then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)

	for _, key in ipairs(keys) do
		local encoded = encode(value[key], seen)
		if encoded ~= "null" then
			parts[#parts + 1] = quote(key) .. ":" .. encoded
		end
	end

	seen[value] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

local function permissive()
	local t = {}
	return setmetatable(t, {
		__index = function(_, key)
			local child = permissive()
			rawset(t, key, child)
			return child
		end,
		__call = function()
			return permissive()
		end,
	})
end

local function deep_extend(_, ...)
	local out = {}
	for i = 1, select("#", ...) do
		local source = select(i, ...)
		if type(source) == "table" then
			for key, value in pairs(source) do
				if type(value) == "table" and type(out[key]) == "table" then
					out[key] = deep_extend("force", out[key], value)
				else
					out[key] = value
				end
			end
		end
	end
	return out
end

local function build_vim()
	local stub = permissive()

	stub.g = setmetatable({}, {
		__newindex = function(t, key, value)
			if key == "colors_name" then
				recorded.colors_name = value
			end
			rawset(t, key, value)
		end,
	})

	stub.api = permissive()
	stub.api.nvim_set_hl = function()
		recorded.highlights = recorded.highlights + 1
	end

	stub.cmd = setmetatable({}, {
		__call = function(_, text)
			local name = type(text) == "string" and text:match("^%s*colorscheme%s+(%S+)")
			if name then
				recorded.colorscheme = name
			end
		end,
		__index = function(_, key)
			return function(argument)
				if key == "colorscheme" and type(argument) == "string" then
					recorded.colorscheme = argument
				end
			end
		end,
	})

	stub.tbl_deep_extend = deep_extend
	stub.tbl_extend = deep_extend
	stub.inspect = tostring

	return stub
end

local REPO = "^[%w%-%._]+/[%w%-%._]+$"

local function walk(node, visit, seen)
	if type(node) ~= "table" or seen[node] then
		return
	end
	seen[node] = true
	visit(node)
	for _, child in pairs(node) do
		walk(child, visit, seen)
	end
end

local function report(payload)
	local file = io.open(output, "w")
	if file then
		file:write(encode(payload, {}))
		file:close()
	end
end

local SANDBOX = {
	assert = assert,
	error = error,
	getmetatable = getmetatable,
	ipairs = ipairs,
	math = math,
	next = next,
	pairs = pairs,
	pcall = pcall,
	print = function() end,
	rawequal = rawequal,
	rawget = rawget,
	rawlen = rawlen,
	rawset = rawset,
	select = select,
	setmetatable = setmetatable,
	string = string,
	table = table,
	tonumber = tonumber,
	tostring = tostring,
	type = type,
	unpack = table.unpack,
}

SANDBOX.vim = build_vim()

SANDBOX.require = function(name)
	local module = {}
	return setmetatable(module, {
		__index = function(_, key)
			if key == "setup" then
				return function(options)
					recorded.setups[#recorded.setups + 1] = {
						module = name,
						options = type(options) == "table" and options or nil,
					}
				end
			end
			if key == "load" then
				return function()
					recorded.loaded = name
				end
			end
			local child = permissive()
			rawset(module, key, child)
			return child
		end,
		__call = function()
			return permissive()
		end,
	})
end
SANDBOX._G = SANDBOX

local chunk, load_error = loadfile(input, "t", SANDBOX)

if not chunk then
	report({ shape = "unknown", error = tostring(load_error) })
	return
end

local ok, result = pcall(chunk)

if not ok then
	if recorded.colors_name or recorded.highlights > 0 then
		report({ shape = "colorscheme_file", colors_name = recorded.colors_name, error = tostring(result) })
	else
		report({ shape = "unknown", error = tostring(result) })
	end
	return
end

if recorded.colors_name or recorded.highlights > 0 then
	report({ shape = "colorscheme_file", colors_name = recorded.colors_name })
	return
end

local plugins, colorscheme, inline = {}, nil, false
local configs = {}

walk(result, function(node)
	if type(node.config) == "function" then
		configs[#configs + 1] = node.config
	end

	if type(node[1]) == "string" and node[1]:match(REPO) then
		plugins[#plugins + 1] = {
			repo = node[1],
			name = type(node.name) == "string" and node.name or nil,
			opts = type(node.opts) == "table" and node.opts or nil,
		}
	end

	if type(node.opts) == "table" then
		local choice = node.opts.colorscheme
		if type(choice) == "string" then
			colorscheme = choice
		elseif type(choice) == "function" then
			inline = true
		end
	end
end, {})

for _, config in ipairs(configs) do
	pcall(config)
end

report({
	shape = inline and "inline_function" or (#plugins > 0 and "plugin" or "none"),
	plugins = plugins,
	colorscheme = colorscheme or recorded.colorscheme or recorded.loaded,
	setups = recorded.setups,
})
