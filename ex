--[[
    Kitty.Club UI Library
    Rebuilt from the converted layout: same sizes, colors, double borders,
    gloss gradients, Zekton font, top highlight line, bottom tab bar.
    Run as a LocalScript / loadstring / ModuleScript.
]]

local Players, UIS, TS, RS, HS, GS =
    game:GetService("Players"), game:GetService("UserInputService"), game:GetService("TweenService"),
    game:GetService("RunService"), game:GetService("HttpService"), game:GetService("GuiService")

local Library = {
    Flags = {}, Options = {}, Recent = {}, _panels = {}, _conns = {}, _mem = {}, _visible = true,
    Accent = Color3.fromRGB(255, 255, 255),
    ToggleKey = Enum.KeyCode.RightShift,
}
local Group = {}; Group.__index = Group

----------------------------------------------------------------- theme / helpers
local FONT  = Font.new("rbxasset://fonts/families/Zekton.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local C = {
    Bg = Color3.fromRGB(25, 26, 26), Panel = Color3.fromRGB(27, 27, 27), Inner = Color3.fromRGB(30, 30, 30),
    Stroke = Color3.fromRGB(51, 51, 51), Off = Color3.fromRGB(110, 110, 110), Active = Color3.fromRGB(36, 36, 37),
}
local GLOSS = { { 0, BLACK }, { .75, WHITE }, { 1, WHITE } }
local TEXT  = { TextLabel = true, TextButton = true, TextBox = true }

local function new(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    if TEXT[class] then o.FontFace = FONT; o.TextSize = 12; o.TextColor3 = WHITE; o.TextStrokeTransparency = 0; o.BackgroundTransparency = 1 end
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function tween(o, t, p, style)
    local tw = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), p)
    tw:Play(); return tw
end

local function grad(o, rot, keys)
    local ks = {}
    for i, k in ipairs(keys) do ks[i] = ColorSequenceKeypoint.new(k[1], k[2]) end
    return new("UIGradient", { Rotation = rot, Color = ColorSequence.new(ks) }, o)
end

