--
-- Node tree bookkeeping shared by the hosts written in Lua. A tree has a
-- hidden root record whose children are the top level nodes. Node records
-- need the fields parent (a node, the root, or false when detached),
-- children (array) and destroyed (boolean); hosts add their own fields.
-- Implements the structure semantics of host/interface.lua.
--

local remove, insert = table.remove, table.insert

local Tree = {}

function Tree.newRoot()
    return { parent = false, children = {}, destroyed = false, isRoot = true }
end

-- Raises unless node is a live node record.
function Tree.check(node, what)
    if type(node) ~= "table" or type(node.children) ~= "table" or node.isRoot then
        error((what or "node") .. " is not a node", 3)
    end
    if node.destroyed then
        error((what or "node") .. " was destroyed", 3)
    end
    return node
end

local function indexOf(list, node)
    for i = #list, 1, -1 do
        if list[i] == node then return i end
    end
    return nil
end

local function unlink(node)
    local parent = node.parent
    if parent then
        local i = indexOf(parent.children, node)
        if i then remove(parent.children, i) end
        node.parent = false
    end
end

function Tree.attach(root, node, parent, nextSibling)
    Tree.check(node, "attach: node")
    if parent == nil then
        parent = root
    else
        Tree.check(parent, "attach: parent")
        local p = parent
        while p do
            if p == node then
                error("attach: cannot attach a node under itself or its subtree", 2)
            end
            p = p.parent
        end
    end
    if nextSibling ~= nil then
        Tree.check(nextSibling, "attach: nextSibling")
        if nextSibling == node or nextSibling.parent ~= parent then
            error("attach: nextSibling is not another child of parent", 2)
        end
    end
    unlink(node)
    local children = parent.children
    if nextSibling then
        insert(children, indexOf(children, nextSibling), node)
    else
        children[#children + 1] = node
    end
    node.parent = parent
end

function Tree.detach(node)
    Tree.check(node, "detach: node")
    unlink(node)
end

local function release(node, onRelease)
    local children = node.children
    for i = 1, #children do
        local child = children[i]
        child.parent = false
        release(child, onRelease)
    end
    node.children = {}
    node.destroyed = true
    if onRelease then onRelease(node) end
end

-- Detaches the node, then marks it and its subtree destroyed, children
-- first; onRelease(node) runs for each.
function Tree.destroy(node, onRelease)
    Tree.check(node, "destroyNode: node")
    unlink(node)
    release(node, onRelease)
end

-- True when the node hangs below the root.
function Tree.inScene(node)
    local p = node.parent
    while p do
        if p.isRoot then return true end
        p = p.parent
    end
    return false
end

-- A snapshot of the node's common state for inspect(); copyContent copies
-- the content record.
function Tree.snapshot(node, copyContent)
    local children = {}
    for i = 1, #node.children do children[i] = node.children[i] end
    local parent = node.parent
    return {
        parent = (parent and not parent.isRoot) and parent or nil,
        topLevel = parent and parent.isRoot or false,
        inScene = Tree.inScene(node),
        children = children,
        x = node.x, y = node.y, rotation = node.rotation, scale = node.scale,
        originX = node.ox, originY = node.oy,
        width = node.width, height = node.height,
        opacity = node.opacity, visible = node.visible, clip = node.clip,
        content = copyContent(node.content),
    }
end

-- The top level nodes, copied.
function Tree.topLevel(root)
    local list = {}
    for i = 1, #root.children do list[i] = root.children[i] end
    return list
end

return Tree
