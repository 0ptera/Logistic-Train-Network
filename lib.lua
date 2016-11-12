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
  --for i,player in pairs(game.players) do
    --player.print(msg)
  --end
  game.print(msg)
end

return copyPrototype, printmsg