local function border(o) -- original double stroke: black outer + gray inner
    new("UIStroke", { BorderOffset = UDim.new(0, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter }, o)
    new("UIStroke", { Color = C.Stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter }, o)
end

local function ring(o, inner)
    new("UIStroke", { BorderOffset = UDim.new(0, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
    new("UIStroke", { Color = inner or WHITE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local function highlight(p)
    local h = new("Frame", { Name = "Highlight_Frame", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 1), ZIndex = 2 }, p)
    grad(h, 0, { { 0, C.Bg }, { .5, WHITE }, { 1, C.Bg } })
    return h
end

local function press(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
local function pointer(i)
    if i and i.UserInputType == Enum.UserInputType.Touch then return Vector2.new(i.Position.X, i.Position.Y) + GS:GetGuiInset() end
    return UIS:GetMouseLocation()
end
local function inside(g, p)
    local a, s = g.AbsolutePosition, g.AbsoluteSize
    return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

-- one global drag handler (sliders, color picker, window dragging)
local drag
table.insert(Library._conns, UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then drag(i) end
end))
table.insert(Library._conns, UIS.InputEnded:Connect(function(i) if press(i) then drag = nil end end))

local function draggable(frame, handle)
    handle.InputBegan:Connect(function(i)
        if not press(i) then return end
        local off = frame.AbsolutePosition - pointer(i)
        drag = function(inp)
            local p = pointer(inp) + off
            tween(frame, .07, { Position = UDim2.fromOffset(p.X, p.Y) }, Enum.EasingStyle.Quad)
        end
    end)
end

local function makeButton(parent, text, pos, size, cb)
    local f = new("Frame", { BackgroundColor3 = C.Inner, Position = pos or UDim2.new(), Size = size }, parent)
    border(f); grad(f, -90, GLOSS)
    local b = new("TextButton", { Text = text, Size = UDim2.fromScale(1, 1) }, f)
    b.MouseEnter:Connect(function() tween(f, .15, { BackgroundColor3 = Color3.fromRGB(46, 46, 46) }) end)
    b.MouseLeave:Connect(function() tween(f, .15, { BackgroundColor3 = C.Inner }) end)
    b.MouseButton1Down:Connect(function() f.BackgroundColor3 = Color3.fromRGB(78, 78, 78); tween(f, .35, { BackgroundColor3 = Color3.fromRGB(46, 46, 46) }) end)
    b.MouseButton1Click:Connect(function() if cb then task.spawn(cb) end end)
    return f, b
end

local function commit(o, el, silent)
    Library.Flags[o.Flag or o.Name] = el.Value
    if not silent and o.Callback then task.spawn(o.Callback, el.Value) end
end
local function register(o, el) Library.Options[o.Flag or o.Name] = el; Library.Flags[o.Flag or o.Name] = el.Value end
local function rowLabel(o, parent, h)
    return new("TextLabel", { Text = o.Name or "", Size = UDim2.new(1, 0, 0, h or 15), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, parent)
end

----------------------------------------------------------------- gui root
function Library:_gui()
    if self.Gui then return self.Gui end
    local g = new("ScreenGui", { Name = "KittyClub", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
    g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    self.Gui = g
    -- click outside closes the open color picker
    table.insert(self._conns, UIS.InputBegan:Connect(function(i)
        if self._cp and press(i) then
            local p = pointer(i)
            if not inside(self._cp.Popup, p) and not inside(self._cp.Swatch, p) then self._cp.Close() end
        elseif i.KeyCode == self.ToggleKey and not UIS:GetFocusedTextBox() then
            self:Toggle()
        end
    end))
    return g
end

function Library:Toggle()
    self._visible = not self._visible
    if self._cp then self._cp.Close() end
    for _, p in ipairs(self._panels) do p.Visible = self._visible end
end

function Library:Unload()
    for _, c in ipairs(self._conns) do c:Disconnect() end
    for _, el in pairs(self.Options) do if el._rb then el._rb:Disconnect() end end
    if self.Gui then self.Gui:Destroy() end
end

----------------------------------------------------------------- elements
function Group:AddLabel(text)
    local l = new("TextLabel", { Text = text, Size = UDim2.new(1, 0, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Off }, self.Container)
    return { SetText = function(_, t) l.Text = t end }
end

function Group:AddButton(o)
    makeButton(self.Container, o.Name, nil, UDim2.new(1, 0, 0, 20), o.Callback)
end

function Group:AddToggle(o)
    local el = { Type = "Toggle", Value = o.Default or false }
    local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15) }, self.Container)
    local box = new("Frame", { BackgroundColor3 = C.Inner, Size = UDim2.fromOffset(15, 15) }, row)
    border(box); grad(box, -90, GLOSS)
    local fill = new("Frame", { BackgroundColor3 = Library.Accent, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new() }, box)
    grad(fill, -90, GLOSS)
    local label = new("TextLabel", { Text = o.Name, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Off }, row)
    local btn = new("TextButton", { Text = "", Size = UDim2.fromScale(1, 1) }, row)
    function el:Set(v, silent)
        self.Value = v and true or false
        tween(fill, .22, { Size = self.Value and UDim2.fromOffset(9, 9) or UDim2.new() }, Enum.EasingStyle.Back)
        tween(label, .2, { TextColor3 = self.Value and WHITE or C.Off })
        commit(o, self, silent)
    end
    btn.MouseButton1Click:Connect(function() el:Set(not el.Value) end)
    register(o, el); el:Set(el.Value, true)
    return el
end

function Group:AddSlider(o)
    local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
    local dec = #(tostring(inc):match("%.(%d+)") or "")
    local fmt = "%." .. dec .. "f"
    local el = { Type = "Slider" }
    local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) }, self.Container)
    rowLabel(o, row)
    local track = new("Frame", { BackgroundColor3 = C.Inner, Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 15) }, row)
    border(track); grad(track, -90, GLOSS)
    local fill = new("Frame", { BackgroundColor3 = Library.Accent, Size = UDim2.fromScale(0, 1) }, track)
    grad(fill, -90, GLOSS)
    local val = new("TextLabel", { Size = UDim2.fromScale(1, 1) }, track)
    local btn = new("TextButton", { Text = "", Size = UDim2.fromScale(1, 1) }, track)
    function el:Set(v, silent)
        v = math.clamp(math.floor((v - min) / inc + .5) * inc + min, min, max)
        v = tonumber(fmt:format(v))
        self.Value = v
        tween(fill, .12, { Size = UDim2.fromScale((v - min) / (max - min), 1) })
        val.Text = fmt:format(v) .. (o.Suffix or "")
        commit(o, self, silent)
    end
    btn.InputBegan:Connect(function(i)
        if not press(i) then return end
        drag = function(inp)
            local a = math.clamp((pointer(inp).X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            el:Set(min + (max - min) * a)
        end
        drag(i)
    end)
    register(o, el); el:Set(o.Default or min, true)
    return el
end

function Group:AddTextbox(o)
    local el = { Type = "Textbox", Value = o.Default or "" }
    local f = new("Frame", { BackgroundColor3 = C.Inner, Size = UDim2.new(1, 0, 0, 18) }, self.Container)
    border(f); grad(f, -90, GLOSS)
    local tb = new("TextBox", {
        Text = el.Value, PlaceholderText = o.Name or "", PlaceholderColor3 = C.Off, ClearTextOnFocus = false,
        Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, -10, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    function el:Set(t, silent) self.Value = tostring(t); tb.Text = self.Value; commit(o, self, silent) end
    tb.Focused:Connect(function() tween(f, .15, { BackgroundColor3 = Color3.fromRGB(46, 46, 46) }) end)
    tb.FocusLost:Connect(function() tween(f, .15, { BackgroundColor3 = C.Inner }); el:Set(tb.Text) end)
    register(o, el)
    return el
end

function Group:AddDropdown(o)
    local opts, multi = o.Options or {}, o.Multi
    local n = #opts
    local el = { Type = "Dropdown", Options = opts }
    el.Value = multi and (o.Default or {}) or (o.Default or opts[1])
    local open = false

    local root = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) }, self.Container)
    rowLabel(o, root)
    local head = new("Frame", { BackgroundColor3 = C.Inner, Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 15) }, root)
    border(head); grad(head, -90, GLOSS)
    local txt = new("TextLabel", { Position = UDim2.fromOffset(4, 15), Size = UDim2.new(1, -24, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, root)
    local plus = new("TextLabel", { Text = "+", Position = UDim2.new(1, -16, 0, 15), Size = UDim2.fromOffset(16, 15) }, root)
    local hb = new("TextButton", { Text = "", Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 15) }, root)
    local wrap = new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(0, 33), Size = UDim2.new(1, 0, 0, 0) }, root)
    local list = new("Frame", { BackgroundColor3 = C.Inner, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, n * 15) }, wrap)
    border(list)
    local rows = {}

    local function selected(opt)
        if multi then return table.find(el.Value, opt) ~= nil end
        return el.Value == opt
    end
    local function refresh()
        txt.Text = multi and (#el.Value > 0 and table.concat(el.Value, ", ") or "None") or tostring(el.Value or "None")
        for opt, b in pairs(rows) do tween(b, .15, { TextColor3 = selected(opt) and WHITE or C.Off }) end
    end
    local function setOpen(s)
        open = s
        plus.Text = s and "-" or "+"
        tween(root, .28, { Size = UDim2.new(1, 0, 0, s and 36 + n * 15 or 30) })
        tween(wrap, .28, { Size = UDim2.new(1, 0, 0, s and n * 15 + 3 or 0) })
    end
    function el:Set(v, silent)
        if multi then
            local set = {}
            for _, x in ipairs(type(v) == "table" and v or {}) do set[x] = true end
            self.Value = {}
            for _, opt in ipairs(opts) do if set[opt] then table.insert(self.Value, opt) end end
        else self.Value = v end
        refresh(); commit(o, self, silent)
    end
    for i, opt in ipairs(opts) do
        local b = new("TextButton", { Text = opt, Position = UDim2.fromOffset(0, (i - 1) * 15), Size = UDim2.new(1, 0, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Off }, list)
        new("UIPadding", { PaddingLeft = UDim.new(0, 4) }, b)
        rows[opt] = b
        b.MouseButton1Click:Connect(function()
            if multi then
                local v = table.clone(el.Value)
                local idx = table.find(v, opt)
                if idx then table.remove(v, idx) else table.insert(v, opt) end
                el:Set(v)
            else el:Set(opt); setOpen(false) end
        end)
    end
    hb.MouseButton1Click:Connect(function() setOpen(not open) end)
    register(o, el); refresh()
    return el
end

----------------------------------------------------------------- color picker
local HUE = {}
for i = 0, 5 do HUE[#HUE + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)) end
HUE[7] = ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1))
for _, hex in ipairs({ "FF4D6D", "FF9F1C", "FFE066", "4ADE80", "22D3EE", "5B8DEF", "A78BFA", "FFFFFF" }) do
    table.insert(Library.Recent, Color3.fromHex(hex))
end

local function pushRecent(c)
    for i, x in ipairs(Library.Recent) do if x == c then table.remove(i and Library.Recent, i) break end end
    table.insert(Library.Recent, 1, c)
    while #Library.Recent > 8 do table.remove(Library.Recent) end
end

function Group:AddColorPicker(o)
    local el = { Type = "ColorPicker", Rainbow = false }
    local h, s, v = (o.Default or WHITE):ToHSV()
    el.Value = Color3.fromHSV(h, s, v)

    local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15) }, self.Container)
    new("TextLabel", { Text = o.Name, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Left }, row)
    local swatch = new("Frame", { BackgroundColor3 = el.Value, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.fromOffset(30, 15) }, row)
    border(swatch); grad(swatch, -90, GLOSS)
    local sb = new("TextButton", { Text = "", Size = UDim2.fromScale(1, 1) }, swatch)

    local gui = Library:_gui()
    local pop, svBase, svCur, hueThumb, hex, rbBtn, pal
    local open, startColor = false, el.Value

    local function apply(silent)
        local c = Color3.fromHSV(h, s, v)
        el.Value = c; swatch.BackgroundColor3 = c
        if pop then
            svBase.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            svCur.BackgroundColor3 = c
            tween(svCur, .06, { Position = UDim2.fromScale(s, 1 - v) }, Enum.EasingStyle.Linear)
            tween(hueThumb, .06, { Position = UDim2.fromScale(.5, h) }, Enum.EasingStyle.Linear)
            hueThumb.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            if not hex:IsFocused() then hex.Text = ("#%02X%02X%02X"):format(math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)) end
        end
        commit(o, el, silent)
    end

    function el:Set(c, silent) h, s, v = c:ToHSV(); apply(silent) end
    function el:SetRainbow(on)
        self.Rainbow = on and true or false
        if self._rb then self._rb:Disconnect(); self._rb = nil end
        if self.Rainbow then self._rb = RS.Heartbeat:Connect(function(dt) h = (h + dt * .2) % 1; apply() end) end
        if rbBtn then tween(rbBtn, .2, { TextColor3 = self.Rainbow and Library.Accent or C.Off }) end
    end

    local function build()
        pop = new("Frame", { Name = "ColorPicker", BackgroundColor3 = C.Bg, Size = UDim2.fromOffset(190, 0), ClipsDescendants = true, Visible = false, ZIndex = 100 }, gui)
        border(pop); highlight(pop)

        -- saturation / value square (white->clear horizontally, clear->black vertically)
        svBase = new("Frame", { BackgroundColor3 = Color3.fromHSV(h, 1, 1), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(150, 112) }, pop)
        border(svBase)
        local w = new("Frame", { BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1) }, svBase)
        new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, w)
        local b = new("Frame", { BackgroundColor3 = BLACK, Size = UDim2.fromScale(1, 1) }, svBase)
        new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, b)
        svCur = new("Frame", { BackgroundColor3 = el.Value, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(s, 1 - v), Size = UDim2.fromOffset(10, 10) }, svBase)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, svCur); ring(svCur)

        -- hue strip
        local hue = new("Frame", { BackgroundColor3 = WHITE, Position = UDim2.fromOffset(166, 8), Size = UDim2.fromOffset(16, 112) }, pop)
        border(hue); new("UIGradient", { Rotation = 90, Color = ColorSequence.new(HUE) }, hue)
        hueThumb = new("Frame", { BackgroundColor3 = Color3.fromHSV(h, 1, 1), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, h), Size = UDim2.new(1, 4, 0, 5) }, hue)
        ring(hueThumb)

        svBase.InputBegan:Connect(function(i)
            if not press(i) then return end
            drag = function(inp)
                local r = (pointer(inp) - svBase.AbsolutePosition) / svBase.AbsoluteSize
                s = math.clamp(r.X, 0, 1); v = 1 - math.clamp(r.Y, 0, 1); apply()
            end
            drag(i)
        end)
        hue.InputBegan:Connect(function(i)
            if not press(i) then return end
            drag = function(inp) h = math.clamp((pointer(inp).Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1); apply() end
            drag(i)
        end)

        -- hex input + rainbow mode
        local hf = new("Frame", { BackgroundColor3 = C.Inner, Position = UDim2.fromOffset(8, 128), Size = UDim2.fromOffset(92, 18) }, pop)
        border(hf); grad(hf, -90, GLOSS)
        hex = new("TextBox", { Text = "", ClearTextOnFocus = false, Size = UDim2.fromScale(1, 1) }, hf)
        hex.FocusLost:Connect(function()
            local t = (hex.Text:gsub("#", ""))
            if #t == 6 and tonumber(t, 16) then el:Set(Color3.fromHex(t)) else apply(true) end
        end)
        local _, rb = makeButton(pop, "Rainbow", UDim2.fromOffset(104, 128), UDim2.fromOffset(78, 18), function() el:SetRainbow(not el.Rainbow) end)
        rbBtn = rb; rb.TextColor3 = el.Rainbow and Library.Accent or C.Off

        -- recent / palette swatches
        pal = {}
        for i = 1, 8 do
            local p = new("TextButton", { Text = "", BackgroundTransparency = 0, Position = UDim2.fromOffset(8 + (i - 1) * 22, 152), Size = UDim2.fromOffset(18, 14) }, pop)
            border(p)
            p.MouseButton1Click:Connect(function() el:Set(p.BackgroundColor3) end)
            pal[i] = p
        end
        apply(true)
    end

    local function close()
        if not open then return end
        open = false; Library._cp = nil
        if el.Value ~= startColor then pushRecent(el.Value) end
        local p = pop
        tween(p, .2, { Size = UDim2.fromOffset(190, 0) }).Completed:Connect(function() if not open then p.Visible = false end end)
    end
    el.Close = close

    sb.MouseButton1Click:Connect(function()
        if open then return close() end
        if Library._cp then Library._cp.Close() end
        if not pop then build() end
        for i, p in ipairs(pal) do p.BackgroundColor3 = Library.Recent[i] or C.Inner end
        local ap, vp = swatch.AbsolutePosition, gui.AbsoluteSize
        local x = math.clamp(ap.X + 30 - 190, 4, vp.X - 194)
        local y = ap.Y + 19
        if y + 174 > vp.Y then y = ap.Y - 178 end
        pop.Position = UDim2.fromOffset(x, y)
        pop.Visible = true; open = true; startColor = el.Value
        el.Popup, el.Swatch = pop, swatch; Library._cp = el
        apply(true)
        tween(pop, .3, { Size = UDim2.fromOffset(190, 174) })
    end)

    register(o, el)
    return el
end

----------------------------------------------------------------- window / tabs
function Library:CreateWindow(o)
    o = o or {}
    local gui = self:_gui()
    local win = { Tabs = {} }

    local f = new("Frame", { Name = "Window_Frame", BackgroundColor3 = C.Bg, Size = UDim2.fromOffset(548, 398), Position = UDim2.new(.32822, 0, .25454, 0) }, gui)
    border(f); highlight(f)
    table.insert(self._panels, f)

    local tf = new("Frame", { Name = "Title_Frame", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) }, f)
    local title = new("TextLabel", { Name = "Title_Label", Text = o.Title or "Kitty.Club", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextXAlignment = Enum.TextXAlignment.Left }, tf)
    grad(title, -90, { { 0, BLACK }, { 1, WHITE } })
    draggable(f, tf)

    local outer = new("Frame", { Name = "Tab_OutterFrame", BackgroundColor3 = C.Panel, Position = UDim2.fromOffset(10, 30), Size = UDim2.fromOffset(528, 325) }, f)
    border(outer)
    new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, outer)

    local bar = new("Frame", { Name = "Tabs_Frame", BackgroundColor3 = C.Panel, Position = UDim2.fromOffset(10, 355), Size = UDim2.fromOffset(528, 37) }, f)
    border(bar)
    new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, bar)

    local function select(tab)
        for _, t in ipairs(win.Tabs) do
            local on = t == tab
            t.Page.Visible = on
            tween(t.Button, .2, { BackgroundColor3 = on and C.Active or C.Panel, TextColor3 = on and WHITE or C.Off })
            tween(t.Line, .3, { BackgroundTransparency = on and 0 or 1 })
        end
    end

    function win:AddTab(name)
        local tab = { Name = name }
        tab.Button = new("TextButton", { Name = "Tab_Button", Text = name, BackgroundTransparency = 0, BackgroundColor3 = C.Panel, TextColor3 = C.Off, Size = UDim2.new(1, 0, 1, 0) }, bar)
        border(tab.Button)
        tab.Line = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 1) }, tab.Button)
        grad(tab.Line, 0, { { 0, C.Bg }, { .5, WHITE }, { 1, C.Bg } })
        tab.Page = new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, outer)

        local function column(x)
            local s = new("ScrollingFrame", {
                Active = true, BackgroundColor3 = C.Inner, ScrollingDirection = Enum.ScrollingDirection.Y,
                Position = UDim2.new(x, x * 8, 0, 0), Size = UDim2.new(.5, -4, 1, 0), CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = C.Stroke,
            }, tab.Page)
            border(s); grad(s, -90, { { 0, Color3.fromRGB(146, 146, 146) }, { 1, WHITE } })
            new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, s)
            new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, s)
            return setmetatable({ Container = s }, Group)
        end
        tab.Left, tab.Right = column(0), column(.5)

        tab.Button.MouseButton1Click:Connect(function() select(tab) end)
        table.insert(win.Tabs, tab)
        local n = #win.Tabs
        for _, t in ipairs(win.Tabs) do t.Button.Size = UDim2.new(1 / n, -2 * (n - 1) / n, 1, 0) end
        if n == 1 then select(tab) end
        return tab
    end

    return win
