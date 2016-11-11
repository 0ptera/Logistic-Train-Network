--- Debug class
--
-- This is very special and it needs a bit discipline to use it correct, so read carefully!
-- 
-- Debugger is turned on/off via remote function
-- Example:
-- remote.add_interface("LogTrains", 
--                      { debug = function() __switchDebug() end })
-- The __switchDebug() exchanges the functions the dbg-class: All functions without _ are exchanged. See down!


global.debugger = global.debugger or false

--- debugger class

dbg = {}
-------------------------------
-- returns status of debugger, do not change!
dbg.mode = function()
    return false
end

dbg._mode = function()
    return true
end
-------------------------------
dbg.print = function(str)
end

dbg._print = function(str)
    game.print(str)
    log("[LT] " .. str)
end

-------------------------------

-- load own debug-functions
require "dbg_funcs"

-------------------------------

---
--- exchanges all functions without "_" with the same parallel-function with "_"
function __switchDebug()
    game.print("[LT] SwitchDebug from " .. tostring(dbg.mode()) .. " to " .. tostring(dbg._mode()))
    for funcName, func in pairs(dbg) do
        if (string.sub(funcName, 0, 1) ~= "_") then
            local funcName2 = "_" .. funcName
            dbg[funcName] = dbg[funcName2]
            dbg[funcName2] = func
        end
    end
    global.debugger = dbg.mode()
end

if global.debugger ~= dbg.mode() then
    __switchDebug()
end
