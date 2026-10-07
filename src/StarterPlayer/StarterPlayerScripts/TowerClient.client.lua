--[[
	TOWER OF FOOD - player screen UI
	Where it goes: StarterPlayer > StarterPlayerScripts  (type: LocalScript)

	Builds the timer, coins/level panel, coin shop and pop-up messages,
	and makes the Jelly Bounce pads launch you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("TowerOfFood")
local notifyEvent = shared:WaitForChild("Notify")
local buyFunction = shared:WaitForChild("BuyItem")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(255, 150, 40)
local DARK = Color3.fromRGB(45, 32, 25)

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------
local function make(className, props)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

local function outline(parent, thickness, color)
	make("UIStroke", { Thickness = thickness or 2, Color = color or Color3.new(0, 0, 0), Parent = parent })
end

local function formatCoins(n)
	if n % 1 == 0 then
		return tostring(math.floor(n))
	end
	return string.format("%.1f", n)
end

local gui = make("ScreenGui", {
	Name = "TowerOfFoodUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

------------------------------------------------------------------------
-- Round timer (top middle)
------------------------------------------------------------------------
local timerFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(200, 60),
	BackgroundColor3 = ORANGE,
	Parent = gui,
})
corner(timerFrame, 14)
outline(timerFrame, 3, Color3.fromRGB(120, 60, 0))
local timerLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0.62, 0),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "0:00",
	Parent = timerFrame,
})
outline(timerLabel, 2)
make("TextLabel", {
	Position = UDim2.fromScale(0.05, 0.6),
	Size = UDim2.fromScale(0.9, 0.32),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 240, 210),
	Text = "until the tower resets",
	Parent = timerFrame,
})

task.spawn(function()
	while true do
		local roundEnd = shared:GetAttribute("RoundEnd")
		if roundEnd then
			local left = math.max(0, math.floor(roundEnd - workspace:GetServerTimeNow()))
			timerLabel.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
			timerFrame.BackgroundColor3 = (left <= 30) and Color3.fromRGB(220, 40, 40) or ORANGE
		end
		task.wait(0.25)
	end
end)

------------------------------------------------------------------------
-- Coins / level panel (left side)
------------------------------------------------------------------------
local stats = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.45, 0),
	Size = UDim2.fromOffset(180, 92),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.1,
	Parent = gui,
})
corner(stats, 14)
local coinsLabel = make("TextLabel", {
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.new(1, -24, 0, 32),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 215, 60),
	Text = "Coins: 0",
	Parent = stats,
})
local levelLabel = make("TextLabel", {
	Position = UDim2.fromOffset(12, 40),
	Size = UDim2.new(1, -24, 0, 22),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = WHITE,
	Text = "Level 1",
	Parent = stats,
})
local xpBack = make("Frame", {
	Position = UDim2.fromOffset(12, 68),
	Size = UDim2.new(1, -24, 0, 14),
	BackgroundColor3 = Color3.fromRGB(20, 15, 10),
	Parent = stats,
})
corner(xpBack, 7)
local xpFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(110, 220, 80),
	Parent = xpBack,
})
corner(xpFill, 7)
local xpText = make("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "0 / 100 XP",
	ZIndex = 2,
	Parent = xpBack,
})
outline(xpText, 1)

local shopButton = make("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.45, 80),
	Size = UDim2.fromOffset(180, 50),
	BackgroundColor3 = ORANGE,
	Font = FONT,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "SHOP",
	Parent = gui,
})
corner(shopButton, 14)
outline(shopButton, 3, Color3.fromRGB(120, 60, 0))

------------------------------------------------------------------------
-- Pop-up messages (bottom middle)
------------------------------------------------------------------------
local toastHolder = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -120),
	Size = UDim2.fromOffset(440, 220),
	BackgroundTransparency = 1,
	Parent = gui,
})
make("UIListLayout", {
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
	Parent = toastHolder,
})
local toastCount = 0

local function toast(text)
	toastCount += 1
	local label = make("TextLabel", {
		Size = UDim2.fromOffset(420, 36),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Text = text,
		LayoutOrder = toastCount,
		Parent = toastHolder,
	})
	corner(label, 10)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = label })
	task.delay(3.5, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		label:Destroy()
	end)
end
notifyEvent.OnClientEvent:Connect(toast)

