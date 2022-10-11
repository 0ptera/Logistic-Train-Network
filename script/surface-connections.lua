function ClearAllSurfaceConnections()
  global.ConnectedSurfaces = {}
end

local function sorted_pair(number1, number2)
  return (number1 < number2) and (number1..'|'..number2) or (number2..'|'..number1)
end

local function lazy_subtable(a_table, key)
  local subtable = a_table[key]
  if not subtable then
    subtable = {}
    a_table[key] = subtable
  end
  return subtable
end

function DisconnectSurfaces(entity1, entity2)
  if not (entity1 and entity1.valid and entity2 and entity2.valid) then
    return -- this gets automatically cleaned up in find_surface_connections()
  end

  local surface_pair_key = sorted_pair(entity1.surface.index, entity2.surface.index)
  local surface_connections = global.ConnectedSurfaces[surface_pair_key]

  if surface_connections then
    surface_connections[sorted_pair(entity1.unit_number, entity2.unit_number)] = nil
  end
end

function ConnectSurfaces(entity1, entity2, network_id)
  if not (entity1 and entity1.valid and entity2 and entity2.valid) then
    error("both entities must be valid")
  end
  if entity1.surface == entity2.surface then
    error("connecting entities on the same surface is nonsensical")
  end

  local surface_pair_key = sorted_pair(entity1.surface.index, entity2.surface.index)
  local surface_connections = lazy_subtable(global.ConnectedSurfaces, surface_pair_key)

  local entity_pair_key = sorted_pair(entity1.unit_number, entity2.unit_number)
  surface_connections[entity_pair_key] = {
    -- enforce a consistent order for repeated calls with the same two entities
    entity1 = entity1.unit_number <= entity2.unit_number and entity1 or entity2,
    entity2 = entity1.unit_number > entity2.unit_number and entity1 or entity2,
    network_id = network_id,
  }
end

-- remove entity references when deleting surfaces
function OnSurfaceRemoved(event)
  -- stop references
  local surfaceID = event.surface_index
  log("removing LTN stops on surface "..tostring(surfaceID) )
  local surface = game.surfaces[surfaceID]
  if surface then
    local train_stops = surface.find_entities_filtered{type = "train-stop"}
    for _, entity in pairs(train_stops) do
      if ltn_stop_entity_names[entity.name] then
        RemoveStop(entity.unit_number)
      end
    end
  end

  -- surface connections; surface_index will either be the first half of the key or the second
  local first_surface = "^"..event.surface_index.."|"
  local second_surface = "|"..event.surface_index.."$"

  for surface_pair_key, _ in pairs(global.ConnectedSurfaces) do
    if string.find(surface_pair_key, first_surface) or string.find(surface_pair_key, second_surface) then
      global.ConnectedSurfaces[surface_pair_key] = nil
    end
  end
end