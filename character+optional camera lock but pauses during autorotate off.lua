-- Replicated Target Lock (Standalone, Re-executable, Real-time GUI Config)
local Players = game:GetService("Players") 
local UIS = game:GetService("UserInputService") 
local RunService = game:GetService("RunService") 
local CoreGui = game:GetService("CoreGui") 
local player = Players.LocalPlayer 
local camera = workspace.CurrentCamera

-- Global Settings Setup (Force-overwrites on re-execution so your code edits apply instantly)
getgenv().TargetLockSettings = { 
    Enabled = true, 
    Radius = 200, 
    MaxRange = 100,
    Prediction = 0.10, 
    LerpMin = 50, 
    LerpMax = 50, 
    LerpVel = 1, 
    HighlightVisible = true, 
    CamLock = false
}

local settings = getgenv().TargetLockSettings

-- Target UI Parent detection 
local targetGuiParent = CoreGui:FindFirstChild("RobloxGui") or player:WaitForChild("PlayerGui")

-- Cleanup Framework (Handles re-execution flawlessly) 
if getgenv().__lockCleanup then getgenv().__lockCleanup() end 
local cleanupTasks = {} 
local activeConns = {} 

local function onCleanup(fn) table.insert(cleanupTasks, fn) end 
local function trackActive(c) table.insert(activeConns, c) return c end

getgenv().__lockCleanup = function() 
    for _, fn in ipairs(cleanupTasks) do pcall(fn) end 
    cleanupTasks = {} 
    for _, c in ipairs(activeConns) do pcall(function() c:Disconnect() end) end 
    activeConns = {} 
    pcall(function() RunService:UnbindFromRenderStep("__CamTrackingLoop__") end) 
    local oldGui = targetGuiParent:FindFirstChild("TargetLock_Gui") 
    if oldGui then oldGui:Destroy() end
    getgenv().__lockCleanup = nil 
end

-- Clear old GUI instance if it exists before making a new one 
local oldGui = targetGuiParent:FindFirstChild("TargetLock_Gui") 
if oldGui then oldGui:Destroy() end

-- ==========================================
-- LOCAL PLAYER CACHING (CPU OPTIMIZATION)
-- ==========================================
local myChar, myRoot, myHum
local function updateLocalCharacter(character)
    myChar = character
    if character then
        task.spawn(function()
            myRoot = character:WaitForChild("HumanoidRootPart", 5)
            myHum = character:WaitForChild("Humanoid", 5)
        end)
    else
        myRoot, myHum = nil, nil
    end
end
trackActive(player.CharacterAdded:Connect(updateLocalCharacter))
updateLocalCharacter(player.Character)
-- ==========================================

-- Target Caching
local targetCache = {} 
local rootToData = {} 
local playerConns = {} 
local diedConns = {}

local function addModel(model) 
    if model == player.Character then return end
    local hrp = model:FindFirstChild("HumanoidRootPart") 
    local hum = model:FindFirstChildOfClass("Humanoid") 
    
    if not hrp or not hum then
        task.spawn(function() 
            local t = 0 
            while t < 2 do 
                task.wait(0.05) 
                t = t + 0.05 
                if not model.Parent then return end 
                hrp = model:FindFirstChild("HumanoidRootPart")
                hum = model:FindFirstChildOfClass("Humanoid") 
                if hrp and hum then break end 
            end
        end) 
    end 
    
    -- Added Health Check: Don't cache bodies that are already dead
    if hrp and hum and hum.Health > 0 then 
        local data = { Root = hrp, Humanoid = hum }
        targetCache[model] = data 
        rootToData[hrp] = data 
        
        -- Event listener: Instantly clears them from cache when they die
        local dc = hum.Died:Connect(function() 
            targetCache[model] = nil 
            rootToData[hrp] = nil 
        end)
        table.insert(diedConns, dc) 
    end 
end

local function removeModel(model) 
    local d = targetCache[model] 
    if d then rootToData[d.Root] = nil end 
    targetCache[model] = nil 
