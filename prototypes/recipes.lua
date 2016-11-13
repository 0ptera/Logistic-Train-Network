local ltn_stop = copyPrototype("recipe", "train-stop", "logistic-train-stop")
ltn_stop.ingredients = {
  {"train-stop", 1},
  {"advanced-circuit", 2}
}
ltn_stop.enabled = false

local ltn_radar = copyPrototype("recipe", "radar", "ltn-control-radar")
ltn_radar.ingredients = {
  {"radar", 1},
  {"advanced-circuit", 2}
}
ltn_radar.enabled = false

data:extend({
  ltn_stop
})
