--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

require "script.constants"

---- INITIALIZATION ----

local function addTrainSignals(loco)
  local cargocount = 0
  local fluidcount = 0
  local artillerycount = 0
  for _, wagon in pairs(game.entity_prototypes) do
    if wagon.type == "cargo-wagon" then
      cargocount = cargocount + 1
      signal = TRAIN_CARGO.."-"..loco.."-"..wagon.name
      global.TrainSignals[signal] = {
        locomotive = loco,
        wagon = wagon.name,
        type = "cargo",
      }
    elseif wagon.type == "fluid-wagon" then
      fluidcount = fluidcount + 1
      signal = TRAIN_FLUID.."-"..loco.."-"..wagon.name
      global.TrainSignals[signal] = {
        locomotive = loco,
        wagon = wagon.name,
        type = "fluid",
      }
    elseif wagon.type == "artillery-wagon" then
      artillerycount = artillerycount + 1
      signal = TRAIN_ARTILLERY.."-"..loco.."-"..wagon.name
      global.TrainSignals[signal] = {
        locomotive = loco,
        wagon = wagon.name,
        type = "artillery",
      }
    end
  end
  if cargocount > 1 then
    signal = TRAIN_CARGO.."-"..loco.."-any"
    global.TrainSignals[signal] = {
      locomotive = loco,
      wagon = "any",
      type = "cargo",
    }
  end
  if fluidcount > 1 then
    signal = TRAIN_FLUID.."-"..loco.."-any"
    global.TrainSignals[signal] = {
      locomotive = loco,
      wagon = "any",
      type = "fluid",
    }
  end
  if artillerycount > 1 then
    signal = TRAIN_ARTILLERY.."-"..loco.."-any"
    global.TrainSignals[signal] = {
      locomotive = loco,
      wagon = "any",
      type = "artillery",
    }
  end
end

