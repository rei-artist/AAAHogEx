require("utils.nut");
require("tile.nut");
require("aystar.nut");
require("pathfinder.nut");
require("roadpathfinder.nut");
require("place.nut");
require("station.nut");
require("estimator.nut");
require("route.nut");
require("trainroute.nut");
require("railbuilder.nut");
require("road.nut");
require("water.nut");
require("air.nut");


class HogeAI extends AIController {
	static version = 110;

	static container = Container();
	static notBuildableList = AIList();
	
	static distanceEstimateSamples = [];
	static distanceSampleIndex = [];
	static productionEstimateSamples = [10, 20, 30, 50, 80, 130, 210, 340, 550, 890, 1440, 2330, 3770];

	turn = null;
	indexPointer = null;
	stockpiled = null;
		
	openttdVersion = null;
	hogeNum = null;
	hogeIndex = null;
	maxStationSpread = null;
	maxTrains = null;
	maxRoadVehicle = null;
	maxShips = null;
	maxAircraft = null;
	isUseAirportNoise = null;
	isDistantJoinStations = null;
	isInfrastructureMaintenance = null;
	futureIncomeRate = null;
	freightTrains = null;
	trainSlopeSteepness = null;
	roadvehSlopeSteepness = null;
	maxLoan = null;
	dayLengthFactor = null;
	prevLoadAmount = null;
	

	roiBase = null;
	buildingTimeBase = null;
	vehicleProfibitBase = null;
	
	estimateTable = null;
	routeCandidates = null;
	constructions = null;
	pendingConstructions = null;
	maybePurchasedLand = null;
	pathFindLimit = null;
	loadData = null;
	lastIntervalDate = null;
	passengerCargo = null;
	mailCargo = null;
	paxMailCargos = null;
	supressInterval = null;
	limitDate = null;
	isTimeoutToMeetSrcDemand = null;
	pathfindings = null;
	townRoadType = null;
	clearWaterCost = null;
	waterRemovable = null;
	roadTrafficRate = null;
	canUsePlaceOnWater = null;
	waitForPriceStartDate = null;
	maxRoi = null;
	cargoVtDistanceValues = null;
	pendingCoastTiles = null;
	intervalSpan = null;
	lastTransferCandidates = null;
	isRich = null;
	lastScanRouteDates = null;
	mountain = null;
	noRouteCnadidates = null;
	
	yeti = null;
	ecs = null;
	firs = null;
	
	static function GetPassengerCargo() {
		local self = HogeAI.Get();
		if(self.passengerCargo == null) {
			local cargoList = AICargoList();
			cargoList.Valuate(AICargo.HasCargoClass, AICargo.CC_PASSENGERS);
			cargoList.KeepValue(1);
			if(cargoList.Count()==0) {
				AILog.Warning("No CC_PASSENGERS cargo");
				self.passengerCargo = false;
			} else {
				if(cargoList.Count()>=2) {
					cargoList.Valuate(function(e) {
						return AICargo.GetCargoLabel(e) == "PASS" ? 1 : 0
					});
					cargoList.KeepValue(1);
				}
				self.passengerCargo = cargoList.Begin();
			}
		}
		if(self.passengerCargo==false) {
			return null;
		}
		
		return self.passengerCargo;
	}
	
	static function GetMailCargo() {
		local self = HogeAI.Get();
		if(self.mailCargo == null) {
			local cargoList = AICargoList();
			cargoList.Valuate(AICargo.HasCargoClass, AICargo.CC_MAIL);
			cargoList.KeepValue(1);
			if(cargoList.Count()==0) {
				AILog.Warning("No CC_MAIL cargo");
				self.mailCargo = false;
			} else {
				if(cargoList.Count()>=2) {
					cargoList.Valuate(function(e) {
						return AICargo.GetCargoLabel(e) == "MAIL" ? 1 : 0
					});
					cargoList.KeepValue(1);
				}
				self.mailCargo = cargoList.Begin();
			}
		}
		if(self.mailCargo==false) {
			return null;
		}
		return self.mailCargo;
	}
	
	function GetPaxMailCargos() {
		if(paxMailCargos==null) {
			paxMailCargos = [];
			foreach(cargo in [GetPassengerCargo(),GetMailCargo()]) {
				if(cargo != null) {
					paxMailCargos.push(cargo);
				}
			}
		}
		return paxMailCargos;
	}

	static function PlantTree(tile) {
		local town = AITile.GetTownAuthority(tile);
		if(AITown.IsValidTown(town)) {
			HogeAI.PlantTreeTown(town);
		}
	}
	
	static function PlantTreeTown(town) {
		local execMode = AIExecMode();
		HgLog.Info("PlantTree town before rating:" + AITown.GetRating (town, AICompany.COMPANY_SELF)+" "+AITown.GetName(town));
		HogeAI.WaitForMoney(1000);
		local townTile = Rectangle.Center(HgTile(AITown.GetLocation(town)),10).lefttop.tile;
		AITile.PlantTreeRectangle(townTile,20,20);
		AIController.Sleep(10);
		HgLog.Info("after town rating:" + AITown.GetRating (town, AICompany.COMPANY_SELF));
	}
	
	static function IsBuildable(tile) {
		if(HogeAI.notBuildableList.HasItem(tile)) {
			return false;
		}
		if(AITile.IsBuildable(tile)) {
			return true;
		}
		if(HogeAI.Get().CanRemoveWater() && AITile.IsSeaTile(tile)) {
			return true;
		}
		/*実効性が薄いのでやらない
		if(HogeAI.IsPurchasedLand(tile)) {
			return true;
		}*/
		return false;
	}
	
	static function IsPurchasedLand(tile) {
		if(!HogeAI.Get().maybePurchasedLand.rawin(tile)) {
			return false;
		}
		if(!AICompany.IsMine(AITile.GetOwner(tile))) {
			return false;
		}
		if(AITile.IsStationTile(tile)) {
			return false;
		}
		if(AIRail.IsRailTile(tile)) {
			return false;
		}
		if(AIRoad.IsRoadTile(tile)) {
			return false;
		}
		if(AIRail.IsRailDepotTile(tile)) {
			return false;
		}
		if(AIRoad.IsRoadDepotTile(tile)) {
			return false;
		}
		return true;
	}
	
	static function IsBuildableRectangle(tile,w,h) {
		if(HogeAI.Get().CanRemoveWater()) {
			foreach(t,k in Rectangle.Corner(HgTile(tile), HgTile(tile)+HgTile.XY(w,h)).GetTileList()) {
				if(!AITile.IsSeaTile(t) && !AITile.IsBuildable(t)) {
					return false;
				}
			}
			return true;
		}
		return AITile.IsBuildableRectangle(tile,w,h);
	}
	
	static function GetTileDistancePathFromPlace(place, path) {
		return path.GetNearestTileDistance(place.GetLocation());
	}
	
	
	static function Get() {
		return HogeAI.container.instance;
	}
	
	constructor() {
		openttdVersion = (AIController.GetVersion() >> 24) - 16;
		if(HogeAI.container.instance != null) {
			HgLog.Error("HogeAI constructor run 2 times");
		}
		HogeAI.container.instance = this;
		turn = 1;
		indexPointer = 0;
		stockpiled = false;
		pathFindLimit = 80;
		estimateTable = {};
		maybePurchasedLand = {};
		
		supressInterval = false;
		yeti = false;
		ecs = false;
		firs = false;
		isTimeoutToMeetSrcDemand = false;
		pathfindings = {};
		canUsePlaceOnWater = false;
		maxRoi = 0;
		cargoVtDistanceValues = {};
		pendingCoastTiles = [];
		intervalSpan = 7;
		lastTransferCandidates = {};
		waterRemovable = false;
		routeCandidates = RouteCandidates();
		constructions = [];
		pendingConstructions = {};
		lastScanRouteDates = {};
		noRouteCnadidates = false;
	}
	
	function Start() {
		SetCompanyName();
		HgLog.Info("AAAHogEx Started! version:"+HogeAI.version+" name:"+AICompany.GetName(AICompany.COMPANY_SELF));
		HgLog.Info("openttd version:"+openttdVersion);
		
		
		/*
		foreach(town,_ in AITownList()) {
			local s = []
			foreach(te in [ AICargo.TE_PASSENGERS ,  AICargo.TE_MAIL , AICargo.TE_GOODS , AICargo.TE_WATER, AICargo.TE_FOOD]) {
				s.push(AITown.GetCargoGoal(town, te));
			}
			HgLog.Info(AITown.GetName(town)+" "+HgArray(s));
		}*/

		/*
		foreach(industry,_ in AIIndustryList()) {
			if(AIIndustry.GetAmountOfStationsAround(industry) >= 1) {
				local tileList = AITileList_IndustryAccepting(industry,5);
				tileList.Valuate(AITile.IsStationTile);
				tileList.RemoveValue(0);
				tileList.Valuate(AITile.GetOwner);
				tileList.RemoveValue(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF));
				if(tileList.Count() >= 1) {
					local tile = tileList.Begin();
					local station = AIStation.GetStationID(tile);
					local vehicleList = AIVehicleList_Station(station);
					HgLog.Info("industry "+AIIndustry.GetName(industry) + " is used by other company ["+AICompany.GetName(tileList.GetValue(tile))+"] vehicleList:"+vehicleList.Count());
					foreach(cargo in AICargoList() ) {
						if(AIStation.GetCargoWaiting(station, cargo) >= 1) {
							HgLog.Info("cargo:"+AICargo.GetName(cargo)+" GetCargoWaiting:true");
						}
					}
				}
			}
		}*/
			
		
		
		/*
		local depot = RoadRoute.CreateDepotNear( HgTile.XY(236,205).tile, AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin())
		HgLog.Warning("CreateDepotNear:"+depot);*/
		/*
		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());
		{
			local execMode = AIExecMode();
			local r = AIRoad.BuildDriveThroughRoadStation(HgTile.XY(358,526).tile, HgTile.XY(359,526).tile, AIRoad.ROADVEHTYPE_BUS , AIStation.STATION_NEW)
			HgLog.Warning("GetLastErrorString:"+r+" "+AIError.GetLastErrorString());
		
		}
		{
			local testMode = AITestMode();
			local r = AIRoad.BuildDriveThroughRoadStation(HgTile.XY(358,526).tile, HgTile.XY(359,526).tile, AIRoad.ROADVEHTYPE_BUS , AIStation.STATION_NEW)
			HgLog.Warning("GetLastErrorString:"+r+" "+AIError.GetLastErrorString());
			//HgLog.Warning("IsBusyRoad:"+RoadPathFinder.IsBusyRoad(HgTile.XY(160,140).tile));
		}*/
		
/*		local result = AIRoad.CanBuildConnectedRoadPartsHere(HgTile.XY(221,203).tile, HgTile.XY(222,203).tile, HgTile.XY(221,204).tile);
		HgLog.Warning("CanBuildConnectedRoadPartsHere "+result);*/
		
		//HgLog.Warning("AICompany.GetOwner:"+(AICompany.COMPANY_INVALID == AITile.GetOwner(HgTile.XY(228,202).tile)));	

		/*
		if(!AIRoad.BuildDriveThroughRoadStation(HgTile.XY(143,162).tile, HgTile.XY(143,163).tile, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW)) {
			HgLog.Warning("BuildDriveThroughRoadStation failed "+AIError.GetLastErrorString());
		} else {
			HgLog.Warning("BuildDriveThroughRoadStation succeeded");
		}
		*/
		
		/*
		local a = [];
		a.push(1);
		a.push(2);
		a.push(3);
		foreach(x in clone a) {
			HgLog.Info("x:"+x);
			ArrayUtils.Remove(a,x);
		}*/
		
		//HgLog.Info("GetCargoAcceptance:"+AITile.GetCargoAcceptance(HgTile.XY(386,465).tile, HogeAI.Get().GetPassengerCargo(), 1, 1, 4));
		
		/*
		local tiles = [];
		local i=0;
		foreach(roadType,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD )) {
			local execMode = AIExecMode();
			local t1 = HgTile.XY(49,126+i);
			local t2 = HgTile.XY(50,126+i);
			AIRoad.SetCurrentRoadType(roadType);
			AIRoad.BuildRoad(t1.tile,t2.tile);
			HgLog.Info("GetBuildCost("+AIRoad.GetName(roadType)+")="+AIRoad.GetBuildCost(roadType,  AIRoad.BT_ROAD));
			HgLog.Info("GetMaintenanceCostFactor("+AIRoad.GetName(roadType)+")="+AIRoad.GetMaintenanceCostFactor(roadType));

			i++;
		}
		i=0;
		foreach(roadType,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_TRAM )) {
			local execMode = AIExecMode();
			local t1 = HgTile.XY(49,126+i);
			local t2 = HgTile.XY(50,126+i);
			tiles.push(t1);
			AIRoad.SetCurrentRoadType(roadType);
			AIRoad.BuildRoad(t1.tile,t2.tile);
			HgLog.Info("GetBuildCost("+AIRoad.GetName(roadType)+")="+AIRoad.GetBuildCost(roadType,  AIRoad.BT_ROAD));
			HgLog.Info("GetMaintenanceCostFactor("+AIRoad.GetName(roadType)+")="+AIRoad.GetMaintenanceCostFactor(roadType));

			i++;
		}*/
		/*
		i = 0;
		local firstRoadType = AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD ).Begin();
		foreach(roadType,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD )) {
			local execMode = AIExecMode();
			local t1 = HgTile.XY(49,126+i);
			local t2 = HgTile.XY(50,126+i);
			AIRoad.SetCurrentRoadType(firstRoadType);
			AIRoad.RemoveRoad(t1.tile,t2.tile);
			i++;
		}*/
		
		/*
		foreach(roadType,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_TRAM )) {
			local execMode = AIExecMode();
			foreach(tile in tiles) {
				HgLog.Info("HasRoadType("+tile+","+AIRoad.GetName(roadType)+")="+AIRoad.HasRoadType(tile.tile, roadType));
			}
			foreach(tile in tiles) {
				AIRoad.SetCurrentRoadType(roadType);
				HgLog.Info("IsRoadTile("+tile+","+AIRoad.GetName(roadType)+")="+AIRoad.IsRoadTile(tile.tile));
			}
			foreach(tile in tiles) {
				local testMode = AITestMode();
				HgLog.Info("ConvertRoadType("+tile+","+AIRoad.GetName(roadType)+")="+AIRoad.ConvertRoadType(tile.tile,tile.tile,roadType)+" "+AIError.GetLastErrorString());
			}
			
			foreach(r,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_TRAM )) {
				HgLog.Info("RoadVehHasPowerOnRoad("+AIRoad.GetName(roadType)+","+AIRoad.GetName(r)+")="+AIRoad.RoadVehHasPowerOnRoad(roadType, r));
			}
		}*/
		
		/* version 13.0以上
		local industryType = AIIndustryType.ResolveNewGRFID(0x4d656f9f, 0x08);
		HgLog.Info("name:"+AIIndustryType.GetName(industryType));
		*/
		
		/*
		local list1 = AITileList();
		local c1 = PerformanceCounter.Start("v1");
		for(local i=0; i<10000; i++) {
			list1.AddRectangle(AIMap.GetTileIndex(10,10),AIMap.GetTileIndex(100,100));
		}
		c1.Stop();
		list1 = AITileList();
		PerformanceCounter.Print();
		local c2 = PerformanceCounter.Start("v2");
		for(local i=0; i<10000; i++) {
			list1.AddRectangle(AIMap.GetTileIndex(10,10),AIMap.GetTileIndex(300,300));
		}
		c2.Stop();
		PerformanceCounter.Print();
		*/
		
		/*
		local list1 = AIList();
		list1.AddItem(1, 4);
		list1.AddItem(2, 3);
		list1.AddItem(3, 2);
		list1.AddItem(4, 1);
		list1.Sort(AIList.SORT_BY_VALUE,true);
		foreach(k,v in list1) {
			HgLog.Info("TestSort:"+k+" "+v);
		}
		list1.Valuate(function(n) {
			return [9,7,8,6][n-1];
		});
		foreach(k,v in list1) {
			HgLog.Info("TestSort:"+k+" "+v);
		}
		list1.RemoveValue(8);
		foreach(k,v in list1) {
			HgLog.Info("TestSort:"+k+" "+v);
		}*/
		
		
		/*
		local test1 = [];
		local c = PerformanceCounter.Start("TestPush");
		for(local i=0; i<10000; i++) {
			test1.push(i);
		}
		c.Stop();
		local test2 = [];
		local c = PerformanceCounter.Start("TestInsert");
		for(local i=0; i<10000; i++) {
			test2.insert(0,i);
		}
		c.Stop();
		local c = PerformanceCounter.Start("TestRemove");
		for(local i=9999; i>=0; i--) {
			test2.remove(i/2);
		}
		c.Stop();
		
		test1 = [];
		for(local i=0; i<100000; i++) {
			test1.push(AIBase.RandRange(10000));
		}
		
		local c = PerformanceCounter.Start("TestSort");
		test1.sort();
		PerformanceCounter.Print();
		HgLog.Info("r:"+test1[99999]);
		
		local a = [1,2,3];
		a.remove(1);
		foreach(n in a) {
			HgLog.Info(n);
		}
		
		HgLog.Info("aaa:" + (typeof AAA) + " bbb:" + BBB.func(BBB));
		*/
		/*
		local c = PerformanceCounter.Start("TestPow");
		for(local i=0; i<100000; i++) {
			pow(i,0.4); // 2000times/d
		}
		c.Stop();
		PerformanceCounter.Print();
		PerformanceCounter.Print();
		local c = PerformanceCounter.Start("TestSqrt");
		for(local i=0; i<100000; i++) {
			sqrt(i); // 2000times/d
		}
		c.Stop();
		PerformanceCounter.Print();*/

		/*
		local tileList = AITileList();
		tileList.AddRectangle(AIMap.GetTileIndex(1,1) , AIMap.GetTileIndex(300,300))
		local c1 = PerformanceCounter.Start("TestValuate");
		for(local i=0; i<10; i++) {
			tileList.Valuate(AITile.IsCoastTile); // 22days 40000tiles/d
		}
		c1.Stop();
		local c2 = PerformanceCounter.Start("Testforeach");
		for(local i=0; i<10; i++) {
			foreach(t,_ in tileList) {
				AITile.IsCoastTile(t); // 34days  26500tiles/d
			}
		}
		c2.Stop();
		PerformanceCounter.Print();*/

		/*
		local town = AITownList().Begin();
		local pax = HogeAI.GetPassengerCargo();
		local c1 = PerformanceCounter.Start("TestAITown.GetLastMonthProduction1");
		for(local i=0; i<100000; i++) {
			AITown.GetLastMonthProduction (town, pax); // 6days
		}
		c1.Stop();
		local c2 = PerformanceCounter.Start("TestAITown.GetLastMonthProduction2");
		local t = {};
		for(local i=0; i<100000; i++) {
			if(!t.rawin(pax)) { // 8days
				t.rawset(pax, AITown.GetLastMonthProduction(town, pax));
			} else {
				t.rawget(pax);
			}
		}
		c2.Stop();
		PerformanceCounter.Print();*/
		/*
		local tileList = AITileList();
		local p1 = AIMap.GetTileIndex(1,1);
		local p2 = AIMap.GetTileIndex(100,100);
		local c2 = PerformanceCounter.Start("AddRectangle");
		for(local i=0; i<10000; i++) {
			tileList.AddRectangle(p1,p2); //1day
		}
		c2.Stop();
		PerformanceCounter.Print();*/
		/*
		local tileList = AITileList();
		local p1 = AIMap.GetTileIndex(1,1);
		local p2 = AIMap.GetTileIndex(100,100);
		tileList.AddRectangle(p1,p2); //1day
		local c2 = PerformanceCounter.Start("IsCoastTile");
		for(local i=0; i<100; i++) {
			tileList.Valuate(AITile.IsCoastTile); // 37000tiles/d
		}
		c2.Stop();
		PerformanceCounter.Print();	*/
		/*
		local tileList = AITileList();
		local p1 = AIMap.GetTileIndex(1,1);
		local c2 = PerformanceCounter.Start("IsCoastTile");
		for(local i=0; i<1000000; i++) {
			AITile.IsCoastTile(p1); //  18500tiles/d
		}
		c2.Stop();
		PerformanceCounter.Print();*/
		
		//HgLog.Info("test:"+AIMarine.IsCanalTile(HgTile.XY(731,449).tile));
	

		local newGrfList = AINewGRFList();
		newGrfList.Valuate( AINewGRF.IsLoaded );
		newGrfList.KeepValue( 1 );
		
		foreach( newGrf,v in newGrfList ) {
			local name = AINewGRF.GetName(newGrf);
			HgLog.Info("NewGRF:" + name);
			if(name.find("YETI") != null) {
				yeti = true;
				stockpiled = true;
				HgLog.Info("yeti: true");
			}
			if(name.find("ECS") != null) {
				ecs = true;
				stockpiled = true;
				HgLog.Info("ecs: true");
			}
			if(name.find("FIRS") != null || name.find("NAIS") != null || name.find("XIS") != null  || name.find("AIRS") != null) {
				firs = true;
				HgLog.Info("firs: true");
			}
		}
		
		foreach(objectType,v in AIObjectTypeList()) {
			HgLog.Info("objType:" + AIObjectType.GetName(objectType) + " views:"+AIObjectType.GetViews(objectType)+" id:"+objectType);
		}
		dayLengthFactor = "GetDayLengthFactor" in AIDate ? AIDate.GetDayLengthFactor() : 1;
		HgLog.Info("dayLengthFactor:"+dayLengthFactor);

		
		clearWaterCost = BuildUtils.GetClearWaterCost();
		/*
		avoidClearWater = BuildUtils.IsTooExpensiveClearWaterCost();
		if(avoidClearWater) {
			HgLog.Info("avoidClearWater");
		}*/
		
		
		//Rectangle.Test();
		/*
		local engineList = AIEngineList(AIVehicle.VT_AIR);
		foreach(e,v in engineList) {
			HgLog.Info("name:"+AIEngine.GetName(e));
			HgLog.Info("plane type:"+AIEngine.GetPlaneType(e));
			HgLog.Info("max speed:"+AIEngine.GetMaxSpeed(e));
			HgLog.Info("capacity:"+AIEngine.GetCapacity(e));
			HgLog.Info("max order distance:"+AIEngine.GetMaximumOrderDistance(e));
			
		}*/
		
		/*
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		foreach(e,v in engineList) {
			HgLog.Info("--- name:"+AIEngine.GetName(e));
			HgLog.Info("max speed:"+AIEngine.GetMaxSpeed(e));
			HgLog.Info("capacity:"+AIEngine.GetCapacity(e));
			HgLog.Info("IsArticulated:"+AIEngine.IsArticulated(e));
			
		}*/
		
		foreach(industryType,v in AIIndustryTypeList()) {
			local s = "";
			foreach(cargo,v in AIIndustryType.GetProducedCargo(industryType)) {
				s += AICargo.GetCargoLabel(cargo)+",";
			}
			s += "/";
			foreach(cargo,v in AIIndustryType.GetAcceptedCargo(industryType)) {
				s += AICargo.GetCargoLabel(cargo)+",";
			}
			HgLog.Info(
				AIIndustryType.GetName(industryType)+
					" IsRaw:"+AIIndustryType.IsRawIndustry(industryType)+
					" IsProcessing:"+AIIndustryType.IsProcessingIndustry(industryType)+
					" Increase:"+AIIndustryType.ProductionCanIncrease (industryType)+
					" "+s);
		}
		
		foreach(cargo,v in AICargoList()) {
			HgLog.Info("id:"+cargo+" name:"+AICargo.GetName(cargo)+" label:"+AICargo.GetCargoLabel(cargo)+
				" towneffect:"+AICargo.GetTownEffect(cargo)+" IsFreight:"+AICargo.IsFreight(cargo));
			foreach(cargoClass in [  
					AICargo.CC_PASSENGERS,
					AICargo.CC_MAIL,
					AICargo.CC_EXPRESS,
					AICargo.CC_ARMOURED,
					AICargo.CC_BULK,
					AICargo.CC_PIECE_GOODS,
					AICargo.CC_LIQUID,
					AICargo.CC_REFRIGERATED,
					AICargo.CC_HAZARDOUS,
					AICargo.CC_COVERED]) {
				if(AICargo.HasCargoClass(cargo,cargoClass)) {
					HgLog.Info("cargoClass:"+cargoClass);
				}
			}
		}
		/*
		foreach(industry,v in AIIndustryList() ) {
			if(AIIndustry.IsBuiltOnWater( industry )) {
				HgLog.Info(AIIndustry.GetName( industry )
					+ " HasDock:"+AIIndustry.HasDock( industry )
					+ " DockLocation:"+HgTile(AIIndustry.GetDockLocation( industry ))
					+ " Location:"+HgTile(AIIndustry.GetLocation(industry)));
				foreach(cargo in AICargoList_IndustryProducing(industry)) {
					HgLog.Info("produce:"+AICargo.GetName(cargo));
				}
				foreach(cargo in AICargoList_IndustryAccepting(industry)) {
					HgLog.Info("accepting:"+AICargo.GetName(cargo));
				}
			}
		}*/

		local loadTypes = AIList();
		loadTypes.AddList(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD));
		loadTypes.AddList(AIRoadTypeList(AIRoad.ROADTRAMTYPES_TRAM));
		loadTypes.Valuate(AIRoad.GetRoadTramType);
		HgLog.Info("ROADTYPE_ROAD:"+AIRoad.ROADTYPE_ROAD);
		HgLog.Info("ROADTYPE_TRAM:"+AIRoad.ROADTYPE_TRAM);
		foreach(roadType,roadTramType in loadTypes) {
			HgLog.Info("RoadType:"+roadType+" "+AIRoad.GetName(roadType)+" isTram:"+(roadTramType==AIRoad.ROADTRAMTYPES_TRAM));
		}
		
