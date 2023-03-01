
class Air {
	static instance_ = GeneratorContainer(function() { 
		return Air(); 
	});
	static function Get() {
		return Air.instance_.Get();
	}

	static airportTraits = [
		{
			level = 1
			airportType = AIAirport.AT_SMALL
			supportBigPlane = false
			population = 800
			maxPlanes = 4
			runways = 1
			stationDateSpan = 20
			cost = 5500
		},{
			level = 2
			airportType = AIAirport.AT_COMMUTER
			supportBigPlane = false
			population = 1000
			maxPlanes = 5
			runways = 1
			stationDateSpan = 16
			cost = 10000
		},{
			level = 3
			airportType = AIAirport.AT_LARGE
			supportBigPlane = true
			population = 2000
			maxPlanes = 5
			runways = 1
			stationDateSpan = 10
			cost = 16000
		},{
			level = 4
			airportType = AIAirport.AT_METROPOLITAN
			supportBigPlane = true
			population = 4000
			maxPlanes = 10
			runways = 2
			stationDateSpan = 7
			cost = 17000
		},{
			level = 5
			airportType = AIAirport.AT_INTERNATIONAL
			supportBigPlane = true
			population = 10000
			maxPlanes = 12			
			runways = 2
			stationDateSpan = 5
			cost = 22000
		},{
			level = 6
			airportType = AIAirport.AT_INTERCON
			supportBigPlane = true
			population = 20000
			maxPlanes = 20
			runways = 4
			stationDateSpan = 3
			cost = 46000
		}
	];
	static allAirportTypes = [
		AIAirport.AT_SMALL, AIAirport.AT_COMMUTER, AIAirport.AT_LARGE, AIAirport.AT_METROPOLITAN, AIAirport.AT_INTERNATIONAL, AIAirport.AT_INTERCON
	];

	function GetAvailableAiportTraits() {
		local result = [];
		foreach(t in Air.airportTraits) {
			if(AIAirport.IsValidAirportType(t.airportType) && AIAirport.IsAirportInformationAvailable(t.airportType)) {
				result.push(t);
			}
		}
		return result;
	}
	
	function GetMinimumAiportType(isBigPlane=false) {
		local a = GetAvailableAiportTraits();
		if(a.len()==0) {
			return null;
		}
		if(isBigPlane) {
			foreach(t in Air.airportTraits) {
				if(t.supportBigPlane) {
					return t.airportType;
				}
			}
			return null;
		} else {
			return a[0].airportType;
		}
	}
	
	function GetAiportTraits(airportType) {
		foreach(t in Air.airportTraits) {
			if(t.airportType == airportType) {
				return t;
			}
		}
		HgLog.Error("Unknown aiportType(GetAiportTraits):"+airportType);
	}
	
	function IsCoverAiportType(airportType1,airportType2) {
		return GetAiportTraits(airportType1).level >= GetAiportTraits(airportType2).level;
	}
}


class AirRoute extends CommonRoute {
	static instances = [];
	

	static function SaveStatics(data) {
		local a = [];
		foreach(route in AirRoute.instances) {
			a.push(route.Save());
		}
		data.airRoutes <- a;
	}
	
	static function LoadStatics(data) {
		AirRoute.instances.clear();
		foreach(t in data.airRoutes) {
			local route = AirRoute();
			route.Load(t);
			
			HgLog.Info("load:"+route);
			
			AirRoute.instances.push(route);	
			PlaceDictionary.Get().AddRoute(route);
		}
	}
	
	
	constructor() {
		CommonRoute.constructor();
		useDepotOrder = false;
		isDestFullLoadOrder = true;
	}
	
	function Save() {
		local t = CommonRoute.Save();
		return t;
	}
	
