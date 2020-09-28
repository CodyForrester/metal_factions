
CommonUnitBehavior = {}
CommonUnitBehavior.__index = CommonUnitBehavior

function CommonUnitBehavior.create()
   local obj = {}             -- our new object
   setmetatable(obj,CommonUnitBehavior)
   
   return obj
end


function CommonUnitBehavior:commonInit(ai, uId)
	self.ai = ai
	self.isEasyMode = (self.ai.mode == "easy")
	self.isBrutalMode = (self.ai.mode == "brutal")

	self.pos = newPosition(spGetUnitPosition(uId,false,false))
	self.unitId = uId
	self.unitDef = UnitDefs[spGetUnitDefID(uId)]
	self.unitDefId = self.unitDef.id
	self.unitName = self.unitDef.name
	self.unitSide = side1Name
	if string.find(self.unitName,"aven_") then
		self.unitSide = side1Name
	elseif string.find(self.unitName,"gear_") then
		self.unitSide = side2Name
	elseif string.find(self.unitName,"claw_")then
		self.unitSide = side3Name
	elseif string.find(self.unitName,"sphere_") then
		self.unitSide = side4Name
	end
	
	if (not self.ai.sideSet and self.ai.useStrategies) then
		self.ai.sideSet = true
		--Spring.Echo("changing side from "..self.ai.side.." to "..self.unitSide) --DEBUG
		self.ai:updateSideStrategy(self.unitSide)
	end

	-- unit properties
	self.isCommander = setContains(unitTypeSets[TYPE_COMMANDER],self.unitName)
	self.isUpgradedCommander = setContains(unitTypeSets[TYPE_UPGRADED_COMMANDER],self.unitName)

	self.isArmed = #self.unitDef.weapons > 0
	self.unitCost = getWeightedCostByName(self.unitName) 
	self.isFullHealth = true
	self.isSeriouslyDamaged = false
	self.isFullyBuilt = false	
	self.isBasePatrolling = false
	self.pFType = getUnitPFType(self.unitDef)
	self.alongPathIdx = 0
	self.canFly = (self.unitDef.canFly)
	self.speed = self.unitDef.speed
	self.maxRange = 0
	self.minRange = 0		-- will run from enemies that get below this
	self.preemptivelyEvade = (not self.canFly) and (not self.isEasyMode)
	if (self.isArmed) then
		self.maxRange = self.unitDef.maxWeaponRange
		if (self.maxRange > 400) then
			self.minRange = self.maxRange*0.8
		else
			self.minRange = 200
		end
	else
		self.minRange = 500
	end
	
	-- last minute hack to make assaults assault
	self.noEvadeUnit = not self.isCommander and (self.unitDef.health / self.unitCost > 5)
	
	self.noEngageUnit = false --might be useful
	self.stuckCounter = 0
	self.lastOrderFrame = 0
	self.lastRetreatOrderFrame = 0
	self.underAttackFrame = 0
end

function CommonUnitBehavior:evadeIfNeeded()
	local tmpFrame = spGetGameFrame()
	
	-- kite shorter range enemies even if not being hit
	-- or just preemptively run from them
	local preemptivelyEvade = false
	if (self.preemptivelyEvade) then
		local eId = spGetUnitNearestEnemy(self.unitId,self.minRange == 0 and 600 or self.minRange,true)
		if (eId) then
			preemptivelyEvade = true
		end
	end
	
	if((not self.noEvadeUnit) and (preemptivelyEvade or (tmpFrame - self.underAttackFrame < UNDER_ATTACK_FRAMES ))) then
		local threatPos = nil
		local threatCost = nil
		local biggestThreatPos = nil
		local biggestThreatCost = 0
		local closestCell = nil
		local xIndex,zIndex = getCellXZIndexesForPosition(self.pos)
		local cellCountX = self.ai.mapHandler.cellCountX
		local cellCountZ = self.ai.mapHandler.cellCountZ 
		
		-- find most threatening nearby enemy cell
		local xi,zi = 0
		local enemyCell = nil
		-- check nearby cells
		for dxi = -2, 2 do
			for dzi = -2, 2 do
				xi = xIndex + dxi
				zi = zIndex + dzi
				if (xi >=0) and (zi >= 0) and xi < cellCountX and zi < cellCountZ then
					if self.ai.unitHandler.enemyCells[xi] then
						enemyCell = self.ai.unitHandler.enemyCells[xi][zi]
						if enemyCell ~= nil then
							threatCost = enemyCell.combinedThreatCost
							if (threatCost > biggestThreatCost ) then
								biggestThreatPos = enemyCell.p
								biggestThreatCost = threatCost
							end
						end													
					end
				end
			end
		end
		-- if none nearby, run from biggest enemy cluster
		for _,enemyCell in ipairs(self.ai.unitHandler.enemyCellList) do
			threatCost = enemyCell.combinedThreatCost
			if (threatCost > biggestThreatCost ) then
				biggestThreatPos = enemyCell.p
				biggestThreatCost = threatCost
			end		
		end

		--TODO bad logic? improve
		if biggestThreatPos ~= nil then
			-- if the threat is cheaper than armed unit, strafe only without backing				
			self:evade(biggestThreatPos, (biggestThreatCost > self.unitCost or (not self.isArmed) ) and UNIT_EVADE_DISTANCE or 100)
			
			return true
		end
	end
	return false
