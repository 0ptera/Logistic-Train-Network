--[[ Copyright (c) 2020 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local icons = {
  ["cargo-warning"] = {type="fluid", name="ltn-cargo-warning"},
  ["cargo-alert"] = {type="fluid", name="ltn-cargo-alert"},
  ["depot-warning"] = {type="fluid", name="ltn-depot-warning"},
  ["depot-empty"] = {type="fluid", name="ltn-depot-empty"},
}

function create_alert(entity, icon, msg, force)
  force = force or (entity and entity.force)
  if not force or not force.valid then
    return
  end
  for _, player in pairs(force.players) do
    if settings.get_player_settings(player)["ltn-interface-factorio-alerts"].value then
      player.add_custom_alert(entity, icons[icon], msg, true)
    end
  end
end

