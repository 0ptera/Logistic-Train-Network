-- code inspired by Optera's LTN and LTN Content Reader
-- LTN is required to run this mod (obviously, since its a UI to display data collected by LTN)
-- https://mods.factorio.com/mod/LogisticTrainNetwork
-- https://mods.factorio.com/mod/LTN_Content_Reader

-- control.lua only handles initial setup and event registration
-- UI and data processing are kept seperate, to allow the UI to always be responsive
-- data_processor.lua module: receives event data from LTN and processes it for usage by UI
-- gui_ctrl.lua module: handles UI events and displays data provided in global.data

-- constants
MOD_NAME = require("ltnc.const").global.mod_name
MOD_PREFIX = require("ltnc.const").global.mod_prefix
GUI_EVENTS = require("ltnc.const").global.gui_events
local LTN_MOD_NAME = require("ltnc.const").global.mod_name_ltn
local LTN_MINIMAL_VERSION = require("ltnc.const").global.minimal_version_ltn
local LTN_CURRENT_VERSION = require("ltnc.const").global.current_version_ltn
local custom_events = {
  on_data_updated = script.generate_event_name(),
  on_train_alert= script.generate_event_name(),
}

-- debugging / logging
-- levels:
--  0 =  no logging at all;
--  1 = log only important events;
--  2 = lots of logging;
--  3 = not available as setting, only for use during development

out = require("ltnc.logger")
debug_level = tonumber(settings.global["ltnc-debug-level"].value)

-- modules
local prc = require("ltnc.data_processing")
local ui = require("ltnc.gui_ctrl")

-- helper functions
local function format_version(version_string)
  return string.format("%02d.%02d.%02d", string.match(version_string, "(%d+).(%d+).(%d+)"))
end
-----------------------------
------ event handlers  ------
-----------------------------

local function on_init()
  -- !DEBUG delete old log, for convenience during debugging
  game.write_file("ltnc.log", "", false, 1)

  -- check for LTN
  local ltn_version = nil
  local ltn_version_string = game.active_mods[LTN_MOD_NAME]
  if ltn_version_string then
    ltn_version = format_version(ltn_version_string)
  end
  if not ltn_version or ltn_version < "01.09.02" then
    out.error(MOD_NAME, "requires version 1.9.2 or later of Logistic Train Network to run.")
  end
  -- also check for LTN interface, just in case
  if not remote.interfaces["logistic-train-network"] then
    out.error("LTN interface is not registered.")
  end
  if debug_level > 0 then
    out.info("control.lua", "Starting mod initialization for mod", MOD_NAME .. ". LTN version", ltn_version_string, "has been detected.")
  end

  -- module init
  ui.on_init()
  prc.on_init(custom_events)


  if debug_level > 0 then
    out.info("control.lua", "Initialization finished.")
  end
end -- on_init()

local function on_settings_changed(event)
  -- notifies modules if one of their settings changed
  if not event then return end
  local pind = event.player_index
  local player = game.players[pind]
  local setting = event.setting

  if debug_level > 0 then
    out.info("control.lua", "Player", player.name, "changed setting", setting)
  end
  if setting == "ltn-dispatcher-delivery-timeout" or setting == "ltnc-history-limit" then
    -- LTN delivery timeout is used in processor
    prc.on_settings_changed(event)
  end
  if setting == "ltnc-window-height" or setting == "ltnc-show-button" then
    ui.setting_changed(pind, setting)
  end
  -- debug settings
  if setting == "ltnc-debug-level" or setting == "ltnc-debug-print" then
    debug_level = tonumber(settings.global["ltnc-debug-level"].value)
    out.on_debug_settings_changed(event)
  end
end

-----------------------------
------- STATIC EVENTS -------
-----------------------------
-- additional events are (un-)registered dynamically as needed by data_processing.lua

script.on_init(on_init)

script.on_load(
  function()
    ui.on_load()
    prc.on_load(custom_events)
    if debug_level > 0 then
      out.info("control.lua", "on_load finished.")
    end
  end
)


script.on_configuration_changed(
  function(data)
    if data and data.mod_changes[LTN_MOD_NAME] then
      local ov = data.mod_changes[LTN_MOD_NAME].old_version
      ov = ov and format_version(ov) or "<not present>"
      local nv = data.mod_changes[LTN_MOD_NAME].new_version
      nv = nv and format_version(nv) or "<not present>"
      if nv >= LTN_MINIMAL_VERSION then
        if nv > LTN_CURRENT_VERSION then
          out.warn("LTN version changed from ", ov, " to ", nv, ". That version is not supported, yet. Depending on the changes to LTN, this could result in issues with LTNC.")
        else
          out.info("control.lua", "LTN version changed from ", ov, " to ", nv)
        end
      else
        out.error("LTN version was changed from ", ov, " to ", nv ".", MOD_NAME, "requires version",  LTN_MINIMAL_VERSION, " or later of Logistic Train Network to run.")
      end
    end
    if data and data.mod_changes[MOD_NAME] then
      ui.on_configuration_changed(data)
      out.info("control.lua", MOD_NAME .. " updated to version " .. tostring(game.active_mods[MOD_NAME]))
    end
  end
)

script.on_event(defines.events.on_player_created, function(event) ui.player_init(event.player_index) end)

script.on_event(defines.events.on_runtime_mod_setting_changed, on_settings_changed)

-- gui events
script.on_event(defines.events.on_gui_closed, ui.on_ui_closed)
script.on_event(GUI_EVENTS, ui.ui_event_handler)
script.on_event("ltnc-toggle-hotkey", ui.on_toggle_button_click)

-- custom events, not properly implemented yet
-- raised when updated data for gui is available
-- script.on_event(custom_events.on_data_updated, ui.update_ui)
-- raised when a train with an error is detected
script.on_event(custom_events.on_train_alert, ui.on_new_alert)