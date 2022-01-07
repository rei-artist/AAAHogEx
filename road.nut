class MyRoadPF extends Road {
	_cost_level_crossing = null;
	_goals = null;
}

function MyRoadPF::InitializePath(sources, goals, ignoreTiles) {
	::Road.InitializePath(sources, goals, ignoreTiles);
	_goals = AIList();
	for (local i = 0; i < goals.len(); i++) {
		_goals.AddItem(goals[i], 0);
	}
}

function MyRoadPF::_Cost(self, path, new_tile, new_direction) {
	local cost = ::Road._Cost(self, path, new_tile, new_direction);
	if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_RAIL)) cost += self._cost_level_crossing;
	return cost;
}

function MyRoadPF::_GetTunnelsBridges(last_node, cur_node, bridge_dir) {
	local slope = AITile.GetSlope(cur_node);
	if (slope == AITile.SLOPE_FLAT && AITile.IsBuildable(cur_node + (cur_node - last_node))) return [];
	local tiles = [];
	for (local i = 2; i < this._max_bridge_length; i++) {
		local bridge_list = AIBridgeList_Length(i + 1);
		local target = cur_node + i * (cur_node - last_node);
		if (!bridge_list.IsEmpty() && !_goals.HasItem(target) &&
				AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), cur_node, target)) {
			tiles.push([target, bridge_dir]);
		}
	}

	if (slope != AITile.SLOPE_SW && slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE && slope != AITile.SLOPE_NE) return tiles;
	local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_node);
	if (!AIMap.IsValidTile(other_tunnel_end)) return tiles;

	local tunnel_length = AIMap.DistanceManhattan(cur_node, other_tunnel_end);
	local prev_tile = cur_node + (cur_node - other_tunnel_end) / tunnel_length;
	if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && tunnel_length >= 2 &&
			prev_tile == last_node && tunnel_length < _max_tunnel_length && AITunnel.BuildTunnel(AIVehicle.VT_ROAD, cur_node)) {
		tiles.push([other_tunnel_end, bridge_dir]);
	}
	return tiles;
}

class RoadRoute extends Route {
	static MAX_VEHICLES = 30;
	static instances = [];

