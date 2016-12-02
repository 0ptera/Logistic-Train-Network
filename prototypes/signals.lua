data:extend({
  {
    type = "item-subgroup",
    name = "LTN-signal",
    group = "signals",
    order = "z[LTN-signal]"
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
  }
})