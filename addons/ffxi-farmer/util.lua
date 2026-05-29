--[[
    util.lua - small framework-free formatting helpers.
    Pure Lua so it can be unit-tested outside the Ashita client.
]]--

local util = {}

-- Format an integer with thousands separators. Floats are floored.
function util.commas(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    out = out:gsub('^,', '')
    if n < 0 then
        out = '-' .. out
    end
    return out
end

-- Format a duration in seconds as HH:MM:SS.
function util.hms(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 0 then sec = 0 end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format('%02d:%02d:%02d', h, m, s)
end

return util
