--[[
    tracker.lua - record loot for the session from two server packets:

    1. Items - the treasure-pool packet (0x0D2). For a solo farmer an item entering
       the pool means you obtain it.
         0x04 uint32  item quantity
         0x10 uint16  item id (0 == empty/cleared slot)
         0x14 uint8   treasure pool slot index

    2. Gil - the kill-message packet (0x02D), the same packet that delivers XP. It is
       a structured binary packet (not chat text), so it is robust and source-specific.
         0x10 uint32  param1  (the amount - gil/xp/etc.)
         0x14 uint32  param2
         0x18 uint16  message id (identifies WHICH reward this is)
       Only the message id that means "obtains gil" is counted, so NPC sales / quest
       payouts are never mistaken for farmed gil. That id is server/era-specific, so
       it is configured at runtime with `/farmer gilmsg <id>` (persisted) - capture it
       with `/farmer debug`, which logs every 0x02D's id and params.

    Run `/farmer debug` to dump raw 0x0D2 / 0x02D fields for verification.
]]--

local struct = require('struct')

local tracker = {}

tracker.session = nil
tracker.resolveName = nil
tracker.debug = false
tracker.logfn = print
tracker.gilMessageId = nil   -- set via /farmer gilmsg <id> once captured

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

-- Item drops (0x0D2).
function tracker.onLoot(data)
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

-- Kill / reward messages (0x02D). Gil is param1 when message id == the configured
-- gil id. Returns the gil amount it counted (for tests) or nil.
function tracker.onKillMessage(data)
    local session = tracker.session
    if session == nil or not session:isRunning() then return nil end
    if data == nil or #data < 0x1A then return nil end

    local param1 = struct.unpack('I', data, 0x10 + 1)
    local param2 = struct.unpack('I', data, 0x14 + 1)
    local msgId  = struct.unpack('H', data, 0x18 + 1)

    if tracker.debug then
        tracker.logfn(string.format('[ffxi-farmer] 0x2D msg=%d param1=%d param2=%d',
            msgId or -1, param1 or -1, param2 or -1))
    end

    if tracker.gilMessageId ~= nil and msgId == tracker.gilMessageId
        and param1 ~= nil and param1 > 0 then
        session:addGil(param1)
        return param1
    end
    return nil
end

function tracker.onPacket(id, data)
    if id == 0x0D2 then
        tracker.onLoot(data)
    elseif id == 0x02D then
        tracker.onKillMessage(data)
    end
end

return tracker
