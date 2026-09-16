--
-- Turns any class into a singleton, providing an API to create/delete
-- the instance and providing access to the instance itself.
--

return function(class)
    assert(type(class) == "table", "No valid class provided")

    local instance = nil

    return {
        create = function()
            assert(instance == nil, "Instance already created")
            instance = class {}
            return instance
        end,

        delete = function()
            assert(instance ~= nil, "No instance created")
            instance:delete()
            instance = nil
        end,

        isCreated = function()
            return instance ~= nil
        end,

        instance = function()
            if instance == nil then
                instance = class {}
            end
            return instance
        end,
    }
end
