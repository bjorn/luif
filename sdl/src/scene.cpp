//
// The node pool: structure and content ownership. Nodes and text contents
// are reused through free lists threaded through Node::next and
// TextContent::nextFree. Code here works with indices, since creating a node
// or a text content can move the pools.
//
#include "internal.h"

#include <cmath>

namespace luif {

namespace {

constexpr int GenerationShift = 24;
constexpr Id IndexMask = (Id(1) << GenerationShift) - 1;

bool isLive(const Scene &scene, Id node)
{
    return node > Scene::Root && node < scene.nodes.size() && scene.nodes[node].alive;
}

// Takes the node out of its parent's child list; its subtree stays with it.
void unlink(std::vector<Node> &nodes, Id id)
{
    Node &node = nodes[id];
    if (node.parent == None)
        return;
    Node &parent = nodes[node.parent];
    if (node.prev != None)
        nodes[node.prev].next = node.next;
    else
        parent.firstChild = node.next;
    if (node.next != None)
        nodes[node.next].prev = node.prev;
    else
        parent.lastChild = node.prev;
    node.parent = node.prev = node.next = None;
}

} // namespace

// Near zero sine and cosine are snapped so right angle rotations stay exact,
// as the LOVE host does (luif/love/transform.lua).
Affine Node::local() const
{
    float cosine = 1, sine = 0;
    if (rotation != 0) {
        cosine = std::cos(rotation);
        sine = std::sin(rotation);
        if (std::fabs(cosine) < 1e-7f) cosine = 0;
        if (std::fabs(sine) < 1e-7f) sine = 0;
    }
    Affine m;
    m.a = scale * cosine;
    m.b = scale * sine;
    m.c = -m.b;
    m.d = m.a;
    m.tx = x + originX - (m.a * originX + m.c * originY);
    m.ty = y + originY - (m.b * originX + m.d * originY);
    return m;
}

Scene::Scene()
{
    nodes.resize(2);
    nodes[Root].alive = true;
    texts.resize(1);
}

Id Scene::create()
{
    Id id = freeNode;
    if (id != None) {
        freeNode = nodes[id].next;
        nodes[id].next = None;
    } else {
        if (nodes.size() > IndexMask)
            return None;        // the handle encoding has no room for more
        id = Id(nodes.size());
        nodes.emplace_back();
    }
    nodes[id].alive = true;
    return id;
}

void Scene::destroy(Id node)
{
    unlink(nodes, node);

    // Depth first without a stack: child lists are consumed from the front
    // and the parent links lead back up.
    Id current = node;
    for (;;) {
        const Id child = nodes[current].firstChild;
        if (child != None) {
            nodes[current].firstChild = nodes[child].next;
            current = child;
            continue;
        }
        const Id parent = nodes[current].parent;
        clearContent(current);
        const uint16_t generation = nodes[current].generation + 1;
        nodes[current] = Node();
        nodes[current].generation = generation;
        nodes[current].next = freeNode;
        freeNode = current;
        if (current == node)
            break;
        current = parent;
    }
}

const char *Scene::attach(Id node, Id parent, Id before)
{
    if (parent == None)
        parent = Root;
    for (Id p = parent; p != None; p = nodes[p].parent)
        if (p == node)
            return "attach: cannot attach a node under itself or its subtree";
    if (before != None && (before == node || nodes[before].parent != parent))
        return "attach: nextSibling is not another child of parent";

    unlink(nodes, node);
    Node &n = nodes[node];
    Node &p = nodes[parent];
    n.parent = parent;
    n.next = before;
    n.prev = before != None ? nodes[before].prev : p.lastChild;
    if (n.prev != None)
        nodes[n.prev].next = node;
    else
        p.firstChild = node;
    if (before != None)
        nodes[before].prev = node;
    else
        p.lastChild = node;
    return nullptr;
}

void Scene::detach(Id node)
{
    unlink(nodes, node);
}

void Scene::clearContent(Id node)
{
    Node &n = nodes[node];
    if (n.kind == ContentKind::Text) {
        // A fresh value releases the string and the vectors
        texts[n.text] = TextContent();
        texts[n.text].nextFree = freeText;
        freeText = n.text;
    }
    n.kind = ContentKind::None;
    n.flags &= ~(FlipX | FlipY | Grayscale | HasFill | HasBorder);
    n.slices = SlicesContent{};
}

TextContent &Scene::makeText(Id node)
{
    if (nodes[node].kind == ContentKind::Text) {
        // A label that changes lays out again without allocating
        TextContent &text = texts[nodes[node].text];
        text.text.clear();
        text.runs.clear();
        text.layoutWidth = -1;
        return text;
    }
    clearContent(node);
    Id id = freeText;
    if (id != None) {
        freeText = texts[id].nextFree;
        texts[id].nextFree = None;
    } else {
        id = Id(texts.size());
        texts.emplace_back();
    }
    nodes[node].kind = ContentKind::Text;
    nodes[node].text = id;
    return texts[id];
}

bool Scene::inScene(Id node) const
{
    for (Id p = nodes[node].parent; p != None; p = nodes[p].parent)
        if (p == Root)
            return true;
    return false;
}

double Scene::handle(Id node) const
{
    return double(int64_t(node) | int64_t(nodes[node].generation) << GenerationShift);
}

Id Scene::resolve(double handle) const
{
    // The range keeps the conversion defined (and NaN out)
    if (!(handle >= 0 && handle < double(int64_t(0x10000) << GenerationShift)))
        return None;
    const int64_t bits = int64_t(handle);
    const Id id = Id(bits) & IndexMask;
    if (double(bits) != handle || !isLive(*this, id)
        || nodes[id].generation != uint16_t(bits >> GenerationShift))
        return None;
    return id;
}

} // namespace luif
