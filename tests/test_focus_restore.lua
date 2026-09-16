--
-- Focus is a reference to an item. A focused item that is detached and
-- attached again keeps the focus, unless the focus moved elsewhere
-- meanwhile; keys reach it only while it is attached. setFocus on an item
-- that is not attached applies once it is. Deleting the focused item clears
-- the focus.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Pointer = require "luif.core.pointer"
    local Sync = require "luif.core.sync"
    local InputFeed = require "tests.inputfeed"

    -- Loaded first: FallbackListeners installs its own fallback when loaded
    require "luif.core.focusscope"
    local feed = InputFeed.attach()
    local previousFallback = Pointer.fallback()
    local fallbacks = 0
    Pointer.setFallback(function() fallbacks = fallbacks + 1 end)

    local root = core.Item { width = 400, height = 300 }
    Sync.addRoot(root)

    local lost, keys = 0, 0
    local field = core.Item {
        width = 50, height = 20, mouseEnabled = true,
        focusLose = function() lost = lost + 1 end,
        keyPress = function() keys = keys + 1 end,
    }
    root:addChild(field)
    field:setFocus()
    t.ok(field:hasFocus(), "field has focus")
    feed.key("a")
    t.eq(keys, 1, "keys reach the attached focused field")

    -- Moving it under an item that is not attached detaches it
    local holder = core.Item { width = 100, height = 100 }
    field:setParent(holder)
    t.ok(not field:isAttached(), "field detached under a detached parent")
    t.ok(field:hasFocus(), "a detached item keeps the focus reference")
    fallbacks = 0
    feed.key("a")
    t.eq(keys, 1, "keys do not reach a detached focused item")
    t.eq(fallbacks, 2, "they go to the fallback instead (press and release)")
    root:addChild(holder)
    t.ok(field:isAttached(), "field attached again with its parent")
    t.ok(field:hasFocus(), "focus kept when attached again")
    t.eq(lost, 0, "no focus loss for a kept focus")
    feed.key("a")
    t.eq(keys, 2, "keys reach it again")

    -- Focus that moves elsewhere while the field is detached stays there
    local limbo = core.Item {}
    field:setParent(limbo)
    local other = core.Item { x = 100, width = 50, height = 20, mouseEnabled = true }
    root:addChild(other)
    other:setFocus()
    t.eq(lost, 1, "the detached field is told it lost the focus")
    field:setParent(holder)
    t.ok(field:isAttached() and not field:hasFocus(), "field does not take the focus back")
    t.ok(other:hasFocus(), "the other item keeps the focus")

    -- setFocus before attachment applies once attached
    local later = core.Item { width = 10, height = 10, mouseEnabled = true }
    later:setFocus()
    t.ok(not other:hasFocus(), "focus left the previous item")
    t.eq(Pointer.focused(), later, "the focus is the detached item")
    root:addChild(later)
    t.ok(later:hasFocus(), "focus given before attachment applies once attached")

    -- Deleting the focused item clears the focus
    later:setParent(limbo)
    later:delete()
    t.eq(Pointer.focused(), nil, "deleting the focused item clears the focus")
    local ok, err = pcall(function() other:setFocus() end)
    t.ok(ok, "no call into a deleted item: " .. tostring(err))
    t.ok(other:hasFocus(), "focus can be set after the focused item was deleted")

    other:setFocus(false)
    limbo:delete()
    root:delete()
    require("luif.core.sync").flush()
    Pointer.setFallback(previousFallback)
    feed.detach()
end
