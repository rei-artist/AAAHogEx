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
	static version = 79;

	static container = Container();
	static notBuildableList = AIList();
	
	static distanceEstimateSamples = [];
	static distanceSampleIndex = [];
	static productionEstimateSamples = [10, 20, 30, 50, 80, 130, 210, 340, 550, 890, 1440, 2330, 3770];

	turn = null;
	indexPointer = null;
	pendings = null;
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
	constractions = null;
	maybePurchasedLand = null;
	pathFindLimit = null;
	loadData = null;
	lastIntervalDate = null;
	passengerCargo = null;
	mailCargo = null;
	paxMailCargos = null;
	supressInterval = null;
	supressInterrupt = null;
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
		pathFindLimit = 150;
		estimateTable = {};
		maybePurchasedLand = {};
		
		supressInterval = false;
		supressInterrupt = false;
		yeti = false;
		ecs = false;
		firs = false;
		isTimeoutToMeetSrcDemand = false;
		pendings = {};
		pathfindings = {};
		canUsePlaceOnWater = false;
		maxRoi = 0;
		cargoVtDistanceValues = {};
		pendingCoastTiles = [];
		intervalSpan = 7;
		lastTransferCandidates = {};
		waterRemovable = false;
		routeCandidates = RouteCandidates();
		constractions = [];
		lastScanRouteDates = {};

		DelayCommandExecuter();
	}
	
	function Start() {
		SetCompanyName();
		HgLog.Info("AAAHogEx Started! version:"+HogeAI.version+" name:"+AICompany.GetName(AICompany.COMPANY_SELF));
		HgLog.Info("openttd version:"+openttdVersion);
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
			local t1 = HgTile.XY(187,221+i);
			local t2 = HgTile.XY(188,221+i);
			tiles.push(t1);
			AIRoad.SetCurrentRoadType(roadType);
			AIRoad.BuildRoad(t1.tile,t2.tile);
			HgLog.Info("GetBuildCost("+AIRoad.GetName(roadType)+")="+AIRoad.GetBuildCost(roadType,  AIRoad.BT_ROAD));
			HgLog.Info("GetMaintenanceCostFactor("+AIRoad.GetName(roadType)+")="+AIRoad.GetMaintenanceCostFactor(roadType));

			i++;
		}
		foreach(roadType,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD )) {
			foreach(tile in tiles) {
				HgLog.Info("HasRoadType("+tile+","+AIRoad.GetName(roadType)+")="+AIRoad.HasRoadType(tile.tile, roadType));
			}
			foreach(tile in tiles) {
				local testMode = AITestMode();
				HgLog.Info("ConvertRoadType("+tile+","+AIRoad.GetName(roadType)+")="+AIRoad.ConvertRoadType(tile.tile,tile.tile,roadType)+" "+AIError.GetLastErrorString());
			}
			
			foreach(r,_ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD )) {
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

		DoLoad();
		
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
		
		UpdateSettings();
		HgLog.Info("maxStationSpread:"+maxStationSpread);
		HgLog.Info("maxTrains:"+maxTrains);
		HgLog.Info("maxRoadVehicle:"+maxRoadVehicle);
		HgLog.Info("maxShips:"+maxShips);
		HgLog.Info("maxAircraft:"+maxAircraft);
		HgLog.Info("isUseAirportNoise:"+isUseAirportNoise);
		HgLog.Info("maxAircraft:"+maxAircraft);
		
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
		
		local currentLoanAmount = AICompany.GetLoanAmount();

		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());
		

		indexPointer = 3; // ++
		while (true) {
			HgLog.Info("######## turn "+turn+" ########");
			prevLoadAmount = currentLoanAmount;
			currentLoanAmount = AICompany.GetLoanAmount();
			ResetEstimateTable();
			while(indexPointer < 4) {
				UpdateSettings();
				CalculateProfitModel();
				limitDate = AIDate.GetCurrentDate() + 600;
				Place.canBuildAirportCache.clear();
				
				DoInterval();
				DoInterrupt();
				DoStep();
				indexPointer ++;
			}
			indexPointer = 0;
			turn ++;
			WaitDays(1);
		}
	}
	
	function CalculateProfitModel() {
		if(!IsRich()/* || (maxRoi < 1000 && !HasIncome(250000))*/) {
			roiBase = true;
			buildingTimeBase = false;
			vehicleProfibitBase = false;
			HgLog.Info("### roiBase");
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
				HgLog.Info("### buildingTimeBase");
				return;
			}
		}
		roiBase = false;
		buildingTimeBase = false;
		vehicleProfibitBase = true;
		HgLog.Info("### vehicleProfibitBase");
		
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
				//SearchAndBuildTransferRoute();
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
			local candidate;
			local routeCandidatesGen = GetRouteCandidatesGen();
			local candidateNum = 1000; // 400 / (16*8) = cargo 4種類
			for(local i=0; (candidate=resume routeCandidatesGen) != null && i<candidateNum; i++) {
				routeCandidates.Push(candidate);
	/*			candidate.score += AIBase.RandRange(10); // ほかのHogexとの競合を防ぐ
				bests.push(candidate);*/
				if(startDate + 365 < AIDate.GetCurrentDate() && GetUsableMoney() > GetInflatedMoney(100000)) {
					HgLog.Warning("routeCandidatesGen reached 365 days");
					break;
				}
			}
			if(routeCandidates.Count()==0) {
				routeCandidates.Extend( GetAirportExchangeCandidates() );
			}
			routeCandidates.CalculateMinValue();
			routeCandidates.Extend( GetTransferCandidates() );
			routeCandidates.Extend( GetMeetPlaceCandidates() );
		}
		local minValue = routeCandidates.minValue;
		
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
		local searchDays = AIDate.GetCurrentDate() - startDate;
		HgLog.Info("searchDays:"+searchDays+" minValue:"+minValue);
		limitDate = AIDate.GetCurrentDate() + max((roiBase ? 356*2 : 365*2) / GetDayLengthFactor(), searchDays * (roiBase ? 2 : 2));
		local dirtyPlaces = {};
		local pendingPlans = [];
		local totalNeeds = 0;
		local endDate = AIDate.GetCurrentDate();
		local buildingStartDate = AIDate.GetCurrentDate();
		while(routeCandidates.Count() >= 1){
			local t = routeCandidates.Pop();
			if(t.vehicleType != AIVehicle.VT_AIR) { //airの場合迅速にやらないといけないので
				DoInterval(); 
			}
			local builder = CreateBuilder(t,pendingPlans,dirtyPlaces);
			if(builder == null) {
				continue;
			}
			HgLog.Info("Try "+t.explain);
			local newRoutes = builder.Build();
			if(newRoutes == null) {
				newRoutes = [];
			} else if(typeof newRoutes != "array") {
				newRoutes = [newRoutes];
			}
			routeCandidates.Extend(pendingPlans);
			pendingPlans.clear();
			if(newRoutes.len() >= 1) {
				foreach(newRoute in newRoutes) {
					if(newRoute.srcHgStation.place != null) {
						newRoute.srcHgStation.place.SetDirtyArround();
					}
					if(newRoute.IsTransfer() && t.rawin("route")) {
						t.route.NotifyAddTransfer();
					}
					if(newRoute.IsBiDirectional() || ecs) {
						local dest = newRoute.destHgStation.place != null ? newRoute.destHgStation.place : newRoute.destHgStation.stationGroup;
						dirtyPlaces.rawset(dest.GetGId()+":"+t.cargo, true);
					}
					local src = newRoute.srcHgStation.place != null ? newRoute.srcHgStation.place : newRoute.srcHgStation.stationGroup;
					dirtyPlaces.rawset(src.GetGId()+":"+t.cargo, true);
				}
				if(roiBase && routeCandidates.Count() >= 1) {
					if(IsRich() && AIDate.GetCurrentDate() - buildingStartDate > searchDays) { // roiBaseから変わったので再検索
						HgLog.Warning("IsRich == true");
						return;
					}
					local next = routeCandidates.Peek();
					if(!("typeName" in t) && t.vehicleType != AIVehicle.VT_AIR) {
						local usable = GetUsableMoney() + GetQuarterlyIncome() * t.estimate.days / 90;
						totalNeeds += t.estimate.price * (t.estimate.vehiclesPerRoute - 1); // TODO: これまでの建築にかかった時間分減らす
						local nextNeeds = next.estimate.buildingCost + next.estimate.price;
						local needs = totalNeeds + nextNeeds;
						HgLog.Info("price:"+t.estimate.price+" vehiclesPerRoute:"+t.estimate.vehiclesPerRoute+" totalNeeds:"+totalNeeds+" nextNeeds:"+nextNeeds+" usable:"+usable);
						endDate = max( endDate, AIDate.GetCurrentDate() + t.estimate.days );
						if(usable < needs) { // 次の建築をしながら、前のルートの乗り物を作れない
							HgLog.Info("usable:"+usable+" needs:"+needs);
							WaitDays(min(min(180,limitDate - AIDate.GetCurrentDate()),max(0,endDate - AIDate.GetCurrentDate())));
							totalNeeds = 0;
							for(local i=0; GetUsableMoney() < nextNeeds; i++) { // 次の建築ができない(最大6か月待つ)
								HgLog.Info("usable:"+usable+" nextNeeds:"+nextNeeds);
								WaitDays(10);
								if(i>=17 || limitDate < AIDate.GetCurrentDate()) {
									return;
								}
							}
						}
						if(next.estimate.value < 200 && IsInfrastructureMaintenance() && next.vehicleType == AIVehicle.VT_ROAD) { 
							WaitDays(365); // 収益性が悪すぎるのでしばらく様子を見て再検索
							return;
						}
					}
					if(roiBase && next.estimate.value < 200) {
						return;
					}
				}
			}
			if(limitDate < AIDate.GetCurrentDate()) {
				return;
			}
		}
	}
	
	function CreateBuilder(plan,pendingPlans,dirtyPlaces) {
		local typeName = ("typeName" in plan) ? plan.typeName : "route";
		if(typeName == "route") {
			return CreateRouteBuilder(plan,pendingPlans,dirtyPlaces);
			
		} else if(typeName == "exchangeAirs") {
			return CreateExchangeAirsBuilder(plan,dirtyPlaces);
		}
	}
	
	function CreateRouteBuilder(t,pendingPlans,dirtyPlaces) {
		local routeClass = Route.Class(t.vehicleType);
		local explain = t.explain;
		/*if(roiBase && t.estimate.value < 150) { 何もしなくなってしまうマップがある
			if(index==0) {
				WaitDays(365); // 最初から収益性が悪すぎるのでしばらく様子をて再検索
			}
			DoPostBuildRoute(rootBuilders);
			return;
		}*/
		if((t.isBiDirectional || ecs) && dirtyPlaces.rawin(t.dest.GetGId()+":"+t.cargo)) { // 同じplaceで競合するのを防ぐ(特にAIRとRAIL)
			HgLog.Info("dirtyPlaces dest "+explain);
			return null;
		}
		if(dirtyPlaces.rawin(t.src.GetGId()+":"+t.cargo)) {
			HgLog.Info("dirtyPlaces src "+explain);
			return null;
		}
		if(t.src instanceof Place && !t.src.CanUseNewRoute(t.cargo, t.vehicleType)) {
			HgLog.Info("Not CanUseNewRoute src "+explain);
			return null;
		}
		if(t.dest instanceof Place && t.dest.IsAcceptingAndProducing(t.cargo) && !t.dest.GetProducing().CanUseNewRoute(t.cargo, t.vehicleType)) {
			HgLog.Info("Not accept or Not CanUseNewRoute dest "+explain);
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
		if(t.rawin("route")) {
			if(!t.route.NeedsAdditionalProducingCargo( t.cargo, null, t.route.destHgStation.stationGroup==t.dest )) {
				//HgLog.Warning("NeedsAdditionalProducing false "+explain+" "+t.route);
				pendingPlans.push(t);
				return null;
			}
			if(t.estimate.destRouteCargoIncome > 0) {
				local finalDestStation = t.route.GetFinalDestStation( null, t.dest );
				if(finalDestStation.place != null && finalDestStation.place.GetDestRouteCargoIncome() == 0) {
					pendingPlans.push(t);
					return null;
				}
			}
			
			//HgLog.Info("NeedsAdditionalProducing true "+explain+" "+t.route);
		} else {
			if(t.estimate.destRouteCargoIncome > 0 && t.dest.GetDestRouteCargoIncome() == 0) {
				pendingPlans.push(t);
				return null;
			}
		}
		
		
		if(t.estimate.additionalRouteIncome >= 1) {
			if(firs) {
				local place = null;
				if(t.rawin("route")) {
					local finalDestStation = t.route.GetFinalDestStation( null, t.dest );
					place = finalDestStation.place;
				} else if(t.dest instanceof Place) {
					place = t.dest;
				}
				if(place != null) {
					if(place.GetAdditionalRouteIncome(t.cargo) == 0) {
						HgLog.Info("Already meet "+explain);
						return null;
					}
				}
			}
		}
		
		local routeBuilder = routeClass.GetBuilderClass()(t.dest, t.src, t.cargo, { 
			pendingToDoPostBuild = false //roiBase ? true : false
			destRoute = t.rawin("route") ? t.route : null
			noDoRoutePlans = true
			routePlans = routeCandidates
		});
		if(routeBuilder.ExistsSameRoute()) {
			HgLog.Info("ExistsSameRoute "+explain);
			return null;
		}
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
		
		foreach(route in ArrayUtils.Shuffle(TrainRoute.instances)) {
			if(route.IsRemoved() || route.IsTransfer() || route.IsUpdatingRail()) {
				continue;
			}
			local lastScanDate = lastScanRouteDates.rawin(route.id) ? lastScanRouteDates.rawget(route.id) : null;
			if(lastScanDate!=null && lastScanDate + 10 * 365 < AIDate.GetCurrentDate()) {
				 // やたらとreturn route作成失敗を繰り返すので10年に1度
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
			

			SearchAndBuildAdditionalSrc(route);
			SearchAndBuildAdditionalDestAsFarAsPossible( route );
			CheckBuildReturnRoute(route);
			DoInterval();
			
			if(limitDate < AIDate.GetCurrentDate()) {
				break;
			}
		}
	}
	
	function GetRouteCandidatesGen() {
		local considerSlope = !IsRich();
		local cargoPlaceInfo = {};
		foreach(i, src in GetMaxCargoPlaces()) {
			//src.production = Place.AdjustProduction(src.place, src.production);
			local count = 0;
			HgLog.Info("src.place:"+src.place.GetName()+" src.cargo:"+AICargo.GetName(src.cargo));
			if(!cargoPlaceInfo.rawin(src.cargo)) {
				local placeInfo = {
					searchProducing = false
				};
				cargoPlaceInfo.rawset(src.cargo, placeInfo);
			}
			foreach(dest in CreateRouteCandidates(src.cargo, src.place, cargoPlaceInfo[src.cargo], 0 , 16)) {
//					Place.GetAcceptingPlaceDistance(src.cargo, src.place.GetLocation()))) {
				
				local routeClass = Route.Class(dest.vehicleType);
				if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
					continue;
				}
				
				local route = {};
				route.cargo <- src.cargo;
				route.dest <- dest.place;
				route.src <- src.place;
				route.production <- dest.production;
				route.maxValue <- src.maxValue;
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
				
				/* TODO CreateRouteCandidatesでやる
				if (route.vehicleType == AIVehicle.VT_RAIL) {
					route.score = VehicleUtils.AdjustTrainScoreBySlope(
						route.score, dest.estimate.engine, route.dest.GetLocation(), route.src.GetLocation());
				
				}*/
				
				//HgLog.Info("score:"+route.score+" "+route.destPlace.GetName()+"<-"+route.place.GetName()+"["+route.distance+"]"+AICargo.GetName(route.cargo));
				yield route;
				count ++;
				if(count >= 25) { // 一か所のソースにつき最大
					break;
				}
			}
			DoInterval();
		}
		return null;
	}

	function GetMaxCargoPlaces() {
		local result = []
		
		local quarterlyIncome = AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		local quarterlyExpnse = AICompany.GetQuarterlyExpenses (AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		HgLog.Info("quarterlyIncome: " + quarterlyIncome + " Enpense:" + quarterlyExpnse);
		
		
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
		foreach(cargo ,_ in cargoList) {
			local vtDistanceValues = [];
			//HgLog.Info("step0 "+AICargo.GetName(cargo));
			DoInterval();
			local places = Place.GetNotUsedProducingPlaces( cargo, 300, indexes );
			if(places.len() == 0) {
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
				local vtPlaceList = AIList();
				vtPlaceList.AddList(placeList);
				vtPlaceList.Valuate(function(placeIndex):(places,cargo,vehicleType) {
					local place = places[placeIndex];
					return place.CanUseNewRoute(cargo, vehicleType) && !Place.IsNgPlace(place, cargo, vehicleType);
				});
				vtPlaceList.KeepValue(1);
				if(vehicleType == AIVehicle.VT_AIR) {
					vtPlaceList.Valuate(function(placeIndex):(places,cargo,minimumAiportType) {
						local place = places[placeIndex];
						return place.CanBuildAirport(minimumAiportType, cargo);
					});
					vtPlaceList.KeepValue(1);
				}
				/* 重い
				vtPlaceList.Valuate(function(placeIndex):(places,cargo,vehicleType) {
					local place = places[placeIndex];
					return place.GetFutureExpectedProduction(cargo,vehicleType);
				});
				vtPlaceList.RemoveValue(0);*/
				if(roiBase) stdProduction = 0;
				foreach(placeIndex,_ in vtPlaceList) {
					local place = places[placeIndex];
/*					if(!place.CanUseNewRoute(cargo, vehicleType)) {
						//HgLog.Warning("!CanUseNewRoute place:"+place.GetName()+" cargo:"+AICargo.GetName(cargo));
						continue;
					}
					if(Place.IsNgPlace(place, cargo, vehicleType)) {
						continue;
					}
					if(vehicleType == AIVehicle.VT_AIR && !place.CanBuildAirport(minimumAiportType, cargo)) {
						continue;
					}*/
					
					local production = place.GetFutureExpectedProduction( cargo, vehicleType );
					if(production == 0) {
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
					vtDistanceValues.push([routeClass.GetVehicleType(), distanceIndex, estimate.value]);
					
					maxRoi = max(estimate.roi,maxRoi);
					HgLog.Info("Estimate d:"+distance+" roi:"+estimate.roi+" income:"+estimate.routeIncome+" ("+estimate.incomePerOneTime+") "
						+ AIEngine.GetName(estimate.engine)+(estimate.rawin("numLoco")?"x"+estimate.numLoco:"") +"("+estimate.vehiclesPerRoute+") "
						+ "runningCost:"+AIEngine.GetRunningCost(estimate.engine)+" capacity:"+estimate.capacity);
					maxValue = max(maxValue, estimate.value);
				}
				
				foreach(r in cargoResult ) {
					r.maxValue <- maxValue;
					r.score <- roiBase ? maxValue * 1000 + r.production : maxValue / 100 * r.production;
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
		foreach(r in result) {
			HgLog.Info("cargo:"+AICargo.GetName(r.cargo) +" place:"+r.place.GetName()+" production:"+r.production+" score:"+r.score);
		}
		return result;
	}
	
	function CreateRouteCandidates(cargo, orgPlace, placeInfo, additionalProduction=0, maxResult=16, options={}) {
		if(Place.IsNgCandidatePlace(orgPlace,cargo)) {
			return [];
		}
		if(orgPlace.IsClosed()) {
			return [];
		}
		if(!(cargo in cargoVtDistanceValues)) {
			return [];
		}
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
		if(CargoUtils.IsPaxOrMail(cargo)) {
			maxCandidates *= 2; // valueが対向サイズに影響するので多めに見る
		}
		
		local candidates = [];
		local checkCount = 0;
		
		
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
			local routeClass = Route.Class(vt);
			if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, routeClass.GetVehicleType()) >= routeClass.GetMaxTotalVehicles()) {
				continue;
			}
			local places = distancePlaces.GetPlaces(distanceIndex);
			HgLog.Info(routeClass.GetLabel()+" distance:"+distanceEstimateSamples[distanceIndex]+" places:"+places.len() + " cur_candidates:"+candidates.len());
			foreach(place in places) {
				if(maxCandidates != 0 && candidates.len() >= maxCandidates) {
					break;
				}
				if(place.IsProducing() && !placeDictionary.CanUseAsSource(place,cargo)) {
					continue;
				}
				
				local t = {place = place};
				t.distance <- AIMap.DistanceManhattan(place.GetLocation(),orgTile);
				if(t.distance == 0) { // はじかないとSearchAndBuildToMeetSrcDemandMin経由で無限ループする事がある
					continue;
				}
				local isBidirectional = orgPlace.IsAcceptingAndProducing(cargo) && t.place.IsAcceptingAndProducing(cargo);
				if(vt == AIVehicle.VT_RAIL) {
					if(!HogeAI.Get().yeti &&  (orgPlaceAcceptingRaw || (t.place.IsAccepting() && t.place.IsRaw()))) {
						continue; // RAWを満たすのにRAILは使わない。(YETIをのぞく)
					}
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
					if(!WaterRoute.CanBuild(orgPlace,  t.place, cargo, isBidirectional)) { // 距離と収益性だけで候補を選ぶと、どことも接続できない事がある。
						continue;
					}
				}
				if(Place.IsNgPlace(orgPlace, cargo, vt) || Place.IsNgPlace(t.place, cargo, vt)) {
					continue;
				}
				if(t.place.IsProducing() && !placeDictionary.CanUseAsSource(t.place,cargo)) {
					continue;
				}
				
				checkCount ++;
				local srcPlace = orgPlace.IsProducing() ? orgPlace : t.place;
				local destPlace = orgPlace.IsProducing() ? t.place : orgPlace;
				local placeProduction;
				if(Place.IsNgPathFindPair(srcPlace, destPlace, vt)) {
					continue;
				}
				if(options.rawin("useLastMonthProduction")) {
					placeProduction = place.GetLastMonthProduction(cargo);
				} else {
					placeProduction = place.GetExpectedProduction(cargo, vt);
					//HgLog.Info("GetExpectedProduction:"+placeProduction+" "+AICargo.GetCargoLabel(cargo)+" "+p.place+" vt:"+vt);
				}
				local orgPlaceProduction;
				local orgPlaceCount;
				if(orgPlaceProductionTable.rawin(vt)) {	
					orgPlaceProduction = orgPlaceProductionTable[vt];
				} else {
					if(options.rawin("useLastMonthProduction")) {
						orgPlaceProduction = orgPlace.GetLastMonthProduction(cargo);
					} else {
						orgPlaceProduction = orgPlace.GetExpectedProduction(cargo, vt);
					}
					orgPlaceProductionTable[vt] <- orgPlaceProduction;
				}
				
				local production;
				if( vt == AIVehicle.VT_RAIL ) {
					if(isBidirectional && roiBase) { /*どうせ延ばすので対向のサイズはあまり関係ない*/
						local srcProduction;
						local destProduction;
						if(orgPlace.IsProducing()) {
							srcProduction = orgPlaceProduction;
							destProduction = placeProduction;
						} else {
							srcProduction = placeProduction;
							destProduction = orgPlaceProduction;
						}
						production = (srcProduction + (srcProduction < destProduction ? srcProduction : destProduction)) / 2;
					} else {
						production = orgPlace.IsProducing() ? orgPlaceProduction : placeProduction;
					}
				} else {
					if(isBidirectional) {
						production = min(orgPlaceProduction,placeProduction);
					} else {
						production = orgPlace.IsProducing() ? orgPlaceProduction : placeProduction;
					}
				}
				
				local infrastractureTypes = routeClass.GetSuitableInfrastractureTypes(orgPlace, t.place, cargo);
				local estimateProduction = production;
				/* 家畜と穀物だって運べるif(vt == AIVehicle.VT_RAIL && orgPlace instanceof TownCargo && t.place instanceof TownCargo) {
					estimateProduction *= 2; // 郵便と旅客を同時に運べる TODO: 本当の値はEstimateをマルチカーゴに対応させる必要がある
				}*/
				

				local estimate = Route.Estimate( vt, cargo, t.distance, estimateProduction, isBidirectional, infrastractureTypes );
				
				if(estimate != null) { 
					estimate = clone estimate;
					estimate.EstimateAdditional( destPlace, srcPlace, infrastractureTypes );
					if(vt != AIVehicle.VT_RAIL && isBidirectional && placeProduction < estimateProduction) {
						local onewayEstimate = Route.Estimate( vt, cargo, t.distance, estimateProduction - placeProduction, false, infrastractureTypes );
						estimate.EstimateOneWay( onewayEstimate ); // bidirectional時にソース側の方が生産量が多い時の追加分
					}
					
				}
				
				if(estimate != null && estimate.value > 0 /*&& estimate.buildingCost <= maxBuildingCost Estimate内ではじいている*/) {

				
					t.vehicleType <- vt;
					t.score <- estimate.value;
					t.estimate <- estimate;
					if(vt == AIVehicle.VT_AIR && cargo == HogeAI.GetPassengerCargo() && orgPlace instanceof TownCargo && t.place instanceof TownCargo) {
						t.score = t.score * 13 / 10; // 郵便がひっついてくる分
					}
					t.production <- production;
					/*
					if((vt == AIVehicle.VT_AIR || vt == AIVehicle.VT_WATER) && pathDistance != 0) {
						t.score = t.score * t.distance / pathDistance;
					}
					if(vt == AIVehicle.VT_WATER) {
						t.score -= (1.0 - t.score * WaterRoute.CheckWaterRate(max(1,t.distance / 16)) * 0.36).tointeger();
					}*/
					
					/*
					if (considerSlope && (vt == AIVehicle.VT_RAIL || vt == AIVehicle.VT_ROAD)) {
						t.score = t.score * 3 / (3 + max( AITile.GetMaxHeight(route.destPlace.GetLocation()) - AITile.GetMaxHeight(route.place.GetLocation()) , 0 ));
					}*/
				
					if(ecs && t.place.IsAccepting() && t.place.IsEcsHardNewRouteDest(cargo)) {
						t.score /= 2;
					}
				
					candidates.push(t);
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
			if(!Route.CanCreateRoute( candidate.vehicleType, orgPlace, candidate.place, cargo )) {
				continue;
			}
			if(Place.IsNgPathFindPair(orgPlace, candidate.place, candidate.vehicleType)) {
				continue;
			}
			if(candidate.vehicleType == AIVehicle.VT_RAIL) {
				if(!HgTile.IsLandConnectedForRail(orgTile, candidate.place.GetLocation())) {
					continue;
				}
				candidate.estimate.value = VehicleUtils.AdjustTrainScoreBySlope(
						candidate.estimate.value, candidate.estimate.engine, orgTile, candidate.place.GetLocation());
			} else if(candidate.vehicleType == AIVehicle.VT_ROAD) {
				if(!HgTile.IsLandConnectedForRoad(orgTile, candidate.place.GetLocation())) {
					continue;
				}
			} else if(candidate.vehicleType == AIVehicle.VT_AIR) {
				if(!candidate.place.CanBuildAirport(minimumAiportType, cargo)) {
					continue;
				}
			} else if(candidate.vehicleType == AIVehicle.VT_WATER) {
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
		
		HgLog.Info("CreateRouteCandidates:" + orgPlace.GetName() + " cargo:"+AICargo.GetName(cargo) + " result:"+result.len()+"/"+candidates.len());
		return result;
	}

	
	function GetLocationFromDest(dest) {
		if(dest instanceof Place) {
			return dest.GetLocation();
		} else {
			return dest.srcHgStation.platformTile;
		}
	}
	

	function SearchAndBuildAdditionalSrc(route) {
		return null;
	}
	
	function GetMeetPlaceCandidates() {
		local result = [];
		foreach(route in Route.GetAllRoutes()) {
			local place = route.srcHgStation.place;
			if(place == null || !place.IsProcessing()) {
				continue;
			}
			if(!route.NeedsAdditionalProducing()) {
				HgLog.Info("!route.NeedsAdditionalProducing() GetMeetPlaceCandidates"+route);
				continue;
			}
			result.extend( GetMeetPlacePlans( place, route ) );
		}
		return result;
	}
	
	function GetTransferCandidates(originalRoute=null,  options={}) {
		if(originalRoute == null) {
			HgLog.Info("# start GetTransferCandidates ALL");
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
		local useLastMonthProduction = options.rawin("useLastMonthProduction") ? options.useLastMonthProduction : false;


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
				if(!lastTransferCandidates.rawin(route.id) || lastTransferCandidates.rawget(route.id) + 365 * 5 > current) {
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
			lastTransferCandidates.rawset(route.id,current);
			local routeResult = [];
			if(route.IsClosed()) {
				continue;
			}
			local additionalPlaces = [];
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
							ok = vehicleType == AIVehicle.VT_ROAD && route.GetDistance() >= 200 && HogeAI.Get().IsInfrastructureMaintenance()/*メンテコストがかかる場合、長距離道路の転送は認める*/;
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
				if(!destOnly) {
					additionalPlaces.extend(CreateTransferPlans(route, false, vehicleType, useLastMonthProduction, options));
				}
				if(!notTreatDest && route.IsBiDirectional() && !route.IsChangeDestination()) {
					additionalPlaces.extend(CreateTransferPlans(route, true, vehicleType, useLastMonthProduction, options));
				}
			}
			foreach(t in additionalPlaces) {
				DoInterval();

				local infrastractureTypes = t.routeClass.GetSuitableInfrastractureTypes(t.src, t.dest, t.cargo);
				local estimate = Route.Estimate( t.routeClass.GetVehicleType(), t.cargo, t.distance, t.production, false, infrastractureTypes );
				if(estimate != null) { // TODO: Estimate()はマイナスの場合も結果を返すべき
					estimate = clone estimate;
					
					estimate.EstimateAdditional( t.dest, t.src, infrastractureTypes, t.route );
					t.estimate <- estimate;
					t.score <- estimate.value;
					routeResult.push(t);
				}
			}
			//HgLog.Info("GetTransferCandidates sort:"+routeResult.len());
			routeResult.sort(function(t1,t2) {
				return t2.score - t1.score;
			});
			local count = 0;
			foreach(t in routeResult) {
				//HgLog.Info("place:"+t.place.GetName()+" cost:"+t.cost+" dist:"+t.distance+" score:"+t.score);
				if(t.vehicleType == AIVehicle.VT_WATER && !WaterRoute.CanBuild(t.src, t.dest, t.cargo, false)) {
					continue;
				}
				if(t.vehicleType == AIVehicle.VT_RAIL && !HgTile.IsLandConnectedForRail(t.src.GetLocation(), t.dest.GetLocation())) {
					continue;
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
			HgLog.Info("# end GetTransferCandidates ALL");
		}
		return result;
	}
	
	
	function SearchAndBuildTransferRoute(originalRoute,  options={}) {
	
	
		HgLog.Info("SearchAndBuildTransferRoute for "+originalRoute);

		local additionalPlaces = GetTransferCandidates(originalRoute, options);
		additionalPlaces.sort(function(a,b) {
			return b.score - a.score;
		});
		foreach(t in additionalPlaces) {
			t.explain <- "Transfer score:"+t.score+" "+t.src+" roi:"+t.estimate.roi+" route:"+t.estimate.routeIncome+" bt:"+t.estimate.buildingTime+" vt:"+t.routeClass.GetLabel()+" production:"+t.production+" for "+t.route;
			HgLog.Info(t.explain);
		}
		
		local limitDate = AIDate.GetCurrentDate() + 90;
		if(originalRoute != null) {
			local latestEngineSet = originalRoute.GetLatestEngineSet();
			HgLog.Info("TryBuild Transfer v:"+latestEngineSet.GetValue()+" distance:"+ originalRoute.GetDistance()
				+" "+latestEngineSet+" build("+latestEngineSet.buildingTime+"d,$"+latestEngineSet.buildingCost+") "+originalRoute);
		}
		/*
		local routePlans = HogeAI.Get().GetSortedRoutePlans(additionalPlaces);
		DoRoutePlans( routePlans ,null ,{ 
			routePlans = routePlans
			noDoRoutePlans = true
			limitDate = limitDate 
		} );*/
		
		foreach(t in additionalPlaces) {
			if(limitDate < AIDate.GetCurrentDate()) {
				HgLog.Info("time limit SearchAndBuildTransferRoute");
				break;
			}
			if(t.score <= 0) {
				continue;
			}
			local latestEngineSet = t.route.GetLatestEngineSet();
			local originalRouteValue = latestEngineSet.GetValue();
			local value = t.estimate.GetValue();
			HgLog.Info("Transfer estimate v:" + value + " " + t.srcPlace.GetName() + "("+ t.distance+") " + t.estimate
				+" build("+t.estimate.buildingTime+"d,$"+t.estimate.buildingCost+")"+" "+t.route);
			if((roiBase && value < originalRouteValue) || (!roiBase && value < originalRouteValue / 2)) {
				continue;
			}
			// TODO 容量オーバーのチェック
			local routeBuilder = t.routeClass.GetBuilderClass()( t.dest, t.srcPlace, t.cargo, { destRoute = t.route });
			if(!routeBuilder.ExistsSameRoute()) {
				HgLog.Info(routeBuilder+" for:"+t.route);
				local newRoute = routeBuilder.Build();
				if(newRoute != null) {
					t.route.NotifyAddTransfer();
				}
				
			}
			DoInterval();
			
		}
		
		return false;
	}
	
	function CreateTransferPlans(route,isDest,vehicleType,useLastMonthProduction=false,options={}) {
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
			minProduction = vehicleType == AIVehicle.VT_RAIL ? 50 : 1;
		} else {
			minDistance = 0;
			maxDistance = 200;
			minProduction = 1;
		}
		if(roiBase) {
			maxDistance = max(50,min(maxDistance, route.GetDistance() / 2));
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
		if(isDest) {
			hgStation = route.destHgStation;
		} else {
			hgStation = route.srcHgStation;
		}
		if(hgStation.place != null && hgStation.place.HasStation(vehicleType)) { // なぜかうまくrouteを作れないが他社に奪われる事があるので、転送先としては不適切
			return [];
		}
		local finalDestStation = route.GetFinalDestStation();
		local finalDestLocation = isDest ? route.srcHgStation.platformTile : finalDestStation.GetLocation();
		local noCheckNeedsAdditionalProducing = options.rawin("noCheckNeedsAdditionalProducing") ? options.noCheckNeedsAdditionalProducing : false;
		
		foreach(cargo in route.GetCargos()) {
		/*
			if(route.destHgStation.stationGroup.IsOverflow(cargo)) {
				TODO: destのadditional
			}*/
			if(!noCheckNeedsAdditionalProducing && !route.NeedsAdditionalProducingCargo(cargo, null, isDest)) {
				//HgLog.Info("!NeedsAdditionalProducingCargo ["+AICargo.GetCargoLabel(cargo)+"] "+route);
				continue;
			}
			
			local srcPlaceInfos = Place.SearchSrcAdditionalPlaces( 
					hgStation, finalDestLocation, 
					cargo, minDistance, maxDistance, minProduction, vehicleType);
			HgLog.Info("TransferCandidates:"+srcPlaceInfos.len()+" "+hgStation.GetName()+"["+AICargo.GetName(cargo)+"] distance:"+maxDistance);
			foreach(data in srcPlaceInfos) {
				if(!data.place.CanUseTransferRoute(cargo, vehicleType)) {
					//HgLog.Info("!CanUseTransferRoute ["+AICargo.GetCargoLabel(cargo)+"] "+route);
					continue;
				}
				local lastMonthProduction = data.place.GetLastMonthProduction(cargo);
				if(lastMonthProduction == 0 && hgStation.stationGroup.HasCargoRating(cargo)) { // 生産していない施設からの転送はゼロルートの場合にしか試さない
					//HgLog.Info("lastMonthProduction == 0 ["+AICargo.GetCargoLabel(cargo)+"] "+route);
					continue;
				}
				local production = useLastMonthProduction ? lastMonthProduction : data.place.GetExpectedProduction(cargo, vehicleType);
				if(production < minProduction) {
					//HgLog.Info("production < minProduction ["+AICargo.GetCargoLabel(cargo)+"] "+route);
					continue;
				}
				
				local t = {};
				t.route <- route;
				t.vehicleType <- vehicleType;
				t.routeClass <- routeClass;
				t.cargo <- cargo;
				t.dest <- hgStation.stationGroup;
				t.src <- data.place;
				t.srcPlace <- data.place;
				t.distance <- data.distance;
				t.production <- production;
				t.isDest <- isDest;
				t.isRaw <- false;
				//HgLog.Info("additionalSrcPlace:"+t.srcPlace.GetName()+" production:"+t.production+"["+AICargo.GetName(t.cargo)+"] distance:"+t.distance+" vt:"+routeClass.GetLabel()+" isDest:"+isDest+" for:"+route);
				additionalPlaces.push(t);
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
			if(dirtyPlaces.rawin(plan.src.GetGId()+":"+plan.cargo)) {
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
			if( newRoute == false) { // ExistsSameRoute
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
		local routeBuilder = routePlan.routeClass.GetBuilderClass()(routePlan.dest, routePlan.src, routePlan.cargo, options);
		if(routeBuilder.ExistsSameRoute()) {
			return false;
		}
		HgLog.Info(routeBuilder + explain);
		local newRoute = routeBuilder.Build();
		if(newRoute != null) {
			if(newRoute.IsTransfer() && routePlan.rawin("route")) {
				routePlan.route.NotifyAddTransfer();
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
		if(!srcPlace.IsIncreasable()) {
			return [];
		}
		local result = [];
		local acceptingPlace = srcPlace.GetAccepting();
		foreach(cargo in acceptingPlace.GetCargos()) {
			if(!acceptingPlace.IsIncreasableInputCargo(cargo)) {
				continue;
			}
			result.extend(CreateRoutePlans({place=acceptingPlace,cargo=cargo},null/*結果数の制限無し*/,{noShowResult=true, noSortResult=true, useLastMonthProduction=true}));
		}
		return result;
	/*
	
		local cargoPlans = GetCargoPlansToMeetSrcDemand(srcPlace.GetAccepting(), forRoute, true);
		local routePlans = [];
		local multiInputProcessing = srcPlace.IsProcessing() && cargoPlans.len() >= 2;
		if(firs && (multiInputProcessing || srcPlace.IsRaw())) {
			foreach(cargoPlan in cargoPlans) {
				HgLog.Info("CargoPlan: "+AICargo.GetName(cargoPlan.cargo)+" srcPlace:"+srcPlace.GetName()+"(SearchAndBuildToMeetSrcDemandMin)");
				routePlans.extend(CreateRoutePlans(cargoPlan,null));
			}
			
		} else {
			foreach(cargoPlan in cargoPlans) {
				routePlans.extend(CreateRoutePlans(cargoPlan,null,{noShowResult=true, noSortResult=true, useLastMonthProduction=true}));
			}
		}
		return routePlans;*/
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
	
	function CreateRoutePlans(cargoPlan, maxResult=20, options={}) {
		local additionalProduction = 0; // expectbaseに変更 //現在生産量でソースを選択しなくてはならないが、初期でほとんど何も生産していない場合がある
		local routePlans = [];
		local cargo = cargoPlan.cargo;
		local noShowResult = options.rawin("noShowResult") ? options.noShowResult : false;
		local noSortResult = options.rawin("noSortResult") ? options.noSortResult : false;
		if(cargoPlan.rawin("srcPlace")) {
			foreach(destCandidate in CreateRouteCandidates(cargo, cargoPlan.srcPlace, {places=[cargoPlan.destPlace]}, 
					additionalProduction, maxResult, options)) {
				local routePlan = {};
				local routeClass = Route.Class(destCandidate.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				routePlan.cargo <- cargo;
				routePlan.src <- cargoPlan.srcPlace;
				routePlan.dest <- destCandidate.place;
				routePlan.distance <- destCandidate.distance;
				routePlan.production <- routePlan.src.GetLastMonthProduction(cargo);
				routePlan.vehicleType <- destCandidate.vehicleType;
				routePlan.routeClass <- routeClass;
				routePlan.estimate <- destCandidate.estimate;
				routePlan.score <- destCandidate.score;
				routePlans.push(routePlan);
			}
		} else if(cargoPlan.place.IsAccepting()) {
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
				routePlan.cargo <- cargo;
				routePlan.src <- srcCandidate.place;
				routePlan.dest <- acceptingPlace;
				routePlan.distance <- srcCandidate.distance;
				routePlan.production <- routePlan.src.GetLastMonthProduction(cargo);
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
			local producingPlace = cargoPlan.place;
			foreach(destCandidate in CreateRouteCandidates(cargo, producingPlace,
					{searchProducing = false}, additionalProduction, maxResult, options)) {
				local routePlan = {};
				local routeClass = Route.Class(destCandidate.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				routePlan.canChangeDest <- true;
				routePlan.cargo <- cargo;
				routePlan.src <- producingPlace;
				routePlan.dest <- destCandidate.place;
				routePlan.distance <- destCandidate.distance;
				routePlan.production <- routePlan.src.GetLastMonthProduction(cargo);
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
			foreach(usingRoute in destHgStation.place.GetProducing().GetRoutesUsingSource()) {
				if(usingRoute.GetRouteWeighting() >= 2) {
					return null;
				} else if(!usingRoute.IsTransfer()) {
					return null;
				}
			}
			foreach(usingRoute in destHgStation.place.GetAccepting().GetRoutesUsingDest()) {
				if(usingRoute == route) {
					continue;
				}
				return null;
			}
		}

		if(route.GetLastRoute().returnRoute != null) {
			return null;
		}
		local maxExtDistance = 0;
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
		}
		
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
		foreach(placeScore in Place.SearchAdditionalAcceptingPlaces(
				route.GetUsableCargos(), route.GetSrcStationTiles(), destHgStation.platformTile, maxExtDistance + 50)) {
			if(placeScore[0].IsSamePlace(destHgStation.place)) {
				continue;
			}
			if(ecs && /*!ecsHardDest &&*/ placeScore[0].IsEcsHardNewRouteDest(route.cargo)) {
				continue;
			}
			if(route.IsBiDirectional() && route.srcHgStation.place!=null && destHgStation.place!=null) {
				if(!placeScore[0].GetProducing().CanUseNewRoute(route.cargo, AIVehicle.VT_RAIL)) {
					continue;
				}
			}
			
			local placeLocation = placeScore[0].GetLocation();
			local nearestInfo = route.pathSrcToDest.path.GetNearestTileDistance(placeLocation);
			local forkPoint = nearestInfo[0];
			local buildingDistance = nearestInfo[1];
			if(!HgTile.IsLandConnectedForRail(placeLocation, forkPoint)) {
				continue;
			}
			local cargoDistance = AIMap.DistanceManhattan(placeLocation, route.srcHgStation.GetLocation());
			placeScore[1] = VehicleUtils.AdjustTrainScoreBySlope( 
				100000 / max(1,abs((cargoDistance - route.GetDistance()) - maxExtDistance))
				, route.GetLatestEngineSet().engine, forkPoint, placeLocation ) * 100 / (buildingDistance + 250);
			placeScores.push(placeScore);
			DoInterval();
		}
		
		placeScores.sort(function(a,b) {
			return b[1] - a[1];
		});
		
		foreach(placeScore in placeScores) {
			DoInterval();
			HgLog.Info("Found an additional accepting place:"+placeScore[0].GetName()+" route:"+route);
			local result = TrainRouteExtendBuilder(route,placeScore[0]).Build();
			if(result == 0) {
				//CheckAndBuildCascadeRoute(placeScore[0],route.cargo);
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
	
		if(route.returnRoute == null && route.GetDistance() >= 400
				&& !route.IsBiDirectional() && !route.IsSingle() && !route.IsTransfer() && !route.IsChangeDestination()) {
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
			return t.production >= 50 && placeDictionary.CanUseAsSource(t.place,cargo);
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
		}).Filter(function(t) {
			return t.distanceFromPath<=250 && t.place.IsAccepting();
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
	
	function GetBuildableStationByPath(path, toTile, cargo, platformLength) {
		local pathDistances = [];
		path = path.Reverse();
		local count = 0;
		while(path != null) {
			if(count++ >= 10) {
				if(toTile == null) {
					pathDistances.push([path, count]);	
				} else {
					pathDistances.push([path, AIMap.DistanceManhattan(path.GetTile(),toTile)]);		
				}
			}
			path = path.GetParent();
		}
		pathDistances.sort(function(a,b){
			return a[1]-b[1];
		});
		local count = 0;
		local stationFactory = TransferStationFactory();
		stationFactory.platformLength = platformLength;
		stationFactory.minPlatformLength = platformLength;
		local dividedRails = 10;
		do {
			local stations = [];
			//local rectangle = null;
			for(local i=0; i<dividedRails && count + i < pathDistances.len(); i++) {
/*				
				local tile = pathDistances[count+i][0].GetTile();
				local r = Rectangle(HgTile(tile) - HgTile.XY(10,10) ,HgTile(tile) + HgTile.XY(11,11));
				if(rectangle == null) {
					rectangle = r;
				} else {
					rectangle = rectangle.Include(r);
				}*/
				
				
				
				local forks = pathDistances[count+i][0].GetMeetsTiles(); //Reverseのmeetsなのでforks
				if(forks == null) {
					continue;
				}
				foreach(forkTiles in forks) {
					local s = forkTiles[2];
					local d = (forkTiles[2] - forkTiles[1]) / AIMap.DistanceManhattan(forkTiles[2],forkTiles[1]);
//					HgLog.Info("forkTiles[0]" + HgTile(forkTiles[0]) + " [1]" + HgTile(forkTiles[1]) + " [2]"+HgTile(forkTiles[2]));
					if(HgStation.GetStationDirectionFromTileIndex(d)==null) {
						HgLog.Warning("forkTiles[1]" + HgTile(forkTiles[1]) + " forkTiles[0]"+HgTile(forkTiles[0]));
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
					
					stations.extend(x);
					
				}
			}
			//stations = stationFactory.CreateInRectangle(rectangle);
			
			foreach(station in stations) {
				station.score = station.GetBuildableScore() + (station.IsProducingCargoWithoutStationGroup(cargo) ? 20 : 0);
			}
			stations.sort(function(a,b) {
				return b.score-a.score;
			});
			HgLog.Info("GetBuildableStationByPath stations:"+stations.len());
			foreach(station in stations) {
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
			
			count += dividedRails;
		} while(count < pathDistances.len());

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
	
	function CreateTownTransferRoutes(townBus, route, station) {
		townBus.CreateTransferRoutes(route, station);
		/* Route側から定期的に呼ぶようになったので廃止
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			HgLog.Warning("AddPending:CreateTownTransferRoutes.(AIError.ERR_LOCAL_AUTHORITY_REFUSES)");
			HogeAI.Get().AddPending("CreateTownTransferRoutes",[townBus, route, station],30);
		}*/
	}
	
	function GetAirportExchangeCandidates() {
		if(AirRoute.IsTooManyVehiclesForNewRoute(AirRoute)) {
			return [];
		}
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
	
	function AddPending(method, arg, days) {
		pendings.rawset({
			method = method
			arg = arg
			limit = AIDate.GetCurrentDate() + days
		},0);
	}

	function DoPending() {
		foreach(pending,_ in pendings) {
			if(pending.limit > AIDate.GetCurrentDate()) {
				continue;
			}
			pendings.rawdelete(pending);
			local arg = pending.arg;
			switch (pending.method) {
				case "CreateTownTransferRoutes":
					CreateTownTransferRoutes(arg[0], arg[1], arg[2]);
					break;
			}
		}
	}
	
	function DoInterrupt() {
		if(supressInterrupt) {
			return;
		}
		supressInterrupt = true;
		DoPending();
		supressInterrupt = false;
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
		
		//HgLog.Info("DoInterval start");
		
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

		CheckTownStatue();
		times.push(AIDate.GetCurrentDate()); //1

		CheckTrainRoute();
		times.push(AIDate.GetCurrentDate()); //2

		CheckRoadRoute();
		times.push(AIDate.GetCurrentDate()); //3

		CheckBus();
		times.push(AIDate.GetCurrentDate()); //4
		
		CheckWaterRoute();
		times.push(AIDate.GetCurrentDate()); //5
		
		CheckAirRoute();
		times.push(AIDate.GetCurrentDate()); //6

		DelayCommandExecuter.Get().Check();
		times.push(AIDate.GetCurrentDate()); //7
		
		DoInterrupt();
		times.push(AIDate.GetCurrentDate()); //8
		
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
			intervalSpan = total;
		} else {
			intervalSpan = 7;
		}
		
		
		local span = max(1,intervalSpan / GetDayLengthFactor());
		lastIntervalDate = AIDate.GetCurrentDate() + span;
		
		AIRail.SetCurrentRailType(currentRailType);
		AIRoad.SetCurrentRoadType(currentRoadType);
		supressInterval = false;
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
		local group = AIVehicle.GetGroupID(vehicle);
		local vehicleType = AIVehicle.GetVehicleType(vehicle);
		HgLog.Warning("ET_VEHICLE_LOST:"+VehicleUtils.GetTypeName(vehicleType)+" "+ vehicle+" "+AIVehicle.GetName(vehicle)+" group:"+AIGroup.GetName(group));
		if(vehicleType == AIVehicle.VT_ROAD || vehicleType == AIVehicle.VT_WATER) {
			if(Route.groupRoute.rawin(group)) {
				Route.groupRoute.rawget(group).OnVehicleLost(vehicle);
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

		table.routeCandidates <- routeCandidates.Save();
		table.constractions <- constractions;

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
		
		routeCandidates.Load(loadData.routeCandidates);
		
		HgLog.Info("constractions load size:"+loadData.constractions.len());
		while(loadData.constractions.len() >= 1) {
			Construction.LoadStatics(loadData.constractions.pop());
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
		return HogeAI.WaitForPrice(HogeAI.GetInflatedMoney(needMoney),1000,maxDays,reason);
	}
	
	function GetInflatedMoney(money) {
		local inflationRate = AICompany.GetMaxLoanAmount().tofloat() / HogeAI.Get().GetMaxLoan().tofloat();
		return (money * inflationRate).tointeger();
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
		return AICompany.GetBankBalance(AICompany.COMPANY_SELF) + (AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount());
	}

	function IsTooExpensive(cost) {
		return HogeAI.GetQuarterlyIncome() < cost && HogeAI.GetUsableMoney() < cost;
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

	function IsDistantJoinStations() {
		return isDistantJoinStations;
	}
	
	function IsInfrastructureMaintenance() {
		return isInfrastructureMaintenance;
	}
	
	function IsInfrastructureMaintenance() {
		return isInfrastructureMaintenance;
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
	
	function IsInfrastructureMaintenance() {
		return isInfrastructureMaintenance;
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
		HgLog.Info("hogeIndex:"+hogeIndex+" hogeNum:"+hogeNum);
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
			if("route" in t) {
				plan.route <- Route.allRoutes[t.route];
			}
			idCounter.Skip(id);
			sortedList.Push(plan);
		}
	}
	
	function Push(t) {
		t.id <- idCounter.Get()
		local s = t;
		if(!("typeName" in t)) {
			s = {
				src = t.src.Save()
				dest = t.dest.Save()
				vehicleType = t.vehicleType
				cargo = t.cargo
				estimate = t.estimate
				score = t.score
			};
			if("route" in t) {
				s.route <- t.route.id;
			}
			if(!("explain" in t)) {
				local routeClass = Route.Class(t.vehicleType);
				t.isBiDirectional <- (t.dest instanceof Place) ? t.dest.IsAcceptingAndProducing(t.cargo) && t.src.IsAcceptingAndProducing(t.cargo) : false;
				t.explain <- t.estimate.value+" "+routeClass.GetLabel()+" "+t.dest+"<="+(t.isBiDirectional?">":"")+t.src+"["+AICargo.GetName(t.cargo)+"] dist:"
					+t.estimate.distance+" prod:"+t.estimate.production;
				if(t.vehicleType == AIVehicle.VT_AIR) {
					t.explain += " infraType:"+t.estimate.infrastractureType;
				}
			}
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