		UpdateSettings();
		
		HgLog.Info("maxStationSpread:"+maxStationSpread);
		HgLog.Info("maxTrains:"+maxTrains);
		HgLog.Info("maxRoadVehicle:"+maxRoadVehicle);
		HgLog.Info("maxShips:"+maxShips);
		HgLog.Info("maxAircraft:"+maxAircraft);
		HgLog.Info("isUseAirportNoise:"+isUseAirportNoise);
		HgLog.Info("maxAircraft:"+maxAircraft);
		
		/*
		local te = 495;
		local power = 1622;
		local maxSpeed = 144;
		local requestSpeed = 30;
		local a = VehicleUtils.GetAcceleration( VehicleUtils.GetSlopeForce(464,464) + VehicleUtils.GetAirDrag(requestSpeed, maxSpeed, requestSpeed), requestSpeed, te, power, 464);
		HgLog.Info("acc:"+a);*/
		
		CheckMountain();

		townRoadType = TownBus.CheckTownRoadType();


		AICompany.SetAutoRenewStatus(false);

		distanceEstimateSamples.clear();
		local maxDistance = max(AIMap.GetMapSizeX(), AIMap.GetMapSizeY());
		local pred = 10;
		local d = 10;
		while(d < maxDistance) {
			local newd = d + pred;
			pred = d;
			d = newd;
			distanceEstimateSamples.push(d);
		}
		for(local i=0; i<maxDistance/10; i++) {
			HogeAI.distanceSampleIndex.push(HogeAI.GetEstimateDistanceIndex( i*10+5 ));
		}


