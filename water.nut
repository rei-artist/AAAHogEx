

class WaterRoute extends CommonRoute {
	static instances = [];
	static usedTiles = {};


	static function SaveStatics(data) {
		local a = [];
		foreach(route in WaterRoute.instances) {
			a.push(route.Save());
		}
		data.waterRoutes <- a;
		data.usedTiles <- WaterRoute.usedTiles;
	}
	
	static function LoadStatics(data) {
		WaterRoute.instances.clear();
		foreach(t in data.waterRoutes) {
			local route = WaterRoute();
			route.Load(t);
			
			HgLog.Info("load:"+route);
			
			WaterRoute.instances.push(route);	
			PlaceDictionary.Get().AddRoute(route);
		}
		foreach(k,v in data.usedTiles) {
			WaterRoute.usedTiles.rawset(k,v);
		}
	}
	
	buoys = null;
	
	constructor() {
		CommonRoute.constructor();
		buoys = [];
	}
	
	function Save() {
		local t = CommonRoute.Save();
		t.buoys <- buoys;
		return t;
	}
	
	function Load(t) {
		CommonRoute.Load(t);
		buoys = t.buoys;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_WATER;
	}	
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxShips;
	}
	
	function GetThresholdVehicleNumRateForNewRoute() {
		return 0.8;
	}

	function GetThresholdVehicleNumRateForSupportRoute() {
		return 0.9;
	}

	function GetLabel() {
		return "Water";
	}
	
	function GetBuilderClass() {
		return WaterRouteBuilder;
	}
	
	function GetBuildingCost(distance) {
		return HogeAI.Get().GetInflatedMoney(10000); // TODO 適当。土地成型すると高額だが、ただのdockは激安(292)
	}
	
	function GetBuildingTime(distance) {
		return 400;
	}
	
	function SetPath(path) {
		local execMode = AIExecMode();
		local count = 0;
		while(path != null) {
			WaterRoute.usedTiles.rawset(path.GetTile(),true);
			if(count % 16 == 15) {
				local tile = path.GetTile();
				if(AIMarine.IsBuoyTile(tile) || AIMarine.BuildBuoy(tile)) {
					buoys.push(tile);
				}
			}
			count ++;
			path = path.GetParent();
		}
	}
	
	function AppendSrcToDestOrder(vehicle) {
		foreach(buoy in buoys) {
			AIOrder.AppendOrder(vehicle, buoy, 0 );
		}
	}
	
	function AppendDestToSrcOrder(vehicle) {
		foreach(i,buoy in buoys) {
			AIOrder.AppendOrder(vehicle, buoys[buoys.len()-i-1], 0 );
		}
	}

}


class WaterRouteBuilder extends CommonRouteBuilder {
	
	constructor(dest, srcPlace, cargo) {
		CommonRouteBuilder.constructor(dest, srcPlace, cargo);
		makeReverseRoute = true;
	}
	
	function GetRouteClass() {
		return WaterRoute;
	}
	
	function CreateStationFactory() { 
		return WaterStationFactory();
	}
	
	function CreatePathBuilder(engine, cargo) {
		return WaterPathBuilder(engine, cargo);
	}
}

class WaterStationFactory extends StationFactory {
	
	constructor() {
		StationFactory.constructor();
		this.ignoreDirectionScore = true;
		this.ignoreDirection = true;
	}
	
	function GetSpreadMargin() {
		return 1; // Buildされるまで向きが確定しないのでSPREAD_OUTしないようにするために1だけ余裕を見る
	}

	function GetStationType() {
		return AIStation.STATION_DOCK;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_WATER;
	}

	function GetPlatformNum() {
		return 1;
	}
	
	function GetPlatformLength() {
		return 1;
	}
	
	function Create(platformTile,stationDirection) {
		return WaterStation(platformTile);
	}
}

class WaterStation extends HgStation {
	
	constructor(platformTile) {
		HgStation.constructor(platformTile, 0);
		this.originTile = platformTile;
		this.platformNum = 1; 
		this.platformLength = 1;
	}
	
	function GetTypeName() {
		return "WaterStation";
	}
	
	function GetStationType() {
		return AIStation.STATION_DOCK;
	}
	
	function BuildStation(joinStation) {
		return AIMarine.BuildDock (platformTile, joinStation)
	}
	
