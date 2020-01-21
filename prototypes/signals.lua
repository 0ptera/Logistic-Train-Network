--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

data:extend({
  {
    type = "item-subgroup",
    name = "LTN-signal",
    group = "signals",
    order = "ltn0[LTN-signal]"
  },
  {
    type = "virtual-signal",
    name = "ltn-depot",
    icon = "__LogisticTrainNetwork__/graphics/icons/depot.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "a-a"
  },
  {
    type = "virtual-signal",
    name = "ltn-network-id",
    icon = "__LogisticTrainNetwork__/graphics/icons/network-id.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "a-b"
  },
  {
    type = "virtual-signal",
    name = "ltn-min-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/min-train-length.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "b-a"
  },
  {
    type = "virtual-signal",
    name = "ltn-max-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-train-length.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "b-b"
  },
  {
    type = "virtual-signal",
    name = "ltn-max-trains",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-trains.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "b-c"
  },
  {
    type = "virtual-signal",
    name = "ltn-provider-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-threshold.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "c-a"
  },
  {
    type = "virtual-signal",
    name = "ltn-provider-stack-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-stack-threshold.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "c-b"
  },
  {
    type = "virtual-signal",
    name = "ltn-provider-priority",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-priority.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "c-c"
  },
  {
    type = "virtual-signal",
    name = "ltn-locked-slots",
    icon = "__LogisticTrainNetwork__/graphics/icons/locked-slot.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "c-d"
  },
  {
    type = "virtual-signal",
    name = "ltn-requester-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/requester-threshold.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "d-a"
  },
  {
    type = "virtual-signal",
    name = "ltn-requester-stack-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/requester-stack-threshold.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "d-b"
  },
  {
    type = "virtual-signal",
    name = "ltn-requester-priority",
    icon = "__LogisticTrainNetwork__/graphics/icons/requester-priority.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "d-c"
  },
  {
    type = "virtual-signal",
    name = "ltn-disable-warnings",
    icon = "__LogisticTrainNetwork__/graphics/icons/disable-warnings.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "d-d"
  },

  {
    type = "item-subgroup",
    name = "ltn-position-signal",
    group = "signals",
    order = "ltn1[ltn-position-signal]"
  },
  {
    type = "item-subgroup",
    name = "ltn-position-signal-cargo-wagon",
    group = "signals",
    order = "ltn2[ltn-position-signal-cargo-wagon]"
  },
  {
    type = "item-subgroup",
    name = "ltn-position-signal-fluid-wagon",
    group = "signals",
    order = "ltn3[ltn-position-signal-fluid-wagon]"
  },
  {
    type = "item-subgroup",
    name = "ltn-position-signal-artillery-wagon",
    group = "signals",
    order = "ltn4[ltn-position-signal-artillery-wagon]"
  },
  {
    type = "virtual-signal",
    name = "ltn-position-any-locomotive",
    -- localised_name = {"virtual-signal-name.ltn-position-any", {"entity-name.locomotive"}},
    icons = {
      { icon = "__base__/graphics/icons/signal/signal_red.png", icon_size = 64, icon_mipmaps = 4 },
      { icon = "__base__/graphics/icons/locomotive.png", icon_size = 64, icon_mipmaps = 4, scale = 0.375 },
    },
    subgroup = "ltn-position-signal",
    order = "a0"
  },
  {
    type = "virtual-signal",
    name = "ltn-position-any-cargo-wagon",
    -- localised_name = {"virtual-signal-name.ltn-position-any", {"entity-name.cargo-wagon"}},
    icons = {
      { icon = "__base__/graphics/icons/signal/signal_red.png", icon_size = 64, icon_mipmaps = 4 },
      { icon = "__base__/graphics/icons/cargo-wagon.png", icon_size = 64, icon_mipmaps = 4, scale = 0.375 },
    },
    subgroup = "ltn-position-signal",
    order = "b0"
  },
  {
    type = "virtual-signal",
    name = "ltn-position-any-fluid-wagon",
    -- localised_name = {"virtual-signal-name.ltn-position-any", {"entity-name.fluid-wagon"}},
    icons = {
      { icon = "__base__/graphics/icons/signal/signal_red.png", icon_size = 64, icon_mipmaps = 4 },
      { icon = "__base__/graphics/icons/fluid-wagon.png", icon_size = 64, icon_mipmaps = 4, scale = 0.375 },
    },
    subgroup = "ltn-position-signal",
    order = "c0"
  },
  {
    type = "virtual-signal",
    name = "ltn-position-any-artillery-wagon",
    -- localised_name = {"virtual-signal-name.ltn-position-any", {"entity-name.artillery-wagon"}},
    icons = {
      { icon = "__base__/graphics/icons/signal/signal_red.png", icon_size = 64, icon_mipmaps = 4 },
      { icon = "__base__/graphics/icons/artillery-wagon.png", icon_size = 64, icon_mipmaps = 4, scale = 0.375 },
    },
    subgroup = "ltn-position-signal",
    order = "d0"
  },

})