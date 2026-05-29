--[[
    ui.lua - the ImGui HUD. A single draggable window (its position auto-persists to
    config/imgui.ini because we never force a position). Shows gil/hr, totals, the
    elapsed timer, control buttons, and the two collapsible pricing panels which
    both render through the shared item_row widget.
]]--

local imgui    = require('imgui')
local item_row = require('item_row')
local util     = require('util')

local ui = {}

local function controls(session)
    if session.state ~= session.RUNNING then
        if imgui.Button('Start') then
            if session.state == session.PAUSED then session:resume() else session:start() end
        end
    else
        if imgui.Button('Pause') then session:pause() end
    end
    imgui.SameLine()
    if imgui.Button('Reset') then
        session:reset()
        item_row.clear()
        if ui.onReset then ui.onReset() end
    end
    imgui.SameLine()
    if imgui.Button('End') then
        session:stop()
    end
end

-- ctx = { session, prices, visible = { bool } }
function ui.render(ctx)
    if not ctx.visible[1] then return end
    local session = ctx.session
    local prices  = ctx.prices

    imgui.SetNextWindowSize({ 320, 0 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('ffxi-farmer', ctx.visible, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.TextColored({ 1.0, 0.85, 0.2, 1.0 },
            string.format('%s gil/hr', util.commas(math.floor(session:gilPerHour()))))
        imgui.Separator()

        imgui.Text(string.format('Total : %s gil', util.commas(session:total())))
        imgui.Text(string.format('  Gil : %s', util.commas(session.gilDropped)))
        imgui.Text(string.format('Items : %s gil', util.commas(session:itemValue())))
        imgui.Text(string.format('Time  : %s  [%s]', util.hms(session:elapsedSeconds()), session.state))
        imgui.Separator()

        controls(session)
        imgui.Separator()

        local untracked = session:untracked()
        if imgui.CollapsingHeader(string.format('%d untracked items', #untracked)) then
            if #untracked == 0 then
                imgui.TextDisabled('  (none - price prompts appear here)')
            end
            for _, e in ipairs(untracked) do
                local newPrice = item_row.render(e.itemId, e.name, e.qty, nil)
                if newPrice ~= nil then
                    prices:set(e.itemId, newPrice)
                end
            end
        end

        local tracked = session:tracked()
        if imgui.CollapsingHeader(string.format('Tracked items (%d)', #tracked)) then
            if #tracked == 0 then
                imgui.TextDisabled('  (none yet)')
            end
            for _, e in ipairs(tracked) do
                local newPrice = item_row.render(e.itemId, e.name, e.qty, e.price)
                if newPrice ~= nil then
                    prices:set(e.itemId, newPrice)
                end
            end
        end
    end
    imgui.End()
end

return ui
