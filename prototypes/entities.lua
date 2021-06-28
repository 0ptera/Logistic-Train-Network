--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local ltn_stop = flib.copy_prototype(data.raw["train-stop"]["train-stop"], "logistic-train-stop")
ltn_stop.icon = "__LogisticTrainNetwork__/graphics/icons/train-stop.png"
ltn_stop.icon_size = 64
ltn_stop.icon_mipmaps = 4
ltn_stop.next_upgrade = nil
ltn_stop.selection_box = {{-0.6, -0.6}, {0.6, 0.6}}
-- ltn_stop.collision_box = {{-0.5, -0.1}, {0.5, 0.4}}

local ltn_stop_in = flib.copy_prototype(data.raw["lamp"]["small-lamp"],"logistic-train-stop-input")
ltn_stop_in.icon = "__LogisticTrainNetwork__/graphics/icons/train-stop.png"
ltn_stop_in.icon_size = 64
ltn_stop_in.icon_mipmaps = 4
ltn_stop_in.next_upgrade = nil
ltn_stop_in.minable = nil
ltn_stop_in.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
ltn_stop_in.selection_priority = (ltn_stop_in.selection_priority or 50) + 10 -- increase priority to default + 10
ltn_stop_in.collision_box = {{-0.15, -0.15}, {0.15, 0.15}}
ltn_stop_in.collision_mask = {"rail-layer"} -- collide only with rail entities
ltn_stop_in.energy_usage_per_tick = "10W"
ltn_stop_in.light = { intensity = 1, size = 6 }
ltn_stop_in.energy_source = {type="void"}

local ltn_stop_out = flib.copy_prototype(data.raw["constant-combinator"]["constant-combinator"],"logistic-train-stop-output")
ltn_stop_out.icon = "__LogisticTrainNetwork__/graphics/icons/output.png"
ltn_stop_out.icon_size = 64
ltn_stop_out.icon_mipmaps = nil
ltn_stop_out.next_upgrade = nil
ltn_stop_out.minable = nil
ltn_stop_out.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
ltn_stop_out.selection_priority = (ltn_stop_out.selection_priority or 50) + 10 -- increase priority to default + 10
ltn_stop_out.collision_box = {{-0.15, -0.15}, {0.15, 0.15}}
ltn_stop_out.collision_mask = {"rail-layer"} -- collide only with rail entities
ltn_stop_out.item_slot_count = 50
ltn_stop_out.sprites = make_4way_animation_from_spritesheet(
  { layers =
    {
      {
        filename = "__LogisticTrainNetwork__/graphics/entity/output.png",
        width = 58,
        height = 52,
        frame_count = 1,
        shift = util.by_pixel(0, 5),
        hr_version =
        {
          scale = 0.5,
          filename = "__LogisticTrainNetwork__/graphics/entity/hr-output.png",
          width = 114,
          height = 102,
          frame_count = 1,
          shift = util.by_pixel(0, 5),
        },
      },
      {
        filename = "__base__/graphics/entity/combinator/constant-combinator-shadow.png",
        width = 50,
        height = 34,
        frame_count = 1,
        shift = util.by_pixel(9, 6),
        draw_as_shadow = true,
        hr_version =
        {
          scale = 0.5,
          filename = "__base__/graphics/entity/combinator/hr-constant-combinator-shadow.png",
          width = 98,
          height = 66,
          frame_count = 1,
          shift = util.by_pixel(8.5, 5.5),
          draw_as_shadow = true,
        },
      },
    },
  })

local control_connection_points = {
  red = util.by_pixel(-3, -7),
  green = util.by_pixel(-1, 0)
}

local ltn_lamp_control = flib.copy_prototype(data.raw["constant-combinator"]["constant-combinator"],"logistic-train-stop-lamp-control")
ltn_lamp_control.icon = "__LogisticTrainNetwork__/graphics/icons/empty.png"
ltn_lamp_control.icon_size = 32
ltn_lamp_control.icon_mipmaps = nil
ltn_lamp_control.next_upgrade = nil
ltn_lamp_control.minable = nil
ltn_lamp_control.selection_box = {{-0.0, -0.0}, {0.0, 0.0}}
ltn_lamp_control.collision_box = {{-0.0, -0.0}, {0.0, 0.0}}
ltn_lamp_control.collision_mask = {} -- disable collision
ltn_lamp_control.item_slot_count = 50
ltn_lamp_control.flags = {"not-blueprintable", "not-deconstructable", "placeable-off-grid"}
ltn_lamp_control.sprites =
{
  north =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    x = 0,
    y = 0,
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0, 0},
  },
  east =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    x = 0,
    y = 0,
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0, 0},
  },
  south =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    x = 0,
    y = 0,
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0, 0},
  },
  west =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    x = 0,
    y = 0,
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0, 0},
  }
}
ltn_lamp_control.activity_led_sprites =
{
  north =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0.0, 0.0},
  },
  east =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0.0, 0.0},
  },
  south =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0.0, 0.0},
  },
  west =
  {
    filename = "__LogisticTrainNetwork__/graphics/icons/empty.png",
    width = 1,
    height = 1,
    frame_count = 1,
    shift = {0.0, 0.0},
  }
}
ltn_lamp_control.activity_led_light =
{
  intensity = 0.0,
  size = 0,
}
ltn_lamp_control.circuit_wire_connection_points =
{
  {
    shadow = control_connection_points,
    wire = control_connection_points
  },
  {
    shadow = control_connection_points,
    wire = control_connection_points
  },
  {
    shadow = control_connection_points,
    wire = control_connection_points
  },
  {
    shadow = control_connection_points,
    wire = control_connection_points
  },
}


data:extend({
  ltn_stop,
  ltn_stop_in,
  ltn_stop_out,
  ltn_lamp_control
})

-- support for cargo ship ports
if mods["cargo-ships"] then
  ltn_port = flib.copy_prototype(data.raw["train-stop"]["port"], "ltn-port")
  ltn_port.selection_box = {{-0.01, -0.6}, {1.9, 0.6}}
  -- ltn_port.collision_box = {{-0.01, -0.1}, {1.9, 0.4}}
  data:extend({
    ltn_port
  })
end