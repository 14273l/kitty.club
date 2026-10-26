--[[
	KittyLib - Roblox UI Library
	Usage:  local Library = loadstring(readfile("KittyLib.lua"))()   -- or paste this source
]]

local Players          = game:GetService("Players")
local UIS              = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local GuiService       = game:GetService("GuiService")
local CoreGui          = game:GetService("CoreGui")

-- Re-execution guard
do
	local env = (getgenv and getgenv()) or _G
	if env.__KittyLib then pcall(function() env.__KittyLib:Unload() end) end
end

----------------------------------------------------------------------------------------------------
-- Feature detection (older clients lack FontFace / UIFlexAlignment)
----------------------------------------------------------------------------------------------------
local hasFontFace = false
do
	local ok = pcall(function()
		local lbl = Instance.new("TextLabel")
		lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	end)
	hasFontFace = ok
end

local function makeFont(family, weight)
	if not hasFontFace then return nil end
	local ok, f = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight, Enum.FontStyle.Normal)
	end)
	return ok and f or nil
end

local fontRegular = makeFont("Zekton", Enum.FontWeight.Regular)
local fontBold    = makeFont("Zekton", Enum.FontWeight.Bold)
if not fontRegular or not fontBold then
	-- Zekton not available (or Font datatype missing) – fall back to the legacy font API
	hasFontFace = false
	fontRegular = Enum.Font.Gotham
	fontBold    = Enum.Font.GothamBold
end

local hasFlex = Enum.UIFlexAlignment ~= nil

local Library = {
	Flags = {}, Options = {}, Windows = {}, Keybinds = {}, Connections = {}, Themed = {},
	Listening = false, ActivePopup = nil, FPS = 60, ConfigFolder = "KittyClub",
	Theme = {
		Accent  = Color3.fromRGB(255, 120, 190),
		Main    = Color3.fromRGB(25, 26, 26),
		Panel   = Color3.fromRGB(27, 27, 27),
		Element = Color3.fromRGB(30, 30, 30),
		Dark    = Color3.fromRGB(21, 21, 21),
		Outline = Color3.fromRGB(51, 51, 51),
		Text    = Color3.fromRGB(255, 255, 255),
		SubText = Color3.fromRGB(134, 134, 135),
	},
	Settings = {
		AnimSpeed    = 1,
		EasingStyle  = Enum.EasingStyle.Quint,
		EasingDirection = Enum.EasingDirection.Out,
		SliderSmooth = 0.5,
		TextStroke   = 0.6,
	},
	Font     = fontRegular,
	FontBold = fontBold,
}
do
	local env = (getgenv and getgenv()) or _G
	env.__KittyLib = Library
end

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------
local TextClasses = { TextLabel = true, TextButton = true, TextBox = true }

function Library:Bind(obj, prop, key)
	obj[prop] = self.Theme[key]
	table.insert(self.Themed, { Obj = obj, Prop = prop, Key = key })
end

local function Create(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	if class == "TextButton" or class == "ImageButton" then o.AutoButtonColor = false end
	if TextClasses[class] then
		if hasFontFace then
			o.FontFace = Library.Font
		else
			o.Font = Library.Font
		end
		o.TextSize = 12
		o.Text = ""
		o.TextColor3 = Library.Theme.Text
		o.BackgroundTransparency = 1
		o.TextStrokeTransparency = Library.Settings.TextStroke
	end
	local theme = props.Theme
	for k, v in pairs(props) do
		if k ~= "Theme" then
			-- Translate FontFace prop to legacy Font prop on older clients
			if k == "FontFace" and not hasFontFace then
				o.Font = v
			else
				o[k] = v
			end
		end
	end
	if theme then
		for p, key in pairs(theme) do Library:Bind(o, p, key) end
	end
	if parent then o.Parent = parent end
	return o
end

local function Stroke(parent, key)
	return Create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Theme = { Color = key or "Outline" },
	}, parent)
end

function Library:Dur(t)
	local speed = self.Settings.AnimSpeed
	if speed <= 0 then return 0 end
	return t / speed
end

function Library:Tween(obj, props, t, style, dir)
	local speed = self.Settings.AnimSpeed
	if speed <= 0 then
		for k, v in pairs(props) do obj[k] = v end
		return nil
	end
	local tw = TweenService:Create(obj, TweenInfo.new((t or 0.2) / speed, style or self.Settings.EasingStyle, dir or self.Settings.EasingDirection), props)
	tw:Play()
	return tw
end

function Library:Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.Connections, c)
	return c
end

local function Fire(obj, ...)
	if obj.Callback then task.spawn(obj.Callback, ...) end
	for _, f in ipairs(obj._changed) do task.spawn(f, ...) end
end

local function Register(obj, flag, opts)
	obj.Flag = flag
	obj._changed = {}
	obj.Callback = opts.Callback
	obj.SkipConfig = opts.SkipConfig
	function obj:OnChanged(f) table.insert(self._changed, f) return self end
	Library.Options[flag] = obj
end

local function InputName(i)
	if i.UserInputType == Enum.UserInputType.Keyboard then return i.KeyCode.Name end
	local n = i.UserInputType.Name
	if n:find("MouseButton") then return n end
	return nil
end

local function ShortKey(n)
	return (n:gsub("MouseButton", "M"):gsub("Left", "L"):gsub("Right", "R"):gsub("Control", "Ctrl"))
end

local function ToHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function FromHex(s)
	local r, g, b = tostring(s):match("#?(%x%x)(%x%x)(%x%x)")
	if not r then return nil end
	return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end

local function ScreenPos(i)
	if i.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		return Vector2.new(i.Position.X + inset.X, i.Position.Y + inset.Y)
	end
	return UIS:GetMouseLocation()
end

local function Dragger(obj, onChange, onBegin, onEnd)
	obj.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if onBegin then onBegin() end
		onChange(ScreenPos(input))
		local moveC, endC
		moveC = UIS.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				onChange(ScreenPos(i))
			end
		end)
		endC = UIS.InputEnded:Connect(function(i)
			if i.UserInputType == input.UserInputType then
				moveC:Disconnect(); endC:Disconnect()
				if onEnd then onEnd() end
			end
		end)
	end)
