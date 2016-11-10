local recipe = copyPrototype("recipe","train-stop", "logistic-train-stop")
recipe.ingredients = {
  {"train-stop", 1},
  {"advanced-circuit", 2}
}
recipe.enabled = false

local lt_stop = copyPrototype("train-stop", "train-stop", "logistic-train-stop")
lt_stop.icon = "__"..MOD_NAME.."__/graphics/icons/train-stop.png"
lt_stop.selection_box = {{-0.6, -0.6}, {0.6, 0.6}}

local lt_stop_i = copyPrototype("item","train-stop", "logistic-train-stop")
lt_stop_i.icon = "__"..MOD_NAME.."__/graphics/icons/train-stop.png"
lt_stop_i.order = "a[train-system]-cc[train-stop]"

local lt_in = copyPrototype("lamp", "small-lamp","logistic-train-stop-input")
lt_in.energy_usage_per_tick = "250W"
lt_in.collision_mask = { "resource-layer" }
lt_in.light = { intensity = 1, size = 6 }
lt_in.minable = nil

local lt_in_i = copyPrototype("item", "small-lamp", "logistic-train-stop-input")
table.insert(lt_in_i.flags, "hidden")

local lt_out = copyPrototype("constant-combinator","constant-combinator","logistic-train-stop-output")
lt_out.collision_mask = {"resource-layer"}
lt_out.item_slot_count = 50
lt_out.minable = nil

local lt_out_i = copyPrototype("item","constant-combinator","logistic-train-stop-output")
table.insert(lt_out_i.flags, "hidden")

data:extend({recipe, lt_stop, lt_stop_i, lt_in, lt_in_i, lt_out, lt_out_i})

table.insert(data.raw["technology"]["automated-rail-transportation"].effects,
{
  type="unlock-recipe",
  recipe = "logistic-train-stop"
})