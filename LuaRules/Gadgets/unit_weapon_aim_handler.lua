function gadget:GetInfo()
   return {
      name = "Weapon Aim Handler Gadget",
      desc = "Overrides weapon targeting in some cases",
      author = "raaar",
      date = "2018",
      license = "PD",
      layer = 1,
      enabled = true,
   }
end

local Echo = Spring.Echo
local floor = math.floor
local ceil = math.ceil
local max = math.max
local spGetUnitWeaponTestRange = Spring.GetUnitWeaponTestRange 
local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitPosition = Spring.GetUnitPosition

local targetForUnitId = {}
local trackedWeaponDefIds = {}

local LOWEST_PRIORITY = 500000000

local torpedoWeaponIds = {
	-- AVEN
	[WeaponDefNames["aven_u1commander_torpedo"].id]=true,
	[WeaponDefNames["aven_u2commander_torpedo"].id]=true,
	[WeaponDefNames["aven_u4commander_torpedo"].id]=true,
	[WeaponDefNames["aven_u5commander_torpedo"].id]=true,
	[WeaponDefNames["aven_u6commander_torpedo"].id]=true,
	[WeaponDefNames["aven_commander_torpedo"].id]=true,
	[WeaponDefNames["aven_lurker_torpedo"].id]=true,
	[WeaponDefNames["aven_piranha_torpedo"].id]=true,
	[WeaponDefNames["aven_tl_torpedo"].id]=true,
	[WeaponDefNames["aven_rush_depthcharge"].id]=true,
	[WeaponDefNames["aven_vanguard_depthcharge"].id]=true,
	[WeaponDefNames["armdepthcharge"].id]=true,
	[WeaponDefNames["aven_slider_s_depthcharge"].id]=true,
	
	-- GEAR
	[WeaponDefNames["gear_commander_torpedo"].id]=true,
	[WeaponDefNames["gear_u1commander_torpedo"].id]=true,
	[WeaponDefNames["gear_u2commander_torpedo"].id]=true,
	[WeaponDefNames["gear_u3commander_torpedo"].id]=true,
	[WeaponDefNames["gear_u4commander_torpedo"].id]=true,
	[WeaponDefNames["gear_u5commander_torpedo"].id]=true,
	[WeaponDefNames["gear_snake_torpedo"].id]=true,
	[WeaponDefNames["gear_noser_torpedo"].id]=true,
	[WeaponDefNames["corssub_weapon"].id]=true,
	[WeaponDefNames["gear_tl_torpedo"].id]=true,
	[WeaponDefNames["coredepthcharge"].id]=true,
	[WeaponDefNames["gear_viking_depthcharge"].id]=true,
	-- CLAW
	[WeaponDefNames["claw_commander_torpedo"].id]=true,
	[WeaponDefNames["claw_u1commander_torpedo"].id]=true,
	[WeaponDefNames["claw_u2commander_torpedo"].id]=true,
	[WeaponDefNames["claw_u3commander_torpedo"].id]=true,
	[WeaponDefNames["claw_u4commander_torpedo"].id]=true,
	[WeaponDefNames["claw_u5commander_torpedo"].id]=true,
	[WeaponDefNames["claw_u6commander_torpedo"].id]=true,
	[WeaponDefNames["claw_spine_torpedo"].id]=true,
	[WeaponDefNames["claw_monster_torpedo"].id]=true,
	[WeaponDefNames["claw_sinker_depthcharge"].id]=true,
	[WeaponDefNames["claw_drakkar_depthcharge"].id]=true,
	-- SPHERE
	[WeaponDefNames["sphere_commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_u1commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_u2commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_u3commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_u4commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_u5commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_u6commander_torpedo"].id]=true,
	[WeaponDefNames["sphere_crab_torpedo"].id]=true,
	[WeaponDefNames["sphere_carp_torpedo"].id]=true,
	[WeaponDefNames["sphere_pluto_torpedo"].id]=true,
	[WeaponDefNames["sphere_clam_torpedo"].id]=true,
	[WeaponDefNames["sphere_endeavour_depthcharge"].id]=true,
	[WeaponDefNames["sphere_oyster_torpedo"].id]=true
}


