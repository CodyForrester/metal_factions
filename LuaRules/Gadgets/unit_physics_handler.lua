function gadget:GetInfo()
   return {
      name = "Physics Handler",
      desc = "Handles some aspects of unit and feature physics",
      author = "raaar",
      date = "2016",
      license = "PD",
      layer = 1,
      enabled = true,
   }
end


-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

if (not gadgetHandler:IsSyncedCode()) then
    return
end


local spAddUnitDamage = Spring.AddUnitDamage
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDirection = Spring.GetUnitDirection
local spGetUnitRadius = Spring.GetUnitRadius
local spGetUnitDefID = Spring.GetUnitDefID
local spGetAllUnits = Spring.GetAllUnits
local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitHealth = Spring.GetUnitHealth
local spSetUnitHealth = Spring.SetUnitHealth
local spUseUnitResource = Spring.UseUnitResource
local spGetUnitVelocity = Spring.GetUnitVelocity
local spSetRelativeVelocity = Spring.MoveCtrl.SetRelativeVelocity
local spSetUnitVelocity = Spring.SetUnitVelocity
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetCommandQueue = Spring.GetCommandQueue
local spGetGameFrame = Spring.GetGameFrame
local spGetUnitIsActive = Spring.GetUnitIsActive
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spCallCOBScript = Spring.CallCOBScript
local spGetFeatureVelocity = Spring.GetFeatureVelocity
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetFeatureRadius = Spring.GetFeatureRadius
local spPlaySoundFile = Spring.PlaySoundFile
local spSpawnCEG = Spring.SpawnCEG
local spSetProjectileCollision = Spring.SetProjectileCollision
local spSpawnProjectile = Spring.SpawnProjectile
local spDestroyUnit = Spring.DestroyUnit

local spSetFeatureVelocity = Spring.SetFeatureVelocity
local spSetFeaturePosition = Spring.SetFeaturePosition
local spSetFeatureRotation = Spring.SetFeatureRotation
local spSetFeatureMoveCtrl = Spring.SetFeatureMoveCtrl

local spSetFeaturePhysics = Spring.SetFeaturePhysics
local spCreateFeature = Spring.CreateFeature

local random = math.random
local floor = math.floor
local min = math.min
local abs = math.abs


local groundCollisionCEG = "COLLISION"
local waterCollisionCEG = "COLLISION"

local groundCollisionSound = "Sounds/XPLOSML2.wav"
local waterCollisionSound = "Sounds/SPLSLRG.wav"

local nanoExplosionCEG = "NANOFRAMEBLAST"
local nanoExplosionSound = "Sounds/NECRNAN2.wav"

local MOVING_CHECK_DELAY = 10
local COLLISION_SPEED_THRESHOLD = 3
local COLLISION_SPEED_MOD = 0.1
local GROUND_COLLISION_H_THRESHOLD = 30

local AIRCRAFT_DEBRIS_METAL_FACTOR = 0.4

local COMSAT_SCAN_DURATION_FRAMES = 450

local moveAnimationUnitIds = {}
local unitPhysicsById = {}
local featureIds = {}
local featurePhysicsById = {}
local magnetarUnitIds = {}
local comsatBeacons = {}
local comsatBeaconDefId = UnitDefNames["cs_beacon"].id

local x,y,z,vx,vy,vz,v,h, enableGC
local function updateUnitPhysics(unitId)
	x,y,z = spGetUnitPosition(unitId)
	vx,vy,vz,v = spGetUnitVelocity(unitId)
	
	if comsatBeacons[unitId] then
		spSetUnitVelocity(unitId,0,0,0)
	end
	-- force physics for magnetar to prevent it from being pushed away 
	if magnetarUnitIds[unitId] == true then
		local groundHeight = spGetGroundHeight(x,z)
		h = y - groundHeight
		if (h > 150 and vy > 0) or v > 1.5 then
			--Spring.Echo("enforced vy for magnetar vy="..vy.." v="..v)
			spSetUnitVelocity(unitId,vx * 0.8/v,0,vz * 0.8/v)
		end
	end  
end

local function updateFeaturePhysics(featureId)
	x,y,z = spGetFeaturePosition(featureId)
	vx,vy,vz = spGetFeatureVelocity(featureId)
end

local function randomNegative(scale)
	return (random() * scale * 2 - scale)
end

