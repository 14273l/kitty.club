--[[
    Kitty.Club UI Library
    Rebuilt from the exported layout: Window, Tabs (bottom bar), 2-column pages,
    Config window, ESP preview window, Watermark, Notifications.

    Elements : Toggle, Slider, Dropdown (single/multi), Button, Textbox, Label, Divider,
               ColorPicker (HSV + hex + rainbow), Keybind (Toggle / Hold / Always)
    Extras   : Config save/load (writefile if available, memory fallback), accent theming,
               menu toggle key, flags, Unload.
]]

local Players          = game:GetService("Players")
local UIS              = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local Stats            = game:GetService("Stats")

local Library = {
	Flags = {},
	Options = {},
	Keybinds = {},
	MemoryConfigs = {},
	ConfigFolder = "KittyClub",
	Theme = {
		Background = Color3.fromRGB(25, 26, 26),
		Panel      = Color3.fromRGB(27, 27, 27),
		Element    = Color3.fromRGB(30, 30, 30),
		Stroke     = Color3.fromRGB(51, 51, 51),
		Text       = Color3.fromRGB(255, 255, 255),
		SubText    = Color3.fromRGB(134, 134, 135),
		Dim        = Color3.fromRGB(68, 68, 68),
		Accent     = Color3.fromRGB(255, 140, 200),
	},
	FontFace = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
	_conns = {},
	_accent = {},
}
local Theme = Library.Theme

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function noop() end

local function Safe(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[KittyLib] callback error: " .. tostring(err)) end
end

local function Clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function Round(v, inc) return math.floor(v / inc + 0.5) * inc end

local function New(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function Tween(o, props, t, style)
	TweenService:Create(o, TweenInfo.new(t or 0.15, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function Stroke(o, color)
	return New("UIStroke", {
		Color = color or Theme.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Parent = o,
	})
end

local function Label(parent, text, props)
	local l = New("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = text or "",
		TextColor3 = Theme.Text,
		TextSize = 14,
		FontFace = Library.FontFace,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = parent,
	})
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

local function Inside(obj, pos)
	local a, s = obj.AbsolutePosition, obj.AbsoluteSize
	return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
end

function Library:Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

function Library:BindAccent(fn)
	table.insert(self._accent, fn)
	fn(Theme.Accent)
end

function Library:SetAccent(color)
	Theme.Accent = color
	for _, fn in ipairs(self._accent) do pcall(fn, color) end
end

local function Highlight(parent)
	local f = New("Frame", {
		Name = "Highlight_Frame", BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 1), ZIndex = 5, Parent = parent,
	})
	local g = New("UIGradient", { Parent = f })
	Library:BindAccent(function(c)
		g.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Theme.Background),
			ColorSequenceKeypoint.new(0.5, c),
			ColorSequenceKeypoint.new(1, Theme.Background),
		}
	end)
	return f
end

