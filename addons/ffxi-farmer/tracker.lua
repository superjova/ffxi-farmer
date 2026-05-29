--[[
    tracker.lua - parse the incoming treasure-pool packet (0x0D2) and feed the
    session. For a solo farmer, an item/gil entering the treasure pool means you
    obtain it, so 0x0D2 is the signal we watch.

    Confirmed offsets (Lootwhore plugin + emulator sources):
      0x04 uint32  gold/gil amount (set when the drop is gil; item id is then 0)
      0x10 uint16  item id
      0x12 uint16  count
      0x14 uint8   treasure pool slot index
    Count/dropper offsets are best confirmed live via `/farmer debug` on your server.
]]--

local struct = require('struct')

local tracker = {}

tracker.session = nil
tracker.resolveName = nil
tracker.debug = false
tracker.logfn = print

-- Dedupe: 0x0D2 can be re-sent (e.g. on pool re-sync). Suppress an identical
-- (slot,item,count) that arrives within a short window of the last identical one.
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

    local gold   = struct.unpack('I', data, 0x04 + 1)
    local itemId = struct.unpack('H', data, 0x10 + 1)
    local count  = struct.unpack('H', data, 0x12 + 1)
    local slot   = struct.unpack('B', data, 0x14 + 1)

    if tracker.debug then
        tracker.logfn(string.format('[ffxi-farmer] 0xD2 gold=%d item=%d count=%d slot=%d',
            gold or -1, itemId or -1, count or -1, slot or -1))
    end

    local key = string.format('%d:%d:%d', slot or 0, itemId or 0, count or 0)
    local now = clock()
    if recent[key] and (now - recent[key]) < DEDUPE_WINDOW then
        return
    end
    recent[key] = now

    if (itemId == nil or itemId == 0) and gold and gold > 0 then
        session:addGil(gold)
    elseif itemId and itemId > 0 then
        local name = tracker.resolveName and tracker.resolveName(itemId) or nil
        local qty = (count and count > 0) and count or 1
        session:addItem(itemId, name, qty)
    end
end

return tracker
