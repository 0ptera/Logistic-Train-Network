local ltn_stop = copyPrototype("item","train-stop", "logistic-train-stop")
ltn_stop.icon = "__"..MOD_NAME.."__/graphics/icons/train-stop.png"
ltn_stop.order = "a[train-system]-cc[train-stop]"

local ltn_stop_in = copyPrototype("item", "small-lamp", "logistic-train-stop-input")
table.insert(ltn_stop_in.flags, "hidden")

local ltn_stop_out = copyPrototype("item","constant-combinator","logistic-train-stop-output")
table.insert(ltn_stop_out.flags, "hidden")
ltn_stop_out.icon = "__"..MOD_NAME.."__/graphics/icons/output.png"

local ltn_lamp_control = copyPrototype("item","constant-combinator","logistic-train-stop-output")
table.insert(ltn_lamp_control.flags, "hidden")
ltn_lamp_control.icon = "__"..MOD_NAME.."__/graphics/icons/empty.png"

local ltn_radar = copyPrototype("item", "radar", "ltn-control-radar")
ltn_radar.icon = "__"..MOD_NAME.."__/graphics/icons/radar.png"
ltn_radar.subgroup = "transport"
ltn_radar.order = "a[train-system]-cd[ltn-control-radar]"
ltn_radar.stack_size = 10

data:extend({
  ltn_stop,
  ltn_stop_in,
  ltn_stop_out,
  ltn_lamp_control
})
