
class Route {

	static function GetAllRoutes() {
		local routes = [];
		routes.extend(TrainRoute.GetAll());
		routes.extend(RoadRoute.instances);
		routes.extend(WaterRoute.instances);
		return routes;
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
}

class CommonRoute extends Route {

	static function SearchRoute( routeInstances, srcPlace, destPlace, destStationGroup, cargo ) {
		foreach(route in routeInstances) {
			if(route.cargo == cargo) {
				if(route.srcHgStation.place.IsSamePlace(srcPlace)) {
					if(route.isTransfer && destStationGroup != null && route.destHgStation.stationGroup == destStationGroup) {
						return route;
					}
					if(!route.isTransfer && destPlace != null && route.destHgStation.place.IsSamePlace(destPlace)) {
						return route;
					}
				} else if(!route.isTransfer && route.IsBiDirectional() && route.destHgStation.place.IsSamePlace(srcPlace)) {
					if(destPlace != null && route.srcHgStation.place.IsSamePlace(destPlace)) {
						return route;
					}
				}
			}
		}
		return null;
	}
	
	static function ChooseEngineCargo(cargo, distance, vehicleType, production) {
		local roiBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		local enginelist = AIEngineList(vehicleType);
		if(vehicleType == AIVehicle.VT_ROAD) {
			enginelist.Valuate(AIEngine.HasPowerOnRoad, AIRoad.GetCurrentRoadType());
			enginelist.KeepValue(1);
		}
		enginelist.Valuate(AIEngine.CanRefitCargo, cargo);
		enginelist.KeepValue(1);
		production = max(20, production);
		enginelist.Valuate(function(e):(distance,cargo,roiBase, production) {
			local capacity = AIEngine.GetCapacity(e);
			local income = HogeAI.GetCargoIncome(distance, cargo, AIEngine.GetMaxSpeed(e), capacity * 30 / production) 
				* capacity * (100+AIEngine.GetReliability (e)) / 200 - AIEngine.GetRunningCost(e);
			if(roiBase) {
				return income * 100 / AIEngine.GetPrice(e);
			} else {
				return income;
			}
		});
		enginelist.KeepAboveValue(0);
		enginelist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		if (enginelist.Count() == 0) return null;
		return enginelist.Begin();
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
			local s = tostring();
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
	
	function BuildDepot(path) {
		local execMode = AIExecMode();
		if(GetVehicleType() == AIVehicle.VT_WATER) {
			//path = path.SubPathIndex(5);
		}
		depot = path.BuildDepot(GetVehicleType());
		if(GetVehicleType() == AIVehicle.VT_ROAD && depot == null) {
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
		
		local nonstopIntermediate = GetVehicleType() == AIVehicle.VT_WATER ? 0 :AIOrder.OF_NON_STOP_INTERMEDIATE;

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
			local production = AIStation.GetCargoPlanned(srcHgStation.GetAIStation(), cargo);
			if(production == 0) {
				production = srcHgStation.place.GetLastMonthProduction(cargo);
			}
			local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
			chosenEngine = CommonRoute.ChooseEngineCargo( cargo, distance, GetVehicleType(), production );
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
	
	
	function GetDestRoutes() {
		local routes = Route.GetAllRoutes();
		local destRoutes = [];
		if(isTransfer) {
			local destGroupStations = HgArray(destHgStation.stationGroup.hgStations);
			foreach(route in routes) {
				if(destGroupStations.Contains(route.srcHgStation)) {
					destRoutes.push(route);
				}
				if(route.IsBiDirectional() && destGroupStations.Contains(route.destHgStation)) {
					destRoutes.push(route);
				}
			}
		} else {
			local producing = destHgStation.place.GetProducing();
			foreach(route in routes) {
				local place = route.srcHgStation.place;
				if(place != null && place.IsSamePlace(producing)) {
					destRoutes.push(route);
				}
			}
			if(HogeAI.Get().stockpiled) {
				local accepting = destHgStation.place.GetAccepting();
				foreach(route in routes) {
					local place = route.destHgStation.place;
					if(route.cargo != cargo && place != null && place.IsSamePlace(producing)) {
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
			if(route instanceof TrainRoute || route instanceof TrainReturnRoute || route.HasRailDest(callRoutes)) {
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
				foreach(r in destRoutes) {
					if(r instanceof TrainRoute || r instanceof TrainReturnRoute || r.HasRailDest()) {
						destRoute = r;
					}
				}
				if(destRoute == null) {
					destRoute = destRoutes[0];
				}
			}
		}
		return destRoute;
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
	
	function CheckBuildVehicle() {
		local execMode = AIExecMode();
		local vehicleList = GetVehicleList();
		
		PerformanceCounter.Start();
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
		
		
		if(AIBase.RandRange(100) < 5 ) {
			local totalVehicles = AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, GetVehicleType());
			if(totalVehicles > GetMaxTotalVehicles() * 0.9 || IsDestOverflow()) {
				maxVehicles -= max(1,(maxVehicles * 0.1).tointeger());
				if(!GetDestRoute()) {
					maxVehicles = max(0, maxVehicles);
				} else {
					maxVehicles = max(5, maxVehicles);
				}
			} else if(needsAddtinalProducing || TrainRoute.instances.len()==0) {
				maxVehicles ++;
				maxVehicles = min(GetMaxVehicles(), maxVehicles);
			}
			local reduce = vehicleList.Count() - maxVehicles;
			foreach(vehicle,v in vehicleList) {
				if(reduce <= 0) {
					break;
				}
				if(!isBiDirectional && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1 ) {
					continue;
				}
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					//HgLog.Warning("Reduce vehicle.maxVehicles:"+maxVehicles+" vehicleList.Count():"+vehicleList.Count()+" "+this);
					AIVehicle.SendVehicleToDepot (vehicle);
					reduce --;
				}
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
						if(IsBiDirectional()) {
							cargoWaiting = min(cargoWaiting,AIStation.GetCargoWaiting(destHgStation.GetAIStation(),cargo));
						}
						local buildNum = max(1, cargoWaiting / capacity);
						buildNum = min(maxVehicles - vehicles.Count(), buildNum) - firstBuild;
						if(TrainRoute.instances.len() >= 1) {
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
		if(GetNumVehicles() >= CommonRoute.MAX_VEHICLES) {
			return false;
		}
		local hgStation = isDest ? destHgStation : srcHgStation;
		local destRoute = GetDestRoute();
		if(!destRoute) {
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
	
	function CheckRenewal() {
		local execMode = AIExecMode();
		
		if(!isClosed) {
			local destRoute = GetDestRoute();
			local routes = [];
			routes.extend(PlaceDictionary.Get().GetUsedAsSourceCargoByTrain(srcHgStation.place, cargo));
			if(IsBiDirectional()) {
				routes.extend(PlaceDictionary.Get().GetUsedAsSourceCargoByTrain(destHgStation.place, cargo));
			}
			foreach(route in routes) {
				//HgLog.Info("GetUsedTrainRoutes:"+route+" destRoute:"+destRoute+" "+this);
				if(destRoute != route && route.NeedsAdditionalProducing()) {
					isClosed = true;
					isRemoved = true;
					HgLog.Warning("Route Remove (Collided train route found)"+this);
				}
			}
			
			if(!isTmpClosed 
					&& ((!isTransfer && !IsValidDestStationCargo())
						|| (isTransfer && (!destRoute || destRoute.IsClosed())))) {
				if(!isTransfer) {
					HgLog.Warning("Route Close (dest can not accept)"+this);
					local destPlace = destHgStation.place.GetProducing();
					if(destPlace instanceof HgIndustry) {
						local stock = destPlace.GetStockpiledCargo(cargo) ;
						if(stock > 0 && TrainRoute.instances.len() >= 1) {
							isTmpClosed = true;
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
				isClosed = false;
				isTmpClosed = false;
				HgLog.Warning("Route ReOpen."+this);
			}
		}
		
		if(isClosed) {
			foreach(vehicle,v in GetVehicleList()) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}
			//TODO 全部いなくなったらstationを削除
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
		return destHgStation.GetName() + "<-"+(IsBiDirectional()?">":"") + srcHgStation.GetName() + "("+GetLabel()+")[" + AICargo.GetName(cargo) + "]"
	}
}

class CommonRouteBuilder {
	
	destStationGroup = null;
	destPlace = null;
	srcPlace = null;
	cargo = null;
	
	constructor(dest, srcPlace, cargo) {
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

	function GetDestLocation() {
		if(destStationGroup != null) {
			return destStationGroup.hgStations[0].platformTile;
		} else {
			return destPlace.GetLocation();
		}
	}
	
	function ExistsSameRoute() {
		return CommonRoute.SearchRoute( GetRouteClass().instances, srcPlace, destPlace, destStationGroup, cargo ) != null;
		/*
		if( IsBiDirectional() ) {
			if( CommonRoute.SearchRoute( RoadRoute.instances, destPlace, srcPlace, null, cargo ) != null ) {
				return true;
			}
		}
		return false;*/
	}
	
	function IsBiDirectional() {
		return destPlace != null && destPlace.GetProducing().IsTreatCargo(cargo);
	}
	
	function Build() {
		local explain = GetLabel()+" route "+(destPlace != null ? destPlace : destStationGroup.hgStations[0]).GetName()+"<-"+srcPlace.GetName();
	
		if(ExistsSameRoute()) {
			HgLog.Info("Already exist."+explain);
			return null;
		}
		
		if(destPlace != null) {
			if(destPlace.GetProducing().IsTreatCargo(cargo)) {
				destPlace = destPlace.GetProducing();
			}
		}
	
		local dest = destPlace != null ? destPlace : destStationGroup.hgStations[0].platformTile;
		if(Place.IsNgPathFindPair(srcPlace, dest, GetVehicleType())) {
			HgLog.Warning("IsNgPathFindPair==true "+explain);
			return null;
		}

		local testMode = AITestMode();
		local engine = CommonRoute.ChooseEngineCargo(cargo, srcPlace.DistanceManhattan(GetDestLocation()), GetVehicleType(), srcPlace.GetLastMonthProduction(cargo));
		if(engine==null) {
			HgLog.Warning("No suitable engine. "+explain);
			return null;
		}
		
		local stationFactory = CreateStationFactory();
		local destHgStation = null;
		local isTransfer = null;
		if(destStationGroup != null) {
			isTransfer = true;
			local destTransferStation = destStationGroup.hgStations[0];
			stationFactory.nearestFor = destTransferStation.platformTile;
			destHgStation = stationFactory.SelectBestHgStation( 
				destStationGroup.GetStationCandidatesInSpread(HogeAI.Get().maxStationSpread, stationFactory),
				destTransferStation.platformTile, 
				srcPlace.GetLocation(), "transfer "+GetLabel()+" stop["+destTransferStation.GetName()+"]");
		} else if(destPlace != null) {
			isTransfer = false;
			if(destPlace instanceof TownCargo) {
				stationFactory.nearestFor = srcPlace.GetLocation();
			}
			destHgStation = stationFactory.CreateBest(destPlace, cargo, srcPlace.GetLocation());
		} else {
			HgLog.Warning("dest is not set."+explain);
			return null;
		}
		local isShareDestStation = false;
		if(destHgStation == null) {
			destHgStation = HgStation.SearchStation(destPlace == null ? destStationGroup : destPlace, stationFactory.GetStationType(), cargo, true);
			if(destHgStation == null) {
				Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
				HgLog.Warning("No destStation."+explain);
				return null;
			}
			HgLog.Warning("Share dest station:"+destHgStation.GetName()+" "+explain);
			isShareDestStation = true;
		}
		local list = HgArray(destHgStation.GetTiles()).GetAIList();
		HogeAI.notBuildableList.AddList(list);
		if(srcPlace instanceof TownCargo) {
			stationFactory.nearestFor = destHgStation.platformTile;
		}
		local srcHgStation = stationFactory.CreateBest(srcPlace, cargo, destHgStation.platformTile);
		HogeAI.notBuildableList.RemoveList(list);
		local isShareSrcStation = false;
		if(srcHgStation == null) {
			srcHgStation = HgStation.SearchStation(srcPlace, stationFactory.GetStationType(), cargo, false);				
			if(srcHgStation == null) {
				Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
				HgLog.Warning("stationFactory.CreateBest failed."+explain);
				return null;
			}
			HgLog.Warning("Share src station:"+srcHgStation.GetName()+" "+explain);
			isShareSrcStation = true;
		}

		local execMode = AIExecMode();
		local rollbackFacitilies = [];
		
		if(!isShareDestStation && !destHgStation.BuildExec()) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("destHgStation.BuildExec failed."+explain);
			return null;
		}
		if(!isShareDestStation) {
			rollbackFacitilies.push(destHgStation);
		}
		
		if(!isShareSrcStation && !srcHgStation.BuildExec()) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("srcHgStation.BuildExec failed."+explain);
			Rollback(rollbackFacitilies);
			return null;
		}
		if(!isShareSrcStation) {
			rollbackFacitilies.push(srcHgStation);
		}
		
		if(srcHgStation.stationGroup == destHgStation.stationGroup) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("Same stationGroup."+explain);
			Rollback(rollbackFacitilies);
			return null;
		}
		
		local pathBuilder = CreatePathBuilder();
		pathBuilder.engine = engine;
		pathBuilder.cargo = cargo;
		if(!pathBuilder.BuildPath(destHgStation.GetEntrances(), srcHgStation.GetEntrances())) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("BuildPath failed."+explain);
			Rollback(rollbackFacitilies);
			return null;
		}
		local distance = AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile)
		if(distance > 40 && distance * 3 / 2 < pathBuilder.path.GetTotalDistance()) {
			Place.AddNgPathFindPair(srcPlace, dest, GetVehicleType());
			HgLog.Warning("Too long path distance."+explain);
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
			HgLog.Warning("BuildDepot failed."+explain);
			Rollback(rollbackFacitilies);
			return null;
		}
		if(distance > 30) {
			route.BuildDestDepot(pathBuilder.path);
		}
		route.SetPath(pathBuilder.path);
		local vehicle = route.BuildVehicle();
		if(vehicle==null) {
			HgLog.Warning("BuildVehicle failed."+explain);
			Rollback(rollbackFacitilies);
			return null;
		}
		route.CloneVehicle(vehicle);
		//Place.SetUsedPlaceCargo(srcPlace,cargo); NgPathFindPairで管理する
		route.instances.push(route);
		HgLog.Info("CommonRouteBuilder.Build succeeded."+route);
		
		PlaceDictionary.Get().AddRoute(route);
		return route;
	}
	
	function Rollback(facilities) {
		foreach(f in facilities) {
			f.Remove();
		}
	}
}