	function Load(t) {
		CommonRoute.Load(t);
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_AIR;
	}	
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxAircraft;
	}
	
	function GetThresholdVehicleNumRateForNewRoute() {
		return TrainRoute.instances.len() >= 1 ? 0.8 : 0.95;
	}

	function GetThresholdVehicleNumRateForSupportRoute() {
		return 0.9;
	}

	function GetLabel() {
		return "Air";
	}
	
	function GetBuilderClass() {
		return AirRouteBuilder;
	}
	
	
	function GetDefaultInfrastractureTypes() {
		local result = [];
		foreach(traints in Air.Get().GetAvailableAiportTraits()) {
			result.push(traints.airportType);
		}	
	
		return result;
	}

	function GetInfrastractureTypes(engine) {
		local result = [];
		local isBigPlane = AIEngine.GetPlaneType(engine) == AIAirport.PT_BIG_PLANE;
		foreach(traints in Air.Get().GetAvailableAiportTraits()) {
			if(!isBigPlane || traints.supportBigPlane) {
				result.push(traints.airportType);
			}
		}
		return result;
	}
	
	function GetSuitableInfrastractureTypes(src, dest, cargo) { //TODO: 何度も呼ばれるのでキャッシュなりを検討
		local result = [];
		foreach(traints in Air.Get().GetAvailableAiportTraits()) {
			if(src.CanBuildAirport(traints.airportType, cargo) && dest.CanBuildAirport(traints.airportType, cargo)) {
				result.push(traints.airportType);
			}
		}
		return result;
	}
	
	function EstimateMaxRouteCapacity(infrastractureType, engineCapacity) {
		if(infrastractureType == null) {
			return 0;
		}
		return 30 * engineCapacity / Air.Get().GetAiportTraits(infrastractureType).stationDateSpan;
	}
	
	function GetInfrastractureCost(infrastractureType, distance) {
		if(!HogeAI.Get().IsInfrastructureMaintenance()) {
			return 0;
		}
		return max(InfrastructureCost.Get().GetCostPerAirport() * 2, HogeAI.Get().GetInflatedMoney(150000));
	}

	function GetPathDistance() {
		local p1 = srcHgStation.platformTile;
		local p2 = destHgStation.platformTile;
		
		local w = abs(AIMap.GetTileX(p1) - AIMap.GetTileX(p2));
		local h = abs(AIMap.GetTileY(p1) - AIMap.GetTileY(p2));
		
		return (min(w,h).tofloat() * 0.414 + max(w,h)).tointeger();
	}

	function SetPath(path) {
	}
	
	function AppendSrcToDestOrder(vehicle) {
	}
	
	function AppendDestToSrcOrder(vehicle) {
	}
	
	
	function CanCreateNewRoute() {
		return true;

		if(HogeAI.Get().IsInfrastructureMaintenance()) {
			return HogeAI.Get().IsRich() /*&& InfrastructureCost.Get().CanExtendAirport()*/;
		} else {
			return true;
		}
	}
	
	function BuildDepot(path) {
		depot = AIAirport.GetHangarOfAirport(srcHgStation.platformTile);
		return true;
	}
	
	function BuildDestDepot(path) {
		destDepot = AIAirport.GetHangarOfAirport(destHgStation.platformTile);
		return true;
	}
	
	function GetStationDateSpan(self) {
		if((typeof self) == "instance" && self instanceof AirRoute) {	
			local srcUsings = ArrayUtils.Without(srcHgStation.GetUsingRoutes(),this).len()+1; // srcHgStation.GetUsingRoutesにまだthisが含まれていない事があるので
			local destUsings = ArrayUtils.Without(destHgStation.GetUsingRoutes(),this).len()+1;
			return max( Air.Get().GetAiportTraits(srcHgStation.airportType).stationDateSpan * srcUsings,
				Air.Get().GetAiportTraits(destHgStation.airportType).stationDateSpan * destUsings );
		} else {
			local traits = Air.Get().GetAvailableAiportTraits();
			if(traits.len() >= 1) {
				return traits[traits.len()-1].stationDateSpan;
			} else {
				return 30;
			}
		}
	}
	
	function IsBigPlane() {
		local vehicle = GetLatestVehicle();
		if(vehicle == null) {
			return false;
		} else {
			return AIEngine.GetPlaneType(AIVehicle.GetEngineType(vehicle)) == AIAirport.PT_BIG_PLANE;
		}
	}
	/*
	function EstimateMaxVehicles(distance, vehicleLength = 0) {
		local airportTraits = Air.Get().GetAvailableAiportTraits()
		if(airportTraits.len() == 0) {
			return 0;
		}
		return airportTraits[0].maxPlanes;
	}
	
	function GetMaxVehicles() {
		local srcMax = Air.Get().GetAiportTraits(srcHgStation.airportType).maxPlanes;
		srcMax = ceil(srcMax / (ArrayUtils.Without(srcHgStation.GetUsingRoutes(),this).len()+1));
		local destMax = Air.Get().GetAiportTraits(destHgStation.airportType).maxPlanes;
		destMax = ceil(destMax / (ArrayUtils.Without(destHgStation.GetUsingRoutes(),this).len()+1));
		local latestVehicle = GetLatestVehicle();
		if(latestVehicle != null) {
			local engine = AIVehicle.GetEngineType(latestVehicle);
			AIEngine.GetMaxSpeed(engine)
			local days = distance * 664 /  / 24 + 5; // TODO 積み込み時間の考慮
		}
		
		return min(srcMax.tointeger(), destMax.tointeger()) * 
	}*/
}


class AirRouteBuilder extends CommonRouteBuilder {
	infrastractureType = null;

