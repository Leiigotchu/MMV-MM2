local shared = odh_shared_plugins


local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({_tasks = {}, _destroyed = false}, Maid)
end

function Maid:GiveTask(task)
    if self._destroyed then self:_cleanupTask(task) return end
    table.insert(self._tasks, task)
    return task
end

function Maid:GiveTasks(...)
    for _, t in ipairs({...}) do self:GiveTask(t) end
end

function Maid:_cleanupTask(task)
    local t = typeof(task)
    if t == "RBXScriptConnection" then task:Disconnect()
    elseif t == "Instance" then task:Destroy()
    elseif t == "function" then task()
    elseif t == "table" and type(task.Destroy) == "function" then task:Destroy()
    end
end

function Maid:DoCleaning()
    if self._destroyed then return end
    self._destroyed = true
    for _, task in ipairs(self._tasks) do self:_cleanupTask(task) end
    self._tasks = {}
end

function Maid:Destroy() self:DoCleaning() end

local RootMaid = Maid.new()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local function Notify(title, msg, dur)
    if msg then
        shared.Notify(title .. ": " .. msg, dur or 3)
    else
        shared.Notify(title, dur or 3)
    end
end

local universalSection = shared.AddSection("Universal")

local noclipEnabled     = false
local loopNoclipMaid    = nil
local noclipOnDuration  = 1
local noclipOffDuration = 1
local loopNoclipActive  = false

local function restoreCollision()
    local character = LocalPlayer.Character
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
end

local function setNoclip(state)
    noclipEnabled = state
    if not state then restoreCollision() end
end

local function startNoclipLoop()
    if loopNoclipMaid then loopNoclipMaid:Destroy() end
    loopNoclipMaid = Maid.new()
    Notify("Loop Noclip", "Started (ON " .. noclipOnDuration .. "s / OFF " .. noclipOffDuration .. "s)", 3)
    local thread = task.spawn(function()
        while loopNoclipActive do
            setNoclip(true)
            task.wait(noclipOnDuration)
            if not loopNoclipActive then break end
            setNoclip(false)
            task.wait(noclipOffDuration)
        end
        setNoclip(false)
    end)
    loopNoclipMaid:GiveTask(function()
        task.cancel(thread)
        setNoclip(false)
    end)
end

local noclipSteppedConn = RunService.Stepped:Connect(function()
    if not noclipEnabled then return end
    local character = LocalPlayer.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end)
RootMaid:GiveTask(noclipSteppedConn)

universalSection:AddToggle("Noclip (Always On)", function(enabled)
    setNoclip(enabled)
end)

universalSection:AddLabel("Loop Noclip")
universalSection:AddLabel("Cycles: ON for X sec then OFF for X sec, repeating")

universalSection:AddToggle("Loop Noclip (Activate / Deactivate)", function(enabled)
    loopNoclipActive = enabled
    if enabled then
        startNoclipLoop()
    else
        loopNoclipActive = false
        if loopNoclipMaid then loopNoclipMaid:Destroy() loopNoclipMaid = nil end
        setNoclip(false)
    end
end)

universalSection:AddSlider("Activate Duration (seconds)", 1, 30, 1, function(value)
    noclipOnDuration = value
    if loopNoclipActive then
        startNoclipLoop()
    end
end)

universalSection:AddSlider("Deactivate Duration (seconds)", 1, 30, 1, function(value)
    noclipOffDuration = value
    if loopNoclipActive then
        startNoclipLoop()
    end
end)

universalSection:AddLabel("Changing sliders auto-restarts the loop")

RootMaid:GiveTask(function()
    loopNoclipActive = false
    if loopNoclipMaid then loopNoclipMaid:Destroy() end
    setNoclip(false)
end)

local resetSelPlr      = nil
local selectedPlayers  = {}
local whitelist        = {}
local resetAuraEnabled = false
local auraStuds        = 15
local maxRetries       = 3
local retryDelay       = 0.15

local maids = {
    loopPlr      = nil,
    loopAll      = nil,
    clickReset   = nil,
    resetAura    = nil,
    autoSheriff  = nil,
    autoMurderer = nil,
}