end

local function trackPlayer(p) 
    if p == player then return end 
    if playerConns[p] then 
        for _, c in ipairs(playerConns[p]) do pcall(function() c:Disconnect() end) end 
    end 
    playerConns[p] = {} 
    if p.Character then addModel(p.Character) end
    table.insert(playerConns[p], p.CharacterAdded:Connect(function(c) task.wait(0.5) addModel(c) end)) 
    table.insert(playerConns[p], p.CharacterRemoving:Connect(function(c) removeModel(c) end)) 
end

for _, model in ipairs(workspace:GetDescendants()) do 
    if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then addModel(model) end 
end 

for _, p in ipairs(Players:GetPlayers()) do trackPlayer(p) end

local c1 = Players.PlayerAdded:Connect(trackPlayer) 
local c2 = Players.PlayerRemoving:Connect(function(p) 
    if p.Character then removeModel(p.Character) end 
    if playerConns[p] then 
        for _, c in ipairs(playerConns[p]) do pcall(function() c:Disconnect() end) end
        playerConns[p] = nil 
    end 
end) 

local c3 = workspace.DescendantAdded:Connect(function(d) 
    if d:IsA("Humanoid") then
        task.wait(0.05) 
        local model = d.Parent 
        if model and model:IsA("Model") and model:FindFirstChild("HumanoidRootPart") then addModel(model) end 
    end 
end) 

local c4 = workspace.DescendantRemoving:Connect(function(d) 
    if d:IsA("Model") and targetCache[d] then removeModel(d) end 
end) 

onCleanup(function() c1:Disconnect() end) 
onCleanup(function() c2:Disconnect() end) 
onCleanup(function() c3:Disconnect() end) 
onCleanup(function() c4:Disconnect() end)
onCleanup(function() 
    for _, conns in pairs(playerConns) do 
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end 
    end 
    playerConns = {}
    for _, c in ipairs(diedConns) do pcall(function() c:Disconnect() end) end
    diedConns = {} 
end)

trackActive(RunService.Heartbeat:Connect(function() 
    local now = os.clock() 
    if not getgenv().__lastRescan or now - getgenv().__lastRescan < 3 then return end
    getgenv().__lastRescan = now 
    for p in pairs(playerConns) do 
        if p.Character and not targetCache[p.Character] then addModel(p.Character) end 
    end 
end))
getgenv().__lastRescan = os.clock()

-- Helper Functions 
local function isRagdolled() 
    if not myHum then return true end 
    return myHum:GetState() == Enum.HumanoidStateType.Physics 
end

local function getTarget(root) 
    local currentCamera = workspace.CurrentCamera 
    if not currentCamera then return nil end

    local aimScreen = UIS:GetMouseLocation()
    local closest, closestWorldDist = nil, math.huge

    for model, data in pairs(targetCache) do
        -- Only allow locking if Health > 0
        if model.Parent and data.Humanoid.Health > 0 then
            local dist = (data.Root.Position - root.Position).Magnitude
            
            if dist <= settings.MaxRange then
                local targetPos = data.Root.Position
                local screenPos, onScreen = currentCamera:WorldToViewportPoint(targetPos)
                
                if (not onScreen or screenPos.Z <= 0) and model:FindFirstChild("Head") then
                    targetPos = model.Head.Position
                    screenPos, onScreen = currentCamera:WorldToViewportPoint(targetPos)
                end

                if onScreen and screenPos.Z > 0 then
                    local sd = (Vector2.new(screenPos.X, screenPos.Y) - aimScreen).Magnitude
                    if sd <= settings.Radius then
                        if dist < closestWorldDist then
                            closestWorldDist = dist
                            closest = data.Root
                        end
                    end
                end
            end
        else
            targetCache[model] = nil
        end
    end
    return closest
end

-- PERFORMANCE OPTIMIZATION: Cache animation & physics states so it doesn't leak memory rendering at 144+ FPS
local lastVertCheck = 0
local cachedVertResult = false

