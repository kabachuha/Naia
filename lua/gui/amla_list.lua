--
-- [amla_list] dialog
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2019 - 2020 by Iris Morelle <shadowm@wesnoth.org>
--
-- See COPYING for usage terms.
--

-------------
-- amlalib --
-------------

amla = {}
amla.__index = amla

local function a_validate(cond, msg, ...)
	if not cond then
		wput(W_ERR, "amla_lib: " .. tostring(msg):format(...))
	end
end

local function a_default(value, default)
	if value == nil then
		return default
	end

	return value
end

local function parse_counted_list(str)
	local res = {}

	if str ~= nil and str ~= "" then
		for sstr in str:gmatch("[^,]+") do
			local id = sstr:match "^%s*(.-)%s*$"

			if not res[id] then
				res[id] = 1
			else
				res[id] = res[id] + 1
			end
		end
	end

	return res
end

local function count_wml_children_with_value(cfg, tag, attr_key, attr_val, stop_count_at)
	local count = 0

	for child in wml.child_range(cfg, tag) do
		if child[attr_key] == attr_val then
			count = count + 1

			if stop_count_at ~= nil and count >= stop_count_at then
				return count
			end
		end
	end

	return count
end

--
-- Constructs a new amla object from a WML table.
--
function amla:new(cfg)
	local o = {}

	setmetatable(o, amla)

	o.__cfg = cfg

	if not cfg then
		a_validate(false, "null advancement config")
		return
	end

	a_validate(cfg.id, "AMLA has no id")
	o.id = a_default(cfg.id, "")

	a_validate(cfg.description, "AMLA has no description")
	o.description = a_default(cfg.description, "")

	o.image = a_default(cfg.image, "")

	o.always_display = a_default(cfg.always_display, false)
	o.max_times = a_default(cfg.max_times, 0)
	o.strict_amla = a_default(cfg.strict_amla, false)
	o.major_amla = a_default(cfg.major_amla, false)

	o.effects = {}

	for eff in wml.child_range(cfg, "effect") do
		table.insert(o.effects, eff)
	end

	-- AMLAs may be listed multiple times in requirement/exclusion lists to
	-- declare that they must be acquired a number of times before being made
	-- available.

	o.require_amla = parse_counted_list(cfg.require_amla)
	o.exclude_amla = parse_counted_list(cfg.exclude_amla)

	return o
end

--
-- Returns whether this is a valid AMLA.
--
function amla:valid()
	return not not self.id
end

--
-- Returns whether the specified unit can acquire this AMLA, checking all
-- possible requirements and exclusions.
--
function amla:unit_can_get(u)
	local mods_cfg = wml.get_child(u.__cfg, "modifications")
	local status = true

	for req_id, req_count in pairs(self.require_amla) do
		local times = count_wml_children_with_value(mods_cfg, "advancement", "id", req_id)

		if times >= req_count then
			status = status and true
		end

		if not status then
			return false
		end
	end

	for exc_id, exc_count in pairs(self.exclude_amla) do
		local times = count_wml_children_with_value(mods_cfg, "advancement", "id", exc_id)

		if times < exc_count then
			status = status and true
		end

		if not status then
			return false
		end
	end

	return true
end

--
-- Returns whether the specified unit has already acquired this AMLA.
--
-- If count is not provided or 0, it defaults to 1.
--
function amla:unit_has(u, count)
	local m = u.__cfg.modifications
	local n = count or 1

	a_validate(u and m, "amla:unit_has(): bad unit")

	return not not n == count_wml_children_with_value(m, "advancement", "id", self.id, count or n)
end

--
-- Compare two AMLA objects for consistency checks.
--
function amla:compare(other)
	local val_attrs = { "id", "description", "image", "always_display", "max_times", "strict_amla", "major_amla" }
	local wml_attrs = { "effects" }
	local list_attrs = { "require_amla", "exclude_amla" }

	for i = 1, #val_attrs do
		if tostring(self[val_attrs[i]]) ~= tostring(other[val_attrs[i]]) then
			return false
		end
	end

	for i = 1, #wml_attrs do
		if wml.tostring(self[wml_attrs[i]]) ~= wml.tostring(other[wml_attrs[i]]) then
			return false
		end
	end

	for i = 1, #list_attrs do
		if self.__cfg[list_attrs[i]] ~= other.__cfg[list_attrs[i]] then
			return false
		end
	end

	return true
end

