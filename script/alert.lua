--[[ Copyright (c) 2020 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local icons = {
  ["provider_undercharge"] = {type="virtual", name="ltn-provider-threshold"},
  ["provider_wrong_load"] = {type="virtual", name="ltn-provider-threshold"},
  ["requester_not_unloaded"] = {type="virtual", name="ltn-requester-threshold"},
  ["requester_wrong_load"] = {type="virtual", name="ltn-requester-threshold"},
}

function create_alert(entity, type)
  local icon = icons[type]
  if icon then
    for _,player in pairs(entity.force.players) do
      player.add_custom_alert(entity, icon, type, true)
    end
  end
end