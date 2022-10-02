--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

on_stops_updated_event = script.generate_event_name()
on_dispatcher_updated_event = script.generate_event_name()
on_dispatcher_no_train_found_event = script.generate_event_name()
on_delivery_created_event = script.generate_event_name()
on_delivery_pickup_complete_event = script.generate_event_name()
on_delivery_completed_event = script.generate_event_name()
on_delivery_failed_event = script.generate_event_name()

on_provider_missing_cargo_alert = script.generate_event_name()
on_provider_unscheduled_cargo_alert = script.generate_event_name()
on_requester_unscheduled_cargo_alert = script.generate_event_name()
on_requester_remaining_cargo_alert = script.generate_event_name()

local function clear_all_surface_connections()
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

local function disconnect_surfaces(entity1, entity2)
  local surface_pair_key = sorted_pair(entity1.surface.index, entity2.surface.index)
  local surface_connections = global.ConnectedSurfaces[surface_pair_key]

  if surface_connections then
    surface_connections[sorted_pair(entity1.unit_number, entity2.unit_number)] = nil
  end
end

local function connect_surfaces(entity1, entity2, network_id)
  if entity1.surface == entity2.surface then
    error("the given entities must not be on the same surface")
  end

  local surface_pair_key = sorted_pair(entity1.surface.index, entity2.surface.index)
  local surface_connections = lazy_subtable(global.ConnectedSurfaces, surface_pair_key)

  local entity_pair_key = sorted_pair(entity1.unit_number, entity2.unit_number)
  surface_connections[entity_pair_key] = {
    entity1 = entity1,
    entity2 = entity2,
    network_id = network_id,
  }
end



-- ltn_interface allows mods to register for update events
remote.add_interface("logistic-train-network", {
  -- updates for ltn_stops
  on_stops_updated = function() return on_stops_updated_event end,

  -- updates for dispatcher
  on_dispatcher_updated = function() return on_dispatcher_updated_event end,
  on_dispatcher_no_train_found = function() return on_dispatcher_no_train_found_event end,
  on_delivery_created = function() return on_delivery_created_event end,

  -- update for updated deliveries after leaving provider
  on_delivery_pickup_complete = function() return on_delivery_pickup_complete_event end,

  -- update for completing deliveries
  on_delivery_completed = function() return on_delivery_completed_event end,
  on_delivery_failed = function() return on_delivery_failed_event end,

  -- alerts
  on_provider_missing_cargo = function() return on_provider_missing_cargo_alert end,
  on_provider_unscheduled_cargo = function() return on_provider_unscheduled_cargo_alert end,
  on_requester_unscheduled_cargo = function() return on_requester_unscheduled_cargo_alert end,
  on_requester_remaining_cargo = function() return on_requester_remaining_cargo_alert end,

  -- Designates two entities on different surfaces as forming a surface connection.
  -- Logically those surfaces are combined into one LTN, that is, deliveries will be created between providers on one surface and requesters on the other.
  -- The connection has a network_id that acts as an additional mask that is applied to potential providers,
  -- so using -1 here would apply no further restrictions and using 0 would make the connection unusable.
  -- The connection is bi-directional but not transitive, i.e. surface A -> B implies B -> A, but A -> B and B -> C does not imply A -> C.
  -- LTN has no notion of how a train actually moves between surfaces.
  -- It is the caller's responsibility to modify the train schedule accordingly, most appropriately in an on_delivery_created_event.
  -- Its field 'surface_connections' will be the table of connections that had a matching network_id and force.
  -- For intra-surface deliveries that field will be an empty table.
  -- Trains will be sourced from the provider surface only and should return to it after leaving the requester.
  -- This is to avoid creating an imbalance in the train pools per surface.
  connect_surfaces = connect_surfaces, -- function(entity1 :: LuaEntity, entity2 :: LuaEntity)

  -- Explicitly severs the surface connection that is formed by the two given entities.
  -- Active deliveries will not be affected.
  -- Calling this function for two entities that are not connected has no effect.
  -- It is not necessary to call this function if one or both of the entities are deleted.
  disconnect_surfaces = disconnect_surfaces, -- function(entity1 :: LuaEntity, entity2 :: LuaEntity)

  -- Clears all surface connections.
  -- Active deliveries will not be affected
  -- This function exists mostly for debugging purposes, so there is no event that is raised afterwards.
  clear_all_surface_connections = clear_all_surface_connections,

  -- TODO handle on_surface_deleted

  -- Re-assigns a delivery to a different train.
  -- Scripts should call this function if they create a train based on another train, for example when moving a train to a different surface.
  -- It is the caller's responsibility to make sure that the new train's schedule matches the old one's before calling this function.
  -- Calling this function with an old_train_id that is not executing a delivery has no effect.
  -- It is not necessary to call this function when coupling trains via script, LTN is already aware of that through Factorio events.
  reassign_delivery = ReassignDelivery,

  -- Allow to keep surfaces mostly separate with a few explicit deliveries between them without the need to set the network_id explicitly on each stop on both surfaces.
  -- TODO set_surface_default_network_id(surface :: LuaSurface, uint network_id)
})


