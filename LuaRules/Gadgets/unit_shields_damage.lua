function gadget:GetInfo()
   return {
      name = "Handles damage mitigation and shield related stuff",
      desc = "Makes shields absorb AOE damage, prevents unit collision damage.",
      author = "raaar",
      date = "July 2013",
      license = "PD",
      layer = 0,
      enabled = true,
   }
end

-- feb 2016 : magnetar dmg handling, make stunned aircraft lose altitude
-- jan 2016 : added dmg taken to xp conversion
-- dec 2015 : added max fire aoe dmg
-- nov 2015 : tweaked fire dmg over time values and scale paralyze dmg with missing health %
-- sep 2015 : added fire dmg over time debuff handling
-- feb 2015 : excluded large shield units from special shield rules
-- jan 2015 : made paralyzer weapons deal % dmg to HP
-- mar 2014 : fixes for spring 97.0 : removed local pointers for spring functions and added missing syncedcode check!
-- Sep 2013 : also disables unit collision damage

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

if (not gadgetHandler:IsSyncedCode()) then
    return
end


local COLVOL_SHIELD = 0
local COLVOL_BASE = 1
local PARALYZE_DAMAGE_FACTOR = 0.33 -- paralyze damage adds this fraction as normal damage
local PARALYZE_MISSING_HP_FACTOR = 2.0 -- how much paralyze damage is amplified by target's missing HP %
local DAMAGE_REPAIR_DISRUPT_FRAMES = 60 

--local projectileHitShield = {}
local weaponDefIdByNameTable = {}
local weaponHitpowerTable = {}
local weaponParalyzerTable = {}
local unitArmorTypeTable = {}
local baseUnitColvolTable = {}
local unitShieldColvolTable = {}
local aircraftTable = {}
local stunnedAircraftTable = {}
local unitBurningTable = {}
local unitBurningDPStepTable = {}
local unitXPTable = {}
local damagedUnitFrameTable = {}

local spGetUnitHealth = Spring.GetUnitHealth
local spSetUnitCollisionVolumeData = Spring.SetUnitCollisionVolumeData
local spGetUnitCollisionVolumeData = Spring.GetUnitCollisionVolumeData
local spSetUnitShieldState = Spring.SetUnitShieldState
local spGetUnitShieldState = Spring.GetUnitShieldState
local spAddUnitDamage = Spring.AddUnitDamage
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitRadius = Spring.GetUnitRadius
local spGetUnitExperience = Spring.GetUnitExperience
local spSetUnitExperience = Spring.SetUnitExperience
local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitDirection = Spring.GetUnitDirection
local spSetUnitVelocity = Spring.SetUnitVelocity
local spGetUnitIsStunned = Spring.GetUnitIsStunned
local spAreTeamsAllied = Spring.AreTeamsAllied
local spSetUnitDirection = Spring.SetUnitDirection
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetAllUnits = Spring.GetAllUnits
local spGetGameFrame = Spring.GetGameFrame
local max = math.max

local STEP_DELAY = 6 		-- process steps every N frames
local FIRE_DMG_PER_STEP = 6	-- 6 dmg every 6 frames, 30 frames per second -> 30 dps
local FIRE_DMG_PER_STEP_HEAVY = 3	-- 3 dmg every 6 frames, 30 frames per second -> 15 dps to heavy armor
local FIRE_DMG_STEPS = 30  -- 6 seconds
local FIRE_AOE_DMG_MAX_PER_STEP = 40 --- 200 dps

local BURNING_CEG = "burneffect"
local BURNING_SOUND = "Sounds/BURN1.wav"

local EMP_CEG = "ElectricSequenceSML2"

local UNIT_DAMAGE_XP = 0.05     -- 100% damage taken is converted to experience using this factor
								-- currently set to half as much as fully damaging and enemy unit of equal power

local disruptorWaveEffectWeaponDefId = WeaponDefNames["aven_bass_disruptor_effect"].id
local disruptorWaveUnitDefId = UnitDefNames["aven_bass"].id
local magnetarWeaponDefId = WeaponDefNames["sphere_magnetar_blast"].id
local magnetarAuraWeaponDefId = WeaponDefNames["sphere_magnetar_aura_blast"].id