local function setFeaturePhysics(featureId,x,y,z,vx,vy,vz)
	spSetFeatureMoveCtrl(featureId,false,1,1,1,1,1,1,1,1,1)
	spSetFeaturePosition(featureId,x,y,z)
	spSetFeatureVelocity(featureId,vx,vy,vz)
	spSetFeatureRotation(featureId,randomNegative(1),randomNegative(1),randomNegative(1))
end

local function isDrone(ud)
  return(ud and ud.customParams and ud.customParams.isdrone)
end


function gadget:UnitCreated(unitId, unitDefId, unitTeam)
	if UnitDefs[unitDefId].isGroundUnit and not UnitDefs[unitDefId].isBuilding and not UnitDefs[unitDefId].isImmobile then
		moveAnimationUnitIds[unitId] = true
	end
	
	if UnitDefs[unitDefId].name == "sphere_magnetar" then
		magnetarUnitIds[unitId] = true
	end

	if (unitDefId == comsatBeaconDefId) then
		comsatBeacons[unitId] = 1
	end
		
	unitPhysicsById[unitId] = {0,0,0,0,0,0,0,false}
end


function gadget:GameFrame(n)
	
	-- increment counter for comsat beacons, remove the ones that expired
	for uId,frames in pairs(comsatBeacons) do
		comsatBeacons[uId] = comsatBeacons[uId] + 1
		
		if (comsatBeacons[uId] > COMSAT_SCAN_DURATION_FRAMES) then
			spDestroyUnit(uId,false,true)
		end
	end
	
	-- check unit physics
	for unitId,oldPhysics in pairs(unitPhysicsById) do
	
		-- get updated physics
		updateUnitPhysics(unitId)
		
		groundHeight = spGetGroundHeight(x,z)
		h = y - groundHeight
		-- prevent repeated collisions when walking down slopes
		if h > GROUND_COLLISION_H_THRESHOLD then
			enableGC = true
		else 
			enableGC = oldPhysics[8]
		end
		
		-- workaround for engine not calling StartMoving when it should in some situations
		if moveAnimationUnitIds[unitId] then
			if (n%MOVING_CHECK_DELAY == 0) then
				if abs(vx) > 0.1 or abs(vz) > 0.1 then
					if abs(h) < 3 then
						spCallCOBScript(unitId,"StartMoving",0)
					end
				else
					spCallCOBScript(unitId,"StopMoving",0)			
				end
			end
		end
		
		if (groundHeight > 0) then
			-- check for high speed ground impact
			if oldPhysics[7] > 0 and h <= 0 and enableGC == true then
				
				-- only trigger this if moving fast
				if abs(oldPhysics[5]) > COLLISION_SPEED_THRESHOLD then
					local radius = spGetUnitRadius(unitId) * 2 * (1 + COLLISION_SPEED_MOD * abs(oldPhysics[5]))
					--Spring.Echo("unit "..unitId.." ground collision at frame "..n.." radius="..radius)
					spSpawnCEG(groundCollisionCEG, x,groundHeight+5,z,0,1,0,radius,radius)
					spPlaySoundFile(groundCollisionSound, math.min(1,math.max(0.2,radius/50)), x, y, z)
					enableGC = false
				end
			end
		else
			-- check for high speed water impact
			if oldPhysics[2] > 0 and y <= 0 then
				if abs(oldPhysics[5]) > COLLISION_SPEED_THRESHOLD then
					local radius = spGetUnitRadius(unitId) * 2 * (1 + COLLISION_SPEED_MOD * abs(oldPhysics[5]))
					--Spring.Echo("unit "..unitId.." water collision at frame "..n.." radius="..radius)
					spSpawnCEG(waterCollisionCEG, x,3,z,0,1,0,radius,radius)
					spPlaySoundFile(waterCollisionSound, math.min(1,math.max(0.2,radius/50)), x, y, z)
					enableGC = false
				end
			end
		end
		
		-- update physics
		oldPhysics[1] = x
		oldPhysics[2] = y
		oldPhysics[3] = z
		oldPhysics[4] = vx
		oldPhysics[5] = vy
		oldPhysics[6] = vz
		oldPhysics[7] = h
		oldPhysics[8] = enableGC
	end
	
	-- feature physics
	for featureId,oldPhysics in pairs(featurePhysicsById) do
	
		-- get updated physics
		updateFeaturePhysics(featureId)
		
		groundHeight = spGetGroundHeight(x,z)
		h = y - groundHeight
		-- prevent repeated collisions when sliding down slopes
		if h > GROUND_COLLISION_H_THRESHOLD then
			enableGC = true
		else 
			enableGC = oldPhysics[8]
		end
		
		if (groundHeight > 0) then
			-- check for high speed ground impact
			if oldPhysics[7] > 0 and h <= 0 and enableGC == true then
				
				-- only trigger this if moving fast
				if abs(oldPhysics[5]) > COLLISION_SPEED_THRESHOLD then
					local radius = spGetFeatureRadius(featureId) * 2 * (1 + COLLISION_SPEED_MOD * abs(oldPhysics[5]))
					--Spring.Echo("feature "..featureId.." ground collision at frame "..n.." radius="..radius)
					spSpawnCEG(groundCollisionCEG, x,groundHeight+5,z,0,1,0,radius,radius)
					spPlaySoundFile(groundCollisionSound, math.min(1,math.max(0.2,radius/50)), x, y, z)
					enableGC = false
				end
			end
		else
			-- check for high speed water impact
			if oldPhysics[2] > 0 and y <= 0 then
				if abs(oldPhysics[5]) > COLLISION_SPEED_THRESHOLD then
					local radius = spGetFeatureRadius(featureId) * 2 * (1 + COLLISION_SPEED_MOD * abs(oldPhysics[5]))
					--Spring.Echo("feature "..featureId.." water collision at frame "..n.." radius="..radius)
					spSpawnCEG(waterCollisionCEG, x,3,z,0,1,0,radius,radius)
					spPlaySoundFile(waterCollisionSound, math.min(1,math.max(0.2,radius/50)), x, y, z)
					enableGC = false
				end
			end
		end
		
		-- update physics
		oldPhysics[1] = x
		oldPhysics[2] = y
		oldPhysics[3] = z
		oldPhysics[4] = vx
		oldPhysics[5] = vy
		oldPhysics[6] = vz
		oldPhysics[7] = h
		oldPhysics[8] = enableGC
	end
