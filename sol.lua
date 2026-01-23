local STARTUP_PATH = "/startup"
local PACKAGES_PATH = "/packages"
local REGISTRIES_PATH = "registries"

local function error_handler(err) return debug.traceback(err) end

local api = {}
do
    function fs.combine_abs(...)
        local combined = fs.combine(...)
        if combined:sub(1, 1) ~= "/" then
            combined = "/" .. combined
        end
        return combined
    end

    local orderPath = fs.combine_abs(PACKAGES_PATH, "load.order")
    if not fs.exists(orderPath) then
        local orderFile = fs.open(orderPath, "w")
        orderFile.write(textutils.serialise({ }))
        orderFile.close()
    end

    function string.trimext(path)
        return path:match("([^/]+)%.%w+$") or path
    end

    local orderFile = fs.open(orderPath, "r")
    local order = textutils.unserialise(orderFile.readAll())
    orderFile.close()
    if type(order) ~= "table" then order = {} end

    if order["sol"] then REGISTRIES_PATH = fs.combine_abs(order[order["sol"]], REGISTRIES_PATH) end

    local cachedPackages = {}

    local function popfn()
        local result = {}
        for k, v in pairs(order) do
            if type(v) == "function" then
                result[k] = v
                order[k] = nil
            end
        end
        return result
    end

    local function pushfn(fns)
        for k, v in pairs(fns) do
            order[k] = v
        end
    end

    order.insert = function(modname, installPath)
        if order[modname] then
            local index = order[modname]
            if order[index] == installPath then return end
            order[index] = installPath
        else
            table.insert(order, installPath)
            order[modname] = #order
            order[modname:match("^(.+)%+")] = #order
            order[modname:match("^(.+)@")] = #order
        end

        -- Functions are not serializable, so we temporarily remove it
        local fns = popfn()

        local orderFile = fs.open(orderPath, "w")
        orderFile.write(textutils.serialise(order))
        orderFile.close()

        pushfn(fns)
    end

    order.remove = function(modname)
        local index = order[modname]
        if not index then return end

        table.remove(order, index)
        order[modname] = nil
        order[modname:match("^(.+)%+")] = nil
        order[modname:match("^(.+)@")] = nil

        -- Functions are not serializable, so we temporarily remove it
        local fns = popfn()

        local orderFile = fs.open(orderPath, "w")
        orderFile.write(textutils.serialise(order))
        orderFile.close()

        pushfn(fns)
    end

    local function solRequire(modname)
        if not modname or modname == "" then error("No modname provided") end
        if cachedPackages[modname] then return cachedPackages[modname] end

        local ip = order[modname]
        if not ip then error("Module '" .. modname .. "' not found") end
        ip = order[ip]

        local mod = {}
        cachedPackages[modname] = mod

        if not package then package = {} end
        local oldPath = package.path
        package.path = (oldPath and (oldPath .. ";") or "") .. fs.combine_abs(ip, "?.lua")

        local success, err = xpcall(function()
            local function loadFile(folder, prefix, p)
                if fs.isDir(p) then
                    local dirName = fs.getName(p)
                    local newPrefix = prefix and (prefix .. "." .. dirName) or dirName
                    folder[dirName] = folder[dirName] or {}
                    for _, subpath in ipairs(fs.list(p)) do
                        loadFile(folder[dirName], newPrefix, fs.combine_abs(p, subpath))
                    end
                elseif p:match("%.lua$") then
                    local filename = p:trimext()
                    local requirePath = prefix and (prefix .. "." .. filename) or filename

                    local mod = _ENV.require(requirePath)
                    if type(mod) == "table" then
                        if filename == modname or filename == "init" then
                            for k, v in pairs(mod) do
                                folder[k] = v
                            end
                        else
                            folder[filename] = mod
                        end
                    end
                end
            end

            local function cleanup(tbl)
                for k, v in pairs(tbl) do
                    if type(v) == "table" then
                        cleanup(v)
                        if next(v) == nil then
                            tbl[k] = nil
                        end
                    elseif v == true then
                        tbl[k] = nil
                    end
                end
            end

            for _, p in ipairs(fs.list(ip)) do
                loadFile(mod, nil, fs.combine_abs(ip, p))
            end

            cleanup(mod)
        end, error_handler)

        if not success then
            cachedPackages[modname] = nil
            printError(err)
        end

        package.path = oldPath
        return mod
    end

    api.loadorder = order
    api.require = solRequire
