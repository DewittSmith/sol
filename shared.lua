STARTUP_PATH = "/startup"
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

if order["sol"] then REGISTRIES_PATH = fs.combine_abs(order[order["sol"]], "registries")
else REGISTRIES_PATH = "registries"
end

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

function order.insert(modname, installPath)
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

function order.remove(modname)
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

return {
    loadorder = order,
    require = function(modname)
        if not modname or modname == "" then error("No modname provided") end
        if cachedPackages[modname] then return cachedPackages[modname] end

        local ip = order[modname]
        if not ip then error("Module '" .. modname .. "' not found") end
        ip = order[ip]

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
}
