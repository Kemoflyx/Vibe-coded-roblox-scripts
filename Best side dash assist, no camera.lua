-- Replicated Side-Arch Dash (Camera Independent, Orientation Independent)
local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")
local player     = Players.LocalPlayer

-- Tunable values
local COOLDOWN         = 2
local COOLDOWN_W       = 7
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

local onCooldown  = false
local onCooldownW = false

if _G.__dashCleanup then _G.__dashCleanup() end
local cleanupTasks = {}
local activeConns  = {}
local function onCleanup(fn) table.insert(cleanupTasks, fn) end
local function trackActive(c) table.insert(activeConns, c) return c end
_G.__dashCleanup = function()
	for _, fn in ipairs(cleanupTasks) do pcall(fn) end
	cleanupTasks = {}
	for _, c in ipairs(activeConns) do pcall(function() c:Disconnect() end) end
	activeConns = {}
	_G.__dashCleanup = nil
end

local targetCache = {}
local playerConns = {}
local diedConns   = {}

local function addModel(model)
	if model == player.Character then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hrp and hum then
		targetCache[model] = { Root = hrp, Humanoid = hum, prevPos = hrp.Position, velocity = Vector3.zero, smoothedPos = hrp.Position }
		local dc = hum.Died:Connect(function() targetCache[model] = nil end)
		table.insert(diedConns, dc)
	end
end

local function removeModel(model) targetCache[model] = nil end

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
		task.wait(0.1)
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

local VEL_SMOOTH = 0.15
local velTracker = trackActive(RunService.Stepped:Connect(function(_, dt)
	if dt <= 0 then return end
	for _, data in pairs(targetCache) do
		local curPos  = data.Root.Position
		local rawVel  = (curPos - data.prevPos) / dt
		data.velocity    = data.velocity:Lerp(Vector3.new(rawVel.X, 0, rawVel.Z), VEL_SMOOTH)
		data.smoothedPos = data.smoothedPos:Lerp(curPos, 0.35)
		data.prevPos     = curPos
	end
end))
onCleanup(function() velTracker:Disconnect() end)

local function getPredictedPos(targetRoot)
	for _, data in pairs(targetCache) do
		if data.Root == targetRoot then
			local vel = data.velocity
			return targetRoot.Position + Vector3.new(vel.X, 0, vel.Z) * DIR_LOOKAHEAD
		end
	end
	return targetRoot.Position
end

