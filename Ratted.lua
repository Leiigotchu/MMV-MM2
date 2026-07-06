local shared = odh_shared_plugins
local my_own_section = shared.AddSection("MM2 PERFORMANCE MONITOR")

-- =============================
--  VARIABLES
-- =============================
local isEnabled = false
local isFpsBoostEnabled = false
local updateConnection = nil
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- Cache original lighting settings for FPS Boost reset
local Lighting = game:GetService("Lighting")
local Terrain = game:GetService("Workspace"):FindFirstChildOfClass("Terrain")
local origGlobalShadows = Lighting.GlobalShadows
local origOutdoorAmbient = Lighting.OutdoorAmbient

-- =============================
--  FUNCTION TO CREATE GUI
-- =============================
local function createMonitorGui()
    -- Cleanup any existing GUI
    if _G.Mm2PingGui then _G.Mm2PingGui:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MM2_Performance_Monitor"
    ScreenGui.Parent = game.CoreGui
    _G.Mm2PingGui = ScreenGui

    -- Ping Label
    local PingLabel = Instance.new("TextLabel")
    PingLabel.Parent = ScreenGui
    PingLabel.BackgroundTransparency = 1
    PingLabel.Position = UDim2.new(0.75, 0, 0, 45)
    PingLabel.Size = UDim2.new(0, 180, 0, 25)
    PingLabel.Font = Enum.Font.Code
    PingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    PingLabel.TextSize = 18
    PingLabel.TextXAlignment = Enum.TextXAlignment.Right
    PingLabel.Text = "Ping: ..."

    -- FPS Label (Positioned directly below the Ping)
    local FpsLabel = Instance.new("TextLabel")
    FpsLabel.Parent = ScreenGui
    FpsLabel.BackgroundTransparency = 1
    FpsLabel.Position = UDim2.new(0.75, 0, 0, 65)
    FpsLabel.Size = UDim2.new(0, 180, 0, 25)
    FpsLabel.Font = Enum.Font.Code
    FpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    FpsLabel.TextSize = 18
    FpsLabel.TextXAlignment = Enum.TextXAlignment.Right
    FpsLabel.Text = "FPS: ..."

    -- Update Logic
    local RunService = game:GetService("RunService")

    updateConnection = RunService.RenderStepped:Connect(function(dt)
        if not isEnabled then 
            updateConnection:Disconnect() 
            return 
        end

        -- Calculate Performance-accurate Ping
        local rawPing = math.floor(localPlayer:GetNetworkPing() * 1000)
        PingLabel.Text = "Ping: " .. rawPing .. "ms"
        
        -- Color transitions for Ping: Green for low, White for high
        if rawPing <= 80 then
            PingLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        else
            PingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end

        -- Calculate FPS
        local fps = math.floor(1 / dt)
        FpsLabel.Text = "FPS: " .. fps

        -- Color transitions for FPS: Green for smooth performance, White for drops
        if fps >= 55 then
            FpsLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        else
            FpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end)
end

-- =============================
--  MONITOR TOGGLE
-- =============================
my_own_section:AddToggle("Show MM2 Monitor", function(bool)
    isEnabled = bool
    
    if isEnabled then
        createMonitorGui()
        shared.Notify("Monitor Enabled", 2)
    else
        if _G.Mm2PingGui then
            _G.Mm2PingGui:Destroy()
            _G.Mm2PingGui = nil
        end
        if updateConnection then
            updateConnection:Disconnect()
        end
        shared.Notify("Monitor Disabled", 2)
    end
end)

-- =============================
--  FPS BOOST TOGGLE
-- =============================
my_own_section:AddToggle("FPS Boost", function(bool)
    isFpsBoostEnabled = bool

    if isFpsBoostEnabled then
        -- Lower graphics components instantly across Workspace
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        
        if Terrain then
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 0
        end

        -- Clear heavy individual instances to optimize rendering
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("VisualEffect") or obj:IsA("PostEffect") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                obj.Enabled = false
            elseif obj:IsA("Texture") or obj:IsA("Decal") then
                obj.Transparency = 1
            end
        end
        shared.Notify("FPS Boost Activated", 2)
    else
        -- Restore original engine properties
        Lighting.GlobalShadows = origGlobalShadows
        Lighting.OutdoorAmbient = origOutdoorAmbient
        
        if Terrain then
            Terrain.WaterWaveSize = 0.15
            Terrain.WaterWaveSpeed = 10
            Terrain.WaterReflectance = 1
            Terrain.WaterTransparency = 1
        end

        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("VisualEffect") or obj:IsA("PostEffect") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                obj.Enabled = true
            elseif obj:IsA("Texture") or obj:IsA("Decal") then
                obj.Transparency = 0
            end
        end
        shared.Notify("FPS Boost Deactivated", 2)
    end
end)

-- =============================
--  CREDITS SECTION
-- =============================
my_own_section:AddParagraph("Credits:", "Made by @shadow | Optimized for MM2")
