--[[
	TOWER OF FOOD - player screen (HUD)
	Where it goes: StarterPlayer > StarterPlayerScripts  (type: LocalScript, name: TowerHUD)

	This builds everything you see on your screen, Tower of Hell style:
	  * the big timer (top middle) with messages popping up under it
	  * "Menu" button and your coins (bottom left)
	  * your level, XP bar and skill points (bottom middle)
	  * the tower progress bar with everyone's face on it (right side)
	  * the music player (bottom right)
	  * the Menu: Shop, Trails, Passes, Skills, Codes and Settings
	Nothing else to set up - it is all made by this script.
	Tip: on a computer you can also press M to open the Menu.

	Each part of the screen lives in its own "do ... end" block. A Roblox script
	can only have about 200 "local" names at its top level, so every block keeps
	its little helpers to itself and only shares what other parts need.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The server (TowerGame) makes this folder with everything we need in it
local gameFolder = ReplicatedStorage:WaitForChild("TowerOfFood")
local notifyEvent = gameFolder:WaitForChild("Notify") :: RemoteEvent
local shopAction = gameFolder:WaitForChild("ShopAction") :: RemoteFunction
local skipEvent = gameFolder:WaitForChild("SkipSection") :: RemoteEvent
local promptPassEvent = gameFolder:WaitForChild("PromptPass") :: RemoteEvent

------------------------------------------------------------------------
-- LOOK (safe to change)
------------------------------------------------------------------------
local FONT_BIG = Enum.Font.Sarpanch -- thin sci-fi font for numbers and titles
local FONT_BOLD = Enum.Font.GothamBold
local FONT_TEXT = Enum.Font.GothamMedium

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 196, 46)
local GOLD_DARK = Color3.fromRGB(190, 120, 14)
local XP_PINK = Color3.fromRGB(255, 0, 214)
local TIMER_RED = Color3.fromRGB(255, 45, 45)
local PANEL = Color3.fromRGB(24, 26, 37)
local CARD = Color3.fromRGB(40, 43, 60)
local SOFT_TEXT = Color3.fromRGB(184, 190, 208)
local GREEN = Color3.fromRGB(54, 190, 88)
local DARK_GREEN = Color3.fromRGB(36, 104, 62)
local GREY = Color3.fromRGB(84, 88, 106)
local BLUE = Color3.fromRGB(64, 136, 255)
local RED = Color3.fromRGB(226, 66, 66)
local ORANGE = Color3.fromRGB(255, 146, 40)
local PURPLE = Color3.fromRGB(168, 92, 255)

-- message colours for each kind of server message
local KIND_COLORS: { [string]: Color3 } = {
	coins = Color3.fromRGB(255, 208, 64),
	level = Color3.fromRGB(200, 140, 255),
	win = Color3.fromRGB(100, 232, 124),
	ok = Color3.fromRGB(100, 232, 124),
	error = Color3.fromRGB(255, 96, 96),
	round = Color3.fromRGB(255, 164, 70),
	info = WHITE,
}

-- each player gets one of these line colours on the progress bar
local MARKER_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(250, 230, 60),
	Color3.fromRGB(80, 220, 110),
	Color3.fromRGB(60, 200, 255),
	Color3.fromRGB(110, 120, 255),
	Color3.fromRGB(200, 100, 255),
	Color3.fromRGB(255, 110, 200),
}

local DESIGN_SIZE = Vector2.new(1280, 720) -- the screen is drawn for this size, then scaled to fit
local MENU_W, MENU_H = 680, 440
local LOBBY_PART = 0.07 -- bottom bit of the progress bar = the lobby
local TOP_PART = 0.06 -- gold top bit = the finish
local TOWER_PART = 1 - LOBBY_PART - TOP_PART
local BAR_WIDTH = 12
local SHAFT_RADIUS = 26 -- inside of the tower walls (studs)
local FEET_OFFSET = 3 -- your HumanoidRootPart is about 3 studs above your feet

------------------------------------------------------------------------
-- Little helpers
------------------------------------------------------------------------
local function attrNumber(inst: Instance, name: string, default: number): number
	local value = inst:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return default
end

local function attrString(inst: Instance, name: string, default: string): string
	local value = inst:GetAttribute(name)
	if type(value) == "string" then
		return value
	end
	return default
end

local function attrTrue(inst: Instance, name: string): boolean
	return inst:GetAttribute(name) == true
end

-- Reads one of the server's JSON lists (nil if it's missing or broken)
local function attrJSON(name: string): any
	local raw = gameFolder:GetAttribute(name)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local json: string = raw
	local ok, result = pcall(function(): any
		return HttpService:JSONDecode(json)
	end)
	if ok then
		return result
	end
	warn("[TowerOfFood] Could not read " .. name .. ": " .. tostring(result))
	return nil
end

local function str(value: any, default: string): string
	if type(value) == "string" then
		return value
	elseif type(value) == "number" then
		return tostring(value)
	end
	return default
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	if n and n == n then
		return n
	end
	return default
end

local function hexColor(value: any, default: Color3): Color3
	if type(value) ~= "string" or value == "" then
		return default
	end
	local ok, color = pcall(Color3.fromHex, value)
	if ok then
		return color
	end
	return default
end