local burningEffectWeaponDefIds = {
	[WeaponDefNames["gear_pyro_flamethrower"].id] = true,
	[WeaponDefNames["gear_u1commander_flamethrower"].id] = true,
	[WeaponDefNames["gear_cube_flamethrower"].id] = true,
	[WeaponDefNames["gear_burner_flamethrower"].id] = true,
	[WeaponDefNames["gear_heater_flamethrower"].id] = true,
	[WeaponDefNames["gear_canister_fireball"].id] = true,
	[WeaponDefNames["gear_firestorm_fireball"].id] = true,
	[WeaponDefNames["gear_eruptor_fireball"].id] = true,
	[WeaponDefNames["gear_u5commander_fireball"].id] = true,
	[WeaponDefNames["gear_canister"].id] = true,
	[WeaponDefNames["gear_eruptor"].id] = true,
	[WeaponDefNames["gear_fire_effect"].id] = true,
	[WeaponDefNames["gear_fire_effect2"].id] = true
}

local burningAOEPerStepWeaponDefIds = {
	[WeaponDefNames["gear_fire_effect"].id] = true,
	[WeaponDefNames["gear_fire_effect2"].id] = true
}

local largeShieldUnits = {}
local dmgModDeadUnits = {} -- for units that deal damage after they die
							-- workaround for unitRulesParams no longer being available

local upgradeFinishedDefIds = {
	[WeaponDefNames["upgrade_red"].id] = true,
	[WeaponDefNames["upgrade_green"].id] = true,
	[WeaponDefNames["upgrade_blue"].id] = true
}

local continuousBeamWeaponDefIds = {
	[WeaponDefNames["sphere_commander_beam"].id] = true,
	[WeaponDefNames["sphere_u1commander_beam"].id] = true,
	[WeaponDefNames["sphere_u2commander_beam"].id] = true,
	[WeaponDefNames["sphere_u3commander_beam"].id] = true,
	[WeaponDefNames["sphere_u4commander_beam"].id] = true,
	[WeaponDefNames["sphere_opal_sphere_beam"].id] = true,
	[WeaponDefNames["sphere_ruby_sphere_beam"].id] = true,
	[WeaponDefNames["sphere_obsidian_sphere_beam"].id] = true,
	[WeaponDefNames["sphere_chroma_beam1"].id] = true,
	[WeaponDefNames["sphere_chroma_beam2"].id] = true,
	[WeaponDefNames["sphere_chroma_beam3"].id] = true
}

local targetDefId = UnitDefNames["target"].id
local targetDamage = 0

-- set unit collision volume data
function SetColvol(unitID, colvolType)
	local d = nil
	if colvolType == COLVOL_SHIELD then
		d = unitShieldColvolTable[unitID]
	else
		d = baseUnitColvolTable[unitID]
	end
	if d ~= nil then
		spSetUnitCollisionVolumeData(unitID, d[1],d[2],d[3], d[4],d[5],d[6],d[7],d[8],d[9])	
	end
end

function gadget:Initialize()
	-- find units armor types and large shield unit def ids
    for _,ud in pairs(UnitDefs) do
    	if ud.name == "sphere_aegis" or ud.name == "sphere_shielder" or ud.name == "sphere_screener" or ud.name == "sphere_hermit" then
    		largeShieldUnits[ud.id] = true
    	end
    	
		local armorTypeStr = "L"
        if ( Game.armorTypes[ud.armorType] == "armor_heavy" ) then armorTypeStr = "H"
        elseif ( Game.armorTypes[ud.armorType] == "armor_medium" ) then armorTypeStr = "M" end

		unitArmorTypeTable[ud.id] = armorTypeStr
    end

	-- find weapon hitpower and paralyzer status
    for _,wd in pairs(WeaponDefs) do        
		local hitpowerStr = "L"
		if ( wd.damages[Game.armorTypes.default] == wd.damages[Game.armorTypes.armor_heavy] ) then
    		hitpowerStr = "H"
		elseif ( wd.damages[Game.armorTypes.default] == wd.damages[Game.armorTypes.armor_medium] ) then
    		hitpowerStr = "M"
    	end
    	
    	weaponDefIdByNameTable[wd.name] = wd.id
    	weaponHitpowerTable[wd.id] = hitpowerStr
    	weaponParalyzerTable[wd.id] = wd.paralyzer
    end