end

-- engage if needed, move towards nearest enemies which outrange you
function CommonUnitBehavior:engageIfNeeded()
	local tmpFrame = spGetGameFrame()
	
	-- check if enemies are already too close
	local eId = spGetUnitNearestEnemy(self.unitId,self.minRange == 0 and 600 or self.minRange,true)
	if eId then
		return false
	end
	
	-- check if enemies are within 2x range
	eId = spGetUnitNearestEnemy(self.unitId,self.maxRange == 0 and 600 or self.maxRange *2,true)

	-- check if you can catch them
	if eId and eId > 0 then
		local eDef = UnitDefs[spGetUnitDefID(eId)]
		if (eDef and eDef.speed > self.speed) then
			--log("enemies too fast ("..self.speed.." vs "..eDef.speed.."), don't engage",self.ai) --DEBUG
			return false
		end
	end
	local preemptivelyEngage = false -- TODO needs work
	
	if((not self.noEngageUnit) and (preemptivelyEngage or (tmpFrame - self.underAttackFrame < UNDER_ATTACK_FRAMES ))) then
		local threatPos = nil
		local threatCost = nil
		local biggestThreatPos = nil
		local biggestThreatCost = 0
		local closestCell = nil
		local xIndex,zIndex = getCellXZIndexesForPosition(self.pos)
		local cellCountX = self.ai.mapHandler.cellCountX
		local cellCountZ = self.ai.mapHandler.cellCountZ 
		
		-- find most threatening nearby enemy cell
		local xi,zi = 0
		local enemyCell = nil
		-- check nearby cells
		for dxi = -2, 2 do
			for dzi = -2, 2 do
				xi = xIndex + dxi
				zi = zIndex + dzi
				if (xi >=0) and (zi >= 0) and xi < cellCountX and zi < cellCountZ then
					if self.ai.unitHandler.enemyCells[xi] then
						enemyCell = self.ai.unitHandler.enemyCells[xi][zi]
						if enemyCell ~= nil then
							threatCost = enemyCell.combinedThreatCost
							if (threatCost > biggestThreatCost ) then
								biggestThreatPos = enemyCell.p
								biggestThreatCost = threatCost
							end
						end													
					end
				end
			end
		end
		-- if none nearby, run towards biggest enemy cluster
		for _,enemyCell in ipairs(self.ai.unitHandler.enemyCellList) do
			threatCost = enemyCell.combinedThreatCost
			if (threatCost > biggestThreatCost ) then
				biggestThreatPos = enemyCell.p
				biggestThreatCost = threatCost
			end		
		end

		
		local friendlyAssistCost = self.unitCost
		local friendlyCells = self.ai.unitHandler.friendlyCells
		if (friendlyCells and friendlyCells[xIndex]) then
			local friendlyCell = friendlyCells[xIndex][zIndex]
			if (friendlyCell and friendlyCell.combinedThreatCost  and friendlyCell.combinedThreatCost > 0 ) then
				friendlyAssistCost = friendlyCell.combinedThreatCost 
			end
		end 
		
		-- enemies too strong, don't even try
		if friendlyAssistCost < biggestThreatCost * ENGAGE_THREAT_FACTOR then
			--log("enemies too strong ("..friendlyAssistCost.." vs "..(biggestThreatCost* ENGAGE_THREAT_FACTOR).."), don't engage",self.ai) --DEBUG
			return false
		end

		if biggestThreatPos ~= nil and biggestThreatCost > 0 then
			--log ("ENGAGE!",self.ai) --DEBUG
			self:engage(biggestThreatPos, UNIT_EVADE_DISTANCE)
			return true
		end
	end
	return false
