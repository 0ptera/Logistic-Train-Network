--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

MOD_NAME = "LogisticTrainNetwork"

ISDEPOT = "ltn-depot"
NETWORKID = "ltn-network-id"
MINTRAINLENGTH = "ltn-min-train-length"
MAXTRAINLENGTH = "ltn-max-train-length"
MAXTRAINS = "ltn-max-trains"
MINREQUESTED = "ltn-requester-threshold"
REQPRIORITY = "ltn-requester-priority"
NOWARN = "ltn-disable-warnings"
MINPROVIDED = "ltn-provider-threshold"
PROVPRIORITY = "ltn-provider-priority"
LOCKEDSLOTS = "ltn-locked-slots"

ControlSignals = {
  [ISDEPOT] = {type="virtual", name=ISDEPOT},
  [NETWORKID] = {type="virtual", name=NETWORKID},
  [MINTRAINLENGTH] = {type="virtual", name=MINTRAINLENGTH},
  [MAXTRAINLENGTH] = {type="virtual", name=MAXTRAINLENGTH},
  [MAXTRAINS] = {type="virtual", name=MAXTRAINS},
  [MINREQUESTED] = {type="virtual", name=MINREQUESTED},
  [REQPRIORITY] = {type="virtual", name=REQPRIORITY},
  [NOWARN] = {type="virtual", name=NOWARN},
  [MINPROVIDED] = {type="virtual", name=MINPROVIDED},
  [PROVPRIORITY] = {type="virtual", name=PROVPRIORITY},
  [LOCKEDSLOTS] = {type="virtual", name=LOCKEDSLOTS},
}

ltn_stop_entity_names = { -- ltn stop entity.name with I/O entity offset away from tracks in tiles
  ["logistic-train-stop"] = 0,
  ["ltn-port"] = 1,
}

ltn_stop_input = "logistic-train-stop-input"
ltn_stop_output = "logistic-train-stop-output"
ltn_stop_output_controller = "logistic-train-stop-lamp-control"

ErrorCodes = {
  [-1] = "white", -- not initialized
  [1] = "red",    -- short circuit / disabled
  [2] = "pink",   -- duplicate stop name
}

ColorLookup = {
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


StopIDList = {} -- stopIDs list for on_tick updates

-- cache often used strings and functions
format = string.format
match = string.match
match_string = "([^,]+),([^,]+)"
btest = bit32.btest
band = bit32.band
ceil = math.ceil
sort = table.sort