end

----------------------------------------------------------------- extra windows
function Library:CreatePreview(o)
    o = o or {}
    local f = new("Frame", { Name = "EspPreView_Window", BackgroundColor3 = C.Bg, Size = UDim2.fromOffset(234, 270), Position = UDim2.new(.16395, 0, .25488, 0) }, self:_gui())
    border(f); highlight(f); draggable(f, f)
    table.insert(self._panels, f)
    local t = new("TextLabel", { Text = o.Title or "Esp Preview", Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Left }, f)
    grad(t, -90, { { 0, BLACK }, { 1, WHITE } })
    local img = new("ImageLabel", { Image = o.Image or "rbxassetid://14408826931", ScaleType = Enum.ScaleType.Fit, ResampleMode = Enum.ResamplerMode.Pixelated, Position = UDim2.new(.05202, 0, .11111, 0), Size = UDim2.fromOffset(209, 225), BackgroundTransparency = 1 }, f)
    border(img)
    return { Frame = f, Image = img, SetImage = function(_, id) img.Image = id end }
end

function Library:Watermark(o)
    o = o or {}
    local f = new("Frame", { Name = "WaterMark_Window", BackgroundColor3 = C.Bg, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), Position = UDim2.new(.39365, 0, .18659, 0) }, self:_gui())
    border(f); highlight(f); draggable(f, f)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, f)
    local l = new("TextLabel", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), Text = "" }, f)
    grad(l, -90, { { 0, BLACK }, { 1, WHITE } })
    local wm = { Frame = f }
    local frames, last = 0, os.clock()
    table.insert(self._conns, RS.Heartbeat:Connect(function()
        frames += 1
        local dt = os.clock() - last
        if dt >= .5 then
            if not wm.Custom then l.Text = ("%s | %d fps | %s"):format(o.Title or "Kitty.Club", math.round(frames / dt), os.date("%m/%d/%y")) end
            frames, last = 0, os.clock()
        end
    end))
    function wm:SetText(t) self.Custom = t ~= nil; if t then l.Text = t end end
    function wm:SetVisible(b) f.Visible = b end
    return wm
