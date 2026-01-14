local args = { ... }

if #args < 2 then
    print("Usage: installer.lua <repo_owner> <repo_name> [ref]")
    return
end

local function endsWith(str, suffix)
    return suffix == "" or string.sub(str, -string.len(suffix)) == suffix
end

local HEADERS = {
    ["User-Agent"] = "ComputerCraft Installer"
}

local repoUrl = "https://api.github.com/repos/%s/%s/contents/"
local repoOwner = args[1]
local repoName = args[2]
repoUrl = string.format(repoUrl, repoOwner, repoName)

if args[3] then
    repoUrl = repoUrl .. "?ref=" .. args[3]
end

local function gitRequest(url)
    local request = http.get({
        url = url,
        headers = HEADERS
    })

    if not request then
        error("Failed to connect to GitHub API.")
    end

    local responseCode = request.getResponseCode()
    if responseCode ~= 200 then
        error("GitHub API returned response code: " .. responseCode)
    end

    local response = request.readAll()
    request.close()

    return textutils.unserialiseJSON(response)
end

local function loadContents(response)
    for _, value in pairs(response) do
        if value.type == "dir" then
            loadContents(gitRequest(value.url))
            goto continue
        elseif value.type ~= "file" then
            goto continue
        end

        if not endsWith(value.name:lower(), ".lua") then
            goto continue
        end

        print("Downloading '" .. value.path .. "'")

        local r = http.get({
            url = value.download_url,
            headers = HEADERS
        })

        local content = r.readAll()
        r.close()

        local file = fs.open(value.path, "w")
        file.write(content)
        file.close()

        ::continue::
    end
end

local response = gitRequest(repoUrl)
loadContents(response)