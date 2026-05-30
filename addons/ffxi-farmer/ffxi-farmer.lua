--[[
    ffxi-farmer - a gil-per-hour farming HUD for Ashita v4.

    Tracks the items and gil you obtain (via the treasure-pool packet), prices them
    from a persistent price book, and projects gil/hour for the session on a
    draggable on-screen bar.

    Commands (also /ffxi-farmer):
      /farmer                 toggle the HUD
      /farmer start           start (or resume) the session timer/tracking
      /farmer pause           pause the timer
      /farmer end | stop      end the session (stops the timer)
      /farmer reset           reset totals, items and timer
      /farmer price <amount>  set the price of the first untracked item
      /farmer setprice <id|name> <amount>   set/override any item's price
      /farmer add <amount>    manually add raw gil
      /farmer debug           toggle raw 0x0D2 packet logging
      /farmer help            list commands
]]--

addon.name    = 'ffxi-farmer'
addon.author  = 'superjova'
addon.version = '1.0'
addon.desc    = 'Gil-per-hour farming HUD: tracks drops & gil, projects gil/hour.'

local chat     = require('chat')
local settings = require('settings')
local Session  = require('session')
local Prices   = require('prices')
local tracker  = require('tracker')
local item_row = require('item_row')
local ui       = require('ui')

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local config = settings.load(T{ visible = true })
local priceData = settings.load(T{ items = T{} }, 'prices')

local prices = Prices.new(priceData, function() settings.save('prices') end)
local session = Session.new(prices:priceFn())

local ctx = {
    session = session,
    prices  = prices,
    visible = { config.visible ~= false },
}

local function msg(text)
    print(chat.header(addon.name) .. chat.message(text))
end

local function resolveName(itemId)
    if AshitaCore == nil then return nil end
    local mgr = AshitaCore:GetResourceManager()
    if mgr == nil then return nil end
    local item = mgr:GetItemById(itemId)
    if item == nil then return nil end
    return item.Name[0]
end

tracker.setup({ session = session, resolveName = resolveName, logfn = print })

-- Let the UI's Reset button also clear the packet-dedupe state.
ui.onReset = function() tracker.reset() end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
local function printHelp()
    msg('commands:')
    msg('  /farmer                - toggle HUD')
    msg('  /farmer start|pause|end|reset')
    msg('  /farmer price <amount> - price the first untracked item')
    msg('  /farmer setprice <id|name> <amount>')
    msg('  /farmer add <amount>   - manually add gil')
    msg('  /farmer debug          - toggle packet logging')
end

local function handleCommand(args)
    local sub = (args[2] or 'toggle'):lower()

    if sub == 'toggle' then
        ctx.visible[1] = not ctx.visible[1]
    elseif sub == 'start' then
        if session.state == Session.PAUSED then session:resume() else session:start() end
        msg('session started.')
    elseif sub == 'pause' then
        session:pause()
        msg('session paused.')
    elseif sub == 'end' or sub == 'stop' then
        session:stop()
        msg(string.format('session ended. total %s gil over %s.',
            require('util').commas(session:total()), require('util').hms(session:elapsedSeconds())))
    elseif sub == 'reset' then
        session:reset()
        item_row.clear()
        tracker.reset()
        msg('session reset.')
    elseif sub == 'price' then
        local amt = tonumber(args[3])
        local list = session:untracked()
        if not list[1] then
            msg('no untracked items.')
        elseif amt == nil then
            msg('usage: /farmer price <amount>')
        else
            prices:set(list[1].itemId, amt)
            msg(string.format('priced %s at %s gil.', list[1].name, require('util').commas(amt)))
        end
    elseif sub == 'setprice' then
        if #args < 4 then
            msg('usage: /farmer setprice <id|name> <amount>')
        else
            local amt = tonumber(args[#args])
            local asId = tonumber(args[3])
            if amt == nil then
                msg('invalid amount.')
            elseif asId ~= nil and #args == 4 then
                prices:set(asId, amt)
                msg(string.format('priced item %d at %s gil.', asId, require('util').commas(amt)))
            else
                local name = table.concat({ unpack(args, 3, #args - 1) }, ' ')
                local id = session:findByName(name)
                if id then
                    prices:set(id, amt)
                    msg(string.format('priced %s at %s gil.', name, require('util').commas(amt)))
                else
                    msg('no tracked item named "' .. name .. '".')
                end
            end
        end
    elseif sub == 'add' then
        local amt = tonumber(args[3])
        if amt == nil then
            msg('usage: /farmer add <amount>')
        else
            session:addGil(amt)
            msg(string.format('added %s gil.', require('util').commas(amt)))
        end
    elseif sub == 'debug' then
        tracker.debug = not tracker.debug
        msg('packet debug ' .. (tracker.debug and 'ON' or 'OFF') .. '.')
    elseif sub == 'help' then
        printHelp()
    else
        msg('unknown subcommand "' .. sub .. '". try /farmer help')
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ashita.events.register('command', 'ffxifarmer_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/ffxi-farmer' and cmd ~= '/farmer' then return end
    e.blocked = true
    handleCommand(args)
end)

ashita.events.register('packet_in', 'ffxifarmer_packet', function(e)
    tracker.onPacket(e.id, e.data)
end)

ashita.events.register('d3d_present', 'ffxifarmer_present', function()
    ui.render(ctx)
end)

ashita.events.register('unload', 'ffxifarmer_unload', function()
    config.visible = ctx.visible[1]
    settings.save()
    settings.save('prices')
end)