local function MakeDraggable(handle, target)
	local dragging, startPos, startFrame
	Library:Connect(handle.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startFrame = true, i.Position, target.Position
		end
	end)
	Library:Connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startPos
			target.Position = UDim2.new(startFrame.X.Scale, startFrame.X.Offset + d.X, startFrame.Y.Scale, startFrame.Y.Offset + d.Y)
		end
	end)
	Library:Connect(UIS.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

local function BindDrag(hit, cb)
	local dragging = false
	Library:Connect(hit.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			cb(i.Position)
		end
	end)
	Library:Connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			cb(i.Position)
		end
	end)
	Library:Connect(UIS.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

function Library:_Reg(obj)
	if obj.Flag then
		self.Options[obj.Flag] = obj
		self.Flags[obj.Flag] = obj.Value
	end
end

function Library:_SetFlag(obj)
	if obj.Flag then self.Flags[obj.Flag] = obj.Value end
end

function Library:ClosePopups()
	if self.OpenPopup then self.OpenPopup() end
end

--------------------------------------------------------------------------------
-- Color picker addon
--------------------------------------------------------------------------------
function Library:_MakeColorPicker(window, holder, opts)
	opts = opts or {}
	local cp = { Type = "ColorPicker", Flag = opts.Flag or opts.Name, Callback = opts.Callback or noop, Rainbow = false }
	local h, s, v = (opts.Default or Color3.new(1, 1, 1)):ToHSV()
	cp.Value = Color3.fromHSV(h, s, v)

	local swatch = New("TextButton", {
		Size = UDim2.fromOffset(24, 12), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundColor3 = cp.Value, ZIndex = 3, Parent = holder,
	})
	Stroke(swatch)

	local popup = New("Frame", {
		BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Size = UDim2.fromOffset(210, 200),
		Visible = false, ZIndex = 100, Parent = window.Menu,
	})
	Stroke(popup); Highlight(popup)

	local sv = New("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(160, 130), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHSV(h, 1, 1), Parent = popup })
	Stroke(sv)
	local white = New("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv })
	New("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = New("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv })
	New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
	local svCursor = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4, Parent = sv })
	Stroke(svCursor, Color3.new(0, 0, 0))
	local svHit = New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = sv })

	local hue = New("Frame", { Position = UDim2.fromOffset(176, 8), Size = UDim2.fromOffset(24, 130), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = popup })
	Stroke(hue)
	New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)), ColorSequenceKeypoint.new(1/6, Color3.fromHSV(1/6, 1, 1)),
			ColorSequenceKeypoint.new(2/6, Color3.fromHSV(2/6, 1, 1)), ColorSequenceKeypoint.new(3/6, Color3.fromHSV(3/6, 1, 1)),
			ColorSequenceKeypoint.new(4/6, Color3.fromHSV(4/6, 1, 1)), ColorSequenceKeypoint.new(5/6, Color3.fromHSV(5/6, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
		},
		Parent = hue,
	})
	local hueCursor = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4, Parent = hue })
	Stroke(hueCursor, Color3.new(0, 0, 0))
	local hueHit = New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = hue })

	local hex = New("TextBox", {
		Position = UDim2.fromOffset(8, 146), Size = UDim2.fromOffset(194, 20), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		Text = "", ClearTextOnFocus = false, TextColor3 = Theme.Text, TextSize = 13, FontFace = Library.FontFace, Parent = popup,
	})
	Stroke(hex)
	local rainbowBtn = New("TextButton", {
		Position = UDim2.fromOffset(8, 172), Size = UDim2.fromOffset(194, 20), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		Text = "Rainbow: Off", AutoButtonColor = false, TextColor3 = Theme.SubText, TextSize = 13, FontFace = Library.FontFace, Parent = popup,
	})
	Stroke(rainbowBtn)

	local function refresh(silent)
		cp.Value = Color3.fromHSV(h, s, v)
		swatch.BackgroundColor3 = cp.Value
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
		hex.Text = string.format("#%02X%02X%02X", math.floor(cp.Value.R * 255 + 0.5), math.floor(cp.Value.G * 255 + 0.5), math.floor(cp.Value.B * 255 + 0.5))
		Library:_SetFlag(cp)
		if not silent then Safe(cp.Callback, cp.Value) end
	end

	BindDrag(svHit, function(pos)
		s = Clamp((pos.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
		v = 1 - Clamp((pos.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
		refresh()
	end)
	BindDrag(hueHit, function(pos)
		h = Clamp((pos.Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 0.999)
		refresh()
	end)

	hex.FocusLost:Connect(function()
		local r, g, b = hex.Text:match("#?(%x%x)(%x%x)(%x%x)")
		if r then
			h, s, v = Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)):ToHSV()
		end
		refresh()
	end)

	local rbConn
	function cp:SetRainbow(b)
		cp.Rainbow = b
		rainbowBtn.Text = "Rainbow: " .. (b and "On" or "Off")
		rainbowBtn.TextColor3 = b and Theme.Accent or Theme.SubText
		if rbConn then rbConn:Disconnect(); rbConn = nil end
		if b then
			rbConn = RunService.Heartbeat:Connect(function()
				h = (tick() % 6) / 6
				refresh()
			end)
			table.insert(Library._conns, rbConn)
		end
	end
	rainbowBtn.MouseButton1Click:Connect(function() cp:SetRainbow(not cp.Rainbow) end)

	function cp:Set(color, silent)
		h, s, v = color:ToHSV()
		refresh(silent)
	end
	function cp:Get() return cp.Value end
	function cp:Export() return { R = cp.Value.R, G = cp.Value.G, B = cp.Value.B, Rainbow = cp.Rainbow } end
	function cp:Import(d)
		cp:SetRainbow(false)
		cp:Set(Color3.new(d.R, d.G, d.B))
		if d.Rainbow then cp:SetRainbow(true) end
	end

	-- popup open/close
	local follow
	local function place()
		local ap, as = swatch.AbsolutePosition, swatch.AbsoluteSize
		local vp, ps = window.Gui.AbsoluteSize, popup.AbsoluteSize
		local x = Clamp(ap.X + as.X - ps.X, 4, math.max(4, vp.X - ps.X - 4))
		local y = ap.Y + as.Y + 4
		if y + ps.Y > vp.Y - 4 then y = ap.Y - ps.Y - 4 end
		popup.Position = UDim2.fromOffset(x, y)
	end
	local function close()
		popup.Visible = false
		if follow then follow:Disconnect(); follow = nil end
		if Library.OpenPopup == close then Library.OpenPopup = nil end
	end
	swatch.MouseButton1Click:Connect(function()
		if popup.Visible then close(); return end
		Library:ClosePopups()
		popup.Visible = true
		place()
		follow = RunService.RenderStepped:Connect(place)
		Library.OpenPopup = close
	end)
	Library:Connect(UIS.InputBegan, function(i)
		if popup.Visible and i.UserInputType == Enum.UserInputType.MouseButton1 then
			if not Inside(popup, i.Position) and not Inside(swatch, i.Position) then close() end
		end
	end)

	refresh(true)
	Library:_Reg(cp)
	return cp
end

--------------------------------------------------------------------------------
-- Keybind addon
--------------------------------------------------------------------------------
local KeyNames = {
	LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
	LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backspace = "Back",
	MouseButton1 = "M1", MouseButton2 = "M2", MouseButton3 = "M3",
}
local function KeyName(k) if not k then return "None" end return KeyNames[k.Name] or k.Name end
local function Matches(key, input)
	if key.EnumType == Enum.KeyCode then return input.KeyCode == key end
	return input.UserInputType == key
end

local ModeCycle = { Toggle = "Hold", Hold = "Always", Always = "Toggle" }

function Library:_MakeKeybind(window, holder, opts)
	opts = opts or {}
	local kb = {
		Type = "Keybind", Flag = opts.Flag or opts.Name, Key = opts.Default, Mode = opts.Mode or "Toggle",
		State = false, Callback = opts.Callback or noop, Changed = opts.Changed or noop, Listening = false,
	}
	kb.Value = kb.State

	local btn = New("TextButton", {
		Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, TextColor3 = Theme.SubText, TextSize = 12, FontFace = Library.FontFace, ZIndex = 3, Parent = holder,
	})
	New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = btn })
	Stroke(btn)

	local function text()
		local t = "[" .. KeyName(kb.Key)
		if kb.Mode ~= "Toggle" then t = t .. " - " .. kb.Mode end
		btn.Text = t .. "]"
	end

	function kb:SetState(state, silent)
		kb.State = state
		kb.Value = state
		Library:_SetFlag(kb)
		btn.TextColor3 = state and Theme.Accent or Theme.SubText
		if not silent then Safe(kb.Callback, state) end
	end
	function kb:SetKey(k, silent)
		kb.Key = k
		text()
		if not silent then Safe(kb.Changed, k) end
	end
	function kb:SetMode(m)
		kb.Mode = m
		text()
		kb:SetState(m == "Always")
	end
	function kb:Get() return kb.State end
	function kb:GetKey() return kb.Key end

	function kb:Export()
		return { Key = kb.Key and kb.Key.Name, KeyType = kb.Key and (kb.Key.EnumType == Enum.KeyCode and "KeyCode" or "UserInputType"), Mode = kb.Mode }
	end
	function kb:Import(d)
		local key
		if d.Key and d.KeyType then pcall(function() key = Enum[d.KeyType][d.Key] end) end
		kb:SetKey(key)
		kb:SetMode(d.Mode or "Toggle")
	end

	btn.MouseButton1Click:Connect(function()
		if kb.Listening then return end
		kb.Listening = true
		Library.Listening = true
		btn.Text = "[...]"
		local c
		c = UIS.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Keyboard then
				kb:SetKey(i.KeyCode ~= Enum.KeyCode.Escape and i.KeyCode or nil)
			elseif i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.MouseButton2 or i.UserInputType == Enum.UserInputType.MouseButton3 then
				if opts.Standalone then return end
				kb:SetKey(i.UserInputType)
			else
				return
			end
			c:Disconnect()
			task.defer(function() kb.Listening = false; Library.Listening = false end)
		end)
	end)
	if not opts.Standalone then
		btn.MouseButton2Click:Connect(function()
			if not kb.Listening then kb:SetMode(ModeCycle[kb.Mode]) end
		end)
		table.insert(Library.Keybinds, kb)
	end

	text()
	if kb.Mode == "Always" then kb:SetState(true, true) end
	Library:_Reg(kb)
	return kb