-------------------------
-- User interface code --
-------------------------

local T = wml.tag

local MISSING_AMLA_ICON = "misc/blank-hex.png~CROP(0,0,60,60)" -- 60x60
local MISSING_UNIT_ICON = "misc/blank-hex.png"                 -- 72x72

-- #textdomain wesnoth-Naia
local _ = wesnoth.textdomain "wesnoth-Naia"

-- NOTE: The radio button ids must match the keys of the ADV_FILTERS table
--       found in the implementation of the dialog!
local adv_filter_grid = {
	T.row {
		--[[
		T.column {
			border = "all",
			border_size = 5,
			T.label {
				id = "adv_display_label",
				label = _("advancements^Display:")
			},
		},
		]]

		T.column {
			border = "all",
			border_size = 5,
			T.toggle_button {
				id = "adv_display_current",
				definition = "radio",
				label = _("advancements^Acquired")
			},
		},

		T.column {
			border = "all",
			border_size = 5,
			T.toggle_button {
				id = "adv_display_available",
				definition = "radio",
				label = _("advancements^Available")
			},
		},

		T.column {
			border = "all",
			border_size = 5,
			T.toggle_button {
				id = "adv_display_all",
				definition = "radio",
				label = _("advancements^All")
			},
		}
	}
}

local adv_list = { T.row { T.column {
	vertical_grow = true,
	horizontal_grow = true,

	-- ICON || LABEL

	T.toggle_panel { T.grid { T.row {
		T.column {
			horizontal_grow = true,
			grow_factor = 1,
			border = "all",
			border_size = 5,
			T.image {
				id = "adv_icon",
				linked_group = "group_adv_icon"
			}
		},

		T.column {
			horizontal_grow = true,
			grow_factor = 1,
			border = "all",
			border_size = 5,
			T.label {
				id = "adv_label",
				linked_group = "group_adv_label"
			}
		},
	} } }
} } }

local main_row = {
	T.column {
		horizontal_grow = true,
		vertical_grow = true,
		border = "all",
		border_size = 5,
		-- Unit preview with the selected advancement's effects applied
		T.unit_preview_pane {
			id = "unit_display"
		}
	},

	T.column {
		vertical_grow = true,
		T.grid {
			-- Filter options at the top
			T.row {
				T.column {
					horizontal_alignment = "right",
					T.grid(adv_filter_grid)
				}
			},

			-- Combined list of advancements and promotions
			T.row {
				grow_factor = 1,
				T.column {
					vertical_grow = true,
					border = "all",
					border_size = 5,
					T.listbox {
						id = "adv_list",
						T.list_definition(adv_list)
					}
				}
			}
		},
	},
}

local amla_dlg = {
	maximum_width = 1024,
	maximum_height = 700,

	T.helptip { id = "tooltip_large" },
	T.tooltip { id = "tooltip_large" },

	T.linked_group { id = "group_adv_icon", fixed_width = true },
	T.linked_group { id = "group_adv_label", fixed_width = true },

	T.grid {
		T.row {
			T.column {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				border = "all",
				border_size = 5,
				T.label {
					label = _("Unit Advancements"),
					definition = "title"
				}
			}
		},

		T.row {
			grow_factor = 1,
			T.column {
				horizontal_grow = true,
				vertical_grow = true,
				T.grid {
					T.row(main_row)
				}
			}
		},

		T.row {
			T.column {
				horizontal_alignment = "right",
				border = "all",
				border_size = 5,
				T.button {
					id = "ok",
					label = wgettext("Close")
				}
			}
		},
	}
}

local function lmsg(lvl, fmt, ...)
	wput(lvl, "[amla_list]: " .. tostring(fmt):format(...))
end

function naia_amla_menu_check()
	return true
end

