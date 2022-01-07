

class WaterRoute extends CommonRoute {
	static instances = [];


	static function SaveStatics(data) {
		local a = [];
		foreach(route in WaterRoute.instances) {
			a.push(route.Save());
		}
		data.waterRoutes <- a;
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
	}
	
	buoys = null;
	
	constructor() {
		buoys = [];
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_WATER;
	}	
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxShips;
	}

	
	function GetLabel() {
		return "Water";
	}
	
	function SetPath(path) {
		local execMode = AIExecMode();
		local count = 0;
		while(path != null) {
			if(count % 16 == 15) {
				if(AIMarine.BuildBuoy (path.GetTile())) {
					buoys.push(path.GetTile());
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
	
	function GetRouteClass() {
		return WaterRoute;
	}
	
	function GetRouteClass() {
		return WaterRoute;
	}
	
	function CreateStationFactory() { 
		return WaterStationFactory();
	}
	
	function CreatePathBuilder() {
		return WaterPathBuilder();
	}
}

class WaterStationFactory extends StationFactory {
	
	constructor() {
		StationFactory.constructor();
		this.ignoreDirScore = true;
	}
	
	function GetStationType() {
		return AIStation.STATION_DOCK;
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
		return BuildPlatform(isTestMode);
	}

	function Remove() {
		//TODO:
		RemoveWorld();
		return true;
	}

	
	function GetTiles() {
		return [platformTile];
	}
	
	function GetEntrances() {
		foreach(d in HgTile.DIR4Index) {
			if(AITile.IsWaterTile(platformTile + d * 2)) {
				return [platformTile + d * 2];
			}
		}
		HgLog.Error("not found water tile:"+HgTile(platformTile));
	
	}
	
	function GetBuildableScore() {
		return 0;
	}
}

class WaterPathBuilder {

	path = null;
	cargo = null;
	engine = null;
	
	function BuildPath(starts ,goals, suppressInterval=false) {
		local pathfinder = WaterPathFinder();
		local pathFindLimit = 100;
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
			if (AITile.IsWaterTile(next_tile) && (AITile.GetSlope(next_tile)==AITile.SLOPE_FLAT || AIMarine.IsLockTile(next_tile))) {
				tiles.push([next_tile, 0xFF]);
			}
		}
		return tiles;
	}

	function _CheckDirection(self, tile, existing_direction, new_direction) {
		return false;
	}
}