local function initialize(oldVersion, newVersion)
  --log("oldVersion: "..tostring(oldVersion)..", newVersion: "..tostring(newVersion))

  ---- always start with stop updated after a config change, ensure consistent data and filled tables
  global.tick_state = 0 -- index determining on_tick update mode 0: init, 1: stop update, 2: sort requests, 3: parse requests, 4: raise API update events
  global.tick_stop_index = nil
  global.tick_request_index = nil
  global.tick_interval_start = nil -- stores tick of last state 0 for on_dispatcher_updated_event.update_interval

  ---- initialize logger
  global.messageBuffer = {}

  ---- initialize Dispatcher
  global.Dispatcher = global.Dispatcher or {}

  -- set in UpdateAllTrains
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity or 0
  global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity or 0
  global.Dispatcher.availableTrains_total_artillery_capacity = global.Dispatcher.availableTrains_total_artillery_capacity or 0
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}                 -- dictionary [type,name] used to quickly find available items
  global.Dispatcher.Provided_by_Stop = global.Dispatcher.Provided_by_Stop or {} -- dictionary [stopID]; used only by interface
  global.Dispatcher.Requests = global.Dispatcher.Requests or {}                 -- array of requests sorted by priority and age; used to loop over all requests
  global.Dispatcher.Requests_by_Stop = global.Dispatcher.Requests_by_Stop or {} -- dictionary [stopID]; used to keep track of already handled requests
  global.Dispatcher.RequestAge = global.Dispatcher.RequestAge or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}

  ---- initialize stops
  global.LogisticTrainStops = global.LogisticTrainStops or {}

  -- create a list of train signals
  global.TrainSignals = {}
  local lococount = 0
  for _, loco in pairs(game.entity_prototypes) do
     if loco.type == "locomotive" then
        lococount = lococount + 1
        addTrainSignals(loco.name)
     end
  end
  if lococount > 1 then
     addTrainSignals("any")
  end

  -- clean obsolete global
  global.Dispatcher.Requested = nil
  global.Dispatcher.Orders = nil
  global.Dispatcher.OrderAge = nil
  global.Dispatcher.Storage = nil
  global.useRailTanker = nil
  global.tickCount = nil
  global.stopIdStartIndex = nil
  global.Dispatcher.UpdateInterval = nil
  global.Dispatcher.UpdateStopsPerTick = nil
  global.TrainStopNames = nil

  -- update to 1.3.0
  if oldVersion and oldVersion < "01.03.00" then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      stop.minDelivery = nil
      stop.ignoreMinDeliverySize = nil
    end
  end

  -- update to 1.5.0 renamed priority to provider_priority
  if oldVersion and oldVersion < "01.05.00" then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      stop.provider_priority = stop.priority or 0
      stop.priority = nil
    end
    global.Dispatcher.Requests = {}
    global.Dispatcher.RequestAge = {}
  end

  -- update to 1.6.1 migrate locomotiveID to trainID
  if oldVersion and oldVersion < "01.06.01" then
    local locoID_to_trainID = {} -- id dictionary
    local new_availableTrains = {}
    local new_Deliveries = {}
    for _,surface in pairs(game.surfaces) do
      local trains = surface.get_trains()
      for _, train in pairs(trains) do
        -- build dictionary
        local loco = Get_Main_Locomotive(train)
        if loco then
          locoID_to_trainID[loco.unit_number] = train.id
        end
      end
    end
    -- log("locoID_to_trainID: "..serpent.block(locoID_to_trainID))

    for locoID, delivery in pairs(global.Dispatcher.Deliveries) do
      local trainID = locoID_to_trainID[locoID]
      if trainID then
        log("Migrating global.Dispatcher.Deliveries from ["..tostring(locoID).."] to ["..tostring(trainID).."]")
        new_Deliveries[trainID] = delivery
      end
    end
    -- log("new_Deliveries: "..serpent.dump(new_Deliveries))
    global.Dispatcher.Deliveries = new_Deliveries
  end

  -- update to 1.8.0
  if oldVersion and oldVersion < "01.08.00" then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      stop.entity.get_or_create_control_behavior().send_to_train = true
      stop.entity.get_or_create_control_behavior().read_from_train = true
    end
  end

  -- update to 1.12.3 migrate networkID to network_id
  if oldVersion and oldVersion < "01.12.03" then
    for train_id, delivery in pairs(global.Dispatcher.Deliveries) do
      delivery.network_id = delivery.networkID
      delivery.networkID = nil
    end
  end

  -- update to 1.13.1 renamed almost all stop properties
  if oldVersion and oldVersion < "01.13.01" and next(global.LogisticTrainStops) then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      stop.lamp_control = stop.lamp_control or stop.lampControl
      stop.lampControl = nil
      stop.error_code = stop.error_code or stop.errorCode or -1
      stop.errorCode = nil
      stop.active_deliveries = stop.active_deliveries or stop.activeDeliveries or {}
      stop.activeDeliveries = nil
      -- control signals
      stop.is_depot = stop.is_depot or stop.isDepot or false
      stop.isDepot = nil
      stop.depot_priority = stop.depot_priority or 0
      stop.max_carriages = stop.max_carriages or stop.maxTraincars or 0
      stop.maxTraincars = nil
      stop.min_carriages = stop.min_carriages or stop.minTraincars or 0
      stop.minTraincars = nil
      stop.max_trains = stop.max_trains or stop.trainLimit or 0
      stop.trainLimit = nil
      stop.providing_threshold = stop.providing_threshold or stop.provideThreshold or min_provided
      stop.provideThreshold = nil
      stop.providing_threshold_stacks = stop.providing_threshold_stacks or stop.provideStackThreshold or 0
      stop.provideStackThreshold = nil
      stop.provider_priority = stop.provider_priority or stop.providePriority or 0
      stop.providePriority = nil
      stop.requesting_threshold = stop.requesting_threshold or stop.requestThreshold or min_requested
      stop.requestThreshold = nil
      stop.requesting_threshold_stacks = stop.requesting_threshold_stacks or stop.requestStackThreshold or 0
      stop.requestStackThreshold = nil
      stop.requester_priority = stop.requester_priority or stop.requestPriority or 0
      stop.requestPriority = nil
      stop.locked_slots = stop.locked_slots or stop.lockedSlots or 0
      stop.lockedSlots = nil
      stop.no_warnings = stop.no_warnings or stop.noWarnings or false
      stop.noWarnings = nil
      -- parked train data will be set during initializeTrainStops() and updateAllTrains()
      stop.parkedTrain = nil
      stop.parkedTrainID = nil
      stop.parkedTrainFacesStop = nil
    end
  end

  -- update to 1.9.4
  if oldVersion and oldVersion < "01.09.04" then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      stop.lamp_control.teleport({stop.input.position.x, stop.input.position.y}) -- move control under lamp
      stop.input.disconnect_neighbour({target_entity=stop.lamp_control, wire=defines.wire_type.green}) -- reconnect wires
      stop.input.disconnect_neighbour({target_entity=stop.lamp_control, wire=defines.wire_type.red})
      stop.input.connect_neighbour({target_entity=stop.lamp_control, wire=defines.wire_type.green})
      stop.input.connect_neighbour({target_entity=stop.lamp_control, wire=defines.wire_type.red})
    end
  end

