
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
require("airport.nut");


class HogeAI extends AIController {
	static container = Container();
	static notBuildableList = AIList();
	
	
	indexPointer = 0;
	pendings = null;
	stockpiled = null;
	
	maxStationSpread = null;
	maxTrains = null;
	maxRoadVehicle = null;
	maxAircraft = null;
	isUseAirportNoise = null;

	pathFindLimit = 150;
	loadData = null;
	lastIntervalDate = null;
	passengerCargo = null;
	mailCargo = null;
	supressInterval = false;
	supressInterrupt = false;
	
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
		if(AITile.IsSeaTile(tile) && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 2000000) {
			return true;
		}
		if(HogeAI.notBuildableList.HasItem(tile)) {
			return false;
		}
		return AITile.IsBuildable(tile);
	}
	
	static function IsBuildableRectangle(tile,w,h) {
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 2000000) {
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
		
		return AICargo.GetCargoIncome(cargo,distance,days + (waitingDate/2).tointeger()) * (HogeAI.IsBidirectionalCargo(cargo) ? 2 : 1) * 365 / (days * 2 + waitingDate);
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
		HogeAI.container.instance = this;
		stockpiled = false;
		pendings = [];
		DelayCommandExecuter();
		AirportTypeState();
	}
	 
	function Start() {
		HgLog.Info("HogeAI Started.");
		
		
		
		DoLoad();
		
		
		
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
			HgLog.Info("name:"+AIIndustryType.GetName(industryType)+
				" IsRawIndustry:"+AIIndustryType.IsRawIndustry(industryType)+
				" IsProcessingIndustry:"+AIIndustryType.IsProcessingIndustry(industryType)+
				" ProductionCanIncrease:"+AIIndustryType.ProductionCanIncrease (industryType));
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
		
		maxStationSpread = AIGameSettings.GetValue("station.station_spread");
		maxStationSpread = maxStationSpread == -1 ? 12 : maxStationSpread;
		maxTrains = AIGameSettings.GetValue("vehicle.max_trains");
		maxRoadVehicle = AIGameSettings.GetValue("vehicle.max_roadveh");
		maxAircraft = AIGameSettings.GetValue("vehicle.max_aircraft");
		isUseAirportNoise = AIGameSettings.GetValue("economy.station_noise_level")==1 ? true : false;

		AICompany.SetAutoRenewStatus(false);
		SetCompanyName();

		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());

		indexPointer ++;
		while (true) {
			DoInterval();
			DoStep();
		}
	}
	
	function DoStep() {
		AIController.Sleep(1);
		DoInterrupt();
		switch(indexPointer) {
			case 0:
				SearchAndBuildToMeetSrcDemandUsingRail();
				break;
			case 1:
				SearchAndBuildToMeetSrcDemandUsingRoad();
				break;
			case 2:
				Airport.CheckBuildAirport();
				break;
			case 3:
				ScanRoutes();
				break;
			case 4:
				ScanPlaces();
				break;
		}
		indexPointer ++;
		if(indexPointer >= 5) {
			indexPointer = 0;
		}
	}

	
	function ScanPlaces() {
		HgLog.Info("###### Scan places");
		AIController.Sleep(1);
		local aiTestMode = AITestMode();
		local isTry = false;
		while(true) {
			local bests = [];
			local candidate;
			local routeCandidatesGen = GetRouteCandidatesGen();
			for(local i=0; (candidate=resume routeCandidatesGen) != null && i<200; i++) {
				bests.push(candidate);
			}
			
			bests.sort(function(a,b) {
				return b.score-a.score; 
			});
			/*
			foreach(e in bests) {
				HgLog.Info("score"+e.score+" "+e.destPlace.GetName() + "<-" + e.place.GetName()+" "+AICargo.GetName(e.cargo)+" distance:"+e.distance);
			}*/
			
			foreach(t in bests){
				DoInterval();
	/*			if(Place.IsUsedPlaceCargo(t.place, t.cargo)) {
					continue;
				}*/
				
				isTry = true;
				if(t.vehicleType == AIVehicle.VT_ROAD) {
					local roadRouteBuilder = RoadRouteBuilder(t.destPlace, t.place, t.cargo);
					if(roadRouteBuilder.ExistsSameRoute()) {
						continue;
					}
					HgLog.Info("Try build RoadRoute: +"+t.destPlace.GetName() + "<-" + t.place.GetName()+" production:"+t.production+"("+AICargo.GetName(t.cargo)+" roi:"+t.roi+")");
					if(roadRouteBuilder.Build() != null) {
						return isTry;
					}
				} else if(t.vehicleType == AIVehicle.VT_RAIL) {
					HgLog.Info("Try build TrainRoute: +"+t.destPlace.GetName() + "<-" + t.place.GetName()+" production:"+t.production+"("+AICargo.GetName(t.cargo)+" roi:"+t.roi+")");
					if(BuildRouteAndAdditional(t.destPlace, t.place, t.cargo)) {
						return isTry;
					}
				}
			}
			if(candidate == null) {
				return isTry;
			}
		}
	}
	
	function ScanRoutes() {
		HgLog.Info("###### Scan routes");
		local limitDate = AIDate.GetCurrentDate() + 600;
		
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
			if(route.transferRoute != null || route.IsUpdatingRail()) {
				continue;
			}
			AIRail.SetCurrentRailType(route.GetRailType());
			route.isBuilding = true;


			if(route.parentRoute == null) {
				if(route.additionalRoute == null ) {
					SearchAndBuildAdditionalSrc(route);
				}
				if(SearchAndBuildAdditionalDest(route) != null && stockpiled && route.destHgStation.place != null) {
					//TreatStockpile(route.destHgStation.place, route.cargo);
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
		local pathFindCostBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 400000;
		local considerSlope = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		local maxDistance = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000 ? 200 : 200;
		local roiBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		foreach(i, src in GetMaxCargoPlaces()) {
			src.production = Place.AdjustProduction(src.place, src.production);
			local destPlaceScores = Place.SearchAcceptingPlacesBestDistance(src.cargo, src.place.GetLocation(), src.bestDistance);
/*			local destPlaceScores;
			if(src.bestDistance != 0) {
				destPlaceScores = Place.SearchAcceptingPlacesBestDistance(src.cargo, src.place.GetLocation(), src.bestDistance);
			} else {
				destPlaceScores = Place.SearchAcceptingPlaces(src.cargo, src.place.GetLocation());
			}*/
			foreach(e in destPlaceScores) {
				if(e.distance > maxDistance) {
					continue;
				}
				local route = clone src;
				local distanceType = route.distanceTypes[min(9,e.distance/20)];
				//route.score *= AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 0/*500000*/ ? 1 : distanceType.roi;
				if(distanceType==null) {
					continue;
				}
				route.vehicleType <- distanceType.vehicleType;
				
				if(route.vehicleType == AIVehicle.VT_RAIL && route.cargo != HogeAI.GetPassengerCargo() && route.place.IsIncreasableProcessingOrRaw() == false) {
					continue;
				}
				route.distance <- e.distance;
				route.destPlace <- e.place;
				if(route.cargo == HogeAI.GetPassengerCargo()) {
					if(route.place instanceof TownCargo && !CanUseTownBus(route.place)) {
						continue;
					}
					if(route.destPlace instanceof TownCargo && !CanUseTownBus(route.destPlace)) {
						continue;
					}
				}
				if(IsBidirectionalCargo(route.cargo)) {
					route.production += route.destPlace.GetProducing().GetLastMonthProduction(route.cargo);
					route.production /= 2;
				}
				route.score = (roiBase ? distanceType.roi : distanceType.income) * route.production; //(route.vehicleType==AIVehicle.VT_ROAD ? min(50,src.production) : src.production);
				if (considerSlope) {
					route.score = route.score * 3 / (3 + max( AITile.GetMaxHeight(route.destPlace.GetLocation()) - AITile.GetMaxHeight(route.place.GetLocation()) , 0 ));
				}
				
				yield route;
			}
			DoInterval();
		}
		return null;
	}
 
	function CanUseTownBus(townCargo) {
		local townBus = TownBus.GetByTown(townCargo.town);
		if(townBus == null) {
			return true;
		} else {
			return townBus.CanUseTransfer();
		}
	}
 
	function CheckAndBuildCascadeRoute(destPlace,cargo) {
		if(stockpiled && AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000) {
			return; // ほんの少ししか生産されないためにbankruptするリスクを回避
		}
		local cascaded = false;
		local producing = destPlace.GetProducing();
		local cargos = producing.GetCargos();
		if(cargos.len() >= 1 && destPlace.IsIncreasable() && destPlace.IsNearAllNeedsExcept(cargo)) {
			HgLog.Info("Try to build cascade route. src place:"+destPlace.GetName());
			foreach(newCargo in producing.GetCargos()) {
				if(PlaceDictionary.Get().IsUsedAsSrouceCargoByTrain(producing, newCargo)) {
					HgLog.Info("Already used. cargo:"+AICargo.GetName(newCargo));
					continue;
				}
				local destPlaceScores = Place.SearchAcceptingPlaces(newCargo, producing.GetLocation());
				if(destPlaceScores.len() >= 1) {
					if(BuildRouteAndAdditional(destPlaceScores[0].place, producing, newCargo)) {
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
		
		local route = BuildRoute(srcPlace,dest,cargo);
		if(route == null) {
			if(dest instanceof Place) {
				Place.AddNgPathFindPair(dest,srcPlace);
			} else {
				Place.AddNgPathFindPair(GetLocationFromDest(dest), srcPlace);
			}
			return false;
		}
		
		
		route.isBuilding = true;
		SearchAndBuildToMeetSrcDemandUsingRail(route);
		SearchAndBuildToMeetSrcDemandUsingRoad(route);
		if(route.transferRoute == null) {
			SearchAndBuildAdditionalSrc(route);
		}

		if(route.transferRoute == null) {
			while(!CheckAndBuildCascadeRoute(dest,cargo)) {
				dest = SearchAndBuildAdditionalDest(route)
				if(dest == null) {
					break;
				}
			}/*
			if(stockpiled && route.destHgStation.place != null) {
				TreatStockpile(route.destHgStation.place, route.cargo);
			}*/
			if(route.additionalRoute != null) {
				CheckBuildReturnRoute(route.additionalRoute);
			}
			CheckBuildReturnRoute(route);
		}
		route.isBuilding = false;
		return true;
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
	
	function SearchAndBuildToMeetSrcDemandUsingRail(originalRoute=null) {
		HgLog.Info((originalRoute==null ? "###### " : "") + "Search and build to meet src demand using rail."+(originalRoute!=null?originalRoute:"(all)"));
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
			if(route instanceof TrainReturnRoute) {
				foreach(data in Place.SearchSrcAdditionalPlaces( 
						route.srcHgStation.platformTile, route.GetFinalDestPlace().GetLocation(), 
						route.cargo, 40, 130, 50, 80, 200, false, true)) {
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
			} else {
				local srcPlace = route.srcHgStation.place;
				if(srcPlace==null || !srcPlace.IsProcessing()) {
					continue;
				}
				local srcAcceptingPlace = srcPlace.GetAccepting();
				if(srcAcceptingPlace.IsIncreasable() && !srcAcceptingPlace.IsRaw()) {
					foreach(cargo in srcAcceptingPlace.GetCargos()) {
						//TODO まだ満たされていないCargoを優先する(for FIRS)
						foreach(data in Place.SearchSrcAdditionalPlaces(
								srcAcceptingPlace, null, 
								cargo, 60, 200, 50, 200, 50, false, true)) {
							local t = {};
							t.route <- route;
							t.cargo <- cargo;
							t.dest <- srcAcceptingPlace;
							t.srcPlace <- data.place;
							t.distance <- data.distance;
							t.production <- data.production;
							t.score <- route.GetDistance() * t.production;
							additionalPlaces.push(t);
							break;
						}
					}
				}
			}
			DoInterval();
		}
		local limitDate = AIDate.GetCurrentDate() + 600;
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
		
		return false;
	}
	
	function GetPlansToMeetSrcDemandUsingRoad(srcAcceptingPlace, route=null) {
		local additionalPlaces = [];
		local maxDistance = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 100000 ? 100 : 200;
		foreach(cargo in srcAcceptingPlace.GetCargos()) {
			if(PlaceDictionary.Get().GetRoutesByDestCargo(srcAcceptingPlace,cargo).len()>=1) {
				continue;
			}
			local l = [];
			foreach(data in Place.SearchSrcAdditionalPlaces( 
					srcAcceptingPlace, null, 
					cargo, 0, (srcAcceptingPlace.IsRaw() ? maxDistance * 3 / 2 : maxDistance), 1, 200, 50, true, false)) {
				local t = {};
				if(route != null) {
					t.route <- route;
				}
				t.cargo <- cargo;
				t.dest <- srcAcceptingPlace;
				t.srcPlace <- data.place;
				t.distance <- data.distance;
				t.production <- data.production;
				t.isRaw <- srcAcceptingPlace.IsRaw();
				l.push(t);
			}
			l.sort(function(a,b) {
				return a.distance - b.distance;
			});
			
			if(l.len()>=1) {
				additionalPlaces.push(l[0]);
			} else if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 1000000/* && srcAcceptingPlace.IsRaw()*/) {
				local l = [];
				foreach(data in Place.SearchSrcAdditionalPlaces( 
						srcAcceptingPlace, null, 
						cargo, 0, maxDistance * 3, 0, 500, 50, true, false)) {
					local t = {};
					if(route != null) {
						t.route <- route;
					}
					t.cargo <- cargo;
					t.dest <- srcAcceptingPlace;
					t.srcPlace <- data.place;
					t.distance <- data.distance;
					t.production <- data.production;
					t.isRaw <- srcAcceptingPlace.IsRaw();
					l.push(t);
				}
				l.sort(function(a,b) {
					return a.distance - b.distance;
				});
				if(l.len() >= 1) {
					additionalPlaces.push(l[0]);
				} else {
					HgLog.Info("Not found place to meet(long) src:"+srcAcceptingPlace.GetName()+" cargo:"+AICargo.GetName(cargo));
				}
			} else {
				HgLog.Info("Not found place to meet(short) src:"+srcAcceptingPlace.GetName()+" cargo:"+AICargo.GetName(cargo));			
			}
		}
		return additionalPlaces;
	}
	
	function GetPlansToMeetSrcDemandUsingRoadTransfer(route,isDest) {
		local maxDistance = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 100000 ? 100 : 200;
		local additionalPlaces = [];
		local hgStation = isDest ? route.destHgStation : route.srcHgStation;
		local finalDestLocation = isDest ? route.srcHgStation.platformTile : route.GetFinalDestPlace().GetLocation();
		
		foreach(data in Place.SearchSrcAdditionalPlaces( 
				hgStation.stationGroup.hgStations[0].platformTile, finalDestLocation, 
				route.cargo, 0, maxDistance, 1, 80, 200, true, false)) {
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
	
	function SearchAndBuildToMeetSrcDemandUsingRoad(originalRoute=null, limitDate=null) {
		HgLog.Info((originalRoute==null ? "###### " : "") + "Search and build to meet src demand using road."+(originalRoute!=null?originalRoute:"(all)"));
		local additionalPlaces = [];
		local routes;
		if(originalRoute != null) {
			routes = [originalRoute];
		} else {
			routes = RouteUtils.GetAllRoutes();
		}
		local tooManyRoadVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_ROAD) > HogeAI.Get().maxRoadVehicle * 0.9;
		
		foreach(route in routes) {
			if(route.NeedsAdditionalProducing()) {
				if(!tooManyRoadVehicles && (route instanceof TrainRoute || route instanceof TrainReturnRoute)) {
					additionalPlaces.extend(GetPlansToMeetSrcDemandUsingRoadTransfer(route,false));
				}
				if(route.srcHgStation.place != null && !(route instanceof RoadRoute && route.isTransfer)) {
					local srcAcceptingPlace = route.srcHgStation.place.GetAccepting();
					if(srcAcceptingPlace.IsIncreasable() && !(route instanceof RoadRoute && srcAcceptingPlace.IsRaw())) {
						additionalPlaces.extend(GetPlansToMeetSrcDemandUsingRoad(srcAcceptingPlace, route));
					}
				}
			}
			if(route.IsBiDirectional() && route.NeedsAdditionalProducing(null,true)) {
				if(!tooManyRoadVehicles && (route instanceof TrainRoute || route instanceof TrainReturnRoute)) {
					additionalPlaces.extend(GetPlansToMeetSrcDemandUsingRoadTransfer(route,true));
				}
			}
			
			DoInterval();
		}
		local maxRoads = AICompany.GetBankBalance(AICompany.COMPANY_SELF) / 100000 + 3;
		local counter = 0;
		if(limitDate==null) {
			limitDate = AIDate.GetCurrentDate() + 600;
		}
		if(additionalPlaces.len() >= 1) {
			foreach(t in additionalPlaces) {
				t.score <- t.production * 100 * (t.isRaw ? 3 : 1) / (t.distance+20);
			}
		
			additionalPlaces.sort(function(a,b) {
				return b.score - a.score;
			});
			foreach(t in additionalPlaces) {
				if(counter >= maxRoads) {
					break;
				}
				if(limitDate < AIDate.GetCurrentDate()) {
					break;
				}
				local dest = t.dest instanceof Place ? t.dest : t.dest.hgStations[0].platformTile;
				local roadRouteBuilder = RoadRouteBuilder(t.dest, t.srcPlace, t.cargo);
				if(!roadRouteBuilder.ExistsSameRoute()) {
					HgLog.Info("Found producing place using road "+t.dest+"<-"+t.srcPlace.GetName()+" route:"+t.route);
					local roadRoute = roadRouteBuilder.Build();
					if(roadRoute != null/* && t.production == 0*/) {
						SearchAndBuildToMeetSrcDemandUsingRoad(roadRoute, limitDate);
					}
				}
				DoInterval();
				counter ++;
				
			}
		}
		
		return false;
	}
	
	
	function SearchAndBuildAdditionalDest(route) {
		if(PlaceDictionary.Get().IsUsedAsSrouceByTrain(route.destHgStation.place.GetProducing(), route)) {
			return null;
		}
		if(route.GetLastRoute().returnRoute != null) {
			return null;
		}
		if(route.trainLength < 7) {
			return null;
		}
		local lastAcceptingTile = route.destHgStation.platformTile;
		foreach(placeScore in Place.SearchAdditionalAcceptingPlaces(route.cargo, route.GetSrcStationTiles(), route.destHgStation.platformTile)) {
			if(route.IsBiDirectional() && route.srcHgStation.place!=null && route.destHgStation.place!=null) {
				if(placeScore[0].GetProducing().GetLastMonthProduction(route.cargo) 
						< min( route.srcHgStation.place.GetProducing().GetLastMonthProduction(route.cargo), 
							route.destHgStation.place.GetProducing().GetLastMonthProduction(route.cargo)) * 2 / 3) {
					continue;
				}
			}
			if(route.cargo == HogeAI.GetPassengerCargo()) {
				if(placeScore[0] instanceof TownCargo && !CanUseTownBus(placeScore[0])) {
					continue;
				}
			}

			HgLog.Info("Found an additional accepting place:"+placeScore[0].GetName()+" route:"+route);
			if(BuildDestRouteAdditional(route,placeScore[0])) {
				CheckAndBuildCascadeRoute(placeScore[0],route.cargo);
				return placeScore[0];
			}
			Place.AddNgPathFindPair(placeScore[0], lastAcceptingTile);
			break; //1つでも失敗したら終了とする。
		}
		return null;
	}
	
	
	function GetMaxCargoPlaces()
	{
		local result = []
		
		local quarterlyIncome = AICompany.GetQuarterlyIncome(AICompany.COMPANY_SELF, 1/*AICompany.CURRENT_QUARTER*/);
		HgLog.Info("quarterlyIncome: " + quarterlyIncome);
		local roiBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		
		foreach(cargo ,dummy in AICargoList()) {
			
			local distanceTypes = array(15);
			
			local bestDistance = 0;
			local maxROI = 0;
			local maxIncome = 0;
			if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_ROAD) > maxRoadVehicle * 0.8) {
				HgLog.Warning("road vehicle too many");
			} else {
				for(local distance = 0; distance < 200; distance += 20) {
					local roadEngine = RoadRoute.ChooseEngineCargo(cargo, distance + 10);
					if(roadEngine != null) {
						local roadIncome = HogeAI.GetCargoIncome(distance + 10, cargo, AIEngine.GetMaxSpeed(roadEngine), 2)
							* AIEngine.GetCapacity(roadEngine)
							* (AIEngine.GetReliability(roadEngine)+100)/200
								- AIEngine.GetRunningCost(roadEngine);
						local roi  = roadIncome * 100 / AIEngine.GetPrice(roadEngine);
						maxROI = max(maxROI,roi);
						maxIncome = max(maxIncome, roadIncome);
						if(roiBase) {
							if(roi == maxROI) {
								bestDistance = distance;
							}
						} else {
							if(roadIncome == maxIncome) {
								bestDistance = distance;
							}
						}					
						local t = {};
						t.roi <- roi;
						t.income <- roadIncome;
						t.vehicleType <- AIVehicle.VT_ROAD;
						distanceTypes[distance/20] = t;
						HgLog.Info("distance:"+distance+" roadROI:"+roi+" income:"+roadIncome);
					}
				}
			}
			
			
			local trainROI = 0;
			local bestTrainDistance = 0;
//				wagonNum = max(1, wagonNum);
			if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_RAIL) > maxTrains * 0.9) {
				HgLog.Warning("train vehicle too many");
			} else {
				for(local distance = 0; distance <200; distance += 20) {
					local trainPlanner = TrainPlanner();
					trainPlanner.cargo = cargo;
					trainPlanner.production = 200;
					trainPlanner.distance = distance + 10;
					trainPlanner.skipWagonNum = 5;
					trainPlanner.limitTrainEngines = 1;
					trainPlanner.limitWagonEngines = 1;
					local engineSets = trainPlanner.GetEngineSetsOrder();
					if(engineSets.len() >= 1) {
						local engineSet = engineSets[0];
						local roi = engineSet.roi;
						local trainIncome = engineSet.income;
						maxROI = max(maxROI, roi);
						maxIncome = max(maxIncome, trainIncome);
						local t = distanceTypes[distance/20];
						local useRail = false;
						if(!roiBase || (quarterlyIncome > 100000 && roi > 50 && (t==null || t.roi > 50))) {
							if((t == null || t.income <= trainIncome) && roi > 0) {
								useRail = true;
							}
							if(trainIncome == maxIncome) {
								bestDistance = distance;
							}
						} else {
							if(t == null || t.roi < roi) {
								useRail = true;
							}
							if(roi == maxROI) {
								bestDistance = distance;
							}
						}
						if(useRail) {
							distanceTypes[distance/20] = {
								roi = roi
								income = trainIncome
								vehicleType = AIVehicle.VT_RAIL
							}
						}
						HgLog.Info("distance:"+distance+" trainROI:"+roi+" income:"+trainIncome+" useRail:"+useRail+" capacity:"+engineSet.capacity
							+" engine:"+AIEngine.GetName(engineSet.trainEngine)+(engineSet.wagonEngine==null?"":" wagon:"+AIEngine.GetName(engineSet.wagonEngine)+"x"+engineSet.numWagon));
					}
				}
			}
			
			HgLog.Info("cargo:"+AICargo.GetName(cargo)+" maxROI:"+maxROI+" maxIncome:"+maxIncome+" bestDistance:"+bestDistance);
			if(maxROI >= 1) {
				foreach(place in Place.GetNotUsedProducingPlaces(cargo,false).array) {
					local canSteal = true;
					foreach(route in PlaceDictionary.Get().GetRoutesBySource(place)) {
						/*if(route instanceof RoadRoute && route.GetDestRoute() == false) {
							continue;
						}*/
						canSteal = route.IsOverflowPlace(place); // 単体の新規ルートは何かに使用されていた場合（余っていない場合）、全て禁止
					}
					if(!canSteal) {
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
					
						local t = {};
						t.cargo <- cargo;
						t.place <- place;
						t.production <- production;
						t.roi <- maxROI;
						t.bestDistance <- bestDistance;
						t.score <- production * (roiBase ? maxROI : maxIncome);
						t.distanceTypes <- distanceTypes;
						result.push(t);
					}
				}
			}
			DoInterval();
		}
		result.sort(function(a,b){
			return -(a.score - b.score);
		});
		return result;
	}
 

	function BuildRoute(srcPlace, dest, cargo) {
		
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
			destHgStation = destStationFactory.SelectBestHgStation( dest.srcHgStation.stationGroup.GetStationCandidatesInSpread(maxStationSpread, destStationFactory),
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
		Place.SetRemovedDestPlace(route.GetFinalDestPlace());
		additionalHgStation.BuildAfter();
		route.AddDestination(additionalHgStation);

		local removeRemain1 = route.pathSrcToDest.CombineByFork(railBuilder.buildedPath1, false);
		local removeRemain2 = route.pathDestToSrc.CombineByFork(railBuilder.buildedPath2, true);
		
		local removePath1 = removeRemain1[0];
		local removePath2 = removeRemain2[0];
		
		route.pathSrcToDest = removeRemain1[1];
		route.pathDestToSrc = removeRemain2[1];
		
		oldDestStation.RemoveDepots();
		
		route.AddAdditionalTiles(removePath1.GetTiles());
		route.AddAdditionalTiles(removePath2.GetTiles());

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
		/*

		local railBuilder2 = RailToStationRailBuilder(route.pathDestToSrc.path.SubPathLastIndex(5),additionalHgStation,false,pathFindLimit,this);
		if(!railBuilder2.Build()) {
			HgLog.Error("cannot build rail pathDestToSrc");
			additionalHgStation.Remove();
			return null;
		}
		local railBuilder1 = RailToStationRailBuilder(route.pathSrcToDest.path.SubPathIndex(5),additionalHgStation,true,pathFindLimit,this, railBuilder2.buildedPath.path);
		if(!railBuilder1.Build()) {
			HgLog.Error("cannot build rail pathSrcToDest");
			additionalHgStation.Remove();
			railBuilder2.buildedPath.Remove();
			if(depot != null) {
				AITile.DemolishTile(depot);
			}
			if(doubleDepots != null) {
				AITile.DemolishTile(doubleDepots[0]);
				AITile.DemolishTile(doubleDepots[1]);
			}
			return null;
		}*/

		local depotPath = route.pathDestToSrc.path.SubPathStart(railBuilder.buildedPath1.path.GetLastTile());
		local depot = depotPath.BuildDepot();
		local doubleDepots = depotPath.BuildDoubleDepot();
		
		route.AddDepot(depot);
		route.AddDepots(doubleDepots);
//		local additionalRoute = TrainRoute(TrainRoute.RT_ADDITIONAL, route.cargo, additionalHgStation, route.destHgStation,
//			railBuilder1.buildedPath, railBuilder2.buildedPath);
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
		local srcPlaces = Place.GetNotUsedProducingPlaces(cargo);
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
			/*			
			railBuilderTransferToPath = RailToStationRailBuilder(returnPath.SubPathEnd(returnPath.GetLastTileAt(4)),transferStation,true,pathFindLimit,this);
			if(!railBuilderTransferToPath.Build()) {
				HgLog.Warning("cannot build railBuilderTransferToPath");
				Rollback(needRollbacks);
				return false;
			}*/
			needRollbacks.push(railBuilderTransferToPath.buildedPath);
			
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
			
			/*
			returnPath = route.GetPathAllDestToSrc(); //書き換えられている可能性があるので改めて取得
			local pathForTransferArrival = returnPath.SubPathStart(railBuilderTransferToPath.buildedPath.path.GetFirstTile());
			railBuilderPathToTransfer = RailToStationRailBuilder(pathForTransferArrival,transferStation,false,pathFindLimit,this);
			if(!railBuilderPathToTransfer.Build()) {
				HgLog.Warning("cannot build railBuilderPathToTransfer");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(railBuilderPathToTransfer.buildedPath);*/
		}

/*
		local srcRouteTrainLength = 7;
		local srcRouteDistance = AIMap.DistanceManhattan(transferStation.platformTile, srcPlace.GetLocation());
		if(srcRouteDistance < 50) {
			srcRouteTrainLength = srcRouteDistance / 10 + 2
		}

		local destStationFactory = TerminalStationFactory(2);//DestRailStationFactory(2);//
		destStationFactory.platformLength = srcRouteTrainLength;
		destStationFactory.nearestFor = transferStation.stationGroup.hgStations[0].platformTile;
		local transferSrcStation = destStationFactory.SelectBestHgStation( transferStation.stationGroup.GetStationCandidatesInSpread(maxStationSpread, destStationFactory),
			transferStation.platformTile, srcPlace.GetLocation(), "transfer");
		if(transferSrcStation == null) {
			//TODO: GetBuildableStatoinByPathの次候補で成功する可能性
			HgLog.Info("cannot build transfer src station");
			Rollback(needRollbacks);
			return false;
		}
		
		local list = HgArray(transferSrcStation.GetTiles()).GetAIList();
		HogeAI.notBuildableList.AddList(list);
		local srcStationFactory = SrcRailStationFactory();
		srcStationFactory.platformLength = srcRouteTrainLength;
		local srcStation = srcStationFactory.CreateBest(srcPlace, route.cargo, transferSrcStation.platformTile);
		HogeAI.notBuildableList.RemoveList(list);
		
		if(srcStation == null) {
			HgLog.Info("cannot build srcStation");
			Rollback(needRollbacks);
			return false;
		}
		
		local srcRouteRailBuilder;
		{
			local aiExecMode = AIExecMode();
			
			transferSrcStation.cargo = route.cargo;
			transferSrcStation.isSourceStation = false;
			if(!transferSrcStation.BuildExec()) {
				HgLog.Warning("cannot build transfer src station");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(transferSrcStation);
			
			srcStation.cargo = route.cargo;
			srcStation.isSourceStation = true;
			if(!srcStation.BuildExec()) {
				HgLog.Warning("cannot build transfer srcStation");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(srcStation);
			
			srcRouteRailBuilder = TwoWayStationRailBuilder(srcStation, transferSrcStation, pathFindLimit, this);
			if(!srcRouteRailBuilder.Build()) {
				HgLog.Warning("srcRouteRailBuilder.Build failed.");
				Rollback(needRollbacks);
				return null;
			}
			needRollbacks.push(srcRouteRailBuilder.buildedPath1);
			needRollbacks.push(srcRouteRailBuilder.buildedPath2);
		}*/
		
		
		{
			local returnDestStation = TerminalStationFactory(2).CreateBest(destPlace, route.cargo, transferStation.platformTile, false);
				// station groupを使うと同一路線の他のreturnと競合して列車が迷子になる事がある
			if(returnDestStation == null) {
				HgLog.Info("cannot build returnDestStation");
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
			
			local pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile());
			
			local pathForTransferDeparutre = pathForReturnDest;//.SubPathEnd(railBuilderReturnDestArrival.pathSrcToDest.GetLastTile());
			local railBuilderReturnDestDeparture = RailToStationRailBuilder(pathForTransferDeparutre,returnDestStation,true,pathFindLimit,this);
			if(!railBuilderReturnDestDeparture.Build()) {
				HgLog.Warning("cannot build railBuilderReturnDestDeparture");
				Rollback(needRollbacks);
				return false;
			}
			needRollbacks.push(railBuilderReturnDestDeparture.buildedPath);
			
			pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile());
			local pathForReturnDestArrival = pathForReturnDest.SubPathStart(railBuilderReturnDestDeparture.buildedPath.path.GetFirstTile()/*pathForReturnDest.GetTileAt(5)*/);
			local railBuilderReturnDestArrival = RailToStationRailBuilder(pathForReturnDestArrival,returnDestStation,false,pathFindLimit,this,railBuilderReturnDestDeparture.buildedPath.path);
			if(!railBuilderReturnDestArrival.Build()) {
				HgLog.Warning("cannot build railBuilderReturnDestArrival");
				Rollback(needRollbacks);
				return false;
			}
			pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile());
/*			local depotPath = pathForReturnDest.SubPathStart(railBuilderReturnDestArrival.buildedPath.path.GetLastTile());
			route.AddDepot(depotPath.BuildDepot());
			route.AddDepots(depotPath.BuildDoubleDepot());*/
			
			//TODO: returnSrc側にもdepot
			
			local aiExecMode = AIExecMode();

			local returnRoute = TrainReturnRoute(transferStation, returnDestStation, 
				railBuilderPathToTransfer.buildedPath, railBuilderTransferToPath.buildedPath,
				railBuilderReturnDestArrival.buildedPath, railBuilderReturnDestDeparture.buildedPath);
				
			route.returnRoute = returnRoute;
			returnRoute.originalRoute = route;
			
/*
			local newRoute = TrainRoute(TrainRoute.RT_RETURN, lastRoute.cargo, srcStation, transferSrcStation,
				srcRouteRailBuilder.buildedPath1, srcRouteRailBuilder.buildedPath2);
			newRoute.trainLength = srcRouteTrainLength;
			transferSrcStation.BuildAfter();
			newRoute.destPlace = destPlace;
			TrainRoute.instances.push(newRoute);
			lastRoute.returnRoute = newRoute;
			Place.SetUsedPlaceCargo(srcPlace,newRoute.cargo);

			newRoute.BuildFirstTrain();
			if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 100000) {
				newRoute.CloneAndStartTrain();
			}*/

			route.AddReturnTransferOrder(transferStation, returnDestStation);
			
			SearchAndBuildToMeetSrcDemandUsingRail(returnRoute);
			SearchAndBuildToMeetSrcDemandUsingRoad(returnRoute);
			

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
			
			foreach(station in stations) {
				if(station.Build(true)) {
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
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 400000) {
			foreach(route in TrainRoute.instances) {
				local station = AIStation.GetStationID(route.srcHgStation.platformTile);		
				local town = AIStation.GetNearestTown (station)
				if(!AITown.HasStatue (town)) {
					AITown.PerformTownAction(town,AITown.TOWN_ACTION_BUILD_STATUE );
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= 400000) {
						break;
					}
				}
			}
		}
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 800000) {
			foreach(route in RoadRoute.instances) {
				local station = AIStation.GetStationID(route.srcHgStation.platformTile);		
				local town = AIStation.GetNearestTown (station)
				if(!AITown.HasStatue (town)) {
					AITown.PerformTownAction(town,AITown.TOWN_ACTION_BUILD_STATUE );
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= 800000) {
						break;
					}
				}
			}
		}
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 1000000) {
			foreach(airport in Airport.instances) {
				local station = AIStation.GetStationID(airport.airportTile);		
				local town = AIStation.GetNearestTown (station)
				if(!AITown.HasStatue (town)) {
					AITown.PerformTownAction(town,AITown.TOWN_ACTION_BUILD_STATUE );
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= 1000000) {
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
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 1000000) {
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
		if(AIBase.RandRange(100) < 25) {
			foreach(townBus in TownBus.instances) {
				townBus.CheckInterval();
			}
		}
	 }
	 
	function CheckAirplane() {
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 100000) {
			local reduce = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_AIR ) > HogeAI.Get().maxAircraft - 10;
			foreach(airport in Airport.instances) {
				airport.CheckCloneVehicle();
				airport.CheckRenewalVehicles(reduce);
				if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= 100000) {
					break;
				}
			}
		}
	}
	
	function CheckRoadRoute() {
	//	if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 50000 || TrainRoute.instances.len() == 0) {
			foreach(route in RoadRoute.instances) {
				route.CheckBuildVehicle();
		//		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= 50000 && TrainRoute.instances.len() >= 1) {
		//			break;
		//		}
			}
//		}
		foreach(route in RoadRoute.instances) {
			route.CheckRenewal();
		}
		//PerformanceCounter.Print();
	}
	

	 
	function OnPathFindingInterval() {
		DoInterval();
		return true;
	}
	
	
	function TreatStockpile(place, cargo) {
		HgLog.Warning("TreatStockpile "+place.GetName()+" "+AICargo.GetName(cargo));
		foreach(destCargo in place.GetProducing().GetCargos()) {
			BuildDestRailOrRoadRoute(place.GetProducing(), destCargo);
		}
		foreach(srcCargo in place.GetAccepting().GetCargos()) {
			if(srcCargo != cargo /*&& AIIndustry.GetStockpiledCargo(destPlace.industry, srcCargo) == 0*/) {
				BuildSrcRailOrRoadRoute(place.GetAccepting(), srcCargo);
			}
		}
	}

	
	function BuildDestRailOrRoadRoute(place, cargo) {
		HgLog.Warning("BuildDestRailOrRoadRoute "+place.GetName()+" "+AICargo.GetName(cargo));
		if(!PlaceDictionary.Get().IsUsedAsSourceCargo(place, cargo)) {
			local isUseRail = place.GetLastMonthProduction(cargo) > 50;
			foreach(dest in Place.SearchAcceptingPlacesBestDistance(cargo, place.GetLocation(), 0)) {
				local newRoute = null;
				if(isUseRail && dest.distance > 60) {
					//newRoute = BuildRoute(place, dest.place, cargo);
				}
				if(newRoute == null) {
					local roadRouteBuilder = RoadRouteBuilder(dest.place, place, cargo);
					if(!roadRouteBuilder.ExistsSameRoute()) {
						newRoute = roadRouteBuilder.Build();
					}
				}
				if(newRoute != null) {
					break;
				}
			}
		}
	}
	
	function BuildSrcRailOrRoadRoute(place, cargo) {
		HgLog.Warning("BuildSrcRailOrRoadRoute "+place.GetName()+" "+AICargo.GetName(cargo));
		foreach(src in Place.SearchSrcAdditionalPlaces(
								place, null, 
								cargo, 10, 500, 0, 400, 50, false, false)) {
			local newRoute = null;
			//if(src.production < 50) {
			local roadRouteBuilder = RoadRouteBuilder(place, src.place, cargo);
			if(!roadRouteBuilder.ExistsSameRoute()) {
				newRoute = roadRouteBuilder.Build();
			}
			/*} else {
				newRoute = BuildRoute(src.place, place, cargo);
			}*/
			if(newRoute != null) {
				SearchAndBuildToMeetSrcDemandUsingRoad(newRoute);
				break;
			}
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
				case "BuildDestRailOrRoadRoute":
					BuildDestRailOrRoadRoute(Place.Load(pending.arg[0]), pending.arg[1]);
					break;
				case "BuildSrcRailOrRoadRoute":
					BuildSrcRailOrRoadRoute(Place.Load(pending.arg[0]), pending.arg[1]);
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

		CheckAirplane();
		times.push(AIDate.GetCurrentDate()); //3

		CheckRoadRoute();
		times.push(AIDate.GetCurrentDate()); //4

		CheckBus();
		times.push(AIDate.GetCurrentDate()); //5

		AirportTypeState.Get().Check();
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
		HgLog.Info("DoInterval "+ s + " total:"+(pre - lastIntervalDate));
		lastIntervalDate = AIDate.GetCurrentDate();
		
		AIRail.SetCurrentRailType(currentRailType);
		
	}
		 
	 function CheckEvent() {
		while(AIEventController.IsEventWaiting()) {
			local event = AIEventController.GetNextEvent();
			switch(event.GetEventType()) {
				case AIEvent.ET_VEHICLE_WAITING_IN_DEPOT:/*
					event = AIEventVehicleWaitingInDepot.Convert(event);
					local vehicle = event.GetVehicleID();
					foreach(route in TrainRoute.instances) {
						if(route.engineVehicles.HasItem (vehicle)) {
							route.OnVehicleWaitingInDepot(vehicle);
							break;
						}
					}*/
					break;
				case AIEvent.ET_INDUSTRY_CLOSE:
					event = AIEventIndustryClose.Convert(event);
					HgLog.Info("ET_INDUSTRY_CLOSE:"+AIIndustry.GetName(event.GetIndustryID()));
					HgIndustry.closedIndustries[event.GetIndustryID()] <- true;
					foreach(i,route in TrainRoute.instances) {
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
			HgLog.Error("ET_VEHICLE_LOST vehicleType == AIVehicle.VT_RAIL");
		}
	}
	 
	function Save() {
		local table = {};	
		table.indexPointer <- indexPointer;
		table.pendings <- pendings;
		table.stockpiled <- stockpiled;
		
		Place.SaveStatics(table);
		HgStation.SaveStatics(table);
		TrainInfoDictionary.SaveStatics(table);
		TrainRoute.SaveStatics(table);
		RoadRoute.SaveStatics(table);
		TownBus.SaveStatics(table);
		Airport.SaveStatics(table);
		return table;
	}


	function Load(version, data) {
		loadData = data;
	}
	
	function DoLoad() {
		if(loadData == null) {
			return;
		}
		indexPointer = loadData.indexPointer;
		pendings = loadData.pendings;
		stockpiled = loadData.stockpiled;
		
		Place.LoadStatics(loadData);
		HgStation.LoadStatics(loadData);
		TrainInfoDictionary.LoadStatics(loadData);
		TrainRoute.LoadStatics(loadData);		
		RoadRoute.LoadStatics(loadData);
		TownBus.LoadStatics(loadData);
		Airport.LoadStatics(loadData);
		HgLog.Info(" Loaded");
	}
	 
	 
	 function SetCompanyName()
	 {
	   if(!AICompany.SetName("Hoge AI")) {
		 local i = 2;
		 while(!AICompany.SetName("Hoge AI #" + i)) {
		   i = i + 1;
		   if(i > 255) break;
		 }
	   }
	   AICompany.SetPresidentName("R. Ishibashi");
	 }
	 
	function WaitForMoney(needMoney) {
		local inflationRate = AICompany.GetMaxLoanAmount().tofloat() / AIGameSettings.GetValue("difficulty.max_loan").tofloat();
		HogeAI.WaitForPrice((needMoney * inflationRate).tointeger());
	}
	
	
	function WaitForPrice(needMoney) {
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF)-needMoney > AICompany.GetLoanAmount()*3) {
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
	
	function GetUsableMoney() {
		return AICompany.GetBankBalance(AICompany.COMPANY_SELF) + (AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount());
	}
}
 