end

-- add base collision volume of shielded unit to table
-- add aircrafts to list
function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	local shieldEnabled,oldShieldPower = spGetUnitShieldState(unitID)
	if shieldEnabled and oldShieldPower > 0 and not (largeShieldUnits[unitDefID] == true) then
		
		-- add base colvol to table 
		local xs, ys, zs, xo, yo, zo, vType, tType, axis, _ = spGetUnitCollisionVolumeData(unitID)
		baseUnitColvolTable[unitID] = {xs,ys,zs,xo,yo,zo,vType,tType,axis}
	
		-- get shield colvol and add it to table
		local ud = UnitDefs[unitDefID]
		local shieldDefID = ud.shieldWeaponDef
		diameter = WeaponDefs[shieldDefID].shieldRadius * 2
		unitShieldColvolTable[unitID] = {diameter,diameter,diameter,xo,yo,zo,3,1,0}

	end
	
	if (UnitDefs[unitDefID].canFly) then
		aircraftTable[unitID] = true
	end
end

-- clear damage modifier for dead unit if unitID is reused
function gadget:UnitCreated(unitID, unitDefID, unitTeam)
	dmgModDeadUnits[unitID] = nil
end

-- process update steps every N frames
-- process aircraft altitude loss every frame
function gadget:GameFrame(n)
	
	-- make stunned aircraft fall
	local x,y,z,h,dx,dy,dz, factor = 0
	for unitId,_ in pairs(stunnedAircraftTable) do  
		x,y,z = spGetUnitPosition(unitId)
		h = spGetGroundHeight(x,z)
		
		factor = math.min((y - h) / 70,3)
		if (y > (h+70)) then
			dx,dy,dz = spGetUnitDirection(unitId)
			spSetUnitVelocity(unitId,dx * factor,dy-1 * factor,dz * factor)
		else
			dx,dy,dz = spGetUnitDirection(unitId)
			spSetUnitVelocity(unitId,0,0,0)
			spSetUnitDirection(unitId,dx,0,dz)
		end
	end

	-- update "on fire" label for all units
	for _,unitID in ipairs(spGetAllUnits()) do
		if(unitBurningTable[unitID]) then
			spSetUnitRulesParam(unitID,"on_fire","1",{public = true})
		else
			spSetUnitRulesParam(unitID,"on_fire","0",{public = true})
		end
	end

	-- handle target damage, for test purposes
	if (n%1800 == 0) then
		if targetDamage > 0 then
			Spring.Echo(n.." dps="..(targetDamage / 60))
			targetDamage = 0
		end
	end

	if (n%STEP_DELAY ~= 0) then
		return
	end

	-- clear burn aoe dmg counter
	unitBurningDPStepTable = {}
		
	-- process shield colvol changes for shielded units
	for unitID,data in pairs(unitShieldColvolTable) do
		local shieldEnabled,shieldPower = spGetUnitShieldState(unitID)
		if shieldEnabled and shieldPower > 100 then
			SetColvol(unitID, COLVOL_SHIELD)
		else
			SetColvol(unitID, COLVOL_BASE)
		end
	end

	-- process burn debuff for burning units
	local dmg, radius = 0
	
	for unitID,data in pairs(unitBurningTable) do	
		
		-- apply damage
		local armorType = unitArmorTypeTable[data.unitDefID]
		if (armorType == "H") then
			dmg = FIRE_DMG_PER_STEP_HEAVY
		else
			dmg = FIRE_DMG_PER_STEP
		end
		spAddUnitDamage(unitID,dmg,0,data.attackerID)

		-- spawn CEG
		x,y,z = spGetUnitPosition(unitID)
		radius = spGetUnitRadius(unitID)
		if radius ~= nil then
			local h = radius / 2
			Spring.SpawnCEG(BURNING_CEG, x - h + math.random(2*h), y+h, z - h + math.random(2*h), 0, 1, 0,radius ,radius)
			Spring.PlaySoundFile(BURNING_SOUND, 4, x, y+h, z)
	
			-- update table
			if (data.steps > 1) then
				data.steps = data.steps - 1
				unitBurningTable[unitID] = data
			else
				unitBurningTable[unitID] = nil
			end
		else
			unitBurningTable[unitID] = nil
		end
	end
	
	-- process unit XP gain
	local xp = 0
	for unitId,addedXP in pairs(unitXPTable) do  
		xp = spGetUnitExperience(unitId)
		if (xp) then
			spSetUnitExperience(unitId, xp + addedXP)
		end
		
		unitXPTable[unitId] = nil
	end

	-- mark stunned aircraft
	local stunned = false
	for unitId,_ in pairs(aircraftTable) do  
		_,stunned,_ = spGetUnitIsStunned(unitId)
		if (stunned) then
			stunnedAircraftTable[unitId] = true
		else
			stunnedAircraftTable[unitId] = nil			
		end
	end
