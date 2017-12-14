local ltn_stop = copyPrototype("item", "train-stop", "logistic-train-stop")
ltn_stop.icon = "__LogisticTrainNetwork__/graphics/icons/train-stop.png"
ltn_stop.icon_size = 32
ltn_stop.order = "a[train-system]-cc[train-stop]"

local ltn_stop_in = copyPrototype("item", "small-lamp", "logistic-train-stop-input")
table.insert(ltn_stop_in.flags, "hidden")

local ltn_stop_out = copyPrototype("item", "constant-combinator","logistic-train-stop-output")
table.insert(ltn_stop_out.flags, "hidden")
ltn_stop_out.icon = "__LogisticTrainNetwork__/graphics/icons/output.png"
ltn_stop_out.icon_size = 32

local ltn_lamp_control = copyPrototype("item", "constant-combinator","logistic-train-stop-lamp-control")
table.insert(ltn_lamp_control.flags, "hidden")
ltn_lamp_control.icon = "__LogisticTrainNetwork__/graphics/icons/empty.png"
ltn_stop_out.icon_size = 32

data:extend({
  ltn_stop,
  ltn_stop_in,
  ltn_stop_out,
  ltn_lamp_control
})