-- 12.5 -> "12.5"   26549 -> "26,549"   1234.5 -> "1,234.5"
local function formatNumber(n: number): string
	local tenths = math.floor(math.abs(n) * 10 + 0.5)
	local result = tostring(tenths // 10)
	while true do
		local withComma, count = string.gsub(result, "^(%d+)(%d%d%d)", "%1,%2")
		result = withComma
		if count == 0 then
			break
		end
	end
	local decimal = tenths % 10
	if decimal > 0 then
		result ..= "." .. tostring(decimal)
	end
	if n < 0 then
		result = "-" .. result
	end
	return result
end

-- 378 seconds -> "6:18"
local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function getRoot(who: Player): BasePart?
	local character = who.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function firstLetter(name: string): string
	for _, code in utf8.codes(name) do
		return string.upper(utf8.char(code))
	end
	return "?"
end

------------------------------------------------------------------------
-- UI building helpers
------------------------------------------------------------------------
type Props = { [string]: any }

-- Copies every property onto the instance (Parent goes last)
local function apply<T>(inst: T, props: Props?): T
	if props then
		local parent = props.Parent
		for key, value in pairs(props) do
			if key ~= "Parent" then
				(inst :: any)[key] = value
			end
		end
		if parent then
			(inst :: any).Parent = parent
		end
	end
	return inst
end

local function make(className: string, props: Props?): Instance
	return apply(Instance.new(className), props)
end

-- an invisible box (set BackgroundTransparency to see it)
local function frame(props: Props?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	return apply(f, props)
end

local function text(props: Props?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = FONT_BOLD
	label.TextSize = 18
	label.TextColor3 = WHITE
	label.Text = ""
	return apply(label, props)
end

local function textButton(props: Props?): TextButton
	local button = Instance.new("TextButton")
	button.BorderSizePixel = 0
	button.BackgroundColor3 = GREY
	button.AutoButtonColor = true
	button.Font = FONT_BOLD
	button.TextSize = 18
	button.TextColor3 = WHITE
	button.Text = ""
	return apply(button, props)
end

local function corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

-- makes a box perfectly round (or a pill if it's long)
local function circle(parent: Instance): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

-- soft dark outline so white text is easy to read on bright walls
local function shadow(label: Instance, strength: number?): UIStroke
	return stroke(label, 2, BLACK, 1 - (strength or 0.45))
end

-- outline around a box (instead of around its text)
local function border(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	local s = stroke(parent, thickness, color, transparency)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

local function padding(parent: Instance, left: number, right: number, top: number, bottom: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingTop = UDim.new(0, top)
	p.PaddingBottom = UDim.new(0, bottom)
	p.Parent = parent
	return p
end

local function listLayout(parent: Instance, horizontal: boolean, gap: number, alignX: Enum.HorizontalAlignment?, alignY: Enum.VerticalAlignment?): UIListLayout
	local layoutObject = Instance.new("UIListLayout")
	layoutObject.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layoutObject.SortOrder = Enum.SortOrder.LayoutOrder
	layoutObject.Padding = UDim.new(0, gap)
	layoutObject.HorizontalAlignment = alignX or Enum.HorizontalAlignment.Left
	layoutObject.VerticalAlignment = alignY or Enum.VerticalAlignment.Top
	layoutObject.Parent = parent
	return layoutObject
end

-- A shiny gold coin drawn with boxes (no image needed)
local function coinIcon(props: Props?, size: number): Frame
	local coin = frame({
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 0,
		BackgroundColor3 = GOLD,
	})
	circle(coin)
	stroke(coin, math.max(1, size / 16), GOLD_DARK)
	local ring = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.58),
		Parent = coin,
	})
	circle(ring)
	stroke(ring, math.max(1, size / 14), GOLD_DARK, 0.1)
	local shine = frame({
		Position = UDim2.fromScale(0.2, 0.14),
		Size = UDim2.fromScale(0.26, 0.15),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = WHITE,
		Rotation = -35,
		Parent = coin,
	})
	circle(shine)
	return apply(coin, props)
end

local function makeSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local clickSound = makeSound("rbxasset://sounds/button.wav", 0.3)
local swooshSound = makeSound("rbxasset://sounds/swoosh.wav", 0.3)
local pingSound = makeSound("rbxasset://sounds/electronicpingshort.wav", 0.6)

local function playSound(sound: Sound, speed: number?)
	sound.PlaybackSpeed = speed or 1
	sound.TimePosition = 0
	sound:Play()
end

------------------------------------------------------------------------
-- THE SCREEN
------------------------------------------------------------------------
do
	local oldGui = playerGui:FindFirstChild("TowerOfFoodUI")
	if oldGui then
		oldGui:Destroy()
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "TowerOfFoodUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- stay clear of phone notches
gui.DisplayOrder = 5
gui.Parent = playerGui

local uiScale = 1 -- how big the HUD is drawn (changes with the screen size)
local isTouch = false -- phone / tablet?
local hudScales: { UIScale } = {}

-- One area of the screen. Everything inside is drawn at DESIGN_SIZE and scaled.
local function hudRoot(name: string, anchor: Vector2, position: UDim2, size: Vector2, zIndex: number): Frame
	local root = frame({
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = zIndex,
		Parent = gui,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = root
	table.insert(hudScales, scale)
	return root
end

local topRoot = hudRoot("Top", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), Vector2.new(720, 330), 45)
local bottomLeft = hudRoot("BottomLeft", Vector2.new(0, 1), UDim2.new(0, 14, 1, -12), Vector2.new(330, 150), 2)
local bottomCenter = hudRoot("BottomCenter", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -10), Vector2.new(300, 90), 2)
local bottomRight = hudRoot("BottomRight", Vector2.new(1, 1), UDim2.new(1, -16, 1, -10), Vector2.new(460, 34), 2)
local centerRoot = hudRoot("Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.45), Vector2.new(780, 240), 30)

-- full-screen layer for confetti and flashes (never blocks clicks)
local effectsLayer = frame({
	Name = "Effects",
	Size = UDim2.fromScale(1, 1),
	ZIndex = 50,
	Parent = gui,
})

-- the Menu window (its insides are made by the MENU part near the bottom)
local menuRoot = frame({
	Name = "Menu",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(MENU_W, MENU_H),
	BackgroundTransparency = 0.04,
	BackgroundColor3 = WHITE,
	Active = true,
	Visible = false,
	ZIndex = 40,
	Parent = gui,
})
local menuScale = Instance.new("UIScale")
menuScale.Parent = menuRoot
local menuFit = 1
local menuCrowdsToasts = false -- true on small screens: the Menu reaches up to the timer

local function screenSize(): Vector2
	local size = gui.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		local camera = workspace.CurrentCamera
		if camera then
			size = camera.ViewportSize
		end
	end
	if size.X < 2 or size.Y < 2 then
		size = DESIGN_SIZE
	end
	return size
end

local function detectTouch(): boolean
	local ok, preferred = pcall(function(): boolean
		return UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end)
	if ok then
		return preferred
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

------------------------------------------------------------------------
-- THE TOWER (the server sends a new "Layout" every round)
------------------------------------------------------------------------
type SectionInfo = { Name: string, Creator: string, Color: Color3, BaseY: number, Height: number }
type TowerLayout = { TopY: number, TopBonus: number, BaseY: number, Sections: { SectionInfo } }

local layout: TowerLayout? = nil
local earnedThisRound = 0 -- coins you got since this tower started

local function readLayout(): TowerLayout?
	local data = attrJSON("Layout")
	if type(data) ~= "table" or type(data.Sections) ~= "table" then
		return nil
	end
	local sections: { SectionInfo } = {}
	for _, entry in ipairs(data.Sections) do
		if type(entry) == "table" then
			table.insert(sections, {
				Name = str(entry.Name, "Section"),
				Creator = str(entry.Creator, ""),
				Color = hexColor(entry.Color, Color3.fromRGB(150, 150, 160)),
				BaseY = num(entry.BaseY, 0),
				Height = math.max(1, num(entry.Height, 30)),
			})
		end
	end
	if #sections == 0 then
		return nil
	end
	table.sort(sections, function(a: SectionInfo, b: SectionInfo): boolean
		return a.BaseY < b.BaseY
	end)
	local first = sections[1]
	local last = sections[#sections]
	return {
		TopY = math.max(num(data.TopY, last.BaseY + last.Height), first.BaseY + 1),
		TopBonus = num(data.TopBonus, 100),
		BaseY = first.BaseY,
		Sections = sections,
	}
end

-- These are filled in by the MENU and SCREEN FIT parts further down
local openMenu: (tab: string?) -> () = function(_tab: string?) end
local toggleMenu: () -> () = function() end
local refreshMenu: () -> () = function() end
local relayout: () -> () = function() end

------------------------------------------------------------------------
-- MESSAGES ("toasts") under the timer
------------------------------------------------------------------------
local toast: (message: string, kind: string) -> ()
local placeToasts: (overTimer: boolean) -> ()
do
	local TOAST_TEXT = 17
	local MAX_TOASTS = 4
	local holder = frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 68),
		Size = UDim2.fromOffset(720, 250),
		ZIndex = 2, -- above the timer when they overlap
		Parent = topRoot,
	})
	listLayout(holder, false, 6, Enum.HorizontalAlignment.Center, nil)

	-- normally under the timer; on small screens with the Menu open they cover the timer instead
	function placeToasts(overTimer: boolean)
		holder.Position = UDim2.new(0.5, 0, 0, if overTimer then 0 else 68)
	end

	local count = 0
	local live: { TextLabel } = {}

	local function remove(label: TextLabel)
		local index = table.find(live, label)
		if index then
			table.remove(live, index)
		end
		label:Destroy()
	end

	function toast(message: string, kind: string)
		local color = KIND_COLORS[kind] or WHITE
		count += 1
		local bounds = TextService:GetTextSize(message, TOAST_TEXT, FONT_BOLD, Vector2.new(560, 1000))
		local label = text({
			Name = "Toast",
			Size = UDim2.fromOffset(math.ceil(bounds.X) + 36, math.ceil(bounds.Y) + 14),
			BackgroundTransparency = 1,
			BackgroundColor3 = Color3.fromRGB(14, 15, 22),
			TextSize = TOAST_TEXT,
			TextColor3 = color,
			TextTransparency = 1,
			TextWrapped = true,
			Text = message,
			LayoutOrder = count,
			Parent = holder,
		})
		corner(label, 14)
		local edge = border(label, 1.5, color, 1)
		table.insert(live, label)
		while #live > MAX_TOASTS do
			remove(live[1])
		end

		local showInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, showInfo, { TextTransparency = 0, BackgroundTransparency = 0.3 }):Play()
		TweenService:Create(edge, showInfo, { Transparency = 0.45 }):Play()

		task.delay(3.5, function()
			if not label.Parent then
				return
			end
			local hideInfo = TweenInfo.new(0.45)
			TweenService:Create(label, hideInfo, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			TweenService:Create(edge, hideInfo, { Transparency = 1 }):Play()
			task.wait(0.5)
			remove(label)
		end)
	end
end

------------------------------------------------------------------------
-- BIG ANNOUNCEMENTS: you won! / level up! / new tower!
------------------------------------------------------------------------
local queueAnnouncement: (kind: string, title: string) -> ()
local levelFlash: () -> ()
local showTowerBanner: (title: string) -> ()
do
	-- something that fades in/out: which property, and its value when shown
	type FadeItem = { Inst: Instance, Prop: string, Shown: number }

	local function fadeItem(inst: Instance, prop: string, shown: number): FadeItem
		return { Inst = inst, Prop = prop, Shown = shown }
	end

	local function fadeItems(items: { FadeItem }, shown: boolean, seconds: number)
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, item in ipairs(items) do
			local goal: { [string]: number } = {}
			goal[item.Prop] = if shown then item.Shown else 1
			TweenService:Create(item.Inst, info, goal):Play()
		end
	end

	-- colourful paper pieces falling down the screen
	local function confetti()
		local size = screenSize()
		for _ = 1, 70 do
			local piece = frame({
				Size = UDim2.fromOffset(math.random(6, 11) * uiScale, math.random(10, 17) * uiScale),
				Position = UDim2.fromOffset(math.random() * size.X, -20 - math.random() * size.Y * 0.35),
				Rotation = math.random(0, 360),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromHSV(math.random(), 0.7, 1),
				Parent = effectsLayer,
			})
			local fallTime = 1.6 + math.random() * 1.4
			local goal = {
				Position = UDim2.fromOffset(piece.Position.X.Offset + math.random(-140, 140) * uiScale, size.Y + 30),
				Rotation = piece.Rotation + math.random(-540, 540),
			}
			TweenService:Create(piece, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), goal):Play()
			task.delay(fallTime + 0.1, function()
				piece:Destroy()
			end)
		end
	end

	-- purple glow at the top and bottom of the screen
	function levelFlash()
		local flash = frame({
			Name = "LevelFlash",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.55,
			BackgroundColor3 = PURPLE,
			Parent = effectsLayer,
		})
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.85),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = flash,
		})
		TweenService:Create(flash, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		task.delay(1, function()
			flash:Destroy()
		end)
	end

	local function showAnnouncement(kind: string, title: string)
		local color = GOLD
		local subtitleText = ""
		local hold = 3
		if kind == "level" then
			color = Color3.fromRGB(205, 150, 255)
			subtitleText = "You are now Level " .. formatNumber(attrNumber(player, "Level", 1)) .. "!"
			hold = 1.4
			playSound(pingSound, 1.3)
		else
			if string.find(string.upper(title), "TOWER") then
				subtitleText = "Total wins: " .. formatNumber(attrNumber(player, "Wins", 1))
			end
			playSound(pingSound)
			confetti()
		end

		local holder = frame({
			Name = "Announcement",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(780, 130),
			Parent = centerRoot,
		})
		local pop = Instance.new("UIScale")
		pop.Scale = 0.5
		pop.Parent = holder
		local titleLabel = text({
			Size = UDim2.new(1, 0, 0, 86),
			Font = FONT_BIG,
			TextScaled = true,
			TextColor3 = color,
			TextTransparency = 1,
			Text = title,
			Parent = holder,
		})
		make("UITextSizeConstraint", { MaxTextSize = 78, Parent = titleLabel })
		local titleStroke = stroke(titleLabel, 3, BLACK, 1)
		local subtitle = text({
			Position = UDim2.fromOffset(0, 88),
			Size = UDim2.new(1, 0, 0, 32),
			Font = FONT_BOLD,
			TextScaled = true,
			TextTransparency = 1,
			Text = subtitleText,
			Parent = holder,
		})
		make("UITextSizeConstraint", { MaxTextSize = 26, Parent = subtitle })
		local subtitleStroke = stroke(subtitle, 2, BLACK, 1)
		local items: { FadeItem } = {
			fadeItem(titleLabel, "TextTransparency", 0),
			fadeItem(titleStroke, "Transparency", 0.3),
			fadeItem(subtitle, "TextTransparency", 0),
			fadeItem(subtitleStroke, "Transparency", 0.4),
		}
		TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		fadeItems(items, true, 0.2)
		task.wait(hold)
		fadeItems(items, false, 0.5)
		task.wait(0.55)
		holder:Destroy()
	end

	-- big announcements wait for each other so they never pile up
	local queue: { { Kind: string, Title: string } } = {}
	local busy = false

	function queueAnnouncement(kind: string, title: string)
		table.insert(queue, { Kind = kind, Title = title })
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			while #queue > 0 do
				local nextOne = table.remove(queue, 1)
				if nextOne then
					local ok, err = pcall(function(): string?
						showAnnouncement(nextOne.Kind, nextOne.Title)
						return nil
					end)
					if not ok then
						warn("[TowerOfFood] Announcement error: " .. tostring(err))
					end
				end
			end
			busy = false
		end)
	end

	-- "NEW TOWER!" with the names of the 8 sections in their colours
	local currentBanner: Frame? = nil

	function showTowerBanner(title: string)
		if currentBanner then
			currentBanner:Destroy()
		end
		local holder = frame({
			Name = "TowerBanner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -24),
			Size = UDim2.fromOffset(780, 160),
			Parent = centerRoot,
		})
		currentBanner = holder
		local items: { FadeItem } = {}
		local titleLabel = text({
			Size = UDim2.new(1, 0, 0, 70),
			Font = FONT_BIG,
			TextSize = 66,
			TextTransparency = 1,
			Text = title,
			Parent = holder,
		})
		local titleStroke = stroke(titleLabel, 3, BLACK, 1)
		table.insert(items, fadeItem(titleLabel, "TextTransparency", 0))
		table.insert(items, fadeItem(titleStroke, "Transparency", 0.35))

		local info = layout
		if info then
			local grid = frame({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 76),
				Size = UDim2.fromOffset(780, 80),
				Parent = holder,
			})
			make("UIGridLayout", {
				CellSize = UDim2.fromOffset(184, 32),
				CellPadding = UDim2.fromOffset(8, 8),
				FillDirectionMaxCells = 4,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			for index, section in ipairs(info.Sections) do
				local chip = text({
					Name = "Section" .. index,
					BackgroundColor3 = section.Color,
					BackgroundTransparency = 1,
					TextScaled = true,
					TextTransparency = 1,
					Text = tostring(index) .. "  " .. section.Name,
					LayoutOrder = index,
					Parent = grid,
				})
				corner(chip, 9)
				padding(chip, 8, 8, 5, 5)
				make("UITextSizeConstraint", { MaxTextSize = 16, Parent = chip })
				local chipStroke = stroke(chip, 1.5, BLACK, 1)
				table.insert(items, fadeItem(chip, "TextTransparency", 0))
				table.insert(items, fadeItem(chip, "BackgroundTransparency", 0.12))
				table.insert(items, fadeItem(chipStroke, "Transparency", 0.45))
			end
		end

		TweenService:Create(holder, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
		}):Play()
		fadeItems(items, true, 0.3)
		task.delay(4.5, function()
			if holder.Parent == nil then
				return
			end
			fadeItems(items, false, 0.6)
			task.wait(0.65)
			holder:Destroy()
			if currentBanner == holder then
				currentBanner = nil
			end
		end)
	end
end

------------------------------------------------------------------------
-- TIMER (top middle) + round bonus label next to it
------------------------------------------------------------------------
local updateTimer: () -> ()
local refreshMutator: () -> ()
do
	local TIMER_SIZE = 56
	local timerLabel = text({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(420, 62),
		Font = FONT_BIG,
		TextSize = TIMER_SIZE,
		Text = "-:--",
		Parent = topRoot,
	})
	shadow(timerLabel, 0.5)
	local timerPulse = Instance.new("UIScale")
	timerPulse.Parent = timerLabel

	-- the round bonus ("x2", "LOW GRAVITY") sits just right of the numbers
	local mutatorLabel = text({
		Name = "Mutator",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 70, 0, 54),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_BIG,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = topRoot,
	})
	shadow(mutatorLabel, 0.5)

	local function placeMutator()
		local width = TextService:GetTextSize(timerLabel.Text, TIMER_SIZE, FONT_BIG, Vector2.new(1000, 200)).X
		mutatorLabel.Position = UDim2.new(0.5, math.ceil(width / 2) + 10, 0, 54)
	end

	function refreshMutator()
		local label = attrString(gameFolder, "MutatorLabel", "")
		mutatorLabel.Text = label
		mutatorLabel.Visible = label ~= ""
		placeMutator()
	end

	local lastText = ""
	function updateTimer()
		local roundEnd = gameFolder:GetAttribute("RoundEnd")
		local timeText = "-:--"
		local left = math.huge
		if type(roundEnd) == "number" then
			left = roundEnd - workspace:GetServerTimeNow()
			timeText = formatTime(left)
		end
		timerLabel.TextColor3 = if left <= 30 then TIMER_RED else WHITE
		if timeText ~= lastText then
			lastText = timeText
			timerLabel.Text = timeText
			placeMutator()
			if left <= 10 and left > 0 then
				-- little "tick" bounce in the last 10 seconds
				timerPulse.Scale = 1.15
				TweenService:Create(timerPulse, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end
	end
end

------------------------------------------------------------------------
-- MENU BUTTON, COINS and SKIP SECTION (bottom left)
------------------------------------------------------------------------
local onCoinsChanged: () -> ()
local updateCoinAnimation: () -> ()
local updateSkipButton: () -> ()
do
	local ICON_SIZE = 64
	local COINS_SIZE = 44
	local COINS_X = ICON_SIZE + 12

	local menuTextButton = textButton({
		Name = "MenuText",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 1, 1, -(ICON_SIZE + 4)),
		Size = UDim2.fromOffset(100, 32),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = FONT_BIG,
		TextSize = 32,
		Text = "Menu",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bottomLeft,
	})
	shadow(menuTextButton, 0.45)

	local menuIconButton = textButton({
		Name = "MenuButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		BackgroundColor3 = Color3.fromRGB(246, 247, 250),
		Parent = bottomLeft,
	})
	corner(menuIconButton, 16)
	border(menuIconButton, 3, Color3.fromRGB(196, 200, 214))
	coinIcon({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = menuIconButton,
	}, 40)

	local coinsLabel = text({
		Name = "Coins",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, COINS_X, 1, -ICON_SIZE / 2),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_BIG,
		TextSize = COINS_SIZE,
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bottomLeft,
	})
	shadow(coinsLabel, 0.45)

	-- only shows when you own the Skip Section pass and you're inside the tower
	local skipButton = textButton({
		Name = "SkipSection",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(ICON_SIZE + 42)),
		Size = UDim2.fromOffset(120, 34),
		BackgroundColor3 = ORANGE,
		Font = FONT_BOLD,
		TextSize = 18,
		Text = "SKIP ⏭",
		TextStrokeTransparency = 0.7,
		Visible = false,
		Parent = bottomLeft,
	})
	corner(skipButton, 12)
	border(skipButton, 2, WHITE, 0.35)

	menuIconButton.Activated:Connect(function()
		playSound(clickSound)
		toggleMenu()
	end)
	menuTextButton.Activated:Connect(function()
		playSound(clickSound)
		toggleMenu()
	end)

	-- counting-up animation for the coin number
	local COUNT_TIME = 0.8
	local known = false
	local shown = 0
	local goal = 0
	local from = 0
	local startTime = 0

	local function coinFloat(amount: number)
		local width = TextService:GetTextSize(coinsLabel.Text, COINS_SIZE, FONT_BIG, Vector2.new(2000, 200)).X
		local x = COINS_X + width + 10
		local float = text({
			Name = "CoinFloat",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, x, 1, -44),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = FONT_BIG,
			TextSize = 30,
			TextColor3 = GOLD,
			Text = "+" .. formatNumber(amount),
			Parent = bottomLeft,
		})
		local floatStroke = shadow(float, 0.55)
		local info = TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(float, info, { Position = UDim2.new(0, x, 1, -90), TextTransparency = 1 }):Play()
		TweenService:Create(floatStroke, info, { Transparency = 1 }):Play()
		task.delay(1.35, function()
			float:Destroy()
		end)
	end

	function onCoinsChanged()
		local raw = player:GetAttribute("Coins")
		if type(raw) ~= "number" then
			return -- your coins haven't loaded yet
		end
		local value: number = raw
		if not known then
			known = true
			shown, goal = value, value
			coinsLabel.Text = formatNumber(value)
			return
		end
		local gained = value - goal
		if gained > 0.05 then
			from = shown
			goal = value
			startTime = os.clock()
			earnedThisRound += gained
			coinFloat(gained)
		else
			-- spent coins: just show the new number
			shown, goal = value, value
			coinsLabel.Text = formatNumber(value)
		end
	end

	function updateCoinAnimation()
		if shown == goal then
			return
		end
		local t = math.clamp((os.clock() - startTime) / COUNT_TIME, 0, 1)
		if t >= 1 then
			shown = goal
			coinsLabel.Text = formatNumber(goal)
		else
			local eased = 1 - (1 - t) ^ 3
			shown = from + (goal - from) * eased
			coinsLabel.Text = formatNumber(math.floor(shown))
		end
	end

	-- Skip Section: pass owned + not used this round + inside the tower (not the last section)
	local cooldown = 0

	function updateSkipButton()
		local show = false
		local info = layout
		if info and attrTrue(player, "Pass_SkipSection") and not attrTrue(player, "SkipUsed") and os.clock() > cooldown then
			local root = getRoot(player)
			local last = info.Sections[#info.Sections]
			if root and last then
				local p = root.Position
				local inShaft = math.sqrt(p.X * p.X + p.Z * p.Z) < SHAFT_RADIUS
				local inTower = p.Y > info.BaseY + 2
				local beforeLast = p.Y - FEET_OFFSET < last.BaseY - 1
				show = inShaft and inTower and beforeLast
			end
		end
		skipButton.Visible = show
	end

	skipButton.Activated:Connect(function()
		playSound(clickSound)
		cooldown = os.clock() + 2
		skipButton.Visible = false
		skipEvent:FireServer()
	end)
end

------------------------------------------------------------------------
-- LEVEL, SKILL POINTS and XP BAR (bottom middle)
------------------------------------------------------------------------
local refreshLevel: () -> ()
do
	local levelLabel = text({
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(300, 30),
		Font = FONT_BIG,
		TextSize = 26,
		RichText = true,
		Text = "<u>Level 1</u>",
		Parent = bottomCenter,
	})
	shadow(levelLabel, 0.45)

	-- "3 Skill Points unspent" - tap it to open the Skills page
	local pointsButton = textButton({
		Name = "SkillPoints",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(300, 18),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = FONT_BIG,
		TextSize = 16,
		Visible = false,
		Parent = bottomCenter,
	})
	shadow(pointsButton, 0.45)
	pointsButton.Activated:Connect(function()
		playSound(clickSound)
		openMenu("SKILLS")
	end)

	-- thin pink XP bar with a tick at each end (hover or tap it to see your XP)
	local xpBar = textButton({
		Name = "XPBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.fromOffset(240, 24),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Parent = bottomCenter,
	})
	local xpTrack = frame({
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 0.8,
		BackgroundColor3 = WHITE,
		Parent = xpBar,
	})
	local xpFill = frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = XP_PINK,
		Parent = xpTrack,
	})
	for _, side in ipairs({ 0, 1 }) do
		frame({
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side, 0.5),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			Parent = xpBar,
		})
	end
	local xpText = text({
		Name = "XPText",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(240, 18),
		TextSize = 15,
		Visible = false,
		Parent = xpBar,
	})
	shadow(xpText, 0.6)

	local token = 0
	local function showXP(seconds: number?)
		token += 1
		local myToken = token
		xpText.Visible = true
		if seconds then
			task.delay(seconds, function()
				if myToken == token then
					xpText.Visible = false
				end
			end)
		end
	end

	xpBar.MouseEnter:Connect(function()
		showXP(nil)
	end)
	xpBar.MouseLeave:Connect(function()
		token += 1
		xpText.Visible = false
	end)
	xpBar.Activated:Connect(function()
		showXP(2.5)
	end)

	function refreshLevel()
		local level = attrNumber(player, "Level", 1)
		local points = attrNumber(player, "SkillPoints", 0)
		local xp = attrNumber(player, "LevelXP", 0)
		local need = math.max(1, attrNumber(player, "LevelNeed", 100))
		levelLabel.Text = "<u>Level " .. formatNumber(level) .. "</u>"
		if points > 0 then
			pointsButton.Text = formatNumber(points) .. (if points == 1 then " Skill Point unspent" else " Skill Points unspent")
			pointsButton.Visible = true
			xpBar.Visible = false
			levelLabel.Position = UDim2.new(0.5, 0, 1, -19)
		else
			pointsButton.Visible = false
			xpBar.Visible = true
			levelLabel.Position = UDim2.fromScale(0.5, 1)
		end
		TweenService:Create(xpFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(math.clamp(xp / need, 0, 1), 1),
		}):Play()
		xpText.Text = formatNumber(xp) .. " / " .. formatNumber(need) .. " XP"
	end