end

--------------------------------------------------------------------------------
-- Config system
--------------------------------------------------------------------------------
local hasFS = writefile and readfile and isfolder and makefolder and isfile and listfiles
local function cfgDir() return Library.ConfigFolder .. "/configs" end

function Library:_EnsureFolders()
	if not hasFS then return end
	pcall(function()
		if not isfolder(self.ConfigFolder) then makefolder(self.ConfigFolder) end
		if not isfolder(cfgDir()) then makefolder(cfgDir()) end
	end)
end

function Library:ExportConfig()
	local t = {}
	for flag, obj in pairs(self.Options) do
		if obj.Export and not obj.NoSave then t[flag] = obj:Export() end
	end
	return HttpService:JSONEncode(t)
end

function Library:ImportConfig(json)
	local ok, t = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(t) ~= "table" then return false end
	for flag, val in pairs(t) do
		local o = self.Options[flag]
		if o and o.Import then pcall(o.Import, o, val) end
	end
	return true
end

function Library:ListConfigs()
	local list = {}
	if hasFS then
		self:_EnsureFolders()
		local ok, files = pcall(listfiles, cfgDir())
		if ok then
			for _, f in ipairs(files) do
				local name = f:match("([^/\\]+)%.json$")
				if name then table.insert(list, name) end
			end
		end
	else
		for name in pairs(self.MemoryConfigs) do table.insert(list, name) end
	end
	table.sort(list)
	return list
end

function Library:SaveConfig(name)
	if not name or name == "" then return false end
	local data = self:ExportConfig()
	if hasFS then
		self:_EnsureFolders()
		return pcall(writefile, cfgDir() .. "/" .. name .. ".json", data)
	end
	self.MemoryConfigs[name] = data
	return true
end

function Library:LoadConfig(name)
	if not name or name == "" then return false end
	if hasFS then
		local path = cfgDir() .. "/" .. name .. ".json"
		if not isfile(path) then return false end
		return self:ImportConfig(readfile(path))
	end
	return self.MemoryConfigs[name] and self:ImportConfig(self.MemoryConfigs[name]) or false
end