end


-- zigzag away from enemy or run to base
function CommonUnitBehavior:evade(threatPos, moveDistance)
	local selfPos = self.pos

	local vx = selfPos.x - threatPos.x
	local vz = selfPos.z - threatPos.z
	
	local norm = sqrt(vx*vx + vz*vz)		
	vx = vx / norm  
	vz = vz / norm

	-- change movement vector if near edge of map
	local nearEdge = false
	local aux = pos.x + vx * moveDistance
	if (aux > Game.mapSizeX - EVADE_EDGE_MARGIN or aux < EVADE_EDGE_MARGIN) then
		nearEdge = true
	end
	aux = pos.z + vz * moveDistance
	if not nearEdge and (aux > Game.mapSizeZ - EVADE_EDGE_MARGIN or aux < EVADE_EDGE_MARGIN) then
		 nearEdge = true
	end
	-- move towards least vulnerable cell
	if (nearEdge) then
		local safePos = self.ai.unitHandler.leastVulnerableCell.p			
		vx = safePos.x - selfPos.x
		vz = safePos.z - selfPos.z

		norm = sqrt(vx*vx + vz*vz)		
		vx = vx / norm  
		vz = vz / norm
	end
		
	vxNormal = vz
	vzNormal = -vx
			
	local pos = newPosition(selfPos.x,selfPos.y,selfPos.z)
	local increment = moveDistance / UNIT_EVADE_WAYPOINTS
	local strafeSign = 1 
	local strafeDistance = 0
	
	local ordersGiven = 0
	for i=1,UNIT_EVADE_WAYPOINTS do
		strafeSign = random(1,10) > 5 and 1 or -1
		strafeDistance = strafeSign * random(1,UNIT_EVADE_STRAFE_DISTANCE)
		
		pos.x = pos.x + vx * increment + vxNormal * strafeDistance
		pos.z = pos.z + vz * increment + vzNormal * strafeDistance
		-- log(pos.x.." ; "..pos.z)
		if  spTestMoveOrder(self.unitDef.id,pos.x,0,pos.z,0,0,0,true,true) then
			ordersGiven = ordersGiven + 1 
			spGiveOrderToUnit(self.unitId,CMD.MOVE,{pos.x,spGetGroundHeight(pos.x,pos.z),pos.z},i > 1 and CMD.OPT_SHIFT or {})
		end
	end
	
	if (ordersGiven == 0) then
		--log(self.unitName.." RUN TO BASE!",self.ai)
		spGiveOrderToUnit(self.unitId,CMD.MOVE,{self.ai.unitHandler.basePos.x - BIG_RADIUS/2 + random( 1, BIG_RADIUS),0,self.ai.unitHandler.basePos.z - BIG_RADIUS/2 + random( 1, BIG_RADIUS)},{})
	end
	
end

