-- Replicated Side-Arch Dash (Camera Independent, Orientation Independent)
local Players        = game:GetService("Players")
local UIS            = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local VIM            = game:GetService("VirtualInputManager")
local player         = Players.LocalPlayer
local camera         = workspace.CurrentCamera

-- Tunable values
local COOLDOWN         = 2
local COOLDOWN_W       = 6
local MAX_RANGE        = 30
local MAX_RANGE_W      = 35
local DASH_SPEED       = 110
local DASH_SPEED_W     = 100
local STEPS            = 20
local DIR_LOOKAHEAD    = 0.10
local FACING_LINGER    = 1
local ARCH_WIDTH_MIN   = 6
local ARCH_WIDTH_MAX   = 14
local ARCH_OVERSHOOT   = 4
local W_SIDE_OFFSET    = 4.5
local W_FORWARD_OFFSET = 1
local LOCK_AIM_RADIUS  = 500
local C_LOCK_AIM_RADIUS = 100 

-- Camera lock timing (seconds)
local CAM_LOCK_DURATION = 0.55

-- ---------------------------
-- Camera POSITION tunables
-- ---------------------------
local CAM_POS_UP_OFFSET       = 1.4    
local CAM_POS_RIGHT_OFFSET    = 1.1  
local CAM_POS_LEFT_OFFSET     = 0      
local CAM_POS_FORWARD_OFFSET  = 0      
local CAM_POS_BACK_OFFSET     = 0      

local CAM_AIM_SCREEN_RIGHT    = 0      
local CAM_AIM_SCREEN_UP       = 0      

local CAM_FOCUS_MULTIPLIER    = 0.25   
local CAM_FOCUS_MIN           = 0    
local CAM_FOCUS_MAX           = 0    

local CAM_OFFSET_RIGHT        = 1.5   

local CAM_USE_CENTER_AIM      = false   -- Forced false: always use cursor

local QD_RANGE        = 10
local QD_FACE_LINGER  = 0.5
local RAG_WATCH_WINDOW = 0.075
local RAG_WATCH_Q_DELAY = 0.005

-- LERP TUNING (Buttery smooth and responsive tracking, scales dynamically)
local RLOCK_LERP_MIN  = 45     -- Smooth tracking for slower movements
local RLOCK_LERP_MAX  = 45     -- Snappy, fast tracking when the target dashes
local RLOCK_LERP_VEL  = 1

local ARC_REBUILD_THRESHOLD = 0.5
local VEL_SMOOTH_FACTOR = 0.15
local POS_SMOOTH_FACTOR = 0.35
local W_FACE_LERP       = 0.0001
local RLOCK_PRED_TIME   = 0.10   -- Restored back to 0.10 seconds (100ms)
local QD_SIDE_TO_Q     = 0.02
local QD_Q_TO_3       = 0.00
local QD_SK_RELEASE   = 0.05
local QD_SECOND_3     = 0.30

local onCooldown  = false
local onCooldownW = false

if getgenv().__dashCleanup then getgenv().__dashCleanup() end
local cleanupTasks = {}
local activeConns  = {}
local function onCleanup(fn) table.insert(cleanupTasks, fn) end
local function trackActive(c) table.insert(activeConns, c) return c end
getgenv().__dashCleanup = function()
    for _, fn in ipairs(cleanupTasks) do pcall(fn) end
    cleanupTasks = {}
    for _, c in ipairs(activeConns) do pcall(function() c:Disconnect() end) end
    activeConns = {}
    getgenv().__dashCleanup = nil
end

local targetCache = {}
local rootToData  = {}
local playerConns = {}
local diedConns   = {}

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
    if hrp and hum then
        local data = { Root = hrp, Humanoid = hum, prevPos = hrp.Position, velocity = Vector3.zero, smoothedPos = hrp.Position }
        targetCache[model] = data
        rootToData[hrp] = data
        local dc = hum.Died:Connect(function() targetCache[model] = nil rootToData[hrp] = nil end)
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
    table.insert(playerConns[p], p.CharacterAdded:Connect(function(c)
        task.wait(0.5)
        addModel(c)
    end))
    table.insert(playerConns[p], p.CharacterRemoving:Connect(function(c)
        removeModel(c)
    end))
