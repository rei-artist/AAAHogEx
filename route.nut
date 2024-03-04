
class Route {
	static allVehicleTypes = [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_WATER, AIVehicle.VT_AIR];

	static allRoutes = {}
	static groupRoute = {}

	static availableVehicleTypesCache = ExpirationTable(30);
	static tooManyVehiclesForNewRouteCache = ExpirationTable(30);

	static function GetAvailableVehicleTypes() {
		if(Route.availableVehicleTypesCache.rawin(0)) {
			Route.availableVehicleTypesCache.rawget(0);
		}
		local result = [];
		foreach(vehicleType in Route.allVehicleTypes) {
			local routeClass = Route.Class(vehicleType);
			if(!routeClass.IsTooManyVehiclesForNewRoute(routeClass)) {
				result.push(vehicleType);
			}
		}
		Route.availableVehicleTypesCache.rawset(0,result);
		return result;
	}
	
	static function ExistsAvailableVehicleTypes(exceptVt = -1) {
		foreach(vehicleType in Route.allVehicleTypes) {
			if(vehicleType == exceptVt) continue;
			if(!Route.IsTooManyVehiclesForNewRouteRaw(vehicleType)) {
				return true;
			}
		}
		return false;
	}

	static function SearchRoutes( bottomRouteWeighting, src, dest, cargo ) {
		return HgArray(ArrayUtils.And(
			src.GetUsingRoutes(), dest.GetUsingRoutes())).Filter(
				function(route):(cargo, bottomRouteWeighting) {
					return route.HasCargo(cargo) && route.GetRouteWeighting() >= bottomRouteWeighting;
				}).array;
	}
	
	static function CanCreateRoute( vehicleType, src, dest ,cargo ) {
		local bottomRouteWeighting = Route.GetRouteWeightingVt(vehicleType);
		foreach(route in ArrayUtils.And(src.GetUsingRoutes(), dest.GetUsingRoutes())) {
			if( !route.IsOverflow(cargo) && route.GetRouteWeighting() > bottomRouteWeighting) {
				return false;
			}
		}
		return true;
	}
		
	static function Class(vehicleType) {
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
		HgLog.Warning("Not supported vehicleType(Class)"+vehicleType);
		return null;
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
			local routeClass = Route.Class(vehicleType);
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
	
	static idCounter = IdCounter();
	
	id = null;
	
	productionCargoCache = null;
	needsAdditionalCache = null;
	overflowCache = null;

	isBuilding = null;
	isTownTransferRoute = null;
	
	constructor() {
		id = idCounter.Get();
		productionCargoCache = ExpirationTable(30);
		needsAdditionalCache = ExpirationTable(30);
		overflowCache = ExpirationTable(30);
		isBuilding = false;
		allRoutes.rawset(id,this);
	}
	
	function Load(t) {
		allRoutes.rawdelete(id); // コンストラクタで仮発行されたidを削除
		id = t.id;
		idCounter.Skip(id);
		allRoutes.rawset(id,this);
	}

	function SaveTo(t) {
		t.id <- id;
	}

	function GetRouteClass() {
		return Route.Class(GetVehicleType());
	}
	
	function IsBuilding() {
		return isBuilding; // ネットワーク作成中なのでCheckClose()はまだしない
	}
	
	function CanCreateNewRoute() {
		return true;
	}

	function IsTooManyVehiclesForNewRoute(self) {
		local vt = self.GetVehicleType();
		if(Route.tooManyVehiclesForNewRouteCache.rawin(vt)) {
			return Route.tooManyVehiclesForNewRouteCache.rawget(vt);
		}
		local result = self._IsTooManyVehiclesForNewRoute(vt);
		Route.tooManyVehiclesForNewRouteCache.rawset(vt,result);
		return result;
	}
	
	function _IsTooManyVehiclesForNewRoute(vt) {
		local routeClass = Route.Class(vt);
		local remaining = routeClass.GetVehicleNumRoom(routeClass);
		if(!Route.ExistsAvailableVehicleTypes(vt) && remaining > 30) {
			return false;
		}
		return remaining <= routeClass.GetMaxTotalVehicles() * (1 - routeClass.GetThresholdVehicleNumRateForNewRoute());
	}
	
	function IsTooManyVehiclesForNewRouteRaw(vt) {
		local routeClass = Route.Class(vt);
		local remaining = routeClass.GetVehicleNumRoom(routeClass);
		return remaining <= routeClass.GetMaxTotalVehicles() * (1 - routeClass.GetThresholdVehicleNumRateForNewRoute());
	}
	
	function IsTooManyVehiclesForSupportRoute(self) {
		local remaining = self.GetVehicleNumRoom(self);
		if(remaining > 30) {
			return false;
		}
		return remaining <= self.GetMaxTotalVehicles() * (1 - self.GetThresholdVehicleNumRateForSupportRoute());
	}
	
	function GetVehicleNumRoom(self) {
		return self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, self.GetVehicleType());
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
		if(!("GetMaxRouteCapacity" in engineSet)) {
			HgLog.Warning("!GetMaxRouteCapacity in engineSet:"+this);
		}
		
		return engineSet.GetMaxRouteCapacity(cargo);
	}

