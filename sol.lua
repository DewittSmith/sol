require("shared")

if not http.checkURL("https://www.google.com/") then
    printError("HTTP client not available. Please enable it in the ComputerCraft settings.")
    return
end

local config = {
    registries = {}
}

local function add_registry(url, ops)
    if url == nil or url == "" then printError("No registry URL specified.") return end
    local FILE_PREFIX = "file://"

    local content = nil
    if url:sub(1, #FILE_PREFIX) == FILE_PREFIX then
        local path = url:sub(#FILE_PREFIX + 1)
        content = fs.open(path, "r")
    else
        content = http.get(url)
    end

    if not content then 
        printError("Failed to download registry from " .. url) 
        return
    end

    if content.getResponseCode and content.getResponseCode() ~= 200 then
        printError("Failed to download registry from " .. url .. " (response code " .. content.getResponseCode() .. ")")
        return
    end
    
    local registryCode = content.readAll()
    content.close()

    local registry = assert(loadstring(registryCode))()
    if not registry.name then registry.name = url:trimext() end

    config.registries[registry.name] = registry
    print("Registry added: " .. registry.name)
end

if fs.exists(REGISTRIES_PATH) then
    for _, file in ipairs(fs.list(REGISTRIES_PATH)) do
        local path = fs.combine_abs(REGISTRIES_PATH, file)
        add_registry("file://" .. path, {})
    end
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

local function get_package_info(registry, inputs)
    local pkg = {
        _inputs = inputs,
        author = inputs.owner,
        package = inputs.name,
        version = "unknown",
        include = { },
        exclude = { },
        hooks = { }
    }

    local pkgData = registry.load_file(inputs, "package.json")
    pkgData = pkgData and textutils.unserialiseJSON(pkgData) or {}

    for k, v in pairs(pkgData) do pkg[k] = v end
    if #pkg.include == 0 then table.insert(pkg.include, "%.lua$") end

    pkg.is_included = function(path)
        if path == nil or path == "" then return false end

        local isIncluded = false
        for _, pattern in ipairs(pkg.include) do
            if path:match(pattern) then
                isIncluded = true
                break
            end
        end

        for _, pattern in ipairs(pkg.exclude) do
            if path:match(pattern) then
                isIncluded = false
                break
            end
        end

        return isIncluded
    end

    pkg.fullname = pkg.package .. "+" .. pkg.author ..  "@" .. registry.name
    pkg.path = fs.combine_abs(PACKAGES_PATH, pkg.fullname)
    pkg.fullpath = fs.combine_abs(pkg.path, pkg.version)

    return pkg
end

local function extract_pkg(package, registry)
    if package == nil or package == "" then error("No package specified.") end

    local inputs = nil
    if registry then
        if type(registry) == "string" then
            registry = config.registries[registry]
            if not registry then error("Registry not found: " .. tostring(registry)) end
        elseif type(registry) ~= "table" then error("Invalid registry specified.") end

        inputs = extract_args(package, registry.inputs)
    else
        for _, r in pairs(config.registries) do
            inputs = extract_args(package, r.inputs)
            if inputs then registry = r break end
        end
    end

    if inputs then return registry, get_package_info(registry, inputs)
    elseif registry then error("No matching format found in registry: " .. registry.name)
    else error("No matching registry found.")
    end
end

local function install_package(registry, pkg, noprompt)
    if fs.exists(pkg.fullpath) then
        print("Package " .. pkg.fullname .. " is already installed, version(s):")
        for _, v in ipairs(fs.list(pkg.path)) do print(" - " .. v) end
        print()

        if noprompt then return
        else
            print("Download anyway? (y/n, default n):")
            local answer = read()
            if answer ~= "y" and answer ~= "Y" then
                print("Installation cancelled.")
                return
            end
        end
    end

    print("Installing to " .. pkg.fullpath .. "...")
    local function write_file(content, path)
        local file = fs.open(path, "w")
        file.write(content)
        file.close()
    end

    local function download(url, path)
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
        write_file(content, fs.combine_abs(pkg.fullpath, path))
    end

    for path, url in registry.list_files(pkg._inputs, pkg) do download(url, path) end

    if pkg.hooks.onload then
        local hook = registry.load_file(pkg._inputs, pkg.hooks.onload)
        write_file(hook, fs.combine_abs(pkg.fullpath, pkg.hooks.onload))

        print("Running onload hook...")

        local startupPath = fs.combine_abs(STARTUP_PATH, pkg.fullname .. "_onload.lua")
        local startup = fs.open(startupPath, "w")
        startup.write("shell.run(\"" .. fs.combine_abs(pkg.fullpath, pkg.hooks.onload) .. "\", \"" .. pkg.fullname .. "\", \"" .. pkg.fullpath .. "\")")
        startup.close()

        shell.run(startupPath)
    end

    sol.loadorder.insert(pkg.fullname, pkg.fullpath)
    print("Package " .. pkg.package .. " installed successfully.")
end

local function uninstall_package(pkg)
    print("Uninstalling package " .. pkg.fullname .. "...")
    if fs.exists(pkg.fullpath) then fs.delete(pkg.fullpath) end
    print("Package " .. pkg.fullname .. " uninstalled successfully.")
end

local function install(package, ops)
    local success, registry, pkg = pcall(extract_pkg, package, ops.registry)
    if not success then printError(registry) return end

    local success, err = pcall(install_package, registry, pkg, ops.noprompt)
    if not success then
        printError(err)

        local success, err = pcall(uninstall_package, pkg)
        if not success then printError("Failed to clean up after failed installation: " .. err) end
    end
end

local function uninstall(package, ops)
    local success, registry, pkg = pcall(extract_pkg, package, ops.registry)
    if not success then printError(registry) return end

    local success, err = pcall(uninstall_package, pkg)
    if not success then printError(err) end
end

local opsParsers = {
    [install] = {
        noprompt = { parse = function(...) return 0, true end },
        registry = { parse = function(...) return 1, ... end },
        ["-np"] = "noprompt",
        ["--noprompt"] = "noprompt",
        ["-r"] = "registry",
        ["--registry"] = "registry",
    },
    [uninstall] = {
        registry = { parse = function(...) return 1, ... end },
        ["-r"] = "registry",
        ["--registry"] = "registry",
    }
}

local function parseOps(fn, ...)
    local ops = {}
    local args = {...}

    local parser = opsParsers[fn]
    if not parser then return ops end

    for i = 1, #args do
        local arg = args[i]
        local key = parser[arg]
        if key ~= nil then
            local argc, value = parser[key].parse(select(i + 1, ...))
            ops[key] = value
            i = i + argc
        else
            printError("Unknown option: " .. tostring(arg))
        end
    end

    return ops
end

local function parseCommand(cmd)
    if cmd[1] == "install" then
        install(cmd[2], parseOps(install, table.unpack(cmd, 3)))
    elseif cmd[1] == "uninstall" then
        uninstall(cmd[2], parseOps(uninstall, table.unpack(cmd, 3)))
    elseif cmd[1] == "registry" and cmd[2] == "add" then
        add_registry(cmd[3], parseOps(add_registry, table.unpack(cmd, 4)))
    else
        printError("Unknown command: " .. tostring(cmd[1]))
    end
end

local args = { ... }
if #args == 0 or args[1] == "sol" then
    return {
        install = install,
        uninstall = uninstall,
        add_registry = add_registry
    }
else
    return parseCommand(args)
end