end

-- cleanup and/or spawn extra effects when some units are destroyed
function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)

	-- store damage modifier from upgrades, for projectiles in flight
	local dmgMod = spGetUnitRulesParam(unitID, "upgrade_damage")
	if (dmgMod) then
		dmgModDeadUnits[unitID] = dmgMod
	else 
		dmgModDeadUnits[unitID] = 0
	end

	-- remove entries from tables when unit is destroyed
	if baseUnitColvolTable[unitID] then
		baseUnitColvolTable[unitID] = nil
	end
	if unitBurningTable[unitID] ~= nil then
		unitBurningTable[unitID] = nil
	end
	if aircraftTable[unitID] ~= nil then
		aircraftTable[unitID] = nil
	end
	if stunnedAircraftTable[unitID] ~= nil then
		stunnedAircraftTable[unitID] = nil
	end	
	if unitXPTable[unitID] ~= nil then
		unitXPTable[unitID] = nil
	end
	if damagedUnitFrameTable[unitID] ~= nil then
		damagedUnitFrameTable[unitID] = nil
	end
	
	-- spawn a fireball when canister dies
	if UnitDefs[unitDefID].name == "gear_canister" then
		local x,y,z = spGetUnitPosition(unitID)
		local _,_,_,_,bp = spGetUnitHealth(unitID)

		if bp > 0.999 then
			local createdId = Spring.SpawnProjectile(WeaponDefNames["gear_canister_fireball"].id,{
				["pos"] = {x,y,z},
				["end"] = {x,0,z},
				["speed"] = {0,-5,0},
				["owner"] = unitID
			})
		end
	-- spawn a fireball when eruptor dies
	elseif UnitDefs[unitDefID].name == "gear_eruptor" then
		local x,y,z = spGetUnitPosition(unitID)
		local _,_,_,_,bp = spGetUnitHealth(unitID)

		if bp > 0.999 then
			local createdId = Spring.SpawnProjectile(WeaponDefNames["gear_eruptor_fireball"].id,{
				["pos"] = {x,y,z},
				["end"] = {x,0,z},
				["speed"] = {0,-5,0},
				["owner"] = unitID
			})
		end
	end
end

