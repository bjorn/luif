//
// Texture handles. A source entry owns its SDL texture (and the grayscale
// copy made on first use); regions share both. Pixel data is not kept on the
// CPU side.
//
#include "internal.h"

namespace luif {

namespace {

// Takes ownership of the surface. None when the texture could not be made.
Id addSurface(Textures &textures, SDL_Surface *surface)
{
    SDL_Texture *sdl = SDL_CreateTextureFromSurface(textures.renderer, surface);
    SDL_DestroySurface(surface);
    if (!sdl)
        return None;
    SDL_SetTextureBlendMode(sdl, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(sdl, textures.filter);

    Texture entry;
    entry.sdl = sdl;
    entry.width = float(sdl->w);
    entry.height = float(sdl->h);
    textures.items.push_back(entry);
    return Id(textures.items.size() - 1);
}

// A copy of the texture with r, g and b replaced by their luma
SDL_Texture *makeGray(SDL_Renderer *renderer, SDL_Texture *texture, SDL_ScaleMode filter)
{
    SDL_Texture *target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                            SDL_TEXTUREACCESS_TARGET, texture->w, texture->h);
    if (!target)
        return nullptr;

    // Viewport, clip and scale are per render target, so switching the target
    // and back leaves those of the previous one alone. The texture is copied
    // without blending or filtering to get its exact pixels.
    SDL_Texture *previous = SDL_GetRenderTarget(renderer);
    SDL_Surface *pixels = nullptr;
    if (SDL_SetRenderTarget(renderer, target)) {
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE);
        SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST);
        if (SDL_RenderTexture(renderer, texture, nullptr, nullptr))
            pixels = SDL_RenderReadPixels(renderer, nullptr);
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
        SDL_SetTextureScaleMode(texture, filter);
        SDL_SetRenderTarget(renderer, previous);
    }
    SDL_DestroyTexture(target);
    if (!pixels)
        return nullptr;

    SDL_Surface *argb = SDL_ConvertSurface(pixels, SDL_PIXELFORMAT_ARGB8888);
    SDL_DestroySurface(pixels);
    if (!argb)
        return nullptr;
    for (int y = 0; y < argb->h; ++y) {
        void *bytes = static_cast<uint8_t *>(argb->pixels) + size_t(y) * argb->pitch;
        uint32_t *row = static_cast<uint32_t *>(bytes);
        for (int x = 0; x < argb->w; ++x) {
            const uint32_t p = row[x];
            // 0.299, 0.587, 0.114 in 16 bit fixed point
            const uint32_t luma = (19595 * ((p >> 16) & 0xFF) + 38470 * ((p >> 8) & 0xFF)
                                   + 7471 * (p & 0xFF) + 32768) >> 16;
            row[x] = (p & 0xFF000000) | luma << 16 | luma << 8 | luma;
        }
    }
    SDL_Texture *gray = SDL_CreateTextureFromSurface(renderer, argb);
    SDL_DestroySurface(argb);
    if (gray) {
        SDL_SetTextureBlendMode(gray, SDL_BLENDMODE_BLEND);
        SDL_SetTextureScaleMode(gray, filter);
    }
    return gray;
}

} // namespace

Textures::~Textures()
{
    clear();
}

void Textures::clear()
{
    for (Texture &entry : items) {
        if (entry.source != None)
            continue;           // regions borrow
        if (entry.gray && entry.gray != entry.sdl)
            SDL_DestroyTexture(entry.gray);
        if (entry.sdl && !entry.external)
            SDL_DestroyTexture(entry.sdl);
    }
    items.assign(1, Texture());
    byPath.clear();
    filter = SDL_SCALEMODE_LINEAR;
}

Id Textures::load(const std::string &path)
{
    const auto found = byPath.find(path);
    if (found != byPath.end())
        return found->second;

    SDL_IOStream *io = files->open(path);
    SDL_Surface *surface = io ? SDL_LoadSurface_IO(io, true) : nullptr;
    const Id id = surface ? addSurface(*this, surface) : None;
    if (id != None)
        byPath.emplace(path, id);
    return id;
}

Id Textures::create(int width, int height, const uint32_t *argb)
{
    // The surface only wraps the pixels for the upload
    SDL_Surface *surface = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_ARGB8888,
                                                 const_cast<uint32_t *>(argb), width * 4);
    return surface ? addSurface(*this, surface) : None;
}

Id Textures::region(Id texture, float x, float y, float width, float height)
{
    const Texture &from = items[texture];
    Texture entry;
    entry.sdl = from.sdl;
    entry.source = from.source != None ? from.source : texture;
    entry.x = from.x + x;
    entry.y = from.y + y;
    entry.width = width;
    entry.height = height;
    items.push_back(entry);
    return Id(items.size() - 1);
}

Id Textures::addExternal(SDL_Texture *texture)
{
    Texture entry;
    entry.external = true;
    items.push_back(entry);
    replaceExternal(Id(items.size() - 1), texture);
    return Id(items.size() - 1);
}

void Textures::replaceExternal(Id texture, SDL_Texture *replacement)
{
    Texture &entry = items[texture];
    if (entry.gray && entry.gray != entry.sdl)
        SDL_DestroyTexture(entry.gray);
    entry.gray = nullptr;
    entry.sdl = replacement;
    entry.width = replacement ? float(replacement->w) : 0;
    entry.height = replacement ? float(replacement->h) : 0;
    for (Texture &region : items)
        if (region.source == texture)
            region.sdl = replacement;
}

SDL_Texture *Textures::gray(Id texture)
{
    Texture &entry = items[texture];
    Texture &source = entry.source != None ? items[entry.source] : entry;
    if (!source.gray) {
        SDL_ScaleMode mode = filter;
        SDL_GetTextureScaleMode(source.sdl, &mode);
        source.gray = makeGray(renderer, source.sdl, mode);
        if (!source.gray)
            source.gray = source.sdl;   // failed; do not try again every frame
    }
    return source.gray;
}

void Textures::setFilter(SDL_ScaleMode mode, Id texture)
{
    // A region shares the image of its source, and so its filter
    const Id only = valid(texture) && items[texture].source != None ? items[texture].source : texture;
    if (only == None)
        filter = mode;
    for (Id id = 1; id < items.size(); ++id) {
        Texture &entry = items[id];
        if (entry.source != None || !entry.sdl || (only != None && id != only))
            continue;
        SDL_SetTextureScaleMode(entry.sdl, mode);
        if (entry.gray)
            SDL_SetTextureScaleMode(entry.gray, mode);
    }
}

} // namespace luif