	function GetCurrentRouteCapacity(cargo) {
		local engineSet = GetLatestEngineSet();
		if(engineSet == null) {
			return 0;
		}
		return engineSet.GetRouteCapacity(cargo, GetNumVehicles());
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
	
	function GetCargoCapacities() {
		local engineSet = GetLatestEngineSet();
		if(engineSet != null) {
			return engineSet.cargoCapacity;
		}
		return {};
	}

	function GetDistance() {
		return AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
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

	function IsOverflowPlace(place,cargo) {
		if(IsDestPlace(place)) {
			return IsOverflow(cargo,true);
		}
		if(IsSrcPlace(place)) {
			return IsOverflow(cargo,false);
		}
		return false;
	}

	function IsOverflow( cargo = null, isDest = false, callRoutes = null ) {
		local key = cargo+"-"+isDest;
		if(overflowCache.rawin(key)) {
			return overflowCache.rawget(key);
		}
		local result = _IsOverflow(cargo, isDest, callRoutes);
		overflowCache.rawset(key,result);
		return result;
	}
	
	function _IsOverflow( cargo = null, isDest = false, callRoutes = null ) {
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
		local bottom = max(300, min(capacity * (HogeAI.Get().roiBase ? 3 : 20), 3000));
		local station = (isDest ? destHgStation : srcHgStation).stationId;
		if(!isDest && !(this instanceof TrainReturnRoute)
				&& AIStation.HasCargoRating(station, cargo) && AIStation.GetCargoRating(station, cargo) < 50) {
			return true; // return routeは満載待機ではないので
		}
		return AIStation.GetCargoWaiting(station, cargo) > bottom;
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
		if(IsTooManyVehiclesForNewRoute(this)) {
			return false;
		}
		if(IsClosed()) {
			return false;
		}
		if(checkRouteCapacity && IsOverflow(cargo,isDest)) {
			return false;
		}
		local key = id + "-" + cargo;
		if(callRoutes == null) {
			callRoutes = {};
		} else if(callRoutes.rawin(key)) {
			HgLog.Warning("NeedsAdditionalProducingCargo() called recursively."+this);
			return false;
		}
		callRoutes.rawset(key,0);

		local hgStation = isDest ? destHgStation : srcHgStation;
		local limitCapacity = GetCargoCapacity(cargo);
/*		if(!IsReturnRoute(isDest)) {
			limitCapacity /= 2;
		}*/
		local cargoWaiting = AIStation.GetCargoWaiting( hgStation.stationId, cargo );
		if(cargoWaiting == 0 && limitCapacity == 0 && cargo != this.cargo
				&& !NeedsAdditionalProducingCargo(this.cargo, callRoutes, false, checkRouteCapacity)) { // 新たな種類のcargoが必要かどうかのチェック
			callRoutes.rawdelete(key);
			return false;	// メインカーゴがこれ以上不要な場合、列車数が飽和している事を示唆している
		}
		if(checkRouteCapacity && !HasLeftCapacity(cargo, isDest)) {
			callRoutes.rawdelete(key);
			return false;
		}

		local result = cargoWaiting <= limitCapacity;
		if(!IsTransfer()) {
			//HgLog.Warning("_NeedsAdditionalProducingCargo "+result+" cargoWaiting:"+cargoWaiting+" limitCapacity:"+limitCapacity+" "+this);
			callRoutes.rawdelete(key);
			return result;
		}
		if(isDest || !result) {
			callRoutes.rawdelete(key);
			return false;
		}
		foreach(destRoute in GetDestRoutes()) {
			if( destRoute.IsBiDirectional() && destRoute.destHgStation.stationGroup == destHgStation.stationGroup ) {
				if( destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, true, checkRouteCapacity) 
						/* いらない？ && !destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, false, checkRouteCapacity)*/ ) {
					callRoutes.rawdelete(key);
					return true;
				}
			} else {
				if( destRoute.NeedsAdditionalProducingCargo(cargo, callRoutes, false, checkRouteCapacity) ) {
					callRoutes.rawdelete(key);
					return true;
				}
			}
		}
		callRoutes.rawdelete(key);
		return false;
	}
	
	function HasLeftCapacity(cargo, isDest = false) {
		if(!isDest && GetVehicleType() == AIVehicle.VT_WATER) return true;
		local station = isDest ? destHgStation : srcHgStation;
		local maxCapacity;
		if( IsReturnRoute(isDest) ) {
			maxCapacity = GetCurrentRouteCapacity(cargo);
			/*dest側に転送しすぎる。local vehicleList = GetVehicleList();
			vehicleList.Valuate(AIVehicle.GetState);
			vehicleList.RemoveValue(AIVehicle.VS_AT_STATION);
			vehicleList.Valuate(AIVehicle.GetCargoLoad, cargo);
			local totalLoad = 0;
			foreach(e,v in vehicleList) {
				totalLoad += v;
			}
			local totalCapacity = vehicleList.Count() * GetCargoCapacity(cargo);
			return max(0, totalCapacity - totalLoad);*/
		} else {
			maxCapacity = GetMaxRouteCapacity(cargo);
		}
		if(CargoUtils.IsPaxOrMail(cargo)) {
			maxCapacity /= 2;
		}
		if(station.stationGroup == null) {
			return false;
		}
		return maxCapacity - station.stationGroup.GetCurrentExpectedProduction(cargo, GetVehicleType(), true) >= 1;
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
		local currentCapacity = GetMaxRouteCapacity(cargo);
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
				return latestEngineSet.days / 2 + latestEngineSet.loadingTime;
			}
			return destRoute.GetTotalCruiseDays(searchedRoute) + latestEngineSet.days / 2 + latestEngineSet.loadingTime;
		} else {
			return latestEngineSet.days / 2 + latestEngineSet.loadingTime;
		}		
	}

	function GetAdditionalVehicles(production,cargo,searchedRoute = null) {
		local capacity = GetCargoCapacity(cargo);
		local vehicles = capacity==0 ? 0 : production / capacity;
		if(!IsTransfer()) {
			return vehicles;
		}
		if(searchedRoute == null) {
			searchedRoute = {};
		}
		if(searchedRoute.rawin(this)) {
			return 0;
		}
		searchedRoute.rawset(this, true);
		local destRoute = GetDestRoute();
		if(!destRoute) {
			return vehicles;
		}
		return destRoute.GetAdditionalVehicles(production,cargo,searchedRoute) + vehicles;
	}

	
	function IsValidDestStationCargo() {
		foreach(cargo,_ in GetCargoCapacities()) {
			if(destHgStation.stationGroup.IsAcceptingCargo(cargo)) {
				if(IsBiDirectional()) {
					if(srcHgStation.stationGroup.IsAcceptingCargo(cargo)) {
						return true;
					}
				} else {
					return true;
				}
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
						if(!r.HasCargos(self.GetCargos())) {
							score = 0;
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
	
	function GetFinalDestRoute(searchedRoute = null) {
		if(!IsTransfer()) {
			return this;
		} else {
			local destRoute = GetDestRoute();
			if(destRoute == false) {
				return null;
			}
			if(searchedRoute == null) {
				searchedRoute = {};
			}
			if(searchedRoute.rawin(this)) {
				return null;
			}
			searchedRoute.rawset(this, true);
			return destRoute.GetFinalDestRoute(searchedRoute);
		}
	}
	
	function GetTransferDistance(searchedRoute = null) {
		if(!IsTransfer()) {
			return 0;
		} else {
			local destRoute = GetDestRoute();
			if(destRoute == false) {
				return 0;
			}
			if(searchedRoute == null) {
				searchedRoute = {};
			}
			if(searchedRoute.rawin(this)) {
				return null;
			}
			searchedRoute.rawset(this, true);
			return destRoute.GetTransferDistance(searchedRoute) + GetDistance();
		}
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
	
	
	function HasCargos(cargos) {
		foreach(c1 in cargos) {
			foreach(c in GetCargos()) {
				if(c == c1) {
					return true;
				}
			}
		}
		return false;
	}
	
	function GetCargos() {
		return [cargo];
	}
	
	function GetUsableCargos() {
		return [cargo];
	}
	
	function GetLastYearProfit() {
		local result = 0;
		foreach(vehicle,_ in GetVehicleList()) {
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
		if(isTownTransferRoute==null) {
			isTownTransferRoute = IsTransfer() && srcHgStation.IsTownStop();
		}
		return isTownTransferRoute;
	}
	
	function IsDestDest(destRoute = null) {
		if(destRoute == null) {
			destRoute = GetDestRoute();
			if(!destRoute) {
				return false;
			}
		}
		if(IsTransfer() && destRoute.IsBiDirectional() && destHgStation.stationGroup == destRoute.destHgStation.stationGroup) {
			return true;
		} else {
			return false;//TODO !isTransfer はplaceの一致で判断
		}
	}
	
	function CheckClose() {
		// TrainRouteの時は、singleがtransferの時のみ呼ばれる
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
			local srcSharing = srcHgStation.stationGroup.GetUsingRoutesAsSource().len() >= 2;
			local destRoutes = [];
			foreach(destRoute in destHgStation.stationGroup.GetUsingRoutesAsSource()) {
				if(destRoute.HasCargo(cargo)) {
					destRoutes.push(destRoute);
				}
			}
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
				if(srcSharing && destRoute.IsOverflow(cargo, IsDestDest(destRoute))) {
					continue;
				}
				if(!destRoute.IsClosed()) {
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
				saveData.lastDestClosedDate = lastDestClosedDate = AIDate.GetCurrentDate();
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
					//HgLog.Warning("GetUsedAsSourceByPriorityRoute:"+route+" "+this);
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

	function InvalidateEngineSet() {
		// overrideして使う
	}

	function CreateGroupName() {
		local src = srcHgStation.GetName();
		local dest = destHgStation.GetName();
		src = src.slice(0,min(6,src.len()));
		dest = dest.slice(0,min(6,dest.len()));
		local s = GetLabel()+" "+(IsTransfer()?"T:":"")+ dest + "<-"+(IsBiDirectional()?">":"") + src +"[" + AICargo.GetName(cargo) + "]";
		return s.slice(0,min(31,s.len()));
	}

	function NotifyChangeDestRoute(callers = null) {
		HgLog.Info("NotifyChangeDestRoute "+this);
		if(callers == null) {
			callers = {};
		} else if(callers.rawin(this)) {
			return;
		}
		callers.rawset(this,0);
		InvalidateEngineSet();
		foreach(route in srcHgStation.stationGroup.GetUsingRoutesAsDest()) {
			route.NotifyChangeDestRoute(callers);
		}
	}

	function NotifyAddTransfer(callers = null) {
		HgLog.Info("NotifyAddTransfer "+this);
		needsAdditionalCache.clear();
		productionCargoCache.clear();
		if(IsTransfer()) {
			if(callers == null) {
				callers = {};
			} else if(callers.rawin(this)) {
				return;
			}
			callers.rawset(this,0);
			foreach(destRoute in GetDestRoutes()) {
				destRoute.NotifyAddTransfer(callers);
			}
		}
	}

	function OnIndustoryClose(industry,usedStations) {
		if(srcHgStation.stationGroup == null) {
			HgLog.Warning("stationGroup == null(OnIndustoryClose) " + this);
			return;
		}
		local srcPlace = srcHgStation.place;
		if(srcPlace != null && srcPlace instanceof HgIndustry && srcPlace.industry == industry) {
			if(GetVehicleType() == AIVehicle.VT_RAIL && HogeAI.Get().IsInfrastructureMaintenance() == false) {
				HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. Search transfer." + this);
				HogeAI.Get().SearchAndBuildTransferRoute(this);
			}
			local saved = false;
			foreach(route in srcHgStation.stationGroup.GetUsingRoutesAsDest()) {
				if(route.IsTransfer()) {
					HgLog.Warning("Src industry "+AIIndustry.GetName(industry)+" closed. But saved because transfer route found."+this);
					saved = true;
				}
			}
			if(saved) {
				usedStations.rawset(srcHgStation,true);
			} else {
				HgLog.Warning("Remove Route (src industry closed:"+AIIndustry.GetName(industry)+")"+this);
				Remove();
			}
		}
		local destPlace = destHgStation.place;
		if(destPlace != null && destPlace instanceof HgIndustry && destPlace.industry == industry) {
			usedStations.rawset(destHgStation,true);
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
	
	function _tostring() {
		local state = IsClosed() ? (IsRemoved()?" Removed":" Closed"): "";
		return (IsTransfer() ? "T:" : "") + destHgStation.GetName() + "<-"+(IsBiDirectional()?">":"") + srcHgStation.GetName()
				+ "[" + AICargo.GetName(cargo) + "]" + GetLabel() + state;
	}
}


class CommonRoute extends Route {
	static checkReducedDate = {};
	static vehicleStartDate = {};
	static vehicleRemoving = {};
	
	static function SaveStatics(saveData) {
		saveData.checkReducedDate <- CommonRoute.checkReducedDate;
		saveData.vehicleStartDate <- CommonRoute.vehicleStartDate;
		saveData.vehicleRemoving <- CommonRoute.vehicleRemoving;
	}
	
	static function LoadStatics(saveData) {
		if("checkReducedDate" in saveData) {
			TableUtils.Extend(CommonRoute.checkReducedDate, saveData.checkReducedDate);
		}
		if("vehicleStartDate" in saveData) {
			TableUtils.Extend(CommonRoute.vehicleStartDate, saveData.vehicleStartDate);
		}
		if("vehicleRemoving" in saveData) {
			TableUtils.Extend(CommonRoute.vehicleRemoving, saveData.vehicleRemoving);
		}
	}

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
				if(route.depot == null) {
					continue;
				}
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
		HogeAI.Get().WaitDays(3,true);
		vehicleList.Valuate(function(v) : (vehicleList,start) {
			if(AIVehicle.GetState(v) != AIVehicle.VS_RUNNING) {
				return -1;
			}
			local d = AIMap.DistanceManhattan( vehicleList.GetValue(v), AIVehicle.GetLocation(v) );
			return VehicleUtils.GetSpeed( d, AIDate.GetCurrentDate() - start );
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
		//local vehiclesRoom = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType);
		local tooManyVehicles = self.IsTooManyVehiclesForNewRoute(self); //vehiclesRoom <= 1;
		
		HgLog.Info("Check RemoveRoute vt:"+self.GetLabel()+" routes:"+routeInstances.len()+" tooMany:"+tooManyVehicles);

		if(vehicleType == AIVehicle.VT_AIR) {
			if(AIDate.GetYear(AIDate.GetCurrentDate()) % 10 == 9) {
				Place.canBuildAirportCache.clear(); //10年に1度キャッシュクリア
			}
		}

		local engineList = AIEngineList(vehicleType);
		engineList.Valuate(AIEngine.GetDesignDate);
		engineList.KeepAboveValue(AIDate.GetCurrentDate() - 365*2); //デザインから出現まで1年かかる
		local engineChanged = engineList.Count() >= 1;

		local vehicleSpeeds = AIList();
		if(vehicleType == AIVehicle.VT_ROAD && AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType) >= 1) {
			vehicleSpeeds = CommonRoute.CalculateVehiclesSpeed(vehicleType);
		}


		local routeRemoved = false;
		local checkRoutes = 0;
		local speedRateSum = 0.0;
		local speedCount = 0;
		local minRoutes = AIList();
		minRoutes.Sort(AIList.SORT_BY_VALUE,true);
		foreach(index, route in routeInstances) {
			if(route.IsClosed()) {
				continue;
			}
			if(route.IsTransfer()) {
				if(vehicleType == AIVehicle.VT_ROAD) {
					// 転送を減らすと転送の新設と廃止でCPU時間が取られる。route.CheckReduceForRoadTransfer(vehicleSpeeds);
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
				minRoutes.AddItem(index, routeProfit);
			}
		}
		
		if(speedCount >= 100) {
			HogeAI.Get().roadTrafficRate = speedRateSum / speedCount;
			HgLog.Info("roadTrafficRate:"+HogeAI.Get().roadTrafficRate);
		}
		
		if((tooManyVehicles && minRoutes.Count() >= 10) || emergency) {
			local removeNum = (minRoutes.Count() + 32) / 33; // 3%を削除
			for(local i=0; i<removeNum; i++) {
				local routeIndex = minRoutes.Begin();
				local route = routeInstances[routeIndex];
				local profit = minRoutes.GetValue(routeIndex);
				HgLog.Warning("RemoveRoute minProfit:"+profit+" "+route);
				route.Remove();
				minRoutes.RemoveItem(routeIndex);
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
				saveData.maxVehicles = this.maxVehicles;
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
	
	startDate = null;
	maxVehicles = null;
	depot = null;
	destDepot = null;
	isClosed = null;
	isRemoved = null;
	isWaitingProduction = null; // まだcargoが来ていないrouteかどうか
	lastDestClosedDate = null;
	useDepotOrder = null;
	isSrcFullLoadOrder = null;
	isDestFullLoadOrder = null;
	cannotChangeDest = null;
	latestEngineSet = null;

	destRoute = null;
	hasRailDest = null;
	stopppedVehicles = null;
	profits = null;
	
	saveData = null;
	
	constructor() {
		Route.constructor();
		isClosed = false;
		isRemoved = false;
		isWaitingProduction = false;
		useDepotOrder = true;
		isSrcFullLoadOrder = true;
		isDestFullLoadOrder = false;
		cannotChangeDest = false;
		profits = [];
		isTransfer = false;
		isBiDirectional = false;
		saveData = {};
	}
	
	function Initialize() {
		if(vehicleGroup == null) {
			vehicleGroup = AIGroup.CreateGroup( GetVehicleType() );
			AIGroup.SetName(vehicleGroup, CreateGroupName());
			Route.groupRoute.rawset(vehicleGroup,this);
		}
		maxVehicles = GetMaxVehicles();
		startDate = AIDate.GetCurrentDate();
		UpdateSavedData();
	}
	
	function Save() {
		return {
			savedData = saveData
		};
	}
	
	function Load(t) {
		saveData = t.savedData;

		Route.Load(saveData);
	
		cargo = saveData.cargo;
		srcHgStation = HgStation.worldInstances[saveData.srcHgStation];
		destHgStation = HgStation.worldInstances[saveData.destHgStation];

		isTransfer = saveData.isTransfer;
		isBiDirectional = saveData.isBiDirectional;
		vehicleGroup = saveData.vehicleGroup;
		if(vehicleGroup != null) {
			Route.groupRoute.rawset(vehicleGroup,this);
		}
		
		startDate = "startDate" in saveData ? saveData.startDate : AIDate.GetCurrentDate();
		depot = saveData.depot;
		destDepot = saveData.destDepot;
		useDepotOrder = saveData.useDepotOrder;
		isDestFullLoadOrder = saveData.isDestFullLoadOrder;
		
		if(saveData.rawin("isClosed")) {
			t = saveData;
		}
		isClosed = t.isClosed;
		isRemoved = t.isRemoved;
		isWaitingProduction = t.isWaitingProduction;
		lastDestClosedDate = t.lastDestClosedDate;
		cannotChangeDest = t.cannotChangeDest;
		latestEngineSet = t.latestEngineSet != null ? delegate CommonEstimation : t.latestEngineSet : null;
		maxVehicles = t.maxVehicles;
		if(!saveData.rawin("isClosed")) {
			saveData.isClosed <- isClosed
			saveData.isRemoved <- isRemoved
			saveData.isWaitingProduction <- isWaitingProduction
			saveData.lastDestClosedDate <- lastDestClosedDate
			saveData.cannotChangeDest <- cannotChangeDest
			saveData.latestEngineSet <- latestEngineSet
			saveData.maxVehicles <- maxVehicles		
		}
	}
	
	function UpdateSavedData() {
		saveData = {
			cargo = cargo
			srcHgStation = srcHgStation.id
			destHgStation = destHgStation.id
			isTransfer = isTransfer
			isBiDirectional = isBiDirectional
			vehicleGroup = vehicleGroup
			startDate = startDate
			depot = depot
			destDepot = destDepot
			useDepotOrder = useDepotOrder
			isDestFullLoadOrder = isDestFullLoadOrder
			
			isClosed = isClosed
			isRemoved = isRemoved
			isWaitingProduction = isWaitingProduction
			lastDestClosedDate = lastDestClosedDate
			cannotChangeDest = cannotChangeDest
			latestEngineSet = latestEngineSet
			maxVehicles = maxVehicles
		};
		Route.SaveTo(saveData);
	}

	function SetCannotChangeDest(cannotChangeDest) {
		saveData.cannotChangeDest = this.cannotChangeDest = cannotChangeDest;
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
		if(srcHgStation instanceof CanalStation || srcHgStation instanceof WaterStation) {
			depot = srcHgStation.GetDepot();
			if(depot != null) {
				return true;
			}
		}
		depot = path.BuildDepot(GetVehicleType());
		if(srcHgStation instanceof CanalStation || srcHgStation instanceof WaterStation) {
			srcHgStation.SetDepot(depot);
		}
		if(depot == null && srcHgStation instanceof RoadStation) {
			depot = srcHgStation.BuildDepot();
		}                        
		if(depot == null && ("GetDepot" in destHgStation)) { // 最悪destで生産
			depot = destHgStation.GetDepot();
		}
		if(depot == null) {
			HgLog.Warning("depot == null. "+this);
			return false;
		}
		return depot != null;
	}
	
	function BuildDestDepot(path) {
		local execMode = AIExecMode();
		path = path.Reverse();		
		
		if(destHgStation instanceof CanalStation || destHgStation instanceof WaterStation) {
			destDepot = destHgStation.GetDepot();
			if(destDepot != null) {
				return true;
			}
		}
		destDepot = path.BuildDepot(GetVehicleType());
		if(destHgStation instanceof CanalStation || destHgStation instanceof WaterStation) {
			destHgStation.SetDepot(destDepot);
		}
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
		//local vehicle = AIVehicle.BuildVehicle(depot, engine);
		local cost = AIEngine.GetPrice(engine);
		local vehicle;
		while(true) {
			HogeAI.WaitForPrice(cost);
			vehicle = BuildUtils.BuildVehicleWithRefitSafe(depot, engine, cargo);
			if(vehicle==null || !AIVehicle.IsValidVehicle(vehicle)) {
				if(AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
					cost += HogeAI.Get().GetInflatedMoney(10000);
					continue;
				}		
				HgLog.Warning("BuildVehicleWithRefit failed. engine:"
					+ AIEngine.GetName(engine) + " depot:" + HgTile(depot)
					+ " " + AIError.GetLastErrorString() + " " + this);
				return null;
			}
			break;
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
			saveData.maxVehicles = maxVehicles = GetMaxVehicles();
		}
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		
		return vehicle;
	}
	
	function MakeOrder(vehicle) {

		local nonstopIntermediate = GetVehicleType() == AIVehicle.VT_ROAD ? AIOrder.OF_NON_STOP_INTERMEDIATE : 0;

		if(useDepotOrder && HogeAI.Get().IsEnableVehicleBreakdowns() && !(this instanceof WaterRoute)) {
			AIOrder.AppendOrder(vehicle, depot, nonstopIntermediate );
		}
		local isBiDirectional = IsBiDirectional();
		local loadOrderFlags =  nonstopIntermediate | (!AITile.IsStationTile(srcHgStation.platformTile) ? 0 : (isSrcFullLoadOrder ? AIOrder.OF_FULL_LOAD_ANY : 0));
		local srcOrderPosition = AIOrder.GetOrderCount(vehicle);
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
		
		if(useDepotOrder && destDepot != null && HogeAI.Get().IsEnableVehicleBreakdowns() && !(this instanceof WaterRoute)) {
			AIOrder.AppendOrder(vehicle, destDepot, nonstopIntermediate );
		}
		local destOrderPosition = AIOrder.GetOrderCount(vehicle);
		if(isTransfer) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, 
				nonstopIntermediate + (!AITile.IsStationTile(destHgStation.platformTile) ? 0 : (AIOrder.OF_TRANSFER | AIOrder.OF_NO_LOAD)));
		} else if(isBiDirectional) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, nonstopIntermediate | (isDestFullLoadOrder ? AIOrder.OF_FULL_LOAD_ANY : 0));
		} else {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile,
				nonstopIntermediate + (!AITile.IsStationTile(destHgStation.platformTile) ? 0 : (AIOrder.OF_UNLOAD | AIOrder.OF_NO_LOAD)));
		}
		/* 最初の車両が積載0でdepotへ行ってしまう if(!isSrcFullLoadOrder) {
			AIOrder.InsertConditionalOrder(vehicle,srcOrderPosition+1,destOrderPosition);
			AIOrder.SetOrderCondition(vehicle,srcOrderPosition+1,AIOrder.OC_LOAD_PERCENTAGE );
			AIOrder.SetOrderCompareFunction(vehicle,srcOrderPosition+1,AIOrder.CF_MORE_THAN  );
			AIOrder.SetOrderCompareValue(vehicle,srcOrderPosition+1,50 );
			AIOrder.InsertOrder(vehicle, srcOrderPosition+2, depot, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_STOP_IN_DEPOT )
		}*/
		if(useDepotOrder && destDepot != null && HogeAI.Get().IsEnableVehicleBreakdowns()) {
			AIOrder.AppendOrder(vehicle, destDepot, AIOrder.OF_SERVICE_IF_NEEDED );
		}

		AppendDestToSrcOrder(vehicle);

	}
	
	function AppendSrcToDestOrder(vehicle) {
	}
	
	function AppendDestToSrcOrder(vehicle) {
	}
	
	function AppendRemoveOrder(vehicle) {
		CommonRoute.vehicleRemoving.rawset(vehicle,true);
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
		local cost = AIEngine.GetPrice(AIVehicle.GetEngineType(vehicle));
		while(true) {
			HogeAI.WaitForPrice(cost);
			result = AIVehicle.CloneVehicle(depot, vehicle, true);
			if(!AIVehicle.IsValidVehicle(result)) {
				if(AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
					cost += HogeAI.Get().GetInflatedMoney(10000);
					continue;
				}		
				if(AIError.GetLastError() == AIVehicle.ERR_VEHICLE_NOT_AVAILABLE && latestEngineSet != null) {
					latestEngineSet.isValid = false;
				}
				HgLog.Warning("CloneVehicle failed. depot:"+HgTile(depot)+" veh:"+AIVehicle.GetName(vehicle)+" "+AIError.GetLastErrorString()+" "+this);
				return null;
			}
			if(AIOrder.GetOrderCount(result) == 0) {
				AIVehicle.SellVehicle(result);
				HgLog.Warning("CloneVehicle failed. depot:"+HgTile(depot)+" veh:"+AIVehicle.GetName(vehicle)+" AIOrder.GetOrderCount(result) == 0 "+this);
				return null;
			}
			break;
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

	function InvalidateEngineSet() {
		latestEngineSet.isValid = false;
	}

	function ChooseEngineSet() {
		local engineExpire = 1500;
		local oldEngine = latestEngineSet != null ? latestEngineSet.engine : null;
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
			saveData.latestEngineSet = latestEngineSet = clone engineSet;
			latestEngineSet.date <- AIDate.GetCurrentDate();
			latestEngineSet.isValid <- true;
			latestEngineSet.productionIndex <- HogeAI.Get().GetEstimateProductionIndex(production);
			latestEngineSet.markSendDepot <- (oldEngine == null || oldEngine==latestEngineSet.engine ? false : true);
			HgLog.Info("ChooseEngine:"+AIEngine.GetName(latestEngineSet.engine)
				+(oldEngine!=null?" old:"+AIEngine.GetName(oldEngine):"")
				+" production:"+production+" "+this);
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
		saveData.latestEngineSet = latestEngineSet = clone engineSet;
		latestEngineSet.date <- AIDate.GetCurrentDate();
		latestEngineSet.isValid <- true;
	}

	function GetVehicleList() {
		return AIVehicleList_Group(vehicleGroup);
	}
	
	function GetNumVehicles() {
		return AIGroup.GetNumVehicles(vehicleGroup, 0);
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
		local vehicleList = GetVehicleList();
		vehicleList.Valuate(AIVehicle.GetAge);
		vehicleList.Sort(AIList.SORT_BY_VALUE,true);
		foreach(vehicle, age in vehicleList) {
			if( CommonRoute.vehicleRemoving.rawin(vehicle) )  {
				continue;
			}
			return vehicle;
		}
		return null;
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
		saveData.maxVehicles = maxVehicles;
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
			if(AppendRemoveOrder(vehicle)) {
				reduce --;
			}
		}
	}

	function SellVehiclesStoppedInDepots() {
		foreach(vehicle,_ in GetVehicleList()) {
			if(AIVehicle.IsStoppedInDepot(vehicle)) {
				SellVehicle(vehicle);
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
	
	function CheckNotProfitableOrStopVehicle( emergency = false, tooMany = false ) {
		local isBiDirectional = IsBiDirectional();
		local vehicleType = GetVehicleType();
		local vehicleList = GetVehicleList();
		vehicleList.Valuate(AIVehicle.IsStoppedInDepot);
		vehicleList.RemoveValue(1);
		
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
			//HgLog.Warning("check SendVehicleToDepot "+this+" vehicleList:"+vehicleList.Count());
		local checkProfitable = !isTransfer && (emergency || AIDate.GetMonth(AIDate.GetCurrentDate()) >= 10);
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
						saveData.maxVehicles = maxVehicles;
						HgLog.Info("maxVehicles:"+maxVehicles+" notProfitable:"+notProfitable+" "+this);
					}
					//HgLog.Info("SendVehicleToDepot(road) "+AIVehicle.GetName(vehicle)+" "+this);
				}
			}
		}
		
		//productionの減少やライバル社がやってきた場合に減らす処理
		if(vehicleType == AIVehicle.VT_WATER) {
			local keepNum = tooMany ? 2 : 3;
			vehicleList.Valuate(AIVehicle.GetState);
			vehicleList.KeepValue(AIVehicle.VS_AT_STATION);
			vehicleList.Valuate(AIVehicle.GetCargoLoad, cargo);
			vehicleList.KeepValue(0);
			if(vehicleList.Count() > keepNum) {
				local removeCount = vehicleList.Count() - keepNum;
				foreach(vehicle,_ in vehicleList) {
					AppendRemoveOrder(vehicle);
					removeCount --;
					if(removeCount == 0) {
						break;
					}
				}
			}
		} else if(vehicleType == AIVehicle.VT_AIR) { //VT_ROADはsrcStation付近でのstop数？
			local reduce = 0;
			if(tooMany) {
				local list = AIList();
				list.AddList(vehicleList);
				list.Valuate(AIVehicle.GetState);
				list.KeepValue(AIVehicle.VS_AT_STATION);
				list.Valuate(AIVehicle.GetCargoLoad, cargo);
				list.KeepValue(0);
				if(list.Count() > 2) {
					local removeCount = reduce = list.Count() - 2;
					foreach(vehicle,_ in list) {
						AppendRemoveOrder(vehicle);
						removeCount --;
						if(removeCount == 0) {
							break;
						}
					}
				}		
			}
			foreach(v,_ in vehicleList) {
				if(AIVehicle.IsInDepot(v) && !AIVehicle.IsStoppedInDepot(v)) {
					AIVehicle.StartStopVehicle(v);
					maxVehicles = min(vehicleList.Count(), maxVehicles);
					maxVehicles = max(0, maxVehicles - 1 - reduce);
					saveData.maxVehicles = maxVehicles;
					break;
				}
			}
		} else if(vehicleType == AIVehicle.VT_ROAD) {
			local currentVehicles = vehicleList.Count();
			if(currentVehicles>=(tooMany ? 1 : 2)) {
				vehicleList.Valuate(AIVehicle.GetCurrentSpeed);
				vehicleList.KeepValue(0);
				vehicleList.Valuate(AIVehicle.GetState);
				
				local waitStations = {};
				local isTownTransfer = IsTownTransferRoute();
				if(isTownTransfer) {
					waitStations.rawset(srcHgStation.platformTile,true);
				} else {
					foreach(v,state in vehicleList) {
						if(state == AIVehicle.VS_AT_STATION) {
							waitStations.rawset(AIVehicle.GetLocation(v),true);
						}
					}
				}
				local waitingCargo = AIStation.GetCargoWaiting(srcHgStation.stationId,cargo);
				if(isTownTransfer && waitingCargo <= 5) {
					foreach(v,state in vehicleList) {
						if(state == AIVehicle.VS_AT_STATION && AIVehicle.GetLocation(v) != srcHgStation.platformTile) {
							vehicleList.RemoveItem(v);
						}
					}
				} else if(tooMany && waitingCargo < 10) {
				} else {
					vehicleList.RemoveValue(AIVehicle.VS_AT_STATION);
				}
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
				if(vehicleList.Count() >= (tooMany ? 1 : 2)) {
					if(!tooMany) {
						vehicleList.RemoveTop(1);
					}
					foreach(vehicle,_ in vehicleList) {
						AppendRemoveOrder(vehicle);
					}
					maxVehicles = min(currentVehicles, maxVehicles);
					maxVehicles = max(0, maxVehicles - vehicleList.Count());
					saveData.maxVehicles = maxVehicles;
					HgLog.Info("maxVehicles:"+maxVehicles+" stopped:"+vehicleList.Count()+" "+this);
				}
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
			saveData.isWaitingProduction = isWaitingProduction = false;
		}
		local townTransfer = IsTownTransferRoute();
		if(townTransfer && AIBase.RandRange(100)<80) { // towntransferは大量にあるのでたまにしか実行しない
			return;
		}

		//local c0 = PerformanceCounter.Start("c00");
		local execMode = AIExecMode();	
		local all = GetVehicleList();
		local vehicleList = AIList();
		
		local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
		local vehiclesSpace = GetMaxTotalVehicles() - totalVehicles;
		local tooMany = vehiclesSpace < 50;

		local choosenEngineSet = null;
		local choosenEngine = null;

		if(!isClosed && !isRemoved) {
			choosenEngineSet = ChooseEngineSet();
			if(choosenEngineSet == null) {
				HgLog.Warning("Route Remove (No engine)."+this);
				Remove();
				return;
			}
			choosenEngine = choosenEngineSet.engine;
		}

		vehicleList.AddList(all);
		vehicleList.Valuate(AIVehicle.IsStoppedInDepot);
		vehicleList.KeepValue(0);

		local inDepot = null;
		if(tooMany || AIBase.RandRange(100) < 10) {
			inDepot = AIList();
			inDepot.AddList(all);
			inDepot.Valuate(AIVehicle.IsStoppedInDepot);
			inDepot.KeepValue(1);
			
			local sellTargets = AIList();
			sellTargets.AddList(inDepot);
			if(!(isRemoved || isClosed || tooMany)) {
				sellTargets.Valuate(AIVehicle.GetEngineType);
				sellTargets.RemoveValue(choosenEngine);
			}
			foreach(v,_ in sellTargets) {
				SellVehicle(v);
			}
			inDepot.RemoveList(sellTargets);
		}
		
		if(isRemoved || isClosed) {
			foreach(v,_ in vehicleList) {
				AppendRemoveOrder(v);
			}
		}
		//c0.Stop();
		
		if(isRemoved && vehicleList.Count() == 0) {
			HgLog.Warning("All vehicles removed."+this);
			RemoveFinished();
		}
		
		if(isClosed || isRemoved) {
			return;
		}

		
		local isBiDirectional = IsBiDirectional();

		local cargoWaiting = AIStation.GetCargoWaiting(srcHgStation.stationId,cargo);
		if(GetVehicleType() == AIVehicle.VT_AIR && IsBiDirectional()) {
			cargoWaiting = min(cargoWaiting, AIStation.GetCargoWaiting(destHgStation.stationId,cargo));
		}
		if(AIBase.RandRange(100) < (HogeAI.Get().buildingTimeBase ? 5 : 25)) {
			//local c02 = PerformanceCounter.Start("c02");
			CheckNotProfitableOrStopVehicle(false,tooMany);
			//c02.Stop();
		}

		//local c021 = PerformanceCounter.Start("c021");
		local needsAddtinalProducing = NeedsAdditionalProducing(null,false,false);
		local isDestOverflow = IsDestOverflow();
		//c021.Stop();

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
				if(HogeAI.Get().buildingTimeBase && (!tooMany || AIBase.RandRange(100) < vehicleList.Count())) {
					local old = maxVehicles;
					maxVehicles = max(0,min(maxVehicles, vehicleList.Count()-reduce));
					saveData.maxVehicles = maxVehicles;
					if(old != maxVehicles) {
						HgLog.Info("maxVehicles:"+maxVehicles+"(isDestOverflow) "+this);
					}
				}
			}
			//c03.Stop();
			return;
		}
		
		if(vehiclesSpace <= 0) {
			return;
		}
		
		if(AIBase.RandRange(100) < (HogeAI.Get().roiBase ? 3 : 15)) {
			//local c22 = PerformanceCounter.Start("c22");
			if(GetVehicleType() == AIVehicle.VT_ROAD && IsTooManyVehiclesForNewRoute(this)) {
			} else if((isTransfer && needsAddtinalProducing) || (!isTransfer && IsOverflow())) {
				local finallyMax = GetMaxVehicles();
				maxVehicles += max(1,finallyMax / 12);
				maxVehicles = min(finallyMax, maxVehicles);
				saveData.maxVehicles = maxVehicles;
				//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
			}
			//c22.Stop();
		}

		
		
		if( AIBase.RandRange(100) < 10 && CargoUtils.IsPaxOrMail(cargo)) { // 作った時には転送が無い時がある
			//local c4 = PerformanceCounter.Start("c4");	
			if(needsAddtinalProducing) {
				CommonRouteBuilder.CheckTownTransferCargo(this,srcHgStation,cargo);
			}
			if(isBiDirectional && NeedsAdditionalProducing(null, true, false)) {
				CommonRouteBuilder.CheckTownTransferCargo(this,destHgStation,cargo);
			}
			//c4.Stop();		
		}

		local enableVehicleBreakDowns = HogeAI.Get().IsEnableVehicleBreakdowns();
		if(!("markSendDepot" in choosenEngineSet)) {
			choosenEngineSet.markSendDepot <- false;
		}

		if((choosenEngineSet!=null && choosenEngineSet.markSendDepot) || (enableVehicleBreakDowns && AIBase.RandRange(100) < 5)) {
/*	|| (lastCheckProductionIndex != null && lastCheckProductionIndex != HogeAI.Get().GetEstimateProductionIndex(GetProduction())))) {このチェックは重いからやらない*/
			//local c5 = PerformanceCounter.Start("c5");
			if(choosenEngineSet!=null && choosenEngineSet.markSendDepot) {
				choosenEngineSet.markSendDepot = false;
			}
			if(vehicleList.Count()>=1) {
				local isAll = true;
				foreach(vehicle,_ in vehicleList) {
					if((choosenEngine != null && choosenEngine != AIVehicle.GetEngineType(vehicle))
								|| (enableVehicleBreakDowns && AIVehicle.GetAgeLeft(vehicle) <= 600) ) {
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
		local needsProduction = (!tooMany && vehicleList.Count() < 10) ? (HogeAI.Get().roiBase ? 30 : 10) : 100; //= min(4,maxVehicles / 2 + 1) ? capacity : bottomWaiting;
		if(townTransfer) needsProduction = max(100,needsProduction);
		if(showLog) {
			HgLog.Info("needsProduction "+needsProduction+" "+this);
		}
		/*
		if(HogeAI.Get().roiBase && isBiDirectional) {
			cargoWaiting = min(cargoWaiting,AIStation.GetCargoWaiting(destHgStation.GetAIStation(),cargo));
		}*/
		if(cargoWaiting > needsProduction || (vehicleList.Count()==0 && (!isTransfer || needsAddtinalProducing))) {
			local vehicles = vehicleList;
			if(!ExistsWaiting(vehicles)) {
				local latestVehicle = null; //遅いGetLatestVehicle();
				foreach(v,_ in vehicleList) {
					if(AIVehicle.GetEngineType(v) == choosenEngine) {
						latestVehicle = v;
						break;
					}
				}
				local firstBuild = 0;
				
				if(latestVehicle == null) {
					BuildVehicleFirst();
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
				} else {
					local capacity = AIVehicle.GetCapacity(latestVehicle, cargo);
					if(capacity == 0) {
						HgLog.Warning("AIVehicle.GetCapacity("+AIVehicle.GetName(latestVehicle)+":"+AIEngine.GetName(AIVehicle.GetEngineType(latestVehicle))+")==0."+this);
						//c6.Stop();
						return; // capacity0の乗り物を増やしてもしょうがない
					}
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
					local buildNum;
					if(vehicleList.Count()==0 && (!isTransfer || needsAddtinalProducing)) {
						buildNum = 1;
					} else {
						buildNum = cargoWaiting / capacity;
						if(cargoWaiting > 200 && capacity > 200 && AIStation.GetCargoRating(srcHgStation.stationId, cargo) <= 25 ) { 
							// 待機量が200、評判25以下で在庫が増えなくなるので、往復時間が長いと容量200以上の車両が増えない
							buildNum = max(1, buildNum);
						}
					}
					if(townTransfer) {
						buildNum = min(1,buildNum);
					} else if(!IsSupportMode()) {
						buildNum = min(buildNum, 4);
					}
					buildNum = min(maxVehicles - vehicles.Count(), buildNum) - firstBuild;
					//if(HogeAI().Get().roiBase) {
					//	buildNum = min(buildNum, max(1, (maxVehicles - vehicles.Count())/8));
					//}
					//buildNum = min(buildNum, 8);
					if(showLog) {
						HgLog.Info("buildNum "+buildNum+" "+this);
					}
					
					//HgLog.Info("CloneVehicle "+buildNum+" "+this);
					if(buildNum >= 1) {
						if(inDepot==null) {
							inDepot = AIList();
							inDepot.AddList(all);
							inDepot.Valuate(AIVehicle.IsStoppedInDepot);
							inDepot.KeepValue(1);
						}
						foreach(v,_ in inDepot) {
							if(choosenEngine == AIVehicle.GetEngineType(v) 
									&& (!HogeAI.Get().IsEnableVehicleBreakdowns() || AIVehicle.GetAgeLeft(v) >= 1000)) {
								AIVehicle.StartStopVehicle(v);
								CommonRoute.vehicleRemoving.rawdelete(v);
								buildNum --;
								if(buildNum == 0) {
									break;
								}
							} else {
								SellVehicle(v);
							}
						}
						if(buildNum >= 1 && depot != null) {
							foreach(v,_ in AIVehicleList_Depot(depot)) { // 共通のdepotに他のgroupの使えるvehicleがいるかも
								if(AIVehicle.IsStoppedInDepot(v) 
										&& choosenEngine == AIVehicle.GetEngineType(v)
										&& AIVehicle.GetCapacity(v, cargo) >= 1
										&& (!HogeAI.Get().IsEnableVehicleBreakdowns() || AIVehicle.GetAgeLeft(v) >= 1000)) {
									CommonRoute.vehicleRemoving.rawdelete(v);
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
	
	function BuildVehicleFirst() {
		local vehicle = BuildVehicle();
		if(vehicle == null) {
			HgLog.Warning("BuildVehicleFirst failed."+AIError.GetLastErrorString()+" "+this);
		}
		if(vehicle != null && GetVehicleType() != AIVehicle.VT_WATER) {
			CloneVehicle(vehicle);
		}
		return vehicle;
	}
	
	static function SellVehicle(vehicle) {
		AIVehicle.SellVehicle(vehicle);
		CommonRoute.vehicleStartDate.rawdelete(vehicle);
		CommonRoute.vehicleRemoving.rawdelete(vehicle);
	}
	
	function ExistsWaiting(vehicles) {
		local vt = GetVehicleType();
		if(vt == AIVehicle.VT_ROAD) {/*
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
		} else if(vt == AIVehicle.VT_WATER) {
			return false;
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
		saveData.isClosed = isClosed = true;
		saveData.isRemoved = isRemoved = true;
		SendAllVehiclesToDepot();
	}
	
	function RemoveFinished() {
		HgLog.Warning("RemoveFinished: "+this);
		if(srcHgStation.place != null && (destHgStation.place != null || destHgStation.stationGroup != null)) {
			Place.AddNgPathFindPair(srcHgStation.place, 
					destHgStation.place != null ? destHgStation.place : destHgStation.stationGroup, GetVehicleType(), 365*10);
		}
		if(vehicleGroup != null) {
			foreach(v,_ in GetVehicleList()) {
				SellVehicle(v);
			}
			Route.groupRoute.rawdelete(vehicleGroup);
			AIGroup.DeleteGroup(vehicleGroup);
			vehicleGroup = null;
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
		saveData.isClosed = isClosed = true;
//		if(!HogeAI.Get().ecs) {
			SendAllVehiclesToDepot();
//		}
	}
	
	function ReOpen() {
		saveData.isRemoved = isRemoved = false;
		saveData.isClosed = isClosed = false;
		this.maxVehicles = GetMaxVehicles(); // これで良いのだろうか？
		saveData.maxVehicles = maxVehicles;
		//HgLog.Info("maxVehicles:"+maxVehicles+" "+this);
		//PlaceDictionary.Get().AddRoute(this); RemoveRouteしてないのにAddRouteされると思う
		HgLog.Warning("Route ReOpen."+this);
	}
	
	function SendAllVehiclesToDepot() {
		foreach(vehicle,_ in GetVehicleList()) {
			AppendRemoveOrder(vehicle);
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
		
		CheckClose();
	}
	
	function NotifyAddTransfer(callers=null) {
		Route.NotifyAddTransfer(callers);
		latestEngineSet.isValid = false;
	}
}


class Construction {
	parent_ = null;
	rollbackFacilities = null;
	saveData = null;

	static function RollbackFromSaveData(saveData) {
		local a = [];
		foreach(f in saveData.rollbackFacilities) {
			local typeName = typeof f;
			if(typeName == "integer") {
				a.push( f );
			} else if(typeName == "array") {
				a.push( BuildedPath( Path.Load(f) ) );
			} else {
				// station:xxx
				local stationId = f.slice(8).tointeger();
				if(HgStation.worldInstances.rawin(stationId)) {
					a.push( HgStation.worldInstances[stationId] );
				}
			}
		}
		Construction.DoRollback(a);
		if(saveData.parent_ != null) {
			Construction.RollbackFromSaveData(saveData.parent_);
		}
	}

	static function DoRollback(facilities) {
		local execMode = AIExecMode();
		foreach(f in facilities) {
			if(f != null) {
				local typeName = typeof f;
				if(typeName == "integer") {
					AITile.DemolishTile(f);
				} else {
					f.Remove();
				}
			}
		}
	}
	
	constructor() {
		rollbackFacilities = [];
		saveData = { 
			rollbackFacilities = []
			parent_ = null
		};
	}
	
	function Build() {
		StartConstraction();
		local result = DoBuild();
		EndConstraction();
		return result;
	}
	
	function StartConstraction() {
		local current = HogeAI.Get().currentConstraction;
		if(current != null) {
			parent_ = current;
			saveData.parent_ = current.saveData;
		}
		HogeAI.Get().currentConstraction = this;
	}
	
	function EndConstraction() {
		HogeAI.Get().currentConstraction = parent_;
		parent_ = null;
	}
	
	function AddRollback(facility, typeName=null) {
		if(typeName == "tiles") {
			saveData.rollbackFacilities.extend(facility);
			rollbackFacilities.extend(facility);
		} else {
			if(typeof facility == "array" || typeof facility == "integer") {
				saveData.rollbackFacilities.push(facility);
			} else if(facility instanceof HgStation) {
				saveData.rollbackFacilities.push("station:"+facility.GetId());
			} else if(facility instanceof BuildedPath) {
				saveData.rollbackFacilities.push(facility.array_);
			} else {
				HgLog.Error("AddRollback error:"+facility);
			}
			rollbackFacilities.push(facility);
		}
	}
	
	function Rollback() {
		Construction.DoRollback(rollbackFacilities);
		ClearRollback();
	}
	
	function ClearRollback() {
		saveData.rollbackFacilities.clear();
		rollbackFacilities.clear();
	}
}

class RouteBuilder extends Construction {
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
		Construction.constructor();
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
		return !Route.CanCreateRoute( GetVehicleType(), src, dest, cargo );
//		return Route.SearchRoutes( Route.GetRouteWeightingVt(GetVehicleType()), src, dest, cargo ).len() >= 1;
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
			if(!WaterRoute.CanBuild(src,dest,cargo,isBiDirectional)) {
				HgLog.Warning("!WaterRoute.CanBuild."+this);
				return null;
			}
		}

		needsToMeetDemand = false;
		local isTransfer = IsTransfer();
		local pendingToDoPostBuild = GetOption("pendingToDoPostBuild",false);
		
		supportRoutes = [];
		
		if(srcPlace != null && !GetOption("notNeedToMeetDemand",false)) {
				local currentProduction = srcPlace.GetLastMonthProduction( cargo );
				if(currentProduction<200 || currentProduction < srcPlace.GetExpectedProduction( cargo, GetVehicleType())) {
					needsToMeetDemand = true;
				}
				if(needsToMeetDemand && currentProduction<50) {
					// 場所がなくなる可能性があるので少量生産以外は後からやる
					local routePlans = GetOption("routePlans", null);
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
		builtRoute = Construction.Build();
		local span = AIDate.GetCurrentDate() - start;
		if(builtRoute == null) {
			HgLog.Info("# RouteBuilder Failed "+vehicleType+" "+span+" "+distance+" "+this);
			return null;
		}
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
		
		local vehicleType = GetVehicleType();
		builtRoute.isBuilding = true;// resultのrouteはまだ不完全な場合がある。(WaterRouteBuilder.BuildCompoundRoute)
		local limit = builtRoute.GetMaxRouteCapacity( cargo );
		
		if(searchTransfer && !GetOption("noExtendRoute",false) && !IsTransfer()) { // 延長チェック
			if(!builtRoute.cannotChangeDest && vehicleType == AIVehicle.VT_RAIL) {
				local extendsRoute = HogeAI.Get().SearchAndBuildAdditionalDestAsFarAsPossible(builtRoute);
			}
		}
		
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
			if(src instanceof HgIndustry) {
				local callers = {};
				foreach(route in src.GetRoutesUsingDest()) {
					if(route.IsRemoved()) continue;
					route.NotifyChangeDestRoute(callers);
					limit -= route.GetTotalDelivableProduction() / 2;
					HgLog.Info("remainCapacity:"+limit+" "+builtRoute);
				}
				foreach(route,_ in callers) {
					if(route.IsRemoved()) continue;
					route.ChooseEngineSet();
					if(routePlans != null) {
						routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( route )));
					}
				}
			}
			
			foreach(route in supportRoutes) { // 本線建設前に作ったルート
				limit -= route.GetTotalDelivableProduction() / 2;
				if(routePlans != null) {
					routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( route )));
				}
				HgLog.Info("remainCapacity:"+limit+" "+builtRoute);
			}
			if(routePlans != null) {
				routePlans.Extend( ShowPlansLog( HogeAI.Get().GetMeetPlacePlans( srcPlace, builtRoute ) ) );
			}
		}
		if(searchTransfer) {
			if(routePlans != null) {
				routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( builtRoute, 
					{ notTreatDest = true, noCheckNeedsAdditionalProducing = true } )));
			}
		}
		local value = engineSet.value;
		if(searchTransfer && !builtRoute.cannotChangeDest && vehicleType == AIVehicle.VT_RAIL) {
			local returnRoute = HogeAI.Get().CheckBuildReturnRoute(builtRoute, value);
			if(returnRoute != null) {
				if(routePlans != null) {
					routePlans.Extend( ShowPlansLog( HogeAI.Get().GetTransferCandidates( returnRoute, 
						{ noCheckNeedsAdditionalProducing = true } ) ) );
				}
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
			if(routePlans != null) {
				routePlans.Extend( ShowPlansLog(transferCandidates) );
			}
			
		}

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
	
	destHgStation = null;
	srcHgStation = null;

	isShareDestStation = null;
	isShareSrcStation = null;
		
	constructor( dest, src, cargo, options = {} ) {
		isShareDestStation = false;
		if(dest instanceof HgStation) {
			destHgStation = dest;
			dest = dest.place != null ? dest.place : dest.stationGroup;
			isShareDestStation = true;
		}
		isShareSrcStation = false;
		if(src instanceof HgStation) {
			srcHgStation = src;
			src = src.place != null ? src.place : src.stationGroup;
			isShareSrcStation = true;
		}
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
		local infrastractureTypes = null;
		if(vehicleType == AIVehicle.VT_AIR && srcHgStation != null && destHgStation != null) { // exchange air用
			infrastractureTypes = [min(srcHgStation.GetAirportType(), destHgStation.GetAirportType())];
		} else {
			infrastractureTypes = routeClass.GetSuitableInfrastractureTypes( src, dest, cargo);
		}
		local engineSet = Route.Estimate(vehicleType, cargo, distance, production, isBiDirectional, infrastractureTypes);
		HgLog.Info("CommonRouteBuilder isBiDirectional:"+isBiDirectional+" production:"+production+" distance:"+distance+" "+this);
		if(engineSet==null) {
			HgLog.Warning("No suitable engine. "+this);
			return null;
		}
		BuildStart(engineSet);
		
		local testMode = AITestMode();
		local destStationFactory = null;
		if(destHgStation == null) {
			destStationFactory = CreateStationFactory(dest);
			destStationFactory.isBiDirectional = isBiDirectional
		}
		if(destHgStation == null && checkSharableStationFirst) {
			destHgStation = SearchSharableStation(dest, destStationFactory.GetStationType(), cargo, true, 
				vehicleType == AIVehicle.VT_AIR ? infrastractureType : null);
			if(destHgStation != null) {
				isShareDestStation = true;
			}
		}
		local isNearestForPair = false;
		if(HogeAI.Get().IsInfrastructureMaintenance()) {
			isNearestForPair = true;
		} else if(vehicleType == AIVehicle.VT_ROAD) {
			isNearestForPair = srcPlace != null && srcPlace instanceof TownCargo;// 街の中心部を通ると渋滞に巻き込まれる為
		} else if(vehicleType == AIVehicle.VT_WATER) {
			isNearestForPair = srcPlace != null && srcPlace instanceof HgIndustry;
		}
		if(destHgStation == null) {
			if(isNearestForPair) {
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
		HogeAI.notBuildableList.AddList(list);

		local srcStationFactory = null;
		if(srcHgStation == null) {
			srcStationFactory = CreateStationFactory(src);
			srcStationFactory.isBiDirectional = isBiDirectional;
			if(isNearestForPair) {
				srcStationFactory.nearestFor = destHgStation.platformTile;
			}
			if(checkSharableStationFirst) {
				srcHgStation = SearchSharableStation(src, srcStationFactory.GetStationType(), cargo, false,
					vehicleType == AIVehicle.VT_AIR ? infrastractureType : null);
				if(srcHgStation != null) {
					isShareSrcStation = true;
				} 
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
		if(isShareSrcStation && isShareDestStation) {
			foreach(r1 in srcHgStation.GetUsingRoutes()) {
				foreach(r2 in destHgStation.GetUsingRoutes()) {
					if(r1 == r2 && r1.cargo == cargo) {
						HgLog.Warning("Cannot share station (same route found)."+this);
						return null;
					}
				}
			}
		}

		{
			local execMode = AIExecMode();
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
				AddRollback(destHgStation);
			}
			
			if(isShareSrcStation) {
				HgLog.Info("Share src station:"+srcHgStation.GetName()+" "+this);
				if(!srcHgStation.Share()) {
					HgLog.Warning("srcHgStation.Share failed."+this);
					return null;
				}
			} else if(!buildPathBeforeStation && !srcHgStation.BuildExec()) {
				HgLog.Warning("srcHgStation.BuildExec failed."+HgTile(srcHgStation.platformTile)+" "+this);
				srcHgStation = SearchSharableStation(src, srcStationFactory.GetStationType(), cargo, false);
				if(srcHgStation == null || !srcHgStation.Share()) {
					Rollback();
					return null;
				}
				HgLog.Info("Share src station:"+srcHgStation.GetName()+" "+this);
				isShareSrcStation = true;
			}
			if(!isShareSrcStation && !isNotRemoveStation && !buildPathBeforeStation) {
				AddRollback(srcHgStation);
			}
			
			if(!buildPathBeforeStation && srcHgStation.stationGroup == destHgStation.stationGroup) {
				Place.AddNgPathFindPair(src, dest, vehicleType);
				HgLog.Warning("Same stationGroup."+this);
				Rollback();
				return null;
			}
			if(path == null) {
				local pathBuilder = CreatePathBuilder(engineSet.engine, cargo);
				if(!pathBuilder.BuildPath( destHgStation.GetEntrances(), srcHgStation.GetEntrances())) {
					if(retryIfNoPathUsingSharableStation && (isShareSrcStation || isShareDestStation)) {
						HgLog.Warning("retryIfSharableStation."+this);
						retryIfNoPathUsingSharableStation = false;
						checkSharableStationFirst = false;
						Rollback();
						return DoBuild();
					}


					if(retryUsingSharableStationIfNoPath && !sharableStationOnly) {
						HgLog.Warning("BuildPath failed.retryBySharableStationOnlyIfPathNotFound"+this);
						sharableStationOnly = true;
						checkSharableStationFirst = true;
						Rollback();
						return DoBuild();
					}
				
					HgLog.Warning("BuildPath failed."+this);
					Place.AddNgPathFindPair(src, dest, vehicleType);
					Rollback();
					return null;
				}
				path = pathBuilder.path;
				local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile)
				if(path != null && distance > 40 && distance * 2 < path.GetTotalDistance(vehicleType)) {
					Place.AddNgPathFindPair(src, dest, vehicleType);
					HgLog.Warning("Too long path distance."+this);
					Rollback();
					return null;
				}
			}
			if(buildPathBeforeStation) {
				if(!isShareSrcStation) {
					if(!srcHgStation.BuildExec()) {
						HgLog.Warning("srcHgStation.BuildExec failed."+HgTile(srcHgStation.platformTile)+" "+this);
						Rollback();
						return null;
					}
					if(!isNotRemoveStation) {
						AddRollback(srcHgStation);
					}					
				}
				if(!isShareDestStation) {
					if(!destHgStation.BuildExec()) {
						HgLog.Warning("destHgStation.BuildExec failed."+HgTile(destHgStation.platformTile)+" "+this);
						Rollback();
						return null;
					}
					if(!isNotRemoveStation) {
						AddRollback(destHgStation);
					}					
				}
			}
			
			if(srcHgStation.stationGroup == null || destHgStation.stationGroup == null) {
				HgLog.Warning("Station was removed."+this); // 稀にDoInterval中にstationがRemoveされる事がある。
				Rollback();
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
			route.SetPath(path);
			
			if(!noDepot) {
				if(!route.BuildDepot(path)) {
					Place.AddNgPathFindPair(src, dest, vehicleType);
					HgLog.Warning("BuildDepot failed."+this);
					Rollback();
					return null;
				}
				if(!isNotRemoveDepot) {
					AddRollback(route.depot);
				}
				route.BuildDestDepot(path);
				if(!isNotRemoveDepot && route.destDepot != null) {
					AddRollback(route.destDepot);
				}
			}
			PlaceDictionary.Get().AddRoute(route);
			route.UpdateSavedData();
			ClearRollback();
			route.instances.push(route); // ChooseEngine内、インフラコスト計算に必要
			if(!isWaitingProduction) {
				route.BuildVehicleFirst();
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
				//HgLog.Info("Cannot get TownBus:"+station.place.GetName()+"["+AICargo.GetName(cargo)+"]");
			} else {
				townBus.CreateTransferRoutes(route, station);
			}
		}
	}

	function CheckTownTransfer(route, station) {
		foreach(cargo in HogeAI.Get().GetPaxMailCargos()) {
			CommonRouteBuilder.CheckTownTransferCargo(route,station,cargo);
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
