
class Route {
	static function SearchRoute( routeInstances, srcPlace, destPlace, destStationGroup, cargo ) {
		foreach(route in routeInstances) {
			if(route.cargo != cargo) {
				continue;
			}
			if(route.srcHgStation.place == null || !route.srcHgStation.place.IsSamePlace(srcPlace)) {
				continue;
			}
			if(route.IsTransfer()) {
				if(destStationGroup != null && route.destHgStation.stationGroup == destStationGroup) {
					return route;
				}
			} else {
				if(route.destHgStation.place == null) {
					continue;
				}
				if(destPlace != null && route.destHgStation.place.IsSamePlace(destPlace)) {
					return route;
				}
				if(route.IsBiDirectional() && route.destHgStation.place.IsSamePlace(srcPlace)) {
					return route;
				}
			}
		}
		return null;
	}
	
	static function GetRouteClassFromVehicleType(vehicleType) {
		switch(vehicleType) {
			case AIVehicle.VT_RAIL:
				return TrainRoute;
			case AIVehicle.VT_ROAD:
				return RoadRoute;
			case AIVehicle.VT_WATER:
				return WaterRoute;
			case AIVehicle.VT_AIR:
				return AirRoute;
		}
		HgLog.Error("Not supported vehicleType(GetRouteClassFromVehicleType)"+vehicleType);
	}
	
	static function AppendNotRemovedRoutes(a, routes) {
		foreach(route in routes) {
			if(!route.IsRemoved()) {
				a.push(route);
			}
		}
	}
	
	static function GetAllRoutes() {
		local routes = [];
		Route.AppendNotRemovedRoutes( routes, TrainRoute.GetAll() );
		Route.AppendNotRemovedRoutes( routes, RoadRoute.instances );
		Route.AppendNotRemovedRoutes( routes, WaterRoute.instances );
		Route.AppendNotRemovedRoutes( routes, AirRoute.instances );
		return routes;
	}
	
	static function Estimate(vehicleType, cargo, distance, production) {
		local cargoTypeDistanceEstimate = HogeAI.Get().cargoTypeDistanceEstimate;
		local estimate = null;
		if(cargoTypeDistanceEstimate.rawin(cargo)) {
			local typeDistanceEstimate = cargoTypeDistanceEstimate[cargo];
			if(typeDistanceEstimate.rawin(vehicleType)) {
				estimate = typeDistanceEstimate[vehicleType][HogeAI.GetEstimateDistanceIndex(distance)];
			}
		}
		local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
		if(estimate == null) {
			estimate = routeClass.EstimateEngineSet.call(routeClass, cargo, distance, production);
		}
		if(estimate == null) {
			return -1;
		}
			// 1カ月で輸送できるMAX量 = capacity × (30日 / 入れ替え時間 + 積み込み時間(=capacity / 積み込み速度)積み込み速度が不明なので正確な見積は不可能 仮に100とする))
			// = stationでさばけるvehicle数 * 積み込み速度
		// 
		local stationDateSpan = Route.GetStationDateSpan(vehicleType);
		local maxDeliver = min(estimate.capacity * 30 / (stationDateSpan + max(3, estimate.capacity / 100)), production);

		if( HogeAI.Get().roiBase ) {
			return estimate.roi;
		} else {
			return maxDeliver * estimate.income / estimate.capacity;
		}
	}
	
	static function GetStationDateSpan(vehicleType) {
		switch(vehicleType) {
			case AIVehicle.VT_RAIL:
				return 5;
			case AIVehicle.VT_ROAD:
				return 2;
			case AIVehicle.VT_WATER:
				return 1;
			case AIVehicle.VT_AIR:
				return 10;
			default:
				HgLog.Error("Not defined stationDateSpan(Route.Estimate):"+vehicleType);
		}
	}
		