function Library:DeleteConfig(name)
	if hasFS then
		pcall(function() delfile(cfgDir() .. "/" .. name .. ".json") end)
	else
		self.MemoryConfigs[name] = nil
	end
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------
function Library:Notify(text, duration, color)
	if not self.NotifyHolder then return end
	duration = duration or 3
	local wrap = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 30), Parent = self.NotifyHolder })
	local f = New("Frame", { BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(-420, 0), Parent = wrap })
	Stroke(f); Highlight(f)
	local lbl = Label(f, text, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, -2) })
	wrap.Size = UDim2.fromOffset(Clamp(lbl.TextBounds.X + 24, 200, 420), 30)
	local bar = New("Frame", { BackgroundColor3 = color or Theme.Accent, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), Parent = f })
	Tween(f, { Position = UDim2.fromOffset(0, 0) }, 0.25)
	Tween(bar, { Size = UDim2.new(0, 0, 0, 2) }, duration, Enum.EasingStyle.Linear)
	task.delay(duration, function()
		Tween(f, { Position = UDim2.fromOffset(-420, 0) }, 0.25)
		task.wait(0.3)
		wrap:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Watermark
--------------------------------------------------------------------------------
function Library:CreateWatermark(opts)
	opts = opts or {}
	local wm = { Format = opts.Format or "{name} | {game} | {date} | {fps} fps | {ping} ms", Name = opts.Name or "Kitty.Club", Game = game.Name }
	local frame = New("Frame", {
		BackgroundColor3 = Theme.Background, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(300, 26), Parent = self.Gui,
	})
	Stroke(frame); Highlight(frame)
	local lbl = Label(frame, "", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) })
	MakeDraggable(frame, frame)

	task.spawn(function()
		pcall(function() wm.Game = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	end)

	local fps, acc = 60, 0
	local function update()
		local ping = 0
		pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
		local vars = { name = wm.Name, game = wm.Game, date = os.date("%x"), time = os.date("%X"), fps = tostring(fps), ping = tostring(ping), user = Players.LocalPlayer.Name }
		lbl.Text = (wm.Format:gsub("{(%w+)}", function(k) return vars[k] or "{" .. k .. "}" end))
		frame.Size = UDim2.fromOffset(lbl.TextBounds.X + 22, 26)
	end
	Library:Connect(RunService.Heartbeat, function(dt)
		fps = math.floor(fps * 0.9 + (1 / math.max(dt, 1e-4)) * 0.1 + 0.5)
		acc = acc + dt
		if acc >= 0.5 then acc = 0; update() end
	end)
	update()

	function wm:SetVisible(b) frame.Visible = b end
	function wm:SetFormat(f) wm.Format = f; update() end
	function wm:SetName(n) wm.Name = n; update() end
	self.Watermark = wm
	return wm
end

--------------------------------------------------------------------------------
-- Elements (shared by sections)
--------------------------------------------------------------------------------
local Elements = {}

local function Row(section, height)
	return New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 18), Parent = section.Content })
end

local function AddonHolder(row)
	return New("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 2, Parent = row,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function AttachAddons(obj, section, holder)
	obj.Section = section
	obj.AddonHolder = holder
	function obj:AddColorPicker(o) return Library:_MakeColorPicker(section.Window, holder, o) end
	function obj:AddKeybind(o) return Library:_MakeKeybind(section.Window, holder, o) end
end

function Elements:AddLabel(text, opts)
	opts = opts or {}
	local row = Row(self, 18)
	local lbl = Label(row, text, { TextWrapped = true, TextColor3 = opts.Color or Theme.SubText })
	local obj = {}
	function obj:Set(t) lbl.Text = t end
	AttachAddons(obj, self, AddonHolder(row))
	return obj
end

function Elements:AddDivider()
	New("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = self.Content })
end

function Elements:AddToggle(opts)
	opts = opts or {}
	local t = { Type = "Toggle", Flag = opts.Flag or opts.Name, Value = false, Callback = opts.Callback or noop }
	local row = Row(self, 18)
	local box = New("Frame", { Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 0, 0.5, -7), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = row })
	Stroke(box)
	local fill = New("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = box })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)), Parent = fill })
	Library:BindAccent(function(c) fill.BackgroundColor3 = c end)
	local lbl = Label(row, opts.Name, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), TextColor3 = Theme.SubText })
	local btn = New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = row })

	function t:Set(v, silent)
		t.Value = v and true or false
		Tween(fill, { BackgroundTransparency = t.Value and 0 or 1 }, 0.12)
		Tween(lbl, { TextColor3 = t.Value and Theme.Text or Theme.SubText }, 0.12)
		Library:_SetFlag(t)
		if not silent then Safe(t.Callback, t.Value) end
	end
	function t:Get() return t.Value end
	function t:Export() return t.Value end
	function t:Import(v) t:Set(v) end
	btn.MouseButton1Click:Connect(function() t:Set(not t.Value) end)

	AttachAddons(t, self, AddonHolder(row))
	Library:_Reg(t)
	if opts.Default then t:Set(true, true) end
	return t
end