	constructor(dest, srcPlace, cargo, options = {}) {
		CommonRouteBuilder.constructor(dest, srcPlace, cargo, options);
		makeReverseRoute = false;
		isNotRemoveStation = HogeAI.Get().IsInfrastructureMaintenance() == false;
		isNotRemoveDepot = true;
		checkSharableStationFirst = true;
	}

	function GetRouteClass() {
		return AirRoute;
	}
	/*
	function Build() {
		if(!InfrastructureCost.Get().CanExtendAirport()) {
			HgLog.Warning("CanExtendAirport false."+this);
			return null;
		}
		return CommonRouteBuilder.Build();
	}*/
	
	function CreateStationFactory(target) { 
		return AirportStationFactory([infrastractureType]);
		/*infrastractureTypeには見積もり結果を使う
		local airportTypes = GetUsingAirportTypes();
		if(airportTypes.len() == 0) {
			return null;
		}
		return AirportStationFactory(airportTypes);*/
	}
	
	function CreatePathBuilder(engine, cargo) {
		return AirPathBuilder();
	}
	
	function GetUsingAirportTypes() {
		local usableAiportTypesDest = GetUsableAirportTypes(dest);
		local usableAiportTypesSrc = GetUsableAirportTypes(srcPlace);
		if(usableAiportTypesDest.len()==0) {
			if(GetUsableStation(dest, cargo) != null) {
				usableAiportTypesDest = Air.allAirportTypes;
			} else {
				HgLog.Info("AddNgPlace. No usable airportTypes:"+dest.GetName());
				Place.AddNgPlace(dest,cargo,AIVehicle.VT_AIR);
			}
		}
		if(usableAiportTypesSrc.len()==0) {
			if(GetUsableStation(srcPlace, cargo) != null) {
				usableAiportTypesSrc = Air.allAirportTypes;
			} else {
				HgLog.Info("AddNgPlace. No usable airportTypes:"+srcPlace.GetName());
				Place.AddNgPlace(dest,cargo,AIVehicle.VT_AIR);
			}
		}
		local usableAiportTypeTable = HgTable.FromArray(usableAiportTypesDest);
		local result = [];
		foreach(t in usableAiportTypesSrc) {
			if(usableAiportTypeTable.rawin(t)) {
				result.push(t);
			}
		}
		result.reverse();
		return result;
	}

	function GetUsableAirportTypes(placeOrGroup) {
		local result = [];
		local distanceCorrection = HogeAI.Get().isUseAirportNoise ? 1 : 0;
		local limitCost = HogeAI.Get().GetUsableMoney() / 4;
		foreach(traits in Air.Get().GetAvailableAiportTraits()) {
			if(traits.cost * 2 > limitCost) {
				continue;
			}
			if(placeOrGroup instanceof Place) {
				if(placeOrGroup.CanBuildAirport(traits.airportType, cargo)) {
					result.push(traits.airportType);
				}
			} else {
				local noiseLevelIncrease = AIAirport.GetNoiseLevelIncrease( location, traits.airportType );
				if( noiseLevelIncrease <= AITown.GetAllowedNoise(AIAirport.GetNearestTown( location, traits.airportType )) + distanceCorrection) {
					result.push(traits.airportType);
				}
			}
		}
		return result;
	}
	
	function GetUsableStation(placeOrGroup, cargo) {
		foreach(station in HgStation.SearchStation(placeOrGroup, AIStation.STATION_AIRPORT, cargo, placeOrGroup instanceof Place ? placeOrGroup.IsAccepting() : null)) {
			if(station.CanShareByMultiRoute()) {
				return station;
			}
		}
		return null;
	}
	
	
	function BuildStart(engineSet) {
		infrastractureType = engineSet.infrastractureType;
	}
}

class AirportStationFactory extends StationFactory {
	airportTypes = null;
	
	currentAirportType = null;
	currentNum = null;
	currentLength = null;
	
	constructor(airportTypes) {
		StationFactory.constructor();
		this.ignoreDirectionScore = true;
		this.ignoreDirection = true;
		this.airportTypes = airportTypes;
	}

	function GetStationType() {
		return AIStation.STATION_AIRPORT;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_AIR;
	}
	
	function GetPlatformNum() {
		return currentNum;
	}
	
	function GetPlatformLength() {
		return currentLength;
	}
	
	function Create(platformTile,stationDirection) {
		return AirStation(platformTile, currentAirportType);
	}
	
	function GetCoverageRadius() {
		return AIAirport.GetAirportCoverageRadius( currentAirportType );
	}
	