--
-- Displays the unit AMLA browser user interface.
--
-- Usage:
--
--   [amla_list]
--       # Position of the unit to list AMLAs for. It must be a valid
--       # map location containing an extant unit.
--       x,y=1,1
--   [/amla_list]
--
function wesnoth.wml_actions.amla_list(cfg)
	local pos = { x = cfg.x, y = cfg.y }
	local u = nil

	if pos.x and pos.y then
		u = wesnoth.get_unit(pos.x, pos.y)
	end

	if not u then
		lmsg(W_ERR, "Map position (%d, %d) not specified, off-map, or does not contain a unit", pos.x, pos.y)
		return
	end

	local uid = ("'%s' (%d, %d)"):format(u.id, u.x, u.y)
	local umods = wml.get_child(u.__cfg, "modifications")

	if not umods then
		lmsg(W_ERR, "Unit %s has no [modifications] block??", uid)
		return
	end

	-- Format: { id: { amla: <amlalib>, times_applied: <int> } }
	local amlas = {}
	-- Format: { id: { unit_type: <unit type>, name: <tstr>, icon: <str> } }
	local promotions = {}

	--
	-- Enumerate AMLAs
	--

	-- Available
	for _, cfg in ipairs(u.advancements) do
		local a = amla:new(cfg)
		if a:valid() then
			if amlas[a.id] then
				-- Duplicate advancement?
				lmsg(W_WARN, "%s has a duplicate AMLA %s available", uid, a.id)
			end

			amlas[a.id] = {
				amla = a,
				times_applied = 0,
			}

			lmsg(W_DBG, "%s has AMLA %s available", uid, a.id)
		else
			lmsg(W_ERR, "skipping invalid AMLA avaiable for %s", uid)
		end
	end

	-- Applied
	for cfg in wml.child_range(umods, "advancement") do
		local a = amla:new(cfg)
		if a:valid() then
			if not amlas[a.id] then
				-- Extraneous advancement, maybe added by [object]?
				lmsg(W_DBG, "%s has non-standard AMLA %s applied", uid, a.id)

				amlas[a.id] = {
					amla = a,
					times_applied = 1,
				}
			else
				amlas[a.id].times_applied = amlas[a.id].times_applied + 1
				lmsg(W_DBG, "%s has AMLA %s applied %d times", uid, a.id, amlas[a.id].times_applied)
			end
		else
			lmsg(W_ERR, "skipping invalid AMLA applied to %s", uid)
		end
	end

	-- Unit type promotions
	for _, ut_id in ipairs(u.advances_to) do
		local ut = wesnoth.unit_types[ut_id]

		if not ut then
			lmsg(W_ERR, "%s has a promotion to unknown unit type '%s'", uid, ut_id)
		else
			promotions[ut_id] = {
				unit_type = ut,
				name = ut.name,
				icon = (ut.__cfg.image_icon or ut.__cfg.image),
			}
		end
	end

	lmsg(W_DBG, "%s has %d AMLAs, %d promotions", uid, table_size(amlas), table_size(promotions))

	--
	-- Set-up the actual dialog
	--

	wesnoth.show_dialog(amla_dlg, function()
		-- Constants
		local ADV_PROMOTION      = 0x00000001
		local ADV_AMLA_AVAILABLE = 0x00000002
		local ADV_AMLA_ACQUIRED  = 0x00000004

		local ADV_FILTERS = {
			-- The keys also match widget identifiers!
			adv_display_available = ADV_PROMOTION | ADV_AMLA_AVAILABLE,
			adv_display_current   = ADV_AMLA_ACQUIRED,
			adv_display_all       = ADV_PROMOTION | ADV_AMLA_AVAILABLE | ADV_AMLA_ACQUIRED,
		}

		-- Variables

		local current_filter = ADV_FILTERS.adv_display_all

		local selected_row = 0

		-- Format defined in state_factory()
		-- This is modified by do_repopulate_adv_list() and needs to be read
		-- from by other functions to update unit preview pane.
		local state = {}

		local preview_unit = nil

		local function state_factory(filter)
			--
			-- The list is displayed with the unit type promotions at the top,
			-- followed by the available (not acquired) AMLAs and the acquired
			-- AMLAs. The .entries field has the list items in the exact same
			-- order that is used for their display.
			--
			-- The id and type of each entry can be used to trace them back to
			-- the amlas and promotions tables above.
			--
			local state = {
				-- Value: [{ <id>, <icon>, <display_text>, <type> }]
				entries = {},
				num_promotions = 0,
				num_available_amlas = 0,
				num_acquired_amlas = 0,
			}

			local function push(type, ...)
				local STATE_FIELD_NAME = {
					[ADV_PROMOTION]      = "num_promotions",
					[ADV_AMLA_AVAILABLE] = "num_available_amlas",
					[ADV_AMLA_ACQUIRED]  = "num_acquired_amlas",
				}
				table.insert(state.entries, { ... })
				table.insert(state.entries[#state.entries], type)
				state[STATE_FIELD_NAME[type]] = state[STATE_FIELD_NAME[type]] + 1
			end

			-- NOTE: We do need to go over the list of AMLAs twice below. This
			-- is so we get the state.entries table's contents in the intended
			-- order. Sadness.

			-- List promotions
			if filter & ADV_PROMOTION ~= 0 then
				for _, type_id in ipairs(table_keys(promotions)) do
					push(ADV_PROMOTION, type_id, promotions[type_id].icon, promotions[type_id].name)
				end
			end

			-- Available AMLAs
			if filter & ADV_AMLA_AVAILABLE ~= 0 then
				for _, amla_id in ipairs(table_keys(amlas)) do
					if amlas[amla_id].times_applied == 0 then
						push(ADV_AMLA_AVAILABLE, amla_id, amlas[amla_id].amla.image, amlas[amla_id].amla.description)
					end
				end
			end

			-- Acquired AMLAs
			if filter & ADV_AMLA_ACQUIRED ~= 0 then
				for _, amla_id in ipairs(table_keys(amlas)) do
					if amlas[amla_id].times_applied > 0 then
						push(ADV_AMLA_ACQUIRED, amla_id, amlas[amla_id].amla.image, amlas[amla_id].amla.description)
					end
				end
			end

			return state
		end

		local function clear_advancements_listbox()
			wesnoth.remove_dialog_item(1, 0, "adv_list")
		end

		local function get_current_type()
			local row = wesnoth.get_dialog_value("adv_list")
			return state.entries[row][4]
		end

		local function get_current_advancement()
			local row = wesnoth.get_dialog_value("adv_list")
			local id, type = state.entries[row][1], state.entries[row][4]

			if type == ADV_PROMOTION then
				return promotions[id]
			else
				return amlas[id]
			end
		end

		local function refresh_unit_preview()
			-- Here we clone the original unit and apply the selected
			-- modifications to the clone for the preview pane.
			preview_unit = u:clone()

			-- We are not supposed to do anything if we are looking at an
			-- advancement the unit has already acquired.
			if get_current_type() == ADV_AMLA_ACQUIRED then
				wesnoth.set_dialog_value(preview_unit, "unit_display")
				return
			end

			local adv = get_current_advancement()
			if not adv.amla then
				local promotion_ut = adv.unit_type
				preview_unit.experience = 0
				preview_unit:transform(promotion_ut.id)
			else
				local promotion_cfg = adv.amla.__cfg
				preview_unit:add_modification("advancement", promotion_cfg)
			end

			wesnoth.set_dialog_value(preview_unit, "unit_display")
		end

		local function rebuild()
			lmsg(W_DBG, "rebuilding [amla_list] display with filters 0x%08x", current_filter)

			clear_advancements_listbox()

			state = state_factory(current_filter)

			-- Repopulate the listbox

			-- TODO: Differentiate between different advancement types in formatting

			for i = 1, #state.entries do
				local id, type, icon, text = state.entries[i][1],
											 state.entries[i][4],
											 state.entries[i][2],
											 state.entries[i][3]
				if not icon then
					if type == ADV_PROMOTION then
						icon = MISSING_UNIT_ICON
					else
						icon = MISSING_AMLA_ICON
					end
				elseif type == ADV_PROMOTION then
					local promotion = promotions[id]
					icon = icon .. ("~TC(%d,%s)"):format(u.side, promotion.unit_type.__cfg.flag_rgb or "magenta")
				end

				wesnoth.set_dialog_value(icon, "adv_list", i, "adv_icon")
				wesnoth.set_dialog_value(text, "adv_list", i, "adv_label")
				-- TODO: is this correct?
				wesnoth.set_dialog_markup(true, "adv_list", i, "adv_label")
			end

			refresh_unit_preview()
		end

		local function do_update_filter_options(new_filter)
			-- Reflect current selection on the radio buttons
			for id, mask in pairs(ADV_FILTERS) do
				wesnoth.set_dialog_value(new_filter == mask, id)
			end

			-- Rebuild view
			current_filter = new_filter
			rebuild()
		end

		for id, mask in pairs(ADV_FILTERS) do
			wesnoth.set_dialog_callback(function() do_update_filter_options(mask) end, id)
		end

		wesnoth.set_dialog_callback(refresh_unit_preview, "adv_list")

		-- This will repopulate the list at the start of the dialog's lifecycle
		do_update_filter_options(ADV_FILTERS.adv_display_all)

		wesnoth.set_dialog_focus("adv_list")
	end)
end