local function checkVerticalAim(root, hum) 
    if not root or not hum then return false end

    local now = os.clock()
    if now - lastVertCheck < 0.05 then
        return cachedVertResult
    end
    lastVertCheck = now

    local isCombatActive = false
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        local priority = track.Priority
        if priority == Enum.AnimationPriority.Action 
           or priority == Enum.AnimationPriority.Action2 
           or priority == Enum.AnimationPriority.Action3 
           or priority == Enum.AnimationPriority.Action4 then
            isCombatActive = true
            break
        end
    end

    local st = hum:GetState()
    local isNativelyAerial = (st == Enum.HumanoidStateType.Flying or st == Enum.HumanoidStateType.Swimming)

    if not isCombatActive and not isNativelyAerial then
        cachedVertResult = false
        return false
    end

    if root.Anchored or hum.PlatformStand or isNativelyAerial then 
        cachedVertResult = true
        return true 
    end

    local bodyGyro = root:FindFirstChildOfClass("BodyGyro")
    if bodyGyro and bodyGyro.MaxTorque.X > 1000 then
        cachedVertResult = true
        return true
    end

    local alignOri = root:FindFirstChildOfClass("AlignOrientation")
    if alignOri and alignOri.AlignType ~= Enum.AlignType.PrimaryAxisParallel and alignOri.MaxTorque > 1000 then
        cachedVertResult = true
        return true
    end

    cachedVertResult = false
    return false
end

-- Camera Tracking State Control 
local function stopCamLock() 
    pcall(function() RunService:UnbindFromRenderStep("__CamTrackingLoop__") end) 
end

local function startCamLock(target) 
    if not settings.CamLock then return end

    RunService:BindToRenderStep("__CamTrackingLoop__", Enum.RenderPriority.Camera.Value + 1, function()
        if not settings.CamLock or not target or not target.Parent then 
            stopCamLock() 
            return 
        end
        
        local rawTargetPos = target.Position
        local currentCamPos = camera.CFrame.Position
        
        if myRoot then
            if myHum then
                myHum.CameraOffset = Vector3.new(0, 0, 0)
            end

            local dist = (rawTargetPos - myRoot.Position).Magnitude
            local dynamicHeight = 5
            
            if dist <= 10 then
                dynamicHeight = 10
            elseif dist >= 50 then
                dynamicHeight = 5
            else
                local alpha = (dist - 10) / 40 
                dynamicHeight = 10 - (5 * alpha)
            end

            local toPlayerDir = myRoot.Position - rawTargetPos
            local flatBackAxis = Vector3.new(toPlayerDir.X, 0, toPlayerDir.Z)
            
            if flatBackAxis.Magnitude > 0.001 then
                flatBackAxis = flatBackAxis.Unit
            else
                flatBackAxis = Vector3.new(0, 0, 1)
            end
            
            local currentZoom = (Vector3.new(currentCamPos.X, myRoot.Position.Y, currentCamPos.Z) - myRoot.Position).Magnitude
            local finalCamPos = myRoot.Position + (flatBackAxis * currentZoom) + Vector3.new(0, dynamicHeight, 0)
            
            camera.CFrame = CFrame.lookAt(finalCamPos, rawTargetPos)
        else
            camera.CFrame = CFrame.lookAt(currentCamPos, rawTargetPos)
        end
    end)
end

-- Lock State Variables 
local isLockEngaged = false 
local currentLockedTarget = nil 
local facingLoopConn = nil 
local targetHighlight = nil 
local lastLockedTarget = nil

onCleanup(function() 
    if targetHighlight then targetHighlight:Destroy() targetHighlight = nil end 
    stopCamLock() 
    if myHum then myHum.AutoRotate = true end 
end)

