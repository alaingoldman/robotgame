--!strict
-- DEAD BATTERY screen: when the server flags "BatteryDead" (battery hit 0 away
-- from base -> frozen, no idle recharge) a pulsing "BATTERY DEAD" banner and a
-- big RETURN button appear above the battery bar. RETURN (click, R, gamepad
-- Y) asks the server to teleport you to your pad (Locker "Return"), where it
-- charges fast; you thaw once it passes CoreLoopConfig.Battery.ReviveAt.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fx = require(script.Parent.Fx)

local ReturnUi = {}

local player = Players.LocalPlayer
local lockerRemote = ReplicatedStorage:WaitForChild("CoreRemotes"):WaitForChild("Locker") :: RemoteEvent

local RED = Color3.fromRGB(255, 72, 72)
local BG = Color3.fromRGB(18, 20, 18)
local TEXT = Color3.fromRGB(228, 228, 216)
local GREEN = Color3.fromRGB(88, 226, 104)

local gui: ScreenGui
local frame: Frame
local title: TextLabel
local sub: TextLabel
local button: TextButton
local scale: UIScale
local lastPress = 0

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function stroke(p: Instance, color: Color3, t: number)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = t
	s.Parent = p
end

local function press()
	if os.clock() - lastPress < 0.5 then
		return
	end
	lastPress = os.clock()
	local s = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = button
	s.Scale = 0.88
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Fx.sound("Tick", 0.5, 1.1)
	lockerRemote:FireServer("Return")
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoreReturn"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Enabled = false

	frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -90)
	frame.Size = UDim2.fromOffset(420, 150)
	frame.BackgroundColor3 = BG
	frame.BackgroundTransparency = 0.1
	frame.Parent = gui
	corner(frame, 10)
	stroke(frame, RED, 2)
	scale = Instance.new("UIScale")
	scale.Parent = frame

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 30
	title.TextColor3 = RED
	title.Text = "BATTERY DEAD"
	title.Parent = frame

	sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 44)
	sub.Size = UDim2.new(1, 0, 0, 18)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 13
	sub.TextColor3 = TEXT
	sub.Text = "Your exo is frozen. Return to base to recharge."
	sub.Parent = frame

	button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -14)
	button.Size = UDim2.fromOffset(260, 58)
	button.BackgroundColor3 = Color3.fromRGB(40, 90, 50)
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 26
	button.TextColor3 = TEXT
	button.Text = "RETURN  [R]"
	button.Parent = frame
	corner(button, 8)
	stroke(button, GREEN, 2)
	button.Activated:Connect(press)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function update()
	local dead = player:GetAttribute("BatteryDead") == true
	local inBase = player:GetAttribute("InBase") == true
	if dead and not gui.Enabled then
		Fx.sound("PowerDown", 0.6, 0.9)
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		ContextActionService:BindActionAtPriority("CoreReturnHome", function(_, st)
			if st == Enum.UserInputState.Begin then
				press()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	elseif not dead and gui.Enabled then
		ContextActionService:UnbindAction("CoreReturnHome")
	end
	gui.Enabled = dead
	if dead then
		-- on the pad: just wait for the charge
		button.Visible = not inBase
		sub.Text = if inBase then "Recharging... you can move again soon" else "Your exo is frozen. Return to base to recharge."
	end
end

function ReturnUi.start()
	build()
	player:GetAttributeChangedSignal("BatteryDead"):Connect(update)
	player:GetAttributeChangedSignal("InBase"):Connect(update)
	update()
	RunService.RenderStepped:Connect(function()
		if gui.Enabled then
			local k = 0.5 + 0.5 * math.sin(os.clock() * 6)
			title.TextTransparency = 0.35 * k
			title.TextColor3 = RED:Lerp(Color3.new(1, 1, 1), 0.25 * k)
		end
	end)
end

return ReturnUi
