--
-- A simple button class with optional label, icon and hoverIcon.
--

local core = require "luif.core"

local ActionBindings = core.ActionBindings
local Sounds = core.Sounds
local TexDb  = core.TexDb
local MouseButton = core.MouseButton

local SkinnableItem = core.SkinnableItem
local DefaultButtonSkin = core.skins.DefaultButtonSkin

local Button = SkinnableItem:extend {
    text = "",
    localize = false,

    selectable = false,
    selected = false,
    sticky = false,     -- Whether the button can be un-toggled interactively
    exclusiveGroup = false,
    focusOnPress = false,
    selectOnPress = false,
    stayPressedOnLeave = false,

    iconSource = false,
    icon = TexDb.empty,
    hoverIcon = false,
    selectedIcon = false,

    fontScale = false,

    clickSound = Sounds.UI.Click,
    disabledClickSound = Sounds.UI.Deny,
    enterSound = Sounds.UI.Hover,
    leaveSound = false,

    skinClass = DefaultButtonSkin,

    mouseEnabled = true,

    skinParts = {
        "label",
        "iconImage",
        "hoverIconImage",
        "selectedIconImage",
    },

    -- Callback functions
    press = false,      -- function(): the button is pressed
    release = false,    -- function(): the button is released
    click = false,      -- function(): the button is clicked
    enter = false,      -- function(): mouse enters the button
    leave = false,      -- function(): mouse leaves the button
    change = false,     -- function(selected, user): button is toggled
                        -- ('user' is "Mouse", "Keyboard" or true when the user toggled it, otherwise false)

    tickInterval = false,

    _mousePressed = false,
    _keyPressed = false,

    -- Used for "hover" state, which behaves a little bit different from _hasMouse. This variable
    -- is true when either the button, or any one of its children, has the mouse (and isn't eating
    -- mouseEntered events).
    _mouseEntered = false,
}

function Button.new(class, self)
    self = SkinnableItem.new(class, self)

    if self.label then
        self.label:setLocalize(self.localize)
        self.label:setText(self.text)
        if self.fontScale then
            self.label:setTextScale(self.fontScale)
        end
    end

    if self.iconImage then
        if self.iconSource then
            self.icon = TexDb[self.iconSource]
        end
        self.iconImage:setTexture(self.icon)
    end
    if self.hoverIcon and self.hoverIconImage then
        self.hoverIconImage:setTexture(self.hoverIcon)
    end
    if self.selectedIcon and self.selectedIconImage then
        self.selectedIconImage:setTexture(self.selectedIcon)
    end

    assert(self.state ~= "disabled", "Manually setting the state not permitted. Set enabled=false instead.")

    self:updateState()

    if self.exclusiveGroup then
        self.exclusiveGroup:bindSelectable(self)
    end

    if self.skin then
        self.resizeTo = self.skin.resizeTo
        self.resizeToMargin = self.skin.resizeToMargin
    end

    if self.resizeTo then
        self[self.resizeTo]:on("implicitSizeChanged", function() self:updateResizeTo() end)
    end

    self:setMouseCursor("arrow")

    return self
end

function Button:attached()
    self:updateResizeTo()
end

function Button:setMouseEnabled(mouseEnabled)
    SkinnableItem.setMouseEnabled(self, mouseEnabled)
    if not mouseEnabled then
        self._mouseEntered = false
        self:updateState()
    end
end

function Button:updateResizeTo()
    if self.resizeTo and self[self.resizeTo] then
        local child = self[self.resizeTo]
        local width, height = child:implicitSize()
        local margin = self.resizeToMargin or { left = 0, top = 0, right = 0, bottom = 0 }
        width = math.max(math.min(width + margin.left + margin.right, self.maximumWidth), self.minimumWidth)
        height = math.max(math.min(height + margin.top + margin.bottom, self.maximumHeight), self.minimumHeight)
        self:setSize(width, height)
    end
end

function Button:delete()
    if self.exclusiveGroup then
        self.exclusiveGroup:unbindSelectable(self)
    end

    return SkinnableItem.delete(self)
end

function Button:setEnabled(enabled, animate)
    SkinnableItem.setEnabled(self, enabled)
    self:updateState(animate)
end

function Button:setText(text, ...)
    self.text = text
    if self.label then
        self.label:setText(text, ...)
        if self.resizeTo == "label" then
            self:updateResizeTo()
        end
    end
end

function Button:setLocalize(localize)
    if self.localize == localize then
        return
    end

    self.localize = localize
    if self.label then
        self.label:setLocalize(localize)
    end
end

function Button:setExclusiveGroup(exclusiveGroup)
    if self.exclusiveGroup == exclusiveGroup then
        return
    end

    if self.exclusiveGroup then
        self.exclusiveGroup:unbindSelectable(self)
    end

    self.exclusiveGroup = exclusiveGroup

    if self.exclusiveGroup then
        self.exclusiveGroup:bindSelectable(self)
    end
end