end

local function MakeDraggable(handle, target)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local start, origin = input.Position, target.Position
		local moveC, endC
		moveC = UIS.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				local d = i.Position - start
				TweenService:Create(target, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y),
				}):Play()
			end
		end)
		endC = UIS.InputEnded:Connect(function(i)
			if i.UserInputType == input.UserInputType then moveC:Disconnect(); endC:Disconnect() end
		end)
	end)
end

----------------------------------------------------------------------------------------------------
-- Root GUI
----------------------------------------------------------------------------------------------------
local Gui = Create("ScreenGui", {
	Name = "KittyLib", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
})
do
	local ok = pcall(function() Gui.Parent = (gethui and gethui()) or CoreGui end)
	if not ok then Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
end
Library.Gui = Gui

Library.Overlay = Create("Frame", { Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 }, Gui)
local NotifyHolder = Create("Frame", {
	Name = "Notifications", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 270, 1, -24), BackgroundTransparency = 1, ZIndex = 20,
}, Gui)
Create("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, NotifyHolder)

function Library:Unload()
	if self.Unloaded then return end
	self.Unloaded = true
	for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
	table.clear(self.Connections)
	for _, kb in ipairs(self.Keybinds) do
		if kb._captureConn then pcall(function() kb._captureConn:Disconnect() end) end
	end
	table.clear(self.Keybinds)
	pcall(function() Gui:Destroy() end)
	if self.OnUnload then pcall(self.OnUnload) end
	local env = (getgenv and getgenv()) or _G
	if env.__KittyLib == self then env.__KittyLib = nil end
end

function Library:SetTheme(key, color)
	self.Theme[key] = color
	for i = #self.Themed, 1, -1 do
		local e = self.Themed[i]
		if e.Obj.Parent == nil then
			table.remove(self.Themed, i)
		elseif e.Key == key then
			self:Tween(e.Obj, { [e.Prop] = color }, 0.25)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Popups
----------------------------------------------------------------------------------------------------
function Library:MakePopup(anchor, size, gap, alignRight)
	local ov = self.Overlay
	local aPos = anchor.AbsolutePosition - ov.AbsolutePosition
	local pos = Vector2.new(alignRight and (aPos.X + anchor.AbsoluteSize.X - size.X) or aPos.X, aPos.Y + anchor.AbsoluteSize.Y + (gap or 4))
	local bounds = ov.AbsoluteSize
	pos = Vector2.new(math.clamp(pos.X, 4, math.max(4, bounds.X - size.X - 4)), pos.Y)
	if pos.Y + size.Y > bounds.Y - 4 then pos = Vector2.new(pos.X, aPos.Y - size.Y - (gap or 4)) end

	local group = Create("CanvasGroup", {
		Size = UDim2.fromOffset(size.X, size.Y), Position = UDim2.fromOffset(pos.X, pos.Y + 6),
		GroupTransparency = 1, Theme = { BackgroundColor3 = "Main" },
	})
	local border = Create("Frame", { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1, ZIndex = 50 }, group)
	Stroke(border)
	return group, pos
end

function Library:OpenPopup(group, pos, owner, onClose)
	self:ClosePopup()
	local blocker = Create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 1 }, self.Overlay)
	group.ZIndex = 2
	group.Parent = self.Overlay
	self.ActivePopup = { Group = group, Blocker = blocker, Owner = owner, OnClose = onClose }
	blocker.MouseButton1Down:Connect(function() Library:ClosePopup() end)
	blocker.MouseButton2Down:Connect(function() Library:ClosePopup() end)
	self:Tween(group, { GroupTransparency = 0, Position = UDim2.fromOffset(pos.X, pos.Y) }, 0.2)
end

function Library:ClosePopup()
	local p = self.ActivePopup
	if not p then return end
	self.ActivePopup = nil
	p.Blocker:Destroy()
	if p.OnClose then p.OnClose() end
	local tw = self:Tween(p.Group, { GroupTransparency = 1, Position = p.Group.Position + UDim2.fromOffset(0, 4) }, 0.15)
	if tw then tw.Completed:Connect(function() p.Group:Destroy() end) else p.Group:Destroy() end
end

----------------------------------------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------------------------------------
local NotifyColors = {
	Info = nil, Success = Color3.fromRGB(90, 220, 130), Warning = Color3.fromRGB(255, 200, 80), Error = Color3.fromRGB(255, 90, 90),
}

function Library:Notify(text, duration, kind)
	duration = duration or 4
	local wrapper = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }, NotifyHolder)
	local inner = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1.2, 0, 0, 0), Theme = { BackgroundColor3 = "Main" },
	}, wrapper)
	Stroke(inner)
	local color = NotifyColors[kind or "Info"]
	local side = Create("Frame", { Size = UDim2.new(0, 2, 1, 0) }, inner)
	if color then side.BackgroundColor3 = color else Library:Bind(side, "BackgroundColor3", "Accent") end
	local label = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = tostring(text), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, inner)
	Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 9) }, label)
	local bar = Create("Frame", { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0.3 }, inner)
	if color then bar.BackgroundColor3 = color else Library:Bind(bar, "BackgroundColor3", "Accent") end

	task.spawn(function()
		local tries = 0
		while inner.AbsoluteSize.Y <= 0 and tries < 10 do
			tries += 1
			RunService.Heartbeat:Wait()
		end
		if Library.Unloaded then return end
		local h = inner.AbsoluteSize.Y
		self:Tween(wrapper, { Size = UDim2.new(1, 0, 0, h) }, 0.25)
		self:Tween(inner, { Position = UDim2.new(0, 0, 0, 0) }, 0.35, Enum.EasingStyle.Back)
		TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
		task.wait(duration)
		if Library.Unloaded then return end
		self:Tween(inner, { Position = UDim2.new(1.2, 0, 0, 0) }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(self:Dur(0.3))
		self:Tween(wrapper, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
		task.wait(self:Dur(0.25))
		wrapper:Destroy()
	end)
end

----------------------------------------------------------------------------------------------------
-- Watermark
----------------------------------------------------------------------------------------------------
function Library:CreateWatermark(title)
	local frame = Create("Frame", {
		Name = "WaterMark_Window", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
		Position = UDim2.fromOffset(20, 20), Theme = { BackgroundColor3 = "Main" },
	}, Gui)
	Stroke(frame)
	local line = Create("Frame", { Size = UDim2.new(1, 0, 0, 1), Theme = { BackgroundColor3 = "Accent" } }, frame)
	Create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, line)
	local label = Create("TextLabel", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = title }, frame)
	Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, label)
	local hit = Create("TextButton", { Size = UDim2.fromScale(1, 1) }, frame)
	MakeDraggable(hit, frame)

	local wm = { Frame = frame, Label = label, Title = title }
	function wm:Update()
		label.Text = string.format("%s | %d fps | %s", self.Title, Library.FPS, os.date("%H:%M"))
	end
	function wm:SetVisible(v) frame.Visible = v end
	wm:Update()
	self.Watermark = wm
	return wm