	function IsTooManyVehiclesForNewRoute() {
		return AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType()) >= GetMaxTotalVehicles() * GetThresholdVehicleNumRateForNewRoute();
	}
	
	function IsTooManyVehiclesForSupportRoute() {
		return AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType()) >= GetMaxTotalVehicles() * GetThresholdVehicleNumRateForSupportRoute();
	}
	
	function GetRouteWeighting() {
		switch(GetVehicleType()) {
			case AIVehicle.VT_RAIL:
				return 3;
			case AIVehicle.VT_WATER:
				return 2;
			case AIVehicle.VT_ROAD:
				return 1;
			case AIVehicle.VT_AIR:
				return 2;
		}
		HgLog.Error("bug GetRouteWeighting "+this);
	}

	static function IsSameStationPlace(stationA, stationB) {
		if(stationA.place != null && stationB.place != null && stationA.place.IsSamePlace(stationB.place)) {
			return true;
		} else if(stationA.stationGroup == stationB.stationGroup) {
			return true;
		} else {
			return false;
		}
	}
	
	function IsSameSrcAndDest(route) {
		if(Route.IsSameStationPlace(srcHgStation, route.srcHgStation) && Route.IsSameStationPlace(destHgStation, route.destHgStation)) {
			return true;
		}
		if(IsBiDirectional() || route.IsBiDirectional()) {
			if(Route.IsSameStationPlace(srcHgStation, route.destHgStation) && Route.IsSameStationPlace(destHgStation, route.srcHgStation)) {
				return true;
			}
		}
		return false;
	}
	
	function IsSrcStationGroup(stationGroup) {
		if(srcHgStation.stationGroup == stationGroup) {
			return true;
		} else if(IsBiDirectional() && destHgStation.stationGroup == stationGroup) {
			return true;
		} else {
			return false;
		}
	}
	
	function IsDestPlace(place) {
		if(destHgStation.place == null) {
			return false;
		}
		return destHgStation.place.IsSamePlace(place);
	}
	
	function IsSrcPlace(place) {
		if(srcHgStation.place == null) {
			return false;
		}
		return srcHgStation.place.IsSamePlace(place);
	}

	function IsOverflowPlace(place) {
		if(IsDestPlace(place)) {
			return IsOverflow(true);
		}
		if(IsSrcPlace(place)) {
			return IsOverflow(false);
		}
		return false;
	}
	
	function NeedsAdditionalProducingPlace(place) {
		if(IsDestPlace(place)) {
			return NeedsAdditionalProducing(null, true);
		}
		if(IsSrcPlace(place)) {
			return NeedsAdditionalProducing(null, false);
		}
		return false;
	}
	
	function GetProduction() {
		local production = AIStation.GetCargoPlanned(srcHgStation.GetAIStation(), cargo);
		if(production == 0 && srcHgStation.place != null) {
			production = srcHgStation.place.GetLastMonthProduction(cargo);
		}
		return production;
	}
	
	function OnIndustoryClose(industry) {
		local srcPlace = srcHgStation.place;
		if(srcPlace != null && srcPlace instanceof HgIndustry && srcPlace.industry == industry) {
			local saved = false;
			foreach(route in srcHgStation.stationGroup.GetUsingRoutesAsDest()) {
				if(route.IsTransfer() && route.cargo == cargo) {
					HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. But saved because transfer route found."+this);
					saved = true;
				}
			}
			if(saved || GetVehicleType() == AIVehicle.VT_RAIL) { // Railの場合、routeを閉じない。追加のtransferが来る事を期待する
				srcHgStation.place = null;
			} else {
				HgLog.Warning("Remove Route (src industry closed:"+AIIndustry.GetName(industry)+")"+this);
				Remove();
			}
		}
/*	
		local destPlace = GetFinalDestPlace();
		if(destPlace != null && (destPlace instanceof HgIndustry) && destPlace.industry == industry) {
			HgLog.Warning("Close dest industry:"+AIIndustry.GetName(industry));
			isClosed = true;
			Close();
		}*/
	}
}


class CommonRoute extends Route {

	
	function EstimateEngineSet(cargo, distance, production) {
		local engineSets = GetEngineSetsVt(GetVehicleType(), cargo, distance, production);
		if(engineSets.len() >= 1) {
			return engineSets[0];
		} else {
			return null;
		}
	}
	
	function GetEngineSetsVt(vehicleType, cargo, distance, production ) {
		local roiBase = HogeAI.Get().roiBase;
		local engineList = AIEngineList(vehicleType);
		if(vehicleType == AIVehicle.VT_ROAD) {
			engineList.Valuate(AIEngine.HasPowerOnRoad, AIRoad.GetCurrentRoadType());
			engineList.KeepValue(1);
		}
		engineList.Valuate(AIEngine.CanRefitCargo, cargo);
		engineList.KeepValue(1);
		
		if((typeof this) == "instance" && this instanceof AirRoute) {
			local usableBigPlane = Air.GetAiportTraits(srcHgStation.airportType).supportBigPlane && Air.GetAiportTraits(destHgStation.airportType).supportBigPlane;
			if(!usableBigPlane) {
				engineList.Valuate( AIEngine.GetPlaneType );
				engineList.RemoveValue(AIAirport.PT_BIG_PLANE );
			}
		}
		if((typeof this) == "instance") {
			local orderDistance = AIOrder.GetOrderDistance(GetVehicleType(), srcHgStation.platformTile, destHgStation.platformTile);
			engineList.Valuate( function(e):(orderDistance) {
			AIOrder.GetOrderDistance
				local d = AIEngine.GetMaximumOrderDistance(e);
				if(d == 0) {
					return 1;
				} else {
					return d > orderDistance ? 1 : 0;
				}
			} );
			engineList.KeepValue(1);
		}
		
		production = max(20, production);
		
		local self = this;
		return HgArray.AIListKey(engineList).Map(function(e):( distance, cargo, production, vehicleType, self ) {
			local capacity = self.GetEngineCapacity(e,cargo,vehicleType);
			local runningCost = AIEngine.GetRunningCost(e);
			local income = HogeAI.GetCargoIncome( distance, cargo, AIEngine.GetMaxSpeed(e) * 2 / 3, max(5,capacity * 30 / production) )
				* capacity * (100+AIEngine.GetReliability (e)) / 200 - runningCost;
			local roi = income * 100 / AIEngine.GetPrice(e);
			return {
				engine = e
				income = income
				roi = roi
				capacity = capacity
			};
		}).Filter(function(e) {
			return e.income > 0;
		}).Sort(function(a,b) : (roiBase) {
			return roiBase ? (b.roi - a.roi) : (b.income - a.income);
		}).array;
	}
	
	function GetEngineCapacity(engine, cargo, vehicleType) {
		local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
		if(routeClass.instances.len() >= 1) {
			local route = routeClass.instances[0];
			local result = AIVehicle.GetBuildWithRefitCapacity(route.depot, engine, cargo);
			//HgLog.Info("GetEngineCapacity:"+result+" engine:"+AIEngine.GetName(engine) + " cargo:"+AICargo.GetName(cargo)+" "+route.GetLabel() );
			return result;
		} else {
			local result = AIEngine.GetCapacity(engine);
			if(vehicleType == AIVehicle.VT_AIR && !AICargo.HasCargoClass( cargo, AICargo.CC_PASSENGERS )) {
				result /= 2;
			}
			
			//HgLog.Info("GetEngineCapacity:"+result+" engine:"+AIEngine.GetName(engine));
			return result;
		}
	}
	
