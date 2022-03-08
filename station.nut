
class StationGroup {
	static idCounter = IdCounter();
	
	id = null;
	hgStations = null;
	isVirtual = null;
	
	isNearWater = null;
	
	constructor() {
		id = idCounter.Get();
		hgStations = [];
		isVirtual = false;
	}
	
	function GetGId() {
		return "StationGroup:"+id;
	}

	function AddHgStation(hgStation) {
		hgStations.push(hgStation);
	}
	
	function RemoveHgStation(hgStation) {
		hgStations = HgArray(hgStations).Remove(hgStation).array;
		if(/*RoadRoute.GetMaxTotalVehicles() == 0 &&*/ IsAllPieceStation()) {
			foreach(station in hgStations) {
				station.Remove();
			}
		}
	}
	
	
	function GetUsingRoutesAsDest() {
		local result = [];
		foreach(route in GetUsingRoutes()) {
			if(route.destHgStation.stationGroup == this) {
				result.push(route);
			}
		}
		return result;
	}
	
	function GetUsingRoutes() {
		local result = [];
		foreach(hgStation in hgStations) {
			result.extend(hgStation.usingRoutes);
		}
		return result; // 同じrouteが複数含まれる事も稀にありうる
	}
	
	function IsAllPieceStation() {
		foreach(station in hgStations) {
			if(!(station instanceof PieceStation)) {
				return false;
			}
		}
		return true;
	}

	function GetLocation() {
		return hgStations[0].platformTile;
	}

	function GetName() {
		return hgStations[0].GetName;
	}	

	function GetStationCandidatesInSpread(stationFactory,checkedTile=null) {
		local rectangle = GetBuildablePlatformRectangle(HogeAI.Get().maxStationSpread - stationFactory.GetSpreadMargin());
		//HgLog.Info("StationGroup.GetStationCandidatesInSpread rectangle:"+rectangle);
		local result = null;
		if(HogeAI.Get().IsDistantJoinStations() == false) {
			result = [];
			foreach(s in  stationFactory.CreateOnTilesAllDirection(GetAroundTiles())) {
				if(s.GetPlatformRectangle().IsInclude(rectangle)) {
					result.push(s);
				}
			}
		} else {
			result = stationFactory.CreateInRectangle(rectangle,checkedTile);
		}
		foreach(s in result) {
			s.stationGroup = this;
		}
		HgLog.Info("StationGroup.GetStationCandidatesInSpread rectangle:"+rectangle+" result:"+result.len());
		return result;
	}
	
	function GetAroundTiles() {
		local aroundTiles = [];
		foreach(station in hgStations) {
			aroundTiles.extend(station.GetPlatformRectangle().GetAroundTiles());
		}
		return HgTable.Keys(HgTable.FromArray(aroundTiles));
	}
	
	function IsNearWater() {
		if(isNearWater != null) {
			return isNearWater;
		}
		local tileList = GetBuildablePlatformRectangle(HogeAI.Get().maxStationSpread - 1).GetTileList()
		tileList.Valuate(AITile.IsCoastTile);
		tileList.KeepValue(1);
		isNearWater = tileList.Count() >= 1;
		return isNearWater;
	}
	
	function GetBuildablePlatformRectangle(stationSpread = null) {
		if(stationSpread == null) {
			stationSpread = HogeAI.Get().maxStationSpread;
		}
		local r1 = null;
		foreach(hgStation in hgStations) {
			local r2 = hgStation.GetPlatformRectangle()
			if(r1 == null) {
				r1 = r2;
			} else {
				r1 = r1.Include(r2);
			}
		}			
		local dx = stationSpread - r1.Width();
		local dy = stationSpread - r1.Height();
		
		return Rectangle(HgTile.XY(r1.lefttop.X()-dx, r1.lefttop.Y()-dy) , HgTile.XY(r1.rightbottom.X()+dx, r1.rightbottom.Y()+dy));
	}
	
	function FindStation(typeName) {
		foreach(station in hgStations) {
			if(station.GetTypeName() == typeName) {
				return station;
			}
		}
		return null;
	}
	
	function IsAcceptingCargo(cargo) {
		foreach(station in hgStations) {
			if(station.IsAcceptingCargo(cargo)) { // TODO 両方合わせて受け入れ可の場合を逃している
				return true;
			}
		}
		return null;
	}
	function IsProducingCargo(cargo) {
		foreach(station in hgStations) {
			if(station.IsProducingCargo(cargo)) {
				return true;
			}
		}
		return null;
	}
	
	function IsTownStop() {
		foreach(station in hgStations) {
			if(station.IsTownStop()) {
				return true;
			}
		}
		return false;
	}
	
	function _tostring() {
		return hgStations.len()>=1 ? hgStations[0].GetName() : "EmptyStationGroup";
	}
}

class StationFactory {
	
	levelTiles = null;
	nearestFor = null;
	checked = null;
	ignoreDirectionScore = null;
	ignoreDirection = null; // assume platformLength=Y, platformNum=X

	constructor() {
		levelTiles = true;
		ignoreDirectionScore = false;
		ignoreDirection = false;
		checked = AIList();
	}
	

	
	function CreateBest(place, cargo, toTile, useStationGroup = true) {
		local testMode = AITestMode();
		local result = null;
		
		if(GetVehicleType() == AIVehicle.VT_AIR) {
			useStationGroup = false; // なぜか空港はJoinしようとするとERR_STATION_TOO_CLOSE_TO_ANOTHER_STATIONが発生するので強制OFF
		}
		
		if(!CargoUtils.IsPaxOrMail(cargo) && nearestFor == null) {
			nearestFor = place.GetLocation();
		}
		
		if(place.HasStation(GetVehicleType())) {
			result = PlaceStation(place.GetStationLocation(GetVehicleType()));
		}

		if(result == null && place.IsProducing() && useStationGroup) {
			result = SelectBestByStationGroup(place,cargo,toTile,true);
		}
		
		if(result == null) {
			local coverage = GetCoverageRadius();
			local tiles = HgArray.Generator( place.GetTiles( coverage ,cargo ) ).array;
			local stations = CreateOnTilesAllDirection(tiles);
			//HgLog.Info("CreateOnTilesAllDirection "+place.GetName()+" tiles:"+tiles.len()+" stations:"+stations.len()+" coverage:"+coverage+" stationType:"+GetStationType());	
			result = SelectBestHgStation(stations, place.GetLocation(), toTile, cargo, place.GetName());
		}
		
		if(result == null /*&& place.IsAccepting()*/ && useStationGroup) {
			result = SelectBestByStationGroup(place, cargo, toTile);
		}
		if(result == null && place instanceof TownCargo && place.IsAccepting()) {
			result = SelectBestWithPieceStation(place, cargo, toTile);
		}
		if(result != null) {
			result.place = place;
			result.cargo = cargo;
		} else {
			HgLog.Warning("stationPlace "+place.GetName()+" CreateBest returned no stations.");		
		}
		return result;
	}
	
	function CreateBestOnStationGroup(stationGroup, cargo, toTile) {
		this.nearestFor = stationGroup.hgStations[0].platformTile;
		local result = this.SelectBestHgStation( 
			stationGroup.GetStationCandidatesInSpread(this),
			this.nearestFor, toTile, cargo, "transfer station on "+stationGroup.hgStations[0].GetName());
		if(result != null) {
			result.cargo = cargo;
		}
		return result;
	}
	
	function GetCoverageRadius() {
		return AIStation.GetCoverageRadius( GetStationType() );
	}
	
	function GetSpreadMargin() {
		return 0;
	}
	
	function SelectBestHgStation(hgStations, fromTile, toTile, cargo, label) {
		local array = GetBestHgStationCosts(hgStations,fromTile,toTile,cargo,label);
		if(array.len()==0) {
			return null;
		} else {
			return array[0][0];
		}
	}
	
	function GetDirScore(stationDirection, fromTile, toTile) {
		local xy = GetStationDirectionXY(stationDirection);
		local pos = fromTile + AIMap.GetTileIndex(xy[0],xy[1]);
		local o = sqrt(AIMap.DistanceSquare(fromTile,toTile));
		return -1 * ((sqrt(AIMap.DistanceSquare(pos,toTile))-o)*10).tointeger();
	}

	function GetStationDirectionXY(stationDirection) {
		switch(stationDirection) {
			case HgStation.STATION_NE:
				return [-1,0];
			case HgStation.STATION_SW:
				return [1,0];
			case HgStation.STATION_SE:
				return [0,1];
			case HgStation.STATION_NW:
				return [0,-1];
		}
	}
	
	function GetBestHgStationCosts(hgStations, fromTile, toTile, cargo, label) {
		local testMode = AITestMode();
		local dirScore = [0,0,0,0];

		if(!ignoreDirectionScore) {
			dirScore[HgStation.STATION_NE] = GetDirScore(HgStation.STATION_NE,fromTile,toTile);
			dirScore[HgStation.STATION_SW] = GetDirScore(HgStation.STATION_SW,fromTile,toTile);
			dirScore[HgStation.STATION_SE] = GetDirScore(HgStation.STATION_SE,fromTile,toTile);
			dirScore[HgStation.STATION_NW] = GetDirScore(HgStation.STATION_NW,fromTile,toTile);
		}
		
		local stations2 = [];
		local isPaxOrMail = CargoUtils.IsPaxOrMail(cargo);
		local radius = GetCoverageRadius();
		local limit = AIDate.GetCurrentDate() + 100;
		
		foreach(station in hgStations) {
			if(checked.HasItem(station.platformTile)) {
				continue;
			}
			if(!station.IsBuildablePreCheck()) {
				continue;
			}
			station.score = dirScore[station.stationDirection] + station.GetBuildableScore();
			if(AITile.IsSeaTile(station.platformTile)) {
				station.score -= 10;
			}
			local platformRect = station.GetPlatformRectangle();
			if(nearestFor != null) {
				local distance = min(AIMap.DistanceManhattan(platformRect.lefttop.tile, nearestFor), AIMap.DistanceManhattan(platformRect.rightbottom.tile, nearestFor));
				station.score -= distance;
			}
			if(isPaxOrMail) {
				station.score += AITile.GetCargoProduction(station.platformTile, cargo, platformRect.Width(), platformRect.Height(), radius);
			}
			stations2.push(station);
			if(limit < AIDate.GetCurrentDate()) {
				HgLog.Warning("Station GetBestHgStationCosts reached limitDate1. stationPlace:"+label);
				break;
			}
			HogeAI.DoInterval();
		}
		stations2.sort(function(a,b) {
			return b.score-a.score;
		});
		HogeAI.DoInterval();
		HgLog.Info("Station candidates:"+stations2.len()+" stationPlace:"+label);
		local candidates = [];
		foreach(station in stations2) {
			checked.AddItem(station.platformTile,0);
			if(station.Build(levelTiles, true)) {
				HgLog.Info("Build succeeded(TestMode) stationPlace:"+label);
				station.levelTiles = levelTiles;
				return [[station,0]]; // この先は重いのでカット
			
				candidates.push(station);
				if(candidates.len() >= 8) {
					break;
				}
			} else {
				//HgLog.Info("Build failed:"+station.GetPlatformRectangle()+" "+station.error+" stationPlace:"+label);
			}
			if(limit < AIDate.GetCurrentDate()) {
				HgLog.Warning("Station GetBestHgStationCosts reached limitDate2. stationPlace:"+label);
				break;
			}
			HogeAI.DoInterval();
		}
		
		return HgArray(candidates).Map(function(s):(toTile) {
			return [s,HgTile(s.platformTile).GetPathFindCost(HgTile(toTile))];
		}).Sort(function(a,b) {
			return a[1] - b[1];
		}).array;
	}
	
