
class Air {
	static instance_ = GeneratorContainer(function() { 
		return Air(); 
	});
	static function Get() {
		return Air.instance_.Get();
	}

	static airportTraits = [
		{
			airportType = AIAirport.AT_SMALL
			supportBigPlane = false
			population = 800
			maxPlanes = 4
		},{
			airportType = AIAirport.AT_COMMUTER
			supportBigPlane = false
			population = 1000
			maxPlanes = 6
		},{
			airportType = AIAirport.AT_LARGE
			supportBigPlane = true
			population = 2000
			maxPlanes = 6
		},{
			airportType = AIAirport.AT_METROPOLITAN
			supportBigPlane = true
			population = 4000
			maxPlanes = 10
		},{
			airportType = AIAirport.AT_INTERNATIONAL
			supportBigPlane = true
			population = 10000
			maxPlanes = 12
		},{
			airportType = AIAirport.AT_INTERCON
			supportBigPlane = true
			population = 20000
			maxPlanes = 20
		}
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
	
	function GetMinimumAiportType() {
		local a = GetAvailableAiportTraits();
		if(a.len()==0) {
			return null;
		}
		return a[0].airportType;
	}
	
	function GetAiportTraits(airportType) {
		foreach(t in Air.airportTraits) {
			if(t.airportType == airportType) {
				return t;
			}
		}
		HgLog.Error("Unknown aiportType(GetAiportTraits):"+airportType);
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
		return 0.9;
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
	
	function SetPath(path) {
	}
	
	function AppendSrcToDestOrder(vehicle) {
	}
	
	function AppendDestToSrcOrder(vehicle) {
	}
	
	function BuildDepot(path) {
		depot = AIAirport.GetHangarOfAirport(srcHgStation.platformTile);
		return true;
	}
		
	function GetMaxVehicles() {
		local srcMax = Air.Get().GetAiportTraits(srcHgStation.airportType).maxPlanes;
		srcMax = ceil(srcMax / (ArrayUtils.Without(srcHgStation.GetUsingRoutes(),this).len()+1)); // srcHgStation.GetUsingRoutesにまだthisが含まれていない事があるので
		local destMax = Air.Get().GetAiportTraits(destHgStation.airportType).maxPlanes;
		destMax = ceil(destMax / (ArrayUtils.Without(destHgStation.GetUsingRoutes(),this).len()+1));
		return min(srcMax.tointeger(), destMax.tointeger()); //TODO 距離の考慮
	}
}


class AirRouteBuilder extends CommonRouteBuilder {

	constructor(dest, srcPlace, cargo) {
		CommonRouteBuilder.constructor(dest, srcPlace, cargo);
		makeReverseRoute = true;
	}

	function GetRouteClass() {
		return AirRoute;
	}
	
	function CreateStationFactory() { 
		local airportTypes = GetUsingAirportTypes();
		if(airportTypes.len() == 0) {
			return null;
		}
		return AirportStationFactory(airportTypes);
	}
	
	function CreatePathBuilder(engine, cargo) {
		return AirPathBuilder();
	}
	
	function GetUsingAirportTypes() {
		local usableAiportTypesDest = GetUsableAirportTypes(dest.GetLocation());
		local usableAiportTypesSrc = GetUsableAirportTypes(srcPlace.GetLocation());
		if(usableAiportTypesDest.len()==0) {
			HgLog.Info("AddNgPlace. No usable airportTypes:"+dest.GetName());
			Place.AddNgPlace(dest,AIVehicle.VT_AIR);
		}
		if(usableAiportTypesSrc.len()==0) {
			HgLog.Info("AddNgPlace. No usable airportTypes:"+srcPlace.GetName());
			Place.AddNgPlace(srcPlace,AIVehicle.VT_AIR);
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

	function GetUsableAirportTypes(location) {
		local result = [];
		local distanceCorrection = HogeAI.Get().isUseAirportNoise ? 1 : 0;
		foreach(traits in Air.Get().GetAvailableAiportTraits()) {
			local noiseLevelIncrease = AIAirport.GetNoiseLevelIncrease( location, traits.airportType );
			if( noiseLevelIncrease <= AITown.GetAllowedNoise(AIAirport.GetNearestTown( location, traits.airportType )) + distanceCorrection) {
				result.push(traits.airportType);
			}
		}
		return result;
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
	
	function CreateBestOnStationGroup( stationGroup, cargo, toTile ) {
		foreach(airportType in airportTypes) {
			SetAirportType(airportType);
			local result = StationFactory.CreateBestOnStationGroup(stationGroup, cargo, toTile);
			if(result != null) {
				return result;
			}
		}
		return null;
	}
	
	function CreateBest( place, cargo, toTile ) {
		foreach(airportType in airportTypes) {			
			SetAirportType(airportType);
			local result = StationFactory.CreateBest(place, cargo, toTile);
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
	
	function BuildStation(joinStation) {
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
			}
			if(!Rectangle(HgTile(platformTile), HgTile(platformTile + AIMap.GetTileIndex(platformNum, platformLength))).LevelTiles()) {
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

	function Remove() {
		AITile.DemolishTile(platformTile);
		RemoveWorld();
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
	
	function CanShareByMultiRoute(routeBuilder) {
		foreach(route in GetUsingRoutes()) {
			if(route.IsBiDirectional()) {
				return false;
			}
		}
		return true;
	}
}

class AirPathBuilder {
	path = null;
	
	function BuildPath(starts ,goals, suppressInterval=false) {
		return true;
	}
}

