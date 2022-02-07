
class Route {
	static allVehicleTypes = [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_WATER, AIVehicle.VT_AIR];

	static function SearchRoutes( bottomRouteWeighting, srcPlace, destPlace, destStationGroup, cargo ) {
		return HgArray(ArrayUtils.And(
			srcPlace.GetProducing().GetRoutesUsingSource(),
			destPlace != null ? destPlace.GetRoutes() : destStationGroup.GetUsingRoutes())).Filter(
				function(route):(cargo, bottomRouteWeighting) {
					return route.cargo == cargo && route.GetRouteWeighting() >= bottomRouteWeighting;
				}).array;
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

	static function Estimate(vehicleType, cargo, distance, production, isBidirectional) {
		local estimateTable = HogeAI.Get().estimateTable;
		local productionIndex = HogeAI.Get().GetEstimateProductionIndex(production);
		local distanceIndex = HogeAI.Get().GetEstimateDistanceIndex(distance);
		local estimate = estimateTable[cargo][vehicleType][productionIndex][distanceIndex][isBidirectional?1:0];
		if(estimate == null) {
			if(estimate == null) {
				local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
				estimate = routeClass.EstimateEngineSet(routeClass, cargo, distance, production, isBidirectional);
				if(estimate == null) {
					estimate = 0;
				} else {
					estimate.value <- HogeAI.Get().roiBase ? estimate.roi : estimate.routeIncome;
				}
			}
			estimateTable[cargo][vehicleType][productionIndex][distanceIndex][isBidirectional?1:0] = estimate;
		}
		if(estimate == 0) {
			return null;
		} else {
			return estimate;
		}
	}
	
		
	function IsTooManyVehiclesForNewRoute(self) {
		return AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType()) >= self.GetMaxTotalVehicles() * self.GetThresholdVehicleNumRateForNewRoute();
	}
	