end

for _, model in ipairs(workspace:GetDescendants()) do
    if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
        addModel(model)
    end
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
        if model and model:IsA("Model") and model:FindFirstChild("HumanoidRootPart") then
            addModel(model)
        end
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
    local now = tick()
    if not getgenv().__lastRescan or now - getgenv().__lastRescan < 3 then return end
    getgenv().__lastRescan = now
    for p in pairs(playerConns) do
        if p.Character and not targetCache[p.Character] then
            addModel(p.Character)
        end
    end
end))
getgenv().__lastRescan = tick()

local velTracker = trackActive(RunService.Stepped:Connect(function(_, dt)
    if dt <= 0 then return end
    for _, data in pairs(targetCache) do
        if not data.Root.Parent then continue end
        local curPos  = data.Root.Position
        local rawVel  = (curPos - data.prevPos) / dt
        data.velocity    = data.velocity:Lerp(Vector3.new(rawVel.X, 0, rawVel.Z), VEL_SMOOTH_FACTOR)
        data.smoothedPos = data.smoothedPos:Lerp(curPos, POS_SMOOTH_FACTOR)
        data.prevPos     = curPos
    end
end))
onCleanup(function() velTracker:Disconnect() end)

local function getPredictedPos(targetRoot)
    local data = rootToData[targetRoot]
    if data then
        local vel = data.velocity
        return targetRoot.Position + Vector3.new(vel.X, 0, vel.Z) * DIR_LOOKAHEAD
    end
    return targetRoot.Position
end

local function getSmoothedPos(targetRoot)
    local data = rootToData[targetRoot]
    return data and data.smoothedPos or targetRoot.Position
end

local function isRagdolled()
    local char = player.Character
    if not char then return true end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return true end
    return hum:GetState() == Enum.HumanoidStateType.Physics
end

local function getCharacter() return player.Character or player.CharacterAdded:Wait() end

local function quadBezier(p0, p1, p2, t)
    return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

local function buildArcTable(p0, p1, p2)
    local tbl = { { t = 0, len = 0 } }
    local prev, total = p0, 0
    for i = 1, STEPS do
        local tt   = i / STEPS
        local curr = quadBezier(p0, p1, p2, tt)
        total = total + (curr - prev).Magnitude
        tbl[i + 1] = { t = tt, len = total }
        prev = curr
    end
    return tbl, total
end

local function arcLenToT(tbl, targetLen)
    local lo, hi = 1, #tbl
    while lo < hi - 1 do
        local mid = math.floor((lo + hi) / 2)
        if tbl[mid].len < targetLen then lo = mid else hi = mid end
    end
    local a, b = tbl[lo], tbl[hi]
    if b.len == a.len then return a.t end
    return a.t + (targetLen - a.len) / (b.len - a.len) * (b.t - a.t)
end

local function press(key)   VIM:SendKeyEvent(true,  key, false, game) end
local function release(key) VIM:SendKeyEvent(false, key, false, game) end

-- HIGHLY ACCURATE SELECTOR: Locks strictly within 15px of cursor, fallbacks to Head, prioritizes closest character distance
-- HIGHLY ACCURATE SELECTOR: Locks strictly within cursor radius, fallbacks to Head, prioritizes closest character distance
local function getTarget(root, range, customRadius)
    local currentCamera = workspace.CurrentCamera
    if not currentCamera then return nil end

    -- Determine which radius to use (defaults to the E dash radius if not provided)
    local activeRadius = customRadius or LOCK_AIM_RADIUS

    -- ALWAYS use the cursor location for aiming
    local aimScreen = UIS:GetMouseLocation()

    local closest, closestWorldDist = nil, math.huge
    for model, data in pairs(targetCache) do
        if model.Parent and data.Humanoid.Health > 0 then
            local dist = (data.Root.Position - root.Position).Magnitude
            if dist <= range then
                local targetPos = data.Root.Position
                -- WorldToViewportPoint correctly handles 2D viewport coordinates and matches GetMouseLocation()
                local screenPos, onScreen = currentCamera:WorldToViewportPoint(targetPos)
                
                -- Upwards Fallback: If target's RootPart is slightly off-screen, verify their Head!
                if (not onScreen or screenPos.Z <= 0) and model:FindFirstChild("Head") then
                    targetPos = model.Head.Position
                    screenPos, onScreen = currentCamera:WorldToViewportPoint(targetPos)
                end

                -- Verify they are actually on screen and in front of the lens
                if onScreen and screenPos.Z > 0 then
                    local sd = (Vector2.new(screenPos.X, screenPos.Y) - aimScreen).Magnitude
                    
                    -- Strictly lock only if they are within our active cursor circle
                    if sd <= activeRadius then
                        -- Prioritize the one closest in world distance (studs) to our character
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

