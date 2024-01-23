

class WaterRoute extends CommonRoute {
	//infrastractureType
	static IF_SEA = 1;
	static IF_CANAL = 2;

	static instances = [];
	static usedTiles = {};
	static canBuildCache = {};


	static function SaveStatics(data) {
		local a = [];
		foreach(route in WaterRoute.instances) {
			a.push(route.Save());
		}
		data.waterRoutes <- a;
		data.usedTiles <- WaterRoute.usedTiles;
		Coasts.SaveStatics(data);
	}
	
	static function LoadStatics(data) {
		WaterRoute.instances.clear();
		foreach(t in data.waterRoutes) {
			local route = WaterRoute();
			route.Load(t);
			
			HgLog.Info("load:"+route+" maxVehicles:"+route.maxVehicles);
			
			WaterRoute.instances.push(route);	
			PlaceDictionary.Get().AddRoute(route);
		}
		foreach(k,v in data.usedTiles) {
			WaterRoute.usedTiles.rawset(k,v);
		}
		Coasts.LoadStatics(data);
	}
	
	buoys = null;
	savedPath = null;
	
	constructor() {
		CommonRoute.constructor();
		buoys = [];
		useDepotOrder = false;
	}
	
	function Save() {
		local t = CommonRoute.Save();
		t.buoys <- buoys;
		t.savedPath <- savedPath;
		return t;
	}
	
	function Load(t) {
		CommonRoute.Load(t);
		buoys = t.buoys;
		savedPath = t.savedPath;
		/*
		if(srcHgStation.GetName().find("0373") != null) {
			foreach(tile in savedPath) {
				HgLog.Info(HgTile(tile));
			}
		}*/
		
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_WATER;
	}	
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxShips;
	}
	
	function GetThresholdVehicleNumRateForNewRoute() {
		return 0.9;
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
	
	function EstimateMaxRouteCapacity(infrastractureType, engineCapacity) {
		return 10 * engineCapacity;
	}
	
	function GetDefaultInfrastractureTypes() {
		return [WaterRoute.IF_SEA];
	}
	
	function GetInfrastractureTypes(engine) {
		return [WaterRoute.IF_CANAL,WaterRoute.IF_SEA];
	}
	
	function GetSuitableInfrastractureTypes(src, dest, cargo) {
		return src.GetCoasts(cargo)==null || dest.GetCoasts(cargo)==null ? [WaterRoute.IF_CANAL] : [WaterRoute.IF_SEA];
	}

	function SetPath(path) {
		savedPath = path.Save();
		
		local execMode = AIExecMode();
		local count = 0;
		while(path != null) {
			WaterRoute.usedTiles.rawset(path.GetTile(),true);
			if(count % 32 == 31) {
				local tile = path.GetTile();
				if(AIMarine.IsBuoyTile(tile) || AIMarine.BuildBuoy(tile)) {
					buoys.push(tile);
				}
			}
			count ++;
			path = path.GetParent();
		}
	}
	
	function GetPath() {
		return Path.Load(savedPath);
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
	
	function IsWaterWithinTiles(from, to, limit, step=5) {
		local distance = sqrt(AIMap.DistanceSquare(from, to));
		local dx = (AIMap.GetTileX(to).tofloat()-AIMap.GetTileX(from)) / distance;
		local dy = (AIMap.GetTileY(to).tofloat()-AIMap.GetTileY(from)) / distance;
		local x = AIMap.GetTileX(from).tofloat();
		local y = AIMap.GetTileY(from).tofloat();
		for(local i=0; i<limit; i+=step) {
			local cur = AIMap.GetTileIndex (x.tointeger(),y.tointeger());
			if(AITile.IsSeaTile(cur)) {
				return true;
			}
			x += dx * step;
			y += dy * step;
		}
		return false;
	}

	function GetNearestCoastTile(from, to, limit) {
		local distance = sqrt(AIMap.DistanceSquare(from, to));
		local dx = (AIMap.GetTileX(to).tofloat()-AIMap.GetTileX(from)) / distance;
		local dy = (AIMap.GetTileY(to).tofloat()-AIMap.GetTileY(from)) / distance;
		local x = AIMap.GetTileX(from).tofloat();
		local y = AIMap.GetTileY(from).tofloat();
		if(limit == null) {
			limit = distance;
		}
		for(local i=0; i<limit; i++) {
			local cur = AIMap.GetTileIndex (x.tointeger(),y.tointeger());
			if(AITile.IsCoastTile(cur)) {
				return cur;
			}
			x += dx;
			y += dy;
		}
		return null;
	}
	
	static function CanBuild(from, to, cargo) {
		//local usableTrain = !TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute) && !HogeAI.Get().roiBase;
		local key = from.GetLocation() + "-" + to.GetLocation() +"-" + cargo +"-" + HogeAI.Get().roiBase; // +"-" + usableTrain;
		if(WaterRoute.canBuildCache.rawin(key)) {
			return WaterRoute.canBuildCache[key];
		}
		local result = WaterRoute._CanBuild(from, to, cargo);
		WaterRoute.canBuildCache.rawset(key,result);
		return result;
	}
	
	static function _CanBuild(from, to, cargo) {
		local usableTrain = !TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute); // && !HogeAI.Get().roiBase;
		local coastsA = to.GetCoasts(cargo);
		local coastsB = from.GetCoasts(cargo);
		if(HogeAI.Get().roiBase) {
			if(coastsA==null || coastsB==null) {
				return false;
			}
		}
		if(!usableTrain && coastsA == null && coastsB == null) {
			return false;
		}
		if(coastsA == null) {
			local coastTile = WaterRoute.GetNearestCoastTile( to.GetLocation(), from.GetLocation(), usableTrain ? null : 35);
			if(coastTile != null) {
				coastsA = Coasts.GetCoasts(coastTile);
			}
		}
		if(coastsB == null) {
			local coastTile = WaterRoute.GetNearestCoastTile( from.GetLocation(), to.GetLocation(), usableTrain ? null : 35);
			if(coastTile != null) {
				coastsB = Coasts.GetCoasts(coastTile);
			}
		}
		if(coastsA != null && coastsB != null && coastsA.IsConnectedOnSea(coastsB)) {
			return true;
		}
		return false;
		
/*
		if(!to.IsNearWater(cargo)) {
			if(!from.IsNearWater(cargo) || (!usableTrain && !WaterRoute.IsWaterWithinTiles( to.GetLocation(), from.GetLocation(), 35 ))) {
				return false;
			}
		} else if(!from.IsNearWater(cargo)) {
			if(!to.IsNearWater(cargo) || (!usableTrain && !WaterRoute.IsWaterWithinTiles( from.GetLocation(), to.GetLocation(), 35 ))) {
				return false;
			}
		}
		return true;*/
	}

}


