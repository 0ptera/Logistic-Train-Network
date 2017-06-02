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
    name = "ltn-min-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/min-train-length.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ba[ltn-min-train-length]"
  },
  {
    type = "virtual-signal",
    name = "ltn-max-train-length",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-train-length.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-bb[ltn-max-train-length]"
  },
  {
    type = "virtual-signal",
    name = "ltn-max-trains",
    icon = "__LogisticTrainNetwork__/graphics/icons/max-trains.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-bc[ltn-max-trains]"
  },
  {
    type = "virtual-signal",
    name = "ltn-requester-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/requester-threshold.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ca[ltn-requester-threshold]"
  },
  {
    type = "virtual-signal",
    name = "ltn-provider-threshold",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-threshold.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-da[ltn-provider-threshold]"
  },  
  {
    type = "virtual-signal",
    name = "ltn-provider-priority",
    icon = "__LogisticTrainNetwork__/graphics/icons/provider-priority.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-db[ltn-provider-priority]"
  },
  {
    type = "virtual-signal",
    name = "ltn-locked-slots",
    icon = "__LogisticTrainNetwork__/graphics/icons/locked-slot.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-dd[ltn-locked-slots]"
  },
  {
    type = "virtual-signal",
    name = "ltn-disable-warnings",
    icon = "__LogisticTrainNetwork__/graphics/icons/disable-warnings.png",
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ea[ltn-disable-warnings]"
  },
})