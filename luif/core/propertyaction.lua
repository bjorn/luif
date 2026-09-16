--
-- Applies property values.
--
-- This effect is mainly useful for controlling when certain non-animated
-- values change in a transition.
--

local core = require "luif.core"

local Array     = core.Array
local Effect    = core.Effect

local PropertyAction = Effect:extend {
    targets = false,    -- Optional list of target IDs (not inherited at the moment, unlike target)

    property = false,   -- Optional property name to match this animation to
    properties = false, -- Optional list of property names to match this animation to
    to = nil,           -- Optional explicit value to which to animate

    _changes = false,
}

local function prepareForTarget(self, target)
    if self.property then
        self._changes = self._changes or {}
        self._changes[#self._changes + 1] = {
            target = target,
            property = self.property,
            to = self.to
        }
    end
    if self.properties then
        for i=1,#self.properties do
            local property = self.properties[i]
            self._changes = self._changes or {}
            self._changes[#self._changes + 1] = {
                target = target,
                property = property,
                to = self.to
            }
        end
    end
end

function PropertyAction:prepare(changes)
    Effect.prepare(self, changes)

    self._changes = false

    -- Add any explicitly defined changes to our list
    if self.to ~= nil then
        if type(self._target) == "table" then
            prepareForTarget(self, self._target)
        end
        if self.targets then
            for i=1,#self.targets do
                local target = self.targets[i]
                if type(target) == "table" then
                    prepareForTarget(self, target)
                end
            end
        end
    end

    -- Only look for implicit matches when no explicit changes were defined
    if not self._changes and changes then
        for i=#changes,1,-1 do
            local change = changes[i]

            if ((not (self.property or self.properties)) or
                (self.property and self.property == change.property) or
                (self.properties and Array.contains(self.properties, change.property))) and
               (not (self._target or self.targets) or
                self._target == change.target or
                self._target == change.target.id or
                (self.targets and (Array.contains(self.targets, change.target) or
                                   Array.contains(self.targets, change.target.id))))
            then
                self._changes = self._changes or {}

                -- Create a copy when we have a target value and leave the
                -- original change alone, which may still be picked up by
                -- another effect.
                if self.to ~= nil then
                    self._changes[#self._changes + 1] = {
                        target = change.target,
                        property = change.property,
                        to = self.to,
                    }
                else
                    self._changes[#self._changes + 1] = change
                    table.remove(changes, i)
                end
            end
        end
    end
end

-- Advances the animation by the given time delta and updates properties
function PropertyAction:update(deltaTime)
    if self._changes then
        for i=1,#self._changes do
            local change = self._changes[i]
            change.target:set(change.property, change.to)
        end
    end

    return Effect.update(self, deltaTime)
end

-- Stops the animation and sets all properties back to their initial value
function PropertyAction:reset()
    if self._changes then
        for i=1,#self._changes do
            local change = self._changes[i]
            change.target:set(change.property, change.from)
        end
    end

    Effect.reset(self)
end

function PropertyAction:finalize()
    self._changes = false
end

return PropertyAction
