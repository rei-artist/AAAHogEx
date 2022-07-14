
require("utils.nut");
require("tile.nut");
require("aystar.nut");
require("pathfinder.nut");
require("roadpathfinder.nut");
require("place.nut");
require("station.nut");
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
	static productionEstimateSamples = [10, 20, 30, 50, 80, 130, 210, 340, 550, 890, 1440, 2330, 3770];

	turn = null;
	indexPointer = null;
	pendings = null;
	stockpiled = null;
		
	maxStationSpread = null;
	maxTrains = null;
	maxRoadVehicle = null;
	maxShips = null;
	maxAircraft = null;
	isUseAirportNoise = null;

	roiBase = null;
	buildingTimeBase = null;
	estimateTable = null;
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
		return false;
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
		if(HogeAI.container.instance != null) {
			HgLog.Error("HogeAI constructor run 2 times");
		}
		HogeAI.container.instance = this;
		turn = 1;
		indexPointer = 0;
		stockpiled = false;
		pathFindLimit = 150;
		supressInterval = false;
		supressInterrupt = false;
		estimateTable = {};
		yeti = false;
		ecs = false;
		firs = false;
		isTimeoutToMeetSrcDemand = false;
		pendings = {};
		pathfindings = {};
		DelayCommandExecuter();
	}
	 
	function Start() {
		HgLog.Info("AAAHogEx Started!");
		
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
		local a = AIList();
		a.AddItem(1,0);
		a.AddItem(2,0);
		foreach(k1,_ in a) {
			foreach(k2,_ in a) {
				HgLog.Info(k1+","+k2);
			}
		}
		
		local a = [1,2]
		foreach(k1 in a) {
			foreach(k2 in a) {
				HgLog.Info(k1+","+k2);
			}
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
			if(name.find("FIRS") != null || name.find("NAIS") != null || name.find("XIS") != null) {
				firs = true;
				HgLog.Info("firs: true");
			}
		}
		
		foreach(objectType,v in AIObjectTypeList()) {
			HgLog.Info("objType:" + AIObjectType.GetName(objectType) + " views:"+AIObjectType.GetViews(objectType)+" id:"+objectType);
		}
		

		DoLoad();
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
			HgLog.Info("name:"+AICargo.GetName(cargo)+" label:"+AICargo.GetCargoLabel(cargo)+
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
		
		foreach(industry,v in AIIndustryList() ) {
			if(AIIndustry.IsBuiltOnWater( industry )) {
				HgLog.Info(AIIndustry.GetName( industry )
					+ " HasDock:"+AIIndustry.HasDock( industry )
					+ " DockLocation:"+HgTile(AIIndustry.GetDockLocation( industry ))
					+ " Location:"+HgTile(AIIndustry.GetLocation(industry)));
			}
		}
		
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
		


		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());

		indexPointer = 3; // ++
		while (true) {
			HgLog.Info("######## turn "+turn+" ########");
			while(indexPointer < 4) {
				AIController.Sleep(1);
				UpdateSettings();
				CalculateProfitModel();
				limitDate = AIDate.GetCurrentDate() + 600;
				ResetEstimateTable();
				Place.canBuildAirportCache.clear();
				
				/*local engineSet = RoadRoute.EstimateEngineSet(RoadRoute, HogeAI.GetPassengerCargo(), 100,  50, true, true );
				RoadBuilder(engineSet.engine).BuildPath([HgTile.XY(273,383).tile], [HgTile.XY(279,391).tile], true);*/
				
				DoInterval();
				DoInterrupt();
				DoStep();
				indexPointer ++;
			}
			indexPointer = 0;
			turn ++;
		}
	}
	
	function CalculateProfitModel() {
		if(!IsRich()) {
			roiBase = true;
			buildingTimeBase = false;
			HgLog.Info("### roiBase");
			return;
		}
		roiBase = false;
		buildingTimeBase = true;
		HgLog.Info("### buildingTimeBase");
		return;
		// 以下廃止。vehicleProfitBaseだと収益がマイナスの時にヘリばかりつくる羽目になる
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
				SearchAndBuildToMeetSrcDemandTransfer();
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
		
		local bests = [];
		local candidate;
		local routeCandidatesGen = GetRouteCandidatesGen();
		local candidateNum = TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute) ? 200 : 200;
		for(local i=0; (candidate=resume routeCandidatesGen) != null && i<candidateNum; i++) {
			bests.push(candidate);
		}
		
		bests.sort(function(a,b) {
			return b.score-a.score; 
		});
		
		//bests = bests.slice(0, min(bests.len(), 50));
		foreach(e in bests) {
			local s = "ScanPlaces.score"+e.score+" production:"+e.production+" value:"+e.estimate.value+" vt:"+e.vehicleType
				+" "+e.destPlace.GetName() + "<-" + e.place.GetName()+" ["+AICargo.GetName(e.cargo)+"] distance:"+e.distance;
			if(e.vehicleType == AIVehicle.VT_AIR) {
				s += " infraType:"+e.infrastractureType;
			}
			HgLog.Info(s);
		}
		
		limitDate = AIDate.GetCurrentDate() + 600;
		local dirtyPlaces = {};
		foreach(t in bests){
			DoInterval();
			if(dirtyPlaces.rawin(t.destPlace.Id()+":"+t.cargo)) { // 同じplaceで競合するのを防ぐ(特にAIRとRAIL)
				continue;
			}
			if(dirtyPlaces.rawin(t.place.Id()+":"+t.cargo)) {
				continue;
			}
			if(!t.place.CanUseNewRoute(t.cargo, t.vehicleType)) {
				continue;
			}
			if(t.destPlace.IsAcceptingAndProducing(t.cargo) && !t.destPlace.GetProducing().CanUseNewRoute(t.cargo, t.vehicleType)) {
				continue;
			}
			if(Place.IsNgPlace(t.destPlace, t.cargo, t.vehicleType) || Place.IsNgPlace(t.place, t.cargo, t.vehicleType)) {
				continue;
			}
			local routeClass = Route.GetRouteClassFromVehicleType(t.vehicleType);
			if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
				continue;
			}
			local routeBuilder = routeClass.GetBuilderClass()(t.destPlace, t.place, t.cargo);
			if(routeBuilder.ExistsSameRoute()) {
				continue;
			}
			HgLog.Info("Try "+routeBuilder+" production:"+t.production+" maxValue:"+t.maxValue+" distance:"+t.distance);
			local newRoute = routeBuilder.Build();
			if(newRoute != null) {
				dirtyPlaces.rawset(t.destPlace.Id()+":"+t.cargo, true);
				dirtyPlaces.rawset(t.place.Id()+":"+t.cargo, true);
				if(!HasIncome(20000) && GetUsableMoney() < GetInflatedMoney(50000)) {
					WaitDays(180); // 建設にコストを掛けすぎて車両が作れなくなる事を防ぐ為に、車両作成の為の時間を空ける
				} else if(!HasIncome(20000) && GetUsableMoney() < GetInflatedMoney(300000)) {
					WaitDays(60); // 建設にコストを掛けすぎて車両が作れなくなる事を防ぐ為に、車両作成の為の時間を空ける
				}
				if(newRoute instanceof TrainRoute) {
					newRoute.isBuilding = true;
					while(SearchAndBuildAdditionalDest(newRoute) != null) {
					}
					SearchAndBuildToMeetSrcDemandTransfer(newRoute, null, {destOnly=true});
					CheckBuildReturnRoute(newRoute);
					newRoute.isBuilding = false;
				}
			}
			if(limitDate < AIDate.GetCurrentDate()) {
				return;
			}
		}
	}
	
	function ScanRoutes() {
		HgLog.Info("###### Scan routes");
		
		if(HogeAI.Get().IsInfrastructureMaintenance()) {
			foreach(route in TrainRoute.removed) { // TODO: Save/Loadに対応していない
				route.RemovePhysically();
				ArrayUtils.Remove(TrainRoute.removed, route);
			}
		}
		if(limitDate < AIDate.GetCurrentDate()) {
			return;
		}

		local aiTestMode = AITestMode();
		local routeRands = []
		foreach(route in TrainRoute.instances) {
			routeRands.push([route, AIBase.RandRange(1000)]);
		}
		routeRands.sort(function(a,b) {
			return a[1] - b[1];
		});
		
		foreach(routeRand in routeRands) {
			local route = routeRand[0];
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
			

			if(route.parentRoute == null) {
				if(route.additionalRoute == null ) {
					SearchAndBuildAdditionalSrc(route);
				}
				while(SearchAndBuildAdditionalDest(route) != null) {
				}
			}
			CheckBuildReturnRoute(route);
			route.isBuilding = false;
			DoInterval();
			
			if(limitDate < AIDate.GetCurrentDate()) {
				break;
			}
		}
	}
	
	function GetRouteCandidatesGen() {
		local considerSlope = !IsRich();
		foreach(i, src in GetMaxCargoPlaces()) {
			//src.production = Place.AdjustProduction(src.place, src.production);
			local count = 0;
			HgLog.Info("src.place:"+src.place.GetName()+" src.cargo:"+AICargo.GetName(src.cargo));
			foreach(dest in CreateRouteCandidates(src.cargo, src.place, 
					Place.GetAcceptingPlaceDistance(src.cargo, src.place.GetLocation()))) {
				
				local routeClass = Route.GetRouteClassFromVehicleType(dest.vehicleType);
				if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
					continue;
				}
				
				local route = {};
				route.cargo <- src.cargo;
				route.place <- src.place;
				route.production <- dest.production;
				route.maxValue <- src.maxValue;
				route.distance <- dest.distance;
				route.destPlace <- dest.place;
				route.vehicleType <- dest.vehicleType;
				route.estimate <- dest.estimate;
				route.score <- dest.score;
				route.infrastractureType <- dest.infrastractureType;
				
				local isDestBi = route.destPlace.IsAcceptingAndProducing(route.cargo);
				
				if(route.vehicleType == AIVehicle.VT_RAIL) {
					if(!route.place.CanUseTrainSource()) {
						continue;
					}
					if(isDestBi && !route.destPlace.GetProducing().CanUseTrainSource()) {
						continue;
					}
				}
				if(isDestBi && !route.destPlace.GetProducing().CanUseNewRoute(route.cargo, route.vehicleType)) {
					continue;
				}
				
				if (considerSlope && (route.vehicleType == AIVehicle.VT_RAIL || route.vehicleType == AIVehicle.VT_ROAD)) {
					local slopeLevel = HgTile(route.place.GetLocation()).GetSlopeLevel(HgTile(route.destPlace.GetLocation()));
					if(isDestBi) {
						slopeLevel = max( slopeLevel, HgTile(route.destPlace.GetLocation()).GetSlopeLevel(HgTile(route.place.GetLocation())));
					}
					route.score = route.score * 8 / (8 + slopeLevel);
				}
				if(ecs && route.destPlace.IsEcsHardNewRouteDest()) {
					route.score = route.score / route.destPlace.GetCargos().len();
				}
				
				//HgLog.Info("score:"+route.score+" "+route.destPlace.GetName()+"<-"+route.place.GetName()+"["+route.distance+"]"+AICargo.GetName(route.cargo));
				yield route;
				count ++;
				if(count >= 50) {
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
			
		local ignoreCargos = {};
		
		HgLog.Info("IsForceToHandleFright: "+IsForceToHandleFright());
		if(IsForceToHandleFright()  && !roiBase) {
			local paxMailOnly = true;
			foreach(route in Route.GetAllRoutes()) {
				if(!CargoUtils.IsPaxOrMail(route.cargo)) {
					paxMailOnly = false;
				}
			}
			if(paxMailOnly) {
				ignoreCargos.rawset( GetPassengerCargo(), true );
				ignoreCargos.rawset( GetMailCargo(), true );
			}
		}
		
	
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		foreach(cargo ,_ in AICargoList()) {		
			if(ignoreCargos.rawin(cargo)) {
				continue;
			}
			if(IsPaxMailOnly() && !CargoUtils.IsPaxOrMail(cargo)) {
				continue;
			}
			
			local maxVehicleType = null;
			local maxValue = 0;
			foreach(routeClass in [TrainRoute, RoadRoute, WaterRoute, AirRoute]) {
				if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
					HgLog.Warning("Too many vehicles."+routeClass.GetLabel());
					continue;
				}
				if(!routeClass.CanCreateNewRoute()) {
					HgLog.Warning("CanCreateNewRoute == false."+routeClass.GetLabel());
					continue;
				}
				local infrastractureType = routeClass.GetDefaultInfrastractureType();
				
				HgLog.Info("Estimate:" + routeClass.GetLabel()+"["+AICargo.GetName(cargo)+"]");
				foreach(distance in distanceEstimateSamples) {
					local estimate = Route.Estimate(routeClass.GetVehicleType(), cargo, distance, 890 /*210*/, CargoUtils.IsPaxOrMail(cargo) ? true: false, infrastractureType);
					if(estimate == null || estimate.value <= 0) {
						continue;
					}
					HgLog.Info("Estimate d:"+distance+" roi:"+estimate.roi+" income:"+estimate.routeIncome+" ("+estimate.incomePerOneTime+") "
						+ AIEngine.GetName(estimate.engine)+(estimate.rawin("numLoco")?"x"+estimate.numLoco:"") +"("+estimate.vehiclesPerRoute+") "
						+ "runningCost:"+AIEngine.GetRunningCost(estimate.engine)+" capacity:"+estimate.capacity);
					maxValue = max(maxValue, estimate.value);
					if(estimate.value == maxValue) {
						maxVehicleType = routeClass.GetVehicleType();
					}
				}
			}
			if(maxValue == 0) {
				continue;
			}
			
			local cargoResult = [];
			local places = Place.GetNotUsedProducingPlaces( cargo ).array;
			
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
			
			foreach(place in places) {
				if(!place.CanUseNewRoute(cargo, maxVehicleType)) {
					continue;
				}
				if(Place.IsNgPlace(place, cargo, maxVehicleType)) {
					continue;
				}
				if(maxVehicleType == AIVehicle.VT_WATER && !place.IsNearWater(cargo)) {
					continue;
				}
				if(maxVehicleType == AIVehicle.VT_AIR && !place.CanBuildAirport(minimumAiportType, cargo)) {
					continue;
				}
				
				local production = place.GetExpectedProduction(cargo,maxVehicleType);
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
				
					cargoResult.push({
						cargo = cargo,
						place = place,
						production = production,
						maxValue = maxValue,
						score = production * maxValue
					});
				}
			}
			HgLog.Info("maxVehicleType:"+maxVehicleType +"cargoResult:"+cargoResult.len());
			if(cargoResult.len() > 16) {
				if(maxVehicleType == AIVehicle.VT_AIR && CargoUtils.IsPaxOrMail(cargo)) {
					foreach(r in cargoResult) {
						r.scoreAirport <- r.place.GetAllowedAirportLevel(minimumAiportType, cargo) * 10000 + max(9999,r.production);				
					}
					cargoResult.sort(function(a,b){
						return -(a.scoreAirport - b.scoreAirport);
					});
				} else {
					cargoResult.sort(function(a,b){
						return -(a.score - b.score);
					});
				}
				result.extend(cargoResult.slice(0,min(cargoResult.len(),16)));
			} else {
				result.extend(cargoResult);
			}
		}
		DoInterval();
		result.sort(function(a,b){
			return -(a.score - b.score);
		});
		return result;
	}
	
	function CreateRouteCandidates(cargo, orgPlace, placeDistances, additionalProduction=0, maxResult=16) {
		local orgTile = orgPlace.GetLocation();
		local orgPlaceAcceptingRaw = orgPlace.IsAccepting() && orgPlace.IsRaw();
		local orgPlaceTraits = orgPlace.GetIndustryTraits();
		local orgPlaceProductionTable = {};
		local orgPlaceUsing = orgPlace.GetRouteCountUsingSource(cargo);
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		local isNgAir = !orgPlace.CanBuildAirport(minimumAiportType, cargo);
		local isNgWater = !orgPlace.IsNearWater(cargo);
		local maxVehicleTable = {};
		//local maxBuildingCost = HogeAI.Get().GetUsableMoney() / 2/*最初期の安全バッファ*/ + HogeAI.Get().GetQuarterlyIncome();
		
		local candidates = placeDistances.Map(function(placeDistance)
				: (cargo,orgTile,orgPlace,orgPlaceAcceptingRaw, orgPlaceTraits, orgPlaceProductionTable, orgPlaceUsing, 
				isNgAir, isNgWater, maxVehicleTable, additionalProduction)  {
			local result = [];
			local t = {};
			t.cargo <- cargo;
			t.place <- placeDistance[0];
			t.distance <- max(0, placeDistance[1] - orgPlace.GetRadius() - t.place.GetRadius());
			
			local vehicleTypes = [];
			if(t.distance < 500) {
				vehicleTypes.extend([AIVehicle.VT_RAIL, AIVehicle.VT_ROAD]);
			}
			if(t.distance < 500 && !isNgWater) {
				vehicleTypes.push(AIVehicle.VT_WATER);
			}
			if(!isNgAir) {
				vehicleTypes.push(AIVehicle.VT_AIR);
			}
			
			foreach(vt in vehicleTypes) {
				local routeClass = Route.GetRouteClassFromVehicleType(vt);
				if(!maxVehicleTable.rawin(vt)) {
					maxVehicleTable[vt] <- AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, routeClass.GetVehicleType()) >= routeClass.GetMaxTotalVehicles();
				}
				if(maxVehicleTable[vt]) {
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
				}
				if(Place.IsNgPathFindPair(orgPlace, t.place, vt)) {
					continue;
				}
				if(Place.IsNgPlace(orgPlace, cargo, vt) || Place.IsNgPlace(t.place, cargo, vt)) {
					continue;
				}
				local srcPlace = orgPlace.IsProducing() ? orgPlace : t.place;
				local destPlace = orgPlace.IsProducing() ? t.place : orgPlace;
				
				local placeProduction = t.place.GetProducing().GetExpectedProduction(cargo, vt)
					/ (t.place.GetProducing().GetRouteCountUsingSource(cargo) + 1);
				local orgPlaceProduction;
				if(orgPlaceProductionTable.rawin(vt)) {	
					orgPlaceProduction = orgPlaceProductionTable[vt];
				} else {
					orgPlaceProduction = orgPlace.GetExpectedProduction(cargo, vt) / (orgPlaceUsing + 1);
					orgPlaceProductionTable[vt] <- orgPlaceProduction;
				}
				
				local isBidirectional = orgPlace.IsAcceptingAndProducing(cargo) && t.place.IsAcceptingAndProducing(cargo);
				local production;
				if(!isBidirectional) {
					production = orgPlace.IsProducing() ? orgPlaceProduction : placeProduction;
				} else {
					production = min( orgPlaceProduction, placeProduction );
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
				local infrastractureType = routeClass.GetSuitableInfrastractureType(orgPlace, t.place, cargo);
				local estimate = Route.Estimate( vt, cargo, pathDistance, production + additionalProduction, isBidirectional, infrastractureType );
				
				
				if(estimate != null && estimate.value > 0 /*&& estimate.buildingCost <= maxBuildingCost Estimate内ではじいている*/) {
					local candidate = clone t;
					
					candidate.estimate <- estimate;
					candidate.vehicleType <- vt;
					candidate.score <- estimate.value;
					candidate.infrastractureType <- infrastractureType;
					if(vt == AIVehicle.VT_AIR && cargo == HogeAI.GetPassengerCargo() && orgPlace instanceof TownCargo && t.place instanceof TownCargo) {
						candidate.score = candidate.score * 13 / 10; // 郵便がひっついてくる分
					}
					candidate.production <- production;
					
					if(vt == AIVehicle.VT_AIR && pathDistance != 0) {
						candidate.score = candidate.score * t.distance / pathDistance;
					}
					
					/*
					if (considerSlope && (vt == AIVehicle.VT_RAIL || vt == AIVehicle.VT_ROAD)) {
						t.score = t.score * 3 / (3 + max( AITile.GetMaxHeight(route.destPlace.GetLocation()) - AITile.GetMaxHeight(route.place.GetLocation()) , 0 ));
					}*/
				
				
					result.push(candidate);
				}
			}
			return result;
		}).Flatten().Filter(function(t):(orgTile) {
			return t.vehicleType != null && t.distance > 0 && !Place.IsNgPathFindPair(t.place,orgTile,t.vehicleType);
		}).Sort(function(a,b) {
			return b.score - a.score;
		}).array;
		local result = [];
		foreach(candidate in candidates) {
			if(Route.SearchRoutes( Route.GetRouteWeightingVt(candidate.vehicleType), orgPlace, candidate.place, null, cargo ).len() >= 1) {
				continue;
			}
			if(candidate.vehicleType == AIVehicle.VT_RAIL || candidate.vehicleType == AIVehicle.VT_ROAD) {
				if(CanRemoveWater() && candidate.vehicleType == AIVehicle.VT_RAIL) {
				} else {
					local cost = HgTile(orgTile).GetPathFindCost(HgTile(candidate.place.GetLocation()));
					if(cost > 300) {		//TODO 道路は本来かなり長距離の橋もいけるが、RoadPathFinderで制限される。
						continue;
					}
				}
			} else if(candidate.vehicleType == AIVehicle.VT_AIR) {
				if(!candidate.place.CanBuildAirport(minimumAiportType, cargo)) {
					continue;
				}
			} else if(candidate.vehicleType == AIVehicle.VT_WATER) {
				if(!candidate.place.IsNearWater(cargo)) {
					continue;
				}
			}
			result.push(candidate);
			if(maxResult != null && result.len() >= maxResult) {
				break;
			}
		}
		if(result.len() == 0) {
			foreach(vt in Route.allVehicleTypes) {
				Place.AddNgPlace(orgPlace, cargo, vt); // 次回のGetMaxCargoPlacesから除外する為に
			}
		}
		
		HgLog.Info("CreateRouteCandidates:" + orgPlace.GetName() + " using:"+orgPlaceUsing+" placeDistances:"+placeDistances.Count()+" cargo:"+AICargo.GetName(cargo) + " result:"+result.len());
		return result;
	}
 
	function CheckAndBuildCascadeRoute(destPlace,cargo) {
		if(stockpiled && !IsRich()) {
			return; // ほんの少ししか生産されないためにbankruptするリスクを回避
		}
		if(!destPlace.IsProcessing() || !destPlace.IsIncreasable()) {
			return;
		}
		
		local cascaded = false;
		local producing = destPlace.GetProducing();
		local cargos = producing.GetCargos();
		if(cargos.len() >= 1 /*&& destPlace.IsNearAllNeedsExcept(cargo)*/) {
			foreach(newCargo in producing.GetCargos()) {
				if(AICargo.GetTownEffect(newCargo) == AICargo.TE_NONE) {
					continue;
				}
				HgLog.Info("Try to build cascade route. src place:"+destPlace.GetName()+" newCargo:["+AICargo.GetName(newCargo)+"]");
				if(PlaceDictionary.Get().IsUsedAsSrouceCargoByTrain(producing, newCargo)) {
					HgLog.Info("Already used. cargo:"+AICargo.GetName(newCargo));
					continue;
				}
				local destPlaceScores = Place.SearchAcceptingPlaces(newCargo, producing.GetLocation(), AIVehicle.VT_RAIL);
				if(destPlaceScores.len() >= 1) {
					if(BuildRouteAndAdditional(destPlaceScores[0].place, producing, newCargo) != null) {
						cascaded = true;
					}
				} else {
					HgLog.Info("Not found accepting place. cargo:"+AICargo.GetName(newCargo));
				}
			}
		}
		return cascaded;
	}
	
	function GetLocationFromDest(dest) {
		if(dest instanceof Place) {
			return dest.GetLocation();
		} else {
			return dest.srcHgStation.platformTile;
		}
	}
	
	function BuildRouteAndAdditional(destPlaceOrStationGroup,srcPlace,cargo) {
		
		local route = BuildRoute(destPlaceOrStationGroup, srcPlace, cargo);
		if(route == null) {
			Place.AddNgPathFindPair(destPlaceOrStationGroup,srcPlace,AIVehicle.VT_RAIL);
			return null;
		}
		
		
		route.isBuilding = true;
		if(!route.IsTransfer()) {
			local currentProduction = srcPlace.GetLastMonthProduction(cargo);
			if(currentProduction==0 || currentProduction < srcPlace.GetExpectedProduction(cargo, AIVehicle.VT_RAIL)) {
				SearchAndBuildToMeetSrcDemandMin(srcPlace, route);
			}
			SearchAndBuildToMeetSrcDemandTransfer(route, null, {notTreatDest = true}/*このあと延長チェックがあるので*/);
		}
		
		if(!route.IsTransfer()) {
		
			/*
			while(!CheckAndBuildCascadeRoute(dest,cargo)) { markChangeDestの関係でここはScanPlaceでやる
				dest = SearchAndBuildAdditionalDest(route)
				if(dest == null) {
					break;
				}
			}
			if(route.IsBiDirectional()) {
				SearchAndBuildToMeetSrcDemandUsingRailTransferForReturnRoute(route);
				SearchAndBuildToMeetSrcDemandTransfer(route);
			}*/
			/* markChangeDestの関係でここはScanPlaceでやる
			if(route.additionalRoute != null) {
				CheckBuildReturnRoute(route.additionalRoute);
			}
			CheckBuildReturnRoute(route);*/
		}
		route.isBuilding = false;
		return route;
	}

	function SearchAndBuildAdditionalSrc(route) {
		//TODO: 10年経っても線路が空いてたら
		/*
		local srcPlace = route.srcHgStation.place;
		foreach(t in Place.SearchSrcAdditionalPlaces(srcPlace, route.GetFinalDestPlace().GetLocation(), route.cargo)) {
			HgLog.Info("Found an additional producing place:"+t.place.GetName()+" route:"+route);
			local additionalRoute = BuildSrcRouteAdditional(route,t.place);
			if(additionalRoute != null) {
				SearchAndBuildToMeetSrcDemandUsingRail(additionalRoute);
				SearchAndBuildToMeetSrcDemandUsingRoad(additionalRoute);
				return additionalRoute;
			}
			Place.AddNgPathFindPair(srcPlace,t.place);
		}*/
		return null;
	}
	
	
	function SearchAndBuildToMeetSrcDemandTransfer(originalRoute=null, routeClass=null, options={}) {
		local notTreatDest = options.rawin("notTreatDest") ? options.notTreatDest : false;
		local destOnly = options.rawin("destOnly") ? options.destOnly : false;
	
		if(routeClass != null) {
			HgLog.Info("Search and build to meet src demand transfer using "+routeClass.GetLabel()+"."+(originalRoute!=null?originalRoute:"(all)"));
		} else  {
			local a = SearchAndBuildToMeetSrcDemandTransfer(originalRoute, WaterRoute, options);
			local b = SearchAndBuildToMeetSrcDemandTransfer(originalRoute, TrainRoute, options);
			local c = SearchAndBuildToMeetSrcDemandTransfer(originalRoute, RoadRoute, options);
			return a || b || c;
		}

		if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
			HgLog.Warning("Too many "+routeClass.GetLabel()+" vehicles.");
			return;
		}
		
		local additionalPlaces = [];
		local routes;
		if(originalRoute != null) {
			routes = [originalRoute];
		} else {
			routes = Route.GetAllRoutes();
		}
		
		local vehicleType = routeClass.GetVehicleType();
		foreach(route in routes) {
			local ok = false;
			if(vehicleType == AIVehicle.VT_AIR) { // 航空機を転送に用いる事はできない(今のところ)
			} else if(vehicleType == AIVehicle.VT_WATER && route.GetVehicleType() != AIVehicle.VT_WATER) { // 船は船以外すべての転送で使用できる。
				ok = true;
			} else {
				switch(route.GetVehicleType()) {
					case AIVehicle.VT_RAIL:
						ok = true;
						break;
					case AIVehicle.VT_ROAD:
						ok = vehicleType == AIVehicle.VT_ROAD && route.GetDistance() >= 200 && HogeAI.Get().IsInfrastructureMaintenance()/*メンテコストがかかる場合、長距離道路の転送は認める*/;
						break;
					case AIVehicle.VT_WATER:
						ok = vehicleType != AIVehicle.VT_WATER;
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
				additionalPlaces.extend(GetPlansToMeetSrcDemandTransfer(route, false, vehicleType));
			}
			if(!notTreatDest && route.IsBiDirectional()) {
				additionalPlaces.extend(GetPlansToMeetSrcDemandTransfer(route, true, vehicleType));
			}
			
			DoInterval();
		}
		foreach(t in additionalPlaces) {
			t.score <- (t.route.GetDistance() * t.route.GetRouteCapacity()) * t.production / (t.distance+20) + Route.GetRouteWeightingVt(routeClass.GetVehicleType());
		}
	
		additionalPlaces.sort(function(a,b) {
			return b.score - a.score;
		});
		local limitDate = AIDate.GetCurrentDate() + 30;
		foreach(t in additionalPlaces) {
			if(limitDate < AIDate.GetCurrentDate()) {
				HgLog.Info("time limit SearchAndBuildToMeetSrcDemandTransfer");
				break;
			}
			local routeBuilder = routeClass.GetBuilderClass()(t.dest, t.srcPlace, t.cargo);
			if(!routeBuilder.ExistsSameRoute()) {
				HgLog.Info(routeBuilder+" for:"+t.route);
				local newRoute = routeBuilder.Build();
				if(newRoute != null) {
					t.route.NotifyAddTransfer();
					if(t.srcPlace.IsProcessing() && t.srcPlace.GetLastMonthProduction(t.cargo) == 0) {
						SearchAndBuildToMeetSrcDemandMin(t.srcPlace, newRoute);
					}
				}
				
			}
			DoInterval();
			
		}
		
		return false;
	}
	
	function GetPlansToMeetSrcDemandTransfer(route,isDest,vehicleType) {
		local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
		if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
			return [];
		}
		if(route.srcHgStation.IsTownStop()) {
			return [];
		}

		local maxDistance;
		local minDistance;
		local minProduction;
		if(vehicleType == AIVehicle.VT_RAIL) {
			minDistance = RoadRoute.IsTooManyVehiclesForSupportRoute(RoadRoute) ? 0 : 50;
			maxDistance = 300;
			minProduction = 50;
		} else {
			minDistance = 0;
			maxDistance = 200;
			minProduction = 1;
		}
		maxDistance = max(100, min(maxDistance, route.GetDistance() / 2));
		
		local additionalPlaces = [];
		local hgStation = isDest ? route.destHgStation : route.srcHgStation;
		local finalDestPlace = route.GetFinalDestPlace();
		if(finalDestPlace == null) {
			return [];
		}
		local finalDestLocation = isDest ? route.srcHgStation.platformTile : finalDestPlace.GetLocation();
		
		foreach(cargo in route.GetCargos()) {
			if(!route.NeedsAdditionalProducingCargo(cargo, null, isDest)) {
				continue;
			}
			foreach(data in Place.SearchSrcAdditionalPlaces( 
					hgStation, finalDestLocation, 
					cargo, minDistance, maxDistance, minProduction, vehicleType)) {
				if(vehicleType == AIVehicle.VT_WATER && !hgStation.stationGroup.IsNearWater()) {
					continue;
				}
				if(!data.place.CanUseTransferRoute(cargo, vehicleType)) {
					continue;
				}
				local t = {};
				t.route <- route;
				t.cargo <- cargo;
				t.dest <- hgStation.stationGroup;
				t.srcPlace <- data.place;
				t.distance <- data.distance;
				t.production <- data.production;
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

	function GetCargoPlansToMeetSrcDemand(acceptingPlace, forRoute = null) {
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
						if(cargoScores["FRUT"].stockpiled == 0 && cargoScores["CERE"].stockpiled == 0) {
							cargoScore.score += 2;
							cargoScore.explain += "+2(stockpile==0)"
						} else if(cargoScore.stockpiled == 0) {
							cargoScore.score = 0;
							cargoScore.explain = "0(meet FRUT or CERE)";
						}
					}
				}
			}
			if(cargoScore.score >= 1) {
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
		if(!firs/*raw industryへのsupplyは重要*/ && !ecs/*acceptできなくなったindustryの対応が必要*/ && roiBase) {
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
			if(!DoCargoPlans(cargoPlans)) {
				if(isTimeoutToMeetSrcDemand) {
					HgLog.Warning("isTimeoutToMeetSrcDemand: true");
				}
				break;
			}
		}
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
					if(searchedPlaces.rawin(accepting.Id())) {
						HgLog.Warning("Circular reference "+accepting.GetName()+". cargoPlan:"+cargoPlanName);
						return true;
					}
					searchedPlaces.rawset(accepting.Id(), true);
					DoCargoPlans( GetCargoPlansToMeetSrcDemand( accepting ), searchedPlaces );
					if(limitDate < AIDate.GetCurrentDate()) {
						isTimeoutToMeetSrcDemand = cargoPlan.score >= 400;
						return false; // return するのは時間切れの場合のみ
					}
				}
			
			}
			foreach(routePlan in CreateRoutePlans( cargoPlan )) {
				local accepting = routePlan.srcPlace.GetAccepting();
				if(routePlan.production == 0 && accepting.GetRoutesUsingDest().len() == 0) {
					local srcName = accepting.GetName()+ "["+AICargo.GetName(routePlan.cargo)+"]";
					HgLog.Info("routePlan: "+ srcName + " is not producing."
						+ "Search routePlan to meet the demand for the srcPlace recursivly. cargoPlan:"+cargoPlanName);
					if(searchedPlaces.rawin(accepting.Id())) {
						HgLog.Warning("Circular reference "+accepting.GetName()+". cargoPlan:"+cargoPlanName);
						return true; // ゼロ生産施設へのルートを建設する為にtrueを返す
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
	
	function DoRoutePlan(routePlan, explain = "") {
		local routeBuilder = routePlan.routeClass.GetBuilderClass()(routePlan.destPlace, routePlan.srcPlace, routePlan.cargo);
		if(!routeBuilder.ExistsSameRoute()) {
			HgLog.Info(routeBuilder + explain);
			local newRoute = routeBuilder.Build();
			if(newRoute != null) {
				if(routePlan.rawin("canChangeDest") && routePlan.canChangeDest) {
				} else {
					newRoute.cannotChangeDest = true;
				}
				return newRoute;
			}
		}
		return null;
	}
	
	function CalculateRoutePlanScore(routePlan) {
		return Route.GetRouteCapacityVt(routePlan.vehicleType) * 1000000 + (routePlan.production == 0 ? 1000 : routePlan.estimate.value * 100) / routePlan.distance;
	}
	
	function CreateRoutePlans(cargoPlan, maxResult=20) {
		local additionalProduction = 100; //現在生産量でソースを選択しなくてはならないが、初期でほとんど何も生産していない場合がある
		local routePlans = [];
		local cargo = cargoPlan.cargo;
		if(cargoPlan.rawin("srcPlace")) {
			local placeDistances = HgArray([[cargoPlan.destPlace, AIMap.DistanceManhattan(cargoPlan.destPlace.GetLocation(), cargoPlan.srcPlace.GetLocation())]]);
			foreach(destCandidate in CreateRouteCandidates(cargo, cargoPlan.srcPlace, placeDistances, additionalProduction, maxResult)) {
				local routePlan = {};
				local routeClass = Route.GetRouteClassFromVehicleType(destCandidate.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				routePlan.cargo <- cargo;
				routePlan.srcPlace <- cargoPlan.srcPlace;
				routePlan.destPlace <- destCandidate.place;
				routePlan.distance <- destCandidate.distance;
				routePlan.production <- routePlan.srcPlace.GetLastMonthProduction(cargo);
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
				local score = cargoPlan.score;
				if(score >= 4) {
					maxDistance = 500;
				} else if(score >= 2) {
					maxDistance = 350;
				} else {
					maxDistance = 200;
				}
				if(roiBase) {
					maxDistance = min(200, maxDistance);
				}
			}
			
			foreach(srcCandidate in CreateRouteCandidates(cargo, acceptingPlace, 
					 Place.GetProducingPlaceDistance(cargo, acceptingPlace.GetLocation(), maxDistance ), additionalProduction, maxResult)) {
				local routePlan = {};
			
				local routeClass = Route.GetRouteClassFromVehicleType(srcCandidate.vehicleType);
				if(!acceptingPlace.IsRaw() && routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) { //raw industryを満たすのは重要なので例外(for FIRS)
					continue;
				}
				routePlan.cargo <- cargo;
				routePlan.srcPlace <- srcCandidate.place;
				routePlan.destPlace <- acceptingPlace;
				routePlan.distance <- srcCandidate.distance;
				routePlan.production <- routePlan.srcPlace.GetLastMonthProduction(cargo);
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
					Place.GetAcceptingPlaceDistance(cargo, producingPlace.GetLocation()), additionalProduction, maxResult)) {
				local routePlan = {};
				local routeClass = Route.GetRouteClassFromVehicleType(destCandidate.vehicleType);
				if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
					continue;
				}
				routePlan.canChangeDest <- true;
				routePlan.cargo <- cargo;
				routePlan.srcPlace <- producingPlace;
				routePlan.destPlace <- destCandidate.place;
				routePlan.distance <- destCandidate.distance;
				routePlan.production <- routePlan.srcPlace.GetLastMonthProduction(cargo);
				routePlan.vehicleType <- destCandidate.vehicleType;
				routePlan.routeClass <- routeClass;
				routePlan.estimate <- destCandidate.estimate;
				routePlan.score <- destCandidate.score;
				routePlans.push(routePlan);
			}
		}
		foreach(routePlan in routePlans) {
			routePlan.score = CalculateRoutePlanScore(routePlan);
		}
		
		routePlans.sort(function(a,b) {
			return b.score - a.score;
		});
		
		return routePlans;
	}

	function SearchAndBuildAdditionalDest(route) {
		/*if(TrainRoute.instances.len() <= 1) { // 最初の1本目は危険なので伸ばさない
			return null;
		}*/
		if(route.cannotChangeDest) {
			return null;
		}
		local destHgStation = route.GetLastHgStation();
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
		if(route.trainLength < 7) {
			return null;
		}
		local maxDistance = 0;
		if(route.IsClosed()) {
			maxDistance = 500;
		} else {
			local currentValue = 0;//route.latestEngineSet.income;
			local estimate = null;
			for(local distance = 0; distance <= 500; distance += 100) {
				estimate = Route.Estimate(AIVehicle.VT_RAIL, route.cargo, route.GetDistance() + distance, route.GetProduction(), route.IsBiDirectional());
				if(estimate == null) {
					break;
				}
				local score = roiBase ? estimate.roi : estimate.routeIncome;
				if(score < currentValue) {
					break;
				}
				currentValue = score;
				maxDistance = distance;
			}
			if(maxDistance == 0) {
				HgLog.Warning("No need to extend route "+route);
				return null;
			}
			HgLog.Info("SearchAndBuildAdditionalDest maxDistance:"+maxDistance+" "+route);
		}
		
		local lastAcceptingTile = destHgStation.platformTile;
		local ecsHardDest = ecs && destHgStation.place.IsEcsHardNewRouteDest();
		foreach(placeScore in Place.SearchAdditionalAcceptingPlaces(route.GetUsableCargos(), route.GetSrcStationTiles(), destHgStation.platformTile, maxDistance)) {
			if(placeScore[0].IsSamePlace(destHgStation.place)) {
				continue;
			}
			if(ecs && !ecsHardDest && placeScore[0].IsEcsHardNewRouteDest()) {
				continue;
			}
			if(route.IsBiDirectional() && route.srcHgStation.place!=null && destHgStation.place!=null) {
				if(!placeScore[0].GetProducing().CanUseNewRoute(route.cargo, AIVehicle.VT_RAIL)) {
					continue;
				}
				/*
				if(placeScore[0].GetProducing().GetLastMonthProduction(route.cargo) 
						< min( route.srcHgStation.place.GetProducing().GetLastMonthProduction(route.cargo), 
							destHgStation.place.GetProducing().GetLastMonthProduction(route.cargo)) * 2 / 3) {
					continue;
				}*/
			}/*
			if(route.cargo == HogeAI.GetPassengerCargo()) {
				if(placeScore[0] instanceof TownCargo && !CanUseTownBus(placeScore[0])) {
					continue;
				}
			}*/

			HgLog.Info("Found an additional accepting place:"+placeScore[0].GetName()+" route:"+route);
			if(BuildDestRouteAdditional(route,placeScore[0])) {
				CheckAndBuildCascadeRoute(placeScore[0],route.cargo);
				return placeScore[0];
			}
			Place.AddNgPathFindPair(placeScore[0], lastAcceptingTile, AIVehicle.VT_RAIL);
			return null; //1つでも失敗したら終了とする。
		}
		HgLog.Info("Not found an additional accepting place. route:"+route);
		return null;
	}
	
	function GetEstimateDistanceIndex(distance) {
		return GetEstimateIndex(HogeAI.distanceEstimateSamples, distance);
	}

	function GetEstimateProductionIndex(production) {
		return GetEstimateIndex(HogeAI.productionEstimateSamples, production);
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
		
	function BuildRoute(destPlaceOrStationGroup, srcPlace, cargo) {
		local distance = AIMap.DistanceManhattan(srcPlace.GetLocation(), destPlaceOrStationGroup.GetLocation());
		local explain = destPlaceOrStationGroup.GetName()+"<-"+srcPlace.GetName()+"["+AICargo.GetName(cargo)+"] distance:"+distance;
		HgLog.Info("# TrainRoute: Try BuildRoute: "+explain);
		
		if(Place.IsNgPlace(destPlaceOrStationGroup, cargo, AIVehicle.VT_RAIL)) {
			HgLog.Warning("TrainRoute: dest is ng facility."+explain);
			return null;
		}
		if(Place.IsNgPlace(srcPlace, cargo, AIVehicle.VT_RAIL)) {
			HgLog.Warning("TrainRoute: src is ng facility."+explain);
			return null;
		}
		if(!PlaceDictionary.Get().CanUseAsSource(srcPlace, cargo)) {
			HgLog.Warning("TrainRoute: src is used."+explain);
			return null;
		}
		local aiExecMode = AIExecMode();
		
		
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.productions = [TrainRoute.GetRoundedProduction(max(50,srcPlace.GetLastMonthProduction(cargo)))]; // 生産0でのルート作成が失敗しないようにする
		trainPlanner.distance = distance;
		trainPlanner.checkRailType = true;

		local engineSets = trainPlanner.GetEngineSetsOrder();
		
		if(engineSets.len()==0) {
			HgLog.Info("TrainRoute: Not found enigneSet "+explain);
			return null;
		}
		HgLog.Info("TrainRoute railType:"+AIRail.GetName(engineSets[0].railType));
		HgLog.Info("AIRail.GetMaintenanceCostFactor:"+AIRail.GetMaintenanceCostFactor(engineSets[0].railType));	
		AIRail.SetCurrentRailType(engineSets[0].railType);
		
		local destTile = null;
		local destHgStation = null;
		destTile = destPlaceOrStationGroup.GetLocation();
		local destStationFactory = TerminalStationFactory(2);
		destStationFactory.distance = distance;
		if(destPlaceOrStationGroup instanceof Place) {
			local destPlace = destPlaceOrStationGroup;
			if(destPlace.GetProducing().IsTreatCargo(cargo)) { // bidirectional
				destPlace = destPlace.GetProducing();
			}
			destHgStation = destStationFactory.CreateBest(destPlace, cargo, srcPlace.GetLocation());
		} else  {
			destStationFactory.useSimple = true;
			destHgStation = destStationFactory.CreateBestOnStationGroup( destPlaceOrStationGroup, cargo, srcPlace.GetLocation() );
		}

		if(destHgStation == null) {
			HgLog.Warning("TrainRoute: No destStation."+explain);
			Place.AddNgPlace(destPlaceOrStationGroup, cargo, AIVehicle.VT_RAIL);
			return null;
		}
		
		local srcStatoinFactory = SrcRailStationFactory();
		srcStatoinFactory.platformLength = destHgStation.platformLength;
		srcStatoinFactory.useSimple = destStationFactory.useSimple;
		local srcHgStation = srcStatoinFactory.CreateBest(srcPlace, cargo, destTile);
		if(srcHgStation == null) {
			HgLog.Warning("TrainRoute: No srcStation."+explain);
			Place.AddNgPlace(srcPlace, cargo, AIVehicle.VT_RAIL);
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
		if(srcPlace instanceof HgIndustry) {
			pathfinding.industries.push(srcPlace.industry);
		}
		if(destPlaceOrStationGroup instanceof HgIndustry) {
			pathfinding.industries.push(destPlaceOrStationGroup.industry);
		}
		this.pathfindings.rawset(pathfinding,0);
		local railBuilder = TwoWayStationRailBuilder(srcHgStation, destHgStation, !HasIncome(10000) ? pathFindLimit * 3 /*無収入で失敗は命取りになりかねない*/: pathFindLimit, pathfinding);
		railBuilder.cargo = cargo;
		railBuilder.platformLength = destHgStation.platformLength;
		railBuilder.distance = distance;
		if(destPlaceOrStationGroup instanceof Place) {
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
			srcHgStation.Remove();
			destHgStation.Remove();
			return null;
		}
		local route = TrainRoute(
			TrainRoute.RT_ROOT, cargo,
			srcHgStation, destHgStation,
			railBuilder.buildedPath1, railBuilder.buildedPath2);
		route.isTransfer = destPlaceOrStationGroup instanceof StationGroup;
		route.AddDepots(railBuilder.depots);
		route.Initialize();

		destHgStation.BuildAfter();
		if(!route.BuildFirstTrain()) {
			HgLog.Warning("TrainRoute: BuildFirstTrain failed."+route);
			srcHgStation.Remove();
			destHgStation.Remove();
			return null;
		}

		TrainRoute.instances.push(route);
		PlaceDictionary.Get().AddRoute(route);
		
		if(CargoUtils.IsPaxOrMail(cargo)) {
			CommonRouteBuilder.CheckTownTransfer(route, srcHgStation);
			CommonRouteBuilder.CheckTownTransfer(route, destHgStation);
		}
		//route.CloneAndStartTrain();
		
		HgLog.Info("# TrainRoute: BuildRoute succeeded: "+route);
		return route;
	}

	function BuildDestRouteAdditional(route, additionalPlace) {
		HgLog.Info("# TrainRoute: Try BuildDestRouteAdditional:"+additionalPlace.GetName()+" route: "+route);
		AIRail.SetCurrentRailType(route.GetRailType());
		if(additionalPlace.GetProducing().IsTreatCargo(route.cargo)) {
			additionalPlace = additionalPlace.GetProducing();
		}
		local stationFactory = TerminalStationFactory(route.additionalRoute!=null?3:2);
		stationFactory.platformLength = route.srcHgStation.platformLength;
		stationFactory.minPlatformLength = route.GetPlatformLength();
		local additionalHgStation = stationFactory.CreateBest(additionalPlace, route.cargo, route.destHgStation.platformTile);
		if(additionalHgStation == null) {
			HgLog.Info("TrainRoute: cannot build additional station");
			return false;
		}

		local aiExecMode = AIExecMode();

		additionalHgStation.cargo = route.cargo;
		additionalHgStation.isSourceStation = false;
		if(!additionalHgStation.BuildExec()) {
			return false;
		}
		
		local railBuilder = TwoWayPathToStationRailBuilder(
			GetterFunction( function():(route) {
				return route.GetTakeAllPathSrcToDest();
			}),
			GetterFunction( function():(route) {
				return route.GetTakeAllPathDestToSrc().Reverse();
			}),
			additionalHgStation, pathFindLimit, this);
			
		railBuilder.cargo = route.cargo;
		railBuilder.platformLength = route.GetPlatformLength();
		railBuilder.distance = AIMap.DistanceManhattan(additionalPlace.GetLocation(), route.destHgStation.GetLocation());
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			railBuilder.isBuildDepotsDestToSrc = true;
		}
		if(!railBuilder.Build()) {
			HgLog.Warning("TrainRoute: railBuilder.Build failed.");
			additionalHgStation.Remove();
			return false;
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

		/* destがcloseしたときに再利用されるので削除しない
		DelayCommandExecuter.Get().Post(300,function():(removePath1,removePath2,oldDestStation) { //TODO: save/loadに非対応
			removePath1.RemoveRails();
			removePath2.RemoveRails();
			oldDestStation.Remove();
		});
		*/
		route.AddAdditionalTiles(removePath1.GetTiles());
		route.AddAdditionalTiles(removePath2.GetTiles());
		BuildedPath(removePath1);
		BuildedPath(removePath2);
		
		
		if(CargoUtils.IsPaxOrMail(route.cargo)) {
			CommonRouteBuilder.CheckTownTransfer(route, route.destHgStation);
		}
					

		HgLog.Info("# TrainRoute: BuildDestRouteAdditional succeeded: "+route);
		return true;
	}
	
	function BuildSrcRouteAdditional(route, additionalPlace) {
		AIRail.SetCurrentRailType(route.GetRailType());
		
		local additionalHgStation = SrcRailStationFactory().CreateBest(additionalPlace, route.cargo, route.destHgStation.platformTile);
		if(additionalHgStation == null) {
			HgLog.Info("cannot build src additional station");
			return null;
		}
		
		local aiExecMode = AIExecMode();
		additionalHgStation.cargo = route.cargo;
		additionalHgStation.isSourceStation = true;
		if(!additionalHgStation.BuildExec()) {
			return null;
		}
		
		local railBuilder = TwoWayPathToStationRailBuilder(
			GetterFunction( function():(route) {
				return route.pathDestToSrc.path;
			}),
			GetterFunction( function():(route) {
				return route.pathSrcToDest.path.Reverse();
			}),
			additionalHgStation, pathFindLimit, this);
		railBuilder.cargo = route.cargo;
		railBuilder.platformLength = route.GetPlatformLength();
		if(!railBuilder.Build()) {
			HgLog.Warning("railBuilder.Build failed.");
			additionalHgStation.Remove();
			return null;
		}
		local depotPath = route.pathDestToSrc.path.SubPathStart(railBuilder.buildedPath1.path.GetLastTile());
		local depot = depotPath.BuildDepot();
		local doubleDepots = depotPath.BuildDoubleDepot();
		
		route.AddDepot(depot);
		route.AddDepots(doubleDepots);
		local additionalRoute = TrainRoute(TrainRoute.RT_ADDITIONAL, route.cargo, additionalHgStation, route.destHgStation,
			railBuilder.buildedPath2, railBuilder.buildedPath1);

		
		TrainRoute.instances.push(additionalRoute);
		route.AddAdditionalRoute(additionalRoute);		
		PlaceDictionary.Get().AddRoute(additionalRoute);
		
		additionalRoute.BuildFirstTrain();
		additionalRoute.CloneAndStartTrain();
		HgLog.Info("BuildSrcRouteAdditional succeeded: "+additionalRoute);
		return additionalRoute;
	}
	
	
	
	function CheckBuildReturnRoute(route) {
		/*if(ecs) { // TODO ECSでは頻繁にdestが受け入れなくなり、destが変更になる事から対応が難しい, YETIも必要な経路では無い事が多い=>受け入れ拒否に対する対応が進んでいる
			return;
		}*/
	
		if(route.returnRoute == null && route.GetDistance() >= 250 && !route.IsBiDirectional()) {
			HgLog.Info("SearchReturnPlacePairs route:"+route);
			local t = SearchReturnPlacePairs(route.GetPathAllDestToSrc(), route.cargo);
			if(t.pairs.len() >= 1) {
				local pair = t.pairs[0];
				HgLog.Info("Found return route:"+pair[0].GetName()+" to "+pair[1].GetName()+" used route:"+route);
				BuildReturnRoute(route,pair[0],pair[1]);
			} else {
				HgLog.Info("Not found ReturnPlacePairs route:"+route);
			}
			
			/* else if(t.placePathDistances.len() >= 1){
				HgLog.Info("Build empty return route:"+t.placePathDistances[0][0].GetName()+" used route:"+route);
				BuildReturnRoute(route,null,t.placePathDistances[0][0]);
			}*/
		}
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

		local srcPlaces = Place.GetNotUsedProducingPlaces( cargo );
		local srcPlaceDistances = srcPlaces.Map(function(place):(cargo) {
			return [place, place.GetExpectedProduction(cargo, AIVehicle.VT_RAIL)];
		}).Filter(function(placeProduction) {
			return placeProduction[1] >= 50;
		}).Map(function(placeProduction) : (checkPointsEnd) {
			placeProduction.extend(HogeAI.GetMinDistanceFromPoints(placeProduction[0].GetLocation(), checkPointsEnd));
			return placeProduction;
		}).Filter(function(placeProductionTileDistance) {
			return 0<=placeProductionTileDistance[3] && placeProductionTileDistance[3]<=150;
		});
		
		local destPlaceDistances = Place.GetCargoAccepting(cargo).Map(function(place) : (checkPointsStart) {
			local tileDistance = HogeAI.GetMinDistanceFromPoints(place.GetLocation(), checkPointsStart);
			return [place, tileDistance[0], tileDistance[1]];
		}).Filter(function(placeTileDistance) {
			return placeTileDistance[2]<=150 && placeTileDistance[0].IsAccepting();
		});

		local result = [];
		foreach(placeProductionTileDistance in srcPlaceDistances.array) {
			local srcPlace = placeProductionTileDistance[0];
			local production = placeProductionTileDistance[1];
			local pathTileS = placeProductionTileDistance[2];
			local distanceS = placeProductionTileDistance[3];
			//production = Place.AdjustProduction(srcPlace, production);

			foreach(placeTileDistance in destPlaceDistances.array) {
				local destPlace = placeTileDistance[0];
				local pathTileD = placeTileDistance[1];
				local distanceD = placeTileDistance[2];
				local used = HgTile(path.GetTile()).DistanceManhattan(HgTile(path.GetLastTile())) 
					- (HgTile(path.GetLastTile()).DistanceManhattan(HgTile(pathTileS)) + HgTile(path.GetTile()).DistanceManhattan(HgTile(pathTileD)));
				if(used < 200) {
					continue;
				}
				local dCost = HgTile(destPlace.GetLocation()).GetPathFindCost(HgTile(pathTileD));
				local sCost = HgTile(srcPlace.GetLocation()).GetPathFindCost(HgTile(pathTileS));
				local xCost = HgTile(srcPlace.GetLocation()).GetPathFindCost(HgTile(destPlace.GetLocation()));
				if(xCost < (dCost + sCost) * 2) {
					continue;
				}
				local score = destPlace.DistanceManhattan(srcPlace.GetLocation()) * production / (dCost + sCost);
				if(dCost < 300 && sCost < 300) {
					result.push([srcPlace,destPlace,score]);
				}
			}
		}
		result.sort(function(a,b) {return b[2] - a[2];});
		return {
			placePathDistances = destPlaceDistances.array
			pairs = result
		};
	}
	
	function BuildReturnRoute(route, srcPlace, destPlace) {
		//TODO 後半は駅作成失敗が多くなるので、先に駅が建てられるかを調べる。ルート検索はコストが重いので最後に
		HgLog.Info("# TrainRoute: Try BuildReturnRoute:"+destPlace.GetName()+"<-"+srcPlace.GetName()+" route: "+route);
		
		local testMode = AITestMode();
		local needRollbacks = [];
		local railStationCoverage = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local returnPath = route.GetPathAllDestToSrc();
		local transferStation = GetBuildableStationByPath(returnPath, srcPlace!=null ? srcPlace.GetLocation() : null, route.cargo, route.GetPlatformLength());
		if(transferStation == null) {
			HgLog.Info("TrainRoute: cannot build transfer station");
			return false;
		}
		AIRail.SetCurrentRailType(route.GetRailType());

		local railBuilderTransferToPath;
		local railBuilderPathToTransfer;
		{
			//TODO 失敗時のロールバック
			local aiExecMode = AIExecMode();
			if(!transferStation.BuildExec()) {
				HgLog.Warning("TrainRoute: cannot build transfer station "+HgTile(transferStation.platformTile)+" "+transferStation.stationDirection);
				return false;
			}
			needRollbacks.push(transferStation);
			
			railBuilderTransferToPath = TailedRailBuilder.PathToStation(GetterFunction( function():(route) {
				local returnPath = route.GetPathAllDestToSrc();
				return returnPath.SubPathEnd(returnPath.GetLastTileAt(4)).Reverse();
			}), transferStation, 150, this, null, false);
			railBuilderTransferToPath.cargo = route.cargo;
			railBuilderTransferToPath.platformLength = route.GetPlatformLength();
			railBuilderTransferToPath.isReverse = true;
			if(!railBuilderTransferToPath.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderTransferToPath");
				Rollback(needRollbacks);
				return false;
			}
			
			needRollbacks.push(railBuilderTransferToPath.buildedPath); // TODO Rollback時に元の線路も一緒に消える事がある。limit date:300の時に消えている
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			railBuilderPathToTransfer = TailedRailBuilder.PathToStation(GetterFunction( function():(route, pointTile) {
				return route.GetPathAllDestToSrc().SubPathStart(pointTile);
			}), transferStation, 150, this);
			railBuilderPathToTransfer.cargo = route.cargo;
			railBuilderPathToTransfer.platformLength = route.GetPlatformLength();
			
			if(!railBuilderPathToTransfer.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderPathToTransfer");
				Rollback(needRollbacks);
				return false;
			}
			
			needRollbacks.push(railBuilderPathToTransfer.buildedPath);
			
		}

		
		{
			local returnDestStationFactory = TerminalStationFactory(2);
			returnDestStationFactory.platformLength = route.GetPlatformLength();
			returnDestStationFactory.minPlatformLength = route.GetPlatformLength();
			
			local returnDestStation = returnDestStationFactory.CreateBest(destPlace, route.cargo, transferStation.platformTile, false);
				// station groupを使うと同一路線の他のreturnと競合して列車が迷子になる事がある
			if(returnDestStation == null) {
				HgLog.Warning("TrainRoute:cannot build returnDestStation");
				Rollback(needRollbacks);
				return false;
			}
				
			local aiExecMode = AIExecMode();
			returnDestStation.cargo = route.cargo;
			returnDestStation.isSourceStation = false;
			if(!returnDestStation.BuildExec()) {
				HgLog.Warning("TrainRoute: cannot build returnDestStation");
				Rollback(needRollbacks); // TODO: 稀にtransfer station側に列車が紛れ込んでいてrouteが死ぬ時がある。(正規ルート側にdouble depotがあるケース？）
				return false;
			}
			needRollbacks.push(returnDestStation);
			
			
			
			local railBuilderReturnDestDeparture = TailedRailBuilder.PathToStation(GetterFunction( function():(route, railBuilderTransferToPath) {
				return route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile()).Reverse();
			}), returnDestStation,  150, this, null, false);
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
			railBuilderReturnDestArrival.cargo = route.cargo;
			railBuilderReturnDestArrival.platformLength = route.GetPlatformLength();
			
			if(!railBuilderReturnDestArrival.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderReturnDestArrival");
				Rollback(needRollbacks);
				return false;
			}
			
			needRollbacks.push(railBuilderReturnDestArrival.buildedPath);
			
			local aiExecMode = AIExecMode();

			local returnRoute = TrainReturnRoute(transferStation, returnDestStation, 
				railBuilderPathToTransfer.buildedPath, railBuilderTransferToPath.buildedPath,
				railBuilderReturnDestArrival.buildedPath, railBuilderReturnDestDeparture.buildedPath);
				
			route.returnRoute = returnRoute;
			returnRoute.originalRoute = route;
			returnRoute.Initialize();
			
			PlaceDictionary.Get().AddRoute(returnRoute);
			

			route.AddReturnTransferOrder(transferStation, returnDestStation);
			
			/* SearchAndBuildToMeetSrcDemandTransferの中でやる
			if(srcPlace.IsProcessing() && srcPlace.GetLastMonthProduction(route.cargo) < srcPlace.GetExpectedProduction(route.cargo, AIVehicle.VT_RAIL)) {
				if(transferStation.place != srcPlace) {
					BuildRoute(transferStation.stationGroup, srcPlace, returnRoute.cargo);
				}
				SearchAndBuildToMeetSrcDemandMin(srcPlace, returnRoute);
			}*/
			SearchAndBuildToMeetSrcDemandTransfer(returnRoute);

			HgLog.Info("# TrainRoute: build return route succeeded:"+returnRoute);
		}
		
		return true;
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
	

	function SearchAndBuildToMeetSrcDemandMin(srcPlace, forRoute) {
		if(roiBase) {
			return;
		}
		HgLog.Info("SearchAndBuildToMeetSrcDemandMin srcPlace:"+srcPlace.GetName()+" route:"+forRoute);
		local cargoPlans = GetCargoPlansToMeetSrcDemand(srcPlace.GetAccepting(), forRoute);
		local routePlans = [];
		local multiInputProcessing = srcPlace.IsProcessing() && cargoPlans.len() >= 2;
		if(firs && (multiInputProcessing || srcPlace.IsRaw())) {
			foreach(cargoPlan in cargoPlans) {
				HgLog.Info("CargoPlan: "+AICargo.GetName(cargoPlan.cargo)+" srcPlace:"+srcPlace.GetName()+"(SearchAndBuildToMeetSrcDemandMin)");
				local routePlans = CreateRoutePlans(cargoPlan,null/*結果数の制限無し*/);
				foreach(plan in routePlans) {
					HgLog.Info("routePlan:"+plan.srcPlace.GetName()+" vt:"+plan.vehicleType+" d:"+plan.distance+"  score:"+plan.score);
				}
				foreach(plan in routePlans) {
					DoRoutePlan(plan);
					break
				}
			}
			
		} else {
			foreach(cargoPlan in cargoPlans) {
				routePlans.extend(CreateRoutePlans(cargoPlan,null/*結果数の制限無し*/));
			}
			local count = 0;
			foreach(plan in SortRoutePlans(routePlans)) {
				if(DoRoutePlan(plan) != null) {
					count += plan.deliver;
					if(count >= 300) {
						break;
					}
				} else {
					break; // 失敗したら終わり。無限に失敗し続ける事がある
				}
			}
		}
		HgLog.Info("End SearchAndBuildToMeetSrcDemandMin srcPlace:"+srcPlace.GetName()+" route:"+forRoute);
	}
	
	function SortRoutePlans(routePlans) {
		foreach(plan in routePlans) { // scoreがestimateベースになっているが、ここで利益を上げる必要はないので効果ベースにする
			plan.deliver <- min(Route.GetRouteCapacityVt(plan.vehicleType)*30,plan.production);
			if(plan.vehicleType == AIVehicle.VT_AIR) {
				plan.score = plan.deliver * 100 / 400;
			} else {
				plan.score = plan.deliver * 100 / (plan.distance+100);
			}
		}
		routePlans.sort(function(p1,p2) {
			return p2.score - p1.score;
		});
		return routePlans;
	}


	function CheckTownStatue() {
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
			route.usedRateCache = null;
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
				if(route.IsNotAdditional()) {
					route.CheckRailUpdate();
				}
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
		foreach(townBus in TownBus.instances) {
			townBus.CheckInterval();
		}
	 }
	 	
	function CheckRoadRoute() {
		if(AIBase.RandRange(100) < 30 &&  TrainRoute.instances.len() == 0 /*&& AirRoute.instances.len() == 0 && WaterRoute.instances.len() == 0*/) {
			CommonRoute.CheckReduce(RoadRoute, RoadRoute.instances, maxRoadVehicle);
		}
		foreach(route in RoadRoute.instances) {
			route.CheckBuildVehicle();
		}
		foreach(route in RoadRoute.instances) {
			route.CheckRenewal();
		}
	}
	
	function CheckWaterRoute() {
		foreach(route in WaterRoute.instances) {
			route.CheckBuildVehicle();
		}
		foreach(route in WaterRoute.instances) {
			route.CheckRenewal();
		}
	}
	
	function CheckAirRoute() {
		if(TrainRoute.instances.len() == 0 && TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute)) { //列車が使えるのに、ルート削除＝＞空港建設のループに陥るのを防ぐ
			CommonRoute.CheckReduce(AirRoute, AirRoute.instances, maxAircraft);
		}
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
			foreach(dest in CreateRouteCandidates(cargo, place, Place.GetAcceptingPlaceDistance(cargo, place.GetLocation()))) {
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
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			HgLog.Warning("AddPending:CreateTownTransferRoutes.(AIError.ERR_LOCAL_AUTHORITY_REFUSES)");
			HogeAI.Get().AddPending("CreateTownTransferRoutes",[townBus, route, station],30);
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

	static function DoInterval() {
		HogeAI.Get()._DoInterval();
	}

	function _DoInterval() {
		if(supressInterval) {
			return;
		}
		local times = [];
		if(lastIntervalDate != null && AIDate.GetCurrentDate() < lastIntervalDate + 7) {
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
					HgIndustry.closedIndustries[event.GetIndustryID()] <- true;
					foreach(route in Route.GetAllRoutes()) {
						route.OnIndustoryClose(event.GetIndustryID());
					}
					foreach(pathfinding,_ in pathfindings) {
						pathfinding.OnIndustoryClose(event.GetIndustryID());
					}
					break;
				case AIEvent.ET_INDUSTRY_OPEN:
					event = AIEventIndustryOpen.Convert(event);
					HgLog.Info("ET_INDUSTRY_OPEN:"+AIIndustry.GetName(event.GetIndustryID())+" ID:"+event.GetIndustryID());
					HgIndustry.closedIndustries.rawdelete(event.GetIndustryID());
					break;
				case AIEvent.ET_VEHICLE_LOST:
					OnVehicleLost(AIEventVehicleLost.Convert(event));
					break;
					
			}
		}
	}

	function OnVehicleLost(event) {
		local vehicle = event.GetVehicleID();
		HgLog.Warning("ET_VEHICLE_LOST:"+AIVehicle.GetName(vehicle));
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("Invalid vehicle");
			return;
		}
		local group = AIVehicle.GetGroupID(vehicle);
		local vehicleType = AIGroup.GetVehicleType(group);
		if(vehicleType == AIVehicle.VT_ROAD) {
			foreach(roadRoute in RoadRoute.instances) {
				if(roadRoute.vehicleGroup == group) {
					roadRoute.OnVehicleLost(vehicle);
				}
			}
		} else if(vehicleType == AIVehicle.VT_RAIL) {
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) != 0) {
				HgLog.Warning("ET_VEHICLE_LOST: SendVehicleToDepot");
				AIVehicle.SendVehicleToDepot (vehicle); // 一旦depot行きを解除
			} else {
				HgLog.Warning("ET_VEHICLE_LOST: SkipToOrder to 0"); // 直角カーブ禁止でChangeDestinationしたときにLOSTする(旧dest支線に入っている時)問題の対応。(他の原因の場合、この対応はまずいかもしれない) 
				AIOrder.SkipToOrder(vehicle, 0);
			}
		
		}
	}
	 
	function Save() {
		local remainOps = AIController.GetOpsTillSuspend();
	
		local table = {};	
		table.turn <- turn;
		table.indexPointer <- indexPointer;
		table.stockpiled <- stockpiled;
		table.estimateTable <- estimateTable;
		table.pathFindCostCache <- HgTile.pathFindCostCache;
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
		estimateTable = loadData.estimateTable;
		if(loadData.rawin("pathFindCostCache")) {
			HgTable.Extend( HgTile.pathFindCostCache, loadData.pathFindCostCache );
		}
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
	   if(!AICompany.SetName("AAAHogEx")) {
		 local i = 2;
		 while(!AICompany.SetName("AAAHogEx #" + i)) {
		   i = i + 1;
		   if(i > 255) break;
		 }
	   }
	   AICompany.SetPresidentName("R. Ishibashi");
	}
	 
	function WaitForMoney(needMoney) {
		HogeAI.WaitForPrice(HogeAI.GetInflatedMoney(needMoney));
	}
	
	function GetInflatedMoney(money) {
		local inflationRate = AICompany.GetMaxLoanAmount().tofloat() / AIGameSettings.GetValue("difficulty.max_loan").tofloat();
		return (money * inflationRate).tointeger();
	}
	
	function WaitForPrice(needMoney, buffer = 10000) {
		local execMode = AIExecMode();
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF)-needMoney > AICompany.GetLoanAmount() + buffer) {
			AICompany.SetMinimumLoanAmount(0);
		}
		local first = true;
		while(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < needMoney + buffer) {
			if(first) {
				first = false;
			} else {
				HgLog.Info("wait for money:"+needMoney);
				AIController.Sleep(100);
			}
			local minimamLoan = min(AICompany.GetMaxLoanAmount(), 
					AICompany.GetLoanAmount() + needMoney - AICompany.GetBankBalance(AICompany.COMPANY_SELF) + buffer);
			//HgLog.Info("minimamLoan:"+minimamLoan);
			AICompany.SetMinimumLoanAmount(minimamLoan);
		}
	}
	
	function WaitDays(days) {
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
		return AICompany.GetQuarterlyIncome (AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1) < cost && GetUsableMoney() < cost;
	}
	
	function HasIncome(money) {
		return HogeAI.GetQuarterlyIncome() >= HogeAI.GetInflatedMoney(money);
	}
	
	function GetQuarterlyIncome() {
		local quarterlyIncome = AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		local quarterlyExpnse = AICompany.GetQuarterlyExpenses (AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		return quarterlyIncome + quarterlyExpnse;
	}
	
	function IsRich() {
		local usableMoney = HogeAI.GetUsableMoney();
		return usableMoney > HogeAI.GetInflatedMoney(1000000) || (usableMoney > HogeAI.GetInflatedMoney(500000) && HasIncome(50000));
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
		return GetSetting("pax_mail_only") == 1;
	}
	
	function IsManyTypesOfFreightAsPossible() {
		return GetSetting("many_types_of_freight_as_possible") == 1;
	}
	
	
	function IsDebug() {
		return GetSetting("IsDebug") == 1;
	}
	
	function IsEnableVehicleBreakdowns() {
		return AIGameSettings.GetValue("difficulty.vehicle_breakdowns") >= 1;
	}

	function IsDistantJoinStations() {
		return AIGameSettings.GetValue("station.distant_join_stations") == 1;
	}
	
	function IsInfrastructureMaintenance() {
		return AIGameSettings.GetValue("economy.infrastructure_maintenance") == 1;
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
	}
}
 