-- Prevent the script from running multiple times
if getgenv().VFXKillerLoaded then 
    return 
end
getgenv().VFXKillerLoaded = true

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

-- Localized function so the engine doesn't have to search the global environment
local function killVFX(obj)
    -- Grouped checks using inheritance where possible
    if obj:IsA("ParticleEmitter") then
        obj.Enabled = false
        obj:Clear() -- Wipes existing particles immediately
        
    elseif obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
        obj.Enabled = false
        
    elseif obj:IsA("Light") then -- 'Light' is the base class for Point, Spot, and Surface lights
        obj.Enabled = false
    end
end

local function scanRoot(root)
    -- Generalized iteration is faster than ipairs
    for _, obj in root:GetDescendants() do 
        killVFX(obj) 
    end
end

-- Perform the initial scan only on visual areas
scanRoot(Workspace)
scanRoot(Lighting)

-- Hook up connections strictly to Workspace and Lighting to prevent UI/Core GUI lag
getgenv().VFXWorkspaceConnection = Workspace.DescendantAdded:Connect(function(obj) 
    task.defer(killVFX, obj) 
end)

getgenv().VFXLightingConnection = Lighting.DescendantAdded:Connect(function(obj) 
    task.defer(killVFX, obj) 
end)

-- Character handling
local lp = Players.LocalPlayer
if lp then
    getgenv().VFXCharConnection = lp.CharacterAdded:Connect(function(char) 
        -- scanRoot inherently covers descendants, no need to wait for them to load individually
        task.defer(scanRoot, char) 
    end)
    
    if lp.Character then 
        scanRoot(lp.Character) 
    end
end
