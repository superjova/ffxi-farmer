--[[
    ui.lua - the ImGui HUD: a single draggable window. The title bar carries the
    live total + gil/hr (so it stays useful when collapsed/minimized); the expanded
    body is a vertical breakdown, the session controls, and the two pricing panels.
]]--

local imgui = require('imgui')
local item_row = require('item_row')
local util = require('util')

local ui = { onReset = nil }

-- Remembered across frames so the untracked panel only auto-collapses on the
-- frame its list becomes empty (not every time a single item is priced).
local prevUntrackedCount = 0

-- Show the real item name. Names are resolved lazily from the resource manager
-- (via ctx.resolveName) in case they weren't available when the drop arrived,
-- and the resolved name is written back into the session so it sticks.
local function displayName(ctx, entry)
    local nm = entry.name
    local unresolved = (nm == nil) or (tostring(nm):match('^Item %d+$') ~= nil)
    if unresolved and ctx.resolveName ~= nil then
        local resolved = ctx.resolveName(entry.itemId)
        if resolved ~= nil and resolved ~= '' then
            local se = ctx.session.items[entry.itemId]
            if se ~= nil then se.name = resolved end
            return resolved
        end
    end
    return nm or ('Item ' .. tostring(entry.itemId))
end

-- Vertical breakdown. Deliberately omits total + gil/hr (those live in the title).
local function renderBreakdown(ctx)
    local session = ctx.session
    imgui.Text(string.format('Time:  %s', util.hms(session:elapsedSeconds())))
    imgui.Text(string.format('Items: %s gil', util.commas(session:itemValue())))
    imgui.Text(string.format('Gil:   %s gil', util.commas(session.gilDropped)))
end

local function renderControls(ctx)
    local session = ctx.session
    if imgui.Button('Start') then
        if session.state == session.PAUSED then session:resume() else session:start() end
    end
    imgui.SameLine()
    if imgui.Button('Pause') then session:pause() end
    imgui.SameLine()
    if imgui.Button('Reset') then
        session:reset()
        item_row.clear()
        if ui.onReset then ui.onReset() end
    end
    imgui.SameLine()
    if imgui.Button('End') then session:stop() end
end

local function renderUntracked(ctx)
    local session = ctx.session
    local list = session:untracked()
    local n = #list

    -- Auto-collapse only on the transition to empty, so pricing one item leaves
    -- the panel open with the remaining items. The '###id' suffix keeps a stable
    -- ImGui id even as the visible count changes (else it would snap shut on save).
    if n == 0 and prevUntrackedCount > 0 and imgui.SetNextItemOpen ~= nil then
        imgui.SetNextItemOpen(false)
    end
    prevUntrackedCount = n

    local header = string.format('%d untracked items###ffxifarmer_untracked', n)
    if imgui.CollapsingHeader(header) then
        for _, entry in ipairs(list) do
            local newPrice = item_row.render(entry.itemId, displayName(ctx, entry), entry.qty, nil)
            if newPrice ~= nil then
                ctx.prices:set(entry.itemId, newPrice)
            end
        end
    end
end

local function renderTracked(ctx)
    local session = ctx.session
    local list = session:tracked()
    if imgui.CollapsingHeader('Tracked items###ffxifarmer_tracked') then
        for _, entry in ipairs(list) do
            local newPrice = item_row.render(entry.itemId, displayName(ctx, entry), entry.qty, entry.price)
            if newPrice ~= nil then
                ctx.prices:set(entry.itemId, newPrice)
            end
        end
    end
end

ui.render = function(ctx)
    if not ctx.visible[1] then return end
    local session = ctx.session

    -- Title: "Farmer | <total> (<rate>/hr)" while a session is live (running or
    -- paused), otherwise just "Farmer". Stable '###' id preserves window identity
    -- and saved position even though the visible title changes.
    local title
    if session.state ~= 'stopped' then
        title = string.format('Farmer | %s (%s/hr)###ffxifarmer',
            util.commas(session:total()),
            util.commas(math.floor(session:gilPerHour())))
    else
        title = 'Farmer###ffxifarmer'
    end

    imgui.SetNextWindowSize({ 320, 0 }, ImGuiCond_FirstUseEver)
    if imgui.Begin(title, ctx.visible, ImGuiWindowFlags_NoFocusOnAppearing) then
        renderBreakdown(ctx)
        imgui.Separator()
        renderControls(ctx)
        imgui.Separator()
        renderUntracked(ctx)
        renderTracked(ctx)
    end
    imgui.End()
end

return ui