	function CheckReduce(vehicleType, routeInstances, maxVehicles) {
		if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType ) > maxVehicles * 0.95 ) {
			local minProfit = null;
			local minRoute = null;
			foreach(route in routeInstances) {
				if(route.IsClosed()) {
					continue;
				}
				local numVehicles = AIGroup.GetNumVehicles( route.vehicleGroup, vehicleType);
				if(numVehicles == 0) {
					continue;
				}
				if(route.srcHgStation.buildedDate != null && route.srcHgStation.buildedDate + 800 > AIDate.GetCurrentDate()) {
					continue;
				}
				local routeProfit = (AIGroup.GetProfitThisYear(route.vehicleGroup) + AIGroup.GetProfitLastYear (route.vehicleGroup)) / numVehicles;
				if(minProfit == null || minProfit > routeProfit) {
					minProfit = routeProfit;
					minRoute = route;
				}
			}
			if(minRoute != null) {
				minRoute.ReduceVehicle();
			}
		}
	}

	
	static MAX_VEHICLES = 30;

	cargo = null;
	isTransfer = null;
	srcHgStation = null;
	destHgStation = null;
	vehicleGroup = null;
	
	maxVehicles = null;
	depot = null;
	destDepot = null;
	isClosed = null;
	isTmpClosed = null;
	isRemoved = null;
	lastTreatStockpile = null;
	useDepotOrder = null;
	
	chosenEngine = null;
	lastChooseEngineDate = null;
	destRoute = null;
	hasRailDest = null;
	
	constructor() {
		this.isClosed = false;
		this.isTmpClosed = false;
		this.isRemoved = false;
		this.useDepotOrder = true;
	}
	
	function Initialize() {
		if(this.vehicleGroup == null) {
			this.vehicleGroup = AIGroup.CreateGroup(GetVehicleType());
			local src = srcHgStation.GetName();
			local dest = destHgStation.GetName();
			src = src.slice(0,min(12,src.len()));
			dest = dest.slice(0,min(12,dest.len()));
			local s = (IsTransfer()?"T:":"")+ src + "<-"+(IsBiDirectional()?">":"") + dest +"[" + AICargo.GetName(cargo) + "]" + GetLabel();
			AIGroup.SetName(this.vehicleGroup, s.slice(0,min(31,s.len())));
		}
		this.maxVehicles = GetMaxVehicles();
	}
	
	function Save() {
		local t = {};
		t.cargo <- cargo;
		t.isTransfer <- isTransfer;
		t.srcHgStation <- srcHgStation.id;
		t.destHgStation <- destHgStation.id;
		t.vehicleGroup <- vehicleGroup;
		
		t.depot <- depot;
		t.destDepot <- destDepot;
		t.isClosed <- isClosed;
		t.isTmpClosed <- isTmpClosed;
		t.isRemoved <- isRemoved;
		t.maxVehicles <- maxVehicles;
		t.lastTreatStockpile <- lastTreatStockpile;
		t.useDepotOrder <- useDepotOrder;
		return t;
	}
	
	function Load(t) {
		cargo = t.cargo;
		srcHgStation = HgStation.worldInstances[t.srcHgStation];
		destHgStation = HgStation.worldInstances[t.destHgStation];
		isTransfer = t.isTransfer;
		vehicleGroup = t.vehicleGroup;
		
		depot = t.depot;
		destDepot = t.destDepot;
		isClosed = t.isClosed;
		isTmpClosed = t.isTmpClosed;
		isRemoved = t.rawin("isRemoved") ? t.isRemoved : false;
		maxVehicles = t.maxVehicles;
		lastTreatStockpile = t.lastTreatStockpile;
		useDepotOrder = t.useDepotOrder;
	}
	
	function SetPath(path) {
	}
	
	function IsBiDirectional() {
		return !isTransfer && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
	}
	
	function IsTransfer() {
		return isTransfer;
	}
	
	function BuildDepot(path) {
		local execMode = AIExecMode();
		if(GetVehicleType() == AIVehicle.VT_WATER) {
			//path = path.SubPathIndex(5);
		}
		depot = path.BuildDepot(GetVehicleType());
		if(depot == null && srcHgStation instanceof RoadStation) {
			depot = srcHgStation.BuildDepot();
		}
		return depot != null;
	}
	
	function BuildDestDepot(path) {
		local execMode = AIExecMode();
		path = path.Reverse();
		if(GetVehicleType() == AIVehicle.VT_WATER) {
			//path = path.SubPathIndex(5);
		}
		destDepot = path.BuildDepot(GetVehicleType());
		return destDepot != null;
	}
	
	
	function BuildVehicle() {
		//HgLog.Info("BuildVehicle."+this);
		local execMode = AIExecMode();
		if(depot == null) {
			HgLog.Warning("depot == null. "+this);
			return null;
		}
		local engine = ChooseEngine();
		if(engine == null) {
			HgLog.Warning("Not found suitable engine. "+this);
			return null;
		}
		HogeAI.WaitForPrice(AIEngine.GetPrice(engine));
		local vehicle = AIVehicle.BuildVehicle(depot, engine);
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("BuildVehicle failed "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIVehicle.RefitVehicle(vehicle, cargo);
		AIGroup.MoveVehicle(vehicleGroup, vehicle);
		
		local nonstopIntermediate = GetVehicleType() == AIVehicle.VT_ROAD ? AIOrder.OF_NON_STOP_INTERMEDIATE : 0;

		if(useDepotOrder) {
			AIOrder.AppendOrder(vehicle, depot, nonstopIntermediate );
		}
		local isBiDirectional = IsBiDirectional();
		if(isBiDirectional) {
			AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, nonstopIntermediate + AIOrder.OF_FULL_LOAD_ANY);
		} else {
			AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, nonstopIntermediate + AIOrder.OF_FULL_LOAD_ANY);
		}
		if(useDepotOrder) {
			AIOrder.AppendOrder(vehicle, depot, AIOrder.OF_SERVICE_IF_NEEDED );
		}
		
		AppendSrcToDestOrder(vehicle);
		
		if(destDepot != null) {
			AIOrder.AppendOrder(vehicle, destDepot, nonstopIntermediate );
		}
		if(isTransfer) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, nonstopIntermediate + AIOrder.OF_TRANSFER + AIOrder.OF_NO_LOAD);
		} else if(isBiDirectional) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, nonstopIntermediate);
		} else {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, nonstopIntermediate + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		}
		if(destDepot != null) {
			AIOrder.AppendOrder(vehicle, destDepot, AIOrder.OF_SERVICE_IF_NEEDED ); //5 or 6
		}

		AppendDestToSrcOrder(vehicle);

		/*
		AIOrder.SetOrderCompareValue(vehicle, 1, 80);
		AIOrder.SetOrderCompareFunction(vehicle, 1, AIOrder.CF_MORE_EQUALS );
		AIOrder.SetOrderCondition(vehicle, 1, AIOrder.OC_RELIABILITY );
		AIOrder.SetOrderJumpTo (vehicle, 1, 3)*/
		
		AIVehicle.StartStopVehicle(vehicle);
		return vehicle;
	}
	
	function AppendSrcToDestOrder(vehicle) {
	}
	
	function AppendDestToSrcOrder(vehicle) {
	}
	
	function CloneVehicle(vehicle) {
		local execMode = AIExecMode();
		if(depot == null) {
			return null;
		}
		local result = null;
		HogeAI.WaitForPrice(AIEngine.GetPrice(AIVehicle.GetEngineType(vehicle)));
		result = AIVehicle.CloneVehicle(depot, vehicle, true);
		if(!AIVehicle.IsValidVehicle(result)) {
			HgLog.Warning("CloneVehicle failed. "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIGroup.MoveVehicle(vehicleGroup, result);
		AIVehicle.StartStopVehicle(result);
		return result;
	}

	function ChooseEngine() {
		if(chosenEngine == null || lastChooseEngineDate + 30 < AIDate.GetCurrentDate()) {
			local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
			local engineSet = EstimateEngineSet( cargo, distance,  GetProduction() );
			chosenEngine = engineSet != null ? engineSet.engine : null;
			lastChooseEngineDate = AIDate.GetCurrentDate();
		}
		return chosenEngine;
	}

	function GetVehicleList() {
		return AIVehicleList_Group(vehicleGroup);
	}
	
	function GetNumVehicles() {
		return AIGroup.GetNumVehicles(vehicleGroup, 0);
	}
	
	
	function GetFinalDestPlace() {
		if(isTransfer) {
			return GetDestRoute().GetFinalDestPlace();
		} else {
			return destHgStation.place;
		}
	}
	
	function IsClosed() {
		return isClosed;
	}
	
	function IsRemoved() {
		return isRemoved;
	}
	
	
	function GetDestRoutes() {
		local routes = Route.GetAllRoutes();
		local destRoutes = [];
		if(isTransfer) {
			if(destHgStation.stationGroup == null) {
				HgLog.Warning("destHgStation.stationGroup == null "+this);
				return [];
			}
			foreach(route in routes) {
				if(route.srcHgStation.stationGroup == destHgStation.stationGroup) {
					destRoutes.push(route);
				}
				if(route.IsBiDirectional() && route.destHgStation.stationGroup == destHgStation.stationGroup) {
					destRoutes.push(route);
				}
			}
		} else {
			local destPlace = destHgStation.place;
			if(destPlace == null || !destPlace.IsIncreasable()) {
				return [];
			}
			destRoutes.extend( PlaceDictionary.Get().GetRoutesBySource( destPlace.GetProducing() ) );
			if(HogeAI.Get().stockpiled) {
				foreach(route in PlaceDictionary.Get().GetRoutesByDest( destPlace.GetAccepting() )) {
					if(route.cargo != cargo) {
						destRoutes.push(route);
					}
				}
			}
		}
		return destRoutes;
	}
	
	function HasRailDest(callRoutes = null) {
		if(hasRailDest != null) {
			return hasRailDest;
		}
	
		if(callRoutes == null) {
			callRoutes = [];
		} else {
			foreach(called in callRoutes) {
				if(called == this) {
					hasRailDest = false;
					return hasRailDest;
				}
			}
		}
		callRoutes.push(this);
		foreach(route in GetDestRoutes()) {
			if(!route.IsClosed() && (route.GetVehicleType() == AIVehicle.VT_RAIL || route.HasRailDest(callRoutes))) {
				hasRailDest = true;
				return hasRailDest;
			}
		}
		hasRailDest = false;
		return hasRailDest;
	}

	function GetDestRoute() { 
		if(destRoute == null) {
			local destRoutes = GetDestRoutes();
			if(destRoutes.len() == 0) {
				destRoute = false;
			} else {
				local self = this;
				destRoute = HgArray(destRoutes).Map(function(r):(self) {
					local score = 0;
					if(!r.IsClosed()) {
						if(r.GetVehicleType() == AIVehicle.VT_RAIL) {
							score = 4;
						} else if(r.HasRailDest()) {
							score = 3;
						} else if(r.GetVehicleType() != self.GetVehicleType()) {
							score = 2;
						} else {
							score = 1;
						}
					}
					return {route = r, score = score};
				}).Sort(function(a,b) {
					return b.score - a.score;
				}).array[0].route;
			}
		}
		return destRoute;
	}
	
	function NotifyChangeDestRoute() {
		destRoute = null;
	}
	
	function GetLatestVehicle() {
		local result = null;
		local youngestAge = null;
	
		local vehicleList = GetVehicleList();
		vehicleList.Valuate(AIVehicle.GetAge);
		foreach(vehicle, age in vehicleList) {
			if(youngestAge == null || age < youngestAge) {
				youngestAge = age;
				result = vehicle;
			}
		}
		return result;
	}
	
	function GetDistance() {
		return AIMap.DistanceManhattan(destHgStation.platformTile, srcHgStation.platformTile);
	}
	
	function GetMaxVehicles() {
		local vehicle = GetLatestVehicle();
		local length = 8;
		if(vehicle != null) {
			length = AIVehicle.GetLength(vehicle);
		}
		if(length <= 0) {
			length = 8;
		}
		return (GetDistance() + 4) * 16 / length / 2;
	}
	
	function IsSupportMode() {
		return (TrainRoute.instances.len() >= 1 || AirRoute.instances.len() >= 1) && GetVehicleType() != AIVehicle.VT_AIR;
	}
	
	function ReduceVehicle() {
		maxVehicles -= max(1,(maxVehicles * 0.1).tointeger());
		maxVehicles = max(!GetDestRoute() ? 0 : 5, maxVehicles);
		if(maxVehicles == 0) {
			HgLog.Warning("Route Remove (maxVehicles reach zero)"+this);
			Remove();
			return;
		}
		local vehicleList = GetVehicleList();
		local reduce = vehicleList.Count() - maxVehicles;
		foreach(vehicle,v in vehicleList) {
			if(reduce <= 0) {
				break;
			}
			if(!IsBiDirectional() && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1 ) {
				continue;
			}
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
				//HgLog.Warning("Reduce vehicle.maxVehicles:"+maxVehicles+" vehicleList.Count():"+vehicleList.Count()+" "+this);
				AIVehicle.SendVehicleToDepot (vehicle);
				reduce --;
			}
		}
	}
	
	function CheckBuildVehicle() {
		local execMode = AIExecMode();
		local vehicleList = GetVehicleList();
		
		local sellCounter = 0;
		foreach(vehicle,v in vehicleList) {
			if(AIVehicle.IsStoppedInDepot(vehicle)) {
				//HgLog.Info("SellVehicle "+this);
				AIVehicle.SellVehicle(vehicle);
				sellCounter ++;
			}
		}
		if(sellCounter >= 1) {
			//HgLog.Info("SellVehicle:"+sellCounter+" "+this);
		}
		
		if(isClosed || isTmpClosed) {
			return;
		}
		
		local isBiDirectional = IsBiDirectional();

		if(AIBase.RandRange(100) < 100) {
			//HgLog.Warning("check SendVehicleToDepot "+this+" vehicleList:"+vehicleList.Count());
			foreach(vehicle,v in vehicleList) {
				if((!isBiDirectional && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1) || AIVehicle.GetAge(vehicle) <= 700) {
					continue;
				}
				local notProfitable = AIVehicle.GetProfitLastYear (vehicle) < 0 && AIVehicle.GetProfitThisYear(vehicle) < 0;
				
				if((notProfitable || AIVehicle.GetAgeLeft(vehicle) <= 600)
						&& (AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					//HgLog.Warning("SendVehicleToDepot notProfitable:"+notProfitable+" ageLeft:"+AIVehicle.GetAgeLeft(vehicle)+" "+AIVehicle.GetName(vehicle)+" "+this);
					AIVehicle.SendVehicleToDepot (vehicle);
					if(notProfitable) {
						maxVehicles = min(vehicleList.Count(), maxVehicles);
						maxVehicles = max(0, maxVehicles - 1);
					}
					//HgLog.Info("SendVehicleToDepot(road) "+AIVehicle.GetName(vehicle)+" "+this);
					break;
				}
			}
		}

		local needsAddtinalProducing = NeedsAdditionalProducing();
		
		local isDestOverflow = IsDestOverflow();
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
		if(isDestOverflow || AIBase.RandRange(100) < 5 || (IsSupportMode() && totalVehicles >= GetMaxTotalVehicles() * 0.9)) {
			local supportRouteRate = 0.9;
			local transferRouteRate = 0.95;
			local rootRouteRate = !IsSupportMode() ?  0.95 : 0.8
			local isReduce = false;
			if(isDestOverflow) {
				isReduce = true;
			} else if(!GetDestRoute()) {
				isReduce = totalVehicles > GetMaxTotalVehicles() * rootRouteRate;
			} else if(IsTransfer()){
				isReduce = totalVehicles > GetMaxTotalVehicles() * transferRouteRate;
			} else {
				isReduce = totalVehicles > GetMaxTotalVehicles() * supportRouteRate;
			}
			if(isReduce) {
				ReduceVehicle();
			} else if(needsAddtinalProducing || !IsSupportMode()) {
				maxVehicles ++;
				maxVehicles = min(GetMaxVehicles(), maxVehicles);
			}
		}
		
		if(isTransfer && !needsAddtinalProducing) {
			return;
		}
		
		
		local needsProduction = vehicleList.Count() < 10 ? 10 : 100;
		if(AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo) > needsProduction || vehicleList.Count()==0) {
			local vehicles = vehicleList;
			if(vehicles.Count() < maxVehicles) {
				vehicles.Valuate(AIVehicle.GetState);
				vehicles.KeepValue(AIVehicle.VS_AT_STATION);
				if(vehicles.Count() == 0) {
					local latestVehicle = GetLatestVehicle();
					local firstBuild = 0;
					if(latestVehicle == null || ChooseEngine() != AIVehicle.GetEngineType(latestVehicle)) {
						//HgLog.Info("BuildVehicle "+this);
						latestVehicle = BuildVehicle();
						firstBuild = 1;
					}
					if(latestVehicle != null) {
						local capacity = AIVehicle.GetCapacity(latestVehicle, cargo);
						local cargoWaiting = AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo);
						local buildNum;
						if(IsBiDirectional()) {
							local destWaiting = AIStation.GetCargoWaiting(destHgStation.GetAIStation(),cargo);
							if(destWaiting < cargoWaiting || destWaiting < capacity) {
								buildNum = destWaiting / capacity;
							} else {
								buildNum = max(1, cargoWaiting / capacity);
							}
						} else {
							buildNum = max(1, cargoWaiting / capacity);
						}
						local buildNum = cargoWaiting / capacity;
						buildNum = min(maxVehicles - vehicles.Count(), buildNum) - firstBuild;
						if(!IsSupportMode()) {
							buildNum = min(buildNum, 10);
						}
						if(isTransfer) {
							buildNum = min(1,buildNum);
						}
						
						//HgLog.Info("CloneVehicle "+buildNum+" "+this);
						if(buildNum >= 1) {
							//HgLog.Info("CloneRoadVehicle:"+buildNum+" "+this);
							local startDate = AIDate.GetCurrentDate();
							for(local i=0; i<buildNum && AIDate.GetCurrentDate() < startDate + 30; i++) {
								if(CloneVehicle(latestVehicle) == null) {
									break;
								}
							}
						}
					}
				}
			}
		} 

	}
	
	function NeedsAdditionalProducing(callRoutes = null, isDest = false) {
		if(isClosed || isTmpClosed) {
			return false;
		}
		if(callRoutes == null) {
			callRoutes = [];
		} else {
			foreach(called in callRoutes) {
				if(called == this) {
					return false;
				}
			}
		}
		callRoutes.push(this);
		local hgStation = isDest ? destHgStation : srcHgStation;
		local destRoute = GetDestRoute();
		if(!destRoute || GetNumVehicles() >= GetMaxVehicles()) {
			local latestVehicle = GetLatestVehicle();
			return latestVehicle != null && AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) < AIVehicle.GetCapacity(latestVehicle, cargo) / 2;
		}
		if(HogeAI.Get().stockpiled && !isTransfer && destRoute.destHgStation.place != null 
				&& destHgStation.place.IsSamePlace(destRoute.destHgStation.place)) {
			return true;
		}
		local result = destRoute.NeedsAdditionalProducing(callRoutes, IsDestDest());
		//HgLog.Info("NeedsAdditionalProducing:"+result+" "+this+" destRoute:"+destRoute);
		return result;
	}
	
	function IsDestDest() {
		local destRout = GetDestRoute();
		if(!destRoute) {
			return false;
		}
		if(HogeAI.Get().IsBidirectionalCargo(destRoute.cargo) && isTransfer && destHgStation.stationGroup == destRoute.destHgStation.stationGroup) {
			return true;
		} else {
			return false;//TODO !isTransfer はplaceの一致で判断
		}
	}

	function IsDestOverflow() {
		local destRout = GetDestRoute();
		if(!destRoute) {
			return false;
		}
		return isTransfer && destRoute.IsOverflow(IsDestDest());
	}

	function IsOverflow(isDest = false) {
		local latestVehicle = GetLatestVehicle();
		local capacity = latestVehicle != null ? AIVehicle.GetCapacity(latestVehicle, cargo) : 0;
		if(isDest) {
			return AIStation.GetCargoWaiting (destHgStation.GetAIStation(), cargo) > max(300, capacity * 3);
		} else {
			return AIStation.GetCargoWaiting (srcHgStation.GetAIStation(), cargo) > max(300, capacity * 3);
		}
	}
	
	function IsValidDestStationCargo() {
		if(destHgStation.stationGroup == null) {
			if(destHgStation.IsAcceptingCargo(cargo)) {
				return true;
			}
		} else {
			foreach(hgStation in destHgStation.stationGroup.hgStations) {
				if(hgStation.IsAcceptingCargo(cargo)) {
					return true;
				}
			}
		}
		return false;
	}
	
	function Remove() {
		isClosed = true;
		isRemoved = true;
		Close();
	}
	
	function Close() {
		isClosed = true;
		foreach(vehicle,v in GetVehicleList()) {
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
				AIVehicle.SendVehicleToDepot (vehicle);
			}
		}
	}
	
	function ReOpen() {
		isRemoved = false;
		isClosed = false;
		isTmpClosed = false;
		this.maxVehicles = GetMaxVehicles(); // これで良いのだろうか？
		PlaceDictionary.Get().AddRoute(this);
		HgLog.Warning("Route ReOpen."+this);
	}
	
	function CheckRenewal() {
		local execMode = AIExecMode();
		
		if(!isClosed) {
			local destRoute = GetDestRoute();
			if(GetVehicleType() != AIVehicle.VT_AIR && !srcHgStation.IsTownStop()) {
				local routes = [];
				if(srcHgStation.place != null) {
					routes.extend(PlaceDictionary.Get().GetUsedAsSourceCargoByRailOrAir(srcHgStation.place, cargo));
				}
				if(IsBiDirectional() && destHgStation.place != null) {
					routes.extend(PlaceDictionary.Get().GetUsedAsSourceCargoByRailOrAir(destHgStation.place, cargo));
				}
				foreach(route in routes) {
					//HgLog.Info("GetUsedTrainRoutes:"+route+" destRoute:"+destRoute+" "+this);
					if(!(IsTransfer() && route.IsSrcStationGroup(destHgStation.stationGroup)) && route.NeedsAdditionalProducing()) {
						if(!destRoute || IsTransfer() || route.IsSameSrcAndDest(this)) {// industryへのsupply以外が対象(for FIRS)
							isClosed = true;
							isRemoved = true;
							HgLog.Warning("Route Remove (Collided rail or air route found)"+this);
						}
					}
				}
			}
			
			if(!isTmpClosed 
					&& ((!isTransfer && !IsValidDestStationCargo())
						|| (isTransfer && (!destRoute || destRoute.IsClosed())))) {
				if(!isTransfer) {
					HgLog.Warning("Route Close (dest can not accept)"+this);
					local destPlace = destHgStation.place.GetProducing();
					if(destPlace instanceof HgIndustry && !destPlace.IsClosed()) {
						local stock = destPlace.GetStockpiledCargo(cargo) ;
						if(stock > 0 && !IsSupportMode()) {
							isTmpClosed = true;
							maxVehicles = min(GetNumVehicles(), maxVehicles);
							maxVehicles = min(1, maxVehicles - max(maxVehicles/10, 1));
						}
					}
				} else {
					HgLog.Warning("Route Close (DestRoute["+destRoute+"] closed)"+this);
				}
				this.destRoute = null; //一旦キャッシュクリア
				this.hasRailDest = null;
				if(!isTmpClosed) {
					isClosed = true;
				}
			}
		}
		if((isClosed || isTmpClosed) && !isRemoved) {
			local destRoute = GetDestRoute();
			if((!isTransfer && IsValidDestStationCargo())
					|| (isTransfer && destRoute!=false && !destRoute.IsClosed())) {
				ReOpen();
			}
		}
		
		if(isClosed) {
			Close();
			return;
		}
		
		if(AIBase.RandRange(100)>=1) {
			return;
		}
		
		destRoute = null; //たまにキャッシュをクリアする
		hasRailDest = null;

		local engine = ChooseEngine();
		if(engine==null) {
			return;
		}
		
		local isAll = true;
		foreach(vehicle,v in GetVehicleList()) {
			if(engine != AIVehicle.GetEngineType(vehicle)) {
				//HgLog.Warning("Engine renewal."+this);
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			} else {
				isAll = false;
			}
		}
		if(isAll) {
			BuildVehicle();
		}
	}
	
	function _tostring() {
		return (IsTransfer() ? "T:" : "") + destHgStation.GetName() + "<-"+(IsBiDirectional()?">":"") + srcHgStation.GetName() + "[" + AICargo.GetName(cargo) + "]" + GetLabel();
	}
}