class WaterRouteBuilder extends CommonRouteBuilder {
	
	constructor(dest, src, cargo, options={}) {
		CommonRouteBuilder.constructor(dest, src, cargo, options);
		makeReverseRoute = false;//true;
		retryIfNoPathUsingSharableStation = true;
		/*if(dest.IsNearWater(cargo) && src.IsNearWater(cargo)) {
			options.buildPathBeforeStation <- true;
		}*/
	}

	function GetRouteClass() {
		return WaterRoute;
	}
	
	function CreateStationFactory(target) {
		if(HogeAI.Get().roiBase) {
			return WaterStationFactory();
		}
		if(target.GetCoasts(cargo) == null) {
			return CanalStationFactory();
		} else {
			return PriorityStationFactory([WaterStationFactory(),CanalStationFactory()]);
		}
	}
	
	function CreatePathBuilder(engine, cargo) {
		return WaterPathBuilder(engine, cargo, GetDistance());
	}
	
	function GetDistance() {
		return AIMap.DistanceManhattan(src.GetLocation(), dest.GetLocation());
	}

	function IsFarFromSea(onLand, nearSea) {
		return !WaterRoute.IsWaterWithinTiles( onLand, nearSea, 35 );
	}
	
	function FindCoast(from, to) {
		return Find(from, to, AITile.IsCoastTile);
	}
	
	function FindSea(from, to) {
		return Find(from, to, AITile.IsSeaTile);
	}
	
	function Find(from, to, func) {
		local distance = sqrt(AIMap.DistanceSquare(from, to));
		local dx = (AIMap.GetTileX(to).tofloat()-AIMap.GetTileX(from)) / distance;
		local dy = (AIMap.GetTileY(to).tofloat()-AIMap.GetTileY(from)) / distance;
		local x = AIMap.GetTileX(from).tofloat();
		local y = AIMap.GetTileY(from).tofloat();
		for(local i=0; i<distance; i++) {
			local cur = AIMap.GetTileIndex(x.tointeger(),y.tointeger());
			if(func(cur)) {
				return cur;
			}
			x += dx;
			y += dy;
		}
		return null;
	}
	
	function CheckConnection(srcTile, destTile) {
		local pathfinder = WaterPathFinder();
		local pathFindLimit = max(150, AIMap.DistanceManhattan(srcTile, destTile) / 10);
		pathfinder.InitializePath([srcTile], [destTile]);
		HgLog.Info("WaterPathBuilder CheckConnection ("+HgTile(srcTile)+"-"+HgTile(destTile)+") limit:"+pathFindLimit);
		local counter = 0;
		local path = false;
		while (path == false && counter < pathFindLimit) {
			path = pathfinder.FindPath(100);
			counter++;
			HogeAI.DoInterval();
		}
		if (path != null && path != false) {
			HgLog.Info("WaterPathBuilder CheckConnection Path found. (" + counter + ")");
			return true;
		} else {
			path = null;
			return false;
		}	
	}
	