function Elements:AddSlider(opts)
	opts = opts or {}
	local min, max, inc = opts.Min or 0, opts.Max or 100, opts.Increment or 1
	local sl = { Type = "Slider", Flag = opts.Flag or opts.Name, Min = min, Max = max, Callback = opts.Callback or noop }
	local decimals = #(tostring(inc):match("%.(%d+)") or "")
	local row = Row(self, 32)
	Label(row, opts.Name, { Size = UDim2.new(0.7, 0, 0, 14) })
	local val = Label(row, "", { Size = UDim2.new(0.3, 0, 0, 14), Position = UDim2.fromScale(0.7, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.SubText })
	local bar = New("Frame", { Position = UDim2.fromOffset(0, 19), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = row })
	Stroke(bar)
	local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = bar })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(140, 140, 140)), Parent = fill })
	Library:BindAccent(function(c) fill.BackgroundColor3 = c end)
	local hit = New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 8), Position = UDim2.fromOffset(0, -4), Parent = bar })

	function sl:Set(v, silent)
		v = Clamp(tonumber(string.format("%." .. decimals .. "f", Round(v, inc))), min, max)
		sl.Value = v
		val.Text = string.format("%." .. decimals .. "f", v) .. (opts.Suffix or "")
		Tween(fill, { Size = UDim2.fromScale((v - min) / math.max(max - min, 1e-9), 1) }, 0.06)
		Library:_SetFlag(sl)
		if not silent then Safe(sl.Callback, v) end
	end
	function sl:Get() return sl.Value end
	function sl:Export() return sl.Value end
	function sl:Import(v) sl:Set(v) end
	BindDrag(hit, function(pos)
		sl:Set(min + (max - min) * Clamp((pos.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1))
	end)

	sl.Value = opts.Default or min
	sl:Set(sl.Value, true)
	Library:_Reg(sl)
	return sl
end

function Elements:AddButton(opts)
	opts = opts or {}
	local row = Row(self, 22)
	local b = New("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, AutoButtonColor = false,
		Text = opts.Name or "Button", TextColor3 = Theme.Text, TextSize = 14, FontFace = Library.FontFace, TextStrokeTransparency = 0.5, Parent = row,
	})
	local st = Stroke(b)
	b.MouseEnter:Connect(function() Tween(st, { Color = Theme.Accent }, 0.12) end)
	b.MouseLeave:Connect(function() Tween(st, { Color = Theme.Stroke }, 0.12) end)
	b.MouseButton1Click:Connect(function()
		b.BackgroundColor3 = Theme.Accent
		Tween(b, { BackgroundColor3 = Theme.Panel }, 0.25)
		Safe(opts.Callback)
	end)
	return b
end

