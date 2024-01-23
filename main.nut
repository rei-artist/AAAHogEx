
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

class AAA {
	function func(self) {
		return self.hello();
	}

	function hello() {
		return "aaa";
	}
}

class BBB extends AAA {
	function hello() {
		return "bbb";
	}
}

class HogeAI extends AIController {
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
	maybePurchasedLand = null;
	pathFindLimit = null;
	loadData = null;
	lastIntervalDate = null;
	passengerCargo = null;
	mailCargo = null;
	supressInterval = null;
	supressInterrupt = null;
	limitDate = null;
	isTimeoutToMeetSrcDemand = null;
	pathfindings = null;
	townRoadType = null;
	clearWaterCost = null;
	roadTrafficRate = null;
	canUsePlaceOnWater = null;
	waitForPriceStartDate = null;
	maxRoi = null;
	cargoVtDistanceValues = null;
	
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
				AILog.Error("No CC_PASSENGERS cargo");
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
		
		return self.passengerCargo;
	}
	
	static function GetMailCargo() {
		local self = HogeAI.Get();
		if(self.mailCargo == null) {
			local cargoList = AICargoList();
			cargoList.Valuate(AICargo.HasCargoClass, AICargo.CC_MAIL);
			cargoList.KeepValue(1);
			if(cargoList.Count()==0) {
				AILog.Error("No CC_MAIL cargo");
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
		
		return self.mailCargo;
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
		cargoVtDistanceValues = {}

		DelayCommandExecuter();
	}
	 
	function Start() {
		HgLog.Info("AAAHogEx Started!");
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
		SetCompanyName();

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
		
		local numCompany = 0;
		local hogex = 0;
		HgLog.Info("firstCompanyId:"+AICompany.COMPANY_FIRST+" lastCompanyId:"+AICompany.COMPANY_LAST);
		for(local id = AICompany.COMPANY_FIRST; id<AICompany.COMPANY_LAST; id++) {
			if(AICompany.ResolveCompanyID(id) != AICompany.COMPANY_INVALID) {
				local name = AICompany.GetName(id);
				if(name != null && name.find("AAAHogEx") != null) {
					hogex ++;
				}
				numCompany ++;
			}
		}
		if(!HogeAI.Get().IsDebug()) {
			WaitDays(AIBase.RandRange(hogex*7));
		}

		if(numCompany > AIIndustryList().Count()) {
			WaitDays(365); // 新しいindustryが建設されるのを待ってみる
		}
		
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
				
				DoInterval(indexPointer==0);
				DoInterrupt();
				DoStep();
				indexPointer ++;
			}
			indexPointer = 0;
			turn ++;
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
			local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
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
			local routeClass = Route.GetRouteClassFromVehicleType(vt);
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
		HgLog.Info("###### Scan places");
		
		if(/*IsForceToHandleFright() &&*/ isTimeoutToMeetSrcDemand) { // Airやるだけなら良いが、余計なルートを作ってsupply chainを混乱させる事があったのでコメントアウト
			return;
		}
		AIController.Sleep(1);
		local aiTestMode = AITestMode();
		
		local startDate = AIDate.GetCurrentDate();
		//local bests = [];
		local candidate;
		local routeCandidatesGen = GetRouteCandidatesGen();
		local bests = GetSortedRoutePlans([]);
		local candidateNum = 1000; // 400 / (16*8) = cargo 4種類
		for(local i=0; (candidate=resume routeCandidatesGen) != null && i<candidateNum; i++) {
			bests.Push(candidate);
/*			candidate.score += AIBase.RandRange(10); // ほかのHogexとの競合を防ぐ
			bests.push(candidate);*/
		}
		bests.Extend( GetTransferCandidates() );
		bests.Extend( GetMeetPlaceCandidates() );
		
		//bests = bests.slice(0, min(bests.len(), 50));
		foreach(e in bests.GetAll()) {
			local s = "ScanPlaces.score "+e.estimate+" "+e.routeClass.GetLabel()
				+" "+e.dest.GetName() + "<-" + e.src.GetName()+" distance:"+e.distance;
			// local s = "ScanPlaces.score"+e.score+" production:"+e.production+" value:"+e.estimate.value+" vt:"+e.routeClass.GetLabel()
				// +" "+e.dest.GetName() + "<-" + e.srcPlace.GetName()+" ["+AICargo.GetName(e.cargo)+"] distance:"+e.distance;
			if(e.vehicleType == AIVehicle.VT_AIR) {
				s += " infraType:"+e.estimate.infrastractureType;
			}
			HgLog.Info(s);
		}
		local searchDays = AIDate.GetCurrentDate() - startDate;
		HgLog.Info("searchDays:"+searchDays);
		limitDate = AIDate.GetCurrentDate() + max((roiBase ? 356 : 365*2) / GetDayLengthFactor(), searchDays * 5);
		local dirtyPlaces = {};
		local rootBuilders = [];
		local pendingPlans = [];
		local totalNeeds = 0;
		local endDate = AIDate.GetCurrentDate();
		local buildingStartDate = AIDate.GetCurrentDate();
		while(bests.Count() >= 1){
			local t = bests.Pop();
			if(t.vehicleType != AIVehicle.VT_AIR) { //airの場合迅速にやらないといけないので
				DoInterval(); 
			}
			local isBiDirectional = (t.dest instanceof Place) ? t.dest.IsAcceptingAndProducing(t.cargo) && t.src.IsAcceptingAndProducing(t.cargo) : false;
			local explain = t.dest+"<="+(isBiDirectional?">":"")+t.src+"["+t.cargo+"]";
			/*if(roiBase && t.estimate.value < 150) { 何もしなくなってしまうマップがある
				if(index==0) {
					WaitDays(365); // 最初から収益性が悪すぎるのでしばらく様子をて再検索
				}
				DoPostBuildRoute(rootBuilders);
				return;
			}*/
			if(isBiDirectional && dirtyPlaces.rawin(t.dest.GetGId()+":"+t.cargo)) { // 同じplaceで競合するのを防ぐ(特にAIRとRAIL)
				HgLog.Info("dirtyPlaces dest "+explain);
				continue;
			}
			if(dirtyPlaces.rawin(t.src.GetGId()+":"+t.cargo)) {
				HgLog.Info("dirtyPlaces src "+explain);
				continue;
			}
			if(!t.src.CanUseNewRoute(t.cargo, t.vehicleType)) {
				HgLog.Info("Not CanUseNewRoute src "+explain);
				continue;
			}
			if(t.dest instanceof Place && t.dest.IsAcceptingAndProducing(t.cargo) && !t.dest.GetProducing().CanUseNewRoute(t.cargo, t.vehicleType)) {
				HgLog.Info("Not accept or Not CanUseNewRoute dest "+explain);
				continue;
			}
			if(Place.IsNgPlace(t.dest, t.cargo, t.vehicleType) || Place.IsNgPlace(t.src, t.cargo, t.vehicleType)) {
				HgLog.Info("NgPlace "+explain);
				continue;
			}
			if(t.routeClass.IsTooManyVehiclesForNewRoute(t.routeClass)) {
				HgLog.Info("TooManyVehicles "+explain);
				continue;
			}
			if(t.src instanceof Place && t.src.IsProcessing() && t.src.IsDirtyArround()) {
				HgLog.Info("DirtyArround "+explain);
				continue;
			}
			if(t.rawin("route")) {
				if(!t.route.NeedsAdditionalProducingCargo( t.cargo, null, t.route.destHgStation.stationGroup==t.dest )) {
					//HgLog.Warning("NeedsAdditionalProducing false "+explain+" "+t.route);
					pendingPlans.push(t);
					continue;
				}
				if(t.estimate.destRouteCargoIncome > 0) {
					local finalDestStation = t.route.GetFinalDestStation( null, t.dest );
					if(finalDestStation.place != null && finalDestStation.place.GetDestRouteCargoIncome() == 0) {
						pendingPlans.push(t);
						continue;
					}
				}
				
				//HgLog.Info("NeedsAdditionalProducing true "+explain+" "+t.route);
			} else {
				if(t.estimate.destRouteCargoIncome > 0 && t.dest.GetDestRouteCargoIncome() == 0) {
					pendingPlans.push(t);
					continue;
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
							continue;
						}
					}
				}
			}
			
			local routeBuilder = t.routeClass.GetBuilderClass()(t.dest, t.src, t.cargo, { 
				pendingToDoPostBuild = false //roiBase ? true : false
				destRoute = t.rawin("route") ? t.route : null
				noDoRoutePlans = true
				routePlans = bests
			});
			if(routeBuilder.ExistsSameRoute()) {
				HgLog.Info("ExistsSameRoute "+explain);
				continue;
			}
			if(t.estimate.value < 0) {
				HgLog.Info("t.estimate.value < 0 ("+t.estimate.value+") "+explain);
				continue;
			}
			HgLog.Info("Try "+routeBuilder+" production:"+t.production+" distance:"+t.distance+" value:"+t.estimate.value);
			local newRoute = routeBuilder.Build();
			bests.Extend(pendingPlans);
			pendingPlans.clear();
			if(newRoute != null) {
				if(t.src instanceof Place) {
					t.src.SetDirtyArround();
				}
				if(newRoute.IsTransfer() && t.rawin("route")) {
					t.route.NotifyAddTransfer();
				}
				rootBuilders.push(routeBuilder);
				if(isBiDirectional) {
					dirtyPlaces.rawset(t.dest.GetGId()+":"+t.cargo, true);
				}
				dirtyPlaces.rawset(t.src.GetGId()+":"+t.cargo, true);
				/*
				if(newRoute instanceof TrainRoute) {
					newRoute.isBuilding = true;
					while(SearchAndBuildAdditionalDest(newRoute) != null) {
					}
					SearchAndBuildToMeetSrcDemandTransfer(newRoute, null, {destOnly=true});
					CheckBuildReturnRoute(newRoute);
					newRoute.isBuilding = false;
				}*/
				if(roiBase && bests.Count() >= 1) {
					if(IsRich() && AIDate.GetCurrentDate() - buildingStartDate > 180) { // roiBaseから変わったので再検索
						DoPostBuildRoute(rootBuilders);
						return;
					}
					local next = bests.Peek();
					local usable = GetUsableMoney() + GetQuarterlyIncome() * t.estimate.days / 90;
					totalNeeds += t.estimate.price * (t.estimate.vehiclesPerRoute - 1); // TODO: これまでの建築にかかった時間分減らす
					local nextNeeds = next.estimate.buildingCost + next.estimate.price;
					local needs = totalNeeds + nextNeeds;
					HgLog.Info("price:"+t.estimate.price+" vehiclesPerRoute:"+t.estimate.vehiclesPerRoute+" totalNeeds:"+totalNeeds+" nextNeeds:"+nextNeeds+" usable:"+usable);
					endDate = max( endDate, AIDate.GetCurrentDate() + t.estimate.days );
					if(usable < needs) { // 次の建築をしながら、前のルートの乗り物を作れない
						HgLog.Info("usable:"+usable+" needs:"+needs);
						WaitDays(min(180,max(0,endDate - AIDate.GetCurrentDate())));
						totalNeeds = 0;
						for(local i=0; GetUsableMoney() < nextNeeds; i++) { // 次の建築ができない(最大6か月待つ)
							HgLog.Info("usable:"+usable+" nextNeeds:"+nextNeeds);
							WaitDays(10);
							if(i>=17) {
								DoPostBuildRoute(rootBuilders);
								return;
							}
						}
					}
					if(next.estimate.value < 200 && IsInfrastructureMaintenance() && next.vehicleType == AIVehicle.VT_ROAD) { 
						WaitDays(365); // 収益性が悪すぎるのでしばらく様子を見て再検索
						DoPostBuildRoute(rootBuilders);
						return;
					}
					if(roiBase && next.estimate.value < 200) {
						DoPostBuildRoute(rootBuilders);
						return;
					}
/*
						if(IsInfrastructureMaintenance()) {
							DoPostBuildRoute(rootBuilders);
							return; // インフラコストの上昇は非線形なので再検索
						}*/						/*
					GetUsableMoney() - next.estimate.buildingCost
					
					
					if(next.estimate.value < 400) {
						local maxMonth = min(12, 12 - next.estimate.value / 40);
						local wait = false;
						for(local i=0; i<maxMonth && !HasIncome(20000) || GetUsableMoney() < GetInflatedMoney(80000);i++) {
							WaitDays(30); // 建設にコストを掛けすぎて車両が作れなくなる事を防ぐ為に、車両作成の為の時間を空ける
							wait = true;
						}
						if(wait) {
							DoPostBuildRoute(rootBuilders);
							return;
						}
					} else {
						if(IsInfrastructureMaintenance()) {
							if(!HasIncome(20000) || GetUsableMoney() < GetInflatedMoney(80000)) {
								WaitDays(120);
								return; // お金ないし念のため再検索
							}
						} else if(!HasIncome(20000) || GetUsableMoney() < GetInflatedMoney(80000)) {
							DoPostBuildRoute(rootBuilders);
							return; // お金ないし念のため再検索
						}
					}*/
					
					/*
					local maxMonth = min(12, 12 - next.estimate.value / 50);
					for(local i=0; i<maxMonth && !HasIncome(20000) || GetUsableMoney() < GetInflatedMoney(80000);i++) {
						WaitDays(30); // 建設にコストを掛けすぎて車両が作れなくなる事を防ぐ為に、車両作成の為の時間を空ける
					}*/
				}/*
				if(IsInfrastructureMaintenance()) {
					DoPostBuildRoute(rootBuilders);
					return; // インフラコストの上昇は非線形なので再検索
				}*/
			}
			if(limitDate < AIDate.GetCurrentDate()) {
				DoPostBuildRoute(rootBuilders);
				return;
			}
		}
		DoPostBuildRoute(rootBuilders);
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
			AIRail.SetCurrentRailType(route.GetRailType());
			route.isBuilding = true;
			
			/*TODO
			local destStation = route.destHgStation.GetAIStation();
			foreach(cargo in route.GetUsableCargos()) {
				local waiting = AIStation.GetCargoWaiting(destStation, cargo);
				if(waiting > 0) {
					CreateDeliverRoute(route, cargo, waiting);
				}
			}*/
			

			SearchAndBuildAdditionalSrc(route);
			if(SearchAndBuildAdditionalDestAsFarAsPossible( route )) {
				CheckBuildReturnRoute(route); // やたらとreturn route作成失敗を繰り返すので延長できた時のみ
				// scan placeでやる SearchAndBuildTransferRoute( route, { useLastMonthProduction = true } );
			}
			route.isBuilding = false;
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
					places = ArrayUtils.Shuffle( Place.GetCargoAccepting(src.cargo).array )
				};
				cargoPlaceInfo.rawset(src.cargo, placeInfo);
			}
			foreach(dest in CreateRouteCandidates(src.cargo, src.place, cargoPlaceInfo[src.cargo], 0 , 16)) {
//					Place.GetAcceptingPlaceDistance(src.cargo, src.place.GetLocation()))) {
				
				local routeClass = Route.GetRouteClassFromVehicleType(dest.vehicleType);
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
		
		
		PlaceProduction.Get().cargoProductionInfos = null;
		if(!roiBase) {
			PlaceProduction.Get().GetCargoProductionInfos(); // Valuateの中で走らないように先に計算
		}
			
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
				ignoreCargos.rawset( GetPassengerCargo(), true );
				ignoreCargos.rawset( GetMailCargo(), true );
			}
		}
		
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		foreach(cargo ,_ in AICargoList()) {
			local vtDistanceValues = [];
			if(ignoreCargos.rawin(cargo)) {
				continue;
			}
			if(IsPaxMailOnly() && !CargoUtils.IsPaxOrMail(cargo)) {
				continue;
			}
			if(IsFreightOnly() && CargoUtils.IsPaxOrMail(cargo)) {
				continue;
			}
			//HgLog.Info("step0 "+AICargo.GetName(cargo));
			
			local placesList = Place.GetNotUsedProducingPlacesList( cargo );
			local places = placesList[0];
			local placeList = ListUtils.Clone(placesList[1]);
			
			if(placeList.Count() > 300) {
				placeList.Sort(AIList.SORT_BY_VALUE, false);
				foreach(placeIndex,_ in placeList) {
					placeList.SetValue(placeIndex, places[placeIndex].GetLastMonthProduction(cargo));
				}
				placeList.KeepTop(300);
			}
			/*
			placeList.Valuate(function(i):(places,cargo){
				return Place.IsNgCandidatePlace(places[i],cargo);
			});
			placeList.RemoveValue(1);
			placeList.Valuate( function(i):(places,cargo) {
				return PlaceDictionary.Get().CanUseAsSource(places[i],cargo);
			});
			placeList.KeepValue(1);*/
			if(placeList.Count() == 0) {
				continue;
			}

			local production = roiBase ? 210 : 890;
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
				}
				if(cargoResult.len() == 0) {
					continue;
				}
				
				local infrastractureTypes = routeClass.GetDefaultInfrastractureTypes();
				
				HgLog.Info("Estimate:" + routeClass.GetLabel()+"["+AICargo.GetName(cargo)+"]");
				foreach(distanceIndex, distance in distanceEstimateSamples) {
					if(vehicleType != AIVehicle.VT_AIR && distance > 550) {
						continue;
					}
					local estimate = Route.Estimate(routeClass.GetVehicleType(), cargo, distance, production, CargoUtils.IsPaxOrMail(cargo) ? true: false, infrastractureTypes);
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
					local resultMax = 16;
					if(cargoResult.len() > resultMax) {
						if(vehicleType == AIVehicle.VT_AIR && CargoUtils.IsPaxOrMail(cargo)) {
							foreach(r in cargoResult) {
								r.scoreAirport <- r.place.GetAllowedAirportLevel(minimumAiportType, cargo) * 10000 + max(9999,r.production);				
							}
							cargoResult.sort(function(a,b){
								return -(a.scoreAirport - b.scoreAirport);
							});
						} else if(vehicleType == AIVehicle.VT_WATER) {
							foreach(r in cargoResult) {
								r.scoreWater <- (r.place.GetCoasts(cargo) != null ? 1 : 0) * 10000 + max(9999,r.production);				
							}
							cargoResult.sort(function(a,b){
								return -(a.scoreWater - b.scoreWater);
							});
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
			vtDistanceValues.sort(function(v1,v2) {
				return v2[2] - v1[2];
			});
			cargoVtDistanceValues.rawset(cargo,vtDistanceValues);
			
			/*
			if(maxVehicleType == AIVehicle.VT_AIR && CargoUtils.IsPaxOrMail(cargo)) {
				local r = [];
				foreach(place in places) {
					r.push([place, place.GetAllowedAirportLevel(minimumAiportType) * 10000 + max(9999,place.GetExpectedProduction(cargo,maxVehicleType))]);
				}
				r.sort(function(p1,p2) {
					return p2[1] - p1[1];
				});
				places = [];
				foreach(e in r) {
					places.push(e[0]);
				}
			}*/
			/*
			foreach(vtValue in vtValues) {
				local vehicleType = vtValue.vehicleType;
				foreach(place in places) {
					if(!place.CanUseNewRoute(cargo, vehicleType)) {
						//HgLog.Warning("!CanUseNewRoute place:"+place.GetName()+" cargo:"+AICargo.GetName(cargo));
						continue;
					}
					if(Place.IsNgPlace(place, cargo, vehicleType)) {
						continue;
					}
					if(vehicleType == AIVehicle.VT_AIR && !place.CanBuildAirport(minimumAiportType, cargo)) {
						continue;
					}
					
					local production = place.GetFutureExpectedProduction(cargo,vehicleType);
					if(production > 0) {
						if(!stockpiled) {
							foreach(acceptingCargo in place.GetAccepting().GetCargos()) {
								local s = place.GetStockpiledCargo(acceptingCargo);
								if(s>0) {
									stockpiled = true;
									break;
									//HgLog.Info("GetStockpiledCargo:"+AICargo.GetName(cargo)+" "+s+" "+place.GetName());	
								}
							}
						}
						production = min(production,1000);
						if(place.IsProcessing()) {
							production += place.GetLastMonthProduction(cargo); //既に生産している工場は検索対象になりやすくする
						}
						cargoResult.push({
							cargo = cargo,
							place = place,
							production = production,
							maxValue = vtValue.maxValue,
							score = roiBase ? vtValue.maxValue * 1000 + production : vtValue.maxValue / 100 * production
						});
					}
				}
			}*/
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
		local maxDistance = placeInfo.rawin("maxDistance") ? placeInfo.maxDistance : 2000;
		if(!placeInfo.rawin("vtPlaces")) {
			placeInfo.rawset("vtPlaces",{});
		}
		local vtPlaces = placeInfo.vtPlaces;
		local orgTile = orgPlace.GetLocation();
		local orgPlaceAcceptingRaw = orgPlace.IsAccepting() && orgPlace.IsRaw();
		local orgPlaceTraits = orgPlace.GetIndustryTraits();
		local orgPlaceProductionTable = {};
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		local isNgAir = !orgPlace.CanBuildAirport(minimumAiportType, cargo);
		//local maxBuildingCost = HogeAI.Get().GetUsableMoney() / 2/*最初期の安全バッファ*/ + HogeAI.Get().GetQuarterlyIncome();
		
		local maxCandidates = maxResult == null ? 0 : maxResult * 2;
		if(CargoUtils.IsPaxOrMail(cargo)) {
			maxCandidates *= 8; // valueが対向サイズに影響するので多めに見る
		}
		
		local candidates = [];
		local candidateCount = 0
		local checkCount = 0;
		
		local places;
		local placeList ;
		if(placeInfo.rawin("placesList")) {
			local placesList = placeInfo.placesList;
			places = placesList[0];
			placeList = ListUtils.Clone(placesList[1]);
		} else {
			places = placeInfo.places;
			placeList = AIList();
			foreach(i,_ in places) {
				placeList.AddItem(i,0);
			}
		}
		local distancePlaces = {};
		placeList.Valuate(function(placeIndex):(places,orgTile,distancePlaces) {
			local place = places[placeIndex];
			local d = AIMap.DistanceManhattan(orgTile, place.GetLocation()) / 10;
			local distanceIndex = HogeAI.distanceSampleIndex[min(d,HogeAI.distanceSampleIndex.len()-1)];
			//  HogeAI.GetEstimateDistanceIndex( AIMap.DistanceManhattan(orgTile, place.GetLocation()) );
			local dplaces;
			if(distancePlaces.rawin(distanceIndex)) {
				dplaces = distancePlaces[distanceIndex];
			} else {
				dplaces = [];
				distancePlaces.rawset(distanceIndex, dplaces);
			}
			dplaces.push(place);
			return 0;
		});
		/*
		local distancePlaces = {};
		foreach(placeIndex, distanceIndex in placeList) {
			local dplaces;
			if(distancePlaces.rawin(distanceIndex)) {
				dplaces = distancePlaces[distanceIndex];
			} else {
				dplaces = [];
				distancePlaces.rawset(distanceIndex, dplaces);
			}
			dplaces.push(places[placeIndex]);
		}*/
		
		foreach( vtDistanceValue in cargoVtDistanceValues[cargo] ) {
			local vt = vtDistanceValue[0];
			local distanceIndex = vtDistanceValue[1];
			if(!distancePlaces.rawin(distanceIndex)) {
				continue;
			}
			local routeClass = Route.GetRouteClassFromVehicleType(vt);
			if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, routeClass.GetVehicleType()) >= routeClass.GetMaxTotalVehicles()) {
				continue;
			}
			foreach(place in distancePlaces[distanceIndex]) {
			
				local vtPlaceKey = vt+"-"+place.Id();
				local p;
				if(vtPlaces.rawin(vtPlaceKey)) {
					p = vtPlaces[vtPlaceKey];
				} else {
					p = {place = place};
					vtPlaces.rawset(vtPlaceKey,p);
				}
				local t = clone p;
				t.distance <- AIMap.DistanceManhattan(place.GetLocation(),orgTile);
				if(t.distance == 0) { // はじかないとSearchAndBuildToMeetSrcDemandMin経由で無限ループする事がある
					continue;
				}
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
					if(!WaterRoute.CanBuild(orgPlace,  t.place, cargo)) { // 距離と収益性だけで候補を選ぶと、どことも接続できない事がある。
						continue;
					}
				}
				if(Place.IsNgPathFindPair(orgPlace, t.place, vt)) {
					continue;
				}
				if(Place.IsNgPlace(orgPlace, cargo, vt) || Place.IsNgPlace(t.place, cargo, vt)) {
					continue;
				}
				if(t.place.IsProducing() && !PlaceDictionary.Get().CanUseAsSource(t.place,cargo)) {
					continue;
				}
				
				checkCount ++;
				local srcPlace = orgPlace.IsProducing() ? orgPlace : t.place;
				local destPlace = orgPlace.IsProducing() ? t.place : orgPlace;
				local placeProduction;
				if(!p.rawin("production")) {
					if(options.rawin("useLastMonthProduction")) {
						placeProduction = p.place.GetProducing().GetLastMonthProduction(cargo);
					} else {
						placeProduction = p.place.GetProducing().GetExpectedProduction(cargo, vt);
					}
					p.production <- placeProduction;
				} else {
					placeProduction = p.production;
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
				
				local isBidirectional = orgPlace.IsAcceptingAndProducing(cargo) && t.place.IsAcceptingAndProducing(cargo);
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
				local pathDistance;
				if(vt == AIVehicle.VT_AIR) {
					local p1 = orgPlace.GetLocation();
					local p2 = t.place.GetLocation();
					local w = abs(AIMap.GetTileX(p1) - AIMap.GetTileX(p2));
					local h = abs(AIMap.GetTileY(p1) - AIMap.GetTileY(p2));
					pathDistance = (min(w,h).tofloat() * 0.414 + max(w,h)).tointeger();
				} else {
					pathDistance = t.distance;
				}
				local infrastractureTypes = routeClass.GetSuitableInfrastractureTypes(orgPlace, t.place, cargo);
				local estimateProduction = production;
				/* 家畜と穀物だって運べるif(vt == AIVehicle.VT_RAIL && orgPlace instanceof TownCargo && t.place instanceof TownCargo) {
					estimateProduction *= 2; // 郵便と旅客を同時に運べる TODO: 本当の値はEstimateをマルチカーゴに対応させる必要がある
				}*/
				

				local estimate = Route.Estimate( vt, cargo, pathDistance, estimateProduction, isBidirectional, infrastractureTypes );
				
				if(estimate != null) { // TODO: Estimate()はマイナスの場合も結果を返すべき
					estimate = clone estimate;
					estimate.EstimateAdditional( destPlace, srcPlace, infrastractureTypes );
				}
				
				if(estimate != null && estimate.value > 0 /*&& estimate.buildingCost <= maxBuildingCost Estimate内ではじいている*/) {

				
					t.vehicleType <- vt;
					t.score <- estimate.value;
					t.estimate <- estimate;
					if(vt == AIVehicle.VT_AIR && cargo == HogeAI.GetPassengerCargo() && orgPlace instanceof TownCargo && t.place instanceof TownCargo) {
						t.score = t.score * 13 / 10; // 郵便がひっついてくる分
					}
					t.production <- production;
					
					if(vt == AIVehicle.VT_AIR && pathDistance != 0) {
						t.score = t.score * t.distance / pathDistance;
					}
					
					/*
					if (considerSlope && (vt == AIVehicle.VT_RAIL || vt == AIVehicle.VT_ROAD)) {
						t.score = t.score * 3 / (3 + max( AITile.GetMaxHeight(route.destPlace.GetLocation()) - AITile.GetMaxHeight(route.place.GetLocation()) , 0 ));
					}*/
				
					if(ecs && t.place.IsAccepting() && t.place.IsEcsHardNewRouteDest(cargo)) {
						t.score /= 2;
					}
				
					candidates.push(t);
					candidateCount ++;
					if(maxCandidates != 0 && candidateCount >= maxCandidates) {
						break;
					}
				}
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
				if(!WaterRoute.CanBuild(orgPlace, candidate.place, cargo)) {
					continue;
				}
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
		
		HgLog.Info("CreateRouteCandidates:" + orgPlace.GetName() + " cargo:"+AICargo.GetName(cargo) + " result:"+result.len()+"/"+candidates.len()+"/"+places.len());
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
			routes = Route.GetAllRoutes();
		}
		local result = [];
		foreach(route in routes) {
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
				if(t.vehicleType == AIVehicle.VT_WATER && !WaterRoute.CanBuild(t.src, t.dest, t.cargo)) {
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
		local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
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
			foreach(data in Place.SearchSrcAdditionalPlaces( 
					hgStation, finalDestLocation, 
					cargo, minDistance, maxDistance, minProduction, vehicleType)) {
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
			//HgLog.Warning("DoRoutePlans plan:"+plan.estimate.value+"/"+limitValue+" "+plan.dest.GetName()+"<-"+plan.src.GetName()+" "+plan.estimate);
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
				//HgLog.Warning("DoRoutePlans:"+routePlans.Count()+" delivale:"+delivable+" sumDelivable:"+sumDelivable+" limit:"+limit.capacity+" newRoute:"+newRoute);
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
				local routeClass = Route.GetRouteClassFromVehicleType(destCandidate.vehicleType);
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
					{placesList = Place.GetCargoProducingList( cargo ), maxDistance = maxDistance}, additionalProduction, maxResult, options)) {
				local routePlan = {};
			
				local routeClass = Route.GetRouteClassFromVehicleType(srcCandidate.vehicleType);
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
					{places=Place.GetCargoAccepting(cargo).array}, additionalProduction, maxResult, options)) {
				local routePlan = {};
				local routeClass = Route.GetRouteClassFromVehicleType(destCandidate.vehicleType);
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
	

	function BuildRouteAndAdditional(destPlaceOrStationGroup,srcPlace,cargo,options={}) {
		local route = BuildRoute(destPlaceOrStationGroup, srcPlace, cargo, options);
		if(route == false) {
			return null;
		}
		if(route == null) {
			Place.AddNgPathFindPair(srcPlace,destPlaceOrStationGroup,AIVehicle.VT_RAIL);
			return null;
		}
		//SearchAndBuildAdditionalDest(route); placeを満たすために作成されている事がある
		return route;
	}
	
	// 戻り値: TrainRoute 失敗はnull, 一時的失敗はfalseを返す
	function BuildRoute(dest, src, cargo, options) {
		local distance = AIMap.DistanceManhattan(src.GetLocation(), dest.GetLocation());
		local isTransfer = options.rawin("transfer") ? options.transfer : (dest instanceof StationGroup);
		local isSingleOrNot = (options.rawin("notUseSingle") && options.notUseSingle) || (src instanceof Place && src.IsProcessing()) ? false : null;
		local explain = (isTransfer ? "T:" : "") + dest.GetName()+"<-"+src.GetName()+"["+AICargo.GetName(cargo)+"] distance:"+distance;
		//HgLog.Info("# TrainRoute: Try BuildRoute: "+explain);

		
		
		local aiExecMode = AIExecMode();
		
		local subCargos = [];
		local isBidirectional = false;
		local cargoProduction = {};
		cargoProduction[cargo] <- max(50,src.GetFutureExpectedProduction(cargo, AIVehicle.VT_RAIL));
		if(dest instanceof Place && src instanceof Place) { //TODO: stationgroupの場合
			foreach(c in src.GetProducingCargos()) {
				if(c != cargo && dest.IsCargoAccepted(c)) {
					cargoProduction[c] <- src.GetFutureExpectedProduction(c, AIVehicle.VT_RAIL);
				}
			}
			isBidirectional = dest.IsAcceptingAndProducing(cargo) && src.IsAcceptingAndProducing(cargo);
		}
		
		local trainEstimator = TrainEstimator();
		trainEstimator.cargo = cargo;
		trainEstimator.isSingleOrNot = isSingleOrNot; //srcが工場の場合、後から生産量が増加する可能性が高いので複線のみにしておく
		trainEstimator.cargoProduction = cargoProduction;
		trainEstimator.distance = distance;
		trainEstimator.checkRailType = true;
		trainEstimator.isRoRo = !isTransfer;
		trainEstimator.isBidirectional = isBidirectional;
		if(options.rawin("destRoute") && options.destRoute != null) {
			trainEstimator.SetDestRoute( options.destRoute, dest, src );
		}
		if(src instanceof StationGroup) {
			trainEstimator.cargoIsTransfered[cargo] <- true;
		}
		local engineSets = trainEstimator.GetEngineSetsOrder();
		/*
		foreach(engineSet in engineSets) {
			HgLog.Info(engineSet.GetTrainString());
		}*/
		
		if(engineSets.len()==0) {
			if(trainEstimator.tooShortMoney == true) {
				HgLog.Info("TrainRoute: tooShortMoney "+explain);
				return false;
			}
			HgLog.Info("TrainRoute: Not found enigneSet "+explain);
			return null;
		}
		HgLog.Info("TrainRoute railType:"+AIRail.GetName(engineSets[0].railType));
		HgLog.Info("AIRail.GetMaintenanceCostFactor:"+AIRail.GetMaintenanceCostFactor(engineSets[0].railType));	
		AIRail.SetCurrentRailType(engineSets[0].railType);
		
		local destTile = null;
		local destHgStation = null;
		destTile = dest.GetLocation();
		local useSingle = engineSets[0].isSingle; //HogeAI.Get().GetUsableMoney() < HogeAI.Get().GetInflatedMoney(100000) && !HogeAI.Get().HasIncome(20000);
		local destStationFactory = TerminalStationFactory();
		destStationFactory.distance = distance;
		destStationFactory.useSingle = useSingle;
		if(dest instanceof Place) {
			local destPlace = dest;
			if(destPlace.GetProducing().IsTreatCargo(cargo)) { // bidirectional
				destPlace = destPlace.GetProducing();
			}
			destHgStation = destStationFactory.CreateBest(destPlace, cargo, src.GetLocation());
		} else  {
			destStationFactory.useSimple = true;
			destHgStation = destStationFactory.CreateBest( dest, cargo, src.GetLocation() );
		}

		if(destHgStation == null) {
			HgLog.Warning("TrainRoute: No destStation."+explain);
			Place.AddNgPlace(dest, cargo, AIVehicle.VT_RAIL);
			return null;
		}
		
		local srcStatoinFactory = SrcRailStationFactory();
		srcStatoinFactory.platformLength = destHgStation.platformLength;
		srcStatoinFactory.useSimple = destStationFactory.useSimple;
		srcStatoinFactory.useSingle = useSingle;
		local srcHgStation = srcStatoinFactory.CreateBest(src, cargo, destTile);
		if(srcHgStation == null) {
			HgLog.Warning("TrainRoute: No srcStation."+explain);
			Place.AddNgPlace(src, cargo, AIVehicle.VT_RAIL);
			return null;
		}

		srcHgStation.cargo = cargo;
		srcHgStation.isSourceStation = true;
		if(!srcHgStation.BuildExec()) { //TODO予約だけしておいて後から駅を作る
			HgLog.Warning("TrainRoute: srcHgStation.BuildExec failed. platform:"+srcHgStation.GetPlatformRectangle()+" "+explain);
			return null;
		}
		destHgStation.cargo = cargo;
		destHgStation.isSourceStation = false;
		if(!destHgStation.BuildExec()) {
			srcHgStation.Remove();
			HgLog.Warning("TrainRoute: destHgStation.BuildExec failed. platform:"+destHgStation.GetPlatformRectangle()+" "+explain);
			return null;
		}
		local pathfinding = Pathfinding();
		if(src instanceof HgIndustry) {
			pathfinding.industries.push(src.industry);
		}
		if(dest instanceof HgIndustry) {
			pathfinding.industries.push(dest.industry);
		}
		this.pathfindings.rawset(pathfinding,0);
		local railBuilder;
		local adjustedPathFindLimit = !HasIncome(10000) && !IsRich() ? pathFindLimit * 3 : pathFindLimit;
		if(useSingle) {
			railBuilder = SingleStationRailBuilder(srcHgStation, destHgStation, adjustedPathFindLimit, pathfinding);
		} else {
			railBuilder = TwoWayStationRailBuilder(srcHgStation, destHgStation, adjustedPathFindLimit, pathfinding);
		}
		railBuilder.engine = engineSets[0].engine;
		railBuilder.cargo = cargo;
		railBuilder.platformLength = destHgStation.platformLength;
		railBuilder.distance = distance;
		if(!useSingle && dest instanceof Place) {
			if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
				railBuilder.isBuildDepotsDestToSrc = true;
			} else {
				railBuilder.isBuildSingleDepotDestToSrc = true;
			}
		}
		local isSuccess = railBuilder.Build();
		this.pathfindings.rawdelete(pathfinding);
		if(!isSuccess) {
			HgLog.Warning("TrainRoute: railBuilder.Build failed."+explain);
			HgStation.AddNgStationTile(srcHgStation); // stationの場所が悪くて失敗する事が割とある
			HgStation.AddNgStationTile(destHgStation);
			srcHgStation.Remove();
			destHgStation.Remove();
			
			return null;
		}
		if(srcHgStation.stationGroup == null || destHgStation.stationGroup == null) {
			HgLog.Warning("TrainRoute: station was removed."+explain); // 稀に建設中に他ルートの削除と重なって駅が削除される事がある
			return null;
		}
		
		
		local route
		if(useSingle) {
			route = TrainRoute(
				TrainRoute.RT_ROOT, cargo,
				srcHgStation, destHgStation,
				railBuilder.buildedPath, null);
		} else {
			route = TrainRoute(
				TrainRoute.RT_ROOT, cargo,
				srcHgStation, destHgStation,
				railBuilder.buildedPath1, railBuilder.buildedPath2);
		}
		route.isTransfer = isTransfer;
		route.AddDepots(railBuilder.depots);
		route.Initialize();

		destHgStation.BuildAfter();
		if(!route.BuildFirstTrain()) {
			HgLog.Warning("TrainRoute: BuildFirstTrain failed."+route);
			route.Demolish();
			return null;
		}
		if(route.latestEngineSet != null && route.latestEngineSet.vehiclesPerRoute >= 2) {
			route.CloneAndStartTrain();
		}
		
		HgLog.Info("TrainRoute pathDistance:"+route.pathDistance+" distance:"+route.GetDistance()+" "+route);

		TrainRoute.instances.push(route);
		PlaceDictionary.Get().AddRoute(route);
		
		if(CargoUtils.IsPaxOrMail(cargo)) {
			CommonRouteBuilder.CheckTownTransfer(route, srcHgStation);
			CommonRouteBuilder.CheckTownTransfer(route, destHgStation);
		}
		//route.CloneAndStartTrain();
		
		//HgLog.Info("# TrainRoute: BuildRoute succeeded: "+route);
		return route;
	}

	function SearchAndBuildAdditionalDestAsFarAsPossible(route) {
		if(roiBase) {
			return null;
		}
		local result = false;
		while(SearchAndBuildAdditionalDest(route, result) != null) {
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
		local maxDistance = 0;
		if(route.IsClosed()) {
			maxDistance = 500;
		} else {
			local currentValue = 0;//route.latestEngineSet.income;
			for(local distance = 0; distance <= 500; distance += 100) {
				local engineSets = route.GetEngineSets(false, distance);
				local estimate = engineSets.len() >= 1 ? engineSets[0] : null;
			
//				estimate = Route.Estimate(AIVehicle.VT_RAIL, route.cargo, route.GetDistance() + distance, route.GetProduction(), route.IsBiDirectional());
				if(estimate == null) {
					break;
				}
				HgLog.Info("AdditionalDest distance:"+(distance+route.GetDistance())+" "+estimate);
				local score = estimate.routeIncome; // 比較元は建築済みなのでbuildingTimeは加味しない
				if(score < currentValue) {
					break;
				}
				currentValue = score;
				maxDistance = distance;
			}
			
			if(!continuation && maxDistance < route.GetDistance() * 5 / 10) {
				HgLog.Warning("No need to extend route "+route);
				return null;
			}
			
			if(maxDistance <= 0) { // transfer分も加味 TODO: まじめに計算
				HgLog.Warning("No need to extend route "+route);
				return null;
			}
//			maxDistance -= 100;
			HgLog.Info("SearchAndBuildAdditionalDest maxDistance:"+maxDistance+" "+route);
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
				route.GetUsableCargos(), route.GetSrcStationTiles(), destHgStation.platformTile, maxDistance)) {
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
				cargoDistance * 100 / (buildingDistance + 250), route.GetLatestEngineSet().engine, forkPoint, placeLocation );
			placeScores.push(placeScore);
			DoInterval();
		}
		
		placeScores.sort(function(a,b) {
			return b[1] - a[1];
		});
		
		foreach(placeScore in placeScores) {
			DoInterval();
			HgLog.Info("Found an additional accepting place:"+placeScore[0].GetName()+" route:"+route);
			local result = BuildDestRouteAdditional(route,placeScore[0]);
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

	function BuildDestRouteAdditional(route, additionalPlace) {
		HgLog.Info("# TrainRoute: Try BuildDestRouteAdditional:"+additionalPlace.GetName()+" route: "+route);
		AIRail.SetCurrentRailType(route.GetRailType());
		if(additionalPlace.GetProducing().IsTreatCargo(route.cargo)) {
			additionalPlace = additionalPlace.GetProducing();
		}
		local stationFactory = TerminalStationFactory();
		stationFactory.platformLength = route.srcHgStation.platformLength;
		stationFactory.minPlatformLength = route.GetPlatformLength();
		if(CargoUtils.IsPaxOrMail(route.cargo)) {
			stationFactory.platformNum = 3;
		}
		local additionalHgStation = stationFactory.CreateBest(additionalPlace, route.cargo, route.destHgStation.platformTile);
		if(additionalHgStation == null) {
			HgLog.Info("TrainRoute: cannot build additional station");
			return 1;
		}

		local aiExecMode = AIExecMode();

		additionalHgStation.cargo = route.cargo;
		additionalHgStation.isSourceStation = false;
		if(!additionalHgStation.BuildExec()) {
			return 1;
		}
		
		local railBuilder = TwoWayPathToStationRailBuilder(
			GetterFunction( function():(route) {
				return route.GetTakeAllPathSrcToDest();
			}),
			GetterFunction( function():(route) {
				return route.GetTakeAllPathDestToSrc().Reverse();
			}),
			additionalHgStation, pathFindLimit, this);
			
		railBuilder.engine = route.GetLatestEngineSet().engine;
		railBuilder.cargo = route.cargo;
		railBuilder.platformLength = route.GetPlatformLength();
		railBuilder.distance = AIMap.DistanceManhattan(additionalPlace.GetLocation(), route.destHgStation.GetLocation());
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			railBuilder.isBuildDepotsDestToSrc = true;
		} else {
			railBuilder.isBuildSingleDepotDestToSrc = true;
		}
		if(!railBuilder.Build()) {
			HgLog.Warning("TrainRoute: railBuilder.Build failed.");
			additionalHgStation.Remove();
			return 2;
		}
		if(additionalHgStation.stationGroup == null) {
			HgLog.Warning("TrainRoute: additionalHgStation was removed."); // 稀に建設中に他ルートの削除と重なって駅が削除される事がある
			return 1;
		}
		
		route.AddDepots(railBuilder.depots);
		if(route.GetLastRoute().returnRoute != null) {
			route.GetLastRoute().RemoveReturnRoute(); // dest追加でreturn routeが成立しなくなる場合があるため。
		}
		
		local oldDestStation = route.destHgStation;
		if(route.GetFinalDestPlace() != null) {
			Place.SetRemovedDestPlace(route.GetFinalDestPlace());
		}
		additionalHgStation.BuildAfter();

		local removeRemain1 = route.pathSrcToDest.CombineByFork(railBuilder.buildedPath1, false);
		local removeRemain2 = route.pathDestToSrc.CombineByFork(railBuilder.buildedPath2, true);
		
		local removePath1 = removeRemain1[0];
		local removePath2 = removeRemain2[0];
		
		route.pathSrcToDest = removeRemain1[1];
		route.pathDestToSrc = removeRemain2[1];
		
		oldDestStation.RemoveDepots();
		
		
		route.AddDestination(additionalHgStation);
		route.AddForkPath(BuildedPath(removePath1)); // ConvertRail用
		route.AddForkPath(BuildedPath(removePath2)); 

		/* destがcloseしたときに再利用されるので削除しない
		DelayCommandExecuter.Get().Post(300,function():(removePath1,removePath2,oldDestStation) { //TODO: save/loadに非対応
			removePath1.RemoveRails();
			removePath2.RemoveRails();
			oldDestStation.Remove();
		});
		*/
		
		/*
		route.AddAdditionalTiles(removePath1.GetTiles());
		route.AddAdditionalTiles(removePath2.GetTiles());*/
		
		
		HgLog.Info("# TrainRoute: BuildDestRouteAdditional succeeded: "+route);
		return 0;
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
				return BuildReturnRoute(route,pair[0],pair[1],limitValue);
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
		local checkPointsStart = path.GetCheckPoints(32,3);
		local checkPointsEnd = path.Reverse().GetCheckPoints(32,3);
		local startTile = path.GetTile();
		local lastTile = path.GetLastTile();
		local totalLength = AIMap.DistanceManhattan(startTile, lastTile);

		local srcPlacesList = Place.GetNotUsedProducingPlacesList( cargo );
		local places = srcPlacesList[0];
		local list = srcPlacesList[1];
		local srcPlaces = [];
		list.Valuate(function(i):(places,srcPlaces){
			srcPlaces.push(places[i]);
			return 0;
		});
		// TODO: 大きなマップだと重い
		local srces = HgArray(srcPlaces).Map(function(place):(cargo) {
			return {
				place = place
				production = place.GetExpectedProduction(cargo, AIVehicle.VT_RAIL)
			}
		}).Filter(function(t) {
			return t.production >= 50;
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
		
		local dests = Place.GetCargoAccepting(cargo).Map(function(place) : (checkPointsStart) {
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
	
	function BuildReturnRoute(route, srcPlace, destPlace, limitValue=null) {
		//TODO 後半は駅作成失敗が多くなるので、先に駅が建てられるかを調べる。ルート検索はコストが重いので最後に
		HgLog.Info("# TrainRoute: Try BuildReturnRoute:"+destPlace.GetName()+"<-"+srcPlace.GetName()+" route: "+route);
		local value = limitValue != null ? limitValue : route.GetLatestEngineSet().value;
		local testMode = AITestMode();
		local needRollbacks = [];
		local railStationCoverage = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local returnPath = route.GetPathAllDestToSrc();
		local transferStation = GetBuildableStationByPath(returnPath, srcPlace!=null ? srcPlace.GetLocation() : null, route.cargo, route.GetPlatformLength());
		if(transferStation == null) {
			HgLog.Info("TrainRoute: cannot build transfer station");
			return null;
		}
		AIRail.SetCurrentRailType(route.GetRailType());

		local railBuilderTransferToPath;
		local railBuilderPathToTransfer;
		{
			//TODO 失敗時のロールバック
			local aiExecMode = AIExecMode();
			if(!transferStation.BuildExec()) {
				// TODO Place.AddNgPlace();
				HgLog.Warning("TrainRoute: cannot build transfer station "+HgTile(transferStation.platformTile)+" "+transferStation.stationDirection);
				return null;
			}
			needRollbacks.push(transferStation);
			

			
			railBuilderTransferToPath = TailedRailBuilder.PathToStation(GetterFunction( function():(route) {
				local returnPath = route.GetPathAllDestToSrc();
				return returnPath.SubPathEnd(returnPath.GetLastTileAt(4)).Reverse();
			}), transferStation, 150, this, null, false);
			railBuilderTransferToPath.engine = route.GetLatestEngineSet().engine;
			railBuilderTransferToPath.cargo = route.cargo;
			railBuilderTransferToPath.platformLength = route.GetPlatformLength();
			railBuilderTransferToPath.isReverse = true;
			railBuilderTransferToPath.isTwoway = false;
			if(!railBuilderTransferToPath.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderTransferToPath");
				Rollback(needRollbacks);
				return null;
			}
			
			needRollbacks.push(railBuilderTransferToPath.buildedPath); // TODO Rollback時に元の線路も一緒に消える事がある。limit date:300の時に消えている
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			railBuilderPathToTransfer = TailedRailBuilder.PathToStation(GetterFunction( function():(route, pointTile) {
				return route.GetPathAllDestToSrc().SubPathStart(pointTile);
			}), transferStation, 150, this);
			railBuilderPathToTransfer.engine = route.GetLatestEngineSet().engine;
			railBuilderPathToTransfer.cargo = route.cargo;
			railBuilderPathToTransfer.platformLength = route.GetPlatformLength();
			railBuilderPathToTransfer.isTwoway = false;
			
			if(!railBuilderPathToTransfer.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderPathToTransfer");
				Rollback(needRollbacks);
				return null;
			}
			
			needRollbacks.push(railBuilderPathToTransfer.buildedPath);
			
		}

		
		{
			local returnDestStationFactory = TerminalStationFactory();
			returnDestStationFactory.platformLength = route.GetPlatformLength();
			returnDestStationFactory.minPlatformLength = route.GetPlatformLength();
			
			local returnDestStation = returnDestStationFactory.CreateBest(destPlace, route.cargo, transferStation.platformTile, false);
				// station groupを使うと同一路線の他のreturnと競合して列車が迷子になる事がある
			if(returnDestStation == null) {
				HgLog.Warning("TrainRoute:cannot build returnDestStation");
				Rollback(needRollbacks);
				return null;
			}
				
			local aiExecMode = AIExecMode();
			returnDestStation.cargo = route.cargo;
			returnDestStation.isSourceStation = false;
			if(!returnDestStation.BuildExec()) {
				HgLog.Warning("TrainRoute: cannot build returnDestStation");
				Rollback(needRollbacks); // TODO: 稀にtransfer station側に列車が紛れ込んでいてrouteが死ぬ時がある。(正規ルート側にdouble depotがあるケース？）
				return null;
			}
			needRollbacks.push(returnDestStation);
			
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			local railBuilderReturnDest = TwoWayPathToStationRailBuilder();
			railBuilderReturnDest.pathDepatureGetter = GetterFunction( function():(route, railBuilderTransferToPath) {
					return route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile()).Reverse();
				});
			railBuilderReturnDest.pathArrivalGetter = GetterFunction( function():(route, pointTile, railBuilderReturnDest) {
					local pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(pointTile);
					return pathForReturnDest.SubPathStart(railBuilderReturnDest.buildedPath1.path.GetFirstTile()); // TODO: railBuilderReturnDestDepartureと分岐点がクロスする事がある
				});
			railBuilderReturnDest.isReverse = true;
			railBuilderReturnDest.destHgStation = returnDestStation;
			railBuilderReturnDest.limitCount = 150;
			railBuilderReturnDest.eventPoller = this;
			railBuilderReturnDest.cargo = route.cargo;
			railBuilderReturnDest.platformLength = route.GetPlatformLength();
			railBuilderReturnDest.distance = AIMap.DistanceManhattan(returnDestStation.GetLocation(), route.srcHgStation.GetLocation());
			if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
				railBuilderReturnDest.isBuildDepotsDestToSrc = true;
			}
			if(!railBuilderReturnDest.Build()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderReturnDestDeparture");
				Rollback(needRollbacks);
				return null;
			}
			

			local returnRoute = TrainReturnRoute(route, transferStation, returnDestStation, 
				railBuilderPathToTransfer.buildedPath, railBuilderTransferToPath.buildedPath,
				railBuilderReturnDest.buildedPath1, railBuilderReturnDest.buildedPath2);
				
			returnRoute.AddDepots( railBuilderReturnDest.depots );

		
			/*
			local railBuilderReturnDestDeparture = TailedRailBuilder.PathToStation(GetterFunction( function():(route, railBuilderTransferToPath) {
				return route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile()).Reverse();
			}), returnDestStation,  150, this, null, false);
			railBuilderReturnDestDeparture.engine = route.GetLatestEngineSet().engine;
			railBuilderReturnDestDeparture.cargo = route.cargo;
			railBuilderReturnDestDeparture.platformLength = route.GetPlatformLength();
			railBuilderReturnDestDeparture.isReverse = true;
			if(!railBuilderReturnDestDeparture.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderReturnDestDeparture");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(railBuilderReturnDestDeparture.buildedPath);
			
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			local railBuilderReturnDestArrival = TailedRailBuilder.PathToStation(GetterFunction( function():(route, pointTile, railBuilderReturnDestDeparture) {
				local pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(pointTile);
				return pathForReturnDest.SubPathStart(railBuilderReturnDestDeparture.buildedPath.path.GetFirstTile()); // TODO: railBuilderReturnDestDepartureと分岐点がクロスする事がある
			}), returnDestStation, 150, this);
			railBuilderReturnDestArrival.engine = route.GetLatestEngineSet().engine;
			railBuilderReturnDestArrival.cargo = route.cargo;
			railBuilderReturnDestArrival.platformLength = route.GetPlatformLength();
			
			if(!railBuilderReturnDestArrival.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderReturnDestArrival");
				Rollback(needRollbacks);
				return false;
			}
			
			needRollbacks.push(railBuilderReturnDestArrival.buildedPath);
			
			if(transferStation.stationGroup==null || returnDestStation.stationGroup==null) {
				HgLog.Warning("TrainRoute: station was removed."); // 稀に建設中に他ルートの削除と重なって駅が削除される事がある
				Rollback(needRollbacks);
				return false;
			}
			
			local aiExecMode = AIExecMode();

			local returnRoute = TrainReturnRoute(route, transferStation, returnDestStation, 
				railBuilderPathToTransfer.buildedPath, railBuilderTransferToPath.buildedPath,
				railBuilderReturnDestArrival.buildedPath, railBuilderReturnDestDeparture.buildedPath);*/
				
			route.returnRoute = returnRoute;
			route.Save();
			returnRoute.Initialize();
			
			PlaceDictionary.Get().AddRoute(returnRoute);
			

			route.slopesTable.clear(); // TODO: ChangeDestinationと同様、登れるのかの再確認が必要
			route.AddReturnTransferOrder(transferStation, returnDestStation);
			
			/* SearchAndBuildToMeetSrcDemandTransferの中でやる
			if(srcPlace.IsProcessing() && srcPlace.GetLastMonthProduction(route.cargo) < srcPlace.GetExpectedProduction(route.cargo, AIVehicle.VT_RAIL)) {
				if(transferStation.place != srcPlace) {
					BuildRoute(transferStation.stationGroup, srcPlace, returnRoute.cargo);
				}
				SearchAndBuildToMeetSrcDemandMin(srcPlace, returnRoute);
			}*/
			
			/*scan placeでやる
			local cargoLimit = {};
			local cargoRoutePlans = {};
			foreach(cargo in route.GetCargos()) {
				cargoLimit.rawset( cargo, route.GetCurrentRouteCapacity(cargo) );
				cargoRoutePlans.rawset( cargo, HogeAI.Get().GetSortedRoutePlans([]) );
				HgLog.Info("return route cargo limit:"+cargoLimit[cargo]+"["+AICargo.GetName(cargo)+"] "+returnRoute);
			}
			
			if(transferStation.place != null) {;
				foreach(cargo in transferStation.place.GetProducingCargos()) {
					if( !cargoLimit.rawin(cargo) ) {
						continue;
					}
					cargoLimit[cargo] -= transferStation.place.GetLastMonthProduction(cargo);
					if(cargoLimit[cargo] > 0) {
						cargoRoutePlans[cargo].Extend( HogeAI.Get().GetMeetPlacePlans( transferStation.place, returnRoute ) );
					}
				}
			}
			local plans = HogeAI.Get().GetTransferCandidates( returnRoute );
			plans.sort(function(a,b) { return b.estimate.value - a.estimate.value; });
			
			foreach( plan in plans ) {
				if( cargoLimit.rawin(plan.cargo) && cargoLimit[plan.cargo] > 0 ) {
					if(cargoRoutePlans[plan.cargo].Count() == 0 || plan.src.GetLastMonthProduction(plan.cargo) >= 1) {
						cargoRoutePlans[plan.cargo].Extend([plan]); // 無生産施設しか無い場合は1つだけ許可する(TODO: 複数ある場合は最もvalueが高いplaceにすべきかもしれない)
					}
				}
			}

			local procrastinatePaxMail = {}
			foreach(cargo, limit in cargoLimit) {
				if(limit > 0) {
					if(CargoUtils.IsPaxOrMail(cargo)) {
						procrastinatePaxMail.rawset(cargo, limit / 2);
						continue;
					}
					DoRoutePlans( cargoRoutePlans[cargo], { capacity = limit , value = value },
						{ routePlans = cargoRoutePlans[cargo], noDoRoutePlans = true }); // TODO: 時間などの敷居が必要かもしれない
				}
			}
			foreach(cargo, limit in procrastinatePaxMail) {
				DoRoutePlans( cargoRoutePlans[cargo], { capacity = limit , value = value },
					{ routePlans = cargoRoutePlans[cargo], noDoRoutePlans = true });
			}*/
		
			//SearchAndBuildTransferRoute(returnRoute);

			HgLog.Info("# TrainRoute: build return route succeeded:"+returnRoute);
			return returnRoute;
		}
		
	}
	
	function Rollback(needRollbacks) {
		local aiExecMode = AIExecMode();
		foreach(e in needRollbacks) {
			e.Remove();
		}
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
					
					local tiles = [];
					for(local j=0; j<10; j++) {
						if(HogeAI.IsBuildable(s)) {
							tiles.push(s);
						}
						s = s + d;
					}
//					tiles.reverse();
					local stationD = (forkTiles[1] - forkTiles[0]) / AIMap.DistanceManhattan(forkTiles[1],forkTiles[0]);
					local x = stationFactory.CreateOnTiles(tiles, HgStation.GetStationDirectionFromTileIndex(-stationD));
					
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
		if(AIBase.RandRange(100) < 25 && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > GetInflatedMoney(800000)) {
			local routes = [];
			routes.extend(RoadRoute.instances);
			routes.extend(WaterRoute.instances);
			routes.extend(AirRoute.instances);
			foreach(route in routes) {
				if(!route.NeedsAdditionalProducing()) {
					continue;
				}
				local station = AIStation.GetStationID(route.srcHgStation.platformTile);		
				local town = AIStation.GetNearestTown (station)
				if(!AITown.HasStatue (town)) {
					AITown.PerformTownAction(town,AITown.TOWN_ACTION_BUILD_STATUE );
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= GetInflatedMoney(800000)) {
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
			foreach(dest in CreateRouteCandidates(cargo, place, {places=Place.GetCargoAccepting(cargo).array})) {
				found = true;
				local routeClass = Route.GetRouteClassFromVehicleType(dest.vehicleType);
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
		local times = [];
		local span = max(1,7 / GetDayLengthFactor());
		if(force) {
			while(lastIntervalDate != null && AIDate.GetCurrentDate() < lastIntervalDate + span) {
				AIController.Sleep(10);
			}
		} else if(lastIntervalDate != null && AIDate.GetCurrentDate() < lastIntervalDate + span) {
			return;
		}
		
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
		
		
		AIController.Sleep(1);
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
		
		lastIntervalDate = AIDate.GetCurrentDate();
		
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
					foreach(route in routes /*Route.GetAllRoutes()*/) {
						route.OnIndustoryClose(event.GetIndustryID());
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
		local group = AIVehicle.GetGroupID(vehicle);
		local vehicleType = AIVehicle.GetVehicleType(vehicle);
		HgLog.Warning("ET_VEHICLE_LOST:"+vehicle+" "+AIVehicle.GetName(vehicle)+" vt:"+vehicleType+" group:"+AIGroup.GetName(group));
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("Invalid vehicle");
			return;
		}
		if(vehicleType == AIVehicle.VT_ROAD) {
			foreach(roadRoute in RoadRoute.instances) {
				if(roadRoute.vehicleGroup == group) {
					roadRoute.OnVehicleLost(vehicle);
				}
			}
		} else if(vehicleType == AIVehicle.VT_WATER ) { //TODO: 全vehicleがロストしている場合、路線廃止
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) != 0) {
				HgLog.Warning("ET_VEHICLE_LOST: SendVehicleToDepot");
				AIVehicle.SendVehicleToDepot (vehicle); // 一旦depot行きを解除
				if(AIBase.RandRange(2) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle); // すぐに再開さた方がうまく行くケースもある
				}
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
		local remainOps = AIController.GetOpsTillSuspend();
	
		local table = {};	
		table.turn <- turn;
		table.indexPointer <- indexPointer;
		table.stockpiled <- stockpiled;
		table.estimateTable <- estimateTable;
		table.maybePurchasedLand <- maybePurchasedLand;
		table.landConnectedCache <- HgTile.landConnectedCache;
		table.cargoVtDistanceValues <- cargoVtDistanceValues;
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

/*		remainOps = AIController.GetOpsTillSuspend();

		Airport.SaveStatics(table);

		HgLog.Info("Airport.SaveStatics consume ops:"+(remainOps - AIController.GetOpsTillSuspend()));*/
		return table;
	}

	function Load(version, data) {
		loadData = data;
	}
	
	function DoLoad() {
		if(loadData == null) {
			return;
		}
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
		Place.LoadStatics(loadData);
		HgStation.LoadStatics(loadData);
		TrainInfoDictionary.LoadStatics(loadData);
		TrainRoute.LoadStatics(loadData);		
		RoadRoute.LoadStatics(loadData);
		WaterRoute.LoadStatics(loadData);
		AirRoute.LoadStatics(loadData);
		TownBus.LoadStatics(loadData);
		
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
			HgLog.Warning("WaitForPrice called recursively:"+needMoney+" "+reason);
			return false;
		}
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
				AIController.Sleep(100);
			}
			local minimamLoan = min(AICompany.GetMaxLoanAmount(), 
					AICompany.GetLoanAmount() + needMoney - AICompany.GetBankBalance(AICompany.COMPANY_SELF) + buffer * 2);
			//HgLog.Info("minimamLoan:"+minimamLoan);
			AICompany.SetMinimumLoanAmount(minimamLoan);
		}
		self.waitForPriceStartDate = null;
		return true;
	}
	
	function WaitDays(days) {
		days /= GetDayLengthFactor();
		days = max(days,1);
		HgLog.Info("WaitDays:"+days);
		local d = AIDate.GetCurrentDate() + days;
		while(AIDate.GetCurrentDate() < d) {
			AIController.Sleep(1);		
			DoInterval();
		}
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
		local usableMoney = HogeAI.GetUsableMoney();
		local loanAmount = AICompany.GetLoanAmount();
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
		if(AIGameSettings.GetValue("ai.ai_disable_veh_roadveh")==1 || GetSetting("disable_veh_roadveh")==1) {
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
		canUsePlaceOnWater = HogeAI.Get().CanRemoveWater() || !WaterRoute.IsTooManyVehiclesForNewRoute(WaterRoute);

	}
}
 