//
// The draw traversal and the quad batch. World transforms, effective opacity
// and the clip rectangle live on the call stack of the traversal; nothing is
// stored on the nodes and nothing is allocated per frame once the batch has
// grown to its working size.
//
#include "internal.h"

#include <algorithm>
#include <cmath>

namespace luif {

SDL_FColor toFColor(Color color, float opacity)
{
    return { float((color >> 16) & 0xFF) / 255.0f, float((color >> 8) & 0xFF) / 255.0f,
             float(color & 0xFF) / 255.0f, float(color >> 24) / 255.0f * opacity };
}

Affine Affine::operator*(const Affine &local) const
{
    Affine m;
    m.a = a * local.a + c * local.b;
    m.b = b * local.a + d * local.b;
    m.c = a * local.c + c * local.d;
    m.d = b * local.c + d * local.d;
    m.tx = a * local.tx + c * local.ty + tx;
    m.ty = b * local.tx + d * local.ty + ty;
    return m;
}

SDL_FPoint Affine::apply(float x, float y) const
{
    return { a * x + c * y + tx, b * x + d * y + ty };
}

//
// Batch
//

void Batch::quad(SDL_Texture *quadTexture, const Affine &transform, float x, float y, float w, float h,
                 float u0, float v0, float u1, float v1, SDL_FColor color)
{
    if (quadTexture != texture) {
        flush();
        texture = quadTexture;
    }
    vertices.push_back({ transform.apply(x, y), color, { u0, v0 } });
    vertices.push_back({ transform.apply(x + w, y), color, { u1, v0 } });
    vertices.push_back({ transform.apply(x + w, y + h), color, { u1, v1 } });
    vertices.push_back({ transform.apply(x, y + h), color, { u0, v1 } });
    // Every quad has the same indices, so they are kept and only ever extended
    for (int first = int(indices.size() / 6 * 4); first < int(vertices.size()); first += 4)
        for (int offset : { 0, 1, 2, 0, 2, 3 })
            indices.push_back(first + offset);
}

void Batch::flush()
{
    if (vertices.empty())
        return;
    // Untextured geometry blends with the draw blend mode, which belongs to
    // the application between frames; textures carry their own.
    if (!texture)
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
    SDL_RenderGeometry(renderer, texture, vertices.data(), int(vertices.size()),
                       indices.data(), int(vertices.size() / 4 * 6));
    vertices.clear();
}

namespace {

//
// Content
//

// The texture to draw an entry with; the grayscale copy has the same size
SDL_Texture *textureFor(Textures &textures, Id id, bool grayscale)
{
    return grayscale ? textures.gray(id) : textures.items[id].sdl;
}

void drawImage(SdlHost::Impl &host, const Node &node, const Affine &world, float opacity)
{
    const ImageContent &image = node.image;
    const SDL_FColor color = toFColor(image.tint, opacity);
    const Texture &entry = host.textures.items[image.texture];
    if (node.width <= 0 || node.height <= 0 || entry.width <= 0 || entry.height <= 0 || color.a <= 0)
        return;
    SDL_Texture *texture = textureFor(host.textures, image.texture, node.flags & Grayscale);
    if (!texture)
        return;     // an application texture that was taken away
    const float tw = float(texture->w), th = float(texture->h);
    float u0 = entry.x / tw, u1 = (entry.x + entry.width) / tw;
    float v0 = entry.y / th, v1 = (entry.y + entry.height) / th;
    if (node.flags & FlipX) std::swap(u0, u1);
    if (node.flags & FlipY) std::swap(v0, v1);
    host.batch.quad(texture, world, 0, 0, node.width, node.height, u0, v0, u1, v1, color);
}

// One axis of a nine-slice, as sliceAxis in luif/host/interface.lua: source
// and destination starts and sizes of the three parts.
struct SliceAxis { float s[3], sw[3], d[3], dw[3]; };

SliceAxis sliceAxis(float size, float total, float a, float b)
{
    size = std::max(size, 0.0f);
    SliceAxis axis = { { 0, a, total - b }, { a, total - a - b, b }, {}, {} };
    if (size >= a + b) {
        axis.d[1] = a;
        axis.d[2] = size - b;
        axis.dw[0] = a;
        axis.dw[1] = size - a - b;
        axis.dw[2] = b;
    } else {
        // The ends shrink proportionally and the middle is empty
        const float k = size / (a + b);
        axis.d[1] = axis.d[2] = axis.dw[0] = a * k;
        axis.dw[2] = b * k;
    }
    return axis;
}

void drawSlices(SdlHost::Impl &host, const Node &node, const Affine &world, float opacity)
{
    const SlicesContent &slices = node.slices;
    const SDL_FColor color = toFColor(slices.tint, opacity);
    if (node.width <= 0 || node.height <= 0 || color.a <= 0)
        return;
    const Texture &entry = host.textures.items[slices.texture];
    SDL_Texture *texture = textureFor(host.textures, slices.texture, node.flags & Grayscale);
    if (!texture)
        return;     // an application texture that was taken away
    const float tw = float(texture->w), th = float(texture->h);
    const SliceAxis h = sliceAxis(node.width, entry.width, slices.left, slices.right);
    const SliceAxis v = sliceAxis(node.height, entry.height, slices.top, slices.bottom);
    for (int row = 0; row < 3; ++row) {
        if (v.sw[row] <= 0 || v.dw[row] <= 0)
            continue;
        const float v0 = (entry.y + v.s[row]) / th, v1 = (entry.y + v.s[row] + v.sw[row]) / th;
        for (int col = 0; col < 3; ++col) {
            if (h.sw[col] <= 0 || h.dw[col] <= 0)
                continue;
            const float u0 = (entry.x + h.s[col]) / tw, u1 = (entry.x + h.s[col] + h.sw[col]) / tw;
            host.batch.quad(texture, world, h.d[col], v.d[row], h.dw[col], v.dw[row],
                            u0, v0, u1, v1, color);
        }
    }
}

void drawFill(SdlHost::Impl &host, const Node &node, const Affine &world, float opacity)
{
    const FillContent &fill = node.fill;
    const float w = node.width, h = node.height;
    if (w <= 0 || h <= 0)
        return;
    Batch &batch = host.batch;
    if (node.flags & HasFill) {
        const SDL_FColor color = toFColor(fill.color, opacity);
        if (color.a > 0)
            batch.quad(nullptr, world, 0, 0, w, h, 0, 0, 0, 0, color);
    }
    if ((node.flags & HasBorder) && fill.borderWidth > 0) {
        const SDL_FColor color = toFColor(fill.borderColor, opacity);
        if (color.a <= 0)
            return;
        // Top and bottom over the full width, left and right between them
        const float bx = std::min(fill.borderWidth, w / 2), by = std::min(fill.borderWidth, h / 2);
        batch.quad(nullptr, world, 0, 0, w, by, 0, 0, 0, 0, color);
        batch.quad(nullptr, world, 0, h - by, w, by, 0, 0, 0, 0, color);
        batch.quad(nullptr, world, 0, by, bx, h - 2 * by, 0, 0, 0, 0, color);
        batch.quad(nullptr, world, w - bx, by, bx, h - 2 * by, 0, 0, 0, 0, color);
    }
}

//
// Traversal
//

// The axis aligned bounds of the box under world, grown to whole pixels as
// the scissor of the LOVE host is. The range keeps the conversion to int
// defined for wild transforms.
SDL_Rect clipBounds(const Affine &world, float width, float height)
{
    const SDL_FPoint p[4] = { world.apply(0, 0), world.apply(width, 0),
                              world.apply(width, height), world.apply(0, height) };
    float x0 = p[0].x, y0 = p[0].y, x1 = x0, y1 = y0;
    for (int i = 1; i < 4; ++i) {
        x0 = std::min(x0, p[i].x);
        y0 = std::min(y0, p[i].y);
        x1 = std::max(x1, p[i].x);
        y1 = std::max(y1, p[i].y);
    }
    constexpr float Range = 1 << 24;
    if (!(x0 <= x1 && y0 <= y1))        // NaN
        return { 0, 0, 0, 0 };
    const int left = int(std::floor(std::clamp(x0, -Range, Range)));
    const int top = int(std::floor(std::clamp(y0, -Range, Range)));
    return { left, top, int(std::ceil(std::clamp(x1, -Range, Range))) - left,
             int(std::ceil(std::clamp(y1, -Range, Range))) - top };
}

// clip is the enclosing clip rectangle, null for none. The pools do not
// change while drawing, so references into them stay valid.
void drawNode(SdlHost::Impl &host, Id id, const Affine &parentWorld, float opacity, const SDL_Rect *clip)
{
    const Node &node = host.scene.nodes[id];
    if (!(node.flags & Visible))
        return;
    opacity *= node.opacity;
    if (!(opacity > 0))
        return;
    const Affine world = parentWorld * node.local();

    SDL_Rect ownClip;
    const bool clips = node.flags & Clip;
    if (clips) {
        ownClip = clipBounds(world, node.width, node.height);
        if (clip ? !SDL_GetRectIntersection(clip, &ownClip, &ownClip) : SDL_RectEmpty(&ownClip))
            return;
        host.batch.flush();
        SDL_SetRenderClipRect(host.renderer, &ownClip);
    }

    switch (node.kind) {
    case ContentKind::None: break;
    case ContentKind::Image: drawImage(host, node, world, opacity); break;
    case ContentKind::Slices: drawSlices(host, node, world, opacity); break;
    case ContentKind::Fill: drawFill(host, node, world, opacity); break;
    case ContentKind::Text:
        host.fonts.draw(host.batch, world, host.scene.texts[node.text], node.width, opacity);
        break;
    }

    for (Id child = node.firstChild; child != None; child = host.scene.nodes[child].next)
        drawNode(host, child, world, opacity, clips ? &ownClip : clip);

    if (clips) {
        host.batch.flush();
        SDL_SetRenderClipRect(host.renderer, clip);
    }
}

} // namespace

void renderScene(SdlHost::Impl &host)
{
    const std::vector<Node> &nodes = host.scene.nodes;
    SDL_SetRenderClipRect(host.renderer, nullptr);
    for (Id child = nodes[Scene::Root].firstChild; child != None; child = nodes[child].next)
        drawNode(host, child, Affine(), 1, nullptr);
    host.batch.flush();
    SDL_SetRenderClipRect(host.renderer, nullptr);
}

} // namespace luif
