-- Replicated Side-Arch Dash (Camera Independent, Orientation Independent)
local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")
local player     = Players.LocalPlayer
local camera     = workspace.CurrentCamera

-- Tunable values
local COOLDOWN         = 2
local COOLDOWN_W       = 6
local MAX_RANGE        = 30
local MAX_RANGE_W      = 35
local DASH_SPEED       = 115
local DASH_SPEED_W     = 100
local STEPS            = 20
local DIR_LOOKAHEAD    = 0.10
local FACING_LINGER    = 1
local ARCH_WIDTH_MIN   = 6
local ARCH_WIDTH_MAX   = 14
local ARCH_OVERSHOOT   = 4
local W_SIDE_OFFSET    = 4.5
local W_FORWARD_OFFSET = 1
local CAM_LOCK_DURATION = 0.55

local QD_RANGE        = 10     -- middle mouse dash max target range (studs)
local QD_FACE_LINGER  = 0.5    -- middle mouse facing linger duration (seconds)
local RAG_WATCH_WINDOW = 0.075  -- ragdoll check window after Q fires (seconds)
local RAG_WATCH_Q_DELAY = 0.005 -- extra wait after Q before starting ragdoll check
local RLOCK_LERP_MIN  = 50     -- C lock min facing lerp speed (standing still)
local RLOCK_LERP_MAX  = 50     -- C lock max facing lerp speed (running)
local RLOCK_LERP_VEL  = 1    -- velocity multiplier for C lock lerp speed
local ARC_REBUILD_THRESHOLD = 0.5 -- studs target must move before arc rebuilds
local VEL_SMOOTH_FACTOR = 0.15   -- velocity smoothing factor for target tracking (lower = smoother)
local POS_SMOOTH_FACTOR = 0.35   -- position smoothing factor for target tracking (lower = smoother)
local W_FACE_LERP       = 0.0001 -- W dash linger facing lerp (lower = slower turn, 0.0001 = very smooth)
local RLOCK_PRED_TIME   = 0.10   -- C lock prediction lookahead time (seconds)
local QD_SIDE_TO_Q     = 0.02   -- seconds between sideKey press and Q (middle mouse dash)
local QD_Q_TO_3       = 0.00   -- seconds between Q and first 3 press
local QD_SK_RELEASE   = 0.05   -- seconds until sideKey releases
local QD_SECOND_3     = 0.30   -- seconds until second 3 press (from sideKey press)

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

-- OPTIMIZATION: Cache local player references so findFirstChild isn't spammed at 144+ FPS
local myChar = nil
local myRoot = nil
local myHum  = nil

local function updateLocalChar(char)
    myChar = char
    myRoot = char and char:WaitForChild("HumanoidRootPart", 5)
    myHum  = char and char:FindFirstChildOfClass("Humanoid")
end

if player.Character then
    updateLocalChar(player.Character)
end

local charAddedConn = player.CharacterAdded:Connect(updateLocalChar)
local charRemovingConn = player.CharacterRemoving:Connect(function()
    myChar, myRoot, myHum = nil, nil, nil
end)
onCleanup(function() charAddedConn:Disconnect() end)
onCleanup(function() charRemovingConn:Disconnect() end)

local targetCache = {}
local rootToData  = {}  -- reverse map: HRP -> data, O(1) lookup
local playerConns = {}
local diedConns   = {}

local function addModel(model)
	if model == player.Character then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	-- Retry until HRP and Humanoid exist (up to 2 seconds)
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


-- Periodic rescan: catches anyone missed due to timing (every 3 seconds)
trackActive(RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if not getgenv().__lastRescan or now - getgenv().__lastRescan < 3 then return end
	getgenv().__lastRescan = now
	for p in pairs(playerConns) do
		if p.Character and not targetCache[p.Character] then
			addModel(p.Character)
		end
	end
end))
getgenv().__lastRescan = os.clock()

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
	if not myChar or not myRoot or not myHum then return true end
	return myHum:GetState() == Enum.HumanoidStateType.Physics
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

