

class WaterRoute extends CommonRoute {
	//infrastractureType
	static IF_SEA = 1;
	static IF_CANAL = 2;

	static instances = [];
	static usedTiles = {};
	static canBuildCache = {};
	static landRateCache = {};


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
	lastRebuildDate = null;
	
	constructor() {
		CommonRoute.constructor();
		buoys = [];
		useDepotOrder = false;
		useServiceOrder = true;
	}
	
	function Load(t) {
		CommonRoute.Load(t);
		
		buoys = saveData.buoys;
		lastRebuildDate = saveData.lastRebuildDate;
	}

	function UpdateSavedData() {
		CommonRoute.UpdateSavedData();

		saveData.buoys <- buoys;
		saveData.lastRebuildDate <- lastRebuildDate;
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
		return 100 * engineCapacity;
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
		local execMode = AIExecMode();
		local count = 0;
		local useBouy = HogeAI.Get().openttdVersion < 14;
		local prev = null;
		while(path != null) {
			local tile = path.GetTile();
			WaterRoute.usedTiles.rawset(tile,true);
			if(useBouy && count % 48 == 47) {
				if(AIMarine.IsBuoyTile(tile) || AIMarine.BuildBuoy(tile)) {
					buoys.push(tile);
				}
			}
			if(prev != null) {
				if(AIMarine.IsLockTile(tile)) {
					AIMarine.BuildBuoy(prev);
				}
				if(AIMarine.IsLockTile(prev)) {
					AIMarine.BuildBuoy(tile);
				}
			}
			count ++;
			prev = tile;
			path = path.GetParent();
		}
		UpdateSavedData();
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

	function OnVehicleLost(vehicle) {
		if( AIVehicle.GetState(vehicle) == AIVehicle.VS_IN_DEPOT ) {
			return;
		}
		if(CommonRoute.vehicleRemoving.rawin(vehicle) && (AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) != 0) {
			local f = AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT);
			local dest = AIOrder.GetOrderDestination(vehicle, AIOrder.ORDER_CURRENT);
			local o1 = AIVehicle.SendVehicleToDepot(vehicle); // 一旦depot行きを解除
			local o2 = AIVehicle.SendVehicleToDepot(vehicle); // すぐに再開
			HgLog.Warning("ET_VEHICLE_LOST: SendVehicleToDepot (retry) "+o1+" "+o2+" "+f+" "+HgTile(dest));
		} else {
			local f = AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT);
			local dest = AIOrder.GetOrderDestination(vehicle, AIOrder.ORDER_CURRENT);
			local load = AIVehicle.GetCargoLoad(vehicle, cargo); // 何も積んでいないvehicleはdepotから出た直後の迷子な可能性が高いので再構築しない
			HgLog.Warning("ET_VEHICLE_LOST:"+f+" "+HgTile(dest)+" load:"+load);
			if(load==0 || (lastRebuildDate != null && lastRebuildDate + 30 > AIDate.GetCurrentDate())) {
				return;
			}
			lastRebuildDate = AIDate.GetCurrentDate();
			
			local execMode = AIExecMode();
			local latestEngineSet = GetLatestEngineSet();
			if(latestEngineSet == null) {
				HgLog.Warning("WaterRoute removed. latestEngineSet==null "+this);
				Remove();
				UpdateSavedData();
				return;
			}
			local engine = latestEngineSet.engine;
			local pathBuilder = WaterPathBuilder(engine,cargo,GetDistance());
			if(!pathBuilder.BuildPath(destHgStation.GetEntrances(), srcHgStation.GetEntrances(), true)) {
				HgLog.Warning("WaterRoute removed.(Rebuild path failed) "+this);
				Remove();
			} else {
				foreach(tile in pathBuilder.path.GetTiles()) {
					WaterRoute.usedTiles.rawset(tile,true);
				}
				HgLog.Warning("Rebuild WaterRoute succeeded");
			}
			UpdateSavedData();
		}
	}


	static function CheckLandRate(from, to, skip = 5) {
		local key = from+"-"+to;
		if(WaterRoute.landRateCache.rawin(key)) {
			return WaterRoute.landRateCache.rawget(key);
		} else {
			local result = WaterRoute._CheckLandRate(from, to, skip);
			WaterRoute.landRateCache.rawset(key,result);
			return result;
		}
	}
	
	// pathfinderはtoからfrom
	static function _CheckLandRate(from, to, skip = 5) {
		local curX = AIMap.GetTileX(from);
		local curY = AIMap.GetTileY(from);
		
		local toX = AIMap.GetTileX(to);
		local toY = AIMap.GetTileY(to);
		
		local water = 0;
		local land = 0;
		while(true) {
			local cur = AIMap.GetTileIndex(curX, curY);
			if(AITile.IsWaterTile(cur) || AIMarine.IsBuoyTile(cur)) {
				water ++;
			} else {
				land ++;
			}
			local dx = abs(toX - curX);
			local dy = abs(toY - curY);
			if(dx < skip && dy < skip) {
				break;
			}
			if(dx > dy) {
				curX += toX > curX ? skip : -skip;
			} else {
				curY += toY > curY ? skip : -skip;
			}
		}
		return land.tofloat() / (water+land).tofloat();
	}

	static function GetDirection(from, to) {
		local fromX = AIMap.GetTileX(from);
		local fromY = AIMap.GetTileY(from);
		local toX = AIMap.GetTileX(to);
		local toY = AIMap.GetTileY(to);
		local dx = toX - fromX;
		local dy = toY - fromY;
		return [dx>0?1:-1,0, dy>0?1:-1];
	}

	static function GetLongerDistance(from,to) {
		local fromX = AIMap.GetTileX(from);
		local fromY = AIMap.GetTileY(from);
		local toX = AIMap.GetTileX(to);
		local toY = AIMap.GetTileY(to);
		return max(abs(fromX-toX),abs(fromY-toY));
	}
	
	static function GetNearestCoastTileDir(dir, from, limit) {
		local cur = from;
		for(local i=0; i<limit; i++) {
			if(AITile.IsCoastTile(cur)) {
				return [cur,i];
			}
			cur += dir;
		}
		return null;
	}

	static function GetNearestCoastTile(from, to, limit) {
	/*
		local fromX = AIMap.GetTileX(from);
		local fromY = AIMap.GetTileY(from);
		local toX = AIMap.GetTileX(to);
		local toY = AIMap.GetTileY(to);
		local dx = toX - fromX;
		local dy = toY - fromY;
		dx = dx < 0 ? -1 : 1;
		dy = dy < 0 ? -1 : 1;
		if(limit == null) limit = IntegerUtils.IntMax;
		local r1 = WaterRoute.GetNearestCoastTileDir(dx, from, min(limit,abs(fromX-toX)));
		if(r1 != null) limit = min(limit, r1[1]);
		local r2 = WaterRoute.GetNearestCoastTileDir(dy * AIMap.GetMapSizeX(), from, min(limit,abs(fromY-toY)));
		if(r1!=null && r2!=null) {
			if(r1[1] < r2[1]) {
				return r1[0];
			} else {
				return r2[0];
			}
		}
		if(r1!=null) return r1[0];
		if(r2!=null) return r2[0];
		return null;*/
		
		
		
		local dirXY = WaterRoute.GetDirection(from,to);
		local d = dirXY[0] + dirXY[1] * AIMap.GetMapSizeX();
		local cur = from;
		if(limit == null) {
			limit = WaterRoute.GetLongerDistance(from,to);
		} else {
			limit = min(WaterRoute.GetLongerDistance(from,to),limit);
		}
		for(local i=0; i<limit; i++) {
			if(AITile.IsCoastTile(cur)) {
				return cur;
			}
			cur += d;
		}
		return null;


/*	
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
		return null;*/
	}
	
	static function CanBuild(from, to, cargo, isBidirectional) {
		//local usableTrain = !TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute) && !HogeAI.Get().roiBase;
		local key = from.GetLocation() + "-" + to.GetLocation() +"-" + cargo +"-" + HogeAI.Get().roiBase; // +"-" + usableTrain;
		if(WaterRoute.canBuildCache.rawin(key)) {
			return WaterRoute.canBuildCache[key];
		}
		local result = WaterRoute._CanBuild(from, to, cargo, isBidirectional);
		WaterRoute.canBuildCache.rawset(key,result);
		return result;
	}
	
	static function _CanBuild(from, to, cargo, isBidirectional) {
		local usableTrain = !isBidirectional && !TrainRoute.IsTooManyVehiclesForNewRoute(TrainRoute); // && !HogeAI.Get().roiBase;
		local coastsA = to.GetCoasts(cargo);
		local coastsB = from.GetCoasts(cargo);
		if(HogeAI.Get().roiBase) {
			if(coastsA==null || coastsB==null) {
				return false;
			}
		}
		local toTile = to.GetLocation();
		local fromTile = from.GetLocation();
		local distance = AIMap.DistanceManhattan(toTile, fromTile);
		if(!usableTrain && coastsA == null && coastsB == null && distance > 100) {
			return false;
		}
		if(coastsA == null) {
/*			if( AITile.GetMinHeight(toTile) >= 4 ) {
				return false;
			}*/
			local coastTile = WaterRoute.GetNearestCoastTile( toTile, fromTile, usableTrain ? null : 35);
			if(coastTile != null) {
				coastsA = Coasts.GetCoasts(coastTile);
			}
		}
		if(coastsB == null) {
/*			if( AITile.GetMinHeight(fromTile) >= 4 ) {
				return false;
			}*/
			local coastTile = WaterRoute.GetNearestCoastTile( fromTile, toTile, usableTrain ? null : 35);
			if(coastTile != null) {
				coastsB = Coasts.GetCoasts(coastTile);
			}
		}
		if(coastsA != null && coastsB != null && coastsA.IsConnectedOnSea(coastsB)) {
			return true;
		}
		if(distance <= 100) {
			if(HgStation.SearchStation(to, AIStation.STATION_DOCK, cargo, true) != null) {
				return true;
			}
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
		retryIfNoPathUsingSharableStation = false;// あんまり成功率高くない true;
		checkSharableStationFirst = true;
		/*if(dest.IsNearWater(cargo) && src.IsNearWater(cargo)) {
			options.buildPathBeforeStation <- true;
		}*/
	}

	function GetRouteClass() {
		return WaterRoute;
	}
	
	function CreateStationFactory(target,engineSet) {
		if(HogeAI.Get().roiBase) {
			return WaterStationFactory();
		}
		local coasts = target.GetCoasts(cargo);
		if(coasts == null) {
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
			if(destTile==null || srcTile==null) {
				return null;
			}
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
				canChangeDest = false
				setRouteCandidates = GetOption("setRouteCandidates",null)
				notUseSingle = true
				notUseCompoundRoute = true } ).Build();
			srcRoute.isBuilding = false;
			if(destRoute == null) {
				return null;
			}
			srcRoute.NotifyAddTransfer(cargo);
			srcRoute.NotifyChangeDestRoute();
			srcRoute.ChooseEngineSet(); //destへ繋がったので再見積もりを行う
			return srcRoute;
		} else {
			local destRoute = WaterRouteBuilder( dest, coastPlace, cargo, {
				searchTransfer = true
				isWaitingProduction = true
				production = 100
				noDoRoutePlans = true
				setRouteCandidates = GetOption("setRouteCandidates",null)
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
			destRoute.NotifyAddTransfer(cargo);
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
		return WaterStation(platformTile,stationDirection);
	}
	function GetTypeName() {
		return "WaterStation";
	}
}

class CanalStationFactory extends StationFactory {
	
	constructor() {
		StationFactory.constructor();
		this.ignoreDirectionScore = true;
	}
	
	function GetSpreadMargin() {
		return 1;
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
	function GetTypeName() {
		return "CanalStation";
	}
}

class WaterStation extends HgStation {
	
	depot = null;
	
	constructor(platformTile,stationDirection) {
		HgStation.constructor(platformTile, stationDirection);
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
		if(isTestMode) {
			return AIMarine.BuildDock(platformTile, joinStation);
		} else {
			return BuildUtils.BuildDockSafe(platformTile, joinStation);
		}
	}
	
	function IsBuildablePreCheck() {
		return AITile.IsCoastTile(platformTile) || AITile.IsSeaTile(platformTile);
	}
	
	function Build(levelTiles=false,isTestMode=true) {
		local water = AITile.IsWaterTile(platformTile)
		if(!water) {
			if(HogeAI.Get().roiBase) {
				local isCoast = AITile.IsCoastTile(platformTile);
				if(!isCoast) {
					if(!isTestMode) {
						HgLog.Warning("WaterStation.Build !water && !coast");
					}
					return false;
				}
				local coasts = Coasts.GetCoasts(platformTile);
				if(coasts!=null && coasts.coastType == Coasts.CT_POND) {
					if(!isTestMode) {
						HgLog.Warning("CT_POND");
					}
					return false;
				}
			}
			if(BuildPlatform(isTestMode,true)) {
				stationDirection = GetStationDirectionFromSlope(AITile.GetSlope(platformTile));
				/*if(!WaterRoute.usedTiles.rawin(HgTile.DIR4Index[GetDir4Index()])) { 海岸沿いの航路でdockが作られなくなる
					return false;
				}*/
				return true;
			}
			if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
				return false;
			}
		}
		//別にそんなに費用かからない。AICompany.GetBankBalance(AICompany.COMPANY_SELF) > GetInflatedMoney(2000000);
		local hgTile = HgTile(platformTile);
		if(!HogeAI.Get().waterRemovable) {
			if(water) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build water");
				}
				return false;
			}
			if(hgTile.GetMaxHeightCount() != 3) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build hgTile.GetMaxHeightCount() != 3");
				}
				return false;
			}
		}
		
		if(isTestMode) {
			foreach(i,dir in HgTile.DIR4Index) {
				if(_Build( dir, isTestMode)) {
					stationDirection = GetStationDirectionFromDir4Index(i);
					return true;
				}
			}
		} else {
			if(_Build( HgTile.DIR4Index[GetDir4Index()], isTestMode)) {
				return true;
			}
		}
		return false;
	}
	
	function _Build(dir, isTestMode=true,) {
		local next = platformTile + dir;
		if(HogeAI.Get().waterRemovable) {
			if(!AITile.IsWaterTile(next) && (HogeAI.Get().roiBase || !AITile.IsCoastTile(next))) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build !AITile.IsWaterTile(next) && !AITile.IsCoastTile(next)");
				}
				return false;
			}
			if(AIMarine.IsBuoyTile(next) || AIMarine.IsWaterDepotTile(next) || AITile.IsStationTile(next)) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build AIMarine.IsBuoyTile(next) || AIMarine.IsWaterDepotTile(next) || AITile.IsStationTile(next)");
				}
				return false;
			}
			if(!WaterPathFinder.LowerToZero(next)) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build WaterPathFinder.LowerToZero");
				}
				return false;
			}
			local back = platformTile - dir;
			if(!HgTile.LevelBound(platformTile, back, 1, false)) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build HgTile.LevelBound(platformTile, back, 1, false)");
				}
				return false;
			}
		} else {
			if(!(AITile.IsCoastTile(next) && HgTile(next).GetMaxHeightCount() == 1)) {
				return false;
			}
			//HgLog.Warning("WaterStation hgTile("+hgTile+").GetConnectionCorners:"+next);
			local success = false;
			foreach(corner in HgTile(platformTile).GetConnectionCorners(HgTile(next))) {
				//HgLog.Warning("WaterStation GetCornerHeight("+hgTile+" "+next+" "+corner+"):"+AITile.GetCornerHeight(hgTile.tile, corner));
				if(AITile.GetCornerHeight(platformTile, corner) == 1) {
					if(!AITile.LowerTile (platformTile, HgTile.GetSlopeFromCorner(corner))) {
						//HgLog.Info("WaterStation AITile.LowerTile failed:" + hgTile+" corner:"+corner+" isTest"+isTestMode);
						continue;
					} else {
						success = true;
						break;
					}
				}
			}
			if(!success) {
				if(!isTestMode) {
					HgLog.Warning("WaterStation.Build !success");
				}
				return false;
			}
		}
		if(WaterRoute.usedTiles.rawin(next)) {
			if(!isTestMode) {
				HgLog.Warning("WaterStation.Build WaterRoute.usedTiles");
			}
			return false;
		}
		local next2 = next + dir;
		if(!AITile.IsWaterTile(next2)) { 
			if(!isTestMode) {
				HgLog.Warning("WaterStation.Build !AITile.IsWaterTile(next2)");
			}
			return false;
		}
		if(isTestMode) {
			return true;
		}
		for(local i=0; !AITile.IsWaterTile(next) && i<100; i++) {
			AIController.Sleep(3); // 少し待たないと海にならない
		}
		if(BuildPlatform(isTestMode)) {
			//HgLog.Info("WaterStation.BuildPlatform succeeded:"+hgTile);
			return true;
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
		return [At(0,0),At(0,1)];
	}

	function GetEntrances() {
		/*local next2 = At(0,2);
		foreach(d2 in HgTile.DIR4Index) {
			if(WaterPathFinder.IsSea(next2 + d2)) {
				return [next2 + d2];
			}
		}
		HgLog.Warning("Not found entrance tile(WaterStation):"+HgTile(next2));*/
		return [At(0,2)];
	}

	function CanBuildJoinableDriveThroughRoadStation(tile) {
		if(!CanBuildDriveThroughRoadStation(tile)) {
			return false;
		}
		foreach(d in HgTile.DIR8Index) {
			if(AITile.IsStationTile(tile+d) && AICompany.IsMine(AITile.GetOwner(tile+d))) {
				return false;
			}
		}
		return true;
	}
	
	function CanBuildDriveThroughRoadStation(tile) {
		if(AIRoad.BuildDriveThroughRoadStation(tile, tile + 1, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW)) {
			return true;
		}
		if(AIRoad.BuildDriveThroughRoadStation(tile, tile + AIMap.GetTileIndex(0, 1), AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW)) {
			return true;
		}
		if(AITile.GetSlope(platformTile) != AITile.SLOPE_FLAT) {
			return false;
		}
		if(AITile.IsBuildable(tile)) {
			return false;
		}
		if(AITile.GetOwner(tile) != AICompany.COMPANY_INVALID){ 
			return false;
		}
		if(AIRoad.IsRoadTile(tile) || AITile.IsWaterTile(tile) || AIMarine.IsBuoyTile(tile)) {
			return false;
		}
		return true;
	}
	
	function GetBuildableScore() {
		local result = 0;
		if(place != null && place instanceof TownCargo 
				&& (!HogeAI.Get().IsDistantJoinStations() || HogeAI.Get().IsAvoidExtendCoverageAreaInTowns())
				&& CargoUtils.IsPaxOrMail(place.cargo) 
				&& TownBus.CanUse(place.cargo)) {
			foreach(d in HgTile.DIR8Index) {
				local busStopTile = platformTile + d;
				if(CanBuildJoinableDriveThroughRoadStation(busStopTile)) {
					result += 20;
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
		} else if(AITile.GetMaxHeight(At(0,-1))!=0) {
			result += 10;
		}
		
		return result;
	}
	
	function CheckBuildTownBus() {
		Rectangle.Center(HgTile(platformTile),3).AppendToTileList(TownBus.ngTileList);
		HgStation.CheckBuildTownBus();
		TownBus.ngTileList.Clear();
	}
	
	function GetDockSlope() {
		switch(stationDirection) {
			case HgStation.STATION_SE:
				return AITile.SLOPE_NW;
			case HgStation.STATION_NW:
				return AITile.SLOPE_SE;
			case HgStation.STATION_NE:
				return AITile.SLOPE_SW;
			case HgStation.STATION_SW:
				return AITile.SLOPE_NE;
			default:
				HgLog.Error("Unknown stationDirection (GetDockSlope):"+stationDirection);
		}
	}
	function GetStationDirectionFromSlope(slopeDirection) {
		switch(slopeDirection) {
			case AITile.SLOPE_NW:
				return HgStation.STATION_SE;
			case AITile.SLOPE_NE:
				return HgStation.STATION_SW;
			case AITile.SLOPE_SW:
				return HgStation.STATION_NE;
			case AITile.SLOPE_SE:
				return HgStation.STATION_NW;
			default:
				HgLog.Error("Unknown slopeDirection (GetStationDirectionFromSlope):"+slopeDirection);
		}
	}
	function GetStationDirectionFromDir4Index(dir4Index) {
		switch(dir4Index) {
			case 0:
				return HgStation.STATION_NE;
			case 1:
				return HgStation.STATION_NW;
			case 2:
				return HgStation.STATION_SE;
			case 3:
				return HgStation.STATION_SW;
			default:
				HgLog.Error("Unknown Dir4Index (GetStationDirectionFromDir4Index):"+dir4Index);
		}
	}
	
	function GetDir4Index() {
		switch(stationDirection) {
			case HgStation.STATION_NE:
				return 0;
			case HgStation.STATION_NW:
				return 1;
			case HgStation.STATION_SE:
				return 2;
			case HgStation.STATION_SW:
				return 3;
			default:
				HgLog.Error("Unknown stationDirection (GetDir4Index):"+stationDirection);
		}
	}
}

class CanalStation extends HgStation {
	depot = null;

	constructor(platformTile, stationDirection) {
		HgStation.constructor(platformTile, stationDirection);
		this.originTile = platformTile;
		this.platformNum = 1; 
		this.platformLength = 2;
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
		return "CanalStation";
	}
	
	function GetStationType() {
		return AIStation.STATION_DOCK;
	}
		
	function BuildStation(joinStation,isTestMode) {
		return AIMarine.BuildDock(platformTile, joinStation)
	}
	
	function IsBuildablePreCheck() {
		//local height = AITile.GetMinHeight(platformTile);
		return AITile.IsBuildable(platformTile);// && 0 <= height && height <= 2;
	}
	
	function Build(levelTiles=true,isTestMode=true) {
		local waterRemovable = HogeAI.Get().waterRemovable;
		local canals = [At(0,1),At(0,2)];
		if(isTestMode) {
			if(!(AIMarine.IsCanalTile(canals[0]) && AICompany.IsMine(AITile.GetOwner(canals[0]))) && !AIMarine.BuildCanal(canals[0])) {
				return false;
			}
			if(!AIMarine.IsCanalTile(canals[1]) && !AIMarine.BuildCanal(canals[1])) {
				return false;
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
			if(!AIMarine.IsCanalTile(t) && !BuildUtils.BuildCanalSafe(t)) {
				HgLog.Warning("BuildCanal1 failed:"+HgTile(t)+" "+AIError.GetLastErrorString());
				return false;
			}
		}
		if(!BuildPlatform(isTestMode)) {
			return false;
		}
		return true;
	}
	
	function GetDepot() {
		if(depot != null) {
			return depot;
		}
		foreach(x in [1,-1]) {
			local t = At(x,1);
			if(AIMarine.IsWaterDepotTile(t) && AICompany.IsMine(AITile.GetOwner(t))) {
				return t;
			}
		}
		foreach(x in [1,-1]) {
			if(BuildDepotX(x)) {
				return At(x,1);
			}
		}
		return null;
	}
	
	function SetDepot(depot) {
		this.depot = depot;
		DoSave();
	}
	
	function BuildDepotX(x) {
		local canals = [At(0,2),At(0,3),At(x,1),At(x,2),At(x,3)];// (0,2)はLockなどに塞がれてないかの確認
		{
			local testMode = AITestMode();
			foreach(t in canals) {
				if(!AIMarine.IsCanalTile(t) && !AIMarine.BuildCanal(t)) { 
					return false;
				}
			}
			if(WaterRoute.usedTiles.rawin(At(x,1)) || WaterRoute.usedTiles.rawin(At(x,2))) {
				return false;
			}
		}
		foreach(t in canals) {
			if(!AIMarine.IsCanalTile(t) && !BuildUtils.BuildCanalSafe(t)) {
				HgLog.Warning("BuildCanal2 failed:"+HgTile(t)+" "+AIError.GetLastErrorString());
				return false;
			}
		}
		local t1 = At(x,1);
		local t2 = At(x,2);
		if(!AIMarine.BuildWaterDepot(min(t1,t2),max(t1,t2))) {
			HgLog.Warning("BuildWaterDepot failed:"+HgTile(t1)+" "+HgTile(t2)+" "+AIError.GetLastErrorString());
			return false;
		}
		foreach(t in [At(0,2),At(0,3),At(x,3)]) {
			WaterRoute.usedTiles.rawset(t,true);
		}
		return true;
	}
	
	function BuildRaiseMode(isTestMode) {
		HogeAI.WaitForMoney(20000);
		local baseHeight = AITile.GetMinHeight(At(0,1)) + 1;
		return HgTile.LevelBound(platformTile, At(0,-1), baseHeight);
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
		return TileListUtils.LevelAverage( GetTileListForLevelTiles( [[0,1],[0,2]] ), null, isTestMode, 0 );*/
	}
	
	function GetTiles() {
		return [At(0,0),At(0,1)];
	}
	
	function GetEntrances() {
		return [At(0,2)];
	}
	
	function Demolish() {
		AIMarine.RemoveDock(platformTile);
		foreach(t in [At(0,2),At(0,1)]) {
			if(WaterRoute.usedTiles.rawin(t)) continue;
			AIMarine.RemoveCanal(t);
		}
		return true;
	}
	
	function GetBuildableScore() {
		if(AITile.IsWaterTile(At(0,2))) {
			return 20;
		}
		local tileList = AITileList();
		tileList.AddRectangle(At(-1,1),At(1,3));
		tileList.Valuate(function(t){
			if( AITile.IsWaterTile(t) 
					|| AITile.IsCoastTile(t) 
					|| (AITile.GetSlope(t) == AITile.SLOPE_FLAT && AITile.IsBuildable(t))) {
				return 1;
			} else {
				return 0;
			}
		});
		tileList.KeepValue(1);
		if(tileList.Count()<=3) {
			return -1000;
		}
		return tileList.Count() - AITile.GetMinHeight(platformTile);
/*	
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
		return result;*/
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
	
	function BuildPath(starts /*dst*/, goals /*src*/, suppressInterval=false) {
		local swapGoalStart = false;
		foreach(goal in goals) {
			if(AIMarine.IsCanalTile(goal) || AITile.GetMinHeight(goal)>=1) {
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
		HgLog.Info("WaterPathBuilder Pathfinding...limit:"+pathFindLimit+" swapGoalStart:"+swapGoalStart);
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
		this.path = path = Path.FromPath(path);
		if(swapGoalStart) {
			this.path = this.path.Reverse();
		}
		path = path.Reverse(); // 建設は検索と同じ方向で行う
		local prev = null;
		//local showLog = false;
		//local checkTile = HgTile.XY(708,1313).tile;
		while(path != null) {
			local cur_tile = path.GetTile();
			local parentPath = path.GetParent();
			/*if(cur_tile == checkTile) showLog = true;
			if(showLog) {
				HgLog.Info("cur:"+HgTile(cur_tile)+(prev!=null?" prev:"+HgTile(prev):"")+" mode:"+path.mode);
			}*/
			local parentTile = parentPath != null ? parentPath.GetTile() : null;
			local mode = path.mode != null ? path.mode.mode : -1;
			if(parentTile!=null && AIMap.DistanceManhattan(cur_tile, parentTile) == 2) {
				if(AITile.GetSlope(cur_tile) != AITile.SLOPE_FLAT) {
					if(!HgTile(cur_tile).Level(path.mode.level)) {
						HgLog.Warning("Cannot Level to "+path.mode.level+" "+HgTile(cur_tile)+" "+AIError.GetLastErrorString());
						return false;
					}
				}
				HogeAI.WaitForMoney(30000);
				if(!WaterPathFinder.IsLock(cur_tile,parentTile) && WaterPathFinder.BuildLock(cur_tile, parentTile, path.mode.level, true)==null) {
					HgLog.Warning("BuildLock failed."+HgTile(cur_tile)+"-"+HgTile(parentTile)+" "+AIError.GetLastErrorString());
					return false;
				}
			} else if(mode >= 256) {
				if(prev != null && AIMarine.AreWaterTilesConnected(cur_tile,prev)) {
				} else {
					if(!WaterPathFinder.LowerToZero(cur_tile)) {
						HgLog.Warning("Cannot lower to zero."+HgTile(cur_tile)+" "+AIError.GetLastErrorString());
						return false;
					}
					HogeAI.WaitForMoney(10000);
					AIMarine.BuildCanal(cur_tile);
				}
			} else if(mode >= 1) {
				if(prev!=null && (AIMarine.AreWaterTilesConnected(cur_tile,prev) || AIMap.DistanceManhattan(cur_tile, prev) == 2)) {
				} else {
					if(AITile.GetSlope(cur_tile) != AITile.SLOPE_FLAT) {
						if(!HgTile(cur_tile).Level(path.mode.level)) {
							HgLog.Warning("Cannot Level to "+path.mode.level+" "+HgTile(cur_tile)+" "+AIError.GetLastErrorString());
							return false;
						}
					}
					HogeAI.WaitForMoney(10000);
					if(!AIMarine.BuildCanal(cur_tile)) {
						HgLog.Warning("BuildCanal failed."+HgTile(cur_tile)+" prev:"+HgTile(prev)+" "+AIError.GetLastErrorString());
						return false;
					}
				}
			}
			prev = cur_tile;
			path = parentPath;
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
	
	static function IsSea(tile) {
		return (AITile.IsSeaTile(tile) && !AIMarine.IsWaterDepotTile(tile) ) 
			|| AIMarine.IsBuoyTile(tile) 
			|| (AITile.IsCoastTile(tile) && HgTile(tile).GetMaxHeightCount()==1);
	}
	
	static function LowerToZero(tile) {
		return HgTile(tile).Level(0);
	}

	static function LowerTo(tile,toHeight) {
		return HgTile(tile).Level(toHeight);
	}
	
	static function BuildLock(prev,next,prevLevel,execMode=false) {
		if(prev == null || WaterRoute.usedTiles.rawin(next) || WaterRoute.usedTiles.rawin(prev)) {
			return null;
		}
		local tile = (prev + next) / 2;
		if(AIMarine.BuildLock(tile) && AITile.GetSlope(prev) == AITile.SLOPE_FLAT && AITile.GetSlope(next) == AITile.SLOPE_FLAT) {
			return AITile.GetMaxHeight(next);
		}
		foreach(t in [prev,tile,next]) {
			if(!AITile.IsBuildable(t) && !AITile.IsWaterTile(t) && !(AITile.IsCoastTile(t) && HgTile(t).GetMaxHeightCount()==1)) {
				return null;
			}
		}
		foreach(t in [next,tile,prev]) {
			if(AIMarine.IsWaterDepotTile(t) || AITile.IsStationTile(t) || AIMarine.IsLockTile(t)) {
				return null;
			}
		}
		local next2 = next + (next - tile);
		local prev2 = prev + (prev - tile);
		if(AITile.IsStationTile(next2) || AITile.IsStationTile(prev2)) { // 駅で行き止まると、depotと航路がつながらない事がある
			return null;
		}
		local newLevel = null;
		if(AITile.GetSlope(prev) == AITile.SLOPE_FLAT) {
			local level = AITile.GetMinHeight(prev);
			if(level != prevLevel) {
				return null;
			}
			if(AITile.GetMaxHeight(next)-1 == prevLevel) {
				newLevel = prevLevel+1;
			} else if(AITile.GetMinHeight(next)+1 == prevLevel) {
				newLevel = prevLevel-1;
			} else {
				return null;
			}
			if(!HgTile(next).Level(newLevel)) {
				return null;
			}
		} else if(AITile.GetSlope(next) == AITile.SLOPE_FLAT) {
			newLevel = AITile.GetMinHeight(next);
			if(abs(newLevel - prevLevel)!=1) {
				return null;
			}
		} else {
			return null;
		}
		if(execMode) {
			HogeAI.WaitForMoney(10000);
			if(!AIMarine.BuildLock(tile)) {
				return null;
			}
		}
		return newLevel;
	}

	static function IsCenterLock(tile) {
		return AIMarine.IsLockTile(tile) && AITile.GetSlope(tile) != AITile.SLOPE_FLAT;
	}
	
	static function IsLock(prev,next) {
		local cur = (prev + next) / 2;
		if(!AIMarine.IsLockTile(prev) || !AIMarine.IsLockTile(cur) || !AIMarine.IsLockTile(next)) {
			return false;
		}
		if (!AIMarine.AreWaterTilesConnected(prev,cur)) {
			return false;
		}
		if (!AIMarine.AreWaterTilesConnected(cur,next)) {
			return false;
		}
		return true;
	}
	
	static function IsCoastAround(tile) {
		foreach(d in HgTile.DIR4Index) {
			local t = tile + d;
			if(!AITile.IsWaterTile(t) || !AIMarine.IsBuoyTile(t)) {
				return true;
			}
		}
		return false;
	}

	_aystar_class = AyStar;//import("graph.aystar", "", 6);
	_pathfinder = null;
	_max_cost = null;
	_running = null;
	goals = null;
	distCache = null;
	
	constructor() {
		_max_cost = 10000000;
		_pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);
		distCache = {};
	}
	
	function InitializePath(sources, goals, ignoreTiles=[]) {
		this.goals = goals;
	
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


	function _Cost(self, path, newTile, state, newDirection) {
		if (path == null) return 0;
		local tile = path.GetTile();
		local dir = (newTile - tile) / AIMap.DistanceManhattan(newTile,tile);
		if (AIMarine.AreWaterTilesConnected(tile,tile+dir)) {
			if(state.mode == 0) {
				if(WaterPathFinder.IsCoastAround(newTile)) {
					return path.GetCost();
				} else {
					if(WaterPathFinder.IsCoastAround(tile)) {
						return path.GetCost() + 5000;
					}
				}
			}
			return path.GetCost() + 100;
		}
		if(path.mode == null) {
		} else if(path.mode.mode == 0 && state.mode >= 256) {
			return path.GetCost() + 5000;
		} else if(path.mode.mode >= 1 && path.mode.level < state.level ) {
			return path.GetCost() + 500;
		}
		
		return path.GetCost() + 190;
	}
	
	function _Estimate(self, cur_tile, cur_direction, goal_tiles) {
		return self.GetDistanceToGoal(cur_tile);
	}
	
	function GetDistanceToGoal(cur_tile) {
		if(distCache.rawin(cur_tile)) {
			return distCache.rawget(cur_tile);
		}
		local min_cost = _max_cost;
		foreach (tile in goals) {
			local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(tile));
			local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(tile));
			min_cost = min(min_cost, min(dx, dy) * 67 * 2 + (max(dx, dy) - min(dx, dy)) * 100);
		}
		local result = min_cost * 2;
		distCache.rawset(cur_tile,result);
		return result;
	}
	
	function _Neighbours(self, path, cur_tile) {
		if (path.GetCost() >= self._max_cost) return [];
		local tiles = [];
		local state = path.mode;
		local par = path.GetParent();
		local prev = par != null ? par.GetTile() : null;
		local haveLock =  prev != null && AIMap.DistanceManhattan(prev,cur_tile) == 2;
		local mode = null;
		local curLevel = null;
		if(state == null) {
			curLevel = AITile.GetMaxHeight(cur_tile);
			if(curLevel==0) {
				mode = 0; // lowermodeから始めると、接続されているのに不必要な削りが発生しうる
			} else {
				mode = 1;
			}
		} else {
			mode = state.mode;
			curLevel = state.level;
		}
		if(haveLock) {
			if(!WaterPathFinder.IsSea(cur_tile) || AITile.GetMinHeight(cur_tile)>=1) {
				if(curLevel==0) {
					mode = 256 <= mode ? mode : 256;
				} else {
					mode = 1 <= mode && mode <= 255 ? mode : 1;
				}
			} else {
				mode = 0;
			}
		}
		local normalMode = mode == 0;
		local lowerMode = mode >= 256;
		local canalBuildMode = !lowerMode && mode >= 1;
		if(canalBuildMode) { // TODO dockが遠くなりすぎてたどりつけなくなる問題
			if (mode >= 200) return [];		
		} else if(lowerMode) {
			if ((mode - 256) >= 30) return [];		
		}
		
		//HgLog.Info("cur_tile"+HgTile(cur_tile)+" "+HgTile(prev));
		local normalMinTile = null;
		local normalMinDist = IntegerUtils.IntMax;
		/*{
			local execMode = AIExecMode();
			AISign.BuildSign(cur_tile, path.GetCost().tostring());
		}*/
		foreach (offset in haveLock ? [(cur_tile - prev)/2] : HgTile.DIR4Index) {
			local next_tile = cur_tile + offset;
			local dir = 0xff; //normalMode ? 0xff : self.GetDirection(next_tile,cur_tile); 重くなってかえってパフォーマンスが落ちる
			if (AIMarine.AreWaterTilesConnected(cur_tile,next_tile)) {
				local newMode = mode;
				if(AIMarine.IsLockTile(cur_tile) && AIMarine.IsLockTile(next_tile) && AITile.GetSlope(next_tile) != AITile.SLOPE_FLAT) {
					local next2Height = AITile.GetMaxHeight(next_tile + offset);
					if(canalBuildMode && next2Height == 0) {
						newMode = 0;
					}
					if(normalMode && next2Height == 1) {
						newMode = 1;
					}
					tiles.push([next_tile + offset, dir, {mode = newMode, level = next2Height}]);
				} else {
					if(normalMode) {
						if(!WaterPathFinder.IsCoastAround(next_tile)) {
							local nextDist = self.GetDistanceToGoal(next_tile);
							if(nextDist < normalMinDist) {
								normalMinTile = next_tile;
								normalMinDist = nextDist;
							}
						}
						tiles.push([next_tile, dir, {mode = newMode, level = curLevel}]);
					} else if(AITile.GetMaxHeight(next_tile) == curLevel) {
						tiles.push([next_tile, dir, {mode = newMode, level = curLevel}]);
					}
				}
				//HgTile(next_tile).BuildSign(""+mode);
			} else if(lowerMode) {
				if(WaterPathFinder.IsSea(next_tile)) {
					tiles.push([next_tile, dir, {mode = 0, level = curLevel}]);
				} else if(WaterPathFinder.LowerToZero(next_tile)) {
					local p = par;
					local i = 0;
					for(; i<2 && p != null; i++) {
						p = p.GetParent();
					}
					local konoji = false;
					if(i==2 && p!=null) {
						local t = p.GetTile();
						if(AIMap.DistanceManhattan(t,next_tile)==2 
								&& (AIMap.GetTileX(t)==AIMap.GetTileX(next_tile) || AIMap.GetTileY(t)==AIMap.GetTileY(next_tile))) {
							konoji = true;
						}
					}
					if(!konoji) {
						tiles.push([next_tile, dir, {mode = mode + 1,level = curLevel}]);
					}
				}
				/*
				if(!haveLock && prev == cur_tile - offset) {
					local newLevel = WaterPathFinder.BuildLock(cur_tile,next_tile+offset,0);
					//HgLog.Warning("newLevel:"+newLevel+" "+HgTile(cur_tile)+"-"+HgTile(next_tile+offset));
					if(newLevel != null) {
						tiles.push([next_tile+offset, dir, {mode = mode+1,level = newLevel}]);
					}
				}*/
			} else if(canalBuildMode) {
				if(AIMarine.BuildCanal(next_tile)
						&& !AIMarine.IsLockTile(cur_tile) /*Lock/Depotの横からCanalを作ってでてはいけない(TODO:横かどうかは調べてない)*/
						&& !AIMarine.IsWaterDepotTile(cur_tile)
						&& AITile.GetMaxHeight(next_tile) == curLevel) {
					tiles.push([next_tile, dir, {mode = mode + 1,level = curLevel}]);
				} else if((AITile.IsWaterTile(next_tile) && AITile.GetSlope(next_tile) == AITile.SLOPE_FLAT) || AIMarine.IsBuoyTile(next_tile)) {
					if(AITile.GetMaxHeight(next_tile) == curLevel
							&& !AIMarine.IsLockTile(next_tile) && !AIMarine.IsWaterDepotTile(next_tile)
							&& !AIMarine.IsLockTile(cur_tile) && !AIMarine.IsWaterDepotTile(cur_tile)) {
						tiles.push([next_tile, dir, {mode = mode,level = curLevel}]);
					}
				} else if(AITile.GetSlope(next_tile) != AITile.SLOPE_FLAT) {
					if(AITile.IsBuildable(next_tile) && HgTile(next_tile).Level(curLevel)
							&& !AIMarine.IsWaterDepotTile(cur_tile)) {
						tiles.push([next_tile, dir, {mode = mode+1,level = curLevel}]);
					}
				}
				if(!haveLock && prev == cur_tile - offset) {
					local newLevel = WaterPathFinder.BuildLock(cur_tile,next_tile+offset,curLevel);
					//HgLog.Warning("newLevel2:"+newLevel+" "+HgTile(cur_tile)+"-"+HgTile(next_tile+offset));
					if(newLevel != null) {
						tiles.push([next_tile+offset, dir, {mode = mode+1,level = newLevel}]);
					}
				}
			} else {
				if(!HogeAI.Get().roiBase && AITile.GetMaxHeight(next_tile)==1 && WaterPathFinder.LowerToZero(next_tile)) {
					tiles.push([next_tile,dir,{mode = 256,level = curLevel}]);
				}
			}
		}
		if(normalMinTile != null) {
			tiles.push([normalMinTile,0xFF,{mode = mode, level = curLevel}]);
		}
		return tiles;
	}

	function GetDirection(cur,pre) {
		local d = cur - pre;
		if(abs(d) == 1) {
			return 1 << (d + 1) / 2;
		} else {
			local w = AIMap.GetMapSizeX();
			return 4 << (d / w + 1) / 2;
		}
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
	
	static LIMIT_SEARCHCOAST = 5000;
	static params = {
		alotofcoast = false
	};

	static function SaveStatics(data) {
		data.tileCoastId <- Coasts.tileCoastId;
		local coastsArray = [];
		foreach(id,coasts in Coasts.idCoasts) {
			coastsArray.push(coasts.saveData);
		}
		data.coastsArray <- coastsArray;
		data.coasts <- Coasts.params;
	}

	static function LoadStatics(data) {
		HgTable.Extend( Coasts.tileCoastId, data.tileCoastId );
		foreach(coastsData in data.coastsArray) {
			Coasts(coastsData.coastType, coastsData.id);
		}
		foreach(coastsData in data.coastsArray) {
			Coasts.idCoasts[coastsData.id].Load(coastsData);
		}
		Coasts.params.alotofcoast = data.coasts.alotofcoast;
	}

	static function IsConnectedOnSea( coastTileA, coastTileB) {
		local coastsA = Coasts.GetCoasts(coastTileA);
		local coastsB = Coasts.GetCoasts(coastTileB);
		return coastsA.IsConnectedOnSea( coastsB );
	}

	static function IsNeedSearch(coastTile) {
		if(Coasts.params.alotofcoast) {
			return false;
		}
		if(Coasts.tileCoastId.rawin(coastTile)) {
			return false;
		}
		return true;
	}

	static function GetCoasts(coastTile) {
		if(Coasts.params.alotofcoast) {
			return GlobalCoasts;
		}
		if(Coasts.tileCoastId.rawin(coastTile)) {
			return Coasts.idCoasts[ Coasts.tileCoastId[ coastTile ] ];
		}
		local coast = Coasts();
		local coastNum = coast.SearchCoastTiles(coastTile);
		if(coastNum == Coasts.LIMIT_SEARCHCOAST) {
			HgLog.Warning("alotofcoast");
			Coasts.params.alotofcoast = true;
			return GlobalCoasts;
		}
		local small = coastNum < 80;
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
		local tileIdMap = Coasts.tileCoastId;
		tileIdMap.rawset(coastTile,id);
		while(tiles.len() >= 1) {
			local tile = tiles.pop();
			count ++;
			if(count == Coasts.LIMIT_SEARCHCOAST) {
				return count;
			}
/*			{
				local execMode = AIExecMode();
				AISign.BuildSign (tile, id.tostring());
			}*/
			foreach(d in HgTile.DIR4Index) {
				local check = tile + d;
				if( !tileIdMap.rawin(check) && IsCoastTile(check) ) {
					tileIdMap.rawset(tile,id);
					tiles.push(check);
				}
			}
		}
		tiles = [coastTile];
		local checked = {};
		while(nearLand==null && tiles.len() >= 1) {
			local tile = tiles.pop();
			checked.rawset(tile,id);
			foreach(d in HgTile.DIR4Index) {
				local check = tile + d;
				if(AITile.GetMinHeight(check) >= 1) {
					nearLand = check;
					break;
				}
				if( !checked.rawin(check) && IsCoastTile(check) ) {
					tiles.push(check);
				}
			}
		}
		return count;
	}
	
	function IsCoastTile(tile) {
		if(AITile.GetMinHeight(tile)!=0) {
			return false;
		}
		if(AITile.IsCoastTile(tile)) {
			return true;
		}
		if(AITile.GetMaxHeight(tile)==1) {
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
		
		local ex = AIMap.GetMapSizeX()-2;
		local ey = AIMap.GetMapSizeY()-2;
		local ends = [[1,y],[x,1],[ex,y],[x,ey]];
		local endsList = AITileList();
		foreach(p in ends) {
			endsList.AddTile(AIMap.GetTileIndex (p[0], p[1]));
		}
		endsList.Sort(AIList.SORT_BY_VALUE, true);
		endsList.Valuate(AIMap.DistanceManhattan, nearLand)
		local end = endsList.Begin();

		local boundCount = 0;
		local myCoast = false;
		local firstLink = null;
		
//		local end = AIMap.GetTileIndex(1,y);
		local tileList = AITileList();
		tileList.AddRectangle(nearLand,end);
		tileList.Valuate(function(t){
			if(Coasts.IsCoastTile(t)) {
				return 2;
			}
			if(AITile.IsSeaTile(t)) { //TODO: ブイ等で誤動作する
				return 1;
			}
			return 3;
		});
		tileList.Sort(AIList.SORT_BY_ITEM, nearLand < end ? true : false);
		local tileList2 = AITileList();
		tileList2.AddList(tileList);
		local distance = AIMap.DistanceManhattan(nearLand,end);
		local nextIdx = distance >= 1 ? (end - nearLand) / distance : 0;
		//HgLog.Info("nextIdx:"+nextIdx+" end:"+HgTile(end)+" nl:"+HgTile(nearLand));
		tileList.Valuate(function(t):(tileList2,nextIdx){
			return tileList2.GetValue(t + nextIdx) == tileList2.GetValue(t) ? 0 : tileList2.GetValue(t);
		});
		tileList.RemoveValue(0);
		local prevType = 3; // landから始まる
		foreach(tile,tileType in tileList) {
			//HgLog.Info("tile:"+HgTile(tile)+" tileType:"+tileType+" bc:"+boundCount);
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
		if(myCoast) boundCount ++;
		
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
				local par = Coasts.GetCoasts(firstLink);
				par.AddIsland(this);
				//HgLog.Info("SearchCoastType "+HgTile(nearLand)+":ISLAND parent:"+par);
			} else {
				GlobalCoasts.AddIsland(this);
				//HgLog.Info("SearchCoastType "+HgTile(nearLand)+":GlobalCoasts");
			}
		}
/*		{
			local execMode = AIExecMode();
			AISign.BuildSign (nearLand, "type:"+coastType+(parentSea!=null? " par["+parentSea.id+"]":"")+" fl:"+(firstLink==null?"null":HgTile(firstLink).tostring()));
		}*/
		HgLog.Info("SearchCoastType "+HgTile(nearLand)+","+HgTile(end)+" bc:"+boundCount+",fl:"+(firstLink==null?"null":HgTile(firstLink).tostring())+","+this);
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
