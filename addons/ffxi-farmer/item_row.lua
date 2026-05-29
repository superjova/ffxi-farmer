--[[
    item_row.lua - the ONE reusable ImGui row widget, used by both the untracked and
    tracked panels. Stateless from the caller's perspective: it returns a price when
    the user clicks Save, and the caller persists it. The only difference between the
    two panels is which list feeds the rows and whether currentPrice is nil.
]]--

local imgui = require('imgui')
local icons = require('icons')
local util  = require('util')

local item_row = {}

-- Persistent ImGui input buffers, one per item id. {[itemId] = { intValue }}
local buffers = {}

local function buffer(itemId, initial)
    local b = buffers[itemId]
    if b == nil then
        b = { math.floor(tonumber(initial) or 0) }
        buffers[itemId] = b
    end
    return b
end

-- render(itemId, name, qty, currentPrice|nil) -> newPrice if Saved this frame, else nil
function item_row.render(itemId, name, qty, currentPrice)
    local saved = nil
    imgui.PushID(itemId)

    -- Icon thumbnail (or an empty slot of the same size so rows line up).
    local handle = icons.handle(itemId)
    if handle ~= nil then
        imgui.Image(handle, { 32, 32 })
    else
        imgui.Dummy({ 32, 32 })
    end
    imgui.SameLine()

    imgui.BeginGroup()
        imgui.Text(string.format('%s  x%d', name or ('Item ' .. tostring(itemId)), qty or 1))

        local b = buffer(itemId, currentPrice)
        imgui.PushItemWidth(90)
        imgui.InputInt('##price', b)
        imgui.PopItemWidth()
        imgui.SameLine()
        if imgui.Button('Save') then
            if b[1] and b[1] >= 0 then
                saved = b[1]
            end
        end
        if currentPrice ~= nil then
            imgui.SameLine()
            imgui.TextColored({ 0.6, 0.9, 0.6, 1.0 },
                string.format('= %s gil', util.commas((qty or 1) * currentPrice)))
        end
    imgui.EndGroup()

    imgui.PopID()
    return saved
end

-- Drop cached input buffers (call on session reset so stale prices don't linger).
function item_row.clear()
    buffers = {}
end

return item_row