local activeResets = {}

local roleCache = {
    data      = nil,
    timestamp = 0,
    TTL       = 0.8,
}

local function getCachedRoleData()
    local now = tick()
    if roleCache.data and (now - roleCache.timestamp) < roleCache.TTL then
        return roleCache.data
    end
    local ok, result = pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if remote and remote:IsA("RemoteFunction") then
            return remote:InvokeServer()
        end
    end)
    if ok and result then
        roleCache.data      = result
        roleCache.timestamp = now
        return result
    end
    roleCache.timestamp = now
    return roleCache.data
end

local function getMyRole()
    local roleData = getCachedRoleData()
    if not roleData then return nil end
    local data = roleData[LocalPlayer.Name]
    if data then return data.Role end
    return nil
end

local function iAmMurderer() return getMyRole() == "Murderer" end
local function iAmSheriff()  return getMyRole() == "Sheriff"  end

local function canTargetSheriff()
    local role = getMyRole()
    if role == "Murderer" then return false end
    return true
end

local function canTargetMurderer()
    local role = getMyRole()
    if role == "Sheriff" then return false end
    return true
end

local function quickScanSheriff()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local tool = char:FindFirstChild("Gun")
                if tool and tool:IsA("Tool") then return player end
            end
            local bp = player.Backpack
            if bp then
                local tool = bp:FindFirstChild("Gun")
                if tool and tool:IsA("Tool") then return player end
            end
        end
    end
    return nil
end

local function isWhitelisted(player)
    return whitelist[player.UserId] == true
end

local function isPlayerSelected(player)
    for _, sel in ipairs(selectedPlayers) do
        if sel.UserId == player.UserId then return true end
    end
    return false
end

local function touch(a, b)
    pcall(function()
        for _ = 1, 3 do
            firetouchinterest(a, b, 0)
            firetouchinterest(a, b, 1)
        end
    end)
end

local function restoreSelf(character, savedData, originalDestroyHeight)
    if not character or not savedData then
        Workspace.FallenPartsDestroyHeight = originalDestroyHeight
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        Workspace.FallenPartsDestroyHeight = originalDestroyHeight
        return
    end
    Workspace.FallenPartsDestroyHeight = originalDestroyHeight
    rootPart.CFrame = savedData.cframe
    rootPart.AssemblyLinearVelocity  = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    rootPart.Velocity                = Vector3.zero
    rootPart.RotVelocity             = Vector3.zero
    humanoid.PlatformStand = false
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    if humanoid.Health < humanoid.MaxHealth then
        humanoid.Health = humanoid.MaxHealth
    end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = true end
    end
end

local MAX_CONCURRENT_RESETS = 6

local function countActiveResets()
    local count = 0
    for _ in pairs(activeResets) do count += 1 end
    return count
end