class RouteBuilder {
	dest = null;
	srcPlace = null;
	cargo = null;
	
	destStationGroup = null;
	destPlace = null;
	
	constructor(dest, srcPlace, cargo) {
		this.dest = dest;
		if(dest instanceof StationGroup) {
			this.destStationGroup = dest;
		} else if(dest instanceof Place) {
			this.destPlace = dest;
		} else {
			HgLog.Warning("Illegal parameter type dest "+typeof dest);
		}
		this.srcPlace = srcPlace;
		this.cargo = cargo;
	}
	
	function GetLabel() {
		return GetRouteClass().GetLabel();
	}
	
	function GetVehicleType() {
		return GetRouteClass().GetVehicleType();
	}

	function ExistsSameRoute() {
		return Route.SearchRoute( GetRouteClass().instances, srcPlace, destPlace, destStationGroup, cargo ) != null;
	}
	
	function GetDestLocation() {
		if(destStationGroup != null) {
			return destStationGroup.hgStations[0].platformTile;
		} else {
			return destPlace.GetLocation();
		}
	}
	
	function _tostring() {
		return "Build "+GetLabel()+" route "+(destPlace != null ? destPlace.GetName() : "T:"+destStationGroup.hgStations[0].GetName())+"<-"+srcPlace.GetName()+" "+AICargo.GetName(cargo);
	}
}

