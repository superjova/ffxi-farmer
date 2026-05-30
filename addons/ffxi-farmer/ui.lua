--[[
    ui.lua - the ImGui HUD: the always-on stats bar plus two collapsible panels
    (untracked items awaiting a price, and tracked items with editable prices).

    Pure-ish: render(ctx) reads from ctx.session / ctx.prices every frame. All the
    persistence lives in prices/settings; here we only call into them.
]]--

local imgui = require('imgui')
local item_row = require('item_row')
local util = require('util')

local ui = { onReset = nil }

-- Remembered across frames so the untracked panel only auto-collapses on the
-- frame its list becomes empty (not every time a single item is priced).
local prevUntrackedCount = 0

local function fmtRate(session)
    local secs = session:elapsedSeconds()
    if secs <= 0 then return '0' end
    return util.commas(math.floor(session:gilPerHour()))
end

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

local function renderBar(ctx)
    local session = ctx.session
    imgui.Text(string.format('Gil/hr: %s', fmtRate(session)))
    imgui.SameLine()
    imgui.Text(string.format('  |  Total: %s', util.commas(session:total())))
    imgui.SameLine()
    imgui.Text(string.format('  |  %s', util.hms(session:elapsedSeconds())))

    local stateLabel = ({
        [0] = 'stopped', [1] = 'running', [2] = 'paused',
    })[session.state] or '?'
    imgui.Text(string.format('Gil dropped: %s   Item value: %s   [%s]',
        util.commas(session.gilDropped),
        util.commas(session:itemValue()),
        stateLabel))
end

local function renderControls(ctx)
    local session = ctx.session
    if imgui.Button('Start') then
        if session.state == 2 then session:resume() else session:start() end
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
    -- the panel open with the remaining items still listed. The '###id' suffix
    -- gives the header a stable ImGui id even though the visible count changes;
    -- without it the header would reset to collapsed every time the count moved
    -- (which is why the whole panel used to snap shut after each Save).
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

    imgui.SetNextWindowSize({ 320, 0 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('ffxi-farmer', ctx.visible, ImGuiWindowFlags_NoFocusOnAppearing) then
        renderBar(ctx)
        imgui.Separator()
        renderControls(ctx)
        imgui.Separator()
        renderUntracked(ctx)
        renderTracked(ctx)
    end
    imgui.End()
end

return ui
