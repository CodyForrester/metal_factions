include("LuaRules/Gadgets/ai/common.lua")
include("LuaRules/Gadgets/ai/modules.lua")
include("LuaRules/Gadgets/ai/AttackerBehavior.lua")
include("LuaRules/Gadgets/ai/TaskQueueBehavior.lua")

AI = {}
AI.__index = AI


function AI.create(id, mode, strategyStr, allyId, mapHandler)
	local obj = {}             -- our new object
	setmetatable(obj,AI)  -- make AI handle lookup
	obj.id = id      -- initialize our object
	obj.mode = mode
	obj.isEasyMode = (mode == "easy")
	obj.isBrutalMode = (mode == "brutal")
	obj.originalStrategyStr = strategyStr
	obj.currentStrategyStr = strategyStr
	obj.originalStrategyName = nil
	obj.currentStrategyName = nil
	obj.currentStrategy = nil
	obj.currentStrategyStage = 1
	obj.useStrategies = strategyStr ~= "classic"
	obj.autoChangeStrategies = strategyStr == "adaptable"	--TODO make this work
	obj.side = "aven"		-- assume aven, but override it after the first unit spawns
	obj.sideSet = false  -- to signal that it needs to be set
	obj.beaconSetPlayerId = nil
	obj.beaconSetTeamId = nil
	obj.beaconFrame = nil
	obj.beaconPos = nil
	obj.allyId = allyId
	obj.mapHandler = mapHandler
   	obj.strategyOverride = false
	
	obj.frameShift = 7*tonumber(id)	-- used to spread out processing from different AIs across multiple frames
	obj.needStartPosAdjustment = false
	obj.sentStartupHelpMsg = false
	return obj
end

