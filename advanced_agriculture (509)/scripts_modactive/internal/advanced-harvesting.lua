-- Add PLANT_GROWTH items to crop plot harvesting output
-- author Droseran

--@module = true

local eventful = require 'plugins.eventful'

local GLOBAL_KEY = 'advanced_harvesting'
local harvested_plants = {}

local function pos2string(pos)
	return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

-- Search the job's farm plot for the plant's information, save it to local harvested_plants array for reference
local function get_harvested_plant(job)
	if job.job_type ~= df.job_type.HarvestPlants then
		return
	end
	
	local harvester = dfhack.job.getWorker(job)
	
	-- This removes a lot of duplicate jobs for the same plant
	if not harvester then
		return
	end
	
	-- For some reason job.pos does not return a z value except this way
	local x = job.pos.x
	local y = job.pos.y
	local z = job.pos.z
	
	-- Turn the positions into a string for indexing by job
	local position = pos2string(job.pos)
	
	local farm = dfhack.job.getHolder(job)
	for i, contained in ipairs(farm.contained_items) do
		local item = contained.item
		local t,u,v = dfhack.items.getPosition(item)
		if x == t and y == u and z == v then
			harvested_plants[position] = {}
			harvested_plants[position].plant = item.mat_index
			harvested_plants[position].count = item:getStackSize()
		end
	end
end

-- Create the growths and move them to the job position when a harvest job is started
-- and has a valid worker
local function create_growths(job)
	if job.job_type ~= df.job_type.HarvestPlants then
		return
	end
	
	local harvester = dfhack.job.getWorker(job)
	
	-- This removes a lot of duplicate jobs for the same plant
	if not harvester then
		return
	end
	
	-- Get the plant's ID and stack size
	local position = pos2string(job.pos)
	local plant_index = harvested_plants[position].plant
	local amount = harvested_plants[position].count
	
	-- Remove the harvested plant in case the job tries to repeat
	harvested_plants[position] = nil
	
	if not plant_index then
		dfhack.printerr('Advanced Harvesting: Plant not recorded for harvesting job.')
		return
	end
	
	-- Get the table of growths for this plant
	local growths = df.global.world.raws.plants.all[plant_index].growths
	
	-- Stop if there are no growths to create
	if #growths < 1 then
		return
	end
	
	-- Create all stockpileable growths for this plant
	for i, growth in ipairs(growths) do
		matinfo = dfhack.matinfo.decode(growth.mat_type, growth.mat_index)
		if matinfo.material.flags.STOCKPILE_PLANT_GROWTH then
			dfhack.items.createItem(
				harvester, df.item_type.PLANT_GROWTH, i,
				growth.mat_type, growth.mat_index, false, amount
			)
		end
	end
	
end

function do_enable()
	-- Using JOB_STARTED to record the necessary plant information
	-- Plant information can be unreliable once the job is completed
	eventful.enableEvent(eventful.eventType.JOB_STARTED, 0)
	-- Using JOB_COMPLETED to actually create the growths
	eventful.enableEvent(eventful.eventType.JOB_COMPLETED, 0)
	eventful.onJobStarted[GLOBAL_KEY] = get_harvested_plant
	eventful.onJobCompleted[GLOBAL_KEY] = create_growths
	print("Enabled Advanced Harvesting.")
end

function do_unload()
	eventful.onJobStarted[GLOBAL_KEY] = nil
	eventful.onJobCompleted[GLOBAL_KEY] = nil
	print("Disabled Advanced Harvesting.")
end

function print_help()
	print("Advanced Harvesting:\n\nThis module returns the farming behavior from before DF 52.03:\nWhen a farm plot is harvested the plant's growths are obtained along with the plant item. Unlike the original behavior, farmers will only pick stockpileable growths in order to avoid clutter.")
end