end

function Library:SetWatermarkVisible(v)
	if self.Watermark then self.Watermark:SetVisible(v) end
end

do -- fps counter
	local frames, last = 0, os.clock()
	Library:Connect(RunService.RenderStepped, function()
		frames += 1
		local now = os.clock()
		if now - last >= 0.5 then
			Library.FPS = math.floor(frames / (now - last) + 0.5)
			frames, last = 0, now
			if Library.Watermark then Library.Watermark:Update() end
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Color picker
----------------------------------------------------------------------------------------------------
function Library:CreateColorPicker(holder, flag, opts)
	opts = opts or {}
	local obj = { Type = "ColorPicker", Alpha = opts.Alpha and true or false, Transparency = opts.Transparency or 0 }
	Register(obj, flag, opts)
	local default = opts.Default or Color3.new(1, 1, 1)
	obj.H, obj.S, obj.V = default:ToHSV()
	obj.Value = default

	local swatch = Create("TextButton", { Size = UDim2.fromOffset(24, 12), BackgroundColor3 = default, BackgroundTransparency = 0 }, holder)
	Stroke(swatch)
	Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180)) }, swatch)

	local function refresh(silent)
		obj.Value = Color3.fromHSV(obj.H, obj.S, obj.V)
		Library.Flags[flag] = obj.Value
		swatch.BackgroundColor3 = obj.Value
		local ui = obj.UI
		if ui then
			ui.SV.BackgroundColor3 = Color3.fromHSV(obj.H, 1, 1)
			ui.SVCursor.Position = UDim2.fromScale(obj.S, 1 - obj.V)
			ui.HueCursor.Position = UDim2.fromScale(obj.H, 0.5)
			if ui.AlphaBar then
				ui.AlphaBar.BackgroundColor3 = obj.Value
				ui.AlphaCursor.Position = UDim2.fromScale(obj.Transparency, 0.5)
			end
			if ui.Hex and not ui.Typing then ui.Hex.Text = ToHex(obj.Value) end
		end
		if not silent then Fire(obj, obj.Value, obj.Transparency) end
	end

	function obj:Set(color, transparency, silent)
		local oldColor, oldT = self.Value, self.Transparency
		self.H, self.S, self.V = color:ToHSV()
		if transparency then self.Transparency = transparency end
		local changed = (Color3.fromHSV(self.H, self.S, self.V) ~= oldColor) or (self.Transparency ~= oldT)
		refresh(silent or not changed)
	end

	function obj:Open()
		local W, H = 200, self.Alpha and 192 or 174
		local group, pos = Library:MakePopup(swatch, Vector2.new(W, H), 4, true)
		local ui = {}

		local sv = Create("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(180, 110), BackgroundColor3 = Color3.fromHSV(self.H, 1, 1) }, group)
		Stroke(sv)
		local white = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, sv)
		Create("UIGradient", { Transparency = NumberSequence.new(0, 1) }, white)
		local black = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0) }, sv)
		Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, black)
		local svCursor = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, ZIndex = 3 }, sv)
		Create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, svCursor)
		local svHit = Create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 4 }, sv)
		Dragger(svHit, function(p)
			self.S = math.clamp((p.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
			self.V = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
			refresh()
		end)
		ui.SV, ui.SVCursor = sv, svCursor

		local hue = Create("Frame", { Position = UDim2.fromOffset(10, 128), Size = UDim2.fromOffset(180, 10), BackgroundColor3 = Color3.new(1, 1, 1) }, group)
		Stroke(hue)
		Create("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}) }, hue)
		local hueCursor = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 14), ZIndex = 3 }, hue)
		Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hueCursor)
		local hueHit = Create("TextButton", { Position = UDim2.fromOffset(0, -3), Size = UDim2.new(1, 0, 1, 6), ZIndex = 4 }, hue)
		Dragger(hueHit, function(p)
			self.H = math.clamp((p.X - hue.AbsolutePosition.X) / hue.AbsoluteSize.X, 0, 0.999)
			refresh()
		end)
		ui.HueCursor = hueCursor

		if self.Alpha then
			local bg = Create("Frame", { Position = UDim2.fromOffset(10, 146), Size = UDim2.fromOffset(180, 10), Theme = { BackgroundColor3 = "Dark" } }, group)
			Stroke(bg)
			local bar = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = self.Value }, bg)
			Create("UIGradient", { Transparency = NumberSequence.new(0, 1) }, bar)
			local cur = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 14), ZIndex = 3 }, bg)
			Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, cur)
			local hit = Create("TextButton", { Position = UDim2.fromOffset(0, -3), Size = UDim2.new(1, 0, 1, 6), ZIndex = 4 }, bg)
			Dragger(hit, function(p)
				self.Transparency = math.clamp((p.X - bg.AbsolutePosition.X) / bg.AbsoluteSize.X, 0, 1)
				refresh()
			end)
			ui.AlphaBar, ui.AlphaCursor = bar, cur
		end

		local hexBg = Create("Frame", { Position = UDim2.fromOffset(10, H - 28), Size = UDim2.fromOffset(180, 18), Theme = { BackgroundColor3 = "Element" } }, group)
		Stroke(hexBg)
		local hex = Create("TextBox", { Size = UDim2.fromScale(1, 1), Text = ToHex(self.Value), ClearTextOnFocus = false, TextColor3 = Library.Theme.SubText }, hexBg)
		hex.Focused:Connect(function() ui.Typing = true end)
		hex.FocusLost:Connect(function()
			ui.Typing = false
			local c = FromHex(hex.Text)
			if c then self:Set(c) else hex.Text = ToHex(self.Value) end
		end)
		ui.Hex = hex

		self.UI = ui
		refresh(true)
		Library:OpenPopup(group, pos, self, function() self.UI = nil end)
	end

	swatch.MouseButton1Click:Connect(function() obj:Open() end)
	refresh(true)
	return obj
