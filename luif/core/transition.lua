--
-- A transition can contain animations. By default they will run in parallel.
--
-- A transition applies to a state change. Property changes not covered by any
-- animations defined as part of the transition are applied at the start of
-- the transition.
--

local core = require "luif.core"

local Array     = core.Array
local Object    = core.Object
local Parallel  = core.Parallel

local Transition = Object:extend {
    -- A name or list of names of destination states
    to = false,

    -- A name or list of names of source states
    from = false,

    -- Whether the transition is enabled. Disabled transitions will be skipped.
    enabled = true,

    _effect = false,

    _reverts = false,   -- Changes to revert back to base state
    _reverting = false, -- Changes being reverted as part of this transition
}

function Transition.new(class, self)
    self = Object.new(class, self)

    -- Convert the state lists to hash tables for faster lookup
    if type(self.to) == "table" then
        self.to = Array.toSet(self.to)
    end
    if type(self.from) == "table" then
        self.from = Array.toSet(self.from)
    end

    if #self.children == 1 then
        -- Single effect, move it to _effect property
        self._effect = self.children[1]
        self._effect:on("finish", function() self:finish() end)
        self.children = {}
    elseif #self.children > 1 then
        -- Create a Parallel animation when multiple child effects are specified
        self._effect = Parallel {}
        self._effect:on("finish", function() self:finish() end)
        self._effect:setChildren(self.children)
        self.children = {}
    end

    return self
end

function Transition:matches(fromStateName, toStateName)
    return self.enabled and
           (not self.from or self.from == fromStateName or self.from[fromStateName]) and
           (not self.to or self.to == toStateName or self.to[toStateName])
end

-- Recurse down into children to find all the property changes for the given state
-- The 'change' function is called for each property change found. A skinned
-- item's content children are visited instead of its skin (the skin applies
-- its own states), and a walk that reaches a skin's content area from above
-- stops there, because the item that owns it visits its children.
local function processPropertyChanges(item, stateName, change, nested)
    local states = item.states

    if states then
        local stateChanges = states[stateName]
        if stateChanges then
            for property,value in pairs(stateChanges) do
                change(item, property, value)
            end
        end
    end

    if nested then
        local owner = item._contentOwner
        if owner and owner.contentArea == item then
            return
        end
    end

    -- Recurse into the children
    local children, first = item:contentChildren()
    for i=first,#children do
        processPropertyChanges(children[i], stateName, change, true)
    end
end

local function hasChangeFor(changes, target, property)
    if changes then
        for i=1,#changes do
            local change = changes[i]
            if change.target == target and change.property == property then
                return true
            end
        end
    end
end

function Transition:apply(item, fromStateName, toStateName)
    -- Optimistic to avoid creating unnecessary garbage
    local changes = false
    local reverts = false
    local reverting = false

    -- Cancel any previously running transition and inherit its revert list
    local lastTransition = item._runningTransition
    if lastTransition then
        -- Make sure it's no longer running
        lastTransition:cancel()
        -- Transfer the list of reverts to this transition
        reverts, lastTransition._reverts = lastTransition._reverts, false
    end

    -- Collect the property changes for this state
    local addChange = function(target, property, value)
        -- Add a revert for this change if there isn't one already
        if not hasChangeFor(reverts, target, property) then
            reverts = reverts or {}
            reverts[#reverts + 1] = {
                target = target,
                property = property,
                to = target[property]
            }
        end

        -- Add the change to the list
        changes = changes or {}
        changes[#changes + 1] = {
            target = target,
            property = property,
            to = value
        }
    end

    if item.states then
        local changes = item.states[toStateName]

        if changes then
            for c=1,#changes do
                local change = changes[c]

                for property, value in pairs(change) do
                    if property ~= "target" and property ~= "targets" then
                        if change.targets then
                            for i=1,#change.targets do
                                addChange(change.targets[i], property, value)
                            end
                        elseif change.target then
                            addChange(change.target, property, value)
                        else
                            error("No target(s) defined for state changes")
                        end
                    end
                end
            end
        end
    else
        processPropertyChanges(item, toStateName, addChange)
    end

    -- Insert any reverts for properties that didn't get a new value into changes
    if reverts then
        for i=1,#reverts do
            local revert = reverts[i]
            if not hasChangeFor(changes, revert.target, revert.property) then
                revert.from = nil -- Possible reuse, so clear any previous 'from' value
                changes = changes or {}
                changes[#changes + 1] = revert
                reverting = reverting or {}
                reverting[#reverting + 1] = revert
            end
        end
    end

    if self._effect then
        -- Starts the effect, filtering out relevant changes
        self._effect:start(changes)
    end

    if changes then
        -- Apply the remaining changes immediately
        for i=1,#changes do
            local change = changes[i]
            change.target:set(change.property, change.to)
        end
    end

    self._reverts = reverts
    self._reverting = reverting
    item._runningTransition = self

    -- When we have no effect, finish immediately
    if not self._effect then
        self:finish()
    end

end

function Transition:finish()
    -- Remove reverted changes
    if self._reverting then
        for i=1,#self._reverting do
            local reverted = self._reverting[i]
            for j=1,#self._reverts do
                local reverts = self._reverts[j]
                if reverted.target == reverts.target and reverted.property == reverts.property then
                    table.remove(self._reverts, j)
                    break
                end
            end
        end
    end

    -- Clear lists of changes
    self._reverting = false

    -- Unreference reverts table when it is empty
    if self._reverts and #self._reverts == 0 then
        self._reverts = false
    end

end

function Transition:cancel()
    if self._effect then
        self._effect:stop()
        self._reverting = false
    end
end

function Transition:setEnabled(enabled)
    self.enabled = enabled
end

return Transition