------------------------------------------------------------------------
-- Coin shop window
------------------------------------------------------------------------
local shopFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.7),
	BackgroundColor3 = Color3.fromRGB(255, 236, 200),
	Visible = false,
	Parent = gui,
})
make("UISizeConstraint", { MaxSize = Vector2.new(460, 380), Parent = shopFrame })
corner(shopFrame, 18)
outline(shopFrame, 4, Color3.fromRGB(120, 60, 0))

local title = make("TextLabel", {
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -80, 0, 44),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = ORANGE,
	Text = "FOOD SHOP",
	Parent = shopFrame,
})
outline(title, 2, Color3.fromRGB(120, 60, 0))

local closeButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = Color3.fromRGB(220, 50, 50),
	Font = FONT,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "X",
	Parent = shopFrame,
})
corner(closeButton, 10)

local list = make("ScrollingFrame", {
	Position = UDim2.fromOffset(12, 60),
	Size = UDim2.new(1, -24, 1, -72),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = shopFrame,
})
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

local items = HttpService:JSONDecode(shared:GetAttribute("ShopItems") or "[]")
local buyButtons = {}

for index, item in ipairs(items) do
	local row = make("Frame", {
		Size = UDim2.new(1, -8, 0, 74),
		BackgroundColor3 = WHITE,
		LayoutOrder = index,
		Parent = list,
	})
	corner(row, 12)
	local swatch = make("Frame", {
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(50, 50),
		BackgroundColor3 = Color3.fromHex(item.Color),
		Parent = row,
	})
	corner(swatch, 25)
	make("TextLabel", {
		Position = UDim2.fromOffset(70, 8),
		Size = UDim2.new(1, -190, 0, 30),
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = DARK,
		Text = item.Name,
		Parent = row,
	})
	make("TextLabel", {
		Position = UDim2.fromOffset(70, 40),
		Size = UDim2.new(1, -190, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(110, 90, 80),
		Text = item.Desc,
		Parent = row,
	})
	local buy = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(100, 46),
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Parent = row,
	})
	corner(buy, 10)
	buyButtons[item.Id] = { Button = buy, Item = item }

	buy.MouseButton1Click:Connect(function()
		if player:GetAttribute("Owned_" .. item.Id) then
			toast("You already own the " .. item.Name .. ". It's in your backpack!")
			return
		end
		local ok, success, message = pcall(function()
			return buyFunction:InvokeServer(item.Id)
		end)
		toast(ok and message or "Shop error, please try again.")
	end)
end

local function refreshShop()
	local coins = player:GetAttribute("Coins") or 0
	for id, entry in pairs(buyButtons) do
		if player:GetAttribute("Owned_" .. id) then
			entry.Button.Text = "OWNED"
			entry.Button.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		else
			entry.Button.Text = formatCoins(entry.Item.Price)
			entry.Button.BackgroundColor3 = (coins >= entry.Item.Price) and Color3.fromRGB(60, 190, 80) or Color3.fromRGB(190, 140, 90)
		end
	end
end

shopButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = not shopFrame.Visible
end)
closeButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

------------------------------------------------------------------------
-- Keep the panel + shop up to date
------------------------------------------------------------------------
local function refreshStats()
	coinsLabel.Text = "Coins: " .. formatCoins(player:GetAttribute("Coins") or 0)
	levelLabel.Text = "Level " .. (player:GetAttribute("Level") or 1)
	local into = player:GetAttribute("LevelXP") or 0
	local need = player:GetAttribute("LevelNeed") or 100
	xpFill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1)
	xpText.Text = into .. " / " .. need .. " XP"
	refreshShop()
end
player.AttributeChanged:Connect(refreshStats)
refreshStats()

------------------------------------------------------------------------
-- Jelly Bounce pads
------------------------------------------------------------------------
local lastBounce = 0

local function hookJelly(part)
	part.Touched:Connect(function(hit)
		local char = player.Character
		if not char or not hit:IsDescendantOf(char) then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root or os.clock() - lastBounce < 0.3 then
			return
		end
		lastBounce = os.clock()
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, part:GetAttribute("Power") or 75, v.Z)
	end)
end

CollectionService:GetInstanceAddedSignal("JellyBounce"):Connect(hookJelly)
for _, part in ipairs(CollectionService:GetTagged("JellyBounce")) do
	hookJelly(part)
end