	function SelectBestWithPieceStation(place, cargo, toTile) {
		HgLog.Info("SelectBestWithPieceStation stationPlace:"+place.GetName());
		local testMode = AITestMode();
		local stationCoverage = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
		local stationCandidates = [];
		
		local pieceStations = [];
		local tileGen = place.GetTiles(stationCoverage, cargo);
		local tile;
		local i=0;
		while((tile = resume tileGen) != null) {
			local pieceStation = PieceStation(tile);
			pieceStation.place = place;
			pieceStation.cargo = cargo;
			if(pieceStation.Build(false, true)) {
				pieceStations.push({
					pieceStation = pieceStation
					distance = AIMap.DistanceManhattan(toTile, tile)
				});
				if(pieceStations.len() >= 30) {
					break;
				}
			}
			i++;
			if(i > 1000) {
				HgLog.Warning("Reach i==1000. stationPlace:"+place.GetName());
				break;
			}
		}
		pieceStations.sort(function(a,b) {
			return a.distance - b.distance;
		});
		
		if(pieceStations.len() == 0) {
			HgLog.Warning("Not found piece station room. stationPlace:"+place.GetName());
			return null;
		}
		
		local pieceStation = pieceStations[0].pieceStation;
		local virtualStationGroup = StationGroup();
		virtualStationGroup.AddHgStation(pieceStation);
		local stationCandidates = virtualStationGroup.GetStationCandidatesInSpread(this);
		
		HgLog.Info("GetStationCandidatesInSpread:"+stationCandidates.len()+"pieceStation:"+HgTile(pieceStation.platformTile)+" stationPlace:"+place.GetName());
		
		local result = SelectBestHgStation(stationCandidates, place.GetLocation(), toTile, cargo, place.GetName());
		if(result != null) {
			result.stationGroup = null; //virtualStationGroupが入っているので
			result.pieceStationTile = pieceStation.platformTile;
		}
		return result;
	}
	 
	
	function SelectBestByStationGroup(place,cargo,toTile,isOnlyProducingCargo=false) {
		local stationGroups = {};
		local stations = [];
		HgTable.Extend(stationGroups, place.GetProducing().GetStationGroups());
		if(!isOnlyProducingCargo) {
			HgTable.Extend(stationGroups, place.GetAccepting().GetStationGroups());
		}
		local oldNearestFor = nearestFor;
		foreach(stationGroup,v in stationGroups) {
			if(stationGroup.IsTownStop()) {
				continue;
			}
			if(place.IsProducing() && !stationGroup.IsProducingCargo(cargo)) {
				continue;
			}
			if(place.IsAccepting() && !stationGroup.IsAcceptingCargo(cargo)) {
				continue;
			}
			if(isOnlyProducingCargo) {
				if(stationGroup.hgStations[0].cargo != cargo) {
					continue;
				}
			}
			nearestFor = stationGroup.hgStations[0].platformTile;
			local s = stationGroup.GetStationCandidatesInSpread(this);
			stations.extend(s);
		}
		local result = SelectBestHgStation(stations, place.GetLocation(), toTile, cargo, place.GetName());
		nearestFor = oldNearestFor;
		return result;
	}
	 
	function GetPlatformWidth(stationDirection) {
		if(stationDirection == HgStation.STATION_NW || stationDirection == HgStation.STATION_SE) {
			return GetPlatformNum();
		} else {
			return GetPlatformLength();
		}
	}

	function GetPlatformHeight(stationDirection) {
		if(stationDirection == HgStation.STATION_NW || stationDirection == HgStation.STATION_SE) {
			return GetPlatformLength();
		} else {
			return GetPlatformNum();
		}
	}
	
	
	function CreateOnTiles(tiles,stationDirection) {
		local result = [];
		foreach(platformTile,v in GetPlatformTiles(tiles,stationDirection)) {
			result.push(Create(platformTile,stationDirection));
		}
		return result;
	}
	
	function CreateOnTilesAllDirection(tiles) {
		
		local result = [];
		
		if(ignoreDirection) {
			foreach(platformTile,v in GetPlatformTiles(tiles,HgStation.STATION_NW)) {
				result.push(Create(platformTile,HgStation.STATION_NW));
			}
		} else {
			foreach(platformTile,v in GetPlatformTiles(tiles,HgStation.STATION_NW)) {
				result.push(Create(platformTile,HgStation.STATION_NW));
				result.push(Create(platformTile,HgStation.STATION_SE));
			}
			foreach(platformTile,v in GetPlatformTiles(tiles,HgStation.STATION_NE)) {
				result.push(Create(platformTile,HgStation.STATION_NE));
				result.push(Create(platformTile,HgStation.STATION_SW));
			}
		}

		return result;
	}
	
	
	function CreateInRectangle(rectangle,checkedTile=null) {
		local result = [];
		local w = GetPlatformLength();
		local h = GetPlatformNum();
		
		if(ignoreDirection) {
			foreach(r in rectangle.GetIncludeRectangles(h,w)) {
				local platformTile = r.lefttop.GetTileIndex();
				if(checkedTile==null || !checkedTile[1].HasItem(platformTile)) {
					if(checkedTile!=null) {
						checkedTile[1].AddItem(platformTile,0);
					}
					result.push(Create(platformTile,HgStation.STATION_NW));
				}
			}
		} else {
			foreach(r in rectangle.GetIncludeRectangles(w,h)) {
				local platformTile = r.lefttop.GetTileIndex();
				if(checkedTile==null || !checkedTile[0].HasItem(platformTile)) {
					if(checkedTile!=null) {
						checkedTile[0].AddItem(platformTile,0);
					}
					result.push(Create(platformTile,HgStation.STATION_NE));
					result.push(Create(platformTile,HgStation.STATION_SW));
				}
			}
			foreach(r in rectangle.GetIncludeRectangles(h,w)) {
				local platformTile = r.lefttop.GetTileIndex();
				if(checkedTile==null || !checkedTile[1].HasItem(platformTile)) {
					if(checkedTile!=null) {
						checkedTile[1].AddItem(platformTile,0);
					}
					result.push(Create(platformTile,HgStation.STATION_NW));
					result.push(Create(platformTile,HgStation.STATION_SE));
				}
			}
		}
		
		return result;
	}
	
	
	function GetPlatformTiles(tiles,stationDirection) {
		local w = GetPlatformWidth(stationDirection);
		local h = GetPlatformHeight(stationDirection);
		local cornerDegrees = GetCornerDegrees(w,h);
		local platformTiles = {};
		
		foreach(tile in tiles) {
			foreach(i, degree in cornerDegrees) {
				local lefttop = tile + AIMap.GetTileIndex(degree[0],degree[1]);
				platformTiles.rawset(lefttop,0);
			}
		}
		
		return platformTiles;
	}
	
	function GetCornerDegrees(w, h) {
		return [[-w+1,-h+1],[0,-h+1],[-w+1,0],[0,0]];
	}
}

class RailStationFactory extends StationFactory {
	platformLength = null;
	distance = null;
	
	constructor() {
		StationFactory.constructor();
	}

	
	function CreateBest(place, cargo, toTile, useStationGroup = true) {
		if(platformLength == null) {
			platformLength = GetMaxStatoinLength(cargo);
		}
	
		for(; platformLength >= 4; platformLength -= max(1, platformLength / 4)) {
			HgLog.Info("TrainRoute: RailStationFactory.CreateBest start "+place.GetName()+" platformLength:"+platformLength);
			local result = StationFactory.CreateBest(place, cargo, toTile, useStationGroup);
			if(result != null) {
				return result;
			}
			checked.Clear();
		}
		return null;
	}
	
	function CreateBestOnStationGroup(stationGroup, cargo, toTile) {
		if(platformLength == null) {
			platformLength = GetMaxStatoinLength(cargo);
		}
	
		for(; platformLength >= 4; platformLength -= max(1, platformLength / 4)) {
			HgLog.Info("TrainRoute: station RailStationFactory.CreateBestOnStationGroup start "+stationGroup.GetName()+" platformLength:"+platformLength);
			local result = StationFactory.CreateBestOnStationGroup(stationGroup, cargo, toTile);
			if(result != null) {
				return result;
			}
			checked.Clear();
		}
		return null;
	}
	
	function GetMaxStatoinLength(cargo) {
		if(distance != null) {
			local result =  min( 3 + distance / 25, AIGameSettings.GetValue("vehicle.max_train_length") );
			if(CargoUtils.IsPaxOrMail(cargo)) {
				result = min(10, result);
			}
			return result;
		} else {
			return 7;
		}
	}

	function GetStationType() {
		return AIStation.STATION_TRAIN;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_RAIL;
	}
}

class RoadStationFactory extends StationFactory {
	stationType = null;
	
	constructor(stationType) {
		StationFactory.constructor();
		this.stationType = stationType;
		this.ignoreDirectionScore = true;
	}
	
	function GetStationType() {
		return stationType;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_ROAD;
	}

	function GetPlatformNum() {
		return 1;
	}
	
	function GetPlatformLength() {
		return 1;
	}
	
	function Create(platformTile,stationDirection) {
		return RoadStation(platformTile,stationDirection,GetStationType());
	}
}

class SrcRailStationFactory extends RailStationFactory {
	useSimple = null;
	
	constructor() {
		RailStationFactory.constructor();
		useSimple = false;
	}

	function GetPlatformNum() {
		return 2;
	}
	function GetPlatformLength() {
		return platformLength;
	}
	function Create(platformTile,stationDirection) {
		if(useSimple) {
			local result = SimpleRailStation(platformTile, GetPlatformLength(), stationDirection);
			result.useDepot = true;
			return result;
		} else {
			return RealSrcRailStation(platformTile, GetPlatformLength(), stationDirection);
		}
	}
}

class DestRailStationFactory extends RailStationFactory {
	platformNum = null;
	
	constructor(platformNum=3) {
		RailStationFactory.constructor();
		this.platformNum = platformNum;
	}
	
	function GetPlatformNum() {
		return platformNum;
	}
	function GetPlatformLength() {
		return platformLength;
	}
	function Create(platformTile,stationDirection) {
		return DestRailStation(platformTile, platformNum, GetPlatformLength(), stationDirection);
	}
}

class TransferStationFactory extends RailStationFactory {
	constructor() {
		RailStationFactory.constructor();
	}
	
	function GetPlatformNum() {
		return 2;
	}
	function GetPlatformLength() {
		return platformLength;
	}
	function Create(platformTile,stationDirection) {
		return TransferStation(platformTile, GetPlatformLength(), stationDirection);
	}
}

class TerminalStationFactory extends RailStationFactory {
	useSimple = null;
	platformNum = null;
	
	constructor(platformNum=2) {
		RailStationFactory.constructor();
		this.platformNum = platformNum;
		this.useSimple = false;
	}
	function GetPlatformNum() {
		return platformNum;
	}
	function GetPlatformLength() {
		return platformLength;
	}
	function Create(platformTile,stationDirection) {
		if(useSimple) {
			return SimpleRailStation(platformTile, GetPlatformLength(), stationDirection);
		} else {
			return SmartStation(platformTile, GetPlatformNum(), GetPlatformLength(), stationDirection);
		}
//		return TerminalStation(platformTile, platformNum, GetPlatformLength(), stationDirection);
	}
}

class HgStation {
	static worldInstances = {};
	static idCounter = IdCounter();
	static placeStationDictionary = {};
	
	static STATION_NW = 0;
	static STATION_NE = 1;
	static STATION_SW = 2;
	static STATION_SE = 3;
	
	static function SaveStatics(data) {
		local a = array(HgStation.worldInstances.len());
		local i=0;
		foreach(station in HgStation.worldInstances) {
			a[i++] = station.savedData; // データが多すぎてSave()がタイムアウトするため事前にTableを準備しておく。AddWorld以後のフィールド変更はsavedDataを都度作る必要がある事に注意
		}
		data.stations <- a;
	}
	
