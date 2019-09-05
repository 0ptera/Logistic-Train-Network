--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

---- INITIALIZATION ----

local function initialize(oldVersion, newVersion)
  --log("oldVersion: "..tostring(oldVersion)..", newVersion: "..tostring(newVersion))

  ---- always start with stop updated after a config change, ensure consistent data and filled tables
  global.tick_state = 0 -- index determining on_tick update mode 0: init, 1: stop update, 2: sort requests, 3: parse requests, 4: raise API update events
  global.stop_update_index = nil

  ---- initialize logger
  global.messageBuffer = {}

  ---- initialize global lookup tables
  global.StopDistances = {} -- reset station distance lookup table
  global.WagonCapacity = { --preoccupy table with wagons to ignore at 0 capacity
    ["rail-tanker"] = 0
  }
  -- set in UpdateAllTrains
  global.StoppedTrains = global.StoppedTrains or {} -- trains stopped at LTN stops

  ---- initialize Dispatcher
  global.Dispatcher = global.Dispatcher or {}

  -- set in UpdateAllTrains
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity or 0
  global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity or 0
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}                 -- dictionary [type,name] used to quickly find available items
  global.Dispatcher.Provided_by_Stop = global.Dispatcher.Provided_by_Stop or {} -- dictionary [stopID]; used only by interface
  global.Dispatcher.Requests = global.Dispatcher.Requests or {}                 -- array of requests sorted by priority and age; used to loop over all requests
  global.Dispatcher.Requests_by_Stop = global.Dispatcher.Requests_by_Stop or {} -- dictionary [stopID]; used to keep track of already handled requests
  global.Dispatcher.RequestAge = global.Dispatcher.RequestAge or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}

  -- clean obsolete global
  global.Dispatcher.Requested = nil
  global.Dispatcher.Orders = nil
  global.Dispatcher.OrderAge = nil
  global.Dispatcher.Storage = nil
  global.useRailTanker = nil
  global.tickCount = nil
  global.stopIdStartIndex = nil --start index for on_tick stop updates
  global.Dispatcher.UpdateInterval = nil      -- set in ResetUpdateInterval()
  global.Dispatcher.UpdateStopsPerTick = nil  -- set in ResetUpdateInterval()

   -- update to 1.4.0
  if oldVersion and oldVersion < "01.04.00" then
    global.Dispatcher.Requests = {} -- wipe existing requests
    global.Dispatcher.RequestAge = {}
  end

  -- update to 1.5.0
  if oldVersion and oldVersion < "01.05.00" then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].providePriority = global.LogisticTrainStops[stopID].priority or 0
      global.LogisticTrainStops[stopID].priority = nil
    end
    global.Dispatcher.Requests = {} -- wipe existing requests
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
        local loco = get_main_locomotive(train)
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

  ---- initialize stops
  global.LogisticTrainStops = global.LogisticTrainStops or {}

  if next(global.LogisticTrainStops) then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].errorCode = global.LogisticTrainStops[stopID].errorCode or -1

      -- update to 1.3.0
      global.LogisticTrainStops[stopID].minDelivery = nil
      global.LogisticTrainStops[stopID].ignoreMinDeliverySize = nil
      global.LogisticTrainStops[stopID].requestThreshold = global.LogisticTrainStops[stopID].requestThreshold or 0
      global.LogisticTrainStops[stopID].provideThreshold = global.LogisticTrainStops[stopID].provideThreshold or 0
      --update to 1.10.2
      global.LogisticTrainStops[stopID].requestStackThreshold = global.LogisticTrainStops[stopID].requestStackThreshold or 0
      global.LogisticTrainStops[stopID].provideStackThreshold = global.LogisticTrainStops[stopID].provideStackThreshold or 0

      -- update to 1.5.0
      global.LogisticTrainStops[stopID].requestPriority = global.LogisticTrainStops[stopID].requestPriority or 0
      global.LogisticTrainStops[stopID].providePriority = global.LogisticTrainStops[stopID].providePriority or 0

      -- update to 1.7.0
      global.LogisticTrainStops[stopID].network_id = global.LogisticTrainStops[stopID].network_id or default_network

      -- update to 1.8.0
      global.LogisticTrainStops[stopID].entity.get_or_create_control_behavior().send_to_train = true
      global.LogisticTrainStops[stopID].entity.get_or_create_control_behavior().read_from_train = true

      -- update to 1.9.4
      stop.lampControl.teleport({stop.input.position.x, stop.input.position.y}) -- move control under lamp
      stop.input.disconnect_neighbour({target_entity=stop.lampControl, wire=defines.wire_type.green}) -- reconnect wires
      stop.input.disconnect_neighbour({target_entity=stop.lampControl, wire=defines.wire_type.red})
      stop.input.connect_neighbour({target_entity=stop.lampControl, wire=defines.wire_type.green})
      stop.input.connect_neighbour({target_entity=stop.lampControl, wire=defines.wire_type.red})
    end
  end

