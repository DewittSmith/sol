STARTUP_PATH = "/startup"
REGISTRIES_PATH = "/registries"
PACKAGES_PATH = "/packages"

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
if type(order) ~= "table" then order = {} end
orderFile.close()

local cachedPackages = {}

function order.insert(modname, installPath)
    table.insert(order, installPath)
    order[modname] = #order
    order[modname:match("^(.+)%+")] = #order
    order[modname:match("^(.+)@")] = #order

    -- Functions are not serializable, so we temporarily remove it
    local oldInsert = order.insert
    order.insert = nil

    local orderFile = fs.open(orderPath, "w")
    orderFile.write(textutils.serialise(order))
    orderFile.close()

    order.insert = oldInsert
end

_G.sol = _G.sol or {}
_G.sol.loadorder = order
_G.sol.require = function(modname)
    if not modname or modname == "" then error("No modname provided") end
    if cachedPackages[modname] then return cachedPackages[modname] end

    local ip = _G.sol.loadorder[modname]
    if not ip then error("Module '" .. modname .. "' not found") end
    ip = _G.sol.loadorder[ip]

    local mod = {}
    cachedPackages[modname] = mod

    local oldPath = package.path
    package.path = oldPath .. ";" .. fs.combine_abs(ip, "?.lua")

    local success, err = pcall(function()
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

                local mod = require(requirePath)
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
    end)

    if not success then
        cachedPackages[modname] = nil
        printError(err)
    end

    package.path = oldPath
    return mod
end