-- zigzag toward enemy
function CommonUnitBehavior:engage(threatPos, moveDistance)
	local selfPos = self.pos

	local vx = selfPos.x - threatPos.x
	local vz = selfPos.z - threatPos.z
	
	local norm = sqrt(vx*vx + vz*vz)		
	vx = vx / norm  
	vz = vz / norm

	-- invert direction
	vx = -vx
	vz = -vz

	-- change movement vector if near edge of map
	local nearEdge = false
	local aux = pos.x + vx * moveDistance
	if (aux > Game.mapSizeX - EVADE_EDGE_MARGIN or aux < EVADE_EDGE_MARGIN) then
		nearEdge = true
	end
	aux = pos.z + vz * moveDistance
	if not nearEdge and (aux > Game.mapSizeZ - EVADE_EDGE_MARGIN or aux < EVADE_EDGE_MARGIN) then
		 nearEdge = true
	end
	-- move towards least vulnerable cell
	if (nearEdge) then
		local safePos = self.ai.unitHandler.leastVulnerableCell.p			
		vx = safePos.x - selfPos.x
		vz = safePos.z - selfPos.z

		norm = sqrt(vx*vx + vz*vz)		
		vx = vx / norm  
		vz = vz / norm
	end
		
	vxNormal = vz
	vzNormal = -vx
			
	local pos = newPosition(selfPos.x,selfPos.y,selfPos.z)
	local increment = moveDistance / UNIT_EVADE_WAYPOINTS
	local strafeSign = 1 
	local strafeDistance = 0
	
	local ordersGiven = 0
	for i=1,UNIT_EVADE_WAYPOINTS do
		strafeSign = random(1,10) > 5 and 1 or -1
		strafeDistance = strafeSign * random(1,UNIT_EVADE_STRAFE_DISTANCE)
		
		pos.x = pos.x + vx * increment + vxNormal * strafeDistance
		pos.z = pos.z + vz * increment + vzNormal * strafeDistance
		-- log(pos.x.." ; "..pos.z)
		if  spTestMoveOrder(self.unitDef.id,pos.x,0,pos.z,0,0,0,true,true) then
			ordersGiven = ordersGiven + 1 
			spGiveOrderToUnit(self.unitId,CMD.MOVE,{pos.x,spGetGroundHeight(pos.x,pos.z),pos.z},i > 1 and CMD.OPT_SHIFT or {})
		end
	end
	
	-- can't reach enemy? run to base?
	if (ordersGiven == 0) then
		--log(self.unitName.." RUN TO BASE!",self.ai)
		spGiveOrderToUnit(self.unitId,CMD.MOVE,{self.ai.unitHandler.basePos.x - BIG_RADIUS/2 + random( 1, BIG_RADIUS),0,self.ai.unitHandler.basePos.z - BIG_RADIUS/2 + random( 1, BIG_RADIUS)},{})
	end
	
end