-- UNLOCK FUNCTION: Safely releases everything back to the player
local function stopTargetLock() 
    isLockEngaged = false 
    currentLockedTarget = nil 
    stopCamLock()
    if facingLoopConn then facingLoopConn:Disconnect() facingLoopConn = nil end 
    if targetHighlight then targetHighlight:Destroy() targetHighlight = nil end 
    if myHum then myHum.AutoRotate = true end 
end

local function startTargetLock(target) 
    if not settings.Enabled then return end
    
    -- Double-check before starting: Don't lock if they are dead
    local checkData = rootToData[target]
    if not checkData or checkData.Humanoid.Health <= 0 then return end

    isLockEngaged = true 
    currentLockedTarget = target 
    lastLockedTarget = target

    if targetHighlight then targetHighlight:Destroy() end
    if settings.HighlightVisible then
        local hl = Instance.new("Highlight")
        hl.FillColor         = Color3.fromRGB(255, 255, 255)
        hl.OutlineColor      = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency  = 0.75
        hl.OutlineTransparency = 0.4
        hl.Parent            = target.Parent
        targetHighlight = hl
    end

    startCamLock(target)

    facingLoopConn = trackActive(RunService.PreRender:Connect(function(dt)
        if not settings.Enabled then stopTargetLock() return end
        if isRagdolled() then stopTargetLock() return end
        if not myRoot then return end
        
        -- DEATH & DESPAWN CHECK (Zero CPU impact, pure O(1) table lookup)
        if not currentLockedTarget or not currentLockedTarget.Parent then 
            stopTargetLock() 
            return 
        end
        local targetData = rootToData[currentLockedTarget]
        if not targetData or targetData.Humanoid.Health <= 0 then 
            stopTargetLock() 
            return 
        end
        
        if myHum then myHum.AutoRotate = false end
        
        local myPos = myRoot.Position
        local targetPos = currentLockedTarget.Position + (currentLockedTarget.AssemblyLinearVelocity * settings.Prediction)
        
        local allowVertical = checkVerticalAim(myRoot, myHum)
        local targetY = allowVertical and targetPos.Y or myPos.Y
        
        local lookAtPos = Vector3.new(targetPos.X, targetY, targetPos.Z)
        
        if (lookAtPos - myPos).Magnitude > 0.01 then
            local targetCFrame = CFrame.lookAt(myPos, lookAtPos)
            local lerpAlpha = math.clamp(dt * settings.LerpMin, 0, 1)
            myRoot.CFrame = myRoot.CFrame:Lerp(targetCFrame, lerpAlpha)
        end
    end))
end

-- State-preserving Ragdoll Relock loop 
local wasRagdolled = false
trackActive(RunService.Heartbeat:Connect(function() 
    if not settings.Enabled then return end 
    local ragdolled = isRagdolled() 
    if ragdolled then wasRagdolled = true return end 
    
    if wasRagdolled and not isLockEngaged and lastLockedTarget and lastLockedTarget.Parent then 
        wasRagdolled = false 
        -- Replaced FindFirstChild string-search with direct O(1) table lookup cache
        local tData = rootToData[lastLockedTarget]
        if tData and tData.Humanoid.Health > 0 then 
            startTargetLock(lastLockedTarget) 
        end 
        return 
    end 
    wasRagdolled = false 
end))

-- Input Bindings 
trackActive(UIS.InputBegan:Connect(function(input, gameProcessed) 
    if gameProcessed then return end 
    if input.KeyCode == Enum.KeyCode.C then 
        if isLockEngaged then 
            stopTargetLock() 
        else 
            if myRoot then 
                local target = getTarget(myRoot) 
                if target then startTargetLock(target) end 
            end 
        end 
    end 
end))

-- GUI CONSTRUCTION (Purely Client-Sided, Minimalist Dark Theme)
local screenGui = Instance.new("ScreenGui") 
screenGui.Name = "TargetLock_Gui"
screenGui.ResetOnSpawn = false 
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling 
screenGui.Parent = targetGuiParent

