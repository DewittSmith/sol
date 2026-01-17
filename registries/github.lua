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

local function load_file(inputs, path)
    local url = string.format(RAW_API, inputs.owner, inputs.name, inputs.ref or "main", path)
    local _, packageData = pcall(read, url)
    return packageData
end

local function list_files(package, inputs)
    local url = string.format(BLOB_API, inputs.owner, inputs.name, inputs.ref or "main")
    local tree = textutils.unserialiseJSON(read(url)).tree

    local output = { }
    local function download(entry)
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
    load_file = load_file,
    list_files = list_files,
    inputs = {
        "github.com/{owner}/{name}",
        "github.com/{owner}/{name}/tree/{ref}",
    },
}