local function getSmoothedPos(targetRoot)
	for _, data in pairs(targetCache) do
		if data.Root == targetRoot then
			return data.smoothedPos
		end
	end
	return targetRoot.Position
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
	rLockConn = trackActive(RunService.PreRender:Connect(function()
		if rLockPaused then return end
		if isRagdolled() then stopRLock() return end
		local c = player.Character
		if not c then return end
		local r = c:FindFirstChild("HumanoidRootPart")
		if not r then return end
		if not rLockTarget or not rLockTarget.Parent then stopRLock() return end
		local h = c:FindFirstChildOfClass("Humanoid")
		if h then h.AutoRotate = false end
		local myPos   = r.Position
		local predPos = getPredictedPos(rLockTarget)
		local dir     = Vector3.new(predPos.X - myPos.X, 0, predPos.Z - myPos.Z)
		if dir.Magnitude > 0.01 then
			local lc = CFrame.lookAt(myPos, myPos + dir)
			r.CFrame = CFrame.new(myPos) * (lc - lc.Position)
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
	local _char0  = player.Character
	local _root0  = _char0 and _char0:FindFirstChild("HumanoidRootPart")
	local _preSD  = nil
	local _preSK  = Enum.KeyCode.D
	if _root0 and not _holdS0 then
		local _tgt0 = getTarget(_root0, _holdW0 and MAX_RANGE_W or MAX_RANGE)
		if _tgt0 then
			local _sp0 = getPredictedPos(_tgt0)
			local _tp0 = Vector3.new(_sp0.X, _root0.Position.Y, _sp0.Z)
			local _to0 = (_tp0 - _root0.Position)
			if _to0.Magnitude > 0.01 then
				_to0 = _to0.Unit
				_preSD = (workspace.CurrentCamera.CFrame.RightVector:Dot(_to0) >= 0) and 1 or -1
				if _holdW0 then _preSD = -_preSD end
				_preSK = _preSD == -1 and Enum.KeyCode.A or Enum.KeyCode.D
			end
		end
		press(_preSK)
		task.delay(0.015, function() press(Enum.KeyCode.Q) end)
		task.delay(0.06,  function() release(Enum.KeyCode.Q) end)
		task.delay(0.075, function() release(_preSK) end)
	else
		press(Enum.KeyCode.Q)
		task.delay(0.06, function() release(Enum.KeyCode.Q) end)
	end
	local _ragWatchStart = tick()
	local _ragWatchFired = false
	local _ragWatchConn
	_ragWatchConn = RunService.Heartbeat:Connect(function()
		if _ragWatchFired then _ragWatchConn:Disconnect() return end
		if tick() - _ragWatchStart > 0.034 then _ragWatchFired = true _ragWatchConn:Disconnect() return end
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
		local conn
		conn = trackActive(RunService.PreRender:Connect(function()
			if isRagdolled() then conn:Disconnect() if hum then hum.AutoRotate = true end return end
			if tick() - startTime >= FACING_LINGER then
				conn:Disconnect()
				if hum then hum.AutoRotate = true end
				return
			end
			applyFacing(root, hum, target)
		end))
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

	local initPred   = getPredictedPos(target)
	local initTarget = Vector3.new(initPred.X, startPos.Y, initPred.Z)
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
		if hum then hum.AutoRotate = false end
		rLockPaused = true
	local yVel = 0  -- track Y velocity for gravity during tween
	local GRAVITY = -196.2  -- studs/s^2 (Roblox default workspace gravity)

		-- Estimate initial total length for progress tracking
		local initPerp2 = Vector3.new(-initTo.Z, 0, initTo.X)
		local initFinal = initTarget + initPerp2 * sideDirection * W_SIDE_OFFSET + initTo * W_FORWARD_OFFSET
		local totalLen  = (initFinal - startPos).Magnitude

		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			if isRagdolled() then connection:Disconnect() if hum then hum.AutoRotate = true end rLockPaused = false return end

			-- Recompute destination only when target moves meaningfully (saves fps)
			local livePos    = getPredictedPos(target)
			local liveTarget = Vector3.new(livePos.X, startPos.Y, livePos.Z)
			local liveToTgt  = (liveTarget - startPos)
			if liveToTgt.Magnitude < 0.01 then return end
			local liveTo   = liveToTgt.Unit
			local livePerp = Vector3.new(-liveTo.Z, 0, liveTo.X)
			local finalPos = liveTarget + livePerp * sideDirection * W_SIDE_OFFSET + liveTo * W_FORWARD_OFFSET
			if (finalPos - initFinal).Magnitude > 0.5 then
				totalLen  = (finalPos - startPos).Magnitude
				initFinal = finalPos
			end

			yVel = yVel + GRAVITY * dt
			traveled = traveled + speed * dt
			if traveled >= totalLen then
				connection:Disconnect()
				local lingerStart = tick()
				local currentDir  = root.CFrame.LookVector
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
					local myPos = root.Position
					local dir2  = Vector3.new(target.Position.X - myPos.X, 0, target.Position.Z - myPos.Z)
					if dir2.Magnitude > 0.01 then
						currentDir = currentDir:Lerp(dir2.Unit, 1 - (0.0001 ^ ldt))
						local lookCFrame = CFrame.lookAt(myPos, myPos + currentDir)
						root.CFrame = CFrame.new(myPos) * (lookCFrame - lookCFrame.Position)
					end
				end))
						return
			end

			-- Move along line toward live final pos
			local moveDir = (finalPos - startPos)
			if moveDir.Magnitude > 0.01 then moveDir = moveDir.Unit end
			local pos = startPos + moveDir * traveled
			local newY = root.Position.Y + yVel * dt
			root.CFrame = CFrame.new(
				Vector3.new(pos.X, newY, pos.Z),
				Vector3.new(pos.X + moveDir.X, newY, pos.Z + moveDir.Z)
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
			if isRagdolled() then facingConn:Disconnect() if hum then hum.AutoRotate = true end return end
			applyFacing(root, hum, target)
		end))

		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			if isRagdolled() then connection:Disconnect() facingConn:Disconnect() if hum then hum.AutoRotate = true end return end

			-- Rebuild arc only when target moves meaningfully (saves fps)
			local livePos    = getPredictedPos(target)
			local liveTarget = Vector3.new(livePos.X, startPos.Y, livePos.Z)
			local liveToTgt  = (liveTarget - startPos)
			if liveToTgt.Magnitude > 0.01 then
				local liveTo    = liveToTgt.Unit
				local livePerp  = Vector3.new(-liveTo.Z, 0, liveTo.X)
				local liveFinal = liveTarget + liveTo * ARCH_OVERSHOOT
				local liveMid   = (startPos + liveFinal) / 2 + livePerp * archWidth * sideDirection
				if (liveFinal - initFinal).Magnitude > 0.5 then
					arcTable, totalLen = buildArcTable(startPos, liveMid, liveFinal)
					initFinal = liveFinal
				end
			end

			if traveled >= totalLen then
				connection:Disconnect()
				facingConn:Disconnect()
				local lingerStart = tick()
				local lingerConn
				lingerConn = trackActive(RunService.PreRender:Connect(function()
					if isRagdolled() then lingerConn:Disconnect() if hum then hum.AutoRotate = true end return end
					if hum then hum.AutoRotate = false end
					if tick() - lingerStart >= FACING_LINGER then
						lingerConn:Disconnect()
						if hum then hum.AutoRotate = true end
						return
					end
					applyFacing(root, hum, target)
				end))
				return
			end
			yVel = yVel + GRAVITY * dt
			traveled = traveled + speed * dt
			local t        = arcLenToT(arcTable, math.min(traveled, totalLen))
			local livePos2 = getPredictedPos(target)
			local liveTgt2 = Vector3.new(livePos2.X, startPos.Y, livePos2.Z)
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
	end) -- end ragdoll watcher
end

local c5 = trackActive(UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode ~= Enum.KeyCode.Unknown then keysHeld[input.KeyCode] = true end
	if input.KeyCode == Enum.KeyCode.E then
		activate()
	elseif input.KeyCode == Enum.KeyCode.C then
		if rLockActive then
			lastRLockTarget = nil  -- manual unlock clears memory
			stopRLock()
		else
			local char = getCharacter()
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local target = getTarget(root, math.huge)
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
