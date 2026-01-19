local SOL_URL = "https://raw.githubusercontent.com/DewittSmith/sol/refs/heads/main/sol.lua"
local SHARED_URL = "https://raw.githubusercontent.com/DewittSmith/sol/refs/heads/main/shared.lua"
local GH_REGISTRY_URL = "https://raw.githubusercontent.com/DewittSmith/sol/refs/heads/main/registries/github.lua"

local function read_file(url)
    local response = http.get(url, HEADERS)
    if not response then error("Failed to fetch URL: " .. url) end
    local content = response.readAll()
    response.close()
    return content
end

local oldShell, oldRequire = _G.shell, _G.require
_G.shell, _G.require = shell, function(modname)
    if modname == "shared" then
        local sharedCode = read_file(SHARED_URL)
        return assert(loadstring(sharedCode))()
    else
        return oldRequire(modname)
    end
end

local success, err = pcall(function()
    print("Loading sol package manager...")
    local sol = read_file(SOL_URL)
    sol = assert(loadstring(sol))()

    print("Loading github registry...")
    sol.add_registry(GH_REGISTRY_URL)

    sol.install("https://github.com/DewittSmith/sol", registry)
end)

if not success then printError("Error loading sol: " .. err) end

_G.shell, _G.require = oldShell, oldRequire