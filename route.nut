
class Route {
	static allVehicleTypes = [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_WATER, AIVehicle.VT_AIR];

	static function SearchRoutes( bottomRouteWeighting, srcPlace, destPlace, destStationGroup, cargo ) {
		return HgArray(ArrayUtils.And(
			srcPlace.GetProducing().GetRoutesUsingSource(),
			destPlace != null ? destPlace.GetRoutes() : destStationGroup.GetUsingRoutes())).Filter(
				function(route):(cargo, bottomRouteWeighting) {
					return route.HasCargo(cargo) && route.GetRouteWeighting() >= bottomRouteWeighting;
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

	static function Estimate(vehicleType, cargo, distance, production, isBidirectional, infrastractureType=null) {
		if(production == 0) {
			return null;
		}
		local estimateTable = HogeAI.Get().estimateTable;
		local productionIndex = HogeAI.Get().GetEstimateProductionIndex(production);
		local distanceIndex = HogeAI.Get().GetEstimateDistanceIndex(distance);
		local key = vehicleType+"-"+cargo+"-"+distanceIndex+"-"+productionIndex+"-"+(isBidirectional?1:0)+"-"+infrastractureType;
		local estimate;
		if(!estimateTable.rawin(key)) {
			local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
			estimate = routeClass.EstimateEngineSet(
				routeClass, cargo, 
				HogeAI.distanceEstimateSamples[distanceIndex], HogeAI.productionEstimateSamples[productionIndex], 
				isBidirectional, infrastractureType);
			if(estimate == null) {
				estimate = 0; // negative cache
			}
			estimateTable[key] <- estimate;
		} else {
			estimate = estimateTable[key];
		}
		if(estimate == 0) {
			return null;
		} else {
			return estimate;
		}
	}
	
	productionCargoCache = null;
	
	constructor() {
		productionCargoCache = {};
	}
	
	function CanCreateNewRoute() {
		return true;
	}
	
	function IsTooManyVehiclesForNewRoute(self) {
		local remaining = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
		if(remaining > 100) {
			return false;
		}
		return remaining <= self.GetMaxTotalVehicles() * (1 - self.GetThresholdVehicleNumRateForNewRoute());
	}
	
	function IsTooManyVehiclesForSupportRoute(self) {
		local remaining = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
		if(remaining > 50) {
			return false;
		}
		return remaining <= self.GetMaxTotalVehicles() * (1 - self.GetThresholdVehicleNumRateForSupportRoute());
	}
	
	function GetVehicleCount(self) {
		return AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
	}
	
	static function IsRateOfVehiclesMoreThan(self,rate) {
		return rate * self.GetMaxTotalVehicles() < AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
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
				return 1;
		}
		HgLog.Error("bug GetRouteWeighting "+this);
	}
	
	function GetDefaultInfrastractureType() {
		return null;
	}
	
	function GetSuitableInfrastractureType(srcPlace, destPlace, cargo) {
		return null;
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
		if(place == null) {
			return false;
		}
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
		return GetProductionCargo(cargo);
	}
	
	function GetProductionCargo(cargo, callers = null) {
		if(productionCargoCache.rawin(cargo)) {
			if(productionCargoCache[cargo].date + 30 > AIDate.GetCurrentDate()) {
				return productionCargoCache[cargo].production;
			}
		} else {
			productionCargoCache[cargo] <- null;
		}
	
		if(callers == null) {
			callers = {};
		}
		local result = 0;
		callers.rawset(this,0);
		if(srcHgStation.place != null && srcHgStation.place instanceof TownCargo) {
			result = srcHgStation.stationGroup.GetAccepters(cargo); //TODO: キャッシュした方がいいかも
			//HgLog.Info("GetAccepters:"+result+"("+srcHgStation.GetName() + ")["+AICargo.GetName(cargo)+"] "+this);
		} else {
			result = srcHgStation.place != null ? srcHgStation.place.GetLastMonthProduction(cargo) : 0;
			foreach(place in srcHgStation.stationGroup.GetProducingHgIndustries(cargo)) {
				if(srcHgStation.place == null || !srcHgStation.place.IsSamePlace(place)) {
					result += place.GetLastMonthProduction(cargo);
				}
			}
		}
		foreach(route in srcHgStation.GetUsingRoutesAsDest()) {
			//HgLog.Info("GetUsingRoutesAsDest:"+route+" "+this+" "+callers.rawin(route)+" "+route.HasCargo(cargo));
			if(route != this && !callers.rawin(route) && route.IsTransfer() && route.HasCargo(cargo)) {
				result += route.GetDelivableProduction(cargo, callers);
			}
		}
		//HgLog.Info("GetProductionCargo:"+result+"("+srcHgStation.GetName() + ")["+AICargo.GetName(cargo)+"] "+this);
		productionCargoCache[cargo] = {
			production = result
			date = AIDate.GetCurrentDate()
		}
		return result;
	}
	
	function GetDelivableProduction(cargo, callers = {}) {
		local result = GetProductionCargo(cargo, callers);
		if(GetVehicleType() == AIVehicle.VT_ROAD) {
			result = min(result, GetCargoCapacity(cargo) * (CargoUtils.IsPaxOrMail(cargo) ? 5 : 20));
		}
		return result;
	}

	function OnIndustoryClose(industry) {
		local srcPlace = srcHgStation.place;
		if(srcPlace != null && srcPlace instanceof HgIndustry && srcPlace.industry == industry) {
			if(GetVehicleType() == AIVehicle.VT_RAIL && HogeAI.Get().IsInfrastructureMaintenance() == false) {
				HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. Search transfer." + this);
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
	
	function GetFinalDestPlace() {
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(!destRoute) {
				return null;
			}
			return destRoute.GetFinalDestPlace();
		} else {
			return destHgStation.place;
		}
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

	// return: false or route instance
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
	
	function CalculateSubCargos() {
		HgLog.Info("CalculateSubCargos:"+this);
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(!destRoute) {
				return [];
			}
			local result = [];
			foreach(subCargo,_ in AICargoList()) {
				if(cargo != subCargo 
						&& srcHgStation.IsProducingCargo(subCargo)
						&& destRoute.HasCargo(subCargo) ) {
					result.push(subCargo);
				}
			}
			return result;
		}
		if(IsBiDirectional()) {
			local result = [];
			foreach(subCargo,_ in AICargoList()) {
				if(cargo != subCargo 
						&& srcHgStation.IsProducingCargo(subCargo) && srcHgStation.IsAcceptingCargo(subCargo)
						&& destHgStation.IsProducingCargo(subCargo) && destHgStation.IsAcceptingCargo(subCargo) ) {
					result.push(subCargo);
				}
			}
			return result;
		} else {
			local result = [];
			foreach(subCargo,_ in AICargoList()) {
				/*if(subCargo == HogeAI.GetPassengerCargo()) {
					continue;
				}*/
				if(cargo != subCargo /*&& srcHgStation.IsProducingCargo(subCargo)*/ && destHgStation.IsAcceptingCargo(subCargo)) {
					if(HogeAI.Get().IsManyTypesOfFreightAsPossible() || (destHgStation.place == null || destHgStation.place.IsCargoAccepted(subCargo))) {
						result.push(subCargo);
						HgLog.Info("subCargo:"+AICargo.GetName(subCargo)+" "+this);
					}
				}
			}
			return result;
		}
	}
	
	function HasCargo(cargo_) {
		foreach(c in GetCargos()) {
			if(c == cargo_) {
				return true;
			}
		}
		return false;
	}
	
	function GetCargos() {
		return [cargo];
	}
	
	function NotifyAddTransfer() {
		productionCargoCache.clear();
	}
	
	function NeedsAdditionalProducing(callRoutes = null, isDest = false) {
		return NeedsAdditionalProducingCargo(cargo, callRoutes, isDest );
	}
	
	function GetLastYearProfit() {
		local result = 0;
		foreach(vehicle in GetVehicles()) {
			result += AIVehicle.GetProfitLastYear(vehicle);
		}
		return result;
	}
	
	function HasTownTransferRoute(isDest, cargo) {
		local station = isDest ? destHgStation : srcHgStation;
		foreach(route in station.stationGroup.GetUsingRoutes()) {
			if(route.srcHgStation.IsTownStop() && route.HasCargo(cargo)) {
				return true;
			}
		}
		return false;
	}
	
	function IsTownTransferRoute() {
		return IsTransfer() && srcHgStation.IsTownStop();
	}
	
	function _tostring() {
		return (IsTransfer() ? "T:" : "") + destHgStation.GetName() + "<-"+(IsBiDirectional()?">":"") + srcHgStation.GetName() + "[" + AICargo.GetName(cargo) + "]" + GetLabel()+(IsClosed()?" Closed":"");
	}
}

class CommonRoute extends Route {

	
	function EstimateEngineSet(self, cargo, distance, production, isBidirectional, infrastractureType=null, isTownBus=false) {
		local engineSets = self.GetEngineSetsVt(self, self.GetVehicleType(), cargo, distance, production, isBidirectional, infrastractureType, isTownBus);
		if(engineSets.len() >= 1) {
			return engineSets[0];
		} else {
			return null;
		}
	}
	
	function GetEngineSetsVt(self, vehicleType, cargo, distance, production, isBidirectional, infrastractureType/*今のところVT_AIRでしか使わない*/, isTownBus=false ) {
		if(distance == 0) {
			return [];
		}
		//HgLog.Info("typeof:self="+(typeof self)+" "+self);
		
		local useReliability = HogeAI.Get().IsEnableVehicleBreakdowns();
		local engineList = AIEngineList(vehicleType);
		engineList.Valuate(AIEngine.CanRefitCargo, cargo);
		engineList.KeepValue(1);
		
		if(isTownBus || (vehicleType == AIVehicle.VT_ROAD && HogeAI.Get().IsDisableTrams())) {
			//local roadType = AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin();
			engineList.Valuate(AIEngine.HasPowerOnRoad, TownBus.GetRoadType()  );
			engineList.KeepValue(1);
		} else if((typeof self) == "instance" && self instanceof RoadRoute) {
			engineList.Valuate(AIEngine.HasPowerOnRoad, self.GetRoadType());
			engineList.KeepValue(1);
		}
		/*
		if((typeof self) == "instance" && self instanceof AirRoute) {
			local usableBigPlane = Air.GetAiportTraits(self.srcHgStation.airportType).supportBigPlane 
				&& Air.GetAiportTraits(self.destHgStation.airportType).supportBigPlane;
			if(!usableBigPlane) {
				engineList.Valuate( AIEngine.GetPlaneType );
				engineList.RemoveValue(AIAirport.PT_BIG_PLANE );
			}
		}*/
		if(vehicleType == AIVehicle.VT_AIR) {
			local usableBigPlane;
			if((typeof self) == "instance" && self instanceof AirRoute) {
				usableBigPlane = Air.GetAiportTraits(self.srcHgStation.airportType).supportBigPlane 
								&& Air.GetAiportTraits(self.destHgStation.airportType).supportBigPlane;			
			} else {
				if(infrastractureType == null) {
					return [];
				}
				usableBigPlane = Air.GetAiportTraits(infrastractureType).supportBigPlane;
			}
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
		local ignoreIncome = false;
		if((typeof self) == "instance" && self instanceof Route) {
			ignoreIncome = self.IsTransfer(); // 短路線がマイナス収支で成立しなくなる。 TODO: 転送先とトータルで収益計算しないといけない。
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
		
		local isTooManyVehicles = Route.IsRateOfVehiclesMoreThan(self,0.65);
		
		local result = [];
		foreach(e,_ in engineList) {
			local capacity = self.GetEngineCapacity(self,e,cargo);
			if(capacity == 0) {
				continue;
			}
			foreach(engineInfrastractureType in self.GetInfrastractureTypes(e)) {
				local runningCost = AIEngine.GetRunningCost(e);
				local cruiseSpeed;
				if(vehicleType == AIVehicle.VT_AIR) {
					cruiseSpeed = AIEngine.GetMaxSpeed(e);
				} else {
					cruiseSpeed = max( 4, AIEngine.GetMaxSpeed(e) * (100 + (useReliability ? AIEngine.GetReliability(e) : 100)) / 200);
				}
				local infraSpeed = self.GetInfrastractureSpeed(engineInfrastractureType);
				if(infraSpeed >= 1) {
					cruiseSpeed = min(infraSpeed, cruiseSpeed);
				}
				local maxVehicles = self.EstimateMaxVehicles(self, pathDistance, cruiseSpeed);
				if(self.IsSupportModeVt(vehicleType) && self.GetMaxTotalVehicles() / 2 < AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType)) {
					maxVehicles = min(maxVehicles, 10); // ROADはなるべく少ない車両数で済ませられる見積をするため
				}
				// This is the amount of cargo transferred per unit of time if using gradualloading. The default is 5 for trains and road vehicles, 10 for ships and 20 for aircraft. 
				// This amount of cargo is loaded to or unloaded from the vehicle every 40 ticks for trains, every 20 ticks for road vehicles and aircraft and every 10 ticks for ships.
				// this property is used for passengers, while mail uses 1/4 (rounded up). You can use callback 12 to control load amounts for passengers and mail independently.
				
				// train:5/40*74 road:10/20*74 air:20/20*74 water:20/10*74
				
				local loadingSpeed; // TODO: capacity/cargo/vehicleTypeによって異なる
				switch(vehicleType) {
					case AIVehicle.VT_ROAD:
						loadingSpeed = 18; //実測だとこれくらい。 37;
						break;
					case AIVehicle.VT_AIR:
						loadingSpeed = 74;
						break;
					case AIVehicle.VT_WATER:
						loadingSpeed = 148;
						break;
				}
				
				/* economy.cpp:1297
				bool air_mail = v->type == VEH_AIRCRAFT && !Aircraft::From(v)->IsNormalAircraft();
				if (air_mail) load_amount = CeilDiv(load_amount, 4);
				*/
		
				if(cargo == HogeAI.GetMailCargo() && vehicleType == AIVehicle.VT_AIR) {
					loadingSpeed /= 2; //実測では半分程度。機体毎に違うのかもしれない。
				}
				local loadingTime = max(1, capacity / loadingSpeed);
				
				/*if(vehicleType == AIVehicle.VT_ROAD) {
					loadingTime = CargoUtils.IsPaxOrMail(cargo) ? capacity / 6 : capacity / 10;
				} else {
					loadingTime = min(10, capacity / 10);
				}*/
				

				local days;
				if(vehicleType == AIVehicle.VT_AIR && cruiseSpeed > 80 && useReliability) {
					local avgBrokenDistance = min(100 * pathDistance / ( (AIEngine.GetReliability(e) * 150 / 100) * cruiseSpeed * 24 / 664), 100) * pathDistance / (100 * 2);
					days = (((pathDistance - avgBrokenDistance) * 664 / cruiseSpeed / 24 + avgBrokenDistance * 664 / 80 / 24) + loadingTime) * 2;
					//local days2 = (pathDistance * 664 / cruiseSpeed / 24 + loadingTime) * 2;
					//HgLog.Info("debug: avgBrokenDistance:" + avgBrokenDistance + " d:"+pathDistance+" v:"+cruiseSpeed+" r:"+AIEngine.GetReliability(e)+" "+AIEngine.GetName(e));
				} else {
					days = (pathDistance * 664 / cruiseSpeed / 24 + loadingTime) * 2;
				}
				days = max(days,1);
				
				local isBuildingEstimate = !isTownBus && !((typeof self) == "instance" && self instanceof Route)/*建設前の見積*/
				local maxBuildingCost = isBuildingEstimate ? HogeAI.Get().GetUsableMoney() + HogeAI.Get().GetQuarterlyIncome(4) * 2 : 0;
				local buildingCost = isBuildingEstimate ? self.GetBuildingCost(engineInfrastractureType, distance, cargo) : 0;
				local deliverableProduction = min(production , self.GetMaxRouteCapacity( engineInfrastractureType, capacity ) );
				local vehiclesPerRoute = max( min( maxVehicles, deliverableProduction * 12 * days / ( 365 * capacity ) ), 1 ); // TODO 往復に1年以上かかる場合計算が狂う
				local price = AIEngine.GetPrice(e);
				if(maxBuildingCost > 0) {
					if(buildingCost + price > maxBuildingCost) {
						//HgLog.Info("buildingCost + price > maxBuildingCost "+self);
						continue;
					}
				}
				local inputProduction = production;
				/*
				if(vehiclesPerRoute < (isBidirectional ? 3 : 2)) {
					inputProduction = inputProduction / 2;
				}*/
				
				
				local waitingInStationTime = max(loadingTime, (capacity * vehiclesPerRoute - (inputProduction * days) / 30)*30 / inputProduction / vehiclesPerRoute );
				
				local incomePerOneTime = AICargo.GetCargoIncome(cargo,distance,days) * capacity;
				local income = incomePerOneTime * 365 * (isBidirectional ? 2 : 1) / (days + waitingInStationTime + loadingTime) - runningCost;;
				//local income = CargoUtils.GetCargoIncome( distance, cargo, cruiseSpeed, waitingInStationTime, isBidirectional ) * capacity - runningCost;
				if(!ignoreIncome && income <= 0) {
					/*
					if(vehicleType == AIVehicle.VT_ROAD) {
						HgLog.Info("income:"+income+" bi:"+isBidirectional+" vehicles:"+vehiclesPerRoute+" building:"+buildingCost+" waiting:"+waitingInStationTime
							+" speed:"+cruiseSpeed+" capacity:"+capacity+" days:"+days+" distance:"+distance+" production:"+production+"["+AICargo.GetName(cargo)+"] "+AIEngine.GetName(e)+" "+AIRoad.GetName(engineInfrastractureType));
					}*/
					continue;
				}
				local infraCost = self.GetInfrastractureCost(engineInfrastractureType, distance);
				local routeIncome = income * vehiclesPerRoute - infraCost;
				local roi = routeIncome * 1000 / (price * vehiclesPerRoute + buildingCost);
				local incomePerVehicle = routeIncome / vehiclesPerRoute;
				local incomePerBuildingTime = routeIncome * 100 / self.GetBuildingTime(pathDistance);
				local value = HogeAI.Get().GetValue(roi,incomePerBuildingTime,incomePerVehicle);
				/*
				if(isTooManyVehicles) {
					value = routeIncome / (vehiclesPerRoute + (CargoUtils.IsPaxOrMail(cargo) ? 4 : 0));
				} else {
					value = HogeAI.Get().GetValue(roi,incomePerBuildingTime,incomePerVehicle);
				}*/
				
				/*
				if(vehicleType == AIVehicle.VT_AIR) {
					HgLog.Info("vt:"+vehicleType+" income:"+routeIncome+"("+incomePerVehicle+") bi:"+isBidirectional+" vehicles:"+vehiclesPerRoute+" infraCost:"+infraCost+" waiting:"+waitingInStationTime
						+" speed:"+cruiseSpeed+" capacity:"+capacity+" days:"+days+" distance:"+distance+" production:"+production+"["+AICargo.GetName(cargo)+"] "+AIEngine.GetName(e));
				}*/
				
				/*
				if(vehicleType == AIVehicle.VT_ROAD) {
					HgLog.Info("rincome:"+routeIncome+"("+income+") roi"+roi+" bi:"+isBidirectional+" vehicles:"+vehiclesPerRoute+" building:"+buildingCost+" waiting:"+waitingInStationTime
						+" speed:"+cruiseSpeed+" capacity:"+capacity+" days:"+days+" distance:"+distance+" production:"+production+"["+AICargo.GetName(cargo)+"] "+AIEngine.GetName(e)+" "+AIRoad.GetName(engineInfrastractureType));
				}*/
				
				result.push( {
					engine = e
					infrastractureType = engineInfrastractureType
					price = price
					runningCost = runningCost
					income = income
					incomePerOneTime = incomePerOneTime
					routeIncome = routeIncome
					roi = roi
					value = value
					capacity = capacity
					vehiclesPerRoute = vehiclesPerRoute
					buildingCost = buildingCost
				} );
			}
		}
		result.sort(function(a,b) {
			return b.value - a.value;
		});
		return result;
	}
	
	function GetEngineCapacity(self, engine, cargo) {
		local result;
		if(self.instances.len() >= 1) {
			foreach(route in self.instances) {
				result = AIVehicle.GetBuildWithRefitCapacity(route.depot, engine, cargo);
				if(result != -1 && result != 1) { // eGVRTSではなぜか誤った値1が返る
					/*if( self.GetVehicleType() == AIVehicle.VT_ROAD) {
						HgLog.Info("capacity:"+result+" engine:"+AIEngine.GetName(engine)+" cargo:"+AICargo.GetName(cargo)+" depot:"+HgTile(route.depot)
							+" GetCapacity:"+ AIEngine.GetCapacity(engine)+" CanPullCargo:"+AIEngine.CanPullCargo(engine,cargo));
					}*/
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
	
	function CheckReduce(self, routeInstances, maxVehicles) {
		if(HogeAI.Get().IsInfrastructureMaintenance()) {
			return; //TODO: Removeでの物理削除が出来たら。メンテナンスコストも加味した利益計算
		}
		if(self.IsTooManyVehiclesForNewRoute(self) && AIDate.GetMonth(AIDate.GetCurrentDate())>=10) {
//		if(self.GetVehicleCount(self) > 0.9 * self.GetMaxTotalVehicles() && AIDate.GetMonth(AIDate.GetCurrentDate())>=10) {
			local minProfit = null;
			local minRoute = null;
			foreach(route in routeInstances) {
				if(route.IsClosed() || route.IsTransfer()) {
					continue;
				}
				local vehicleList = AIVehicleList_Group(route.vehicleGroup);
				vehicleList.Valuate(AIVehicle.GetAge);
				vehicleList.KeepAboveValue(800);
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
	
	function GetInfrastractureTypes(engine) {
		return [null];
	}
	
	function GetInfrastractureCost(infrastractureType, distance) {
		return 0;
	}
	
	function GetInfrastractureSpeed(infrastractureType) {
		return 0;
	}
	
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
	stopppedVehicles = null;
	lastCheckProductionIndex = null;
	
	constructor() {
		Route.constructor();
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
	
	function GetInfrastractureType() {
		return null;
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
	
	function GetCargoCapacity(cargo) {
		local latestVehicle = GetLatestVehicle();
		return latestVehicle != null ? AIVehicle.GetCapacity(latestVehicle,cargo) : 0;
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
		local loadOrderFlags =  nonstopIntermediate | (!AITile.IsStationTile (srcHgStation.platformTile) ? 0 : (IsSrcFullLoadOrder() ? AIOrder.OF_FULL_LOAD_ANY : 0));
		if(isBiDirectional) {
			if(!AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, loadOrderFlags)) {
				HgLog.Warning("AppendOrder failed. destination: "+HgTile(srcHgStation.platformTile)+" "+AIError.GetLastErrorString()+" "+this);
			}
		} else {
			if(!AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, loadOrderFlags)) {
				HgLog.Warning("AppendOrder failed. destination: "+HgTile(srcHgStation.platformTile)+" "+AIError.GetLastErrorString()+" "+this);
			}
		}
		if(useDepotOrder && HogeAI.Get().IsEnableVehicleBreakdowns()) {
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
		if(destDepot != null && HogeAI.Get().IsEnableVehicleBreakdowns()) {
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
	
	function IsSrcFullLoadOrder() {
		return true;
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
		local depot = this.depot;
		local destDepot = false;
		if(this instanceof AirRoute && IsBiDirectional()) {
			destDepot = GetNumVehicles() % 2 == 1;
			if(destDepot) {
				depot = AIAirport.GetHangarOfAirport(destHgStation.platformTile);
			}
		}
		
		local result = null;
		HogeAI.WaitForPrice(AIEngine.GetPrice(AIVehicle.GetEngineType(vehicle)));
		result = AIVehicle.CloneVehicle(depot, vehicle, true);
		if(!AIVehicle.IsValidVehicle(result)) {
			HgLog.Warning("CloneVehicle failed. "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIGroup.MoveVehicle(vehicleGroup, result);
		if(destDepot) {
			AIOrder.SkipToOrder(result, 1);
		}
		AIVehicle.StartStopVehicle(result);
		return result;
	}

	function ChooseEngine() {
		local engineExpire = GetVehicleType() == AIVehicle.VT_ROAD ? 1000 : 365;
	
		if(chosenEngine == null || lastChooseEngineDate + engineExpire < AIDate.GetCurrentDate()) {
			local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
			local production = GetProduction();
			local engineSet = EstimateEngineSet( this, cargo, distance,  production, IsBiDirectional() );
			lastCheckProductionIndex = HogeAI.Get().GetEstimateProductionIndex(production);
			chosenEngine = engineSet != null ? engineSet.engine : null;
			if(chosenEngine == null) {
				HgLog.Warning("Not found suitable engine. production:"+production+" "+this);
			} else {
				HgLog.Info("ChooseEngine:"+AIEngine.GetName(chosenEngine)+" production:"+production+" "+this);
			}
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
	
	function GetVehicles() {
		return HgArray.AIListKey(GetVehicleList()).array;
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
		return min( days * 2 / self.GetStationDateSpan(self) + 1, (distance + 4) * 16 / vehicleLength / 2 ) + 2;
	}

	function GetMaxVehicles() {
		local vehicle = GetLatestVehicle();
		if(vehicle == null) {
			return 1;
		}
		local length = AIVehicle.GetLength(vehicle);
		local engine = AIVehicle.GetEngineType(vehicle);
		local cruiseSpeed = max( 4, AIEngine.GetMaxSpeed(engine) * ( 100 + AIEngine.GetReliability(engine)) / 200);
		local infraSpeed = GetInfrastractureSpeed(GetInfrastractureType());
		if(infraSpeed >= 1) {
			cruiseSpeed = min(infraSpeed, cruiseSpeed);
		}
		return EstimateMaxVehicles(this, GetDistance(), cruiseSpeed, length);
	}
	
	function GetStationDateSpan(self) {
		switch(self.GetVehicleType()) {
			case AIVehicle.VT_RAIL:
				return 5;
			case AIVehicle.VT_ROAD:
				return 1;
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
			maxVehicles = max(!GetDestRoute() || (IsDestOverflow() && NeedsAdditionalProducing()) ? 0 : 5, maxVehicles);
		}
		maxVehicles = min(maxVehicles, GetMaxVehicles());
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		if(maxVehicles == 0 && !IsTransfer()) {
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
				//HgLog.Info("ReduceVehicle maxVehicles:"+maxVehicles+" vehicleList.Count:"+vehicleList.Count()+" "+this);
				AIVehicle.SendVehicleToDepot (vehicle);
				reduce --;
			}
		}
	}

	function CheckBuildVehicle() {
		local c = PerformanceCounter.Start("CheckBuildVehicle");	
		_CheckBuildVehicle();
		c.Stop();
	}
	
	function SellVehiclesStoppedInDepots() {
		foreach(vehicle,_ in GetVehicleList()) {
			if(AIVehicle.IsStoppedInDepot(vehicle)) {
				AIVehicle.SellVehicle(vehicle);
			}
		}
	}
	
	function CheckNotProfitableOrStopVehicle() {
		local isBiDirectional = IsBiDirectional();
		local vehicleType = GetVehicleType();
		local vehicleList = GetVehicleList();
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
			//HgLog.Warning("check SendVehicleToDepot "+this+" vehicleList:"+vehicleList.Count());
		local checkStop = vehicleType == AIVehicle.VT_ROAD && (HogeAI.Get().roiBase || totalVehicles >= GetMaxTotalVehicles() * 0.85);
		local checkProfitable = AIDate.GetMonth(AIDate.GetCurrentDate()) >= 10 && !isTransfer;
		if(checkStop || checkProfitable) { // transferはトータルで利益を上げていれば問題ない。 TODO:トータルで利益を上げているかのチェック
			local newStopped = {};
			foreach(vehicle,v in vehicleList) {
				if((!isBiDirectional && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1) ) {
					continue;
				}
				local age = AIVehicle.GetAge(vehicle);
				local notProfitable = checkProfitable && age > 800 ? AIVehicle.GetProfitLastYear(vehicle) < 0 && AIVehicle.GetProfitThisYear(vehicle) < 0 : false;
				local stopped = false;
				if(checkStop && age > 30/*出来立て路線がいきなり0になるのを防ぐ*/ && !notProfitable && AIVehicle.GetCurrentSpeed(vehicle) == 0 && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED && !AIVehicle.IsStoppedInDepot(vehicle)) {
					local location = AIVehicle.GetLocation(vehicle);
					if(srcHgStation.platformTile != location && destHgStation.platformTile != location) {
						if(stopppedVehicles != null && stopppedVehicles.rawin(vehicle)) {
							stopped = true;
						} else {
							newStopped.rawset(vehicle,0);
						}
					}
				}
				
				if((stopped || notProfitable) && (AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					//HgLog.Warning("SendVehicleToDepot notProfitable:"+notProfitable+" ageLeft:"+AIVehicle.GetAgeLeft(vehicle)+" "+AIVehicle.GetName(vehicle)+" "+this);
					AIVehicle.SendVehicleToDepot (vehicle);
					if((stopped || notProfitable) && vehicleType == AIVehicle.VT_ROAD) { //多すぎて赤字の場合は減らしてもNeedsAdditionalProducing==falseのはず。渋滞がひどくて赤字のケースがあるのでROADだけケア
						maxVehicles = min(vehicleList.Count(), maxVehicles);  // TODO: リセッションで一時的に利益がでていないケースがありうる。継続的に利益が出ていない路線をどうするか
						maxVehicles = max(0, maxVehicles - 1);
						HgLog.Warning("maxVehicles:"+maxVehicles+" notProfitable:"+notProfitable+" stopped:"+stopped+" "+this);
					}
					//HgLog.Info("SendVehicleToDepot(road) "+AIVehicle.GetName(vehicle)+" "+this);
					break;
				}
			}
			stopppedVehicles = newStopped;
		}
	}
	
	function _CheckBuildVehicle() {
	
		local showLog = false; //srcHgStation.GetName().find("0108") != null;
		if(showLog) {
			HgLog.Info("_CheckBuildVehicle "+this);
		}
		
	
		local execMode = AIExecMode();
		local all = GetVehicleList();
		local inDepot = AIList();
		local vehicleList = AIList();
		
		local sellCounter = 0;
		foreach(vehicle,_ in all) {
			if(AIVehicle.IsStoppedInDepot(vehicle)) {
				if(isRemoved) {
					AIVehicle.SellVehicle(vehicle);
				} else {
					inDepot.AddItem(vehicle,0);
				}
			} else {
				vehicleList.AddItem(vehicle,0);
			}
		}
		
		if(isRemoved && vehicleList.Count() == 0) {
			HgLog.Warning("All vehicles removed."+this);
			ArrayUtils.Remove(getclass().instances, this);
			//HgLog.Info("SellVehicle:"+sellCounter+" "+this);		}
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

		CheckNotProfitableOrStopVehicle();

		local needsAddtinalProducing = NeedsAdditionalProducing();
		local isDestOverflow = IsDestOverflow();
		local usingRoutes = srcHgStation.stationGroup.GetUsingRoutesAsSource();
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
		if(isTransfer && (usingRoutes.len() >= 2 || HogeAI.Get().IsPoor() || totalVehicles >= GetMaxTotalVehicles() * 0.85)) { // 資源を取り合っているケース。不必要なvehicleはなるべく減らし必要な方へ流す
			if( vehicleList.Count() >= 2 && (isDestOverflow || maxVehicles > GetMaxVehicles() || (!needsAddtinalProducing && AIBase.RandRange(100) < 25))) {
				foreach(vehicle,v in vehicleList) {
					if(!isBiDirectional && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1 ) {
						continue;
					}
					if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
						//HgLog.Info("SendVehicleToDepot vehicles:"+vehicleList.Count()+"/"+maxVehicles+" isDestOverflow:"+isDestOverflow+" "+this);
						/*overlowしてれば追加で作られないはず
						maxVehicles = min(vehicleList.Count(), maxVehicles);  // TODO: リセッションで一時的に利益がでていないケースがありうる。継続的に利益が出ていない路線をどうするか
						maxVehicles = max(1, maxVehicles - 1);
						HgLog.Warning("maxVehicles:"+maxVehicles+" isDestOverflow "+this);*/
						AIVehicle.SendVehicleToDepot (vehicle);
						break;
					}
				}
			}
		}
		if(IsTooManyVehiclesForNewRoute(this)) {
			foreach(v,_ in inDepot) {
				AIVehicle.SellVehicle(v);
			}
			inDepot.Clear();
			local isReduce = false;
			if(!GetDestRoute()) {
				if(IsSupportMode()) {
					isReduce = totalVehicles > GetMaxTotalVehicles() * 0.8 && GetMaxTotalVehicles() - totalVehicles < 30;
				} else {
					isReduce = totalVehicles > GetMaxTotalVehicles() * 0.95 && GetMaxTotalVehicles() - totalVehicles < 5;
				}
			} else if(IsTransfer()){
				isReduce = totalVehicles > GetMaxTotalVehicles() * 0.85 && GetMaxTotalVehicles() - totalVehicles < 20;
			} else { //supportRoute
				isReduce = totalVehicles > GetMaxTotalVehicles() * 0.9 && GetMaxTotalVehicles() - totalVehicles < 10;
			}
			if(isReduce) {
				ReduceVehicle();
			}
		} else if(AIBase.RandRange(100) < 25) {
			if((isTransfer && needsAddtinalProducing) || (!isTransfer && IsOverflow())) {
				maxVehicles ++;
				maxVehicles = min(GetMaxVehicles(), maxVehicles);
				//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
			}
		}
		
		if(isDestOverflow) {
			if(showLog) {
				HgLog.Info("isDestOverflow "+this);
			}
			return;
		}

		
		local latestVehicle = GetLatestVehicle();
		local capacity = 10;
		if(latestVehicle != null) {
			capacity = AIVehicle.GetCapacity(latestVehicle, cargo);
		}
		local bottomWaiting = max(min(200, HogeAI.Get().roiBase ? capacity * 6 : capacity), 10);
		/*
		if(HogeAI.Get().roiBase && IsBiDirectional() && AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo) < bottomWaiting && vehicleList.Count()>=4) {
			return;
		}*/
		
		local needsProduction = vehicleList.Count() < 10 ? 10 : 100; //= min(4,maxVehicles / 2 + 1) ? capacity : bottomWaiting;
		if(showLog) {
			HgLog.Info("needsProduction "+needsProduction+" "+this);
		}
		if(AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo) > needsProduction || vehicleList.Count()==0) {
			local vehicles = vehicleList;
			if(showLog) {
				HgLog.Info("maxVehicles "+maxVehicles+" "+this);
			}
			if(vehicles.Count() < maxVehicles) {
				vehicles.Valuate(AIVehicle.GetState);
				vehicles.KeepValue(AIVehicle.VS_AT_STATION);
				if(showLog) {
					HgLog.Info("vehicles.KeepValue(AIVehicle.VS_AT_STATION) "+vehicles.Count()+" "+this);
				}
				if(vehicles.Count() == 0) {
					local firstBuild = 0;
					local choosenEngine = ChooseEngine();
					
					if(latestVehicle == null || choosenEngine != AIVehicle.GetEngineType(latestVehicle)) {
						//HgLog.Info("BuildVehicle "+this);
						if(showLog) {
							HgLog.Info("BuildVehicle "+this);
						}
						local c9 = PerformanceCounter.Start("BuildVehicle");	
						latestVehicle = BuildVehicle();
						c9.Stop();
						if(latestVehicle != null) {
							local c8 = PerformanceCounter.Start("CloneVehicle");	
							CloneVehicle(latestVehicle);
							c8.Stop();
							firstBuild = 2;
						}
					}
					if(latestVehicle != null) {
						local capacity = AIVehicle.GetCapacity(latestVehicle, cargo);
						local cargoWaiting = max(0, AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo)/* - bottomWaiting*/);
						if(showLog) {
							HgLog.Info("cargoWaiting:"+cargoWaiting+" capacity:"+capacity+" "+this);
						}
						local buildNum;
						if(IsBiDirectional()) {
							local destWaiting = max(0, AIStation.GetCargoWaiting(destHgStation.GetAIStation(),cargo)/* - bottomWaiting*/);
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
						//if(HogeAI().Get().roiBase) {
						//	buildNum = min(buildNum, max(1, (maxVehicles - vehicles.Count())/8));
						//}
						//buildNum = min(buildNum, 8);
						if(isTransfer) {
							buildNum = min(1,buildNum);
						}
						if(showLog) {
							HgLog.Info("buildNum "+buildNum+" "+this);
						}
						
						//HgLog.Info("CloneVehicle "+buildNum+" "+this);
						if(buildNum >= 1) {
							foreach(v,_ in inDepot) {
								if(choosenEngine == AIVehicle.GetEngineType(v) && AIVehicle.GetAgeLeft(v) >= 1000) {
									AIVehicle.StartStopVehicle(v);
									buildNum --;
									if(buildNum == 0) {
										break;
									}
								} else {
									AIVehicle.SellVehicle(v);
								}
							}
							if(buildNum >= 1) {
								foreach(v,_ in AIVehicleList_Depot(depot)) {
									if(AIVehicle.IsStoppedInDepot(v) && choosenEngine == AIVehicle.GetEngineType(v) && AIVehicle.GetAgeLeft(v) >= 1000) {
										AIOrder.ShareOrders(v, latestVehicle);
										AIGroup.MoveVehicle(vehicleGroup, v);
										AIVehicle.StartStopVehicle(v);
										buildNum --;
										if(buildNum == 0) {
											break;
										}
									}
								}
							}

							//HgLog.Info("CloneRoadVehicle:"+buildNum+" "+this);
							local startDate = AIDate.GetCurrentDate();
							for(local i=0; i<buildNum && AIDate.GetCurrentDate() < startDate + 30; i++) {
								local c8 = PerformanceCounter.Start("CloneVehicle");	
								if(CloneVehicle(latestVehicle) == null) {
									c8.Stop();
									break;
								}
								c8.Stop();
							}
						}
					}
				}
			}
		} 

	}
	

	function NeedsAdditionalProducingCargo(cargo, callRoutes = null, isDest = false) {
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
		if(!destRoute || GetNumVehicles() >= maxVehicles) {
			local latestVehicle = GetLatestVehicle();
			return latestVehicle != null && AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) < AIVehicle.GetCapacity(latestVehicle, cargo) / 2;
		}
		if(HogeAI.Get().stockpiled && !isTransfer && destRoute.destHgStation.place != null 
				&& destHgStation.place.IsSamePlace(destRoute.destHgStation.place)) {
			return true;
		}
		local result = destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, IsDestDest());
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
		local capacity = GetCargoCapacity(cargo);
		local bottom = max(300, min(capacity * 5, 4096));
		local station = isDest ? destHgStation : srcHgStation;
		return AIStation.GetCargoWaiting (station.GetAIStation(), cargo) > bottom; // || AIStation.GetCargoRating(destHgStation.GetAIStation(), cargo) < 30;
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
		local c = PerformanceCounter.Start("CheckRenewal");	
		_CheckRenewal();
		c.Stop();
	}
	
	function _CheckRenewal() {
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
					if(route.IsClosed() || (!route.NeedsAdditionalProducingPlace(srcHgStation.place) && !route.NeedsAdditionalProducingPlace(destHgStation.place))) {
						continue;
					}
					if(IsTransfer() && route.IsSrcStationGroup(destHgStation.stationGroup)) {
						continue;
					}
					if(destRoute!=false && !IsTransfer() && !route.IsSameSrcAndDest(this)) {// industryへのsupply以外が対象(for FIRS)
						continue;
					}
					HgLog.Warning("Route Remove (Collided rail route found)"+this);
					Remove();
					return;
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
		
		if(AIBase.RandRange(100)==0) {
			destRoute = null; //たまにキャッシュをクリアする
			hasRailDest = null;
		}
		
		if(AIBase.RandRange(100)<5 || (lastCheckProductionIndex != null && lastCheckProductionIndex != HogeAI.Get().GetEstimateProductionIndex(GetProduction()))) {
			//HgLog.Warning("Check renewal."+this);
			local newEngine = ChooseEngine();
			local isAll = true;
			foreach(vehicle,v in GetVehicleList()) {
				if((newEngine != null && newEngine != AIVehicle.GetEngineType(vehicle)) || AIVehicle.GetAgeLeft(vehicle) <= 600) {
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
	checkSharableStationFirst = null;
	
	constructor(dest, srcPlace, cargo) {
		RouteBuilder.constructor(dest, srcPlace, cargo);
		makeReverseRoute = false;
		isNotRemoveStation = false;
		isNotRemoveDepot = false;
		checkSharableStationFirst = false;
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
		if(destStationGroup != null && destStationGroup.hgStations.len() == 0) {
			HgLog.Error("destStationGroup.hgStations.len() == 0 "+this);
			return null;
		}
		
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
		if(!PlaceDictionary.Get().CanUseAsSource(srcPlace, cargo)) {
			HgLog.Warning("src is used."+this);
			return null;
		}

		local testMode = AITestMode();
		
		local routeClass = GetRouteClass();
		local isBidirectional = destPlace != null ? destPlace.IsAcceptingAndProducing(cargo) : false;
		local distance = srcPlace.DistanceManhattan(GetDestLocation());
		local production = srcPlace.GetLastMonthProduction(cargo);
		local infrastractureType = routeClass.GetSuitableInfrastractureType(srcPlace, destPlace, cargo);
		local engineSet = Route.Estimate(vehicleType, cargo, distance, production, isBidirectional, infrastractureType);
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
		local isShareDestStation = false;
		if(checkSharableStationFirst) {
			destHgStation = SearchSharableStation(dest, stationFactory.GetStationType(), cargo, true, infrastractureType);
			if(destHgStation != null) {
				isShareDestStation = true;
			}
		}
		if(destHgStation == null) {
			if(destStationGroup != null) {
				isTransfer = true;
				destHgStation = stationFactory.CreateBestOnStationGroup( destStationGroup, cargo, srcPlace.GetLocation() );
			} else if(destPlace != null) {
				isTransfer = false;
				if((destPlace instanceof TownCargo && vehicleType == AIVehicle.VT_ROAD) || vehicleType == AIVehicle.VT_WATER) {
					stationFactory.nearestFor = srcPlace.GetLocation();
				}
				destHgStation = stationFactory.CreateBest( destPlace, cargo, srcPlace.GetLocation() );
			}
		}
		if(destHgStation == null) {
			destHgStation = SearchSharableStation(dest, stationFactory.GetStationType(), cargo, true);
			if(destHgStation != null) {
				isShareDestStation = true;
			}
		}
		if(destHgStation == null) {
			Place.AddNgPlace(dest, cargo, vehicleType);
			HgLog.Warning("No destStation."+this);
			return null;
		}
		local list = HgArray(destHgStation.GetTiles()).GetAIList();
		HogeAI.notBuildableList.AddList(list);
		if((destPlace != null && destPlace instanceof TownCargo && vehicleType == AIVehicle.VT_ROAD) || vehicleType == AIVehicle.VT_WATER) {
			stationFactory.nearestFor = destHgStation.platformTile;
		}
		local srcHgStation = null
		local isShareSrcStation = false;
		if(checkSharableStationFirst) {
			srcHgStation = SearchSharableStation(srcPlace, stationFactory.GetStationType(), cargo, false, infrastractureType);
			if(srcHgStation != null) {
				isShareSrcStation = true;
			}
		}
		if(srcHgStation == null) {
			srcHgStation = stationFactory.CreateBest(srcPlace, cargo, destHgStation.platformTile);
		}
		HogeAI.notBuildableList.RemoveList(list);
		if(srcHgStation == null) {
			srcHgStation = SearchSharableStation(srcPlace, stationFactory.GetStationType(), cargo, false);
			if(srcHgStation != null) {
				isShareSrcStation = true;
			}
		}
		if(srcHgStation == null) {
			Place.AddNgPlace(srcPlace, cargo, vehicleType);
			HgLog.Warning("stationFactory.CreateBest failed."+this);
			return null;
		}

		local execMode = AIExecMode();
		local rollbackFacitilies = [];
		
		if(isShareDestStation) {
			HgLog.Warning("Share dest station:"+srcHgStation.GetName()+" "+this);
			if(!destHgStation.Share()) {
				HgLog.Warning("destHgStation.Share failed."+this);
				return null;
			}
		} else if(!destHgStation.BuildExec()) {
			HgLog.Warning("destHgStation.BuildExec failed."+this);
			return null;
		}
		if(!isShareDestStation && !isNotRemoveStation) {
			rollbackFacitilies.push(destHgStation);
		}
		
		if(isShareSrcStation) {
			HgLog.Warning("Share src station:"+srcHgStation.GetName()+" "+this);
			if(!srcHgStation.Share()) {
				HgLog.Warning("srcHgStation.Share failed."+this);
				return null;
			}
		} else if(!srcHgStation.BuildExec()) {
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
		
		local route = routeClass();
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
		
		/* 時間が経ってから調べた方が良い(必要ないかもしれない)
		if(!route.IsTransfer()) {
			HogeAI.Get().SearchAndBuildToMeetSrcDemandTransfer(route);
		}*/
		
		return route;
	}
	
	function CheckTownTransferCargo(route, station, cargo) {
		if(route.HasCargo(cargo)) {
			local townBus;
			townBus = TownBus.CheckTown(station.place.town, null, cargo, !HogeAI.Get().IsDistantJoinStations());
			if(townBus == null) {
				HgLog.Warning("Cannot get TownBus:"+station.place.GetName()+"["+AICargo.GetName(cargo)+"]");
			} else {
				HogeAI.Get().CreateTownTransferRoutes(townBus, route, station);
			}
		}
	}

	function CheckTownTransfer(route, station) {
		if(station.place != null && station.place instanceof TownCargo) {
			CommonRouteBuilder.CheckTownTransferCargo(route,station,HogeAI.GetPassengerCargo());
			CommonRouteBuilder.CheckTownTransferCargo(route,station,HogeAI.GetMailCargo());
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
	
	function SearchSharableStation(placeOrGroup, stationType, cargo, isAccepting, infrastractureType=null) {
		foreach(station in HgStation.SearchStation(placeOrGroup, stationType, cargo, isAccepting)) {
			if(station.CanShareByMultiRoute(infrastractureType)) {
				return station;
			}
		}
		return null;
	}
	
	function BuildStart(engineSet) {
		// overrideして使う
	}
}

class InfrastructureCost {
	static _instance = GeneratorContainer(function() { 
		return InfrastructureCost(); 
	});

	static function Get() {
		return InfrastructureCost._instance.Get();
	}

	
	railTypeCostCache = null;
	roadTypeCostCache = null;
	
	lastCheckDate = null;
	
	constructor() {
		railTypeCostCache = {};
		roadTypeCostCache = {};
	}
	
	
	function CheckCache() {
		local current = AIDate.GetCurrentDate();
		if(lastCheckDate != null && GetYearMonth(current) > GetYearMonth(lastCheckDate)) {
			railTypeCostCache.clear();
			roadTypeCostCache.clear();
		}
		lastCheckDate = current;
	}

	function GetYearMonth(date) {
		return AIDate.GetYear(date) * 12 + AIDate.GetMonth(date) - 1;
	}
	
	function GetCostPerDistanceRail(railType) {
		if(!HogeAI.Get().IsInfrastructureMaintenance()) {
			return 0;
		}
		CheckCache();
		if(railTypeCostCache.rawin(railType)) {
			return railTypeCostCache[railType];
		}
		local result;
		local distance = 0;
		foreach(route in TrainRoute.GetTrainRoutes(railType)) {
			distance += route.GetDistance();
		}
		if(distance == 0) {
			result = 0;
		} else {
			result = AIInfrastructure.GetMonthlyRailCosts(AICompany.COMPANY_SELF , railType) * 12 * 2 / distance;
		}
		railTypeCostCache[railType] <- result;
		return result;
	}
	
	function GetCostPerDistanceRoad(roadType) {
		if(!HogeAI.Get().IsInfrastructureMaintenance()) {
			return 0;
		}
		CheckCache();
		if(roadTypeCostCache.rawin(roadType)) {
			return roadTypeCostCache[roadType];
		}
		local distance = 0;
		foreach(route in RoadRoute.GetRoadRoutes(roadType)) {
			distance += route.GetDistance();
		}
		local result;
		if(distance == 0) {
			result = AIRoad.GetMaintenanceCostFactor(roadType) * 2; //すぐ増えるので最初から倍に
		} else {
			result = AIInfrastructure.GetMonthlyRoadCosts (AICompany.COMPANY_SELF, roadType) * 12 / distance;
		}
		roadTypeCostCache[roadType] <- result;
		return result;
	}
	
	function GetCostPerAirport() {
		if(!HogeAI.Get().IsInfrastructureMaintenance()) {
			return 0;
		}
		local piece = AIInfrastructure.GetInfrastructurePieceCount(AICompany.COMPANY_SELF, AIInfrastructure.INFRASTRUCTURE_AIRPORT);
		if(piece == 0) {
			return 0;
		}
		return AIInfrastructure.GetMonthlyInfrastructureCosts(AICompany.COMPANY_SELF, AIInfrastructure.INFRASTRUCTURE_AIRPORT) * 12	/ piece;
	}

	
}
