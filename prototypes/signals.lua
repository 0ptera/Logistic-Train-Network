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
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-aa[ltn-depot]"
  },
  {
    type = "virtual-signal",
    name = "ltn-network-id",
    icon = "__LogisticTrainNetwork__/graphics/icons/network-id.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ab[ltn-network-id]"
  },  
  {
    type = "virtual-signal",
    name = "ltn-min-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/min-train-length.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ba[ltn-min-train-length]"
  },
  {
    type = "virtual-signal",
    name = "ltn-max-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-train-length.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-bb[ltn-max-train-length]"
  },
  {
    type = "virtual-signal",
    name = "ltn-max-trains",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-trains.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-bc[ltn-max-trains]"
  },
  {
    type = "virtual-signal",
    name = "ltn-provider-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-threshold.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ca[ltn-provider-threshold]"
  },  
  {
    type = "virtual-signal",
    name = "ltn-provider-priority",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-priority.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-cb[ltn-provider-priority]"
  },
  {
    type = "virtual-signal",
    name = "ltn-locked-slots",
    icon = "__LogisticTrainNetwork__/graphics/icons/locked-slot.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-cd[ltn-locked-slots]"
  },
  {
    type = "virtual-signal",
    name = "ltn-requester-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/requester-threshold.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-da[ltn-requester-threshold]"
  },
  {
    type = "virtual-signal",
    name = "ltn-requester-priority",
    icon = "__LogisticTrainNetwork__/graphics/icons/requester-priority.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-db[ltn-requester-priority]"
  },  
  {
    type = "virtual-signal",
    name = "ltn-disable-warnings",
    icon = "__LogisticTrainNetwork__/graphics/icons/disable-warnings.png",
    icon_size = 32,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-dd[ltn-disable-warnings]"
  },
})