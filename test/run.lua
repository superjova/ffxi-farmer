--[[
    Offline unit tests for the framework-free modules (session, prices, util).
    Run from the repo root:  lua test/run.lua
    These do NOT require the Ashita client; they exercise pure logic only.
]]--

package.path = package.path .. ';./addons/ffxi-farmer/?.lua'

local Session = require('session')
local Prices  = require('prices')
local util    = require('util')

local passed, failed = 0, 0

local function check(name, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print('  FAIL: ' .. name)
    end
end

local function approx(a, b)
    return math.abs(a - b) < 1e-6
end

-- ---------------------------------------------------------------------------
-- util
-- ---------------------------------------------------------------------------
check('commas thousands',   util.commas(1234) == '1,234')
check('commas millions',    util.commas(1000000) == '1,000,000')
check('commas small',       util.commas(100) == '100')
check('commas negative',    util.commas(-1234) == '-1,234')
check('commas floors float', util.commas(1234.9) == '1,234')
check('hms basic',          util.hms(3661) == '01:01:01')
check('hms zero',           util.hms(0) == '00:00:00')
check('hms minutes',        util.hms(90) == '00:01:30')

-- ---------------------------------------------------------------------------
-- prices
-- ---------------------------------------------------------------------------
do
    local saves = 0
    local p = Prices.new({ items = {} }, function() saves = saves + 1 end)
    check('price get nil before set', p:get(100) == nil)
    check('price set returns true', p:set(100, 500) == true)
    check('price get after set', p:get(100) == 500)
    check('price set persisted', saves == 1)
    check('price set rejects negative', p:set(100, -5) == false)
    check('price unchanged after reject', p:get(100) == 500)

    local fn = p:priceFn()
    check('priceFn reflects live data', fn(100) == 500)
    p:set(100, 750)
    check('priceFn sees later updates', fn(100) == 750)
end

-- ---------------------------------------------------------------------------
-- session: timer with an injected fake clock
-- ---------------------------------------------------------------------------
do
    local now = 0
    local clock = function() return now end
    local s = Session.new(function() return nil end, clock)

    check('starts stopped', s.state == Session.STOPPED)
    check('elapsed 0 at start', s:elapsedSeconds() == 0)
    check('gilPerHour 0 with no time', s:gilPerHour() == 0)

    s:start()
    now = 100
    check('elapsed tracks running', s:elapsedSeconds() == 100)

    s:pause()
    now = 200
    check('elapsed frozen while paused', s:elapsedSeconds() == 100)

    s:resume()
    now = 250
    check('elapsed resumes', s:elapsedSeconds() == 150)

    s:stop()
    now = 999
    check('elapsed frozen after stop', s:elapsedSeconds() == 150)

    s:reset()
    check('reset clears timer', s:elapsedSeconds() == 0 and s.state == Session.STOPPED)
end

-- ---------------------------------------------------------------------------
-- session + prices: totals, gil/hr, and on-demand re-pricing
-- ---------------------------------------------------------------------------
do
    local now = 0
    local clock = function() return now end
    local saves = 0
    local prices = Prices.new({ items = {} }, function() saves = saves + 1 end)
    local s = Session.new(prices:priceFn(), clock)

    s:start()
    s:addGil(1000)
    s:addItem(4096, 'Fire Crystal', 10)   -- unpriced
    s:addItem(8233, 'Beetle Jaw', 4)      -- unpriced
    s:addItem(4096, 'Fire Crystal', 2)    -- accumulates -> qty 12

    check('gil dropped accumulates', s.gilDropped == 1000)
    check('item qty accumulates', s.items[4096].qty == 12)
    check('total is gil only while unpriced', s:total() == 1000)
    check('two untracked items', s:untrackedCount() == 2)
    check('tracked empty', #s:tracked() == 0)

    -- price one item
    prices:set(4096, 500)
    check('one untracked left', s:untrackedCount() == 1)
    check('one tracked now', #s:tracked() == 1)
    check('total includes priced item', s:total() == 1000 + 12 * 500) -- 7000

    -- price the second item
    prices:set(8233, 250)
    check('no untracked left', s:untrackedCount() == 0)
    check('total includes both', s:total() == 1000 + 12 * 500 + 4 * 250) -- 8000

    -- gil/hr after 1 hour
    now = 3600
    check('gilPerHour after 1h', approx(s:gilPerHour(), 8000))

    -- RE-PRICE a tracked item -> totals and gil/hr must reflect immediately
    prices:set(4096, 1000)
    check('total reflects re-price', s:total() == 1000 + 12 * 1000 + 4 * 250) -- 14000
    check('gilPerHour reflects re-price', approx(s:gilPerHour(), 14000))

    -- findByName for the setprice-by-name command path
    check('findByName matches', s:findByName('beetle jaw') == 8233)
    check('findByName miss', s:findByName('nonexistent') == nil)

    -- tracked() exposes current price and line value
    local tracked = s:tracked()
    local byId = {}
    for _, e in ipairs(tracked) do byId[e.itemId] = e end
    check('tracked price correct', byId[4096].price == 1000)
    check('tracked value correct', byId[4096].value == 12000)
end

-- ---------------------------------------------------------------------------
print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
