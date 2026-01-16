local BLOB_API = "https://api.github.com/repos/%s/%s/git/trees/%s?recursive=true"
local RAW_API = "https://raw.githubusercontent.com/%s/%s/%s/%s"

local function read(url)
    local content = http.get(url)
    if not content then
        error("Failed to read file from " .. url)
    end

    if content.getResponseCode() ~= 200 then
        error("Failed to read file from " .. url .. " (response code " .. content.getResponseCode() .. ")")
    end

    local data = content.readAll()
    content.close()
    return data
end

local function load_package(inputs)
    local result = {
        author = inputs.owner,
        package = inputs.name,
        version = "unknown"
    }

    local url = string.format(RAW_API, inputs.owner, inputs.name, inputs.ref or "main", "package.json")

    local success, packageData = pcall(read, url)
    if not success then return result end
    packageData = textutils.unserialiseJSON(packageData)

    for k, v in pairs(packageData) do 
        result[k] = v
    end

    return result
end

local function list_files(package, inputs)
    local url = string.format(BLOB_API, inputs.owner, inputs.name, inputs.ref or "main")
    local tree = textutils.unserialiseJSON(read(url)).tree

    local output = { }
    local function download(entry)
        print(entry.path)
        if entry.type ~= "blob" then return end
        if not package.is_included(entry.path) then return end
        output[entry.path] = string.format(RAW_API, inputs.owner, inputs.name, inputs.ref or "main", entry.path)
    end

    for _, entry in pairs(tree) do
        download(entry)
    end

    return pairs(output)
end

return {
    load_package = load_package,
    list_files = list_files,
    inputs = {
        "github.com/{owner}/{name}",
        "github.com/{owner}/{name}/tree/{ref}",
    },
}