end

if not http.checkURL("https://www.google.com/") then
    printError("HTTP client not available. Please enable it in the ComputerCraft settings.")
    return
end

local config = {
    registries = {}
}

function require(modname) return api.require(modname) end

function add_registry(url, ops)
    ops = ops or {}

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
    if not ops.silent then print("Registry added: " .. registry.name) end
end

if fs.exists(REGISTRIES_PATH) then
    for _, file in ipairs(fs.list(REGISTRIES_PATH)) do
        if file:sub(-4) == ".lua" then
            local path = fs.combine(REGISTRIES_PATH, file)
            add_registry("file://" .. path, { silent = true })
        end
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

    if pkg.hooks.onstartup then
        local hook = registry.load_file(pkg._inputs, pkg.hooks.onstartup)
        write_file(hook, fs.combine_abs(pkg.fullpath, pkg.hooks.onstartup))

        print("Running onstartup hook...")

        local startupPath = fs.combine_abs(STARTUP_PATH, pkg.fullname .. "_onstartup.lua")
        local startup = fs.open(startupPath, "w")
        startup.write("shell.run(\"" .. fs.combine_abs(pkg.fullpath, pkg.hooks.onstartup) .. "\", \"" .. pkg.fullname .. "\", \"" .. pkg.fullpath .. "\")")
        startup.close()

        shell.run(startupPath)
    end

    api.loadorder.insert(pkg.fullname, pkg.fullpath)
    print("Package " .. pkg.package .. " installed successfully.")
end

local function uninstall_package(pkg)
    print("Uninstalling package " .. pkg.fullname .. "...")

    if fs.exists(pkg.fullpath) then 
        fs.delete(pkg.path)

        for _, file in ipairs(fs.list(STARTUP_PATH)) do
            if file:match("^" .. pkg.fullname .. ".*") then
                fs.delete(fs.combine_abs(STARTUP_PATH, file))
            end
        end

        api.loadorder.remove(pkg.fullname)
    end

    print("Package " .. pkg.fullname .. " uninstalled successfully.")
end

function install(package, ops)
    ops = ops or {}

    local success, registry, pkg = xpcall(extract_pkg, error_handler, package, ops.registry)
    if not success then printError(registry) return end

    local success, err = xpcall(install_package, error_handler, registry, pkg, ops.noprompt)
    if not success then
        printError(err)

        local success, err = xpcall(uninstall_package, error_handler, pkg)
        if not success then printError("Failed to clean up after failed installation: " .. err) end
    end
end

function uninstall(package, ops)
    ops = ops or {}

    local success, registry, pkg = xpcall(extract_pkg, error_handler, package, ops.registry)
    if not success then printError(registry) return end

    local success, err = xpcall(uninstall_package, error_handler, pkg)
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
    },
    [add_registry] = {
        silent = { parse = function(...) return 0, true end },
        ["-s"] = "silent",
        ["--silent"] = "silent",
    },
}

local function parseOps(fn, ...)
    local ops = {}
    local args = {...}

    local parser = opsParsers[fn]
    if not parser then return ops end

    local i = 1
    while i <= #args do
        local arg = args[i]
        local key = parser[arg]
        if key ~= nil then
            local argc, value = parser[key].parse(select(i + 1, ...))
            ops[key] = value
            i = i + argc + 1
        else
            printError("Unknown option: " .. tostring(arg))
            i = i + 1
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
        add_registry = add_registry,
        require = api.require,
    }
else
    parseCommand(args)
end