class CommonRouteBuilder extends RouteBuilder {
	makeReverseRoute = null;
	
	constructor(dest, srcPlace, cargo) {
		RouteBuilder.constructor(dest, srcPlace, cargo);
		makeReverseRoute = false;
	}
			
	function Build() {
		if(ExistsSameRoute()) {
			HgLog.Info("Already exist."+this);
			return null;
		}
		
		if(destPlace != null) {
			if(destPlace.GetProducing().IsTreatCargo(cargo)) {
				destPlace = destPlace.GetProducing();
			}
		}
	
		local dest = destPlace != null ? destPlace : destStationGroup.hgStations[0];
		if(Place.IsNgPathFindPair(srcPlace, dest, GetVehicleType())) {
			HgLog.Warning("IsNgPathFindPair==true "+this);
			return null;
		}
		if(Place.IsNgPlace(dest, GetVehicleType())) {
			HgLog.Warning("dest is ng facility."+this);
			return null;
		}
		if(Place.IsNgPlace(srcPlace, GetVehicleType())) {
			HgLog.Warning("src is ng facility."+this);
			return null;
		}

		local testMode = AITestMode();
		local engineSet = GetRouteClass().EstimateEngineSet.call( GetRouteClass(), 
			cargo, srcPlace.DistanceManhattan(GetDestLocation()), srcPlace.GetLastMonthProduction(cargo));
		if(engineSet==null) {
			HgLog.Warning("No suitable engine. "+this);
			return null;
		}
		
		local stationFactory = CreateStationFactory();
		if(stationFactory == null) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("CreateStationFactory failed. "+this);
			return null;
		}
		
