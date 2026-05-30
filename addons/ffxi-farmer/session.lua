--[[
    session.lua - the farming session state machine and gil/hour math.

    Deliberately framework-free (no Ashita globals) so it can be unit-tested with
    stock Lua. Item value is computed ON DEMAND from an injected price lookup, so
    editing a price anywhere instantly re-flows into total() and gilPerHour() with
    no reconciliation step.
]]--

local Session = {}
Session.__index = Session

Session.STOPPED = 'stopped'
Session.RUNNING = 'running'
Session.PAUSED  = 'paused'

-- priceFn(itemId) -> unit price or nil
-- clock() -> monotonic-ish wall seconds (defaults to os.time; injectable for tests)
function Session.new(priceFn, clock)
    local self = setmetatable({}, Session)
    self.priceFn = priceFn or function() return nil end
    self.clock = clock or os.time
    self:reset()
    return self
end

function Session:reset()
    self.state = Session.STOPPED
    self.startedAt = nil
    self.accumulatedSeconds = 0
    self.gilDropped = 0
    self.items = {}   -- [itemId] = { name = string, qty = number }
    self.order = {}   -- insertion order of itemIds for stable UI listing
end

function Session:start()
    if self.state == Session.RUNNING then return end
    -- Treat start-from-paused as a resume so we never drop accumulated time.
    self.startedAt = self.clock()
    self.state = Session.RUNNING
end

function Session:pause()
    if self.state ~= Session.RUNNING then return end
    self.accumulatedSeconds = self.accumulatedSeconds + (self.clock() - self.startedAt)
    self.startedAt = nil
    self.state = Session.PAUSED
end

function Session:resume()
    if self.state ~= Session.PAUSED then return end
    self.startedAt = self.clock()
    self.state = Session.RUNNING
end

function Session:stop()
    if self.state == Session.RUNNING and self.startedAt then
        self.accumulatedSeconds = self.accumulatedSeconds + (self.clock() - self.startedAt)
    end
    self.startedAt = nil
    self.state = Session.STOPPED
end

function Session:isRunning()
    return self.state == Session.RUNNING
end

function Session:elapsedSeconds()
    local e = self.accumulatedSeconds
    if self.state == Session.RUNNING and self.startedAt then
        e = e + (self.clock() - self.startedAt)
    end
    return e
end

function Session:addGil(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    self.gilDropped = self.gilDropped + amount
end

function Session:addItem(itemId, name, qty)
    qty = tonumber(qty) or 1
    if qty <= 0 then qty = 1 end
    local it = self.items[itemId]
    if not it then
        it = { name = name or ('Item ' .. tostring(itemId)), qty = 0 }
        self.items[itemId] = it
        self.order[#self.order + 1] = itemId
    end
    if name and name ~= '' then
        it.name = name
    end
    it.qty = it.qty + qty
end

-- Sum of qty * price over every priced item (unpriced items contribute 0).
function Session:itemValue()
    local total = 0
    for id, it in pairs(self.items) do
        local p = self.priceFn(id)
        if p then
            total = total + (it.qty * p)
        end
    end
    return total
end

function Session:total()
    return self.gilDropped + self:itemValue()
end

function Session:gilPerHour()
    local secs = self:elapsedSeconds()
    if secs <= 0 then return 0 end
    return self:total() / (secs / 3600)
end

-- Items with no price yet (need the user to fill one in).
function Session:untracked()
    local list = {}
    for _, id in ipairs(self.order) do
        if self.priceFn(id) == nil then
            local it = self.items[id]
            list[#list + 1] = { itemId = id, name = it.name, qty = it.qty }
        end
    end
    return list
end

-- Items that have a price, with current price and line value (for the editable panel).
function Session:tracked()
    local list = {}
    for _, id in ipairs(self.order) do
        local p = self.priceFn(id)
        if p ~= nil then
            local it = self.items[id]
            list[#list + 1] = {
                itemId = id,
                name = it.name,
                qty = it.qty,
                price = p,
                value = it.qty * p,
            }
        end
    end
    return list
end

function Session:untrackedCount()
    local n = 0
    for _, id in ipairs(self.order) do
        if self.priceFn(id) == nil then n = n + 1 end
    end
    return n
end

-- Find an accumulated item by (case-insensitive) name; returns itemId or nil.
function Session:findByName(name)
    if not name then return nil end
    local target = name:lower()
    for id, it in pairs(self.items) do
        if it.name:lower() == target then
            return id
        end
    end
    return nil
end

return Session