local function VoidReset(TargetPlayer, _retryCount)
    if TargetPlayer == LocalPlayer then return end
    if isWhitelisted(TargetPlayer) then return end
    if activeResets[TargetPlayer.UserId] then return end

    _retryCount = _retryCount or 0

    if countActiveResets() >= MAX_CONCURRENT_RESETS then
        task.defer(function()
            task.wait(0.05 * (_retryCount + 1))
            VoidReset(TargetPlayer, _retryCount)
        end)
        return
    end

    local Character = LocalPlayer.Character
    if not Character then return end

    local Humanoid   = Character:FindFirstChildOfClass("Humanoid")
    local RootPart   = Humanoid and Humanoid.RootPart
    local TCharacter = TargetPlayer.Character
    if not (Humanoid and RootPart and TCharacter) then return end

    local TRootPart = TCharacter:FindFirstChild("HumanoidRootPart")
    local THead     = TCharacter:FindFirstChild("Head")
    if not TRootPart then return end

    local touchParts = {}
    local partPriority = {"HumanoidRootPart", "Head", "UpperTorso", "Torso"}
    for _, name in ipairs(partPriority) do
        local p = TCharacter:FindFirstChild(name)
        if p then table.insert(touchParts, p) end
        if #touchParts >= 4 then break end
    end
    if #touchParts == 0 then
        for _, part in ipairs(TCharacter:GetChildren()) do
            if part:IsA("BasePart") then table.insert(touchParts, part) end
        end
    end

    local savedData             = { cframe = RootPart.CFrame }
    local originalDestroyHeight = Workspace.FallenPartsDestroyHeight
    local done                  = false

    Workspace.FallenPartsDestroyHeight = -math.huge
    Humanoid.PlatformStand = true

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.new(0, -200000, 0)
    bv.Parent   = RootPart

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P         = 9e8
    bg.Parent    = RootPart

    local startTime  = tick()
    local RESET_DURATION = 0.35
    local resetObj   = { bv = bv, bg = bg, conn = nil }
    activeResets[TargetPlayer.UserId] = resetObj

    local function cleanup(success)
        if done then return end
        done = true
        activeResets[TargetPlayer.UserId] = nil
        if resetObj.conn then
            resetObj.conn:Disconnect()
            resetObj.conn = nil
        end
        pcall(function() bv:Destroy() end)
        pcall(function() bg:Destroy() end)
        restoreSelf(Character, savedData, originalDestroyHeight)
        if not success and _retryCount < maxRetries then
            task.delay(retryDelay, function()
                if TargetPlayer.Parent and not isWhitelisted(TargetPlayer) then
                    VoidReset(TargetPlayer, _retryCount + 1)
                end
            end)
        end
    end

    local frameCount = 0

    resetObj.conn = RunService.Heartbeat:Connect(function()
        frameCount += 1

        if not TargetPlayer.Character or not TRootPart.Parent then
            cleanup(true)
            return
        end

        if tick() - startTime >= RESET_DURATION then
            cleanup(false)
            return
        end

        if not Character.Parent or not RootPart.Parent then
            cleanup(true)
            return
        end

        local headPos = THead and THead.Position
            or (TRootPart.Position + Vector3.new(0, 2.5, 0))

        RootPart.CFrame                  = CFrame.new(headPos)
        RootPart.AssemblyLinearVelocity  = Vector3.new(0, -200000, 0)
        RootPart.AssemblyAngularVelocity = Vector3.new(15000, 15000, 15000)

        if frameCount % 2 == 1 then
            for _ = 1, 5 do
                for _, part in ipairs(touchParts) do
                    touch(RootPart, part)
                end
            end
        else
            for _ = 1, 3 do
                touch(RootPart, TRootPart)
                if THead then touch(RootPart, THead) end
            end
        end

        pcall(sethiddenproperty, RootPart, "PhysicsRepRootPart", TRootPart)

        if Humanoid.Health < Humanoid.MaxHealth * 0.5 then
            pcall(function() Humanoid.Health = Humanoid.MaxHealth end)
        end
    end)
end

local function findSheriff()
    if not canTargetSheriff() then return nil end

    local quickResult = quickScanSheriff()
    if quickResult and quickResult ~= LocalPlayer and not isWhitelisted(quickResult) then
        return quickResult
    end

    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Sheriff" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= LocalPlayer and not isWhitelisted(p) then return p end
            end
        end
    end
    return nil
end

local function findMurderer()
    if not canTargetMurderer() then return nil end

    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Murderer" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= LocalPlayer and not isWhitelisted(p) then return p end
            end
        end
    end
    return nil
end

local resetSection = shared.AddSection("187 Reset Player v3")

resetSection:AddLabel("Credits: @187")
resetSection:AddLabel("v3 - Role-Aware + Auto Retry + Less Lag")

resetSection:AddButton("Check My Role", function()
    local role = getMyRole()
    Notify("Your Role", role or "Innocent / No Role", 4)
end)

resetSection:AddLabel("Innocent/Spectator/No Role = targets BOTH roles")
resetSection:AddLabel("Murderer = skips Sheriff | Sheriff = skips Murderer")

resetSection:AddButton("Reset Sheriff", function()
    if not canTargetSheriff() then
        Notify("Blocked", "Murderer cannot target Sheriff here", 3)
        return
    end
    local target = findSheriff()
    if target then task.spawn(VoidReset, target)
    else Notify("Error", "No Sheriff / Gun Holder Found", 3) end
end)