-- order (move, patrol or fight) to closest cell along a path given by a list of cells
-- if the order is a table {o1,o2}, o1 is used when moving forward and o2 is used when backtracking to avoid threats
function CommonUnitBehavior:orderToClosestCellAlongPath(cellList, order, reverse, ensureSafety)
	
	if cellList == nil then
		--log("OrderToClosestCellAlongPath :: cellList is nil! unit"..self.unitName,self.ai)
		return false
	end
	
	local selfPos = self.pos

	local goalCell = nil
	local startCell = nil
	if reverse then
		goalCell = cellList[1]
		startCell = cellList[#cellList]
	else
		goalCell = cellList[#cellList]
		startCell = cellList[1]
	end

	if(goalCell == nil) then
		--log("goal cell nil! unit"..self.unitName.." CLSize="..#cellList,self.ai)
		return false
	end

	local progressOrder = nil
	local backTrackOrder = nil
	if (type(order) == 'table') then
		progressOrder = order[1]
		backtrackOrder = order[2]
	else
		progressOrder = order
		backtrackOrder = order
	end
	local minSQDistance = INFINITY
	local d = 0
	local orderCell = nil
	local closestCell = nil
	local enemyCell = nil
	local idx = 1
	local xIndex = nil
	local zIndex = nil
	local enemyCells = self.ai.unitHandler.enemyCells
	local dangerCells = self.ai.unitHandler.dangerCells
	local safe = true
	local backTrack = false
	local oldIdx = self.alongPathIdx
	local newIdx = 1
	--Spring.MarkerAddPoint(selfPos.x,500,selfPos.z,"UNIT!") --DEBUG
	
	-- find the closest cell
	for i,cell in ipairs(cellList) do
		safe = true
		if ensureSafety then
			-- if fails the safety test, skip	
			xIndex, zIndex = getCellXZIndexesForPosition(cell.p)
			enemyCell = getCellFromTableIfExists(enemyCells,xIndex,zIndex)
			dangerCell = getCellFromTableIfExists(dangerCells,xIndex,zIndex)
			if (enemyCell == nil and dangerCell == nil) or (enemyCell and self.isArmed and enemyCell.combinedThreatCost <= self.unitCost)  then
				d = sqDistance(selfPos.x,cell.p.x,selfPos.z,cell.p.z)
				if (d < minSQDistance) then
					minSQDistance = d
					idx = i
				end
			else
				safe = false
			end
		else
			d = sqDistance(selfPos.x,cell.p.x,selfPos.z,cell.p.z)
			if (d < minSQDistance) then
				minSQDistance = d
				idx = i
			end
		end
		--Spring.MarkerAddPoint(cell.p.x,500,cell.p.z,"RAID "..i.." d="..d..(safe and " SAFE" or "")) --DEBUG
	end

	
	if reverse then
		-- move to the previous cell, up to start
		nexIdx = max(idx-1,1)
		orderCell = cellList[nexIdx]
		
		if (newIdx > oldIdx) then
			backTrack = true
		end
	else
		-- move to the next cell, up to goal
		newIdx = min(idx+1,#cellList) 
		orderCell = cellList[newIdx]

		if (newIdx > oldIdx) then
			backTrack = true
		end
	end

	-- if far from base and the closest cell is far away, path probably changed and now you're lost!
	if minSQDistance > HUGE_RADIUS*HUGE_RADIUS and (not checkWithinDistance(selfPos,self.ai.unitHandler.basePos,HUGE_RADIUS)) then
		-- go home
		self:retreat()
	end
 	
	local pos = orderCell.p
	if checkWithinDistance(selfPos,pos,CELL_SIZE) then
		if(progressOrder == CMD.FIGHT and (not backTrack)) then
			-- just got in, patrol on it
			spGiveOrderToUnit(self.unitId,CMD.PATROL,{pos.x,pos.y,pos.z},{})
			local px = pos.x - SML_RADIUS/2 + random( 1, SML_RADIUS)
			local pz = pos.z - SML_RADIUS/2 + random( 1, SML_RADIUS) 
			spGiveOrderToUnit(self.unitId,CMD.PATROL,{px,spGetGroundHeight(px,pz),pz},CMD.OPT_SHIFT)
		end
	else
		-- if farther away, use order on the cell
		spGiveOrderToUnit(self.unitId,backTrack and backTrackOrder or progressOrder,{pos.x,spGetGroundHeight(pos.x,pos.z),pos.z},{})
		-- queue a patrol order for progressing aircraft using "fight"
		if(progressOrder == CMD.FIGHT and (not backTrack) and (self.canFly or self.isCommander)) then
			local px = pos.x - SML_RADIUS/2 + random( 1, SML_RADIUS)
			local pz = pos.z - SML_RADIUS/2 + random( 1, SML_RADIUS) 
			
			spGiveOrderToUnit(self.unitId,CMD.PATROL,{px,spGetGroundHeight(px,pz),pz},CMD.OPT_SHIFT)
		end
	end
	
	-- commanders and other task queue units need trigger to re-check their tasks if they're set on patrol
	if self:internalName() == "taskqueuebehavior" then
		--log(self.unitName.." scheduled to re-check tasks",self.ai) --DEBUG
		self.progress = true
		self.currentProject = "custom"
		self.waitLeft = 200
	end
		
	self.alongPathIdx = newIdx
	
	return true
end


-- execute order with position as target (generally move, fight or patrol)
-- unless already there
function CommonUnitBehavior:orderToPosition(pos, order)
	
	local selfPos = self.pos
	if ( abs(selfPos.x - pos.x) > SML_RADIUS or abs(selfPos.z - pos.z) > SML_RADIUS  ) then
		local px = pos.x - SML_RADIUS/2 + random( 1, SML_RADIUS)
		local pz = pos.z - SML_RADIUS/2 + random( 1, SML_RADIUS)
		spGiveOrderToUnit(self.unitId,order,{px,spGetGroundHeight(px,pz),pz},{})
	else
		self:evadeIfNeeded()
	end

	self.isBasePatrolling = false
end