		/*if(numCompany > AIIndustryList().Count()) {
			WaitDays(365); // 新しいindustryが建設されるのを待ってみる
		}*/
		

		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());
		
		DoLoad();

		local currentLoanAmount = AICompany.GetLoanAmount();
		indexPointer = 3; // ++
		while (true) {
			CalculateProfitModel();
			HgLog.Info("######## turn:"+turn+ " "+ GetProfitModelName() + " ######## { ");
			prevLoadAmount = currentLoanAmount;
			currentLoanAmount = AICompany.GetLoanAmount();
			ResetEstimateTable();
			while(indexPointer < 4) {
				UpdateSettings();
				limitDate = AIDate.GetCurrentDate() + 600;
				Place.canBuildAirportCache.clear();
				
				DoInterval();
				DoStep();
				indexPointer ++;
			}
			indexPointer = 0;
			turn ++;
			WaitDays(1);
			HgLog.Info("}");
		}
	}
	
	function GetProfitModelName() {
		if(roiBase) {
			return "roiBase";
		}
		if(buildingTimeBase) {
			return "buildingTimeBase";
		}
		if(vehicleProfibitBase) {
			return "vehicleProfitBase";
		}
		return "illegal";
	}
	
	function CalculateProfitModel() {
		if(!IsRich() || IsInflation()/* || (maxRoi < 1000 && !HasIncome(250000))*/) {
			roiBase = true;
			buildingTimeBase = false;
			vehicleProfibitBase = false;
			return;
		}
		roiBase = false;
		// 以下廃止。vehicleProfitBaseだと収益がマイナスの時にヘリばかりつくる羽目になる => 収益がマイナスの時はRouteを廃止すべき
		
		foreach(vehicleType in Route.allVehicleTypes) {
			local routeClass = Route.Class(vehicleType);
			local max =  routeClass.GetMaxTotalVehicles();
			local current = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType);
			local room = max - current;
			if(room >= 100 && current < max * 7 / 10) {
				roiBase = false;
				buildingTimeBase = true;
				vehicleProfibitBase = false;
				return;
			}
		}
		roiBase = false;
		buildingTimeBase = false;
		vehicleProfibitBase = true;
		
		return;
		/*
		local landVts = [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_AIR];
		local landVehicles = 0;
		local landMax = 0;
		foreach(vt in landVts) {
			local routeClass = Route.Class(vt);
			landVehicles += routeClass.GetVehicleCount(routeClass);
			landMax += routeClass.GetMaxTotalVehicles();
		}
		if(landMax !=0 && landVehicles < landMax / 2) { // TODO: 船オンリーマップ
			roiBase = false;
			buildingTimeBase = true;
			HgLog.Info("### buildingTimeBase");
		} else {
			roiBase = false;
			buildingTimeBase = false;
			HgLog.Info("### vehicleProfitBase");
		}*/
	}
	
	function GetValue(roi,incomePerBuildingTime,incomePerVehicle) {
		if(roiBase) {
			return roi;
		}
		if(buildingTimeBase) {
			return incomePerBuildingTime;
		}
		return incomePerVehicle;
	}
	
	function DoStep() {
		switch(indexPointer) {
			case 0:
				//CheckBuildedPaths();
				break;
			case 1:
				SearchAndBuildToMeetSrcDemand();
				break;
			case 2:
				ScanRoutes();
				break;
			case 3:
				ScanPlaces();
				break;
		}
	}

	function ResetEstimateTable() {
		estimateTable.clear();
	}
	
	function ScanPlaces() {
		_ScanPlaces();
		routeCandidates.Clear();
	}

	function _ScanPlaces() {
		HgLog.Info("###### Scan places");
		
		if(/*IsForceToHandleFright() &&*/ isTimeoutToMeetSrcDemand) { // Airやるだけなら良いが、余計なルートを作ってsupply chainを混乱させる事があったのでコメントアウト
			return;
		}
		local aiTestMode = AITestMode();
		
		local startDate = AIDate.GetCurrentDate();
		
		if(routeCandidates.Count() == 0) {
			HgLog.Info("GetRouteCandidates {");
			local candidate;
			local maxCargoPlaces = GetMaxCargoPlaces();
			local startDateRouteGen = AIDate.GetCurrentDate(); // GetMaxCargoPlacesに時間がかかると、1placeしか調べなくなるため
			local routeCandidatesGen = GetRouteCandidatesGen(maxCargoPlaces);
			local candidateNum = 1000; // 400 / (16*8) = cargo 4種類
			for(local i=0; (candidate=resume routeCandidatesGen) != null && i<candidateNum; i++) {
				routeCandidates.Push(candidate);
	/*			candidate.score += AIBase.RandRange(10); // ほかのHogexとの競合を防ぐ
				bests.push(candidate);*/
				if(startDateRouteGen + 365 < AIDate.GetCurrentDate() && GetUsableMoney() > GetInflatedMoney(100000)) {
					HgLog.Warning("routeCandidatesGen reached 365 days");
					break;
				}
			}
			HgLog.Info("} GetRouteCandidates");
			if(routeCandidates.Count()==0) {
				routeCandidates.Extend( GetAirportExchangeCandidates() );
			}
			routeCandidates.CalculateMinValue();
			routeCandidates.Extend( GetTransferCandidates() );
			routeCandidates.Extend( GetMeetPlaceCandidates() );
		}
		local minValue = routeCandidates.minValue;
		
		HgLog.Info("routeCandidates.GetAll "+routeCandidates.Count()+" {");
		foreach(t in routeCandidates.GetAll()) {
			if(!("explain" in t)) {
				local routeClass = Route.Class(t.vehicleType);
				if(!("isBiDirectional" in t)) {
					t.isBiDirectional <- (t.dest instanceof Place) ? t.dest.IsAcceptingAndProducing(t.cargo) && t.src.IsAcceptingAndProducing(t.cargo) : false;
				}
				t.explain <- t.estimate.value+" "+routeClass.GetLabel()+" "+t.dest+"<="+(t.isBiDirectional?">":"")+t.src+"["+t.cargo+"] dist:"+AIMap.DistanceManhattan(t.src.GetLocation(),t.dest.GetLocation());
				if(t.vehicleType == AIVehicle.VT_AIR) {
					t.explain += " infraType:"+t.estimate.infrastractureType;
				}
			}
			local s = "ScanPlace "+t.explain;
			HgLog.Info(s);
		}
		HgLog.Info("} routeCandidates.GetAll "+routeCandidates.Count());
		noRouteCnadidates = routeCandidates.Count() == 0;
		local searchDays = AIDate.GetCurrentDate() - startDate;
		HgLog.Info("searchDays:"+searchDays+" minValue:"+minValue);
		limitDate = AIDate.GetCurrentDate() + max((roiBase ? 356*2 : 365*2) / GetDayLengthFactor(), searchDays * (roiBase ? 2 : 2));
		startDate = AIDate.GetCurrentDate();
		local dirtyPlaces = {};
		local pendingPlans = [];
		local totalNeeds = 0;
		local endDate = AIDate.GetCurrentDate();
		local buildingStartDate = AIDate.GetCurrentDate();
		local builtAirOfInfrastructureMaintenance = false;
		while(routeCandidates.Count() >= 1){
			local t = routeCandidates.Pop();
			if(builtAirOfInfrastructureMaintenance && t.vehicleType == AIVehicle.VT_AIR) {
				HgLog.Warning("Need to estimate again for bulding two airports with InfrastructureMaintenance");
				return;
			}
			if(IsInfrastructureMaintenance()) {
				// AirportExchangeCandidatesにbuildingCostやpriceは無い
				local nextFlag = false;
				while("buildingCost" in t.estimate && t.estimate.buildingCost + t.estimate.price > GetUsableMoney()) {
					HgLog.Warning("Not enough money to build route(InfrastructureMaintenance) building:"+t.estimate.buildingCost+" price:"+t.estimate.price+" "+t.estimate);
					if(HogeAI.Get().GetQuarterlyIncome() <= 0) {
						nextFlag = true;
						break;
					}
					if(limitDate < AIDate.GetCurrentDate()) {
						HgLog.Warning("ScanPlaces reached limitDate");
						return;
					}				
					WaitDays(10);
				}
				if(nextFlag) continue;
			}
			if(t.vehicleType != AIVehicle.VT_AIR || IsInfrastructureMaintenance()) { //airの場合迅速にやらないといけないので
				DoInterval(); 
			}
			local builder = CreateBuilder(t,pendingPlans,dirtyPlaces,limitDate);
			if(builder == null) {
				continue;
			}
			HgLog.Info("#### TryBuild "+t.explain+" {");
			local newRoutes = builder.Build();
			if(newRoutes == null) {
				newRoutes = [];
			} else if(typeof newRoutes != "array") {
				newRoutes = [newRoutes];
			}
			HgLog.Info("} TryBuild");
			routeCandidates.Extend(pendingPlans);
			pendingPlans.clear();
			if(newRoutes.len() >= 1) {
				if("srcPlace" in t) {
					dirtyPlaces.rawset(t.srcPlace.GetFacilityId()+":"+t.cargo, true);
				}
				if(t.vehicleType == AIVehicle.VT_AIR) {
					if(IsInfrastructureMaintenance()) builtAirOfInfrastructureMaintenance = true;
				}
				foreach(newRoute in newRoutes) {
					if(newRoute.srcHgStation.place != null) {
						newRoute.srcHgStation.place.SetDirtyArround();
					}
					if(t.rawin("route") && t.route != null) {
						if(t.route.IsBiDirectional() && t.route.destHgStation.stationGroup == t.dest) {
						} else {
							t.route.NotifyAddTransfer(t.cargo);
						}
					}
					if(t.rawin("sourceRoute") && t.sourceRoute != null) {
						t.sourceRoute.NotifyChangeDestRoute();
					}
					local destPlace = newRoute.GetFinalDestPlace(); // TODO 複数placeには未対応
					if(destPlace != null) {
						local producingPlace = destPlace.GetProducing();
						producingPlace.GetPlaceCache().expectedProduction.clear();
						producingPlace.GetPlaceCache().currentExpectedProduction.clear();
						foreach(route in producingPlace.GetRoutesUsingSource()) {
							route.needsAdditionalCache.clear();
						}
					}
					if(firs && newRoute.destHgStation.place != null && newRoute.destHgStation.place.IsRaw()) {
						// supply cargoはdirtyにしない
					} else {
						local src = newRoute.srcHgStation.place != null ? newRoute.srcHgStation.place : newRoute.srcHgStation.stationGroup;
						foreach(cargo,_ in newRoute.GetEngineCargos()) {
							dirtyPlaces.rawset(src.GetFacilityId()+":"+cargo, true);
							HgLog.Warning("dirtyPlaces.rawset:"+(src.GetFacilityId()+":"+cargo)+" "+newRoute);
						}
						if(newRoute.IsBiDirectional() || ecs) {
							local dest = newRoute.destHgStation.place != null ? newRoute.destHgStation.place : newRoute.destHgStation.stationGroup;
							//dirtyPlaces.rawset(dest.GetGId()+":"+t.cargo, true);
							foreach(cargo,_ in newRoute.GetEngineCargos()) {
								dirtyPlaces.rawset(dest.GetFacilityId()+":"+cargo, true);
								HgLog.Warning("dirtyPlaces.rawset:"+(dest.GetFacilityId()+":"+cargo)+" "+newRoute);
							}
						}
					}
				}
				if(roiBase && routeCandidates.Count() >= 1) {
					if(IsRich() && AIDate.GetCurrentDate() - buildingStartDate > searchDays) { // roiBaseから変わったので再検索
						HgLog.Warning("IsRich == true");
						return;
					}
					local next = routeCandidates.Peek();
					if(!("typeName" in t) && t.vehicleType != AIVehicle.VT_AIR) {
						local usable = GetUsableMoney() + GetQuarterlyIncome() * t.estimate.days / 90;
						totalNeeds += t.estimate.price * (t.estimate.vehiclesPerRoute - newRoutes[0].GetNumVehicles()); // TODO: これまでの建築にかかった時間分減らす
						local nextNeeds = next.estimate.buildingCost + next.estimate.price;
						local needs = totalNeeds + nextNeeds - HogeAI.Get().GetQuarterlyIncome() / (3 * 30) * (AIDate.GetCurrentDate() - startDate);
						HgLog.Info("price:"+t.estimate.price+" vehiclesPerRoute:"+t.estimate.vehiclesPerRoute+" totalNeeds:"+totalNeeds+" nextNeeds:"+nextNeeds+" usable:"+usable);
						endDate = max( endDate, AIDate.GetCurrentDate() + t.estimate.days );
						if(usable < needs) { // 次の建築をしながら、前のルートの乗り物を作れない
							HgLog.Info("usable:"+usable+" needs:"+needs);
							//WaitDays(30);
							local waitDays = min(min(180,limitDate - AIDate.GetCurrentDate()),max(0,endDate - AIDate.GetCurrentDate()));
							if(waitDays >= 180) {
								HgLog.Warning("waitDays >= 180 "+waitDays);
								return;
							}
							WaitDays(waitDays);
							for(local i=0; (usable=GetUsableMoney()) < nextNeeds; i++) { // 次の建築ができない(最大6か月待つ)
								HgLog.Info("usable:"+usable+" nextNeeds:"+nextNeeds);
								WaitDays(10);
								if(i>=17 || limitDate < AIDate.GetCurrentDate()) {
									HgLog.Warning("ScanPlaces reached limitDate");
									return;
								}
							}
						}
						if(next.estimate.value < 100 && IsInfrastructureMaintenance() && next.vehicleType == AIVehicle.VT_ROAD) { 
							HgLog.Warning("next.estimate.value < 100");
							WaitDays(365); // 収益性が悪すぎるのでしばらく様子を見て再検索
							return;
						}
					}
					if(roiBase && next.estimate.value < 200) {
						HgLog.Warning("ScanPlaces next.estimate.value < 200");
						return;
					}
				}
			}
			if(limitDate < AIDate.GetCurrentDate()) {
				HgLog.Warning("ScanPlaces reached limitDate");
				return;
			}
		}
	}
	
	function CreateBuilder(plan,pendingPlans,dirtyPlaces,limitDate) {
		local typeName = ("typeName" in plan) ? plan.typeName : "route";
		if(typeName == "route") {
			return CreateRouteBuilder(plan,pendingPlans,dirtyPlaces,limitDate);
			
		} else if(typeName == "exchangeAirs") {
			return CreateExchangeAirsBuilder(plan,dirtyPlaces);
		}
	}
	
	function CreateRouteBuilder(t,pendingPlans,dirtyPlaces,limitDate) {
		local routeClass = Route.Class(t.vehicleType);
		local explain = t.explain;
		/*if(roiBase && t.estimate.value < 150) { 何もしなくなってしまうマップがある
			if(index==0) {
				WaitDays(365); // 最初から収益性が悪すぎるのでしばらく様子をて再検索
			}
			DoPostBuildRoute(rootBuilders);
			return;
		}*/
		if((t.isBiDirectional || ecs) && dirtyPlaces.rawin(t.dest.GetFacilityId()+":"+t.cargo)) { // 同じplaceで競合するのを防ぐ(特にAIRとRAIL)
			HgLog.Info("dirtyPlaces dest "+explain);
			return null;
		}
		if(dirtyPlaces.rawin(t.src.GetFacilityId()+":"+t.cargo)) {
			HgLog.Info("dirtyPlaces src "+explain);
			return null;
		}
		if("srcPlace" in t && dirtyPlaces.rawin(t.srcPlace.GetFacilityId()+":"+t.cargo)) {
			HgLog.Info("dirtyPlaces srcPlace "+t.srcPlace+" "+explain);
			return null;
		}
		if(!t.src.CanUseNewRoute(t.cargo, t.vehicleType)) {
			HgLog.Info("Not CanUseNewRoute src "+explain);
			return null;
		}
		if(t.isBiDirectional && !t.dest.CanUseNewRoute(t.cargo, t.vehicleType)) {
			HgLog.Info("Not CanUseNewRoute dest:"+t.dest+" "+explain);
			return null;
		}
		if(Place.IsNgPlace(t.dest, t.cargo, t.vehicleType) || Place.IsNgPlace(t.src, t.cargo, t.vehicleType)) {
			HgLog.Info("NgPlace "+explain);
			return null;
		}
		if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
			HgLog.Info("TooManyVehicles "+explain);
			return null;
		}
		if(t.src instanceof Place && t.src.IsProcessing() && t.src.IsDirtyArround()) {
			HgLog.Info("DirtyArround "+explain);
			return null;
		}
		local destRoute = ("route" in t) ? t.route : null;
		if(destRoute != null) {
			if(!destRoute.NeedsAdditionalProducingCargo( t.cargo, null, destRoute.destHgStation.stationGroup==t.dest )) {
				HgLog.Info("skip transfer build !destRoute.NeedsAdditionalProducing "+explain+" destRoute:"+destRoute);
				return null;
			}
			if(t.estimate.destRouteCargoIncome > 0) {
				local finalDestStation = destRoute.GetFinalDestStation( null, t.dest );
				if(finalDestStation.place != null && finalDestStation.place.GetDestRouteCargoIncome(t.cargo) == 0) {
					HgLog.Warning("DRCI == 0 place:" + finalDestStation.place + "[" + AICargo.GetName(t.cargo)+"] "+ explain + " destRoute:"+destRoute);
					return null;
				}
			}
			//HgLog.Info("NeedsAdditionalProducing true "+explain+" "+t.route);
		} else {
			if(t.estimate.destRouteCargoIncome > 0 && t.dest.GetDestRouteCargoIncome(t.cargo) == 0) {
				HgLog.Warning("DRCI == 0 "+explain);
				return null;
			}
		}
		local sourceRoute = ("sourceRoute" in t) ? t.sourceRoute : null;
		
		if(t.estimate.additionalRouteIncome > 0) {
			local place = destRoute != null ? destRoute.GetAcceptingPlace(t.cargo) : t.dest;
			local ari = place == null ? 0 : place.GetAdditionalRouteIncome(t.cargo);
			HgLog.Info("additionalRouteIncome="+ari+" place:"+place+" "+explain);
			if(ari == 0) {
				HgLog.Warning("additionalRouteIncome == 0 place:"+place+" "+explain);
				return null;
			}
		}
		
		local routeBuilder = routeClass.GetBuilderClass()(t.dest, t.src, t.cargo, { 
			pendingToDoPostBuild = false //roiBase ? true : false
			destRoute = destRoute!=null ? destRoute.id : null
			sourceRoute = sourceRoute!=null ? sourceRoute.id : null
			setRouteCandidates = true
			canChangeDest = t.rawin("canChangeDest") ? t.canChangeDest : 
				destRoute==null && t.estimate.destRouteCargoIncome == 0 && t.estimate.additionalRouteIncome == 0
			estimate = t.estimate
			limitDate = limitDate
		});
		if(t.estimate.value < 0) {
			HgLog.Info("t.estimate.value < 0 ("+t.estimate.value+") "+explain);
			return null;
		}
		return routeBuilder;
	}
	
	function CreateExchangeAirsBuilder(t, dirtyPlaces) {
		local routeClass = Route.Class(t.vehicleType);
		local stations = [];
		foreach(stationId in t.stations) {
			local station = HgStation.worldInstances[stationId];
			stations.push(station);
			if(dirtyPlaces.rawin(station.place.GetGId()+":"+t.cargo)) {
				HgLog.Info("dirtyPlaces "+t.explain);
				return null;
			}
		}
		return ExchangeAirsBuilder(t.cargo, stations, Route.allRoutes[t.route1],Route.allRoutes[t.route2]);
	}
	
	function DoPostBuildRoute(rootBuilders) {
		if(!roiBase) {
			return;
		}
		foreach(builder in rootBuilders) {
			builder.DoPostBuild();
		}
	}
	
	function ScanRoutes() {
		HgLog.Info("###### Scan routes");
		
		if(HogeAI.Get().IsInfrastructureMaintenance()) {
			foreach(route in TrainRoute.removed) { // TODO: Save/Loadに対応していない
				route.Demolish();
			}
			TrainRoute.removed.clear();
		}
		if(limitDate < AIDate.GetCurrentDate()) {
			return;
		}

		local aiTestMode = AITestMode();
		local list = AIList();
		list.Sort(AIList.SORT_BY_VALUE, false);
		foreach(index, route in TrainRoute.instances) {
			if(route.IsRemoved() || route.IsTransfer() || route.IsUpdatingRail()) {
				continue;
			}
			local lastScanDate = lastScanRouteDates.rawin(route.id) ? lastScanRouteDates.rawget(route.id) : null;
			if(lastScanDate!=null && lastScanDate + 10 * 365 < AIDate.GetCurrentDate()) {
				 // やたらとreturn route作成失敗を繰り返すので10年に1度
				continue;
			}
			local engineSet = route.GetLatestEngineSet();
			if( engineSet == null) {
				continue;
			}
			list.AddItem(route.id, engineSet.GetTotalProduction());
		}
		foreach(id,prod in list) {
			if(!Route.allRoutes.rawin(id)) continue;
			local route = Route.allRoutes[id];
			if(route.IsRemoved() || route.IsUpdatingRail()) {
				continue;
			}
			lastScanRouteDates.rawset(route.id,AIDate.GetCurrentDate());
			AIRail.SetCurrentRailType(route.GetRailType());
			/*TODO
			local destStation = route.destHgStation.GetAIStation();
			foreach(cargo in route.GetUsableCargos()) {
				local waiting = AIStation.GetCargoWaiting(destStation, cargo);
				if(waiting > 0) {
					CreateDeliverRoute(route, cargo, waiting);
				}
			}*/
			

			SearchAndBuildAdditionalDestAsFarAsPossible( route );
			CheckBuildReturnRoute(route);
			DoInterval();
			
			if(limitDate < AIDate.GetCurrentDate()) {
				break;
			}
		}
	}
	
	function GetRouteCandidatesGen(cargoPlaces) {
		local cargoPlaceInfo = {};
		local cargoUsed = {}
		local usedDistance = min(max(AIMap.GetMapSizeX(), AIMap.GetMapSizeY())/8, 200);
		foreach(i, srcInfo in cargoPlaces) {
			//src.production = Place.AdjustProduction(src.place, src.production);
			local count = 0;
			/*
			if(cargoUsed.rawin(srcInfo.cargo)) {
				local short = false;
				foreach(location in cargoUsed[srcInfo.cargo]) {
					if(AIMap.DistanceManhattan(location, srcInfo.place.GetLocation()) < usedDistance) {
						short = true;
						break;
					}
				}
				if(short) continue;
			} else {
				cargoUsed.rawset(srcInfo.cargo, []);
			}
			cargoUsed[srcInfo.cargo].push(srcInfo.place.GetLocation());*/

			if(!cargoPlaceInfo.rawin(srcInfo.cargo)) {
				local placeInfo = {
					searchProducing = false
				};
				cargoPlaceInfo.rawset(srcInfo.cargo, placeInfo);
			}
			local useLastMonths = [false];
			if(!roiBase && srcInfo.place.IsProcessing()) {
				useLastMonths.push(true);
			}
			foreach(useLastMonth in useLastMonths) {
				HgLog.Info("src.place:"+srcInfo.place.GetName()+" ["+AICargo.GetName(srcInfo.cargo)+"] "+(useLastMonth?"useLastMonth":"")+" {");
				foreach(dest in CreateRouteCandidates(srcInfo.cargo, srcInfo.place, cargoPlaceInfo[srcInfo.cargo], 0 , 4, {useLastMonthProduction=useLastMonth})) {
	//					Place.GetAcceptingPlaceDistance(src.cargo, src.place.GetLocation()))) {
					
					local routeClass = Route.Class(dest.vehicleType);
					if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
						continue;
					}
					
					local route = {};
					route.cargo <- srcInfo.cargo;
					route.dest <- dest.place;
					route.src <- srcInfo.place;
					route.production <- dest.production;
					route.maxValue <- srcInfo.maxValue;
					route.distance <- dest.distance;
					route.routeClass <- routeClass;
					route.vehicleType <- dest.vehicleType;
					route.estimate <- dest.estimate;
					route.score <- dest.score;
					
					local isDestBi = route.dest.IsAcceptingAndProducing(route.cargo);
					if(isDestBi && route.dest instanceof Place) {
						route.dest = route.dest.GetProducing();
					}
					
					if(route.vehicleType == AIVehicle.VT_RAIL) {
						if(!route.src.CanUseTrainSource()) {
							continue;
						}
						if(isDestBi && !route.dest.GetProducing().CanUseTrainSource()) {
							continue;
						}
					}
					if(isDestBi && !route.dest.GetProducing().CanUseNewRoute(route.cargo, route.vehicleType)) {
						continue;
					}
					yield route;
					count ++;
					if(count >= 25) { // 一か所のソースにつき最大
						break;z
					}
				}
				HgLog.Info("}");
				DoInterval();
			}
		}
		return null;
	}

	function GetMaxCargoPlaces() {
	
		local result = []
		
		local quarterlyIncome = AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		local quarterlyExpnse = AICompany.GetQuarterlyExpenses (AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		HgLog.Info("GetMaxCargoPlaces QuarterlyIncome:" + quarterlyIncome + " Expnse:" + quarterlyExpnse + " {");
		
		PlaceProduction.Get().ClearCargoInfos();
			
		local ignoreCargos = {};
		
		HgLog.Info("IsForceToHandleFright: "+IsForceToHandleFright());
		if(IsForceToHandleFright()  && !roiBase) {
			local paxMailOnly = true;
			foreach(route in Route.GetAllRoutes()) {
				if(!CargoUtils.IsPaxOrMail(route.cargo)) {
					paxMailOnly = false;
					break;
				}
			}
			if(paxMailOnly) {
				foreach(cargo in GetPaxMailCargos()) {
					ignoreCargos.rawset( cargo, true );
				}
			}
		}
		
		local cargoList = AIList();
		foreach(cargo ,_ in AICargoList()) {
			if(ignoreCargos.rawin(cargo)) {
				continue;
			}
			if(IsPaxMailOnly() && !CargoUtils.IsPaxOrMail(cargo)) {
				continue;
			}
			if(IsFreightOnly() && CargoUtils.IsPaxOrMail(cargo)) {
				continue;
			}
			if(!CargoUtils.IsDelivable(cargo)) {
				continue;
			}
			cargoList.AddItem(cargo,0);
		}
		local indexes;
		local mapSize = AIMap.GetMapSizeX() * AIMap.GetMapSizeY();
		if(mapSize > 2048*2048 && hogeNum==1) {
			local segment = mapSize/(2048*2048);
			indexes = PlaceProduction.Get().GetIndexesInSegment(AIBase.RandRange(segment),segment);
		} else {
			indexes = PlaceProduction.Get().GetIndexesInSegment(hogeIndex,hogeNum);
		}
		if(indexes != null) {
			HgLog.Info("indexes:"+HgArray(indexes));
		}
		
		local resultMax = max(16,128 / max(cargoList.Count(),1));
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		local cargosPlaces = {};
		foreach(route in Route.GetAllRoutes()) {
			if(route.IsClosed() || route.IsTransfer() || route.destHgStation.place == null) continue;
			local place = route.destHgStation.place.GetProducing();
			if(place.IsClosed()) continue;
			if(place instanceof HgIndustry) {
				foreach(cargo in place.GetCargos()) {
					if(place.GetLastMonthTransportedPercentage(cargo)>0) continue;
					if(!cargosPlaces.rawin(cargo)) {
						cargosPlaces.rawset(cargo,[place]);
					} else {
						cargosPlaces.rawget(cargo).push(place);
					}
				}
			}
		}
		foreach(cargo ,_ in cargoList) {
			local vtDistanceValues = [];
			//HgLog.Info("step0 "+AICargo.GetName(cargo));
			DoInterval();
			local places = [];
			if(cargosPlaces.rawin(cargo)) {
				places.extend(cargosPlaces.rawget(cargo));
			}
			places.extend(Place.GetNotUsedProducingPlaces( cargo, 300, indexes ));
			if(places.len() == 0) {
				//HgLog.Warning("step0 places.len() == 0 "+AICargo.GetName(cargo));
				continue;
			}
			local placeList = AIList();
			for(local i=0; i<places.len(); i++) {
				placeList.AddItem(i,0);
			}

			local stdProduction = roiBase ? 210 : 890;
			foreach(routeClass in [TrainRoute, RoadRoute, WaterRoute, AirRoute]) {
				//HgLog.Info("step1 "+routeClass.GetLabel());
				if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
					//HgLog.Info("Too many vehicles."+routeClass.GetLabel());
					continue;
				}
				if(!routeClass.CanCreateNewRoute()) {
					HgLog.Warning("CanCreateNewRoute == false."+routeClass.GetLabel());
					continue;
				}
				local cargoResult = [];
				local maxValue = 0;
				local vehicleType = routeClass.GetVehicleType();
				if(roiBase) stdProduction = 0;
				local endDate = AIDate.GetCurrentDate() + 2;
				foreach(place in places) {
					if(endDate < AIDate.GetCurrentDate()) {
						HgLog.Warning("estimate too slow");
						break;
					}
					if(!place.CanUseNewRoute(cargo, vehicleType) || Place.IsNgPlace(place, cargo, vehicleType)) {
						//HgLog.Warning("step1 "+place+" "+place.CanUseNewRoute(cargo, vehicleType)+" "+Place.IsNgPlace(place, cargo, vehicleType));
						continue;
					}
					if(vehicleType == AIVehicle.VT_AIR) {
						if(!place.CanBuildAirport(minimumAiportType, cargo)) continue;
					}
					if(place.IsClosed()) continue;
					
					local production = place.GetExpectedProduction( cargo, vehicleType, false );
					if(production == 0) {
						//HgLog.Warning("step2 "+place+" "+production);
						continue;
					}
					production = min(production,1000);
					if(place.IsProcessing()) {
						production += place.GetLastMonthProduction(cargo); //既に生産している工場は検索対象になりやすくする
					}
					cargoResult.push({
						cargo = cargo
						place = place
						production = production
					});
					if(roiBase) stdProduction = max(stdProduction,production);
				}
				if(cargoResult.len() == 0) {
					//HgLog.Warning("step3 cargoResult.len()=0 "+AICargo.GetName(cargo));
					continue;
				}
				
				local infrastractureTypes = routeClass.GetDefaultInfrastractureTypes();
				
				HgLog.Info("Estimate:" + routeClass.GetLabel()+"["+AICargo.GetName(cargo)+"] prod:"+stdProduction);
				foreach(distanceIndex, distance in distanceEstimateSamples) {
					if(vehicleType != AIVehicle.VT_AIR && distance > 550) {
						continue;
					}
					local estimate = Route.Estimate(routeClass.GetVehicleType(), cargo, distance, stdProduction, CargoUtils.IsPaxOrMail(cargo) ? true: false, infrastractureTypes);
					if(estimate == null || estimate.value <= 0) {
						continue;
					}
					vtDistanceValues.push([routeClass.GetVehicleType(), distanceIndex, estimate.value, estimate]);
					
					maxRoi = max(estimate.roi,maxRoi);
					HgLog.Info("Estimate d:"+distance+" "+estimate);
					/*
					HgLog.Info("Estimate d:"+distance+" roi:"+estimate.roi+" income:"+estimate.routeIncome+" ("+estimate.incomePerOneTime+") "
						+ AIEngine.GetName(estimate.engine)+(estimate.rawin("numLoco")?"x"+estimate.numLoco:"") +"("+estimate.vehiclesPerRoute+") "
						+ "runningCost:"+AIEngine.GetRunningCost(estimate.engine)+" capacity:"+estimate.capacity);*/
					maxValue = max(maxValue, estimate.value);
				}
				
				foreach(r in cargoResult ) {
					r.maxValue <- maxValue;
					if(roiBase) {
						r.score <- maxValue * 1000 + r.production;
					} else if(buildingTimeBase) {
						r.score <- maxValue / 100 * r.production;
					} else {
						r.score <- maxValue * 1000 + r.production;
					}
				}
				if(cargoResult.len() >= 1) {
					HgLog.Info("cargoResult:"+cargoResult.len());
					if(cargoResult.len() > resultMax) {
						if(vehicleType == AIVehicle.VT_AIR && CargoUtils.IsPaxOrMail(cargo)) {
							foreach(r in cargoResult) {
								r.scoreAirport <- r.place.GetAllowedAirportLevel(minimumAiportType, cargo) * 10000 + min(9999,r.production);				
							}
							cargoResult.sort(function(a,b){
								return -(a.scoreAirport - b.scoreAirport);
							});
						} else if(vehicleType == AIVehicle.VT_WATER) {
							foreach(r in cargoResult) {
//								r.scoreWater <- (r.place.GetCoasts(cargo) != null ? 1 : 0) * 10000 + min(9999,r.production);	
								r.scoreWater <- (r.place.IsNearWater(cargo) ? 1 : 0) * 10000 +  min(9999,r.production);				
							}
							cargoResult.sort(function(a,b){
								return -(a.scoreWater - b.scoreWater);
							});
							/*
							foreach(r in cargoResult) {
								HgLog.Info(r.place+" scoreWater:"+r.scoreWater+" prod:"+r.production);
							}*/
						} else {
							cargoResult.sort(function(a,b){
								return -(a.score - b.score);
							});
						}
						
						result.extend(cargoResult.slice(0,min(cargoResult.len(),resultMax)));
					} else {
						result.extend(cargoResult);
					}
					//break;
				}
			}
			//HgLog.Info("vtDistanceValues:"+vtDistanceValues.len());
			vtDistanceValues.sort(function(v1,v2) {
				return v2[2] - v1[2];
			});
			cargoVtDistanceValues.rawset(cargo,vtDistanceValues);
			
		}
		DoInterval();
		result.sort(function(a,b){
			return -(a.score - b.score);
		});
		/*
		if(turn == 1 && hogeNum >= 2 && hogeIndex % 2==1 && result.len() >= 1) {
			local topCargo = result[0].cargo;
			local newResult = [];
			foreach(r in result) {
				if(r.cargo == topCargo) continue;
				newResult.push(r);
			}
			if(newResult.len() >= 1) result = newResult;
		}*/
		
		local r2 = [];
		local exists = {};
		foreach(r in result) {
			local key = r.cargo + "-"+r.place.Id();
			if(exists.rawin(key)) continue;
			exists.rawset(key,key);
			HgLog.Info("cargo:"+AICargo.GetName(r.cargo) +" place:"+r.place.GetName()+" production:"+r.production+" score:"+r.score);
			r2.push(r);
		}
		HgLog.Info("}");
		return r2;
	}
	
	function CreateRouteCandidates(cargo, orgPlace, placeInfo, additionalProduction=0, maxResult=8, options={}) {
		if(Place.IsNgCandidatePlace(orgPlace,cargo)) {
			HgLog.Info("IsNgCandidatePlace:" + orgPlace + "["+AICargo.GetName(cargo)+ "] (CreateRouteCandidates)");
			return [];
		}
		if(orgPlace.IsClosed()) {
			HgLog.Info("IsClosed:" + orgPlace + "["+AICargo.GetName(cargo)+ "] (CreateRouteCandidates)");
			return [];
		}
		if(!(cargo in cargoVtDistanceValues)) {
			HgLog.Info("!(cargo in cargoVtDistanceValues):" + orgPlace + "["+AICargo.GetName(cargo)+ "] (CreateRouteCandidates)");
			return [];
		}
		local useLastMonthProduction = options.rawin("useLastMonthProduction") && options.useLastMonthProduction;
		local placeDictionary = PlaceDictionary.Get();
		local vtSamplesValues = cargoVtDistanceValues[cargo];
		local orgTile = orgPlace.GetLocation();
		local orgPlaceAcceptingRaw = orgPlace.IsAccepting() && orgPlace.IsRaw();
		local orgPlaceTraits = orgPlace.GetIndustryTraits();
		local orgPlaceProductionTable = {};
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		local isNgAir = !orgPlace.CanBuildAirport(minimumAiportType, cargo);
		//local maxBuildingCost = HogeAI.Get().GetUsableMoney() / 2/*最初期の安全バッファ*/ + HogeAI.Get().GetQuarterlyIncome();
		
		local maxCandidates = maxResult == null ? 0 : maxResult * 2;
		if(CargoUtils.IsPaxOrMail(cargo)) { // valueが対向サイズに影響するので多めに見る
			if(!TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute)) {
				maxCandidates *= 2; //roiBase ? 2 : 2;
			} else {
				maxResult *= 2;
				maxCandidates *= roiBase ? 2 : 1;
			}
		}

		local candidates = [];
		local checkCount = 0;
		
		HgLog.Info("Start CreateRouteCandidates:" + orgPlace + "["+AICargo.GetName(cargo)+ "]"+ (useLastMonthProduction?"useLastMonth":"")+"{");
		
		local distancePlaces = null;
		local mapSizeBig = AIMap.GetMapSizeX() * AIMap.GetMapSizeY() > 2048 * 2048;
		if(placeInfo.rawin("searchProducing")) {
			local places = Place.GetCargoPlaces(cargo,placeInfo.searchProducing);
			if(mapSizeBig && places.len() > 300) {
				local maxDistanceIndex = 0;
				foreach( vtDistanceValue in vtSamplesValues ) {
					maxDistanceIndex = max(maxDistanceIndex, vtDistanceValue[1]);
				}
				local maxDistance = distanceEstimateSamples[maxDistanceIndex];
				if(maxDistance > 1000) {
					distancePlaces = CargoDistancePlaces(cargo, placeInfo.searchProducing, orgTile);
				} else {
					distancePlaces = DistancePlaces(
						PlaceProduction.Get().GetArroundPlaces( cargo, placeInfo.searchProducing, orgTile, 0, maxDistance), orgTile);
				}
			} else {
				distancePlaces = DistancePlaces(places, orgTile);
			}
		} else {
			distancePlaces = DistancePlaces(placeInfo.places, orgTile);
		}
		foreach( vtDistanceValue in vtSamplesValues ) {
			local vt = vtDistanceValue[0];
			local routeClass = Route.Class(vt);
			local distanceIndex = vtDistanceValue[1];
			local sampleEstimate = vtDistanceValue[3];
			local routeClass = Route.Class(vt);
			if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, routeClass.GetVehicleType()) >= routeClass.GetMaxTotalVehicles()) {
				continue;
			}
			local places = distancePlaces.GetPlaces(distanceIndex);
			// HgLog.Info(routeClass.GetLabel()+" distance:"+distanceEstimateSamples[distanceIndex]+" places:"+places.len() + " cur_candidates:"+candidates.len());
			foreach(place in places) {
				if(maxCandidates != 0 && candidates.len() >= maxCandidates) {
					break;
				}
				local distance = AIMap.DistanceManhattan(place.GetLocation(),orgTile);
				if(distance == 0) { // はじかないとSearchAndBuildToMeetSrcDemandMin経由で無限ループする事がある
					continue;
				}
				/*if(vt != AIVehicle.VT_AIR && distance > 800) {
					continue;
				}*/
				if(place.IsProducing() && !place.CanUseNewRoute(cargo, vt)) {
					continue;
				}
				local t = {};
				t.distance <- distance;
				local isBidirectional = orgPlace.IsAcceptingAndProducing(cargo) && place.IsAcceptingAndProducing(cargo);
				if(isBidirectional) {
					place = place.GetProducing();
				}
				t.place <- place;
				if(vt == AIVehicle.VT_RAIL) {
					if(HogeAI.Get().ecs) {
						local cargoLabel = AICargo.GetCargoLabel(cargo);
						if(cargoLabel == "DYES") {
							continue;
						} else if(cargoLabel == "STEL") {
							local acceptingTraits = orgPlace.IsAccepting() ? orgPlaceTraits : t.place.GetIndustryTraits();
							if(acceptingTraits == "FERT,FOOD,/FISH,STEL,LVST,") { // Tinning factory
								continue;
							}
						}
					}
				} else if(vt == AIVehicle.VT_WATER) {
					if(!WaterRoute.CanBuild(orgPlace,  t.place, cargo, isBidirectional)) { 
						// 距離と収益性だけで候補を選ぶと、どことも接続できない事がある。
						//HgLog.Info("!WaterRoute.CanBuild "+orgPlace+" "+t.place);
						continue;
					}
				} else if(vt == AIVehicle.VT_AIR) {
					if(!t.place.CanBuildAirport(minimumAiportType, cargo)) {
						continue;
					}
				}
				if(Place.IsNgPlace(orgPlace, cargo, vt) || Place.IsNgPlace(t.place, cargo, vt)) {
					continue;
				}
				
				checkCount ++;
				local srcPlace = orgPlace.IsProducing() ? orgPlace : t.place;
				local destPlace = orgPlace.IsProducing() ? t.place : orgPlace;
				local placeProduction = 0;
				if(Place.IsNgPathFindPair(srcPlace, destPlace, vt)) {
					continue;
				}
				if(place.IsProducing()) {
					if(useLastMonthProduction) {
						placeProduction = place.GetCurrentExpectedProduction(cargo, vt);
						//HgLog.Info("GetCurrentExpectedProduction:"+placeProduction+"["+AICargo.GetName(cargo)+"] "+place+" vt:"+vt);
					} else {
						placeProduction = place.GetExpectedProduction(cargo, vt);
						//HgLog.Info("GetExpectedProduction:"+placeProduction+"["+AICargo.GetName(cargo)+"] "+place+" vt:"+vt);
					}
				}
				local orgPlaceProduction;
				local orgPlaceCount;
				local minProduction = false;
				if(orgPlace.IsAccepting()) {
					orgPlaceProduction = 0;
				} else if(orgPlaceProductionTable.rawin(vt)) {	
					orgPlaceProduction = orgPlaceProductionTable[vt].production;
					minProduction = orgPlaceProductionTable[vt].minProduction;
				} else {
					if(useLastMonthProduction) {
						orgPlaceProduction = orgPlace.GetCurrentExpectedProduction(cargo, vt);
						//HgLog.Info("GetCurrentExpectedProduction:"+orgPlaceProduction+"["+AICargo.GetName(cargo)+"] "+orgPlace+" vt:"+vt);
						if(firs && orgPlaceProduction==0) {
							if(orgPlace.IsProcessing()) {
								minProduction = true;
								orgPlaceProduction = orgPlace.GetExpectedProduction(cargo, vt, false, true);
								//HgLog.Info("GetExpectedProduction:"+orgPlaceProduction+"["+AICargo.GetName(cargo)+"] "+orgPlace+" vt:"+vt);
							}
						}
					} else {
						orgPlaceProduction = orgPlace.GetExpectedProduction(cargo, vt);
						//HgLog.Info("GetExpectedProduction:"+orgPlaceProduction+"["+AICargo.GetName(cargo)+"] "+orgPlace+" vt:"+vt);
					}
					orgPlaceProductionTable[vt] <- {production = orgPlaceProduction, minProduction = minProduction};
					if(orgPlaceProduction < 27) {
						HgLog.Info("GetExpectedProduction:"+orgPlaceProduction+"<27 ["+AICargo.GetName(cargo)+"] "+orgPlace+" vt:"+vt);
						return []; // 抜けないとNG登録されて以後チェックされないくなる
					}
				}
				
				local production;
				if(isBidirectional) {
					if( vt == AIVehicle.VT_RAIL ) {
						if(sampleEstimate.isSingle) {
							//production = (orgPlaceProduction + min(orgPlaceProduction,placeProduction)) / 2;
							production = min(orgPlaceProduction,placeProduction);
						} else {
							// どうせ延ばすので対向のサイズはあまり関係ないが少しだけ加味
							production = (orgPlaceProduction * 2 + min(orgPlaceProduction,placeProduction)) / 3;
						}
					} else if( vt == AIVehicle.VT_WATER) {
						//production = (orgPlaceProduction + min(orgPlaceProduction,placeProduction)) / 2;
						production = min(orgPlaceProduction,placeProduction);
					}  else {
						production = min(orgPlaceProduction,placeProduction);
					}
				} else {
					production = orgPlace.IsProducing() ? orgPlaceProduction : placeProduction;
				}
				
				local infrastractureTypes = routeClass.GetSuitableInfrastractureTypes(orgPlace, t.place, cargo);
				local estimateProduction = production;
				
				if(estimateProduction < 27) {
					//HgLog.Info("estimateProduction < 27 "+vt+" "+AICargo.GetName(cargo)+" "+estimateProduction);
					continue; // firsのengineering supplies的にも最低これくらい無いと無意味
				}
				local estimate = Route.Estimate( vt, cargo, t.distance, estimateProduction, isBidirectional, infrastractureTypes );
				
				if(estimate != null) { 
					estimate = clone estimate;
					estimate.EstimateAdditional( destPlace, srcPlace, infrastractureTypes, null, null, false, useLastMonthProduction, minProduction);
					if(vt == AIVehicle.VT_WATER && isBidirectional && placeProduction < orgPlaceProduction) {
						local onewayEstimate = Route.Estimate( vt, cargo, t.distance, orgPlaceProduction - placeProduction, false, infrastractureTypes );
						if(onewayEstimate != null) {
							estimate.EstimateOneWay( onewayEstimate ); // bidirectional時にソース側の方が生産量が多い時の追加分
						}
					}
				} else {
					//HgLog.Info("estimate==null "+vt+" "+AICargo.GetName(cargo)+" "+t.distance+" "+estimateProduction);
				}
				
				if(estimate != null && estimate.value > 0 /*&& estimate.buildingCost <= maxBuildingCost Estimate内ではじいている*/) {

				
					t.vehicleType <- vt;
					t.score <- estimate.value;
					t.isBiDirectional <- isBidirectional;
					t.estimate <- estimate;
					/*if(vt == AIVehicle.VT_AIR && cargo == HogeAI.GetPassengerCargo() && orgPlace instanceof TownCargo && t.place instanceof TownCargo) {
						t.score = t.score * 13 / 10; // 郵便がひっついてくる分
					}*/
					t.production <- production;
					if(ecs && t.place.IsAccepting() && t.place.IsEcsHardNewRouteDest(cargo)) {
						t.score /= 2;
					}
				
					candidates.push(t);
				} else {
					//HgLog.Info("EstimateAdditional==null "+vt+" "+AICargo.GetName(cargo)+" "+t.distance+" "+estimateProduction+" "+destPlace+" "+srcPlace);
				}
			}
			if(maxCandidates != 0 && candidates.len() >= maxCandidates) {
				break;
			}
		}
		
		candidates.sort(function(a,b) {
			return b.score - a.score;
		});
		
		local result = [];
		foreach(candidate in candidates) {
			if(Place.IsNgPathFindPair(orgPlace, candidate.place, candidate.vehicleType)) {
				continue;
			}
			if(candidate.vehicleType == AIVehicle.VT_RAIL) {
				if(candidate.estimate.isSingle) {
					if(!HgTile.IsLandConnectedForRoad(orgTile, candidate.place.GetLocation())) {
						continue;
					}
				} else {
					if(!HgTile.IsLandConnectedForRail(orgTile, candidate.place.GetLocation())) {
						continue;
					}
				}
				local from, to;
				if(candidate.isBiDirectional || !candidate.place.IsProducing()) {
					from = orgTile;
					to = candidate.place.GetLocation();
				} else {
					from = candidate.place.GetLocation();
					to = orgTile;
				}
				local notExtend = candidate.estimate.destRouteCargoIncome > 0 || candidate.estimate.additionalRouteIncome > 0;
				candidate.estimate.value = VehicleUtils.AdjustTrainScoreBySlope(
						candidate.estimate.value, candidate.estimate.engine, from, to, !notExtend || candidate.isBiDirectional );
			} else if(candidate.vehicleType == AIVehicle.VT_ROAD) {
				if(!HgTile.IsLandConnectedForRoad(orgTile, candidate.place.GetLocation())) {
					continue;
				}
			} else if(candidate.vehicleType == AIVehicle.VT_AIR) {
				if(!candidate.place.CanBuildAirport(minimumAiportType, cargo)) {
					continue;
				}
			} else if(candidate.vehicleType == AIVehicle.VT_WATER) {
				local h1 = AITile.GetMaxHeight(orgTile);
				local h2 = AITile.GetMaxHeight(candidate.place.GetLocation());
				candidate.estimate.value = candidate.estimate.value * 10 / (10 + max(0,abs(h1-h2) - 2));
			
				/*if(!WaterRoute.CanBuild(orgPlace, candidate.place, cargo)) {
					continue;
				}*/
			}
			result.push(candidate);
			if(maxResult != null && result.len() >= maxResult) {
				break;
			}
		}
		if(result.len() == 0) {
			Place.AddNgCandidatePlace(orgPlace, cargo);
			/*foreach(vt in Route.allVehicleTypes) {
				Place.AddNgPlace(orgPlace, cargo, vt); // 次回のGetMaxCargoPlacesから除外する為に
			}*/
		}
		
		HgLog.Info("} CreateRouteCandidates:" + orgPlace + "["+AICargo.GetName(cargo) + "] result:"+result.len()+"/"+candidates.len());
		return result;
	}
	
	function GetLocationFromDest(dest) {
		if(dest instanceof Place) {
			return dest.GetLocation();
		} else {
			return dest.srcHgStation.platformTile;
		}
	}

	function GetMeetPlaceCandidates() {
		HgLog.Info("GetMeetPlaceCandidates {");
		local result = [];
		foreach(route in Route.GetAllRoutes()) {
			local place = route.srcHgStation.place;
			if(place == null/* firsのrawとか || !place.IsProcessing()*/) {
				continue;
			}
			if(!route.NeedsAdditionalProducing()) {
				//HgLog.Info("!route.NeedsAdditionalProducing() GetMeetPlaceCandidates"+route);
				continue;
			}
			result.extend( GetMeetPlacePlans( place, route ) );
		}
		HgLog.Info("} GetMeetPlaceCandidates");
		return result;
	}
	
	function GetTransferCandidates(originalRoute=null,  options={}) {
		if(originalRoute == null) {
			HgLog.Info("GetTransferCandidates ALL {");
		}
		local startDate = AIDate.GetCurrentDate();
		local notTreatDest = options.rawin("notTreatDest") ? options.notTreatDest : false;
		local destOnly = options.rawin("destOnly") ? options.destOnly : false;
		local isDest = options.rawin("isDest") ? options.isDest : null;
		if(isDest != null) {
			if(isDest) {
				notTreatDest = false;
				destOnly = true;
			} else {
				notTreatDest = true;
				destOnly = false;
			}
		}
		local routes;
		if(originalRoute != null) {
			routes = [originalRoute];
		} else {
			routes = [];
			local routeList = AIList();
			local current = AIDate.GetCurrentDate();
			routeList.Sort(AIList.SORT_BY_VALUE,false);
			local allRoutes = Route.GetAllRoutes();
			foreach(index,route in allRoutes) {
				if(!lastTransferCandidates.rawin(route.id) || lastTransferCandidates.rawget(route.id) + 365 * 5 < current) {
					routeList.AddItem(index, route.GetDistance());
				}
			}
			foreach(index,_ in routeList) {
				routes.push(allRoutes[index]);
			}
		}
		local result = [];
		foreach(route in routes) {
			local current = AIDate.GetCurrentDate();
			if(startDate + 365 < current) {
				HgLog.Warning("GetTransferCandidates reached limit time(365 days).");
				break;
			}
			if(route.IsRemoved()) continue;
			if(route.IsSupportRaw()) continue;
			lastTransferCandidates.rawset(route.id,current);
			local routeResult = [];
			local transferPlans = [];
			foreach(routeClass in [WaterRoute,TrainRoute,RoadRoute]) {
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					//HgLog.Info("Too many "+routeClass.GetLabel()+" vehicles.");
					continue;
				}
				local vehicleType = routeClass.GetVehicleType();
			
				local ok = false;
				if(vehicleType == AIVehicle.VT_AIR) { // 航空機を転送に用いる事はできない(今のところ)
				} else {
					switch(route.GetVehicleType()) {
						case AIVehicle.VT_RAIL:
							ok = true; //!route.IsSingle();
							break;
						case AIVehicle.VT_ROAD:
							ok = vehicleType == AIVehicle.VT_ROAD; // && route.GetDistance() >= 200 && HogeAI.Get().IsInfrastructureMaintenance()/*メンテコストがかかる場合、長距離道路の転送は認める*/;
							break;
						case AIVehicle.VT_WATER:
							//ok = vehicleType != AIVehicle.VT_WATER;
							ok = true;
							break;
						case AIVehicle.VT_AIR:
							if(route.IsBigPlane()) {
								ok = vehicleType == AIVehicle.VT_ROAD || vehicleType == AIVehicle.VT_RAIL;
							} else {
								ok = vehicleType == AIVehicle.VT_ROAD;
							}
							break;
					}
				}
				if(!ok) {
					continue;
				}
				local plans = [];
				if(!route.IsClosed()) {
					if(!destOnly) {
						plans.extend(CreateTransferPlans(route, false, vehicleType, options));
					}
					if(!notTreatDest && route.IsBiDirectional() && !route.IsChangeDestination()) {
						plans.extend(CreateTransferPlans(route, true, vehicleType, options));
					}else {
						//HgLog.Info("notTreatDest:"+notTreatDest+" IsBiDirectional:"+route.IsBiDirectional()+" IsChangeDestination:"+route.IsChangeDestination()+" "+route);
					}
				}
				if(route.GetDistance() > 1000) { // 転送があると伸びなくなるので路線がすでに長い時にやる
					plans.extend(CreateDestTransferPlans(route, vehicleType));
				}
				HgLog.Info("CreateTransferPlans "+plans.len()+ " by "+ HgVehicleType(vehicleType)+ " "+route);
				transferPlans.extend(plans);
			}
			foreach(t in transferPlans) {
				DoInterval();
				//HgLog.Info("transferPlans t.src:"+t.src+" dist:"+t.distance+" prod:"+t.production+" cargo:"+AICargo.GetName(t.cargo)+" "+t.routeClass.GetVehicleType());
				if(t.src instanceof Place && !t.src.CanUseNewRoute(t.cargo, t.vehicleType)) {
					//HgLog.Info("!t.src.CanUseNewRoute");
					continue;
				}
				
				//local c1 = PerformanceCounter.Start("estimate1"+t.routeClass.GetLabel());
				local infrastractureTypes = t.routeClass.GetSuitableInfrastractureTypes(t.src, t.dest, t.cargo);
				local estimate = Route.Estimate( t.routeClass.GetVehicleType(), t.cargo, t.distance, t.production, false, infrastractureTypes );
				//c1.Stop();
				//HgLog.Info("estimate:"+estimate);
				if(estimate != null) { // TODO: Estimate()はマイナスの場合も結果を返すべき
					//local c2 = PerformanceCounter.Start("estimate2"+t.routeClass.GetLabel());
					estimate = clone estimate;
					
					estimate.EstimateAdditional( t.dest, t.src, infrastractureTypes, t.route, t.sourceRoute, false, t.useLastMonthProduction );
					t.estimate <- estimate;
					t.score <- estimate.value;
					//HgLog.Info("GetTransferCandidates:"+t.dest+"<-"+t.src+" prod:"+t.production+" "+estimate);
					routeResult.push(t);
					//c2.Stop();
				}
			}
			PerformanceCounter.Print();
			//HgLog.Info("GetTransferCandidates sort:"+routeResult.len());
			routeResult.sort(function(t1,t2) {
				return t2.score - t1.score;
			});
			local count = 0;
			foreach(t in routeResult) {
				if(firs && CargoUtils.IsSupplyCargo(t.cargo) && t.estimate.additionalRouteIncome == 0) {
					continue; // firsでは使用されているrawへの供給以外のsupport材輸送は禁止
				}
				if(t.vehicleType == AIVehicle.VT_WATER) {
					if(!WaterRoute.CanBuild(t.src, t.dest, t.cargo, false)) {
						continue;
					}
					local h1 = AITile.GetMaxHeight(t.src.GetLocation());
					local h2 = AITile.GetMaxHeight(t.dest.GetLocation());
					t.estimate.value = t.estimate.value * 10 / (10 + max(0,abs(h1-h2) - 2));
				}
				if(t.vehicleType == AIVehicle.VT_RAIL) {
					if(!HgTile.IsLandConnectedForRail(t.src.GetLocation(), t.dest.GetLocation())) {
						continue;
					}
					t.estimate.value = VehicleUtils.AdjustTrainScoreBySlope(
							t.estimate.value, t.estimate.engine, t.src.GetLocation(), t.dest.GetLocation());				
				}
				if(t.vehicleType == AIVehicle.VT_ROAD && !HgTile.IsLandConnectedForRoad(t.src.GetLocation(), t.dest.GetLocation())) {
					continue;
				}
				result.push(t);
				count ++;
				if(count > 16) {
					break;
				}
			}
			
			DoInterval();
		}
		HgLog.Info("GetTransferCandidates result:"+result.len());
		if(originalRoute == null) {
			HgLog.Info("} GetTransferCandidates ALL");
		}
		return result;
	}
	
	function CreateDestTransferPlans( route, vehicleType ) {
		local routeClass = Route.Class(vehicleType);
		if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
			return [];
		}
		if(route.IsBiDirectional()) {
			return [];
		}
		local lastStation = null;
		if(route.IsTransfer()) {
			return []; 
			// 全ソース位置から計算していないので、マイナス収支になる事がある。またoverflowも一時的な事がある
			/*local overflow = true;
			foreach(usedRoute in route.destHgStation.stationGroup.GetRoutesUsingSource()) {
				if(!usedRoute.HasCargo(route.cargo)) {
					continue;
				}
				if(!usedRoute.IsFullLoadStation(route.destHgStation.stationGroup)) {
					return []; // full loadでない駅をソースにすると全て吸い取ってしまうので禁止
				}
				if(!usedRoute.IsOverflow()) {
					overflow = false;
				}
			}
			if(overflow) {
				lastStation = route.destHgStation;
			}*/
		} else {
			lastStation = route.GetLastDestHgStation();
		}
		if(lastStation == null) {
			return [];
		}
		local result = [];
		local maxDistance = 500;
		foreach(cargo in route.srcHgStation.stationGroup.GetProducingCargos()) {
			//HgLog.Info("CreateDestTransferPlans ["+AICargo.GetName(cargo)+"] "+route);
			if(route.destHgStation.stationGroup.IsAcceptingCargo(cargo)) continue;
			local srcs = route.destHgStation.stationGroup.GetSources(cargo, true);
			//HgLog.Info("CreateDestTransferPlans ["+AICargo.GetName(cargo)+"] srcs.len()="+srcs.len()+" "+route);
			if(srcs.len() == 0) continue;
			local srcStationGroup = srcs[0].stationGroup;
			local srcPlaces = srcStationGroup.GetProducingPlaces(cargo);
			foreach(srcPlace in srcPlaces) {
				if(!srcPlace.CanUseNewRoute(cargo,vehicleType)) {
					//HgLog.Info("CreateDestTransferPlans ["+AICargo.GetName(cargo)+"] !srcPlace.CanUseNewRoute "+route);
					continue;
				}
				
				foreach(place in PlaceProduction.Get().GetArroundPlaces(cargo, false, lastStation.platformTile, 0, maxDistance)) {
					//local drci = place.GetDestRouteCargoIncome(cargo);
					//local aincome = place.GetAdditionalRouteIncome(cargo);
					//HgLog.Info("CreateDestTransferPlans ["+AICargo.GetName(cargo)+"] "+place+" drci:"+drci+" aincome:"+aincome+" "+route);
					//if(drci==0 && aincome==0) continue;
					
					local t = {};
					t.route <- null;
					t.sourceRoute <- route;
					t.vehicleType <- vehicleType;
					t.routeClass <- routeClass;
					t.cargo <- cargo;
					t.dest <- place;
					t.src <- lastStation.stationGroup;
					t.srcPlace <- srcPlace;
					t.distance <- AIMap.DistanceManhattan(t.src.GetLocation(), t.dest.GetLocation());
					// estimateでstation rateに応じて減らすので。stationGroupですでに減った分を増やす。(転送用のEstimate()を作るべきかもしれない)
					t.production <- route.srcHgStation.stationGroup.GetCurrentExpectedProduction(cargo,route.GetVehicleType(),true) * 3 / 2;
					t.useLastMonthProduction <- true;
					t.canChangeDest <- false;
					result.push(t);

					local tFinal = {};
					tFinal.route <- null;
					tFinal.sourceRoute <- null;
					tFinal.vehicleType <- vehicleType;
					tFinal.routeClass <- routeClass;
					tFinal.cargo <- cargo;
					tFinal.dest <- place;
					tFinal.src <- srcPlace;
					tFinal.srcPlace <- srcPlace;
					tFinal.distance <- AIMap.DistanceManhattan(tFinal.src.GetLocation(), tFinal.dest.GetLocation());
					if(tFinal.distance <= maxDistance) {
						tFinal.production <- srcPlace.GetCurrentExpectedProduction(cargo,vehicleType,false);
						tFinal.useLastMonthProduction <- true;
						result.push(tFinal);
					}
				}
				
				break; // 各cargoで1place調べれば十分
			}
		}
		return result;
	}
	
	function CreateTransferPlans(route,isDest,vehicleType,options={}) {
		local routeClass = Route.Class(vehicleType);
		if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
			return [];
		}
		if(route.srcHgStation.IsTownStop()) {
			return [];
		}
		/*
		if(route.IsTransfer()) { // 転送先がRoadやsingle railの事があるのでとりあえず。実際にはroute capacityに空きがあるかどうかの計算が必要
			return [];
		}*/

		local maxDistance;
		local minDistance;
		local minProduction;
		if(vehicleType == AIVehicle.VT_RAIL || vehicleType == AIVehicle.VT_WATER) {
			minDistance = 0;
			maxDistance = 500;
			minProduction = vehicleType == AIVehicle.VT_RAIL ? 1 : 1;
		} else {
			minDistance = 0;
			maxDistance = 200;
			minProduction = 1;
		}
		if(roiBase) {
			maxDistance = max(100,min(maxDistance, route.GetDistance() / 2));
		} else {
			// やらない方がパフォーマンスが良い minProduction = 0; // まだ生産されていない施設を起こして転送する事を検討
		}
		if(route.IsTransfer()) {
			local finalRoute = route.GetFinalDestRoute();
			if(finalRoute==null) {
				return [];
			}
			if(finalRoute.IsBiDirectional()) {
				maxDistance = min(maxDistance,finalRoute.GetDistance()/2 - route.GetTransferDistance());
			}
		}
		if(route.IsBiDirectional()) {
			maxDistance = min(maxDistance,route.GetDistance()/2);
		}
		
		local additionalPlaces = [];
		local hgStation;
		local targetStation;
		if(isDest) {
			hgStation = route.destHgStation;
			targetStation = route.srcHgStation;
		} else {
			hgStation = route.srcHgStation;
			targetStation = route.destHgStation;
		}
		if(hgStation.place != null && hgStation.place.HasStation(vehicleType)) { 
			// 例えば油田。なぜかうまくrouteを作れないが転送できたとしても他社に奪われる事があるので、転送先としては不適切
			return [];
		}
		//local finalDestStation = route.GetFinalDestStation();
		//local finalDestLocation = isDest ? route.srcHgStation.platformTile : finalDestStation.GetLocation();
		local noCheckNeedsAdditionalProducing = options.rawin("noCheckNeedsAdditionalProducing") ? options.noCheckNeedsAdditionalProducing : false;
		
		foreach(cargo in route.GetCargos()) {
			local dests = targetStation.stationGroup.GetDests(cargo, route.IsTransfer());
			if(dests.len()==0) {
				HgLog.Info("dests.len()==0 ["+AICargo.GetName(cargo)+"] CreateTransferPlans isDest:"+isDest+" "+route);
				continue;
			}
			local finalDestLocation = dests[0].GetLocation(); //TODO: 複数ある場合の考慮。（重心？）
		
		/*
			if(route.destHgStation.stationGroup.IsOverflow(cargo)) {
				TODO: destのadditional
			}*/
			if(!noCheckNeedsAdditionalProducing && !route.NeedsAdditionalProducingCargo(cargo, null, isDest)) {
				HgLog.Info("!NeedsAdditionalProducingCargo ["+AICargo.GetName(cargo)+"] CreateTransferPlans isDest:"+isDest+" "+route);
				continue;
			}
			
			local srcPlaceInfos = Place.SearchSrcAdditionalPlaces( 
					hgStation, finalDestLocation, 
					cargo, minDistance, maxDistance, minProduction, vehicleType);
			HgLog.Info("TransferCandidates:"+HgVehicleType(vehicleType)+" isDest:"+isDest+" res:"+srcPlaceInfos.len()
				+" "+hgStation.GetName()+"["+AICargo.GetName(cargo)+"] maxDistance:"+maxDistance+" final:"+dests[0]);
			foreach(srcInfo in srcPlaceInfos) {
				local place = srcInfo.place;
				//HgLog.Info("place:"+place+" dist:"+srcInfo.distance);
				if(!place.CanUseNewRoute(cargo, vehicleType)) {
					HgLog.Info("!CanUseTransferRoute ["+AICargo.GetName(cargo)+"] "+place);
					continue;
				}
				
			
				foreach(useLastMonthProduction in [true,false]) {
					if(!useLastMonthProduction) {
						if(place.GetAccepting().GetCargos().len() == 0) continue;
					}
					local production = useLastMonthProduction ? place.GetCurrentExpectedProduction(cargo, vehicleType) : place.GetExpectedProduction(cargo, vehicleType);
					if(production < minProduction) {
						//HgLog.Info("production < minProduction:"+production+"<"+minProduction+" "+place+"["+AICargo.GetName(cargo)+"] useLastMonthProduction:"+useLastMonthProduction+" "+route);
						continue;
					}
					
					local placeTile = srcInfo.place.GetLocation();
					local exists = false;

					local distTo = AIMap.DistanceManhattan(placeTile,targetStation.stationGroup.GetLocation());
					local distFrom = AIMap.DistanceManhattan(placeTile,hgStation.stationGroup.GetLocation());
					if(distTo - distFrom > distFrom / 2) { // 1.5倍延ばしたらその先に行ける場合は転送しない
						local t = {};
						t.route <- route;
						t.sourceRoute <- null;
						t.vehicleType <- vehicleType;
						t.routeClass <- routeClass;
						t.cargo <- cargo;
						t.dest <- hgStation.stationGroup;
						t.src <- srcInfo.place;
						t.srcPlace <- srcInfo.place;
						t.distance <- srcInfo.distance;
						t.production <- min(route.GetLeftCapacity(cargo), production);
						t.useLastMonthProduction <- useLastMonthProduction;
						//HgLog.Info("additionalSrcPlace:"+t.srcPlace.GetName()+" dest:"+t.dest+ " production:"+t.production+"["+AICargo.GetName(t.cargo)+"] capa:"+route.GetLeftCapacity(cargo)+" distance:"+t.distance+" vt:"+routeClass.GetLabel()+" isDest:"+isDest+" for:"+route);
						additionalPlaces.push(t);
						exists = true;
					}
					if(route.IsTransfer()) { // 転送先が転送の場合、そのdestに直接運んだ場合も (2hop以上先も見る？)
						local nextRoute = route.GetDestRoute();
						if(nextRoute != false) {
							local distTo = AIMap.DistanceManhattan(placeTile,nextRoute.destHgStation.stationGroup.GetLocation());
							if(distTo - distFrom > distFrom / 2) {
								local t = {};
								t.route <- nextRoute;
								t.sourceRoute <- null;
								t.vehicleType <- vehicleType;
								t.routeClass <- routeClass;
								t.cargo <- cargo;
								t.dest <- nextRoute.srcHgStation.stationGroup;
								if(t.dest != null) { //念のため
									t.src <- srcInfo.place;
									t.srcPlace <- srcInfo.place;
									t.distance <- AIMap.DistanceManhattan(placeTile, t.dest.GetLocation());
									if(t.distance <= maxDistance) {
										t.production <- min(nextRoute.GetLeftCapacity(cargo), production);
										t.useLastMonthProduction <- useLastMonthProduction;
										//HgLog.Info("additionalSrcPlace:"+t.srcPlace.GetName()+" dest:"+t.dest+ " production:"+t.production+"["+AICargo.GetName(t.cargo)+"] distance:"+t.distance+" vt:"+routeClass.GetLabel()+" isDest:"+isDest+" for:"+route);
										additionalPlaces.push(t);
										exists = true;
									}
								}
							}
						}
					}
					if(exists) {
						// 直接運んだ場合のプランとも比較する
						local finalPlaces = dests[0].GeAcceptingPlaces(cargo);
						if(finalPlaces.len() >= 1) { // towncargoの場合0になるはず
							local t = {};
							t.route <- null;
							t.sourceRoute <- null;
							t.vehicleType <- vehicleType;
							t.routeClass <- routeClass;
							t.cargo <- cargo;
							t.dest <- finalPlaces[0];
							t.src <- srcInfo.place;
							t.srcPlace <- srcInfo.place;
							t.distance <- AIMap.DistanceManhattan(placeTile, t.dest.GetLocation());
							if(t.distance <= maxDistance) {
								t.production <- production;
								t.useLastMonthProduction <- useLastMonthProduction;
								//HgLog.Info("additionalSrcPlace:"+t.srcPlace.GetName()+" dest:"+t.dest+" production:"+t.production+"["+AICargo.GetName(t.cargo)+"] distance:"+t.distance+" vt:"+routeClass.GetLabel()+" isDest:"+isDest+" for:"+route);
								additionalPlaces.push(t);
							}
						}
					}
				}
			}
		}
		return additionalPlaces;
	}

	function GetNeedsOfRoutes(place, searchedPlaces = null) {
		HgLog.Info("GetNeedsOfRoutes place:"+place.GetName());
		if(searchedPlaces == null) {
			searchedPlaces = {};
		}
		local producing = place.GetProducing();
		if(searchedPlaces.rawin(producing.Id())) {
			return 100; // リング状のインダストリチェーンを見つけた
		}
		searchedPlaces.rawset(producing.Id(), true);
		local result = 0;
		foreach( route in producing.GetRoutesUsingSource() ) {
			HgLog.Info("GetNeedsOfRoutes place:"+place.GetName()+" using:"+route);
			if(route.NeedsAdditionalProducing()) {
				HgLog.Info("NeedsAdditionalProducing:true");
				result += route.GetRouteCapacity() 
					+ (route.destHgStation.place != null ? GetNeedsOfRoutes(route.destHgStation.place, searchedPlaces) : 0);
			}
		}
		return result;
	}

	function GetCargoPlansToMeetSrcDemand(acceptingPlace, forRoute = null, isGetAll = false) {
		if(!acceptingPlace.IsIncreasable()) {
			return [];
		}
		
		local cargos = [];
		foreach(cargo in acceptingPlace.GetCargos()) {
			if(acceptingPlace.IsIncreasableInputCargo(cargo)) {
				cargos.push(cargo);
			}
		}
		if(cargos.len() == 0) {
			return [];
		}
		
		local industryTraits = acceptingPlace instanceof HgIndustry ? acceptingPlace.GetIndustryTraits() : "";		
		
		local stockpiledAverage = 0;
		if(stockpiled) {
			foreach(cargo in cargos) {
				stockpiledAverage += acceptingPlace.GetStockpiledCargo(cargo);
			}
			stockpiledAverage /= cargos.len();
		}
		
		local producingPlace = acceptingPlace.GetProducing();
		local needs = GetNeedsOfRoutes(producingPlace);
		
		local labelCargoMap = {};
		local totalSupplied = 0;
		foreach(cargo in cargos) {
			labelCargoMap.rawset(AICargo.GetCargoLabel(cargo),cargo);
			foreach(route in acceptingPlace.GetRoutesUsingDest(cargo)) {
				totalSupplied += route.GetRouteCapacity();
			}
		}
		local totalNeeds = 0;
		foreach(cargo in producingPlace.GetCargos()) {
			foreach(route in producingPlace.GetRoutesUsingSource(cargo)) {
				totalNeeds += route.GetRouteCapacity();
			}
		}
		

		
		local cargoScores = {};
		local cargoScoreExplain = {};
		local stopped = 0;
		
		foreach(cargo in cargos) {
			local scoreExplain = "SRC";
			local score = 0; // 1以上: 探す 4以上: cargoを作りに行く
			local supplied = 0;
			
			foreach(route in acceptingPlace.GetRoutesUsingDest(cargo)) { //満たされていないcargoを優先する(for FIRS)
				supplied += route.GetRouteCapacity();
			}
			HgLog.Info("supplied:"+supplied+" "+acceptingPlace.GetName()+" "+AICargo.GetName(cargo));
			
			totalSupplied += supplied;
			local stockpiledCargo = 0;
			if(stockpiled) {
				if(!acceptingPlace.IsCargoAccepted(cargo)) {
					stopped += supplied;
					HgLog.Info("stopped:"+stopped+" "+acceptingPlace.GetName()+" "+AICargo.GetName(cargo));
					continue;
				}
				stockpiledCargo = acceptingPlace.GetStockpiledCargo(cargo) ;
				if(stockpiledCargo == 0) {
					if(ecs && (industryTraits == "STEL,/AORE,COAL,"/* Aluminium plant*/ 
							|| industryTraits == "STEL,/IORE,COAL,"/*Steel mill*/ 
							|| industryTraits == "GLAS,/SAND,COAL,"/*glass works*/
							|| industryTraits == "BDMT,GOOD,/RFPR,GLAS,"/*plastic plant*/)) {
						score += 3; // 全部入力しないと何も生産しない
						scoreExplain += "+3(stockpile==0)"
					} else {
						score += 1;
						scoreExplain += "+1(stockpile==0)"
					}
				}
				if(stockpiledCargo < stockpiledAverage) {
					score += 1;
					scoreExplain += "+1(stockpile<stockpiledAverage)"
				}
				local d = stockpiledCargo / 200;
				if(d >= 1) {
					score -= d;
					scoreExplain += "-"+d+"(stockpiledCargo/200)"
				}
			} else {
				score += 1;
				scoreExplain += "1(default)"
				score -= supplied;
				scoreExplain += "-"+supplied+"(supplied)";
			}
			if(totalSupplied == 0) {
				if(yeti) {
					score += 20;
					scoreExplain += "+20(nothingSupplied)" //yetiでは施設閉鎖のリスクがあるので最高優先
				} else {
					score += 1;
					scoreExplain += "+1(nothingSupplied)"
				}
			}
			
			local cargoLabel = AICargo.GetCargoLabel(cargo);

			
			cargoScores[cargoLabel] <- {
				cargo = cargo
				score = score
				explain = scoreExplain
				supplied = supplied
				stockpiled = stockpiledCargo
			};
		}
		
		if(!acceptingPlace.IsRaw() && !acceptingPlace.IsProcessing()) { // この場合全てのcargoを満たさなくても良い(FIRSでは)
			if(totalSupplied >= 2) {
				return [];
			}
		}
		

		local result = [];
		foreach(cargoLabel, cargoScore in cargoScores) {
			if(stockpiled && !acceptingPlace.IsRaw()) {
				cargoScore.score += stopped;
				cargoScore.explain += "+"+stopped+"(stopped)";
			}
			if(totalSupplied == 0 && acceptingPlace.IsProcessing()) {
				cargoScore.score += 2;
				cargoScore.explain += "+2(IsProcessing && totalSupplied==0)"
			}
			if(yeti) {
				local sunk = min(4, totalNeeds + totalSupplied + 1);
				if(acceptingPlace.GetName().find("4X ") != null) { // Worker Yard
					cargoScore.score += 3;
					cargoScore.explain += "+3(Worker Yard)";
					if(cargoLabel == "PASS") {
						if(cargoScore.supplied < 3) {
							cargoScore.score += sunk;
							cargoScore.explain += "+"+sunk+"(PASS)"
						} else {
							cargoScore.score = 0;
							cargoScore.explain = "0(PASS)"
						}
					} else if(cargoLabel == "FOOD") {
						if(cargoScore.supplied < 3 && cargoScores["PASS"].supplied >= 3) {
							cargoScore.score += sunk;
							cargoScore.explain += "+"+sunk+"(FOOD)"
						} else {
							cargoScore.score = 0;
							cargoScore.explain = "0(FOOD)"
						}
					} else if(cargoLabel == "BDMT") {
						if(cargoScore.supplied < 3 && cargoScores["PASS"].supplied >= 3 && cargoScores["FOOD"].supplied >= 3) {
							cargoScore.score += sunk;
							cargoScore.explain += "+"+sunk+"(BDMT)"
						} else {
							cargoScore.score = 0;
							cargoScore.explain = "0(BDMT)"
						}
					}
				} else {
					if(cargoLabel == "YETI") {
						if(cargoScore.supplied < 3) {
							cargoScore.score += sunk;
							cargoScore.explain += "+"+sunk+"(YETI)"
						} else {
							cargoScore.score = 0;
							cargoScore.explain = "0(YETI)"
						}
					} else {
						if(cargoScore.supplied < 3
								&& (!cargoScores.rawin("YETI") || cargoScores["YETI"].supplied >= 3)) {
							cargoScore.score += sunk;
							cargoScore.explain += "+"+sunk+"("+cargoLabel+")"
						} else {
							cargoScore.score = 0;
							cargoScore.explain = "0("+cargoLabel+")"
						}
					}
				}
			}
			if(ecs) {
				if(industryTraits == "PETR,RFPR,/OLSD,OIL_,") {
					if(cargoLabel == "OLSD") {
						cargoScore.score = 0;
						cargoScore.explain = "0(OLSD)"
					}
				} else if( industryTraits == "FERT,FOOD,/GLAS,FRUT,CERE,") {
					if(cargoLabel == "GLAS") {
						if(cargoScore.stockpiled == 0) {
							cargoScore.score += 2;
							cargoScore.explain += "+2(stockpile==0)"
						}
					} else {
						if((cargoScores.rawin("FRUT") && cargoScores["FRUT"].stockpiled == 0) && (cargoScores.rawin("CERE") && cargoScores["CERE"].stockpiled == 0)) {
							cargoScore.score += 2;
							cargoScore.explain += "+2(stockpile==0)"
						} else if(cargoScore.stockpiled == 0) {
							cargoScore.score = 0;
							cargoScore.explain = "0(meet FRUT or CERE)";
						}
					}
				}
			}
			if(isGetAll || cargoScore.score >= 1) {
				local cargoPlan = {};
				cargoPlan.place <- acceptingPlace;
				cargoPlan.cargo <- cargoScore.cargo;
				cargoPlan.score <- cargoScore.score * 100 + needs;
				cargoPlan.scoreExplain <- "("+cargoScore.explain + ")*100+"+needs+"(needs)";
				if(forRoute != null) {
					cargoPlan.forRoute <- forRoute;
				}
				result.push(cargoPlan);
			}
		}
		
		
		return result;
	}

	function GetCargoPlansToMeetDestSupply(destPlace, forRoute = null) {
		local result = [];
		if(!destPlace.IsIncreasable()) {
			return result;
		}
		
		local producingPlace = destPlace.GetProducing();
		local deliverOut = false;
		foreach(cargo in producingPlace.GetCargos()) {
			if(producingPlace.GetLastMonthTransportedPercentage(cargo) > 0) {
				deliverOut = true;
			}
		}
		if(!stockpiled) {
			return [];
		}
		
		local acceptingPlace = destPlace.GetAccepting();
		local totalStopped = 0;
		
		foreach(cargo in acceptingPlace.GetCargos()) {
			local supplied = 0;
			foreach(route in acceptingPlace.GetRoutesUsingDest(cargo)) {
				supplied += route.GetRouteCapacity();
			}
			if(stockpiled) {
				if(!acceptingPlace.IsCargoAccepted(cargo)) {
					totalStopped += supplied;
				}
				if(acceptingPlace.IsCargoNotAcceptedRecently(cargo)) {
					totalStopped += supplied;
				}
			}
		}
		//HgLog.Info("GetCargoPlansToMeetDestSupply total stopped:"+totalStopped+" "+destPlace.GetName());
		
		
		local usedRoutes = PlaceDictionary.Get().GetRoutesBySource(producingPlace);
		foreach(cargo in producingPlace.GetCargos()) {
			if(ecs && cargo == HogeAI.GetPassengerCargo()) {// ecsの釣り船は出力要らない
				continue;
			}
		
			local scoreExplain = "";
			local used = 0;
			foreach(route in usedRoutes) {
				if(route.cargo == cargo) {
					used += route.GetRouteCapacity();
				}
			}
			local transportedPercentage = producingPlace.GetLastMonthTransportedPercentage(cargo);
			//HgLog.Info("GetCargoPlansToMeetDestSupply cargo:"+AICargo.GetName(cargo)+" used:"+used+" transportedPercentage:"+transportedPercentage+" "+destPlace.GetName());
			if( transportedPercentage < 75 ) {
				local cargoPlan = {};
				cargoPlan.place <- producingPlace;
				cargoPlan.cargo <- cargo;
				local score = 0;
				local scoreExplain = "DEST";
				if(Place.IsAcceptedByTown(cargo)) { 
					score += 2;
					scoreExplain += "+2(IsAcceptedByTown)";
				}
				if(totalStopped >= 1) {
					score += totalStopped;
					scoreExplain += "+"+totalStopped+"(stopped)";
					
				}
				if(transportedPercentage==0) {
					score += 1;
					scoreExplain += "+1(transportedPercentage==0)";
					
				}
				if(!deliverOut) {
					score += 1;
					scoreExplain += "+1(nothing deliver out)";
				}
				if(used>=1) {
					score -= used;
					scoreExplain += "-"+used+"(used)";
				}
				cargoPlan.score <- score * 100;
				cargoPlan.scoreExplain <- scoreExplain;
				if(forRoute != null) {
					cargoPlan.forRoute <- forRoute;
				}
				result.push(cargoPlan);
			}
		}
		return result;
	}
		
	function SearchAndBuildToMeetSrcDemand(originalRoute=null) {
		if(/*!firs raw industryへのsupplyは重要 &&*/ !ecs/*acceptできなくなったindustryの対応が必要*/ && !yeti /*コストベースで動かないので不要な事が多い && roiBase */) {
			return;
		}
		HgLog.Info((originalRoute==null ? "###### " : "") + "Search and build to meet place demand for:" + (originalRoute!=null?originalRoute:"all routes"));
		isTimeoutToMeetSrcDemand = false;
		while( true ) {
			local routes;
			if(originalRoute != null) {
				routes = [originalRoute];
			} else {
				routes = Route.GetAllRoutes();
			}
			local placePlans = {};
			foreach(route in routes) {
				foreach(place in route.GetPlacesToMeetDemand()) {
					place = place.GetAccepting();
					local routeScore = route.GetRouteWeighting();
					if(route instanceof CommonRoute && route.HasRailDest()) {
						routeScore += 1;
					}
					if(route.GetProduction() == 0) {
						routeScore += 1;
					}
					local placeId = place.Id();
					local cargoPlans = [];
					if(!placePlans.rawin(placeId)) {
						cargoPlans.extend(GetCargoPlansToMeetSrcDemand(place, route));
						cargoPlans.extend(GetCargoPlansToMeetDestSupply(place, route));
						placePlans.rawset(placeId,{
							//routeScore = routeScore
							cargoPlans = cargoPlans
						});
					} else {
						//placePlans[placeId].routeScore = max(placePlans[placeId].routeScore, routeScore);
					}
				}
				
				DoInterval();
			}
			local cargoPlans = [];
			foreach(placeId, placePlan in placePlans) {
				foreach(cargoPlan in placePlan.cargoPlans) {
					//cargoPlan.score += placePlan.routeScore;
					//cargoPlan.scoreExplain += "routeScore:+"+placePlan.routeScore;
					cargoPlans.push(cargoPlan);
				}
			}
			
			if(cargoPlans.len() == 0) {
				break;
			}
			
			local demandAndSupplyPlans = []
			foreach(cargoPlan1 in cargoPlans) {
				if(!cargoPlan1.place.IsProducing() || cargoPlan1.score < 400) { // 出力側は強い必要が無ければマッチする必要は無い。単純にたくさん取れるところから引くべき
					continue;
				}
				foreach(cargoPlan2 in cargoPlans) {
					if(!cargoPlan2.place.IsAccepting()) {
						continue;
					}
					if(cargoPlan1.cargo == cargoPlan2.cargo) {
						demandAndSupplyPlans.push( {
							place = cargoPlan2.place
							cargo = cargoPlan2.cargo
							destPlace = cargoPlan2.place
							srcPlace = cargoPlan1.place
							score = cargoPlan2.score + 100
							scoreExplain = cargoPlan2.scoreExplain + "+1(MatchNeeds:"+cargoPlan1.place.GetName()+")"
						});
					}
				}
			}
			cargoPlans.extend(demandAndSupplyPlans);

			isTimeoutToMeetSrcDemand = false;
			if(!DoCargoPlans(cargoPlans) || limitDate < AIDate.GetCurrentDate()) {
				if(isTimeoutToMeetSrcDemand) {
					HgLog.Warning("isTimeoutToMeetSrcDemand: true");
				}
				break;
			}
		}
	}
	
	function SearchAndBuildToMeetSrcDemandMin(srcPlace, forRoute, limit, options = {}) {
		if(roiBase) {
			return [];
		}
		HgLog.Info("SearchAndBuildToMeetSrcDemandMin srcPlace:"+srcPlace.GetName()+" route:"+forRoute);
		local result = DoRoutePlans( GetSortedRoutePlans( GetMeetPlacePlans(srcPlace, forRoute) ), limit, options );
		HgLog.Info("End SearchAndBuildToMeetSrcDemandMin srcPlace:"+srcPlace.GetName()+" route:"+forRoute);
		return result;
	}
	
	function GetSortedRoutePlans(plans) {
		local result = SortedList( function(plan) {
			return plan.estimate.value;
		});
		result.Extend(plans);
		return result;
	}

	function DoRoutePlans(routePlans, limit, options) {
		local limitValue = limit.rawin("value") ? limit.value : 0;
		if( !roiBase ) {
			limitValue = min(limitValue,0/*40000*/); ///= 4;
		}
		//HgLog.Warning("DoRoutePlans limit.capacity:"+limit.capacity+" limit.value:"+limitValue);
		if( limit.capacity < 0 ) {
			return [];
		}
		local result = [];
		local sumDelivable = 0;
		local failCount = 0;
		local dirtyPlaces = {};
		while(routePlans.Count() >= 1) {
			local plan = routePlans.Pop();
			HgLog.Info("DoRoutePlans plan:"+plan.estimate.value+"/"+limitValue+" "+plan.dest.GetName()+"<-"+plan.src.GetName()+" "+plan.estimate);
			if(dirtyPlaces.rawin(plan.src.GetFacilityId()+":"+plan.cargo)) {
				HgLog.Info("dirtyPlaces src "+plan.src.GetName());
				continue;
			}
			if(plan.estimate.value < limitValue) {
				continue;
			}
			if(sumDelivable >= limit.capacity) { // TODO: firsではcargoごとのlimit
				continue;
			}
			local newRoute = DoRoutePlan(plan,"",options);
			if( newRoute == false) {
				continue;
			}
			if( newRoute != null) {
				dirtyPlaces.rawset(plan.src.GetGId()+":"+plan.cargo, true);
				result.push(newRoute);
				local delivable = newRoute.GetTotalDelivableProduction();
				sumDelivable += delivable;
				//HgLog.Info("DoRoutePlans:"+routePlans.Count()+" delivaleProd:"+delivable+" sumDelivable:"+sumDelivable+"/limit:"+limit.capacity+" newRoute:"+newRoute);
			} else {
				//HgLog.Warning("DoRoutePlans:"+routePlans.Count()+" failCount:"+failCount);
				failCount ++;
				if(plan.vehicleType == AIVehicle.VT_WATER) {
					if(failCount >= 6) { // waterは失敗しまくる
						break;
					}
				} else {
					if(failCount >= 2) {
						break;
					}
				}
			}
		}
		return result;
	}
	
	function DoRoutePlan(routePlan, explain = "", options = {}) {
		local newOptions = clone options;
		if("canChangeDest" in routePlan) {
			newOptions.rawset("canChangeDest", routePlan.canChangeDest);
		}
		local routeBuilder = routePlan.routeClass.GetBuilderClass()(routePlan.dest, routePlan.src, routePlan.cargo, newOptions);
		HgLog.Info(routeBuilder + explain);
		local newRoute = routeBuilder.Build();
		if(newRoute != null) {
			if(newRoute.IsTransfer() && routePlan.rawin("route")) {
				routePlan.route.NotifyAddTransfer(newRoute.cargo);
			}
			if(routePlan.rawin("canChangeDest") && routePlan.canChangeDest) {
			} else {
				newRoute.SetCannotChangeDest(true);
			}
			return newRoute;
		}
		return null;
	}
	
	function SortRoutePlans(routePlans) {
		foreach(plan in routePlans) {
			plan.deliver <- min( plan.estimate.GetRouteCapacity(plan.cargo), plan.production );
			plan.score = plan.estimate.value;
		}
		routePlans.sort(function(p1,p2) {
			return p2.score - p1.score;
		});
		foreach(e in routePlans) {
			local s = "CreateRoutePlans.score"+e.score+" production:"+e.production+" deliver:"+e.deliver+" vt:"+e.vehicleType
				+" "+e.destPlace.GetName() + "<-" + e.srcPlace.GetName()+" ["+AICargo.GetName(e.cargo)+"] distance:"+e.distance;
			HgLog.Info(s);
		}
		return routePlans;
	}
	
	function GetMeetPlacePlans(srcPlace, forRoute = null) {
		if(!srcPlace.IsIncreasable() || srcPlace instanceof TownCargo) { // TODO: 砂漠の食料と水とか
			return [];
		}
		local acceptingPlace = srcPlace.GetAccepting();
		local result = [];
		foreach(cargo in acceptingPlace.GetCargos()) {
			if(firs) {
			} else {
				if(!acceptingPlace.IsIncreasableInputCargo(cargo)) {
					continue;
				}
			}
			foreach(useLastMonth in [true,false]) {
				result.extend(CreateRoutePlans({place=acceptingPlace,cargo=cargo},8,
					{noShowResult=true, noSortResult=true, useLastMonthProduction=useLastMonth}));
			}
		}
		return result;
	}


	function DoCargoPlans( cargoPlans, searchedPlaces = null ) {
		if(searchedPlaces == null) {
			searchedPlaces = {};
		}
		foreach(cargoPlan in cargoPlans) {
			cargoPlan.location <- cargoPlan.place.GetLocation();
		}
		cargoPlans.sort(function(a,b) {
			if(a.score == b.score) {
				return b.location - a.location;
			} else {
				return b.score - a.score;
			}
		});
		foreach(cargoPlan in cargoPlans) {
			HgLog.Info("cargoPlan:"+cargoPlan.place.GetName()+"["+AICargo.GetName(cargoPlan.cargo)+"] score:"+cargoPlan.score+" "+cargoPlan.scoreExplain);
		}
		foreach(cargoPlan in cargoPlans) {
			local cargoPlanName = cargoPlan.place.GetName()+ "["+AICargo.GetName(cargoPlan.cargo)+"]";
			if(!cargoPlan.rawin("srcPlace") && cargoPlan.place.IsAccepting()) {
				local searchedPlacesLocal = clone searchedPlaces;
				foreach(supplyer in cargoPlan.place.GetRoutesUsingDest(cargoPlan.cargo)) { // すでにそのcargoを供給しているルートがあるのでまずはそちらを満たせるか調べてみる。
					if(supplyer.GetVehicleType() != AIVehicle.VT_RAIL) {
						continue;
					}
					local supplyerPlace = supplyer.srcHgStation.place;
					if(supplyerPlace == null) {
						continue;
					}
					local accepting = supplyerPlace.GetAccepting();
					HgLog.Info("Found supplyer("+supplyer+").cargoPlan:"+cargoPlanName);
					if(searchedPlacesLocal.rawin(accepting.Id())) {
						HgLog.Warning("Circular reference "+accepting.GetName()+". cargoPlan:"+cargoPlanName);
						return false; // 無限ループするのでfalseを返す
					}
					searchedPlacesLocal.rawset(accepting.Id(), true);
					DoCargoPlans( GetCargoPlansToMeetSrcDemand( accepting ), searchedPlacesLocal );
					if(limitDate < AIDate.GetCurrentDate()) {
						isTimeoutToMeetSrcDemand = cargoPlan.score >= 400;
						return false; // return するのは時間切れの場合のみ
					}
				}
			
			}
			foreach(routePlan in CreateRoutePlans( cargoPlan )) {
				local accepting = routePlan.src.GetAccepting();
				if(routePlan.production == 0 && accepting.GetRoutesUsingDest().len() == 0) {
					local srcName = accepting.GetName()+ "["+AICargo.GetName(routePlan.cargo)+"]";
					HgLog.Info("routePlan: "+ srcName + " is not producing."
						+ "Search routePlan to meet the demand for the srcPlace recursivly. cargoPlan:"+cargoPlanName);
					if(searchedPlaces.rawin(accepting.Id())) {
						HgLog.Warning("Circular reference "+accepting.GetName()+". cargoPlan:"+cargoPlanName);
						return false; // 無限ループするのでfalseを返す。<=ゼロ生産施設へのルートを建設する為にtrueを返す
					}
					searchedPlaces.rawset(accepting.Id(), true);
					DoCargoPlans( GetCargoPlansToMeetSrcDemand( accepting ), searchedPlaces );
					if(limitDate < AIDate.GetCurrentDate()) {
						isTimeoutToMeetSrcDemand = cargoPlan.score >= 400;
						return false;
					}
				}
				if(DoRoutePlan(routePlan,  cargoPlan.rawin("forRoute") ? " for:"+cargoPlan.forRoute:"") != null) {
					HgLog.Info("Success to meet the demand for cargoPlan:"+cargoPlanName);
					if(limitDate < AIDate.GetCurrentDate()) {
						isTimeoutToMeetSrcDemand = cargoPlan.score >= 400;
						return false;
					} else {
						return true;
					}
				}
				if(limitDate < AIDate.GetCurrentDate()) {
					isTimeoutToMeetSrcDemand = cargoPlan.score >= 400;
					return false;
				}
				if(cargoPlan.score < 100) {
					return false;
				}
			}
			DoInterval();
		}
		return false;
	}
	
	function CalculateRoutePlanScore(routePlan) {
		return Route.GetRouteCapacityVt(routePlan.vehicleType) * 1000000 + (routePlan.production == 0 ? 1000 : routePlan.estimate.value * 100) / routePlan.distance;
	}
	
	function CreateRoutePlans(cargoPlan, maxResult=8, options={}) {
		local additionalProduction = 0; // expectbaseに変更 //現在生産量でソースを選択しなくてはならないが、初期でほとんど何も生産していない場合がある
		local routePlans = [];
		local cargo = cargoPlan.cargo;
		local noShowResult = options.rawin("noShowResult") ? options.noShowResult : false;
		local noSortResult = options.rawin("noSortResult") ? options.noSortResult : false;
		if(cargoPlan.rawin("srcPlace")) { // destPlace <- srcPlace 固定
			foreach(destCandidate in CreateRouteCandidates(cargo, cargoPlan.srcPlace, {places=[cargoPlan.destPlace]}, 
					additionalProduction, maxResult, options)) {
				local routePlan = {};
				local routeClass = Route.Class(destCandidate.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				if(!cargoPlan.srcPlace.CanUseNewRoute(cargo,destCandidate.vehicleType)) {
					continue;
				}
				routePlan.canChangeDest <- false;
				routePlan.cargo <- cargo;
				routePlan.src <- cargoPlan.srcPlace;
				routePlan.dest <- destCandidate.place;
				routePlan.distance <- destCandidate.distance;
				routePlan.production <- destCandidate.production;
				routePlan.vehicleType <- destCandidate.vehicleType;
				routePlan.routeClass <- routeClass;
				routePlan.estimate <- destCandidate.estimate;
				routePlan.score <- destCandidate.score;
				routePlans.push(routePlan);
			}
		} else if(cargoPlan.place.IsAccepting()) { // destPlace固定
			local acceptingPlace = cargoPlan.place;
			local maxDistance = 0;
			if(cargoPlan.rawin("maxDistance")) {
				maxDistance = cargoPlan.maxDistance;
			} else {
				maxDistance = 500;
			}
			
			foreach(srcCandidate in CreateRouteCandidates(cargo, acceptingPlace, 
					{searchProducing = true, maxDistance = maxDistance}, additionalProduction, maxResult, options)) {
				local routePlan = {};
			
				local routeClass = Route.Class(srcCandidate.vehicleType);
				if(!acceptingPlace.IsRaw() && routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) { //raw industryを満たすのは重要なので例外(for FIRS)
					continue;
				}
				if(!srcCandidate.place.CanUseNewRoute(cargo,srcCandidate.vehicleType)) {
					continue;
				}
				routePlan.canChangeDest <- false;
				routePlan.cargo <- cargo;
				routePlan.src <- srcCandidate.place;
				routePlan.dest <- acceptingPlace;
				routePlan.distance <- srcCandidate.distance;
				routePlan.production <- srcCandidate.production;
				routePlan.vehicleType <- srcCandidate.vehicleType;
				routePlan.routeClass <- routeClass;
				routePlan.estimate <- srcCandidate.estimate;
				routePlan.score <- srcCandidate.score;
				if(roiBase && routePlan.production==0) {
					continue;
				}
				routePlans.push(routePlan);
			}
		} else {
			local producingPlace = cargoPlan.place;// srcPlace固定
			foreach(destCandidate in CreateRouteCandidates(cargo, producingPlace,
					{searchProducing = false}, additionalProduction, maxResult, options)) {
				local routePlan = {};
				local routeClass = Route.Class(destCandidate.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				if(!producingPlace.CanUseNewRoute(cargo,destCandidate.vehicleType)) {
					continue;
				}
				routePlan.canChangeDest <- true;
				routePlan.cargo <- cargo;
				routePlan.src <- producingPlace;
				routePlan.dest <- destCandidate.place;
				routePlan.distance <- destCandidate.distance;
				routePlan.production <- destCandidate.production;
				routePlan.vehicleType <- destCandidate.vehicleType;
				routePlan.routeClass <- routeClass;
				routePlan.estimate <- destCandidate.estimate;
				routePlan.score <- destCandidate.score;
				routePlans.push(routePlan);
			}
		}
		/*距離の短さより収益性で評価する
		foreach(routePlan in routePlans) {
			routePlan.score = CalculateRoutePlanScore(routePlan);
		}*/
		
		if(!noSortResult) {
			routePlans.sort(function(a,b) {
				return b.score - a.score;
			});
		}
		if(!noShowResult) {
			foreach(e in routePlans) {
				local s = "CreateRoutePlans.score"+e.score+" production:"+e.production+" value:"+e.estimate.value+" vt:"+e.vehicleType
					+" "+e.dest.GetName() + "<-" + e.src.GetName()+" ["+AICargo.GetName(e.cargo)+"] distance:"+e.distance;
				HgLog.Info(s);
			}
		}
		
		return routePlans;
	}
	
	function GetEstimateDistanceIndex(distance) {
		return HogeAI.GetEstimateIndex(HogeAI.distanceEstimateSamples, distance);
	}

	function GetEstimateRange(sample, index) {
		local result = [null,null];
		if(index-1 >= 0) {
			result[0] = (sample[index-1] + sample[index]) / 2;
		}
		if(index+1 < sample.len()) {
			result[1] = (sample[index+1] + sample[index]) / 2;
		}
		return result;
	}

	function GetEstimateProductionIndex(production) {
		return HogeAI.GetEstimateIndex(HogeAI.productionEstimateSamples, production);
	}

	function GetEstimateIndex(samples, value) {
		local pre = null;
		foreach(i, d in samples) {
			if(value < d) {
				if(i==0) {
					return 0;
				} else {
					if(abs(pre-value) > abs(d-value)) {
						return i;
					} else {
						return i-1;
					}
				}
			}
			pre = d;
		}
		return samples.len() - 1;
	}
	

	function SearchAndBuildAdditionalDestAsFarAsPossible(route, continuation = false) {
		if(roiBase) {
			return null;
		}
		local result = false;
		while(SearchAndBuildAdditionalDest(route, continuation) != null) {
			continuation = true;
			result = true;
		}
		if(result) {
			if(CargoUtils.IsPaxOrMail(route.cargo)) {
				CommonRouteBuilder.CheckTownTransfer(route, route.destHgStation);
			}
		}
		return result;
	}

	function SearchAndBuildAdditionalDest(route, continuation = false) {
		/*if(TrainRoute.instances.len() <= 1) { // 最初の1本目は危険なので伸ばさない
			return null;
		}*/
		if(route.IsSingle()) {
			return null;
		}
		if(route.cannotChangeDest) {
			return null;
		}
		local destHgStation = route.GetLastDestHgStation();
		if(destHgStation.place == null) {
			return null;
		}
		
		if(destHgStation.place instanceof HgIndustry) {
			foreach(usingRoute in destHgStation.place.GetRoutesUsingSource()) {
				if(usingRoute.GetRouteWeighting() >= 2) {
					return null;
				} else if(!usingRoute.IsTransfer()) {
					return null;
				}
			}
			foreach(usingRoute in destHgStation.place.GetRoutesUsingDest()) {
				if(usingRoute == route) {
					continue;
				}
				return null;
			}
		}

		if(route.GetLastRoute().returnRoute != null) {
			return null;
		}
		if(route.GetDistance() > TrainRoute.GetIdealDistance(route.cargo)) {
			return null;
		}
		
		local maxExtDistance = min(1000, TrainRoute.GetIdealDistance(route.cargo) - route.pathDistance);
		if(maxExtDistance < 100) {
			return null;
		}
		/*
		
		if(route.IsClosed()) {
			maxExtDistance = 500;
		} else {
			local currentValue = 0;//route.latestEngineSet.income;
			for(local extDistance = 0; extDistance <= 500; extDistance += 100) {
				local engineSets = route.GetEngineSets(false, extDistance);
				local estimate = engineSets.len() >= 1 ? engineSets[0] : null;
			
//				estimate = Route.Estimate(AIVehicle.VT_RAIL, route.cargo, route.GetDistance() + distance, route.GetProduction(), route.IsBiDirectional());
				if(estimate == null) {
					break;
				}
				HgLog.Info("AdditionalDest distance:"+(extDistance+route.GetDistance())+" "+estimate);
				local score = estimate.routeIncome; // 比較元は建築済みなのでbuildingTimeは加味しない
				if(score > currentValue) {
					currentValue = score;
					maxExtDistance = extDistance;
				}
			}
			
			if(!continuation && (maxExtDistance < route.GetDistance() /2 && maxExtDistance < 400)) {
				HgLog.Warning("No need to extend route "+route);
				return null;
			}
			
			if(maxExtDistance <= 0) { // transfer分も加味 TODO: まじめに計算
				HgLog.Warning("No need to extend route "+route);
				return null;
			}
//			maxDistance -= 100;
			HgLog.Info("SearchAndBuildAdditionalDest maxExtDistance:"+maxExtDistance+" "+route);
		}*/
		
		local lastAcceptingTile = destHgStation.platformTile;
		local ecsHardDest = ecs && destHgStation.place.IsEcsHardNewRouteDest(route.cargo);
		
		/*
		local checkTiles = route.pathSrcToDest.path.GetTiles(16);
		checkTiles = checkTiles.slice(0,min(checkTiles.len(),16));
		foreach(t in checkTiles) {
			HgLog.Info("checkTiles:"+HgTile(t));
		}*/
		
		local tryCount = 0;
		local placeScores = [];
		local minPopulation = null;
		if(route != null && route.IsBiDirectional()) {
			local place = destHgStation.place;
			if(place != null && place instanceof TownCargo) {
				minPopulation = min(1500,AITown.GetPopulation(place.town));
			}
		}
		local srcLocations = [];
		local srcStationGroup = route.srcHgStation.stationGroup;
		local x = 0;
		local y = 0;
		local srcCruiseDays = 0;
		local sources = srcStationGroup.GetSources(route.cargo);
		foreach(src in sources) { //TODO: 複数cargo
			local location = src.stationGroup.GetLocation();
			if(location == null) continue;
			srcLocations.push(location);
			x += AIMap.GetTileX(location);
			y += AIMap.GetTileY(location);
			srcCruiseDays += src.days;
		}
		local sourcesNum = sources.len();
		if(sourcesNum == 0) {
			HgLog.Warning("SearchAndBuildAdditionalDest sourcesNum == 0 "+route);
			return null;
		}
		x /= sourcesNum;
		y /= sourcesNum;
		srcCruiseDays /= sourcesNum;
		local srcCenterTile = AIMap.GetTileIndex(x,y);
		local engineSet =  route.GetLatestEngineSet();
		if(engineSet == null) {
			HgLog.Warning("SearchAndBuildAdditionalDest engineSet == null "+route);
			return null;
		}
		local cargoProduction = {};
		foreach(cargo in srcStationGroup.GetProducingCargos()) {
			if(!engineSet.cargoCapacity.rawin(cargo)) {
				if(srcStationGroup.CanUseNewRoute(cargo, route.GetVehicleType())) {
					cargoProduction[cargo] <- srcStationGroup.GetCurrentExpectedProduction(cargo, route.GetVehicleType(), false);
				}
			} else {
				cargoProduction[cargo] <- srcStationGroup.GetCurrentExpectedProduction(cargo, route.GetVehicleType(), true);
			}
		}
		
		local production = srcStationGroup.GetExpectedProduction(route.cargo, route.GetVehicleType(), true);
		local estimateCurrent = Route.Estimate(AIVehicle.VT_RAIL, route.cargo, route.GetDistance(), production , route.isBiDirectional, [route.GetRailType()]);
		if(estimateCurrent == null) {
			HgLog.Warning("SearchAndBuildAdditionalDest estimateCurrent == null production:"+production+" "+route);
			return null;
		}
		estimateCurrent = clone estimateCurrent;
		estimateCurrent.AppendCruiseDistance(route.pathDistance);
		estimateCurrent.AppendSources(srcCenterTile, srcCruiseDays, destHgStation.place);
		estimateCurrent.Estimate();

		local currentRouteIncome = estimateCurrent.routeIncome;
		local currentValue = currentRouteIncome / estimateCurrent.buildingTime;
		DoInterval();
		HgLog.Info("SearchAndBuildAdditionalDest currentValue:"+currentValue
			+" routeIncome:"+currentRouteIncome+" cargoDist:"+route.GetDistance()+" production:"+production+" buildingDist:"+route.pathDistance+" "+route);
		foreach(placeScore in Place.SearchAdditionalAcceptingPlaces(
				route.GetUsableCargos(), srcLocations, destHgStation.platformTile, 
				1000, minPopulation)) {
			if(placeScore[0].IsSamePlace(destHgStation.place)) {
				continue;
			}
			if(ecs && /*!ecsHardDest &&*/ placeScore[0].IsEcsHardNewRouteDest(route.cargo)) {
				continue;
			}
			/* 延ばせないよりはマシ
			if(route.IsBiDirectional() && route.srcHgStation.place!=null && destHgStation.place!=null) {
				if(!placeScore[0].GetProducing().CanUseNewRoute(route.cargo, AIVehicle.VT_RAIL)) {
					continue;
				}
			}*/
			
			local placeLocation = placeScore[0].GetLocation();
			//local nearestInfo = route.pathSrcToDest.path.GetNearest(placeLocation);
			//local forkPoint = nearestInfo.path.tile;
			//local buildingDistance = nearestInfo.distance;
			local forkPoint = destHgStation.platformTile;
			local buildingDistance = AIMap.DistanceManhattan(placeLocation, destHgStation.platformTile);
			local reuseDistance = route.pathDistance; ///*route.pathDistance -*/ nearestInfo.path.GetRailDistance();
			local cruiseDistance = reuseDistance + buildingDistance;
			local cargoDistance = AIMap.DistanceManhattan(placeLocation, route.srcHgStation.GetLocation());
			local estimate = Route.Estimate(AIVehicle.VT_RAIL, route.cargo, cargoDistance, production, route.isBiDirectional, [route.GetRailType()]);
			if(estimate == null) {
				HgLog.Info("addtional place:"+placeScore[0]+" estimate == null");
				continue;
			}
			estimate = clone estimate;
			estimate.AppendCruiseDistance(cruiseDistance);
			estimate.AppendSources(srcCenterTile, srcCruiseDays, placeScore[0]);
			estimate.Estimate();
			local buildingTime = 100 + max(100,buildingDistance * 4);
			
			local value = (estimate.routeIncome - estimateCurrent.routeIncome) / buildingTime;
			HgLog.Info("addtional place:"+placeScore[0]+" value:"+value+" routeIncome:"+estimate.routeIncome+" cargoDist:"+cargoDistance+" reuseDist:"+reuseDistance+" buildingDist:"+buildingDistance);
			if(value < currentValue / 5) continue;
			local slopeRate = VehicleUtils.AdjustTrainScoreBySlope( 100, route.GetLatestEngineSet().engine, forkPoint, placeLocation, true );
			if(slopeRate < 50) {
				continue;
			}
			local score = value;
			placeScore[1] = score * slopeRate / 100;
			if(placeScore[0] != null && placeScore[0] instanceof TownCargo) {
				placeScore[1] = (placeScore[1].tofloat() * (min(3000,AITown.GetPopulation(placeScore[0].town))+1500) / 3000).tointeger();
			}
			local orgScore = placeScore[1];
			local income = AICargo.GetCargoIncome(route.cargo, cargoDistance, estimate.cruiseDays) * cargoProduction[route.cargo];
			foreach(subCargo,prod in cargoProduction) {
				if(subCargo == route.cargo) continue;
				if(placeScore[0].IsAcceptingCargo(subCargo)) {
					// TODO: 全部運べるとは限らない
					placeScore[1] += (orgScore * AICargo.GetCargoIncome(subCargo, cargoDistance, estimate.cruiseDays).tofloat() * prod / income).tointeger();
				}
			}
			placeScores.push(placeScore);
			DoInterval();
		}
		
		placeScores.sort(function(a,b) {
			return b[1] - a[1];
		});
		
		foreach(placeScore in placeScores) {
			DoInterval();	
			if(!HgTile.IsLandConnectedForRail(placeScore[0].GetLocation(), destHgStation.platformTile)) {
				continue;
			}
			HgLog.Info("Found an additional accepting place:"+placeScore[0].GetName()+" route:"+route);		

			local result = TrainRouteExtendBuilder(route,placeScore[0]).Build();
			if(result == 0) {
				//CheckAndBuildCascadeRoute(placeScore[0],route.cargo);
				lastTransferCandidates.rawdelete(route.id);
				return placeScore[0];
			}
			Place.AddNgPathFindPair(placeScore[0], lastAcceptingTile, AIVehicle.VT_RAIL);
			if(result == 1) { // stationを作れなかった場合
				continue;
			}
			return null;
		}
		HgLog.Info("Not found an additional accepting place. route:"+route);
		return null;
	}

	function CheckBuildReturnRoute(route, limitValue=null) {
		/*if(ecs) { // TODO ECSでは頻繁にdestが受け入れなくなり、destが変更になる事から対応が難しい, YETIも必要な経路では無い事が多い=>受け入れ拒否に対する対応が進んでいる
			return;
		}*/
	
		HgLog.Info("CheckBuildReturnRoute:"+route+" "+route.GetDistance());
		if(route.returnRoute == null && route.GetDistance() >= 800
				&& !route.IsBiDirectional() && !route.IsSingle() && !route.IsTransfer() && !route.IsChangeDestination() && !route.cannotChangeDest) {
			HgLog.Info("SearchReturnPlacePairs route:"+route);
			local t = SearchReturnPlacePairs(route.GetPathAllDestToSrc(), route.cargo);
			if(t.pairs.len() >= 1) {
				local pair = t.pairs[0];
				HgLog.Info("Found return route:"+pair[0].GetName()+" to "+pair[1].GetName()+" used route:"+route);
				return TrainReturnRouteBuilder(route,pair[0],pair[1]).Build();
			} else {
				HgLog.Info("Not found ReturnPlacePairs route:"+route);
			}
			
			/* else if(t.placePathDistances.len() >= 1){
				HgLog.Info("Build empty return route:"+t.placePathDistances[0][0].GetName()+" used route:"+route);
				BuildReturnRoute(route,null,t.placePathDistances[0][0]);
			}*/
		}
		return null;
	}
	
	function GetMinDistanceFromPoints(location, points) {
		local minInfo = null;
		foreach(tile in points) {
			local d = AIMap.DistanceManhattan(tile, location);
			if(minInfo == null || d < minInfo[1]) {
				minInfo = [tile,d];
			}
		}
		return minInfo;
	}
	
	function SearchReturnPlacePairs(path,cargo) {
		local placeDictionary = PlaceDictionary.Get();
		local checkPointsStart = path.GetCheckPoints(32,3);
		local checkPointsEnd = path.Reverse().GetCheckPoints(32,3);
		local startTile = path.GetTile();
		local lastTile = path.GetLastTile();
		local totalLength = AIMap.DistanceManhattan(startTile, lastTile);

		local srcPlaces = PlaceProduction.Get().GetArroundPlaces(cargo, true, lastTile, 0, totalLength / 2);
		local srces = HgArray(srcPlaces).Map(function(place):(cargo) {
			return {
				place = place
				production = place.GetExpectedProduction(cargo, AIVehicle.VT_RAIL)
			}
		}).Filter(function(t) :(placeDictionary,cargo) {
			return t.production >= 50 && !Place.IsNgPlace(t.place,cargo,AIVehicle.VT_RAIL);
		}).Map(function(t) : (checkPointsEnd) {
			local tiled = HogeAI.GetMinDistanceFromPoints(t.place.GetLocation(), checkPointsEnd);
			t.pathTile <- tiled[0];
			t.distanceFromPath <- tiled[1];
			return t;
		}).Filter(function(t) {
			return t.distanceFromPath <= 250;
		}).Map(function(t):(startTile) {
			t.score <- AIMap.DistanceManhattan(t.place.GetLocation(), startTile ) * t.production / (t.distanceFromPath + 250);
			return t;
		}).Sort(function(a,b){
			return b.score - a.score;
		}).Slice(0,16);
		
		local destPlaces = PlaceProduction.Get().GetArroundPlaces(cargo, false, startTile, 0, totalLength / 2);
		local dests = HgArray(destPlaces).Map(function(place) : (checkPointsStart) {
			local tiled = HogeAI.GetMinDistanceFromPoints(place.GetLocation(), checkPointsStart);
			return {
				place = place
				pathTile = tiled[0]
				distanceFromPath = tiled[1]
			}
		}).Filter(function(t):(cargo) {
			return t.distanceFromPath<=250 && t.place.IsAccepting() && !Place.IsNgPlace(t.place,cargo,AIVehicle.VT_RAIL);
		}).Map(function(t):(lastTile) {
			t.score <- AIMap.DistanceManhattan(t.place.GetLocation(), lastTile ) / (t.distanceFromPath + 250);
			return t;
		}).Sort(function(a,b){
			return b.score - a.score;
		}).Slice(0,8);

		local pairs = [];
		foreach(src in srces.array) {
			local srcPlace = src.place;
			local production = src.production;
			local pathTileS = src.pathTile;
			local distanceS = src.distanceFromPath;
			//production = Place.AdjustProduction(srcPlace, production);

			foreach(dest in dests.array) {
				local destPlace = dest.place;
				local pathTileD = dest.pathTile;
				local distanceD = dest.distanceFromPath;
				local used = HgTile(path.GetTile()).DistanceManhattan(HgTile(lastTile)) 
					- (HgTile(lastTile).DistanceManhattan(HgTile(pathTileS)) + HgTile(startTile).DistanceManhattan(HgTile(pathTileD)));
				if(used < 200 || used < distanceS + distanceD || used < totalLength / 2) {
					continue;
				}
				local dCost = AIMap.DistanceManhattan(destPlace.GetLocation(), pathTileD);
				local sCost = AIMap.DistanceManhattan(srcPlace.GetLocation(), pathTileS);
				local xCost = AIMap.DistanceManhattan(srcPlace.GetLocation(), destPlace.GetLocation());
				local score = xCost * production / (dCost + sCost + 500);
				pairs.push([srcPlace,destPlace,pathTileS,pathTileD,score]);
			}
		}
		pairs.sort(function(a,b) {return b[4] - a[4];});
		local resultPair = [];
		foreach(pair in pairs) {
			if(HgTile.IsLandConnectedForRail(pair[1].GetLocation(), pair[3])
					&& HgTile.IsLandConnectedForRail(pair[0].GetLocation(), pair[2])) {
				resultPair.push(pair);
				if(resultPair.len() >= 1) {
					break;
				}
			}
		}
		
		return {
			pairs = resultPair
		};
	}
	
	function GetBuildableStationByPath(path, gap, srcTile, toTile, cargo, platformLength) {
		path = path.Reverse().GetParentLen(gap);
		if(path == null) {
			HgLog.Warning("path.Reverse().GetParentLen==null(GetBuildableStationByPath)");
			return null;
		}
		local count = 0;
		local minCandidates = 64;
		local paths = [];
		local pathDistance = AIList();
		pathDistance.Sort(AIList.SORT_BY_VALUE, true);
		while(path != null) {
			local parentPath = path.GetParent();
			if(parentPath == null) break;
			if(srcTile == null) {
				pathDistance.AddItem(paths.len(),count);
			} else {
				// parentが分岐の起点なのでそこからの距離を計算する
				local t = parentPath.GetTile();
				pathDistance.AddItem(paths.len(), AIMap.DistanceManhattan(t,srcTile) + AIMap.DistanceManhattan(t,toTile));
			}
			paths.push(path);
			path = parentPath;
			count++;
			if(count > 128) break;
		}
		local count = 0;
		local stationFactory = TransferStationFactory();
		stationFactory.platformLength = platformLength;
		stationFactory.minPlatformLength = platformLength;
		
		local stations = [];
		local stationScore = AIList();
		stationScore.Sort(AIList.SORT_BY_VALUE, false);

		foreach(pathIndex,distance in pathDistance) {
			if(stations.len() >= minCandidates) break;
		
			path = paths[pathIndex];
					
			local forks = path.GetMeetsTiles(); //Reverseのmeetsなのでforks
			if(forks == null) {
				continue;
			}
			foreach(forkTiles in forks) {
				local s = forkTiles[2];
				local forkable;
				{
					local testMode = AITestMode();
					forkable = !AIRail.IsRailTile(forkTiles[2]) && AIRail.BuildRail(forkTiles[0], forkTiles[1], forkTiles[2]);
				}
				//HgLog.Info("forkTiles:"+HgTile.GetTilesString(forkTiles)+" "+forkable);
				local freeSideScore = forkable ? 5 : 0;
				local d = (forkTiles[2] - forkTiles[1]) / AIMap.DistanceManhattan(forkTiles[2],forkTiles[1]);
//					HgLog.Info("forkTiles[0]" + HgTile(forkTiles[0]) + " [1]" + HgTile(forkTiles[1]) + " [2]"+HgTile(forkTiles[2]));
				if(HgStation.GetStationDirectionFromTileIndex(d)==null) {
					//HgLog.Warning("forkTiles[1]" + HgTile(forkTiles[1]) + " forkTiles[0]"+HgTile(forkTiles[0]));
				}
				
				local tileList = AITileList();
				for(local j=0; j<10; j++) {
					if(HogeAI.IsBuildable(s)) {
						tileList.AddItem(s,s);
					}
					s = s + d;
				}
//					tiles.reverse();
				local stationD = (forkTiles[1] - forkTiles[0]) / AIMap.DistanceManhattan(forkTiles[1],forkTiles[0]);
				local x = stationFactory.CreateOnTiles(tileList, HgStation.GetStationDirectionFromTileIndex(-stationD));
				
				foreach(station in x) {
					if(!station.IsBuildablePreCheck()) continue;
					station.score = station.GetBuildableScore() + (station.IsProducingCargoWithoutStationGroup(cargo) ? 5 : 0) + freeSideScore - distance / 10;
					//HgLog.Info("station.score:"+station.score+" "+ HgTile(forkTiles[2])
					//	+" "+station.GetPlatformRectangle()+" "+HgTile.GetTilesString(forkTiles));
					stationScore.AddItem(stations.len(), station.score);
					stations.push(station);
				}
			}
		}
		//stations = stationFactory.CreateInRectangle(rectangle);
		HgLog.Info("GetBuildableStationByPath stations:"+stations.len());
		foreach(stationIndex,score in stationScore) {
			local station = stations[stationIndex];
			if(station.Build(true, true)) {
				station.levelTiles = true;
				station.cargo = cargo;
				station.isSourceStation = true;
				local industries = station.SearchIndustries(cargo, true);
				if(industries.len() >= 1) {
					station.place = HgIndustry(industries[0],true);
				}
				return station;
			}
		}

		return null;
	}

	function GetCenterTileOfPlaces(places) {
		local srcX=0, srcY=0;
		foreach(place in places) {
			local p = place.GetLocation();
			srcX += AIMap.GetTileX(p);
			srcY += AIMap.GetTileY(p);
		}
		srcX /= places.len();
		srcY /= places.len();
		return AIMap.GetTileIndex(srcX,srcY);
	}

	function CheckMountain() {
		local w = AIMap.GetMapSizeX() * AIMap.GetMapSizeY();
		local maxHeight = 0;
		for(local i=0; i<100; i++) {
			local tile = AIBase.RandRange(w);
			maxHeight = max(maxHeight, AITile.GetMaxHeight(tile));
		}
		this.mountain = maxHeight >= 30;
		HgLog.Info("mountain:"+this.mountain);
	}

	function CheckTownStatue() {
		local execMode = AIExecMode();
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > GetInflatedMoney(400000)) {
			foreach(route in TrainRoute.instances) {
				local station = AIStation.GetStationID(route.srcHgStation.platformTile);		
				local town = AIStation.GetNearestTown (station)
				if(!AITown.HasStatue (town)) {
					AITown.PerformTownAction(town,AITown.TOWN_ACTION_BUILD_STATUE );
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= GetInflatedMoney(400000)) {
						break;
					}
				}
			}
		}
		if(AIBase.RandRange(100) < 25 && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > GetInflatedMoney(1200000)) {
			local routes = [];
			routes.extend(RoadRoute.instances);
			routes.extend(WaterRoute.instances);
			routes.extend(AirRoute.instances);
			foreach(route in routes) {
				local station = AIStation.GetStationID(route.srcHgStation.platformTile);		
				local town = AIStation.GetNearestTown(station)
				if(!AITown.HasStatue (town)) {
					if(!route.NeedsAdditionalProducing()) {
						continue;
					}
					AITown.PerformTownAction(town,AITown.TOWN_ACTION_BUILD_STATUE );
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= GetInflatedMoney(1200000)) {
						break;
					}
				}
			}
		}
	}

	function CheckTrainRoute() {
		local times = [];
		foreach(route in TrainRoute.instances) {
			route.CheckClose();
		}
		times.push(AIDate.GetCurrentDate()); //0
		foreach(route in TrainRoute.instances) {
			route.CheckTrains();
		}
		times.push(AIDate.GetCurrentDate());
		foreach(route in TrainRoute.instances) {
			route.CheckCloneTrain();
		}
		times.push(AIDate.GetCurrentDate()); //1
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > GetInflatedMoney(1000000)) {
			foreach(route in TrainRoute.instances) {
				route.CheckRailUpdate();
			}
		}
		times.push(AIDate.GetCurrentDate()); //2

		local s = "";
		local pre = null;
		foreach(time in times) {
			if(pre!=null) {
				s += (time - pre) + " ";
			}
			pre = time;
		}
		HgLog.Info("CheckTrainRoute "+ s);
		PerformanceCounter.Print();
	}
	 
	function CheckBus() {
		TownBus.canUseCargo.clear();
		foreach(townBus in TownBus.instances) {
			townBus.CheckInterval();
		}
	 }
	 	
	function CheckRoadRoute() {
		CommonRoute.CheckReduce(RoadRoute);
		foreach(route in RoadRoute.instances) {
			route.CheckBuildVehicle();
		}
		foreach(route in RoadRoute.instances) {
			route.CheckRenewal();
		}
		if(AIBase.RandRange(100) < 10) {
			RoadRoute.CheckPendingDemolishLines();
		}
	}

	function CheckWaterRoute() {
		CommonRoute.CheckReduce(WaterRoute);
		foreach(route in WaterRoute.instances) {
			route.CheckBuildVehicle();
		}
		foreach(route in WaterRoute.instances) {
			route.CheckRenewal();
		}
	}
	
	function CheckAirRoute() {
		CommonRoute.CheckReduce(AirRoute);
		foreach(route in AirRoute.instances) {
			route.CheckBuildVehicle();
		}
		foreach(route in AirRoute.instances) {
			route.CheckRenewal();
		}
	}

	function DoPendingConstructions() {
		local t = clone pendingConstructions;
		foreach(index, info in t) {
			if(info.time < AIDate.GetCurrentDate()) {
				HgLog.Info("DoPending "+info.construction);
				Construction.LoadStatics(info.construction);
				pendingConstructions.rawdelete(index);
			}
		}
	}
	
	function PostPending(after, construction) {
		pendingConstructions.rawset(AIBase.Rand(), {time = AIDate.GetCurrentDate() + after, construction = construction.saveData});
	}

	function BuildDestRoute(place, cargo) {
		local startDate = AIDate.GetCurrentDate();
		place = place.GetProducing();
		if(!PlaceDictionary.Get().IsUsedAsSourceCargo(place, cargo)) {
			HgLog.Info("BuildDestRoute "+place.GetName()+" "+AICargo.GetName(cargo));
			local found = false;
			foreach(dest in CreateRouteCandidates(cargo, place, {searchProducing=false})) {
				found = true;
				local routeClass = Route.Class(dest.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				local routeBuilder = routeClass.GetBuilderClass()(dest.place, place, cargo);
				if(routeBuilder.ExistsSameRoute()) {
					continue;
				}
				HgLog.Info("Try "+routeBuilder+"(BuildDestRoute)");
				if(routeBuilder.Build() != null) {
					return;
				}
				if(startDate + 100 < AIDate.GetCurrentDate()) {
					HgLog.Warning("Timeup(BuildDestRoute:"+place.GetName()+" "+AICargo.GetName(cargo)+")");
					break;
				}
			}
			if(!found) {
				HgLog.Warning("Not found route(BuildDestRoute:"+place.GetName()+" "+AICargo.GetName(cargo)+")");
			}
		} else {
			HgLog.Info("skip BuildDestRoute(Already used) "+place.GetName()+" "+AICargo.GetName(cargo));
		}
	}
	
	
	function GetAirportExchangeCandidates() {
		if(AirRoute.IsTooManyVehiclesForNewRoute(AirRoute)) {
			return [];
		}
		HgLog.Info("GetAirportExchangeCandidates {");
		local result = [];
		foreach(cargo in HogeAI.Get().GetPaxMailCargos()) {
			local routes = [];
			local current = AIDate.GetCurrentDate();
			foreach(route in AirRoute.instances) {
				if(!route.IsRemoved() && route.IsBiDirectional() && route.cargo == cargo && route.startDate + 365 < current) {
					routes.push(route);
				}
			}
			if(routes.len() <= 1) {
				continue;
			}
			local done = {};
			for(local i=0;i<min(1000,routes.len()*routes.len()); i++) {
				local i1 = AIBase.RandRange(routes.len());
				local i2 = AIBase.RandRange(routes.len());
				if(i1 == i2) continue;
				local key = min(i1,i2)+"-"+max(i1,i2);
				if(done.rawin(key)) continue;
				done.rawset(key,true);
				local r1 = routes[i1];
				local r2 = routes[i2];
				local s1 = r1.srcHgStation;
				local d1 = r1.destHgStation;
				local s2 = r2.srcHgStation;
				local d2 = r2.destHgStation;
			
				local currentValue = EstimateAir(s1,d1,cargo) + EstimateAir(s2,d2,cargo);
				if(currentValue < 0) {
					continue;
				}
				foreach(ss in [[s1,s2,d1,d2],[s1,d2,s2,d1]]) {
					local newValue = EstimateAir(ss[0],ss[1],cargo) + EstimateAir(ss[2],ss[3],cargo);
					if(newValue > 0 && newValue > currentValue * 1.1) {
						local value = newValue - currentValue;
						local estimate = {
							typeName = "exchangeAirs"
							vehicleType = AIVehicle.VT_AIR
							cargo = cargo
							estimate = { value = value }
							score = value
							route1 = r1.id
							route2 = r2.id
							stations = [ss[0].id,ss[1].id,ss[2].id,ss[3].id]
							isBiDirectional = true
							explain = value + "(org:" +currentValue +") exchangeAirs "+ss[0]+"<=>"+ss[1]+" "+ss[2]+"<=>"+ss[3]
						};
						result.push(estimate);
					}
				}
			}
		}
		HgLog.Info("}");
		return result;
	}
	
	function EstimateAir(src,dest,cargo) {
		local distance = AIMap.DistanceManhattan(dest.GetLocation(),src.GetLocation());
		local production = min(dest.stationGroup.GetExpectedProduction(cargo, AIVehicle.VT_AIR, true)
			,src.stationGroup.GetExpectedProduction(cargo, AIVehicle.VT_AIR, true));
		local infra = min(src.GetAirportType(), dest.GetAirportType());
		local estimate = Route.Estimate(AIVehicle.VT_AIR, cargo, distance, production, true, [infra]);
		if(estimate != null) {
			estimate = clone estimate;
			estimate.EstimateAdditional( dest.stationGroup, src.stationGroup, [infra] );
			return estimate.routeIncome; // 空港当りの収入ベース
		} else {
			//HgLog.Warning("EstimateAir failed:"+src+" "+dest+" ["+AICargo.GetName(cargo)+"] production:"+production);
			return -1000000;
		}
	}
	

	static function DoInterval(force = false) {
		HogeAI.Get()._DoInterval(force);
	}

	function _DoInterval(force = false) {
		if(supressInterval) {
			return;
		}
		if(force) {
			while(lastIntervalDate != null && AIDate.GetCurrentDate() < lastIntervalDate) {
				AIController.Sleep(10);
			}
		} else if(lastIntervalDate != null && AIDate.GetCurrentDate() < lastIntervalDate) {
			return;
		}
		
		local times = [];
		
		/*
		foreach(station,_ in AIStationList(AIStation.STATION_TRAIN)) {
			foreach(cargo,_ in AICargoList()) {
				local v = AIStation.GetCargoPlanned(station,cargo);
				if(v != 0) {
					HgLog.Info("GetCargoPlanned:"+v+" Cargo["+AICargo.GetName(cargo)+"] Station["+AIStation.GetName(station)+"]");
				}
			}
		}*/
		
		HgLog.Info("DoInterval {");
		
		supressInterval = true;
		UpdateSettings();
		
		local aiExecMode = AIExecMode();
		AICompany.SetMinimumLoanAmount(AICompany.GetLoanAmount() - AICompany.GetBankBalance(AICompany.COMPANY_SELF) + 10000);
		
		local currentRailType = AIRail.GetCurrentRailType();
		local currentRoadType = AIRoad.GetCurrentRoadType();
		
		lastIntervalDate = AIDate.GetCurrentDate();

		PlaceProduction.Get().Check();
		
		local execMode = AIExecMode();
		CheckEvent();
		times.push(AIDate.GetCurrentDate()); //0
		
		CommonRoute.CheckOldVehicles();
		times.push(AIDate.GetCurrentDate()); //1

		CheckTownStatue();
		times.push(AIDate.GetCurrentDate()); //2

		CheckTrainRoute();
		times.push(AIDate.GetCurrentDate()); //3

		CheckRoadRoute();
		times.push(AIDate.GetCurrentDate()); //4

		CheckBus();
		times.push(AIDate.GetCurrentDate()); //5
		
		CheckWaterRoute();
		times.push(AIDate.GetCurrentDate()); //6
		
		CheckAirRoute();
		times.push(AIDate.GetCurrentDate()); //7
		
		local s = "";
		local pre = lastIntervalDate;
		foreach(time in times) {
			s += (time - pre) + " ";
			pre = time;
		}
		local total = pre - lastIntervalDate;
		if(total >= 4) {
			HgLog.Warning("DoInterval "+ s + " total:"+(pre - lastIntervalDate));
		} else {
			//HgLog.Info("DoInterval "+ s + " total:"+(pre - lastIntervalDate));
		}
		PerformanceCounter.Print();
		if(total > 7 && Route.ExistsAvailableVehicleTypes()) {
			intervalSpan = min(30,total);
		} else {
			intervalSpan = 7;
		}
		
		
		local span = max(1,intervalSpan / GetDayLengthFactor());
		lastIntervalDate = AIDate.GetCurrentDate() + span;
		
		DoPendingConstructions();
		
		AIRail.SetCurrentRailType(currentRailType);
		AIRoad.SetCurrentRoadType(currentRoadType);
		supressInterval = false;
		HgLog.Info("}");
	}

	function OnPathFindingInterval() {
		DoInterval();
		return true;
	}
	
	function CheckEvent() {
		while(AIEventController.IsEventWaiting()) {
			local event = AIEventController.GetNextEvent();
			switch(event.GetEventType()) {
				case AIEvent.ET_VEHICLE_WAITING_IN_DEPOT:
					break;
				case AIEvent.ET_INDUSTRY_CLOSE:
					event = AIEventIndustryClose.Convert(event);
					HgLog.Info("ET_INDUSTRY_CLOSE:"+AIIndustry.GetName(event.GetIndustryID())+" ID:"+event.GetIndustryID());
					HgIndustry.industryClosedDate.rawset(event.GetIndustryID(), AIDate.GetCurrentDate());
					local place = HgIndustry(event.GetIndustryID(),true);
					local routes = [];
					routes.extend( PlaceDictionary.Get().GetRoutesBySource(place) );
					routes.extend( PlaceDictionary.Get().GetRoutesByDest(place) );
					local usedStations = {};
					foreach(route in routes /*Route.GetAllRoutes()*/) {
						route.OnIndustoryClose(event.GetIndustryID(),usedStations);
					}
					foreach(station,_ in usedStations) {
						station.place = null;
						station.DoSave();
					}
					foreach(pathfinding,_ in pathfindings) {
						pathfinding.OnIndustoryClose(event.GetIndustryID());
					}
					Place.DeletePlaceChaceIndustry(event.GetIndustryID());
					break;
				case AIEvent.ET_INDUSTRY_OPEN:
					event = AIEventIndustryOpen.Convert(event);
					HgLog.Info("ET_INDUSTRY_OPEN:"+AIIndustry.GetName(event.GetIndustryID())+" ID:"+event.GetIndustryID());
					break;
				case AIEvent.ET_VEHICLE_CRASHED:
					OnVehicleCrashed(AIEventVehicleCrashed.Convert(event));
					break;
				case AIEvent.ET_VEHICLE_LOST:
					OnVehicleLost(AIEventVehicleLost.Convert(event));
					break;					
			}
		}
	}

	function OnVehicleLost(event) {
		local vehicle = event.GetVehicleID();
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("ET_VEHICLE_LOST: Invalid vehicle "+vehicle);
			return;
		}
		local vehicleType = AIVehicle.GetVehicleType(vehicle);
		local route = Route.GetRouteByVehicle(vehicle);
		HgLog.Warning("ET_VEHICLE_LOST:"+VehicleUtils.GetTypeName(vehicleType)+" "+ vehicle+" "+AIVehicle.GetName(vehicle)+" "+route);
		if(route != null) {
			route.OnVehicleLost(vehicle);
		} else {
			local execMode = AIExecMode();
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
				AIVehicle.SendVehicleToDepot(vehicle);
			}
		}
	}
	
	function OnVehicleCrashed(event) {
		local vehicle = event.GetVehicleID();
		local crashSite = event.GetCrashSite();
		local crashReason = event.GetCrashReason();
		local vehicleType = AIVehicle.GetVehicleType(vehicle);
		local group = AIVehicle.GetGroupID(vehicle);
		HgLog.Warning("ET_VEHICLE_CRASHED:"+vehicle+" "+AIVehicle.GetName(vehicle)+" vt:"+vehicleType+" group:"+AIGroup.GetName(group)
			+" crashSite:"+HgTile(crashSite)+" crashReason:"+crashReason);
	}
	 
	function Save() {
		if(loadData != null) {
			return loadData;
		}
	
		local remainOps = AIController.GetOpsTillSuspend();
	
		local table = {};	
		table.turn <- turn;
		table.indexPointer <- indexPointer;
		table.stockpiled <- stockpiled;
		table.estimateTable <- estimateTable;
		table.maybePurchasedLand <- maybePurchasedLand;
		table.landConnectedCache <- HgTile.landConnectedCache;
		table.cargoVtDistanceValues <- cargoVtDistanceValues;
		table.lastTransferCandidates <- lastTransferCandidates;
		table.lastScanRouteDates <- lastScanRouteDates;
		Place.SaveStatics(table);

		HgLog.Info("Place.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		HgStation.SaveStatics(table);

		HgLog.Info("HgStation.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		TrainInfoDictionary.SaveStatics(table);

		HgLog.Info("TrainInfoDictionary.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		TrainRoute.SaveStatics(table);

		HgLog.Info("TrainRoute.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		CommonRoute.SaveStatics(table);
		RoadRoute.SaveStatics(table);		

		HgLog.Info("RoadRoute.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		WaterRoute.SaveStatics(table);
		
		HgLog.Info("WaterRoute.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		AirRoute.SaveStatics(table);

		HgLog.Info("AirRoute.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));
		remainOps = AIController.GetOpsTillSuspend();

		TownBus.SaveStatics(table);

		HgLog.Info("TownBus.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));

		BuildUtils.Get().Save(table);

		table.routeCandidates <- routeCandidates.Save();
		table.constractions <- constructions;
		table.pendingConstructions <- pendingConstructions;

/*		remainOps = AIController.GetOpsTillSuspend();

		Airport.SaveStatics(table);

		HgLog.Info("Airport.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));*/
		
		
		//HgLog.Info("nestlevel:"+CheckNest(table));
		
		return table;
	}
	
	function CheckNest(data,level=0) {
		local result = level;
		local typeName = typeof data;
		if(typeName == "table") {
			foreach(k,v in data) {
				result = max(result,CheckNest(k,level+1));
				result = max(result,CheckNest(v,level+1));
			}
		} else if(typeName == "array") {
			foreach(v in data) {
				result = max(result,CheckNest(v,level+1));
			}
		}
		return result;
	}

	function Load(version, data) {
		loadData = data;
	}
	
	function DoLoad() {
		if(loadData == null) {
			return;
		}
		//HgLog.Info("nestlevel:"+CheckNest(loadData));
		supressInterval = true;
		UpdateSettings();
		turn = loadData.turn;
		indexPointer = loadData.indexPointer;
		stockpiled = loadData.stockpiled;
		//estimateTable = loadData.estimateTable; delegateが入らない
		if(loadData.rawin("maybePurchasedLand")) {
			maybePurchasedLand = loadData.maybePurchasedLand;
		}
		if(loadData.rawin("landConnectedCache")) {
			HgTable.Extend( HgTile.landConnectedCache, loadData.landConnectedCache );
		}
		cargoVtDistanceValues = loadData.cargoVtDistanceValues;
		if(loadData.rawin("lastTransferCandidates")) {
			lastTransferCandidates = loadData.lastTransferCandidates;
		}
		lastScanRouteDates = loadData.lastScanRouteDates;
		Place.LoadStatics(loadData);
		HgStation.LoadStatics(loadData);
		TrainInfoDictionary.LoadStatics(loadData);
		TrainRoute.LoadStatics(loadData);		
		CommonRoute.LoadStatics(loadData);
		RoadRoute.LoadStatics(loadData);
		WaterRoute.LoadStatics(loadData);
		AirRoute.LoadStatics(loadData);
		TownBus.LoadStatics(loadData);
		BuildUtils.Get().Load(loadData);
		
		//routeCandidates.Load(loadData.routeCandidates);
		
		HgLog.Info("constructions load size:"+loadData.constractions.len());
		while(loadData.constractions.len() >= 1) {
			Construction.LoadStatics(loadData.constractions.top());
			loadData.constractions.pop();
		}
		if("pendingConstructions" in loadData) {
			pendingConstructions = loadData.pendingConstructions;
		}
		
		loadData = null;
		supressInterval = false;
		HgLog.Info(" Loaded");
	}

	function SetCompanyName() {
		AICompany.SetPresidentName("R. Ishibashi");
		if(AICompany.GetName( AICompany.COMPANY_SELF ).find("AAAHogEx") != null) {
			return;
		}
		local i = 0;
	    if(!AICompany.SetName("AAAHogEx")) {
			i = 2;
			while(!AICompany.SetName("AAAHogEx #" + i)) {
				i = i + 1;
				if(i > 255) break;
			}
		}
	}
	
	function WaitForMoney(needMoney, maxDays = 0,reason = "") {
		return HogeAI.WaitForPrice(HogeAI.GetInflatedMoney(needMoney),HogeAI.GetInflatedMoney(1000),maxDays,reason);
	}
	
	function GetInflatedMoney(money) {
		return (money * HogeAI.GetInflationRate()).tointeger();
	}
	
	function GetInflationRate() {
		return AICompany.GetMaxLoanAmount().tofloat() / HogeAI.Get().GetMaxLoan().tofloat();
	}
	
	function WaitForPrice(needMoney, buffer = 1000, maxDays = 0, reason = "") {
		local self = HogeAI.Get();

		if(self.waitForPriceStartDate != null) {
			HgLog.Error("WaitForPrice called recursively:"+needMoney+" "+reason); // 呼ばれないはず
			AIController.Sleep(10);
			return false;
		}

		local oldSupressInterval = self.supressInterval;
		self.supressInterval = true;

		local execMode = AIExecMode();
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF)-needMoney > AICompany.GetLoanAmount() + buffer) {
			AICompany.SetMinimumLoanAmount(0);
		}
		local first = true;
		self.waitForPriceStartDate = AIDate.GetCurrentDate();
		while(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < needMoney + buffer) {
			if(first) {
				first = false;
			} else {
				if(maxDays > 0 && AIDate.GetCurrentDate() > self.waitForPriceStartDate + maxDays) {
					HgLog.Info("wait for money reached max days:"+maxDays+" "+reason);
					self.waitForPriceStartDate = null;
					self.supressInterval = oldSupressInterval;
					return false;
				}
			
				HgLog.Info("wait for money:"+needMoney+" "+reason);
				local emergency = HogeAI.GetUsableMoney() < 0;
				foreach(route in Route.GetAllRoutes()) {
					if(route.isBuilding) continue; // first buildの最中に呼ばれて、first vehicleがsellされる事がある
					if(route instanceof CommonRoute) {
						route.SellVehiclesStoppedInDepots();
						route.CheckNotProfitableOrStopVehicle(emergency);
					}
				}
				CommonRoute.CheckReduce(RoadRoute,emergency);
				CommonRoute.CheckReduce(AirRoute,emergency);
				self.DoPendings(20);
			}
			local minimamLoan = min(AICompany.GetMaxLoanAmount(), 
					AICompany.GetLoanAmount() + needMoney - AICompany.GetBankBalance(AICompany.COMPANY_SELF) + buffer * 2);
			//HgLog.Info("minimamLoan:"+minimamLoan);
			AICompany.SetMinimumLoanAmount(minimamLoan);
		}
		self.waitForPriceStartDate = null;
		self.supressInterval = oldSupressInterval;
		return true;
	}
	
	function WaitDays(days, strict = false) {
		days /= GetDayLengthFactor();
		days = max(days,1);
		HgLog.Info("WaitDays:"+days);
		local d = AIDate.GetCurrentDate() + days;
		while(AIDate.GetCurrentDate() < d) {
			if(strict) {
				AIController.Sleep(1);
			} else {
				DoPendings();
			}
			DoInterval();
		}
	}
	
	function DoPendings(sleepTime = 1) {
		if(Coasts.params.alotofcoast) {
			AIController.Sleep(sleepTime);
			return;
		}
		while(pendingCoastTiles.len() >= 1) {
			local coastTile = pendingCoastTiles.pop();
			if(!Coasts.tileCoastId.rawin(coastTile)) {
				Coasts.GetCoasts(coastTile);
				AIController.Sleep(1);
				return;
			}
		}
		local w = AIMap.GetMapSize();
		for(local i=0; i<100000; i++) {
			local tile = AIBase.RandRange(w);
			if(AITile.IsCoastTile(tile) && Coasts.IsNeedSearch(tile)) {
				Coasts.GetCoasts(tile);
				AIController.Sleep(1);
				return;
			}
		}
		AIController.Sleep(sleepTime);
	}
	
	function GetUsableMoney() {
		return min(1000000000,AICompany.GetBankBalance(AICompany.COMPANY_SELF)) + (AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount());
	}

	function IsTooExpensive(cost) {
		return HogeAI.GetQuarterlyIncome(4) < cost && HogeAI.GetUsableMoney() < cost;
	}
	
	function HasIncome(money) {
		return HogeAI.GetQuarterlyIncome() >= HogeAI.GetInflatedMoney(money);
	}
	
	function GetQuarterlyIncome(n=1) {
		local quarterlyIncome = 0;
		local quarterlyExpnse = 0;
		for(local i=AICompany.CURRENT_QUARTER+1; i<AICompany.CURRENT_QUARTER+1+n && i<AICompany.EARLIEST_QUARTER ; i++) {
			quarterlyIncome += AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, i);
			quarterlyExpnse += AICompany.GetQuarterlyExpenses (AICompany.COMPANY_SELF, i);
		}
		return quarterlyIncome + quarterlyExpnse;
	}
	
	function IsRich() {
		if(isRich==null) {
			isRich = _IsRich();
		}
		return isRich;
	}

	function _IsRich() {
		local usableMoney = HogeAI.GetUsableMoney();
		local loanAmount = AICompany.GetLoanAmount();
		//HgLog.Info("usableMoney:"+usableMoney+" loanAmount:"+loanAmount);
		if(usableMoney > HogeAI.GetInflatedMoney(10000000)) return true;
		return ((usableMoney > HogeAI.GetInflatedMoney(500000) && HasIncome(100000))
			|| usableMoney > HogeAI.GetInflatedMoney(2000000)) 
				&& (loanAmount == 0 || prevLoadAmount > loanAmount);
	}
	
	function IsPoor() {
		local usableMoney = HogeAI.GetUsableMoney();
		return usableMoney < HogeAI.GetInflatedMoney(100000) && !HasIncome(25000);
	}

	function IsAvoidRemovingWater() {
		return GetSetting("Avoid removing water") == 1;	
	}
	
	function IsDisableTrams() {
		return GetSetting("disable_veh_tram") == 1;	
	}
	
	function IsDisableRoad() {
		return GetSetting("disable_veh_roadveh") == 1;	
	}
	
	function CanRemoveWater() {
		return HogeAI.GetUsableMoney() > GetInflatedMoney(2000000) && IsAvoidRemovingWater() == false;
	}

	function IsForceToHandleFright() {
		return GetSetting("IsForceToHandleFright") == 1;
	}
	
	function IsAvoidSecondaryIndustryStealing() {
		return GetSetting("IsAvoidSecondaryIndustryStealing") == 1;
	}
	
	function IsAvoidExtendCoverageAreaInTowns() {
		return GetSetting("IsAvoidExtendCoverageAreaInTowns") == 1;
	}
	
	function IsPreferReusingExistingRoads() {
		return GetSetting("IsPreferReusingExistingRoads") == 1;
	}
	
	function CanExtendCoverageAreaInTowns() {
		return !IsAvoidExtendCoverageAreaInTowns() && IsDistantJoinStations();
	}
	
	function IsPaxMailOnly() {
		return GetSetting("usable_cargos") == 1;
	}
	
	function IsFreightOnly() {
		return GetSetting("usable_cargos") == 2;
	}
	
	function IsManyTypesOfFreightAsPossible() {
		return GetSetting("many_types_of_freight_as_possible") == 1;
	}
	
	function IsDisabledPrefixedStatoinName() {
		return GetSetting("disable_prefixed_station_name") == 1;
	}
	
	function IsDebug() {
		return GetSetting("IsDebug") == 1;
	}
	
	function IsEnableVehicleBreakdowns() {
		return AIGameSettings.GetValue("difficulty.vehicle_breakdowns") >= 1;
	}
	
	function GetVehicleBreakdownDifficulty() {
		return AIGameSettings.GetValue("difficulty.vehicle_breakdowns");
	}
	

	function IsDistantJoinStations() {
		return isDistantJoinStations;
	}
	
	function IsInfrastructureMaintenance() {
		return isInfrastructureMaintenance;
	}
	
	function IsInflation() {
		return AIGameSettings.GetValue("economy.inflation") == 1;	
	}

	function GetFreightTrains() {
		return freightTrains;
	}
	
	function GetTrainSlopeSteepness() {
		return trainSlopeSteepness;
	}

	function GetRoadvehSlopeSteepness() {
		return roadvehSlopeSteepness;
	}
	
	function GetMaxLoan() {
		return maxLoan;
	}

	function IsTownCargogenModeQuadratic() {
		return AIGameSettings.GetValue("economy.town_cargogen_mode") == 1;
	}
	
	function GetDayLengthFactor() {
		return dayLengthFactor;
	}

	function UpdateSettings() {		
		maxStationSpread = AIGameSettings.GetValue("station.station_spread");
		maxStationSpread = maxStationSpread == -1 ? 12 : maxStationSpread;
		maxTrains = AIGameSettings.GetValue("vehicle.max_trains");
		maxRoadVehicle = AIGameSettings.GetValue("vehicle.max_roadveh");
		maxShips = AIGameSettings.GetValue("vehicle.max_ships");
		maxAircraft = AIGameSettings.GetValue("vehicle.max_aircraft");
		isUseAirportNoise = AIGameSettings.GetValue("economy.station_noise_level")==1 ? true : false;
		if(AIGameSettings.GetValue("ai.ai_disable_veh_train")==1 || GetSetting("disable_veh_train")==1) {
			maxTrains = 0;
		}
		if(AIGameSettings.GetValue("ai.ai_disable_veh_roadveh")==1 || (HogeAI.Get().IsDisableRoad() && HogeAI.Get().IsDisableTrams())) {
			maxRoadVehicle = 0;
		}
		if(AIGameSettings.GetValue("ai.ai_disable_veh_ship")==1 || GetSetting("disable_veh_ship")==1) {
			maxShips = 0;
		}
		if(AIGameSettings.GetValue("ai.ai_disable_veh_aircraft")==1 || GetSetting("disable_veh_aircraft")==1) {
			maxAircraft = 0;
		}
		isDistantJoinStations = AIGameSettings.GetValue("station.distant_join_stations") == 1;
		isInfrastructureMaintenance = AIGameSettings.GetValue("economy.infrastructure_maintenance") == 1;
		freightTrains = AIGameSettings.GetValue("vehicle.freight_trains");
		trainSlopeSteepness = AIGameSettings.GetValue("vehicle.train_slope_steepness");
		roadvehSlopeSteepness = AIGameSettings.GetValue("vehicle.roadveh_slope_steepness");
		maxLoan = AIGameSettings.GetValue("difficulty.max_loan");
		canUsePlaceOnWater = CanRemoveWater() || !WaterRoute.IsTooManyVehiclesForNewRoute(WaterRoute);
		waterRemovable = clearWaterCost < max(GetQuarterlyIncome() / 10, GetUsableMoney() / 100);
		isRich = null;//true;
		local currentYear = AIDate.GetYear( AIDate.GetCurrentDate() );
		futureIncomeRate = 100;
		if(IsInflation() && currentYear < 2090) {
			futureIncomeRate = max(80, 100 - (2090 - currentYear));
		}

		hogeIndex = 0;
		hogeNum = 0;
		//HgLog.Info("firstCompanyId:"+AICompany.COMPANY_FIRST+" lastCompanyId:"+AICompany.COMPANY_LAST);
		
		for(local id = AICompany.COMPANY_FIRST; id<AICompany.COMPANY_LAST; id++) {
			if(AICompany.ResolveCompanyID(id) != AICompany.COMPANY_INVALID) {
				local name = AICompany.GetName(id);
				if(name != null && name.find("AAAHogEx") != null) {
					if(AICompany.IsMine(id)) {
						hogeIndex = hogeNum;
					}
					hogeNum ++;
				}
			}
		}
		
		//hogeNum = 1;
		/*
		HgLog.Info("InflationRate:"+HogeAI.GetInflationRate());
		HgLog.Info("hogeIndex:"+hogeIndex+" hogeNum:"+hogeNum);*/
	}

	function CheckBuildedPaths() {
		HgLog.Info("CheckBuildedPaths {");
		local s = AIMap.GetMapSizeX() * AIMap.GetMapSizeY();
	
		for(local index=0; index<s; index++) {
			if(AIRail.IsRailTile(index) && AICompany.IsMine(AITile.GetOwner(index))) {
				if(!BuildedPath.Contains(index)) {
					HgLog.Warning("Unmanaged rail tile found:"+HgTile(index));
				}
			}
		}
		HgLog.Info("}");
	}
}

class RouteCandidates {
	idCounter = null;
	saveData = null;
	sortedList = null;
	minValue = 0;
	
	constructor() {
		idCounter = IdCounter();
		Clear();
	}
	
	function Clear() {
		saveData = {minValue = 0, plans = {}};
		sortedList = SortedList( function(plan) {
			return plan.estimate.value;
		});
	}
	
	function Save() {
		return saveData;
	}
	
	function Load(data) {
		saveData = data;
		minValue = data.minValue;
		HgLog.Info("RouteCandates load size:"+data.plans.len());
		foreach(id,t in data.plans) {
			//HgLog.Info("RouteCandates.Load "+id);
			local plan = {
				id = id
				src = Place.Load(t.src)
				dest = Place.Load(t.dest)
				vehicleType = t.vehicleType
				cargo = t.cargo
				estimate = t.estimate
				score = t.score
			};
			if("canChangeDest" in t) {
				plan.canChangeDest <- t.canChangeDest;
			}
			if("route" in t) {
				plan.route <- Route.allRoutes[t.route];
			}
			if("sourceRoute" in t) {
				plan.sourceRoute <- Route.allRoutes[t.sourceRoute];
			}
			idCounter.Skip(id);
			sortedList.Push(plan);
		}
	}
	
	function Push(t) {
		t.id <- idCounter.Get()
		if(!("explain" in t)) {
			local routeClass = Route.Class(t.vehicleType);
			t.isBiDirectional <- (t.dest instanceof Place) ? t.dest.IsAcceptingAndProducing(t.cargo) && t.src.IsAcceptingAndProducing(t.cargo) : false;
			t.explain <- t.estimate.value + " "+t.dest+"<="+(t.isBiDirectional?">":"")+t.src+" "+t.estimate;
/*			t.explain <- t.estimate.value+" "+routeClass.GetLabel()+" "+t.dest+"<="+(t.isBiDirectional?">":"")+t.src+"["+AICargo.GetName(t.cargo)+"] dist:"
				+t.estimate.distance+" prod:"+t.estimate.production;*/
			if(t.vehicleType == AIVehicle.VT_AIR) {
				t.explain += " infraType:"+t.estimate.infrastractureType;
			}
		}
		local s;
		if(!("typeName" in t)) {
			// 保存用tableを作成する
			s = {
				src = t.src.Save()
				dest = t.dest.Save()
				vehicleType = t.vehicleType
				cargo = t.cargo
				estimate = t.estimate
				score = t.score
			};
			if("canChangeDest" in t) {
				s.canChangeDest <- t.canChangeDest;
			}
			if(("route" in t) && t.route != null) {
				s.route <- t.route.id;
			}
			if(("sourceRoute" in t) && t.sourceRoute != null) {
				s.sourceRoute <- t.sourceRoute.id;
			}
		} else {
			s = t;
		}
		saveData.plans.rawset(t.id, s);
		sortedList.Push(t);
	}

	function Extend(plans) {
		foreach(plan in plans) {
			Push(plan);
		}
	}
	
	function Count() {
		return sortedList.Count();
	}

	function Peek() {
		return sortedList.Peek();
	}
	
	function Pop() {
		local result = sortedList.Pop();
		saveData.rawdelete(result.id);
		return result;
	}
	
	function GetAll() {
		return sortedList.GetAll();
	}
	
	function CalculateMinValue() {
		minValue = 0;
		local count = sortedList.Count();
		local i = 0;
		foreach(e in sortedList.GetAll()) {
			i++;
			if(minValue==0 && i >= count / 2) {
				minValue = e.score * 8 / 10;
				break;
			}
		}
		saveData.minValue = minValue;
	}
}