local function getTarget(root, range)
	local mousePos = UIS:GetMouseLocation()
	local closest, closestDist = nil, math.huge
	for model, data in pairs(targetCache) do
		if model.Parent and data.Humanoid.Health > 0 then
			local dist = (data.Root.Position - root.Position).Magnitude
			if dist <= range then
				local screenPos = workspace.CurrentCamera:WorldToScreenPoint(data.Root.Position)
				local sd = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
				if sd < closestDist then
					closestDist = sd
					closest = data.Root
				end
			end
		else
			targetCache[model] = nil
		end
	end
	return closest
end

-- PERFORMANCE OPTIMIZATION: Caches vertical checking calculations every 0.05s to protect rendering frames
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
    
    if not isCombatActive and not isNativelyAerial then
        cachedVertResult = false
        return false
    end
    
    if root.Anchored or hum.PlatformStand or isNativelyAerial then 
        cachedVertResult = true
        return true 
    end
    
    for _, v in ipairs(root:GetChildren()) do
        if v:IsA("BodyGyro") then
            if v.MaxTorque.X > 1000 then 
                cachedVertResult = true
                return true 
            end
        elseif v:IsA("AlignOrientation") then
            if v.AlignType ~= Enum.AlignType.PrimaryAxisParallel and v.MaxTorque > 1000 then 
                cachedVertResult = true
                return true 
            end
        end
    end
    
    cachedVertResult = false
    return false
end

local function applyFacing(root, hum, targetRoot)
	if hum then hum.AutoRotate = false end
	local myPos    = root.Position
	local smoothed = getSmoothedPos(targetRoot)
	local dir      = Vector3.new(smoothed.X - myPos.X, 0, smoothed.Z - myPos.Z)
	if dir.Magnitude > 0.01 then
		local lookCFrame = CFrame.lookAt(myPos, myPos + dir)
		root.CFrame = CFrame.new(myPos) * (lookCFrame - lookCFrame.Position)
	end
end

local keysHeld = {}

local rLockActive = false
local rLockPaused = false
local rLockTarget = nil
local rLockConn   = nil
local rHighlight  = nil
local lastRLockTarget = nil  -- remembers target for auto-relock

-- Register stopRLock to run on re-execution
onCleanup(function()
	if rHighlight then rHighlight:Destroy() rHighlight = nil end
	if myHum then myHum.AutoRotate = true end
end)