end

function Library:Notify(text, duration)
    duration = duration or 3
    local gui = self:_gui()
    if not self._notif then
        self._notif = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 12), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y }, gui)
        new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, self._notif)
    end
    local wrap = new("Frame", { Name = "Notification_Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 30) }, self._notif)
    local cg = new("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1, Position = UDim2.fromOffset(0, -10), Size = UDim2.fromScale(1, 1) }, wrap)
    local body = new("Frame", { BackgroundColor3 = C.Bg, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, cg)
    border(body)
    local lbl = new("TextLabel", { Text = text, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextXAlignment = Enum.TextXAlignment.Left }, body)
    grad(lbl, -90, { { 0, BLACK }, { 1, WHITE } })
    wrap.Size = UDim2.fromOffset(math.max(200, lbl.TextBounds.X + 24), 30)
    local bar = new("Frame", { BackgroundColor3 = self.Accent, Size = UDim2.new(1, 0, 0, 1), ZIndex = 2 }, body)
    tween(cg, .35, { GroupTransparency = 0, Position = UDim2.new() })
    tween(bar, duration, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear)
    task.delay(duration, function()
        tween(cg, .3, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) }).Completed:Wait()
        tween(wrap, .2, { Size = UDim2.fromOffset(wrap.AbsoluteSize.X, 0) }).Completed:Wait()
        wrap:Destroy()
    end)
end

----------------------------------------------------------------- configs
local wf, rf, lf, mf, isf, df = writefile, readfile, listfiles, makefolder, isfolder, delfile
local HASFS = wf and rf and lf and mf and isf and df

function Library:CreateConfigWindow()
    local folder = "KittyClub/configs"
    if HASFS then pcall(function() if not isf("KittyClub") then mf("KittyClub") end if not isf(folder) then mf(folder) end end) end

    local f = new("Frame", { Name = "Config_Window", BackgroundColor3 = C.Bg, Size = UDim2.fromOffset(235, 265), Position = UDim2.new(.7052, 0, .25488, 0) }, self:_gui())
    border(f); highlight(f); draggable(f, f)
    table.insert(self._panels, f)
    local t = new("TextLabel", { Text = "Configs", Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Left }, f)
    grad(t, -90, { { 0, BLACK }, { 1, WHITE } })

    local list = new("ScrollingFrame", { Name = "Configs_Frame", BackgroundColor3 = C.Bg, Position = UDim2.fromOffset(10, 34), Size = UDim2.fromOffset(215, 150), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = C.Stroke }, f)
    border(list)
    new("UIListLayout", { SortOrder = Enum.SortOrder.Name }, list)
    new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, list)

    local nameBox = new("Frame", { BackgroundColor3 = C.Inner, Position = UDim2.fromOffset(10, 190), Size = UDim2.fromOffset(215, 18) }, f)
    border(nameBox); grad(nameBox, -90, GLOSS)
    local tb = new("TextBox", { Text = "", PlaceholderText = "config name", PlaceholderColor3 = C.Off, ClearTextOnFocus = false, Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, -10, 1, 0), TextXAlignment = Enum.TextXAlignment.Left }, nameBox)

    local selected
    local function names()
        local out = {}
        if HASFS then
            for _, p in ipairs(lf(folder)) do local n = p:match("([^/\\]+)%.json$"); if n then table.insert(out, n) end end
        else for n in pairs(self._mem) do table.insert(out, n) end end
        return out
    end
    local function refresh()
        for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        for _, n in ipairs(names()) do
            local b = new("TextButton", { Name = n, Text = n, Size = UDim2.new(1, 0, 0, 22), TextColor3 = n == selected and WHITE or C.Off }, list)
            b.MouseButton1Click:Connect(function() selected = n; tb.Text = n; refresh() end)
        end
    end
    local function serialize()
        local t = {}
        for k, el in pairs(self.Options) do
            local v = el.Value
            if typeof(v) == "Color3" then t[k] = { c = { v.R, v.G, v.B }, rb = el.Rainbow } else t[k] = v end
        end
        return HS:JSONEncode(t)
    end
    local function load(str)
        for k, v in pairs(HS:JSONDecode(str)) do
            local el = self.Options[k]
            if el then
                if type(v) == "table" and v.c then el:Set(Color3.new(unpack(v.c))); el:SetRainbow(v.rb) else el:Set(v) end
            end
        end
    end

    local function save()
        local n = tb.Text:gsub("[^%w_%- ]", "")
        if n == "" then return self:Notify("Enter a config name") end
        if HASFS then wf(folder .. "/" .. n .. ".json", serialize()) else self._mem[n] = serialize() end
        selected = n; refresh(); self:Notify("Saved " .. n)
    end
    makeButton(f, "Save", UDim2.fromOffset(10, 214), UDim2.fromOffset(105, 20), save)
    makeButton(f, "Delete", UDim2.fromOffset(120, 214), UDim2.fromOffset(105, 20), function()
        if not selected then return end
        if HASFS then df(folder .. "/" .. selected .. ".json") else self._mem[selected] = nil end
        self:Notify("Deleted " .. selected); selected = nil; refresh()
    end)
    makeButton(f, "Load Config", UDim2.fromOffset(10, 238), UDim2.fromOffset(215, 20), function()
        if not selected then return self:Notify("Select a config first") end
        local ok = pcall(function() load(HASFS and rf(folder .. "/" .. selected .. ".json") or self._mem[selected]) end)
        self:Notify(ok and ("Loaded " .. selected) or "Failed to load config")
    end)
    refresh()
    return f
end

return Library