end

-- cleanup when some units are destroyed
function gadget:UnitDestroyed(unitId, unitDefId, unitTeam,attackerId, attackerDefId, attackerTeamId)
	if (moveAnimationUnitIds[unitId]) then
		moveAnimationUnitIds[unitId] = nil
	end

	if magnetarUnitIds[unitId] then
		magnetarUnitIds[unitId] = nil
	end

	-- remove entries from tables when unit is destroyed
	if comsatBeacons[unitId] then
		comsatBeacons[unitId] = nil
	end

	local _,_,_,_,bp = spGetUnitHealth(unitId)

	-- if unit is an aircraft which leaves no wreckage, spawn some debris
	local ud = UnitDefs[unitDefId]
	--Spring.Echo("unit destroyed")
	if ud and ud.canFly == true and (unitDefId ~= comsatBeaconDefId) and not isDrone(ud) and tostring(ud.wreckName) == '' then
		if bp > 0.999 or (attackerId ~= nil and bp > 0.5) then
			--Spring.Echo("aircraft destroyed "..tostring(ud.wreckName))
			local physics = unitPhysicsById[unitId]
			if (physics ~= nil) then
				--Spring.Echo("aircraft destroyed had physics!")
				local metalAmount = ud.metalCost * AIRCRAFT_DEBRIS_METAL_FACTOR
				local fId = nil
				local radius = ud.xsize*2
				local spawnName = nil
				local smallPieceV = 2
				local largePieceV = 1
				
				--Spring.Echo("radius="..tostring(radius).." metalAmount="..tostring(metalAmount).." vx="..physics[4].." vy="..physics[5].." vz="..physics[6])
				if metalAmount < 300 then
					-- spawn small debris only
					for i=0,metalAmount,50 do
						spawnName = "debris"..tostring(random(3))
						--Spring.Echo("spawning "..spawnName)
						fId = spCreateFeature(spawnName,physics[1],physics[2],physics[3],random(4)-1)
						if (fId) then
							setFeaturePhysics(fId,physics[1] + random(radius),physics[2],physics[3] + random(radius),randomNegative(smallPieceV)+physics[4],randomNegative(smallPieceV)+physics[5],randomNegative(smallPieceV)+physics[6])
						end
					end
				else 
					-- spawn small debris
					for i=0,floor(metalAmount/2),50 do
						spawnName = "debris"..tostring(random(3))
						--Spring.Echo("spawning "..spawnName)
						fId = spCreateFeature(spawnName,physics[1],physics[2],physics[3],random(4)-1)	
						if (fId) then
							setFeaturePhysics(fId,physics[1] + random(radius),physics[2],physics[3] + random(radius),randomNegative(smallPieceV)+physics[4],randomNegative(smallPieceV)+physics[5],randomNegative(smallPieceV)+physics[6])
						end
					end
					-- spawn large debris
					for i=0,floor(metalAmount/2),100 do
						spawnName = "debris"..tostring(random(4,6))
						--Spring.Echo("spawning "..spawnName)
						fId = spCreateFeature(spawnName,physics[1],physics[2],physics[3],math.random(4)-1)
						if (fId) then
							setFeaturePhysics(fId,physics[1] + random(radius),physics[2],physics[3] + random(radius),randomNegative(largePieceV)+physics[4],randomNegative(largePieceV)+physics[5],randomNegative(largePieceV)+physics[6])
						end
					end
				end
			end
		end
	-- unit was not fully built but leaves wreckage		
	elseif (ud and (not isDrone(ud)) and (tostring(ud.wreckName) ~= '') and bp > 0.5 and bp < 1 and attackerId ~= nil) then
		--Spring.Echo("attackerId="..tostring(attackerId).." attackerDefId="..tostring(attackerDefId).." attackerTeamId="..tostring(attackerTeamId))
		
		local physics = unitPhysicsById[unitId]
		
		if (physics ~= nil) then
			local radius = spGetUnitRadius(unitId)
			local dx,dy,dz = spGetUnitDirection(unitId)
			--Spring.Echo("dx="..tostring(dx).." dz="..tostring(dz))
			
			-- bigger effect for expensive units
			radius = radius + ud.metalCost / 100 
			
			spSpawnCEG(nanoExplosionCEG, physics[1],physics[2],physics[3],0,1,0,radius,radius)
			spPlaySoundFile(nanoExplosionSound, math.min(1,math.max(0.2,radius/50)), physics[1], physics[2], physics[3])
			
			
			local dir = 0
			if abs(dx) > abs(dz) then
				if dx > 0 then
					dir = 1
				else 
					dir = 3
				end
			else
				if dz > 0 then
					dir = 0
				else 
					dir = 2
				end
			end
			--Spring.Echo("dir="..dir)
			
			-- create actual explosion
			local createdId = spSpawnProjectile(WeaponDefNames[ud.deathExplosion].id,{
				["pos"] = {physics[1],physics[2]+radius/3,physics[3]},
				["end"] = {physics[1],physics[2]+radius/3,physics[3]},
				["speed"] = {0,1,0},
				["owner"] = unitTeam
			})
			if (createdId) then
				spSetProjectileCollision(createdId)
			end
			
			-- create feature
			fId = spCreateFeature(ud.wreckName,physics[1],physics[2],physics[3],dir)
		end		
	end


	-- if nano frame, spawn effects
	if bp < 1 and bp > 0.35 then
		local physics = unitPhysicsById[unitId]
		
		if (physics ~= nil) then
			local radius = spGetUnitRadius(unitId)
			
			-- bigger effect for expensive units
			radius = radius + ud.metalCost / 100 
			
			spSpawnCEG(nanoExplosionCEG, physics[1],physics[2],physics[3],0,1,0,radius,radius)
			spPlaySoundFile(nanoExplosionSound, math.min(1,math.max(0.2,radius/50)), physics[1], physics[2], physics[3])
		end
	end

	unitPhysicsById[unitId] = nil
end

function gadget:FeatureCreated(featureId, allyTeam)
	featureIds[featureId] = true
	featurePhysicsById[featureId] = {0,0,0,0,0,0,0,false}
end

-- cleanup when features are destroyed
function gadget:FeatureDestroyed(featureId, allyTeam)
	featureIds[featureId] = nil
	featurePhysicsById[featureId] = nil
end


-- prevent nano frames from using self-D
function gadget:AllowCommand(unitId, unitDefId, unitTeam, cmdId, cmdParams, cmdOptions, cmdTag, synced)
	if cmdId == CMD.SELFD then
		local _,_,_,_,bp = spGetUnitHealth(unitId)
		if bp < 1 then
			return false
		end
	end 
	return true
end