resetSection:AddButton("Reset Murderer", function()
    if not canTargetMurderer() then
        Notify("Blocked", "Sheriff cannot target Murderer here", 3)
        return
    end
    local murderer = findMurderer()
    if murderer then task.spawn(VoidReset, murderer)
    else Notify("Error", "No Murderer Found", 3) end
end)

resetSection:AddButton("Reset Both (Sheriff + Murderer)", function()
    local role = getMyRole()
    if role == "Murderer" then
        Notify("Blocked", "You are the Murderer", 3)
        return
    end
    if role == "Sheriff" then
        Notify("Blocked", "You are the Sheriff", 3)
        return
    end
    local sheriff  = findSheriff()
    local murderer = findMurderer()
    if sheriff  then task.spawn(VoidReset, sheriff)  end
    if murderer then task.spawn(VoidReset, murderer) end
    if not sheriff and not murderer then
        Notify("Error", "No targets found", 3)
    end
end)

resetSection:AddButton("Reset All", function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and not isWhitelisted(p) then
            task.spawn(VoidReset, p)
        end
    end
end)

resetSection:AddPlayerDropdown("Reset Player", function(p)
    resetSelPlr = p
    if p and p ~= LocalPlayer and not isWhitelisted(p) then
        task.spawn(VoidReset, p)
    elseif p and isWhitelisted(p) then
        Notify("Whitelist", p.Name .. " is whitelisted!", 3)
    end
end)

resetSection:AddPlayerDropdown("Select Players", function(p)
    if p and p ~= LocalPlayer and not isPlayerSelected(p) then
        table.insert(selectedPlayers, p)
        Notify("Selected", p.Name .. " added to reset list", 3)
    elseif p and isPlayerSelected(p) then
        Notify("Error", p.Name .. " is already selected", 3)
    end
end)

resetSection:AddButton("Clear Selected Players", function()
    selectedPlayers = {}
    Notify("Cleared", "All selected players removed", 3)
end)

resetSection:AddSlider("Max Retries", 0, 5, 3, function(value)
    maxRetries = value
end)

resetSection:AddSlider("Retry Delay (x0.1s)", 1, 10, 2, function(value)
    retryDelay = value * 0.1
end)

resetSection:AddToggle("Auto Reset Sheriff", function(enabled)
    if maids.autoSheriff then maids.autoSheriff:Destroy() end
    if enabled then
        maids.autoSheriff = Maid.new()
        local thread = task.spawn(function()
            while true do
                pcall(function()
                    if canTargetSheriff() then
                        local target = findSheriff()
                        if target then task.spawn(VoidReset, target) end
                    end
                end)
                task.wait(0.25)
            end
        end)
        maids.autoSheriff:GiveTask(function() task.cancel(thread) end)
    end
end)

resetSection:AddToggle("Auto Reset Murderer", function(enabled)
    if maids.autoMurderer then maids.autoMurderer:Destroy() end
    if enabled then
        maids.autoMurderer = Maid.new()
        local thread = task.spawn(function()
            while true do
                pcall(function()
                    if canTargetMurderer() then
                        local target = findMurderer()
                        if target then task.spawn(VoidReset, target) end
                    end
                end)
                task.wait(0.4)
            end
        end)
        maids.autoMurderer:GiveTask(function() task.cancel(thread) end)
    end
end)

resetSection:AddToggle("Loop Reset Player(s)", function(s)
    if maids.loopPlr then maids.loopPlr:Destroy() end
    if s then
        maids.loopPlr = Maid.new()
        local thread = task.spawn(function()
            while true do
                pcall(function()
                    if resetSelPlr and resetSelPlr.Parent and not isWhitelisted(resetSelPlr) then
                        task.spawn(VoidReset, resetSelPlr)
                    end
                    for _, player in ipairs(selectedPlayers) do
                        if player and player.Parent and not isWhitelisted(player) then
                            task.spawn(VoidReset, player)
                        end
                    end
                end)
                task.wait(0.4)
            end
        end)
        maids.loopPlr:GiveTask(function() task.cancel(thread) end)
    end
end)