-- track unit's weapons
local function trackWeapons(unitDefID)
	local ud = UnitDefs[unitDefID]
	if ud.weapons and ud.weapons[1] and ud.weapons[1].weaponDef then
		for wNum,w in pairs(ud.weapons) do
			if not trackedWeaponDefIds[w.weaponDef] then
				local weap=WeaponDefs[w.weaponDef]
			    if weap.isShield == false and weap.description ~= "No Weapon" then
					trackedWeaponDefIds[w.weaponDef] = true 
					Script.SetWatchWeapon(w.weaponDef,true)
			    end
		    end
		end
    end
end

-------------------------- SYNCED CODE ONLY
if (not gadgetHandler:IsSyncedCode()) then
	return false
end



function gadget:Initialize()
	-- track torpedoes fired from submarines
	for id,_ in pairs(torpedoWeaponIds) do
		Script.SetWatchWeapon(id,true)
		--Spring.Echo("WEAPON "..id.." BLOCKED")
	end
end


-- mark units that targeted other units for attack
-- clear marking if STOP command is used
function gadget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if cmdID == CMD.ATTACK then
		--Spring.Echo("attacker="..unitID)
		--for i,v in ipairs(cmdParams) do
		--	Spring.Echo("cmdParams["..i.."]="..v)
		--end

		if cmdParams then
			local targetId = tonumber(cmdParams[1])
			if Spring.ValidUnitID(targetId) then
				--Spring.Echo("target is "..targetId.." / "..UnitDefs[Spring.GetUnitDefID(targetId)].name)
				targetForUnitId[unitID] = tonumber(cmdParams[1])
				trackWeapons(unitDefID) -- required for AllowWeaponTarget to be called
			end
		end		
	end
	if cmdID == CMD.STOP then
		targetForUnitId[unitID] = nil
		--Spring.Echo("target cleared for "..unitID)
	end
end

-- weapon target check
function gadget:AllowWeaponTarget(attackerID, targetID, attackerWeaponNum, attackerWeaponDefID, defaultPriority)
	--Spring.Echo(attackerID.." ALLOWTARGET "..targetID.." ? prio="..tostring(defaultPriority))
	--Spring.Echo(attackerID.." has line of fire to "..targetID.." ? "..tostring(Spring.GetUnitWeaponHaveFreeLineOfFire(attackerID,attackerWeaponNum,targetID)))
	
	
	if defaultPriority == nil then
		defaultPriority = LOWEST_PRIORITY
	end
	
	-- TODO : this is not working, probable engine bug (this was true on 104.0, check on 104.0.1)
	-- it does work but only if the owner is busy, else an attack order is added and it'll start firing
	if torpedoWeaponIds[attackerWeaponDefID] then
		-- if target is on land, return false
		local x,y,z = spGetUnitPosition(targetID)
		local h = spGetGroundHeight(x,z)
		if (h > 0 or y > 30) then
			--Spring.Echo("TORPEDO FIRING AT LAND "..Spring.GetGameFrame())
			return false,0
		end
	end
	
	if targetForUnitId[attackerID] then
		-- only do this if in range of the target
		if (spGetUnitWeaponTestRange(attackerID, attackerWeaponNum, targetForUnitId[attackerID]) == true) then
			--Spring.Echo("in range "..tonumber(targetForUnitId[attackerID]).." / "..UnitDefs[Spring.GetUnitDefID(targetForUnitId[attackerID])].name)

			-- if unit is marked as target, reject all other targets
			if targetForUnitId[attackerID] == targetID then
				--Spring.Echo("focus "..tonumber(targetID).." / "..UnitDefs[Spring.GetUnitDefID(targetID)].name)
				return true,defaultPriority
			else
				return false,defaultPriority
			end
		else
			-- out of range, clear target
			targetForUnitId[attackerID] = nil
		end
	end
	
	return true,defaultPriority
end

-- cleanup target markings when attacker or target is destroyed
function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	-- attacker destroyed
	if targetForUnitId[unitID] then
		targetForUnitId[unitID] = nil
	end
	
	-- target destroyed
	for uId,tId in pairs(targetForUnitId) do
		if tId == unitID then
			targetForUnitId[uId] = nil
		end
	end
end