local mainFrame = Instance.new("Frame") 
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 220, 0, 310) 
mainFrame.Position = UDim2.new(0.05, 0, 0.3, 0) 
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25) 
mainFrame.BorderSizePixel = 0 
mainFrame.Active = true
mainFrame.Draggable = true 
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner") 
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = mainFrame

local title = Instance.new("TextLabel") 
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1 
title.Text = "TARGET LOCK CONFIG" 
title.TextColor3 = Color3.fromRGB(240, 240, 240) 
title.Font = Enum.Font.SourceSansBold
title.TextSize = 16 
title.Parent = mainFrame

local function createToggle(name, text, position, default, callback) 
    local btn = Instance.new("TextButton") 
    btn.Name = name 
    btn.Size = UDim2.new(0, 190, 0, 30)
    btn.Position = position 
    btn.BackgroundColor3 = default and Color3.fromRGB(45, 110, 45) or Color3.fromRGB(110, 45, 45) 
    btn.Text = text .. ": " .. (default and "ON" or "OFF") 
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.SourceSansSemibold 
    btn.TextSize = 14 
    btn.BorderSizePixel = 0 
    btn.Parent = mainFrame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = btn

    btn.MouseButton1Click:Connect(function()
        local state = not settings[name]
        settings[name] = state
        btn.BackgroundColor3 = state and Color3.fromRGB(45, 110, 45) or Color3.fromRGB(110, 45, 45)
        btn.Text = text .. ": " .. (state and "ON" or "OFF")
        callback(state)
    end)
end

local function createTextBox(name, labelText, position, default, callback) 
    local label = Instance.new("TextLabel") 
    label.Size = UDim2.new(0, 100, 0, 30)
    label.Position = position 
    label.BackgroundTransparency = 1 
    label.Text = labelText 
    label.TextColor3 = Color3.fromRGB(180, 180, 180) 
    label.Font = Enum.Font.SourceSans 
    label.TextSize = 14 
    label.TextXAlignment = Enum.TextXAlignment.Left 
    label.Position = position + UDim2.new(0, 15, 0, 0)
    label.Parent = mainFrame

    local box = Instance.new("TextBox")
    box.Name = name
    box.Size = UDim2.new(0, 80, 0, 25)
    box.Position = position + UDim2.new(0, 110, 0, 2)
    box.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.Text = tostring(default)
    box.Font = Enum.Font.SourceSans
    box.TextSize = 14
    box.BorderSizePixel = 0
    box.Parent = mainFrame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = box

    box.FocusLost:Connect(function(enterPressed)
        local val = tonumber(box.Text)
        if val then
            settings[name] = val
            callback(val)
        else
            box.Text = tostring(settings[name])
        end
    end)
end

-- Populate GUI Layout Elements dynamically 
createToggle("Enabled", "System Master", UDim2.new(0, 15, 0, 40), settings.Enabled, function(state) 
    if not state then stopTargetLock() end 
end)

createToggle("HighlightVisible", "Target Highlight", UDim2.new(0, 15, 0, 75), settings.HighlightVisible, function(state) 
    if isLockEngaged and currentLockedTarget then startTargetLock(currentLockedTarget) end 
end)

createToggle("CamLock", "Camera Tracking", UDim2.new(0, 15, 0, 110), settings.CamLock, function(state) 
    if state and isLockEngaged and currentLockedTarget then startCamLock(currentLockedTarget) else stopCamLock() end 
end)

createTextBox("Radius", "Aim Radius:", UDim2.new(0, 0, 0, 150), settings.Radius, function() end) 
createTextBox("MaxRange", "Max Distance:", UDim2.new(0, 0, 0, 180), settings.MaxRange, function() end)
createTextBox("Prediction", "Prediction:", UDim2.new(0, 0, 0, 210), settings.Prediction, function() end) 
createTextBox("LerpMin", "Min Lerp Spd:", UDim2.new(0, 0, 0, 240), settings.LerpMin, function() end)
createTextBox("LerpMax", "Max Lerp Spd:", UDim2.new(0, 0, 0, 270), settings.LerpMax, function() end)