	function SetAirportType(airportType) {
		currentAirportType = airportType;
		currentNum = AIAirport.GetAirportWidth(airportType);
		currentLength = AIAirport.GetAirportHeight(airportType);
		HgLog.Info("SetAirportType:"+airportType+" "+currentNum+"x"+currentLength);
	}
	
	
	function CreateBest( target, cargo, toTile ) {
		foreach(airportType in airportTypes) {			
			SetAirportType(airportType);
			local result = StationFactory.CreateBest(target, cargo, toTile);
			if(result != null) {
				return result;
			}
		}
		return null;
	}
}


class AirStation extends HgStation {
	airportType = null;
	
	constructor(platformTile, airportType) {
		HgStation.constructor(platformTile, 0);
		this.originTile = platformTile;
		this.airportType = airportType;
		this.platformNum = AIAirport.GetAirportWidth(airportType);
		this.platformLength = AIAirport.GetAirportHeight(airportType);
	}
	
	
	function Save() {
		local t = HgStation.Save();
		t.airportType <- airportType;
		return t;
	}
	
	function GetTypeName() {
		return "AirStation";
	}
	
	function GetAirportType() {
		return airportType;
	}
	
	function GetStationType() {
		return AIStation.STATION_AIRPORT;
	}
	
	function GetCoverageRadius() {
		return AIAirport.GetAirportCoverageRadius( airportType );
	}

	function IsBuildablePreCheck() {
		if(!HogeAI.IsBuildable(platformTile)) {
			return false;
		}
		if(!HogeAI.IsBuildable(platformTile + AIMap.GetTileIndex(platformNum-1,0))) {
			return false;
		}
		if(!HogeAI.IsBuildable(platformTile + AIMap.GetTileIndex(0,platformLength-1))) {
			return false;
		}
		if(!HogeAI.IsBuildable(platformTile + AIMap.GetTileIndex(platformNum-1,platformLength-1))) {
			return false;
		}
		return true;
	}
	
	function BuildStation(joinStation,isTestMode) {
		HogeAI.WaitForPrice(AIAirport.GetPrice(airportType));
		return AIAirport.BuildAirport (platformTile, airportType, joinStation);
	}
	
	function Build(levelTiles=true,isTestMode=true) {
		if(levelTiles) {
			if(isTestMode) {
				local allowdNoise = AITown.GetAllowedNoise( AIAirport.GetNearestTown( platformTile, airportType ));
				if(AIAirport.GetNoiseLevelIncrease( platformTile, airportType ) > allowdNoise) {
					return false;
				}
				local tilesGen = GetTilesGen();
				local tile;
				while((tile = resume tilesGen) != null) {
					if(!HogeAI.IsBuildable(tile)) {
						return false;
					}
				}
				if(!BuildPlatform(isTestMode) 
					&& ( AIError.GetLastError() == AIStation.ERR_STATION_TOO_MANY_STATIONS_IN_TOWN
						|| AIError.GetLastError() == AIStation.ERR_STATION_TOO_CLOSE_TO_ANOTHER_STATION ) ) {
					return false;
				}
			}
			if(!Rectangle(HgTile(platformTile), HgTile(platformTile + AIMap.GetTileIndex(platformNum, platformLength))).LevelTiles(AIRail.RAILTRACK_NW_SE, isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles(AirStation) failed");
				}
				return false;
			}
			if(isTestMode) {
				return true;
			}
		}

		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform(AirStation) failed");
			}
			return false;
		}
		return true;
	}

	function Demolish() {
		AIAirport.RemoveAirport(platformTile);
		return true;
	}

	function GetTilesGen() {
		for(local i=0; i<platformNum; i++) {
			for(local j=0; j<platformLength; j++) {
				yield platformTile + AIMap.GetTileIndex(i,j);
			}
		}
		return null;
	}
	
	function GetTiles() {
		return HgArray.Generator(GetTilesGen()).array;
	}
	
	function GetEntrances() {
		return [];
	}
	
	function GetBuildableScore() {
		return 0;
	}
	
	function CanShareByMultiRoute(infrastractureType = null) {
		if(infrastractureType != null) {
			if( GetAirportTraits().level < Air.Get().GetAiportTraits(infrastractureType).level ) {
				return false;
			}
		}
		usingRoutes = GetUsingRoutes();
		if(usingRoutes.len() >= 3) { // 最低数1のルートが大量にシェアされて小型空港が溢れかえるので
			return false;
		}
		foreach(route in usingRoutes) {
			if(route.IsBiDirectional()) {
				return false;
			}
		}
		return true;
	}
	
	function GetAirportTraits() {
		return Air.Get().GetAiportTraits(airportType);
	}
}

class AirPathBuilder {
	path = null;
	
	function BuildPath(starts ,goals, suppressInterval=false) {
		return true;
	}
}

