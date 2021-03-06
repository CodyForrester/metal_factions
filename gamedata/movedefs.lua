--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    moveDefs.lua
--  brief:   move data definitions
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local commonDepthModParams = {
	quadraticCoeff = 0,
	linearCoeff = 0,
}

local moveDefs = {
	smallboat = {
		footprintx=3,
		footprintz=3,
		minwaterdepth=5,
		crushStrength=50,
	},
	MEDIUMBOAT = {
		footprintx=4,
		footprintz=4,
		minwaterdepth=18,
		crushstrength=200,
	},
	LARGEBOAT = {
		FootprintX=7,
		FootprintZ=7,
		MinWaterDepth=30,
		CrushStrength=1600,
	},
	KBOTHT4 = {
		FootprintX=4,
		FootprintZ=4,
		MaxWaterDepth=35,
		MaxSlope=36,
		CrushStrength=70,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	KBOTHT3 = {
		FootprintX=3,
		FootprintZ=3,
		MaxWaterDepth=35,
		MaxSlope=36,
		CrushStrength=40,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	KBOTHT2 = {
		FootprintX=2,
		FootprintZ=2,
		MaxWaterDepth=35,
		MaxSlope=36,
		CrushStrength=0,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	KBOTUW3 = {
		FootprintX=3,
		FootprintZ=3,
		Submarine=1,
		MaxWaterSlope=40,
		MaxSlope=36,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	KBOTAT = {
		FootprintX=3,
		FootprintZ=3,
		MaxWaterDepth=35,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKBH3 = {
		FootprintX=3,
		FootprintZ=3,
		MaxWaterDepth=35,
		MaxSlope=32,
		CrushStrength=100,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKDH3 = {
		FootprintX=3,
		FootprintZ=3,
		Submarine=1,
		MaxWaterSlope=40,
		MaxSlope=31,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	KBOTDS2 = {
		FootprintX=2,
		FootprintZ=2,
		Submarine=1,
		MaxWaterSlope=32,
		MaxSlope=32,
		CrushStrength=150,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKHOVER2 = {
		FootprintX=2,
		FootprintZ=2,
		MaxSlope=26,
		BadSlope=26,
		MaxWaterSlope=255,
		BadWaterSlope=255,
		CrushStrength=10,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKHOVER3 = {
		FootprintX=3,
		FootprintZ=3,
		MaxSlope=26,
		BadSlope=26,
		MaxWaterSlope=255,
		BadWaterSlope=255,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKHOVER4 = {
		FootprintX=4,
		FootprintZ=4,
		MaxSlope=26,
		BadSlope=26,
		MaxWaterSlope=255,
		BadWaterSlope=255,
		CrushStrength=50,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKHOVER5 = {
		FootprintX=5,
		FootprintZ=5,
		MaxSlope=26,
		BadSlope=26,
		MaxWaterSlope=255,
		BadWaterSlope=255,
		CrushStrength=50,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKSH2 = {
		FootprintX=2,
		FootprintZ=2,
		MaxWaterDepth=35,
		MaxSlope=32,
		CrushStrength=10,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKSH3 = {
		FootprintX=3,
		FootprintZ=3,
		MaxWaterDepth=35,
		MaxSlope=32,
		CrushStrength=15,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKSH4 = {
		FootprintX=4,
		FootprintZ=4,
		MaxWaterDepth=35,
		MaxSlope=32,
		CrushStrength=100,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKBH4 = {
		FootprintX=4,
		FootprintZ=4,
		MaxSlope=32,
		CrushStrength=400,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	BOATSUB = {
		FootprintX=4,
		FootprintZ=4,
		MinWaterDepth=36,
		CrushStrength=100,
		Submarine=1,
		depthmodparams=commonDepthModParams,
	},
	BOATSUB5 = {
		FootprintX=5,
		FootprintZ=5,
		MinWaterDepth=36,
		CrushStrength=100,
		Submarine=1,
		depthmodparams=commonDepthModParams,
	},
	KBOTATUW = {
		FootprintX=3,
		FootprintZ=3,
		CrushStrength=150,
		Submarine=1,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKDH5 = {
		FootprintX=5,
		FootprintZ=5,
		Submarine=1,
		MaxWaterSlope=40,
		MaxSlope=31,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	TANKDH6 = {
		FootprintX=6,
		FootprintZ=6,
		Submarine=1,
		MaxWaterSlope=40,
		MaxSlope=31,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	},
	KBOTUW4 = {
		FootprintX=4,
		FootprintZ=4,
		Submarine=1,
		MaxWaterSlope=40,
		MaxSlope=36,
		CrushStrength=30,
		depthmodparams=commonDepthModParams,
		slopemod=6,
	}
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- convert from map format to the expected array format

local array = {}
local i = 1
for k,v in pairs(moveDefs) do
	--v.heatmapping = false -- disable heatmapping
	v.allowRawMovement = true
	array[i] = v
	v.name = k
	i = i + 1
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return array

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
