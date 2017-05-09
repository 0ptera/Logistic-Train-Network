require "config"
require "interface"

local MOD_NAME = "LogisticTrainNetwork"

local MINTRAINLENGTH = "min-train-length"
local MAXTRAINLENGTH = "max-train-length"
local MAXTRAINS = "ltn-max-trains"
local MINDELIVERYSIZE = "min-delivery-size"
local PRIORITY = "stop-priority"
local IGNOREMINDELIVERYSIZE = "ltn-no-min-delivery-size"
local LOCKEDSLOTS = "ltn-locked-slots"
local ISDEPOT = "ltn-depot"

local ErrorCodes = {
  "red",    -- circuit/signal error
  "pink"    -- duplicate stop name
}
local StopIDList = {} -- stopIDs list for on_tick updates
local stopsPerTick = 1 -- step width of StopIDList

local match = string.match
local ceil = math.ceil
local sort = table.sort

---- BOOTSTRAP ----
do
local function initialize(oldVersion, newVersion)
  --log("oldVersion: "..tostring(oldVersion)..", newVersion: "..tostring(newVersion))
  ---- disable instant blueprint in creative mode
  if game.active_mods["creative-mode"] then
    remote.call("creative-mode", "exclude_from_instant_blueprint", "logistic-train-stop-input")
    remote.call("creative-mode", "exclude_from_instant_blueprint", "logistic-train-stop-output")
    remote.call("creative-mode", "exclude_from_instant_blueprint", "logistic-train-stop-lamp-control")
  end

  ---- initialize logger
  global.messageBuffer = {}

  global.StopDistances = global.StopDistances or {} -- station distance lookup table
  global.stopIdStartIndex = global.stopIdStartIndex or 1 --global index should prevent desync by updating different stops

  ---- initialize Dispatcher
  global.Dispatcher = global.Dispatcher or {}
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}
  global.Dispatcher.Requests = global.Dispatcher.Requests or {}
  global.Dispatcher.RequestAge = global.Dispatcher.RequestAge or {}

  -- clean obsolete global
  global.Dispatcher.Requested = nil
  global.Dispatcher.Orders = nil
  global.Dispatcher.OrderAge = nil
  global.Dispatcher.Storage = nil
  global.useRailTanker = nil

  -- update to 0.4
  if oldVersion and oldVersion < "00.04.00" then
    log("[LTN] Updating Dispatcher.Deliveries to 0.4.0.")
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
      if delivery.shipment == nil then
        if delivery.item and delivery.count then
          global.Dispatcher.Deliveries[trainID].shipment = {[delivery.item] = delivery.count}
        else
          global.Dispatcher.Deliveries[trainID].shipment = {}
        end
      end
    end
  end

  ---- initialize stops
  global.LogisticTrainStops = global.LogisticTrainStops or {}
  local validLampControls = {}

  if next(global.LogisticTrainStops) ~= nil then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].errorCode = global.LogisticTrainStops[stopID].errorCode or 0
      -- update to 0.3.8
      if stop.lampControl == nil then
        local lampctrl = stop.entity.surface.create_entity
        {
          name = "logistic-train-stop-lamp-control",
          position = stop.input.position,
          force = stop.entity.force
        }
        lampctrl.operable = false -- disable gui
        lampctrl.minable = false
        lampctrl.destructible = false -- don't bother checking if alive
        lampctrl.connect_neighbour({target_entity=stop.input, wire=defines.wire_type.green})
        lampctrl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-white"}, count = 1 }}}
        global.LogisticTrainStops[stopID].lampControl = lampctrl
        global.LogisticTrainStops[stopID].input.operable = false
        global.LogisticTrainStops[stopID].input.get_or_create_control_behavior().use_colors = true
        global.LogisticTrainStops[stopID].input.get_or_create_control_behavior().circuit_condition = {condition = {comparator=">",first_signal={type="virtual",name="signal-anything"}}}
      end
      -- update to 1.1.1 remove orphaned lamp controls
      validLampControls[stop.lampControl.unit_number] = true

      -- update to 0.9.5
      global.LogisticTrainStops[stopID].activeDeliveries = global.LogisticTrainStops[stopID].activeDeliveries or {}
      if type(stop.activeDeliveries) ~= "table" then
        stop.activeDeliveries = {}
        for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
          if delivery.from == stop.entity.backer_name or delivery.to == stop.entity.backer_name then
            table.insert(stop.activeDeliveries, trainID)
          end
        end
      end

      -- update to 0.10.2
      global.LogisticTrainStops[stopID].trainLimit = global.LogisticTrainStops[stopID].trainLimit or 0
      global.LogisticTrainStops[stopID].parkedTrainFacesStop = global.LogisticTrainStops[stopID].parkedTrainFacesStop or true
      global.LogisticTrainStops[stopID].lockedSlots = global.LogisticTrainStops[stopID].lockedSlots or 0

      UpdateStopOutput(stop) --make sure output is set
      --UpdateStop(stopID)
    end
    script.on_event(defines.events.on_tick, ticker) --subscribe ticker when train stops exist
  end

  -- update to 1.1.1 remove orphaned lamp controls
  if oldVersion and oldVersion < "01.01.01" then
    local lcDeleted = 0
    for _, surface in pairs(game.surfaces) do
      local lcEntities = surface.find_entities_filtered{name="logistic-train-stop-lamp-control"}
      if lcEntities then
      for k, v in pairs(lcEntities) do
        if not validLampControls[v.unit_number] then
          v.destroy()
          lcDeleted = lcDeleted+1
        end
      end
      end
    end
    log("[LTN] removed "..lcDeleted.. " orphaned lamp control entities.")
  end
end

-- has to run every time the mod configuration is changed to catch stops from other mods
local function buildStopNameList()
  global.TrainStopNames = global.TrainStopNames or {} -- dictionary of all train stops by all mods

  for _, surface in pairs(game.surfaces) do
    local foundStops = surface.find_entities_filtered{type="train-stop"}
    if foundStops then
      for k, stop in pairs(foundStops) do
        AddStopName(stop.unit_number, stop.backer_name)
      end
    end
  end
end