		local destHgStation = null;
		local isTransfer = null;
		if(destStationGroup != null) {
			isTransfer = true;
			destHgStation = stationFactory.CreateBestOnStationGroup( destStationGroup, cargo, srcPlace.GetLocation() );
		} else if(destPlace != null) {
			isTransfer = false;
			if(destPlace instanceof TownCargo || GetVehicleType() == AIVehicle.VT_WATER) {
				stationFactory.nearestFor = srcPlace.GetLocation();
			}
			destHgStation = stationFactory.CreateBest( destPlace, cargo, srcPlace.GetLocation() );
		} else {
			HgLog.Warning("dest is not set."+this);
			return null;
		}
		local isShareDestStation = false;
		if(destHgStation == null) {
			destHgStation = HgStation.SearchStation(destPlace == null ? destStationGroup : destPlace, stationFactory.GetStationType(), cargo, true);
			if(destHgStation == null || !destHgStation.CanShareByMultiRoute()) {
				Place.AddNgPlace(dest,GetVehicleType());
				HgLog.Warning("No destStation."+this);
				return null;
			}
			HgLog.Warning("Share dest station:"+destHgStation.GetName()+" "+this);
			isShareDestStation = true;
		}
		local list = HgArray(destHgStation.GetTiles()).GetAIList();
		HogeAI.notBuildableList.AddList(list);
		if(srcPlace instanceof TownCargo || GetVehicleType() == AIVehicle.VT_WATER) {
			stationFactory.nearestFor = destHgStation.platformTile;
		}
		local srcHgStation = stationFactory.CreateBest(srcPlace, cargo, destHgStation.platformTile);
		HogeAI.notBuildableList.RemoveList(list);
		local isShareSrcStation = false;
		if(srcHgStation == null) {
			srcHgStation = HgStation.SearchStation(srcPlace, stationFactory.GetStationType(), cargo, false);				
			if(srcHgStation == null || !srcHgStation.CanShareByMultiRoute()) {
				Place.AddNgPlace(srcPlace,GetVehicleType());
				HgLog.Warning("stationFactory.CreateBest failed."+this);
				return null;
			}
			HgLog.Warning("Share src station:"+srcHgStation.GetName()+" "+this);
			isShareSrcStation = true;
		}