	static function LoadStatics(data) {
		local groups = {};
		HgStation.worldInstances.clear();
		foreach(t in data.stations) {
			local station;
			switch(t.name) {
				case "PieceStation":
					station = PieceStation(t.platformTile);
					break;
				case "PlaceStation":
					station = PlaceStation(t.platformTile);
					break;
				case "SmartStation":
					station = SmartStation(t.platformTile, t.platformNum, t.platformLength, t.stationDirection);
					break;
				case "TransferStation":
					station = TransferStation(t.platformTile, t.platformLength, t.stationDirection);
					break;
				case "DestRailStation":
					station = DestRailStation(t.platformTile, t.platformNum, t.platformLength, t.stationDirection);
					break;
				case "TerminalStation":
					station = TerminalStation(t.platformTile, t.platformNum, t.platformLength, t.stationDirection);
					break;
				case "SrcRailStation":
					station = SrcRailStation(t.platformTile, t.platformLength, t.stationDirection);
					break;
				case "RealSrcRailStation":
					station = RealSrcRailStation(t.platformTile, t.platformLength, t.stationDirection);
					break;
				case "SimpleRailStation":
					station = SimpleRailStation(t.platformTile, t.platformLength, t.stationDirection);
					break;
				case "RoadStation":
					station = RoadStation(t.platformTile, t.stationDirection, t.stationType);
					break;
				case "WaterStation":
					station = WaterStation(t.platformTile);
					break;
				case "AirStation":
					station = AirStation(t.platformTile, t.airportType);
					break;
			}
			station.id = t.id;
			HgStation.idCounter.Skip(station.id);
			station.place = t.place != null ? Place.Load(t.place) : null;
			station.cargo = t.cargo;
			station.buildedDate = t.buildedDate;
			local stationGroup;
			if(!groups.rawin(t.stationGroup)) {
				stationGroup = StationGroup();
				stationGroup.id = t.stationGroup;
				StationGroup.idCounter.Skip(stationGroup.id);
				groups[stationGroup.id] <- stationGroup;
			} else {
				stationGroup = groups[t.stationGroup];
			}
			HgLog.Info("load station:"+station.GetName()+" "+station.GetTypeName()+" "+stationGroup.id+" "+(station.place != null ? station.place : ""));
			station.stationGroup = stationGroup;
			station.Load(t);
			station.savedData = t.rawin("savedData") ? t.savedData : station.Save();
			stationGroup.hgStations.push(station);
			HgStation.worldInstances[station.id] <- station;
			if(station.place != null) {
				station.place.AddStation(station);
			}
			BuildedPath.AddTiles(station.GetTiles());
		}
	}
	
	static function SearchStation(placeOrGroup, stationType, cargo, isAccepting) {
		local result = [];
		local stations;
		local isStationGroup;
		if(placeOrGroup instanceof Place) {
			stations = [];
			stations.extend( placeOrGroup.GetAccepting().GetStations() );
			stations.extend( placeOrGroup.GetProducing().GetStations() );
			isStationGroup = false;
		} else {
			stations = placeOrGroup.hgStations;
			isStationGroup = true;
		}
	
		foreach(hgStation in stations) {
			if(hgStation.GetStationType() == stationType) {
				if(isStationGroup) {
					result.push(hgStation);
				} else if(isAccepting) {
					if(hgStation.stationGroup.IsAcceptingCargo(cargo)) {
						result.push(hgStation);
					}
				} else {
					if(hgStation.stationGroup.IsProducingCargo(cargo)) {
						result.push(hgStation);
					}
				}
			}
		}
		return result; // 同じstationが複数返る事があり得る
	}
	
	id = null;
	platformTile = null;
	stationDirection = null;
	place = null;
	cargo = null;
	platformNum = null;
	platformLength = null;
	buildedDate = null;
	stationGroup = null;
	
	savedData = null;

	originTile = null;
	score = null;
	levelTiles = null;
	isSourceStation = null; // for BuildNewGRFRailStation
	name = null;
	builded = null;
	pieceStationTile = null;
	platformRectangle = null;
	usingRoutes = null;
	
	constructor(platformTile, stationDirection) {
		this.platformTile = platformTile;
		this.stationDirection = stationDirection;
		this.levelTiles = true;
		this.builded = false;
		this.usingRoutes = [];
	}
	
	function Save() {
		local t = {};
		t.id <- id;
		t.name <- GetTypeName();
		t.platformTile <- platformTile;
		t.stationDirection <- stationDirection;			
		t.place <- place != null ? place.Save() : null;
		t.cargo <- cargo;
		t.platformNum <- platformNum;
		t.platformLength <- platformLength;
		t.buildedDate <- buildedDate;
		if(stationGroup==null) {
			HgLog.Error("station.stationGroup==null "+t.name+" "+GetName());
		} else {
			t.stationGroup <- stationGroup.id;
		}
		return t;
	}
	
	function Load(t) {
	}

	function AddWorld() {
		this.id = idCounter.Get();
		if(stationGroup == null) {
			stationGroup = StationGroup();
		}
		
		SetName();
		buildedDate = AIDate.GetCurrentDate();
		stationGroup.AddHgStation(this);
		worldInstances[this.id] <- this;

		if(place != null) {
			place.AddStation(this);
		}

		BuildedPath.AddTiles(GetTiles());
		
		savedData = Save();
	}
	
	function RemoveWorld() {
		HgLog.Info("HgStation.RemoveWorld."+this);

		if(worldInstances.rawin(this.id)) {
			delete worldInstances[this.id];
		} else {
			HgLog.Warning("Station is not in worldInstances.(at HgStation.RemoveWorld()) "+this);
		}
		if(stationGroup != null) {
			stationGroup.RemoveHgStation(this);
			stationGroup = null;
		}
		if(place != null) {
			place.RemoveStation(this);
		}

		place = null;
		id = null;
		

		//BuildedPath.RemoveTiles(GetTiles());
	}
	
	function GetLocation() {
		return platformTile;
	}
	
	function BuildPlatform(isTestMode, supressWarning = false) {
		//isTestMode = false;
		local joinStation = AIBaseStation.STATION_NEW
		if(stationGroup != null && stationGroup.hgStations.len() >= 1 && !stationGroup.isVirtual) {
			if(!HogeAI.IsDistantJoinStations()) {
				joinStation = AIStation.STATION_JOIN_ADJACENT; // TODO 隣接駅が複数ある場合どうなるのだろうか…
			} else {
				joinStation = stationGroup.hgStations[0].GetAIStation();
			}
		}
	
		
		for(local i=0;; i++) {
			if(BuildStation(joinStation, isTestMode)) {
				return true;
			}
			if(i==1) {
				break;
			}
			if(!isTestMode && AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
				HogeAI.PlantTree(platformTile);
				continue;
			}
			break;
		}
		if(!isTestMode && !supressWarning) {
			local joinString = joinStation.tostring();
			if(joinStation == AIBaseStation.STATION_NEW) {
				joinString = "STATION_NEW"
			}
			HgLog.Warning("BuildStation failed. "+AIError.GetLastErrorString()+" "+GetPlatformRectangle()+" joinStation:"+joinString+" "+GetTypeName());
		}
		return false;
	}
	
	function At(x, y) {
		return MoveTile(originTile, x, y);
	}
		
	function GetRectangle(x1,y1, x2,y2) {
		local r1 = Rectangle.Corner(HgTile(At(x1,y1)), HgTile(At(x2-1,y2-1)));
		return Rectangle(r1.lefttop, r1.rightbottom + HgTile.XY(1,1));
	}
	
	function GetPlatformRectangle() {
		if(platformRectangle == null) {
			switch(GetPlatformRailTrack()) {
				case AIRail.RAILTRACK_NW_SE:
					platformRectangle = Rectangle(HgTile(platformTile),HgTile(platformTile) + HgTile.XY(platformNum,platformLength));
					break;
				case AIRail.RAILTRACK_NE_SW:
					platformRectangle =  Rectangle(HgTile(platformTile),HgTile(platformTile) + HgTile.XY(platformLength,platformNum));
					break;
				default:
					AIError.Log("Unknown PlatformRailTrack:"+GetPlatformRailTrack()+" (GetPlatformRectangle)");
			}
		}
		return platformRectangle;
	}
	
	function GetPlatformConnectionTiles() {
		local result = [];
		local railTrack = GetPlatformRailTrack();
		local x = AIMap.GetTileX(platformTile);
		local y = AIMap.GetTileY(platformTile);
		for(local i=0; i<platformNum; i++) {
			if(railTrack == AIRail.RAILTRACK_NW_SE) {
				result.push(AIMap.GetTileIndex(x+i,y-1));
				result.push(AIMap.GetTileIndex(x+i,y+platformLength));
			} else {
				result.push(AIMap.GetTileIndex(x-1,y+i));
				result.push(AIMap.GetTileIndex(x-platformLength,y+i));
			}
		}
		return result;
	}
	
	//abstrat function GetBuildableScore()
	//abstrat function Build()
	//abstrat function GetDepotTile() 列車を作るための
	
	function IsFlat(tile) {
		return AITile.GetSlope(tile) == AITile.SLOPE_FLAT;
	}
	
	
	function BuildPieceStation(tile) {
		local pieceStation = PieceStation(tile);
		pieceStation.place = place;
		pieceStation.cargo = cargo;
		pieceStation.stationGroup = stationGroup;
		return pieceStation.BuildExec();
	}
	
	function BuildExec() {
		if(cargo != null && AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			TownBus.Check(platformTile,null,cargo);
		} else {
			TownBus.Check(platformTile);
		}
		
		if(!builded) {
			HogeAI.WaitForMoney(40000);
			if(!Build(levelTiles,false)) {
				return false;
			}
		}
		
		AddWorld();

		if(place != null && cargo != null && place instanceof TownCargo && !(this instanceof PieceStation)) {
			if(place.IsProducing() && !RoadRoute.IsTooManyVehiclesForSupportRoute(RoadRoute)) {
				TownBus.CheckTown(place.town, null, AICargo.HasCargoClass(cargo, AICargo.CC_MAIL) ? cargo : null); // 駅が町から遠くてTownBusが作られない場合がある
			} else {
				local success = false;
				if(pieceStationTile != null) {
					success = BuildPieceStation(pieceStationTile);
				} else {
					local tileList = stationGroup.GetBuildablePlatformRectangle().GetTileList();
					local coverageRadius = AIStation.GetCoverageRadius(PieceStation.GetStationTypeCargo(cargo));
					foreach(tile in place.GetTiles(coverageRadius, cargo)) {
						if(tileList.HasItem(tile)) {
							if(BuildPieceStation(tile)) {
								success = true;
								break;
							} else if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
								break;
							}
						}
					}
				}
				if(!success) {
					HgLog.Warning("pieceStation.BuildExec failed:"+this+" "+AIError.GetLastErrorString());
					//Remove(); // 空港建設で支持を落すため、がかなりの確率で失敗するので
					return true;
				}
			}
		}
		HgLog.Info("HgStation.BuildExec succeeded."+this);