end

----------------------------------------------------------------------------------------------------
-- Keybind
----------------------------------------------------------------------------------------------------
function Library:CreateKeybind(holder, flag, opts)
	opts = opts or {}
	local obj = { Type = "KeyPicker", Key = nil, Mode = opts.Mode or "Toggle", State = false, NoTrigger = opts.NoTrigger, KeyChanged = opts.KeyChanged, Name = opts.Name or flag }
	Register(obj, flag, opts)

	local btn = Create("TextButton", { Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, Text = "[None]", TextColor3 = Library.Theme.SubText }, holder)
	Create("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2) }, btn)

	function obj:SetKey(name, silent)
		if typeof(name) == "EnumItem" then name = name.Name end
		self.Key = name
		btn.Text = "[" .. (name and ShortKey(name) or "None") .. "]"
		if self.KeyChanged and not silent then self.KeyChanged(name) end
	end

	function obj:SetState(b, silent)
		b = not not b
		if self.State == b then return end
		self.State = b
		Library.Flags[flag] = b
		if not silent then Fire(self, b) end
	end

	function obj:SetMode(m)
		self.Mode = m
		self:SetState(m == "Always")
	end

	btn.MouseButton1Click:Connect(function()
		if obj.Listening or Library.Listening then return end
		obj.Listening = true
		Library.Listening = true
		btn.Text = "[...]"
		btn.TextColor3 = Library.Theme.Accent
		local c
		c = UIS.InputBegan:Connect(function(i)
			local n = InputName(i)
			if not n then return end
			c:Disconnect()
			obj._captureConn = nil
			if n == "Escape" or n == "Backspace" then n = nil end
			obj:SetKey(n)
			btn.TextColor3 = Library.Theme.SubText
			task.delay(0.15, function() obj.Listening = false; Library.Listening = false end)
		end)
		obj._captureConn = c
	end)
	btn.MouseButton2Click:Connect(function()
		local order = { Toggle = "Hold", Hold = "Always", Always = "Toggle" }
		obj:SetMode(order[obj.Mode] or "Toggle")
		Library:Notify(obj.Name .. " mode: " .. obj.Mode, 1.5)
	end)

	obj:SetKey(opts.Default, true)
	if obj.Mode == "Always" then obj.State = true end
	Library.Flags[flag] = obj.State
	table.insert(Library.Keybinds, obj)
	return obj
end

Library:Connect(UIS.InputBegan, function(input)
	if UIS:GetFocusedTextBox() or Library.Listening then return end
	local name = InputName(input)
	if not name then return end
	for _, w in ipairs(Library.Windows) do
		if w.ToggleKey == name then w:SetVisible(not w.Open) end
	end
	for _, kb in ipairs(Library.Keybinds) do
		if not kb.NoTrigger and kb.Key == name then
			if kb.Mode == "Toggle" then kb:SetState(not kb.State)
			elseif kb.Mode == "Hold" then kb:SetState(true) end
		end
	end
end)
Library:Connect(UIS.InputEnded, function(input)
	local name = InputName(input)
	if not name then return end
	for _, kb in ipairs(Library.Keybinds) do
		if kb.Key == name and kb.Mode == "Hold" and not kb.NoTrigger then kb:SetState(false) end
	end
end)

----------------------------------------------------------------------------------------------------
-- Sections & elements
----------------------------------------------------------------------------------------------------
local Section = {}; Section.__index = Section
local Tab = {}; Tab.__index = Tab
local Window = {}; Window.__index = Window

function Section:_Flag(name, opts)
	return opts.Flag or (self.Tab.Name .. "/" .. self.Name .. "/" .. name)
end

local function MakeRow(self, height)
	local row = Create("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1 }, self.Container)
	local holder = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 3,
	}, row)
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	return row, holder
end

local function RowLabel(row, text, x)
	x = x or 0
	return Create("TextLabel", {
		Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x, 0, 16), Text = text,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Library.Theme.SubText,
	}, row)
end

local function AttachAddons(obj, holder, name)
	function obj:AddColorPicker(opts)
		opts = opts or {}
		return Library:CreateColorPicker(holder, opts.Flag or (obj.Flag .. "_Color"), opts)
	end
	function obj:AddKeybind(opts)
		opts = opts or {}
		opts.Name = opts.Name or name
		return Library:CreateKeybind(holder, opts.Flag or (obj.Flag .. "_Key"), opts)
	end
end

