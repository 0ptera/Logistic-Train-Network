--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

on_stops_updated_event = script.generate_event_name()
on_dispatcher_updated_event = script.generate_event_name()
on_delivery_completed_event = script.generate_event_name()
on_delivery_failed_event = script.generate_event_name()


-- ltn_interface allows mods to register for update events
remote.add_interface("logistic-train-network", {
  -- updates for ltn_stops
  get_on_stops_updated_event = function() return on_stops_updated_event end,

  -- updates for whole dispatcher
  get_on_dispatcher_updated_event = function() return on_dispatcher_updated_event end,

  -- update for completing deliveries
  get_on_delivery_completed_event = function() return on_delivery_completed_event end,
  get_on_delivery_failed_event = function() return on_delivery_failed_event end,
})


--[[ register events from LTN:
if remote.interfaces["logistic-train-network"] then
  script.on_event(remote.call("logistic-train-network", "get_on_stops_updated_event"), on_stops_updated)
  script.on_event(remote.call("logistic-train-network", "get_on_dispatcher_updated_event"), on_dispatcher_updated)
end
]]--


--[[ EVENTS
get_on_stops_updated_event ->
  called after LTN finished gathering stop data and created deliveries

Contains:
  logistic_train_stops = {
    [stopID], {
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
    }
  }


get_on_dispatcher_updated_event ->
  called after LTN finished gathering stop data and created deliveries

Contains:
  update_interval = int -- LTN update interval (depends on existing ltn stops and stops per tick setting
  provided_by_stop = { [stopID], { [item], count } }
  requests_by_stop = { [stopID], { [item], count } }
  deliveries = { trainID = {force, train, from, to, networkID, started, shipment = { item = count } } }
  available_trains = { [trainID ], { capacity, fluid_capacity, force, network_id, train } }


get_on_delivery_completed_event ->
  Called when train leaves delivery target stop

Contains:
  event.delivery = {force, train, from, to, networkID, started, shipment = { [item], count } }
  event.trainID


get_on_delivery_failed_event ->
  Called when rolling stock of a train gets removed or the delivery timed out

Contains:
  event.delivery = {force, train, from, to, networkID, started, shipment = { [item], count } }
  event.trainID

--]]