-- HELPER: Accurately checks the physical properties of the game to see if vertical aim is allowed.
-- Upgraded to check active combat animation priorities to prevent getting stuck on leaked BodyGyros.
local function checkVerticalAim(root, hum)
    if not root or not hum then return false end
    
    -- Detect if a custom skill/combat animation is playing. 
    -- Roblox default animations are Core or Idle; moves always use Action priority.
    local isCombatActive = false
    local playingTracks = hum:GetPlayingAnimationTracks()
    for _, track in ipairs(playingTracks) do
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
    
    -- If no combat animation is playing, and they aren't natively flying/swimming,
    -- then any BodyGyro left behind is just a ghost/abandoned gyro. Force horizontal!
    if not isCombatActive and not isNativelyAerial then
        return false
    end
    
    -- If combat is active or they are natively flying/swimming, check physical rules
    if root.Anchored or hum.PlatformStand or isNativelyAerial then 
        return true 
    end
    
    for _, v in ipairs(root:GetChildren()) do
        if v:IsA("BodyGyro") then
            if v.MaxTorque.X > 1000 then return true end
        elseif v:IsA("AlignOrientation") then
            if v.AlignType ~= Enum.AlignType.PrimaryAxisParallel and v.MaxTorque > 1000 then 
                return true 
            end
        end
    end
    
    return false
end

-- State-preserving smoothed tracking for Dashes (Immune to Camera Jitter/Drag)
local function applyFacing(root, hum, targetRoot, dt, currentSmoothDir)
    if hum then hum.AutoRotate = false end
    local myPos    = root.Position
    
    -- Dash facing now uses the EXACT SAME prediction as C-Lock
    local _rld = rootToData[targetRoot]
    local predPos = targetRoot.Position + (_rld and Vector3.new(_rld.velocity.X, 0, _rld.velocity.Z) * RLOCK_PRED_TIME or Vector3.zero)
    
    local canAimVertically = checkVerticalAim(root, hum)
    local targetY = canAimVertically and predPos.Y or myPos.Y
    
    local dir = Vector3.new(predPos.X - myPos.X, targetY - myPos.Y, predPos.Z - myPos.Z)
    if dir.Magnitude > 0.01 then
        dir = dir.Unit
        local baseDir = currentSmoothDir or root.CFrame.LookVector
        
        -- Use dynamic speed matching the C-Lock setting (20-45 scale)
        local spd = _rld and _rld.velocity.Magnitude or 0
        local lerpSpeed = math.clamp(RLOCK_LERP_MIN + spd * RLOCK_LERP_VEL, RLOCK_LERP_MIN, RLOCK_LERP_MAX)
        
        local newSmoothDir = baseDir:Lerp(dir, 1 - math.exp(-lerpSpeed * (dt or 1/60)))
        
        -- CRITICAL FIX: Normalize newly calculated smooth direction to prevent magnitude decay!
        if newSmoothDir.Magnitude > 0.001 then
            newSmoothDir = newSmoothDir.Unit
        end
        
        -- Flatten post-lerp just to be 100% safe if horizontal
        if not canAimVertically then
            newSmoothDir = Vector3.new(newSmoothDir.X, 0, newSmoothDir.Z)
            if newSmoothDir.Magnitude > 0.01 then newSmoothDir = newSmoothDir.Unit end
        end

        if newSmoothDir.Magnitude > 0.01 then
            local lookCFrame = CFrame.lookAt(myPos, myPos + newSmoothDir)
            local targetCFrame = CFrame.new(myPos) * (lookCFrame - lookCFrame.Position)
            
            root.CFrame = targetCFrame
            
            for _, v in ipairs(root:GetChildren()) do
                if v:IsA("BodyGyro") then
                    v.CFrame = targetCFrame
                elseif v:IsA("AlignOrientation") and v.Mode == Enum.OrientationAlignmentMode.OneAttachment then
                    v.CFrame = targetCFrame
                end
            end
        end
        return newSmoothDir
    end
    return currentSmoothDir