	function IsTooManyVehiclesForSupportRoute(self) {
		return AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType()) >= self.GetMaxTotalVehicles() * self.GetThresholdVehicleNumRateForSupportRoute();
	}
	
	
	function GetRouteWeighting() {
		return GetRouteWeightingVt(GetVehicleType());
	}

	function GetRouteWeightingVt(vehicleType) {
		switch(vehicleType) {
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

	function GetRouteCapacity() {
		return GetRouteCapacityVt(GetVehicleType());
	}
	
	function GetRouteCapacityVt(vehicleType) {
		switch(vehicleType) {
			case AIVehicle.VT_RAIL:
				return 10;
			case AIVehicle.VT_WATER:
				return 10;
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
	
	function NeedsToMeetDestDemandPlace(place) {
		if(HogeAI.Get().ecs && place != null && place instanceof HgIndustry) {
			return true;
		}
		return false;
	}
	
	function GetPlacesToMeetDemand() {
		local result = [];
		if( NeedsAdditionalProducing() && !(this instanceof RoadRoute && IsTransfer()) ) {
			if(srcHgStation.place != null) {
				local acceptingPlace = srcHgStation.place.GetAccepting();
				if(acceptingPlace.IsIncreasable() && !(this instanceof RoadRoute && acceptingPlace.IsRaw())) {
					result.push(acceptingPlace);
				}
			}
			if(IsBiDirectional() && destHgStation.place != null) {
				local acceptingPlace = destHgStation.place.GetAccepting();
				if(acceptingPlace.IsIncreasable() && !(this instanceof RoadRoute && acceptingPlace.IsRaw())) {
					result.push(acceptingPlace);
				}
			}
		}
		result.extend(GetPlacesToMeetDestDemand());
		return result;
	}
	
	function GetPlacesToMeetDestDemand() {
		local result = [];
		if(NeedsToMeetDestDemandPlace(destHgStation.place)) {
			result.push(destHgStation.place);
		}
		if(IsBiDirectional() && NeedsToMeetDestDemandPlace(srcHgStation.place)) {
			result.push(srcHgStation.place);
		}
		return result;
	}
	
	
	function GetProduction() {
		local planned = AIStation.GetCargoPlanned(srcHgStation.GetAIStation(), cargo);
		local lastMonth = srcHgStation.place != null ? srcHgStation.place.GetLastMonthProduction(cargo) : 0;
		return max(planned, lastMonth);
	}

	function OnIndustoryClose(industry) {
		local srcPlace = srcHgStation.place;
		if(srcPlace != null && srcPlace instanceof HgIndustry && srcPlace.industry == industry) {
			if(GetVehicleType() == AIVehicle.VT_RAIL) {
				HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. Search transfer." + this);
				HogeAI.Get().SearchAndBuildToMeetSrcDemandUsingRailTransfer(this, true);
				HogeAI.Get().SearchAndBuildToMeetSrcDemandTransfer(this);
			}
			local saved = false;
			foreach(route in srcHgStation.stationGroup.GetUsingRoutesAsDest()) {
				if(route.IsTransfer() && route.cargo == cargo) {
					HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. But saved because transfer route found."+this);
					saved = true;
				}
			}
			if(saved) {
				srcHgStation.place = null;
				srcHgStation.savedData = srcHgStation.Save();
			} else {
				HgLog.Warning("Remove Route (src industry closed:"+AIIndustry.GetName(industry)+")"+this);
				Remove();
			}
		}
		local destPlace = destHgStation.place;
		if(destPlace != null && destPlace instanceof HgIndustry && destPlace.industry == industry) {
			HgLog.Warning("Remove Route (dest industry closed:"+AIIndustry.GetName(industry)+")"+this);
			Remove();
		}
		
/*	
		local destPlace = GetFinalDestPlace();
		if(destPlace != null && (destPlace instanceof HgIndustry) && destPlace.industry == industry) {
			HgLog.Warning("Close dest industry:"+AIIndustry.GetName(industry));
			isClosed = true;
			Close();
		}*/
	}
	
	function GetDistance() {
		return AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
	}
}


class CommonRoute extends Route {

	
	function EstimateEngineSet(self, cargo, distance, production, isBidirectional, isTownBus=false) {
		local engineSets = self.GetEngineSetsVt(self, self.GetVehicleType(), cargo, distance, production, isBidirectional, isTownBus);
		if(engineSets.len() >= 1) {
			return engineSets[0];
		} else {
			return null;
		}
	}
	
	function GetEngineSetsVt(self, vehicleType, cargo, distance, production, isBidirectional, isTownBus=false ) {
		if(distance == 0) {
			return [];
		}
		local engineList = AIEngineList(vehicleType);
		engineList.Valuate(AIEngine.CanRefitCargo, cargo);
		engineList.KeepValue(1);
		
		if(isTownBus) {
			local roadType = AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin();
			engineList.Valuate(AIEngine.HasPowerOnRoad, roadType );
			engineList.KeepValue(1);
		} else if((typeof self) == "instance" && self instanceof RoadRoute) {
			engineList.Valuate(AIEngine.HasPowerOnRoad, self.GetRoadType());
			engineList.KeepValue(1);
		}
		if((typeof self) == "instance" && self instanceof AirRoute) {
			local usableBigPlane = Air.GetAiportTraits(self.srcHgStation.airportType).supportBigPlane 
				&& Air.GetAiportTraits(self.destHgStation.airportType).supportBigPlane;
			if(!usableBigPlane) {
				engineList.Valuate( AIEngine.GetPlaneType );
				engineList.RemoveValue(AIAirport.PT_BIG_PLANE );
			}
		}
		local orderDistance;
		if((typeof self) == "instance" && self instanceof Route) {
			orderDistance = AIOrder.GetOrderDistance(self.GetVehicleType(), self.srcHgStation.platformTile, self.destHgStation.platformTile);
		} else {
			local x;
			local y;
			if(distance < AIMap.GetMapSizeX()-2) {
				x = distance + 1;
				y = 1;
			} else {
				x = AIMap.GetMapSizeX()-2;
				y = min(AIMap.GetMapSizeY()-2, distance - x + 1);
			}
			AIMap.GetMapSizeY()
			orderDistance = AIOrder.GetOrderDistance(self.GetVehicleType(), AIMap.GetTileIndex(1,1), AIMap.GetTileIndex(x,y));
		}
		local pathDistance;
		if((typeof self) == "instance" && self instanceof Route) {
			pathDistance = GetPathDistance();
		} else {
			pathDistance = distance;
		}
		
		
		engineList.Valuate( function(e):(orderDistance) {
			local d = AIEngine.GetMaximumOrderDistance(e);
			if(d == 0) {
				return 1;
			} else {
				return d > orderDistance ? 1 : 0;
			}
		} );
		engineList.KeepValue(1);
		
		production = max(20, production);
		
		local buildingCost = self.GetBuildingCost(distance)
		
		return HgArray.AIListKey(engineList).Map(function(e):( distance, pathDistance, cargo, production, isBidirectional, buildingCost, vehicleType, self ) {
			local capacity = self.GetEngineCapacity(self,e,cargo);
			if(capacity == 0) {
				return { income = 0 };
			}
			local runningCost = AIEngine.GetRunningCost(e);
			local cruiseSpeed;
			if(vehicleType == AIVehicle.VT_AIR) {
				cruiseSpeed = AIEngine.GetMaxSpeed(e);
			} else {
				cruiseSpeed = max( 4, AIEngine.GetMaxSpeed(e) * ( 100 + AIEngine.GetReliability(e)) / 200 );
			}
			local maxVehicles = self.EstimateMaxVehicles(self, pathDistance, cruiseSpeed);
			if(self.IsSupportModeVt(vehicleType) && self.GetMaxTotalVehicles() / 2 < AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType)) {
				maxVehicles = min(maxVehicles, 10); // ROADはなるべく少ない車両数で済ませられる見積をするため
			}
			local loadingTime = min(5, capacity / 10); // TODO: capacity/cargo/vehicleTypeによって異なる

			local days;
			if(vehicleType == AIVehicle.VT_AIR && cruiseSpeed > 80) {
				local avgBrokenDistance = min(100 * pathDistance / ( (AIEngine.GetReliability(e) * 150 / 100) * cruiseSpeed * 24 / 664), 100) * pathDistance / (100 * 2);
				days = (((pathDistance - avgBrokenDistance) * 664 / cruiseSpeed / 24 + avgBrokenDistance * 664 / 80 / 24) + loadingTime) * 2;
				//local days2 = (pathDistance * 664 / cruiseSpeed / 24 + loadingTime) * 2;
				//HgLog.Info("debug: days:" + days + " old:" + days2 + " d:"+pathDistance+" v:"+cruiseSpeed+" r:"+AIEngine.GetReliability(e));
			} else {
				days = (pathDistance * 664 / cruiseSpeed / 24 + loadingTime) * 2;
			}
			
			local routeCapacity = 0;
			switch(vehicleType) {
				case AIVehicle.VT_ROAD:
					routeCapacity = capacity * 5;
					break;
				case AIVehicle.VT_AIR:
					routeCapacity = capacity;
					break;
				case AIVehicle.VT_WATER:
					routeCapacity = capacity * 3;
					break;
			};
			local deliverableProduction = min(production , routeCapacity);
			local vehiclesPerRoute = max( min( maxVehicles, deliverableProduction * 12 * days / ( 365 * capacity ) ), 1 ); // TODO 往復に1年以上かかる場合計算が狂う
			local inputProduction = production;
			if(vehiclesPerRoute < (isBidirectional ? 3 : 2)) {
				inputProduction = inputProduction / 2;
			}
			
			
			local waitingInStationTime = max(loadingTime, (capacity * vehiclesPerRoute - (inputProduction * days) / 30)*30 / inputProduction / vehiclesPerRoute );
			
			local incomePerOneTime = AICargo.GetCargoIncome(cargo,distance,days);
			local income = incomePerOneTime * 365 / (days + waitingInStationTime) * (isBidirectional ? 2 : 1) * capacity - runningCost;;
			//local income = CargoUtils.GetCargoIncome( distance, cargo, cruiseSpeed, waitingInStationTime, isBidirectional ) * capacity - runningCost;
			local price = AIEngine.GetPrice(e);
			local routeIncome = income * vehiclesPerRoute;
			local roi = routeIncome * 1000 / (price * vehiclesPerRoute + buildingCost);
			local value;
			return {
				engine = e
				price = price
				runningCost = runningCost
				income = income
				routeIncome = routeIncome
				roi = roi
				value = HogeAI.Get().roiBase ? roi : routeIncome
				capacity = capacity
				vehiclesPerRoute = vehiclesPerRoute
			};
		}).Filter(function(e) {
			return e.income > 0;
		}).Sort(function(a,b) {
			return b.value - a.value;
		}).array;
	}
	
	function GetEngineCapacity(self, engine, cargo) {
		local result;
		if(self.instances.len() >= 1) {
			foreach(route in self.instances) {
				result = AIVehicle.GetBuildWithRefitCapacity(route.depot, engine, cargo);
				if(result != -1) {
					return result;
				}
			}
		}
		result = AIEngine.GetCapacity(engine);
		if( self.GetVehicleType() == AIVehicle.VT_AIR) {
			if(cargo == HogeAI.GetPassengerCargo()) {
				result = result * 115 / 100;
			} else {
				result /= 2;
			}
		}
		return result;
	}
	
	function CheckReduce(vehicleType, routeInstances, maxVehicles) {
		if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType ) > maxVehicles * 0.9 ) {
			local minProfit = null;
			local minRoute = null;
			foreach(route in routeInstances) {
				if(route.IsClosed()) {
					continue;
				}
				local vehicleList = AIVehicleList_Group(route.vehicleGroup);
				vehicleList.Valuate(AIVehicle.GetAge);
				vehicleList.KeepAboveValue(700);
				if(vehicleList.Count()==0) {
					continue;
				}
				local sum = 0;
				foreach(vehicle,v in vehicleList) {
					sum += AIVehicle.GetProfitLastYear(vehicle) + AIVehicle.GetProfitThisYear(vehicle);
				}
				local routeProfit = sum / (vehicleList.Count() * 2);
				if(minProfit == null || minProfit > routeProfit) {
					minProfit = routeProfit;
					minRoute = route;
				}
			}
			if(minRoute != null) {
				HgLog.Warning("RemoveRoute minProfit:"+minProfit+" "+minRoute);
				minRoute.Remove();
//				minRoute.ReduceVehicle(true);
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
	lastDestClosedDate = null;
	useDepotOrder = null;
	isDestFullLoadOrder = null;
	cannotChangeDest = null;
	
	chosenEngine = null;
	lastChooseEngineDate = null;
	destRoute = null;
	hasRailDest = null;
	
	constructor() {
		this.isClosed = false;
		this.isTmpClosed = false;
		this.isRemoved = false;
		this.useDepotOrder = true;
		this.isDestFullLoadOrder = false;
		this.cannotChangeDest = false;
	}
	
	function Initialize() {
		if(this.vehicleGroup == null) {
			this.vehicleGroup = AIGroup.CreateGroup(GetVehicleType());
			local src = srcHgStation.GetName();
			local dest = destHgStation.GetName();
			src = src.slice(0,min(11,src.len()));
			dest = dest.slice(0,min(11,dest.len()));
			local s = (IsTransfer()?"T:":"")+ dest + "<-"+(IsBiDirectional()?">":"") + src +"[" + AICargo.GetName(cargo) + "]" + GetLabel();
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
		t.lastDestClosedDate <- lastDestClosedDate;
		t.useDepotOrder <- useDepotOrder;
		t.isDestFullLoadOrder <- isDestFullLoadOrder;
		t.cannotChangeDest <- cannotChangeDest;
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
		isRemoved = t.isRemoved;
		maxVehicles = t.maxVehicles;
		lastDestClosedDate = t.lastDestClosedDate;
		useDepotOrder = t.useDepotOrder;
		isDestFullLoadOrder = t.isDestFullLoadOrder;
		cannotChangeDest = t.cannotChangeDest;
	}

	function SetPath(path) {
	}
	
	function IsBiDirectional() {
		return !isTransfer && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
	}
	
	function IsTransfer() {
		return isTransfer;
	}
	
	function IsRoot() {
		return !GetDestRoute();
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
		local loadOrderFlags =  nonstopIntermediate | (!AITile.IsStationTile (srcHgStation.platformTile) ? 0 : AIOrder.OF_FULL_LOAD_ANY);
		if(isBiDirectional) {
			if(!AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, loadOrderFlags)) {
				HgLog.Warning("AppendOrder failed. destination: "+HgTile(srcHgStation.platformTile)+" "+AIError.GetLastErrorString()+" "+this);
			}
		} else {
			if(!AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, loadOrderFlags)) {
				HgLog.Warning("AppendOrder failed. destination: "+HgTile(srcHgStation.platformTile)+" "+AIError.GetLastErrorString()+" "+this);
			}
		}
		if(useDepotOrder) {
			AIOrder.AppendOrder(vehicle, depot, AIOrder.OF_SERVICE_IF_NEEDED );
		}
		
		AppendSrcToDestOrder(vehicle);
		
		if(destDepot != null) {
			AIOrder.AppendOrder(vehicle, destDepot, nonstopIntermediate );
		}
		if(isTransfer) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, 
				nonstopIntermediate + (!AITile.IsStationTile(destHgStation.platformTile) ? 0 : (AIOrder.OF_TRANSFER | AIOrder.OF_NO_LOAD)));
		} else if(isBiDirectional) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, nonstopIntermediate | (isDestFullLoadOrder ? AIOrder.OF_FULL_LOAD_ANY : 0));
		} else {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile,
				nonstopIntermediate + (!AITile.IsStationTile(destHgStation.platformTile) ? 0 : (AIOrder.OF_UNLOAD | AIOrder.OF_NO_LOAD)));
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
		
		maxVehicles = GetMaxVehicles();
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		
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
			local engineSet = EstimateEngineSet( this, cargo, distance,  GetProduction(), IsBiDirectional() );
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
	
	function GetPathDistance() {
		return AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
	}
	
	
	function GetDestRoutes() {
		local destRoutes = [];
		if(isTransfer) {
			if(destHgStation.stationGroup == null) {
				HgLog.Warning("destHgStation.stationGroup == null "+this);
				return [];
			}
			foreach(route in destHgStation.stationGroup.GetUsingRoutes()) {
				if(route == this) {
					continue;
				}
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
		
	function EstimateMaxVehicles(self, distance, speed, vehicleLength = 0) {
		if(vehicleLength <= 0) {
			vehicleLength = 8;
		}
		local days = distance * 664 / speed / 24;
		return min( days * 2 / self.GetStationDateSpan(self) + 1, (distance + 4) * 16 / vehicleLength / 2 );
	}

	function GetMaxVehicles() {
		local vehicle = GetLatestVehicle();
		if(vehicle == null) {
			return 1;
		}
		local length = AIVehicle.GetLength(vehicle);
		local engine = AIVehicle.GetEngineType(vehicle);
		local cruiseSpeed = max( 4, AIEngine.GetMaxSpeed(engine) * ( 100 + AIEngine.GetReliability(engine)) / 200);
		return EstimateMaxVehicles(this, GetDistance(), cruiseSpeed, length);
	}
	
	function GetStationDateSpan(self) {
		switch(self.GetVehicleType()) {
			case AIVehicle.VT_RAIL:
				return 5;
			case AIVehicle.VT_ROAD:
				return 2;
			case AIVehicle.VT_WATER:
				return 1;
			case AIVehicle.VT_AIR:
				return 12; // override
			default:
				HgLog.Error("Not defined stationDateSpan(Route.Estimate)"+self);
		}
	}
	
	function IsSupportModeVt(vehicleType) {
		return (TrainRoute.instances.len() >= 1 || AirRoute.instances.len() >= 1) && vehicleType != AIVehicle.VT_AIR;
	}
	
	function IsSupportMode() {
		return IsSupportModeVt(GetVehicleType());
	}
	
	function ReduceVehicle(force = false) {
		local vehicleList = GetVehicleList();
		maxVehicles = min(vehicleList.Count(), maxVehicles);
		maxVehicles -= max(1,(maxVehicles * 0.1).tointeger());
		if(!force) {
			maxVehicles = max(!GetDestRoute() ? 0 : 5, maxVehicles);
		}
		maxVehicles = min(maxVehicles, GetMaxVehicles());
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		if(maxVehicles == 0) {
			HgLog.Warning("Route Remove (maxVehicles reach zero)"+this);
			Remove();
			return;
		}
		local reduce = vehicleList.Count() - maxVehicles;
		foreach(vehicle,v in vehicleList) {
			if(reduce <= 0) {
				break;
			}
			if(!force && !IsBiDirectional() && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1 ) {
				continue;
			}
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
				HgLog.Info("ReduceVehicle maxVehicles:"+maxVehicles+" vehicleList.Count:"+vehicleList.Count()+" "+this);
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
		
		if((sellCounter >= 1 || vehicleList.Count() == 0 ) && isRemoved) {
			if(sellCounter == vehicleList.Count()) {
				HgLog.Warning("All vehicles removed."+this);
				ArrayUtils.Remove(getclass().instances, this);
			}
		
			//HgLog.Info("SellVehicle:"+sellCounter+" "+this);
		}
		if(isTmpClosed) {
			return;
		}
		if(isClosed) {
			foreach(vehicle,v in vehicleList) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}
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
						//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
					}
					//HgLog.Info("SendVehicleToDepot(road) "+AIVehicle.GetName(vehicle)+" "+this);
					break;
				}
			}
		}

		local needsAddtinalProducing = NeedsAdditionalProducing();
		
		local needsReduce = IsDestOverflow() || maxVehicles > GetMaxVehicles();
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
		if(needsReduce || AIBase.RandRange(100) < 5 || (IsSupportMode() && totalVehicles >= GetMaxTotalVehicles() * 0.85)) {
			local supportRouteRate = 0.9;
			local transferRouteRate = 0.85;
			local rootRouteRate = !IsSupportMode() ?  0.95 : 0.8;
			local isReduce = false;
			if(needsReduce) {
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
			}
		} else if(AIBase.RandRange(100) < 10) {
			if(needsAddtinalProducing || !IsSupportMode() || IsOverflow()) {
				maxVehicles ++;
				maxVehicles = min(GetMaxVehicles(), maxVehicles);
				//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
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
						if(latestVehicle != null) {
							CloneVehicle(latestVehicle);
							firstBuild = 2;
						}
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
							buildNum = min(buildNum, 3);
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
		if(isTransfer && destRoute.IsBiDirectional() && destHgStation.stationGroup == destRoute.destHgStation.stationGroup) {
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
			return AIStation.GetCargoWaiting (destHgStation.GetAIStation(), cargo) > max(300, capacity * 3) || AIStation.GetCargoRating(destHgStation.GetAIStation(), cargo) < 30;
		} else {
			return AIStation.GetCargoWaiting (srcHgStation.GetAIStation(), cargo) > max(300, capacity * 3) || AIStation.GetCargoRating(srcHgStation.GetAIStation(), cargo) < 30;
		}
	}
	
	function IsValidDestStationCargo() {
		foreach(hgStation in destHgStation.stationGroup.hgStations) {
			if(hgStation.IsAcceptingCargo(cargo)) {
				return true;
			}
		}
		if(IsBiDirectional()) {
			foreach(hgStation in srcHgStation.stationGroup.hgStations) {
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
		PlaceDictionary.Get().RemoveRoute(this);
	}
	
	function Close() {
		isClosed = true;
	}
	
	function ReOpen() {
		isRemoved = false;
		isClosed = false;
		isTmpClosed = false;
		this.maxVehicles = GetMaxVehicles(); // これで良いのだろうか？
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		PlaceDictionary.Get().AddRoute(this);
		HgLog.Warning("Route ReOpen."+this);
	}
	
	function CheckRenewal() {
		local execMode = AIExecMode();
		
		if(isRemoved) {
			return;
		}
		if(srcHgStation.place != null && srcHgStation.place.IsClosed()) {
			HgLog.Warning("Route Remove (src place closed)"+this);
			Remove();
			return;
		}
		if(destHgStation.place != null && destHgStation.place.IsClosed()) {
			HgLog.Warning("Route Remove (dest place closed)"+this);
			Remove();
			return;
		}
		
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
							Remove();
							HgLog.Warning("Route Remove (Collided rail or air route found)"+this);
							return;
						}
					}
				}
			}
			
			if(!isTmpClosed 
					&& ((!isTransfer && !IsValidDestStationCargo())
						|| (isTransfer && (!destRoute || destRoute.IsClosed())))) {
				if(!isTransfer && destHgStation.place != null) {
					HgLog.Warning("Route Close (dest can not accept)"+this);
					lastDestClosedDate = AIDate.GetCurrentDate();
					local destPlace = destHgStation.place.GetProducing();
					if(destPlace instanceof HgIndustry && !destPlace.IsClosed()) {
						local stock = destPlace.GetStockpiledCargo(cargo) ;
						if(stock > 0) {
							isTmpClosed = true;
							maxVehicles = min(GetNumVehicles(), maxVehicles);
							maxVehicles = min(1, maxVehicles - max(maxVehicles/10, 1));
							//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
						}
					}
				} else {
					if((destRoute == false && isTransfer) || (destRoute != false && destRoute.IsRemoved())) {
						HgLog.Warning("Route Remove (DestRoute["+destRoute+"] removed)"+this);
						Remove();
						return;
					} else {
						HgLog.Warning("Route Close (DestRoute["+destRoute+"] closed)"+this);
					}
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
					|| (isTransfer && destRoute != false && !destRoute.IsClosed())) {
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
		return Route.SearchRoutes( Route.GetRouteWeightingVt(GetVehicleType()), srcPlace, destPlace, destStationGroup, cargo ).len() >= 1;
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
	isNotRemoveStation = null;
	isNotRemoveDepot = null;
	
	constructor(dest, srcPlace, cargo) {
		RouteBuilder.constructor(dest, srcPlace, cargo);
		makeReverseRoute = false;
		isNotRemoveStation = false;
		isNotRemoveDepot = false;
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
	
		local vehicleType = GetVehicleType();
		local dest = destPlace != null ? destPlace : destStationGroup.hgStations[0];

		if(Place.IsNgPathFindPair(srcPlace, dest, vehicleType)) {
			HgLog.Warning("IsNgPathFindPair==true "+this);
			return null;
		}
		if(Place.IsNgPlace(dest, cargo, vehicleType)) {
			HgLog.Warning("dest is ng facility."+this);
			return null;
		}
		if(Place.IsNgPlace(srcPlace, cargo, vehicleType)) {
			HgLog.Warning("src is ng facility."+this);
			return null;
		}

		local testMode = AITestMode();
		
		local isBidirectional = destPlace != null ? destPlace.IsAcceptingAndProducing(cargo) : false;
		local distance = srcPlace.DistanceManhattan(GetDestLocation());
		local production = srcPlace.GetLastMonthProduction(cargo);
		local engineSet = Route.Estimate(vehicleType, cargo, distance, production, isBidirectional);
		if(engineSet==null) {
			HgLog.Warning("No suitable engine. "+this);
			return null;
		}
		BuildStart(engineSet);
		
		local stationFactory = CreateStationFactory();
		if(stationFactory == null) {
			Place.AddNgPathFindPair(srcPlace, dest, vehicleType);
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
			if(destPlace instanceof TownCargo || vehicleType == AIVehicle.VT_WATER) {
				stationFactory.nearestFor = srcPlace.GetLocation();
			}
			destHgStation = stationFactory.CreateBest( destPlace, cargo, srcPlace.GetLocation() );
		} else {
			HgLog.Warning("dest is not set."+this);
			return null;
		}
		local isShareDestStation = false;
		if(destHgStation == null) {
			destHgStation = SearchSharableStation(destPlace == null ? destStationGroup : destPlace, stationFactory.GetStationType(), cargo, true);
			if(destHgStation == null) {
				Place.AddNgPlace(dest, cargo, vehicleType);
				HgLog.Warning("No destStation."+this);
				return null;
			}
			HgLog.Warning("Share dest station:"+destHgStation.GetName()+" "+this);
			isShareDestStation = true;
		}
		local list = HgArray(destHgStation.GetTiles()).GetAIList();
		HogeAI.notBuildableList.AddList(list);
		if(srcPlace instanceof TownCargo || vehicleType == AIVehicle.VT_WATER) {
			stationFactory.nearestFor = destHgStation.platformTile;
		}
		local srcHgStation = stationFactory.CreateBest(srcPlace, cargo, destHgStation.platformTile);
		HogeAI.notBuildableList.RemoveList(list);
		local isShareSrcStation = false;
		if(srcHgStation == null) {
			srcHgStation = SearchSharableStation(srcPlace, stationFactory.GetStationType(), cargo, false);				
			if(srcHgStation == null) {
				Place.AddNgPlace(srcPlace, cargo, vehicleType);
				HgLog.Warning("stationFactory.CreateBest failed."+this);
				return null;
			}
			HgLog.Warning("Share src station:"+srcHgStation.GetName()+" "+this);
			isShareSrcStation = true;
		}

		local execMode = AIExecMode();
		local rollbackFacitilies = [];
		
		if(!isShareDestStation && !destHgStation.BuildExec()) {
			HgLog.Warning("destHgStation.BuildExec failed."+this);
			return null;
		}
		if(!isShareDestStation && !isNotRemoveStation) {
			rollbackFacitilies.push(destHgStation);
		}
		
		if(!isShareSrcStation && !srcHgStation.BuildExec()) {
			HgLog.Warning("srcHgStation.BuildExec failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		if(!isShareSrcStation && !isNotRemoveStation) {
			rollbackFacitilies.push(srcHgStation);
		}
		
		if(srcHgStation.stationGroup == destHgStation.stationGroup) {
			Place.AddNgPathFindPair(srcPlace, dest, vehicleType);
			HgLog.Warning("Same stationGroup."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		
		local pathBuilder = CreatePathBuilder(engineSet.engine, cargo);
		if(!pathBuilder.BuildPath(destHgStation.GetEntrances(), srcHgStation.GetEntrances())) {
			Place.AddNgPathFindPair(srcPlace, dest, vehicleType);
			HgLog.Warning("BuildPath failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile)
		if(pathBuilder.path != null && distance > 40 && distance * 2 < pathBuilder.path.GetTotalDistance()) {
			Place.AddNgPathFindPair(srcPlace, dest, vehicleType);
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
			Place.AddNgPathFindPair(srcPlace, dest, vehicleType);
			HgLog.Warning("BuildDepot failed."+this);
			Rollback(rollbackFacitilies);
			return null;
		}
		if(isNotRemoveDepot) {
			rollbackFacitilies.push(route.depot);
		}

		if(pathBuilder.path != null && distance > 30) {
			route.BuildDestDepot(pathBuilder.path);
			if(isNotRemoveDepot) {
				rollbackFacitilies.push(route.destDepot);
			}
		}
		route.SetPath(pathBuilder.path);
		local vehicle = route.BuildVehicle();
		if(vehicle==null) {
			Place.AddNgPathFindPair(srcPlace, dest, vehicleType);
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
		
		if(CargoUtils.IsPaxOrMail(cargo)) {
			CheckTownTransfer(route, srcHgStation); // TODO: 失敗時(ERR_TOWN_AUTHORITYとか)に一定時間後にリトライする仕組み
			CheckTownTransfer(route, destHgStation);
		}
		
		return route;
	}

	function CheckTownTransfer(route, station) {
		if(station.place != null && station.place instanceof TownCargo) {
			local townBus = TownBus.CheckTown(station.place.town, null, station.place.cargo);
			if(townBus != null) {
				townBus.CreateTransferRoutes(route, station);
			}
		}
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
	
	function SearchSharableStation(placeOrGroup, stationType, cargo, isAccepting) {
		foreach(station in HgStation.SearchStation(placeOrGroup, stationType, cargo, isAccepting)) {
			if(station.CanShareByMultiRoute()) {
				return station;
			}
		}
		return null;
	}
	
	function BuildStart(engineSet) {
		// overrideして使う
	}
}