
class Route {
	static allVehicleTypes = [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_WATER, AIVehicle.VT_AIR];

	static checkedNewRoute = ExpirationRawTable(365);
	static availableVehicleTypesCache = ExpirationTable(30);

	static function GetAvailableVehicleTypes() {
		if(Route.availableVehicleTypesCache.rawin(0)) {
			Route.availableVehicleTypesCache.rawget(0);
		}
		local result = [];
		foreach(vehicleType in Route.allVehicleTypes) {
			local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
			if(!routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
				result.push(vehicleType);
			}
		}
		Route.availableVehicleTypesCache.rawset(0,result);
		return result;
	}

	static function SearchRoutes( bottomRouteWeighting, src, dest, cargo ) {
		return HgArray(ArrayUtils.And(
			src.GetUsingRoutes(), dest.GetUsingRoutes())).Filter(
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

	static function EstimateBestVehicleType(cargo, distance, production, isBidirectional) {
		local result = null;
		foreach(vehicleType in Route.allVehicleTypes) {
			local estimate = Route.Estimate(vehicleType, cargo, distance, production, isBidirectional);
			if(estimate != null) {
				if(result == null) {
					result = estimate;
				} else if(result.value < estimate.value) {
					result = estimate;
				}
			}
		}
		return result;
	}

	static function Estimate(vehicleType, cargo, distance, production, isBidirectional, infrastractureTypes=null) {
		if(production == 0) {
			return null;
		}
		local estimateTable = HogeAI.Get().estimateTable;
		local productionIndex = HogeAI.Get().GetEstimateProductionIndex(production);
		local distanceIndex = HogeAI.Get().GetEstimateDistanceIndex(distance);
		local key = vehicleType+"-"+cargo+"-"+distanceIndex+"-"+productionIndex+"-"+(isBidirectional?1:0);
		if(infrastractureTypes != null) {
			foreach(i,infraType in infrastractureTypes) {
				key += (i==0?"-":",")+infraType;
			}
		}
		local estimate;
		if(!estimateTable.rawin(key)) {
			local routeClass = Route.GetRouteClassFromVehicleType(vehicleType);
			local estimator = routeClass.GetEstimator(routeClass);
			estimator.cargo = cargo;
			estimator.distance = HogeAI.distanceEstimateSamples[distanceIndex];
			estimator.production = HogeAI.productionEstimateSamples[productionIndex];
			estimator.isBidirectional = isBidirectional;
			estimator.infrastractureTypes = infrastractureTypes;
			estimate = estimator.Estimate();
			if(estimate == null) {
				estimate = 0; // negative cache
			}
			estimateTable[key] <- estimate;
		} else {
			estimate = estimateTable[key];
			if(estimate != 0 && !AIEngine.IsBuildable(estimate.engine)) {
				// 古い
				estimateTable.rawdelete(key);
				return Route.Estimate(vehicleType, cargo, distance, production, isBidirectional, infrastractureTypes);
			}
			
		}
		if(estimate == 0) {
			return null;
		} else {
			return estimate;
		}
	}
	
	productionCargoCache = null;
	needsAdditionalCache = null;

	isBuilding = null;
	
	constructor() {
		productionCargoCache = ExpirationTable(30);
		needsAdditionalCache = ExpirationTable(30);
		isBuilding = false;
	}
	
	function IsBuilding() {
		return isBuilding; // ネットワーク作成中なのでCheckClose()はまだしない
	}
	
	function CanCreateNewRoute() {
		return true;
	}
	
	function IsTooManyVehiclesForNewRoute(self) {
		local remaining = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
		if(remaining > 30) {
			return false;
		}
		return remaining <= self.GetMaxTotalVehicles() * (1 - self.GetThresholdVehicleNumRateForNewRoute());
	}
	
	function IsTooManyVehiclesForSupportRoute(self) {
		local remaining = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
		if(remaining > 30) {
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

	function GetMaxRouteCapacity(cargo) {
		local engineSet = GetLatestEngineSet();
		if(engineSet == null) {
			return 0;
		}
		return engineSet.GetMaxRouteCapacity(cargo);
	}

	function GetCurrentRouteCapacity(cargo) {
		local engineSet = GetLatestEngineSet();
		if(engineSet == null) {
			return 0;
		}
		return engineSet.GetRouteCapacity(cargo);
	}	
	
	function GetCargoCapacity(cargo) {
		local engineSet = GetLatestEngineSet();
		if(engineSet != null) {
			if(engineSet.cargoCapacity.rawin(cargo)) {
				return engineSet.cargoCapacity[cargo];
			}
		}
		return 0;
	}

	function GetDefaultInfrastractureTypes() {
		return null;
	}
	
	function GetSuitableInfrastractureTypes(src, dest, cargo) {
		return null;
	}
	
	// overrideして使う
	function GetRouteInfrastractureCost() {
		return 0;
	}
	
	static function GetPaxMailTransferBuildingCost(cargo) {
		if(CargoUtils.IsPaxOrMail(cargo)) {
			if(!HogeAI.Get().IsDistantJoinStations()) {
				local pax = HogeAI.Get().GetPassengerCargo();
				if(TownBus.CanUse(pax)) {
					local busPrice = TownBus.busPrice[pax];
					return busPrice * 8 + HogeAI.GetInflatedMoney(2000); // 都市の規模による
				}
			} else {
				return HogeAI.GetInflatedMoney(5000);
			}
		}
		return 0;
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
	
	function GetSrcStationGroup(isDest) {
		if(isDest) {
			return destHgStation.stationGroup;
		} else {
			return srcHgStation.stationGroup;
		}
	}
	
	function GetDestStationGroup(isDest) {
		if(isDest) {
			return srcHgStation.stationGroup;
		} else {
			return destHgStation.stationGroup;
		}
	}
	
	function GetOtherSideStation(stationGroup) {
		if(destHgStation.stationGroup == stationGroup) {
			return srcHgStation;
		} else {
			return destHgStation;
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
	
	function IsDestOverflow( cargo = null ) {
		if(cargo == null) {
			cargo = this.cargo;
		}
		if( !IsTransfer() ) {
			return false;
		}
		local destRoute = GetDestRoute();
		if(!destRoute) {
			return false;
		}
		return destRoute.IsOverflow( cargo, IsDestDest() );
	}

	function IsOverflow( cargo = null, isDest = false, callRoutes = null ) {
		if( callRoutes == null ) {
			callRoutes = {};
		}
		if( callRoutes.rawin(this) ) {
			return false;
		}
		callRoutes.rawset(this,0);

		if(cargo == null) {
			cargo = this.cargo;
		}
		if( IsTransfer() ) {
			local destRoute = GetDestRoute();
			if(!destRoute) {
				return false;
			}
			if( destRoute.IsOverflow(cargo, IsDestDest(), callRoutes ) ) {
				return true;
			}
		}

		local capacity = GetCargoCapacity(cargo);
		local bottom = max(300, min(capacity * 20, 3000));
		local station = (isDest ? destHgStation : srcHgStation).GetAIStation();
		if(!isDest && !(this instanceof TrainReturnRoute)
				&& AIStation.HasCargoRating(station, cargo) && AIStation.GetCargoRating(station, cargo) < 50) {
			return true; // return routeは満載待機ではないので
		}
		return AIStation.GetCargoWaiting(station, cargo) > bottom;
	}
	
	function IsOverflowPlace(place,cargo) {
		if(IsDestPlace(place)) {
			return IsOverflow(cargo,true);
		}
		if(IsSrcPlace(place)) {
			return IsOverflow(cargo,false);
		}
		return false;
	}
	
	function NeedsAdditionalProducing(callRoutes = null, isDest = false, checkRouteCapacity = true) {
		return NeedsAdditionalProducingCargo(cargo, callRoutes, isDest, checkRouteCapacity );
	}
	
	function NeedsAdditionalProducingCargo(cargo, callRoutes = null, isDest = false, checkRouteCapacity = true) {
		local key = cargo+"-"+isDest+"-"+checkRouteCapacity;
		if(needsAdditionalCache.rawin(key)) {
			return needsAdditionalCache.rawget(key);
		}
		local result = _NeedsAdditionalProducingCargo(cargo, callRoutes, isDest, checkRouteCapacity);
		needsAdditionalCache.rawset(key,result);
		return result;
	}

	function _NeedsAdditionalProducingCargo(cargo, callRoutes = null, isDest = false, checkRouteCapacity = true ) {
		if(IsClosed()) {
			return false;
		}
		if(checkRouteCapacity && IsOverflow(cargo,isDest)) {
			return false;
		}
	
		if(callRoutes == null) {
			callRoutes = {};
		} else if(callRoutes.rawin(this)) {
			HgLog.Warning("NeedsAdditionalProducingCargo() called recursively."+this);
			return false;
		}
		callRoutes.rawset(this,0);

		local hgStation = isDest ? destHgStation : srcHgStation;
		local limitCapacity = GetCargoCapacity(cargo);
		if(!IsReturnRoute(isDest)) {
			limitCapacity /= 2;
		}
		local cargoWaiting = AIStation.GetCargoWaiting( hgStation.GetAIStation(), cargo );
		if(cargoWaiting == 0 && limitCapacity == 0 && cargo != this.cargo
				&& !NeedsAdditionalProducingCargo(this.cargo,null,false,checkRouteCapacity)) { // 新たな種類のcargoが必要かどうかのチェック
			return false;	// メインカーゴがこれ以上不要な場合、列車数が飽和している事を示唆している
		}
		if(checkRouteCapacity && GetLeftCapacity(cargo, isDest) == 0) {
			return false;
		}

		local result = cargoWaiting <= limitCapacity;
		if(!IsTransfer()) {
			//HgLog.Warning("_NeedsAdditionalProducingCargo "+result+" cargoWaiting:"+cargoWaiting+" limitCapacity:"+limitCapacity+" "+this);
			return result;
		}
		if(isDest || !result) {
			return false;
		}
		foreach(destRoute in GetDestRoutes()) {
			if( destRoute.IsBiDirectional() && destRoute.destHgStation.stationGroup == destHgStation.stationGroup ) {
				if( destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, true, checkRouteCapacity) 
						&& !destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, false, checkRouteCapacity) ) {
					return true;
				}
			} else {
				if( destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, false, checkRouteCapacity) ) {
					return true;
				}
			}
		}
		return false;
	}
	
	function GetLeftCapacity(cargo, isDest = false) {
		local station = isDest ? destHgStation : srcHgStation;
		// CurrentExpectedProductionは完ぺきではないが、さすがに2倍を超えていたらオーバーしていると思う
		local maxCapacity;
		if( IsReturnRoute(isDest) ) {
			maxCapacity = GetCurrentRouteCapacity(cargo);
		} else {
			maxCapacity = GetMaxRouteCapacity(cargo);
		}
		if(station.stationGroup == null) {
			return 0;
		}
		return max(0, maxCapacity - station.stationGroup.GetCurrentExpectedProduction(cargo, GetVehicleType(), true));
	}
	
	// TrainReturnRouteでoverrideされる
	function IsReturnRoute(isDest) {
		return isDest;
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
	
	function GetCargoProductions() {
		local result = {};
		foreach(cargo in GetCargos()) {
			result[cargo] <- GetProductionCargo(cargo);
		}
		return result;
	}
	
	function GetTotalDelivableProduction() {
		local result = 0;
		foreach(cargo in GetCargos()) {
			result += GetDelivableProduction(cargo);
		}
		return result;
	}
	
	function GetProductionCargo(cargo, callers = null) {
		local key = cargo ;
		if(productionCargoCache.rawin(key)) {
			return productionCargoCache.rawget(key);
		}
		if(callers == null) {
			callers = {};
		}
		if(callers.rawin(this)) {
			HgLog.Warning("GetProductionCargo recursive call:"+this);
			return 0;
		}
		callers.rawset(this,true);
	
		local result = 0;
		result = srcHgStation.GetProduction(cargo, this, callers);
		if(result == 0 && IsBiDirectional()) {
			result = destHgStation.GetProduction(cargo, this, callers);
		}
		
		//HgLog.Info("GetProductionCargo:"+result+"("+srcHgStation.GetName() + ")["+AICargo.GetName(cargo)+"] "+this);
		productionCargoCache.rawset(key, result);
		
		callers.rawdelete(this);
		return result;
	}

	function GetProductionCargoInfos(cargo, callers = null) {
		local key = cargo ;
		if(productionCargoInfosCache.rawin(key)) {
			return productionCargoInfosCache.rawget(key);
		}

		if(callers == null) {
			callers = {};
		}
		if(callers.rawin(this)) {
			HgLog.Warning("GetProductionCargo recursive call:"+this);
			return [];
		}
		callers.rawset(this,true);
	
		local result = clone srcHgStation.GetProductionInfos(cargo, this, callers);
		local cruiseDays = GetLatestEngineSet().days / 2;
		foreach(productionInfo in result) {
			productionInfo.cruiseDays += cruiseDays;
		}
		//HgLog.Info("GetProductionCargo:"+result+"("+srcHgStation.GetName() + ")["+AICargo.GetName(cargo)+"] "+this);
		productionCargoInfosCache.rawset(key, result);
		
		callers.rawdelete(this);
		return result;
	}

	function GetDelivableProduction(cargo, callers = null) {
		local result = GetProductionCargo(cargo, callers);
		local currentCapacity = GetCurrentRouteCapacity(cargo);
		if(currentCapacity == 0 && GetVehicleType() == AIVehicle.VT_RAIL) {
			currentCapacity = GetRouteCapacity() * 100; // TODO: 実際に車両が作れるかどうかの検査
		}		
		//HgLog.Info("Route.GetDelivableProduction "+result+" currentCapacity:"+currentCapacity+"["+AICargo.GetName(cargo)+"] "+this);
		return min( result, currentCapacity );
	}
	
	function GetDelivableProductionInfos(cargo, callers = null ) {
		local result = GetProductionCargoInfos(cargo, callers);
		local currentCapacity = GetCurrentRouteCapacity(cargo);
		if(currentCapacity == 0 && GetVehicleType() == AIVehicle.VT_RAIL) {
			currentCapacity = GetRouteCapacity() * 100;
		}
		local total = 0;
		foreach( productionInfo in result ) {
			total += result.production;
		}
		local rate = total * 100 / currentCapacity;
		foreach( productionInfo in result ) {
			productionInfo.production = productionInfo.production * rate / 100;
		}
		return result;
	}

	function GetCargoIsTransfered() {
		local result = {};
		foreach(cargo in GetCargos()) {
			if(srcHgStation.stationGroup.IsCargoTransferToHere(cargo)) { // TODO: bidirectionalの場合
				result.rawset(cargo,true);
			}
		}
		return result;
	}

	function GetTotalCruiseDays(searchedRoute = null) {
		if(searchedRoute == null) {
			searchedRoute = {};
		}
		if(searchedRoute.rawin(this)) {
			return 0;
		}
		searchedRoute.rawset(this, true);
		local latestEngineSet = GetLatestEngineSet();
		if(latestEngineSet == null) {
			HgLog.Warning("latestEngineSet == null "+this);
			return 0;
		}
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(!destRoute) {
				return latestEngineSet.days / 2;
			}
			return destRoute.GetTotalCruiseDays(searchedRoute) + latestEngineSet.days / 2;
		} else {
			return latestEngineSet.days / 2;
		}		
	}

	function GetDistance() {
		return AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
	}
	
	function IsValidDestStationCargo() {
		if(destHgStation.stationGroup.IsAcceptingCargo(cargo)) {
			if(IsBiDirectional()) {
				if(srcHgStation.stationGroup.IsAcceptingCargo(cargo)) {
					return true;
				}
			} else {
				return true;
			}
		}
		return false;
	}
	
	function GetFinalDestPlace() {
		return GetFinalDestStation().place;
	}
	
	function GetFinalDestStation(searchedRoute = null, src = null) {
		if(searchedRoute == null) {
			searchedRoute = {};
		}
		if(searchedRoute.rawin(this)) {
			return destHgStation;
		}
		searchedRoute.rawset(this, true);
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(!destRoute) {
				return destHgStation;
			}
			return destRoute.GetFinalDestStation(searchedRoute, destHgStation.stationGroup);
		} else {
			return GetOtherSideStation(src);
		}		
	}
	
	
	function GetLastDestHgStation() {
		return destHgStation;
	}
	
	function GetDestRoutes() {
		local destRoutes = [];
		if(isTransfer) {
			if(destHgStation.stationGroup == null) {
				HgLog.Warning("destHgStation.stationGroup == null "+this);
				return [];
			}
			return destHgStation.stationGroup.GetUsingRoutesAsSource();
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
		local src = srcHgStation.stationGroup;
		local dest = destHgStation.stationGroup;
	
		if(IsTransfer()) {
			local cargoList = AICargoList();
			cargoList.Valuate(function(subCargo):(cargo,src) {
				return subCargo != cargo && src.IsProducingCargo(subCargo);
			})
			cargoList.KeepValue(1);
			local result = [];
			foreach(destRoute in GetDestRoutes()) {
				foreach(subCargo,_ in cargoList) {
					if(destRoute.HasCargo(subCargo) ) {
						result.push(subCargo);
					}
				}			
			
			}
			return result;
		}
		if(IsBiDirectional()) {
			local result = [];
			foreach(subCargo,_ in AICargoList()) {
				if(subCargo == this.cargo) {
					continue;
				}
				if(HogeAI.Get().IsManyTypesOfFreightAsPossible()) {
					if(src.IsAcceptingCargo(subCargo) && dest.IsAcceptingCargo(subCargo)) {
						result.push(subCargo);
					}
				} else {
					if(src.IsAcceptingAndProducing(subCargo) && dest.IsAcceptingAndProducing(subCargo)) {
						result.push(subCargo);
					}
				}
			}
			return result;
		} else {
			local result = [];
			foreach(subCargo,_ in AICargoList()) {
				/*if(subCargo == HogeAI.GetPassengerCargo()) {
					continue;
				}*/
				if(cargo != subCargo /*&& srcHgStation.IsProducingCargo(subCargo)*/ && dest.IsAcceptingCargo(subCargo)) {
					/*
					if(!CargoUtils.IsPaxOrMail(cargo) && AICargo.HasCargoClass(subCargo, AICargo.TE_PASSENGERS)) {
						// 貨物と人を混ぜない
						continue;
					}*/
				
					/*if(destHgStation.place != null && CargoUtils.IsPaxOrMail(subCargo)) {
						continue; // 街にbidirectionalじゃない手段でpax/mailは運ばない
					}*/
					if(HogeAI.Get().IsManyTypesOfFreightAsPossible() || (destHgStation.place == null || destHgStation.place.IsCargoAccepted(subCargo))) {
						result.push(subCargo);
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
	
	function NotifyAddTransfer(callers = null) {
		if(callers == null) {
			callers = {};
		}
		if(callers.rawin(this)) {
			return;
		}
		callers.rawset(this,0);
		needsAdditionalCache.clear();
		productionCargoCache.clear();
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(destRoute != false) {
				destRoute.NotifyAddTransfer(callers);
			}
		}
	}

	function OnIndustoryClose(industry) {
		local srcPlace = srcHgStation.place;
		if(srcPlace != null && srcPlace instanceof HgIndustry && srcPlace.industry == industry) {
			if(GetVehicleType() == AIVehicle.VT_RAIL && HogeAI.Get().IsInfrastructureMaintenance() == false) {
				HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. Search transfer." + this);
				HogeAI.Get().SearchAndBuildTransferRoute(this);
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
	
	
	function IsDestDest() {
		local destRoute = GetDestRoute();
		if(!destRoute) {
			return false;
		}
		if(IsTransfer() && destRoute.IsBiDirectional() && destHgStation.stationGroup == destRoute.destHgStation.stationGroup) {
			return true;
		} else {
			return false;//TODO !isTransfer はplaceの一致で判断
		}
	}
	
	function CheckClose() {
		if(IsRemoved() || IsBuilding()) {
			return;
		}
		if(srcHgStation.stationGroup == null) {
			HgLog.Warning("Route Remove (srcHgStation removed) "+this);
			Remove();
			return;
		}
		if(destHgStation.stationGroup == null) {
			HgLog.Warning("Route Remove (destHgStation removed) "+this);
			Remove();
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
		if(IsTransfer()) {
			local destRoutes = destHgStation.stationGroup.GetUsingRoutesAsSource();
			local srcSharing = srcHgStation.stationGroup.GetUsingRoutesAsSource().len() >= 2;
			/*
			if(destHgStation.GetName().find("2340") != null) {
				HgLog.Warning("GetUsingRoutesAsSource:"+destRoutes.len()+" "+destHgStation.stationGroup+" "+this);
				foreach(route in destRoutes) {
					HgLog.Warning("GetUsingRoutesAsSource:"+route+" "+route.srcHgStation.stationGroup+" "+this);
				}
			}*/
			
			if(destRoutes.len() == 0) {
				HgLog.Warning("Route Remove (destStation is used by nothing)"+this);
				Remove();
				return;
			}
			local closedAllDest = true;
			foreach(destRoute in destRoutes) {
				if(srcSharing && destRoute.IsOverflow(cargo)) {
					continue;
				}
				if(!destRoute.IsClosed() && destRoute.HasCargo(cargo)) {
					closedAllDest = false;
					break;
				}
			}
			if(!IsClosed() && closedAllDest) {
				HgLog.Warning("Route Close (All destRoute closed)"+this);
				Close();
			} else if(IsClosed() && !closedAllDest) {
				ReOpen();
			}
		} else {
			local acceptedCargo = IsValidDestStationCargo();
			if(destHgStation.place == null && !acceptedCargo) {
				// destHgStationをshareしているとplace==nullになる事がある
				//この場合、placeが一時的に閉じただけなのかどうかがわからない。Routeがplaceを持つ必要があるかもしれない
				HgLog.Warning("Route Remove (destStation.place == null && not accept cargo)"+this); 
				Remove();
				return;
			}
			if(!IsClosed() && !acceptedCargo) {
				HgLog.Warning("Route Close (dest can not accept)"+this);
				lastDestClosedDate = AIDate.GetCurrentDate();
				local destPlace = destHgStation.place.GetProducing();
				if(destPlace instanceof HgIndustry && !destPlace.IsClosed()) {
					Close();
				} else if(destPlace instanceof TownCargo) { //街の受け入れ拒否は一時的なものと判断
					Close();
				}
			} else if(IsClosed() && acceptedCargo) {
				ReOpen();
			}

			if(GetVehicleType() == AIVehicle.VT_ROAD || IsSingle()) {
				local routes = [];
				if(srcHgStation.place != null) {
					routes.extend(PlaceDictionary.Get().GetUsedAsSourceByPriorityRoute(srcHgStation.place, cargo));
				}
				if(IsBiDirectional() && destHgStation.place != null) {
					routes.extend(PlaceDictionary.Get().GetUsedAsSourceByPriorityRoute(destHgStation.place, cargo));
				}
				foreach(route in routes) {
					HgLog.Warning("GetUsedAsSourceByPriorityRoute:"+route+" "+this);
					if(route.IsClosed() || (!route.NeedsAdditionalProducingPlace(srcHgStation.place) && !route.NeedsAdditionalProducingPlace(destHgStation.place))) {
						continue;
					}
					if(route.IsSameSrcAndDest(this)) {// industryへのsupply以外が対象(for FIRS)
						continue;
					}
					HgLog.Warning("Route Remove (Collided rail route found)"+this);
					Remove();
					return;
				}
			}
		}
	}

	function _tostring() {
		return (IsTransfer() ? "T:" : "") + destHgStation.GetName() + "<-"+(IsBiDirectional()?">":"") + srcHgStation.GetName()
				+ "[" + AICargo.GetName(cargo) + "]" + GetLabel() + (IsClosed()?" Closed":"");
	}
}


class CommonRoute extends Route {
	static checkReducedDate = {};
	static vehicleStartDate = {};

	
	function EstimateEngineSet(self, cargo, distance, production, isBidirectional, infrastractureTypes=null, isTownBus=false) {
		local estimator = self.GetEstimator(self);
		estimator.cargo = cargo;
		estimator.distance = distance;
		estimator.production = production;
		estimator.isBidirectional = isBidirectional;
		estimator.infrastractureTypes = infrastractureTypes;
		estimator.isTownBus = isTownBus;
		return estimator.Estimate();
		
	
	}
	
	function GetEstimator(self = null) {
		return CommonEstimator(self == null ? this : self);
	}
	
	function GetEngineCapacity(self, engine, cargo) {
		local result;
		
		if(self.GetVehicleType() == AIVehicle.VT_ROAD && AIEngine.IsArticulated(engine)) {
			return  AIEngine.GetCapacity(engine); // ArticulatedだとなぜかGetBuildWithRefitCapacityの値がとても小さい
		}
		
		if(self.instances.len() >= 1) {
			foreach(route in self.instances) {
				result = AIVehicle.GetBuildWithRefitCapacity(route.depot, engine, cargo);
				/*
				if(self.GetVehicleType() == AIVehicle.VT_ROAD && AIEngine.IsArticulated(engine)) {
							HgLog.Warning("capacity:"+result+" engine:"+AIEngine.GetName(engine)+" cargo:"+AICargo.GetName(cargo)+" depot:"+HgTile(route.depot)
									+" GetCapacity:"+ AIEngine.GetCapacity(engine)+" CanPullCargo:"+AIEngine.CanPullCargo(engine,cargo));
					return  AIEngine.GetCapacity(engine); // ArticulatedだとなぜかGetBuildWithRefitCapacityの値がとても小さい
				}*/
				if(result != -1) {
					/*HgLog.Info("capacity:"+result+" engine:"+AIEngine.GetName(engine)+" cargo:"+AICargo.GetName(cargo)+" depot:"+HgTile(route.depot)
							+" GetCapacity:"+ AIEngine.GetCapacity(engine)+" CanPullCargo:"+AIEngine.CanPullCargo(engine,cargo));*/
					return result;
				}
			}
		} else {
			if(self.GetVehicleType() == AIVehicle.VT_WATER) {
				local depotTile;
				if(!WaterRoute.rawin("defaultDepot")) {
					local execMode = AIExecMode();
					depotTile = HgTile.XY(3,3).tile;
					AIMarine.BuildWaterDepot(depotTile, HgTile.XY(2,3).tile);
					WaterRoute.defaultDepot <- depotTile;
				} else {
					depotTile = WaterRoute.defaultDepot;
				}
				result = AIVehicle.GetBuildWithRefitCapacity(depotTile, engine, cargo);
				//HgLog.Info("capacity:"+result+" engine:"+AIEngine.GetName(engine)+" cargo:"+AICargo.GetName(cargo)+" depot:"+HgTile(depotTile));
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
	
	static function CalculateVehiclesSpeed(vehicleType) {
		local vehicleList = AIVehicleList();
		vehicleList.Valuate( AIVehicle.GetVehicleType );
		vehicleList.KeepValue( vehicleType );
		vehicleList.Valuate( AIVehicle.GetState );
		vehicleList.KeepValue( AIVehicle.VS_RUNNING );
		
		local start = AIDate.GetCurrentDate();
		vehicleList.Valuate(AIVehicle.GetLocation);
		HogeAI.Get().WaitDays(3);
		vehicleList.Valuate(function(v) : (vehicleList,start) {
			if(AIVehicle.GetState(v) != AIVehicle.VS_RUNNING) {
				return -1;
			}
			local d = AIMap.DistanceManhattan( vehicleList.GetValue(v), AIVehicle.GetLocation(v) );
			return CargoUtils.GetSpeed( d, AIDate.GetCurrentDate() - start );
		});
		vehicleList.RemoveValue( -1 );
		return vehicleList;
	}

	static function CheckReduce(self,emergency = false) {
		local routeInstances = self.instances;
		local vehicleType = self.GetVehicleType();
		if(AIDate.GetMonth(AIDate.GetCurrentDate()) < 10) {
			return;
		}
		if(CommonRoute.checkReducedDate.rawin(vehicleType) && CommonRoute.checkReducedDate[vehicleType] > AIDate.GetCurrentDate() - 100) {
			return;
		}
		CommonRoute.checkReducedDate.rawset(vehicleType, AIDate.GetCurrentDate());
		
		local execMode = AIExecMode();
		local vehiclesRoom = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType);
		local tooManyVehicles = vehiclesRoom <= 1;
		
		HgLog.Info("Check RemoveRoute vt:"+self.GetLabel()+" "+self.GetLabel()+" routes:"+routeInstances.len());

		if(vehicleType == AIVehicle.VT_AIR) {
			if(AIDate.GetYear(AIDate.GetCurrentDate()) % 10 == 9) {
				Place.canBuildAirportCache.clear(); //10年に1度キャッシュクリア
			}
		}

		local engineList = AIEngineList(vehicleType);
		engineList.Valuate(AIEngine.GetDesignDate);
		engineList.KeepAboveValue(AIDate.GetCurrentDate() - 365*2); //デザインから出現まで1年かかる
		local engineChanged = engineList.Count() >= 1;

		local vehicleSpeeds = null;
		if(vehicleType == AIVehicle.VT_ROAD) {
			vehicleSpeeds = CommonRoute.CalculateVehiclesSpeed(vehicleType);
		}


		local minProfit = null;
		local minRoute = null;
		local routeRemoved = false;
		local checkRoutes = 0;
		local speedRateSum = 0.0;
		local speedCount = 0;
		foreach(route in routeInstances) {
			if(route.IsClosed()) {
				continue;
			}
			if(route.IsTransfer()) {
				if(vehicleType == AIVehicle.VT_ROAD) {
					route.CheckReduceForRoadTransfer(vehicleSpeeds);
				}
				continue;
			}
			
			if(engineChanged) {
				local engineSet = route.GetLatestEngineSet();
				if(engineSet != null && engineSet.date < AIDate.GetCurrentDate() - 365 * 10) {
					engineSet.isValid = false;
				}
			}
			local vehicleList = AIVehicleList_Group(route.vehicleGroup);
			local totalValue = 0;
			foreach(v,_ in vehicleList) {
				totalValue += AIVehicle.GetCurrentValue(v);
			}
			
			local infraCost = route.GetRouteInfrastractureCost();
			route.profits.push(AIGroup.GetProfitLastYear(route.vehicleGroup));
			local sum = 0;
			local checkYear = emergency ? 3 : 5;
			local averageProfit = null;
			if(route.profits.len() >= checkYear) {
				for(local i=0; i<checkYear; i++) {
					sum += route.profits[route.profits.len() - i - 1];
				}
				averageProfit = sum / checkYear - infraCost - totalValue * 9 / 100/*減価償却*/;
				if(averageProfit < 0) {
					HgLog.Warning("RemoveRoute averageProfit:"+averageProfit+" infraCost:"+infraCost+" "+route);
					route.Remove();
					routeRemoved = true;
					continue;
				}
			}
			vehicleList.Valuate(AIVehicle.IsStoppedInDepot);
			vehicleList.RemoveValue(1);
			if(vehicleType == AIVehicle.VT_ROAD) {
				foreach(v,_ in vehicleList) {
					if(vehicleSpeeds.HasItem(v)) {
						speedRateSum += vehicleSpeeds.GetValue(v).tofloat() / AIEngine.GetMaxSpeed(AIVehicle.GetEngineType(v));
						speedCount ++;
					}
				}
			}
			vehicleList.Valuate(CommonRoute.GetStartAge);
			vehicleList.KeepAboveValue(365);
			if(vehicleList.Count()==0) {
				continue;
			}
			checkRoutes ++;
			if(vehicleType == AIVehicle.VT_ROAD) {
				if(AIGroup.GetProfitThisYear(route.vehicleGroup) < AIGroup.GetProfitLastYear(route.vehicleGroup) / 2) {
					HgLog.Warning("ReduceVehiclesToHalf (profit down more than half) "+route);
					route.ReduceVehiclesToHalf();
				}
			}
			
			if(averageProfit != null) {
				local routeProfit = averageProfit / (vehicleList.Count() * 2);
				if(minProfit == null || minProfit > routeProfit) {
					minProfit = routeProfit;
					minRoute = route;
				}
			}
		}
		
		if(speedCount >= 100) {
			HogeAI.Get().roadTrafficRate = speedRateSum / speedCount;
			HgLog.Info("roadTrafficRate:"+HogeAI.Get().roadTrafficRate);
		}
		
		if(emergency || (tooManyVehicles /*&& engineChanged*/)) {
			if(minRoute != null && checkRoutes >= 3) {
				HgLog.Warning("RemoveRoute minProfit:"+minProfit+" "+minRoute);
				minRoute.Remove();
			}
		}

		
	}
	
	function CheckReduceForRoadTransfer(vehiclesSpeed) { // transferは利益で削減しないのでスピードで落とす
		local vehicleList = AIVehicleList_Group(vehicleGroup);
		vehicleList.Valuate(function(v):(vehiclesSpeed) { return vehiclesSpeed.HasItem(v) ? vehiclesSpeed.GetValue(v) : -1;} );
		vehicleList.RemoveValue(-1);
		local latestEngineSet = GetLatestEngineSet();
		if(vehicleList.Count() >= 6 && latestEngineSet != null) {
			//HgLog.Warning("AverageSpeed "+ListUtils.Average(vehicleList)+" max:"+AIEngine.GetMaxSpeed(latestEngineSet.engine)+" "+this)
			if(ListUtils.Average(vehicleList) < AIEngine.GetMaxSpeed(latestEngineSet.engine) /*latestEngineSet.cruiseSpeed*/ / 4) {
				ReduceVehiclesToHalf();
				HgLog.Warning("ReduceVehiclesToHalf (averageSpeed < maxSpeed / 4) maxVehicles:"+maxVehicles+" "+this);
			}
		}
	}
	
	function ReduceVehiclesToHalf() {
		local vehicleList = AIVehicleList_Group(this.vehicleGroup);
		vehicleList.Valuate(AIVehicle.IsStoppedInDepot);
		vehicleList.RemoveValue(1);
		foreach(v,_ in vehicleList) {
			if(AIBase.RandRange(2) == 0) {
				this.AppendRemoveOrder(v);
				this.maxVehicles = min(vehicleList.Count(), this.maxVehicles);
				this.maxVehicles = max(0, this.maxVehicles - 1);
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
	isBiDirectional = null;
	srcHgStation = null;
	destHgStation = null;
	vehicleGroup = null;
	
	maxVehicles = null;
	depot = null;
	destDepot = null;
	isClosed = null;
	isRemoved = null;
	isWaitingProduction = null; // まだcargoが来ていないrouteかどうか
	lastDestClosedDate = null;
	useDepotOrder = null;
	isDestFullLoadOrder = null;
	cannotChangeDest = null;
	latestEngineSet = null;

	destRoute = null;
	hasRailDest = null;
	stopppedVehicles = null;
	profits = null;
	
	savedData = null;
	
	constructor() {
		Route.constructor();
		isClosed = false;
		isRemoved = false;
		isWaitingProduction = false;
		useDepotOrder = true;
		isDestFullLoadOrder = false;
		cannotChangeDest = false;
		profits = [];
		isTransfer = false;
		isBiDirectional = false;
		savedData = {};
	}
	
	function Initialize() {
		if(this.vehicleGroup == null) {
			this.vehicleGroup = AIGroup.CreateGroup( GetVehicleType() );
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
		t.savedData <- savedData;
		
		t.isClosed <- isClosed;
		t.isRemoved <- isRemoved;
		t.isWaitingProduction <- isWaitingProduction;
		t.maxVehicles <- maxVehicles;
		t.lastDestClosedDate <- lastDestClosedDate;
		t.cannotChangeDest <- cannotChangeDest;
		t.latestEngineSet <- latestEngineSet;
		return t;
	}
	
	function Load(t) {
		savedData = t.savedData;
	
		cargo = savedData.cargo;
		srcHgStation = HgStation.worldInstances[savedData.srcHgStation];
		destHgStation = HgStation.worldInstances[savedData.destHgStation];

		isTransfer = savedData.isTransfer;
		isBiDirectional = savedData.isBiDirectional;
		vehicleGroup = savedData.vehicleGroup;
		depot = savedData.depot;
		destDepot = savedData.destDepot;
		useDepotOrder = savedData.useDepotOrder;
		isDestFullLoadOrder = savedData.isDestFullLoadOrder;
		
		isClosed = t.isClosed;
		isRemoved = t.isRemoved;
		isWaitingProduction = t.isWaitingProduction;
		maxVehicles = t.maxVehicles;
		lastDestClosedDate = t.lastDestClosedDate;
		cannotChangeDest = t.cannotChangeDest;
		latestEngineSet = t.latestEngineSet != null ? delegate CommonEstimation : t.latestEngineSet : null;
	}
	
	function UpdateSavedData() {
		savedData = {
			cargo = cargo
			srcHgStation = srcHgStation.id
			destHgStation = destHgStation.id
			isTransfer = isTransfer
			isBiDirectional = isBiDirectional
			vehicleGroup = vehicleGroup
			depot = depot
			destDepot = destDepot
			useDepotOrder = useDepotOrder
			isDestFullLoadOrder = isDestFullLoadOrder
		};
	}

	function SetPath(path) {
	}
	
	function GetInfrastractureType() {
		return null;
	}
	
	function IsBiDirectional() {
		return isBiDirectional; //!isTransfer && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
	}
	
	function IsTransfer() {
		return isTransfer;
	}
	
	function IsSingle() {
		return false;
	}
	
	function IsRoot() {
		return !GetDestRoute();
	}
	
	function GetLatestEngineSet() {
		return latestEngineSet;
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
		if(depot == null) {
			HgLog.Warning("depot == null. "+this);
			return null;
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
		//local vehicle = AIVehicle.BuildVehicle(depot, engine);
		local vehicle = AIVehicle.BuildVehicleWithRefit(depot, engine, cargo);
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("BuildVehicleWithRefit failed. engine:"
				+ AIEngine.GetName(engine) + " depot:" + HgTile(depot)
				+ " " + AIError.GetLastErrorString() + " " + this);
			return null;
		}
		//HgLog.Warning("GetRefitCapacity:"+AIVehicle.GetRefitCapacity(vehicle, cargo)+" "+AIEngine.GetName(engine)+" "+this);
		//AIVehicle.RefitVehicle (vehicle, cargo);
		
		if(AIVehicle.GetCapacity(vehicle, cargo) == 0) {
			HgLog.Warning("BuildVehicle failed (capacity==0) engine:"+AIEngine.GetName(engine)+" "+AIError.GetLastErrorString()+" "+this);
			AIVehicle.SellVehicle(vehicle);
			return null;
		}
		
		
		AIGroup.MoveVehicle(vehicleGroup, vehicle);
		MakeOrder(vehicle);
		/*
		AIOrder.SetOrderCompareValue(vehicle, 1, 80);
		AIOrder.SetOrderCompareFunction(vehicle, 1, AIOrder.CF_MORE_EQUALS );
		AIOrder.SetOrderCondition(vehicle, 1, AIOrder.OC_RELIABILITY );
		AIOrder.SetOrderJumpTo (vehicle, 1, 3)*/
		
		StartVehicle(vehicle);
		
		if(GetVehicleType() != AIVehicle.VT_ROAD || maxVehicles==1/*ルート作成直後(とは限らないが…)*/) { // ROADのmaxVehiclesは渋滞に関する情報の為リセットしない
			maxVehicles = GetMaxVehicles();
		}
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		
		return vehicle;
	}
	
	function MakeOrder(vehicle) {

		local nonstopIntermediate = GetVehicleType() == AIVehicle.VT_ROAD ? AIOrder.OF_NON_STOP_INTERMEDIATE : 0;

		if(useDepotOrder && HogeAI.Get().IsEnableVehicleBreakdowns()) {
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
		
		if(useDepotOrder && destDepot != null && HogeAI.Get().IsEnableVehicleBreakdowns()) {
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
		if(useDepotOrder && destDepot != null && HogeAI.Get().IsEnableVehicleBreakdowns()) {
			AIOrder.AppendOrder(vehicle, destDepot, AIOrder.OF_SERVICE_IF_NEEDED ); //5 or 6
		}

		AppendDestToSrcOrder(vehicle);

	}
	
	function IsSrcFullLoadOrder() {
		return true;
	}
	
	function AppendSrcToDestOrder(vehicle) {
	}
	
	function AppendDestToSrcOrder(vehicle) {
	}
	
	function AppendRemoveOrder(vehicle) {
		if(AIVehicle.IsStoppedInDepot(vehicle)) {
			return false;
		}
		if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) != 0) {
			return false;
		}
		if(!AIVehicle.SendVehicleToDepot(vehicle)) {
			local lastError = AIError.GetLastError();
			HgLog.Warning("SendVehicleToDepot failed:"+AIVehicle.GetName(vehicle)+" "+AIError.GetLastErrorString()+" "+this);
			if(lastError == AIError.ERR_UNKNOWN) { // たぶん迷子
				local depot = CreateDepotNear(AIVehicle.GetLocation(vehicle));
				if(depot != null) {
					local result = AIVehicle.SendVehicleToDepot(vehicle);
					HgLog.Warning("SendVehicleToDepot:"+result+" after build depot:"+HgTile(depot)+" "+AIError.GetLastErrorString()+" "+this);
					return result;
				}
			}
			
			return false;
		}
		return true;
		
		// TODO: 使い終わったvehicleを再利用する時の問題(オーダーがおかしくなってる) / GetLatestVehicleの問題(Groupからはずす？/sell時はグループ関係なしにdepotに止まっているやつがいたら消す)
		local latestVehicle = GetLatestVehicle();
		if(destDepot != null && latestVehicle != vehicle) {
			local execMode = AIExecMode();
			local lastOrderPosition = AIOrder.GetOrderCount(vehicle)-1;
			if(AIOrder.IsGotoDepotOrder (vehicle, lastOrderPosition) && 
					(AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, lastOrderPosition)) != 0) {
				return false;
			}
			local orderDestination = AIOrder.GetOrderDestination(vehicle, lastOrderPosition);
			local currentOrderPosition = AIOrder.ResolveOrderPosition( vehicle, AIOrder.ORDER_CURRENT );
			AIOrder.UnshareOrders(vehicle);
			AIOrder.CopyOrders(vehicle,latestVehicle);
			AIOrder.SkipToOrder(vehicle, currentOrderPosition);
			if( AITile.IsStationTile(orderDestination)) {
				local flags = AIOrder.GetOrderFlags(vehicle, lastOrderPosition);
				flags = flags & ~(AIOrder.OF_NO_UNLOAD | AIOrder.OF_FULL_LOAD | AIOrder.OF_FULL_LOAD_ANY);
				flags = flags | AIOrder.OF_NO_LOAD;
				AIOrder.SetOrderFlags(vehicle, lastOrderPosition, flags);
			}
			AIOrder.AppendOrder(vehicle, destDepot,  AIOrder.OF_STOP_IN_DEPOT);
			return true;
		} else {
			return AIVehicle.SendVehicleToDepot(vehicle);
		}
	}
	
	function CreateDepotNear(location) {
		return null; //必要に応じてoverride
	}
	
	function CloneVehicle(vehicle) {
		local execMode = AIExecMode();
		if(this.depot == null) {
			HgLog.Warning("CloneVehicle failed. depot == null "+this);
			return null;
		}
		local depot = this.depot;
		local skipToOrder = null;
		if(this instanceof AirRoute && IsBiDirectional()) {
			if(GetNumVehicles() % 2 == 1) {
				depot = AIAirport.GetHangarOfAirport(destHgStation.platformTile);
				skipToOrder = 1;
			}
		}
		if(this instanceof RoadRoute && IsBiDirectional() && destDepot != null) {
			if(GetNumVehicles() % 2 == 1) {
				depot = destDepot;
				skipToOrder = HogeAI.Get().IsEnableVehicleBreakdowns() ? AIOrder.GetOrderCount(vehicle) - 2 : 1;
			}
		}
	
		local result = null;
		HogeAI.WaitForPrice(AIEngine.GetPrice(AIVehicle.GetEngineType(vehicle)));
		result = AIVehicle.CloneVehicle(depot, vehicle, true);
		if(!AIVehicle.IsValidVehicle(result)) {
			if(AIError.GetLastError() == AIVehicle.ERR_VEHICLE_NOT_AVAILABLE && latestEngineSet != null) {
				latestEngineSet.isValid = false;
			}
			HgLog.Warning("CloneVehicle failed. depot:"+HgTile(depot)+" veh:"+AIVehicle.GetName(vehicle)+" "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIGroup.MoveVehicle(vehicleGroup, result);
		if(skipToOrder != null) {
			AIOrder.SkipToOrder(result, skipToOrder);
		}
		StartVehicle(result);
		return result;
	}
	
	function StartVehicle(vehicle) {
		AIVehicle.StartStopVehicle(vehicle);
		CommonRoute.vehicleStartDate.rawset(vehicle,AIDate.GetCurrentDate());
	}

	function ChooseEngineSet() {
		local engineExpire = 1500;
		if(latestEngineSet == null 
				|| !latestEngineSet.isValid 
				|| latestEngineSet.date + engineExpire < AIDate.GetCurrentDate() 
				|| !AIEngine.IsBuildable(latestEngineSet.engine)) {
			local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
			local production = GetProduction();
			local engineSet;
			if(!HogeAI.Get().roiBase && IsTownTransferRoute()) { // 高速化のため
				engineSet = Route.Estimate( GetVehicleType(), cargo, distance,  production, IsBiDirectional(), [TownBus.GetRoadType()] );
			} else {
				engineSet = EstimateEngineSet( this, cargo, distance,  production, IsBiDirectional() );
			}
			if(engineSet == null) {
				HgLog.Warning("Not found suitable engine. production:"+production+" "+this);
				return null;
			}
			latestEngineSet = clone engineSet;
			latestEngineSet.date <- AIDate.GetCurrentDate();
			latestEngineSet.isValid <- true;
			latestEngineSet.productionIndex <- HogeAI.Get().GetEstimateProductionIndex(production);
			HgLog.Info("ChooseEngine:"+AIEngine.GetName(latestEngineSet.engine)+" production:"+production+" "+this);
		}
		return latestEngineSet;
	}

	function ChooseEngine() {
		local engineSet = ChooseEngineSet();
		if(engineSet == null) {
			return null;
		}
		return engineSet.engine;
	}
	
	function SetLatestEngineSet(engineSet) {
		latestEngineSet = clone engineSet;
		latestEngineSet.date <- AIDate.GetCurrentDate();
		latestEngineSet.isValid <- true;
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

	function IsChangeDestination() {
		return false;
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
				local lastOrderPosition = AIOrder.GetOrderCount(vehicle)-1;
				if(AIOrder.IsGotoDepotOrder (vehicle, lastOrderPosition) && 
						(AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, lastOrderPosition)) != 0) {
					continue;
				}
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
		return min( days * 2 / self.GetStationDateSpan(self) + 1, (distance + 4) * 16 / vehicleLength) + 2;
	}

	function GetMaxVehicles() {
		local vehicle = GetLatestVehicle();
		if(vehicle == null) {
			return 1;
		}
		local length = AIVehicle.GetLength(vehicle);
		local engine = AIVehicle.GetEngineType(vehicle);
		local cruiseSpeed = max( 4, AIEngine.GetMaxSpeed(engine)
				* ( 100 + (HogeAI.Get().IsEnableVehicleBreakdowns() ? AIEngine.GetReliability(engine) : 100)) / 200 );
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
		return vehicleType == AIVehicle.VT_ROAD
				&& (TrainRoute.instances.len() >= 1 || AirRoute.instances.len() >= 1 || WaterRoute.instances.len() >= 1);
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

	function SellVehiclesStoppedInDepots() {
		foreach(vehicle,_ in GetVehicleList()) {
			if(AIVehicle.IsStoppedInDepot(vehicle)) {
				AIVehicle.SellVehicle(vehicle);
				CommonRoute.vehicleStartDate.rawdelete(vehicle);
			}
		}
	}
	
	//static
	function GetStartAge(vehicle) {
		if(CommonRoute.vehicleStartDate.rawin(vehicle)) {
			return AIDate.GetCurrentDate() - CommonRoute.vehicleStartDate[vehicle];
		} else {
			return AIVehicle.GetAge(vehicle);
		}
	}
	
	function CheckNotProfitableOrStopVehicle( emergency = false ) {
		local isBiDirectional = IsBiDirectional();
		local vehicleType = GetVehicleType();
		local vehicleList = GetVehicleList();
		vehicleList.Valuate(AIVehicle.IsStoppedInDepot);
		vehicleList.RemoveValue(1);
		
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
			//HgLog.Warning("check SendVehicleToDepot "+this+" vehicleList:"+vehicleList.Count());
		local checkProfitable = (emergency || AIDate.GetMonth(AIDate.GetCurrentDate()) >= 10) && !isTransfer;
		local latestEngineSet = GetLatestEngineSet();
		local checkAge = emergency ? latestEngineSet != null && min(latestEngineSet.days,800) : 800;
		if(checkProfitable) { // transferはトータルで利益を上げていれば問題ない。 TODO:トータルで利益を上げているかのチェック
			foreach(vehicle,v in vehicleList) {
				local age = GetStartAge(vehicle);
				local notProfitable = age > checkAge && AIVehicle.GetProfitLastYear(vehicle) + AIVehicle.GetProfitThisYear(vehicle) < 0;
				if(notProfitable) {
					//HgLog.Warning("SendVehicleToDepot notProfitable:"+notProfitable+" ageLeft:"+AIVehicle.GetAgeLeft(vehicle)+" "+AIVehicle.GetName(vehicle)+" "+this);
					//AIVehicle.SendVehicleToDepot (vehicle);
					AppendRemoveOrder(vehicle);
					if(vehicleType == AIVehicle.VT_ROAD) { //多すぎて赤字の場合は減らしてもNeedsAdditionalProducing==falseのはず。渋滞がひどくて赤字のケースがあるのでROADだけケア
						maxVehicles = min(vehicleList.Count(), maxVehicles);  // TODO: リセッションで一時的に利益がでていないケースがありうる。継続的に利益が出ていない路線をどうするか
						maxVehicles = max(0, maxVehicles - 1);
						HgLog.Info("maxVehicles:"+maxVehicles+" notProfitable:"+notProfitable+" "+this);
					}
					//HgLog.Info("SendVehicleToDepot(road) "+AIVehicle.GetName(vehicle)+" "+this);
				}
			}
		}
		
		//productionの減少やライバル社がやってきた場合に減らす処理
		if(vehicleType == AIVehicle.VT_WATER) {
			vehicleList.Valuate(AIVehicle.GetState);
			vehicleList.KeepValue(AIVehicle.VS_AT_STATION);
			vehicleList.Valuate(AIVehicle.GetCargoLoad, cargo);
			vehicleList.KeepValue(0);
			if(vehicleList.Count() >=4) {
				local removeCount = vehicleList.Count() - 3;
				foreach(vehicle,_ in vehicleList) {
					AppendRemoveOrder(vehicle);
					removeCount --;
					if(removeCount == 0) {
						break;
					}
				}
			}
		} else if(vehicleType == AIVehicle.VT_AIR) { //VT_ROADはsrcStation付近でのstop数？
			foreach(v,_ in vehicleList) {
				if(AIVehicle.IsInDepot(v) && !AIVehicle.IsStoppedInDepot(v)) {
					AIVehicle.StartStopVehicle(v);
					maxVehicles = min(vehicleList.Count(), maxVehicles);
					maxVehicles = max(0, maxVehicles - 1);
					break;
				}
			}
		} else if(vehicleType == AIVehicle.VT_ROAD) {
			local currentVehicles = vehicleList.Count();
			
			vehicleList.Valuate(AIVehicle.GetCurrentSpeed);
			vehicleList.KeepValue(0);
			vehicleList.Valuate(AIVehicle.GetState);
			
			local waitStations = {};
			foreach(v,_ in vehicleList) {
				if(AIVehicle.GetState(v) == AIVehicle.VS_AT_STATION) {
					waitStations.rawset(AIVehicle.GetLocation(v),true);
				}
			}
			vehicleList.RemoveValue(AIVehicle.VS_AT_STATION);
			vehicleList.Valuate(function(v):(waitStations) {
				local location = AIVehicle.GetLocation(v);
				foreach(p,_ in waitStations) {
					if(AIMap.DistanceManhattan(location,p) <= 4) {
						return 1;
					}
				}
				return 0;
			});
			vehicleList.KeepValue(1);
			if(vehicleList.Count() >= 2) {
				vehicleList.RemoveTop(1);
				foreach(vehicle,_ in vehicleList) {
					AppendRemoveOrder(vehicle);
				}
				maxVehicles = min(currentVehicles, maxVehicles);
				maxVehicles = max(0, maxVehicles - vehicleList.Count());
				HgLog.Info("maxVehicles:"+maxVehicles+" stopped:"+vehicleList.Count()+" "+this);
			}
		}
	}
	
	function CheckBuildVehicle() {
		local c = PerformanceCounter.Start("CheckBuildVehicle");	
		_CheckBuildVehicle();
		c.Stop();
	}
	
	function _CheckBuildVehicle() {
	
		local showLog = false; //srcHgStation.GetName().find("0349") != null;
		if(showLog) {
			HgLog.Info("_CheckBuildVehicle "+this);
		}

		if(isWaitingProduction) {
			if(GetProduction() == 0) {
				return;
			}
			isWaitingProduction = false;
		}

		//local c0 = PerformanceCounter.Start("c00");
		local execMode = AIExecMode();	
		local all = GetVehicleList();
		local inDepot = AIList();
		local vehicleList = AIList();
		
		local sellCounter = 0;
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
		local tooMany = GetMaxTotalVehicles() - totalVehicles < 50;

		local choosenEngine = null;

		if(!isClosed && !isRemoved) {
			choosenEngine = ChooseEngine();
			if(choosenEngine == null) {
				HgLog.Warning("Route Remove (No engine)."+this);
				Remove();
				return;
			}
		}

		vehicleList.AddList(all);
		vehicleList.Valuate(AIVehicle.IsStoppedInDepot);
		vehicleList.KeepValue(0);
		all.Valuate(AIVehicle.IsStoppedInDepot);
		all.KeepValue(1);
		inDepot.AddList(all);
		if(!(isRemoved || isClosed || tooMany)) {
			all.Valuate(AIVehicle.GetEngineType);
			all.RemoveValue(choosenEngine);
		}
		foreach(v,_ in all) {
			AIVehicle.SellVehicle(v);
			CommonRoute.vehicleStartDate.rawdelete(v);
		}
		inDepot.RemoveList(all);
		sellCounter += all.Count();
		if(isRemoved) {
			foreach(v,_ in vehicleList) {
				AppendRemoveOrder(v);
			}
		}
		//c0.Stop();
/*		
		foreach(vehicle,_ in all) {
			if(AIVehicle.IsStoppedInDepot(vehicle)) {
				if(isRemoved || isClosed || tooMany || AIVehicle.GetEngineType(vehicle) != choosenEngine) {
					AIVehicle.SellVehicle(vehicle);
					CommonRoute.vehicleStartDate.rawdelete(vehicle);
					sellCounter ++;
				} else {
					inDepot.AddItem(vehicle,0);
				}
			} else {
				if(isRemoved) {
					AppendRemoveOrder(vehicle);
				}
				if(AIBase.RandRange(100) < 5 // LOSTしてる可能性があるので時々再検索
						&& (AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) != 0) {
					AIVehicle.SendVehicleToDepot(vehicle);
					AIVehicle.SendVehicleToDepot(vehicle);
				}
				vehicleList.AddItem(vehicle,0);
			}
		}*/
		
		if(isRemoved && vehicleList.Count() == 0) {
			HgLog.Warning("All vehicles removed."+this);
			RemoveFinished();
		}
		
		if(sellCounter >= 1) { // 不採算Vehicleを売った直後にcloneするのを避けるため
			return;
		}
		
		if(isClosed || isRemoved) {
			return;
		}

		
		local isBiDirectional = IsBiDirectional();

		if(AIBase.RandRange(100) < (HogeAI.Get().buildingTimeBase ? 5 : 25)) {
			//local c02 = PerformanceCounter.Start("c02");
			CheckNotProfitableOrStopVehicle();
			//c02.Stop();
		}

		//local c021 = PerformanceCounter.Start("c021");
		local needsAddtinalProducing = NeedsAdditionalProducing(null,false,false);
		local isDestOverflow = IsDestOverflow();
		local usingRoutes = srcHgStation.stationGroup.GetUsingRoutesAsSource();
		//c021.Stop();

		/*統一的に減らす仕組みがある
		if(isTransfer && (usingRoutes.len() >= 2 || HogeAI.Get().IsPoor() || totalVehicles >= GetMaxTotalVehicles() * 0.85)) {
			if( vehicleList.Count() >= 2 && (isDestOverflow || maxVehicles > GetMaxVehicles() || (!needsAddtinalProducing && AIBase.RandRange(100) < 25))) {
				foreach(vehicle,v in vehicleList) {
					if(!isBiDirectional && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1 ) {
						continue;
					}
					if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
						AIVehicle.SendVehicleToDepot (vehicle);
						break;
					}
				}
			}
		}
		if(IsTooManyVehiclesForNewRoute(this) && IsSupportMode()) {
			local isReduce = false;
			if(!IsTransfer()) {
				isReduce = totalVehicles > GetMaxTotalVehicles() * 0.8 && GetMaxTotalVehicles() - totalVehicles < 30;
			} else {
				isReduce = totalVehicles > GetMaxTotalVehicles() * 0.85 && GetMaxTotalVehicles() - totalVehicles < 20;
			}
			if(isReduce) {
				ReduceVehicle();
			}
		} else */
		if(isDestOverflow) {
			//local c03 = PerformanceCounter.Start("c03");
			if(showLog) {
				HgLog.Info("isDestOverflow "+this);
			}
			if(tooMany || AIBase.RandRange(100) < vehicleList.Count()) {
				local reduce = 1; //max(1,vehicleList.Count() / 30);
				local count = 0;
				foreach(vehicle,_ in vehicleList) {
					if(AppendRemoveOrder(vehicle)) {
						count ++;
						if(count >= reduce) {
							break;
						}
					}
				}
				if(HogeAI.Get().buildingTimeBase) {
					local old = maxVehicles;
					maxVehicles = max(0,min(maxVehicles, vehicleList.Count()-reduce));
					if(old != maxVehicles) {
						HgLog.Info("maxVehicles:"+maxVehicles+"(isDestOverflow) "+this);
					}
				}
			}
			//c03.Stop();
			return;
		}		
		
		
		if(AIBase.RandRange(100) < (HogeAI.Get().roiBase ? 3 : 15)) {
			//local c22 = PerformanceCounter.Start("c22");
			if((isTransfer && needsAddtinalProducing) || (!isTransfer && IsOverflow())) {
				local finallyMax = GetMaxVehicles();
				maxVehicles += max(1,finallyMax / 12);
				maxVehicles = min(finallyMax, maxVehicles);
				//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
			}
			//c22.Stop();
		}

		
		
		if(AIBase.RandRange(100) < 10 && CargoUtils.IsPaxOrMail(cargo)) { // 作った時には転送が無い時がある
			//local c4 = PerformanceCounter.Start("c4");	
			if(needsAddtinalProducing) {
				CommonRouteBuilder.CheckTownTransferCargo(this,srcHgStation,cargo);
			}
			if(isBiDirectional && NeedsAdditionalProducing(null, true, true)) {
				CommonRouteBuilder.CheckTownTransferCargo(this,destHgStation,cargo);
			}
			//c4.Stop();		
		}

		local engineSet = GetLatestEngineSet();
		if(vehicleList.Count() >= 1
				&& (AIBase.RandRange(100)<5 || engineSet == null || !engineSet.isValid )) {
/*	|| (lastCheckProductionIndex != null && lastCheckProductionIndex != HogeAI.Get().GetEstimateProductionIndex(GetProduction())))) {このチェックは重いからやらない*/
			//HgLog.Warning("Check renewal."+this);
			//local c5 = PerformanceCounter.Start("c5");	
			local isAll = true;
			foreach(vehicle,_ in vehicleList) {
				if(((choosenEngine != null && choosenEngine != AIVehicle.GetEngineType(vehicle)) 
							|| (HogeAI.Get().IsEnableVehicleBreakdowns() && AIVehicle.GetAgeLeft(vehicle) <= 600) )) {
					AppendRemoveOrder(vehicle);
				} else {
					isAll = false;
				}
			}
			if(isAll) {
				local vehicle = BuildVehicle();
				if(vehicle != null) {
					CloneVehicle(vehicle);
				}
			}
			//c5.Stop();	
		}	
		if(showLog) {
			HgLog.Info("maxVehicles "+maxVehicles+" "+this);
		}
		if(vehicleList.Count() >= maxVehicles) {
			return;
		}
		
		
		//local bottomWaiting = max(min(200, HogeAI.Get().roiBase ? capacity * 6 : capacity), 10);
		/*
		if(HogeAI.Get().roiBase && IsBiDirectional() && AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo) < bottomWaiting && vehicleList.Count()>=4) {
			return;
		}*/
		
		//local c6 = PerformanceCounter.Start("c6");	
		local needsProduction = vehicleList.Count() < 10 ? 10 : 100; //= min(4,maxVehicles / 2 + 1) ? capacity : bottomWaiting;
		if(showLog) {
			HgLog.Info("needsProduction "+needsProduction+" "+this);
		}
		if(AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo) > needsProduction 
				|| (vehicleList.Count()==0 && (!isTransfer || needsAddtinalProducing))) {
			local vehicles = vehicleList;
			if(!ExistsWaiting(vehicles)) {
				local latestVehicle = null;
				foreach(v,_ in vehicleList) {
					if(AIVehicle.GetEngineType(v) == choosenEngine) {
						latestVehicle = v;
						break;
					}
				}

				local firstBuild = 0;
				
				if(latestVehicle == null) {
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
					if(capacity == 0) {
						HgLog.Warning("AIVehicle.GetCapacity("+AIVehicle.GetName(latestVehicle)+":"+AIEngine.GetName(AIVehicle.GetEngineType(latestVehicle))+")==0."+this);
						//c6.Stop();
						return; // capacity0の乗り物を増やしてもしょうがない
					}
					local cargoWaiting = max(0, AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo)/* - bottomWaiting*/);
					if(showLog) {
						HgLog.Info("cargoWaiting:"+cargoWaiting+" capacity:"+capacity+" "+this);
					}
					/*
					local buildNum;
					if(IsBiDirectional()) {
						local destWaiting = max(0, AIStation.GetCargoWaiting(destHgStation.GetAIStation(),cargo);
						if(destWaiting < cargoWaiting || destWaiting < capacity) {
							buildNum = destWaiting / capacity;
						} else {
							buildNum = max(1, cargoWaiting / capacity);
						}
					} else {
						buildNum = max(1, cargoWaiting / capacity);
					}*/
					local buildNum = (vehicleList.Count()==0 && (!isTransfer || needsAddtinalProducing)) ? 1 : cargoWaiting / capacity;
					buildNum = min(maxVehicles - vehicles.Count(), buildNum) - firstBuild;
					if(!IsSupportMode()) {
						buildNum = min(buildNum, 4);
					}
					//if(HogeAI().Get().roiBase) {
					//	buildNum = min(buildNum, max(1, (maxVehicles - vehicles.Count())/8));
					//}
					//buildNum = min(buildNum, 8);
					if(IsTownTransferRoute()) {
						buildNum = min(1,buildNum);
					}
					if(showLog) {
						HgLog.Info("buildNum "+buildNum+" "+this);
					}
					
					//HgLog.Info("CloneVehicle "+buildNum+" "+this);
					if(buildNum >= 1) {
						foreach(v,_ in inDepot) {
							if(choosenEngine == AIVehicle.GetEngineType(v) 
									&& (!HogeAI.Get().IsEnableVehicleBreakdowns() || AIVehicle.GetAgeLeft(v) >= 1000)) {
								AIVehicle.StartStopVehicle(v);
								buildNum --;
								if(buildNum == 0) {
									break;
								}
							} else {
								CommonRoute.vehicleStartDate.rawdelete(v);
								AIVehicle.SellVehicle(v);
							}
						}
						if(buildNum >= 1 && depot != null) {
							foreach(v,_ in AIVehicleList_Depot(depot)) { // 共通のdepotに他のgroupの使えるvehicleがいるかも
								if(AIVehicle.IsStoppedInDepot(v) 
										&& choosenEngine == AIVehicle.GetEngineType(v)
										&& (!HogeAI.Get().IsEnableVehicleBreakdowns() || AIVehicle.GetAgeLeft(v) >= 1000)) {
									AIOrder.ShareOrders(v, latestVehicle);
									AIGroup.MoveVehicle(vehicleGroup, v);
									StartVehicle(v);
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
		//c6.Stop();
	}
	
	function ExistsWaiting(vehicles) {
		if(GetVehicleType() == AIVehicle.VT_ROAD) {/*
			local srcStationId = srcHgStation.GetAIStation();
			local destStationId = destHgStation.GetAIStation();
			local isBiDirectional = IsBiDirectional();*/

			local list = AIList();
			list.AddList(vehicles);
			list.Valuate(AIVehicle.GetState);
			list.RemoveValue(AIVehicle.VS_CRASHED);
			list.Valuate(AIVehicle.GetCurrentSpeed);
			list.KeepValue(0);
			return list.Count() >= 1;
/*			
			foreach(v,_ in list) {
				if(AIVehicle.GetState(v) == AIVehicle.VS_AT_STATION) {
					return true;
				}
				local location = AIVehicle.GetLocation(v);
				local stationId = AIStation.GetStationID(location);
				if(AIStation.IsValidStation(stationId)) {
					if(srcStationId == stationId) {
						return true;
					}
					if(isBiDirectional && destStationId == stationId) {
						return true;
					}
				}
				if(AIVehicle.GetState(v) != AIVehicle.VS_CRASHED && AIVehicle.GetCurrentSpeed(v) == 0) {
					return true;
				}
			}*/
		} else {
			local list = AIList();
			list.AddList(vehicles);
			list.Valuate(AIVehicle.GetState);
			list.KeepValue(AIVehicle.VS_AT_STATION);
			return list.Count() >= 1;
		}	
		return false;
	}
	
	function Demolish() {
		// override必要
	}

	function Remove() {
		if(IsBuilding()) {
			HgLog.Warning("Cannot Remove Route (IsBuilding == true) "+this);
			return;
		}
		isClosed = true;
		isRemoved = true;
		SendAllVehiclesToDepot();
	}
	
	function RemoveFinished() {
		HgLog.Warning("RemoveFinished: "+this);
		if(srcHgStation.place != null && (destHgStation.place != null || destHgStation.stationGroup != null)) {
			Place.AddNgPathFindPair(srcHgStation.place, 
					destHgStation.place != null ? destHgStation.place : destHgStation.stationGroup, GetVehicleType(), 365*10);
		}
		PlaceDictionary.Get().RemoveRoute(this);
		ArrayUtils.Remove(getclass().instances, this);
		if(HogeAI.Get().IsInfrastructureMaintenance()) {
			Demolish();
		}
		srcHgStation.RemoveIfNotUsed();
		destHgStation.RemoveIfNotUsed();
	}
	
	function Close() {
		isClosed = true;
//		if(!HogeAI.Get().ecs) {
			SendAllVehiclesToDepot();
//		}
	}
	
	function ReOpen() {
		isRemoved = false;
		isClosed = false;
		this.maxVehicles = GetMaxVehicles(); // これで良いのだろうか？
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		PlaceDictionary.Get().AddRoute(this);
		HgLog.Warning("Route ReOpen."+this);
	}
	
	function SendAllVehiclesToDepot() {
		foreach(vehicle,_ in GetVehicleList()) {
			AppendRemoveOrder(vehicle);
/*			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
				AIVehicle.SendVehicleToDepot (vehicle);
			}*/
		}
	}
	
	function CheckRenewal() {
		local c = PerformanceCounter.Start("CheckRenewal");	
		_CheckRenewal();
		c.Stop();
	}
	
	// tmpClose: 一時的に受け入れが拒否されている remove:　削除シーケンスへ入った
	function _CheckRenewal() {
		local execMode = AIExecMode();
		
		if(isRemoved) {
			return;
		}
	
		
		/* やらない方がパフォーマンスが良い
		if(HogeAI.Get().buildingTimeBase && AIBase.RandRange(100) < 10) {
			CheckNewRoute();
		}*/
		
		CheckClose();
	}
	
	function CheckNewRoute() {
		if(GetVehicleType() != AIVehicle.VT_WATER) {
			return;
		}
		local src = srcHgStation.stationGroup;
		local dest = destHgStation.stationGroup;
		local key = src.id + "-" + dest.id;
		if(Route.checkedNewRoute.rawin(key)) {
			return;
		}
		Route.checkedNewRoute.rawset(key,true);

		HgLog.Info("CheckNewRoute "+this);
		foreach(cargo,_ in AICargoList()) {
			if(cargo == this.cargo) {
				continue;
			}
			if(dest.IsAcceptingCargo(cargo)) {
				CreateNewRoute(dest, src, cargo, GetPath());
			} else if(src.IsAcceptingCargo(cargo)) {
				CreateNewRoute(src, dest, cargo, GetPath().Reverse());
			}
		}
	}
	
	function CreateNewRoute(dest, src, cargo, path) {
		local srcIsProducing = src.IsProducingCargo(cargo);
		local routeBuilder = GetBuilderClass()(dest, src, cargo, { 
			transfer = dest.IsCargoDeliverFromHere(cargo)
			checkSharableStationFirst = true
			path = path
			isWaitingProduction = !srcIsProducing
			production = !srcIsProducing ? 100 : null
			searchTransfer = false
		});
		if(routeBuilder.ExistsSameRoute()) {
			HgLog.Info("CreateNewRoute ExistsSameRoute:"+routeBuilder+" from "+this);
			return;
		}
		HgLog.Info("CreateNewRoute:"+routeBuilder+" "+this);
		local newRoute = routeBuilder.Build();
		if(newRoute != null) {
			HgLog.Info("CreateNewRoute succeeded:"+newRoute+" from "+this);
		} else {
			HgLog.Warning("CreateNewRoute failed:"+newRoute+" from "+this);
		}
	}
}


class RouteBuilder {
	dest = null;
	src = null;
	cargo = null;
	options = null;
	
	destStationGroup = null;
	destPlace = null;
	srcStationGroup  = null;
	srcPlace = null;
	isBiDirectional = null;
	
	builtRoute = null;
	supportRoutes = null;
	routePlans = null;
	needsToMeetDemand = null;
	
	constructor(dest, src, cargo, options = {}) {
		this.options = options;
		this.dest = dest;
		if(dest instanceof StationGroup) {
			this.destStationGroup = dest;
		} else if(dest instanceof Place) {
			this.destPlace = dest;
		} else {
			HgLog.Warning("Illegal parameter type dest "+typeof dest);
		}
		this.src = src;
		if(src instanceof StationGroup) {
			this.srcStationGroup = src;
		} else if(src instanceof Place) {
			this.srcPlace = src;
		} else {
			HgLog.Warning("Illegal parameter type src "+typeof src);
		}
		this.cargo = cargo;
		this.isBiDirectional = !IsTransfer() && dest.IsAcceptingAndProducing(cargo) && src.IsAcceptingAndProducing(cargo);
		this.routePlans = SortedList( function(plan){ return plan.value; } );
	}
	
	function GetOption(name, defaultValue) {
		if( options.rawin(name) ){
			return options.rawget(name);
		} else {
			return defaultValue;
		}
	}
	
	function GetLabel() {
		return GetRouteClass().GetLabel();
	}
	
	function GetVehicleType() {
		return GetRouteClass().GetVehicleType();
	}

	function ExistsSameRoute() {
		return Route.SearchRoutes( Route.GetRouteWeightingVt(GetVehicleType()), src, dest, cargo ).len() >= 1;
	}
	
	function GetDestLocation() {
		if(destStationGroup != null) {
			return destStationGroup.hgStations[0].platformTile;
		} else {
			return destPlace.GetLocation();
		}
	}
	
	function CheckClose() {
		if(srcPlace != null && srcPlace.IsClosed()) {
			HgLog.Warning("RouteBuilder.Build failed.(srcPlace closed)"+this);
			return true;
		}
		if(destPlace != null && destPlace.IsClosed()) {
			HgLog.Warning("RouteBuilder.Build failed.(destPlace closed)"+this);
			return true;
		}
		if(destStationGroup != null && destStationGroup.hgStations.len() == 0) {
			HgLog.Warning("RouteBuilder.Build failed.(destStationGroup removed)"+this);
			return true;
		}
		
		return false;
	}
	
	function Build() {
		if(CheckClose()) {
			return null;
		}
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
		
		if(Place.IsNgPathFindPair(src, dest, vehicleType)) {
			HgLog.Warning("IsNgPathFindPair==true "+this);
			return null;
		}
		if(Place.IsNgPlace(dest, cargo, vehicleType)) {
			HgLog.Warning("dest is ng facility."+this);
			return null;
		}
		if(Place.IsNgPlace(src, cargo, vehicleType)) {
			HgLog.Warning("src is ng facility."+this);
			return null;
		}
		if(srcPlace != null && !PlaceDictionary.Get().CanUseAsSource(srcPlace, cargo)) {
			HgLog.Warning("src is used."+this);
			return null;
		}
		if(vehicleType == AIVehicle.VT_WATER) {
			if(!WaterRoute.CanBuild(src,dest,cargo)) {
				HgLog.Warning("!WaterRoute.CanBuild."+this);
				return null;
			}
		}

		needsToMeetDemand = false;
		local isTransfer = IsTransfer();
		local pendingToDoPostBuild = GetOption("pendingToDoPostBuild",false);
		
		supportRoutes = [];
		
		if(srcPlace != null && !GetOption("notNeedToMeetDemand",false)) {
			// if( HogeAI.Get().firs ) {
				// if(srcPlace.IsIncreasable()) {
					// HgLog.Warning("RouteBuilder.Build firs "+srcPlace.GetName()+" "+this);
					// if(srcPlace.IsProcessing()) {
						// foreach(cargo in srcPlace.GetNotToMeetCargos()) {
							// HgLog.Warning("RouteBuilder.Build GetNotToMeetCargos "+AICargo.GetName(cargo)+" "+srcPlace.GetName()+" "+this);
							// needsToMeetDemand = true;
							// local cargoPlan = {
								// place = srcPlace.GetAccepting()
								// cargo = cargo
							// };
							// local routePlans = SortedList(function(plan) {
								// return plan.estimate.value; /*-plan.estimate.buildingTime;*/
							// });
							// routePlans.Extend( HogeAI.Get().CreateRoutePlans(cargoPlan,null/*,{useLastMonthProduction=true}*/) );
							// HogeAI.Get().DoRoutePlans( routePlans, {capacity = 1}, {searchTransfer = false,notNeedToMeetDemand=true,useLastMonthProduction=true} );
						// }
					// } else {
						// if( srcPlace.GetToMeetCargos().len() == 0 ) {
							// supportRoutes.extend( HogeAI.Get().SearchAndBuildToMeetSrcDemandMin( srcPlace, null, {capacity = 1},
								// {searchTransfer = false,notNeedToMeetDemand=true,useLastMonthProduction=true}));
						// }
					// }
				// }
			// } else {
				local currentProduction = srcPlace.GetLastMonthProduction( cargo );
				if(currentProduction<200 || currentProduction < srcPlace.GetExpectedProduction( cargo, GetVehicleType())) {
					needsToMeetDemand = true;
				}
				if(needsToMeetDemand && currentProduction<50) {
					// 場所がなくなる可能性があるので少量生産以外は後からやる
					local routePlans = GetOption("routePlans", null);
					if(routePlans == null) {
						routePlans = HogeAI.Get().GetSortedRoutePlans([]); // optionsにnullがセットされている事があるので
					}
					supportRoutes.extend( HogeAI.Get().SearchAndBuildToMeetSrcDemandMin( srcPlace, null, 
						{capacity = 1}, 
						{searchTransfer = false, routePlans = routePlans, noDoRoutePlans = true}));
					if(supportRoutes.len() == 0 && currentProduction == 0) {
						HgLog.Warning("RouteBuilder.Build failed (SearchAndBuildToMeetSrcDemandMin failed)"+this);
						return null;
					}
				}
			// }
		}
		if(CheckClose()) {
			return null;
		}
		local distance  = AIMap.DistanceManhattan(src.GetLocation(),dest.GetLocation());
		HgLog.Info("# RouteBuilder Start "+this+" distance:"+distance);
		local start = AIDate.GetCurrentDate();
		builtRoute = DoBuild();
		local span = AIDate.GetCurrentDate() - start;
		if(builtRoute == null) {
			HgLog.Info("# RouteBuilder Failed "+vehicleType+" "+span+" "+distance+" "+this);
			return null;
		}
		HgLog.Info("TimeValue " + builtRoute.GetLatestEngineSet().buildingTime + " " + HogeAI.Get().GetQuarterlyIncome(4));
		HgLog.Info("# RouteBuilder Succeeded "+vehicleType+" "+span+" "+distance+" "+this);
		if(CheckClose()) {
			return null;
		}
		if(!pendingToDoPostBuild) {
			DoPostBuild();
		}

		
		return builtRoute;
		
	}
	
	function DoPostBuild() {
		if(builtRoute == null) {
			return;
		}
		local engineSet = builtRoute.GetLatestEngineSet();
		if( engineSet == null ) {
			HgLog.Info("engineSet == null "+builtRoute);
			return;
		}
		
		local searchTransfer = GetOption("searchTransfer",true);
		local routePlans = GetOption("routePlans", null);
		if(routePlans == null) {
			routePlans = HogeAI.Get().GetSortedRoutePlans([]); // optionsにnullがセットされている事があるので
		}
		local noDoRoutePlans = GetOption("noDoRoutePlans",false);
		
		local vehicleType = GetVehicleType();
		builtRoute.isBuilding = true;// resultのrouteはまだ不完全な場合がある。(WaterRouteBuilder.BuildCompoundRoute)
		local limit = builtRoute.GetMaxRouteCapacity( cargo );
		
		if(searchTransfer && !GetOption("noExtendRoute",false) && !IsTransfer()) { // 延長チェック
			if(!builtRoute.cannotChangeDest && vehicleType == AIVehicle.VT_RAIL) {
				local extendsRoute = HogeAI.Get().SearchAndBuildAdditionalDestAsFarAsPossible(builtRoute);
				/*
				if(extendsRoute && !builtRoute.IsChangeDestination()) {
					HogeAI.Get().SearchAndBuildTransferRoute( builtRoute, {
//						notTreatDest = true
						useLastMonthProduction = true });
				}*/
			}
	/*		
			if(builtRoute.IsBiDirectional()) {
				HogeAI.Get().SearchAndBuildTransferRoute( builtRoute, {
					destOnly = true
					useLastMonthProduction = true });
			}*/

		}
		
		/*
		if(searchTransfer && !IsTransfer()) {
			routePlans.Extend( HogeAI.Get().GetTransferCandidates(builtRoute, {
				notTreatDest = GetVehicleType() == AIVehicle.VT_RAIL
				useLastMonthProduction = true }));
		}*/
		builtRoute.ChooseEngineSet(); // engineSetを最新に更新
		HgLog.Info("MaxRouteCapacity:"+limit+" "+builtRoute);
		if(srcPlace != null) {
			limit -= srcPlace.GetCurrentExpectedProduction( cargo, vehicleType, true );
			HgLog.Info("remainCapacity:"+limit+" "+builtRoute);
		}
		if(!GetOption("notNeedToMeetDemand",false) && limit > 0 && srcPlace != null) {
			if(CheckClose()) {
				builtRoute.isBuilding = false;
				return;
			}
			foreach(route in supportRoutes) { // 本線建設前に作ったルート
				limit -= route.GetTotalDelivableProduction() / 2;
				routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( route )));
				HgLog.Info("remainCapacity:"+limit+" "+builtRoute);
			}
			routePlans.Extend( ShowPlansLog( HogeAI.Get().GetMeetPlacePlans( srcPlace, builtRoute ) ) );
			/*
			
			local newRoutes = HogeAI.Get().SearchAndBuildToMeetSrcDemandMin( srcPlace, builtRoute, 
					builtRoute.GetMaxRouteCapacity( cargo ) - srcPlace.GetLastMonthProduction( cargo ) - deliver, 
					{ searchTransfer = false } );
			supportRoutes.extend( newRoutes	);*/
		}
		if(searchTransfer) {
			routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( builtRoute, 
				{ notTreatDest = true, noCheckNeedsAdditionalProducing = true } )));
		}
		local value = engineSet.value;
		if(limit > 0 && !noDoRoutePlans) {
			if(CargoUtils.IsPaxOrMail(cargo)) {
				limit /= 6;
			}
			HogeAI.Get().DoRoutePlans( routePlans, 
				{ capacity = limit / 2, value = value },
				{ routePlans = routePlans, noDoRoutePlans = true } );
		}
		if(searchTransfer && !builtRoute.cannotChangeDest && vehicleType == AIVehicle.VT_RAIL) {
			local returnRoute = HogeAI.Get().CheckBuildReturnRoute(builtRoute, value);
			if(returnRoute != null) {
				routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( returnRoute, 
					{ noCheckNeedsAdditionalProducing = true } ) ) );
			}
		}
		if(isBiDirectional) {
			local destPlace = builtRoute.destHgStation.place;
			local limit = builtRoute.GetCurrentRouteCapacity(cargo);
			if(destPlace != null) {
				limit -= destPlace.GetCurrentExpectedProduction(cargo, vehicleType, true);
			}
			if(CargoUtils.IsPaxOrMail(cargo)) {
				limit /= 3;
			}
			local transferCandidates = HogeAI.Get().GetTransferCandidates( builtRoute, 
				{ destOnly = true } )
			if(noDoRoutePlans) {
				routePlans.Extend( ShowPlansLog(transferCandidates) );
			} else {
				local revRoutePlans = HogeAI.Get().GetSortedRoutePlans(transferCandidates);
				HogeAI.Get().DoRoutePlans(revRoutePlans ,
					{ capacity = limit, value = value },
					{ routePlans = revRoutePlans, noDoRoutePlans = true } );	
			}
			
				
			
		}

		/* どこかのタイミングで対向のtransferチェックする。scanplaceかな？
		if(IsTransfer()) {
			local destRoute = builtRoute.GetDestRoute();
			if(destRoute != false && destRoute.IsBiDirectional()) {
				local isDest = builtRoute.destHgStation.stationGroup == destRoute.destHgStation.stationGroup;
				if(destRoute.GetDestStationGroup(isDest).GetExpectedProduction(cargo,destRoute.GetVehicleType(),true) == 0) {
					HogeAI.Get().SearchAndBuildTransferRoute( destRoute, { isDest = isDest, cargo = cargo });
				}
			}
		}*/
		/*
		foreach(supportRoute in supportRoutes) {
			if(CheckClose()) {
				builtRoute.isBuilding = false;
				return null;
			}
			HogeAI.Get().SearchAndBuildTransferRoute( supportRoute, {
				notTreatDest = true 
				useLastMonthProduction = true });
		}*/
		builtRoute.isBuilding = false;
	}
	
	function ShowPlansLog( plans ) {
		foreach(e in HogeAI.Get().GetSortedRoutePlans(plans).GetAll()) {
			HgLog.Info("RouteBuilder:"+e.estimate+" "+e.dest.GetName()+"<-"+e.src.GetName());
		}
		return plans;
	}
	
	function IsTransfer() {
		return options.rawin("transfer") ? options.transfer : (dest instanceof StationGroup);
	}
	
	function _tostring() {
		return "Build "+GetLabel()+"Route " + (IsTransfer() ? "T:" : "") +dest+"<-"+(isBiDirectional?">":"")+src+" "+AICargo.GetName(cargo);
	}
}

class CommonRouteBuilder extends RouteBuilder {
	makeReverseRoute = null;
	isNotRemoveStation = null;
	isNotRemoveDepot = null;
	checkSharableStationFirst = null;
	sharableStationOnly = null;
	retryIfNoPathUsingSharableStation = null;
	retryUsingSharableStationIfNoPath = null;
	
	
	constructor( dest, src, cargo, options = {} ) {
		RouteBuilder.constructor(dest, src, cargo, options );
		makeReverseRoute = GetOption("makeReverseRoute",false);
		isNotRemoveStation = GetOption("isNotRemoveStation",false);
		isNotRemoveDepot = GetOption("isNotRemoveDepot",false);
		checkSharableStationFirst = GetOption("checkSharableStationFirst",false);
		sharableStationOnly = GetOption("sharableStationOnly",false);
		retryIfNoPathUsingSharableStation = false;
		retryUsingSharableStationIfNoPath = false;
	}
			
	function DoBuild() {


		if(destStationGroup != null && destStationGroup.hgStations.len() == 0) {
			HgLog.Error("destStationGroup.hgStations.len() == 0 "+this);
			return null;
		}
		/*
		if(!(dest instanceof StationGroup) && vehicleType == AIVehicle.VT_WATER) {
			local currentProduction = srcPlace.GetLastMonthProduction(cargo);
			if(currentProduction==0 || currentProduction < srcPlace.GetExpectedProduction(cargo, vehicleType)) {
				HogeAI.Get().SearchAndBuildToMeetSrcDemandMin(srcPlace);
			}
		}*/

		local buildPathBeforeStation = false; //GetOption("buildPathBeforeStation",false);
		local path = GetOption("path",null);
		local noDepot = GetOption("noDepot",false);
		local isWaitingProduction = GetOption("isWaitingProduction",false);
		local production = GetOption("production",null);
		if(retryIfNoPathUsingSharableStation) {
			checkSharableStationFirst = true;
		}
		
		local routeClass = GetRouteClass();
		local vehicleType = GetVehicleType();
		
		local distance = AIMap.DistanceManhattan( src.GetLocation(), dest.GetLocation() );
		if(production == null) {
			production = src.GetExpectedProduction( cargo, vehicleType );
		}
		local infrastractureTypes = routeClass.GetSuitableInfrastractureTypes( src, dest, cargo);
		local engineSet = Route.Estimate(vehicleType, cargo, distance, production, isBiDirectional, infrastractureTypes);
		HgLog.Info("CommonRouteBuilder isBiDirectional:"+isBiDirectional+" production:"+production+" distance:"+distance+" "+this);
		if(engineSet==null) {
			HgLog.Warning("No suitable engine. "+this);
			return null;
		}
		BuildStart(engineSet);
		
		local testMode = AITestMode();
		local destStationFactory = CreateStationFactory(dest);
		destStationFactory.isBiDirectional = isBiDirectional
		local destHgStation = null;
		local isShareDestStation = false;
		if(checkSharableStationFirst) {
			destHgStation = SearchSharableStation(dest, destStationFactory.GetStationType(), cargo, true, 
				vehicleType == AIVehicle.VT_AIR ? infrastractureType : null);
			if(destHgStation != null) {
				isShareDestStation = true;
			}
		}
		local isNearestForPair = 
				((HogeAI.Get().IsInfrastructureMaintenance() || (destPlace != null && destPlace instanceof TownCargo))
					&& vehicleType == AIVehicle.VT_ROAD) // 街の中心部を通ると渋滞に巻き込まれる為
				|| (destPlace != null && destPlace instanceof HgIndustry && vehicleType == AIVehicle.VT_WATER)
		if(destHgStation == null) {
			if(destPlace != null && isNearestForPair) {
				destStationFactory.nearestFor = src.GetLocation();
			}
			destHgStation = destStationFactory.CreateBest( dest, cargo, src.GetLocation() );
		}
		if(destHgStation == null) {
			destHgStation = SearchSharableStation(dest, destStationFactory.GetStationType(), cargo, true);
			if(destHgStation != null) {
				isShareDestStation = true;
			}
		}
		if(destHgStation == null) {
			if(vehicleType != AIVehicle.VT_WATER) { // CompoundRouteがあるのでNgPlaceにはしない
				Place.AddNgPlace(dest, cargo, vehicleType);
			}
			HgLog.Warning("No destStation."+this);


			return null;
		}
		local list = HgArray(destHgStation.GetTiles()).GetAIList();
		local srcStationFactory = CreateStationFactory(src);
		srcStationFactory.isBiDirectional = isBiDirectional;
		HogeAI.notBuildableList.AddList(list);
		if(destPlace != null && isNearestForPair) {
			srcStationFactory.nearestFor = destHgStation.platformTile;
		}
		local srcHgStation = null
		local isShareSrcStation = false;
		if(checkSharableStationFirst) {
			srcHgStation = SearchSharableStation(src, srcStationFactory.GetStationType(), cargo, false,
				vehicleType == AIVehicle.VT_AIR ? infrastractureType : null);
			if(srcHgStation != null) {
				isShareSrcStation = true;
			} 
		}
		if(srcHgStation == null) {
			srcHgStation = srcStationFactory.CreateBest(src, cargo, destHgStation.platformTile);
		}
		HogeAI.notBuildableList.RemoveList(list);
		if(srcHgStation == null) {
			srcHgStation = SearchSharableStation(src, srcStationFactory.GetStationType(), cargo, false);
			if(srcHgStation != null) {
				isShareSrcStation = true;
			}
		}
		if(srcHgStation == null) {
			if(vehicleType != AIVehicle.VT_WATER) { // CompoundRouteがあるのでNgPlaceにはしない
				Place.AddNgPlace(src, cargo, vehicleType);
			}
			HgLog.Warning("No srcStation."+this);
			return null;
		}
		if(sharableStationOnly && (!isShareSrcStation && !isShareDestStation)) {
			HgLog.Warning("No Sharable station."+this);
			return null;
		}

		{
			local execMode = AIExecMode();
			local rollbackFacitilies = [];
			if((destHgStation instanceof WaterStation) && (srcHgStation instanceof WaterStation)) {
				buildPathBeforeStation = true;
			}
			
			
			if(isShareDestStation) {
				HgLog.Info("Share dest station:"+destHgStation.GetName()+" "+this);
				if(!destHgStation.Share()) {
					HgLog.Warning("destHgStation.Share failed."+this);
					return null;
				}
			} else if(!buildPathBeforeStation && !destHgStation.BuildExec()) {
				HgLog.Warning("destHgStation.BuildExec failed."+HgTile(destHgStation.platformTile)+" "+this);
				destHgStation = SearchSharableStation(dest, destStationFactory.GetStationType(), cargo, true);
				if(destHgStation == null || !destHgStation.Share()) {
					return null;
				}
				HgLog.Info("Share dest station:"+destHgStation.GetName()+" "+this);
				isShareDestStation = true;
			}
			if(!isShareDestStation && !isNotRemoveStation && !buildPathBeforeStation) {
				rollbackFacitilies.push(destHgStation);
			}
			
			if(isShareSrcStation) {
				HgLog.Info("Share src station:"+srcHgStation.GetName()+" "+this);
				if(!srcHgStation.Share()) {
					HgLog.Warning("srcHgStation.Share failed."+this);
					return null;
				}
			} else if(!buildPathBeforeStation && !srcHgStation.BuildExec()) {
				HgLog.Warning("srcHgStation.BuildExec failed."+this);
				srcHgStation = SearchSharableStation(src, srcStationFactory.GetStationType(), cargo, false);
				if(srcHgStation == null || !srcHgStation.Share()) {
					Rollback(rollbackFacitilies);
					return null;
				}
				HgLog.Info("Share src station:"+srcHgStation.GetName()+" "+this);
				isShareSrcStation = true;
			}
			if(!isShareSrcStation && !isNotRemoveStation && !buildPathBeforeStation) {
				rollbackFacitilies.push(srcHgStation);
			}
			
			if(!buildPathBeforeStation && srcHgStation.stationGroup == destHgStation.stationGroup) {
				Place.AddNgPathFindPair(src, dest, vehicleType);
				HgLog.Warning("Same stationGroup."+this);
				Rollback(rollbackFacitilies);
				return null;
			}
			if(path == null) {
				local pathBuilder = CreatePathBuilder(engineSet.engine, cargo);
				if(!pathBuilder.BuildPath( destHgStation.GetEntrances(), srcHgStation.GetEntrances())) {
					if(retryIfNoPathUsingSharableStation && (isShareSrcStation || isShareDestStation)) {
						HgLog.Warning("retryIfSharableStation."+this);
						retryIfNoPathUsingSharableStation = false;
						checkSharableStationFirst = false;
						return DoBuild();
					}


					if(retryUsingSharableStationIfNoPath && !sharableStationOnly) {
						HgLog.Warning("BuildPath failed.retryBySharableStationOnlyIfPathNotFound"+this);
						sharableStationOnly = true;
						checkSharableStationFirst = true;
						Rollback(rollbackFacitilies);
						return DoBuild();
					}
				
					HgLog.Warning("BuildPath failed."+this);
					Place.AddNgPathFindPair(src, dest, vehicleType);
					Rollback(rollbackFacitilies);
					return null;
				}
				path = pathBuilder.path;
				local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile)
				if(path != null && distance > 40 && distance * 2 < path.GetTotalDistance(vehicleType)) {
					Place.AddNgPathFindPair(src, dest, vehicleType);
					HgLog.Warning("Too long path distance."+this);
					Rollback(rollbackFacitilies);
					return null;
				}
			}
			if(buildPathBeforeStation) {
				if(!isShareSrcStation) {
					if(!srcHgStation.BuildExec()) {
						HgLog.Warning("srcHgStation.BuildExec failed."+this);
						Rollback(rollbackFacitilies);
						return null;
					}
					if(!isNotRemoveStation) {
						rollbackFacitilies.push(srcHgStation);
					}					
				}
				if(!isShareDestStation) {
					if(!destHgStation.BuildExec()) {
						HgLog.Warning("destHgStation.BuildExec failed."+this);
						Rollback(rollbackFacitilies);
						return null;
					}
					if(!isNotRemoveStation) {
						rollbackFacitilies.push(destHgStation);
					}					
				}
			}
			
			if(srcHgStation.stationGroup == null || destHgStation.stationGroup == null) {
				HgLog.Warning("Station was removed."+this); // 稀にDoInterval中にstationがRemoveされる事がある。
				Rollback(rollbackFacitilies);
				return null;
			}
			local route = routeClass();
			route.cargo = cargo;
			route.srcHgStation = srcHgStation;
			route.destHgStation = destHgStation;
			route.isTransfer = IsTransfer();		
			route.isBiDirectional = isBiDirectional;
			route.isWaitingProduction = isWaitingProduction;
			route.Initialize();
			
			if(!noDepot) {
				if(!route.BuildDepot(path)) {
					Place.AddNgPathFindPair(src, dest, vehicleType);
					HgLog.Warning("BuildDepot failed."+this);
					Rollback(rollbackFacitilies);
					return null;
				}
				if(!isNotRemoveDepot) {
					rollbackFacitilies.push(route.depot);
				}
				route.BuildDestDepot(path);
				if(!isNotRemoveDepot && route.destDepot != null) {
					rollbackFacitilies.push(route.destDepot);
				}
			}
			route.SetPath(path);
			PlaceDictionary.Get().AddRoute(route);
			route.UpdateSavedData();
			route.instances.push(route); // ChooseEngine内、インフラコスト計算に必要
			if(!isWaitingProduction) {
				local vehicle = route.BuildVehicle();
				if(vehicle==null) {
					route.instances.pop();
					PlaceDictionary.Get().RemoveRoute(route);
					Place.AddNgPathFindPair(src, dest, vehicleType, 365*10);
					HgLog.Warning("BuildVehicle failed."+this);
					Rollback(rollbackFacitilies);
					route.Demolish();
					return null;
				}
				local reverseRoute = null;
				if(makeReverseRoute && route.IsBiDirectional()) {
					reverseRoute = BuildReverseRoute(route, path);
				}
				if(reverseRoute == null) {
					route.CloneVehicle(vehicle);
				}
				//Place.SetUsedPlaceCargo(src,cargo); NgPathFindPairで管理する
			} else {
				route.SetLatestEngineSet(engineSet);
			}
			HgLog.Info("CommonRouteBuilder.Build succeeded."+route);
			
			/* 時間が経ってから調べた方が良い(必要ないかもしれない)
			if(!route.IsTransfer()) {
				HogeAI.Get().SearchAndBuildTransferRoute(route);
			}*/
			return route;
			
		}
	}
	
	function DoPostBuild() {
		if(builtRoute == null) {
			return;
		}
	
		//AirRoute作成は空いているうちに迅速にやらないといけないので時間がかかる処理は後回し
		if(CargoUtils.IsPaxOrMail(cargo)) {
			local execMode = AIExecMode();
			CheckTownTransfer(builtRoute, builtRoute.srcHgStation);
			CheckTownTransfer(builtRoute, builtRoute.destHgStation);
		}
		RouteBuilder.DoPostBuild();
	}
	
	function CheckTownTransferCargo(route, station, cargo) {
		if(station.place == null || !(station.place instanceof TownCargo) || route.IsTownTransferRoute()) {
			return;
		}
		if(route.HasCargo(cargo)) {
			local townBus;
			townBus = TownBus.CheckTown(station.place.town, null, cargo);
			if(townBus == null) {
				HgLog.Info("Cannot get TownBus:"+station.place.GetName()+"["+AICargo.GetName(cargo)+"]");
			} else {
				townBus.CreateTransferRoutes(route, station);
			}
		}
	}

	function CheckTownTransfer(route, station) {
		CommonRouteBuilder.CheckTownTransferCargo(route,station,HogeAI.GetPassengerCargo());
		CommonRouteBuilder.CheckTownTransferCargo(route,station,HogeAI.GetMailCargo());
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
		reverseRoute.UpdateSavedData();
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
			if(stationType == AIStation.STATION_TRUCK_STOP && !isAccepting) {
				if(station.cargo != cargo && station.place.IsProducing()) { // Roadで異なるcargoを1つのstationでは受けると詰まってwaitingしているcargoのvehicleが量産される。
					continue;
				}
			}
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
			return AIRail.GetMaintenanceCostFactor(railType) * 4;
		}
		CheckCache();
		if(railTypeCostCache.rawin(railType)) {
			return railTypeCostCache[railType];
		}
		local result;
		local distance = 0;
		foreach(route in TrainRoute.GetTrainRoutes(railType)) {
			distance += route.GetDistance() / (route.IsSingle() ? 2 : 1);
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
			return [0,AIRoad.GetMaintenanceCostFactor(roadType)* 2];
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
			result = AIRoad.GetMaintenanceCostFactor(roadType) * 2;
		} else {
			result = AIInfrastructure.GetMonthlyRoadCosts (AICompany.COMPANY_SELF, roadType) * 12 / distance;
		}
		roadTypeCostCache[roadType] <- [distance,result];
		//HgLog.Info("GetCostPerDistanceRoad distance:"+distance+" cost/d:"+result);
		return [distance,result];
	}
	
	function GetCostPerAirport() {
		return GetCostPerPiece(AIInfrastructure.INFRASTRUCTURE_AIRPORT);
	}
	
	function GetCostPerRoad(roadType) {
		if(!HogeAI.Get().IsInfrastructureMaintenance()) {
			return 0;
		}
		local piece = AIInfrastructure.GetRoadPieceCount (AICompany.COMPANY_SELF, roadType);
		if(piece == 0) {
			return 0;
		}
		return AIInfrastructure.GetMonthlyRoadCosts (AICompany.COMPANY_SELF, roadType) * 12	/ piece;
	}
	
	function GetCostPerPiece(infrastractureType) {
		if(!HogeAI.Get().IsInfrastructureMaintenance()) {
			return 0;
		}
		local piece = AIInfrastructure.GetInfrastructurePieceCount(AICompany.COMPANY_SELF, infrastractureType);
		if(piece == 0) {
			return 0;
		}
		return AIInfrastructure.GetMonthlyInfrastructureCosts(AICompany.COMPANY_SELF, infrastractureType) * 12	/ piece;
	}

	
}