local function stopRLock()
	rLockActive = false
	rLockTarget = nil
	if rLockConn then rLockConn:Disconnect() rLockConn = nil end
	if rHighlight then rHighlight:Destroy() rHighlight = nil end
	if myHum then myHum.AutoRotate = true end
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
	local smoothDir = nil  -- smoothed facing direction, velocity-weighted lerp
	
    rLockConn = trackActive(RunService.PreRender:Connect(function(dt)
		if rLockPaused then return end
		if isRagdolled() then stopRLock() return end
		if not myChar or not myRoot or not myHum then return end
		if not rLockTarget or not rLockTarget.Parent then stopRLock() return end
        
        -- MATH 1: Added checkVerticalAim functionality back in
		local canAimVertically = checkVerticalAim(myRoot, myHum)
        myHum.AutoRotate = false
        
		local myPos   = myRoot.Position
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
            
			-- Velocity-based lerp speed: faster lerp when target moves fast, min 8 max 20
			local _tData = rootToData[rLockTarget]
			local spd = _tData and _tData.velocity.Magnitude or 0
			local lerpSpeed = math.clamp(RLOCK_LERP_MIN + spd * RLOCK_LERP_VEL, RLOCK_LERP_MIN, RLOCK_LERP_MAX)
			if not smoothDir then smoothDir = rawDir end
			
            smoothDir = smoothDir:Lerp(rawDir, 1 - math.exp(-lerpSpeed * (dt or 1/60)))
            
            -- Normalize newly calculated smooth direction to prevent magnitude decay
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
                
				myRoot.CFrame = targetCFrame
                
                -- SILENCE PHYSICS ENGINE TUG-OF-WAR
                for _, v in ipairs(myRoot:GetChildren()) do
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

-- Auto-relock watcher: if C lock was active and ragdoll clears, relock onto same target
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

-- Dash
local function activate()
	local _holdW0 = keysHeld[Enum.KeyCode.W] == true
	local _holdS0 = keysHeld[Enum.KeyCode.S] == true
	local _preSD  = nil
	local _preSK  = Enum.KeyCode.D
	local _noKeys = not _holdW0 and not _holdS0 and not keysHeld[Enum.KeyCode.A] and not keysHeld[Enum.KeyCode.D]
	if myRoot and not _holdS0 then
		local _range = _holdW0 and MAX_RANGE_W or MAX_RANGE
		local _tgt0  = getTarget(myRoot, _range)
		if not _tgt0 then return end
		if _noKeys then
			local _tp0 = Vector3.new(_tgt0.Position.X, myRoot.Position.Y, _tgt0.Position.Z)
			local _to0 = (_tp0 - myRoot.Position)
			if _to0.Magnitude > 0.01 then
				_to0 = _to0.Unit
				_preSD = workspace.CurrentCamera.CFrame.RightVector:Dot(_to0) >= 0 and 1 or -1
				_preSK = _preSD == -1 and Enum.KeyCode.A or Enum.KeyCode.D
			end
			press(_preSK)
			task.delay(QD_SIDE_TO_Q,               function() press(Enum.KeyCode.Q) release(Enum.KeyCode.Q) end)
			task.delay(QD_SK_RELEASE,              function() release(_preSK) end)
		else
			press(Enum.KeyCode.Q)
			task.delay(0.06, function() release(Enum.KeyCode.Q) end)
		end
	else
		local _tgt0 = myRoot and getTarget(myRoot, math.huge) or nil
		if not _tgt0 then return end
		press(Enum.KeyCode.Q)
		task.delay(0.06, function() release(Enum.KeyCode.Q) end)
	end
	local _ragWatchStart = nil
	local _ragWatchFired = false
	local _ragWatchConn
	-- Start timing from when Q fires so ragdoll cancel has time to register
	task.delay(QD_SIDE_TO_Q + RAG_WATCH_Q_DELAY, function() _ragWatchStart = os.clock() end)
	_ragWatchConn = trackActive(RunService.Heartbeat:Connect(function()
		if not _ragWatchStart then return end
		if _ragWatchFired then _ragWatchConn:Disconnect() return end
		if os.clock() - _ragWatchStart > RAG_WATCH_WINDOW then _ragWatchFired = true _ragWatchConn:Disconnect() return end
		if isRagdolled() then return end
		_ragWatchFired = true
		_ragWatchConn:Disconnect()
		local holdingW = _holdW0
		local holdingS = _holdS0

	if holdingS then
		if not myRoot or not myHum then return end
		local target = getTarget(myRoot, math.huge)
		if not target then return end
		local startTime = os.clock()
		local conn
		conn = trackActive(RunService.PreRender:Connect(function()
			if isRagdolled() then conn:Disconnect() if myHum then myHum.AutoRotate = true end return end
			if os.clock() - startTime >= FACING_LINGER then
				conn:Disconnect()
				if myHum then myHum.AutoRotate = true end
				return
			end
			applyFacing(myRoot, myHum, target)
		end))
		return
	end

	if holdingW and onCooldownW then return end
	if not holdingW and onCooldown then return end
	if not myRoot or not myHum then return end
	local target = getTarget(myRoot, holdingW and MAX_RANGE_W or MAX_RANGE)
	if not target then return end
	if holdingW then onCooldownW = true else onCooldown = true end

	local startPos = myRoot.Position

	local initTarget = Vector3.new(target.Position.X, startPos.Y, target.Position.Z)
	local initTo     = (initTarget - startPos)
	if initTo.Magnitude < 0.01 then return end
	initTo = initTo.Unit
	local sideDirection = ((workspace.CurrentCamera.CFrame.RightVector):Dot(initTo) >= 0) and 1 or -1
	if holdingW then sideDirection = -sideDirection end
	local sideKey = sideDirection == -1 and Enum.KeyCode.A or Enum.KeyCode.D

	local speed    = holdingW and DASH_SPEED_W or DASH_SPEED
	local traveled = 0
	local connection

	if holdingW then
		-- W dash: track target live each frame, always end to their right
		myHum.AutoRotate = false
		rLockPaused = true

		-- Estimate initial total length for progress tracking
		local initPerp2 = Vector3.new(-initTo.Z, 0, initTo.X)
		local initFinal = initTarget + initPerp2 * sideDirection * W_SIDE_OFFSET + initTo * W_FORWARD_OFFSET
		local totalLen  = (initFinal - startPos).Magnitude

		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			if isRagdolled() then connection:Disconnect() if myHum then myHum.AutoRotate = true end rLockPaused = false return end

			-- Recompute destination only when target moves meaningfully (saves fps)
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
				local lingerStart = os.clock()
				local currentDir  = myRoot.CFrame.LookVector
				local lingerConn
				lingerConn = trackActive(RunService.PreRender:Connect(function(ldt)
					if isRagdolled() then lingerConn:Disconnect() if myHum then myHum.AutoRotate = true end rLockPaused = false return end
					if myHum then myHum.AutoRotate = false end
					if os.clock() - lingerStart >= FACING_LINGER then
						lingerConn:Disconnect()
						if myHum then myHum.AutoRotate = true end
						rLockPaused = false
						return
					end
					local myPos = myRoot.Position
					local dir2  = Vector3.new(target.Position.X - myPos.X, 0, target.Position.Z - myPos.Z)
					if dir2.Magnitude > 0.01 then
						currentDir = currentDir:Lerp(dir2.Unit, 1 - (W_FACE_LERP ^ ldt))
						local lookCFrame = CFrame.lookAt(myPos, myPos + currentDir)
						myRoot.CFrame = CFrame.new(myPos) * (lookCFrame - lookCFrame.Position)
					end
				end))
						return
			end

			-- Move along line toward live final pos
			local moveDir = (finalPos - startPos)
			if moveDir.Magnitude > 0.01 then moveDir = moveDir.Unit end
			local pos = startPos + moveDir * traveled
			myRoot.CFrame = CFrame.new(
				Vector3.new(pos.X, myRoot.Position.Y, pos.Z),
				Vector3.new(pos.X + moveDir.X, myRoot.Position.Y, pos.Z + moveDir.Z)
			)
		end))
	else
		-- Side dash: rebuild arc every frame toward live target position
		local distance   = (initTarget - startPos).Magnitude
		local archWidth  = ARCH_WIDTH_MIN + (distance / MAX_RANGE) * (ARCH_WIDTH_MAX - ARCH_WIDTH_MIN)
		local initPerp   = Vector3.new(-initTo.Z, 0, initTo.X)
		local initFinal  = initTarget + initTo * ARCH_OVERSHOOT
		local initMid    = (startPos + initFinal) / 2 + initPerp * archWidth * sideDirection
		local arcTable, totalLen = buildArcTable(startPos, initMid, initFinal)

		local facingConn
	local yVel = 0  -- track Y velocity for gravity during tween
	local GRAVITY = -196.2  -- studs/s^2 (Roblox default workspace gravity)

		facingConn = trackActive(RunService.PreRender:Connect(function()
			if isRagdolled() then facingConn:Disconnect() if myHum then myHum.AutoRotate = true end return end
			applyFacing(myRoot, myHum, target)
		end))

		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			if isRagdolled() then connection:Disconnect() facingConn:Disconnect() if myHum then myHum.AutoRotate = true end return end

			-- Rebuild arc only when target moves meaningfully (saves fps)
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
				local lingerStart = os.clock()
				local lingerConn
				lingerConn = trackActive(RunService.PreRender:Connect(function()
					if isRagdolled() then lingerConn:Disconnect() if myHum then myHum.AutoRotate = true end return end
					if myHum then myHum.AutoRotate = false end
					if os.clock() - lingerStart >= FACING_LINGER then
						lingerConn:Disconnect()
						if myHum then myHum.AutoRotate = true end
						return
					end
					applyFacing(myRoot, myHum, target)
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
			local newY = myRoot.Position.Y + yVel * dt
			myRoot.CFrame = CFrame.new(Vector3.new(curvePos.X, newY, curvePos.Z)) * (myRoot.CFrame - myRoot.CFrame.Position)
		end))
	end

	task.delay(holdingW and COOLDOWN_W or COOLDOWN, function()
		if holdingW then onCooldownW = false else onCooldown = false end
	end)
	end)) -- end ragdoll watcher
