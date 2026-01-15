local CONFIG_FILE = "sol.config"
local HEADERS = {
    ["User-Agent"] = "Sol-Package-Manager"
}

local config = {
    registries = {
        ["github"] = {
            targets = {
                {
                    api = "https://api.github.com/repos/{owner}/{name}/contents",
                    format = "github.com/{owner}/{name}"
                }
            },
            headers = {}
        }
    }
}

if not http.checkURL("https://www.google.com/") then
    error("HTTP client not available. Please enable it in the ComputerCraft settings.")
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

    pattern = pattern .. "$"
    return pattern, vars
end

-- Try to match a target string against a format pattern
local function match_format(target, format)
    local pattern, vars = parse_format(format)
    local captures = { target:match(pattern) }
    if #captures == 0 then
        return nil
    end

    local result = {}
    for i, varname in ipairs(vars) do
        result[varname] = captures[i]
    end

    return result
end

-- Try to match against multiple format patterns
local function reverse_interpolate(target, formats)
    for i, format in ipairs(formats) do
        local result = match_format(target, format)
        if result then
            return result, i  -- Also return the index of matched format
        end
    end

    return nil, nil
end

-- Format a URL template with the extracted arguments
local function format_url(template, args)
    local result = template
    for key, value in pairs(args) do
        result = result:gsub("{" .. key .. "}", value)
    end

    return result
end

-- Parse target and generate URL
local function target_to_url(target, targets)
    for _, target_config in ipairs(targets) do
        local args = match_format(target, target_config.format)
        if args then
            local url = format_url(target_config.api, args)
            return url, nil, args
        end
    end

    return nil, "No matching format found"
end

if fs.exists(CONFIG_FILE) then
    local file = fs.open(CONFIG_FILE, "r")
    local localConfig = file.readAll()
    file.close()

    localConfig = textutils.unserialise(localConfig)
    error("Local config loading not yet implemented.")
end

local function read_file(headers, url)
    local content = http.get({ url = url, headers = headers })
    if not content then error("Failed to download file from " .. url) end
    local data = content.readAll()
    content.close()
    return data
end

local function install_url(registry, package, url)
    local headers = HEADERS
    for k, v in pairs(registry.headers or {}) do
        headers[k] = v
    end

    local request = http.get({ url = url, headers = headers })
    if not request then error("Failed to connect to registry: " .. name) end
    local responseCode = request.getResponseCode()
    if responseCode ~= 200 then error("Registry " .. name .. " returned response code: " .. responseCode) end

    local response = request.readAll()
    request.close()
    response = textutils.unserialiseJSON(response)
    local packageData = { prefix = fs.combine("packages", package.name) }
    for _, value in pairs(response) do
        if value.type == "file" and value.name == "package.json" then
            packageData = textutils.unserialiseJSON(read_file(headers, value.download_url))
            break
        end
    end

    if not packageData.version then packageData.version = "latest" end
    packageData.prefix = fs.combine(packageData.prefix, packageData.version)

    local include, exclude = {}, {}
    if packageData.main then
        table.insert(include, "^" .. packageData.main .. "$")
    end

    if packageData.include then
        for _, pattern in ipairs(packageData.include) do
            table.insert(include, pattern)
        end
    end

    if packageData.exclude then
        for _, pattern in ipairs(packageData.exclude) do
            table.insert(exclude, pattern)
        end
    end

    if #include == 0 then
        table.insert(include, "%.lua$")
    end

    local function download(entry)
        if entry.type == "dir" then
            local dir = textutils.unserialiseJSON(read_file(headers, entry.url))
            for _, subentry in pairs(dir) do download(subentry) end
        elseif entry.type == "file" then
            for _, pattern in ipairs(include) do
                if not entry.path:match(pattern) then return end
            end

            for _, pattern in ipairs(exclude) do
                if entry.path:match(pattern) then return end
            end

            print("Downloading " .. entry.path)
            local content = read_file(headers, entry.download_url)
            local filePath = fs.combine(packageData.prefix, entry.path)
            local file = fs.open(filePath, "w")
            file.write(content)
            file.close()
        end
    end

    for _, entry in pairs(response) do download(entry) end
end

local function install(package)
    if package == nil then error("No package specified.") end

    print("Installing package:")
    print(package)
    for name, registry in pairs(config.registries) do
        local apiUrl, err, p = target_to_url(package, registry.targets)
        if apiUrl then
            install_url(registry, p, apiUrl)
            break
        end
    end
end

local function parseCommand(cmd)
    if cmd[1] == "install" then
        install(cmd[2])
    elseif cmd[1] == "sol" then
        return {
            install = install
        }
    else
        error("Unknown command: " .. tostring(cmd[1]))
    end
end

return parseCommand({ ... })