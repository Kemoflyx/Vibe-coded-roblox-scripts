-- Replicated Side-Arch Dash (Camera Independent, Orientation Independent)
local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")
local player     = Players.LocalPlayer

-- Tunable values
local COOLDOWN         = 2      -- normal side dash cooldown (seconds)
local COOLDOWN_W       = 5      -- W front dash cooldown (seconds)
local MAX_RANGE        = 30     -- normal side dash max target range (studs)
local MAX_RANGE_W      = 35     -- W front dash max target range (studs)
local DASH_SPEED       = 115    -- normal side arch movement speed
local DASH_SPEED_W     = 100    -- W held front dash movement speed
local STEPS            = 20     -- arc resolution (higher = smoother curve)
local DIR_LOOKAHEAD    = 0.10   -- prediction window for tween destination and facing (seconds)
local FACING_LINGER    = 1      -- how long character keeps facing target after dash (seconds)
local ARCH_WIDTH_MIN   = 6      -- minimum side dash arc width (studs)
local ARCH_WIDTH_MAX   = 14     -- maximum side dash arc width at full range (studs)
local ARCH_OVERSHOOT   = 4      -- how far past target the arc endpoint extends (studs)
local W_SIDE_OFFSET    = 4.5    -- W dash lateral offset from target (studs)
local W_FORWARD_OFFSET = 1      -- W dash forward offset past target (studs)

local onCooldown  = false
local onCooldownW = false

-- Cleanup previous instance on re-execute
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

-- Target cache
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

-- Velocity tracker: exponential moving average smooths out per-frame noise
-- so prediction and facing don't jitter when the target's replicated position twitches
local VEL_SMOOTH = 0.15  -- lower = smoother but more lag, higher = more reactive
local velTracker = trackActive(RunService.Stepped:Connect(function(_, dt)
	if dt <= 0 then return end
	for _, data in pairs(targetCache) do
		local curPos  = data.Root.Position
		local rawVel  = (curPos - data.prevPos) / dt
		data.velocity    = data.velocity:Lerp(Vector3.new(rawVel.X, 0, rawVel.Z), VEL_SMOOTH)
		data.smoothedPos = data.smoothedPos:Lerp(curPos, 0.35)  -- smooths out network interpolation noise
		data.prevPos     = curPos
	end
end))
onCleanup(function() velTracker:Disconnect() end)

-- Returns predicted position DIR_LOOKAHEAD seconds ahead, XZ only
local function getPredictedPos(targetRoot)
	for _, data in pairs(targetCache) do
		if data.Root == targetRoot then
			local vel = data.velocity
			return targetRoot.Position + Vector3.new(vel.X, 0, vel.Z) * DIR_LOOKAHEAD
		end
	end
	return targetRoot.Position
end

-- Returns the smoothed position of a target root, damping network interpolation noise
local function getSmoothedPos(targetRoot)
	for _, data in pairs(targetCache) do
		if data.Root == targetRoot then
			return data.smoothedPos
		end
	end
	return targetRoot.Position
end

-- Helpers
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

-- Facing uses real position — prediction is only for the one-time tween destination,
-- not per-frame facing (per-frame prediction causes jitter as velocity fluctuates)
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

-- Dash
local function activate(holdingW, holdingS)

	if holdingS then
		local char = getCharacter()
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local target = getTarget(root, math.huge)
		if not target then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		press(Enum.KeyCode.Q)
		task.delay(0.06, function() release(Enum.KeyCode.Q) end)
		local startTime = tick()
		local conn
		conn = trackActive(RunService.PreRender:Connect(function()
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

	-- Tween destination uses predicted position
	local rawTargetPos  = getPredictedPos(target)
	local startPos      = root.Position
	local targetPos     = Vector3.new(rawTargetPos.X, startPos.Y, rawTargetPos.Z)
	local toTarget      = (targetPos - startPos).Unit
	local distance      = (targetPos - startPos).Magnitude
	local perp          = Vector3.new(-toTarget.Z, 0, toTarget.X)
	local sideDirection = ((root.CFrame.RightVector):Dot(toTarget) >= 0) and 1 or -1
	if holdingW then sideDirection = -sideDirection end
	local sideKey = sideDirection == -1 and Enum.KeyCode.A or Enum.KeyCode.D

	press(sideKey)
	task.wait(0.015)
	press(Enum.KeyCode.Q)
	task.delay(0.06,  function() release(Enum.KeyCode.Q) end)
	task.delay(0.075, function() release(sideKey) end)

	local speed    = holdingW and DASH_SPEED_W or DASH_SPEED
	local traveled = 0
	local connection

	if holdingW then
		local finalPos = targetPos + perp * sideDirection * W_SIDE_OFFSET + toTarget * W_FORWARD_OFFSET
		local totalLen = (finalPos - startPos).Magnitude
		local moveDir  = (finalPos - startPos).Unit
		if hum then hum.AutoRotate = false end
		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			traveled = traveled + speed * dt
			if traveled >= totalLen then
				connection:Disconnect()
				local lingerStart = tick()
				local currentDir  = root.CFrame.LookVector
				local lingerConn
				lingerConn = trackActive(RunService.PreRender:Connect(function(ldt)
					if hum then hum.AutoRotate = false end
					if tick() - lingerStart >= FACING_LINGER then
						lingerConn:Disconnect()
						if hum then hum.AutoRotate = true end
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
			local pos = startPos + moveDir * traveled
			root.CFrame = CFrame.new(
				Vector3.new(pos.X, root.Position.Y, pos.Z),
				Vector3.new(pos.X + moveDir.X, root.Position.Y, pos.Z + moveDir.Z)
			)
		end))
	else
		local archWidth = ARCH_WIDTH_MIN + (distance / MAX_RANGE) * (ARCH_WIDTH_MAX - ARCH_WIDTH_MIN)
		local finalPos  = targetPos + toTarget * ARCH_OVERSHOOT
		local midpoint  = (startPos + finalPos) / 2 + perp * archWidth * sideDirection
		local arcTable, totalLen = buildArcTable(startPos, midpoint, finalPos)
		local facingConn
		facingConn = trackActive(RunService.PreRender:Connect(function()
			applyFacing(root, hum, target)
		end))
		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			if traveled >= totalLen then
				connection:Disconnect()
				facingConn:Disconnect()
				local lingerStart = tick()
				local lingerConn
				lingerConn = trackActive(RunService.PreRender:Connect(function()
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
			traveled = traveled + speed * dt
			local t        = arcLenToT(arcTable, math.min(traveled, totalLen))
			local curvePos = quadBezier(startPos, midpoint, finalPos, t)
			root.CFrame = CFrame.new(Vector3.new(curvePos.X, root.Position.Y, curvePos.Z)) * (root.CFrame - root.CFrame.Position)
		end))
	end

	task.delay(holdingW and COOLDOWN_W or COOLDOWN, function()
		if holdingW then onCooldownW = false else onCooldown = false end
	end)
end

-- Track all movement keys ourselves so state is never stale
local keysHeld = {}
local c5 = trackActive(UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	keysHeld[input.KeyCode] = true
	if input.KeyCode == Enum.KeyCode.E then
		activate(keysHeld[Enum.KeyCode.W] == true, keysHeld[Enum.KeyCode.S] == true)
	end
end))
local c6 = trackActive(UIS.InputEnded:Connect(function(input)
	keysHeld[input.KeyCode] = false
end))
onCleanup(function() c5:Disconnect() end)
onCleanup(function() c6:Disconnect() end)

