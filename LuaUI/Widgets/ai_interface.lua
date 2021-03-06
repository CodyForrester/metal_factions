function widget:GetInfo()
  return {
    name      = "AI interface",
    desc      = "Adds actions to some key, mouse and chat message combinations meant for AI interaction",
    author    = "raaar",
    date      = "2020",
    license   = "PD",
    layer     = 1000,
    enabled   = true
  }
end

include("keysym.h.lua")

local aiBeaconMode = false
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local spGetPlayerList = Spring.GetPlayerList
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetLocalPlayerID = Spring.GetLocalPlayerID
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
local spSendMessageToPlayer = Spring.SendMessageToPlayer

local floor = math.floor
local MOUSE_LEFT = 1
local MOUSE_MID =2
local MOUSE_RIGHT = 3

local SYSTEM_PREFIX_PATTERNS	= {"%[~"}
local NAME_PREFIX_PATTERNS		= {"%<", "%["}
local NAME_POSTFIX_PATTERNS		= {"%> ", "%] "}

local AI_MSG_PREFIX = "#AI"

---------- helper functions

-- extract a player name from a text message
-- (note: this can generate false positives if
-- player has name of form "<XYZ>" or "[XYZ]"
-- for certain system messages since strings
-- returned will then be "XYZ>" and "XYZ]"
-- rather than "")
-- copied from the message separator widget
function getPlayerName(playerMessage)
	-- if on loading sequence, assume it's not a player
	if (string.find(playerMessage, SYSTEM_PREFIX_PATTERNS[1]) == 1) then
		return ""
	end

	local i1 = string.find(playerMessage, NAME_PREFIX_PATTERNS[1])
	local i2 = string.find(playerMessage, NAME_POSTFIX_PATTERNS[1])

	if (i1 ~= nil and i2 ~= nil and i1 == 1) then
		-- player messages start with "<" so start index is 2
		return (string.sub(playerMessage, 2, i2 - 1))
	end

	local j1 = string.find(playerMessage, NAME_PREFIX_PATTERNS[2])
	local j2 = string.find(playerMessage, NAME_POSTFIX_PATTERNS[2])

	if (j1 ~= nil and j2 ~= nil and j1 == 1) then
		-- spectator messages start with "[" so start index is 2
		return (string.sub(playerMessage, 2, j2 - 1))
	end

	-- no match found
	return ""
end


function getPlayerIdFromName(playerName)
	local players = spGetPlayerList()
	local playerId = nil
	for i,pId in ipairs(players) do
		local name = spGetPlayerInfo(pId)
		if (name == playerName) then
			---Spring.Echo("id="..pId.." name="..name)
			playerId = pId
		end
	end
	
	return playerId
end




---------- callins

function widget:Initialize()

end


function widget:KeyPress(key, mods, isRepeat)
	if mods.ctrl and mods.alt then
		aiBeaconMode = true
	end
end

-- workaround for menu not showing up
function widget:KeyRelease()
	aiBeaconMode = false
end


function widget:MousePress(mx,my,button)
	if (aiBeaconMode) then
		local type, pos = spTraceScreenRay(mx, my, true)
		if pos then 
			if button == MOUSE_LEFT then
				Spring.SendLuaRulesMsg("SETBEACON|"..floor(pos[1]).."|"..floor(pos[2]).."|"..floor(pos[3]))	
				return false	
			elseif button == MOUSE_RIGHT then
				Spring.SendLuaRulesMsg("REMOVEBEACON|"..floor(pos[1]).."|"..floor(pos[2]).."|"..floor(pos[3]))	
				return false	
			end
		end
	end
end

-- check console message, figure out if it's an AI command sent by the player and forward it
-- TODO find another way to do this
function widget:AddConsoleLine(line)
	if (string.len(line) > 0 and string.find(line, AI_MSG_PREFIX)) then
		local playerName = getPlayerName(line)
		local playerId = getPlayerIdFromName(playerName)
		local myPlayerId = spGetLocalPlayerID()
		if (playerId == myPlayerId) then
			local msg = string.sub(line, string.find(line, AI_MSG_PREFIX),-1)  
			local tokens = {}
			-- get tokens
			for token in string.gmatch(msg, "[^%s]+") do
   				tokens[#tokens+1] = token
			end

			if #tokens == 1 then
				spSendMessageToPlayer(myPlayerId,"usage : #AI [<playerId>] <command> <parameters>\nAvailable commands :\nSTATUS : show current status\nSTRATEGY <strategyName> : change strategy\nCOMPAD : give the player a commander pad")
				return
			end
			
			if #tokens >= 2 then
				local str = ""
				for i,token in ipairs(tokens) do
					if i > 1 then
						if i > 2 then
							str = str.."|"..token
						else
							str = str..token
						end
					end
				end
				spSendLuaRulesMsg(str)				
			end
		end
	end
end
