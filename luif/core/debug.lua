--
-- Debug helpers of core:
--
--   local Debug = core.Debug
--   Debug.dbg(fn)                 runs fn only while debugging is enabled
--   Debug.dbgprint(channel, ...)  prints "[channel]" and the values
--   Debug.dbgtrace(msg, level)    prints msg with a traceback
--   Debug.setEnabled(flag)
--
-- Debugging is off by default; the application enables it (the example
-- does so when LUIF_DEBUG is set). The hooks in core/class.lua
-- are installed when core.class loads, so enable debugging before that.
--

local Debug = {
    enabled = false,
}

function Debug.setEnabled(flag)
    Debug.enabled = flag and true or false
end

function Debug.dbg(fn)
    if Debug.enabled then
        return fn()
    end
end

function Debug.dbgprint(channel, ...)
    print("[" .. tostring(channel) .. "]", ...)
end

-- level counts from the caller of dbgtrace, like debug.traceback's own.
function Debug.dbgtrace(msg, level)
    print(debug.traceback(tostring(msg), (level or 1) + 1))
end

return Debug