end

-- run every time the mod configuration is changed to catch stops from other mods
-- ensures global.LogisticTrainStops contains valid entities
local function initializeTrainStops()
  global.LogisticTrainStops = global.LogisticTrainStops or {}
  -- remove invalidated stops
  for stopID, stop in pairs (global.LogisticTrainStops) do
    if not stop then
      log("[LTN] removing empty stop entry "..tostring(stopID) )
      global.LogisticTrainStops[stopID] = nil
    elseif not(stop.entity and stop.entity.valid) then
      -- stop entity is corrupt/missing remove I/O entities
      log("[LTN] removing corrupt stop "..tostring(stopID) )
      if stop.input and stop.input.valid then
        stop.input.destroy()
      end
      if stop.output and stop.output.valid then
        stop.output.destroy()
      end
      if stop.lamp_control and stop.lamp_control.valid then
        stop.lamp_control.destroy()
      end
      global.LogisticTrainStops[stopID] = nil
    end
  end

  -- add missing ltn stops
  for _, surface in pairs(game.surfaces) do
    local foundStops = surface.find_entities_filtered{type="train-stop"}
    if foundStops then
      for k, stop in pairs(foundStops) do
        -- validate global.LogisticTrainStops
        if ltn_stop_entity_names[stop.name] then
          local ltn_stop = global.LogisticTrainStops[stop.unit_number]
          if ltn_stop then
            if not(ltn_stop.output and ltn_stop.output.valid and ltn_stop.input and ltn_stop.input.valid and ltn_stop.lamp_control and ltn_stop.lamp_control.valid) then
              -- I/O entities are corrupted
              log("[LTN] recreating corrupt stop "..tostring(stop.backer_name) )
              global.LogisticTrainStops[stop.unit_number] = nil
              CreateStop(stop) -- recreate to spawn missing I/O entities

            end
          else
            log("[LTN] recreating stop missing from global.LogisticTrainStops "..tostring(stop.backer_name) )
            CreateStop(stop) -- recreate LTN stops missing from global.LogisticTrainStops
          end
        end
      end
    end
  end
end

-- run every time the mod configuration is changed to catch changes to wagon capacities by other mods
local function updateAllTrains()
  -- reset global lookup tables
  global.StoppedTrains = {} -- trains stopped at LTN stops
  global.StopDistances = {} -- reset station distance lookup table
  global.WagonCapacity = {  --preoccupy table with wagons to ignore at 0 capacity
    ["rail-tanker"] = 0
  }
  global.Dispatcher.availableTrains_total_capacity = 0
  global.Dispatcher.availableTrains_total_fluid_capacity = 0
  global.Dispatcher.availableTrains_total_artillery_capacity = 0
  global.Dispatcher.availableTrains = {}

  -- remove all parked train from logistic stops
  for stopID, stop in pairs (global.LogisticTrainStops) do
    stop.parked_train = nil
    stop.parked_train_id = nil
    UpdateStopOutput(stop)
  end

  -- add still valid trains back to stops
  for force_name, force in pairs(game.forces) do
    local trains = force.get_trains()
    if trains then
      for _, train in pairs(trains) do
        if train.station and ltn_stop_entity_names[train.station.name] then
          TrainArrives(train)
        end
      end
    end
  end
end