end

local keysHeld = {}

local rLockActive = false
local rLockPaused = false
local rLockTarget = nil
local rLockConn   = nil
local rHighlight  = nil
local lastRLockTarget = nil

onCleanup(function()
    if rHighlight then rHighlight:Destroy() rHighlight = nil end
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h then h.AutoRotate = true end
end)

local function stopRLock()
    rLockActive = false
    rLockTarget = nil
    if rLockConn then rLockConn:Disconnect() rLockConn = nil end
    if rHighlight then rHighlight:Destroy() rHighlight = nil end
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h then h.AutoRotate = true end
end

local function startRLock(target)
    rLockActive = true
    rLockTarget = target
    lastRLockTarget = target
    local hl = Instance.new("Highlight")
    hl.FillColor         = Color3.fromRGB(255, 255, 255)
    hl.OutlineColor      = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency  = 0.5
    hl.Parent            = target.Parent
    rHighlight = hl
    local smoothDir = nil
    
    rLockConn = trackActive(RunService.PreRender:Connect(function(dt)
        if rLockPaused then return end
        if isRagdolled() then stopRLock() return end
        local c = player.Character
        if not c then return end
        local r = c:FindFirstChild("HumanoidRootPart")
        if not r then return end
        if not rLockTarget or not rLockTarget.Parent then stopRLock() return end
        local h = c:FindFirstChildOfClass("Humanoid")
        
        local canAimVertically = checkVerticalAim(r, h)
        
        if h then h.AutoRotate = false end
        local myPos   = r.Position
        local _rld = rootToData[rLockTarget]
        local predPos = rLockTarget.Position + (_rld and Vector3.new(_rld.velocity.X, 0, _rld.velocity.Z) * RLOCK_PRED_TIME or Vector3.zero)
        
        -- Apply Y targeting ONLY when the game naturally allows it.
        local targetY = canAimVertically and predPos.Y or myPos.Y
        local rawDir  = Vector3.new(predPos.X - myPos.X, targetY - myPos.Y, predPos.Z - myPos.Z)
        
        if rawDir.Magnitude > 0.01 then
            rawDir = rawDir.Unit
            
            -- Keep prediction perfectly horizontal if vertical aiming is restricted
            if not canAimVertically then
                rawDir = Vector3.new(rawDir.X, 0, rawDir.Z).Unit
            end
            
            local _tData = rootToData[rLockTarget]
            local spd = _tData and _tData.velocity.Magnitude or 0
            local lerpSpeed = math.clamp(RLOCK_LERP_MIN + spd * RLOCK_LERP_VEL, RLOCK_LERP_MIN, RLOCK_LERP_MAX)
            if not smoothDir then smoothDir = rawDir end
            
            -- Smooth tracking with dynamic velocity scaling
            smoothDir = smoothDir:Lerp(rawDir, 1 - math.exp(-lerpSpeed * (dt or 1/60)))
            
            -- CRITICAL FIX: Normalize smoothDir to prevent magnitude decay, enabling actual lerp speed control!
            if smoothDir.Magnitude > 0.001 then
                smoothDir = smoothDir.Unit
            end
            
            -- Enforce strict horizontal aim post-lerp
            if not canAimVertically then
                smoothDir = Vector3.new(smoothDir.X, 0, smoothDir.Z)
                if smoothDir.Magnitude > 0.01 then smoothDir = smoothDir.Unit end
            end
            
            if smoothDir.Magnitude > 0.01 then
                local lc = CFrame.lookAt(myPos, myPos + smoothDir)
                local targetCFrame = CFrame.new(myPos) * (lc - lc.Position)
                
                r.CFrame = targetCFrame
                
                -- SILENCE PHYSICS ENGINE TUG-OF-WAR
                for _, v in ipairs(r:GetChildren()) do
                    if v:IsA("BodyGyro") then
                        v.CFrame = targetCFrame
                    elseif v:IsA("AlignOrientation") and v.Mode == Enum.OrientationAlignmentMode.OneAttachment then
                        v.CFrame = targetCFrame
                    end
                end
            end
        end
    end))