function Button:setIcon(icon)
    self.icon = icon
    if self.iconImage then
        self.iconImage:setTexture(icon)
        if self.resizeTo == "iconImage" then
            self:updateResizeTo()
        end
    end
end

function Button:setIconSource(name)
    self.iconSource = name
    self:setIcon(TexDb[name])
end

function Button:setHoverIcon(icon)
    self.hoverIcon = icon
    if self.hoverIconImage then
        self.hoverIconImage:setTexture(icon)
        if self.resizeTo == "hoverIconImage" then
            self:updateResizeTo()
        end
    end
end

function Button:setSelectedIcon(icon)
    self.selectedIcon = icon
    if self.selectedIconImage then
        self.selectedIconImage:setTexture(icon)
        if self.resizeTo == "selectedIconImage" then
            self:updateResizeTo()
        end
    end
end

function Button:updateState(animate)
    local state = "up"

    if not self.enabled then
        state = "disabled"
    elseif self._keyPressed then
        state = "down"
    elseif self._mousePressed then
        -- Down while the mouse is still on the button (or stayPressedOnLeave), otherwise over
        state = (self._mouseEntered or self.stayPressedOnLeave) and "down" or "over"
    elseif self._mouseEntered then
        state = "over"
    end

    if self.selected then
        state = state .. "AndSelected"
    end

    self:setState(state, animate)
end

function Button:setSelected(selected, animate, user)
    if self.selected == selected then
        return
    end

    self.selected = selected

    self:emit("change", selected, user or false)

    self:updateState(animate)
end

function Button:toggle(animate, user)
    self:setSelected(not self.selected, animate, user)
end

function Button:toggleAsUser(animate)
    self:setSelected(not self.selected, animate, true)
end

function Button:mouseEnter(event)
    self._mouseEntered = true
    if not (self.stayPressedOnLeave and self._mousePressed) then
        self:updateState()
        if self.enabled and self.enterSound then
            Sounds.play(self.enterSound)
        end
        self:emit("enter")
    end
    event:ignore()
end

function Button:mouseLeave(event)
    self._mouseEntered = false
    if not (self.stayPressedOnLeave and self._mousePressed) then
        self:updateState()
        if self.leaveSound then
            Sounds.play(self.leaveSound)
        end
        self:emit("leave")
    end
    event:ignore()
end

function Button:mousePress(event)
    if event:button() == MouseButton.Left then
        if self.enabled then
            self._mousePressed = true

            if self.focusOnPress then
                self:setFocus()
            end
            local sound = self.clickSound
            if self.selectable then
                if self.selectOnPress then
                    if self.sticky and self.selected then
                        sound = self.disabledClickSound
                    else
                        self.selected = not self.selected
                        self:emit("change", self.selected, "Mouse")
                    end
                elseif self.sticky and self.selected then
                    sound = self.disabledClickSound
                end
            end
            self:updateState()
            self:emit("press")
            self:startTimeout()

            if sound then
                Sounds.play(sound)
            end
        else
            if self.disabledClickSound then
                Sounds.play(self.disabledClickSound)
            end
        end
    else
        event:ignore()
    end
end

function Button:mouseDoubleClick(event)
    return self:mousePress(event)
end

function Button:mouseRelease(event)
    if event:button() == MouseButton.Left then
        self._mousePressed = false

        -- A release while under the mouse always means we've been clicked
        if self._mouseEntered and self.enabled then
            if self.selectable and not self.selectOnPress and not (self.sticky and self.selected) then
                self.selected = not self.selected
                self:emit("change", self.selected, "Mouse")
            end
            self:emit("release")
            self:emit("click")
            self:updateState()
            self:stopTimeout()
        elseif self.enabled then
            self:emit("release")
            self:updateState()
        end
    else
        event:ignore()
    end
end

function Button:actionPress(action)
    if action == "Activate" then
        self._keyPressed = true

        if self.enabled then
            self:updateState()
            self:emit("press")
        end
    end
end

function Button:keyPress(event)
    local action = ActionBindings.mapKeyPress(event:key())
    if action then
        self:actionPress(action)
    else
        event:ignore()
    end
end

function Button:keyRelease(event)
    if ActionBindings.mapKeyPress(event:key()) == "Activate" then
        self._keyPressed = false

        if self.enabled then
             if self.selectable and not (self.sticky and self.selected) then
                self.selected = not self.selected
                self:emit("change", self.selected, "Keyboard")
            end
            self:emit("release")
            self:emit("click")
            self:updateState()
        end
    else
        event:ignore()
    end
end

function Button:startTimeout()
    if self.tickInterval then
        self:setTimeout("tick", 3 * self.tickInterval, function() self:timeout() end)
    end
end

function Button:stopTimeout()
    self:clearTimeout("tick")
end

function Button:timeout()
    -- Only apply value change when the button is still down
    if self:isDown() then
        self:emit("tick")
    end

    -- Reschedule the timeout
    self:setTimeout("tick", self.tickInterval, function() self:timeout() end)
end

function Button:isDown()
    return (self._mousePressed and self._mouseEntered) or self._keyPressed
end

return Button