end

------------------------------------------------------------------------
-- MUSIC PLAYER (bottom right) - plays the songs in the server's CONFIG.MUSIC
------------------------------------------------------------------------
local musicRow: Frame
local loadMusicList: () -> ()
local setMusicOn: (on: boolean) -> ()
local isMusicOn: () -> boolean
do
	musicRow = frame({
		Name = "Music",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = bottomRight,
	})
	listLayout(musicRow, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local trackName = text({
		Name = "TrackName",
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_TEXT,
		TextSize = 23,
		LayoutOrder = 1,
		Parent = musicRow,
	})
	shadow(trackName, 0.5)
	local nextButton = textButton({
		Name = "Next",
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		TextSize = 24,
		Text = "▶",
		LayoutOrder = 2,
		Parent = musicRow,
	})
	shadow(nextButton, 0.5)

	type Track = { Name: string, Id: string }
	local tracks: { Track } = {}
	local index = 0
	local musicOn = true
	local failedInARow = 0
	local playToken = 0

	local sound = Instance.new("Sound")
	sound.Name = "TowerOfFoodMusic"
	sound.Volume = 0.4
	sound.Looped = false
	sound.Parent = SoundService

	local function playTrack(newIndex: number)
		if #tracks == 0 then
			sound:Stop()
			return
		end
		index = ((newIndex - 1) % #tracks) + 1
		local track = tracks[index]
		playToken += 1
		local myToken = playToken
		sound:Stop()
		sound.SoundId = track.Id
		sound.TimePosition = 0
		trackName.Text = "♪ " .. track.Name
		if musicOn then
			sound:Play()
		end
		-- a song that never loads (wrong or private ID) gets skipped
		task.delay(12, function()
			if myToken ~= playToken or sound.IsLoaded or not musicOn then
				return
			end
			failedInARow += 1
			warn("[TowerOfFood] The song \"" .. track.Name .. "\" didn't load. Check its ID in CONFIG.MUSIC (TowerGame script).")
			if failedInARow < #tracks then
				playTrack(index + 1)
			else
				sound:Stop()
				musicRow.Visible = false
				relayout()
			end
		end)
	end

	sound.Loaded:Connect(function()
		failedInARow = 0
	end)
	sound.Ended:Connect(function()
		playTrack(index + 1)
	end)

	function isMusicOn(): boolean
		return musicOn
	end

	function setMusicOn(on: boolean)
		musicOn = on
		if on then
			if #tracks > 0 then
				if not sound.IsLoaded then
					playTrack(index) -- try this song again (and check it loads)
				elseif sound.TimePosition > 0 then
					sound:Resume()
				else
					sound:Play()
				end
			end
		else
			sound:Pause()
		end
		trackName.TextTransparency = if on then 0 else 0.45
		nextButton.TextTransparency = if on then 0 else 0.3
	end

	function loadMusicList()
		local data = attrJSON("Music")
		local list: { Track } = {}
		if type(data) == "table" then
			for _, entry in ipairs(data) do
				if type(entry) == "table" then
					local id = str(entry.Id, "")
					if tonumber(id) then
						id = "rbxassetid://" .. id -- plain numbers work too
					end
					if id ~= "" then
						local name = str(entry.Name, "Music")
						if #name > 28 then
							name = string.sub(name, 1, 26) .. "..."
						end
						table.insert(list, { Name = name, Id = id })
					end
				end
			end
		end
		-- only restart the music if the list really changed
		local changed = #list ~= #tracks
		if not changed then
			for i, track in ipairs(list) do
				if track.Id ~= tracks[i].Id or track.Name ~= tracks[i].Name then
					changed = true
				end
			end
		end
		if not changed then
			return
		end
		tracks = list
		failedInARow = 0
		musicRow.Visible = #tracks > 0
		relayout()
		if #tracks > 0 then
			playTrack(math.random(1, #tracks))
		else
			playToken += 1
			sound:Stop()
		end
	end

	-- ▶ = next song (or turn the music back on if it's off)
	nextButton.Activated:Connect(function()
		playSound(clickSound)
		if not musicOn then
			setMusicOn(true)
			refreshMenu()
		else
			playTrack(index + 1)
		end
	end)
end

------------------------------------------------------------------------
-- PROGRESS BAR (right side): one colour per section, a face per player
------------------------------------------------------------------------
local progressRoot: Frame
local progressScale: UIScale
local rebuildBar: () -> ()
local addMarker: (who: Player) -> ()
local removeMarker: (who: Player) -> ()
local updateMarkerTargets: () -> ()
local updateMarkers: (dt: number) -> ()
do
	progressRoot = frame({
		Name = "Progress",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 80),
		Size = UDim2.fromOffset(170, 500),
		Parent = gui,
	})
	progressScale = Instance.new("UIScale")
	progressScale.Parent = progressRoot

	local bar = frame({
		Name = "Bar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, BAR_WIDTH, 1, 0),
		BackgroundTransparency = 0.6,
		BackgroundColor3 = BLACK,
		ZIndex = 1,
		Parent = progressRoot,
	})
	border(bar, 1, BLACK, 0.5)

	-- "+100 (coin)" next to the gold top = bonus for reaching the top
	local topBonus = frame({
		Name = "TopBonus",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(BAR_WIDTH + 6), TOP_PART / 2, 0),
		Size = UDim2.fromOffset(100, 24),
		ZIndex = 6,
		Parent = progressRoot,
	})
	listLayout(topBonus, true, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local topBonusText = text({
		Name = "Amount",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_BIG,
		TextSize = 22,
		Text = "+100",
		LayoutOrder = 1,
		Parent = topBonus,
	})
	shadow(topBonusText, 0.55)
	coinIcon({ LayoutOrder = 2, Parent = topBonus }, 18)

	local function segment(fromPart: number, sizePart: number, color: Color3, transparency: number)
		frame({
			Name = "Segment",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1 - fromPart),
			Size = UDim2.fromScale(1, sizePart + 0.002),
			BackgroundTransparency = transparency,
			BackgroundColor3 = color,
			Parent = bar,
		})
	end

	function rebuildBar()
		for _, child in ipairs(bar:GetChildren()) do
			if child.Name == "Segment" then
				child:Destroy()
			end
		end
		segment(0, LOBBY_PART, Color3.fromRGB(214, 218, 228), 0.05)
		local info = layout
		if info then
			local span = math.max(1, info.TopY - info.BaseY)
			for _, section in ipairs(info.Sections) do
				local from = (section.BaseY - info.BaseY) / span
				segment(LOBBY_PART + from * TOWER_PART, section.Height / span * TOWER_PART, section.Color, 0.08)
			end
			topBonusText.Text = "+" .. formatNumber(info.TopBonus)
		else
			segment(LOBBY_PART, TOWER_PART, Color3.fromRGB(150, 155, 170), 0.5)
		end
		segment(LOBBY_PART + TOWER_PART, TOP_PART, GOLD, 0)
	end

	-- where a height in the world is on the bar (0 = bottom, 1 = top)
	local function heightToBar(y: number): number
		local info = layout
		local feet = y - FEET_OFFSET
		if not info then
			return LOBBY_PART * 0.3
		end
		if feet < info.BaseY then
			local t = math.clamp(feet / math.max(1, info.BaseY), 0, 1)
			return LOBBY_PART * (0.3 + 0.7 * t)
		elseif feet <= info.TopY then
			return LOBBY_PART + (feet - info.BaseY) / math.max(1, info.TopY - info.BaseY) * TOWER_PART
		end
		return LOBBY_PART + TOWER_PART + math.clamp((feet - info.TopY) / 20, 0, 1) * TOP_PART
	end

	type Marker = {
		Holder: Frame,
		Line: Frame,
		Earned: Frame?,
		EarnedText: TextLabel?,
		Size: number,
		LineThickness: number,
		Target: number,
		Current: number,
		Shift: number,
		TargetShift: number,
		Fresh: boolean, -- just added: jump straight to the right spot
		Placed: boolean, -- drawn at least once
	}
	local markers: { [Player]: Marker } = {}
	local faces: { [number]: string } = {} -- avatar pictures we already looked up

	local function loadFace(userId: number, avatar: ImageLabel, letter: TextLabel)
		local cached = faces[userId]
		if cached then
			avatar.Image = cached
			letter.Visible = false
			return
		end
		task.spawn(function()
			local ok, content = pcall(function(): string
				local image = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
				return image
			end)
			local image = ""
			if ok and content ~= "" then
				image = content
				faces[userId] = content
			elseif userId > 0 then
				image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48"
			end
			if image ~= "" and avatar.Parent then
				avatar.Image = image
				letter.Visible = false
			end
		end)
	end

	function addMarker(who: Player)
		if markers[who] then
			return
		end
		local isMe = who == player
		local size = if isMe then 34 else 26
		local color = if isMe then WHITE else MARKER_COLORS[(who.UserId % #MARKER_COLORS) + 1]
		local line = frame({
			Name = "Line",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(20, 2),
			BackgroundTransparency = if isMe then 0 else 0.15,
			BackgroundColor3 = color,
			ZIndex = if isMe then 4 else 2,
			Parent = progressRoot,
		})
		local holder = frame({
			Name = "Face",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(size, size),
			ZIndex = if isMe then 5 else 3,
			Parent = progressRoot,
		})
		local avatar = make("ImageLabel", {
			Name = "Avatar",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = color:Lerp(BLACK, 0.45),
			Image = "",
			Parent = holder,
		}) :: ImageLabel
		circle(avatar)
		stroke(avatar, if isMe then 2.5 else 1.5, color, 0)
		local letter = text({
			Name = "Letter",
			Size = UDim2.fromScale(1, 1),
			TextSize = math.floor(size * 0.5),
			Text = firstLetter(who.DisplayName),
			Parent = avatar,
		})
		loadFace(who.UserId, avatar, letter)

		local marker: Marker = {
			Holder = holder,
			Line = line,
			Earned = nil,
			EarnedText = nil,
			Size = size,
			LineThickness = if isMe then 3 else 2,
			Target = LOBBY_PART * 0.3,
			Current = LOBBY_PART * 0.3,
			Shift = 0,
			TargetShift = 0,
			Fresh = true,
			Placed = false,
		}

		if isMe then
			-- coins you've earned this round, shown next to your face
			local earned = frame({
				Name = "Earned",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(0, -6, 0.5, 0),
				Size = UDim2.fromOffset(110, 22),
				Visible = false,
				Parent = holder,
			})
			listLayout(earned, true, 3, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
			local earnedText = text({
				Name = "Amount",
				Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = FONT_BIG,
				TextSize = 20,
				LayoutOrder = 1,
				Parent = earned,
			})
			shadow(earnedText, 0.55)
			coinIcon({ LayoutOrder = 2, Parent = earned }, 16)
			marker.Earned = earned
			marker.EarnedText = earnedText
		end
		markers[who] = marker
	end

	function removeMarker(who: Player)
		local marker = markers[who]
		if marker then
			marker.Holder:Destroy()
			marker.Line:Destroy()
			markers[who] = nil
		end
	end

	-- works out where everyone should be (10 times a second)
	function updateMarkerTargets()
		local list: { Marker } = {}
		for who, marker in pairs(markers) do
			local root = getRoot(who)
			local target
			if root then
				target = heightToBar(root.Position.Y)
			else
				-- no character right now: use how many sections they've cleared
				local info = layout
				local stage = attrNumber(who, "Stage", 0)
				if info and stage > 0 and info.Sections[stage + 1] then
					target = heightToBar(info.Sections[stage + 1].BaseY + FEET_OFFSET)
				else
					target = LOBBY_PART * 0.3
				end
			end
			marker.Target = target
			if marker.Fresh then
				marker.Fresh = false
				marker.Current = target
				marker.Placed = false -- draw it at its real spot next frame
			end
			table.insert(list, marker)
		end
		-- faces that would sit on top of each other get nudged sideways
		table.sort(list, function(a: Marker, b: Marker): boolean
			return a.Target < b.Target
		end)
		local barHeight = progressRoot.Size.Y.Offset
		local previous = -math.huge
		local column = 0
		for _, marker in ipairs(list) do
			local y = marker.Target * barHeight
			if y - previous < 20 then
				column = math.min(column + 1, 4)
			else
				column = 0
			end
			previous = y
			marker.TargetShift = column * 22
		end

		local mine = markers[player]
		if mine and mine.Earned and mine.EarnedText then
			mine.Earned.Visible = earnedThisRound > 0.05
			mine.EarnedText.Text = "+" .. formatNumber(earnedThisRound)
			-- hide the "+100" top label while your own coins label would cover it
			topBonus.Visible = not (mine.Earned.Visible and mine.Target > 1 - TOP_PART * 2.5)
		end
	end

	-- slides the faces smoothly to their spots (every frame)
	function updateMarkers(dt: number)
		local alpha = 1 - math.exp(-dt * 10)
		for _, marker in pairs(markers) do
			local moving = math.abs(marker.Target - marker.Current) > 0.0002 or math.abs(marker.TargetShift - marker.Shift) > 0.05
			if moving or not marker.Placed then
				marker.Placed = true
				marker.Current += (marker.Target - marker.Current) * alpha
				marker.Shift += (marker.TargetShift - marker.Shift) * alpha
				local x = BAR_WIDTH + 6 + marker.Shift
				local y = 1 - marker.Current
				marker.Holder.Position = UDim2.new(1, -x, y, 0)
				marker.Line.Position = UDim2.new(1, 0, y, 0)
				marker.Line.Size = UDim2.fromOffset(x + marker.Size * 0.5, marker.LineThickness)
			end
		end
	end
end

------------------------------------------------------------------------
-- SCREEN FIT: makes everything the right size for computers, tablets and phones
------------------------------------------------------------------------
local updateHotbarShift: () -> ()
do
	local StarterGui = game:GetService("StarterGui")
	local hotbarShift = 0

	-- top of Roblox's jump button on phones/tablets, measured from the bottom
	local function jumpButtonTop(size: Vector2): number
		if math.min(size.X, size.Y) <= 500 then
			return 90
		end
		return 210
	end

	relayout = function()
		local size = screenSize()
		isTouch = detectTouch()
		uiScale = math.clamp(math.min(size.X / DESIGN_SIZE.X, size.Y / DESIGN_SIZE.Y), 0.72, 1.6)
		for _, scale in ipairs(hudScales) do
			scale.Scale = uiScale
		end

		-- on phones the music player sits above the jump button
		local jumpTop = jumpButtonTop(size)
		if isTouch then
			bottomRight.Position = UDim2.new(1, -16, 1, -(jumpTop + 12))
		else
			bottomRight.Position = UDim2.new(1, -16, 1, -10)
		end

		-- progress bar: tall on computers, shorter on phones (clear of the jump button)
		local top = math.max(size.Y * 0.1, 64)
		local bottom = size.Y * 0.9
		if isTouch then
			bottom = size.Y - jumpTop - 20
			if musicRow.Visible then
				bottom -= 34 * uiScale + 12
			end
		end
		local barPixels = math.max(120, bottom - top)
		progressScale.Scale = uiScale
		progressRoot.Position = UDim2.new(1, -8, 0, top)
		progressRoot.Size = UDim2.fromOffset(170, barPixels / uiScale)

		bottomCenter.Position = UDim2.new(0.5, 0, 1, -10 - hotbarShift)

		-- the Menu fits in the space under the timer (a bit bigger on phones so it's easy to tap)
		local timerBottom = 6 + 62 * uiScale + 4
		local spaceY = math.max(100, size.Y - timerBottom - 6)
		local fitScreen = math.min(size.X * 0.94 / MENU_W, spaceY / MENU_H)
		menuFit = if isTouch then fitScreen else math.min(uiScale, fitScreen)
		menuScale.Scale = menuFit
		menuRoot.Position = UDim2.new(0.5, 0, 0, timerBottom + spaceY / 2)
		local gapAboveMenu = (spaceY - MENU_H * menuFit) / 2
		menuCrowdsToasts = gapAboveMenu < 70 * uiScale
		placeToasts(menuRoot.Visible and menuCrowdsToasts)
	end

	-- lift the level display above the Roblox backpack bar when you have gear (coils!)
	function updateHotbarShift()
		local count = 0
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, child in ipairs(backpack:GetChildren()) do
				if child:IsA("Tool") then
					count += 1
				end
			end
		end
		local character = player.Character
		if character and character:FindFirstChildOfClass("Tool") then
			count += 1
		end
		local okBackpack, backpackOn = pcall(function(): boolean
			return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
		end)
		local shift = if count > 0 and (not okBackpack or backpackOn) then 74 else 0
		if shift ~= hotbarShift then
			hotbarShift = shift
			TweenService:Create(bottomCenter, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, 0, 1, -10 - shift),
			}):Play()
		end
	end
end

------------------------------------------------------------------------
-- HIDE OTHER PLAYERS (a setting) - only changes what YOU see
------------------------------------------------------------------------
local setHideOthers: (on: boolean) -> ()
local isHidingOthers: () -> boolean
local hideOthersStep: () -> ()
do
	local hiding = false
	type HideEntry = { Parts: { BasePart }, Decals: { Decal }, Effects: { Instance }, Dirty: boolean, Connections: { RBXScriptConnection } }
	local entries: { [Model]: HideEntry } = {}
	-- what name tags looked like before we hid them ("weak" = forgets removed characters)
	local savedBillboards = setmetatable({} :: { [BillboardGui]: boolean }, { __mode = "k" })
	local savedNames = setmetatable({} :: { [Humanoid]: Enum.HumanoidDisplayDistanceType }, { __mode = "k" })

	local function fadeEffect(inst: Instance, value: number)
		if inst:IsA("Trail") then
			inst.LocalTransparencyModifier = value
		elseif inst:IsA("ParticleEmitter") then
			inst.LocalTransparencyModifier = value
		elseif inst:IsA("Beam") then
			inst.LocalTransparencyModifier = value
		elseif inst:IsA("Fire") then
			inst.LocalTransparencyModifier = value
		elseif inst:IsA("Smoke") then
			inst.LocalTransparencyModifier = value
		elseif inst:IsA("Sparkles") then
			inst.LocalTransparencyModifier = value
		end
	end

	local function isEffect(inst: Instance): boolean
		return inst:IsA("Trail") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
	end

	-- name tags and the VIP/level sign above their heads
	local function hideNameTags(inst: Instance)
		if inst:IsA("BillboardGui") then
			if savedBillboards[inst] == nil then
				savedBillboards[inst] = inst.Enabled
			end
			inst.Enabled = false
		elseif inst:IsA("Humanoid") then
			if savedNames[inst] == nil then
				savedNames[inst] = inst.DisplayDistanceType
			end
			inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end

	local function scanCharacter(character: Model, entry: HideEntry)
		entry.Parts, entry.Decals, entry.Effects = {}, {}, {}
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(entry.Parts, d)
			elseif d:IsA("Decal") then
				table.insert(entry.Decals, d)
			elseif isEffect(d) then
				table.insert(entry.Effects, d)
			else
				hideNameTags(d)
			end
		end
		entry.Dirty = false
	end

	-- runs every frame while the setting is on
	function hideOthersStep()
		for _, other in ipairs(Players:GetPlayers()) do
			local character = other.Character
			if other ~= player and character then
				local entry = entries[character]
				if not entry then
					local newEntry: HideEntry = { Parts = {}, Decals = {}, Effects = {}, Dirty = true, Connections = {} }
					local function markDirty()
						newEntry.Dirty = true
					end
					table.insert(newEntry.Connections, character.DescendantAdded:Connect(markDirty))
					table.insert(newEntry.Connections, character.DescendantRemoving:Connect(markDirty))
					entries[character] = newEntry
					entry = newEntry
				end
				if entry.Dirty then
					scanCharacter(character, entry)
				end
				for _, part in ipairs(entry.Parts) do
					part.LocalTransparencyModifier = 1
				end
				for _, decal in ipairs(entry.Decals) do
					decal.LocalTransparencyModifier = 1
				end
				for _, effect in ipairs(entry.Effects) do
					fadeEffect(effect, 1)
				end
			end
		end
		-- forget characters that are gone
		for character, entry in pairs(entries) do
			if character.Parent == nil then
				for _, connection in ipairs(entry.Connections) do
					connection:Disconnect()
				end
				entries[character] = nil
			end
		end
	end

	local function showEveryone()
		for character, entry in pairs(entries) do
			for _, connection in ipairs(entry.Connections) do
				connection:Disconnect()
			end
			for _, d in ipairs(character:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				elseif d:IsA("Decal") then
					d.LocalTransparencyModifier = 0
				else
					fadeEffect(d, 0)
				end
			end
		end
		table.clear(entries)
		for billboard, enabled in pairs(savedBillboards) do
			billboard.Enabled = enabled
			savedBillboards[billboard] = nil
		end
		for humanoid, displayType in pairs(savedNames) do
			humanoid.DisplayDistanceType = displayType
			savedNames[humanoid] = nil
		end
	end

	function isHidingOthers(): boolean
		return hiding
	end

	function setHideOthers(on: boolean)
		hiding = on
		if not on then
			showEveryone()
		end
	end
end

------------------------------------------------------------------------
-- MENU (Shop, Trails, Passes, Skills, Codes, Settings)
------------------------------------------------------------------------
local rebuildMenuLists: (which: string?) -> ()
local selectTab: (tabName: string) -> ()
do
	local MarketplaceService = game:GetService("MarketplaceService")
	local GuiService = game:GetService("GuiService")

	corner(menuRoot, 22)
	border(menuRoot, 2, WHITE, 0.82)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(34, 37, 52), PANEL),
		Parent = menuRoot,
	})

	local title = text({
		Name = "Title",
		Position = UDim2.fromOffset(22, 10),
		Size = UDim2.fromOffset(120, 44),
		Font = FONT_BIG,
		TextSize = 38,
		Text = "MENU",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = menuRoot,
	})
	shadow(title, 0.4)

	-- your coins inside the menu
	local coinsChip = frame({
		Name = "Coins",
		Position = UDim2.fromOffset(140, 14),
		Size = UDim2.fromOffset(240, 36),
		Parent = menuRoot,
	})
	listLayout(coinsChip, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	coinIcon({ LayoutOrder = 1, Parent = coinsChip }, 26)
	local coinsText = text({
		Name = "Amount",
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_BIG,
		TextSize = 30,
		TextColor3 = GOLD,
		Text = "0",
		LayoutOrder = 2,
		Parent = coinsChip,
	})

	local closeButton = textButton({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = RED,
		TextSize = 22,
		Text = "X",
		Modal = true, -- frees the mouse while the menu is open
		Parent = menuRoot,
	})
	circle(closeButton)

	local tabBar = frame({
		Name = "Tabs",
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.fromOffset(MENU_W - 32, 38),
		Parent = menuRoot,
	})
	listLayout(tabBar, true, 6, Enum.HorizontalAlignment.Center, nil)

	local pageHolder = frame({
		Name = "Pages",
		Position = UDim2.fromOffset(16, 112),
		Size = UDim2.fromOffset(MENU_W - 32, MENU_H - 126),
		Parent = menuRoot,
	})

	local TAB_NAMES = { "SHOP", "TRAILS", "PASSES", "SKILLS", "CODES", "SETTINGS" }
	local tabButtons: { [string]: TextButton } = {}
	local pages: { [string]: ScrollingFrame } = {}
	local currentTab = "SHOP"

	for order, tabName in ipairs(TAB_NAMES) do
		local tab = textButton({
			Name = tabName,
			Size = UDim2.fromOffset(102, 38),
			BackgroundColor3 = CARD,
			TextSize = 15,
			Text = tabName,
			LayoutOrder = order,
			Parent = tabBar,
		})
		corner(tab, 10)
		tabButtons[tabName] = tab

		local page = make("ScrollingFrame", {
			Name = tabName,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = WHITE,
			ScrollBarImageTransparency = 0.6,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
			Parent = pageHolder,
		}) :: ScrollingFrame
		listLayout(page, false, 8, nil, nil)
		padding(page, 2, 12, 2, 8)
		pages[tabName] = page
	end

	-- little red bubble on the SKILLS tab when you have points to spend
	local skillsBadge = text({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = RED,
		TextSize = 13,
		Visible = false,
		ZIndex = 3,
		Parent = tabButtons.SKILLS,
	})
	circle(skillsBadge)

	function selectTab(tabName: string)
		if not pages[tabName] then
			return
		end
		currentTab = tabName
		for name, page in pairs(pages) do
			page.Visible = name == tabName
		end
		for name, tab in pairs(tabButtons) do
			local active = name == tabName
			tab.BackgroundColor3 = if active then WHITE else CARD
			tab.TextColor3 = if active then PANEL else WHITE
		end
	end

	for _, tabName in ipairs(TAB_NAMES) do
		tabButtons[tabName].Activated:Connect(function()
			playSound(clickSound)
			selectTab(tabName)
		end)
	end

	-- grey hint line at the top of a page
	local function pageNote(page: Instance, order: number, message: string)
		text({
			Name = "Note",
			Size = UDim2.new(1, 0, 0, 22),
			Font = FONT_TEXT,
			TextSize = 15,
			TextColor3 = SOFT_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = message,
			LayoutOrder = order,
			Parent = page,
		})
	end

	local function clearPage(page: Instance)
		for _, child in ipairs(page:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- the square picture on the left of each card
	local function iconBox(color: Color3): Frame
		local box = frame({
			Name = "Icon",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(48, 48),
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
		})
		corner(box, 12)
		return box
	end

	local function coilIcon(color: Color3): Frame
		local box = iconBox(color:Lerp(BLACK, 0.55))
		for i = 0, 2 do
			local ringPiece = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 14 + i * 10),
				Size = UDim2.fromOffset(30, 7),
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				Parent = box,
			})
			circle(ringPiece)
			border(ringPiece, 1.5, WHITE, 0.3)
		end
		return box
	end

	local function trailIcon(color: Color3): Frame
		local box = iconBox(color:Lerp(BLACK, 0.6))
		local streak = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.45, 0.55),
			Size = UDim2.fromOffset(38, 12),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			Rotation = -25,
			Parent = box,
		})
		circle(streak)
		make("UIGradient", {
			Color = ColorSequence.new(color:Lerp(WHITE, 0.4), color),
			Transparency = NumberSequence.new(0.85, 0),
			Parent = streak,
		})
		local dot = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.45, 15, 0.55, -7),
			Size = UDim2.fromOffset(13, 13),
			BackgroundTransparency = 0,
			BackgroundColor3 = color:Lerp(WHITE, 0.25),
			Parent = box,
		})
		circle(dot)
		return box
	end

	local function glyphIcon(color: Color3, glyph: string, glyphColor: Color3): Frame
		local box = iconBox(color)
		text({
			Size = UDim2.fromScale(1, 1),
			TextScaled = true,
			TextColor3 = glyphColor,
			Text = glyph,
			Parent = box,
		})
		padding(box, 6, 6, 10, 10)
		return box
	end

	type Row = {
		Frame: Frame,
		Desc: TextLabel,
		Button: TextButton,
		ButtonText: TextLabel,
		ButtonCoin: Frame,
		Badge: TextLabel,
		Extra: TextLabel,
	}

	-- one card on a page: picture, name, description and a button on the right
	local function makeRow(page: Instance, order: number, rowTitle: string, desc: string, icon: Frame): Row
		local row = frame({
			Name = rowTitle,
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundTransparency = 0,
			BackgroundColor3 = CARD,
			LayoutOrder = order,
			Parent = page,
		})
		corner(row, 14)
		icon.Parent = row
		text({
			Name = "Title",
			Position = UDim2.fromOffset(72, 10),
			Size = UDim2.new(1, -310, 0, 24),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = rowTitle,
			Parent = row,
		})
		local descLabel = text({
			Name = "Desc",
			Position = UDim2.fromOffset(72, 36),
			Size = UDim2.new(1, -310, 0, 30),
			Font = FONT_TEXT,
			TextSize = 15,
			TextColor3 = SOFT_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Text = desc,
			Parent = row,
		})
		-- small green tag like "EQUIPPED" (hidden until needed)
		local badge = text({
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -150, 0.5, 0),
			Size = UDim2.fromOffset(84, 22),
			BackgroundTransparency = 0,
			BackgroundColor3 = GREEN,
			TextSize = 12,
			Text = "EQUIPPED",
			Visible = false,
			Parent = row,
		})
		corner(badge, 6)
		-- extra info left of the button (like "Lv 3/10")
		local extra = text({
			Name = "Extra",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -150, 0.5, 0),
			Size = UDim2.fromOffset(84, 24),
			Font = FONT_BIG,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Right,
			Visible = false,
			Parent = row,
		})
		local button = textButton({
			Name = "Action",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(128, 44),
			Parent = row,
		})
		corner(button, 12)
		-- the button shows [coin] price, or a word like OWNED / EQUIP
		local inside = frame({
			Name = "Inside",
			Size = UDim2.fromScale(1, 1),
			Parent = button,
		})
		listLayout(inside, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		local buttonCoin = coinIcon({ LayoutOrder = 1, Visible = false, Parent = inside }, 20)
		local buttonText = text({
			Name = "Label",
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 17,
			LayoutOrder = 2,
			Parent = inside,
		})
		return {
			Frame = row,
			Desc = descLabel,
			Button = button,
			ButtonText = buttonText,
			ButtonCoin = buttonCoin,
			Badge = badge,
			Extra = extra,
		}
	end

	local function setButton(row: Row, label: string, color: Color3, showCoin: boolean, enabled: boolean)
		row.ButtonText.Text = label
		row.ButtonText.TextTransparency = if enabled then 0 else 0.35
		row.ButtonCoin.Visible = showCoin
		row.Button.BackgroundColor3 = color
		row.Button.AutoButtonColor = enabled
	end

	-- asks the server to buy / equip / level up etc. and shows its answer
	local busy = false
	local function runShopAction(action: string, id: string): boolean
		if busy then
			return false
		end
		busy = true
		local ok, success, message = pcall(function(): (boolean, string)
			local result, answer = shopAction:InvokeServer(action, id)
			return result == true, str(answer, "")
		end)
		busy = false
		if not ok then
			toast("The shop didn't answer. Try again!", "error")
			return false
		end
		if message ~= "" then
			toast(message, if success then "ok" else "error")
		end
		refreshMenu()
		return success
	end

	-- SHOP + TRAILS ---------------------------------------------------
	type ShopItem = { Id: string, Name: string, Category: string, Price: number, Desc: string, Color: Color3 }
	local shopRows: { { Item: ShopItem, Row: Row } } = {}

	local function onShopClicked(item: ShopItem)
		playSound(clickSound)
		local owned = attrTrue(player, "Owned_" .. item.Id)
		if item.Category == "Trail" then
			if not owned then
				runShopAction("Buy", item.Id)
			elseif attrString(player, "EquippedTrail", "") == item.Id then
				runShopAction("Unequip", item.Id)
			else
				runShopAction("Equip", item.Id)
			end
		elseif owned then
			toast("You own the " .. item.Name .. ". It's in your backpack!", "info")
		else
			runShopAction("Buy", item.Id)
		end
	end

	local function buildShop()
		local data = attrJSON("ShopItems")
		clearPage(pages.SHOP)
		clearPage(pages.TRAILS)
		table.clear(shopRows)
		pageNote(pages.SHOP, 0, "Coils stay in your backpack forever. Hold one to use it!")
		pageNote(pages.TRAILS, 0, "Wear one trail at a time. Tap EQUIP to put it on.")
		if type(data) ~= "table" then
			return
		end
		for order, entry in ipairs(data) do
			if type(entry) == "table" then
				local item: ShopItem = {
					Id = str(entry.Id, ""),
					Name = str(entry.Name, "Item"),
					Category = str(entry.Category, "Gear"),
					Price = num(entry.Price, 0),
					Desc = str(entry.Desc, ""),
					Color = hexColor(entry.Color, GOLD),
				}
				if item.Id ~= "" then
					local isTrail = item.Category == "Trail"
					local page = if isTrail then pages.TRAILS else pages.SHOP
					local icon = if isTrail then trailIcon(item.Color) else coilIcon(item.Color)
					local row = makeRow(page, order, item.Name, item.Desc, icon)
					row.Button.Activated:Connect(function()
						onShopClicked(item)
					end)
					table.insert(shopRows, { Item = item, Row = row })
				end
			end
		end
	end

	local function refreshShop(coins: number)
		local equipped = attrString(player, "EquippedTrail", "")
		for _, entry in ipairs(shopRows) do
			local item, row = entry.Item, entry.Row
			local owned = attrTrue(player, "Owned_" .. item.Id)
			row.Badge.Visible = false
			if owned and item.Category == "Trail" then
				if equipped == item.Id then
					setButton(row, "UNEQUIP", RED, false, true)
					row.Badge.Visible = true
				else
					setButton(row, "EQUIP", BLUE, false, true)
				end
			elseif owned then
				setButton(row, "OWNED", DARK_GREEN, false, false)
			else
				local canAfford = coins >= item.Price
				setButton(row, formatNumber(item.Price), if canAfford then GREEN else GREY, true, canAfford)
			end
		end
	end

	-- PASSES (Robux) ---------------------------------------------------
	type PassInfo = { Key: string, Name: string, Desc: string, Id: number }
	local passRows: { { Pass: PassInfo, Row: Row } } = {}
	local passPrices: { [number]: number } = {}
	local PASS_ICONS: { [string]: string } = {
		X2Coins = "x2",
		DoubleJump = "JUMP",
		SkipSection = "SKIP",
		VIP = "VIP",
		NuggetTrail = "NUG",
	}

	local function fetchPassPrice(passId: number)
		if passId <= 0 or passPrices[passId] then
			return
		end
		task.spawn(function()
			local ok, info = pcall(function(): { [string]: any }
				return MarketplaceService:GetProductInfoAsync(passId, Enum.InfoType.GamePass)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				passPrices[passId] = info.PriceInRobux
				refreshMenu()
			end
		end)
	end

	local function onPassClicked(pass: PassInfo)
		playSound(clickSound)
		if attrTrue(player, "Pass_" .. pass.Key) then
			toast("You already own " .. pass.Name .. "!", "info")
		elseif pass.Id == 0 then
			toast(pass.Name .. " is coming soon!", "info")
		else
			promptPassEvent:FireServer(pass.Key)
		end
	end

	local function buildPasses()
		local data = attrJSON("Passes")
		clearPage(pages.PASSES)
		table.clear(passRows)
		pageNote(pages.PASSES, 0, "Passes are bought with Robux and last forever.")
		if type(data) ~= "table" then
			return
		end
		for order, entry in ipairs(data) do
			if type(entry) == "table" then
				local pass: PassInfo = {
					Key = str(entry.Key, ""),
					Name = str(entry.Name, "Pass"),
					Desc = str(entry.Desc, ""),
					Id = num(entry.Id, 0),
				}
				if pass.Key ~= "" then
					local glyph = PASS_ICONS[pass.Key] or string.upper(string.sub(pass.Name, 1, 3))
					local row = makeRow(pages.PASSES, order, pass.Name, pass.Desc, glyphIcon(GOLD, glyph, PANEL))
					row.Button.Activated:Connect(function()
						onPassClicked(pass)
					end)
					table.insert(passRows, { Pass = pass, Row = row })
					fetchPassPrice(pass.Id)
				end
			end
		end
	end

	local function refreshPasses()
		for _, entry in ipairs(passRows) do
			local pass, row = entry.Pass, entry.Row
			if attrTrue(player, "Pass_" .. pass.Key) then
				setButton(row, "OWNED", DARK_GREEN, false, false)
			elseif pass.Id == 0 then
				setButton(row, "Coming soon", GREY, false, false)
			else
				local price = passPrices[pass.Id]
				setButton(row, if price then "R$ " .. formatNumber(price) else "BUY", GREEN, false, true)
			end
		end
	end

	-- SKILLS -------------------------------------------------------------
	type SkillInfo = { Id: string, Name: string, Desc: string, Max: number }
	local skillRows: { { Skill: SkillInfo, Row: Row, Pips: { Frame } } } = {}
	local pointsHeader: TextLabel? = nil
	local SKILL_LOOKS: { [string]: { Color: Color3, Glyph: string } } = {
		Speed = { Color = Color3.fromRGB(70, 160, 255), Glyph = "»" },
		Jump = { Color = Color3.fromRGB(110, 210, 110), Glyph = "↑" },
		Coins = { Color = GOLD, Glyph = "$" },
		XP = { Color = Color3.fromRGB(190, 110, 255), Glyph = "XP" },
	}

	local function onSkillClicked(skill: SkillInfo)
		playSound(clickSound)
		if attrNumber(player, "Skill_" .. skill.Id, 0) >= skill.Max then
			toast(skill.Name .. " is already maxed out!", "info")
		elseif attrNumber(player, "SkillPoints", 0) < 1 then
			toast("No skill points left. Level up to get more!", "error")
		else
			runShopAction("Skill", skill.Id)
		end
	end

	local function buildSkills()
		local data = attrJSON("Skills")
		clearPage(pages.SKILLS)
		table.clear(skillRows)
		pointsHeader = text({
			Name = "Points",
			Size = UDim2.new(1, 0, 0, 30),
			Font = FONT_BIG,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Skill points: 0",
			LayoutOrder = -2,
			Parent = pages.SKILLS,
		})
		pageNote(pages.SKILLS, -1, "You get 1 skill point every time you level up.")
		if type(data) ~= "table" then
			return
		end
		for order, entry in ipairs(data) do
			if type(entry) == "table" then
				local skill: SkillInfo = {
					Id = str(entry.Id, ""),
					Name = str(entry.Name, "Skill"),
					Desc = str(entry.Desc, ""),
					Max = math.max(1, math.floor(num(entry.Max, 10))),
				}
				if skill.Id ~= "" then
					local look = SKILL_LOOKS[skill.Id]
					local icon = if look
						then glyphIcon(look.Color, look.Glyph, WHITE)
						else glyphIcon(BLUE, string.upper(string.sub(skill.Name, 1, 1)), WHITE)
					local row = makeRow(pages.SKILLS, order, skill.Name, skill.Desc, icon)
					row.Extra.Visible = true
					row.Desc.Size = UDim2.new(1, -310, 0, 16)
					-- little boxes that fill up as the skill levels up
					local pipHolder = frame({
						Name = "Pips",
						Position = UDim2.fromOffset(72, 56),
						Size = UDim2.fromOffset(200, 8),
						Parent = row.Frame,
					})
					listLayout(pipHolder, true, 3, nil, nil)
					local pipCount = math.min(skill.Max, 20)
					local pipWidth = math.clamp(math.floor(170 / pipCount) - 3, 3, 14)
					local pips: { Frame } = {}
					for i = 1, pipCount do
						local pip = frame({
							Size = UDim2.fromOffset(pipWidth, 8),
							BackgroundTransparency = 0,
							BackgroundColor3 = GREY,
							LayoutOrder = i,
							Parent = pipHolder,
						})
						corner(pip, 3)
						table.insert(pips, pip)
					end
					row.Button.Activated:Connect(function()
						onSkillClicked(skill)
					end)
					table.insert(skillRows, { Skill = skill, Row = row, Pips = pips })
				end
			end
		end
	end

	local function refreshSkills()
		local points = attrNumber(player, "SkillPoints", 0)
		local header = pointsHeader
		if header then
			header.Text = "Skill points: " .. formatNumber(points)
			header.TextColor3 = if points > 0 then GOLD else WHITE
		end
		skillsBadge.Visible = points > 0
		skillsBadge.Text = if points > 99 then "99" else formatNumber(points)
		for _, entry in ipairs(skillRows) do
			local skill, row = entry.Skill, entry.Row
			local level = attrNumber(player, "Skill_" .. skill.Id, 0)
			row.Extra.Text = "Lv " .. formatNumber(level) .. "/" .. formatNumber(skill.Max)
			local filled = math.floor(level / skill.Max * #entry.Pips + 0.001)
			for i, pip in ipairs(entry.Pips) do
				pip.BackgroundColor3 = if i <= filled then GOLD else GREY
			end
			if level >= skill.Max then
				setButton(row, "MAX", DARK_GREEN, false, false)
			else
				setButton(row, "+", if points > 0 then GREEN else GREY, false, points > 0)
			end
		end
	end

	-- CODES ----------------------------------------------------------------
	do
		local page = pages.CODES
		pageNote(page, 0, "Got a code? Type it here for free coins! Each code works once.")
		local codeRow = frame({
			Name = "CodeRow",
			Size = UDim2.new(1, 0, 0, 56),
			LayoutOrder = 1,
			Parent = page,
		})
		local codeBox = make("TextBox", {
			Name = "CodeBox",
			Size = UDim2.new(1, -170, 1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = CARD,
			Font = FONT_BOLD,
			TextSize = 22,
			TextColor3 = WHITE,
			PlaceholderText = "Type a code here",
			PlaceholderColor3 = SOFT_TEXT,
			Text = "",
			ClearTextOnFocus = false,
			Parent = codeRow,
		}) :: TextBox
		corner(codeBox, 12)
		border(codeBox, 2, WHITE, 0.8)
		local redeemButton = textButton({
			Name = "Redeem",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 156, 1, 0),
			BackgroundColor3 = GREEN,
			TextSize = 20,
			Text = "REDEEM",
			Parent = codeRow,
		})
		corner(redeemButton, 12)

		local function redeem()
			local code = string.gsub(codeBox.Text, "^%s*(.-)%s*$", "%1")
			if code == "" then
				toast("Type a code first!", "error")
				return
			end
			if runShopAction("Redeem", code) then
				codeBox.Text = ""
			end
		end

		redeemButton.Activated:Connect(function()
			playSound(clickSound)
			redeem()
		end)
		codeBox.FocusLost:Connect(function(enterPressed: boolean)
			if enterPressed then
				redeem()
			end
		end)
	end

	-- SETTINGS -------------------------------------------------------------
	type Toggle = { Switch: TextButton, Knob: Frame, State: TextLabel, Get: () -> boolean }
	local toggles: { Toggle } = {}

	local function refreshToggles()
		for _, toggle in ipairs(toggles) do
			local on = toggle.Get()
			toggle.Switch.BackgroundColor3 = if on then GREEN else GREY
			toggle.State.Text = if on then "ON" else "OFF"
			toggle.State.TextColor3 = if on then KIND_COLORS.ok else SOFT_TEXT
			TweenService:Create(toggle.Knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(if on then 0.72 else 0.28, 0.5),
			}):Play()
		end
	end

	local function makeToggle(order: number, label: string, desc: string, get: () -> boolean, set: (boolean) -> ())
		local row = frame({
			Name = label,
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundTransparency = 0,
			BackgroundColor3 = CARD,
			LayoutOrder = order,
			Parent = pages.SETTINGS,
		})
		corner(row, 14)
		text({
			Position = UDim2.fromOffset(18, 10),
			Size = UDim2.new(1, -200, 0, 24),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = label,
			Parent = row,
		})
		text({
			Position = UDim2.fromOffset(18, 36),
			Size = UDim2.new(1, -200, 0, 18),
			Font = FONT_TEXT,
			TextSize = 15,
			TextColor3 = SOFT_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = desc,
			Parent = row,
		})
		local state = text({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -96, 0.5, 0),
			Size = UDim2.fromOffset(50, 24),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		local switch = textButton({
			Name = "Switch",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(68, 34),
			Parent = row,
		})
		circle(switch)
		local knob = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.28, 0.5),
			Size = UDim2.fromOffset(26, 26),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			Parent = switch,
		})
		circle(knob)
		switch.Activated:Connect(function()
			playSound(clickSound)
			set(not get())
			refreshToggles()
		end)
		table.insert(toggles, { Switch = switch, Knob = knob, State = state, Get = get })
	end

	makeToggle(1, "Music", "Play the game's songs", isMusicOn, setMusicOn)
	makeToggle(2, "Hide other players", "See only yourself (handy when it's busy)", isHidingOthers, setHideOthers)
	makeToggle(3, "Show progress bar", "The bar with everyone's faces on the right", function(): boolean
		return progressRoot.Visible
	end, function(on: boolean)
		progressRoot.Visible = on
	end)

	-- OPEN / CLOSE ---------------------------------------------------------
	function refreshMenu()
		local coins = attrNumber(player, "Coins", 0)
		coinsText.Text = formatNumber(coins)
		refreshShop(coins)
		refreshPasses()
		refreshSkills()
		refreshToggles()
	end

	-- which = "ShopItems", "Passes" or "Skills" (nil = all of them)
	function rebuildMenuLists(which: string?)
		if which == nil or which == "ShopItems" then
			buildShop()
		end
		if which == nil or which == "Passes" then
			buildPasses()
		end
		if which == nil or which == "Skills" then
			buildSkills()
		end
		refreshMenu()
	end

	local function closeMenu()
		menuRoot.Visible = false
		placeToasts(false)
	end

	function openMenu(tab: string?)
		selectTab(tab or currentTab)
		refreshMenu()
		if not menuRoot.Visible then
			menuRoot.Visible = true
			placeToasts(menuCrowdsToasts)
			playSound(swooshSound)
			menuScale.Scale = menuFit * 0.92
			TweenService:Create(menuScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = menuFit }):Play()
		end
	end

	function toggleMenu()
		if menuRoot.Visible then
			closeMenu()
		else
			openMenu(nil)
		end
	end

	closeButton.Activated:Connect(function()
		playSound(clickSound)
		closeMenu()
	end)

	-- the Roblox Esc menu closes ours too, so nothing gets stuck open
	GuiService.MenuOpened:Connect(closeMenu)

	-- M key opens/closes the Menu on a computer
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.M then
			toggleMenu()
		end
	end)