	function Build(levelTiles=false,isTestMode=true) {
		if(!AITile.IsCoastTile(platformTile)) {
			return false;
		}
		if(BuildPlatform(isTestMode,true)) {
			return true;
		}
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			return false;
		}
		local hgTile = HgTile(platformTile);
		if(hgTile.GetMaxHeightCount() != 3) {
			return false;
		}
		foreach(next in hgTile.GetDir4()) {
			//HgLog.Warning("WaterStation step3 "+next+" "+AITile.IsWaterTile(next.tile)+" "+(AITile.GetSlope(next.tile) != AITile.SLOPE_FLAT)+" "+AIMarine.IsWaterDepotTile(next.tile));
			if(!(AITile.IsCoastTile(next.tile) && next.GetMaxHeightCount() == 1)) {
				continue;
			}
			//HgLog.Warning("WaterStation hgTile("+hgTile+").GetConnectionCorners:"+next);
			local success = false;
			foreach(corner in hgTile.GetConnectionCorners(next)) {
				//HgLog.Warning("WaterStation GetCornerHeight("+hgTile+" "+next+" "+corner+"):"+AITile.GetCornerHeight(hgTile.tile, corner));
				if(AITile.GetCornerHeight(hgTile.tile, corner) == 1) {
					if(!AITile.LowerTile (hgTile.tile, HgTile.GetSlopeFromCorner(corner))) {
						//HgLog.Info("WaterStation AITile.LowerTile failed:" + hgTile+" corner:"+corner+" isTest"+isTestMode);
						continue;
					} else {
						if(!isTestMode) {
							for(local i=0; !AITile.IsWaterTile(next.tile) && i<100; i++) {
								AIController.Sleep(3); // 少し待たないと海にならない
							}
						}
						success = true;
						break;
					}
				}
			}
			if(!success) {
				continue;
			}
			if(!AITile.IsWaterTile(platformTile + (next.tile - platformTile))){
				continue;
			}
			
			if(isTestMode) {
				return true;
			}
			if(BuildPlatform(isTestMode)) {
				//HgLog.Info("WaterStation.BuildPlatform succeeded:"+hgTile);
				return true;
			}
			HgLog.Warning("WaterStation.BuildPlatform failed:"+hgTile+" "+AIError.GetLastErrorString());
		}
		return false;
	}

	function Remove() {
		AITile.DemolishTile(platformTile);
		RemoveWorld();
		return true;
	}

	
	function GetTiles() {
		return [platformTile];
	}
	
	function GetEntrances() {
		local stationId = AIStation.GetStationID (platformTile);
		foreach(d in HgTile.DIR4Index) {
			if(AIStation.GetStationID(platformTile + d) != stationId) {
				continue;
			}
			foreach(d2 in HgTile.DIR4Index) {
				if(WaterPathFinder.CanThroughShipTile(platformTile + d + d2)) {
					return [platformTile + d + d2];
				}
			}
		}
		HgLog.Warning("Not found entrance tile(WaterStation):"+HgTile(platformTile));
		return [platformTile];
	}
	
	function GetBuildableScore() {
		return 0;
	}
}

class WaterPathBuilder {

	path = null;
	cargo = null;
	engine = null;
	
	constructor(engine, cargo) {
		this.engine = engine;
		this.cargo = cargo;
	}
	
	function BuildPath(starts ,goals, suppressInterval=false) {
		local pathfinder = WaterPathFinder();
		local pathFindLimit = 15;
		pathfinder.InitializePath(starts, goals);		
		HgLog.Info("WaterPathBuilder Pathfinding...limit:"+pathFindLimit);
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
			HgLog.Info("WaterPathBuilder Path found. (" + counter + ")");
		} else {
			path = null;
			HgLog.Warning("WaterPathBuilder Pathfinding failed.");
			return false;
		}
		this.path = Path.FromPath(path);
		return true;
	}
}


class WaterPathFinder {
	static OFFSETS = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1),
					 AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)];
	
	static function CanThroughShipTile(tile) {
		return (AITile.IsWaterTile(tile) 
				&& !AIMarine.IsWaterDepotTile(tile) 
				&& ( AITile.GetSlope(tile) == AITile.SLOPE_FLAT || AIMarine.IsLockTile(tile) ) 
			) || AIMarine.IsBuoyTile(tile);
	}
	
	_aystar_class = import("graph.aystar", "", 6);
	_pathfinder = null;
	_max_cost = null;
	_running = null;
	
	constructor() {
		this._max_cost = 10000000;
		this._pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);	
	}
	
	function InitializePath(sources, goals, ignoreTiles=[]) {
		local nsources = [];

		foreach (node in sources) {
			nsources.push([node, 0xFF]);
		}
		this._pathfinder.InitializePath(nsources, goals, ignoreTiles);
	}
	
	function FindPath(iterations) {
		local test_mode = AITestMode();
		local ret = this._pathfinder.FindPath(iterations);
		this._running = (ret == false) ? true : false;
		return ret;
	}


	function _Cost(self, path, new_tile, new_direction) {
		if (path == null) return 0;
		return path.GetCost() + 100;
	}
	
	function _Estimate(self, cur_tile, cur_direction, goal_tiles) {
		local min_cost = self._max_cost;
		foreach (tile in goal_tiles) {
			local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(tile));
			local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(tile));
			min_cost = min(min_cost, min(dx, dy) * 67 * 2 + (max(dx, dy) - min(dx, dy)) * 100);
		}
		return min_cost * 2;
	}
	
	function _Neighbours(self, path, cur_node) {
		if (path.GetCost() >= self._max_cost) return [];
		local tiles = [];
		foreach (offset in WaterPathFinder.OFFSETS) {
			local next_tile = cur_node + offset;
			if (WaterPathFinder.CanThroughShipTile(next_tile)) {
				tiles.push([next_tile, 0xFF]);
			}
		}
		return tiles;
	}

	function _CheckDirection(self, tile, existing_direction, new_direction) {
		return false;
	}
}
