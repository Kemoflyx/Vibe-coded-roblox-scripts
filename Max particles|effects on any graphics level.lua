local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Lighting   = game:GetService("Lighting")

local Cache = setmetatable({}, { __mode = "k" })

if getgenv().GraphicsPatcher then
    for _, v in pairs(getgenv().GraphicsPatcher.Conns) do v:Disconnect() end
end
getgenv().GraphicsPatcher = { Conns = {} }
local Conns = getgenv().GraphicsPatcher.Conns

local function patch(obj)
    if Cache[obj] then return end
    if obj:IsA("ParticleEmitter") then
        local originalRate = obj.Rate
        if originalRate > 0 then
            Cache[obj] = { rate = originalRate, acc = 0 }
            obj.Rate = 0
            obj.Brightness = math.max(obj.Brightness, 1.5)
        end
    elseif obj:IsA("Beam") then
        Cache[obj] = true
        obj.Segments = math.max(obj.Segments, 10)
    elseif obj:IsA("Light") then
        Cache[obj] = true
        obj.Shadows = true
    end
end

local function safeScan(root)
    local descendants = root:GetDescendants()
    for i = 1, #descendants do
        patch(descendants[i])
        if i % 200 == 0 then task.wait() end
    end
end

task.spawn(safeScan, Workspace)
task.spawn(safeScan, Lighting)

table.insert(Conns, Workspace.DescendantAdded:Connect(patch))
table.insert(Conns, Lighting.DescendantAdded:Connect(patch))

local deadKeys = {}

table.insert(Conns, RunService.Heartbeat:Connect(function(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position
    dt = math.min(dt, 0.1)

    for emitter, data in pairs(Cache) do
        -- Prune dead entries right here instead of letting them pile up
        if not emitter.Parent then
            deadKeys[#deadKeys + 1] = emitter
            continue
        end

        if type(data) ~= "table" or not emitter.Enabled then continue end

        local parent = emitter.Parent
        if parent:IsA("BasePart") then
            if (parent.Position - camPos).Magnitude > 150 then continue end
        end

        data.acc = data.acc + dt
        local interval = 1 / data.rate
        if data.acc >= interval then
            local count = math.floor(data.acc / interval)
            data.acc = data.acc - (count * interval)
            emitter:Emit(count)
        end
    end

    -- Flush dead entries accumulated this frame
    for i = 1, #deadKeys do
        Cache[deadKeys[i]] = nil
        deadKeys[i] = nil
    end
end))