end

------------------------------------------------------------------------
-- VIP CHAT TAG: a gold [VIP] in front of VIP players' chat messages
------------------------------------------------------------------------
do
	local TextChatService = game:GetService("TextChatService")
	local ok, err = pcall(function(): string?
		if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
			return nil
		end
		TextChatService.OnIncomingMessage = function(message: TextChatMessage)
			local properties = Instance.new("TextChatMessageProperties")
			pcall(function()
				local source = message.TextSource
				if source then
					local sender = Players:GetPlayerByUserId(source.UserId)
					if sender and sender:GetAttribute("Pass_VIP") == true then
						properties.PrefixText = "<font color=\"#FFC42E\">[VIP]</font> " .. message.PrefixText
					end
				end
			end)
			return properties
		end
		return nil
	end)
	if not ok then
		warn("[TowerOfFood] Could not set up the VIP chat tag: " .. tostring(err))
	end
end

------------------------------------------------------------------------
-- HOOKING IT ALL UP
------------------------------------------------------------------------
-- messages from the server
notifyEvent.OnClientEvent:Connect(function(message: any, kind: any)
	local textValue = str(message, "")
	local kindValue = str(kind, "info")
	if textValue == "" then
		return
	end
	toast(textValue, kindValue)
	if kindValue == "win" then
		queueAnnouncement("win", textValue)
	elseif kindValue == "level" then
		levelFlash()
		queueAnnouncement("level", "LEVEL UP!")
	end
end)

