--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

MOD_NAME = "LogisticTrainNetwork"

ISDEPOT = "ltn-depot"
DEPOT_PRIORITY = "ltn-depot-priority"
NETWORKID = "ltn-network-id"
MINTRAINLENGTH = "ltn-min-train-length"
MAXTRAINLENGTH = "ltn-max-train-length"
MAXTRAINS = "ltn-max-trains"
REQUESTED_THRESHOLD = "ltn-requester-threshold"
REQUESTED_STACK_THRESHOLD = "ltn-requester-stack-threshold"
REQUESTED_PRIORITY = "ltn-requester-priority"
NOWARN = "ltn-disable-warnings"
PROVIDED_THRESHOLD = "ltn-provider-threshold"
PROVIDED_STACK_THRESHOLD = "ltn-provider-stack-threshold"
PROVIDED_PRIORITY = "ltn-provider-priority"
LOCKEDSLOTS = "ltn-locked-slots"
REQUIRE_CIRCUIT_CONTROL = "ltn-require-circuit-control"

ControlSignals = {
  [ISDEPOT] = {type="virtual", name=ISDEPOT},
  [DEPOT_PRIORITY] = {type="virtual", name=DEPOT_PRIORITY},
  [NETWORKID] = {type="virtual", name=NETWORKID},
  [MINTRAINLENGTH] = {type="virtual", name=MINTRAINLENGTH},
  [MAXTRAINLENGTH] = {type="virtual", name=MAXTRAINLENGTH},
  [MAXTRAINS] = {type="virtual", name=MAXTRAINS},
  [REQUESTED_THRESHOLD] = {type="virtual", name=REQUESTED_THRESHOLD},
  [REQUESTED_STACK_THRESHOLD] = {type="virtual", name=REQUESTED_STACK_THRESHOLD},
  [REQUESTED_PRIORITY] = {type="virtual", name=REQUESTED_PRIORITY},
  [NOWARN] = {type="virtual", name=NOWARN},
  [PROVIDED_THRESHOLD] = {type="virtual", name=PROVIDED_THRESHOLD},
  [PROVIDED_STACK_THRESHOLD] = {type="virtual", name=PROVIDED_STACK_THRESHOLD},
  [PROVIDED_PRIORITY] = {type="virtual", name=PROVIDED_PRIORITY},
  [LOCKEDSLOTS] = {type="virtual", name=LOCKEDSLOTS},
  [REQUIRE_CIRCUIT_CONTROL] = {type="virtual", name=REQUIRE_CIRCUIT_CONTROL},
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

-- cache often used strings and functions
format = string.format
match = string.match
match_string = "([^,]+),([^,]+)"
btest = bit32.btest
band = bit32.band
ceil = math.ceil
sort = table.sort