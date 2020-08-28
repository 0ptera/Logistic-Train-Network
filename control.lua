--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

Get_Distance = require("__flib__.misc").get_distance
Get_Main_Locomotive = require("__flib__.train").get_main_locomotive
Get_Train_Name = require("__flib__.train").get_backer_name

require "script.constants"
require "script.settings"
require "script.interface"
require "script.print"
require "script.alert"
require "script.utils"
require "script.stop-update"
require "script.dispatcher"
require "script.stop-events"
require "script.train-events"
require "script.init" -- requires other modules loaded first