function Section:AddToggle(name, opts)
	opts = opts or {}
	local flag = self:_Flag(name, opts)
	local row, holder = MakeRow(self, 16)
	local box = Create("Frame", { Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(14, 14), Theme = { BackgroundColor3 = "Dark" } }, row)
	local boxStroke = Stroke(box)
	local fill = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), Theme = { BackgroundColor3 = "Accent" } }, box)
	Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) }, fill)
	local label = RowLabel(row, name, 22)
	local hit = Create("TextButton", { Size = UDim2.fromScale(1, 1) }, row)

	local obj = { Type = "Toggle", Value = false }
	Register(obj, flag, opts)
	function obj:Set(v, silent)
		v = not not v
		if self.Value == v then Library.Flags[flag] = v return end
		self.Value = v
		Library.Flags[flag] = v
		Library:Tween(fill, { Size = v and UDim2.new(1, -4, 1, -4) or UDim2.fromOffset(0, 0) }, 0.22, Enum.EasingStyle.Back)
		Library:Tween(label, { TextColor3 = v and Library.Theme.Text or Library.Theme.SubText }, 0.2)
		if not silent then Fire(self, v) end
	end
	hit.MouseButton1Click:Connect(function() obj:Set(not obj.Value) end)
	hit.MouseEnter:Connect(function() Library:Tween(boxStroke, { Color = Library.Theme.Accent }, 0.15) end)
	hit.MouseLeave:Connect(function() Library:Tween(boxStroke, { Color = Library.Theme.Outline }, 0.15) end)

	-- init without tweening (no flash on creation)
	obj.Value = opts.Default and true or false
	Library.Flags[flag] = obj.Value
	fill.Size = obj.Value and UDim2.new(1, -4, 1, -4) or UDim2.fromOffset(0, 0)
	label.TextColor3 = obj.Value and Library.Theme.Text or Library.Theme.SubText

	AttachAddons(obj, holder, name)
	return obj
end

function Section:AddSlider(name, opts)
	opts = opts or {}
	local flag = self:_Flag(name, opts)
	local min, max, rounding = opts.Min or 0, opts.Max or 100, opts.Rounding or 0
	local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, self.Container)
	RowLabel(row, name)
	local valueLabel = Create("TextLabel", { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Library.Theme.SubText }, row)
	local bar = Create("Frame", { Position = UDim2.fromOffset(0, 19), Size = UDim2.new(1, 0, 0, 9), Theme = { BackgroundColor3 = "Dark" } }, row)
	local barStroke = Stroke(bar)
	local fill = Create("Frame", { Size = UDim2.fromScale(0, 1), Theme = { BackgroundColor3 = "Accent" } }, bar)
	Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 165)) }, fill)
	local hit = Create("TextButton", { Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 17) }, row)

	local obj = { Type = "Slider", Min = min, Max = max }
	Register(obj, flag, opts)
	local shown, target, conn = 0, 0, nil

	local function animate()
		if conn then return end
		conn = RunService.RenderStepped:Connect(function(dt)
			local s = Library.Settings.SliderSmooth
			if s <= 0 or Library.Settings.AnimSpeed <= 0 then
				shown = target
			else
				local rate = 70 * (1 - s) + 7
				shown = shown + (target - shown) * (1 - math.exp(-rate * dt))
			end
			fill.Size = UDim2.new(shown, 0, 1, 0)
			if math.abs(target - shown) < 0.0005 then
				shown = target
				fill.Size = UDim2.new(shown, 0, 1, 0)
				conn:Disconnect(); conn = nil
			end
		end)
	end

	local function fmt(v)
		return (opts.Prefix or "") .. string.format("%." .. rounding .. "f", v) .. (opts.Suffix or "")
	end

	function obj:Set(v, silent)
		v = math.clamp(tonumber(v) or min, min, max)
		local m = 10 ^ rounding
		v = math.floor(v * m + 0.5) / m
		local changed = v ~= self.Value
		self.Value = v
		Library.Flags[flag] = v
		valueLabel.Text = fmt(v)
		target = (max == min) and 0 or (v - min) / (max - min)
		animate()
		if changed and not silent then Fire(self, v) end
	end

	Dragger(hit, function(p)
		local a = math.clamp((p.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		obj:Set(min + (max - min) * a)
	end, function() Library:Tween(barStroke, { Color = Library.Theme.Accent }, 0.15) end,
	function() Library:Tween(barStroke, { Color = Library.Theme.Outline }, 0.15) end)

	obj:Set(opts.Default or min, true)
	shown = target
	fill.Size = UDim2.new(shown, 0, 1, 0)
	return obj
end

function Section:AddDropdown(name, opts)
	opts = opts or {}
	local flag = self:_Flag(name, opts)
	local multi = opts.Multi
	local row = MakeRow(self, 38)
	RowLabel(row, name)
	local box = Create("TextButton", {
		Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = Library.Theme.SubText, BackgroundTransparency = 0,
		Theme = { BackgroundColor3 = "Dark" },
	}, row)
	local boxStroke = Stroke(box)
	Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 20) }, box)
	local arrow = Create("TextLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 16, 0.5, 0), Size = UDim2.fromOffset(14, 14), Text = "+" }, box)

	local obj = { Type = "Dropdown", Values = opts.Values or {}, Multi = multi, Value = multi and {} or nil }
	Register(obj, flag, opts)

	local function display()
		local txt
		if multi then
			local list = {}
			for _, v in ipairs(obj.Values) do if obj.Value[v] then list[#list + 1] = tostring(v) end end
			txt = #list > 0 and table.concat(list, ", ") or nil
		else
			txt = obj.Value ~= nil and tostring(obj.Value) or nil
		end
		box.Text = txt or "None"
		box.TextColor3 = txt and Library.Theme.Text or Library.Theme.SubText
	end

	function obj:Set(v, silent)
		if multi then
			local set = {}
			if type(v) == "table" then
				for k, val in pairs(v) do
					if type(val) == "boolean" then
						if val then set[k] = true end
					else
						set[val] = true
					end
				end
			end
			self.Value = set
		else
			if self.Value == v then Library.Flags[flag] = v; display() return end
			self.Value = v
		end
		Library.Flags[flag] = self.Value
		display()
		if not silent then Fire(self, self.Value) end
	end

	function obj:SetValues(vals)
		self.Values = vals
		if not multi and self.Value ~= nil and not table.find(vals, self.Value) then self:Set(nil, true) end
		display()
	end

	function obj:Open()
		if #self.Values == 0 then return end
		local n = #self.Values
		local vis = math.max(1, math.min(n, opts.MaxVisible or 6))
		local group, pos = Library:MakePopup(box, Vector2.new(box.AbsoluteSize.X, vis * 20 + 4), 2)
		local scroll = Create("ScrollingFrame", {
			Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1,
			ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Theme = { ScrollBarImageColor3 = "Accent" },
		}, group)
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		for _, val in ipairs(self.Values) do
			local b = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 20), Text = tostring(val), TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
			}, scroll)
			Create("UIPadding", { PaddingLeft = UDim.new(0, 6) }, b)
			local function selected() if multi then return self.Value[val] else return self.Value == val end end
			local function paint() Library:Tween(b, { TextColor3 = selected() and Library.Theme.Accent or Library.Theme.SubText }, 0.15) end
			b.TextColor3 = selected() and Library.Theme.Accent or Library.Theme.SubText
			b.MouseEnter:Connect(function() Library:Tween(b, { BackgroundTransparency = 0.92 }, 0.1) end)
			b.MouseLeave:Connect(function() Library:Tween(b, { BackgroundTransparency = 1 }, 0.1) end)
			b.MouseButton1Click:Connect(function()
				if multi then
					local nv = table.clone(self.Value)
					nv[val] = (not nv[val]) or nil
					self:Set(nv)
					paint()
				else
					self:Set(val)
					Library:ClosePopup()
				end
			end)
		end
		Library:OpenPopup(group, pos, self, function()
			arrow.Text = "+"
			Library:Tween(boxStroke, { Color = Library.Theme.Outline }, 0.15)
		end)
		arrow.Text = "-"
		Library:Tween(boxStroke, { Color = Library.Theme.Accent }, 0.15)
	end

	box.MouseButton1Click:Connect(function() obj:Open() end)
	local d = opts.Default
	if multi then obj:Set(d or {}, true) else obj:Set(d, true) end
	return obj
