data:extend({
  {
    type = "item-subgroup",
    name = "LTN-signal",
    group = "signals",
    order = "z[LTN-signal]"
  },

  {
    type = "virtual-signal",
    name = "min-train-length",
    icon = "__"..MOD_NAME.."__/graphics/icons/min-train-length.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-aa[min-train-length]"
  },
  {
    type = "virtual-signal",
    name = "max-train-length",
    icon = "__"..MOD_NAME.."__/graphics/icons/max-train-length.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ab[max-train-length]"
  },
  {
    type = "virtual-signal",
    name = "min-delivery-size",
    icon = "__"..MOD_NAME.."__/graphics/icons/min-shipment-size.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ac[min-delivery-size]"
  },
  {
    type = "virtual-signal",
    name = "stop-priority",
    icon = "__"..MOD_NAME.."__/graphics/icons/stop-priority.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ad[stop-priority]"
  },
  {
    type = "virtual-signal",
    name = "ltn-depot",
    icon = "__"..MOD_NAME.."__/graphics/icons/depot.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ae[ltn-depot]"
  },
  {
    type = "virtual-signal",
    name = "ltn-no-min-delivery-size",
    icon = "__"..MOD_NAME.."__/graphics/icons/no-min-shipment-size.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ae[ltn-depot]"
  }
})