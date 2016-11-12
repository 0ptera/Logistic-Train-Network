function copyPrototype(type, name, newName)
  if not data.raw[type][name] then error("type "..type.." "..name.." doesn't exist") end
  local p = table.deepcopy(data.raw[type][name])
  p.name = newName
  if p.minable and p.minable.result then
    p.minable.result = newName
  end
  if p.place_result then
    p.place_result = newName
  end
  if p.result then
    p.result = newName
  end
  return p
end

function printmsg(msg)
  if global.log_output.console then
    game.print(msg)
  end
  if global.log_output.log then
    log("[LT] " .. msg)
  end
end

return copyPrototype, printmsg