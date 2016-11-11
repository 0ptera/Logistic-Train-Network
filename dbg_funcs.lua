--
-- By default the non-underscore-functions are just empty functions! This means Lua
-- has to call this function and immediatelly returns. This should be nearly the same
-- speed as "if debug_mode then"-constructs.
-- 
-- Please avoid such constructions:
--  dbg.ftext(ntt.entity.surface, ntt.entity.position, "DRP " .. ntt.prev.tracker .. " "..ntt.manager .. " " .. unit_number, 1)
-- This is slow, cause the parameter has to be calculated BEFORE debug knows if it should be printed or not.
-- The right way to do this:
--  dbg.ftext(ntt, unit_number, 1)
-- and do the rest in the underscore-debug-function!
-- So for every type of debugging you want to do you need to create an own debug-function
--

-----------------------------
dbg.example = function(surface, area, unit_number)
end

-- print the unit_number on every edge of the area (2 positions) on surface with a flying-text
dbg._example = function(surface, area, unit_number)
    for _, i in pairs({'left_top', 'right_bottom'}) do
        for _, j in pairs({'left_top', 'right_bottom'}) do
            local pos = {area[i].x-2, area[j].y}
            surface.create_entity({ name = "flying-text", position = pos, text = unit_number})
        end
    end
end

-------------------------------

dbg.show_train = function(train_ptr, txt)
end

-- print a text over the assigne train
dbg._show_train = function(train_ptr, txt)
    if train_ptr == nil then return end
    local train = global.Dispatcher.availableTrains[train_ptr.id]
    local entity = train.front_stock
    entity.surface.create_entity({ name = "flying-text", position = entity.position, text = txt})
end

