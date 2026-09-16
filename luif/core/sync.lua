--
-- Mirrors the item tree into a retained host scene (host/interface.lua):
-- one host node per attached item. Items only describe themselves and mark
-- what changed; Sync.flush(), once per frame after layout, creates, moves and
-- destroys nodes and pushes node properties and content. Nothing else in
-- core touches nodes.
--
--   Sync.flush()                    applies every pending change
--   Sync.propertiesChanged(item)    transform, size, opacity, visibility, clip
--   Sync.contentChanged(item)       content
--   Sync.childrenChanged(item)      the item's node children (nil: the roots)
--   Sync.addRoot(item)              makes a parentless item a root and attaches its tree
--   Sync.removeRoot(item)           unregisters a root and detaches its tree
--   Sync.raiseRoot(item)            moves a root to the top
--   Sync.isRoot(item), Sync.roots() the registered roots, bottom to top
--   Sync.attached(item)             an item joined a root (marks it dirty)
--   Sync.deleted(item)              an item was deleted
--   Sync.setHost(host)              host for new roots (nil: the application host)
--   Sync.host(item)                 host of the item's root, or the default
--   Sync.node(item)                 the item's node, for tests and tools
--   Sync.uiScale()                  the UI scale root nodes get (Update.uiScale)
--   Sync.setScaleSource(fn)         where uiScale() reads it (core/update.lua sets it)
--
-- Items implement:
--
--   item:describeNode(p)    fills p.x, p.y, p.rotation (radians), p.scale,
--                           p.originX, p.originY, p.width, p.height,
--                           p.opacity (0..1), p.visible and p.clip; p starts
--                           with the node defaults
--   item:pushContent(host, node)
--                           sets the node's content with a host content
--                           function (setImage, setSlices, setText or
--                           setFill); items without content do nothing.
--                           An item that needs more than one content has
--                           child items for the rest
--
-- Structure: a node's children are the nodes of the item's children, in
-- child order (a skinnable item's skin is its first child, and its content
-- children are children of the skin's content area). Roots are top level
-- nodes in their registration order.
--
-- Roots: applications register their top level items with Sync.addRoot
-- (TopLayer and tooltips do the same), and Sync.removeRoot or deleting the
-- item unregisters them. Giving a root a parent unregisters it too.
--
-- Hosts: a root's nodes live in the host that was the default when the root
-- was registered (Sync.setHost, by default the application host of
-- core/host.lua). Tests render a tree into a recording host
-- (host/recording.lua) by setting it before registering the root.
--
-- UI scale: items are in virtual units. The flush composes Update.uiScale
-- (Sync.uiScale()) into the transform of every root node, so only root nodes
-- carry it; a root's own x, y and scale stay virtual. A changed scale re-pushes
-- the root transforms in the next flush. core/pointer.lua divides the input
-- feed by the same scale.
--
-- The flush only pushes the node properties that differ from what a node
-- has. Content is pushed again whenever the item marked it changed (setters
-- skip values that did not change), and a frame without changes makes no
-- host calls. Nodes are created and attached first and destroyed last, so an
-- item moved out of a subtree that leaves in the same frame keeps its node. The flush is bracketed with beginBatch and
-- endBatch on hosts that have them.
--

local core = require "luif.core"

local Host = core.Host

local Sync = {}

local remove = table.remove

local override = false

function Sync.setHost(host)
    override = host or false
end

function Sync.defaultHost()
    return override or Host.get()
end

--
-- UI scale
--

local scaleSource = false
local appliedScale = 1          -- the scale root nodes were pushed with

-- core/update.lua registers Update.uiScale as the source when it loads;
-- without a source the scale is 1.
function Sync.setScaleSource(fn)
    scaleSource = fn or false
end

function Sync.uiScale()
    return scaleSource and scaleSource() or 1
end

--
-- Roots
--

local roots = {}                -- registered roots, bottom to top
local rootHosts = {}            -- root -> host

function Sync.isRoot(item)
    return rootHosts[item] ~= nil
end

function Sync.roots()
    return roots
end

-- The host the item's nodes live in, or the host a new root would use.
function Sync.host(item)
    local root = item and item._root
    return root and rootHosts[root] or Sync.defaultHost()
end

--
-- Dirty marking
--

local dirtyProps = {}
local dirtyContent = {}
local dirtyChildren = {}
local rootsDirty = false
local anyDirty = false

function Sync.propertiesChanged(item)
    if item._root then
        dirtyProps[item] = true
        anyDirty = true
    end
end

function Sync.contentChanged(item)
    if item._root then
        dirtyContent[item] = true
        anyDirty = true
    end
end

function Sync.childrenChanged(item)
    if item then
        dirtyChildren[item] = true
    else
        rootsDirty = true
    end
    anyDirty = true
end

-- Registers a parentless item (core/item.lua) as a root in the default host
-- and attaches its tree: its items get nodes in the next flush.
function Sync.addRoot(item)
    assert(not item.parent, "Sync.addRoot: the item has a parent")
    if rootHosts[item] then
        return
    end
    rootHosts[item] = Sync.defaultHost()
    roots[#roots + 1] = item
    rootsDirty, anyDirty = true, true
    item:_setRoot(item)
end

-- Unregisters a root and detaches its tree, unless the item already joined
-- another root (Item:setParent moves a root into an attached tree that way).
function Sync.removeRoot(item)
    if not rootHosts[item] then
        return
    end
    rootHosts[item] = nil
    for i = #roots, 1, -1 do
        if roots[i] == item then
            remove(roots, i)
        end
    end
    rootsDirty, anyDirty = true, true
    if item._root == item then
        item:_setRoot(false)
    end
end

function Sync.raiseRoot(item)
    if not rootHosts[item] or roots[#roots] == item then
        return
    end
    for i = #roots, 1, -1 do
        if roots[i] == item then
            remove(roots, i)
        end
    end
    roots[#roots + 1] = item
    rootsDirty, anyDirty = true, true
end

--
-- Records: the node of an item and what the node has
--
--   { item, host, node, parent = record, kids = { record, ... },
--     nodeParent = record, state }
--
-- kids are the records of the node's children in child order. parent is
-- false for a record that lost its place in this flush; nodeParent is where
-- its node still physically is. A top record per host stands for the top
-- level (node nil).
--

local records = {}
local tops = {}                 -- host -> top record

local function topOf(host)
    local top = tops[host]
    if not top then
        top = { host = host, node = nil, kids = {}, top = true }
        tops[host] = top
    end
    return top
end

function Sync.node(item)
    local rec = records[item]
    return rec and rec.node or nil
end

-- An item joined a root: a node it kept (detached and attached again before
-- a flush) did not see the changes made meanwhile.
function Sync.attached(item)
    if records[item] then
        dirtyProps[item] = true
        dirtyContent[item] = true
        dirtyChildren[item] = true
        anyDirty = true
    end
end

function Sync.deleted(item)
    dirtyProps[item] = nil
    dirtyContent[item] = nil
    dirtyChildren[item] = nil
    local rec = records[item]
    if rec then
        rec.deleted = true
    end
end

--
-- Properties
--

local function newState()
    return {
        x = 0, y = 0, rotation = 0, scale = 1, originX = 0, originY = 0,
        width = 0, height = 0, opacity = 1, visible = true, clip = false,
    }
end

-- Scratch table handed to describeNode, reset to the node defaults first.
local scratch = newState()

local function resetScratch()
    local p = scratch
    p.x, p.y, p.rotation, p.scale, p.originX, p.originY = 0, 0, 0, 1, 0, 0
    p.width, p.height, p.opacity, p.visible, p.clip = 0, 0, 1, true, false
    return p
end

local function pushProperties(host, node, state, p)
    if p.x ~= state.x or p.y ~= state.y or p.rotation ~= state.rotation or p.scale ~= state.scale
            or p.originX ~= state.originX or p.originY ~= state.originY then
        host.setTransform(node, p.x, p.y, p.rotation, p.scale, p.originX, p.originY)
        state.x, state.y, state.rotation, state.scale = p.x, p.y, p.rotation, p.scale
        state.originX, state.originY = p.originX, p.originY
    end
    if p.width ~= state.width or p.height ~= state.height then
        host.setSize(node, p.width, p.height)
        state.width, state.height = p.width, p.height
    end
    if p.opacity ~= state.opacity then
        host.setOpacity(node, p.opacity)
        state.opacity = p.opacity
    end
    local visible = p.visible and true or false
    if visible ~= state.visible then
        host.setVisible(node, visible)
        state.visible = visible
    end
    local clip = p.clip and true or false
    if clip ~= state.clip then
        host.setClip(node, clip)
        state.clip = clip
    end
end

--
-- The flush
--

local flushing = false
local batched = {}              -- hosts whose batch was opened in this flush
local built = {}                -- records created in this flush
local orphans = {}              -- records that lost their parent in this flush

local function touch(host)
    if not batched[host] then
        batched[host] = true
        if host.beginBatch then
            host.beginBatch()
        end
    end
end

-- A root node gets S(scale) * its local transform, written in the local
-- transform's form with the same origin.
local function scaleRoot(p, scale)
    p.x = scale * p.x + (scale - 1) * p.originX
    p.y = scale * p.y + (scale - 1) * p.originY
    p.scale = scale * p.scale
end

local function pushNode(rec)
    local p = resetScratch()
    local item = rec.item
    item:describeNode(p)
    local scale = rootHosts[item] and appliedScale or false
    if scale and scale ~= 1 then
        scaleRoot(p, scale)
    end
    rec.scaled = scale
    pushProperties(rec.host, rec.node, rec.state, p)
end

local function pushNodeContent(rec)
    rec.item:pushContent(rec.host, rec.node)
end

local function unlink(rec)
    local parent = rec.parent
    if parent then
        local kids = parent.kids
        for i = #kids, 1, -1 do
            if kids[i] == rec then
                remove(kids, i)
                break
            end
        end
        rec.parent = false
    end
end

local function forget(rec)
    records[rec.item] = nil
    rec.parent = false
    local kids = rec.kids
    for i = 1, #kids do
        forget(kids[i])
    end
end

local function destroy(rec)
    unlink(rec)
    rec.destroyed = true
    touch(rec.host)
    rec.host.destroyNode(rec.node)
    forget(rec)
end

local reconcile

-- A node for the item with its properties, content and subtree, detached.
local function build(item, host)
    touch(host)
    local rec = {
        item = item, host = host, node = host.createNode(), parent = false, kids = {},
        state = newState(),
    }
    records[item] = rec
    built[rec] = true
    pushNode(rec)
    pushNodeContent(rec)
    reconcile(rec)
    return rec
end

-- Makes the node children of rec follow the item's draw children. Nodes
-- that stay in order are not touched; the others are created or moved in
-- front of their successor. Records that are no longer children become
-- orphans, destroyed at the end of the flush unless attached elsewhere.
function reconcile(rec)
    local host, node = rec.host, rec.node
    local desired, count
    if rec.top then
        desired, count = {}, 0
        for i = 1, #roots do
            local root = roots[i]
            if rootHosts[root] == host then
                count = count + 1
                desired[count] = root
            end
        end
    else
        desired = rec.item.children
        count = #desired
    end

    local kids = rec.kids
    local index = {}
    for i = 1, #kids do
        index[kids[i]] = i
    end

    -- Keep the records that already are children here in increasing order
    local keep = {}
    local last = 0
    for i = 1, count do
        local crec = records[desired[i]]
        local at = crec and index[crec]
        if at and at > last then
            keep[crec] = true
            last = at
        end
    end

    local newKids, placed = {}, {}
    local nextNode = nil
    for i = count, 1, -1 do
        local child = desired[i]
        local crec = records[child]
        if crec and crec.host ~= host then
            destroy(crec)
            crec = nil
        end
        if not crec then
            crec = build(child, host)
        end
        if not keep[crec] then
            if crec.parent ~= rec then
                unlink(crec)
            end
            touch(host)
            host.attach(crec.node, node, nextNode)
        end
        -- An item that became or stopped being a root gains or loses the scale
        if crec.scaled ~= (rec.top and appliedScale or false) then
            pushNode(crec)
        end
        crec.parent, crec.nodeParent = rec, rec
        orphans[crec] = nil
        newKids[i] = crec
        placed[crec] = true
        nextNode = crec.node
    end

    for i = 1, #kids do
        local old = kids[i]
        if old.parent == rec and not placed[old] then
            old.parent = false
            orphans[old] = true
        end
    end
    rec.kids = newKids
end

local function attachedRecord(item)
    local rec = records[item]
    if rec and not rec.deleted and rawget(item, "_root") then
        return rec
    end
    return nil
end

function Sync.flush()
    if flushing then
        return
    end
    local scale = Sync.uiScale()
    if scale ~= appliedScale then
        appliedScale = scale
        for i = 1, #roots do
            dirtyProps[roots[i]] = true
            anyDirty = true
        end
    end
    if not anyDirty then
        return
    end
    flushing = true
    anyDirty = false

    -- Structure: roots first, then the items whose children changed
    if rootsDirty then
        rootsDirty = false
        local hosts = {}
        for host in pairs(tops) do
            hosts[host] = true
        end
        for i = 1, #roots do
            hosts[rootHosts[roots[i]]] = true
        end
        for host in pairs(hosts) do
            reconcile(topOf(host))
        end
    end
    local changedChildren = dirtyChildren
    dirtyChildren = {}
    for item in pairs(changedChildren) do
        local rec = attachedRecord(item)
        if rec and not built[rec] then
            reconcile(rec)
        end
    end

    -- Properties and content of nodes that existed before this flush
    local changedProps, changedContent = dirtyProps, dirtyContent
    dirtyProps, dirtyContent = {}, {}
    for item in pairs(changedProps) do
        local rec = attachedRecord(item)
        if rec and not built[rec] then
            pushNode(rec)
        end
    end
    for item in pairs(changedContent) do
        local rec = attachedRecord(item)
        if rec and not built[rec] then
            pushNodeContent(rec)
        end
    end

    -- Nodes of items that left. A node inside another node that goes is
    -- released with it.
    local doomed = {}
    for rec in pairs(orphans) do
        if not rec.parent and records[rec.item] == rec then
            doomed[rec] = true
        end
    end
    for rec in pairs(doomed) do
        local covered = false
        local above = rec.nodeParent
        while above do
            if doomed[above] or above.destroyed then
                covered = true
                break
            end
            above = above.nodeParent
        end
        if covered then
            forget(rec)
        else
            destroy(rec)
        end
    end

    orphans = {}
    built = {}
    for host in pairs(batched) do
        if host.endBatch then
            host.endBatch()
        end
    end
    batched = {}
    flushing = false
end

return Sync