function Elements:AddTextbox(opts)
	opts = opts or {}
	local tb = { Type = "Textbox", Flag = opts.Flag or opts.Name, Value = opts.Default or "", Callback = opts.Callback or noop }
	local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = self.Content })
	Label(holder, opts.Name, { Size = UDim2.new(1, 0, 0, 14) })
	local box = New("TextBox", {
		Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		Text = tb.Value, PlaceholderText = opts.Placeholder or "", PlaceholderColor3 = Theme.Dim, TextColor3 = Theme.Text,
		TextSize = 13, FontFace = Library.FontFace, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
	})
	New("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = box })
	local st = Stroke(box)
	box.Focused:Connect(function() Tween(st, { Color = Theme.Accent }, 0.12) end)
	box.FocusLost:Connect(function()
		Tween(st, { Color = Theme.Stroke }, 0.12)
		tb:Set(box.Text)
	end)
	function tb:Set(v, silent)
		tb.Value = tostring(v)
		box.Text = tb.Value
		Library:_SetFlag(tb)
		if not silent then Safe(tb.Callback, tb.Value) end
	end
	function tb:Get() return tb.Value end
	function tb:Export() return tb.Value end
	function tb:Import(v) tb:Set(v) end
	Library:_Reg(tb)
	return tb
end

function Elements:AddDropdown(opts)
	opts = opts or {}
	local dd = { Type = "Dropdown", Flag = opts.Flag or opts.Name, Options = opts.Options or {}, Multi = opts.Multi or false, Callback = opts.Callback or noop }
	dd.Value = dd.Multi and {} or nil
	local btns = {}

	local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = self.Content }, {
		New("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Label(holder, opts.Name, { Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 1 })
	local box = New("TextButton", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = holder })
	local st = Stroke(box)
	local txt = Label(box, "", { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -26, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, TextSize = 13 })
	local arrow = Label(box, "+", { Position = UDim2.new(1, -18, 0, 0), Size = UDim2.fromOffset(14, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.SubText })
	local list = New("ScrollingFrame", {
		LayoutOrder = 3, Visible = false, Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = holder,
	}, { New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }), New("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }) })
	Stroke(list)
	Library:BindAccent(function(c) list.ScrollBarImageColor3 = c end)

	local function isSelected(o) if dd.Multi then return dd.Value[o] == true end return dd.Value == o end
	local function display()
		local parts = {}
		if dd.Multi then
			for _, o in ipairs(dd.Options) do if dd.Value[o] then table.insert(parts, o) end end
			txt.Text = #parts > 0 and table.concat(parts, ", ") or "None"
		else
			txt.Text = dd.Value or "None"
		end
		txt.TextColor3 = (dd.Multi and #parts > 0 or (not dd.Multi and dd.Value)) and Theme.Text or Theme.SubText
		for o, b in pairs(btns) do b.TextColor3 = isSelected(o) and Theme.Accent or Theme.SubText end
		Library:_SetFlag(dd)
	end
	local function setOpen(b)
		list.Visible = b
		arrow.Text = b and "-" or "+"
		Tween(st, { Color = b and Theme.Accent or Theme.Stroke }, 0.12)
	end
	box.MouseButton1Click:Connect(function() setOpen(not list.Visible) end)

	local function pick(o)
		if dd.Multi then dd.Value[o] = (not dd.Value[o]) or nil else dd.Value = o; setOpen(false) end
		display()
		Safe(dd.Callback, dd.Value)
	end

	function dd:Refresh(options, keep)
		if options then dd.Options = options end
		for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		table.clear(btns)
		if not keep then dd.Value = dd.Multi and {} or nil end
		for i, o in ipairs(dd.Options) do
			local b = New("TextButton", {
				LayoutOrder = i, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "  " .. tostring(o), TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.SubText, TextSize = 13, FontFace = Library.FontFace, TextStrokeTransparency = 0.5, AutoButtonColor = false, Parent = list,
			})
			b.MouseButton1Click:Connect(function() pick(o) end)
			b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.7; b.BackgroundColor3 = Theme.Stroke end)
			b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
			btns[o] = b
		end
		list.Size = UDim2.new(1, 0, 0, Clamp(#dd.Options, 1, 6) * 20 + 4)
		display()
	end

	function dd:Set(v, silent)
		if dd.Multi then
			dd.Value = {}
			if type(v) == "table" then
				for k, x in pairs(v) do
					if type(k) == "number" then dd.Value[x] = true elseif x then dd.Value[k] = true end
				end
			end
		else
			dd.Value = v
		end
		display()
		if not silent then Safe(dd.Callback, dd.Value) end
	end
	function dd:Get() return dd.Value end
	function dd:Export()
		if not dd.Multi then return dd.Value end
		local out = {}
		for _, o in ipairs(dd.Options) do if dd.Value[o] then table.insert(out, o) end end
		return out
	end
	function dd:Import(v) dd:Set(v) end

	dd:Refresh()
	if opts.Default ~= nil then dd:Set(opts.Default, true) end
	Library:_Reg(dd)
	return dd
end

function Elements:AddColorPicker(opts)
	opts = opts or {}
	local row = Row(self, 18)
	Label(row, opts.Name, { TextColor3 = Theme.Text })
	local holder = AddonHolder(row)
	local cp = Library:_MakeColorPicker(self.Window, holder, opts)
	AttachAddons(cp, self, holder)
	return cp
end

function Elements:AddKeybind(opts)
	opts = opts or {}
	local row = Row(self, 18)
	Label(row, opts.Name, { TextColor3 = Theme.Text })
	local holder = AddonHolder(row)
	local kb = Library:_MakeKeybind(self.Window, holder, opts)
	AttachAddons(kb, self, holder)
	return kb
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Tab:AddSection(name, side)
	side = side or ((self._n % 2 == 0) and "Left" or "Right")
	self._n = self._n + 1
	local column = side == "Right" and self.Right or self.Left
	local sec = New("Frame", { BackgroundColor3 = Theme.Element, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = column }, {
		New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		New("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	Stroke(sec)
	local hdr = Label(sec, name or "", { Size = UDim2.new(1, 0, 0, 16), TextColor3 = Theme.Accent })
	Library:BindAccent(function(c) hdr.TextColor3 = c end)
	New("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = sec })
	return setmetatable({ Content = sec, Window = self.Window, Tab = self }, { __index = Elements })
end

for _, fn in ipairs({ "AddToggle", "AddSlider", "AddDropdown", "AddButton", "AddTextbox", "AddLabel", "AddDivider", "AddColorPicker", "AddKeybind" }) do
	Tab[fn] = function(self, ...)
		self.Default = self.Default or self:AddSection("General", "Left")
		return self.Default[fn](self.Default, ...)
	end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
function Library:CreateWindow(opts)
	opts = opts or {}
	local window = { Tabs = {}, MenuKey = opts.MenuKey or Enum.KeyCode.RightShift, Library = self }

	local gui = New("ScreenGui", { Name = HttpService:GenerateGUID(false), ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true, DisplayOrder = 999 })
	local ok = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
	if not ok or not gui.Parent then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
	self.Gui, window.Gui = gui, gui

	local menu = New("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	self.Menu, window.Menu = menu, menu

	self.NotifyHolder = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(440, 600), Parent = gui }, {
		New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- Main frame
	local main = New("Frame", { Name = "Window_Frame", BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Size = opts.Size or UDim2.fromOffset(548, 398), Position = UDim2.fromScale(0.329, 0.257), Parent = menu })
	Stroke(main); Highlight(main)
	window.Main = main
	local titleFrame = New("Frame", { Name = "Title_Frame", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = main })
	Label(titleFrame, opts.Title or "Kitty.Club", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 16 })
	MakeDraggable(titleFrame, main)

	local content = New("Frame", { Name = "Tab_OutterFrame", BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 1, -73), Parent = main }, {
		New("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	Stroke(content)

	local tabsFrame = New("Frame", { Name = "Tabs_Frame", BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Position = UDim2.new(0, 10, 1, -43), Size = UDim2.new(1, -20, 0, 37), Parent = main }, {
		New("UIListLayout", { HorizontalFlex = Enum.UIFlexAlignment.Fill, VerticalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal }),
	})
	Stroke(tabsFrame)

	function window:SelectTab(tab)
		Library:ClosePopups()
		for _, t in ipairs(window.Tabs) do
			local on = t == tab
			t.Page.Visible = on
			t.Button.TextColor3 = on and Theme.Text or Theme.SubText
			t.Button.BackgroundColor3 = on and Theme.Element or Theme.Panel
			t.Indicator.Visible = on
		end
		window.Tab = tab
	end

	function window:CreateTab(name)
		local tab = setmetatable({ Name = name, Window = window, _n = 0 }, Tab)
		local btn = New("TextButton", {
			BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, AutoButtonColor = false, Text = name, TextSize = 14, FontFace = Library.FontFace,
			TextColor3 = Theme.SubText, TextStrokeTransparency = 0.5, Size = UDim2.fromOffset(100, 37), LayoutOrder = #window.Tabs, Parent = tabsFrame,
		})
		local ind = New("Frame", { BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Visible = false, Parent = btn })
		Library:BindAccent(function(c) ind.BackgroundColor3 = c end)
		local page = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
		local function column(pos, size)
			local sf = New("ScrollingFrame", {
				BackgroundTransparency = 1, BorderSizePixel = 0, Position = pos, Size = size, ScrollBarThickness = 2,
				CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = page,
			}, {
				New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
				New("UIPadding", { PaddingRight = UDim.new(0, 5) }),
			})
			Library:BindAccent(function(c) sf.ScrollBarImageColor3 = c end)
			return sf
		end
		tab.Left = column(UDim2.fromScale(0, 0), UDim2.new(0.5, -4, 1, 0))
		tab.Right = column(UDim2.new(0.5, 4, 0, 0), UDim2.new(0.5, -4, 1, 0))
		tab.Page, tab.Button, tab.Indicator = page, btn, ind
		btn.MouseButton1Click:Connect(function() window:SelectTab(tab) end)
		table.insert(window.Tabs, tab)
		if #window.Tabs == 1 then window:SelectTab(tab) end
		return tab
	end

	function window:SetVisible(b)
		menu.Visible = b
		if not b then Library:ClosePopups() end
	end
	function window:Toggle() window:SetVisible(not menu.Visible) end

	Library:Connect(UIS.InputBegan, function(i, gp)
		if gp or Library.Listening or UIS:GetFocusedTextBox() then return end
		if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == window.MenuKey then window:Toggle() end
	end)

	-- Global keybind processing
	Library:Connect(UIS.InputBegan, function(i, gp)
		if gp or Library.Listening or UIS:GetFocusedTextBox() then return end
		for _, kb in ipairs(Library.Keybinds) do
			if kb.Key and kb.Mode ~= "Always" and Matches(kb.Key, i) then
				if kb.Mode == "Toggle" then kb:SetState(not kb.State) else kb:SetState(true) end
			end
		end
	end)
	Library:Connect(UIS.InputEnded, function(i)
		for _, kb in ipairs(Library.Keybinds) do
			if kb.Key and kb.Mode == "Hold" and Matches(kb.Key, i) then kb:SetState(false) end
		end
	end)

	----------------------------------------------------------------------------
	-- Config window
	----------------------------------------------------------------------------
	function window:CreateConfigWindow()
		local cw = New("Frame", { Name = "Config_Window", BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Size = UDim2.fromOffset(235, 265), Position = UDim2.fromScale(0.6756, 0.257), Parent = menu })
		Stroke(cw); Highlight(cw)
		local tf = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = cw })
		Label(tf, "Configs", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 16 })
		MakeDraggable(tf, cw)

		local list = New("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 32), Size = UDim2.fromOffset(215, 128), BackgroundColor3 = Theme.Element, BorderSizePixel = 0,
			ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = cw,
		}, { New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }), New("UIPadding", { PaddingTop = UDim.new(0, 2) }) })
		Stroke(list)
		Library:BindAccent(function(c) list.ScrollBarImageColor3 = c end)

		local nameBox = New("TextBox", {
			Position = UDim2.fromOffset(10, 166), Size = UDim2.fromOffset(215, 20), BackgroundColor3 = Theme.Element, BorderSizePixel = 0,
			Text = "", PlaceholderText = "Config name...", PlaceholderColor3 = Theme.Dim, TextColor3 = Theme.Text, TextSize = 13,
			FontFace = Library.FontFace, ClearTextOnFocus = false, Parent = cw,
		})
		Stroke(nameBox)

		local selected
		local function refresh()
			for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
			for i, name in ipairs(Library:ListConfigs()) do
				local b = New("TextButton", {
					LayoutOrder = i, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "  " .. name, TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = name == selected and Theme.Accent or Theme.SubText, TextSize = 13, FontFace = Library.FontFace, AutoButtonColor = false, Parent = list,
				})
				b.MouseButton1Click:Connect(function() selected = name; nameBox.Text = name; refresh() end)
			end
		end
		local function button(text, pos, size, cb)
			local b = New("TextButton", {
				Position = pos, Size = size, BackgroundColor3 = Theme.Element, BorderSizePixel = 0, AutoButtonColor = false, Text = text,
				TextColor3 = Theme.Text, TextSize = 14, FontFace = Library.FontFace, TextStrokeTransparency = 0.5, Parent = cw,
			})
			local st = Stroke(b)
			b.MouseEnter:Connect(function() Tween(st, { Color = Theme.Accent }, 0.12) end)
			b.MouseLeave:Connect(function() Tween(st, { Color = Theme.Stroke }, 0.12) end)
			b.MouseButton1Click:Connect(cb)
		end
		button("Save", UDim2.fromOffset(10, 192), UDim2.fromOffset(105, 22), function()
			local n = nameBox.Text:gsub("[^%w_%- ]", "")
			if n == "" then return Library:Notify("Enter a config name", 2) end
			Library:SaveConfig(n); selected = n; refresh()
			Library:Notify("Saved config: " .. n, 2)
		end)
		button("Delete", UDim2.fromOffset(120, 192), UDim2.fromOffset(105, 22), function()
			if selected then Library:DeleteConfig(selected); Library:Notify("Deleted config: " .. selected, 2); selected = nil; nameBox.Text = ""; refresh() end
		end)
		button("Load Config", UDim2.fromOffset(10, 220), UDim2.fromOffset(215, 22), function()
			if selected and Library:LoadConfig(selected) then Library:Notify("Loaded config: " .. selected, 2) else Library:Notify("Could not load config", 2) end
		end)
		refresh()
		window.ConfigWindow = cw
		return { Frame = cw, Refresh = refresh }
	end

	----------------------------------------------------------------------------
	-- ESP preview window
	----------------------------------------------------------------------------
	function window:CreatePreview(popts)
		popts = popts or {}
		local pv = { Parts = {} }
		local frame = New("Frame", { Name = "EspPreView_Window", BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Size = UDim2.fromOffset(234, 270), Position = UDim2.fromScale(0.178, 0.257), Parent = menu })
		Stroke(frame); Highlight(frame)
		local tf = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = frame })
		Label(tf, "Esp Preview", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 16 })
		MakeDraggable(tf, frame)

		local img = New("ImageLabel", {
			Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(209, 225), BackgroundTransparency = 1, BorderSizePixel = 0,
			Image = popts.Image or "rbxassetid://14408826931", ScaleType = Enum.ScaleType.Fit, ResampleMode = Enum.ResamplerMode.Pixelated, Parent = frame,
		})
		Stroke(img)

		local box = New("Frame", { Position = UDim2.fromScale(0.22, 0.1), Size = UDim2.fromScale(0.56, 0.82), BackgroundTransparency = 1, Parent = img })
		local boxStroke = New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = box })
		local nameL = Label(box, "Player", { Position = UDim2.new(0, 0, 0, -15), Size = UDim2.new(1, 0, 0, 13), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13 })
		local hpBack = New("Frame", { Position = UDim2.new(0, -6, 0, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = box })
		local hp = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.8, 0), BackgroundColor3 = Color3.fromRGB(80, 255, 100), BorderSizePixel = 0, Parent = hpBack })
		local dist = Label(box, "12m", { Position = UDim2.new(0, 0, 1, 2), Size = UDim2.new(1, 0, 0, 13), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13 })

		pv.Parts = { Box = { box }, Name = { nameL }, Health = { hpBack }, Distance = { dist } }
		function pv:Set(feature, state)
			local p = pv.Parts[feature]
			if not p then return end
			if feature == "Box" then boxStroke.Enabled = state else p[1].Visible = state end
		end
		function pv:SetColor(feature, c)
			if feature == "Box" then boxStroke.Color = c
			elseif feature == "Name" then nameL.TextColor3 = c
			elseif feature == "Distance" then dist.TextColor3 = c
			elseif feature == "Health" then hp.BackgroundColor3 = c end
		end
		function pv:SetName(t) nameL.Text = t end
		function pv:SetImage(i) img.Image = i end
		window.Preview = pv
		return pv
	end

	----------------------------------------------------------------------------
	-- Settings tab (menu key, accent, watermark, unload)
	----------------------------------------------------------------------------
	function window:CreateSettingsTab()
		local tab = window:CreateTab("Settings")
		local sec = tab:AddSection("Menu", "Left")
		sec:AddKeybind({ Name = "Menu Key", Default = window.MenuKey, Standalone = true, Flag = "MenuKey",
			Changed = function(k) if k and k.EnumType == Enum.KeyCode then window.MenuKey = k end end })
		sec:AddColorPicker({ Name = "Accent Color", Default = Theme.Accent, Flag = "AccentColor", Callback = function(c) Library:SetAccent(c) end })
		sec:AddToggle({ Name = "Watermark", Default = true, Flag = "WatermarkEnabled", Callback = function(v) if Library.Watermark then Library.Watermark:SetVisible(v) end end })
		sec:AddButton({ Name = "Unload UI", Callback = function() Library:Unload() end })
		local info = tab:AddSection("Info", "Right")
		info:AddLabel("Right-click a keybind to cycle its mode (Toggle / Hold / Always).")
		info:AddLabel("Press Escape while binding to clear a key.")
		return tab
	end

	self.Window = window
	return window
end

function Library:Unload()
	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	table.clear(self._conns)
	if self.Gui then self.Gui:Destroy() end
	table.clear(self.Keybinds)
	table.clear(self.Options)
	table.clear(self.Flags)
	self.Unloaded = true
end

return Library
