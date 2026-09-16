--
-- A modal message dialog: a dimmed, full screen InputBlocker holding a framed
-- panel that pops in with a Fade and an outBack Scale, after the
-- MessageDialog of the Source of Tales client. Return confirms, Escape cancels, and
-- nothing underneath receives input while it is open.
--
--   dialog:open {
--       title = "Quit", message = "Leave the example?",
--       confirmText = "Quit", cancelText = "Stay",  -- without cancelText: one button
--       confirmed = function() ... end, canceled = function() ... end,
--   }
--

local core = require "luif.core"

local FontDb   = core.FontDb
local TopLayer = core.TopLayer

local Host  = core.Host
local skins = require "skins"

local PANEL_WIDTH, PANEL_HEIGHT = 420, 150
local MESSAGE_TOP, MESSAGE_MARGIN, BUTTON_AREA = 48, 30, 74

local Dialog = core.InputBlocker:extend {
    panel = false,
    titleLabel = false,
    messageLabel = false,
    confirmButton = false,
    cancelButton = false,

    _options = false,
}

function Dialog.new(class, self)
    self.layout = core.AnchorLayout {}

    self.titleLabel = core.Label {
        text = "", wrap = false,
        font = FontDb.Small, color = 0xFF1C2433,
        horizontalCenter = 0, top = 7,
    }
    self.messageLabel = core.Label {
        text = "", align = "center",
        color = 0xFFC8E8E8,
        left = MESSAGE_MARGIN, right = MESSAGE_MARGIN, top = MESSAGE_TOP,
    }
    self.confirmButton = core.Button {
        skinClass = skins.CompactButtonSkin, text = "OK",
        right = 22, bottom = 20,
    }
    self.cancelButton = core.Button {
        skinClass = skins.CompactButtonSkin, text = "Cancel",
        left = 22, bottom = 20,
    }

    self.panel = core.Item {
        width = PANEL_WIDTH, height = PANEL_HEIGHT,
        horizontalCenter = 0, verticalCenter = 0,
        layout = core.AnchorLayout {},

        core.Rectangle { color = 0xFF000000, alpha = 170, left = 3, top = 3, right = 3, bottom = 3 },
        core.Scale9 { source = "frame_with_title", left = 0, top = 0, right = 0, bottom = 0 },
        self.titleLabel,
        self.messageLabel,
        self.cancelButton,
        self.confirmButton,
    }

    self.children = {
        core.Rectangle { color = 0xFF000000, alpha = 150, left = 0, top = 0, right = 0, bottom = 0 },
        self.panel,
    }

    self = core.InputBlocker.new(class, self)

    self.confirmButton.click = function() self:close(true) end
    self.cancelButton.click = function() self:close(false) end

    return self
end

function Dialog:isOpen()
    return self.visible
end

function Dialog:open(options)
    self._options = options

    self.titleLabel:setText((options.title or ""):upper())
    self.messageLabel:setText(options.message or "")
    self.confirmButton:setText(options.confirmText or "OK")
    self.cancelButton:setText(options.cancelText or "")
    self.cancelButton:setVisible(options.cancelText ~= nil)

    -- Grow the panel with the message
    local font = self.messageLabel.font
    local host = Host.get()
    local _, lines = host.wrapText(font, options.message or "", PANEL_WIDTH - 2 * MESSAGE_MARGIN)
    local height = math.max(PANEL_HEIGHT,
                            MESSAGE_TOP + #lines * host.lineHeight(font) + BUTTON_AREA)
    self.panel:setHeight(height)

    if self.visible then
        return
    end

    -- The top layer covers the whole screen and is kept above everything
    local layer = TopLayer.instance()
    if self.parent ~= layer then
        layer:addChild(self)
    end
    self:setSize(layer:size())

    -- Start from the hidden look so the first frame does not flash
    self:setAlpha(0)
    self.panel:setScale(0.75)

    self:show(core.Parallel {
        core.Fade { from = 0, to = 255, duration = 200, ease = "outQuad" },
        core.Scale { target = self.panel, from = 0.75, to = 1, duration = 320, ease = "outBack" },
    })
end

function Dialog:close(confirmed)
    if not self.visible then
        return
    end

    local options = self._options
    self._options = false

    self:hide(core.Parallel {
        core.Fade { to = 0, duration = 150, ease = "inQuad" },
        core.Scale { target = self.panel, to = 0.9, duration = 150, ease = "inQuad" },
    })

    local callback = options and (confirmed and options.confirmed or options.canceled)
    if callback then
        callback()
    end
end

-- Keeps the layer covering the screen when the UI scale or window changes
function Dialog:fitToParent()
    if self.parent then
        self:setSize(self.parent:size())
    end
end

-- The InputBlocker swallows every event; keys are handled on the way.
function Dialog:event(event)
    if event.name == "keyPress" and not event:isAutoRepeat() then
        if event:isKey("return", "kpenter", "space") then
            self:close(true)
        elseif event:isKey("escape") then
            self:close(false)
        end
    end
    return true
end

return Dialog