end


-- Camera Lock (middle mouse only)
local function startCameraLock(root, target)
	local startTime = os.clock()
	local unlocked  = false
	local stepName  = "__dashCamLock__"

	local lv = camera.CFrame.LookVector
	local hMag = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
	local rawPitch = hMag > 0.001 and (lv.Y / hMag) or 0
	local tanPitch = math.clamp(rawPitch, -2, 0.5)

	local function doUnlock()
		if unlocked then return end
		unlocked = true
		RunService:UnbindFromRenderStep(stepName)
	end

	RunService:BindToRenderStep(stepName, Enum.RenderPriority.Camera.Value + 1, function()
		if os.clock() - startTime >= CAM_LOCK_DURATION then doUnlock() return end
		local camPos = camera.CFrame.Position
		local hDist  = Vector3.new(target.Position.X - camPos.X, 0, target.Position.Z - camPos.Z).Magnitude
		local aimY   = camPos.Y + tanPitch * hDist
		local aimPos = Vector3.new(target.Position.X, aimY, target.Position.Z)
		camera.CFrame = CFrame.new(camPos, aimPos)
	end)

	return doUnlock
end

-- Quick dash (MouseButton3): sideKey+Q + facing, no tween, 0.5s linger, no stack
local function quickDash()
	if isRagdolled() then return end
	if not myRoot or not myHum then return end
	local target = getTarget(myRoot, QD_RANGE)
	if not target then return end  -- out of range: no keys pressed at all

	-- Compute side from camera
	local tp = Vector3.new(target.Position.X, myRoot.Position.Y, target.Position.Z)
	local to = (tp - myRoot.Position)
	if to.Magnitude < 0.01 then return end
	to = to.Unit
	local sd = (workspace.CurrentCamera).CFrame.RightVector:Dot(to) >= 0 and 1 or -1
	local sk = sd == -1 and Enum.KeyCode.A or Enum.KeyCode.D

	press(sk)
	task.delay(QD_SIDE_TO_Q,                   function() press(Enum.KeyCode.Q) release(Enum.KeyCode.Q) end)
	task.delay(QD_SIDE_TO_Q + QD_Q_TO_3,        function() press(Enum.KeyCode.Three) release(Enum.KeyCode.Three) end)
	task.delay(QD_SK_RELEASE,                    function() release(sk) end)
	task.delay(QD_SECOND_3,                      function() press(Enum.KeyCode.Three) release(Enum.KeyCode.Three) end)

	startCameraLock(myRoot, target)
	local startTime = os.clock()
	local conn
	conn = trackActive(RunService.PreRender:Connect(function()
		if isRagdolled() then
			conn:Disconnect()
			if myHum then myHum.AutoRotate = true end
			return
		end
		if os.clock() - startTime >= QD_FACE_LINGER then
			conn:Disconnect()
			if myHum then myHum.AutoRotate = true end
			return
		end
		applyFacing(myRoot, myHum, target)
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
			lastRLockTarget = nil  -- manual unlock clears memory
			stopRLock()
		else
			if myRoot then
				local target = getTarget(myRoot, math.huge)
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