	static function SearchRoute( srcPlace, destPlace, destStationGroup, cargo ) {
		foreach(route in RoadRoute.instances) {
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

	static function SaveStatics(data) {
		local array = [];
		foreach(route in RoadRoute.instances) {
			local t = {};
			t.cargo <- route.cargo;
			t.isTransfer <- route.isTransfer;
			t.srcHgStation <- route.srcHgStation.id;
			t.destHgStation <- route.destHgStation.id;
			t.vehicleGroup <- route.vehicleGroup;
			t.depot <- route.depot;
			t.destDepot <- route.destDepot;
			t.isClosed <- route.isClosed;
			t.isTmpClosed <- route.isTmpClosed;
			t.isRemoved <- route.isRemoved;
			t.maxVehicles <- route.maxVehicles;
			t.lastTreatStockpile <- route.lastTreatStockpile;
			t.useDepotOrder <- route.useDepotOrder;
			array.push(t);
		}
		data.roadRoutes <- array;
	}
	
	static function LoadStatics(data) {
		RoadRoute.instances.clear();
		foreach(t in data.roadRoutes) {
			local route = RoadRoute(
				t.cargo, 
				HgStation.worldInstances[t.srcHgStation], 
				HgStation.worldInstances[t.destHgStation], 
				t.isTransfer, 
				t.vehicleGroup );
			route.depot = t.depot;
			route.destDepot = t.destDepot;
			route.isClosed = t.isClosed;
			route.isTmpClosed = t.isTmpClosed;
			route.isRemoved = t.rawin("isRemoved") ? t.isRemoved : false;
			route.maxVehicles = t.maxVehicles;
			route.lastTreatStockpile = t.lastTreatStockpile;
			route.useDepotOrder = t.useDepotOrder;
			HgLog.Info("load roadroute:"+route);
			
			RoadRoute.instances.push(route);	
			PlaceDictionary.Get().AddRoute(route);
		}
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
	lastTreatStockpile = null;
	useDepotOrder = null;
	
	chosenEngine = null;
	lastChooseEngineDate = null;
	destRoute = null;
	hasRailDest = null;
	
	constructor(cargo, srcHgStation, destHgStation, isTransfer, vehicleGroup=null) {
		this.cargo = cargo;
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.isTransfer = isTransfer;
		if(vehicleGroup==null) {
			this.vehicleGroup = AIGroup.CreateGroup(AIVehicle.VT_ROAD);
		} else {
			this.vehicleGroup = vehicleGroup;
		}
		this.isClosed = false;
		this.isTmpClosed = false;
		this.isRemoved = false;
		this.useDepotOrder = true;
		this.maxVehicles = GetMaxVehicles();
	}
	
	function BuildDepot(path) {
		local execMode = AIExecMode();
		depot = path.BuildDepot(true);
		if(depot == null) {
			depot = srcHgStation.BuildDepot();
		}
		return depot != null;
	}
	
	function BuildDestDepot(path) {
		local execMode = AIExecMode();
		destDepot = path.Reverse().BuildDepot(true);
		return destDepot != null;
	}
	
	function IsBiDirectional() {
		return !isTransfer && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
	}
	
	function BuildVehicle() {
		//HgLog.Info("BuildVehicle."+this);
		local execMode = AIExecMode();
		if(depot == null) {
			return null;
		}
		local engine = ChooseEngine();
		if(engine == null) {
			HgLog.Warning("Not found suitable engine.(RoadRoute) "+this);
			return null;
		}
		HogeAI.WaitForPrice(AIEngine.GetPrice(engine));
		local vehicle = AIVehicle.BuildVehicle(depot, engine);
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("RoadRoute.BuildVehicle failed "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIVehicle.RefitVehicle(vehicle, cargo);
		AIGroup.MoveVehicle(vehicleGroup, vehicle);

		if(useDepotOrder) {
			AIOrder.AppendOrder(vehicle, depot, AIOrder.OF_NON_STOP_INTERMEDIATE );
		}
		local isBiDirectional = IsBiDirectional();
		if(isBiDirectional) {
			AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
		} else {
			AIOrder.AppendOrder(vehicle, srcHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_FULL_LOAD_ANY);
		}
		if(useDepotOrder) {
			AIOrder.AppendOrder(vehicle, depot, AIOrder.OF_SERVICE_IF_NEEDED );
		}
		
		if(destDepot != null) {
			AIOrder.AppendOrder(vehicle, destDepot, AIOrder.OF_NON_STOP_INTERMEDIATE );
		}
		if(isTransfer) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_TRANSFER + AIOrder.OF_NO_LOAD);
		} else if(isBiDirectional) {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
		} else {
			AIOrder.AppendOrder(vehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		}
		if(destDepot != null) {
			AIOrder.AppendOrder(vehicle, destDepot, AIOrder.OF_SERVICE_IF_NEEDED ); //5 or 6
		}
		/*
		AIOrder.SetOrderCompareValue(vehicle, 1, 80);
		AIOrder.SetOrderCompareFunction(vehicle, 1, AIOrder.CF_MORE_EQUALS );
		AIOrder.SetOrderCondition(vehicle, 1, AIOrder.OC_RELIABILITY );
		AIOrder.SetOrderJumpTo (vehicle, 1, 3)*/
		
		AIVehicle.StartStopVehicle(vehicle);
		return vehicle;
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
			HgLog.Warning("RoadRoute.CloneVehicle failed. "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIGroup.MoveVehicle(vehicleGroup, result);
		AIVehicle.StartStopVehicle(result);
		return result;
	}

	static function ChooseEngineCargo(cargo, distance) {
		local roiBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		local enginelist = AIEngineList(AIVehicle.VT_ROAD);
		enginelist.Valuate(AIEngine.HasPowerOnRoad, AIRoad.GetCurrentRoadType());
		enginelist.KeepValue(1);
		enginelist.Valuate(AIEngine.CanRefitCargo, cargo);
		enginelist.KeepValue(1);
		enginelist.Valuate(function(e):(distance,cargo,roiBase) {
			local income = HogeAI.GetCargoIncome(distance, cargo, AIEngine.GetMaxSpeed(e)) * AIEngine.GetCapacity(e) * (100+AIEngine.GetReliability (e)) / 200 - AIEngine.GetRunningCost(e);
			if(income<0) {
//				HgLog.Info("RoadRoute predictIncome: "+income+ " "+AIEngine.GetName(e)+" "+this);
			}
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

	function ChooseEngine() {
		if(chosenEngine == null || lastChooseEngineDate + 30 < AIDate.GetCurrentDate()) {
			chosenEngine = RoadRoute.ChooseEngineCargo(cargo, AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile));
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
		local routes = RouteUtils.GetAllRoutes();
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
			//HgLog.Info("SellRoadVehicle:"+sellCounter+" "+this);
		}
		
		if(isClosed || isTmpClosed) {
			return;
		}
		
		local isBiDirectional = IsBiDirectional();

		if(AIBase.RandRange(100) < 100) {
			//HgLog.Warning("check SendVehicleToDepot "+this+" vehicleList:"+vehicleList.Count());
			foreach(vehicle,v in vehicleList) {
				if((!isBiDirectional && AIVehicle.GetCargoLoad(vehicle,cargo) >= 1) || AIVehicle.GetAge(vehicle) <= 365) {
					continue;
				}
				local notProfitable = AIVehicle.GetProfitLastYear (vehicle) < 0 && AIVehicle.GetProfitThisYear(vehicle) < 0;
				
				if((notProfitable || AIVehicle.GetAgeLeft(vehicle) <= 600)
						&& (AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
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
			if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_ROAD) > HogeAI.Get().maxRoadVehicle * 0.9 || IsDestOverflow()) {
				maxVehicles -= max(1,(maxVehicles * 0.1).tointeger());
				if(!GetDestRoute()) {
					maxVehicles = max(0, maxVehicles);
				} else {
					maxVehicles = max(5, maxVehicles);
				}
			} else if(needsAddtinalProducing) {
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
						local buildNum = AIStation.GetCargoWaiting(srcHgStation.GetAIStation(),cargo) / capacity;
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
							for(local i=0; i<buildNum; i++) {
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
		if(GetNumVehicles() >= RoadRoute.MAX_VEHICLES) {
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
		if(isDest) {
			return AIStation.GetCargoWaiting (destHgStation.GetAIStation(), cargo) > 300;
		} else {
			return AIStation.GetCargoWaiting (srcHgStation.GetAIStation(), cargo) > 300;
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
			foreach(route in PlaceDictionary.Get().GetUsedAsSourceCargoByTrain(srcHgStation.place, cargo)) {
				//HgLog.Info("GetUsedTrainRoutes:"+route+" destRoute:"+destRoute+" "+this);
				if(destRoute != route && route.NeedsAdditionalProducing()) {
					isClosed = true;
					isRemoved = true;
					HgLog.Warning("RoadRoute Remove (Collided train route found)"+this);
				}
			}
			
			if(!isTmpClosed 
					&& ((!isTransfer && !IsValidDestStationCargo())
						|| (isTransfer && (!destRoute || destRoute.IsClosed())))) {
				if(!isTransfer) {
					HgLog.Warning("RoadRoute Close (dest can not accept)"+this);
					local destPlace = destHgStation.place.GetProducing();
					if(destPlace instanceof HgIndustry) {
						local stock = destPlace.GetStockpiledCargo(cargo) ;
						if(stock > 0 && TrainRoute.instances.len() >= 1) {
							isTmpClosed = true;
						}
					}
				} else {
					HgLog.Warning("RoadRoute Close (DestRoute["+destRoute+"] closed)"+this);
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
				HgLog.Warning("RoadRoute ReOpen road route."+this);
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
		
		foreach(vehicle,v in GetVehicleList()) {
			if(engine != AIVehicle.GetEngineType(vehicle)) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}
		}
	}
	

	function OnVehicleLost(vehicle) {
		HgLog.Warning("RoadRoute OnVehicleLost  "+this); //TODO: 再度道路を作る
		local execMode = AIExecMode();
		if(!RoadBuilder().BuildRoad(destHgStation.GetEntrances(), srcHgStation.GetEntrances(), true)) {
			HgLog.Warning("RoadRoute removed.(Rebuild road failed) "+this);
			isClosed = true;
			isRemoved = true;
			foreach(vehicle,v in GetVehicleList()) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}
		} else {
			HgLog.Warning("Rebuild road route succeeded"); //TODO: 再度道路を作る
		}
	}
	
	function _tostring() {
		return destHgStation.GetName() + "<-" + srcHgStation.GetName() + "(road)[" + AICargo.GetName(cargo) + "]"
	}
}


class RoadRouteBuilder {
	
	static function BuildRoadUntilFree(p1,p2) {
		return BuildUtils.RetryUntilFree( function():(p1,p2) {
			return AIRoad.BuildRoad(p1,p2);
		});
	}
	
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
	
	function GetDestLocation() {
		if(destStationGroup != null) {
			return destStationGroup.hgStations[0].platformTile;
		} else {
			return destPlace.GetLocation();
		}
	}
	
	function ExistsSameRoute() {
		if( RoadRoute.SearchRoute( srcPlace, destPlace, destStationGroup, cargo ) != null ) {
			return true;
		}
		if( IsBiDirectional() ) {
			if( RoadRoute.SearchRoute( destPlace, srcPlace, null, cargo ) != null ) {
				return true;
			}
		}
		return false;
	}
	
	function IsBiDirectional() {
		return destPlace != null && destPlace.GetProducing().IsTreatCargo(cargo);
	}
	
	function Build() {
		if(ExistsSameRoute()) {
			HgLog.Info("Already exist road route "+(destPlace != null ? destPlace : destStationGroup.hgStations[0]).GetName()+"<-"+srcPlace.GetName());
			return null;
		}
		
		if(destPlace != null) {
			if(destPlace.GetProducing().IsTreatCargo(cargo)) {
				destPlace = destPlace.GetProducing();
			}
		}
	
		local dest = destPlace != null ? destPlace : destStationGroup.hgStations[0].platformTile;
		if(Place.IsNgPathFindPair(srcPlace, dest)) {
			HgLog.Warning("IsNgPathFindPair==true");
			return null;
		}

		local testMode = AITestMode();
		local engine = RoadRoute.ChooseEngineCargo(cargo, srcPlace.DistanceManhattan(GetDestLocation()));
		if(engine==null) {
			HgLog.Warning("No suitable engine.");
			return null;
		}
		
		local roadStationFactory = RoadStationFactory(AICargo.HasCargoClass(cargo,AICargo.CC_PASSENGERS) ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
		local destHgStation = null;
		local isTransfer = null;
		if(destStationGroup != null) {
			isTransfer = true;
			local destTransferStation = destStationGroup.hgStations[0];
			roadStationFactory.nearestFor = destTransferStation.platformTile;
			destHgStation = roadStationFactory.SelectBestHgStation( 
				destStationGroup.GetStationCandidatesInSpread(HogeAI.Get().maxStationSpread, roadStationFactory),
				destTransferStation.platformTile, 
				srcPlace.GetLocation(), "transfer road stop["+destTransferStation.GetName()+"]");
		} else if(destPlace != null) {
			isTransfer = false;
			if(destPlace instanceof TownCargo) {
				roadStationFactory.nearestFor = srcPlace.GetLocation();
			}
			destHgStation = roadStationFactory.CreateBest(destPlace, cargo, srcPlace.GetLocation());
		} else {
			HgLog.Warning("dest is not set.");
			return null;
		}
		if(destHgStation == null) {
			Place.AddNgPathFindPair(srcPlace, dest);
			HgLog.Warning("No destStation.");
			return null;
		}
		local list = HgArray(destHgStation.GetTiles()).GetAIList();
		HogeAI.notBuildableList.AddList(list);
		if(srcPlace instanceof TownCargo) {
			roadStationFactory.nearestFor = destHgStation.platformTile;
		}
		local srcHgStation = roadStationFactory.CreateBest(srcPlace, cargo, destHgStation.platformTile);
		HogeAI.notBuildableList.RemoveList(list);
		if(srcHgStation == null) {			
			Place.AddNgPathFindPair(srcPlace, dest);
			HgLog.Warning("roadStationFactory.CreateBest failed.");
			return null;
		}

		local execMode = AIExecMode();
		if(!destHgStation.BuildExec()) {
			Place.AddNgPathFindPair(srcPlace, dest);
			HgLog.Warning("destHgStation.BuildExec failed.");
			return null;
		}
		if(!srcHgStation.BuildExec()) {
			Place.AddNgPathFindPair(srcPlace, dest);
			HgLog.Warning("srcHgStation.BuildExec failed.");
			return null;
		}
		local roadBuilder = RoadBuilder();
		roadBuilder.engine = engine;
		roadBuilder.cargo = cargo;
		if(!roadBuilder.BuildRoad(destHgStation.GetEntrances(), srcHgStation.GetEntrances())) {
			Place.AddNgPathFindPair(srcPlace, dest);
			HgLog.Warning("BuildRoad failed.");
			return null;
		}
		local roadRoute = RoadRoute(cargo, srcHgStation, destHgStation, isTransfer);
		if(!roadRoute.BuildDepot(roadBuilder.path)) {
			Place.AddNgPathFindPair(srcPlace, dest);
			HgLog.Warning("BuildDepot failed.");
			return null;
		}
		if(AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile) > 30) {
			roadRoute.BuildDestDepot(roadBuilder.path);
		}
		local vehicle = roadRoute.BuildVehicle();
		if(vehicle==null) {
			HgLog.Warning("BuildVehicle failed.");
			return null;
		}
		roadRoute.CloneVehicle(vehicle);
		//Place.SetUsedPlaceCargo(srcPlace,cargo); NgPathFindPairで管理する
		RoadRoute.instances.push(roadRoute);
		HgLog.Info("RoadRouteBuilder.Build succeeded.");
		
		PlaceDictionary.Get().AddRoute(roadRoute);
		return roadRoute;
	}
}

class RoadBuilder {	
	path = null;
	cargo = null;
	engine = null;
	ignoreTiles = null;
	
	constructor() {
		ignoreTiles = [];
	}

	function BuildRoad(starts ,goals, suppressInterval=false) {
		local pathfinder = MyRoadPF();
		local pathFindLimit = 100;
		pathfinder._cost_level_crossing = 1000;
		pathfinder._cost_coast = 50;
		pathfinder._cost_slope = 0;
		pathfinder._cost_bridge_per_tile = 100;
		pathfinder._cost_tunnel_per_tile = 100;
		pathfinder._max_bridge_length = 20;
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000) {
			pathfinder._max_tunnel_length = 6;
		}
		if(IsConsiderSlope()) {
			pathfinder._cost_slope = 200;
			pathfinder._cost_no_existing_road = 100;
			pathfinder._cost_coast = 100;
			pathfinder._estimate_rate = 1;
			pathFindLimit = 500;
		}
		local distance = AIMap.DistanceManhattan(starts[0],goals[0]);
		if(distance > 200) {
			pathFindLimit = 400;
		}
		
		pathfinder.InitializePath(starts, goals, ignoreTiles);
		
		
		HgLog.Info("RoadRoute Pathfinding...limit:"+pathFindLimit+" distance:"+distance);
		local counter = 0;
		local path = false;
		while (path == false && counter < pathFindLimit) {
			path = pathfinder.FindPath(100);
			counter++;
			if(!suppressInterval) {
				HogeAI.DoInterval();
			}
		}
		if (path != null && path != false) {
			HgLog.Info("RoadRoute Path found. (" + counter + ")");
		} else {
			path = null;
			HgLog.Warning("RoadRoute Pathfinding failed.");
			return false;
		}
		this.path = path = Path.FromPath(path);
		
		while (path != null) {
			local par = path.GetParent();
			if (par != null) {
				local last_node = path.GetTile();
				if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
					HogeAI.WaitForMoney(1000);
					if (!RoadRouteBuilder.BuildRoadUntilFree(path.GetTile(), par.GetTile())) {
						local error = AIError.GetLastError();
						if(error != AIError.ERR_ALREADY_BUILT) {
							HgLog.Warning("BuildRoad failed."+HgTile(path.GetTile())+" "+HgTile(par.GetTile())+" "+AIError.GetLastErrorString());
							return RetryBuildRoad(path, starts);
						}
					}
				} else {
					if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
						if (AIRoad.IsRoadTile(path.GetTile())) {
							AITile.DemolishTile(path.GetTile());
						}
						HogeAI.WaitForMoney(20000);
						if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
							if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
								HgLog.Warning("BuildTunnel(Road) failed."+HgTile(path.GetTile())+" "+HgTile(par.GetTile())+" "+AIError.GetLastErrorString());
								return RetryBuildRoad(path, starts);
							}
						} else {
							local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
							bridge_list.Valuate(AIBridge.GetMaxSpeed);
							bridge_list.Sort(AIList.SORT_BY_VALUE, false);
							if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
								HgLog.Warning("BuildBridge(Road) failed."+HgTile(path.GetTile())+" "+HgTile(par.GetTile())+" "+AIError.GetLastErrorString());
								return RetryBuildRoad(path, starts);
							}
						}	
					}
				}
			}
			path = par;
		}
		HgLog.Info("BuildRoad Pathfinding succeeded");
		return true;
	}
	
	function RetryBuildRoad(curPath, goals) {
		HgLog.Warning("RetryBuildRoad");
		if(AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) { // 高すぎて失敗した可能性があるため、繰り返さないようにする
			ignoreTiles.push(curPath.GetTile());
		}
		local startPath = this.path.SubPathEnd(curPath.GetTile());
		if(startPath == null) {
			HgLog.Warning("No start tiles("+curPath.GetTile()+")");
			return false;
		}
		return BuildRoad(startPath.GetTiles(), goals);
	}
	
	function IsConsiderSlope() {
		if(engine == null || cargo == null) {
			return false;
		}
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 100000 && RouteUtils.GetAllRoutes().len()>=1) {
			return false;
		}
		local weight = VehicleUtils.GetCargoWeight(cargo, AIEngine.GetCapacity(engine));
		return VehicleUtils.GetForce(AIEngine.GetMaxTractiveEffort(engine), AIEngine.GetPower(engine), AIEngine.GetMaxSpeed(engine)/2) 
			- VehicleUtils.GetSlopeForce(weight,1,weight) < 0;
	}
	
}

class TownBus {
	
	static instances = [];
	
	static function SaveStatics(data) {
		local array = [];
		foreach(townBus in TownBus.instances) {
			local t = {};
			t.town <- townBus.town;
			t.stations <- townBus.stations;
			t.depot <- townBus.depot;
			t.removeBus <- townBus.removeBus;
			array.push(t);
		}
		data.townBus <- array;
	}
	
	static function LoadStatics(data) {
		TownBus.instances.clear();
		foreach(t in data.townBus) {
			local townBus = TownBus(t.town);
			townBus.stations = t.stations;
			townBus.depot = t.depot;
			townBus.removeBus = t.removeBus;
			TownBus.instances.push(townBus);
		}
	}
	
	
	static function Check(tile, ignoreTileList=null) {
	/*
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 200000) {
			return;
		}*/ //TODO busの採算性のチェック
		local authorityTown = AITile.GetTownAuthority (tile);
		if(!AITown.IsValidTown(authorityTown)) {
			return;
		}
		TownBus.CheckTown(authorityTown, ignoreTileList);
	}
	
	static function CheckTown(authorityTown, ignoreTileList=null) {
		/*if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 200000) {
			return;
		}*/
		foreach(townBus in TownBus.instances) {
			if(townBus.town == authorityTown) {
				return;
			}
		}
		local aiExec = AIExecMode();
		local townBus = TownBus(authorityTown);
		TownBus.instances.push(townBus);
		if(!townBus.BuildBusStops()) {
			return;
		}
		if(!townBus.BuildBusDepot(ignoreTileList != null ? ignoreTileList : AIList())) {
			return;
		}
		townBus.BuildBus();
	}
	
	static function GetByTown(town) {
		foreach(townBus in TownBus.instances) {
			if(townBus.town == town) {
				return townBus;
			}
		}
		return null;
	}
	
	town = null;
	stations = null;
	depot = null;
	removeBus = null;
	
	
	
	constructor(town) {
		this.town = town;
		this.stations = [];
	}
	
	function BuildBus() {
		local currentBus = GetBus();
	
		local busEngine = ChooseBusEngine();
		if(busEngine == null) {
			HgLog.Warning("Not found bus engine "+this);
			return false;
			
		}
		HogeAI.WaitForPrice(AIEngine.GetPrice(busEngine));
		local bus = AIVehicle.BuildVehicle(depot, busEngine);
		if(!AIVehicle.IsValidVehicle(bus)) {
			HgLog.Warning("BuildBus failed "+this);
			return false;
		}
		AIVehicle.RefitVehicle(bus, HogeAI.GetPassengerCargo());

		if(currentBus != null) {
			AIOrder.ShareOrders(bus, currentBus);
		} else {
			AIOrder.AppendOrder(bus, stations[0], AIOrder.OF_NON_STOP_INTERMEDIATE);
			AIOrder.AppendOrder(bus, stations[1], AIOrder.OF_NON_STOP_INTERMEDIATE);
		}
		AIVehicle.StartStopVehicle(bus);
		return true;
	}
	
	function ChangeTransferOrder(toPlatform, srcStation) {
		local bus = GetBus();
		AIOrder.RemoveOrder(bus,AIOrder.GetOrderCount(bus)-1);
		AIOrder.RemoveOrder(bus,AIOrder.GetOrderCount(bus)-1);
		AIOrder.AppendOrder(bus, srcStation, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_FULL_LOAD_ANY);
		AIOrder.AppendOrder(bus, toPlatform, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_TRANSFER | AIOrder.OF_NO_LOAD);
	}

	function ChooseBusEngine() {
		return RoadRoute.ChooseEngineCargo(HogeAI.GetPassengerCargo(), AIMap.DistanceManhattan(stations[0],stations[1]));
	/*
		local enginelist = AIEngineList(AIVehicle.VT_ROAD);
		enginelist.Valuate(AIEngine.HasPowerOnRoad, AIRoad.GetCurrentRoadType());
		enginelist.KeepValue(1);
		enginelist.Valuate(AIEngine.CanRefitCargo, HogeAI.GetPassengerCargo());
		enginelist.KeepValue(1);
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) <= 600000) {
			enginelist.Valuate(function(e){
				return AIEngine.GetPrice(e)+AIEngine.GetRunningCost(e) * 3;
			});
		} else {
			enginelist.Valuate(function(e){
				return AIEngine.GetRunningCost(e);
			});
		}
		enginelist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING );
		if (enginelist.Count() == 0) {
			return null;
		}
		return enginelist.Begin();*/
	}
	
	function BuildBusStops() {
		local aiTest = AITestMode();
		local tile = AITown.GetLocation(town);
		local rect = Rectangle.Center(HgTile(tile),5);
		 
		local tiles = HgArray.AIListKey(rect.GetTileList()).array;
		local stationA = FindStationTile(tiles);
		tiles.reverse();
		local stationB = FindStationTile(tiles);
		if(stationA != null && stationB != null && stationA[0] != stationB[0]) {
			local aiExec = AIExecMode();
			HogeAI.WaitForMoney(10000);
			if(!AIRoad.BuildDriveThroughRoadStation (stationA[0], stationA[1], AIRoad.ROADVEHTYPE_BUS , AIStation.STATION_NEW)) {
				HgLog.Warning("failed BuildDriveThroughRoadStation"+HgTile(stationA[0])+" "+this);
				return false;
			}
			stations.push(stationA[0]);
			if(!AIRoad.BuildDriveThroughRoadStation (stationB[0], stationB[1], AIRoad.ROADVEHTYPE_BUS , AIStation.STATION_NEW)) {
				HgLog.Warning("failed BuildDriveThroughRoadStation"+HgTile(stationB[0])+" "+this);
				return false;
			}
			stations.push(stationB[0]);
			return true;
		}
		return false;
	}
	
	function BuildBusDepot(ignoreTileList) {
		local aiTest = AITestMode();
		local dirs = [AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(0, -1)];
		for(local i=5; i<=15; i+=2) {
			local rect = Rectangle.Center(HgTile(AITown.GetLocation(town)),i);
			foreach(tile in HgArray.AIListKey(rect.GetTileList()).array) {
				if(!AIRoad.IsRoadTile(tile) || AITile.GetOwner(tile) != AICompany.COMPANY_INVALID) { 
					continue;
				}
				foreach(dir in dirs) {
					local depotTile = tile + dir;
					if(ignoreTileList.HasItem(depotTile)) {
						continue;
					}
					if(AIRoad.BuildRoadDepot (depotTile, tile)) {
						local aiExec = AIExecMode();
						HogeAI.WaitForMoney(10000);
						if(!AIRoad.AreRoadTilesConnected(tile, depotTile) && !AIRoad.BuildRoad(tile, depotTile)) {
							continue;
						}
						if(!AIRoad.BuildRoadDepot (depotTile, tile)) {
							HgLog.Warning("failed BuildRoadDepot"+HgTile(depotTile)+" "+this);
							return false;
						}
						this.depot = depotTile;
						return true;
					}
				}
			}
		}
		HgLog.Warning("failed BuildRoadDepot"+this);
		return false;
	}
	
	function FindStationTile(tiles) {
		local dirs = [AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(0, 1)];
		local passengerCargo = HogeAI.GetPassengerCargo();
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP);
		foreach(tile in tiles) {
			if(!AIRoad.IsRoadTile (tile) || AITile.GetCargoAcceptance(tile,passengerCargo, 1, 1, radius) <= 8 || AITile.GetOwner(tile) != AICompany.COMPANY_INVALID) {
				continue;
			}
			foreach(dir in dirs) {
				if(AIRoad.BuildDriveThroughRoadStation (tile, tile + dir, AIRoad.ROADVEHTYPE_BUS , AIStation.STATION_NEW)) {
					return [tile,tile+dir];
				}
			}
			
		}
		
		return null;
	}
	
	function CreateTransferRoadRoute(number, srcStationTile, toHgStation) {
		local srcHgStation = PieceStation(srcStationTile);
		srcHgStation.name = AITown.GetName(town)+" #"+number;
		srcHgStation.place = GetPlace();
		srcHgStation.cargo = HogeAI.GetPassengerCargo();
		srcHgStation.builded = true;
		srcHgStation.BuildExec();
		local roadRoute = RoadRoute(HogeAI.GetPassengerCargo(), srcHgStation, toHgStation, true);
		roadRoute.depot = depot;
		roadRoute.useDepotOrder = false;
		local vehicle = roadRoute.BuildVehicle();
		if(vehicle==null) {
			HgLog.Warning("BuildVehicle failed.(TownBus.CreateTransferRoadRoute)"+this);
			return false;
		}
		roadRoute.CloneVehicle(vehicle);
		RoadRoute.instances.push(roadRoute);
		HgLog.Info("TownBus.CreateTransferRoadRoute succeeded."+this);
		return true;
	}
	
	function CheckInterval() {
		if(removeBus != null) {
			if(AIVehicle.IsStoppedInDepot(removeBus)) {
				AIVehicle.SellVehicle(removeBus);
				removeBus = null;
			}
		}
		if(stations.len()<2) {
			return;
		}
		if(AIBase.RandRange(100) < 5 && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 500000) {
			CheckRenewal();
		}
		CheckTransfer();
	}

	function CheckRenewal() {
		local bus = GetBus();
		local aiExec = AIExecMode();
		if(bus == null || removeBus != null) {
			return;
		}
		local engine = ChooseBusEngine();
		if(engine != AIVehicle.GetEngineType(bus) || AIVehicle.GetAgeLeft(bus) <= 600) {
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(bus, AIOrder.ORDER_CURRENT)) == 0) {
				AIVehicle.SendVehicleToDepot (bus);
			}
			removeBus = bus;
			BuildBus();
		}
	}
	
	function GetPlace() {
		return TownCargo(town, HogeAI.GetPassengerCargo(), true);
	}
	
	function CanUseTransfer() {
		return stations.len() == 2;
	}
		
	function CheckTransfer() {
		if(!CanUseTransfer()) {
			return;
		}
		
		local place = GetPlace();
		local usedRoutes = PlaceDictionary.Get().GetRoutesBySource(place);
		if(usedRoutes.len()>0 /*&& usedRoutes[0] instanceof RoadRoute*/) { // TODO 複数あるケース
			local usedRoute = usedRoutes[0];
			local toHgStation;
			if(usedRoute.srcHgStation.place.IsSamePlace(place)) {
				toHgStation = usedRoute.srcHgStation.stationGroup.FindStation("PieceStation");
			} else {
				toHgStation = usedRoute.destHgStation.stationGroup.FindStation("PieceStation");
			}
			if(toHgStation == null) {
				HgLog.Warning("PieceStation not found.(CheckTransfer)"+this);
				return;
			}
			
			removeBus = GetBus();
			if(removeBus != null) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(removeBus, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (removeBus);
				}
			}
			if(RoadBuilder().BuildRoad([stations[0]], [toHgStation.platformTile], true)) {
				CreateTransferRoadRoute(1, stations[0], toHgStation);
			}
			if(RoadBuilder().BuildRoad([stations[1]], [toHgStation.platformTile], true)) {
				CreateTransferRoadRoute(2, stations[1], toHgStation);
			}
			stations.clear();
		}
	}
	
	function GetBus() {
		if(stations.len() != 2) {
			return null;
		}
		local list = AIVehicleList_Station(AIStation.GetStationID(stations[0]));
		if(list.Count()==0) {
			list = AIVehicleList_Station(AIStation.GetStationID(stations[1]));
			if(list.Count()==0) {
				return null;
			}
		}
		
		local result = list.Begin();
		if(result == removeBus) {
			if(list.IsEnd()) {
				return null;
			}
			result = list.Next();
		}
		return result;
	}
	
	function _tostring() {
		return "TownBus["+AITown.GetName(town)+"]";
	}
}
