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

class RoadRoute extends CommonRoute {
	static instances = [];


	static function SaveStatics(data) {
		local a = [];
		foreach(route in RoadRoute.instances) {
			a.push(route.Save());
		}
		data.roadRoutes <- a;
	}
	
	static function LoadStatics(data) {
		RoadRoute.instances.clear();
		foreach(t in data.roadRoutes) {
			local route = RoadRoute();
			route.Load(t);
			
			HgLog.Info("load:"+route);
			
			RoadRoute.instances.push(route);	
			PlaceDictionary.Get().AddRoute(route);
		}
	}

	function GetVehicleType() {
		return AIVehicle.VT_ROAD;
	}
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxRoadVehicle;
	}
	
	function GetLabel() {
		return "Road";
	}

	function OnVehicleLost(vehicle) {
		HgLog.Warning("RoadRoute OnVehicleLost  "+this); //TODO 連続で来るのを抑制
		local execMode = AIExecMode();
		if(!RoadBuilder().BuildPath(destHgStation.GetEntrances(), srcHgStation.GetEntrances(), true)) {
			HgLog.Warning("RoadRoute removed.(Rebuild road failed) "+this);
			isClosed = true;
			isRemoved = true;
			foreach(vehicle,v in GetVehicleList()) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}
		} else {
			HgLog.Warning("Rebuild road route succeeded");
		}
	}
}


class RoadRouteBuilder extends CommonRouteBuilder {
	
	static function BuildRoadUntilFree(p1,p2) {
		return BuildUtils.RetryUntilFree( function():(p1,p2) {
			return AIRoad.BuildRoad(p1,p2);
		});
	}
	
	function GetRouteClass() {
		return RoadRoute;
	}
	
	function CreateStationFactory() { 
		return RoadStationFactory(AICargo.HasCargoClass(cargo,AICargo.CC_PASSENGERS) ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
	}
	
	function CreatePathBuilder() {
		return RoadBuilder();
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

	function BuildPath(starts ,goals, suppressInterval=false) {
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
		return BuildPath(startPath.GetTiles(), goals);
	}
	
	function IsConsiderSlope() {
		if(engine == null || cargo == null) {
			return false;
		}
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 100000 && Route.GetAllRoutes().len()>=1) {
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
		return CommonRoute.ChooseEngineCargo(HogeAI.GetPassengerCargo(), AIMap.DistanceManhattan(stations[0],stations[1]), AIVehicle.VT_ROAD);
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
		local roadRoute = RoadRoute();
		roadRoute.cargo = HogeAI.GetPassengerCargo();
		roadRoute.srcHgStation = srcHgStation;
		roadRoute.destHgStation = toHgStation;
		roadRoute.isTransfer = true;
		roadRoute.depot = depot;
		roadRoute.useDepotOrder = false;
		roadRoute.Initialize();
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
			if(RoadBuilder().BuildPath([stations[0]], [toHgStation.platformTile], true)) {
				CreateTransferRoadRoute(1, stations[0], toHgStation);
			}
			if(RoadBuilder().BuildPath([stations[1]], [toHgStation.platformTile], true)) {
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
