--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local ltn_stop = optera_lib.copy_prototype(data.raw["item"]["train-stop"], "logistic-train-stop")
ltn_stop.icon = "__LogisticTrainNetwork__/graphics/icons/train-stop.png"
ltn_stop.icon_size = 32
ltn_stop.order = ltn_stop.order.."-c"

local ltn_stop_in = optera_lib.copy_prototype(data.raw["item"]["small-lamp"], "logistic-train-stop-input")
ltn_stop_in.flags = {"hidden"}

local ltn_stop_out = optera_lib.copy_prototype(data.raw["item"]["constant-combinator"],"logistic-train-stop-output")
ltn_stop_out.flags = {"hidden"}
ltn_stop_out.icon = "__LogisticTrainNetwork__/graphics/icons/output.png"
ltn_stop_out.icon_size = 32

local ltn_lamp_control = optera_lib.copy_prototype(data.raw["item"]["constant-combinator"],"logistic-train-stop-lamp-control")
ltn_lamp_control.flags = {"hidden"}
ltn_lamp_control.icon = "__LogisticTrainNetwork__/graphics/icons/empty.png"
ltn_lamp_control.icon_size = 32

data:extend({
  ltn_stop,
  ltn_stop_in,
  ltn_stop_out,
  ltn_lamp_control
})

-- support for cargo ship ports
if mods["cargo-ships"] then
  ltn_port =optera_lib.copy_prototype(data.raw["item"]["port"], "ltn-port")
  ltn_port.order = ltn_port.order.."-c"

  data:extend({
    ltn_port
  })
end