end

-- run every time the mod configuration is changed to catch stops from other mods
-- ensures global.LogisticTrainStops contains valid entities
local function initializeTrainStops()
  global.LogisticTrainStops = global.LogisticTrainStops or {}
  global.TrainStopNames = global.TrainStopNames or {} -- dictionary of all train stops by all mods

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
      if stop.lampControl and stop.lampControl.valid then
        stop.lampControl.destroy()
      end
      global.LogisticTrainStops[stopID] = nil
    end
  end

  -- add missing ltn stops and build stop name list
  for _, surface in pairs(game.surfaces) do
    local foundStops = surface.find_entities_filtered{type="train-stop"}
    if foundStops then
      for k, stop in pairs(foundStops) do

        -- validate global.LogisticTrainStops
        if ltn_stop_entity_names[stop.name] then
          local ltn_stop = global.LogisticTrainStops[stop.unit_number]
          if ltn_stop then
            if not(ltn_stop.output and ltn_stop.output.valid and ltn_stop.input and ltn_stop.input.valid and ltn_stop.lampControl and ltn_stop.lampControl.valid) then
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

        AddStopName(stop.unit_number, stop.backer_name)
      end
    end
  end
end

-- run every time the mod configuration is changed to catch changes to wagon capacities by other mods
local function updateAllTrains()
  global.Dispatcher.availableTrains_total_capacity = 0
  global.Dispatcher.availableTrains_total_fluid_capacity = 0
  global.Dispatcher.availableTrains = {}
  global.StoppedTrains = {}
  -- remove all parked train from logistic stops
  for stopID, stop in pairs (global.LogisticTrainStops) do
    stop.parkedTrain =  nil
    stop.parkedTrainID = nil
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
  -- always track built/removed train stops for duplicate name list
  script.on_event({
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
  }, OnEntityCreated)
  script.on_event({
    defines.events.on_pre_player_mined_item,
    defines.events.on_robot_pre_mined,
    defines.events.on_entity_died,
    script_raised_destroy
  }, OnEntityRemoved)
  script.on_event({
    defines.events.on_pre_surface_deleted,
    defines.events.on_pre_surface_cleared,
  }, OnSurfaceRemoved)

  if global.LogisticTrainStops and next(global.LogisticTrainStops) then
    script.on_event(defines.events.on_tick, OnTick)
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

  initializeTrainStops()
  initialize(oldVersion, newVersion)
  updateAllTrains()
  registerEvents()

  log("[LTN] ".. MOD_NAME.." "..tostring(newVersionString).." initialized.")
end)

script.on_configuration_changed(function(data)
  initializeTrainStops()
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
  updateAllTrains()
  registerEvents()
  log("[LTN] ".. MOD_NAME.." "..tostring(game.active_mods[MOD_NAME]).." configuration updated.")
end)
