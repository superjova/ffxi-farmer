--[[
    prices.lua - the persistent price book (item id -> unit gil price).

    Framework-free: it is handed a plain data table and a save callback, so it can
    be unit-tested with a mock. In-game these come from the Ashita 'settings'
    library (see ffxi-farmer.lua).
]]--

local Prices = {}
Prices.__index = Prices

-- data:  table shaped { items = { [itemId] = price } } (e.g. a settings block)
-- saveFn: called after every mutation to persist (e.g. settings.save('prices'))
function Prices.new(data, saveFn)
    local self = setmetatable({}, Prices)
    self.data = data or { items = {} }
    if self.data.items == nil then
        self.data.items = {}
    end
    self.saveFn = saveFn or function() end
    return self
end

function Prices:get(itemId)
    return self.data.items[itemId]
end

function Prices:set(itemId, price)
    price = tonumber(price)
    if price == nil or price < 0 then return false end
    self.data.items[itemId] = price
    self.saveFn()
    return true
end

function Prices:clear(itemId)
    self.data.items[itemId] = nil
    self.saveFn()
end

-- A closure suitable for Session.new's priceFn. Reads live data, so prices set
-- after construction are reflected immediately.
function Prices:priceFn()
    local data = self.data
    return function(itemId)
        return data.items[itemId]
    end
end

return Prices