-- a new tower every round
local lastRoundId: number? = nil
local function onRoundChanged()
	local roundId = gameFolder:GetAttribute("RoundId")
	if type(roundId) ~= "number" or roundId == lastRoundId then
		return
	end
	local firstLook = lastRoundId == nil
	lastRoundId = roundId
	earnedThisRound = 0
	-- wait a moment so the new Layout has arrived too
	task.delay(if firstLook then 2 else 0.4, function()
		layout = readLayout()
		rebuildBar()
		showTowerBanner(if firstLook then "TOWER OF FOOD" else "NEW TOWER!")
	end)
end

player.AttributeChanged:Connect(function(name: string)
	if name == "Coins" then
		onCoinsChanged()
		refreshMenu()
	elseif name == "Level" or name == "LevelXP" or name == "LevelNeed" or name == "SkillPoints" then
		refreshLevel()
		refreshMenu()
	elseif name == "EquippedTrail" or string.sub(name, 1, 6) == "Owned_" or string.sub(name, 1, 6) == "Skill_" or string.sub(name, 1, 5) == "Pass_" then
		refreshMenu()
	end
end)

gameFolder.AttributeChanged:Connect(function(name: string)
	if name == "Layout" then
		layout = readLayout()
		rebuildBar()
	elseif name == "RoundId" then
		onRoundChanged()
	elseif name == "MutatorLabel" then
		refreshMutator()
	elseif name == "ShopItems" or name == "Skills" or name == "Passes" then
		rebuildMenuLists(name)
	elseif name == "Music" then
		loadMusicList()
	end
end)