		return true;
	}
	
	
	function MoveTile(tile,dx,dy) {
		switch(stationDirection) {
			case HgStation.STATION_SE:
				return tile + AIMap.GetTileIndex(dx,dy);
			case HgStation.STATION_SW:
				return tile + AIMap.GetTileIndex(dy,-dx);
			case HgStation.STATION_NW:
				return tile + AIMap.GetTileIndex(-dx,-dy);
			case HgStation.STATION_NE:
				return tile + AIMap.GetTileIndex(-dy,dx);
			default:
				HgLog.Error("Unknown stationDirection (MoveTile):"+stationDirection);
		}
	}
	
	function GetPlatformRailTrack() {
		switch(stationDirection) {
			case HgStation.STATION_SE:
			case HgStation.STATION_NW:
				return AIRail.RAILTRACK_NW_SE;
			case HgStation.STATION_NE:
			case HgStation.STATION_SW:
				return AIRail.RAILTRACK_NE_SW;
			default:
				HgLog.Error("Unknown stationDirection (GetPlatformRailTrack):"+stationDirection);
		}
	}
	
	static function GetStationDirectionFromTileIndex(tileDirection) {
		if(tileDirection == HgTile.XY(-1,0).tile) {
			return HgStation.STATION_NE;
		}
		if(tileDirection == HgTile.XY(0,-1).tile) {
			return HgStation.STATION_NW;
		}
		if(tileDirection == HgTile.XY(1,0).tile) {
			return HgStation.STATION_SW;
		}
		if(tileDirection == HgTile.XY(0,1).tile) {
			return HgStation.STATION_SE;
		}
		gLog.Error("Unknown tileDirection (GetStationDirectionFromTileIndex):"+tileDirection);
	}
	
	function GetFrontTile(tile) {
		return MoveTile(tile,0,1);
	}
	
	function GetAIStation() {
		return AIStation.GetStationID(platformTile);
	}
	
	function SetName() {
		local s = id.tostring();
		s = "0000".slice(0,max(0,4-s.len()))+s;
		if(name != null) {
			AIStation.SetName(GetAIStation(), s+name);
		} else if(place != null) {
			AIStation.SetName(GetAIStation(), s+place.GetName());
		} else if(cargo != null) {
			local hasPlace = false;
			foreach(station in stationGroup.hgStations) {
				if(station.place != null) {
					hasPlace = true;
				}
			}
			if(!hasPlace) {
				local town = AITile.GetClosestTown(GetLocation());	
				AIStation.SetName(GetAIStation(), s+AITown.GetName(town)+" "+AICargo.GetName(cargo)+" Yard");
			}
		}
	}
	
	function GetName() {
		local stationId = GetAIStation();
		if(AIStation.IsValidStation(stationId) ) {
			return AIStation.GetName(GetAIStation());
		} else {
			return "InvalidStation "+HgTile(platformTile);
		}
	}

	function GetArrivalsTile() {
		local result = [];
		foreach(tiles in GetArrivalsTiles()) {
			result.push(tiles[0]);
			result.push(tiles[1]);
		}
		return result;
	}

	function GetDeparturesTile() {
		local result = [];
		foreach(tiles in GetDeparturesTiles()) {
			result.push(tiles[0]);
			result.push(tiles[1]);
		}
		return result;
	}
	
	function IsAcceptingCargo(cargo) {
		local rect = GetPlatformRectangle();
		local coverageRadius = GetCoverageRadius();
		return AITile.GetCargoAcceptance(rect.lefttop.tile, cargo, rect.Width(), rect.Height(), coverageRadius ) >= 8;
	}
	
	function IsProducingCargo(cargo) {
		local rect = GetPlatformRectangle();
		local coverageRadius = GetCoverageRadius();
		return AITile.GetCargoProduction(rect.lefttop.tile, cargo, rect.Width(), rect.Height(), coverageRadius ) >= 1;
	}
	
	
	function GetCoverageRadius() {
		return AIStation.GetCoverageRadius( GetStationType() );
	}
	
	function SearchIndustries(cargo, isProducing) {
		local result = [];
		local tileList = AIList();
		local radius = GetCoverageRadius();
		foreach(tile,_ in AITileList_StationType(GetAIStation(), GetStationType())) {
			tileList.AddList(Rectangle.Center(tile, radius).GetTileList());
		}
		local industryList = AIList();
		foreach(tile,_ in tileList) {
			industryList.AddItem(AIIndustry.GetIndustryID(tile),0);
		}
		local platformTileList = GetPlatformRectangle().GetTileList();
		foreach(industry,_ in industryList) {
			foreach(tile in HgIndustry(industry, isProducing).GetTiles(radius, cargo)) { // TODO: isProducing==falseの場合、最も小さいindustryIdのみを返す
				if(platformTileList.HasItem(tile)) {
					result.push(industry);
					break;
				}
			}
		}
		return result;
	}

	function GetUsingRoutesAsDest() {
		local result = [];
		local routes = Route.GetAllRoutes();
		foreach(route in routes) {
			if(route.destHgStation == this) {
				result.push(route);
			}
		}
		return result;
	}

	function GetIgnoreTiles() {
		return [];
	}

	function IsBuildablePreCheck() {
		return true;
	}
	
	function CanShareByMultiRoute() {
		return true; // CommonRouteBuilderから呼ばれる
	}
	
	function GetUsingRoutes() {
		return usingRoutes;
	}
	
	function GetUsingRoutesWithout(route) {
		return usingRoutes;
	}
	
	function AddUsingRoute(route) {
		ArrayUtils.Add(usingRoutes, route);
	}
	
	function RemoveUsingRoute(route) {
		ArrayUtils.Remove(usingRoutes, route);
	}
	
	function IsTownStop() {
		if(GetName().find("#") != null) { // TownBus stop
			return true;
		}
		return false;
	}
	
	function GetTileListForLevelTiles(tiles) {
		local tileList = AIList();
		local d1 = HgTile.XY(1,0).tile;
		local d2 = HgTile.XY(0,1).tile;
		local d3 = HgTile.XY(1,1).tile;
		local xy;
		foreach(xy in tiles) {
			local tile = At(xy[0],xy[1]);
			tileList.AddItem(tile,0);
			tileList.AddItem(tile + d1,0);
			tileList.AddItem(tile + d2,0);
			tileList.AddItem(tile + d3,0);
		}
		return tileList;
	}
	
	function _tostring() {
		return GetTypeName()+":"+id+"["+GetName()+" at "+HgTile(GetLocation())+"]";
	}


}


class RailStation extends HgStation {

	function IsBuildablePreCheck() {
		local platformRect = GetPlatformRectangle();
		return HogeAI.IsBuildable(platformRect.lefttop.tile) && HogeAI.IsBuildable(platformRect.rightbottom.tile - AIMap.GetTileIndex(1,1));
	}

	function BuildStation(joinStation,isTestMode) {
		local track = GetPlatformRailTrack();
		foreach(tile in GetPlatformConnectionTiles()) {
			if(AICompany.IsMine(AITile.GetOwner(tile))) {
				local tracks = AIRail.GetRailTracks(tile);
				if((tracks & track) != 0) {
					if(!isTestMode) {
						HgLog.Warning("Found station connected rail."+HgTile(tile));
					}
					return false;
				}
			}
		}
	
		if(cargo==null) {
			local cargos = null;
			if(place != null) {
				cargos = place.GetCargos();
			}
			if(cargos != null && cargos.len() >= 1) {
				cargo = cargos[0];
			}
		}
		if(cargo == null) {
			return AIRail.BuildRailStation(platformTile, GetPlatformRailTrack(), platformNum, platformLength, joinStation);
		} else {
			local industryType;
			if(place != null) {
				if(place instanceof HgIndustry) {
					industryType = AIIndustry.GetIndustryType(place.industry);
				} else if(place instanceof TownCargo) {
					industryType = AIIndustryType.INDUSTRYTYPE_TOWN;
				}
			}
			if(industryType == null) {
				industryType = AIIndustryType.INDUSTRYTYPE_UNKNOWN;
			}
		
			return AIRail.BuildNewGRFRailStation(platformTile, GetPlatformRailTrack(), platformNum, platformLength, joinStation, 
				cargo,  industryType,  industryType, 500, isSourceStation!=null ? isSourceStation : (place!=null ? place.IsProducing() : true));
		}
	}
	
	function RemoveStation() {
		local r = GetPlatformRectangle();
		return AIRail.RemoveRailStationTileRectangle (platformTile, platformTile + AIMap.GetTileIndex(r.Width()-1, r.Height()-1), false);
	}
	
	function GetStationType() {
		return AIStation.STATION_TRAIN;
	}
}

class RoadStation extends HgStation {
	static roads = [[1,0],[0,0],[0,1],[1,1],[2,1],[2,0],[1,0]];
	
	stationType = null;
	
	constructor(platformTile, stationDirection, stationType) {
		HgStation.constructor(platformTile, stationDirection/*HgStation.GetStationDirectionFromTileIndex(frontTile - platformTile)*/);
		this.stationType = stationType;
		this.platformNum = 1;
		this.platformLength = 1;
		if(stationDirection == HgStation.STATION_SE) {
			originTile =  MoveTile(platformTile,-1,0);
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile =  MoveTile(platformTile,-1,0);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile =  MoveTile(platformTile,-1,0);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile =  MoveTile(platformTile,-1,0);
		}
	}
	
	function GetStationType() {
		return stationType;
	}

	
	function Save() {
		local t = HgStation.Save();
		t.stationType <- stationType;
		return t;
	}
	
	function GetTypeName() {
		return "RoadStation";
	}
	
	static function GetRoadVehicleType(stationType) {
		switch(stationType) {
			case AIStation.STATION_BUS_STOP: 
				return AIRoad.ROADVEHTYPE_BUS;
			case AIStation.STATION_TRUCK_STOP: 
				return AIRoad.ROADVEHTYPE_TRUCK;
		}
	}
	
	function GetPlatformRailTrack() { // 向きが逆だった
		switch(HgStation.GetPlatformRailTrack()) {
			case AIRail.RAILTRACK_NW_SE:
				return AIRail.RAILTRACK_NE_SW;
			case AIRail.RAILTRACK_NE_SW:
				return AIRail.RAILTRACK_NW_SE;
		}
	}
	
	function BuildStation(joinStation,isTestMode) {
		local result = AIRoad.BuildDriveThroughRoadStation(At(1,0), At(0,0), RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
		if(!result) {
			//HgLog.Warning("platformTile:"+HgTile(At(0,0))+" front:"+HgTile(At(1,0))+" GetRoadVehicleType:"+RoadStation.GetRoadVehicleType(GetStationType())+" joinStation:"+AIStation.GetName(joinStation)+" "+AIError.GetLastErrorString());
		}
		return result;
	}
	
	function Build(levelTiles=true,isTestMode=true) {
//		HgLog.Warning("Build levelTiles:"+levelTiles+" isTestMode:"+isTestMode);

		if(levelTiles) {
			if(isTestMode) {
				foreach(tile in GetTiles()) {
					if(!HogeAI.IsBuildable(tile) && (!AIRoad.IsRoadTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile))) {
						return false;
					}
				}
			}
			if(!GetRectangle(0,0, 3,2).LevelTiles(GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles failed");
				}
				return false;
			}
			if(isTestMode) {
				if(!BuildPlatform(isTestMode) 
						&& (AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR 
								|| AIError.GetLastError() == AIRoad.ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION
								|| AIError.GetLastError() == AIError.ERR_UNKNOWN/*道路状況によってはこれが返る*/)) {
					return false;
				}
				return true;
			}
		}

		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform failed");
			}
			return false;
		}
		
		local prev = null;
		foreach(road in roads) {
			if(prev != null) {
				if(!RoadRouteBuilder.BuildRoadUntilFree(At(prev[0],prev[1]), At(road[0],road[1])) && AIError.GetLastError() != AIError.ERR_ALREADY_BUILT){ 
					if(!isTestMode) {
						HgLog.Warning("BuildRoad failed "+HgTile(At(prev[0],prev[1]))+"-"+HgTile(At(road[0],road[1])) + " " + AIError.GetLastErrorString());
					}
					return false;
				}
			}
			prev = road;
		}
		
		return true;
	}
	
	function BuildDepot() {
		foreach(road in roads) {
			local tile = At(road[0],road[1]);
			foreach(hgTile in HgTile(tile).GetDir4()) {
				if(hgTile.BuildRoadDepot(hgTile.tile, tile)) {
					return hgTile.tile;
				}
			}
		}
		return null;
	}

	function Remove() {
		AIRoad.RemoveRoadStation(platformTile);
		RemoveWorld();
		return true;
	}

	function GetTiles() {
		local result = [];
		foreach(road in roads) {
			result.push(At(road[0],road[1]));
		}
		return result;
	}
	
	function GetEntrances() {
		local result = [];
		foreach(road in roads) {
			local p = At(road[0],road[1]);
			if(p != platformTile) {
				result.push(At(road[0],road[1]));
			}
		}
		return result;
	}
	
	function GetBuildableScore() {
		return 0;
/*		local result = 0; //TODO: 周囲がflat isbuildableかどうか
		
		foreach(tile in GetTiles()) {
			if(HogeAI.IsBuildable(tile)) {
				result ++;
				if(IsFlat(tile)) {
					result ++;
				}
			}
		}
		return result * 2;*/
	}
}

