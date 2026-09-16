--
-- Animates properties.
--

local core = require "luif.core"

local Array     = core.Array
local Ease      = core.Ease
local Effect    = core.Effect

local Animate = Effect:extend {
    age = 0,
    progress = 0,

    -- The duration of the animation in milliseconds
    _duration = 250,

    targets = false,    -- Optional list of target IDs

    property = false,   -- Optional property name to match this animation to
    properties = false, -- Optional list of property names to match this animation to
    from = false,       -- Optional explicit value from which to animate
    to = false,         -- Optional explicit value to which to animate

    ease = Ease.linear,

    _changes = false,
}

local function prepareForTarget(self, target)
    if self.property then
        self._changes = self._changes or {}
        self._changes[#self._changes + 1] = {
            target = target,
            property = self.property,
            from = self.from or target[self.property],
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
                from = self.from or target:get(property),
                to = self.to
            }
        end
    end
end

function Animate.new(class, self)
    local ease = self.ease or class.ease
    if type(ease) == "string" then
        self.ease = assert(Ease[ease], "unknown easing curve")
    end
    return Effect.new(class, self)
end

function Animate:prepare(changes)
    Effect.prepare(self, changes)

    self._changes = false

    -- Add any explicitly defined changes to our list
    if self.to then
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
            local target = change.target
            local property = change.property

            if ((not (self.property or self.properties)) or
                (self.property and self.property == property) or
                (self.properties and Array.contains(self.properties, property))) and
               (not (self._target or self.targets) or
                self._target == target or
                self._target == target.id or
                (self.targets and (Array.contains(self.targets, target) or
                                   Array.contains(self.targets, target.id))))
            then
                self._changes = self._changes or {}

                -- Create a copy when we have a target value and leave the
                -- original change alone, which may still be picked up by
                -- another effect.
                if self.to then
                    self._changes[#self._changes + 1] = {
                        target = target,
                        property = property,
                        from = change.from,
                        to = self.to,
                    }
                else
                    self._changes[#self._changes + 1] = change
                    table.remove(changes, i)
                end
            end
        end
    end

    -- Remember the from values
    if self._changes then
        for i=1,#self._changes do
            local change = self._changes[i]
            local property = change.property
            change.from = self.from or change.from or change.target:get(property)
            self:checkChange(change)
        end
    end

    self.age = 0
end

function Animate:checkChange(change)
    assert(type(change.from) == "number", "can't interpolate non-numbers")
    assert(type(change.to) == "number", "can't interpolate non-numbers")
end

-- Advances the animation by the given time delta and updates properties
function Animate:update(deltaTime)
    self.age = self.age + deltaTime
    local finished = self.age >= self._duration

    self.progress = finished and 1 or self.ease(self.age / self._duration)

    if self._changes then
        for i=1,#self._changes do
            local change = self._changes[i]
            local property = change.property
            local value = self:interpolate(change.from, change.to, self.progress)
            change.target:set(property, value)
        end
    end

    return Effect.update(self, deltaTime, self.age - self._duration)
end

-- Stops the animation and sets all properties back to their initial value
function Animate:reset()
    if self._changes then
        for i=1,#self._changes do
            local change = self._changes[i]
            change.target:set(change.property, change.from)
        end
    end

    Effect.reset(self)
end

function Animate:isDone()
    return self.age >= self._duration
end

function Animate:finalize()
    self._changes = false
end

-- Interpolation function, defaults to standard numerical interpolation
function Animate:interpolate(from, to, progress)
    return from + (to - from) * progress
end

return Animate
