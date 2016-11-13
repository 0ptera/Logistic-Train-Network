data:extend({
  {
    type = "item-subgroup",
    name = "LTN-signal",
    group = "signals",
    order = "z[LTN-signal]"
  },

  {
    type = "virtual-signal",
    name = "min-delivery-size",
    icon = "__"..MOD_NAME.."__/graphics/icons/shipment-min-size.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ac[min-delivery-size]"
  }

})