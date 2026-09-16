local core = require "luif.core"

local Class = core.Class
local Debug = core.Debug

local EffectManager = Class:extend {
    runningAnimations = {},
    pendingChanges = {},
}

function EffectManager:add(animation)
    self.pendingChanges[animation] = true
end

function EffectManager:remove(animation)
    self.pendingChanges[animation] = false
end

function EffectManager:update(deltaTime)
    for animation, playing in pairs(self.pendingChanges) do
        self.runningAnimations[animation] = playing and animation or nil
        self.pendingChanges[animation] = nil
    end

    for animation in pairs(self.runningAnimations) do
        if self.pendingChanges[animation] == nil then
            if not animation.paused and animation:update(deltaTime) then
                animation:setRunning(false)
                animation:emit("finish")
            end
        end
    end
end

function EffectManager:dump()
    Debug.dbgprint("EffectManager", "Running Animations:")
    for _,animation in pairs(self.runningAnimations) do
        Debug.dbgprint("EffectManager", " ", animation:toString(), animation:locationCreated())
    end
end

return EffectManager