end

local wasRagdolled = false
trackActive(RunService.Heartbeat:Connect(function()
    local ragdolled = isRagdolled()
    if ragdolled then
        wasRagdolled = true
        return
    end
    if wasRagdolled and not rLockActive and lastRLockTarget and lastRLockTarget.Parent then
        wasRagdolled = false
        startRLock(lastRLockTarget)
        return
    end
    wasRagdolled = false
end))

local function startCameraLock(root, target)
    local startTime = tick()
    local unlocked  = false
    local stepName  = "__dashCamLock__"

    local rawYGap    = camera.CFrame.Position.Y - root.Position.Y
    local focusOffY  = math.clamp(rawYGap * CAM_FOCUS_MULTIPLIER, CAM_FOCUS_MIN, CAM_FOCUS_MAX) + CAM_POS_UP_OFFSET

    local netRightOffset = CAM_POS_RIGHT_OFFSET - CAM_POS_LEFT_OFFSET
    local netForwardOffset = CAM_POS_FORWARD_OFFSET - CAM_POS_BACK_OFFSET

    local function doUnlock()
        if unlocked then return end
        unlocked = true
        RunService:UnbindFromRenderStep(stepName)
    end

    RunService:BindToRenderStep(stepName, Enum.RenderPriority.Camera.Value + 1, function()
        if tick() - startTime >= CAM_LOCK_DURATION then doUnlock() return end
        local curCF = camera.CFrame

        local lv   = curCF.LookVector
        local hMag = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
        local pitchRad = math.clamp(
            math.atan2(lv.Y, math.max(hMag, 0.001)),
            -1.2, 0.5
        )

        local baseFocusPos = root.Position + Vector3.new(0, focusOffY, 0)

        local toH = Vector3.new(target.Position.X - baseFocusPos.X, 0, target.Position.Z - baseFocusPos.Z)
        if toH.Magnitude <= 0.01 then
            local facingCF = CFrame.lookAt(baseFocusPos, target.Position)
            local rotCF    = facingCF * CFrame.Angles(pitchRad, 0, 0)
            local zoomDist = math.max((curCF.Position - baseFocusPos).Magnitude, 0.5)
            local correctCamPos = baseFocusPos - rotCF.LookVector * zoomDist
            camera.CFrame = rotCF + (correctCamPos - baseFocusPos)
            return
        end

        local forwardDir = toH.Unit
        local rightDir = Vector3.new(-toH.Z, 0, toH.X).Unit

        local focusPos = baseFocusPos
            + rightDir * netRightOffset
            + forwardDir * netForwardOffset

        local toH2 = Vector3.new(target.Position.X - focusPos.X, 0, target.Position.Z - focusPos.Z)
        if toH2.Magnitude > 0.01 then
            if CAM_OFFSET_RIGHT ~= 0 then
                local rightDir2 = Vector3.new(-toH2.Z, 0, toH2.X).Unit
                toH2 = toH2 + rightDir2 * CAM_OFFSET_RIGHT
            end

            local facingCF = CFrame.lookAt(focusPos, focusPos + toH2)
            local rotCF    = facingCF * CFrame.Angles(pitchRad, 0, 0)

            local zoomDist = math.max((curCF.Position - focusPos).Magnitude, 0.5)
            local correctCamPos = focusPos - rotCF.LookVector * zoomDist
            camera.CFrame = rotCF + (correctCamPos - baseFocusPos)
        end
    end)

    return doUnlock
end

