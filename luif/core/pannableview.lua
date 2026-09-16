--
-- An item that displays other content which can be panned and/or zoomed
--

local core = require "luif.core"
local MouseButton = core.MouseButton

local Math = core.Math

local PannableView = core.Item:extend {
    mouseEnabled = true,

    zoom = false,

    minZoom = 1, -- number value, "crop" or "fit"
    maxZoom = 1, -- number value, "crop" or "fit"

    _minZoom = false, -- internal
    _maxZoom = false, -- internal

    -- paddingLeft, paddingRight, paddingTop and paddingBottom override padding
    padding = false,
    paddingLeft = false,
    paddingRight = false,
    paddingTop = false,
    paddingBottom = false,

    focusX = 0, -- focus point in content coordinates
    focusY = 0,
    anchorX = 0, -- focus point in item coordinates
    anchorY = 0,

    targetZoom = false,
    targetAnchorX = 0,
    targetAnchorY = 0,

    mousePressed = false,

    animation = false,
    content = false,
    clip = true,
    centered = false,
}

function PannableView.new(class, self)
    self.layout = core.AnchorLayout {}

    if not self.content and #self > 0 then
        self.content = core.Array.takeFirst(self)
    end

    self.children = {
        core.Item {
            layout = core.AnchorLayout {},
            id = "container",
            self.content,
        }
    }
    self = core.Item.new(class,self)
    self.container = self:findChild("container")

    assert(self.minZoom == false or self.minZoom == "fit" or self.minZoom == "crop" or type(self.minZoom) == "number")
    assert(self.maxZoom == false or self.maxZoom == "fit" or self.maxZoom == "crop" or type(self.maxZoom) == "number")
    self:calcMinMaxZoom()

    self.zoom = Math.clamp((self.zoom == self.minZoom) and self._minZoom or self.zoom or 1, self._minZoom, self._maxZoom)
    self.targetZoom = self.zoom
    self.content:setTransformOrigin(0, 0)   -- Panning places the content's top left
    self.content:setScale(self.zoom)

    self.container:on("resize", function(w,h) self:onResize(w,h) end)

    if self.content.resize ~= nil then
        self.content:on("resize", function(w,h) self:onResize(w,h) end)
    end

    self.container.left   = self.paddingLeft   or self.padding or 0
    self.container.right  = self.paddingRight  or self.padding or 0
    self.container.top    = self.paddingTop    or self.padding or 0
    self.container.bottom = self.paddingBottom or self.padding or 0

    return self
end

function PannableView:mousePress(event)
    if event:button() == MouseButton.Left or event:button() == MouseButton.Right then
        self.mousePressed = true
    else
        event:ignore()
    end
end

function PannableView:mouseRelease(event)
    if event:button() == MouseButton.Left or event:button() == MouseButton.Right then
        self.mousePressed = false
    else
        event:ignore()
    end
end

function PannableView:mouseMove(event)
    if self.mousePressed then
        local dx, dy = event:dx(), event:dy()
        self.anchorX = self.anchorX + dx
        self.anchorY = self.anchorY + dy
        self.targetAnchorX, self.targetAnchorY = self.anchorX, self.anchorY
        self:updatePosition()
    else
        event:ignore()
    end
end

function PannableView:doZoom(amount, anchorX, anchorY)
    if not anchorX or not anchorY then
        anchorX = self.width/2
        anchorY = self.height/2
    end

    if not self.animation then
        self.focusX = (anchorX - self.content.x) / self.zoom
        self.focusY = (anchorY - self.content.y) / self.zoom
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.targetAnchorX, self.targetAnchorY = anchorX, anchorY
    end

    self.targetZoom = self.targetZoom * (1 + amount)
    self.targetZoom = self.maxZoom and math.min(self.targetZoom, self._maxZoom) or self.targetZoom
    self.targetZoom = self.minZoom and math.max(self.targetZoom, self._minZoom) or self.targetZoom

    self:animate(self.targetZoom)
end

function PannableView:mouseWheel(event)
    local amount = event:value() / 10
    local x, y = event:pos()
    self:doZoom(amount, x - self.container.x, y - self.container.y)
