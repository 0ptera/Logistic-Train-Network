local ltn_stop = copyPrototype("train-stop", "train-stop", "logistic-train-stop")
ltn_stop.icon = "__"..MOD_NAME.."__/graphics/icons/train-stop.png"
ltn_stop.selection_box = {{-0.6, -0.6}, {0.6, 0.6}}

local ltn_stop_in = copyPrototype("lamp", "small-lamp","logistic-train-stop-input")
ltn_stop_in.energy_usage_per_tick = "250W"
ltn_stop_in.collision_mask = { "resource-layer" }
ltn_stop_in.light = { intensity = 1, size = 6 }
ltn_stop_in.minable = nil
ltn_stop_in.flags = {"not-blueprintable", "not-deconstructable"}

local ltn_stop_out = copyPrototype("constant-combinator","constant-combinator","logistic-train-stop-output")
ltn_stop_out.icon = "__"..MOD_NAME.."__/graphics/icons/output.png"
ltn_stop_out.sprites =
{
  north =
  {
    filename = "__"..MOD_NAME.."__/graphics/entity/output.png",
    x = 158,
    y = 5,
    width = 79,
    height = 63,
    frame_count = 1,
    shift = {0.140625, 0.140625},
  },
  east =
  {
    filename = "__"..MOD_NAME.."__/graphics/entity/output.png",
    y = 5,
    width = 79,
    height = 63,
    frame_count = 1,
    shift = {0.140625, 0.140625},
  },
  south =
  {
    filename = "__"..MOD_NAME.."__/graphics/entity/output.png",
    x = 237,
    y = 5,
    width = 79,
    height = 63,
    frame_count = 1,
    shift = {0.140625, 0.140625},
  },
  west =
  {
    filename = "__"..MOD_NAME.."__/graphics/entity/output.png",
    x = 79,
    y = 5,
    width = 79,
    height = 63,
    frame_count = 1,
    shift = {0.140625, 0.140625},
  }
}
ltn_stop_in.collision_mask = { "resource-layer" }
ltn_stop_out.item_slot_count = 50
ltn_stop_out.minable = nil
ltn_stop_out.flags = {"not-blueprintable", "not-deconstructable"}

local ltn_radar = copyPrototype("radar", "radar", "ltn-control-radar")
ltn_radar.icon = "__"..MOD_NAME.."__/graphics/icons/radar.png"
ltn_radar.pictures =
{
  filename = "__"..MOD_NAME.."__/graphics/entity/radar.png",
  priority = "low",
  width = 153,
  height = 131,
  apply_projection = false,
  direction_count = 64,
  line_length = 8,
  shift = {0.875, -0.34375}  
}

data:extend({
  ltn_stop,
  ltn_stop_in,
  ltn_stop_out
})