local function activate()
    local _holdW0 = keysHeld[Enum.KeyCode.W] == true
    local _holdS0 = keysHeld[Enum.KeyCode.S] == true
    if _holdW0 and onCooldownW then return end
    if not _holdW0 and not _holdS0 and onCooldown then return end
    local _char0  = player.Character
    local _root0  = _char0 and _char0:FindFirstChild("HumanoidRootPart")
    local _preSD  = nil
    local _preSK  = Enum.KeyCode.D
    local _noKeys = not _holdW0 and not _holdS0 and not keysHeld[Enum.KeyCode.A] and not keysHeld[Enum.KeyCode.D]
    if _root0 and not _holdS0 then
        local _range = _holdW0 and MAX_RANGE_W or MAX_RANGE
        local _tgt0  = getTarget(_root0, _range)
        if not _tgt0 then return end
        if _noKeys then
            local _tp0 = Vector3.new(_tgt0.Position.X, _root0.Position.Y, _tgt0.Position.Z)
            local _to0 = (_tp0 - _root0.Position)
            if _to0.Magnitude > 0.01 then
                _to0 = _to0.Unit
                _preSD = (camera).CFrame.RightVector:Dot(_to0) >= 0 and 1 or -1
                _preSK = _preSD == -1 and Enum.KeyCode.A or Enum.KeyCode.D
            end
            press(_preSK)
            task.delay(QD_SIDE_TO_Q,  function() press(Enum.KeyCode.Q) release(Enum.KeyCode.Q) end)
            task.delay(QD_SK_RELEASE, function() release(_preSK) end)
        else
            press(Enum.KeyCode.Q) release(Enum.KeyCode.Q)
        end
    else
        local _tgt0 = _root0 and getTarget(_root0, math.huge) or nil
        if not _tgt0 then return end
        press(Enum.KeyCode.Q) release(Enum.KeyCode.Q)
    end
    local _ragWatchStart = nil
    local _ragWatchFired = false
    local _ragWatchConn
    task.delay(QD_SIDE_TO_Q + RAG_WATCH_Q_DELAY, function() _ragWatchStart = tick() end)
    _ragWatchConn = trackActive(RunService.Heartbeat:Connect(function()
        if not _ragWatchStart then return end
        if _ragWatchFired then _ragWatchConn:Disconnect() return end
        if tick() - _ragWatchStart > RAG_WATCH_WINDOW then _ragWatchFired = true _ragWatchConn:Disconnect() return end
        if isRagdolled() then return end
        _ragWatchFired = true
        _ragWatchConn:Disconnect()
        local holdingW = _holdW0
        local holdingS = _holdS0

    if holdingS then
        local char = getCharacter()
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local target = getTarget(root, math.huge)
        if not target then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local startTime = tick()
        local sFaceDir = nil
        local conn
        conn = trackActive(RunService.PreRender:Connect(function(dt)
            if isRagdolled() then conn:Disconnect() if hum then hum.AutoRotate = true end return end
            if tick() - startTime >= FACING_LINGER then
                conn:Disconnect()
                if hum then hum.AutoRotate = true end
                return
            end
            sFaceDir = applyFacing(root, hum, target, dt, sFaceDir)
        end))
        local unlockCam = startCameraLock(root, target)
        return
    end

    if holdingW and onCooldownW then return end
    if not holdingW and onCooldown then return end
    local char = getCharacter()
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local target = getTarget(root, holdingW and MAX_RANGE_W or MAX_RANGE)
    if not target then return end
    if holdingW then onCooldownW = true else onCooldown = true end
    local hum = char:FindFirstChildOfClass("Humanoid")

    local startPos = root.Position
    local initTarget = Vector3.new(target.Position.X, startPos.Y, target.Position.Z)
    local initTo     = (initTarget - startPos)
    if initTo.Magnitude < 0.01 then return end
    initTo = initTo.Unit
    local sideDirection = _preSD or (((camera).CFrame.RightVector):Dot(initTo) >= 0) and 1 or -1
    if not _preSD and holdingW then sideDirection = -sideDirection end
    local sideKey = sideDirection == -1 and Enum.KeyCode.A or Enum.KeyCode.D

    local speed    = holdingW and DASH_SPEED_W or DASH_SPEED
    local traveled = 0
    local connection

    if holdingW then
        if hum then hum.AutoRotate = false end
        rLockPaused = true

        local initPerp2 = Vector3.new(-initTo.Z, 0, initTo.X)
        local initFinal = initTarget + initPerp2 * sideDirection * W_SIDE_OFFSET + initTo * W_FORWARD_OFFSET
        local totalLen  = (initFinal - startPos).Magnitude

        connection = trackActive(RunService.Heartbeat:Connect(function(dt)
            if isRagdolled() then connection:Disconnect() if hum then hum.AutoRotate = true end rLockPaused = false return end

            local liveTarget = Vector3.new(target.Position.X, startPos.Y, target.Position.Z)
            local liveToTgt  = (liveTarget - startPos)
            if liveToTgt.Magnitude < 0.01 then return end
            local liveTo   = liveToTgt.Unit
            local livePerp = Vector3.new(-liveTo.Z, 0, liveTo.X)
            local finalPos = liveTarget + livePerp * sideDirection * W_SIDE_OFFSET + liveTo * W_FORWARD_OFFSET
            if (finalPos - initFinal).Magnitude > ARC_REBUILD_THRESHOLD then
                totalLen  = (finalPos - startPos).Magnitude
                initFinal = finalPos
            end

            traveled = traveled + speed * dt
            if traveled >= totalLen then
                connection:Disconnect()
                local lingerStart = tick()
                local lingerFaceDir = nil
                local lingerConn
                lingerConn = trackActive(RunService.PreRender:Connect(function(ldt)
                    if isRagdolled() then lingerConn:Disconnect() if hum then hum.AutoRotate = true end rLockPaused = false return end
                    if hum then hum.AutoRotate = false end
                    if tick() - lingerStart >= FACING_LINGER then
                        lingerConn:Disconnect()
                        if hum then hum.AutoRotate = true end
                        rLockPaused = false
                        return
                    end
                    lingerFaceDir = applyFacing(root, hum, target, ldt, lingerFaceDir)
                end))
                local unlockCam = startCameraLock(root, target)
                return
            end

            local moveDir = (finalPos - startPos)
            if moveDir.Magnitude > 0.01 then moveDir = moveDir.Unit end
            local pos = startPos + moveDir * traveled
            root.CFrame = CFrame.new(
                Vector3.new(pos.X, root.Position.Y, pos.Z),
                Vector3.new(pos.X + moveDir.X, root.Position.Y, pos.Z + moveDir.Z)
            )
        end))
    else
        local distance   = (initTarget - startPos).Magnitude
        local archWidth  = ARCH_WIDTH_MIN + (distance / MAX_RANGE) * (ARCH_WIDTH_MAX - ARCH_WIDTH_MIN)
        local initPerp   = Vector3.new(-initTo.Z, 0, initTo.X)
        local initFinal  = initTarget + initTo * ARCH_OVERSHOOT
        local initMid    = (startPos + initFinal) / 2 + initPerp * archWidth * sideDirection
        local arcTable, totalLen = buildArcTable(startPos, initMid, initFinal)

        local facingConn
        facingConn = trackActive(RunService.PreRender:Connect(function(dt)
            if isRagdolled() then facingConn:Disconnect() if hum then hum.AutoRotate = true end return end
            archFaceDir = applyFacing(root, hum, target, dt, archFaceDir)
        end))
        local unlockCam = startCameraLock(root, target)
        local yVel = 0
        local GRAVITY = -196.2

        connection = trackActive(RunService.Heartbeat:Connect(function(dt)
            if isRagdolled() then connection:Disconnect() facingConn:Disconnect() if hum then hum.AutoRotate = true end return end

            local liveTarget = Vector3.new(target.Position.X, startPos.Y, target.Position.Z)
            local liveToTgt  = (liveTarget - startPos)
            if liveToTgt.Magnitude > 0.01 then
                local liveTo    = liveToTgt.Unit
                local livePerp  = Vector3.new(-liveTo.Z, 0, liveTo.X)
                local liveFinal = liveTarget + liveTo * ARCH_OVERSHOOT
                local liveMid   = (startPos + liveFinal) / 2 + livePerp * archWidth * sideDirection
                if (liveFinal - initFinal).Magnitude > ARC_REBUILD_THRESHOLD then
                    arcTable, totalLen = buildArcTable(startPos, liveMid, liveFinal)
                    initFinal = liveFinal
                end
            end

            if traveled >= totalLen then
                connection:Disconnect()
                facingConn:Disconnect()
                unlockCam()
                unlockCam = startCameraLock(root, target)
                local lingerStart = tick()
                local archLingerDir = nil
                local lingerConn
                lingerConn = trackActive(RunService.PreRender:Connect(function(ldt)
                    if isRagdolled() then lingerConn:Disconnect() if hum then hum.AutoRotate = true end return end
                    if hum then hum.AutoRotate = false end
                    if tick() - lingerStart >= FACING_LINGER then
                        lingerConn:Disconnect()
                        if hum then hum.AutoRotate = true end
                        return
                    end
                    archLingerDir = applyFacing(root, hum, target, ldt, archLingerDir)
                end))
                return
            end
            yVel = yVel + GRAVITY * dt
            traveled = traveled + speed * dt
            local t        = arcLenToT(arcTable, math.min(traveled, totalLen))
            local liveTgt2 = Vector3.new(target.Position.X, startPos.Y, target.Position.Z)
            local liveTo2  = (liveTgt2 - startPos)
            local liveFin2, liveMid2
            if liveTo2.Magnitude > 0.01 then
                liveTo2  = liveTo2.Unit
                local lp2 = Vector3.new(-liveTo2.Z, 0, liveTo2.X)
                liveFin2  = liveTgt2 + liveTo2 * ARCH_OVERSHOOT
                liveMid2  = (startPos + liveFin2) / 2 + lp2 * archWidth * sideDirection
            else
                liveFin2 = initFinal
                liveMid2 = initMid
            end
            local curvePos = quadBezier(startPos, liveMid2, liveFin2, t)
            local newY = root.Position.Y + yVel * dt
            root.CFrame = CFrame.new(Vector3.new(curvePos.X, newY, curvePos.Z)) * (root.CFrame - root.CFrame.Position)
        end))
    end

    task.delay(holdingW and COOLDOWN_W or COOLDOWN, function()
        if holdingW then onCooldownW = false else onCooldown = false end
    end)
    end))