end

function PannableView:applyBounds(anchorX, anchorY)
    local x = -self.focusX * self.zoom + anchorX
    local y = -self.focusY * self.zoom + anchorY

    local w, h = self.content:scaledSize()
    local sw, sh = self.container:size()

    if self.centered then
        x, y = (sw-w)/2, (sh-h)/2
    else
        local xBound = sw-w
        local yBound = sh-h
        x = xBound > 0 and (sw-w)/2 or Math.clamp(x, xBound, 0)
        y = yBound > 0 and (sh-h)/2 or Math.clamp(y, yBound, 0)
        if self.zoom == 1 then
            x = math.floor(x)
            y = math.floor(y)
        end
    end

    anchorX = x - (-self.focusX * self.zoom)
    anchorY = y - (-self.focusY * self.zoom)

    return anchorX, anchorY, x, y
end

function PannableView:updatePosition()
    local anchorX, anchorY, x, y = self:applyBounds(self.anchorX, self.anchorY)
    self.anchorX, self.anchorY = anchorX, anchorY
    self.content:setPos(x, y)
end

function PannableView:setZoom(zoom)
    self.zoom = zoom
    self.content:setScale(zoom)
    self:updatePosition()
end

function PannableView:animate(zoom)
    self.animation = self:start("zoom", core.Animate {
        target = self,
        property = "zoom",
        to = zoom,
        ease = core.Ease.outQuad,
        duration = 300,
        finish = function()
            self.animation = false
            self.targetZoom = self.zoom
        end,
    })
end

function PannableView:animateTo(anchorX, anchorY, interactive)
    anchorX, anchorY = self:applyBounds(anchorX, anchorY)

    self.targetAnchorX = anchorX
    self.targetAnchorY = anchorY

    local ease, duration

    if interactive then
        ease = core.Ease.outCubic
        duration = 500
    else
        ease = core.Ease.inOutQuad
        duration = 1000
    end

    if self.anchorX ~= anchorX then
        self:start("anchorX", core.Animate {
            property = "anchorX",
            to = anchorX,
            ease = ease,
            duration = duration,
        })
    end

    if self.anchorY ~= anchorY then
        self:start("anchorY", core.Animate {
            property = "anchorY",
            to = anchorY,
            ease = ease,
            duration = duration,
        })
    end
end

function PannableView:setAnchorX(anchorX)
    if self.anchorX ~= anchorX then
        self.anchorX = anchorX
        self:updatePosition()
    end
end

function PannableView:setAnchorY(anchorY)
    if self.anchorY ~= anchorY then
        self.anchorY = anchorY
        self:updatePosition()
    end
end

function PannableView:fitToView()
    local w, h = self.content:size()
    if w == 0 and h == 0 then
        return
    end

    local sw, sh = self.container:size()
    local zoom = math.min(sw / w, sh / h, self._maxZoom)

    self:animate(zoom)
end

function PannableView:calcMinMaxZoom()
    local contentWidth, contentHeight = self.content:size()
    local viewWidth, viewHeight = self.container:size()

    local minZoom = self.minZoom
    local maxZoom = self.maxZoom

    minZoom = minZoom == "fit" and math.min(viewWidth / contentWidth, viewHeight / contentHeight) or
              minZoom == "crop" and math.max(viewWidth / contentWidth, viewHeight / contentHeight) or
              minZoom

    maxZoom = maxZoom == "fit" and math.min(viewWidth / contentWidth, viewHeight / contentHeight) or
              maxZoom == "crop" and math.max(viewWidth / contentWidth, viewHeight / contentHeight) or
              maxZoom

    self._minZoom = math.min(maxZoom, minZoom)
    self._maxZoom = math.max(maxZoom, minZoom)
end

function PannableView:onResize()
    local locked = self._minZoom == self.zoom

    self:calcMinMaxZoom()

    local zoom = Math.clamp(self.zoom, self._minZoom, self._maxZoom)

    if locked or self.zoom ~= zoom then
        self:setZoom(zoom)
    end

    self:updatePosition()
end

return PannableView