class PlaceStation extends HgStation {
	constructor(platformTile) {
		HgStation.constructor(platformTile,0);
		this.platformNum = 0;
		this.platformLength = 0;
	}

	function GetTypeName() {
		return "PlaceStation";
	}
	
	function Build(levelTiles=false,isTestMode=false) {
		return true;
	}

	function Remove() {
		return true;
	}

	function IsAcceptingCargo(cargo) {
		return place.GetAccepting().IsTreatCargo(cargo);
	}

	function IsProducingCargo(cargo) {
		return place.GetProducing().IsTreatCargo(cargo);
	}

	function GetStationType() {
		return null;
	}
	
	function GetTiles() {
		return [];
	}
	
	function GetEntrances() {
		return [GetLocation()-1]; //それ自体は通行できないので少しずらす
	}
}

class PieceStation extends HgStation {

	constructor(platformTile) {
		HgStation.constructor(platformTile,0);
		originTile = platformTile;
		platformNum = 1;
		platformLength = 1;
	}
	
	function GetTypeName() {
		return "PieceStation";
	}
	
	function Build(levelTiles=false,isTestMode=false) {
		if(!AIRoad.IsRoadTile(platformTile)) {
			return false;
		}
		if(isTestMode) {
			local connects = [];
			foreach(d in HgTile.DIR4Index) {
				connects.push(AIRoad.AreRoadTilesConnected(platformTile, platformTile + d));
			}
			local isSlope0 = RoadPathFinder._IsSlopedRoad(platformTile + HgTile.DIR4Index[0], platformTile, platformTile + HgTile.DIR4Index[3]);
			local isSlope1 = RoadPathFinder._IsSlopedRoad(platformTile + HgTile.DIR4Index[1], platformTile, platformTile + HgTile.DIR4Index[2]);
			if(connects[0]) {
				return !connects[1] && !connects[2] && connects[3] && !isSlope0;
			} else if(connects[1]) {
				return !connects[0] && connects[2] && !connects[3] && !isSlope1;
			} else {
				return (!connects[2] || !connects[3]) && !isSlope0 && !isSlope1;
			}
		}
		
		return BuildPlatform(isTestMode, true);
	}
	
	function BuildStation(joinStation,isTestMode) {
		local currentRoadType = AIRoad.GetCurrentRoadType();
		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());
		local result = _BuildStation(joinStation);
		AIRoad.SetCurrentRoadType(currentRoadType);
		return result;
	}
	
	function _BuildStation(joinStation) {
//		HgLog.Info("platformTile:"+HgTile(platformTile)+" front:"+HgTile(GetFrontTile(platformTile))+" GetRoadVehicleType:"+GetRoadVehicleType()+" joinStation:"+joinStation);
		
		if(BuildUtils.RetryUntilFree(function():(platformTile,joinStation) {
			return AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[0], 
				RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
		})) {
			return true;
		}
		if(BuildUtils.RetryUntilFree(function():(platformTile,joinStation) {
			return AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[1], 
				RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
		})) {
			return true;
		}
		return false;
	}
	
	function BuildAfter() {
	}
	
	function Remove() {
		AIRoad.RemoveRoadStation(platformTile);
		RemoveWorld();
		return true;
	}
	
	function GetTiles() {
		return [platformTile];
	}
	
	function GetEntrances() {
		return [platformTile];
	}
	
	function GetStationType() {
		return PieceStation.GetStationTypeCargo(cargo);
	}
	
	static function GetStationTypeCargo(cargo) {
		if(AICargo.HasCargoClass (cargo, AICargo.CC_PASSENGERS)) {
			return AIStation.STATION_BUS_STOP;
		} else {
			return AIStation.STATION_TRUCK_STOP;
		}
	}
	
}

class TransferStation extends RailStation {
	constructor(platformTile, platformLength, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		this.platformNum = 2;
		this.platformLength = platformLength;

		if(stationDirection == HgStation.STATION_SE) {
			originTile =  MoveTile(platformTile,0,0);
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile =  MoveTile(platformTile,-1,-platformLength+1);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile =  MoveTile(platformTile,0,-platformLength+1);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile =  MoveTile(platformTile,-1,0);
		}
	}
	
	function GetTypeName() {
		return "TransferStation";
	}
	
	
	function GetArrivalsTiles() {
		return [[At(1,platformLength+1),At(1,platformLength)]];
	
	}
	
	function GetDeparturesTiles() {
		return [[At(1,-3), At(1,-2)]];
	}

	function GetIgnoreTiles() {
		return [At(0,-3), At(0,platformLength+1)];
	}

	
	function GetRails() {
		local result = [];
		
		result.push([[1,-3],[1,-2],[1,-1]]);
		result.push([[1,-2],[1,-1],[1,0]]);
		result.push([[1,-3],[1,-2],[0,-2]]);
		result.push([[1,-2],[0,-2],[0,-1]]);
		result.push([[0,-2],[0,-1],[0,0]]);

		local a = [];
/*		a.push([[0,-1],[0,0],[-1,0]]);
		a.push([[0,1],[0,0],[-1,0]]);
		a.push([[1,-1],[1,0],[2,0]]);
		a.push([[1,1],[1,0],[2,0]]);*/

		a.push([[0,-1],[0,0],[1,0]]);
		a.push([[0,0],[1,0],[1,1]]);
		a.push([[1,-1],[1,0],[1,1]]);
		foreach(r in a) {
			local nr = [];
			foreach(p in r) {
				nr.push([p[0],p[1] + platformLength]);
			}
			result.push(nr);
		}
		
		return result;
	}
	
	
	function GetMustBuildableAndFlatTiles() {
		for(local x=0; x<2; x++) {
			for(local y=-2; y<platformLength+1; y++) {
				yield [x,y];
			}
		}
		yield [1,platformLength+2];
		yield [1,-3];

/*		yield [-1,platformLength];
		yield [2,platformLength];*/

		return null;
	}
	
	
	function GetHopeBuildableAndFlatTiles() {
		return [];
	}

	function GetDepots() {
		return [];//[[At(-1,platformLength), At(0,platformLength)],[At(2,platformLength), At(1,platformLength)]];
	}

	function Build(levelTiles=true, isTestMode=true) {
		local tilesGen = GetMustBuildableAndFlatTiles();
		local tiles = [];
		local xy;
		while((xy = resume tilesGen) != null) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
			tiles.push(xy);
		}

		if(!TileListUtil.LevelAverage(GetTileListForLevelTiles(tiles), GetPlatformRailTrack(), isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
			}
			return false;
		}

		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform failed."+AIError.GetLastErrorString());
				return false;
			} else if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				return false;
			}
		}
		/*
		foreach(depot in GetDepots() ) {
			if(!AIRail.BuildRailDepot(depot[0], depot[1])) {
				if(!isTestMode) {
					HgLog.Warning("BuildRailDepot failed."+AIError.GetLastErrorString());
					return false;
				} else if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
					return false;
				}
			}
		}*/
		
		if(isTestMode) {
			return true;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("BuildRail Failed."+AIError.GetLastErrorString());
				return false;
			}
		}
		
		BuildSignal();
		
		return true;
	}
	
	
	function BuildAfter() {
	}
	
	function RemoveDepots() {
		/*
		foreach(depot in GetDepots() ) {
			AITile.DemolishTile(depot[0]);
		}*/
	}
	
	function BuildSignal() {
		AIRail.BuildSignal(At(0,-1),At(0,0),AIRail.SIGNALTYPE_PBS_ONEWAY );
		AIRail.BuildSignal(At(1,-1),At(1,0),AIRail.SIGNALTYPE_PBS_ONEWAY );
	}
	
	function RemoveSignal() {
		AIRail.RemoveSignal(At(0,-1),At(0,0));
		AIRail.RemoveSignal(At(1,-1),At(1,0));
	}
	
	
	function Remove() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " "+AIError.GetLastErrorString());
			result = false;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+HgTile(At(rail[1][0],rail[1][1]))+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		
		//RemoveDepots();
		
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
/*		result.push(At(-1,platformLength));
		result.push(At(2,platformLength));*/
		return result;
	}
	
	function GetBuildableScore() {
		local result = 0;
		foreach(xy in GetHopeBuildableAndFlatTiles()) {
			if(AITile.IsBuildable(At(xy[0],xy[1]))) {
				result ++;
				if(IsFlat(At(xy[0],xy[1]))) {
					result ++;
				}
			}
		}
		return result;
	}
}

class SmartStation extends RailStation {
		
	constructor(platformTile, platformNum, platformLength, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		this.platformNum = platformNum;
		this.platformLength = platformLength;

		if(stationDirection == HgStation.STATION_SE) {
			originTile =  MoveTile(platformTile,platformNum-2,0);
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile =  MoveTile(platformTile,-1,-platformLength+1);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile =  MoveTile(platformTile,platformNum-2,-platformLength+1);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile =  MoveTile(platformTile,-1,0);
		}
	}
	
	
	function GetTypeName() {
		return "SmartStation";
	}
	
	
	function GetArrivalsTiles() {
		if(platformNum==2) {
			return [[At(0,platformLength+5),At(0,platformLength+4)]];
		} else if(platformNum==3) {
			return [[At(-1,platformLength+6),At(-1,platformLength+5)]];
		}
	
	}
	
	function GetDeparturesTiles() {
		return [[At(1,platformLength+4),At(1,platformLength+3)]];
	}
	
	function GetRails() {
		local result = [];
		
		result.push([[0,-1],[0,0],[0,1]]);
		result.push([[0,-1],[0,0],[-1,0]]);
		//result.push([[0,-1],[0,0],[1,0]]);
		result.push([[1,0],[0,0],[0,1]]);

		result.push([[0,0],[-1,0],[-1,1]]);

		result.push([[1,-1],[1,0],[0,0]]);
		result.push([[1,-1],[1,0],[1,1]]);
		//result.push([[1,1],[1,0],[0,0]]);
		result.push([[1,0],[1,1],[1,2]]);
		result.push([[1,1],[1,2],[1,3]]);
		result.push([[1,2],[1,3],[1,4]]);

		result.push([[-1,0],[-1,1],[-1,2]]);

		result.push([[-1,1],[-1,2],[0,2]]);
		result.push([[-1,2],[0,2],[0,3]]);
		result.push([[0,2],[0,3],[1,3]]);
		result.push([[0,3],[1,3],[1,4]]);
		
		if(platformNum==3) {
			result.push([[-1,-1],[-1,0],[-1,1]]);
			result.push([[-1,-1],[-1,0],[-2,0]]);
			result.push([[-1,0],[-2,0],[-2,1]]);
			result.push([[-2,0],[-2,1],[-2,2]]);
			result.push([[-2,1],[-2,2],[-1,2]]);
			result.push([[-2,2],[-1,2],[-1,3]]);
			result.push([[-1,2],[-1,3],[-1,4]]);
			result.push([[-1,3],[-1,4],[-1,5]]);
			result.push([[-1,4],[-1,5],[-1,6]]);
			result.push([[0,4],[0,5],[-1,5]]);
			result.push([[0,5],[-1,5],[-1,6]]);
		}

		local n = [];
		foreach(r in result) {
			local nr = [];
			foreach(p in r) {
				nr.push([p[0],p[1] + platformLength]);
			}
			n.push(nr);
		}

		return n;
	}
	
	function GetIgnoreTiles() {
		if(platformNum==3) {
			return [At(0, platformLength+6)];
		} else {
			return [];
		}
	}

