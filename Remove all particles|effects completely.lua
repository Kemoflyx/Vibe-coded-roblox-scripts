local Players = game:GetService("Players")

local INVISIBLE_SEQ = NumberSequence.new(1)
local ZERO_SEQ      = NumberSequence.new(0)

local function kill(obj)
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

local function scanRoot(root)
    for _, obj in ipairs(root:GetDescendants()) do kill(obj) end
end

scanRoot(game.Workspace)
scanRoot(game:GetService("Lighting"))

game.DescendantAdded:Connect(function(obj) task.defer(kill, obj) end)

local lp = Players.LocalPlayer
if lp then
    lp.CharacterAdded:Connect(function(char) task.defer(scanRoot, char) end)
    if lp.Character then scanRoot(lp.Character) end
end
