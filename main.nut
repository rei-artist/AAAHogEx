
require("utils.nut");
require("tile.nut");
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
	
	static distanceEstimateSamples = [10, 20, 30, 50, 80, 130, 210, 340, 550, 890];
	static productionEstimateSamples = [30, 50, 80, 130, 210, 340, 550, 890, 1440];

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
	
	yeti = null;
	ecs = null;
	
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
		if(!HogeAI.Get().IsAvoidRemovingWater() && AITile.IsSeaTile(tile) && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 2000000) {
			return true;
		}
		return false;
	}
	
	static function IsBuildableRectangle(tile,w,h) {
		if(!HogeAI.Get().IsAvoidRemovingWater() && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 2000000) {
			foreach(t,k in Rectangle.Corner(HgTile(tile), HgTile(tile)+HgTile.XY(w,h)).GetTileList()) {
				if(!AITile.IsSeaTile(t) && !AITile.IsBuildable(t)) {
					return false;
				}
			}
			return true;
		}
		return AITile.IsBuildableRectangle(tile,w,h);
	}
	
	static function GetCargoIncome(distance, cargo, speed, waitingDate=0) {
		if(speed<=0) {
			return 0;
		}
		local days = distance*664/speed/24;
		days = days == 0 ? 1 : days;
		local income = AICargo.GetCargoIncome(cargo,distance,days + (waitingDate/2).tointeger());
		if(HogeAI.IsBidirectionalCargo(cargo)) {
			income = income * 3 / 2;
		}
		return income * 365 / (days * 2 + waitingDate);
	}

	static function IsBidirectionalCargo(cargo) {
		local townEffect = AICargo.GetTownEffect(cargo);
		return townEffect == AICargo.TE_PASSENGERS || townEffect == AICargo.TE_MAIL;
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
		isTimeoutToMeetSrcDemand = false;
		pendings = [];
		DelayCommandExecuter();
	}
	 
	function Start() {
		HgLog.Info("AAAHogEx Started!");
		
		HgLog.Info("aaa:" + AAA.func(AAA) + " bbb:" + BBB.func(BBB));
		
		local newGrfList = AINewGRFList();
		newGrfList.Valuate( AINewGRF.IsLoaded );
		newGrfList.KeepValue( 1 );
		
		foreach( newGrf,v in newGrfList ) {
			local name = AINewGRF.GetName(newGrf);
			HgLog.Info("NewGRF:" + name);
			if(name.find("YETI") != null) {
				yeti = true;
				stockpiled = true;
			}
			if(name.find("ECS") != null) {
				ecs = true;
				stockpiled = true;
			}
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
		
		maxStationSpread = AIGameSettings.GetValue("station.station_spread");
		maxStationSpread = maxStationSpread == -1 ? 12 : maxStationSpread;
		maxTrains = AIGameSettings.GetValue("vehicle.max_trains");
		maxRoadVehicle = AIGameSettings.GetValue("vehicle.max_roadveh");
		maxShips = AIGameSettings.GetValue("vehicle.max_ships");
		maxAircraft = AIGameSettings.GetValue("vehicle.max_aircraft");
		isUseAirportNoise = AIGameSettings.GetValue("economy.station_noise_level")==1 ? true : false;
		
		HgLog.Info("maxStationSpread:"+maxStationSpread);
		HgLog.Info("maxTrains:"+maxTrains);
		HgLog.Info("maxRoadVehicle:"+maxRoadVehicle);
		HgLog.Info("maxShips:"+maxShips);
		HgLog.Info("maxAircraft:"+maxAircraft);
		HgLog.Info("isUseAirportNoise:"+isUseAirportNoise);

		AICompany.SetAutoRenewStatus(false);
		SetCompanyName();

		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());

		indexPointer ++;
		while (true) {
			HgLog.Info("######## turn "+turn+" ########");
			while(indexPointer < 4) {
				AIController.Sleep(1);
				roiBase = GetUsableMoney() < GetInflatedMoney(500000) && !HasIncome(200000);
				if(roiBase) {
					HgLog.Info("### roiBase");
				}
				limitDate = AIDate.GetCurrentDate() + 600;
				ResetEstimateTable();
				DoInterval();
				DoInterrupt();
				DoStep();
				indexPointer ++;
			}
			indexPointer = 0;
			turn ++;
		}
	}
	
	function DoStep() {
		switch(indexPointer) {
			case 0:
				SearchAndBuildToMeetSrcDemandUsingRailTransfer();
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
		foreach(cargo ,dummy in AICargoList()) {
			local vehicleEstimates = {};
			estimateTable[cargo] <- vehicleEstimates;
			foreach(vt in [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_WATER, AIVehicle.VT_AIR]) {
				local prodctionEstimates = array(productionEstimateSamples.len());
				vehicleEstimates[vt] <- prodctionEstimates;
				for(local i=0 ;i<prodctionEstimates.len(); i++) {
					prodctionEstimates[i] = array(distanceEstimateSamples.len());
				}
			}
		}
	}
	
	function ScanPlaces() {
		HgLog.Info("###### Scan places");
		/*
		if(isTimeoutToMeetSrcDemand) {
			return;
		}*/
		AIController.Sleep(1);
		local aiTestMode = AITestMode();
		
		local bests = [];
		local candidate;
		local routeCandidatesGen = GetRouteCandidatesGen();
		for(local i=0; (candidate=resume routeCandidatesGen) != null && i<200; i++) {
			bests.push(candidate);
		}
		
		bests.sort(function(a,b) {
			return b.score-a.score; 
		});
		
		//bests = bests.slice(0, min(bests.len(), 50));
		foreach(e in bests) {
			HgLog.Info("score"+e.score+" production:"+e.production+" value:"+e.estimate.value+" vt:"+e.vehicleType
				+" "+e.destPlace.GetName() + "<-" + e.place.GetName()+" "+AICargo.GetName(e.cargo)+" distance:"+e.distance);
		}
		
		limitDate = AIDate.GetCurrentDate() + 300;
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
				if(GetUsableMoney() < GetInflatedMoney(300000)) {
					WaitDays(60); // 建設にコストを掛けすぎて車両が作れなくなる事を防ぐ為に、車両作成の為の時間を空ける
				}
			}
			if(limitDate < AIDate.GetCurrentDate()) {
				return;
			}
		}
	}
	
	function ScanRoutes() {
		HgLog.Info("###### Scan routes");
		
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
			if(route.IsRemoved() || route.transferRoute != null || route.IsUpdatingRail()) {
				continue;
			}
			AIRail.SetCurrentRailType(route.GetRailType());
			route.isBuilding = true;


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
			
			if(limitDate > AIDate.GetCurrentDate()) {
				break;
			}
		}
	}
	
	function GetRouteCandidatesGen() {
		local considerSlope = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		local maxDistance = !HasIncome(1000) ? 100 : 200;
		foreach(i, src in GetMaxCargoPlaces()) {
			//src.production = Place.AdjustProduction(src.place, src.production);
			local count = 0;
			foreach(dest in CreateRouteCandidates(src.cargo, src.place, 
					Place.GetAcceptingPlaceDistance(src.cargo, src.place.GetLocation()))) {
				if((dest.vehicleType == AIVehicle.VT_ROAD || dest.vehicleType == AIVehicle.VT_RAIL) && dest.distance > maxDistance) {
					continue;
				}
				local routeClass = Route.GetRouteClassFromVehicleType(dest.vehicleType);
				if(routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
					continue;
				}
				
				local route = {};
				route.cargo <- src.cargo;
				route.place <- src.place;
				route.production <- src.production;
				route.maxValue <- src.maxValue;
				route.distance <- dest.distance;
				route.destPlace <- dest.place;
				route.vehicleType <- dest.vehicleType;
				route.estimate <- dest.estimate;
				route.score <- dest.score;
				
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
					route.score = route.score * 3 / (3 + max( AITile.GetMaxHeight(route.destPlace.GetLocation()) - AITile.GetMaxHeight(route.place.GetLocation()) , 0 ));
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

	function CreateRouteCandidates(cargo, orgPlace, placeDistances, minProduction=0) {
		local orgTile = orgPlace.GetLocation();
		local orgPlaceAcceptingRaw = orgPlace.IsAccepting() && orgPlace.IsRaw();
		local orgPlaceTraits = orgPlace.GetIndustryTraits();
		local orgPlaceProduction = orgPlace.GetExpectedProduction(cargo) / (orgPlace.GetRoutesUsingSource(cargo).len() + 1);
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		local isNgAir = !orgPlace.CanBuildAirport(minimumAiportType, cargo);
		local isNgWater = !orgPlace.IsNearWater(cargo);
		
		local candidates = placeDistances.Map(function(placeDistance)
				: (cargo,orgTile,orgPlace,orgPlaceAcceptingRaw, orgPlaceTraits, orgPlaceProduction, isNgAir, isNgWater, minProduction)  {
			local result = [];
			local t = {};
			t.cargo <- cargo;
			t.place <- placeDistance[0];
			t.distance <- max(0, placeDistance[1] - orgPlace.GetRadius() - t.place.GetRadius());
			
			local placeProduction = t.place.GetExpectedProduction(cargo) / (t.place.GetRoutesUsingSource(cargo).len() + 1);
			local vehicleTypes = [];
			if(t.distance < 300) {
				vehicleTypes.extend([AIVehicle.VT_RAIL, AIVehicle.VT_ROAD]);
			}
			if(t.distance < 500 && !isNgWater) {
				vehicleTypes.push(AIVehicle.VT_WATER);
			}
			if(!isNgAir) {
				vehicleTypes.push(AIVehicle.VT_AIR);
			}
			
			foreach(vt in vehicleTypes) {
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
				
				if(Route.SearchRoutes( Route.GetRouteWeightingVt(vt), srcPlace, destPlace, null, cargo ).len() >= 1) {
					continue;
				}
				
				local isBidirectional = orgPlace.IsAcceptingAndProducing(cargo) && t.place.IsAcceptingAndProducing(cargo);
				local production;
				if(!isBidirectional) {
					production = orgPlace.IsProducing() ? orgPlaceProduction : placeProduction;
				} else {
					production = min( orgPlaceProduction, placeProduction );
				}
				local estimate = Route.Estimate( vt, cargo, t.distance, max(minProduction, production) );
				if(estimate != null) {
					local candidate = clone t;
					
					candidate.estimate <- estimate;
					candidate.vehicleType <- vt;
					candidate.score <- estimate.value;
					if(!isBidirectional && HogeAI.IsBidirectionalCargo(cargo)) {
						candidate.score /= 2;
					}/*
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
			if(candidate.vehicleType == AIVehicle.VT_RAIL || candidate.vehicleType == AIVehicle.VT_ROAD) {
				local cost = HgTile(orgTile).GetPathFindCost(HgTile(candidate.place.GetLocation()));
				if(cost > 300) {
					continue;
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
			if(result.len() >= 20) {
				break;
			}
		}
		
		HgLog.Info("CreateRouteCandidates: " + orgPlace.GetName()+ " cargo:"+AICargo.GetName(cargo) + " result:"+result.len());
		return result;
	}
	 
 
 
 
	function CheckAndBuildCascadeRoute(destPlace,cargo) {
		if(stockpiled && AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000) {
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
	
	function BuildRouteAndAdditional(dest,srcPlace,cargo) {
		
		local route = BuildRoute(dest, srcPlace, cargo);
		if(route == null) {
			if(dest instanceof Place) {
				Place.AddNgPathFindPair(dest,srcPlace,AIVehicle.VT_RAIL);
			} else {
				Place.AddNgPathFindPair(GetLocationFromDest(dest), srcPlace, AIVehicle.VT_RAIL);
			}
			return null;
		}
		
		
		route.isBuilding = true;
		SearchAndBuildToMeetSrcDemandUsingRailTransfer(route);
		SearchAndBuildToMeetSrcDemandTransfer(route);
		if(route.transferRoute == null) {
			SearchAndBuildAdditionalSrc(route);
		}

		if(route.transferRoute == null) {
			/*
			while(!CheckAndBuildCascadeRoute(dest,cargo)) { markChangeDestの関係でここはScanPlaceでやる
				dest = SearchAndBuildAdditionalDest(route)
				if(dest == null) {
					break;
				}
			}*/
			if(route.IsBiDirectional()) {
				SearchAndBuildToMeetSrcDemandUsingRailTransfer(route);
				SearchAndBuildToMeetSrcDemandTransfer(route);
			}
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
	
	
	function SearchAndBuildToMeetSrcDemandUsingRailTransfer(originalRoute=null) {
		HgLog.Info((originalRoute==null ? "###### " : "") + "Search and build to meet src demand using rail transfer."+(originalRoute!=null?originalRoute:"(all)"));
		
		local routeClass = Route.GetRouteClassFromVehicleType(AIVehicle.VT_RAIL);
		if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
			return;
		}
		
		local minDistance = RoadRoute.GetMaxTotalVehicles() == 0 ? 1 : 40;
		
		local additionalPlaces = [];
		local routes = [];
		if(originalRoute != null) {
			routes.push(originalRoute);
		} else {
			routes.extend(TrainRoute.GetAll());
		}
		foreach(route in routes) {
			if(route instanceof RoadRoute) {
				continue;
			}
			if(!route.NeedsAdditionalProducing()) {
				continue;
			}
			if(route instanceof TrainReturnRoute && route.GetFinalDestPlace() != null) {
				foreach(data in Place.SearchSrcAdditionalPlaces( 
						route.srcHgStation, route.GetFinalDestPlace().GetLocation(), 
						route.cargo, minDistance, 130, 50, 80, 200, AIVehicle.VT_RAIL)) {
					local t = {};
					t.route <- route;
					t.cargo <- route.cargo;
					t.dest <- route;
					t.srcPlace <- data.place;
					t.distance <- data.distance;
					t.production <- data.production;
					t.score <- 0;
					additionalPlaces.push(t);
					break;
				}
			}
			DoInterval();
		}
		local limitDate = AIDate.GetCurrentDate() + 100;
		if(additionalPlaces.len() >= 1) {
			additionalPlaces.sort(function(a,b) {
				return b.score - a.score;
			});
			foreach(t in additionalPlaces) {
				if(!PlaceDictionary.Get().CanUseAsSource(t.srcPlace,t.cargo)) {
					continue;
				}
				HgLog.Info("Found producing place using rail "+t.dest+"<-"+t.srcPlace.GetName()+" route:"+t.route);
				BuildRouteAndAdditional(t.dest, t.srcPlace, t.cargo);
				DoInterval();
				if(limitDate < AIDate.GetCurrentDate()) {
					break;
				}
			}
		}
		
	}
	
	function GetPlansToMeetSrcDemandTransfer(route,isDest,vehicleType) {
		if(route.GetVehicleType() == vehicleType) {
			return [];
		}
		local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
		if(routeClass.IsTooManyVehiclesForSupportRoute(routeClass)) {
			return [];
		}

		local maxDistance = 200;
		if(roiBase) {
			maxDistance = min(maxDistance, route.GetDistance() / 2);
		}
		
		local additionalPlaces = [];
		local hgStation = isDest ? route.destHgStation : route.srcHgStation;
		if(route.GetFinalDestPlace() == null) {
			return [];
		}
		local finalDestLocation = isDest ? route.srcHgStation.platformTile : route.GetFinalDestPlace().GetLocation();
		
		foreach(data in Place.SearchSrcAdditionalPlaces( 
				hgStation, finalDestLocation, 
				route.cargo, 0, maxDistance, 1, 80, 200, vehicleType)) {
			if(vehicleType == AIVehicle.VT_WATER && !hgStation.stationGroup.IsNearWater()) {
				continue;
			}
			if(!data.place.CanUseTransferRoute(route.cargo, vehicleType)) {
				continue;
			}
			local t = {};
			t.route <- route;
			t.cargo <- route.cargo;
			t.dest <- hgStation.stationGroup;
			t.srcPlace <- data.place;
			t.distance <- data.distance;
			t.production <- data.production;
			t.isRaw <- false;
			additionalPlaces.push(t);
		}
		return additionalPlaces;
	}
		
	function GetCargoPlansToMeetSrcDemand(acceptingPlace, forRoute = null) {
		local result = [];
		if(!acceptingPlace.IsIncreasable()) {
			return result;
		}
		
		local cargos = acceptingPlace.GetCargos();
		if(cargos.len() == 0) {
			return result;
		}
		
		local stockpiledAverage = 0;
		if(stockpiled) {
			foreach(cargo in cargos) {
				stockpiledAverage += acceptingPlace.GetStockpiledCargo(cargo);
			}
			stockpiledAverage /= cargos.len();
		}
		
		local producingPlace = acceptingPlace.GetProducing();
		
		local labelCargoMap = {};
		local totalSupplied = 0;
		foreach(cargo in cargos) {
			labelCargoMap.rawset(AICargo.GetCargoLabel(cargo),cargo);
			foreach(route in acceptingPlace.GetRoutesUsingDest(cargo)) {
				totalSupplied += route.GetRouteWeighting();
			}
		}
		local totalNeeds = 0;
		foreach(cargo in producingPlace.GetCargos()) {
			foreach(route in producingPlace.GetRoutesUsingSource(cargo)) {
				totalNeeds += route.GetRouteWeighting();
			}
		}
		
		
		local cargoScores = {};
		local cargoScoreExplain = {};
		local totalSupplied = 0;
		local stopped = 0;
		
		foreach(cargo in cargos) {
			local scoreExplain = "SRC";
			local score = 0; // 1以上: 探す 4以上: cargoを作りに行く
			local supplied = 0;
			
			foreach(route in acceptingPlace.GetRoutesUsingDest(cargo)) { //満たされていないcargoを優先する(for FIRS)
				supplied += route.GetRouteWeighting();
			}
			HgLog.Info("supplied:"+supplied+" "+acceptingPlace.GetName()+" "+AICargo.GetName(cargo));
			
			score -= supplied;
			scoreExplain += "-"+supplied+"(supplied)";
			totalSupplied += supplied;
			if(stockpiled) {
				if(!acceptingPlace.IsCargoAccepted(cargo)) {
					stopped += supplied;
					HgLog.Info("stopped:"+stopped+" "+acceptingPlace.GetName()+" "+AICargo.GetName(cargo));
					continue;
				}
				if(acceptingPlace.GetStockpiledCargo(cargo) == 0) {
					score += 1;
					scoreExplain += "+1(stockpile==0)"
				}
				if(acceptingPlace.GetStockpiledCargo(cargo) < stockpiledAverage) {
					score += 1;
					scoreExplain += "+1(stockpile<stockpiledAverage)"
				}
			} else {
				score += 1;
				scoreExplain += "1(default)"
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
			local industryTraits = acceptingPlace instanceof HgIndustry ? acceptingPlace.GetIndustryTraits() : "";
			if(yeti) {
				if(acceptingPlace.GetName().find("4X ") != null) { // Worker Yard
					if(cargoLabel == "PASS") {
						if(acceptingPlace.GetStockpiledCargo(cargo) == 0) {
							local sunk = totalNeeds + totalSupplied + 1;
							score += sunk;
							scoreExplain += "+"+sunk+"(PASS)"
						} else {
							score = 0;
							scoreExplain = "0(PASS)"
						}
					} else if(cargoLabel == "FOOD") {
						if(acceptingPlace.GetStockpiledCargo(cargo) == 0 
								&& acceptingPlace.GetStockpiledCargo(labelCargoMap["PASS"]) >= 1) {
							local sunk = totalNeeds + totalSupplied + 1;
							score += sunk;
							scoreExplain += "+"+sunk+"(FOOD)"
						} else {
							score = 0;
							scoreExplain = "0(FOOD)"
						}
					} else if(cargoLabel == "BDMT") {
						if(acceptingPlace.GetStockpiledCargo(cargo) == 0
								&& acceptingPlace.GetStockpiledCargo(labelCargoMap["PASS"]) >= 1
								&& acceptingPlace.GetStockpiledCargo(labelCargoMap["FOOD"]) >= 1) {
							local sunk = totalNeeds + totalSupplied + 1;
							score += sunk;
							scoreExplain += "+"+sunk+"(BDMT)"
						} else {
							score = 0;
							scoreExplain = "0(BDMT)"
						}
					}
				} else {
					if(cargoLabel == "YETI") {
						if(acceptingPlace.GetStockpiledCargo(cargo) == 0) {
							local sunk = totalNeeds + totalSupplied + 1;
							score += sunk;
							scoreExplain += "+"+sunk+"(YETI)"
						} else {
							score = 0;
							scoreExplain = "0(YETI)"
						}
					} else {
						if(acceptingPlace.GetStockpiledCargo(cargo) == 0
								&& (!labelCargoMap.rawin("YETI")
									|| acceptingPlace.GetStockpiledCargo(labelCargoMap["YETI"]) >= 1)) {
							local sunk = totalNeeds + totalSupplied + 1;
							score += sunk;
							scoreExplain += "+"+sunk+"("+cargoLabel+")"
						} else {
							score = 0;
							scoreExplain = "0("+cargoLabel+")"
						}
					}
				}
			}
			/*
			if(ecs) {
				local cargoLabel = AICargo.GetCargoLabel(cargo);
				if(cargoLabel == "DYES") {
					score -= 1;
					scoreExplain += "-1(DYES)"
				}
				if(cargoLabel == "GLAS") {
					score -= 1;
					scoreExplain += "-1(GLAS)"
				}
				if(cargoLabel == "COAL") {
					score -= 1;
					scoreExplain += "-1(COAL)"
				}
				if(industryTraits == "FERT,FOOD,/FISH,STEL,LVST,") {
					if(cargoLabel == "STEL") {
						score -= 1;
						scoreExplain += "-1(STEL(Tinning Factory))"
					}
				} else if(industryTraits == "VEHI,/DYES,GLAS,STEL,") {
					if(cargoLabel == "STEL") {
						score += 1;
						scoreExplain += "+1(STEL(Vehicles factory))"
					}
				}
			}
			*/
			
			cargoScores[cargoLabel] <- {
				cargo = cargo
				score = score
				explain = scoreExplain
				supplied = supplied
			};
		}
		
		if(!acceptingPlace.IsRaw() && !acceptingPlace.IsProcessing()) { // この場合全てのcargoを満たさなくても良い(FIRSでは)
			if(totalSupplied >= 2) {
				return result;
			}
		}
		/*
		if(ecs) {
			if(industryTraits == "GOOD,/FICR,DYES,WOOL,") {
				if(cargoScores["FICR"].supplied >= 1) {
					cargoScores["WOOL"].score -= 1;
					cargoScores["WOOL"].scoreExplain += "-1(Textile mill)"
				}
				if(cargoScores["WOOL"].supplied >= 1) {
					cargoScores["FICR"].score -= 1;
					cargoScores["FICR"].scoreExplain += "-1(Textile mill)"
				}
				if(cargoScores["WOOL"].supplied >= 1 || cargoScores["FICR"].supplied >= 1) {
					cargoScores["DYES"].score += 2;
					cargoScores["DYES"].scoreExplain += "+2(Textile mill)"
				}
			}
			if(industryTraits == "GOOD,/DYES,PAPR,") {
				if(cargoScores["PAPR"].supplied >= 1) {
					cargoScores["DYES"].score += 1;
					cargoScores["DYES"].scoreExplain += "+1(Textile mill)"
				}
				if(cargoScores["WOOL"].supplied >= 1) {
					cargoScores["FICR"].score -= 1;
					cargoScores["FICR"].scoreExplain += "-1(Textile mill)"
				}
				if(cargoScores["WOOL"].supplied >= 1 || cargoScores["FICR"].supplied >= 1) {
					cargoScores["DYES"].score += 2;
					cargoScores["DYES"].scoreExplain += "-2(Textile mill)"
				}
			}
		}
		*/
		
		foreach(cargoLabel, cargoScore in cargoScores) {
			if(stockpiled && !acceptingPlace.IsRaw()) {
				cargoScore.score += stopped;
				cargoScore.explain += "+"+stopped+"(stopped)";
			}
/*			if(ecs) {
				if(cargoScore.supplied == 0) {
					cargoScore.score += totalSupplied / 2;
					cargoScore.explain += "+"+(totalSupplied / 2)+"(supplied==0)"
				}
			} else {*/
				if(totalSupplied == 0 && acceptingPlace.IsProcessing()) {
					cargoScore.score += 2;
					cargoScore.explain += "+2(IsProcessing && totalSupplied==0)"
				}
//			}
			
			local cargoPlan = {};
			cargoPlan.place <- acceptingPlace;
			cargoPlan.cargo <- cargoScore.cargo;
			cargoPlan.score <- cargoScore.score;
			cargoPlan.scoreExplain <- cargoScore.explain;
			if(forRoute != null) {
				cargoPlan.forRoute <- forRoute;
			}
			result.push(cargoPlan);
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
				supplied += route.GetRouteWeighting();
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
					used += route.GetRouteWeighting();
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
				cargoPlan.score <- score;
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
							routeScore = routeScore
							cargoPlans = cargoPlans
						});
					} else {
						placePlans[placeId].routeScore = max(placePlans[placeId].routeScore, routeScore);
					}
				}
				
				DoInterval();
			}
			local cargoPlans = [];
			foreach(placeId, placePlan in placePlans) {
				foreach(cargoPlan in placePlan.cargoPlans) {
					cargoPlan.score += placePlan.routeScore;
					cargoPlan.scoreExplain += "routeScore:+"+placePlan.routeScore;
					cargoPlans.push(cargoPlan);
				}
			}
			
			if(cargoPlans.len() == 0) {
				break;
			}
			
			local demandAndSupplyPlans = []
			foreach(cargoPlan1 in cargoPlans) {
				if(!cargoPlan1.place.IsProducing() || cargoPlan1.score < 4) { // 出力側は強い必要が無ければマッチする必要は無い。単純にたくさん取れるところから引くべき
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
							score = cargoPlan2.score + 1
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
			foreach(routePlan in CreateRoutePlans( cargoPlan )) {
				local accepting = routePlan.srcPlace.GetAccepting();
				if(routePlan.production == 0 && accepting.GetRoutesUsingDest().len() == 0) {
					local srcName = accepting.GetName()+ "["+AICargo.GetName(routePlan.cargo)+"]";
					HgLog.Warning("routePlan: "+ srcName + " is not producing."
						+ "Search routePlan to meet the demand for the srcPlace recursivly.");
					if(searchedPlaces.rawin(accepting.Id())) {
						HgLog.Warning("routePlan: Not found producing place.(circular reference)"+srcName);
						return true; // ゼロ生産施設へのルートを建設する為にtrueを返す
					}
					searchedPlaces.rawset(accepting.Id(), true);
					if(!DoCargoPlans( GetCargoPlansToMeetSrcDemand( accepting ), searchedPlaces ) ) {
						if(limitDate < AIDate.GetCurrentDate()) {
							isTimeoutToMeetSrcDemand = cargoPlan.score >= 4;
						}
						return false;
					}
				}
				local routeBuilder = routePlan.routeClass.GetBuilderClass()(routePlan.destPlace, routePlan.srcPlace, routePlan.cargo);
				if(!routeBuilder.ExistsSameRoute()) {
					HgLog.Info(routeBuilder + ( cargoPlan.rawin("forRoute") ? " for:"+cargoPlan.forRoute:"") );
					local newRoute = routeBuilder.Build();
					if(newRoute != null) {
						newRoute.cannotChangeDest = true;
						if(limitDate < AIDate.GetCurrentDate()) {
							isTimeoutToMeetSrcDemand = cargoPlan.score >= 4;
							return false;
						} else {
							return true;
						}
					}
				}
				if(limitDate < AIDate.GetCurrentDate()) {
					isTimeoutToMeetSrcDemand = cargoPlan.score >= 4;
					return false;
				}
				if(cargoPlan.score <= 0) {
					return false;
				}
			}
			DoInterval();
		}
		return false;
	}
	
	function CreateRoutePlans(cargoPlan) {
		local minProduction = 200; // 将来、最低これくらいの輸送量になる事は見越して輸送手段を選ぶ
		local routePlans = [];
		local cargo = cargoPlan.cargo;
		if(cargoPlan.rawin("destPlace")) {
			local placeDistances = HgArray([[cargoPlan.destPlace, AIMap.DistanceManhattan(cargoPlan.destPlace.GetLocation(), cargoPlan.srcPlace.GetLocation())]]);
			foreach(destCandidate in CreateRouteCandidates(cargo, cargoPlan.srcPlace, placeDistances, minProduction)) {
				local routePlan = {};
				local routeClass = Route.GetRouteClassFromVehicleType(destCandidate.vehicleType);
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
			
			foreach(srcCandidate in CreateRouteCandidates(cargo, acceptingPlace, 
					 Place.GetProducingPlaceDistance(cargo, acceptingPlace.GetLocation(), maxDistance ), minProduction)) {
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
					Place.GetAcceptingPlaceDistance(cargo, producingPlace.GetLocation()), minProduction)) {
				local routePlan = {};
				local routeClass = Route.GetRouteClassFromVehicleType(destCandidate.vehicleType);
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
		
		routePlans.sort(function(a,b) {
			return b.score - a.score;
		});
		
		return routePlans;
	}
		
	
	function SearchAndBuildToMeetSrcDemandTransfer(originalRoute=null, routeClass=null) {
		if(routeClass != null) {
			HgLog.Info("Search and build to meet src demand transfer using "+routeClass.GetLabel()+"."+(originalRoute!=null?originalRoute:"(all)"));
		} else  {
			local b = SearchAndBuildToMeetSrcDemandTransfer(originalRoute, WaterRoute);
			local a = SearchAndBuildToMeetSrcDemandTransfer(originalRoute, RoadRoute);
			return a || b;
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
		
		foreach(route in routes) {
			if(route.NeedsAdditionalProducing()) {
				if(route.GetVehicleType() != AIVehicle.VT_ROAD) {
					additionalPlaces.extend(GetPlansToMeetSrcDemandTransfer(route,false, routeClass.GetVehicleType()));
				}
			}
			if(route.IsBiDirectional() && route.NeedsAdditionalProducing(null,true)) {
				if(route.GetVehicleType() != AIVehicle.VT_ROAD) {
					additionalPlaces.extend(GetPlansToMeetSrcDemandTransfer(route, true, routeClass.GetVehicleType()));
				}
			}
			
			DoInterval();
		}
		foreach(t in additionalPlaces) {
			t.score <- t.production * 100 * (t.isRaw ? 3 : 1) / (t.distance+20);
		}
	
		additionalPlaces.sort(function(a,b) {
			return b.score - a.score;
		});
		local limitDate = AIDate.GetCurrentDate() + 30;
		foreach(t in additionalPlaces) {
			if(limitDate < AIDate.GetCurrentDate()) {
				break;
			}
			local routeBuilder = routeClass.GetBuilderClass()(t.dest, t.srcPlace, t.cargo);
			if(!routeBuilder.ExistsSameRoute()) {
				HgLog.Info(routeBuilder+" for:"+t.route);
				routeBuilder.Build();
			}
			DoInterval();
			
		}
		
		return false;
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

		if(route.GetLastRoute().returnRoute != null) {
			return null;
		}
		if(route.trainLength < 7) {
			return null;
		}		
		local maxDistance = 0;
		if(route.IsClosed()) {
			maxDistance = 300;
		} else {
			local currentValue = 0;//route.latestEngineSet.income;
			local estimate = null;
			for(local distance = 0; distance <= 300; distance += 100) {
				estimate = Route.Estimate(AIVehicle.VT_RAIL, route.cargo, route.GetDistance() + distance, route.GetProduction());
				if(estimate == null || estimate.value < currentValue) {
					break;
				}
				currentValue = estimate.value;
				maxDistance = distance;
			}
			if(maxDistance == 0) {
				HgLog.Warning("No need to extend route "+route);
				return null;
			}
			HgLog.Info("SearchAndBuildAdditionalDest maxDistance:"+maxDistance+" "+route);
		}
		
		local lastAcceptingTile = destHgStation.platformTile;
		foreach(placeScore in Place.SearchAdditionalAcceptingPlaces(route.cargo, route.GetSrcStationTiles(), destHgStation.platformTile, maxDistance)) {
			if(placeScore[0].IsSamePlace(destHgStation.place)) {
				continue;
			}
			if(route.IsBiDirectional() && route.srcHgStation.place!=null && destHgStation.place!=null) {
				if(!placeScore[0].GetProducing().CanUseNewRoute(route.cargo, AIVehicle.VT_RAIL)) {
					continue;
				}
				if(placeScore[0].GetProducing().GetLastMonthProduction(route.cargo) 
						< min( route.srcHgStation.place.GetProducing().GetLastMonthProduction(route.cargo), 
							destHgStation.place.GetProducing().GetLastMonthProduction(route.cargo)) * 2 / 3) {
					continue;
				}
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
			break; //1つでも失敗したら終了とする。
		}
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
	
	
	function GetMaxCargoPlaces() {
		local result = []
		
		local quarterlyIncome = AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		local quarterlyExpnse = AICompany.GetQuarterlyExpenses (AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		HgLog.Info("quarterlyIncome: " + quarterlyIncome + " Enpense:" + quarterlyExpnse);
		
		
		local ignoreCargos = {};
		/*
		if(yeti && !roiBase) { // YETIは、YETIが美味しくないので、これをしないと10年は旅客とメールしかやらない
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
		}*/
		
	
		local minimumAiportType = Air.Get().GetMinimumAiportType();
		foreach(cargo ,dummy in AICargoList()) {		
			if(ignoreCargos.rawin(cargo)) {
				continue;
			}
			
			local maxVehicleType = null;
			local maxValue = 0;
			foreach(routeClass in [TrainRoute, RoadRoute, WaterRoute, AirRoute]) {
				if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, routeClass.GetVehicleType()) >= routeClass.GetMaxTotalVehicles()) {
					HgLog.Warning("Too many vehicles."+routeClass.GetLabel());
					continue;
				}
				HgLog.Info("Estimate:" + routeClass.GetLabel()+"["+AICargo.GetName(cargo)+"]");
				foreach(distance in distanceEstimateSamples) {
					local estimate = Route.Estimate(routeClass.GetVehicleType(), cargo, distance, 210);
					if(estimate == null) {
						continue;
					}
					HgLog.Info("Estimate d:"+distance+" roi:"+estimate.roi+" income:"+estimate.routeIncome+" "
						+AIEngine.GetName(estimate.engine)+" runningCost:"+AIEngine.GetRunningCost(estimate.engine)+" capacity:"+estimate.capacity);
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
			foreach(place in Place.GetNotUsedProducingPlaces( cargo ).array) {
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
				
				local production = place.GetLastMonthProduction(cargo);
				if(production > 0) {
					foreach(acceptingCargo in place.GetAccepting().GetCargos()) {
						local s = place.GetStockpiledCargo(acceptingCargo);
						if(s>0) {
							stockpiled = true;
							break;
							//HgLog.Info("GetStockpiledCargo:"+AICargo.GetName(cargo)+" "+s+" "+place.GetName());	
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
			if(cargoResult.len() > 20) {
				cargoResult.sort(function(a,b){
					return -(a.score - b.score);
				});
				result.extend(cargoResult.slice(0,min(cargoResult.len(),20)));
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
	
	function GetValue(roiBase,roi,income) {
		if(roiBase) {
/*			if(roi < 100) {
				return roi;
			} else {
				return income * roi / 100 * roi / 100;
			}*/
			return roi;
		} else {
			return income;
		}
	}
	
	function BuildRoute(dest, srcPlace, cargo) {
		
		local aiExecMode = AIExecMode();
		
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.production = max(50, srcPlace.GetLastMonthProduction(cargo));
		trainPlanner.distance = AIMap.DistanceManhattan(srcPlace.GetLocation(), GetLocationFromDest(dest));
		trainPlanner.skipWagonNum = 3;

		local engineSets = trainPlanner.GetEngineSetsOrder();
		
		if(engineSets.len()==0) {
			HgLog.Info("Not found enigneSet "+AICargo.GetName(cargo));
			return null;
		}
		AIRail.SetCurrentRailType(engineSets[0].railType);
		
		local destTile = null;
		local destHgStation = null;
		destTile = GetLocationFromDest(dest);
		if(dest instanceof Place) {
			if(dest != null) {
				if(dest.GetProducing().IsTreatCargo(cargo)) {
					dest = dest.GetProducing();
				}
			}
			
			destHgStation = TerminalStationFactory().CreateBest(dest, cargo, srcPlace.GetLocation());
		} else  {
			local stationGroup = dest.srcHgStation.stationGroup;
			
			local destStationFactory = TerminalStationFactory(2);//DestRailStationFactory(2);//
			destStationFactory.nearestFor = destTile;
			destHgStation = destStationFactory.SelectBestHgStation( dest.srcHgStation.stationGroup.GetStationCandidatesInSpread(destStationFactory),
				destTile, srcPlace.GetLocation(), "transfer");
		
		}

		if(destHgStation == null) {
			return null;
		}
		
		local srcHgStation = SrcRailStationFactory().CreateBest(srcPlace, cargo, destTile);
		if(srcHgStation == null) {
			return null;
		}

		srcHgStation.cargo = cargo;
		srcHgStation.isSourceStation = true;
		if(!srcHgStation.BuildExec()) { //TODO予約だけしておいて後から駅を作る
			return null;
		}
		destHgStation.cargo = cargo;
		destHgStation.isSourceStation = false;
		if(!destHgStation.BuildExec()) {
			srcHgStation.Remove();
			return null;
		}
		
		local railBuilder = TwoWayStationRailBuilder(srcHgStation, destHgStation, cargo, pathFindLimit, this);
		if(!railBuilder.Build()) {
			HgLog.Warning("railBuilder.Build failed.");
			srcHgStation.Remove();
			destHgStation.Remove();
			return null;
		}
		local route = TrainRoute(
			TrainRoute.RT_ROOT, cargo,
			srcHgStation, destHgStation,
			railBuilder.buildedPath1, railBuilder.buildedPath2);
		if(!(dest instanceof Place)) {
			route.transferRoute = dest;
		}
			
			
		destHgStation.BuildAfter();
		route.BuildFirstTrain();
		TrainRoute.instances.push(route);
		PlaceDictionary.Get().AddRoute(route);
		if(cargo == HogeAI.GetPassengerCargo() && srcPlace instanceof TownCargo) {
			foreach(townBus in TownBus.instances) {
				townBus.CheckTransfer();
			}
		}
		route.CloneAndStartTrain();
		
		HgLog.Info("BuildRoute succeeded: "+route);
		return route;
	}

	function BuildDestRouteAdditional(route, additionalPlace) {
		AIRail.SetCurrentRailType(route.GetRailType());
		if(additionalPlace.GetProducing().IsTreatCargo(route.cargo)) {
			additionalPlace = additionalPlace.GetProducing();
		}
		local additionalHgStation = TerminalStationFactory(route.additionalRoute!=null?3:2).CreateBest(additionalPlace, route.cargo, route.destHgStation.platformTile);
		if(additionalHgStation == null) {
			HgLog.Info("cannot build additional station");
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
			additionalHgStation, route.cargo, pathFindLimit, this);
		railBuilder.isBuildDepotsDestToSrc = true;
		if(!railBuilder.Build()) {
			HgLog.Warning("railBuilder.Build failed.");
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
		
		route.AddAdditionalTiles(removePath1.GetTiles());
		route.AddAdditionalTiles(removePath2.GetTiles());
		
		route.AddDestination(additionalHgStation);

		// dest placeがcloseされた時に再利用できるかもしれない。
		/* Groupで使用されている事があるので残す
		DelayCommandExecuter.Get().Post(300,function():(removePath1,removePath2,oldDestStation) { //TODO: save/loadに非対応
			removePath1.RemoveRails();
			removePath2.RemoveRails();
			oldDestStation.Remove();
		});
		*/
		
		
		if(route.cargo == HogeAI.GetPassengerCargo()) {
			foreach(townBus in TownBus.instances) {
				townBus.CheckTransfer();
			}
		}
			

		HgLog.Info("BuildDestRouteAdditional succeeded: "+route);
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
			additionalHgStation, route.cargo, pathFindLimit, this);
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
		if(stockpiled) { // TODO ECSでは頻繁にdestが受け入れなくなり、destが変更になる事から対応が難しい, YETIも必要な経路では無い事が多い
			return;
		}
	
		if(route.returnRoute == null && route.GetDistance() >= 150 && !route.IsBiDirectional()) {
			local t = SearchReturnPlacePairs(route.GetPathAllDestToSrc(), route.cargo);
			if(t.pairs.len() >= 1) {
				local pair = t.pairs[0];
				HgLog.Info("Found return route:"+pair[0].GetName()+" to "+pair[1].GetName()+" used route:"+route);
				BuildReturnRoute(route,pair[0],pair[1]);
			}/* else if(t.placePathDistances.len() >= 1){
				HgLog.Info("Build empty return route:"+t.placePathDistances[0][0].GetName()+" used route:"+route);
				BuildReturnRoute(route,null,t.placePathDistances[0][0]);
			}*/
		}
	}
	
	function SearchReturnPlacePairs(path,cargo) {
		local srcPlaces = Place.GetNotUsedProducingPlaces( cargo );
		local srcPlaceDistances = srcPlaces.Map(function(place):(cargo) {
			return [place, place.GetLastMonthProduction(cargo)];
		}).Filter(function(placeProduction) {
			return placeProduction[1] >= 50;
		}).Map(function(placeProduction) : (path) {
			placeProduction.extend(HogeAI.GetTileDistancePathFromPlace(placeProduction[0],path));
			return placeProduction;
		}).Filter(function(placeProductionTileDistance) {
			return 0<=placeProductionTileDistance[3] && placeProductionTileDistance[3]<=100;
		});
		
		local destPlaceDistances = Place.GetCargoAccepting(cargo).Map(function(place) : (path) {
			local tileDistance = HogeAI.GetTileDistancePathFromPlace(place,path);
			return [place, tileDistance[0], tileDistance[1]];
		}).Filter(function(placeTileDistance) {
			return placeTileDistance[2]<=100 && placeTileDistance[0].IsAccepting();
		});

		local result = [];
		foreach(placeProductionTileDistance in srcPlaceDistances.array) {
			local srcPlace = placeProductionTileDistance[0];
			local production = placeProductionTileDistance[1];
			local pathTileS = placeProductionTileDistance[2];
			local distanceS = placeProductionTileDistance[3];
			production = Place.AdjustProduction(srcPlace, production);

			foreach(placeTileDistance in destPlaceDistances.array) {
				local destPlace = placeTileDistance[0];
				local pathTileD = placeTileDistance[1];
				local distanceD = placeTileDistance[2];
				local used = HgTile(path.GetTile()).DistanceManhattan(HgTile(path.GetLastTile())) 
					- (HgTile(path.GetLastTile()).DistanceManhattan(HgTile(pathTileS)) + HgTile(path.GetTile()).DistanceManhattan(HgTile(pathTileD)));
				if(used < 100) {
					continue;
				}
				local dCost = HgTile(destPlace.GetLocation()).GetPathFindCost(HgTile(pathTileD));
				local sCost = HgTile(srcPlace.GetLocation()).GetPathFindCost(HgTile(pathTileS));
				local xCost = HgTile(srcPlace.GetLocation()).GetPathFindCost(HgTile(destPlace.GetLocation()));
				if(xCost < (dCost + sCost) * 2) {
					continue;
				}
				local score = destPlace.DistanceManhattan(srcPlace.GetLocation()) * production / (dCost + sCost);
				if(dCost < 100 && sCost < 100) {
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
		local testMode = AITestMode();
		local needRollbacks = [];
		local railStationCoverage = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local returnPath = route.GetPathAllDestToSrc();
		local transferStation = GetBuildableStationByPath(returnPath, srcPlace!=null ? srcPlace.GetLocation() : null, route.cargo);
		if(transferStation == null) {
			HgLog.Info("cannot build transfer station");
			return false;
		}
		AIRail.SetCurrentRailType(route.GetRailType());

		local railBuilderTransferToPath;
		local railBuilderPathToTransfer;
		{
			//TODO 失敗時のロールバック
			local aiExecMode = AIExecMode();
			transferStation.cargo = route.cargo;
			transferStation.isSourceStation = true;
			if(!transferStation.BuildExec()) {
				HgLog.Warning("cannot build transfer station "+HgTile(transferStation.platformTile)+" "+transferStation.stationDirection);
				return false;
			}
			needRollbacks.push(transferStation);
			
			railBuilderTransferToPath = TailedRailBuilder.PathToStation(GetterFunction( function():(route) {
				local returnPath = route.GetPathAllDestToSrc();
				return returnPath.SubPathEnd(returnPath.GetLastTileAt(4)).Reverse();
			}), transferStation, route.cargo, 150, this, null, false);
			railBuilderTransferToPath.isReverse = true;
			if(!railBuilderTransferToPath.BuildTails()) {
				HgLog.Warning("cannot build railBuilderTransferToPath");
				Rollback(needRollbacks);
				return false;
			}
			
			needRollbacks.push(railBuilderTransferToPath.buildedPath); // TODO Rollback時に元の線路も一緒に消える事がある。limit date:300の時に消えている
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			railBuilderPathToTransfer = TailedRailBuilder.PathToStation(GetterFunction( function():(route, pointTile) {
				return route.GetPathAllDestToSrc().SubPathStart(pointTile);
			}), transferStation, route.cargo, 150, this);
			
			if(!railBuilderPathToTransfer.BuildTails()) {
				HgLog.Warning("cannot build railBuilderPathToTransfer");
				Rollback(needRollbacks);
				return false;
			}
			
			needRollbacks.push(railBuilderPathToTransfer.buildedPath);
			
		}

		
		{
			local returnDestStation = TerminalStationFactory(2).CreateBest(destPlace, route.cargo, transferStation.platformTile, false);
				// station groupを使うと同一路線の他のreturnと競合して列車が迷子になる事がある
			if(returnDestStation == null) {
				HgLog.Warning("cannot build returnDestStation");
				Rollback(needRollbacks);
				return false;
			}
				
			local aiExecMode = AIExecMode();
			returnDestStation.cargo = route.cargo;
			returnDestStation.isSourceStation = false;
			if(!returnDestStation.BuildExec()) {
				HgLog.Warning("cannot build returnDestStation");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(returnDestStation);
			
			
			
			local railBuilderReturnDestDeparture = TailedRailBuilder.PathToStation(GetterFunction( function():(route, railBuilderTransferToPath) {
				return route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile()).Reverse();
			}), returnDestStation, route.cargo, 150, this, null, false);
			railBuilderReturnDestDeparture.isReverse = true;
			if(!railBuilderReturnDestDeparture.BuildTails()) {
				HgLog.Warning("cannot build railBuilderReturnDestDeparture");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(railBuilderReturnDestDeparture.buildedPath);
			
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			local railBuilderReturnDestArrival = TailedRailBuilder.PathToStation(GetterFunction( function():(route, pointTile, railBuilderReturnDestDeparture) {
				local pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(pointTile);
				return pathForReturnDest.SubPathStart(railBuilderReturnDestDeparture.buildedPath.path.GetFirstTile());
			}), returnDestStation, route.cargo, 150, this);
			
			if(!railBuilderReturnDestArrival.BuildTails()) {
				HgLog.Warning("cannot build railBuilderReturnDestArrival");
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
			PlaceDictionary.Get().AddRoute(returnRoute);
			

			route.AddReturnTransferOrder(transferStation, returnDestStation);
			
			SearchAndBuildToMeetSrcDemandUsingRailTransfer(returnRoute);
			SearchAndBuildToMeetSrcDemandTransfer(returnRoute);
			

			HgLog.Info("build return route succeeded");
		}
		
		return true;
	}
	
	function Rollback(needRollbacks) {
		local aiExecMode = AIExecMode();
		foreach(e in needRollbacks) {
			e.Remove();
		}
	}
	
	
	function GetBuildableStationByPath(path, toTile, cargo) {
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
				station.score = station.GetBuildableScore() + (station.IsProducingCargo(cargo) ? 20 : 0);
			}
			stations.sort(function(a,b) {
				return b.score-a.score;
			});
			HgLog.Info("GetBuildableStationByPath stations:"+stations.len());
			foreach(station in stations) {
				if(station.Build(true, true)) {
					station.levelTiles = true; //TODO: stationが保持するのは不適切。StationBuildをクラス化
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

/*		local s = "";
		local pre = null;
		foreach(time in times) {
			if(pre!=null) {
				s += (time - pre) + " ";
			}
			pre = time;
		}
		HgLog.Info("CheckTrainRoute "+ s);
		PerformanceCounter.Print();*/
	}
	 
	 function CheckBus() {
		foreach(townBus in TownBus.instances) {
			townBus.CheckInterval();
		}
	 }
	 	
	function CheckRoadRoute() {
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
	
		CommonRoute.CheckReduce(AIVehicle.VT_AIR, AirRoute.instances, maxAircraft);
		foreach(route in AirRoute.instances) {
			route.CheckBuildVehicle();
		}
		foreach(route in AirRoute.instances) {
			route.CheckRenewal();
		}
	}

	 
	function OnPathFindingInterval() {
		DoInterval();
		return true;
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
	
	
	function AddPending(method, arg) {
		pendings.push({
			method = method
			arg = arg
		});
	}

	function DoPending() {
		foreach(pending in pendings) {
			switch (pending.method) {
				case "BuildDestRoute":
					BuildDestRoute(Place.Load(pending.arg[0]), pending.arg[1]);
					break;
			}
		}
		pendings.clear();
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
		local currentRailType = AIRail.GetCurrentRailType();
		
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
		//HgLog.Info("DoInterval "+ s + " total:"+(pre - lastIntervalDate));
		lastIntervalDate = AIDate.GetCurrentDate();
		
		AIRail.SetCurrentRailType(currentRailType);
		
	}
		 
	 function CheckEvent() {
		while(AIEventController.IsEventWaiting()) {
			local event = AIEventController.GetNextEvent();
			switch(event.GetEventType()) {
				case AIEvent.ET_VEHICLE_WAITING_IN_DEPOT:
					break;
				case AIEvent.ET_INDUSTRY_CLOSE:
					event = AIEventIndustryClose.Convert(event);
					HgLog.Info("ET_INDUSTRY_CLOSE:"+AIIndustry.GetName(event.GetIndustryID()));
					HgIndustry.closedIndustries[event.GetIndustryID()] <- true;
					foreach(route in Route.GetAllRoutes()) {
						route.OnIndustoryClose(event.GetIndustryID());
					}
					break;
				case AIEvent.ET_INDUSTRY_OPEN:
					event = AIEventIndustryOpen.Convert(event);
					HgLog.Info("ET_INDUSTRY_OPEN:"+AIIndustry.GetName(event.GetIndustryID()));
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
			HgLog.Warning("ET_VEHICLE_LOST vehicleType == AIVehicle.VT_RAIL");
		}
	}
	 
	function Save() {
		local remainOps = AIController.GetOpsTillSuspend();
	
		local table = {};	
		table.turn <- turn;
		table.indexPointer <- indexPointer;
		table.pendings <- pendings;
		table.stockpiled <- stockpiled;
		table.estimateTable <- estimateTable;
		
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
		pendings = loadData.pendings;
		stockpiled = loadData.stockpiled;
		estimateTable = loadData.estimateTable;
		
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
	 
	 
	 function SetCompanyName()
	 {
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
	
	function WaitForPrice(needMoney) {
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF)-needMoney > AICompany.GetLoanAmount() + 10000) {
			AICompany.SetMinimumLoanAmount(0);
		}
		local first = true;
		while(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < needMoney + 5000) {
			if(first) {
				HgLog.Info("wait for money:"+needMoney);
				first = false;
			} else {
				AIController.Sleep(10);			
			}
			AICompany.SetMinimumLoanAmount(
				min(AICompany.GetMaxLoanAmount(), 
					AICompany.GetLoanAmount() + needMoney - AICompany.GetBankBalance(AICompany.COMPANY_SELF) + 10000));
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
		local quarterlyIncome = AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		local quarterlyExpnse = AICompany.GetQuarterlyExpenses (AICompany.COMPANY_SELF, AICompany.CURRENT_QUARTER + 1);
		return quarterlyIncome + quarterlyExpnse >= HogeAI.GetInflatedMoney(money);
	}
	
	function IsAvoidRemovingWater() {
		return GetSetting("Avoid removing water") == 1;	

	}
}
 