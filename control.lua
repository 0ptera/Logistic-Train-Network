local MOD_NAME = "LightedPolesPlus"

function EntityBuilt(event)
	local entity = event.created_entity

	if entity.type == "electric-pole" and string.find(entity.name, "lighted-") then
    --log("placing hidden lamp for "..entity.name.." at "..entity.position.x..","..entity.position.y )
		local lamp = entity.surface.create_entity{name = "hidden-small-lamp", position = entity.position, force = entity.force}
		lamp.destructible = false
    lamp.minable = false
	end
end

script.on_event(defines.events.on_built_entity, EntityBuilt)
script.on_event(defines.events.on_robot_built_entity, EntityBuilt)


function EntityMined(event)
	local entity = event.entity

	if entity.type == "electric-pole" and string.find(entity.name, "lighted-") then
		local lamps = entity.surface.find_entities_filtered {
			name = 'hidden-small-lamp',
			position = entity.position,
		}
		for _, lamp in pairs(lamps) do
      --log("removing hidden lamp of "..entity.name.." at "..entity.position.x..","..entity.position.y )
			lamp.destroy()
		end
	end
end

script.on_event(defines.events.on_pre_player_mined_item, EntityMined)
script.on_event(defines.events.on_entity_died, EntityMined)
script.on_event(defines.events.on_robot_pre_mined, EntityMined)


--[[
Event table returned with the event
    player_index = player_index, --The index of the player who moved the entity
    moved_entity = entity, --The entity that was moved
    start_pos = position --The position that the entity was moved from
]]--
function EntityMoved(event)
  -- log(tostring(event.player_index)..", entity: "..tostring(event.moved_entity.name)..", new pos: "..event.moved_entity.position.x..","..event.moved_entity.position.y..", old pos: "..event.start_pos.x..","..event.start_pos.y)
	local entity = event.moved_entity

	if entity and entity.type == "electric-pole" and string.find(entity.name, "lighted-") then
		local lamps = entity.surface.find_entities_filtered {
			name = 'hidden-small-lamp',
			position = event.start_pos,
		}
    for _, lamp in pairs(lamps) do
      lamp.teleport(entity.position)
		end
	end

end

function onLoad()
  --register to PickerExtended
  if remote.interfaces["picker"] and remote.interfaces["picker"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("picker", "dolly_moved_entity_id"), EntityMoved)
  end
end
script.on_init(onLoad)
script.on_load(onLoad)


function Initialize(event)
  -- enable researched recipes
  for i, force in pairs(game.forces) do
    for _, tech in pairs(force.technologies) do
      if tech.researched then
        for _, effect in pairs(tech.effects) do
          if effect.type == "unlock-recipe" then
            force.recipes[effect.recipe].enabled = true
          end
        end
      end
    end
  end


  -- take care of orphaned lamps and poles
  -- removing all hidden lamps and placing them at lighted poles should be faster than checking for lamps without poles and poles without lamps
  if event.mod_changes[MOD_NAME] and event.mod_changes[MOD_NAME].old_version and event.mod_changes[MOD_NAME].old_version < "1.0.0" then
    game.print("[LEP+] old version: "..event.mod_changes[MOD_NAME].old_version..", resetting positions of all lamps.")
    for _, surface in pairs(game.surfaces) do
      lamps = surface.find_entities_filtered {
        name = 'hidden-small-lamp',
      }
      for _, lamp in pairs(lamps) do
        lamp.destroy()
      end

      local poles = surface.find_entities_filtered {
        type = "electric-pole",
      }
      for _, pole in pairs(poles) do
        if string.find(pole.name, "lighted-") then
          local lamp = pole.surface.create_entity{name = "hidden-small-lamp", position = pole.position, force = pole.force}
          lamp.destructible = false
          lamp.minable = false
        end
      end
    end
  end

end
script.on_configuration_changed(Initialize)