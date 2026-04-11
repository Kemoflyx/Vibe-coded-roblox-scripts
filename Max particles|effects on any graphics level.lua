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
        end
    elseif obj:IsA("Beam") then
        Cache[obj] = true
        obj.Segments = math.max(obj.Segments, 10)
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
-- defer so objects are fully initialized before we touch them
table.insert(Conns, Workspace.DescendantAdded:Connect(function(obj)
    task.defer(patch, obj)
end))
table.insert(Conns, Lighting.DescendantAdded:Connect(function(obj)
    task.defer(patch, obj)
end))
local deadKeys = {}
table.insert(Conns, RunService.Heartbeat:Connect(function(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position
    dt = math.min(dt, 0.1)
    for emitter, data in pairs(Cache) do
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
    for i = 1, #deadKeys do
        Cache[deadKeys[i]] = nil
        deadKeys[i] = nil
    end
end))
