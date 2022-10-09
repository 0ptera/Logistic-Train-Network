--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]



--create stop
function CreateStop(entity)
  if global.LogisticTrainStops[entity.unit_number] then
    if message_level >= 1 then printmsg({"ltn-message.error-duplicated-unit_number", entity.unit_number}, entity.force) end
    if debug_log then log("(CreateStop) duplicate stop unit number "..entity.unit_number) end
    return
  end
  local stop_offset = ltn_stop_entity_names[entity.name]
  local posIn, posOut, rotOut, search_area
  --log("Stop created at "..entity.position.x.."/"..entity.position.y..", orientation "..entity.direction)
  if entity.direction == 0 then --SN
    posIn = {entity.position.x + stop_offset, entity.position.y - 1}
    posOut = {entity.position.x - 1 + stop_offset, entity.position.y - 1}
    rotOut = 0
    search_area = {
      {entity.position.x + 0.001 - 1 + stop_offset, entity.position.y + 0.001 - 1},
      {entity.position.x - 0.001 + 1 + stop_offset, entity.position.y - 0.001}
    }
  elseif entity.direction == 2 then --WE
    posIn = {entity.position.x, entity.position.y + stop_offset}
    posOut = {entity.position.x, entity.position.y - 1 + stop_offset}
    rotOut = 2
    search_area = {
      {entity.position.x + 0.001, entity.position.y + 0.001 - 1 + stop_offset},
      {entity.position.x - 0.001 + 1, entity.position.y - 0.001 + 1 + stop_offset}
    }
  elseif entity.direction == 4 then --NS
    posIn = {entity.position.x - 1 - stop_offset, entity.position.y}
    posOut = {entity.position.x - stop_offset, entity.position.y}
    rotOut = 4
    search_area = {
      {entity.position.x + 0.001 - 1 - stop_offset, entity.position.y + 0.001},
      {entity.position.x - 0.001 + 1 - stop_offset, entity.position.y - 0.001 + 1}
    }
  elseif entity.direction == 6 then --EW
    posIn = {entity.position.x - 1, entity.position.y - 1 - stop_offset}
    posOut = {entity.position.x - 1, entity.position.y - stop_offset}
    rotOut = 6
    search_area = {
      {entity.position.x + 0.001 - 1, entity.position.y + 0.001 - 1 - stop_offset},
      {entity.position.x - 0.001, entity.position.y - 0.001 + 1 - stop_offset}
    }
  else --invalid orientation
    if message_level >= 1 then printmsg({"ltn-message.error-stop-orientation", tostring(entity.direction)}, entity.force) end
    if debug_log then log("(CreateStop) invalid train stop orientation "..tostring(entity.direction) ) end
    entity.destroy()
    return
  end

  local input, output, lampctrl
  -- handle blueprint ghosts and existing IO entities preserving circuit connections
  local ghosts = entity.surface.find_entities(search_area)
  for _,ghost in pairs (ghosts) do
    if ghost.valid then
      if ghost.name == "entity-ghost" then
        if ghost.ghost_name == ltn_stop_input then
          -- log("reviving ghost input at "..ghost.position.x..", "..ghost.position.y)
          _, input = ghost.revive()
        elseif ghost.ghost_name == ltn_stop_output then
          -- log("reviving ghost output at "..ghost.position.x..", "..ghost.position.y)
          _, output = ghost.revive()
        elseif ghost.ghost_name == ltn_stop_output_controller then
          -- log("reviving ghost lamp-control at "..ghost.position.x..", "..ghost.position.y)
          _, lampctrl = ghost.revive()
        end
      -- something has built I/O already (e.g.) Creative Mode Instant Blueprint
      elseif ghost.name == ltn_stop_input then
        input = ghost
        -- log("Found existing input at "..ghost.position.x..", "..ghost.position.y)
      elseif ghost.name == ltn_stop_output then
        output = ghost
        -- log("Found existing output at "..ghost.position.x..", "..ghost.position.y)
      elseif ghost.name == ltn_stop_output_controller then
        lampctrl = ghost
        -- log("Found existing lamp-control at "..ghost.position.x..", "..ghost.position.y)
      end
    end
  end

  if input == nil then -- create new
    input = entity.surface.create_entity
    {
      name = ltn_stop_input,

      position = posIn,
      force = entity.force
    }
  end
  input.operable = false -- disable gui
  input.minable = false
  input.destructible = false -- don't bother checking if alive

  if lampctrl == nil then
    lampctrl = entity.surface.create_entity
    {
      name = ltn_stop_output_controller,
      position = {input.position.x + 0.45, input.position.y + 0.45}, -- slight offset so adjacent lamps won't connect
      force = entity.force
    }
    -- log("building lamp-control at "..lampctrl.position.x..", "..lampctrl.position.y)
  end
  lampctrl.operable = false -- disable gui
  lampctrl.minable = false
  lampctrl.destructible = false -- don't bother checking if alive

  -- connect lamp and control
  lampctrl.get_control_behavior().parameters = {{index = 1, signal = {type="virtual",name="signal-white"}, count = 1 }}
  input.connect_neighbour({target_entity=lampctrl, wire=defines.wire_type.green})
  input.connect_neighbour({target_entity=lampctrl, wire=defines.wire_type.red})
  input.get_or_create_control_behavior().use_colors = true
  input.get_or_create_control_behavior().circuit_condition = {condition = {comparator=">",first_signal={type="virtual",name="signal-anything"}}}

  if output == nil then -- create new
    output = entity.surface.create_entity
    {
      name = ltn_stop_output,
      position = posOut,
      direction = rotOut,
      force = entity.force
    }
  end
  output.operable = false -- disable gui
  output.minable = false
  output.destructible = false -- don't bother checking if alive

  -- enable reading contents and sending signals to trains
  entity.get_or_create_control_behavior().send_to_train = true
  entity.get_or_create_control_behavior().read_from_train = true

  global.LogisticTrainStops[entity.unit_number] = {
    entity = entity,
    input = input,
    output = output,
    lamp_control = lampctrl,
    parked_train = nil,
    parked_train_id = nil,
    active_deliveries = {},   --delivery IDs to/from stop
    error_code = -1,          --key to error_codes table
    is_depot = false,
    depot_priority = 0,
    network_id = default_network,
    min_carriages = 0,
    max_carriages = 0,
    max_trains = 0,
    requesting_threshold = min_requested,
    requesting_threshold_stacks = 0,
    requester_priority = 0,
    no_warnings = false,
    providing_threshold = min_provided,
    providing_threshold_stacks = 0,
    provider_priority = 0,
    locked_slots = 0,
  }
  UpdateStopOutput(global.LogisticTrainStops[entity.unit_number])

  -- register events
  -- script.on_event(defines.events.on_tick, OnTick)
  script.on_nth_tick(nil)
  script.on_nth_tick(dispatcher_nth_tick, OnTick)
  script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
  script.on_event(defines.events.on_train_created, OnTrainCreated)
  if debug_log then log("(OnEntityCreated) on_nth_tick("..dispatcher_nth_tick.."), on_train_changed_state, on_train_created registered") end
