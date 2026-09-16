--
-- The label: one node with text content. Colour tags, abbreviation
-- and obfuscation are resolved here (core/textlayout.lua) and measured
-- through the node's host. textScale scales the text itself: the implicit
-- size is the measured size times textScale, and the node box is the format
-- rectangle (or the text's own size without one) in unscaled font units.
-- scale, rotation and the transform origin work as on any item.
--

local core = require "luif.core"

local Item = core.Item
local Text = core.Text
local FontDb = core.FontDb
local TextLayout = core.TextLayout
local Sync = core.Sync

local instances = setmetatable({}, { __mode = "k" })

local Label = Item:extend {
    text = "",
    font = false,        -- A font handle; FontDb.Text when not set
    fontName = false,    -- Expects a base name for looking up in FontDb
    color = 0xffffffff,
    visible = true,
    alpha = 255,
    textScale = 1,
    localize = false,    -- Whether a string text goes through core.Text (translation and substitution)
    uppercase = false,
    wrap = true,
    abbreviate = false,
    wrappingWidth = false,
    align = "left",
    obfuscate = false,

    heightForWidth = true,

    implicitSizeChanged = false,         -- function(width, height)

    -- While attached: whether the format rectangle is enabled and its width
    -- (false until known), and the cached layout
    _fmtEnabled = false,
    _fmtWidth = false,
    _layout = false,
}

local alignment = {
    left = "left",
    right = "right",
    center = "center",
}

local function displayText(self)
    local text = type(self.text) == "table" and Text.get(self.text) or self.text
    return tostring(self.uppercase and string.upper(text) or text or "")
end

local function currentLayout(self)
    local layout = self._layout
    if not layout then
        layout = TextLayout.layout(Sync.host(self), self.font, displayText(self), {
            color = self.color or 0xFFFFFFFF,
            scale = self.textScale,
            limit = self._fmtEnabled and self._fmtWidth or false,
            abbreviate = self.abbreviate,
            obfuscate = self.obfuscate,
        })
        self._layout = layout
    end
    return layout
end

-- The layout changed: drop the cache and update the node.
local function changed(self)
    self._layout = false
    Sync.propertiesChanged(self)
    Sync.contentChanged(self)
end

-- The format width follows the wrapping width or the label's width.
local function updateFormatWidth(self)
    local width = self.wrappingWidth or (self:size())
    if self._fmtWidth ~= width then
        self._fmtWidth = width
        self._layout = false
    end
end

function Label.new(class, self)
    instances[self] = true
    self = Item.new(class, self)

    if self.fontName then
        self.font = FontDb[self.fontName]
    end
    self.font = self.font or FontDb.Text

    self.heightForWidth = self.wrap and not self.abbreviate
    self.text = (self.localize and type(self.text) == "string") and Text(self.text) or self.text
    return self
end

-- The item's node with the text scale added to its scale. The node box is
-- in unscaled font units, so the origin moves into those units and the
-- position makes up the difference: the node covers the item's box.
function Label:describeNode(p)
    Item.describeNode(self, p)
    local layout = currentLayout(self)
    local textScale = self.textScale
    if textScale > 0 and textScale ~= 1 then
        p.x = p.x + p.originX * (1 - 1 / textScale)
        p.y = p.y + p.originY * (1 - 1 / textScale)
        p.originX, p.originY = p.originX / textScale, p.originY / textScale
        p.scale = p.scale * textScale
    end
    p.width, p.height = layout.boxWidth, layout.boxHeight
end

function Label:pushContent(host, node)
    local layout = currentLayout(self)
    host.setText(node, self.font, layout.display, self.color or 0xFFFFFFFF,
                 alignment[self.align], layout.wrap)
end

function Label:attached()
    assert(alignment[self.align], "Label: unknown alignment " .. tostring(self.align))

    self._fmtEnabled = (self.wrap or self.abbreviate) and true or false
    self._fmtWidth = false
    self._layout = false
    if self._fmtEnabled and (self.width or self.wrappingWidth) then
        updateFormatWidth(self)
    end

    self:updateImplicitSize()
end

function Label:detached()
    self._layout = false
end

function Label:delete()
    instances[self] = nil
    Item.delete(self)
end

function Label:setSize(width, height)
    if self.width == width and self.height == height then
        return
    end

    Item.setSize(self, width, height)
    if self._root then
        if self.wrap or self.abbreviate then
            updateFormatWidth(self)
            self:updateImplicitSize()
        end
        changed(self)
    end
end

function Label:updateImplicitSize()
    local layout = currentLayout(self)
    local implicitWidth, implicitHeight = layout.width, layout.height
    if self.implicitWidth ~= implicitWidth or self.implicitHeight ~= implicitHeight then
        self.implicitWidth, self.implicitHeight = implicitWidth, implicitHeight
        if not (self.width and self.height) then
            self:invalidateParentLayout()
        end
        self:emit("implicitSizeChanged", implicitWidth, implicitHeight)
    end
end

function Label:setText(text, ...)
    self.text = (self.localize and type(text) == "string") and Text(text, ...) or text
    if self._root then
        self._layout = false
        -- This may have changed the size of the text
        self:updateImplicitSize()
        changed(self)
    end
end

function Label:hasText()
    return self.text ~= "" and      -- not an empty string and
           self.text.id ~= ""       -- not an empty id => has text
end

function Label:setLocalize(localize)
    self.localize = localize
    self:setText(self.text)
end

function Label:setUppercase(uppercase)
    self.uppercase = uppercase
    if self._root then
        self._layout = false
        self:updateImplicitSize()
        changed(self)
    end
end

function Label:setFont(font)
    self.font = font or FontDb.Text
    if self._root then
        self._layout = false
        -- This may have changed the size of the text
        self:updateImplicitSize()
        changed(self)
    end
end

function Label:setFontName(name)
    self.fontName = name
    self:setFont(FontDb[name])
end

function Label:setColor(color)
    if self.color == color then
        return
    end

    self.color = color
    if self._root then
        changed(self)
    end
end

function Label:setTextScale(textScale)
    if self.textScale == textScale then
        return
    end

    self.textScale = textScale
    if self._root then
        self._layout = false

        -- This may have changed the size of the text
        self:updateImplicitSize()
        changed(self)
    end
end

function Label:setWrap(wrap)
    self.wrap = wrap
    self.heightForWidth = self.wrap
    if self._root then
        self._fmtEnabled = wrap and true or false
        if wrap then
            updateFormatWidth(self)
        end
        changed(self)
    end
end

function Label:setWrappingWidth(wrappingWidth)
    if self.wrappingWidth == wrappingWidth then
        return
    end

    self.wrappingWidth = wrappingWidth
    if self._root and (self.wrap or self.abbreviate) then
        updateFormatWidth(self)
        changed(self)
    end
end

function Label:setObfuscate(obfuscate)
    self.obfuscate = obfuscate
    if self._root then
        changed(self)
    end
end

function Label:setAbbreviate(abbreviate)
    self.abbreviate = abbreviate
    if self._root then
        changed(self)
    end
end

-- The laid out text (a string, or colour runs); for tests and tools.
function Label:displayedText()
    return currentLayout(self).display
end

function Label.fontScaleChanged(font)
    for label in pairs(instances) do
        if label._root and label.font == font then
            label._layout = false
            local layout = currentLayout(label)
            label.implicitWidth, label.implicitHeight = layout.width, layout.height
            label:invalidateParentLayout()
            changed(label)
        end
    end
end

-- Shows the text of every label again, e.g. after loading other strings
function Label.updateLabels()
    for label in pairs(instances) do
        label:setText(label.text)
        label:setFont(label.font)
    end
end

return Label
