data:extend({
  {
    type = "item-subgroup",
    name = "LogisticTrains-signal",
    group = "signals",
    order = "z[LogisticTrains-signal]"
  },

  {
    type = "virtual-signal",
    name = "min-delivery-size",
    icon = "__"..MOD_NAME.."__/graphics/icons/shipment-size.png",
    subgroup = "LogisticTrains-signal",
    order = "z[LogisticTrains-signal]-ac"
  }

})