end

function Section:AddColorPicker(name, opts)
	opts = opts or {}
	local row, holder = MakeRow(self, 16)
	RowLabel(row, name)
	return Library:CreateColorPicker(holder, self:_Flag(name, opts), opts)
end

function Section:AddKeybind(name, opts)
	opts = opts or {}
	opts.Name = opts.Name or name
	local row, holder = MakeRow(self, 16)
	RowLabel(row, name)
	return Library:CreateKeybind(holder, self:_Flag(name, opts), opts)
end

function Section:AddTextbox(name, opts)
	opts = opts or {}
	local flag = self:_Flag(name, opts)
	local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, self.Container)
	RowLabel(row, name)
	local bg = Create("Frame", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 20), Theme = { BackgroundColor3 = "Dark" } }, row)
	local st = Stroke(bg)
	local box = Create("TextBox", {
		Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Left,
		PlaceholderText = opts.Placeholder or "", PlaceholderColor3 = Library.Theme.SubText, ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, bg)
	local obj = { Type = "Textbox", Value = "" }
	Register(obj, flag, opts)
	function obj:Set(t, silent)
		t = tostring(t or "")
		local changed = (self.Value ~= t)
		self.Value = t
		Library.Flags[flag] = t
		if box.Text ~= t then box.Text = t end
		if changed and not silent then Fire(self, t) end
	end
	box.Focused:Connect(function() Library:Tween(st, { Color = Library.Theme.Accent }, 0.15) end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if opts.Numeric then
			local f = box.Text:gsub("[^%d%.%-]", "")
			if f ~= box.Text then box.Text = f; return end
		end
		-- original behavior: silently update the value, fire only on FocusLost
		if not opts.Finished then
			obj.Value = box.Text
			Library.Flags[flag] = box.Text
		end
	end)
	box.FocusLost:Connect(function()
		Library:Tween(st, { Color = Library.Theme.Outline }, 0.15)
		obj:Set(box.Text)
	end)
	obj:Set(opts.Default, true)
	return obj
end

function Section:AddButton(name, opts)
	if type(opts) == "function" then opts = { Callback = opts } end
	opts = opts or {}
	local btn = Create("TextButton", { Size = UDim2.new(1, 0, 0, 22), Text = name, BackgroundTransparency = 0, Theme = { BackgroundColor3 = "Dark" } }, self.Container)
	local st = Stroke(btn)
	Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)) }, btn)
	local obj = { Type = "Button", Callback = opts.Callback }
	btn.MouseEnter:Connect(function() Library:Tween(btn, { BackgroundColor3 = Color3.fromRGB(40, 40, 40) }, 0.15) end)
	btn.MouseLeave:Connect(function() Library:Tween(btn, { BackgroundColor3 = Library.Theme.Dark }, 0.15) end)
	btn.MouseButton1Click:Connect(function()
		st.Color = Library.Theme.Accent
		Library:Tween(st, { Color = Library.Theme.Outline }, 0.35)
		if obj.Callback then task.spawn(obj.Callback) end
	end)
	function obj:SetText(t) btn.Text = t end
	return obj
end

function Section:AddLabel(text, opts)
	local l = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Library.Theme.SubText,
	}, self.Container)
	local obj = {}
	function obj:SetText(t) l.Text = t end
	return obj
end

function Section:AddDivider()
	return Create("Frame", { Size = UDim2.new(1, 0, 0, 1), Theme = { BackgroundColor3 = "Outline" } }, self.Container)
end

----------------------------------------------------------------------------------------------------
-- Tab
----------------------------------------------------------------------------------------------------
function Tab:AddSection(name, side)
	if not side then side = (#self.Left.Sections <= #self.Right.Sections) and "Left" or "Right" end
	local col = side == "Right" and self.Right or self.Left
	local card = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Theme = { BackgroundColor3 = "Element" } }, col.Frame)
	Stroke(card)
	Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 9), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, card)
	Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	local head = Create("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 0 }, card)
	Create("TextLabel", { Size = UDim2.new(1, 0, 0, 14), Text = name, TextXAlignment = Enum.TextXAlignment.Left, FontFace = Library.FontBold }, head)
	local line = Create("Frame", { Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), Theme = { BackgroundColor3 = "Accent" } }, head)
	Create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, line)
	local container = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, card)
	Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, container)

	local s = setmetatable({ Name = name, Tab = self, Container = container, Window = self.Window }, Section)
	table.insert(col.Sections, s)
	return s