-- if unit has active shield with power > 0, drain damage from shield first instead of going directly to hp
function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	-- disable bass self-damage
	if (weaponDefID == disruptorWaveEffectWeaponDefId and unitDefID == disruptorWaveUnitDefId) then
		return 0
	end
	-- disable magnetar self-damage, but drain shield
	if (weaponDefID == magnetarWeaponDefId) then
		spSetUnitShieldState(unitID, 0)
		if (unitID == attackerID) then
			return 0	
		end
	end
	-- disable upgrade finished effect self-damage
	if (upgradeFinishedDefIds[weaponDefID]) then
		return 0
	end
	
	-- disables unit collision damage
	if (weaponDefID == -3) then
		return 0
	end
	
	-- show animation for AOE damage from disruptor weapons 
	if (weaponDefID == disruptorWaveEffectWeaponDefId or weaponDefID == magnetarWeaponDefId or weaponDefID == magnetarAuraWeaponDefId) then
		local showEffect = false
		if weaponDefID == magnetarAuraWeaponDefId then
			if math.random() < 0.2 then
				showEffect = true
			end
		else 
			showEffect = true
		end
		
		if (showEffect) then
			local _,_,_,x,y,z = spGetUnitPosition(unitID,true)
			if x ~= nil then
				Spring.SpawnCEG(EMP_CEG, x - 10 + math.random(20), y, z - 10 + math.random(20), 0, 1, 0,30 ,30)
				--Spring.PlaySoundFile(EMP_SOUND, 4, x, y+h, z)
			end
		end
	end
	 
	-- increase damage due to veteran status for continuous beam weapons
	-- to compensate for not getting reload time reduction
	local dmgMod = 0 
	if (continuousBeamWeaponDefIds[weaponDefID]) then
		if attackerID and attackerID > 0 then
			local xp = spGetUnitExperience(attackerID)
			local xpMod = 1
            if xp and xp > 0 then
        		xpMod = 1+0.35*(xp/(xp+1))
            end		 
        	damage = damage	* xpMod
		end
	end

	-- increase damage based on attacker's damage modifiers, if any
	dmgMod = 0
	if attackerID and attackerID > 0 then 
		if dmgModDeadUnits[attackerID] then
			dmgMod = dmgModDeadUnits[attackerID]
		else
			dmgMod = spGetUnitRulesParam(attackerID, "upgrade_damage")
		end
		if dmgMod and dmgMod ~= 0 then
			damage = damage	* (1 + dmgMod)
			--Spring.Echo("deals more dmg : "..damage.." (x"..(1+dmgMod)..")")
		end
	end
	
	-- add/refresh burning debuff, limit fire aoe damage
	if ( burningEffectWeaponDefIds[weaponDefID]) then
		unitBurningTable[unitID] = {steps = FIRE_DMG_STEPS,unitDefID = unitDefID, attackerID = attackerID}

		if ( burningAOEPerStepWeaponDefIds[weaponDefID]) then
			local finalDamage = damage
			-- decrease damage based on defender's hp modifiers, if any 
			local defMod = spGetUnitRulesParam(unitID, "upgrade_hp")
			if defMod and defMod ~= 0 then
				finalDamage = finalDamage	/ (1 + defMod)
			end
			
			local oldDmg = unitBurningDPStepTable[unitID]
			local newDmg = 0
			if oldDmg == nil then
				oldDmg = 0
			end
			
			newDmg = oldDmg + finalDamage
			
			if oldDmg < FIRE_AOE_DMG_MAX_PER_STEP and newDmg > FIRE_AOE_DMG_MAX_PER_STEP then
				finalDamage = FIRE_AOE_DMG_MAX_PER_STEP - oldDmg
			elseif newDmg > FIRE_AOE_DMG_MAX_PER_STEP then
				finalDamage = 0
			end
			
			--if newDmg > FIRE_AOE_DMG_MAX_PER_STEP then
				--Spring.Echo("Fire AOE damage prevented : threshold="..(FIRE_AOE_DMG_MAX_PER_STEP*6).." total="..(newDmg*6))
			--end
			
			unitBurningDPStepTable[unitID] = newDmg
			
			return finalDamage 
		end 
	end

	-- get unit shield status
	local shieldEnabled,oldShieldPower = spGetUnitShieldState(unitID)

	if shieldEnabled and oldShieldPower > 0 and not (largeShieldUnits[unitDefID] == true) then
		local newShieldPower = oldShieldPower
		local damageAbsorbedByShield = 0
		local hitPower = weaponHitpowerTable[weaponDefID]
		local armorType = unitArmorTypeTable[unitDefID]
		local correctedDamage = damage
		local factor = 1
		
		if (hitPower ~= nil and armorType ~= nil) then
			if (hitPower == "L" and armorType == "H") then
		    	factor = 4
			elseif (hitPower == "L" and armorType == "M") then
				factor = 2
			elseif (hitPower == "M" and armorType == "H") then
				factor = 2
			end
			correctedDamage = damage * factor
		end
	  
		-- calculate how much dmg the shield absorbed
		if correctedDamage < oldShieldPower then
			newShieldPower = oldShieldPower - correctedDamage
			damageAbsorbedByShield = correctedDamage
	    else 
	    	newShieldPower = 0
			damageAbsorbedByShield = oldShieldPower 
		end

		-- update shield state
		spSetUnitShieldState(unitID, newShieldPower)

		-- Echo("unit " .. unitID .. " ("..armorType.. ") : shield absorbed " .. math.floor(damageAbsorbedByShield) .. " damage ("..hitPower.. ") ".. math.floor(oldShieldPower) .. " -> " .. math.floor(newShieldPower).. " unit takes "..math.max(math.ceil((correctedDamage - damageAbsorbedByShield)/factor),0))


		finalDamage = math.max(math.ceil((correctedDamage - damageAbsorbedByShield)/factor),0)

		-- decrease damage based on defender's hp modifiers, if any 
		local defMod = spGetUnitRulesParam(unitID, "upgrade_hp")
		if defMod and defMod ~= 0 then
			finalDamage = finalDamage	/ (1 + defMod)
		end

		-- adds % of paralyzer damage as normal damage to HP
		if (paralyzer) then
			spAddUnitDamage(unitID,finalDamage*PARALYZE_DAMAGE_FACTOR,0,attackerID)
		
			-- amplify paralyzer damage for lower hp units
			local health,maxHealth,_,_,_ = spGetUnitHealth(unitID)
			local factor = 1 + (1 - max(health,0)/maxHealth)
			finalDamage = finalDamage * factor
		end
		
		return finalDamage
	end
	
	-- decrease damage based on defender's hp modifiers, if any 
	local defMod = spGetUnitRulesParam(unitID, "upgrade_hp")
	if defMod and defMod ~= 0 then
		damage = damage	/ (1 + defMod)
		--Spring.Echo("takes less dmg : "..(1/ (1 + defMod)))
	end
	
	-- adds % of paralyzer damage as normal damage to HP
	if (paralyzer) then
		spAddUnitDamage(unitID,damage*PARALYZE_DAMAGE_FACTOR,0,attackerID)

		-- amplify paralyzer damage for lower hp units
		local health,maxHealth,_,_,_ = spGetUnitHealth(unitID)
		local factor = 1 + (1 - max(health,0)/maxHealth) * PARALYZE_MISSING_HP_FACTOR
		return damage * factor
	end
	
	return damage
end

-- handle XP modifier when units take damage from enemies
function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if (unitDefID == targetDefId) then
		targetDamage = targetDamage + damage
		return
	end
	if (attackerTeam and (not spAreTeamsAllied(unitTeam,attackerTeam))) then
		-- add entry to table
		if unitXPTable[unitID] == nil then
			unitXPTable[unitID] = 0
		end
		
		local health,maxHealth,_,_,_ = spGetUnitHealth(unitID) 
		local frac = damage / maxHealth
		unitXPTable[unitID] = unitXPTable[unitID] + frac * UNIT_DAMAGE_XP
	end
	if (damage > 0 ) then
		damagedUnitFrameTable[unitID] = spGetGameFrame()
		--Spring.Echo("UNIT DAMAGED unitId="..unitID.." f="..spGetGameFrame())
	end 
end

function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)
	--Spring.Echo("STEP builderId="..builderID.." unitId="..unitID.." part="..part)
	
	-- if unit got damaged recently, deny half of the build steps
	local f = spGetGameFrame()
	if damagedUnitFrameTable[unitID] and (f - damagedUnitFrameTable[unitID] < DAMAGE_REPAIR_DISRUPT_FRAMES) then
		if f%2 == 0 then
			return false
		end
	end
	return true
end