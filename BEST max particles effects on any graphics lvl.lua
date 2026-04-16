-- SETTINGS: Change this and re-run the script to update live!
_G.ParticleLevel = 10 -- Range 1 to 10
_G.MaxDistance   = 250 -- Particles further than this won't render

local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

-- This table persists across re-executions so we never lose the TRUE original rate
shared.ParticleRegistry = shared.ParticleRegistry or setmetatable({}, { __mode = "k" })
local Registry = shared.ParticleRegistry

if getgenv().ParticlePatcher then
    getgenv().ParticlePatcher:Disconnect()
end

local function patch(obj)
    if not obj:IsA("ParticleEmitter") then return end
    
    -- Store the REAL original rate only once
    if not Registry[obj] then
        Registry[obj] = {
            rate = obj.Rate,
            parent = obj.Parent,
            isPart = obj.Parent and obj.Parent:IsA("BasePart"),
            isAttachment = obj.Parent and obj.Parent:IsA("Attachment")
        }
    end
    
    local data = Registry[obj]
    local multiplier = math.clamp(_G.ParticleLevel / 10, 0.1, 1)
    
    -- If we are close enough, set the rate based on our slider
    obj.Rate = data.rate * multiplier
end

-- Scan and Update
for _, v in pairs(Workspace:GetDescendants()) do
    pcall(patch, v)
end

-- Monitor new objects
getgenv().ParticlePatcher = Workspace.DescendantAdded:Connect(patch)

-- High-Performance Distance Culling Loop
local updateConnection
updateConnection = RunService.Heartbeat:Connect(function()
    if getgenv().ParticlePatcher ~= updateConnection then 
        updateConnection:Disconnect() 
        return 
    end
    
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position
    local multiplier = math.clamp(_G.ParticleLevel / 10, 0.1, 1)

    for emitter, data in pairs(Registry) do
        local parent = emitter.Parent
        if not parent then continue end
        
        if not emitter.Enabled then 
            continue 
        end

        local pos
        if data.isPart then pos = parent.Position
        elseif data.isAttachment then pos = parent.WorldPosition
        end

        if pos then
            if (pos - camPos).Magnitude > _G.MaxDistance then
                emitter.Rate = 0 -- Optimization: Kill rate if too far
            else
                -- Restore rate based on current Graphics Level
                emitter.Rate = data.rate * multiplier
            end
        end
    end
end)
getgenv().ParticlePatcher = updateConnection