-- pick a strategy, given its identifier and the side
function AI:setStrategy(side,strategyStr,noMessage)
	
	-- if "adaptable", pick one strategy depending on the map
	if strategyStr == "adaptable" then
		local mapProfile = self.mapHandler.mapProfile
		
		if mapProfile == MAP_PROFILE_LAND_FLAT then
			viableStrategyStrList = {"assault","skirmisher","air","amphibious"}
			strategyStr = viableStrategyStrList[random( 1, #viableStrategyStrList)]
		elseif mapProfile == MAP_PROFILE_LAND_RUGGED then
			viableStrategyStrList = {"assault","skirmisher","air","amphibious"}
			strategyStr = viableStrategyStrList[random( 1, #viableStrategyStrList)]
		elseif mapProfile == MAP_PROFILE_WATER or mapProfile == MAP_PROFILE_MIXED  then
			viableStrategyStrList = {"air","amphibious"}
			strategyStr = viableStrategyStrList[random( 1, #viableStrategyStrList)]
		elseif mapProfile == MAP_PROFILE_AIRONLY then
			viableStrategyStrList = {"air"}
			strategyStr = viableStrategyStrList[random( 1, #viableStrategyStrList)]
		end
		self.currentStrategyStr = strategyStr
	end

	local stratList = strategyTable[side.."_"..strategyStr]

	if (stratList and #stratList > 0) then
		self.currentStrategyStr = strategyStr 
		self.currentStrategy = stratList[random( 1, #stratList)]
		self.currentStrategyName = self.currentStrategy.name
		if not noMessage then
			self:messageAllies("Using strategy \""..strategyStr.."\" : "..self.currentStrategyName)
		end
	else
		self:messageAllies("ERROR : Could not find strategy "..strategyStr.." for side "..side.." using default")
		self.useStrategies = false
		self.autoChangeStrategies = nil
	end
	
	if (self.currentStrategy and self.currentStrategy.upgrades) then
		self.upgradePath = self.currentStrategy.upgrades
	end
end

function AI:updateSideStrategy(side)
	if side ~= self.side then
		self.sideSet = true
		self.side = side
		if (self.useStrategies) then
			--Spring.Echo("updating side and strategy to "..side.."/"..self.currentStrategyStr )	
			self:setStrategy(side,self.currentStrategyStr,false)
		end
	end
end


function AI:isBeaconActive()
	if self.beaconFrame ~=nil then
		local f = spGetGameFrame()

		if f - self.beaconFrame < BEACON_DURATION_FRAMES then
			return true
		else
			-- beacon expired, remove marker
			spMarkerErasePosition(self.beaconPos.x,self.beaconPos.y,self.beaconPos.z)
		end 
	end
	
	return false
end
 


-- check if ally team has start box set (whole map => no start box)
function AI:hasStartBox(xMin,xMax,zMin,zMax)
	if xMin > 1 then
		return true
	end
	if zMin > 1 then
		return true
	end
	if xMax < Game.mapSizeX-1 then
		return true
	end
	if zMax < Game.mapSizeZ-1 then
		return true
	end
	
	return false
end

-- find good starting position within start box
-- if start boxes aren't set, return the assigned start position
function AI:findStartPos(doRangeCheck, minStartPosDist)
	local xMin, zMin, xMax, zMax = Spring.GetAllyTeamStartBox(self.allyId)
	if self:hasStartBox(xMin,xMax,zMin,zMax) and (xMax > xMin + 100) and (zMax > zMin + 100) then
		local rangeCheck = true
		local METAL_POTENTIAL_THRESHOLD = 1
		
		
		local xMin, zMin, xMax, zMax = Spring.GetAllyTeamStartBox(self.allyId)
		
		-- adjust min distance taking into account zone size and number of allies 
		local allies = Spring.GetTeamList(self.allyId)
		local numAllies = #allies
		if (numAllies > 0 and doRangeCheck and minStartPosDist == INFINITY) then
			minStartPosDist = ((xMax-xMin) + (zMax-zMin)) / (1.5*numAllies)
		end
		
		for _, cell in spairs(self.mapHandler.mapCellList, function(t,a,b) return t[b].metalPotential < t[a].metalPotential end) do
			rangeCheck = true
	
			-- check that cell center is within start box for the team and has metal potential
			if cell.metalSpotCount > 0 and cell.metalPotential >= METAL_POTENTIAL_THRESHOLD and (cell.p.x > xMin and cell.p.x < xMax) and (cell.p.z > zMin and cell.p.z < zMax) then
				-- Echo("cellX="..cell.p.x.." cellZ="..cell.p.z.." metal="..cell.metalPotential) --DEBUG
			
				if (numAllies > 0 and doRangeCheck) then
					-- check range from every other ally
					for _,teamId in pairs(allies) do
						local x,y,z
						local uPos
						-- if it's another AI, check if it set the position already
						if (GG.mFAIStartPosByTeamId[teamId]) then
							uPos = GG.mFAIStartPosByTeamId[teamId]
						else
							-- humans already picked their positions
							x,y,z = Spring.GetTeamStartPosition(teamId)
							uPos = {x=x,y=y,z=z}
						end
						
						if(checkWithinDistance(cell.p,uPos,minStartPosDist) == true) then
							rangeCheck = false
							break
						end
					end
				end
				
				-- return spot
				if rangeCheck == true then
					local mSpot = cell.metalSpots[1]
					
					if (mSpot == nil) then
						mSpot = {x=cell.p.x, z=cell.p.z}
					end
					local spot = {}
					spot.x = min(xMax, max(xMin, mSpot.x -50 + random(100)))
					spot.z = min(zMax, max(zMin, mSpot.z -50 + random(100)))  
					spot.y = spGetGroundHeight(spot.x, spot.z)		
					
					-- Spring.Echo("found start position for MFAI id="..self.id.." at ("..spot.x..";"..spot.y..";"..spot.z..")") --DEBUG
					return spot
				end
			end
		end
	else
		-- no start boxes, return the fixed start pos
		local x,y,z = Spring.GetTeamStartPosition(self.id)
		return {x=x,y=y,z=z}
	end

	-- allies are too close, maybe there's no way around it
	-- try again with lower min distance or range check disabled
	if (doRangeCheck) then
		if (minStartPosDist > 200) then
			return self:findStartPos(true,minStartPosDist/2)
		else
			-- Spring.Echo("could not find start position for MFAI id="..self.id.." : trying again with distance check disabled") --DEBUG
			return self:findStartPos(false,0)
		end
	end
	
	Spring.Echo("could not find start position for MFAI id="..self.id) --DEBUG
	return nil
end 

function AI:Init()
	-- Echo("initializing AI for teamID="..self.id) --DEBUG
	-- Echo(#modules)	 --DEBUG
	self.modules = {}
	if next(modules) ~= nil then
		for i,m in ipairs(modules) do
			newModule = m.create()
			local internalName = newModule:internalName()
			self[internalName] = newModule
			table.insert(self.modules,newModule)
			newModule:Init(self)
			-- Echo("added "..newModule:name().." module") --DEBUG
		end
	end
	
	-- table with unit behaviors indexed by unitId
	self.unitBehaviors = {}
end


function AI:addUnitBehavior(unitId,unitDefId)
	-- add behavior
	local beh = nil
	un = UnitDefs[unitDefId].name
	if UnitDefs[unitDefId].isBuilder or setContains(unitTypeSets[TYPE_SUPPORT],un) or taskQueues[un] ~= nil then
 		-- log("adding task queue behavior for unit "..un, self)
		beh = TaskQueueBehavior.create()
		beh:Init(self,unitId)
	elseif setContains(unitTypeSets[TYPE_ATTACKER],un) then
		-- log("adding attacker behavior for unit "..un, self)
		beh = AttackerBehavior.create()
		beh:Init(self,unitId)
	end
	self.unitBehaviors[unitId] = beh
end

function AI:messageAllies(msg)
	Spring.SendMessageToAllyTeam(self.allyId,"--- AI "..self.id..": "..msg)
	--Spring.SendMessage("--- AI "..self.id..": "..msg)
end

function AI:markerAllies(x,y,z,msg)
	SendToUnsynced("AIEvent",self.id,self.allyId,EXTERNAL_RESPONSE_SETMARKER,x.."|"..y.."|"..z.."|"..msg)
end

function AI:eraseMarkerAllies(x,y,z)
	SendToUnsynced("AIEvent",self.id,self.allyId,EXTERNAL_RESPONSE_REMOVEMARKER,x.."|"..y.."|"..z)
end

-- process external command
function AI:processExternalCommand(msg,playerId,teamId,pName)
	if (msg) then
		local parameters = splitString(msg,"|")
		local command = parameters[1] 
		--Spring.Echo("command was: "..command)
		if (command == EXTERNAL_CMD_SETBEACON) then
			local px = tonumber(parameters[2])
			local py = tonumber(parameters[3])
			local pz = tonumber(parameters[4])
			
			-- remove existing marker if any
			if (self.beaconPos ~= nil) then
				self:eraseMarkerAllies(self.beaconPos.x,self.beaconPos.y,self.beaconPos.z)
				--spMarkerErasePosition(self.beaconPos.x,self.beaconPos.y,self.beaconPos.z)
			end
			
			self.beaconSetPlayerId = playerId
			self.beaconSetTeamId = teamId
			self.beaconFrame = spGetGameFrame()
			self.beaconPos = newPosition(px,py,pz)

			local seconds = floor((self.beaconFrame + BEACON_DURATION_FRAMES) / 30) 
			local hh = floor(seconds / 3600)
			local mm = floor(seconds % 3600 / 60)
			local ss = floor(seconds % 3600 % 60)
   			hh = hh < 10 and "0"..hh or hh
   			mm = mm < 10 and "0"..mm or mm
   			ss = ss < 10 and "0"..ss or ss
			
			--spMarkerAddPoint(px,py,pz,"AI BEACON\nuntil "..hh..":"..mm..":"..ss.."\n("..pName..")")
			self:markerAllies(px,py,pz,"AI BEACON\nuntil "..hh..":"..mm..":"..ss.."\n("..pName..")")

		elseif (command == EXTERNAL_CMD_REMOVEBEACON) then
			self.beaconSetPlayerId = playerId
			self.beaconSetTeamId = teamId
			
			-- remove existing marker if any
			if (self.beaconPos ~= nil) then
				self:eraseMarkerAllies(self.beaconPos.x,self.beaconPos.y,self.beaconPos.z)
				--spMarkerErasePosition(self.beaconPos.x,self.beaconPos.y,self.beaconPos.z)
			end
			self.beaconFrame = nil
			self.beaconPos = nil

		elseif (command == EXTERNAL_CMD_STATUS) then
			if self.useStrategies then
				self:messageAllies("Current strategy : \""..self.currentStrategyStr.."\" : "..self.currentStrategyName)
			else
				self:messageAllies("Classic Mode")
			end
			self:messageAllies("Last 10 min efficiency : "..tostring(self.unitHandler.teamCombatEfficiency))
		elseif (command == EXTERNAL_CMD_STRATEGY) then
			local targetTeamId = tonumber(parameters[2])
			local strategyStr = nil	
			if (targetTeamId ~= nil) then
				strategyStr = parameters[3]
			else
				strategyStr = parameters[2]
			end 
			
			if (targetTeamId == nil or targetTeamId == self.id) then
				if (strategyStr ~= nil and strategyTable[self.side.."_"..strategyStr]) then
					self:setStrategy(self.side,strategyStr)
				else
					self:messageAllies("ERROR: strategy "..tostring(strategyStr).." not found for "..self.side)
				end
			end
		elseif (command == EXTERNAL_CMD_COMPAD) then
			local targetTeamId = tonumber(parameters[2])
			
			if (targetTeamId == nil or targetTeamId == self.id) then

				-- get all the AI units, try to find a commander pad
				local units = spGetTeamUnits(self.id)
				local shareUId, ud, tmpName = nil
				local shareX,shareZ = 0
				for _,uId in pairs(units) do 
					ud = UnitDefs[spGetUnitDefID(uId)]
					tmpName = ud.name
					if setContains(unitTypeSets[TYPE_RESPAWNER],tmpName) then
						shareUId = uId
						shareX,_,shareZ = spGetUnitPosition(uId,false,false)
						break
					end
				end
			
				if (shareUId ~= nil) then
					spTransferUnit(shareUId,teamId,true)
					self:messageAllies("commander respawner pad shared at ("..floor(shareX)..","..floor(shareZ)..")")
				else
					self:messageAllies("no commander pad available, try again later...")
				end
			end
		end
	end
end

----------------------- engine event handlers

function AI:GameFrame(n)
	if self.gameEnd == true then
		return
	end
	
	if (n > 100) and (not self.sentStartupHelpMsg) then
		local strategiesStr = ""
		for i,str in ipairs(availableStrategyIds) do
			strategiesStr = strategiesStr.."\n"..str
		end
		self:messageAllies("Use CTRL-ALT-CLICK to set AI beacon (RIGHT click to clear)")
		self:messageAllies("Type #AI to view commands")
		if self.useStrategies then
			self:messageAllies("Current strategy : \""..self.currentStrategyStr.."\" : "..self.currentStrategyName)
			self:messageAllies("Available strategies:")
			for i,str in ipairs(availableStrategyIds) do
				self:messageAllies(" "..str)
			end
		else
			self:messageAllies("Classic Mode")
		end

		self.sentStartupHelpMsg = true
	end
	
	for i,m in ipairs(self.modules) do
		if m == nil then
			log("nil module!")
		else
			if (m.GameFrame ~= nil) then
				m:GameFrame(n)
			end
		end
	end
	
	-- add behaviour for units missing	
    for uId,_ in pairs(self.ownUnitIds) do
		if ((self.recentlyDestroyedUnitIds == nil or self.recentlyDestroyedUnitIds[uId] == nil or (n - self.recentlyDestroyedUnitIds[uId] > 10)) and self.unitBehaviors[uId] == nil) then
			self:addUnitBehavior(uId, spGetUnitDefID(uId))
		end
    end 
	
	for i,b in pairs(self.unitBehaviors) do
		if (b.GameFrame ~= nil) then
			b:GameFrame(n)
		end
	end
	
	-- resource compensation for brutal mode
	if (self.isBrutalMode) then
		if fmod(n,15) == 0 then
			local minutesPassed = floor(n/FRAMES_PER_MIN)
			spAddTeamResource(self.id,"metal",BRUTAL_BASE_INCOME_METAL + minutesPassed * BRUTAL_BASE_INCOME_METAL_PER_MIN  )
			spAddTeamResource(self.id,"energy",BRUTAL_BASE_INCOME_ENERGY + minutesPassed * BRUTAL_BASE_INCOME_ENERGY_PER_MIN )
		end
	end
end

function AI:UnitCreated(unitId, unitDefId, teamId, builderId)
	if self.gameEnd == true then
		return
	end
	if self.needStartPosAdjustment == true then
		return
	end
	
	-- only relevant for own units
	if (teamId == self.id and self.modules ~= nil) then
		for i,m in ipairs(self.modules) do
			if (m.UnitCreated ~= nil) then
				m:UnitCreated(unitId,unitDefId,builderId)
			end
		end

		-- add behavior
		self:addUnitBehavior(unitId, unitDefId)
	end
end

function AI:UnitFinished(unitId, unitDefId, teamId)
	if self.gameEnd == true then
		return
	end
	if self.needStartPosAdjustment == true then
		return
	end
	
	-- only relevant for own units
	if (teamId == self.id and self.modules ~= nil) then
		for i,m in ipairs(self.modules) do
			if (m.UnitFinished ~= nil) then
				m:UnitFinished(unitId)
			end
		end
		
		if (self.unitBehaviors[unitId] ~= nil and self.unitBehaviors[unitId].UnitFinished ~= nil) then
			self.unitBehaviors[unitId]:UnitFinished(unitId)
		end
	end
end

function AI:UnitDestroyed(unitId, unitDefId, teamId, attackerId, attackerDefId, attackerTeamId)
	if self.gameEnd == true then
		return
	end
	for i,m in ipairs(self.modules) do
		if (m.UnitDestroyed ~= nil) then
			m:UnitDestroyed(unitId,teamId, unitDefId)
		end
	end
	
	if (teamId == self.id) then
		for i,b in pairs(self.unitBehaviors) do
			if (b.UnitDestroyed ~= nil) then
				b:UnitDestroyed(unitId)
			end
		end
		
		-- remove behavior from table
		self.unitBehaviors[unitId] = nil
		if (self.recentlyDestroyedUnitIds == nil) then
			self.recentlyDestroyedUnitIds = {}
		end
		self.recentlyDestroyedUnitIds[unitId] = spGetGameFrame()
	end
end

function AI:UnitIdle(unitId, unitDefId, teamId)
	if self.gameEnd == true then
		return
	end
	if self.needStartPosAdjustment == true then
		return
	end
	-- only relevant for own units
	if (teamId == self.id) then
		for i,m in ipairs(self.modules) do
			if (m.UnitIdle ~= nil) then
				m:UnitIdle(unitId)
			end
		end
		
		if (self.unitBehaviors[unitId] ~= nil and self.unitBehaviors[unitId].UnitIdle ~= nil) then
			self.unitBehaviors[unitId]:UnitIdle(unitId)
		end
	end
end

function AI:UnitDamaged(unitId, unitDefId, unitTeamId, damage, paralyzer, weaponDefId, projectileId, attackerId, attackerDefId, attackerTeamId)
	if self.gameEnd == true then
		return
	end

	-- only relevant for own units
	if (unitTeamId == self.id) then
		for i,m in ipairs(self.modules) do
			if (m.UnitDamaged ~= nil) then
				m:UnitDamaged(unitId, unitDefId, unitTeamId, damage, paralyzer, weaponDefId, projectileId, attackerId, attackerDefId, attackerTeamId)
			end
		end
		
		if (self.unitBehaviors[unitId] ~= nil and self.unitBehaviors[unitId].UnitDamaged ~= nil) then
			self.unitBehaviors[unitId]:UnitDamaged(unitId, unitDefId, unitTeamId, damage, paralyzer, weaponDefId, projectileId, attackerId, attackerDefId, attackerTeamId)
		end		
	end
end

function AI:UnitTaken(unitId, unitDefId, teamId, newTeamId)
	if self.gameEnd == true then
		return
	end

	--log("unit taken t="..teamId.." nt="..newTeamId,self.ai) --DEBUG
 	-- only relevant for own units
	if (teamId == self.id and newTeamId ~= self.id) then
		for i,m in ipairs(self.modules) do
			if (m.UnitTaken ~= nil) then
				m:UnitTaken(unitId)
			end
		end
		
		if (self.unitBehaviors[unitId] ~= nil and self.unitBehaviors[unitId].UnitTaken ~= nil) then
			self.unitBehaviors[unitId]:UnitTaken(unitId)
		end
		
		-- remove behavior from table
		self.unitBehaviors[unitId] = nil
	end
end


function AI:UnitGiven(unitId, unitDefId, teamId, oldTeamId)
	if self.gameEnd == true then
		return
	end

	--log("unit given t="..teamId.." ot="..oldTeamId,self.ai) --DEBUG
	-- only relevant for own units
	if (teamId == self.id and self.modules ~= nil) then
		for i,m in ipairs(self.modules) do
			if (m.UnitGiven ~= nil) then
				m:UnitGiven(unitId,unitDefId,teamId,oldTeamId)
			end
		end

		-- add behavior
		self:addUnitBehavior(unitId, unitDefId)
	end
end

function AI:GameEnd()
	self.gameEnd = true
	for i,m in ipairs(self.modules) do
		if (m.GameEnd ~= nil) then
			m:GameEnd()
		end
	end
end