script.on_load(function()
	if global.LogisticTrainStops ~= nil and next(global.LogisticTrainStops) ~= nil then
		script.on_event(defines.events.on_tick, ticker) --subscribe ticker when train stops exist
    for stopID, stop in pairs(global.LogisticTrainStops) do --outputs are not stored in save
      UpdateStopOutput(stop)
      StopIDList[#StopIDList+1] = stopID
    end
    stopsPerTick = ceil(#StopIDList/(dispatcher_update_interval-1))
	end
  log("[LTN] on_load: complete")
end)

script.on_init(function()
  buildStopNameList()

  -- format version string to "00.00.00"
  local oldVersion, newVersion = nil
  local newVersionString = game.active_mods[MOD_NAME]
  if newVersionString then
    newVersion = string.format("%02d.%02d.%02d", string.match(newVersionString, "(%d+).(%d+).(%d+)"))
  end
  initialize(oldVersion, newVersion)
  log("[LTN] on_init: ".. MOD_NAME.." "..tostring(newVersionString).." initialized.")
end)

script.on_configuration_changed(function(data)
  buildStopNameList()
  if data and data.mod_changes[MOD_NAME] then
    -- format version string to "00.00.00"
    local oldVersion, newVersion = nil
    local oldVersionString = data.mod_changes[MOD_NAME].old_version
    if oldVersionString then
      oldVersion = string.format("%02d.%02d.%02d", string.match(oldVersionString, "(%d+).(%d+).(%d+)"))
    end
    local newVersionString = data.mod_changes[MOD_NAME].new_version
    if newVersionString then
      newVersion = string.format("%02d.%02d.%02d", string.match(newVersionString, "(%d+).(%d+).(%d+)"))
    end

    initialize(oldVersion, newVersion)
    log("[LTN] on_configuration_changed: ".. MOD_NAME.." "..tostring(newVersionString).." initialized. Previous version: "..tostring(oldVersionString))
  end
end)

end

---- EVENTS ----

-- add stop to TrainStopNames
function AddStopName(stopID, stopName)
  if stopName then -- is it possible to have stops without backer_name?
    if global.TrainStopNames[stopName] then
      -- prevent adding the same stop multiple times
      local idExists = false
      for i=1, #global.TrainStopNames[stopName] do
        if stopID == global.TrainStopNames[stopName][i] then
          idExists = true
          -- log(stopID.." already exists for "..stopName)
        end
      end
      if not idExists then
        -- multiple stops of same name > add id to the list
        table.insert(global.TrainStopNames[stopName], stopID)
        -- log("added "..stopID.." to "..stopName)
      end
    else
      -- create new name-id entry
      global.TrainStopNames[stopName] = {stopID}
      -- log("creating entry "..stopName..": "..stopID)
    end
  end
end

-- remove stop from TrainStopNames
function RemoveStopName(stopID, stopName)
  if global.TrainStopNames[stopName] and #global.TrainStopNames[stopName] > 1 then
    -- multiple stops of same name > remove id from the list
    for i=#global.TrainStopNames[stopName], 1, -1 do
      if global.TrainStopNames[stopName][i] == stopID then
        table.remove(global.TrainStopNames[stopName], i)
        -- log("removed "..stopID.." from "..stopName)
      end
    end
  else
    -- remove name-id entry
    global.TrainStopNames[stopName] = nil
    -- log("removed entry "..stopName..": "..stopID)
  end
end


do --create stop
local function createStop(entity)
  if global.LogisticTrainStops[entity.unit_number] then
    if log_level >= 1 then printmsg({"ltn-message.error-duplicated-unit_number", entity.unit_number}) end
    return
  end

  local posIn, posOut, rot
  --log("Stop created at "..entity.position.x.."/"..entity.position.y..", orientation "..entity.direction)
  if entity.direction == 0 then --SN
    posIn = {entity.position.x, entity.position.y-1}
    posOut = {entity.position.x-1, entity.position.y-1}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x-3, entity.position.y-3},{entity.position.x-1, entity.position.y+3}} }
    rot = 0
  elseif entity.direction == 2 then --WE
    posIn = {entity.position.x, entity.position.y}
    posOut = {entity.position.x, entity.position.y-1}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x-3, entity.position.y-3},{entity.position.x+3, entity.position.y-1}} }
    rot = 2
  elseif entity.direction == 4 then --NS
    posIn = {entity.position.x-1, entity.position.y}
    posOut = {entity.position.x, entity.position.y}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x+1, entity.position.y-3},{entity.position.x+3, entity.position.y+3}} }
    rot = 4
  elseif entity.direction == 6 then --EW
    posIn = {entity.position.x-1, entity.position.y-1}
    posOut = {entity.position.x-1, entity.position.y}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x-3, entity.position.y+1},{entity.position.x+3, entity.position.y+3}} }
    rot = 6
  else --invalid orientation
    if log_level >= 1 then printmsg({"ltn-message.error-stop-orientation", entity.direction}) end
    entity.destroy()
    return
  end

  local lampctrl = entity.surface.create_entity
  {
    name = "logistic-train-stop-lamp-control",
    position = posIn,
    force = entity.force
  }
  lampctrl.operable = false -- disable gui
  lampctrl.minable = false
  lampctrl.destructible = false -- don't bother checking if alive
  lampctrl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-white"}, count = 1 }}}

  local input, output
  -- revive ghosts (should preserve connections)
  --local ghosts = entity.surface.find_entities_filtered{area={{entity.position.x-2, entity.position.y-2},{entity.position.x+2, entity.position.y+2}} , name="entity-ghost"}
  local ghosts = entity.surface.find_entities({{entity.position.x-1.1, entity.position.y-1.1},{entity.position.x+1.1, entity.position.y+1.1}} )
  for _,ghost in pairs (ghosts) do
    if ghost.name == "entity-ghost" and ghost.ghost_name == "logistic-train-stop-input" then
      --printmsg("reviving ghost input at "..ghost.position.x..", "..ghost.position.y)
      _, input = ghost.revive()
    elseif ghost.name == "entity-ghost" and ghost.ghost_name == "logistic-train-stop-output" then
      --printmsg("reviving ghost output at "..ghost.position.x..", "..ghost.position.y)
      _, output = ghost.revive()
    -- something has built I/O already (e.g.) Creative Mode Instant Blueprint
    elseif ghost.name == "logistic-train-stop-input" then
      input = ghost
      --printmsg("Found existing input at "..ghost.position.x..", "..ghost.position.y)
    elseif ghost.name == "logistic-train-stop-output" then
      output = ghost
      --printmsg("Found existing output at "..ghost.position.x..", "..ghost.position.y)
    end
  end

  if input == nil then -- create new
    input = entity.surface.create_entity
    {
      name = "logistic-train-stop-input",

      position = posIn,
      force = entity.force
    }
  end
  input.operable = false -- disable gui
  input.minable = false
  input.destructible = false -- don't bother checking if alive
  input.connect_neighbour({target_entity=lampctrl, wire=defines.wire_type.green})
  input.get_or_create_control_behavior().use_colors = true
  input.get_or_create_control_behavior().circuit_condition = {condition = {comparator=">",first_signal={type="virtual",name="signal-anything"}}}

  if output == nil then -- create new
    output = entity.surface.create_entity
    {
      name = "logistic-train-stop-output",
      position = posOut,
      direction = rot,
      force = entity.force
    }
  end
  output.operable = false -- disable gui
  output.minable = false
  output.destructible = false -- don't bother checking if alive

  global.LogisticTrainStops[entity.unit_number] = {
    entity = entity,
    input = input,
    output = output,
    lampControl = lampctrl,
    isDepot = false,
    ignoreMinDeliverySize = false,
    trainLimit = 0,
    activeDeliveries = {},  --delivery IDs to/from stop
    errorCode = 0,          --key to errorCodes table
    parkedTrain = nil,
    parkedTrainID = nil
  }
  StopIDList[#StopIDList+1] = entity.unit_number
  UpdateStopOutput(global.LogisticTrainStops[entity.unit_number])

  if #StopIDList == 1 then
    stopsPerTick = 1 --initialize ticker indexes
    global.stopIdStartIndex = 1
    script.on_event(defines.events.on_tick, ticker) --subscribe ticker on first created train stop
    if log_level >= 4 then printmsg("on_tick subscribed", false) end
  end
end

script.on_event(defines.events.on_built_entity, function(event)
  local entity = event.created_entity
  if entity.type == "train-stop" then
     AddStopName(entity.unit_number, entity.backer_name)
  end
  if entity.valid and entity.name == "logistic-train-stop" then
		createStop(entity)
    return
	end

  -- handle adding carriages to parked trains
  if entity.type == "locomotive" or entity.type == "cargo-wagon" or entity.type == "fluid-wagon" then
    entity.train.manual_mode = true
    UpdateTrain(entity.train)
    --entity.train.manual_mode = false
    return
  end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  local entity = event.created_entity
  if entity.type == "train-stop" then
     AddStopName(entity.unit_number, entity.backer_name)
  end
  if entity.valid and entity.name == "logistic-train-stop" then
		createStop(entity)
	end
end)
end

do -- stop removed
function removeStop(entity)
  local stopID = entity.unit_number
  local stop = global.LogisticTrainStops[stopID]

  -- clean lookup tables
  for i=#StopIDList, 1, -1 do
    if StopIDList[i] == stopID then
      table.remove(StopIDList, i)
    end
  end
  for k,v in pairs(global.StopDistances) do
    if k:find(stopID) then
      global.StopDistances[k] = nil
    end
  end

  -- remove available train
  if stop and stop.isDepot and stop.parkedTrainID then
    global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
  end

  -- destroy IO entities
  if stop and stop.input and stop.input.valid and stop.output and stop.output.valid and stop.lampControl and stop.lampControl.valid then
    stop.input.destroy()
    stop.output.destroy()
    stop.lampControl.destroy()
  else
    -- destroy broken IO entities
    local ghosts = entity.surface.find_entities({{entity.position.x-1.1, entity.position.y-1.1},{entity.position.x+1.1, entity.position.y+1.1}} )
    for _,ghost in pairs (ghosts) do
      if ghost.name == "logistic-train-stop-input" or ghost.name == "logistic-train-stop-output" or ghost.name == "logistic-train-stop-lamp-control" then
        --printmsg("removing broken "..ghost.name.." at "..ghost.position.x..", "..ghost.position.y)
        ghost.destroy()
      end
    end
  end

  global.LogisticTrainStops[stopID] = nil

  if StopIDList == nil or #StopIDList == 0 then
    script.on_event(defines.events.on_tick, nil) --unsubscribe ticker on last removed train stop
    if  log_level >= 4 then printmsg("on_tick unsubscribed: Removed last Logistic Train Stop", false) end
  end
end

script.on_event(defines.events.on_preplayer_mined_item, function(event)
  local entity = event.entity
  if entity.type == "train-stop" then
    RemoveStopName(entity.unit_number, entity.backer_name)
  end
  if entity.name == "logistic-train-stop" then
    removeStop(entity)
    return
  end

  -- handle removing carriages from parked trains
  if entity.type == "locomotive" or entity.type == "cargo-wagon" or entity.type == "fluid-wagon" then
    entity.train.manual_mode = true
    UpdateTrain(entity.train)
    --entity.train.manual_mode = false
    return
  end
end)

script.on_event(defines.events.on_robot_pre_mined, function(event)
  local entity = event.entity
  if entity.type == "train-stop" then
    RemoveStopName(entity.unit_number, entity.backer_name)
  end
  if entity.name == "logistic-train-stop" then
    removeStop(entity)
  end
end)

script.on_event(defines.events.on_entity_died, function(event)
  local entity = event.entity
  if entity.type == "train-stop" then
    RemoveStopName(entity.unit_number, entity.backer_name)
  end
  if entity.name == "logistic-train-stop" then
    removeStop(entity)
    return
  end

  -- handle removing carriages from parked trains
  if entity.type == "locomotive" or entity.type == "cargo-wagon" or entity.type == "fluid-wagon" then
    entity.train.manual_mode = true
    UpdateTrain(entity.train)
    --entity.train.manual_mode = false
    return
  end
end)
end


do --train state changed
script.on_event(defines.events.on_train_changed_state, function(event)
  UpdateTrain(event.train)
end)
end


do --rename stop
local function renamedStop(targetID, old_name, new_name)
  -- find identical stop names
  local duplicateName = false
  local renameDeliveries = true
  for stopID, stop in pairs(global.LogisticTrainStops) do
    if stop.entity.backer_name == old_name then
      renameDeliveries = false
    end
  end
  -- rename deliveries if no other stop old_name exists
  if renameDeliveries then
    for trainID, delivery in pairs(global.Dispatcher.Deliveries) do
      if delivery.to == old_name then
        delivery.to = new_name
        --log("renamed delivery.to "..old_name.." > "..new_name)
      end
      if delivery.from == old_name then
        delivery.from = new_name
        --log("renamed delivery.from "..old_name.." > "..new_name)
      end
    end
  end
end

script.on_event(defines.events.on_entity_renamed, function(event)
  local uid = event.entity.unit_number
  local oldName = event.old_name
  local newName = event.entity.backer_name

  if event.entity.type == "train-stop" then
    RemoveStopName(uid, oldName)
    AddStopName(uid, newName)
  end

  if event.entity.name == "logistic-train-stop" then
    --log("(on_entity_renamed) uid:"..uid..", old name: "..oldName..", new name: "..newName)
    renamedStop(uid, oldName, newName)
  end
end)

script.on_event(defines.events.on_pre_entity_settings_pasted, function(event)
  local uid = event.destination.unit_number
  local oldName = event.destination.backer_name
  local newName = event.source.backer_name

  if event.destination.type == "train-stop" then
    RemoveStopName(uid, oldName)
    AddStopName(uid, newName)
  end

  if event.destination.name == "logistic-train-stop" then
    --log("(on_pre_entity_settings_pasted) uid:"..uid..", old name: "..oldName..", new name: "..newName)
    renamedStop(uid, oldName, newName)
  end
end)
end

function ticker(event)
  -- exit when there are no logistic train stops
  local next = next
  if global.LogisticTrainStops == nil or next(global.LogisticTrainStops) == nil then
    script.on_event(defines.events.on_tick, nil)
    if log_level >= 4 then printmsg("no LogisticTrainStops, unsubscribed from on_tick", false) end
    return
  end

  local tick = game.tick
  global.tickCount = global.tickCount or 1

  if global.tickCount == 1 then
    stopsPerTick = ceil(#StopIDList/(dispatcher_update_interval-1)) -- 59 ticks for stop Updates, 60th tick for dispatcher
    global.stopIdStartIndex = 1

    -- clear Dispatcher.Storage
    global.Dispatcher.Provided = {}
    global.Dispatcher.Requests = {}

    -- remove messages older than message_filter_age from messageBuffer
    for bufferedMsg, v in pairs(global.messageBuffer) do
      if (tick - v.tick) > message_filter_age then
        global.messageBuffer[bufferedMsg] = nil
      end
    end
  end

  local stopIdLastIndex = global.stopIdStartIndex + stopsPerTick - 1
  if stopIdLastIndex > #StopIDList then
    stopIdLastIndex = #StopIDList
  end
  for i = global.stopIdStartIndex, stopIdLastIndex, 1 do
    local stopID = StopIDList[i]
    if log_level >= 4 then printmsg(global.tickCount.."/"..tick.." updating stopID "..tostring(stopID), false) end
    UpdateStop(stopID)
  end
  global.stopIdStartIndex = stopIdLastIndex + 1


  if global.tickCount == dispatcher_update_interval then
    global.tickCount = 1
    --clean up deliveries in case train was destroyed or removed
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
      if not delivery.train or not delivery.train.valid then
        if log_level >= 1 then printmsg({"ltn-message.delivery-removed-train-invalid", delivery.from, delivery.to}) end
        removeDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if log_level >= 1 then printmsg({"ltn-message.delivery-removed-timeout", delivery.from, delivery.to, tick-delivery.started}) end
        removeDelivery(trainID)
      end
    end

    -- remove no longer active requests from global.Dispatcher.RequestAge[stopID]
    local newRequestAge = {}
    for _,request in pairs (global.Dispatcher.Requests) do
      local age = global.Dispatcher.RequestAge[request.stopID]
      if age then
        newRequestAge[request.stopID] = age
      end
    end
    global.Dispatcher.RequestAge = newRequestAge

    -- sort requests by age
    sort(global.Dispatcher.Requests, function(a, b)
        return a.age < b.age
      end)

    -- find best provider, merge shipments, find train, generate delivery, reset age
    if next(global.Dispatcher.availableTrains) ~= nil then -- no need to parse requests without available trains
      for reqIndex, request in pairs (global.Dispatcher.Requests) do

        local delivery = ProcessRequest(request)
        if delivery then
          break
        end

      end
    end

  else -- dispatcher update
      global.tickCount = global.tickCount + 1
  end
end


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

function removeDelivery(trainID)
  if global.Dispatcher.Deliveries[trainID] then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      for i=#stop.activeDeliveries, 1, -1 do --trainID should be unique => checking matching stop name not required
        if stop.activeDeliveries[i] == trainID then
          table.remove(stop.activeDeliveries, i)
        end
      end
    end
    global.Dispatcher.Deliveries[trainID] = nil
  end
end

-- return new schedule_record
-- itemlist = {first_signal.type, first_signal.name, constant}
function NewScheduleRecord(stationName, condType, condComp, itemlist, countOverride)
  local record = {station = stationName, wait_conditions = {}}

  if condType == "item_count" then
    -- write itemlist to conditions
    for i=1, #itemlist do
      local condFluid = nil
      if itemlist[i].type == "fluid" then
        condFluid = "fluid_count"
      end

      -- make > into >=
      if condComp == ">" then
        countOverride = itemlist[i].count - 1
      end

      local cond = {comparator = condComp, first_signal = {type = itemlist[i].type, name = itemlist[i].name}, constant = countOverride or itemlist[i].count}
      record.wait_conditions[#record.wait_conditions+1] = {type = condFluid or condType, compare_type = "and", condition = cond }
    end

    if finish_loading then -- let inserters finish
      record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "and", ticks = 120 }
    end

    if stop_timeout > 0 then -- if stop_timeout is set add inactivity condition
      record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "or", ticks = stop_timeout } -- send stuck trains away
    end
  elseif condType == "inactivity" then
    record.wait_conditions[#record.wait_conditions+1] = {type = condType, compare_type = "and", ticks = condComp }
  end
  return record
end


do --ProcessRequest
-- return all stations providing item, ordered by priority and item-count
local function GetProviders(force, item, min_count, min_length, max_length)
  local stations = {}
  local providers = global.Dispatcher.Provided[item]
  if not providers then
    return nil
  end
  -- get all providing stations
  for stopID, count in pairs (providers) do
  if not(stopID == "sumCount" or stopID == "sumStops") then --skip sumCount, sumStops
    local stop = global.LogisticTrainStops[stopID]
    --log("requester train length: "..min_length.."-"..max_length..", provider train length: "..stop.minTraincars.."-"..stop.maxTraincars)
    if stop and stop.entity.force.name == force.name
    and (stop.minTraincars == 0 or max_length == 0 or stop.minTraincars <= max_length)
    and (stop.maxTraincars == 0 or min_length == 0 or stop.maxTraincars >= min_length) then --check if provider can actually service trains from requester
      local activeDeliveryCount = #stop.activeDeliveries
      if count > 0 and (use_Best_Effort or stop.ignoreMinDeliverySize or count >= min_count) and (stop.trainLimit == 0 or activeDeliveryCount < stop.trainLimit) then
        if log_level >= 4 then printmsg("(GetProviders): found ".. count .."/"..min_count.." ".. item.." at "..stop.entity.backer_name.." priority: "..stop.priority.." minTraincars: "..stop.minTraincars.." maxTraincars: "..stop.maxTraincars.." locked Slots: "..stop.lockedSlots, false) end
        stations[#stations +1] = {entity = stop.entity, priority = stop.priority, activeDeliveryCount = activeDeliveryCount, item = item, count = count, minTraincars = stop.minTraincars, maxTraincars = stop.maxTraincars, lockedSlots = stop.lockedSlots}
      end
    end
  end
  end
  -- sort by priority and count
  sort(stations, function(a, b)
      if a.activeDeliveryCount ~= b.activeDeliveryCount then --sort by #deliveries 1st
        return a.activeDeliveryCount < b.activeDeliveryCount
      end
      if a.priority ~= b.priority then --sort by priority 2nd
          return a.priority > b.priority
      end
      return a.count > b.count --finally sort by item count
    end)
  return stations
end

local function GetStationDistance(stationA, stationB)
  local stationPair = stationA.unit_number..","..stationB.unit_number
  if global.StopDistances[stationPair] then
    --log(stationPair.." found, distance: "..global.StopDistances[stationPair])
    return global.StopDistances[stationPair]
  else
    local dist = GetDistance(stationA.position, stationB.position)
    global.StopDistances[stationPair] = dist
    --log(stationPair.." calculated, distance: "..dist)
    return dist
  end
end

local InventoryLookup = { --preoccupy table with wagons to ignore at 0 capacity
  ["rail-tanker"] = 0
}

local function getInventorySize(entity)
  local capacity = 0
  if entity.type == "cargo-wagon" then
    capacity = entity.prototype.get_inventory_size(defines.inventory.cargo_wagon)
  elseif entity.type == "fluid-wagon" then
    for n=1, #entity.fluidbox do
      capacity = capacity + entity.fluidbox.get_capacity(n)
    end
  end
  --log("(getInventorySize) adding "..entity.name.." capcacity: "..capacity)
  InventoryLookup[entity.name] = capacity
  return capacity
end


local function GetTrainInventorySize(train, type, reserved)
  local inventorySize = 0
  local fluidCapacity = 0
  if not train.valid then
    return inventorySize
  end

  --log("Train "..GetTrainName(train).." carriages: "..#train.carriages..", cargo_wagons: "..#train.cargo_wagons)
  for _,wagon in pairs (train.carriages) do
    if wagon.type ~= "locomotive" then
      local capacity = InventoryLookup[wagon.name] or getInventorySize(wagon)
      --log("(GetTrainInventorySize) wagon.name:"..wagon.name.." capacity:"..capacity)
      if wagon.type == "fluid-wagon" then
        fluidCapacity = fluidCapacity + capacity
      else
        inventorySize = inventorySize + capacity - reserved
      end
    end
  end
  if type == "fluid" then
    return fluidCapacity
  end
  return inventorySize
end

-- return available train with smallest suitable inventory or largest available inventory
-- if minTraincars is set, number of locos + wagons has to be bigger
-- if maxTraincars is set, number of locos + wagons has to be smaller
local function GetFreeTrain(nextStop, minTraincars, maxTraincars, type, size, reserved)
  local train = nil
  if minTraincars == nil or minTraincars < 0 then minTraincars = 0 end
  if maxTraincars == nil or maxTraincars < 0 then maxTraincars = 0 end
  local largestInventory = 0
  local smallestInventory = 0
  local smallestDistance = 0
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    if DispTrain.valid and DispTrain.station then
      local locomotive = GetMainLocomotive(DispTrain)
      if locomotive.force.name == nextStop.force.name then -- train force matches
        local inventorySize = 0
        if (minTraincars == 0 or #DispTrain.carriages >= minTraincars) and (maxTraincars == 0 or #DispTrain.carriages <= maxTraincars) then -- train length fits
          -- get total inventory of train for requested item type
          inventorySize = GetTrainInventorySize(DispTrain, type, reserved)
          if inventorySize >= size then
            -- train can be used for delivery
            if inventorySize <= smallestInventory or smallestInventory == 0 then
              local distance = GetStationDistance(DispTrain.station, nextStop)
              if distance < smallestDistance or smallestDistance == 0 then
                smallestDistance = distance
                smallestInventory = inventorySize
                train = {id=DispTrainKey, inventorySize=inventorySize}
                if log_level >= 4 then printmsg("(GetFreeTrain): found train "..locomotive.backer_name..", length: "..minTraincars.."<="..#DispTrain.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance, false) end
              end
            end

          elseif smallestInventory == 0 and inventorySize > 0 and (inventorySize >= largestInventory or largestInventory == 0) then
            -- store biggest available train
            local distance = GetStationDistance(DispTrain.station, nextStop)
            if distance < smallestDistance or smallestDistance == 0 then
              smallestDistance = distance
              largestInventory = inventorySize
              train = {id=DispTrainKey, inventorySize=inventorySize}
              if log_level >= 4 then printmsg("(GetFreeTrain): largest available train "..locomotive.backer_name..", length: "..minTraincars.."<="..#DispTrain.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance, false) end
            end
          end

        end --train length fits
      end
    else
      -- remove invalid train
      global.Dispatcher.availableTrains[DispTrainKey] = nil
    end
  end
  return train
end


-- creates a single delivery from a given request
-- returns generated delivery or nil
function ProcessRequest(request)
  local stopID = request.stopID
  local requestStation = global.LogisticTrainStops[stopID]

  if not requestStation or not (requestStation.entity and requestStation.entity.valid) then
    return nil -- station was removed since request was generated
  end

  local minDelivery = requestStation.minDelivery
  local maxTraincars = requestStation.maxTraincars
  local minTraincars = requestStation.minTraincars
  local orders = {}
  local deliveries = nil

  if requestStation.trainLimit > 0 and #requestStation.activeDeliveries >= requestStation.trainLimit then
    if log_level >= 4 then printmsg(requestStation.entity.backer_name.." skipped: "..#requestStation.activeDeliveries.." >= "..requestStation.trainLimit) end
    return nil -- reached train limit
  end

  -- find providers for requested items
  for item, count in pairs (request.itemlist) do
    -- split merged key into type & name
    local itype, iname = match(item, "([^,]+),([^,]+)")
    if not (itype and iname and (game.item_prototypes[iname] or game.fluid_prototypes[iname])) then
      if log_level >= 1 then printmsg({"ltn-message.error-parse-item", item}) end
      goto skipRequestItem
    end

    local localname
    if itype=="fluid" then
      localname = game.fluid_prototypes[iname].localised_name
    else
      localname = game.item_prototypes[iname].localised_name
    end

    -- get providers ordered by priority
    local providers = GetProviders(requestStation.entity.force, item, minDelivery, minTraincars, maxTraincars)
    if not providers or #providers < 1 then
      if log_level >= 2 then printmsg({"ltn-message.no-provider-found", localname}, true) end
      goto skipRequestItem
    end

    -- only one delivery is created so use only the best provider
    local providerStation = providers[1]
    if log_level >= 3 then printmsg({"ltn-message.provider-found", providerStation.entity.backer_name, tostring(providerStation.priority), tostring(providerStation.activeDeliveryCount), providerStation.count, localname}, true)
    elseif log_level >= 4 then
      for n, provider in pairs (providers) do
        printmsg("Provider["..n.."] "..provider.entity.backer_name..": Priority "..tostring(provider.priority)..", "..tostring(provider.activeDeliveryCount).." deliveries, "..tostring(provider.count).." "..localname.." available.")
      end
    end

    -- limit count to availability of highest priority provider
    local deliverySize = count
    if count > providerStation.count then
      deliverySize = providerStation.count
    end
    local stacks = deliverySize -- for fluids stack = tanker capacity
    if itype == "item" then
      stacks = ceil(deliverySize / game.item_prototypes[iname].stack_size) -- calculate amount of stacks item count will occupy
    end

    -- maxTraincars = shortest set max-train-length
    if providerStation.maxTraincars > 0 and (providerStation.maxTraincars < requestStation.maxTraincars or requestStation.maxTraincars == 0) then
      maxTraincars = providerStation.maxTraincars
    end
    -- minTraincars = longest set min-train-length
    if providerStation.minTraincars > 0 and (providerStation.minTraincars > requestStation.minTraincars or requestStation.minTraincars == 0) then
      minTraincars = providerStation.minTraincars
    end

    -- merge into existing shipments
    local to = requestStation.entity.backer_name
    local from = providerStation.entity.backer_name
    local toID = requestStation.entity.unit_number
    local fromID = providerStation.entity.unit_number
    local insertnew = true
    local loadingList = {type=itype, name=iname, localname=localname, count=deliverySize, stacks=stacks}

    -- try inserting into existing order
    for i=1, #orders do
      if orders[i].fromID == fromID and itype == "item" and orders[i].loadingList[1].type == "item" then
        orders[i].loadingList[#orders[i].loadingList+1] = loadingList
        orders[i].totalStacks = orders[i].totalStacks + stacks
        insertnew = false
        if log_level >= 4 then  printmsg("inserted into order "..i.."/"..#orders.." "..from.." >> "..to..": "..deliverySize.." in "..stacks.." stacks "..itype..","..iname.." min length: "..minTraincars.." max length: "..maxTraincars, false) end
        break
      end
    end
    -- create new order for fluids and different provider-requester pairs
    if insertnew then
      orders[#orders+1] = {toID=toID, fromID=fromID, minDelivery=minDelivery, minTraincars=minTraincars, maxTraincars=maxTraincars, totalStacks=stacks, lockedSlots=providerStation.lockedSlots, loadingList={loadingList} }
      if log_level >= 4 then  printmsg("added new order "..#orders.." "..from.." >> "..to..": "..deliverySize.." in "..stacks.." stacks "..itype..","..iname.." min length: "..minTraincars.." max length: "..maxTraincars, false) end
    end

    ::skipRequestItem:: -- use goto since lua doesn't know continue
  end -- find providers for requested items


  -- find trains for orders
  for orderIndex=1, #orders do
    local loadingList = orders[orderIndex].loadingList
    local totalStacks = orders[orderIndex].totalStacks
    local lockedSlots = orders[orderIndex].lockedSlots
    local minTraincars = orders[orderIndex].minTraincars
    local maxTraincars = orders[orderIndex].maxTraincars

    -- get station names
    local toStop = global.LogisticTrainStops[orders[orderIndex].toID]
    local fromStop = global.LogisticTrainStops[orders[orderIndex].fromID]
    if not toStop or not fromStop then
      if log_level >= 1 then printmsg({"ltn-message.error-no-stop"}) end
      goto skipOrder
    end
    local to = toStop.entity.backer_name
    local from = fromStop.entity.backer_name

    -- find train
    local train = GetFreeTrain(fromStop.entity, minTraincars, maxTraincars, loadingList[1].type, totalStacks, lockedSlots)
    if not train then
      if log_level >= 3 then
        if #loadingList == 1 then
          printmsg({"ltn-message.no-train-found", tostring(minTraincars), tostring(maxTraincars), loadingList[1].localname}, true)
        else
          printmsg({"ltn-message.no-train-found-merged", tostring(minTraincars), tostring(maxTraincars), tostring(totalStacks)}, true)
        end
      end
      goto skipOrder
    end
    if log_level >= 3 then printmsg({"ltn-message.train-found", tostring(train.inventorySize), tostring(totalStacks)}) end

    -- recalculate delivery amount to fit in train
    if train.inventorySize < totalStacks then
      -- recalculate partial shipment
      if loadingList[1].type == "fluid" then
        -- fluids are simple
        loadingList[1].count = train.inventorySize
      else
        -- items need a bit more math
        for i=#loadingList, 1, -1 do
          if totalStacks - loadingList[i].stacks < train.inventorySize then
            -- remove stacks until it fits in train
            loadingList[i].stacks = loadingList[i].stacks - (totalStacks - train.inventorySize)
            totalStacks = train.inventorySize
            local newcount = loadingList[i].stacks * game.item_prototypes[loadingList[i].name].stack_size
            loadingList[i].count = newcount
            break
          else
            -- remove item and try again
            totalStacks = totalStacks - loadingList[i].stacks
            table.remove(loadingList, i)
          end
        end
      end
    end

    if log_level >= 4 then
      for i=1, #loadingList do
        printmsg("Creating Delivery: "..loadingList[i].count.." in "..loadingList[i].stacks.." stacks "..loadingList[i].type..","..loadingList[i].name..", "..from.." >> "..to, false)
      end
    elseif log_level >= 2 then
      if #loadingList == 1 then
        printmsg({"ltn-message.creating-delivery", from, to, loadingList[1].count, loadingList[1].localname})
      else
        printmsg({"ltn-message.creating-delivery-merged", from, to, totalStacks})
      end
    end

    -- create schedule
    local selectedTrain = global.Dispatcher.availableTrains[train.id]
    local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]
    local schedule = {current = 1, records = {}}
    schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "inactivity", 120)
    schedule.records[2] = NewScheduleRecord(from, "item_count", ">", loadingList)
    schedule.records[3] = NewScheduleRecord(to, "item_count", "=", loadingList, 0)
    selectedTrain.schedule = schedule

    -- store delivery
    local delivery = {}
    for i=1, #loadingList do
      delivery[loadingList[i].type..","..loadingList[i].name] = loadingList[i].count
    end
    global.Dispatcher.Deliveries[train.id] = {train=selectedTrain, started=game.tick, from=from, to=to, shipment=delivery}
    global.Dispatcher.availableTrains[train.id] = nil

    -- move Request to the back of the queue
    global.Dispatcher.RequestAge[orders[orderIndex].toID] = nil

    -- set lamps on stations to yellow
    -- trains will pick a stop by their own logic so we have to parse by name
    for stopID, stop in pairs (global.LogisticTrainStops) do
      if stop.entity.backer_name == from or stop.entity.backer_name == to then
        table.insert(global.LogisticTrainStops[stopID].activeDeliveries, train.id)
      end
    end

    -- stop after first delivery was created
    do return delivery end -- explicit block needed ... lua really sucks ...

    ::skipOrder:: -- use goto since lua doesn't know continue
  end --for orders

  return nil
end

end


------------------------------------- STOP FUNCTIONS -------------------------------------

-- update stop output when train enters/leaves
function UpdateTrain(train)
  local trainID = GetTrainID(train)
  local trainName = GetTrainName(train)

  if not trainID then --train has no locomotive
    if log_level >= 4 then printmsg("Notice (UpdateTrain): couldn't assign train id", false) end
    --TODO: Update all stops?
    return
  end

  if train.valid and train.manual_mode == false and train.state == defines.train_state.wait_station and train.station ~= nil and train.station.name == "logistic-train-stop" then
    local stopID = train.station.unit_number
    local stop = global.LogisticTrainStops[stopID]
    if stop then
      stop.parkedTrain = train
      stop.parkedTrainID = trainID

      if log_level >= 3 then printmsg({"ltn-message.train-arrived", trainName, stop.entity.backer_name}) end

      local frontDistance = GetDistance(train.front_stock.position, train.station.position)
      local backDistance = GetDistance(train.back_stock.position, train.station.position)
      if log_level >= 4 then printmsg("Front Stock Distance: "..frontDistance..", Back Stock Distance: "..backDistance, false) end
      if frontDistance > backDistance then
        stop.parkedTrainFacesStop = false
      else
        stop.parkedTrainFacesStop = true
      end

      if stop.isDepot then
        -- remove delivery
        removeDelivery(trainID)

        -- make train available for new deliveries
        global.Dispatcher.availableTrains[trainID] = train

        -- reset schedule
        local schedule = {current = 1, records = {}}
        schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "inactivity", 300)
        train.schedule = schedule
        if stop.errorCode == 0 then
          setLamp(stopID, "blue")
        end
      end

      UpdateStopOutput(stop)
      return
    end

  else --remove train from station
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stop.parkedTrainID == trainID then
        if stop.isDepot then
          global.Dispatcher.availableTrains[trainID] = nil
          if stop.errorCode == 0 then
            setLamp(stopID, "green")
          end
        else -- normal stop
          local delivery = global.Dispatcher.Deliveries[trainID]
          if delivery then
            -- remove delivery from stop
            for i=#stop.activeDeliveries, 1, -1 do
              if stop.activeDeliveries[i] == trainID then
                table.remove(stop.activeDeliveries, i)
              end
            end

            if delivery.from == stop.entity.backer_name then
              -- update delivery counts to train inventory
              local inventory = train.get_contents()
              for item, count in pairs (delivery.shipment) do
                local itype, iname = match(item, "([^,]+),([^,]+)")
                if itype and iname then
                  -- workaround for get_contents() not returning fluids
                  local traincount = inventory[iname] or GetFluidCount(stop.parkedTrain, iname)
                  if log_level >= 4 then printmsg("(UpdateTrain): updating delivery after train left "..delivery.from..", "..item.." "..tostring(traincount) ) end
                  delivery.shipment[item] = traincount
                end
              end
              delivery.pickupDone = true -- remove reservations from this delivery
            elseif global.Dispatcher.Deliveries[trainID].to == stop.entity.backer_name then
              -- remove completed delivery
              global.Dispatcher.Deliveries[trainID] = nil
            end
          end
        end

        -- remove train reference
        stop.parkedTrain = nil
        stop.parkedTrainID = nil
        if log_level >= 3 then printmsg({"ltn-message.train-left", trainName, stop.entity.backer_name}) end

        UpdateStopOutput(stop)
        return
      end
    end
  end
end

do --UpdateStop
local validSignals = {
  [MINTRAINLENGTH] = true,
  [MAXTRAINLENGTH] = true,
  [MAXTRAINS] = true,
  [MINDELIVERYSIZE] = true,
  [PRIORITY] = true,
  [IGNOREMINDELIVERYSIZE] = true,
  [LOCKEDSLOTS] = true,
  [ISDEPOT] = true
}
local function getCircuitValues(entity)
  local greenWire = entity.get_circuit_network(defines.wire_type.green)
  local redWire =  entity.get_circuit_network(defines.wire_type.red)
  local items = {}
  if greenWire and greenWire.signals then
    for _, v in pairs(greenWire.signals) do
      if v.signal.type ~= "virtual" or validSignals[v.signal.name] then
        items[v.signal.type..","..v.signal.name] = v.count
      end
    end
  end
  if redWire and redWire.signals then
    for _, v in pairs(redWire.signals) do
      if v.signal.type ~= "virtual" or validSignals[v.signal.name] then
        if items[v.signal.type..","..v.signal.name] ~= nil then
          items[v.signal.type..","..v.signal.name] = items[v.signal.type..","..v.signal.name] + v.count
        else
          items[v.signal.type..","..v.signal.name] = v.count
        end
      end
    end
  end
  return items
end

-- return true if stop, output, lamp are on same logic network
local function detectShortCircuit(checkStop)
  local scdetected = false
  local networks = {}
  local entities = {checkStop.entity, checkStop.output, checkStop.input}

  for k, entity in pairs(entities) do
    local greenWire = entity.get_circuit_network(defines.wire_type.green)
    if greenWire then
      if networks[greenWire.network_id] then
        scdetected = true
      else
        networks[greenWire.network_id] = entity.unit_number
      end
    end
    local redWire =  entity.get_circuit_network(defines.wire_type.red)
    if redWire then
      if networks[redWire.network_id] then
        scdetected = true
      else
        networks[redWire.network_id] = entity.unit_number
      end
    end
  end

  return scdetected
end

-- update stop input signals
function UpdateStop(stopID)
  local stop = global.LogisticTrainStops[stopID]

  -- remove invalid stops
  if not stop or not (stop.entity and stop.entity.valid) or not (stop.input and stop.input.valid) or not (stop.output and stop.output.valid) or not (stop.lampControl and stop.lampControl.valid) then
    if log_level >= 1 then printmsg({"ltn-message.error-invalid-stop", stopID}) end
    for i=#StopIDList, 1, -1 do
      if StopIDList[i] == stopID then
        table.remove(StopIDList, i)
      end
    end
    return
  end

  -- remove invalid trains
  if stop.parkedTrain and not stop.parkedTrain.valid then
    global.LogisticTrainStops[stopID].parkedTrain = nil
    global.LogisticTrainStops[stopID].parkedTrainID = nil
  end

  -- get circuit values
  local circuitValues = getCircuitValues(stop.input)
  if not circuitValues then
    return
  end

  -- read configuration signals and remove them from the signal list (should leave only item and fluid signal types)
  local isDepot = circuitValues["virtual,"..ISDEPOT] or 0
  circuitValues["virtual,"..ISDEPOT] = nil
  local minTraincars = circuitValues["virtual,"..MINTRAINLENGTH] or 0
  circuitValues["virtual,"..MINTRAINLENGTH] = nil
  local maxTraincars = circuitValues["virtual,"..MAXTRAINLENGTH] or 0
  circuitValues["virtual,"..MAXTRAINLENGTH] = nil
  local trainLimit = circuitValues["virtual,"..MAXTRAINS] or 0
  circuitValues["virtual,"..MAXTRAINS] = nil
  local minDelivery = circuitValues["virtual,"..MINDELIVERYSIZE] or min_delivery_size
  circuitValues["virtual,"..MINDELIVERYSIZE] = nil
  local priority = circuitValues["virtual,"..PRIORITY] or 0
  circuitValues["virtual,"..PRIORITY] = nil
  local ignoreMinDeliverySize = circuitValues["virtual,"..IGNOREMINDELIVERYSIZE] or 0
  circuitValues["virtual,"..IGNOREMINDELIVERYSIZE] = nil
  local lockedSlots = circuitValues["virtual,"..LOCKEDSLOTS] or 0
  circuitValues["virtual,"..LOCKEDSLOTS] = nil
  -- check if it's a depot
  if isDepot > 0 then
    stop.isDepot = true

    -- reset duplicate name error
    if stop.errorCode == 2 then
      stop.errorCode = 0
    end

    -- add parked train to available trains
    if stop.parkedTrainID and stop.parkedTrain.valid and not global.Dispatcher.Deliveries[stop.parkedTrainID] then
      global.Dispatcher.availableTrains[stop.parkedTrainID] = stop.parkedTrain
    end

    if detectShortCircuit(stop) then
      -- signal error
      global.LogisticTrainStops[stopID].errorCode = 1
      setLamp(stopID, ErrorCodes[1])
    else
      -- signal error fixed, depots ignore all other errors
      global.LogisticTrainStops[stopID].errorCode = 0

      global.LogisticTrainStops[stopID].minDelivery = nil
      global.LogisticTrainStops[stopID].minTraincars = minTraincars
      global.LogisticTrainStops[stopID].maxTraincars = maxTraincars
      global.LogisticTrainStops[stopID].priority = 0
      global.LogisticTrainStops[stopID].ignoreMinDeliverySize = false
      if stop.parkedTrain then
        setLamp(stopID, "blue")
      else
        setLamp(stopID, "green")
      end
    end

  -- not a depot > check if the name is unique
  elseif #global.TrainStopNames[stop.entity.backer_name] == 1 then
    stop.isDepot = false

    -- reset duplicate name error
    if stop.errorCode == 2 then
      stop.errorCode = 0
    end

    -- remove parked train from available trains
    if stop.parkedTrainID then
      global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
    end

    -- update input signals of stop
    local requestItems = {}
    global.Dispatcher.RequestAge[stopID] = global.Dispatcher.RequestAge[stopID] or game.tick

    if detectShortCircuit(stop) then
      -- signal error
      global.LogisticTrainStops[stopID].errorCode = 1
      setLamp(stopID, ErrorCodes[1])
    else
      -- signal error fixed
      global.LogisticTrainStops[stopID].errorCode = 0
      for item, count in pairs (circuitValues) do
        for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
          local deliverycount = delivery.shipment[item]
          if deliverycount then
            if stop.parkedTrain and stop.parkedTrainID == trainID then
              -- calculate items +- train inventory
              local itype, iname = match(item, "([^,]+),([^,]+)")
              if itype and iname then
                local traincount = 0
                if itype == "fluid" then
                  -- traincount = stop.parkedTrain.get_fluid_count(iname)
                  -- workaround for not existing API call get_fluid_count(name)
                  traincount = GetFluidCount(stop.parkedTrain, iname)
                else
                  traincount = stop.parkedTrain.get_item_count(iname)
                end

                if delivery.to == stop.entity.backer_name then
                  if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating requested count with train inventory: "..item.." "..count.." + "..traincount) end
                  count = count + traincount
                elseif delivery.from == stop.entity.backer_name then
                  if traincount <= deliverycount then
                    if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating provided count with train inventory: "..item.." "..count.." - "..deliverycount - traincount) end
                    count = count - (deliverycount - traincount)
                  else --train loaded more than delivery
                    if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating delivery count with overloaded train inventory: "..item.." "..traincount) end
                    -- update delivery to new size
                    global.Dispatcher.Deliveries[trainID].shipment[item] = traincount
                  end
                  if count < 0 then count = 0 end --make sure we don't turn it into a request
                end
              end

            else
              -- calculate items +- deliveries
              if delivery.to == stop.entity.backer_name then
                if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating requested count with delivery: "..item.." "..count.." + "..deliverycount) end
                count = count + deliverycount
              elseif delivery.from == stop.entity.backer_name and not delivery.pickupDone then
                if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating provided count with delivery: "..item.." "..count.." - "..deliverycount) end
                count = count - deliverycount
                if count < 0 then count = 0 end --make sure we don't turn it into a request
              end

            end
          end
        end -- for delivery

        -- update Dispatcher Storage
        if count > 0 then
           local provided = global.Dispatcher.Provided[item] or {}
          provided[stopID] = count
          if provided.sumCount then
            provided.sumCount = provided.sumCount + count
          else
            provided.sumCount = count
          end
          if provided.sumStops then
            provided.sumStops = provided.sumStops + 1
          else
            provided.sumStops = 1
          end
          global.Dispatcher.Provided[item] = provided
          if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." provides "..item.." "..count, false) end
        elseif count*-1 >= minDelivery then
          count = count * -1
          requestItems[item] = count
          if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." requested "..item.." "..count..", age: "..global.Dispatcher.RequestAge[stopID].."/"..game.tick, false) end
        end

      end -- for circuitValues

      global.LogisticTrainStops[stopID].minDelivery = minDelivery
      global.LogisticTrainStops[stopID].minTraincars = minTraincars
      global.LogisticTrainStops[stopID].maxTraincars = maxTraincars
      global.LogisticTrainStops[stopID].trainLimit = trainLimit
      global.LogisticTrainStops[stopID].priority = priority
      if ignoreMinDeliverySize > 0 then
        global.LogisticTrainStops[stopID].ignoreMinDeliverySize = true
      else
        global.LogisticTrainStops[stopID].ignoreMinDeliverySize = false
      end
      global.LogisticTrainStops[stopID].lockedSlots = lockedSlots

      -- create Requests {stopID, age, itemlist={[item], count}}
      global.Dispatcher.Requests[#global.Dispatcher.Requests+1] = {age = global.Dispatcher.RequestAge[stopID], stopID = stopID, itemlist = requestItems}

      if #stop.activeDeliveries > 0 then
        setLamp(stopID, "yellow")
      else
        setLamp(stopID, "green")
      end

    end --if detectShortCircuit(stop)

  else
    -- duplicate stop name error
    global.LogisticTrainStops[stopID].errorCode = 2
    setLamp(stopID, ErrorCodes[2])
  end
end

end

do --setLamp
local ColorLookup = {
  red = "signal-red",
  green = "signal-green",
  blue = "signal-blue",
  yellow = "signal-yellow",
  pink = "signal-pink",
  cyan = "signal-cyan",
  white = "signal-white",
  grey = "signal-grey",
  black = "signal-black"
}
function setLamp(stopID, color)
  if ColorLookup[color] and global.LogisticTrainStops[stopID] then
    global.LogisticTrainStops[stopID].lampControl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name=ColorLookup[color]}, count = 1 }}}
    return true
  end
  return false
end
end

function UpdateStopOutput(trainStop)
  local signals = {}
  local index = 1

	if trainStop.parkedTrain and trainStop.parkedTrain.valid then
    -- get train composition
    local carriages = trainStop.parkedTrain.carriages
		local carriagesDec = {}
		if trainStop.parkedTrainFacesStop then --train faces forwards >> iterate normal
      for i=1, #carriages do
        local name = carriages[i].name
        if carriagesDec[name] then
          carriagesDec[name] = carriagesDec[name] + 2^(i-1)
        else
          carriagesDec[name] = 2^(i-1)
        end
      end
    else --train faces backwards >> iterate backwards
      n = 0
      for i=#carriages, 1, -1 do
        local name = carriages[i].name
        if carriagesDec[name] then
          carriagesDec[name] = carriagesDec[name] + 2^n
        else
          carriagesDec[name] = 2^n
        end
        n=n+1
      end
    end

    for k ,v in pairs (carriagesDec) do
      table.insert(signals, {index = index, signal = {type="virtual",name="LTN-"..k}, count = v })
      index = index+1
    end

    if not trainStop.isDepot then
      -- Update normal stations
      local conditions = trainStop.parkedTrain.schedule.records[trainStop.parkedTrain.schedule.current].wait_conditions
      if conditions ~= nil then
        for _, c in pairs(conditions) do
          if c.condition then
            if c.type == "item_count" then
              if c.condition.comparator == ">" then --train expects to be loaded with x of this item
                table.insert(signals, {index = index, signal = c.condition.first_signal, count = c.condition.constant + 1 })
                index = index+1
              elseif (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
                table.insert(signals, {index = index, signal = c.condition.first_signal, count = trainStop.parkedTrain.get_item_count(c.condition.first_signal.name) * -1 })
                index = index+1
              end
            elseif c.type == "fluid_count" then
              if c.condition.comparator == ">" then --train expects to be loaded with x of this item
                table.insert(signals, {index = index, signal = c.condition.first_signal, count = c.condition.constant + 1 })
                index = index+1
              elseif (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
                --table.insert(signals, {index = index, signal = c.condition.first_signal, count = trainStop.parkedTrain.get_fluid_count(c.condition.first_signal.name) * -1 })
                local fluidcount = GetFluidCount(trainStop.parkedTrain, c.condition.first_signal.name)
                table.insert(signals, {index = index, signal = c.condition.first_signal, count = fluidcount * -1 })
                index = index+1
              end
            end
          end
        end
      end

    end

  end
  -- will reset if called with no parked train
  if index > 1 then
    trainStop.output.get_control_behavior().parameters = {parameters=signals}
  else
    trainStop.output.get_control_behavior().parameters = nil
  end
end

---------------------------------- HELPER FUNCTIONS ----------------------------------

function GetMainLocomotive(train)
  if train.valid and train.locomotives and (#train.locomotives.front_movers > 0 or #train.locomotives.back_movers > 0) then
    return train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
  end
end

function GetTrainID(train)
  local loco = GetMainLocomotive(train)
  return loco and loco.unit_number
end

function GetTrainName(train)
  local loco = GetMainLocomotive(train)
  return loco and loco.backer_name
end

function GetFluidCount(train, fluid)
  local count = 0
  for k, wagon in pairs(train.fluid_wagons) do
    for i=1, #wagon.fluidbox do
      if wagon.fluidbox[i] then
        --log("(GetFluidCount) fluid: "..fluid..", fluidbox: "..tostring(wagon.fluidbox[i].type).." "..tostring(wagon.fluidbox[i].amount))
        if wagon.fluidbox[i].type == fluid then
          count = count + wagon.fluidbox[i].amount
        end
      end
    end
  end
  return count
end

--local square = math.sqrt
function GetDistance(a, b)
  local x, y = a.x-b.x, a.y-b.y
  --return square(x*x+y*y) -- sqrt shouldn't be necessary for comparing distances
  return (x*x+y*y)
end
