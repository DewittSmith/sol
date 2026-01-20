local _, installPath = ...
local solPath = fs.combine(installPath, "sol.lua")
if installPath:sub(1, 1) ~= "/" then solPath = "/" .. solPath end
os.loadAPI(solPath)
shell.setAlias("sol", solPath)