--[[ register events from LTN:
if remote.interfaces["logistic-train-network"] then
  script.on_event(remote.call("logistic-train-network", "on_stops_updated"), on_stops_updated)
  script.on_event(remote.call("logistic-train-network", "on_dispatcher_updated"), on_dispatcher_updated)
end
]]--


--[[ EVENTS
on_stops_updated
Raised every UpdateInterval, after delivery generation
-> Contains:
event.logistic_train_stops = {  [stop_id],  {
    -- stop data
    active_deliveries,
    entity,
    input,
    output,
    lamp_control,
    error_code,

    -- control signals
    is_depot,
    depot_priority,
    network_id,
    max_carriages,
    min_carriages,
    max_trains,
    providing_threshold,
    providing_threshold_stacks,
    provider_priority,
    requesting_threshold,
    requesting_threshold_stacks,
    requester_priority,
    locked_slots,
    no_warnings,

    -- parked train data
    parked_train,
    parked_train_id,
    parked_train_faces_stop,
}}


on_dispatcher_updated
Raised every UpdateInterval, after delivery generation
-> Contains:
  event.update_interval = int -- time in ticks LTN needed to run all updates, varies depending on number of stops and requests
  event.provided_by_stop = { [stop_id], { [item], count } }
  event.requests_by_stop = { [stop_id], { [item], count } }
  event.deliveries = { [train_id], {force, train, from, to, network_id, started, shipment = { [item], count } } }
  event.available_trains = { [train_id], { capacity, fluid_capacity, force, depot_priority, network_id, train } }


on_dispatcher_no_train_found
Raised when no train was found to handle a request
-> Contains:
  event.to = requester.backer_name
  event.to_id = requester.unit_number
  event.network_id
  (optional) event.item
  (optional) event.from
  (optional) event.from_id
  (optional) event.min_carriages
  (optional) event.max_carriages
  (optional) event.shipment = { [item], count }


on_delivery_created
Raised after dispatcher assigned delivery to a train
    event.train_id
    event.train
    event.from
    event.from_id
    event.to
    event.to_id
    event.shipment = { [item], count }
  })


on_delivery_pickup_complete
Raised when a train leaves provider stop
-> Contains:
  event.train_id
  event.train
  event.planned_shipment= { [item], count }
  event.actual_shipment = { [item], count } -- shipment updated to train inventory


on_delivery_completed
Raised when train leaves requester stop
-> Contains:
  event.train_id
  event.train
  event.shipment= { [item], count }


on_delivery_failed
Raised when rolling stock of a train gets removed, the delivery timed out, train enters depot stop with active delivery
-> Contains:
  event.train_id
  event.shipment= { [item], count } }


----  Alerts ----

on_dispatcher_no_train_found
Raised when depot was empty
-> Contains:
  event.to
  event.to_id
  event.network_id
  event.item

on_dispatcher_no_train_found
Raised when no matching train was found
-> Contains:
  event.to
  event.to_id
  event.network_id
  event.from
  event.from_id
  event.min_carriages
  event.max_carriages
  event.shipment

on_provider_missing_cargo
Raised when trains leave provider with less than planned load
-> Contains:
  event.train
  event.station
  planned_shipment = { [item], count } }
  actual_shipment = { [item], count } }

on_provider_unscheduled_cargo
Raised when trains leave provider with wrong cargo
-> Contains:
  event.train
  event.station
  planned_shipment = { [item], count } }
  unscheduled_load = { [item], count } }

on_requester_unscheduled_cargo
Raised when trains arrive at requester with wrong cargo
-> Contains:
  event.train
  event.station
  planned_shipment = { [item], count } }
  unscheduled_load = { [item], count } }

on_requester_remaining_cargo
Raised when trains leave requester with remaining cargo
-> Contains:
  event.train
  event.station
  remaining_load = { [item], count } }

--]]