	function DoBuild() {
		local notUseCompoundRoute = GetOption("notUseCompoundRoute",false);
		/*
		if(HogeAI.Get().roiBase) {
			local destTile = dest.GetLocation();
			local srcTile = src.GetLocation();
			local destSea = FindSea(destTile,srcTile);
			if(destSea == null) {
				HgLog.Warning("destSea not found."+this);
				return null;
			}
			local srcSea = FindSea(srcTile,destTile);
			if(srcSea == null) {
				HgLog.Warning("srcSea not found."+this);
				return null;
			}
			if(!CheckConnection(srcSea,destSea)) {
				HgLog.Warning("CheckConnection failed."+this);
				return null;
			}
		}*/
		
	
		local result = CommonRouteBuilder.DoBuild();
		if(!HogeAI.Get().roiBase // 見積もり考慮されていないので、鉄道が高額な場合破綻する
				&& !notUseCompoundRoute && !isBiDirectional && result == null && !TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute)) {
			local destTile = dest.GetLocation();
			local srcTile = src.GetLocation();
		
			local isDestFarFromSea = IsFarFromSea( destTile, srcTile );
			local isSrcFarFromSea = IsFarFromSea( srcTile, destTile );
			if((isDestFarFromSea && isSrcFarFromSea) || (!isDestFarFromSea && !isSrcFarFromSea)) {
				HgLog.Warning("isDestFarFromSea:"+isDestFarFromSea+" isSrcFarFromSea:"+isSrcFarFromSea+" "+this);
				return null;
			}
			local from = isDestFarFromSea ? destTile : srcTile;
			local to = isDestFarFromSea ? srcTile : destTile;
			
			local coastTile = FindCoast( from, to );
			if(coastTile == null) {
				HgLog.Warning("coast not found "+this);
				return null;
			}
			if(Coasts.GetCoasts(coastTile).coastType == Coasts.CT_POND) {
				HgLog.Warning("CT_POND "+this);
				return null;
			}
			return BuildCompoundRoute( isDestFarFromSea, coastTile );
		}
		return result;
	}
	
	function BuildCompoundRoute(isDestFarFromSea, coastTile) {
		HgLog.Info("## BuildCompoundRoute coastTile:"+HgTile(coastTile)+" "+this);
		
		local coastPlace = CoastPlace( coastTile );
		
		if(isDestFarFromSea) {
			local srcRoute = WaterRouteBuilder( coastPlace, src, cargo, {
				searchTransfer = false
				transfer = true, 
				notUseCompoundRoute = true, 
				notNeedToMeetDemand = true } ).Build();
			if(srcRoute == null) {
				return null;
			}
			srcRoute.isBuilding = true; //ネットワークが不完全なのでこれをしないとルートがRemove()される
			local destRoute = TrainRouteBuilder( dest, srcRoute.destHgStation.stationGroup, cargo, {
				searchTransfer = true
				noDoRoutePlans = true
				noExtendRoute = true
				routePlans = GetOption("routePlans",null)
				notUseSingle = true
				notUseCompoundRoute = true } ).Build();
			srcRoute.isBuilding = false;
			if(destRoute == null) {
				return null;
			}
			srcRoute.NotifyAddTransfer();
			srcRoute.NotifyChangeDestRoute();
			srcRoute.ChooseEngineSet(); //destへ繋がったので再見積もりを行う
			return srcRoute;
		} else {
			local destRoute = WaterRouteBuilder( dest, coastPlace, cargo, {
				searchTransfer = true
				isWaitingProduction = true
				production = 100
				noDoRoutePlans = true
				routePlans = GetOption("routePlans",null)
				notUseCompoundRoute = true } ).Build();
			if(destRoute == null) {
				return null;
			}
			destRoute.isBuilding = true; //ネットワークが不完全なのでこれをしないとルートがRemove()される
			local srcRoute = TrainRouteBuilder( destRoute.srcHgStation.stationGroup, src, cargo,  {
				searchTransfer = false
				transfer = true
				notUseSingle = true
				notUseCompoundRoute = true, 
				notNeedToMeetDemand = true } ).Build();
			destRoute.isBuilding = false;
			if(srcRoute == null) {
				return null;
			}
			destRoute.NotifyAddTransfer();
			return srcRoute;
		}
		HgLog.Info("## Succeeded BuildCompoundRoute "+this);
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

class CanalStationFactory extends StationFactory {
	
	constructor() {
		StationFactory.constructor();
		this.ignoreDirectionScore = true;
	}
	
	function GetSpreadMargin() {
		return 0;
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
		return 1; // CeveredAreaを検索する時にCanalStationはplatformTileに対して回転するので1で計算させる(他のstationはplatformTileが常に左上)
	}
	
	function Create(platformTile,stationDirection) {
		return CanalStation(platformTile,stationDirection);
	}
}

class WaterStation extends HgStation {
	
	depot = null;
	
	constructor(platformTile) {
		HgStation.constructor(platformTile, 0);
		this.originTile = platformTile;
		this.platformNum = 1; 
		this.platformLength = 1;
	}
	
	function Save() {
		local t = HgStation.Save();
		t.depot <- depot;
		return t;
	}
	
	function Load(t) {
		depot = t.depot;
	}
	
	function GetTypeName() {
		return "WaterStation";
	}
	
	function GetStationType() {
		return AIStation.STATION_DOCK;
	}
	
	function BuildStation(joinStation,isTestMode) {
		return AIMarine.BuildDock(platformTile, joinStation)
	}
	
	function IsBuildablePreCheck() {
		return AITile.IsCoastTile(platformTile) || AITile.IsSeaTile(platformTile);
	}
	
	function Build(levelTiles=false,isTestMode=true) {
		local water = AITile.IsWaterTile(platformTile)
		if(!AITile.IsCoastTile(platformTile) && !water) {
			return false;
		}
		if(BuildPlatform(isTestMode,true)) {
			return true;
		}
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			return false;
		}
		local waterRemovable = HogeAI.Get().clearWaterCost < max(HogeAI.Get().GetQuarterlyIncome() / 10,HogeAI.Get().GetUsableMoney() / 100); //別にそんなに費用かからない。AICompany.GetBankBalance(AICompany.COMPANY_SELF) > GetInflatedMoney(2000000);
		local hgTile = HgTile(platformTile);
		if(!waterRemovable) {
			if(water) {
				return false;
			}
			if(hgTile.GetMaxHeightCount() != 3) {
				return false;
			}
		}
		foreach(next in hgTile.GetDir4()) {
			//HgLog.Warning("WaterStation step3 "+next+" "+AITile.IsWaterTile(next.tile)+" "+(AITile.GetSlope(next.tile) != AITile.SLOPE_FLAT)+" "+AIMarine.IsWaterDepotTile(next.tile));
			if(WaterRoute.usedTiles.rawin(next)) {
				continue;
			}
			if(waterRemovable) {
				local back = platformTile - (next.tile - platformTile);
				local edge = platformTile + (next.tile - platformTile);
				if(!AITile.IsWaterTile(edge)) { // ここのlowerはやらない。たぶん地面に池ができるだけ
					continue;
				}
				if(!HgTile.LevelBound(platformTile, next.tile, 0)) {
					continue;
				}
				if(!HgTile.LevelBound(platformTile, back, 1)) {
					continue;
				}
			} else {
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
			}
			if(!AITile.IsWaterTile(platformTile + (next.tile - platformTile) * 2)) { 
				continue;
			}
			if(isTestMode) {
				return true;
			}
			for(local i=0; !AITile.IsWaterTile(next.tile) && i<100; i++) {
				AIController.Sleep(3); // 少し待たないと海にならない
			}
			if(BuildPlatform(isTestMode)) {
				//HgLog.Info("WaterStation.BuildPlatform succeeded:"+hgTile);
				return true;
			}
			HgLog.Warning("WaterStation.BuildPlatform failed:"+hgTile+" "+AIError.GetLastErrorString());
		}
		return false;
	}

	function Demolish() {
		AIMarine.RemoveDock(platformTile);
		return true;
	}

	function SetDepot(depot) {
		this.depot = depot;
		DoSave();
	}
	
	function GetDepot() {
		return depot;
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
	
	function CanBuildDriveThroughRoadStation(tile) {
		if(AIRoad.BuildDriveThroughRoadStation(tile, tile + 1, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW)
			|| AIRoad.BuildDriveThroughRoadStation(tile, tile + AIMap.GetTileIndex(0, 1), AIRoad.ROADVEHTYPE_BUS, AIStation.		
STATION_NEW)) {
			foreach(d in HgTile.DIR8Index) {
				if(AITile.IsStationTile(tile+d) && AICompany.IsMine(AITile.GetOwner(tile+d))) {
					return false;
				}
			}
			return true;
		}
		return false;
	}
	
	function GetBuildableScore() {
		local result = 0;
		if(place != null && place instanceof TownCargo 
				&& !HogeAI.Get().IsDistantJoinStations() 
				&& CargoUtils.IsPaxOrMail(place.cargo) 
				&& TownBus.CanUse(place.cargo)) {
			foreach(d in HgTile.DIR8Index) {
				local busStopTile = platformTile + d;
				if(CanBuildDriveThroughRoadStation(busStopTile)) {
					result += 10;
					if(AIRoad.IsRoadTile(busStopTile)) {
						result += 10;
					}
					break;
				}
			}
		}
		
		if(HogeAI.Get().roiBase) {
			if(AITile.IsCoastTile(platformTile)) {
				result += 10;
				if(AIMarine.BuildDock(platformTile, AIStation.STATION_NEW)) {
					result += 50;
				}
			}
		}
		
		return result;
	}
}

class CanalStation extends HgStation {

	constructor(platformTile, stationDirection) {
		HgStation.constructor(platformTile, stationDirection);
		this.originTile = platformTile;
		this.platformNum = 1; 
		this.platformLength = 2;
	}
	
	function GetTypeName() {
		return "CanalStation";
	}
	
	function GetStationType() {
		return AIStation.STATION_DOCK;
	}
	
	function BuildStation(joinStation,isTestMode) {
		return AIMarine.BuildDock(platformTile, joinStation)
	}
	
	function IsBuildablePreCheck() {
		local height = AITile.GetMinHeight(platformTile);
		return AITile.IsBuildable(platformTile) &&  (height == 1 || height == 0);
	}
	

	function Build(levelTiles=true,isTestMode=true) {
		local waterRemovable = !HogeAI.Get().roiBase && HogeAI.Get().clearWaterCost < max(HogeAI.Get().GetQuarterlyIncome() / 10,HogeAI.Get().GetUsableMoney() / 100); 
		local canals = [At(0,1),At(0,2)];
		if(isTestMode) {
			foreach(t in canals) {
				if(AITile.GetMinHeight(t) >= 2) {
					return false;
				}
				if(!AIMarine.IsCanalTile(t) && !AIMarine.BuildCanal(t)) {
					return false;
				}
			}
		}
		local slope = AITile.GetSlope(platformTile);
		local lowerMode = false;
		if(GetCanalSlope() != slope) {
			if(!BuildRaiseMode(isTestMode) && (!waterRemovable || !(lowerMode = BuildLowerMode(isTestMode)))) {
				return false;
			}
		}
		if(WaterRoute.usedTiles.rawin(At(0,1))) {
			return false;
		}
		if(isTestMode) {
			return true;
		}
		foreach(t in canals) {
			if(!BuildUtils.BuildSafe(function():(t) {
				return AIMarine.IsCanalTile(t) || AIMarine.BuildCanal(t);
			})) {
				HgLog.Warning("BuildCanal failed:"+HgTile(t)+" "+AIError.GetLastErrorString());
				return false;
			}
		}
		if(!BuildPlatform(isTestMode)) {
			return false;
		}
		if(lowerMode) {
			//海水が入ってくるまで時間がかかるので運河を作る事にした。AITile.DemolishTile(At(0,2)); // 運河に阻まれて海水が入ってこないケースを防止
		}
		return true;
	}
	
	function BuildRaiseMode(isTestMode) {
		if(isTestMode) {
			foreach(t in [At(-1,-1),At(-1,0),At(0,-1),At(1,-1),At(1,0)]) {
				if(!AITile.IsBuildable(t)) {
					return false;
				}
			}
		}
		local boundCorners = HgTile.GetCorners( HgTile(platformTile).GetDirection(HgTile(At(0,-1))) );
		foreach(corner in boundCorners) {
			if(AITile.GetCornerHeight(platformTile,corner) == 1) {
				if(!TileListUtil.RaiseTile(platformTile,HgTile.GetSlopeFromCorner(corner))) {
					return false;
				}
			}
		}
		return true;
	}
	
	
	function BuildLowerMode(isTestMode) {
		if(AITile.GetMaxHeight(platformTile)!=1 || AITile.GetMinHeight(platformTile)!=1) {
			return false;
		}
		HogeAI.WaitForMoney(20000);
		return WaterPathFinder.LowerToZero(At(0,1)) && WaterPathFinder.LowerToZero(At(0,2));
/*		
	
		if(AITile.GetMaxHeight(platformTile)!=1) {
			return false;
		}
		return TileListUtil.LevelAverage( GetTileListForLevelTiles( [[0,1],[0,2]] ), null, isTestMode, 0 );*/
	}
	
	function GetTiles() {
		return [At(0,0),At(0,1)];
	}
	
	function GetEntrances() {
		return [At(0,2)];
	}
	
	function Demolish() {
		AIMarine.RemoveDock(platformTile);
		return true;
	}
	
	function GetBuildableScore() {
		local result = 0;
		local slope = AITile.GetSlope(platformTile);
		if(GetCanalSlope() != slope) {
			result += 2;
		}
		foreach(t in [At(-1,1),At(1,1),At(-1,2),At(1,2),At(-1,3),At(0,3),At(1,3)]) {
			if(AIMarine.IsCanalTile(t) || (AITile.IsBuildable(t) && AITile.GetSlope(t) == AITile.SLOPE_FLAT)) {
				result ++;
			}
		}
		return result;
	}
	
	function GetPlatformRectangle() {
		if(platformRectangle == null) {
			platformRectangle = Rectangle.CornerTiles(HgTile(At(0,0)),HgTile(At(0,1)));
		}
		return platformRectangle;
	}
	
	static function GetCanalSlope() {
		switch(stationDirection) {
			case HgStation.STATION_SE:
				return AITile.SLOPE_NW;
			case HgStation.STATION_SW:
				return AITile.SLOPE_NE;
			case HgStation.STATION_NW:
				return AITile.SLOPE_SE;
			case HgStation.STATION_NE:
				return AITile.SLOPE_SW;
		}
	}
	
}

class WaterPathBuilder {

	path = null;
	cargo = null;
	engine = null;
	distance = null;
	
	constructor(engine, cargo, distance) {
		this.engine = engine;
		this.cargo = cargo;
		this.distance = distance;
	}
	
	function BuildPath(starts ,goals, suppressInterval=false) {
		local swapGoalStart = false;
		foreach(goal in goals) {
			if(AIMarine.IsCanalTile(goal)) {
				swapGoalStart = true;
				local t = starts;
				starts = goals;
				goals = t;
				break;
			}
		}
	
		local pathfinder = WaterPathFinder();
		local pathFindLimit = max(HogeAI.Get().roiBase ? 15 : 15, distance / 10);
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
		if(swapGoalStart) {
			this.path = this.path.Reverse();
		}
		local lowerToZeroTiles = [];
		while(path != null) {
			local cur_tile = path.GetTile();
			if(path.mode >= 1 
					&& (AIMarine.IsBuoyTile(cur_tile) 
						|| (AITile.IsRiverTile(cur_tile) && AITile.GetSlope(cur_tile) == AITile.SLOPE_FLAT)
						|| AITile.IsSeaTile(cur_tile) 
						|| AIMarine.IsCanalTile(cur_tile) 
						|| AIMarine.IsLockTile(cur_tile))) {
			} else if(path.mode >= 256) {
				HogeAI.WaitForMoney(15000);
				if(!WaterPathFinder.LowerToZero(cur_tile)) {
					HgLog.Warning("Cannot lower to zero."+HgTile(cur_tile)+" "+AIError.GetLastErrorString());
					return false;
				}
				AIMarine.BuildCanal(cur_tile);
				lowerToZeroTiles.push(cur_tile);
			} else if(path.mode >= 1) {
				HogeAI.WaitForMoney(10000);
				if(AIMarine.BuildCanal(cur_tile)) {
				} else if(AIMarine.BuildLock(cur_tile)) {
				} else {
					HgLog.Warning("Cannot build canal or lock."+HgTile(cur_tile)+" "+AIError.GetLastErrorString());
					return false;
				}
			}
			path = path.GetParent();
		}
		/*
		foreach(index,t in lowerToZeroTiles) {
			if(index == 0) {
				HgLog.Info("wait for entering water");
			}
			local i=0;
			for(; !AITile.IsWaterTile(t) && i<100; i++) {
				AIController.Sleep(1);
			}
			if(i==100) {
				HgLog.Warning("Timed out: entering water");
				break;
			}
		}*/
		
		return true;
	}
}

class WaterPathFinder {
	
	static function CanThroughShipTile(tile) {
		return (AITile.IsSeaTile(tile) && !AIMarine.IsWaterDepotTile(tile) 
			) || AIMarine.IsBuoyTile(tile);
	}
	
	static function LowerToZero(tile) {
		local lowerSlopes = 0;
		foreach(corner in [AITile.CORNER_W, AITile.CORNER_S, AITile.CORNER_E, AITile.CORNER_N]) {
			local height = AITile.GetCornerHeight(tile, corner);
			if(height == 1) {
				lowerSlopes = lowerSlopes | HgTile.GetSlopeFromCorner(corner);
			} else if(height >= 2) {
				return false;
			}
		}
		return lowerSlopes == 0 || AITile.LowerTile(tile, lowerSlopes);
	}
	
	_aystar_class = AyStar;//import("graph.aystar", "", 6);
	_pathfinder = null;
	_max_cost = null;
	_running = null;
	canalCostConsider = null;
	
	constructor() {
		this._max_cost = 10000000;
		this._pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);
		this.canalCostConsider = true; //!HogeAI.Get().IsRich();
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


	function _Cost(self, path, new_tile, new_direction, mode) {
		if (path == null) return 0;
		local par = path.GetParent();
		if(par != null) {
			if(par.mode == 0 && mode == 1) {
				return path.GetCost() + 5000;
			} else if(par.mode >= 1 && AITile.GetMaxHeight(par.GetTile()) < AITile.GetMaxHeight(new_tile) ) {
				return path.GetCost() + 1000;
			}
		}
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
	
	function _Neighbours(self, path, cur_tile) {
		if (path.GetCost() >= self._max_cost) return [];
		local tiles = [];
		local mode = path.mode;
		if(mode == null) {
			if(!WaterPathFinder.CanThroughShipTile(cur_tile)) {
				if(AITile.GetMaxHeight(cur_tile)==0) {
					mode = 257;
				} else {
					mode = 1;
				}
			} else {
				mode = 0;
			}
		}
		local lowerMode = mode >= 256;
		local canalBuildMode = !lowerMode && mode >= 1;
		if(self.canalCostConsider) {
			if(canalBuildMode) { // TODO dockが遠くなりすぎてたどりつけなくなる問題
				if (mode >= 40) return [];		
			} else if(lowerMode) {
				if ((mode - 256) >= 30) return [];		
			}
		}
		local lockBuilded = (canalBuildMode || !self.canalCostConsider) && (AIMarine.BuildLock(cur_tile) || self.IsCenterLock(cur_tile));
		local par = path.GetParent();
		local prev = par != null ? par.GetTile() : null;
		if(lockBuilded && prev == null) {
			return [];
		}
		foreach (offset in lockBuilded ? [(cur_tile - prev)*2] : HgTile.DIR4Index) {
			local next_tile = cur_tile + offset;
			if (AIMarine.AreWaterTilesConnected(cur_tile,next_tile)) {
				if(lowerMode && AITile.GetMaxHeight(next_tile)>=1) {
					continue;
				}
				tiles.push([next_tile, 0xFF, (canalBuildMode || lowerMode) ? mode : 0]);
				//HgTile(next_tile).BuildSign(""+mode);
			} else if(lowerMode) {
				if(WaterPathFinder.CanThroughShipTile(next_tile)) {
					tiles.push([next_tile, 0xFF, 0]);
				} else if(WaterPathFinder.LowerToZero(next_tile)) {
					tiles.push([next_tile, 0xFF, mode + 1]);
				}
			} else if(canalBuildMode) {
				if(lockBuilded && WaterPathFinder.CanThroughShipTile(next_tile)) {
					tiles.push([next_tile, 0xFF, 0]);
				} else if(AIMarine.BuildCanal(next_tile)) {
					tiles.push([next_tile, 0xFF, mode + 1]);
				} else if(prev == cur_tile - offset && (AIMarine.BuildLock(next_tile) || self.IsCenterLock(next_tile))) {
					tiles.push([next_tile, 0xFF, mode + 1]);
				}
			} else if(!self.canalCostConsider) {
				if(lockBuilded) {
					tiles.push([next_tile, 0xFF, 1]);
				}
			}
		}
		return tiles;
	}
	
	function IsCenterLock(tile) {
		return AIMarine.IsLockTile(tile) && AITile.GetSlope(tile) != AITile.SLOPE_FLAT;
	}

	function _CheckDirection(self, tile, existing_direction, new_direction) {
		return false;
	}
	
}


class Coasts {
	static idCounter = IdCounter();
	static idCoasts = {};
	static tileCoastId = {};

	static CT_ISLAND = 1;
	static CT_SEA = 2;
	static CT_POND = 3;

	static function SaveStatics(data) {
		data.tileCoastId <- Coasts.tileCoastId;
		local coastsArray = [];
		foreach(id,coasts in Coasts.idCoasts) {
			coastsArray.push(coasts.saveData);
		}
		data.coastsArray <- coastsArray;
	}

	static function LoadStatics(data) {
		HgTable.Extend( Coasts.tileCoastId, data.tileCoastId );
		foreach(coastsData in data.coastsArray) {
			Coasts(coastsData.coastType, coastsData.id);
		}
		foreach(coastsData in data.coastsArray) {
			Coasts.idCoasts[coastsData.id].Load(coastsData);
		}
	}

	static function IsMapLarge() {
		return false; //AIMap.GetMapSizeX() * AIMap.GetMapSizeY() >= 4096 * 4096; 
	}
	
	static function IsConnectedOnSea( coastTileA, coastTileB) {
		local coastsA = Coasts.GetCoasts(coastTileA);
		local coastsB = Coasts.GetCoasts(coastTileB);
		return coastsA.IsConnectedOnSea( coastsB );
	}

	static function GetCoasts(coastTile) {
		if(Coasts.IsMapLarge()) {
			return GlobalCoasts;
		}
		if(Coasts.tileCoastId.rawin(coastTile)) {
			return Coasts.idCoasts[ Coasts.tileCoastId[ coastTile ] ];
		}
		local coast = Coasts();
		local small = coast.SearchCoastTiles(coastTile) < 80;
		if(coast.nearLand == null) { // 陸地が無い
			coast.coastType = Coasts.CT_ISLAND;
			coast.Save();
			return GlobalCoasts;
		}
		coast.SearchCoastType();
		if(coast.coastType == Coasts.CT_SEA && small) {
			coast.coastType = Coasts.CT_POND;
		}
		coast.Save();
		return coast;
	}
	
	static function FindCoast(location) {
		local x = AIMap.GetTileX(location);
		local y = AIMap.GetTileY(location);
		x--; //結果に対して再呼び出しされるので
		while(x > 1) {
			local cur = AIMap.GetTileIndex(x,y);
			if(Coasts.IsCoastTile(cur)) {
				return cur;
			}
			x--;
		}
		return null;
	}
	
	id = null;
	coastType = null;
	nearLand = null;
	parentSea = null;
	childrenIslands = null;
	
	saveData = null;

	constructor(coastType = null, id = null) {
		if(id == null) {
			this.id = idCounter.Get();
		} else {
			this.id = id;
			idCounter.Skip(id);
		}
		this.coastType = coastType;
		this.childrenIslands = {};
		Coasts.idCoasts.rawset(this.id, this);
		Save();
	}
	
	function Save() {
		saveData = {
			id = id
			coastType = coastType
			nearLand = nearLand
			parentSea = parentSea == null ? null : parentSea.id
			childrenIslands = childrenIslands
		};
	}
	
	function Load(data) {
		nearLand = data.nearLand;
		parentSea = data.parentSea == null ? null : idCoasts[data.parentSea];
		childrenIslands = data.childrenIslands;
		saveData = data;
	}

	function IsConnectedOnSea( anotherCoasts ) {
		if(id == anotherCoasts.id) {
			return true;
		}
		if(coastType == CT_POND || anotherCoasts.coastType == CT_POND) {
			return false;
		}
		if(coastType == CT_SEA) {
			if(anotherCoasts.coastType == CT_SEA) {
				return false;
			}
			return childrenIslands.rawin(anotherCoasts.id);
		} else if(coastType == CT_ISLAND){
			if(parentSea == null) {
				return false;
			}
			return parentSea.IsConnectedOnSea(anotherCoasts);
		} else {
			HgLog.Error("coastType invalid "+this);
			return false;
		}
	}
	
	function SearchCoastTiles(coastTile) {
		local tiles = [coastTile];
		local count = 0;
		while(tiles.len() >= 1) {
			local tile = tiles.pop();
			Coasts.tileCoastId.rawset(tile,id);
			count ++;
			/*{
				local execMode = AIExecMode();
				AISign.BuildSign (tile, id.tostring());
			}*/
			foreach(d in HgTile.DIR4Index) {
				local check = tile + d;
				if(nearLand == null && AITile.GetMinHeight(check) >= 1) {
					nearLand = check;
				}
				if( !Coasts.tileCoastId.rawin(check) && IsCoastTile(check) ) {
					tiles.push(check);
				}
			}
		}
		return count;
	}
	
	function IsCoastTile(tile) {
		if(AITile.IsCoastTile(tile)) {
			return true;
		}
		if(AITile.GetMinHeight(tile)==0 && AITile.GetMaxHeight(tile)==1) {
			return true;
		}
		if(AITile.IsSeaTile(tile) && AIMap.DistanceFromEdge(tile) == 1) {
			return true;
		}
		return false;
	}
	
	
	function SearchCoastType() {
		local x = AIMap.GetTileX(nearLand);
		local y = AIMap.GetTileY(nearLand);
		local ex = AIMap.GetMapSizeX();
		local ey = AIMap.GetMapSizeY();
		local ends = [[1,y],[x,1],[ex,y],[x,ey]];
		local endsList = AITileList();
		foreach(p in ends) {
			endsList.AddTile(AIMap.GetTileIndex (p[0], p[1]));
		}
		endsList.Sort(AIList.SORT_BY_VALUE, true);
		endsList.Valuate(AIMap.DistanceManhattan, nearLand);
		local end = endsList.Begin();

		local boundCount = 0;
		local myCoast = false;
		local firstLink = null;
		
		//local end = AIMap.GetTileIndex(1,y);
		local tileList = AITileList();
		tileList.AddRectangle(nearLand,end);
		tileList.Valuate(function(t){
			if(AITile.IsSeaTile(t)) { //TODO: ブイ等で誤動作する
				return 1;
			}
			if(Coasts.IsCoastTile(t)) {
				return 2;
			}
			return 3;
		});
		tileList.Sort(AIList.SORT_BY_ITEM, nearLand < end ? true : false);
		local tileList2 = AITileList();
		tileList2.AddList(tileList);
		tileList.Valuate(function(t):(tileList2){
			return tileList2.GetValue(t-1) == tileList2.GetValue(t) ? 0 : tileList2.GetValue(t);
		});
		tileList.RemoveValue(0);
		local prevType = 3; // landから始まる
		foreach(tile,tileType in tileList) {
			//HgLog.Info("tile:"+HgTile(tile)+" tileType:"+tileType);
			if(tileCoastId.rawin(tile) && tileCoastId[tile] == id) {
				myCoast = true;
			} else {
				if(firstLink == null && boundCount % 2 == 1 && tileType == 2/*Coasts.IsCoastTile*/) {
					firstLink = tile;
				}
				if(myCoast) { // 直前が「自分の」coast
					if(prevType != tileType) {
						boundCount ++;
					}
					myCoast = false;
				}
				prevType = tileType;
			}
		}
		
		/*
		local cur = nearLand;
		local prev = cur;
		while(cur >= end) {
			if(tileCoastId.rawin(cur) && tileCoastId[cur] == id) {
				myCoast = true;
			} else {
				if(firstLink == null && boundCount % 2 == 1 && IsCoastTile(cur)) {
					firstLink = cur;
				}
			
				if(myCoast) { // 直前が「自分の」coast
					if(AITile.IsSeaTile(prev) != AITile.IsSeaTile(cur)) { //TODO: ブイ等で誤動作する
						boundCount ++;
					}
					myCoast = false;
				}
				prev = cur;
			}
			cur--;
		}*/
		if(boundCount % 2 == 0) {
			coastType = CT_SEA;
//			HgLog.Info("SearchCoastType "+HgTile(nearLand)+":SEA");
		} else {
			coastType = CT_ISLAND;
			if(firstLink != null) {
				Coasts.GetCoasts(firstLink).AddIsland(this);
//				HgLog.Info("SearchCoastType "+HgTile(nearLand)+":ISLAND parent");
			} else {
				GlobalCoasts.AddIsland(this);
//				HgLog.Info("SearchCoastType "+HgTile(nearLand)+":GlobalCoasts");
			}
		}
		HgLog.Info("SearchCoastType "+HgTile(nearLand)+":"+this);
	}
	
	function AddIsland(coasts) {
		if(coastType == CT_SEA) {
			coasts.parentSea = this;
			this.childrenIslands.rawset(coasts.id,0);
		} else {
			if(parentSea != null) {
				parentSea.AddIsland(coasts);
			}
		}
	}
	
	
	function _tostring() {
		return "Coasts:"+id+" type:"+coastType + (parentSea!=null? " parent["+parentSea+"]":"");
	}
}

GlobalCoasts <- Coasts(Coasts.CT_SEA);