	function GetMustBuildableAndFlatTiles() {
		if(platformNum==2) {
			for(local x=0; x<2; x++) {
				for(local y=0; y<platformLength+6; y++) {
					yield [x,y];
				}
			}

			yield [-1,platformLength];
			yield [-1,platformLength+1];
			yield [-1,platformLength+2];
		} else if(platformNum==3) {
			for(local x=-1; x<2; x++) {
				for(local y=0; y<platformLength+5; y++) {
					yield [x,y];
				}
			}
			yield [-1,platformLength+6];

			yield [-2,platformLength];
			yield [-2,platformLength+1];
			yield [-2,platformLength+2];
		}

		return null;
	}
	
	function GetHopeBuildableAndFlatTiles() {
		local result = [];
		if(platformNum==2) {
			for(local x=-1; x<3; x++) {
				for(local y=platformLength+5; y<platformLength+7; y++) {
					result.push([x,y]);
				}
			}
			result.push([2,platformLength+4]);
		} else if(platformNum==3) {
			for(local x=-2; x<3; x++) {
				for(local y=platformLength+5; y<platformLength+7; y++) {
					result.push([x,y]);
				}
			}
			result.push([2,platformLength+4]);
		}
		return result;
	}


	function Build(levelTiles=true, isTestMode=true) {
		local tilesGen = GetMustBuildableAndFlatTiles();
		local tiles = [];
		local xy;
		while((xy = resume tilesGen) != null) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
			tiles.push(xy);
		}

		if(!TileListUtil.LevelAverage(GetTileListForLevelTiles(tiles), GetPlatformRailTrack(), isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
			}
			return false;
		}

		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform failed."+AIError.GetLastErrorString());
				return false;
			} else if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				return false;
			}
		}
		
		local bridge_list = AIBridgeList_Length(4);
		bridge_list.Valuate(AIBridge.GetMaxSpeed);
		bridge_list.Sort(AIList.SORT_BY_VALUE, false);
		if(!AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), At(0,platformLength+1), At(0,platformLength+4))) {
			if(!isTestMode) {
				HgLog.Warning("BuildBridge failed."+AIError.GetLastErrorString());
				return false;
			} else if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				return false;
			}
		}
		
		if(isTestMode) {
			return true;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("BuildRail Failed."+AIError.GetLastErrorString());
				return false;
			}
		}
		
		BuildSignal();
		
		return true;
	}
	
	
	function BuildAfter() {
	}
	
	function RemoveDepots() {
	}
	
	function BuildSignal() {
		AIRail.BuildSignal(At(1,platformLength+2),At(1,platformLength+1),AIRail.SIGNALTYPE_PBS_ONEWAY );
		AIRail.BuildSignal(At(0,platformLength+3),At(0,platformLength+2),AIRail.SIGNALTYPE_PBS_ONEWAY );
	}
	
	function RemoveSignal() {
		AIRail.RemoveSignal(At(1,platformLength+2),At(1,platformLength+1));
		AIRail.RemoveSignal(At(0,platformLength+3),At(0,platformLength+2));
	}
	
	
	function Remove() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " "+AIError.GetLastErrorString());
			result = false;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+HgTile(At(rail[1][0],rail[1][1]))+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		
		AITile.DemolishTile(At(0,platformLength+1));
		
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
		result.push(At(0,platformLength+1));
		result.push(At(0,platformLength+4));
		return result;
	}
	
	function GetBuildableScore() {
		local result = 0;
		foreach(xy in GetHopeBuildableAndFlatTiles()) {
			local tile = At(xy[0],xy[1]);
			if(AITile.IsBuildable(tile)) {
				result ++;
				if(IsFlat(tile)) {
					result ++;
				}
			}
		}
		return result;
	}
	
}

class DestRailStation extends RailStation {
	depots = null;

	constructor( platformTile, platformNum, platformLength, stationDirection) {
		this.platformNum = platformNum;
		this.platformLength = platformLength;
		HgStation.constructor(platformTile,stationDirection);
		if(stationDirection == HgStation.STATION_SE) {
			originTile =  MoveTile(platformTile,0,-2);
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile =  MoveTile(platformTile,1-platformNum,-platformLength-1);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile =  MoveTile(platformTile,0,-platformLength-1);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile =  MoveTile(platformTile,1-platformNum,-2);
		}
		depots = [];
	}
	
	function GetTypeName() {
		return "DestRailStation";
	}

	function Save() {
		local t = HgStation.Save();
		t.depots <- depots;
		return t;
	}
	
	function Load(t) {
		depots = t.depots;
	}
	
	function Build(levelTiles=false, isTestMode=true) {
		local needsBuildable = [];
		for(local i=0; i<platformNum; i++) {
			needsBuildable.push([i,platformLength+3]);
			needsBuildable.push([i,-1]);
		}
		foreach(xy in needsBuildable) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
		}
		if(levelTiles) {
			if(isTestMode) {
				foreach(tile in GetTiles()) {
					if(!HogeAI.IsBuildable(tile)) {
						if(!isTestMode) {
							HgLog.Warning("not IsBuildable "+HgTile(tile));
						}
						return false;
					}
				}
			}
			if(!GetRectangle(0,0, platformNum,platformLength+3).LevelTiles(GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
			if(isTestMode) {
				if(!BuildPlatform(isTestMode) && AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
					return false;
				}
				return true;
			}
		}
		
		
		local rails = GetRails();
		foreach(rail in rails) {
			if(!HogeAI.IsBuildable(At(rail[1][0],rail[1][1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(rail[1][0],rail[1][1])));
				}
				return false;
			}
		}
		local needsFlat = [];
		for(local i=0; i<platformNum; i++) {
			needsFlat.push([i,platformLength+2]);
			needsFlat.push([i,0]);
		}
		foreach(xy in needsFlat) {
			if(!IsFlat(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not Flat "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
		}
		
		if(!GetPlatformRectangle().IsBuildable()) {
			if(!isTestMode) {
				HgLog.Warning("not IsBuildable PlatformRectangle");
			}
			return false;
		}
		
		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform failed."+AIError.GetLastErrorString());
			}
			return false;
		}
		
		
		foreach(rail in rails) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				if(!isTestMode) {
					HgLog.Warning("BuildRail Failed."+AIError.GetLastErrorString());
				}
				return false;
			}
		}
		for(local x=0; x<platformNum; x++) {
			if(!BuildRailTracksAll(At(x,0))) {
				if(!isTestMode) {
					HgLog.Warning("BuildRailTracksAll Failed."+AIError.GetLastErrorString());
				}
				return false;
			}
			
			if(!BuildRailTracksAll(At(x,platformLength+2))) {
				if(!isTestMode) {
					HgLog.Warning("BuildRailTracksAll Failed."+AIError.GetLastErrorString());
				}
				return false;
			}
		}
		for(local x=1; x<platformNum-1; x++) {
		}

		BuildSignal();
		
		return true;
	}
	
	function BuildDepot(p1,p2) {
		if(AIRail.BuildRailDepot(p1,p2)) {
			depots.push(p1);
		}
		savedData = Save();
	}
	
	function RemoveDepots() {
		foreach(tile in depots) {
			if(!BuildUtils.DemolishTileUntilFree(tile)) {
				HgLog.Warning("DemolishTile failed."+HgTile(tile)+" "+AIError.GetLastErrorString());
			}
		}
		depots = [];
		savedData = Save();
	}
	
	function BuildAfter() {
		for(local x=0; x<platformNum; x++) {
			BuildDepot(At(x,-1),At(x,0));
		}
//		BuildDepot(At(-1,0),At(0,0));
//		BuildDepot(At(platformNum,0),At(platformNum-1,0));
	}
	
	function Remove() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " "+AIError.GetLastErrorString());
			result = false;
		}
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+HgTile(At(rail[1][0],rail[1][1]))+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		for(local x=0; x<platformNum; x++) {
			foreach(tile in [At(x,0),At(x,platformLength+2)]) {
				if(!RemoveRailTracksAll(tile)) {
					HgLog.Warning("RemoveRailTracksAll failed."+HgTile(tile)+" "+AIError.GetLastErrorString());
					result = false;
				}
			}
		}
		RemoveDepots();
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
		for(local x=0; x<platformNum; x++) {
			result.push(At(x,0));
			result.push(At(x,platformLength+2));
		}
		result.extend(depots);
		return result;
	}
	
	function GetRails() {
		local rails = [];
		for(local i=0; i<platformNum; i++) {
			rails.push([[i,platformLength],[i,platformLength+1],[i,platformLength+2]]);
		}
		return rails;
	}
	
	function BuildRailTracksAll(tile) {
		local railTracks = [AIRail.RAILTRACK_NE_SW,AIRail.RAILTRACK_NW_SE ,AIRail.RAILTRACK_NW_NE ,AIRail.RAILTRACK_SW_SE ,AIRail.RAILTRACK_NW_SW ,AIRail.RAILTRACK_NE_SE];
		foreach(railTrack in railTracks) {
			if(!AIRail.BuildRailTrack(tile,railTrack)) {
				return false;
			}
		}
		return true;
	}
	
	function RemoveRailTracksAll(tile) {
		local railTracks = [AIRail.RAILTRACK_NE_SW,AIRail.RAILTRACK_NW_SE ,AIRail.RAILTRACK_NW_NE ,AIRail.RAILTRACK_SW_SE ,AIRail.RAILTRACK_NW_SW ,AIRail.RAILTRACK_NE_SE];
		foreach(railTrack in railTracks) {
			if(!AIRail.RemoveRailTrack(tile,railTrack)) {
				return false;
			}
		}
		return true;
	}
	
	function BuildSignal() {
		for(local i=0; i<platformNum; i++) {
			if(!AIRail.BuildSignal(At(i,platformLength+1),At(i,platformLength),AIRail.SIGNALTYPE_PBS_ONEWAY )) {
				return false;
			}
		}
		return true;
	}
	
	function RemoveSignal() {
		for(local i=0; i<platformNum; i++) {
			if(!AIRail.RemoveSignal(At(i,platformLength+1),At(i,platformLength))) {
				return false;
			}
		}
		return true;
	}
	
	function GetBuildableScore() {
		// TODO向きの考慮もここで行う
		return GetEntranceRooms() + GetEntranceFlats();
	}
	
	function GetEntranceRooms() {
		local result = 0;
		for(local i=-1; i<=platformNum; i++) {
			for(local j=platformLength+2; j<=platformLength+3;j++) {
				if(HogeAI.IsBuildable(At(i,j))) {
					result ++;
				}
			}
		}
		result -= platformNum;
		for(local i=0; i<platformNum; i++) {
			if(HogeAI.IsBuildable(At(i,-1))) {
				result ++;
			}
		}
		for(local i=-1; i<=platformLength+1; i++) {
			if(HogeAI.IsBuildable(At(-1,i))) {
				result ++;
			}
			if(HogeAI.IsBuildable(At(platformNum,i))) {
				result ++;
			}
		}
		
		return result * 3;
	}
	
	function GetEntranceFlats() {
		local result = 0;
		for(local i=-1; i<=platformNum; i++) {
			for(local j=platformLength+2; j<=platformLength+3;j++) {
				if(IsFlat(At(i,j)) && HogeAI.IsBuildable(At(i,j))) {
					result ++;
				}
			}
		}
		result -= platformNum;
		for(local i=0; i<platformNum; i++) {
			if(IsFlat(At(i,-1)) && HogeAI.IsBuildable(At(i,-1))) {
				result ++;
			}
		}
		return result;
	}
	/*
	function GetArrivalsTiles() {
		local result = [];
		for(local i=0; i<platformNum; i++) {
			result.push([At(i,-1),At(i,0)]);
		}
		result.push([At(-1,0),At(0,0)]);
		result.push([At(platformNum,0),At(platformNum-1,0)]);
		return result;
	}*/
	
	
	function GetArrivalsTiles() {
		local result = [];
		for(local i=0; i<platformNum; i++) {
			result.push([At(i,0),At(i,1)]);
		}
		return result;
	}
	
	function GetDeparturesTiles() {
		local result = [];
		for(local i=0; i<platformNum; i++) {
			result.push([At(i,platformLength+2),At(i,platformLength+1)]);
		}
		return result;
	}
	/*
	function GetDeparturesTiles() {
		local result = [];
		for(local i=0; i<platformNum; i++) {
			result.push([At(i,7),At(i,6)]);
		}
		result.push([At(-1,6),At(0,6)]);
		result.push([At(platformNum,6),At(platformNum-1,6)]);
		return result;
	}*/
	
	function At(x,y) {
		local result = HgStation.At(platformNum-1-x,(platformLength+2)-y); //向きが逆だったので補正
		if(result == null) {
			HgLog.Warning("null platformTile:"+HgTile(platformTile)+" d:"+stationDirection);
		}
		return result;
	}
	
	
}