		local execMode = AIExecMode();
		local rollbackFacitilies = [];
		
		if(!isShareDestStation && !destHgStation.BuildExec()) {
			Place.AddNgPlace(dest,GetVehicleType());
			HgLog.Warning("destHgStation.BuildExec failed."+this);
			return null;
		}
		if(!isShareDestStation) {
			rollbackFacitilies.push(destHgStation);
		}
		
		if(!isShareSrcStation && !srcHgStation.BuildExec()) {
			Place.AddNgPlace(srcPlace,GetVehicleType());
			HgLog.Warning("srcHgStation.BuildExec failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		if(!isShareSrcStation) {
			rollbackFacitilies.push(srcHgStation);
		}
		
		if(srcHgStation.stationGroup == destHgStation.stationGroup) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("Same stationGroup."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		
		local pathBuilder = CreatePathBuilder(engineSet.engine, cargo);
		if(!pathBuilder.BuildPath(destHgStation.GetEntrances(), srcHgStation.GetEntrances())) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("BuildPath failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile)
		if(pathBuilder.path != null && distance > 40 && distance * 2 < pathBuilder.path.GetTotalDistance()) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("Too long path distance."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		
		local route = GetRouteClass()();
		route.cargo = cargo;
		route.srcHgStation = srcHgStation;
		route.destHgStation = destHgStation;
		route.isTransfer = isTransfer;		
		route.Initialize();

		if(!route.BuildDepot(pathBuilder.path)) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("BuildDepot failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		rollbackFacitilies.push(route.depot);

		if(pathBuilder.path != null && distance > 30) {
			route.BuildDestDepot(pathBuilder.path);
			rollbackFacitilies.push(route.destDepot);
		}
		route.SetPath(pathBuilder.path);
		local vehicle = route.BuildVehicle();
		if(vehicle==null) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("BuildVehicle failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		local reverseRoute = null;
		if(makeReverseRoute && route.IsBiDirectional()) {
			reverseRoute = BuildReverseRoute(route, pathBuilder.path);
		}
		if(reverseRoute == null) {
			route.CloneVehicle(vehicle);
		}
		//Place.SetUsedPlaceCargo(srcPlace,cargo); NgPathFindPairで管理する
		route.instances.push(route);
		HgLog.Info("CommonRouteBuilder.Build succeeded."+route);
		
		PlaceDictionary.Get().AddRoute(route);
		return route;
	}
	
	function BuildReverseRoute( originalRoute, path ) {
		local reverseRoute = GetRouteClass()();
		reverseRoute.cargo = originalRoute.cargo;
		reverseRoute.srcHgStation = originalRoute.destHgStation;
		reverseRoute.destHgStation = originalRoute.srcHgStation;
		reverseRoute.isTransfer = false;
		reverseRoute.Initialize();
		
		if(path != null) {
			path = path.Reverse();
		}
		
		if(originalRoute.destDepot != null) {
			reverseRoute.depot = originalRoute.destDepot;
		} else {
			if(!reverseRoute.BuildDepot(path)) {
				HgLog.Warning("reverseRoute.BuildDepot failed."+this);
				return null;
			}
		}
		reverseRoute.destDepot = originalRoute.depot;
		if(path != null) {
			reverseRoute.SetPath(path);
		}
		local vehicle = reverseRoute.BuildVehicle();
		if(vehicle==null) {
			HgLog.Warning("BuildVehicle failed.(BuildReverseRoute)"+this);
			return null;
		}
		reverseRoute.instances.push(reverseRoute);
		HgLog.Info("CommonRouteBuilder.BuildReverseRoute succeeded."+reverseRoute);
		PlaceDictionary.Get().AddRoute(reverseRoute);
		
		return reverseRoute;
	}
	
	function Rollback(facilities) {
		foreach(f in facilities) {
			if(f != null) {
				if(typeof f == "integer") {
					AITile.DemolishTile(f);
				} else {
					f.Remove();
				}
			}
		}
	}
}