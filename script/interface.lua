--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

on_stops_updated_event = script.generate_event_name()
on_dispatcher_updated_event = script.generate_event_name()
on_dispatcher_no_train_found_event = script.generate_event_name()
on_delivery_pickup_complete_event = script.generate_event_name()
on_delivery_completed_event = script.generate_event_name()
on_delivery_failed_event = script.generate_event_name()

-- ltn_interface allows mods to register for update events
remote.add_interface("logistic-train-network", {
  -- updates for ltn_stops
  on_stops_updated = function() return on_stops_updated_event end,

  -- updates for dispatcher
  on_dispatcher_updated = function() return on_dispatcher_updated_event end,
  on_dispatcher_no_train_found = function() return on_dispatcher_no_train_found_event end,

  -- update for updated deliveries after leaving provider
  on_delivery_pickup_complete = function() return on_delivery_pickup_complete_event end,

  -- update for completing deliveries
  on_delivery_completed = function() return on_delivery_completed_event end,
  on_delivery_failed = function() return on_delivery_failed_event end,
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
event.logistic_train_stops = {  [stopID],  {
    -- stop data
    activeDeliveries,
    entity,
    input,
    output,
    lampControl,
    errorCode,

    -- control signals
    isDepot,
    network_id,
    maxTraincars,
    minTraincars,
    trainLimit,
    provideThreshold,
    provideStackThreshold,
    providePriority,
    requestThreshold,
    requestStackThreshold,
    requestPriority,
    lockedSlots,
    noWarnings,

    -- parked train data
    parkedTrain,
    parkedTrainID,
    parkedTrainFacesStop,
}}


on_dispatcher_updated
Raised every UpdateInterval, after delivery generation
-> Contains:
  event.update_interval = int -- time in ticks LTN needed to run all updates, varies depending on number of stops and requests
  event.provided_by_stop = { [stop_id], { [item], count } }
  event.requests_by_stop = { [stop_id], { [item], count } }
  event.deliveries = { [train_id], {force, train, from, to, network_id, started, shipment = { [item], count } } }
  event.available_trains = { [train_id], { capacity, fluid_capacity, force, network_id, train } }


on_dispatcher_no_train_found
Raised when no train was found to handle a request
-> Contains:
  event.to = requester.backer_name
  event.to_id = requester.unit_number
  event.network_id
  (optional) event.item
  (optional) event.from
  (optional) event.from_id
  (optional) event.minTraincars
  (optional) event.maxTraincars
  (optional) event.shipment = { [item], count }


on_delivery_pickup_complete
Raised when a train leaves provider stop
-> Contains:
  event.train_id
  event.planned_shipment= { [item], count } }
  event.actual_shipment = { [item], count } } -- shipment updated to train inventory


on_delivery_completed
Raised when train leaves requester stop
-> Contains:
  event.train_id
  event.shipment= { [item], count } }


on_delivery_failed
Raised when rolling stock of a train gets removed or the delivery timed out
-> Contains:
  event.train_id
  event.shipment= { [item], count } }

--]]