resetSection:AddToggle("Loop Reset All", function(s)
    if maids.loopAll then maids.loopAll:Destroy() end
    if s then
        maids.loopAll = Maid.new()
        local thread = task.spawn(function()
            while true do
                pcall(function()
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer and p.Parent and not isWhitelisted(p) then
                            task.spawn(VoidReset, p)
                        end
                    end
                end)
                task.wait(0.4)
            end
        end)
        maids.loopAll:GiveTask(function() task.cancel(thread) end)
    end
end)

resetSection:AddToggle("Click Reset", function(enabled)
    if maids.clickReset then maids.clickReset:Destroy() end
    if enabled then
        maids.clickReset = Maid.new()
        local function onInput(input, processed)
            if processed then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                local mouse  = LocalPlayer:GetMouse()
                local target = mouse.Target
                if target then
                    local character = target:FindFirstAncestorWhichIsA("Model")
                    if character then
                        local player = Players:GetPlayerFromCharacter(character)
                        if player and player ~= LocalPlayer and not isWhitelisted(player) then
                            task.spawn(VoidReset, player)
                            Notify("Click Reset", "Resetting " .. player.Name, 2)
                        elseif player and isWhitelisted(player) then
                            Notify("Click Reset", player.Name .. " is whitelisted!", 3)
                        end
                    end
                end
            end
        end
        if UserInputService.TouchEnabled then
            maids.clickReset:GiveTask(UserInputService.TouchTap:Connect(onInput))
        end
        maids.clickReset:GiveTask(UserInputService.InputBegan:Connect(onInput))
    end
end)

resetSection:AddToggle("Reset Aura", function(enabled)
    resetAuraEnabled = enabled
    if maids.resetAura then maids.resetAura:Destroy() end
    if enabled then
        maids.resetAura = Maid.new()
        local thread = task.spawn(function()
            while resetAuraEnabled do
                pcall(function()
                    local character = LocalPlayer.Character
                    local rootPart  = character and character:FindFirstChild("HumanoidRootPart")
                    if rootPart then
                        for _, player in ipairs(Players:GetPlayers()) do
                            if player ~= LocalPlayer and not isWhitelisted(player) then
                                local tc = player.Character
                                local tr = tc and tc:FindFirstChild("HumanoidRootPart")
                                if tr and (rootPart.Position - tr.Position).Magnitude <= auraStuds then
                                    task.spawn(VoidReset, player)
                                end
                            end
                        end
                    end
                end)
                task.wait(0.4)
            end
        end)
        maids.resetAura:GiveTask(function() task.cancel(thread) end)
    end
end)

resetSection:AddSlider("Aura Studs", 5, 50, 15, function(value)
    auraStuds = value
end)

resetSection:AddPlayerDropdown("Add to Whitelist", function(p)
    if p and p ~= LocalPlayer then
        whitelist[p.UserId] = true
        Notify("Whitelist", p.Name .. " added to whitelist", 3)
    end
end)

resetSection:AddButton("Clear Whitelist", function()
    whitelist = {}
    Notify("Whitelist", "Whitelist cleared!", 3)
end)

RootMaid:GiveTask(function()
    for _, m in pairs(maids) do if m then m:Destroy() end end
    for _, r in pairs(activeResets) do
        if r.conn then r.conn:Disconnect() end
        pcall(function() r.bv:Destroy() end)
        pcall(function() r.bg:Destroy() end)
    end
    activeResets = {}
end)

RootMaid:GiveTasks(
    function() if maids.loopPlr      then maids.loopPlr:Destroy()      end end,
    function() if maids.loopAll      then maids.loopAll:Destroy()       end end,
    function() if maids.clickReset   then maids.clickReset:Destroy()    end end,
    function() if maids.resetAura    then maids.resetAura:Destroy()     end end,
    function() if maids.autoSheriff  then maids.autoSheriff:Destroy()   end end,
    function() if maids.autoMurderer then maids.autoMurderer:Destroy()  end end
)

shared.Notify("187 Reset v3 + Universal loaded.", 3)
