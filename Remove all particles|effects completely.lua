-- Kill GraphicsPatcher first so Emit() stops before we touch anything
if getgenv().GraphicsPatcher then
    for _, v in pairs(getgenv().GraphicsPatcher.Conns) do v:Disconnect() end
    getgenv().GraphicsPatcher = nil
end

if getgenv().VFXKillerLoaded then
    if getgenv().VFXWorkspaceConnection then getgenv().VFXWorkspaceConnection:Disconnect() end
    if getgenv().VFXLightingConnection then getgenv().VFXLightingConnection:Disconnect() end
    if getgenv().VFXCharConnection then getgenv().VFXCharConnection:Disconnect() end
    getgenv().VFXKillerLoaded = nil
end
getgenv().VFXKillerLoaded = true

local Workspace = game:GetService("Workspace")
local Lighting  = game:GetService("Lighting")
local Players   = game:GetService("Players")

local Cache = getgenv().GraphicsPatcherCache  -- restore original rates if patcher ran

local INVIS = NumberSequence.new(1)  -- fully transparent

local function killVFX(obj)
    if obj:IsA("ParticleEmitter") then
        -- Restore original rate first so Clear() actually wipes everything cleanly
        if Cache and Cache[obj] and type(Cache[obj]) == "table" then
            obj.Rate = Cache[obj].rate
            Cache[obj] = nil
        end
        obj.Rate         = 0
        obj.Enabled      = false
        obj.Brightness   = 0
        obj.Transparency = INVIS  -- invisible even if somehow re-enabled
        obj.Speed        = NumberRange.new(0)
        obj:Clear()
    elseif obj:IsA("Trail") then
        obj.Enabled      = false
        obj.Transparency = INVIS
    elseif obj:IsA("Beam") then
        obj.Enabled      = false
        obj.Transparency = INVIS
    elseif obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
        obj.Enabled = false
        pcall(function() obj.Size = 0 end)     -- Fire/Smoke have Size
        pcall(function() obj.Density = 0 end)  -- Smoke has Density
    elseif obj:IsA("Light") then
        obj.Enabled = false
    end
end

local function scanRoot(root)
    for _, obj in root:GetDescendants() do
        killVFX(obj)
    end
end

scanRoot(Workspace)
scanRoot(Lighting)

getgenv().VFXWorkspaceConnection = Workspace.DescendantAdded:Connect(function(obj)
    task.defer(killVFX, obj)
end)
getgenv().VFXLightingConnection = Lighting.DescendantAdded:Connect(function(obj)
    task.defer(killVFX, obj)
end)

local lp = Players.LocalPlayer
if lp then
    getgenv().VFXCharConnection = lp.CharacterAdded:Connect(function(char)
        task.defer(scanRoot, char)
    end)
    if lp.Character then
        scanRoot(lp.Character)
    end
end
