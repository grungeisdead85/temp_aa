-- Enforce placing sapling workshop only on plantable tiles and convert it to a sapling on reaction completion
-- author Droseran

--@module = true

local eventful = require 'plugins.eventful'
local repeatUtil = require 'repeat-util'
local utils = require 'utils'

local GLOBAL_KEY = 'advanced_planting'

-- Get the id of a custom workshop
local function get_custom_workshop_id(token)
	for i, workshop in ipairs(df.global.world.raws.buildings.workshops) do
		if workshop.code == token then
			return workshop.id
		end
	end
	return nil
end

local prepared_ground_id = get_custom_workshop_id('AP_PREPARED_GROUND')

-- Following tables used for identifying tiles in multiple functions
-- Tiletypes which can grow plants
local arable_tiletypes = {
	[df.tiletype_material.SOIL] = true,
	[df.tiletype_material.GRASS_LIGHT] = true,
	[df.tiletype_material.GRASS_DARK] = true,
	[df.tiletype_material.ASHES] = true
}
-- Tiletypes that can have mud which can grow plants
local stone_tiletypes = {
	[df.tiletype_material.STONE] = true,
	[df.tiletype_material.LAVA_STONE] = true,
	[df.tiletype_material.MINERAL] = true,
}

local function getPlayerEntity()
	local civ_id = df.global.plotinfo.civ_id
	for i, entity in ipairs(df.global.world.entities.all) do
		if entity.id == civ_id then
			return entity
		end
	end
	return nil
end

-- Add the custom workshop to the permitted buildings of the currently played entity
local function add_permitted_building()
	local player_civ = getPlayerEntity()
	if prepared_ground_id then
		utils.insert_sorted(player_civ.entity_raw.workshops.permitted_building_id, prepared_ground_id)
	end
end

-- Return the building object for a given building ID
local function get_building(building_id)
	for i, building in ipairs(df.global.world.buildings.all) do
		if building.id == building_id then
			return building
		end
	end
	return nil
end

-- Determines if the tile at a given position has a mud spatter
local function is_muddy(pos)
	local block = dfhack.maps.getTileBlock(pos)
	for i, event in ipairs(block.block_events) do
		if getmetatable(event) == "block_square_event_material_spatterst" then
			if event.mat_type == df.builtin_mats.MUD then
				return true
			end
		end
	end
	return false
end

-- Cancels the placement of AP_PREPARED_GROUND workshop if the tile doesn't support plant growth
local function verify_workshop_placement(building_id)
	local prepared_ground = get_building(building_id)
	if not prepared_ground then
		return
	end
	
	-- Ignore buildings that aren't AP_PREPARED_GROUND
	if prepared_ground:getCustomType() ~= prepared_ground_id then
		return
	end
	
	local pos = utils.getBuildingCenter(prepared_ground)
	
	-- Determine if the ground under the workshop can grow a plant
	-- If it can't, remove the workshop
	local tile = dfhack.maps.getTileType(pos)
	if not arable_tiletypes[df.tiletype.attrs[tile].material] then
		if stone_tiletypes[df.tiletype.attrs[tile].material] then
			if df.tiletype.attrs[tile].special == df.tiletype_special.SMOOTH then
				dfhack.buildings.deconstruct(prepared_ground)
			end
			
			if not is_muddy(pos) then
				dfhack.buildings.deconstruct(prepared_ground)
			end
		else
			dfhack.buildings.deconstruct(prepared_ground)
		end
	end
end

