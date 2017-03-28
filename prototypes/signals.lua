data:extend({
  {
    type = "item-subgroup",
    name = "LTN-signal",
    group = "signals",
    order = "z[LTN-signal]"
  },

  {
    type = "virtual-signal",
    name = "ltn-depot",
    icon = "__LogisticTrainNetwork__/graphics/icons/depot.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-aa[ltn-depot]"
  },
  {
    type = "virtual-signal",
    name = "min-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/min-train-length.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ba[min-train-length]"
  },
  {
    type = "virtual-signal",
    name = "max-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-train-length.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-bb[max-train-length]"
  },
  {
    type = "virtual-signal",
    name = "min-delivery-size",
    icon = "__LogisticTrainNetwork__/graphics/icons/min-shipment-size.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ca[min-delivery-size]"
  },
  {
    type = "virtual-signal",
    name = "stop-priority",
    icon = "__LogisticTrainNetwork__/graphics/icons/stop-priority.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-da[stop-priority]"
  },
  {
    type = "virtual-signal",
    name = "ltn-no-min-delivery-size",
    icon = "__LogisticTrainNetwork__/graphics/icons/no-min-shipment-size.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-db[ltn-depot]"
  }
})