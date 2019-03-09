--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

-- write msg to console for all member of force
-- skips over any duplicate messages (clearing filter is done in on_tick)
function printmsg(msg, force, useFilter)
  local msgKey = ""
  if force and force.valid then
    msgKey = force.name..", "
  else
    msgKey = "all, "
  end
  if type(msg) == "table" then
    for k, v in pairs(msg) do
      if type(v) == "table" then
        msgKey = msgKey..v[1]..", "
      elseif type(v) == "string" then
        msgKey = msgKey..v..", "
      end
    end
  else
    msgKey = msg
  end

  -- print message
  if global.messageBuffer[msgKey] == nil or not useFilter then
    if force and force.valid then
      force.print(msg)
    else
      game.print(msg)
    end
  end

  -- add current tick to messageBuffer if msgKey doesn't exist
  global.messageBuffer[msgKey] = global.messageBuffer[msgKey] or {tick = game.tick}
end