-- Replace the workshop at the location with the specific shrub or sapling
local function replace_workshop(job)
	if job.job_type ~= df.job_type.CustomReaction then
		return
	end
	
	-- Ensure this is one of the Advanced Planting reactions
	if not string.find(job.reaction_name, "^AP_PLANT_") then
		return
	end
	
	-- Get the building of the job (to delete it later)
	local workshop = dfhack.job.getHolder(job)
	if not workshop then
		return
	end
	
	-- Get the ID of the plant from the material of the item used in the job
	-- Also get the material index of the plant for grow_trees checks
	local seed = job.items[0].item
	if not seed then
		return
	end
	
	local plant_id = dfhack.matinfo.getToken(seed)
	local plant_index = seed.mat_index
	plant_id = string.match(plant_id, ":(.+):")
	
	-- coordinates is a string for the run_command below
	local pos = utils.getBuildingCenter(workshop)
	local coordinates = workshop.centerx .. ',' .. workshop.centery .. ',' .. workshop.z
	
	-- Remove the workshop so the tree can be created
	workshop:setBuildStage(0)
	dfhack.buildings.deconstruct(workshop)
	
	-- Arable ground was checked when the building was placed
	-- Since workshops remove mud when building completes, make the ground muddy if it's stone
	local tile = dfhack.maps.getTileType(pos)
	if stone_tiletypes[df.tiletype.attrs[tile].material] then
		local leftover = dfhack.maps.addMaterialSpatter(pos, df.builtin_mats.MUD, -1, -1, 255)
	end
	
	-- Using force option to allow planting regardless of water features
	-- This allows players to make irrigation channels with willows on the banks
	-- Tiles near player-built water features don't count as WET
	dfhack.run_command('plant create "' .. plant_id .. '" ' .. coordinates .. ' --age 1 --force')
end

-- Old code for trying to avoid a bug that likely wasn't due to normal game behavior
-- Leaving this in to clean up any sapling arrays left behind for players using previous versions
-- Grow planted saplings after they reach 2 years old (checked seasonally and on map load)
-- This prevents DF from deleting them due to biome restrictions
local function grow_trees()
	-- Iterate over a temporary copy of planted_saplings so they can be safely deleted
	local saplings = state.planted_saplings
	
	for coord, mat_index in pairs(saplings) do
		-- Implementing goto instead of continue might be the stupidest decision I've seen in a language
		-- Have to nest another loop and break out of the inner one to implement continue behavior
		repeat
			-- Split coord into three values of x, y, z
			local x = coord:split(',')
			z = x[3]
			y = x[2]
			x = x[1]
			
			-- Get the plant
			local plant = dfhack.maps.getPlantAtTile(x,y,z)
			
			-- If it's missing go to next plant
			if not plant then
				break
			end
			
			-- If dead or wrong plant species, go to next plant
			if plant.material ~= mat_index then
				state.planted_saplings[coord] = nil
				break
			elseif plant.damage_flags.dead then
				state.planted_saplings[coord] = nil
				break
			end
			
			-- Adding a year if doing so won't take it over three years old
			if plant.grow_counter < 80639 then -- 80640 is two years
				plant.grow_counter = plant.grow_counter + 40320
			end
		until true
	end
	
	-- Remove the old state
	state = get_default_state()
	dfhack.persistent.saveWorldData(GLOBAL_KEY, state)
end

-- Table of sapling coordinates and plant index numbers to check for growth at 2 years old
-- This enables bypassing the DF native tree growth which will delete
-- saplings if they are in the wrong biome
local function get_default_state()
	return {
		planted_saplings = {}
	}
end

state = state or get_default_state()

function do_enable()
	state = get_default_state()
	utils.assign(state, dfhack.persistent.getWorldData(GLOBAL_KEY, state))
	add_permitted_building()
	eventful.enableEvent(eventful.eventType.BUILDING, 0)
	eventful.enableEvent(eventful.eventType.JOB_COMPLETED, 0)
	
	-- Clear out old saplings arrays, the bug was caused by a different issue than expected
	if state.saplings then
		grow_trees()
	end
	
	eventful.onBuildingCreatedDestroyed[GLOBAL_KEY] = verify_workshop_placement
	eventful.onJobCompleted[GLOBAL_KEY] = replace_workshop
end

function do_unload()
	eventful.onBuildingCreatedDestroyed[GLOBAL_KEY] = nil
	eventful.onJobCompleted[GLOBAL_KEY] = nil
end

function print_help()
	print("Enforces placing the Prepared Ground workshop only on plantable tiles and converts it to a sapling on reaction completion.")
end