class TerminalStation extends DestRailStation {

	function GetTypeName() {
		return "TerminalStation";
	}
	
	
	function GetArrivalsTiles() {
		local x = platformNum / 2;
		return [[At(x,-1),At(x,0)]];
	}
	
	function GetDeparturesTiles() {
		return [[At(platformNum+1,platformLength+2),At(platformNum,platformLength+2)]];
	}
	
	function GetRails() {
		local result = [];
		
		if(platformNum==2) {
			result.push([[0,1],[0,0],[1,0]]);
			result.push([[platformNum-1,-1],[platformNum-1,0],[platformNum-1,1]]);
			result.push([[platformNum-2,0],[platformNum-1,0],[platformNum-1,-1]]);
		} else if(platformNum >= 3) {
			result.push([[0,-1],[0,0],[0,1]]);
			result.push([[0,-1],[0,0],[1,0]]);
			result.push([[0,1],[0,0],[1,0]]);
			for(local x=1; x<platformNum-1; x++) {
				result.push([[x-1,0],[x,0],[x,1]]);
				result.push([[x,1],[x,0],[x+1,0]]);
				result.push([[x+1,0],[x,0],[x,-1]]);
				result.push([[x,-1],[x,0],[x-1,0]]);
				result.push([[x-1,0],[x,0],[x+1,0]]);
				result.push([[x,-1],[x,0],[x,1]]);
			}
			result.push([[platformNum-2,0],[platformNum-1,0],[platformNum-1,-1]]);
			result.push([[platformNum-2,0],[platformNum-1,0],[platformNum-1,1]]);
			result.push([[platformNum-1,-1],[platformNum-1,0],[platformNum-1,1]]);
		}

		local y = platformLength+1;
		for(local x=0; x<platformNum; x++) {
			result.push([[x,y-1],[x,y],[x,y+1]]);
			result.push([[x,y],[x,y+1],[x+1,y+1]]);
			if(x!=0) {
				result.push([[x-1,y+1],[x,y+1],[x+1,y+1]]);
			}
		}
		result.push([[platformNum-1,y+1],[platformNum,y+1],[platformNum+1,y+1]]);
		
		return result;
	}
	
	function GetIgnoreTiles() {
		local result = [];
		local arrivalX = platformNum / 2;
		for(local x=0; x<platformNum; x++) {
			if(x != arrivalX) {
				result.push(At(x,-1));
			}
		}
		for(local y=-1; y<=platformLength+1; y++) {
			result.push(At(platformNum,y));
		}
		return result;
	}
	
	function GetMustBuildableAndFlatTiles() {
		for(local x=0; x<platformNum; x++) {
			for(local y=-1; y<platformLength+3; y++) {
				yield [x,y];
			}
		}
		yield [platformNum,platformLength+2];
		yield [platformNum+1,platformLength+2];
		yield [platformNum / 2,-2];
		return null;
	}
	
	function GetHopeBuildableAndFlatTiles() {
		local result = [];
		for(local x=platformNum; x<platformNum+2; x++) {
			for(local y=-2; y<platformLength+2; y++) {
				result.push([x,y]);
			}
		}
		result.push([platformNum-1,-2]);
		result.push([platformNum-1,-3]);
		return result;
	}
	
	function Build(levelTiles=true, isTestMode=true) {
		local tilesGen = GetMustBuildableAndFlatTiles();
		local tiles = [];
		local xy;
		while((xy = resume tilesGen) != null) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
			tiles.push(xy);
		}
		if(levelTiles) {
			local tileList = AIList();
			local d1 = HgTile.XY(1,0).tile;
			local d2 = HgTile.XY(0,1).tile;
			local d3 = HgTile.XY(1,1).tile;
			foreach(xy in tiles) {
				local tile = At(xy[0],xy[1]);
				tileList.AddItem(tile,0);
				tileList.AddItem(tile + d1,0);
				tileList.AddItem(tile + d2,0);
				tileList.AddItem(tile + d3,0);
			}
			if(!TileListUtil.LevelAverage(tileList, GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
			if(isTestMode) {
				if(!BuildPlatform(isTestMode) && AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
					return false;
				}
				return true;
			}
		}
		
		
		if(!BuildPlatform(isTestMode)) {
			HgLog.Warning("BuildPlatform failed."+AIError.GetLastErrorString());
			return false;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("BuildRail Failed."+AIError.GetLastErrorString());
				return false;
			}
		}
		
		BuildSignal();
		
		return true;
	}
	
	function Remove() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " "+AIError.GetLastErrorString());
			result = false;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+HgTile(At(rail[1][0],rail[1][1]))+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		RemoveDepots();
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
		result.extend(depots);
		return result;
	}
	
	function GetBuildableScore() {
		local result = 0;
		foreach(xy in GetHopeBuildableAndFlatTiles()) {
			if(AITile.IsBuildable(At(xy[0],xy[1]))) {
				result ++;
				if(IsFlat(At(xy[0],xy[1]))) {
					result ++;
				}
			}
		}
		return result;
	}
	
}

class SrcRailStation extends RailStation {

	constructor(platformTile, platformLength, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		platformNum = 2;
		this.platformLength = platformLength;

		if(stationDirection == HgStation.STATION_SE) {
			originTile =  MoveTile(platformTile,-1,-1);
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile =  MoveTile(platformTile,-2,-platformLength);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile =  MoveTile(platformTile,-1,-platformLength);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile =  MoveTile(platformTile,-2,-1);
		}
	}
	
