--[[
    tracker.lua - record loot for the session from two sources:

    1. Items: the incoming treasure-pool packet (0x0D2). For a solo farmer an item
       entering the pool means you obtain it, so 0x0D2 is the signal we watch.
       Offsets (confirmed via the Lootwhore plugin + LandSandBoat packet source):
         0x04 uint32  item quantity
         0x10 uint16  item id (0 == empty/cleared slot)
         0x14 uint8   treasure pool slot index

    Gil is handled separately (and server-driven) by session:observeGil, fed from
    the player's live gil total read out of game memory - not from this packet and
    not from chat text.

    Run `/farmer debug` to dump raw 0x0D2 bytes if an item field still looks wrong.
]]--

local struct = require('struct')

local tracker = {}

tracker.session = nil
tracker.resolveName = nil
tracker.debug = false
tracker.logfn = print

local MAX_STACK = 99   -- treasure-pool items are 1..99; anything else is a misread

local function hexdump(data, n)
    local out = {}
    for i = 1, math.min(n, #data) do
        out[i] = string.format('%02X', string.byte(data, i))
    end
    return table.concat(out, ' ')
end

-- Dedupe: 0x0D2 can be re-sent (e.g. on pool re-sync). Suppress an identical
-- (slot,item) that arrives within a short window of the last identical one.
-- A real re-drop into the same slot lands outside this window and still counts.
local DEDUPE_WINDOW = 1.0
local recent = {}   -- key -> timestamp
local clock = os.clock

function tracker.setup(deps)
    tracker.session     = deps.session
    tracker.resolveName = deps.resolveName
    if deps.clock then clock = deps.clock end
    if deps.logfn then tracker.logfn = deps.logfn end
end

function tracker.reset()
    recent = {}
end

function tracker.onPacket(id, data)
    if id ~= 0x0D2 then return end
    local session = tracker.session
    if session == nil or not session:isRunning() then return end
    if data == nil or #data < 0x16 then return end

    local count  = struct.unpack('I', data, 0x04 + 1)   -- item quantity
    local itemId = struct.unpack('H', data, 0x10 + 1)
    local slot   = struct.unpack('B', data, 0x14 + 1)

    if tracker.debug then
        tracker.logfn(string.format('[ffxi-farmer] 0xD2 item=%d count=%d slot=%d | %s',
            itemId or -1, count or -1, slot or -1, hexdump(data, 0x1C)))
    end

    -- Ignore empty-slot / pool-clear packets so they can't add phantom totals.
    if itemId == nil or itemId == 0 then return end

    -- Suppress re-sent pool packets for the same slot/item within a short window.
    local key = string.format('%d:%d', slot or 0, itemId)
    local now = clock()
    if recent[key] and (now - recent[key]) < DEDUPE_WINDOW then
        return
    end
    recent[key] = now

    -- Guard against a misread count (e.g. the old x191 bug): clamp to a sane
    -- stack size, defaulting to 1 for anything out of range.
    local qty = count or 1
    if qty < 1 or qty > MAX_STACK then qty = 1 end

    local name = tracker.resolveName and tracker.resolveName(itemId) or nil
    session:addItem(itemId, name, qty)
end

return tracker
