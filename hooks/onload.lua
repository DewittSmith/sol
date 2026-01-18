local _, installPath = ...

if not string.find(package.path, installPath, 1, true) then
    package.path = package.path .. ";" .. fs.combine(installPath, "?.lua")
end

if not shell.aliases()["sol"] then
    print("Add alias for sol? (y/n, default: y)")
    local answer = read()

    if answer ~= "n" and answer ~= "N" then
        shell.setAlias("sol", fs.combine(installPath, "sol.lua"))
    end
end