-- register events
local function registerEvents()
  local filters_on_built = {{ filter="type", type="train-stop" }}
  local filters_on_mined = {{ filter="type", type="train-stop" }, { filter="rolling-stock" }}

  -- always track built/removed train stops for duplicate name list
  script.on_event( defines.events.on_built_entity, OnEntityCreated, filters_on_built )
  script.on_event( defines.events.on_robot_built_entity, OnEntityCreated, filters_on_built )
  script.on_event( {defines.events.script_raised_built, defines.events.script_raised_revive, defines.events.on_entity_cloned}, OnEntityCreated )


  script.on_event( defines.events.on_pre_player_mined_item, OnEntityRemoved, filters_on_mined )
  script.on_event( defines.events.on_robot_pre_mined, OnEntityRemoved, filters_on_mined )
  script.on_event( defines.events.on_entity_died, function(event) OnEntityRemoved(event, true) end, filters_on_mined )
  script.on_event( defines.events.script_raised_destroy, OnEntityRemoved )

  script.on_event( {defines.events.on_pre_surface_deleted, defines.events.on_pre_surface_cleared }, OnSurfaceRemoved )

  if global.LogisticTrainStops and next(global.LogisticTrainStops) then
    -- script.on_event(defines.events.on_tick, OnTick)
    script.on_nth_tick(nil)
    script.on_nth_tick(dispatcher_nth_tick, OnTick)
    script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
    script.on_event(defines.events.on_train_created, OnTrainCreated)
  end

  -- disable instant blueprint in creative mode
  if remote.interfaces["creative-mode"] and remote.interfaces["creative-mode"]["exclude_from_instant_blueprint"] then
    remote.call("creative-mode", "exclude_from_instant_blueprint", ltn_stop_input)
    remote.call("creative-mode", "exclude_from_instant_blueprint", ltn_stop_output)
    remote.call("creative-mode", "exclude_from_instant_blueprint", ltn_stop_output_controller)
  end

  -- blacklist LTN entities from picker dollies
  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["add_blacklist_name"] then
    for name, offset in pairs(ltn_stop_entity_names) do
      remote.call("PickerDollies", "add_blacklist_name", name, true)
    end
    remote.call("PickerDollies", "add_blacklist_name", ltn_stop_input, true)
    remote.call("PickerDollies", "add_blacklist_name", ltn_stop_output, true)
    remote.call("PickerDollies", "add_blacklist_name", ltn_stop_output_controller, true)
  end
end

script.on_load(function()
  registerEvents()
end)

script.on_init(function()
  -- format version string to "00.00.00"
  local oldVersion, newVersion = nil
  local newVersionString = game.active_mods[MOD_NAME]
  if newVersionString then
    newVersion = format("%02d.%02d.%02d", match(newVersionString, "(%d+).(%d+).(%d+)"))
  end
  initialize(oldVersion, newVersion)
  initializeTrainStops()
  updateAllTrains()
  registerEvents()

  log("[LTN] ".. MOD_NAME.." "..tostring(newVersionString).." initialized.")
end)

script.on_configuration_changed(function(data)
  if data and data.mod_changes[MOD_NAME] then
    -- format version string to "00.00.00"
    local oldVersion, newVersion = nil
    local oldVersionString = data.mod_changes[MOD_NAME].old_version
    if oldVersionString then
      oldVersion = format("%02d.%02d.%02d", match(oldVersionString, "(%d+).(%d+).(%d+)"))
    end
    local newVersionString = data.mod_changes[MOD_NAME].new_version
    if newVersionString then
      newVersion = format("%02d.%02d.%02d", match(newVersionString, "(%d+).(%d+).(%d+)"))
    end

    if oldVersion and oldVersion < "01.01.01" then
      log("[LTN] Migration failed. Migrating from "..tostring(oldVersionString).." to "..tostring(newVersionString).."not supported.")
      printmsg("[LTN] Error: Direct migration from "..tostring(oldVersionString).." to "..tostring(newVersionString).." is not supported. Oldest supported version: 1.1.1")
      return
    else
      initialize(oldVersion, newVersion)
      log("[LTN] Migrating from "..tostring(oldVersionString).." to "..tostring(newVersionString).." complete.")
      printmsg("[LTN] Migration from "..tostring(oldVersionString).." to "..tostring(newVersionString).." complete.")
    end
  end
  initializeTrainStops()
  updateAllTrains()
  registerEvents()
  log("[LTN] ".. MOD_NAME.." "..tostring(game.active_mods[MOD_NAME]).." configuration updated.")
end)
