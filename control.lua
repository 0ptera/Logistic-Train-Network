--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local get_distance = require("__OpteraLib__.script.misc").get_distance_squared
local get_main_locomotive = require("__OpteraLib__.script.train").get_main_locomotive
local get_train_name = require("__OpteraLib__.script.train").get_train_name

require "script.constants"
require "script.settings"
require "script.interface"
require "script.print"
require "script.utils"
require "script.station"
require "script.stop-update"
require "script.dispatcher"
require "script.stop-events"
require "script.train-events"
require "script.init" -- requires other modules loaded first