end

----------------------------------------------------------------------------------------------------
-- Window
----------------------------------------------------------------------------------------------------
function Library:CreateWindow(opts)
	opts = opts or {}
	local size = opts.Size or UDim2.fromOffset(548, 398)
	local win = setmetatable({
		Title = opts.Title or "Kitty.Club", Tabs = {}, Open = false,
		ToggleKey = (typeof(opts.ToggleKey) == "EnumItem" and opts.ToggleKey.Name) or opts.ToggleKey or "RightShift",
	}, Window)
	table.insert(Library.Windows, win)

	local root = Create("Frame", { Name = "Window_Frame", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = size, BackgroundTransparency = 1 }, Gui)
	local scale = Create("UIScale", { Scale = 0.94 }, root)
	local rootStroke = Stroke(root)
	rootStroke.Transparency = 1
	local body = Create("CanvasGroup", { Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Theme = { BackgroundColor3 = "Main" } }, root)
	win.Root, win.Body = root, body

	local hl = Create("Frame", { Size = UDim2.new(1, 0, 0, 1), ZIndex = 5, Theme = { BackgroundColor3 = "Accent" } }, body)
	Create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, hl)
	Create("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, 30), Text = win.Title, TextXAlignment = Enum.TextXAlignment.Left, FontFace = Library.FontBold }, body)
	local dragHandle = Create("TextButton", { Size = UDim2.new(1, 0, 0, 30) }, body)
	MakeDraggable(dragHandle, root)

	local content = Create("Frame", { Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 1, -79), Theme = { BackgroundColor3 = "Panel" } }, body)
	Stroke(content)
	win.Pages = Create("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1 }, content)

	local bar = Create("Frame", { Position = UDim2.new(0, 10, 1, -43), Size = UDim2.new(1, -20, 0, 37), Theme = { BackgroundColor3 = "Panel" } }, body)
	Stroke(bar)
	local tabLayout = Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
	}, bar)
	if hasFlex then
		tabLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill
		tabLayout.VerticalFlex   = Enum.UIFlexAlignment.Fill
	end
	win.TabBar = bar

	function win:SetVisible(v)
		self.Open = v
		Library:ClosePopup()
		if v then
			root.Visible = true
			Library:Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
			Library:Tween(body, { GroupTransparency = 0 }, 0.25)
			Library:Tween(rootStroke, { Transparency = 0 }, 0.25)
		else
			Library:Tween(scale, { Scale = 0.94 }, 0.2)
			Library:Tween(body, { GroupTransparency = 1 }, 0.2)
			Library:Tween(rootStroke, { Transparency = 1 }, 0.2)
			task.delay(Library:Dur(0.22), function()
				if not self.Open then root.Visible = false end
			end)
		end
	end

	function win:SelectTab(tab)
		if self.CurrentTab == tab then return end
		Library:ClosePopup()
		local old = self.CurrentTab
		self.CurrentTab = tab
		if old then
			Library:Tween(old.Page, { GroupTransparency = 1 }, 0.15)
			Library:Tween(old.Button, { TextColor3 = Library.Theme.SubText }, 0.2)
			Library:Tween(old.Indicator, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 2) }, 0.2)
			task.delay(Library:Dur(0.16), function()
				if self.CurrentTab ~= old then old.Page.Visible = false end
			end)
		end
		tab.Page.Visible = true
		tab.Page.Position = UDim2.fromOffset(0, 8)
		Library:Tween(tab.Page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.3)
		Library:Tween(tab.Button, { TextColor3 = Library.Theme.Text }, 0.2)
		Library:Tween(tab.Indicator, { BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 2) }, 0.25)
	end

	function win:AddTab(name)
		local t = setmetatable({ Name = name, Window = self }, Tab)
		local btn = Create("TextButton", { Size = UDim2.new(0, 50, 1, 0), Text = name, TextColor3 = Library.Theme.SubText }, bar)
		local ind = Create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0, 0, 0, 2), BackgroundTransparency = 1, Theme = { BackgroundColor3 = "Accent" } }, btn)
		local page = Create("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, self.Pages)

		local function column(side)
			local sf = Create("ScrollingFrame", {
				Size = UDim2.new(0.5, -4, 1, 0), Position = side == "Left" and UDim2.new() or UDim2.new(0.5, 4, 0, 0),
				BackgroundTransparency = 1, ScrollBarThickness = 2, Theme = { ScrollBarImageColor3 = "Accent" },
				CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
				BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png", TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			}, page)
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
			Create("UIPadding", { PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 6) }, sf)
			return { Frame = sf, Sections = {} }
		end
		t.Left, t.Right = column("Left"), column("Right")
		t.Page, t.Button, t.Indicator = page, btn, ind

		btn.MouseButton1Click:Connect(function() self:SelectTab(t) end)
		btn.MouseEnter:Connect(function() if self.CurrentTab ~= t then Library:Tween(btn, { TextColor3 = Color3.fromRGB(200, 200, 200) }, 0.15) end end)
		btn.MouseLeave:Connect(function() if self.CurrentTab ~= t then Library:Tween(btn, { TextColor3 = Library.Theme.SubText }, 0.15) end end)

		table.insert(self.Tabs, t)
		if not self.CurrentTab then self:SelectTab(t) end
		return t
	end

	if opts.Watermark ~= false and not Library.Watermark then
		Library:CreateWatermark(win.Title)
	end

	win:SetVisible(true)
	return win
end

----------------------------------------------------------------------------------------------------
-- Configs
----------------------------------------------------------------------------------------------------
local function HasFS()
	return (writefile and readfile and isfolder and makefolder and isfile and listfiles and delfile) and true or false
end

local function Serialize(o)
	local t = o.Type
	if t == "Toggle" or t == "Slider" or t == "Textbox" then return o.Value end
	if t == "Dropdown" then
		if o.Multi then
			local l = {}
			for k, v in pairs(o.Value) do if v then l[#l + 1] = k end end
			return l
		end
		return o.Value
	end
	if t == "ColorPicker" then return { Hex = ToHex(o.Value), T = o.Transparency } end
	if t == "KeyPicker" then return { Key = o.Key, Mode = o.Mode } end
end

local function Deserialize(o, v)
	local t = o.Type
	if t == "ColorPicker" and type(v) == "table" then
		local c = FromHex(v.Hex); if c then o:Set(c, v.T) end
	elseif t == "KeyPicker" and type(v) == "table" then
		o:SetKey(v.Key); o:SetMode(v.Mode or "Toggle")
	elseif o.Set then
		o:Set(v)
	end
end

local function CleanName(name)
	return (tostring(name or ""):gsub("[^%w%-_ ]", ""))
end

function Library:ListConfigs()
	if not HasFS() or not isfolder(self.ConfigFolder) then return {} end
	local out = {}
	for _, p in ipairs(listfiles(self.ConfigFolder)) do
		local n = p:match("([^/\\]+)%.json$")
		if n then out[#out + 1] = n end
	end
	table.sort(out)
	return out
end

function Library:SaveConfig(name)
	if not HasFS() then return false, "Executor has no file functions" end
	name = CleanName(name)
	if name:gsub("%s", "") == "" then return false, "Enter a config name" end
	if not isfolder(self.ConfigFolder) then makefolder(self.ConfigFolder) end
	local data = {}
	for flag, o in pairs(self.Options) do
		if not o.SkipConfig then data[flag] = Serialize(o) end
	end
	writefile(self.ConfigFolder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	return true
end

function Library:LoadConfig(name)
	if not HasFS() then return false, "Executor has no file functions" end
	if not name then return false, "Select a config" end
	local path = self.ConfigFolder .. "/" .. CleanName(name) .. ".json"
	if not isfile(path) then return false, "Config not found" end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok or type(data) ~= "table" then return false, "Corrupt config" end
	for flag, v in pairs(data) do
		local o = self.Options[flag]
		if o and not o.SkipConfig then pcall(Deserialize, o, v) end
	end
	return true
end

function Library:DeleteConfig(name)
	if not HasFS() or not name then return false end
	local path = self.ConfigFolder .. "/" .. CleanName(name) .. ".json"
	if isfile(path) then delfile(path) return true end
	return false
end

----------------------------------------------------------------------------------------------------
-- Settings tab
----------------------------------------------------------------------------------------------------
function Window:AddSettingsTab(name)
	local tab = self:AddTab(name or "Settings")
	local menu = tab:AddSection("Menu", "Left")

	menu:AddKeybind("Menu Key", {
		Flag = "_MenuKey", Default = self.ToggleKey, NoTrigger = true, SkipConfig = true,
		KeyChanged = function(k) self.ToggleKey = k or "RightShift" end,
	})
	menu:AddColorPicker("Accent Color", {
		Flag = "_Accent", Default = Library.Theme.Accent,
		Callback = function(c) Library:SetTheme("Accent", c) end,
	})
	menu:AddToggle("Show Watermark", { Flag = "_Watermark", Default = true, Callback = function(v) Library:SetWatermarkVisible(v) end })
	menu:AddButton("Unload UI", function() Library:Unload() end)

	local anim = tab:AddSection("Animations", "Left")
	anim:AddSlider("Animation Speed", {
		Flag = "_AnimSpeed", Min = 0, Max = 3, Default = 1, Rounding = 1, Suffix = "x",
		Callback = function(v) Library.Settings.AnimSpeed = v end,
	})
	anim:AddSlider("Slider Smoothness", {
		Flag = "_SliderSmooth", Min = 0, Max = 1, Default = Library.Settings.SliderSmooth, Rounding = 2,
		Callback = function(v) Library.Settings.SliderSmooth = v end,
	})
	anim:AddDropdown("Easing Style", {
		Flag = "_EaseStyle", Values = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Back", "Elastic", "Bounce" }, Default = "Quint",
		Callback = function(v) if v and Enum.EasingStyle[v] then Library.Settings.EasingStyle = Enum.EasingStyle[v] end end,
	})
	anim:AddDropdown("Easing Direction", {
		Flag = "_EaseDir", Values = { "In", "Out", "InOut" }, Default = "Out",
		Callback = function(v) if v and Enum.EasingDirection[v] then Library.Settings.EasingDirection = Enum.EasingDirection[v] end end,
	})

	local cfg = tab:AddSection("Configs", "Right")
	local nameBox = cfg:AddTextbox("Config Name", { Flag = "_CfgName", Placeholder = "my config", SkipConfig = true })
	local list = cfg:AddDropdown("Config List", { Flag = "_CfgList", Values = Library:ListConfigs(), SkipConfig = true })
	local function refresh() list:SetValues(Library:ListConfigs()) end
	local function result(ok, err, okMsg)
		if ok then Library:Notify(okMsg, 3, "Success") else Library:Notify(err or "Failed", 3, "Error") end
	end
	cfg:AddButton("Save / Create", function()
		local n = nameBox.Value ~= "" and nameBox.Value or list.Value
		local ok, err = Library:SaveConfig(n)
		result(ok, err, "Saved config '" .. tostring(n) .. "'")
		refresh()
	end)
	cfg:AddButton("Load", function()
		local ok, err = Library:LoadConfig(list.Value)
		result(ok, err, "Loaded config '" .. tostring(list.Value) .. "'")
	end)
	cfg:AddButton("Delete", function()
		local n = list.Value
		if Library:DeleteConfig(n) then Library:Notify("Deleted '" .. tostring(n) .. "'", 3, "Warning"); list:Set(nil, true) else Library:Notify("Nothing to delete", 3, "Error") end
		refresh()
	end)
	cfg:AddButton("Refresh List", refresh)
	if not HasFS() then cfg:AddLabel("Your executor has no file functions, configs are disabled.") end

	return tab
end

return Library
