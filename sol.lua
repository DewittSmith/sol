local REGISTRIES_PATH = "registries"
local CONFIG_FILE = "sol.config"

local function filename_without_extension(path)
    return path:match("([^/]+)%.%w+$") or path
end

if not http.checkURL("https://www.google.com/") then
    error("HTTP client not available. Please enable it in the ComputerCraft settings.")
end

local config = {
    registries = {}
}

local function add_registry(url)
    if url == nil or url == "" then
        error("No registry URL specified.")
    end

    local content = http.get(url)

    if not content then 
        error("Failed to download registry from " .. url) 
    end

    if content.getResponseCode() ~= 200 then
        error("Failed to download registry from " .. url .. " (response code " .. content.getResponseCode() .. ")")
    end
    
    local registryCode = content.readAll()
    content.close()

    local registry = assert(loadstring(registryCode))()
    if not registry.name then registry.name = filename_without_extension(url) end

    config.registries[registry.name] = registry
    print("Registry added: " .. registry.name)
end

if fs.exists(REGISTRIES_PATH) then
    for _, file in ipairs(fs.list(REGISTRIES_PATH)) do
        local path = fs.combine(REGISTRIES_PATH, file)
        add_registry("file://" .. path)
    end
end

if fs.exists(CONFIG_FILE) then
    local file = fs.open(CONFIG_FILE, "r")
    local localConfig = file.readAll()
    file.close()

    localConfig = textutils.unserialise(localConfig)
    error("Local config loading not yet implemented.")
end

for name, registry in pairs(config.registries) do
    registry.name = name
end

-- Convert a format pattern into a Lua pattern and capture variable names
local function parse_format(format)
    local vars = {}
    local pattern = format
    pattern = pattern:gsub("[%.%-%+%[%]%(%)%^%$%%]", "%%%1")
    pattern = pattern:gsub("{([^}]+)}", function(varname)
        table.insert(vars, varname)
        return "([^/]+)"
    end)

    return pattern, vars
end

-- Try to match a target string against a format pattern
local function match_format(target, format)
    local pattern, vars = parse_format(format)
    local captures = { target:match(pattern) }
    if #captures == 0 then return nil end

    local result = {}
    for i, varname in ipairs(vars) do
        result[varname] = captures[i]
    end

    return result
end

-- Try to extract arguments from target string against multiple format patterns
local function extract_args(target, formats)
    for _, format in ipairs(formats) do
        local args = match_format(target, format)
        if args then return args end
    end
    return nil
end

local function install_url(registry, inputs)
    local package = registry.load_package(inputs)
    if #package.include == 0 then table.insert(package.include, "%.lua$") end
    if package.main then table.insert(package.include, "^" .. package.main .. "$") end
    package.is_included = function(path)
        if path == nil or path == "" then return false end

        for _, pattern in ipairs(package.include or {}) do
            if not path:match(pattern) then return false end
        end

        for _, pattern in ipairs(package.exclude or {}) do
            if path:match(pattern) then return false end
        end

        return true
    end

    local pathPrefix = fs.combine("packages", package.package .. "+" .. package.author ..  "@" .. registry.name , package.version)
    print("Installing to " .. pathPrefix .. "...")
    for path, url in registry.list_files(package, inputs) do
        print("Downloading " .. path .. "...")

        local request = http.get(url)
        if not request then 
            error("Failed to download file from " .. url) 
        end

        if request.getResponseCode() ~= 200 then
            error("Failed to download file from " .. url .. " (response code " .. request.getResponseCode() .. ")")
        end

        local content = request.readAll()
        request.close()        

        local fullPath = fs.combine(pathPrefix, path)
        local file = fs.open(fullPath, "w")
        file.write(content)
        file.close()
    end
end

local function install(package, registry)
    if package == nil or package == "" then
        error("No package specified.")
    end

    if registry then
        if type(registry) == "string" then
            registry = config.registries[registry]
            if not registry then
                error("Registry not found: " .. tostring(registry))
            end
        elseif type(registry) ~= "table" then
            error("Invalid registry specified.")
        end

        local inputs = extract_args(package, registry.inputs)
        if inputs then
            install_url(registry, inputs)
        else
            error("No matching format found in registry: " .. registry.name)
        end
    else
        for _, registry in pairs(config.registries) do
            local inputs = extract_args(package, registry.inputs)
            if inputs then
                install_url(registry, inputs)
                break
            end
        end
    end
end

local function parseCommand(cmd)
    if cmd[1] == "install" then
        install(cmd[2])
    elseif cmd[1] == "add-registry" then
        add_registry(cmd[2])
    elseif #cmd == 0 or cmd[1] == "sol" then
        return {
            install = install,
            add_registry = add_registry
        }
    else
        error("Unknown command: " .. tostring(cmd[1]))
    end
end

return parseCommand({ ... })