end

local function quickDash()
    if isRagdolled() then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local target = getTarget(root, QD_RANGE)
    if not target then return end

    local tp = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
    local to = (tp - root.Position)
    if to.Magnitude < 0.01 then return end
    to = to.Unit
    local sd = (camera).CFrame.RightVector:Dot(to) >= 0 and 1 or -1
    local sk = sd == -1 and Enum.KeyCode.A or Enum.KeyCode.D

    press(sk)
    task.delay(QD_SIDE_TO_Q,             function() press(Enum.KeyCode.Q) release(Enum.KeyCode.Q) end)
    task.delay(QD_SIDE_TO_Q + QD_Q_TO_3, function() press(Enum.KeyCode.Three) release(Enum.KeyCode.Three) end)
    task.delay(QD_SK_RELEASE,            function() release(sk) end)
    task.delay(QD_SECOND_3,              function() press(Enum.KeyCode.Three) release(Enum.KeyCode.Three) end)

    startCameraLock(root, target)
    local startTime = tick()
    local qdFaceDir = nil
    local conn
    conn = trackActive(RunService.PreRender:Connect(function(dt)
        if isRagdolled() then
            conn:Disconnect()
            if hum then hum.AutoRotate = true end
            return
        end
        if tick() - startTime >= QD_FACE_LINGER then
            conn:Disconnect()
            if hum then hum.AutoRotate = true end
            return
        end
        qdFaceDir = applyFacing(root, hum, target, dt, qdFaceDir)
    end))
end

local c5 = trackActive(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode ~= Enum.KeyCode.Unknown then keysHeld[input.KeyCode] = true end
    if input.KeyCode == Enum.KeyCode.E then
        activate()
    elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
        quickDash()
    elseif input.KeyCode == Enum.KeyCode.C then
        if rLockActive then
            lastRLockTarget = nil
            stopRLock()
        else
            local char = getCharacter()
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                -- Pass the new C_LOCK_AIM_RADIUS here so it doesn't use the E Dash default of 50
                local target = getTarget(root, math.huge, C_LOCK_AIM_RADIUS)
                if target then startRLock(target) end
            end
        end
    end
end))
local c6 = trackActive(UIS.InputEnded:Connect(function(input)
    if input.KeyCode ~= Enum.KeyCode.Unknown then keysHeld[input.KeyCode] = false end
end))
onCleanup(function() c5:Disconnect() end)
onCleanup(function() c6:Disconnect() end)
