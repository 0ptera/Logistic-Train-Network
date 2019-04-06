--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

Station = {}

function Station_get(name)
  local station = global.LogisticStations[name]
  if station then return station end
  station = {
    name = name,
    master = -1,
    ltnStopCount = 0,
    stops = {},
    pendingTrains = {},
    parkedTrains = {},
    isDepot = false,
    errorCode = -1,
    finishedErrorCode = -1,
    greenNetworkID = nil,
    redNetworkID = nil,
  }
  global.LogisticStations[name] = station
  return station
end

function Station_addPendingTrain(self, trainID)
  self.pendingTrains[trainID] = true
end

function Station_trainArrived(self, trainID)
  if self.pendingTrains[trainID] then
    self.pendingTrains[trainID] = nil
    self.parkedTrains[trainID] = trainID
  end
end

function Station_removeTrain(self, trainID)
  self.pendingTrains[trainID] = nil
  self.parkedTrains[trainID] = nil
end

function Station_replaceTrain(self, oldTrainID, newTrainID)
  if self.pendingTrains[oldTrainID] then
    self.pendingTrains[oldTrainID] = nil
    self.pendingTrains[newTrainID] = true
    return true
  end
  if self.parkedTrains[oldTrainID] then
    self.parkedTrains[oldTrainID] = nil
    self.parkedTrains[newTrainID] = true
    return true
  end
  return false
end

function Station_isParked(self, trainID)
  return self.parkedTrains[trainID]
end

function Station_trainCount(self)
  return table_size(self.pendingTrains) + table_size(self.parkedTrains)
end

function Station_pendingCount(self)
  return table_size(self.pendingTrains)
end

function Station_hasPending(self)
  return table_size(self.pendingTrains) > 0
end

function Station_addStop(name, stopID)
  local station = Station_get(name)
  station.stops[stopID] = true
  return station
end

function Station_addStopEntity(entity)
  return Station_addStop(entity.backer_name, entity.unit_number)
end

function Station_removeStopFromStation(self, stopID)
  self.stops[stopID] = nil
  if table_size(self.stops) == 0 then
    global.LogisticStations[self.name] = nil
  end
end

function Station_removeStop(name, stopID)
  local station = Station_get(name)
  Station_removeStopFromStation(station, stopID)
  return station
end

function Station_removeStopEntity(entity)
  return Station_removeStop(entity.backer_name, entity.unit_number)
end

function Station_numStops(self)
  return table_size(self.stops)
end

function Station_mergeStation(self, old)
  for k, _ in pairs(old.pendingTrains) do
    self.pendingTrains[k] = true
  end
  for k, _ in pairs(old.parkedTrains) do
    self.parkedTrains[k] = true
  end
end

function Station_isMaster(self, stopID)
  if self.stops[self.master] then
    return self.master == stopID
  end
  self.master = stopID
  return true
end
