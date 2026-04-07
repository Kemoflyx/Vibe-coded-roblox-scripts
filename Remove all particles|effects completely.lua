-- Prevent the script from running multiple times and stacking events
if getgenv().VFXKillerLoaded then 
    return 
end
getgenv().VFXKillerLoaded = true

local Players = game:GetService("Players")

local INVISIBLE_SEQ = NumberSequence.new(1)
local ZERO_SEQ      = NumberSequence.new(0)

-- Assigning the kill function to the global environment
getgenv().KillVFX = function(obj)
    if obj:IsA("ParticleEmitter") then
        pcall(function() obj.Enabled      = false         end)
        pcall(function() obj.Rate         = 0             end)
        pcall(function() obj.Transparency = INVISIBLE_SEQ end)
        pcall(function() obj.Size         = ZERO_SEQ      end)
        pcall(function() obj:Clear()                      end)

    elseif obj:IsA("Trail") then
        pcall(function() obj.Enabled      = false         end)
        pcall(function() obj.Transparency = INVISIBLE_SEQ end)
        pcall(function() obj.WidthScale   = ZERO_SEQ      end)

    elseif obj:IsA("Beam") then
        pcall(function() obj.Enabled      = false end)
        pcall(function() obj.Transparency = 1     end)
        pcall(function() obj.Width0       = 0     end)
        pcall(function() obj.Width1       = 0     end)

    elseif obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
        pcall(function() obj.Enabled = false end)

    elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
        pcall(function() obj.Enabled = false end)
    end
end

-- Assigning the scanning function to the global environment
getgenv().ScanRootVFX = function(root)
    for _, obj in ipairs(root:GetDescendants()) do 
        getgenv().KillVFX(obj) 
    end
end

-- Perform the initial scan
getgenv().ScanRootVFX(game:GetService("Workspace"))
getgenv().ScanRootVFX(game:GetService("Lighting"))

-- Hook up connections and store them in getgenv() in case you ever want to disconnect them later
getgenv().VFXDescendantConnection = game.DescendantAdded:Connect(function(obj) 
    task.defer(getgenv().KillVFX, obj) 
end)

local lp = Players.LocalPlayer
if lp then
    getgenv().VFXCharConnection = lp.CharacterAdded:Connect(function(char) 
        task.defer(getgenv().ScanRootVFX, char) 
    end)
    if lp.Character then 
        getgenv().ScanRootVFX(lp.Character) 
    end
end