Players.PlayerAdded:Connect(function(who: Player)
	addMarker(who)
end)
Players.PlayerRemoving:Connect(function(who: Player)
	removeMarker(who)
end)
for _, other in ipairs(Players:GetPlayers()) do
	addMarker(other)
end

-- re-fit the screen when it changes size or you switch between touch and keyboard
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	relayout()
end)
UserInputService.LastInputTypeChanged:Connect(function()
	if detectTouch() ~= isTouch then
		relayout()
	end
end)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		relayout()
	end)
end)

-- every frame: smooth animations. 10 times a second: everything else.
local slowTimer = 0
RunService.RenderStepped:Connect(function(dt: number)
	updateCoinAnimation()
	updateMarkers(dt)
	if isHidingOthers() then
		hideOthersStep()
	end
	slowTimer += dt
	if slowTimer >= 0.1 then
		slowTimer = 0
		updateTimer()
		updateMarkerTargets()
		updateSkipButton()
		updateHotbarShift()
	end
end)

-- fill everything in for the first time
relayout()
layout = readLayout()
rebuildBar()
refreshMutator()
updateTimer()
refreshLevel()
onCoinsChanged()
rebuildMenuLists()
selectTab("SHOP")
setMusicOn(true)
loadMusicList()
onRoundChanged()
