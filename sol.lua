local shell = shell or require("shell")

local REGISTRIES_PATH = "registries"
local CONFIG_FILE = "sol.config"

local function filename_without_extension(path)
    return path:match("([^/]+)%.%w+$") or path
end

if not http.checkURL("https://www.google.com/") then
    printError("HTTP client not available. Please enable it in the ComputerCraft settings.")
    return
end

local config = {
    registries = {}
}

local function add_registry(url)
    if url == nil or url == "" then
        printError("No registry URL specified.")
        return
    end

    local content = http.get(url)

    if not content then 
        printError("Failed to download registry from " .. url) 
        return
    end

    if content.getResponseCode() ~= 200 then
        printError("Failed to download registry from " .. url .. " (response code " .. content.getResponseCode() .. ")")
        return
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
    printError("Local config loading not yet implemented.")
    return
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

local function install_package(registry, inputs)
    local package = {
        author = inputs.owner,
        package = inputs.name,
        version = "unknown",
        include = { },
        exclude = { },
    }

    local packageData = registry.load_file(inputs, "package.json")
    packageData = packageData and textutils.unserialiseJSON(packageData) or {}

    for k, v in pairs(packageData) do package[k] = v end
    if #package.include == 0 then table.insert(package.include, "%.lua$") end
    if package.main then table.insert(package.include, "^" .. package.main .. "$") end

    package.is_included = function(path)
        if path == nil or path == "" then return false end

        local isIncluded = false
        for _, pattern in ipairs(package.include) do
            if path:match(pattern) then
                isIncluded = true
                break
            end
        end

        for _, pattern in ipairs(package.exclude) do
            if path:match(pattern) then
                isIncluded = false
                break
            end
        end

        return isIncluded
    end

    local pathPrefix = fs.combine("packages", package.package .. "+" .. package.author ..  "@" .. registry.name , package.version)
    print("Installing to " .. pathPrefix .. "...")
    for path, url in registry.list_files(package, inputs) do
        print("Downloading " .. path .. "...")

        local request = http.get(url)
        if not request then 
            printError("Failed to download file from " .. url) 
            return
        end

        if request.getResponseCode() ~= 200 then
            printError("Failed to download file from " .. url .. " (response code " .. request.getResponseCode() .. ")")
            return
        end

        local content = request.readAll()
        request.close()        

        local fullPath = fs.combine(pathPrefix, path)
        local file = fs.open(fullPath, "w")
        file.write(content)
        file.close()
    end

    if package.main then
        print("Add " .. package.package .. " alias? (y/n, default: y)")
        local answer = read()
        if answer == "" or answer == "y" or answer == "Y" then
            local aliasPath = fs.combine(pathPrefix, package.main)
            shell.setAlias(package.package, aliasPath)
            print("Added alias for " .. package.package)
        end
    end
end

local function install(package, registry)
    if package == nil or package == "" then
        printError("No package specified.")
        return
    end

    if registry then
        if type(registry) == "string" then
            registry = config.registries[registry]
            if not registry then
                printError("Registry not found: " .. tostring(registry))
                return
            end
        elseif type(registry) ~= "table" then
            printError("Invalid registry specified.")
            return
        end

        local inputs = extract_args(package, registry.inputs)
        if inputs then
            install_package(registry, inputs)
        else
            printError("No matching format found in registry: " .. registry.name)
            return
        end
    else
        for _, registry in pairs(config.registries) do
            local inputs = extract_args(package, registry.inputs)
            if inputs then
                install_package(registry, inputs)
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
        printError("Unknown command: " .. tostring(cmd[1]))
        return
    end
end

return parseCommand({ ... })