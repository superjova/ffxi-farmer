--[[
    icons.lua - turn an item id into a cached Direct3D texture for ImGui thumbnails.

    Uses the bundled d3d8 FFI binding to build a texture from the item's 32x32 icon
    bitmap (item.Bitmap / item.ImageSize from the resource manager). Everything is
    defensive: if d3d8/ffi is unavailable or texture creation fails, get() returns
    nil and the UI simply renders an empty slot, so the HUD never breaks.
]]--

local icons = {}

local cache = {}              -- [itemId] = texture | false (false = known failure)
local ok_ffi, ffi = pcall(require, 'ffi')
local ok_d3d, d3d8 = pcall(require, 'd3d8')
local device = nil
if ok_d3d then
    local ok, dev = pcall(function() return d3d8.get_device() end)
    if ok then device = dev end
end

local function build(itemId)
    if not (ok_ffi and ok_d3d and device) then return nil end
    if AshitaCore == nil then return nil end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId)
    if item == nil or item.Bitmap == nil or item.ImageSize == nil or item.ImageSize == 0 then
        return nil
    end

    local ok, tex = pcall(function()
        local ptr = ffi.new('IDirect3DTexture8*[1]')
        local hr = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
            device, item.Bitmap, item.ImageSize,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000,
            nil, nil, ptr)
        if hr ~= ffi.C.S_OK then
            return nil
        end
        return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]))
    end)

    if not ok then return nil end
    return tex
end

-- Returns the raw texture object (cached) or nil.
function icons.get(itemId)
    local cached = cache[itemId]
    if cached ~= nil then
        return cached or nil
    end
    local tex = build(itemId)
    cache[itemId] = tex or false
    return tex
end

-- Returns an integer texture id usable as imgui.Image's first argument, or nil.
function icons.handle(itemId)
    local tex = icons.get(itemId)
    if tex == nil then return nil end
    if not ok_ffi then return nil end
    return tonumber(ffi.cast('uint32_t', tex))
end

function icons.clearCache()
    cache = {}
end

return icons