	function GetTypeName() {
		return "SrcRailStation";
	}
	function Build(levelTiles=false, isTestMode=true) {
		local tilesGen = GetMustBuildableAndFlatTiles();
		local tiles = [];
		local xy;
		while((xy = resume tilesGen) != null) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
			tiles.push(At(xy[0],xy[1]));
		}
		if(levelTiles) {
			if(!TileListUtil.LevelAverageTiles(tiles, GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
			if(isTestMode) {
				if(!BuildPlatform(isTestMode) && AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
					return false;
				}
				return true;
			}
			
		}

		if(!BuildPlatform(isTestMode)) {
			return false;
		}
		foreach(depot in GetDepots()) {
			if(!AIRail.BuildRailDepot(At(depot[0][0],depot[0][1]),At(depot[1][0],depot[1][1]))) {
				if(!isTestMode) {
					HgLog.Warning("AIRail.BuildRailDepot Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				if(!isTestMode) {
					HgLog.Warning("AIRail.BuildRail Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}			
		
			
		BuildSignal(); //テストモードでは必ず失敗する
		return true;
	}
	
	function BuildAfter() {
	}
	
	function Remove() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " " + AIError.GetLastErrorString());
			result = false;
		}
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+At(rail[1][0],rail[1][1])+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		foreach(depot in GetDepots()) {
			if(!AITile.DemolishTile(At(depot[0][0],depot[0][1]))) {
				HgLog.Warning("DemolishTile failed."+HgTile(depot)+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
		foreach(depot in GetDepots()) {
			result.push(At(depot[0][0],depot[0][1]));
		}
		return result;
	}
	
	
	function BuildSignal() {
		if(!AIRail.BuildSignal(At(2,0),At(2,1),AIRail.SIGNALTYPE_PBS_ONEWAY )) {
			return false;
		}
		if(!AIRail.BuildSignal(At(0,platformLength),At(0,platformLength-1),AIRail.SIGNALTYPE_PBS_ONEWAY )) {
			return false;
		}
		
		return true;
	}
	
	function RemoveSignal() {
		AIRail.RemoveSignal(At(2,0),At(2,1));
		AIRail.RemoveSignal(At(0,platformLength),At(0,platformLength-1));
	}
	
	function GetBuildableScore() {
		// TODO向きの考慮もここで行う
		local result = 0;
		for(local i=-1; i<=3; i++) {
			for(local j=platformLength+3; j<=platformLength+5;j++) {
				local xy = At(i,j);
				if(HogeAI.IsBuildable(xy)) {
					result ++;
					if(IsFlat(xy)) {
						result ++;
					}
				}
			}
		}
		return result;
	}
	
	function GetMustBuildableAndFlatTiles() {
		for(local x=0; x<3; x++) {
			for(local y=0; y<=platformLength+3; y++) {
				yield [x,y];
			}
		}
		yield [2,platformLength+3];
		yield [3,platformLength+2];
		return null;
	}
	
	
	
	function GetArrivalsTiles() {
		return [[At(2,platformLength+3),At(2,platformLength+2)]];
	}
	
	function GetDeparturesTiles() {
		return [[At(0,platformLength+2),At(0,platformLength+1)]];
	}
	
	function GetRails() {
		local result = [];
		result.push([[0,1],[0,0],[1,0]]);
		result.push([[0,0],[1,0],[2,0]]);
		result.push([[1,0],[2,0],[2,1]]);
		for(local i=1; i<platformLength+2; i++) {
			result.push([[0,i-1],[0,i],[0,i+1]]);
		}
		
		local a = [];
		a.push([[2,0],[2,1],[2,2]]);
		a.push([[1,1],[2,1],[2,2]]);
		a.push([[2,1],[2,2],[1,2]]);
		a.push([[2,1],[2,2],[3,2]]);
		a.push([[2,3],[2,2],[1,2]]);
		a.push([[2,3],[2,2],[3,2]]);
		a.push([[1,0],[1,1],[2,1]]);
		a.push([[1,0],[1,1],[0,1]]);
		a.push([[0,1],[1,1],[2,1]]);
		a.push([[1,1],[0,1],[0,2]]);
		a.push([[1,1],[0,1],[0,0]]);
		/*
		a.push([[0,4],[0,5],[-1,5]]);
		a.push([[1,5],[0,5],[-1,5]]);
		a.push([[0,6],[0,5],[-1,5]]);*/
		foreach(r in a) {
			result.push([
				[r[0][0],r[0][1]+platformLength],
				[r[1][0],r[1][1]+platformLength],
				[r[2][0],r[2][1]+platformLength]]);
		}
		return result;
	}
	
	/*
	function GetArrivalTile() {
		return At(2,7);
	}
	
	function GetStationArrivalTile() {
		return At(2,6);
	}

	function GetDepartureTile() {
		return At(0,6);
	}

	function GetStationDepartureTile() {
		return At(0,5);
	}*/
	function GetDepots() {
		return [
			[[1,platformLength+2],[2,platformLength+2]],
			[[3,platformLength+2],[2,platformLength+2]]];
//			[[-1,platformLength+1],[0,platformLength+1]]];
	}
	
	
	function GetDepotTile() {
		return At(1,platformLength+2);
	}
	
	function GetServiceDepotTile() {
		return At(3,platformLength+2);
	}
	
	function At(x,y) {
		return HgStation.At(-x+3,y); //左右反転
	}
}



class RealSrcRailStation extends RailStation {

	constructor(platformTile, platformLength, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		platformNum = 3;
		this.platformLength = platformLength;

		if(stationDirection == HgStation.STATION_SE) {
			originTile = MoveTile(platformTile, platformNum - 3, 0); //駅の座標系でplatformをどう動かしたら原点に来るか
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile = MoveTile(platformTile, -2, -platformLength+1);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile = MoveTile(platformTile, platformNum - 3, -platformLength+1);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile = MoveTile(platformTile, -2, 0);
		}
	}
	
	function GetTypeName() {
		return "RealSrcRailStation";
	}
	function Build(levelTiles=false, isTestMode=true) {
		local tilesGen = GetMustBuildableTiles();
		local xy;
		while((xy = resume tilesGen) != null) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
		}
		if(levelTiles) {
			local preAverage = null;
			foreach(tiles in GetMustFlatTiles()) {
				local tileList = GetTileListForLevelTiles(tiles);
				local average = TileListUtil.CalculateAverageLevel(tileList);
				if(preAverage != null && abs(preAverage - average) >= 2) {
					if(!isTestMode) {
						HgLog.Warning("LevelTiles Failed. Average levels too far apart");
					}
					return false;
				}
				preAverage = average;
				
				if(!TileListUtil.LevelAverage(tileList, GetPlatformRailTrack(), isTestMode, average)) {
					if(!isTestMode) {
						HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
					}
					return false;
				}
			}
		}
		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode || AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				return false;
			}
		}
		foreach(depot in GetDepots()) {
			if(!AIRail.BuildRailDepot(At(depot[0][0],depot[0][1]),At(depot[1][0],depot[1][1]))) {
				if(!isTestMode || AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
					if(!isTestMode) {
						HgLog.Warning("AIRail.BuildRailDepot Failed "+AIError.GetLastErrorString());
					}
					return false;
				}
			}
		}

		local bridge_list = AIBridgeList_Length(4);
		bridge_list.Valuate(AIBridge.GetMaxSpeed);
		bridge_list.Sort(AIList.SORT_BY_VALUE, false);
		if(!AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), At(1,platformLength+3), At(1,platformLength+6))) {
			if(!isTestMode || AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				if(!isTestMode) {
					HgLog.Warning("BuildBridge failed."+AIError.GetLastErrorString());
				}
				return false;
			}
		}

		if(isTestMode) {
			return true;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				if(!isTestMode) {
					HgLog.Warning("AIRail.BuildRail Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}			
		
			
		BuildSignal();
		return true;
	}
	
	function BuildAfter() {
	}
	
	function Remove() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " " + AIError.GetLastErrorString());
			result = false;
		}
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+At(rail[1][0],rail[1][1])+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		foreach(depot in GetDepots()) {
			if(!AITile.DemolishTile(At(depot[0][0],depot[0][1]))) {
				HgLog.Warning("DemolishTile failed."+HgTile(depot)+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		AITile.DemolishTile(At(1,platformLength+3)); //bridge
		
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
		foreach(depot in GetDepots()) {
			result.push(At(depot[0][0],depot[0][1]));
		}
		return result;
	}
	
	
	function BuildSignal() {
		for(local i=0; i<3; i++) {
			if(!AIRail.BuildSignal(At(i,platformLength),At(i,platformLength-1),AIRail.SIGNALTYPE_PBS )) {
				return false;
			}
		}
		if(!AIRail.BuildSignal(At(1,platformLength+2),At(1,platformLength+3),AIRail.SIGNALTYPE_PBS )) {
			return false;
		}
		return true;
	}
	
	function RemoveSignal() {
		for(local i=0; i<3; i++) {
			AIRail.RemoveSignal(At(i,platformLength),At(i,platformLength-1));
		}
		AIRail.RemoveSignal(At(1,platformLength+2),At(1,platformLength+3));
	}
	
	function GetBuildableScore() {
		// TODO向きの考慮もここで行う
		local result = 0;
		for(local i=-1; i<=3; i++) {
			for(local j=platformLength+7; j<=platformLength+8;j++) {
				local xy = At(i,j);
				if(HogeAI.IsBuildable(xy)) {
					result ++;
					if(IsFlat(xy)) {
						result ++;
					}
				}
			}
		}
		return result;
	}
	
	function GetMustBuildableTiles() {
		for(local x=0; x<3; x++) {
			for(local y=0; y<=platformLength+6; y++) {
				yield [x,y];
			}
		}
		yield [1,platformLength+7];
		return null;
	}
	
	function GetMustFlatTiles() {
		local result = [];
		local a = [];
		for(local x=0; x<3; x++) {
			for(local y=0; y<platformLength; y++) {
				a.push([x,y]);
			}
		}
		result.push(a);
		
		a = [];
		for(local x=0; x<3; x++) {
			for(local y=platformLength+1; y<=platformLength+6; y++) {
				a.push([x,y]);
			}
		}
		a.push([1,platformLength+7]);
		a.push([2,platformLength+7]);
		result.push(a);
		return result;
	}
	
	
	function GetArrivalsTiles() {
		return [[At(1,platformLength+7),At(1,platformLength+6)]];
	}
	
	function GetDeparturesTiles() {
		return [[At(2,platformLength+6),At(2,platformLength+5)]];
	}
	
	function GetRails() {
		local result = [];
		local a = [];
		
		for(local i=0 /*3-platformLength*/; i<6; i++) {
			a.push([[0,-1+i],[0,i],[0,1+i]]);
		}
		for(local i=0; i<3; i++) {
			a.push([[1,-1+i],[1,i],[1,1+i]]);
		}
		for(local i=0; i<6; i++) {
			a.push([[2,-1+i],[2,i],[2,1+i]]);
		}
		
		a.push([[1,0],[1,1],[0,1]]);
		a.push([[1,1],[0,1],[0,2]]);

		a.push([[0,0],[0,1],[1,1]]);
		a.push([[0,1],[1,1],[1,2]]);

		a.push([[2,0],[2,1],[1,1]]);
		a.push([[2,1],[1,1],[1,2]]);

		
		a.push([[0,3],[0,4],[1,4]]);
		a.push([[0,4],[1,4],[1,5]]);
		a.push([[1,4],[1,5],[2,5]]);
		a.push([[1,5],[2,5],[2,6]]);

		a.push([[0,6],[0,5],[1,5]]);
		a.push([[0,5],[1,5],[1,4]]);
		a.push([[1,5],[1,4],[2,4]]);
		a.push([[1,4],[2,4],[2,3]]);

		a.push([[0,5],[1,5],[2,5]]);

		foreach(r in a) {
			result.push([
				[r[0][0],r[0][1]+platformLength],
				[r[1][0],r[1][1]+platformLength],
				[r[2][0],r[2][1]+platformLength]]);
		}
		return result;
	}
	
	
	function GetDepots() {
		return [
			[[0,platformLength+6],[0,platformLength+5]]
			/*,[[0,2],[0,3]]*/];
	}
	
	
	function GetDepotTile() {
		return At(0,platformLength+6);
	}
	
	function GetServiceDepotTile() {
		return At(0,platformLength+6);
	}
	
}



class SimpleRailStation extends RailStation {
	useDepot = null;

	constructor(platformTile, platformLength, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		platformNum = 2;
		this.platformLength = platformLength;

		if(stationDirection == HgStation.STATION_SE) {
			originTile = MoveTile(platformTile, 0, 0); //駅の座標系でplatformをどう動かしたら原点に来るか
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile = MoveTile(platformTile, 1-platformNum, -platformLength+1);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile = MoveTile(platformTile,0, -platformLength+1);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile = MoveTile(platformTile, 1-platformNum, 0);
		}
	}
	
	function GetTypeName() {
		return "SimpleRailStation";
	}
	function Build(levelTiles=false, isTestMode=true) {
		local tiles = [];
		local tilesGen = GetMustBuildableTiles();
		local xy;
		while((xy = resume tilesGen) != null) {
			if(!HogeAI.IsBuildable(At(xy[0],xy[1]))) {
				if(!isTestMode) {
					HgLog.Warning("not IsBuildable "+HgTile(At(xy[0],xy[1])));
				}
				return false;
			}
			tiles.push(xy);
		}
		if(levelTiles) {
			if(!TileListUtil.LevelAverage(GetTileListForLevelTiles(tiles), GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}
		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode || AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				return false;
			}
		}
		foreach(depot in GetDepots()) {
			if(!AIRail.BuildRailDepot(At(depot[0][0],depot[0][1]),At(depot[1][0],depot[1][1]))) {
				if(!isTestMode || AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
					if(!isTestMode) {
						HgLog.Warning("AIRail.BuildRailDepot Failed "+AIError.GetLastErrorString());
					}
					return false;
				}
			}
		}

		if(isTestMode) {
			return true;
		}
		
		foreach(rail in GetRails()) {
			if(!AIRail.BuildRail(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				if(!isTestMode) {
					HgLog.Warning("AIRail.BuildRail Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}			
		
		return true;
	}
	
	function BuildAfter() {
	}
	
	function Remove() {
		local result = true;
		
		local r = GetPlatformRectangle();
		if(!RemoveStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " " + AIError.GetLastErrorString());
			result = false;
		}
		foreach(rail in GetRails()) {
			if(!AIRail.RemoveRail(
					At(rail[0][0],rail[0][1]),
					At(rail[1][0],rail[1][1]),
					At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("RemoveRail failed. "+At(rail[1][0],rail[1][1])+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		foreach(depot in GetDepots()) {
			if(!AITile.DemolishTile(At(depot[0][0],depot[0][1]))) {
				HgLog.Warning("DemolishTile failed."+HgTile(depot)+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		
		RemoveWorld();
		return result;
	}
	
	function GetTiles() {
		local result = [];
		
		local r = GetPlatformRectangle();
		result.extend(HgArray.AIListKey(r.GetTileList()).array);
		foreach(rail in GetRails()) {
			result.push(At(rail[1][0],rail[1][1]));
		}
		foreach(depot in GetDepots()) {
			result.push(At(depot[0][0],depot[0][1]));
		}
		return result;
	}
	
		
	function GetBuildableScore() {
		local result = 0;
		for(local i=-1; i<=2; i++) {
			for(local j=platformLength+2; j<=platformLength+3;j++) {
				local xy = At(i,j);
				if(HogeAI.IsBuildable(xy)) {
					result ++;
					if(IsFlat(xy)) {
						result ++;
					}
				}
			}
		}
		return result;
	}
	
	function GetMustBuildableTiles() {
		for(local x=0; x<2; x++) {
			for(local y=0; y<=platformLength+2; y++) {
				yield [x,y];
			}
		}
		if(useDepot) {
			yield [-1,platformLength];
		}
		return null;
	}
	
	
	
	function GetArrivalsTiles() {
		return [[At(0,platformLength+1),At(0,platformLength+0)]];
	}
	
	function GetDeparturesTiles() {
		return [[At(1,platformLength+1),At(1,platformLength+0)]];
	}
	
	function GetRails() {
		local result = [];
		local a = [];
		
		a.push([[0,-1],[0,0],[0,1]]);
		a.push([[1,-1],[1,0],[1,1]]);

		a.push([[0,-1],[0,0],[1,0]]);
		a.push([[1,-1],[1,0],[0,0]]);

		a.push([[0,1],[0,0],[1,0]]);
		a.push([[1,1],[1,0],[0,0]]);
		
		if(useDepot) {
			a.push([[0,-1],[0,0],[-1,0]]);
			a.push([[0,1],[0,0],[-1,0]]);
			a.push([[-1,0],[0,0],[1,0]]);
		}
		foreach(r in a) {
			result.push([
				[r[0][0],r[0][1]+platformLength],
				[r[1][0],r[1][1]+platformLength],
				[r[2][0],r[2][1]+platformLength]]);
		}
		return result;
	}
	
	
	function GetDepots() {
		if(useDepot) {
			return [
				[[-1,platformLength],[0,platformLength]]
			];
		} else {
			return [];
		}
	}
	
	
	function GetDepotTile() {
		return At(-1,platformLength);
	}
	
	function GetServiceDepotTile() {
		return GetDepotTile();
	}
	
}