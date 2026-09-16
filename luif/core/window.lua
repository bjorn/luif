--
-- A window component with a title label, icon and close button.
--

local core = require "luif.core"
local MouseButton = core.MouseButton

local DefaultWindowSkin = core.skins.DefaultWindowSkin
local SkinnableItem   = core.SkinnableItem
local Text              = core.Text
local Update            = core.Update

local TexDb             = core.TexDb

local clamp             = core.Math.clamp

local Window = SkinnableItem:extend {
    icon = TexDb.empty,
    title = "",
    localize = false,

    width = 300,
    height = 200,

    movable = true,     -- Whether the window can be dragged around
    resizable = true,   -- Whether the window can be resized
    closeable = true,   -- Whether the window close button is visible
    autoMoveToTop = true,   -- Whether becoming visible or being clicked moves this window to the top

    skinClass = DefaultWindowSkin,

    -- Callbacks
    close = false,      -- Called when the close button is pressed

    skinParts = {
        "rear",
        "titleBar",
        "titleLabel",
        "iconImage",
        "closeButton",
        "minimizeButton",
        "resizeHandle",
    },

    state = "active",

    _moving = false,
    _moveStartX = false,
    _moveStartY = false,

    _resizing = false,
    _resizeStartWidth = false,
    _resizeStartHeight = false,

    _startMouseX = false,
    _startMouseY = false,
}

function Window.new(class, self)
    self = SkinnableItem.new(class, self)

    if self.titleBar then
        self.titleBar:setMouseEnabled(self.movable)
    end
    if self.titleLabel then
        self.titleLabel:setLocalize(self.localize)
        self.titleLabel:setText(self.title)
    end
    if self.iconImage then
        self.iconImage:setTexture(self.icon)
    end
    if self.closeButton then
        self.closeButton.click = function() self:emit("close") end
        if not self.closeable then
            self.closeButton:setVisible(false)
            self.closeButton:setEnabled(false)
        end
    end
    if self.minimizeButton then
        self.minimizeButton.click = function()
            local newState = self.state == "minimized" and "active" or "minimized"
            self:setState(newState)
        end
    end
    if self.resizeHandle then
        self.resizeHandle:setVisible(self.resizable)
        self.resizeHandle:setMouseEnabled(self.resizable)
    else
        self.resizable = false
    end

    if not self.active then
        self:setState("inactive")
    end

    return self
end

local animRatio = .05
local function disappearPos(self)
    local w, h = self:size()
    local disappearX = w / 2 * animRatio
    local disappearY = h / 2 * animRatio
    return disappearX, disappearY
end

function Window:setVisible(visible)
    if self.visible == visible then
        return
    end
    if visible and self.autoMoveToTop then
        self:moveToTop()
    end

    local effect

    if visible then
        local disappearX, disappearY = disappearPos(self)
        effect = self.showEffect or core.Parallel {
            target = self.skin,
            duration = 150,
            core.Animate { property = "x", from = disappearX, to = 0, ease = core.Ease.outCubic },
            core.Animate { property = "y", from = disappearY, to = 0, ease = core.Ease.outCubic },
            core.Scale { from = (1 - animRatio), to = 1, ease = core.Ease.outCubic },
            core.Fade { from = 0, to = 255, ease = core.Ease.outCubic },
       }
    elseif self.active then
        local disappearX, disappearY = disappearPos(self)
        effect = self.hideEffect or core.Parallel {
            target = self.skin,
            core.Animate { property = "x", to = disappearX, ease = core.Ease.outCubic },
            core.Animate { property = "y", to = disappearY, ease = core.Ease.outCubic },
            core.Scale { to = (1 - animRatio), ease = core.Ease.outCubic },
            core.Fade { to = 0, ease = core.Ease.outCubic },
       }
    end

    SkinnableItem.setVisible(self, visible, effect)
end

function Window:setTitle(title, ...)
    title = (self.localize and type(title) ~= "table") and Text(title, ...) or title

    self.title = title

    if self.titleLabel then
        self.titleLabel:setText(title)
    end
end

function Window:setIcon(icon)
    self.icon = icon
    if self.iconImage then
        self.iconImage:setTexture(self.icon)
    end
end

function Window:setActive(active)
    if self.active == active then
        return
    end

    SkinnableItem.setActive(self, active)
    self:setState(active and "active" or "inactive")
end

function Window:setCloseable(closeable)
    self.closeable = closeable
    if self.closeButton then
        self.closeButton:setVisible(self.closeable)
        self.closeButton:setEnabled(self.closeable)
    end
end

function Window:mousePress(event)
    if event:button() == MouseButton.Left then
        if self.autoMoveToTop then
            self:moveToTop()
        end

        if event.source == self.titleBar then
            self._moving = true
            self._startMouseX, self._startMouseY = event:absolutePos()
            self._moveStartX, self._moveStartY = self:pos()
        elseif event.source == self.resizeHandle then
            self._resizing = true
            self._startMouseX, self._startMouseY = event:absolutePos()
            self._moveStartX, self._moveStartY = self:pos()
            self._resizeStartWidth, self._resizeStartHeight = self:size()
        end
    else
        event:ignore()
    end
end

function Window:mouseRelease(event)
    if event:button() == MouseButton.Left then
        self._moving = false
        self._resizing = false
        return
    end

    event:ignore()
end

function Window:mouseMove(event)
    if not (self._moving or self._resizing) then
        event:ignore()
        return
    end

    -- The mouse is not allowed to go off the screen
    local absX, absY = event:absolutePos()
    local dx = clamp(absX, 0, Update.virtualScreenWidth) - self._startMouseX
    local dy = clamp(absY, 0, Update.virtualScreenHeight) - self._startMouseY

    if self._resizing then
        -- Depending on where the resize handle is anchored, it affects
        -- the window size differently.
        local dw = self.resizeHandle.right and dx or -dx
        local dh = self.resizeHandle.bottom and dy or -dy

        -- Adjust the diff to potential changes in the window position
        -- during resize (can happen when the window is positioned by a
        -- layout). When the resize handle is anchored to the top or left,
        -- another approach is needed.
        if self.resizeHandle.bottom then
            dh = dh + (self._moveStartY - self.y)
        end
        if self.resizeHandle.right then
            dw = dw + (self._moveStartX - self.x)
        end

        local w = clamp(self._resizeStartWidth + dw, self.minimumWidth, self.maximumWidth)
        local h = clamp(self._resizeStartHeight + dh, self.minimumHeight, self.maximumHeight)

        -- Depending on where the resize handle is anchored, the position
        -- is also affected.
        dx = self.resizeHandle.right and 0 or (self._resizeStartWidth - w)
        dy = self.resizeHandle.bottom and 0 or (self._resizeStartHeight - h)

        self:setSize(w, h)
    end

    -- Try not to fight with AnchorLayout over positioning
    if not (self.left or self.right or self.horizontalCenter) then
        self:setX(self._moveStartX + dx)
    end
    if not (self.top or self.bottom or self.verticalCenter) then
        self:setY(self._moveStartY + dy)
    end
end

return Window