end

function OnEntityCreated(event)
  local entity = event.created_entity or event.entity or event.destination
  if not entity or not entity.valid then return end

  if ltn_stop_entity_names[entity.name] then
    CreateStop(entity)
  end
end


-- stop removed
function RemoveStop(stopID, create_ghosts)
  local stop = global.LogisticTrainStops[stopID]

  -- clean lookup tables
  for k,v in pairs(global.StopDistances) do
    if k:find(stopID) then
      global.StopDistances[k] = nil
    end
  end

  -- remove available train
  if stop and stop.is_depot and stop.parked_train_id and global.Dispatcher.availableTrains[stop.parked_train_id] then
    global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[stop.parked_train_id].capacity
    global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[stop.parked_train_id].fluid_capacity
    global.Dispatcher.availableTrains[stop.parked_train_id] = nil
  end

  -- destroy IO entities, broken IO entities should be sufficiently handled in initializeTrainStops()
  if stop then
    if stop.input and stop.input.valid then
      if create_ghosts then
        stop.input.destructible = true
        stop.input.die()
      else
        stop.input.destroy()
      end
    end
    if stop.output and stop.output.valid then
      if create_ghosts then
        stop.output.destructible = true
        stop.output.die()
      else
        stop.output.destroy()
      end
    end
    if stop.lamp_control and stop.lamp_control.valid then stop.lamp_control.destroy() end
  end

  global.LogisticTrainStops[stopID] = nil

  if not next(global.LogisticTrainStops) then
    -- reset tick indexes
    global.tick_state = 0
    global.tick_stop_index = nil
    global.tick_request_index = nil

    -- unregister events
    script.on_nth_tick(nil)
    script.on_event(defines.events.on_train_changed_state, nil)
    script.on_event(defines.events.on_train_created, nil)
    if debug_log then log("(OnEntityRemoved) Removed last LTN Stop: on_nth_tick, on_train_changed_state, on_train_created unregistered") end
  end
end

function OnEntityRemoved(event)
  local entity = event.entity
  if not entity or not entity.valid then return end

  if entity.train then
    local trainID = entity.train.id
    -- remove from stop if parked
    if global.StoppedTrains[trainID] then
      TrainLeaves(trainID)
    end
    -- removing any carriage fails a delivery
    -- otherwise I'd have to handle splitting and merging a delivery across train parts
    local delivery = global.Dispatcher.Deliveries[trainID]
    if delivery then
      script.raise_event(on_delivery_failed_event, {train_id = trainID, shipment = delivery.shipment})
      RemoveDelivery(trainID)
    end

  elseif ltn_stop_entity_names[entity.name] then
    RemoveStop(entity.unit_number, true)
  end
end


-- remove stop references when deleting surfaces
function OnSurfaceRemoved(event)
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
end


--rename stop
local function renamedStop(targetID, old_name, new_name)
  -- find identical stop names
  local duplicateName = false
  local renameDeliveries = true
  for stopID, stop in pairs(global.LogisticTrainStops) do
    if not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lamp_control.valid then
      RemoveStop(stopID)
    elseif stop.entity.backer_name == old_name then
      renameDeliveries = false
    end
  end
  -- rename deliveries only if no other LTN stop old_name exists
  if renameDeliveries then
    if debug_log then log("(OnEntityRenamed) last LTN stop "..old_name.." renamed, updating deliveries to "..new_name..".") end
    for trainID, delivery in pairs(global.Dispatcher.Deliveries) do
      if delivery.to == old_name then
        delivery.to = new_name
      end
      if delivery.from == old_name then
        delivery.from = new_name
      end
    end
  end
end

script.on_event(defines.events.on_entity_renamed, function(event)
  local uid = event.entity.unit_number
  local oldName = event.old_name
  local newName = event.entity.backer_name
  if ltn_stop_entity_names[event.entity.name] then
    renamedStop(uid, oldName, newName)
  end
end)

