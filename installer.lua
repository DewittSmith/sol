local args = { ... }

local function printUsage()
    print("Installer Usage:")
    print("  installer.lua <repo_owner> <repo_name> [options]")
    print("")
    print("Arguments:")
    print("  <repo_owner>    GitHub username/org owning repo.")
    print("  <repo_name>     Name of the GitHub repo.")
    print("")
    print("Options:")
    print("  -r, --ref <ref> Specify branch/tag/commit SHA.")
    print("  -e, --extensions <exts> Comma-separated exts")
    print("    (whitelist by default, use -b for blacklist)")
    print("  -b, --blacklist   Treat extensions as blacklist.")
    print("  -h, --help        Show this help message.")
end

local function parseArguments(args)
    if #args < 2 then
        printUsage()
        return nil
    end

    local repo_owner = args[1]
    local repo_name = args[2]
    local ref = nil
    local extensions = nil
    local blacklist = false

    local i = 3
    while i <= #args do
        if args[i] == "--ref" or args[i] == "-r" then
            if i + 1 > #args then
                print("Missing value for " .. args[i])
                return nil
            end
            ref = args[i + 1]
            i = i + 2
        elseif args[i] == "--extensions" or args[i] == "-e" then
            if i + 1 > #args then
                print("Missing value for " .. args[i])
                return nil
            end
            extensions = args[i + 1]
            i = i + 2
        elseif args[i] == "--blacklist" or args[i] == "-b" then
            blacklist = true
            i = i + 1
        elseif args[i] == "--help" or args[i] == "-h" then
            printUsage()
            return nil
        else
            print("Unknown argument: " .. args[i])
            return nil
        end
    end

    return repo_owner, repo_name, ref, extensions, blacklist
end

local repo_owner, repo_name, ref, extensions, blacklist = parseArguments(args)
if not repo_owner then return end

local function get_extension(filename)
    return filename:match("%.([^.]+)$")
end

local HEADERS = {
    ["User-Agent"] = "ComputerCraft Installer"
}

local extensionWhitelist = {}
if extensions then
    for ext in string.gmatch(extensions, "[^,]+") do
        extensionWhitelist[ext:lower():gsub("%s+", "")] = true
    end
elseif not blacklist then
    extensionWhitelist["lua"] = true
end

local isBlacklist = blacklist

local repoUrl = "https://api.github.com/repos/%s/%s/contents/"
repoUrl = string.format(repoUrl, repo_owner, repo_name)

if ref then
    repoUrl = repoUrl .. "?ref=" .. ref
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

        local ext = get_extension(value.name:lower())
        if isBlacklist then
            if extensionWhitelist[ext] then
                goto continue
            end
        else
            if not extensionWhitelist[ext] then
                goto continue
            end
        end

        print("Downloading " .. value.path .. "...")

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