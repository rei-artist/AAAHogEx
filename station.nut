
class StationGroup {
	static idCounter = IdCounter();
	
	id = null;
	hgStations = null;
	isVirtual = null;
	
	coasts = null;
	coverageTileList = null;
	coverageRectangles = null;
	cargoProducingPlaces = null;
	
	acceptingCargoCache = null;
	producingCargoCache = null;
	
	constructor() {
		id = idCounter.Get();
		hgStations = [];
		isVirtual = false;
		cargoProducingPlaces = ExpirationTable(3*365);
		acceptingCargoCache = ExpirationTable(7);
		producingCargoCache = ExpirationTable(7);
	}

	function GetGId() {
		return "StationGroup:"+id;
	}
	
	function Save() {
		return {
			name="StationGroup"
			id = id
		};
	}

	function AddHgStation(hgStation) {
		hgStations.push(hgStation);
		coverageTileList = null;
		coverageRectangles = null;
		cargoProducingPlaces.clear();
	}
	
	function RemoveHgStation(hgStation) {
		hgStations = HgArray(hgStations).Remove(hgStation).array;
		coverageTileList = null;
		coverageRectangles = null;
		cargoProducingPlaces.clear();
		return;
	}
	
	function GetRoutesUsingDest() {
		return GetUsingRoutesAsDest();
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

	function GetRoutesUsingSource() {
		return GetUsingRoutesAsSource();
	}
	
	function GetUsingRoutesAsSource() {
		local result = [];
		foreach(route in GetUsingRoutes()) {
			if(route.srcHgStation.stationGroup == this) {
				result.push(route);
			}
			if(route.IsBiDirectional()) {
				if(route.destHgStation.stationGroup == this) {
					result.push(route);
				}
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
		if(hgStations.len() == 0) {
			return null;
		}
		return hgStations[0].platformTile;
	}

	function GetName() {
		if(hgStations.len() == 0) {
			return "Removed StationGroup";
		}
		return hgStations[0].GetName();
	}
	
	function GetAIStation() {
		if(hgStations.len() == 0) {
			return null;
		}
		return hgStations[0].stationId;
	}
	
	function HasCargoRating(cargo) {
		return AIStation.HasCargoRating (hgStations[0].stationId, cargo);
	}

	function GetStationCandidatesInSpread(stationFactory,checkedTile=null) {
		if( stationFactory.GetVehicleType() == AIVehicle.VT_ROAD ) {
			local tileList = AITileList_StationType( GetAIStation(), stationFactory.GetStationType());
			if(tileList.Count() >= 4) {
				return []; // 美的観点から同一道路ステーションは4つまで
			}
		}
	
		local maxStationSpread = HogeAI.Get().maxStationSpread;
		local maxRadius = min(maxStationSpread, max(stationFactory.GetPlatformNum(),stationFactory.GetPlatformLength()) + 12);
		local rectangle = GetBuildablePlatformRectangle(maxStationSpread - stationFactory.GetSpreadMargin(), maxRadius);
		//HgLog.Info("StationGroup.GetStationCandidatesInSpread rectangle:"+rectangle);
		local result = null;
		if(HogeAI.Get().IsDistantJoinStations() == false) {
			result = [];
			foreach(s in stationFactory.CreateOnTilesAllDirection(GetAroundTileList())) {
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
	
	function GetAroundTileList() {
		local result = AITileList();
		foreach(station in hgStations) {
			result.AddList(station.GetPlatformRectangle().GetAroundTileList());
		}
		return result;
	}
	
	function GetFutureExpectedProduction( cargo, vehicleType ) {
		return GetExpectedProduction( cargo, vehicleType );
	}


	function GetLastMonthProduction( cargo )  {
		local result = 0;
		foreach(place in GetProducingHgIndustries(cargo)) {
			result += place.GetLastMonthProduction(cargo, vehicleType, isMine);
		}
		local townCargo = GetTownCargo(cargo);
		if(townCargo != null) {
			result += townCargo.GetLastMonthProduction(cargo,vehicleType,isMine);
		}

		foreach(transferRoute in GetUsingRoutesAsDest()) {
			if(transferRoute.IsTownTransferRoute()) { // TownCargo.GetExpectedProductionに含まれる
				continue;
			}
			//HgLog.Info("GetUsingRoutesAsDest:"+route+" "+this+" "+callers.rawin(route)+" "+route.HasCargo(cargo));
			if(!callers.rawin(transferRoute) && transferRoute.IsTransfer() && transferRoute.srcHgStation.stationGroup != this) {
				result += transferRoute.GetDelivableProduction(cargo, callers);
			}
		}
		//HgLog.Info("StationGroup.GetExpectedProduction "+result+" "+this);
		return result;
	}

	function GetCurrentExpectedProduction( cargo, vehicleType, isMine = false, callers = null )  {
		return GetExpectedProduction( cargo, vehicleType, isMine, callers );
	}
	
	function GetExpectedProduction( cargo, vehicleType, isMine = false, callers = null)  {
		local result = 0;
		foreach(place in GetProducingHgIndustries(cargo)) {
			local prod = place.GetCurrentExpectedProduction(cargo, vehicleType, isMine);
			result += prod;
			//HgLog.Info("GetExpectedProduction place:"+place+" prod:"+prod);
		}
		local townCargo = GetTownCargo(cargo);
		if(townCargo != null) {
			result += townCargo.GetCurrentExpectedProduction(cargo,vehicleType,isMine);
		}

		foreach(transferRoute in GetUsingRoutesAsDest()) {
			if(transferRoute.IsTownTransferRoute()) { // TownCargo.GetExpectedProductionに含まれる
				continue;
			}
			//HgLog.Info("GetUsingRoutesAsDest:"+route+" "+this+" "+callers.rawin(route)+" "+route.HasCargo(cargo));
			if(callers == null) {
				callers = {};
			}
			if(!callers.rawin(transferRoute) && transferRoute.IsTransfer() && transferRoute.srcHgStation.stationGroup != this) {
				result += transferRoute.GetDelivableProduction(cargo, callers);
			}
		}
		local usings = max(1, GetUsingRoutesAsSource().len() + (!isMine ? 1 : 0));
		return result / usings;
	}
	
	function GetExpectedProductionInfos( cargo, vehicleType, isMine = false, callers = null ) {
		// 使われてない？ n対nの輸送路評価用
		local result = {}
		local location = GetLocation();
		foreach(place in GetProducingHgIndustries(cargo)) {
			result.push({
				location = location
				cruiseDays = 0
				production = place.GetCurrentExpectedProduction(cargo, vehicleType, isMine)
			});
		}
		local townCargo = GetTownCargo(cargo);
		if(townCargo != null) {
			result.push({
				location = location
				cruiseDays = 0
				production = townCargo.GetCurrentExpectedProduction(cargo,vehicleType,isMine)
			});
		}
		foreach(transferRoute in GetUsingRoutesAsDest()) {
			if(transferRoute.IsTownTransferRoute()) { // TownCargo.GetExpectedProductionに含まれる
				continue;
			}
			
			//HgLog.Info("GetUsingRoutesAsDest:"+route+" "+this+" "+callers.rawin(route)+" "+route.HasCargo(cargo));
			if(callers == null) {
				callers = {};
			}
			if(!callers.rawin(transferRoute) && transferRoute.IsTransfer() && transferRoute.srcHgStation.stationGroup != this) {
				result.extend( transferRoute.GetDelivableProductionInfos(cargo, callers) );
			}
		}
		local usings = max(1, GetUsingRoutesAsSource().len() + (!isMine ? 1 : 0));
		foreach( productionInfo in result ) {
			productionInfo.production /= usings;
		}
		return result;
	}

	function GetTownCargo(cargo) {
		if(!CargoUtils.IsPaxOrMail(cargo)) {
			return null;
		}
		foreach(station in hgStations) {
			if(station.place != null && station.place instanceof TownCargo) {
				return TownCargo(station.place.town, cargo, true);
			}
		}
		return null;
	}
	
	function IsCargoTransferToHere(cargo) {
		foreach(transferRoute in GetUsingRoutesAsDest()) {
			if(transferRoute.IsTransfer() && transferRoute.HasCargo(cargo)) {
				//HgLog.Info("IsCargoTransferToHere true "+AICargo.GetName(cargo)+" "+AIStation.GetName(GetAIStation()));
				return true;
			}
		}
		//HgLog.Info("IsCargoTransferToHere false "+AICargo.GetName(cargo)+" "+AIStation.GetName(GetAIStation()));
		return false;
	}
	
	function IsCargoDeliverFromHere(cargo) {
		foreach(transferRoute in GetUsingRoutesAsSource()) {
			if(transferRoute.HasCargo(cargo)) {
				return true;
			}
		}
		return false;
	}

	function GetCoasts(cargo=null) {
		if(coasts != null) {
			return coasts == false ? null : coasts;
		}
		local tileList;
		if(HogeAI.Get().IsDistantJoinStations()) {
			tileList = GetBuildablePlatformRectangle(HogeAI.Get().maxStationSpread - 1).GetTileList();
		} else {
			tileList = HgArray(GetAroundTiles()).GetAIList();
		}
		tileList.Valuate(AITile.IsCoastTile);
		tileList.KeepValue(1);
		if(tileList.Count() >= 1) {
			coasts = Coasts.GetCoasts( tileList.Begin() );
		}
		if(coasts == null) {
			coasts = false;
			return null;
		}
		return coasts;
	}
	
	function GetBuildablePlatformRectangle(stationSpread = null, maxRadius = null) {
		if(stationSpread == null) {
			stationSpread = HogeAI.Get().maxStationSpread;
		}
		local r1 = null;
		foreach(hgStation in hgStations) {
			local r2 = hgStation.GetPlatformRectangle();
			if(r1 == null) {
				r1 = r2;
			} else {
				r1 = r1.Include(r2);
			}
		}			
		local dx = stationSpread - r1.Width();
		local dy = stationSpread - r1.Height();
		if(maxRadius != null) {
			dx = min(maxRadius, dx);
			dy = min(maxRadius, dy);
		}
		local lefttop = HgTile.InMapXY(r1.lefttop.X()-dx, r1.lefttop.Y()-dy);
		local rightbottom = HgTile.InMapXY(r1.rightbottom.X()+dx, r1.rightbottom.Y()+dy);
		if(lefttop.X() > rightbottom.X()) {
			HgLog.Error("GetBuildablePlatformRectangle lefttop.X() > rightbottom.X():"+lefttop+" "+rightbottom+"r1:"+r1);
			return r1;
		}
		if(lefttop.Y() > rightbottom.Y()) {
			HgLog.Error("GetBuildablePlatformRectangle lefttop.Y() > rightbottom.Y():"+lefttop+" "+rightbottom+"r1:"+r1);
			return r1;
		}
		//HgLog.Warning("GetBuildablePlatformRectangle "+lefttop+" "+rightbottom+" r1:"+r1+" dx:"+dx+" dy:"+dy);
		return Rectangle(lefttop, rightbottom);
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
		if(acceptingCargoCache.rawin(cargo)) {
			return acceptingCargoCache.rawget(cargo);
		}
		local result = _IsAcceptingCargo(cargo);
		acceptingCargoCache.rawset(cargo,result);
		return result;
	}
	
	function _IsAcceptingCargo(cargo) {
		return IsAcceptingCargoHere(cargo) || IsCargoDeliverFromHere(cargo);
	}
	
	function IsAcceptingCargoHere(cargo) {
		if(hgStations.len()==1 && hgStations[0]instanceof PlaceStation) {
			return hgStations[0].IsAcceptingCargo(cargo);
		}
		local value = 0;
		foreach(r in GetCoverageRectangles()) {
			value += AITile.GetCargoAcceptance(r.lefttop.tile, cargo, r.Width(), r.Height(), 0);
			if(value >= 8) {
				return true;
			}
		}
		return false;
	}
	
	function GetAccepters(cargo) {
		local value = 0;
		foreach(r in GetCoverageRectangles()) {
			value += AITile.GetCargoAcceptance(r.lefttop.tile, cargo, r.Width(), r.Height(), 0);
		}
		return value;
	}
	
	function IsProducingCargo(cargo) {
		if(producingCargoCache.rawin(cargo)) {
			return producingCargoCache.rawget(cargo);
		}
		local result = _IsProducingCargo(cargo);
		producingCargoCache.rawset(cargo,result);
		return result;
	}
	
	function _IsProducingCargo(cargo) {
		return IsProducingCargoHere(cargo) || IsCargoTransferToHere(cargo);
	}
	
	function IsProducingCargoHere(cargo) {

		if(hgStations.len()==1 && hgStations[0]instanceof PlaceStation) {
			return hgStations[0].IsProducingCargo(cargo);
		}
		local value = 0;
		foreach(r in GetCoverageRectangles()) {
			value += AITile.GetCargoProduction(r.lefttop.tile, cargo, r.Width(), r.Height(), 0);
			if(value >= 1) {
				return true;
			}
		}
		return false;
	}
	
	function GetProducingCargos() {
		local result = [];
		foreach(cargo,_ in AICargoList()) {
			if(IsProducingCargo(cargo)) {
				result.push(cargo);
			}
		}
		return result;
	}
	
	function GetProducers(cargo) {
		local value = 0;
		foreach(r in GetCoverageRectangles()) {
			value += AITile.GetCargoProduction(r.lefttop.tile, cargo, r.Width(), r.Height(), 0);
		}
		return value;
	}
	
	function IsAcceptingAndProducing(cargo) {
		return IsProducingCargo(cargo) && IsAcceptingCargo(cargo);
	}
	
	function GetProducingHgIndustries(cargo) {
		if(!cargoProducingPlaces.rawin(cargo)) { // 駅が作られた後に建設された施設は見つけられない。定期的にキャッシュクリアが必要
			cargoProducingPlaces.rawset(cargo, SearchHgIndustries(cargo,true));
		}
		return cargoProducingPlaces.rawget(cargo);
	}
	
	function SearchHgIndustries(cargo, isProducing) {
		local result = [];
		local industryList = AIList();
		foreach(tile,_ in GetCoverageTileList()) {
			if(isProducing) {
				if(AITile.GetCargoProduction(tile, cargo, 1, 1, 0 ) >= 1) {
					industryList.AddItem(AIIndustry.GetIndustryID(tile),0);
				}
			} else {
				if(AITile.IsAcceptingCargo(tile, cargo, 1, 1, 0 ) >= 8) { // TODO: isProducing==falseの場合、最も小さいindustryIdのみを返す
					industryList.AddItem(AIIndustry.GetIndustryID(tile),0);
				}
			}
		}
		foreach(station in hgStations) {
			if(station instanceof PlaceStation // PlaceStationはCoverageTileを持たない
					&& station.place != null 
					&& station.place instanceof HgIndustry 
					&& station.place.IsTreatCargo(cargo, isProducing)) {

				industryList.AddItem(station.place.industry,0);
			}
		}
		//HgLog.Info("SearchHgIndustries:"+industryList.Count()+" cargo:"+AICargo.GetName(cargo)+" isProducing:"+isProducing+" "+this);
		local result = [];
		foreach(industry,_ in industryList) {
			result.push(HgIndustry(industry, isProducing));
		}
		return result;
	}

	function GetCoverageRectangles() {
		if(coverageRectangles == null) {
			coverageRectangles = TileListUtils.GetRectangles( GetCoverageTileList() );
		}
		return coverageRectangles;
	}

	function GetCoverageTileList() {
		if(coverageTileList == null) {
			if(HogeAI.Get().openttdVersion >= 14) {
				coverageTileList = AITileList_StationCoverage( GetAIStation() );
				//HgLog.Info("AITileList_StationCoverage:"+coverageTileList.Count());
			} else {
				coverageTileList = AITileList();
				local stationTypes = {};
				local stationId = hgStations[0].stationId;
				foreach(station in hgStations) {
					if(station.GetStationType() != null) {
						stationTypes.rawset(station.GetStationType(),station);
					}
				} 
				foreach(stationType,station in stationTypes) {
					local radius = station.GetCoverageRadius();
					foreach(tile,_ in AITileList_StationType(stationId, stationType)) {
						Rectangle.Center(HgTile(tile), radius).AppendToTileList(coverageTileList);
					}
				}
			}
		}
		return coverageTileList;
	}
	
	function IsTownStop() {
		foreach(station in hgStations) {
			if(station.IsTownStop()) {
				return true;
			}
		}
		return false;
	}
	
	function HasAirport() {
		foreach(station in hgStations) {
			if(station instanceof AirStation) {
				return true;
			}
		}
		return false;
	}
	
	function CanBuildAirport(airportType, cargo) {
		return true; //TODO: 付近に街がある場合はノイズチェックがいる
	}
	
	
	function Remove() {
		if(GetUsingRoutes().len() != 0) {
			HgLog.Warning("StationGroup.Remove() GetUsingRoutes not zero:"+GetUsingRoutes().len());
			return;
		}
		foreach(station in hgStations) {
			station.RemoveWorld();
			station.Demolish();
		}
	}

	function _tostring() {
		return hgStations.len()>=1 ? hgStations[0].GetName() : "EmptyStationGroup";
	}
}


class StationFactory {
	
	levelTiles = null;
	nearestFor = null;
	nearestFor2 = null;
	checked = null;
	ignoreDirectionScore = null;
	ignoreDirection = null; // assume platformLength=Y, platformNum=X
	isBiDirectional = null;

	place = null;

	constructor() {
		levelTiles = true;
		ignoreDirectionScore = false;
		ignoreDirection = false;
		isBiDirectional = false;
		checked = AIList();
	}
	

	
	function CreateBest(target, cargo, toTile, useStationGroup = true) {
		if(target instanceof StationGroup) {
			return CreateBestOnStationGroup(target, cargo, toTile);
		}
		this.place = target;
	
		local testMode = AITestMode();
		local result = null;
	
		if(GetVehicleType() == AIVehicle.VT_AIR) {
			useStationGroup = false; // srcの取り合いで結局あまり良い結果にならない
		}
		if(nearestFor == null) {
			if(place instanceof TownCargo) {
				nearestFor = toTile;
			} else if(!CargoUtils.IsPaxOrMail(cargo)) {
				nearestFor = place.GetLocation();
			}
		}
		if(place.HasStation(GetVehicleType())) {
			result = PlaceStation(place.GetStationLocation(GetVehicleType()));
		}

		if(result == null && place.IsProducing() && useStationGroup) {
			result = SelectBestByStationGroup(place,cargo,toTile,true);
		}
		
		if(result == null) {
			local stations = CreateOnTilesAllDirection(place.GetCargoTileList( GetCoverageRadius() ,cargo ));
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
		local testMode = AITestMode();
		
		this.place = null;
		if(HogeAI.Get().IsDistantJoinStations() == false) {
			this.nearestFor = toTile;
		} else {
			this.nearestFor = stationGroup.hgStations[0].platformTile;
			this.nearestFor2 = toTile;
		}
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
		
		local considerAcceptance = place != null && place instanceof TownCargo;
		if(this instanceof RoadStationFactory && HogeAI.Get().IsDistantJoinStations()) {
			considerAcceptance = false;
		}

		local radius = GetCoverageRadius();
		local startDate = AIDate.GetCurrentDate();
		local stationScoreList = AIList();
		stationScoreList.Sort( AIList.SORT_BY_VALUE , false);
		foreach(stationIndex, station in hgStations) {
			if(checked.HasItem(station.platformTile)) {
				continue;
			}
			if(!station.IsBuildablePreCheck()) {
				continue;
			}
			station.cargo = cargo; // WaterStation.GetBuildableScore()で必要
			station.place = place;
			station.score = dirScore[station.stationDirection] + station.GetBuildableScore();
			if(AITile.IsSeaTile(station.platformTile)) {
				station.score -= 10;
			}
			local platformRect = station.GetPlatformRectangle();
			if(!platformRect.rightbottom.IsValid()) {
				continue;
			}
			
			if(nearestFor != null) {
				local p1 = platformRect.lefttop.tile;
				local p2 = platformRect.rightbottom.tile;
				local distance = min(AIMap.DistanceManhattan(p1, nearestFor), AIMap.DistanceManhattan(p2, nearestFor));
				if(nearestFor2 != null) {
					distance += min(4,min(AIMap.DistanceManhattan(p1, nearestFor2), AIMap.DistanceManhattan(p2, nearestFor2)));
				}
				station.score -= distance;
			}
			
			if(considerAcceptance) {
				local acceptance = AITile.GetCargoAcceptance(station.platformTile, cargo, platformRect.Width(), platformRect.Height(), radius);
				if(acceptance < 8) {
					continue;
				}
				station.score += acceptance;
			}
			stationScoreList.AddItem(stationIndex, station.score);
			if(startDate + 60  < AIDate.GetCurrentDate()) {
				HgLog.Warning("Station GetBestHgStationCosts reached limitDate1. stationPlace:"+label);
				break;
			}
			HogeAI.DoInterval();
		}
		startDate = AIDate.GetCurrentDate();
		HogeAI.DoInterval();
		HgLog.Info(this+" days:"+(AIDate.GetCurrentDate()-startDate)+" candidates:"+stationScoreList.Count()+"/"+hgStations.len()
			+" by:"+label+(considerAcceptance?" considerAcceptance":""));
		local candidates = [];
		foreach(stationIndex,score in stationScoreList) {
			local station = hgStations[stationIndex];
			//HgLog.Info("checkPlatform:"+station.GetPlatformRectangle());
			checked.AddItem(station.platformTile,0);
			if(HgStation.IsNgStationTile(station)) {
				continue;
			}
			if(station.Build(levelTiles, true)) {
				HgLog.Info("Build succeeded(TestMode) "+station+" stationPlace:"+label);
				station.levelTiles = levelTiles;
				return [[station,0]]; // この先は重いのでカット
			}
			if(startDate + 60 < AIDate.GetCurrentDate()) {
				HgLog.Warning("Station GetBestHgStationCosts reached limitDate2. stationPlace:"+label);
				break;
			}
			HogeAI.DoInterval();
		}
		return [];
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
			if(GetVehicleType() == AIVehicle.VT_AIR && stationGroup.HasAirport()) {
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
			foreach( route in stationGroup.GetUsingRoutesAsSource() ) {
				if(route instanceof TrainReturnRoute) {
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
	
	
	function CreateOnTiles(tileList,stationDirection) {
		local result = [];
		foreach(platformTile in GetPlatformTiles(tileList,stationDirection)) {
			result.push(Create(platformTile,stationDirection));
		}
		return result;
	}
	
	function CreateOnTilesAllDirection(tileList) {
		
		local result = [];
		
		if(ignoreDirection) {
			foreach(platformTile in GetPlatformTiles(tileList,HgStation.STATION_NW)) {
				result.push(Create(platformTile,HgStation.STATION_NW));
			}
		} else {
			foreach(platformTile in GetPlatformTiles(tileList,HgStation.STATION_NW)) {
				result.push(Create(platformTile,HgStation.STATION_NW));
				result.push(Create(platformTile,HgStation.STATION_SE));
			}
			foreach(platformTile in GetPlatformTiles(tileList,HgStation.STATION_NE)) {
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
			foreach(platformTile,_ in rectangle.GetIncludeRectanglesLefttopTileList(h,w)) {
				if(checkedTile==null || !checkedTile[1].HasItem(platformTile)) {
					if(checkedTile!=null) {
						checkedTile[1].AddItem(platformTile,0);
					}
					result.push(Create(platformTile,HgStation.STATION_NW));
				}
			}
		} else {
			foreach(platformTile,_ in rectangle.GetIncludeRectanglesLefttopTileList(w,h)) {
				if(checkedTile==null || !checkedTile[0].HasItem(platformTile)) {
					if(checkedTile!=null) {
						checkedTile[0].AddItem(platformTile,0);
					}
					result.push(Create(platformTile,HgStation.STATION_NE));
					result.push(Create(platformTile,HgStation.STATION_SW));
				}
			}
			foreach(platformTile,_ in rectangle.GetIncludeRectanglesLefttopTileList(h,w)) {
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
	
	
	function GetPlatformTiles(tileList,stationDirection) {
		local w = GetPlatformWidth(stationDirection);
		local h = GetPlatformHeight(stationDirection);

		local cornerIndex = AIMap.GetTileIndex(-w+1,-h+1);
		local acceptableTileList = AITileList();
		acceptableTileList.AddList(tileList);
		acceptableTileList.Valuate(AIMap.GetTileX);
		acceptableTileList.KeepBetweenValue(w,AIMap.GetMapSizeX()-w);
		acceptableTileList.Valuate(AIMap.GetTileY);
		acceptableTileList.KeepBetweenValue(h,AIMap.GetMapSizeY()-h);
		local platformTileList = AITileList();
		foreach(tile,_ in acceptableTileList) {
			platformTileList.AddRectangle(tile + cornerIndex, tile);
		}
		local result = [];
		foreach(t,_ in platformTileList) {
			if(IsBuildableRectangle(t,w,h)) {
				result.push(t);
			}
		}
		return result;
	}
	
	function IsBuildableRectangle(t,w,h) {
		return true;
	}
	
	function GetCornerDegrees(w, h) {
		return [[-w+1,-h+1],[0,-h+1],[-w+1,0],[0,0]];
	}

	function _tostring() {
		return "StationFactory["+VehicleUtils.ToString(GetVehicleType())+"]";
	}
}

class RailStationFactory extends StationFactory {
	minPlatformLength = null;
	platformLength = null;
	distance = null;
	
	constructor() {
		StationFactory.constructor();
	}

	
	function CreateBest(target, cargo, toTile, useStationGroup = true) {
		if(minPlatformLength == null) {
			minPlatformLength = 4;
		}
		if(platformLength == null) {
			platformLength = GetMaxStatoinLength(cargo);
		}
	
		for(; platformLength >= minPlatformLength; platformLength -= max(1, platformLength / 4)) {
			HgLog.Info("TrainRoute: RailStationFactory.CreateBest start "+target.GetName()+" platformLength:"+platformLength);
			local result = StationFactory.CreateBest(target, cargo, toTile, useStationGroup);
			if(result != null) {
				return result;
			}
			checked.Clear();
		}
		return null;
	}
	
	function GetMaxStatoinLength(cargo) {
		if(distance != null) {
			local settingMax = min(HogeAI.Get().maxStationSpread , AIGameSettings.GetValue("vehicle.max_train_length"));
			local result =  min( 4 + distance / 25, settingMax );
			if(HogeAI.Get().IsInfrastructureMaintenance()) {
				//result = max(4, min(7, result / 2)); マップが広いとむしろ不利になる
			}
			/*if(CargoUtils.IsPaxOrMail(cargo)) {
				result = min(10, result);
			}*/
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

	function IsBuildableRectangle(tile,w,h) {
		if(!AITile.IsBuildableRectangle(tile,w,h)) {
			return false;
		}
		local tileList = AITileList();
		tileList.AddRectangle(tile, tile + AIMap.GetTileIndex(w-1, h-1));
		tileList.Valuate(AITile.GetMaxHeight);
		tileList.Sort(AIList.SORT_BY_VALUE,false);
		local max = 0;
		foreach(t,v in tileList) {
			max = v;
			break;
		}
		tileList.Valuate(AITile.GetMinHeight);
		tileList.Sort(AIList.SORT_BY_VALUE,true);
		local min = 0;
		foreach(t,v in tileList) {
			min = v;
			break;
		}
		return max - min < 3;
	}
}

class PriorityStationFactory extends StationFactory {
	stationFactories = null;
	index = null;
	
	constructor(stationFactories) {
		StationFactory.constructor();
		this.stationFactories = stationFactories;
		this.index = 0;
	}
	
	function GetCurrent() {
		return stationFactories[index];
	}
	
	
	function GetStationType() {
		return GetCurrent().GetStationType();
	}
	
	function GetVehicleType() {
		return GetCurrent().GetVehicleType();
	}

	function GetPlatformNum() {
		return GetCurrent().GetPlatformNum();
	}
	
	function GetPlatformLength() {
		return GetCurrent().GetPlatformLength();
	}
	
	function Create(platformTile,stationDirection) {
		return GetCurrent().Create(platformTile,stationDirection);
	}
	
	function InitializeCurrentParameters() {
		local current = GetCurrent();
		current.nearestFor = nearestFor;
		current.isBiDirectional = isBiDirectional;
	}

	function CreateBest(target, cargo, toTile, useStationGroup = true) {
		for(index = 0; index < stationFactories.len(); index++ ) {
			InitializeCurrentParameters();
			local result = GetCurrent().CreateBest(target, cargo, toTile, useStationGroup);
			if(result != null) {
				return result;
			}
		}
		index = 0;
		return null;
	}
	
}

class RoadStationFactory extends StationFactory {
	cargo = null;
	isPieceStation = null;
	platformNum = null;
	
	constructor(cargo,isPieceStation = false) {
		StationFactory.constructor();
		this.cargo = cargo;
		if(isPieceStation) {
			this.ignoreDirection = true;
		}
		this.ignoreDirectionScore = true;
		this.isPieceStation = isPieceStation;
		if(!isPieceStation && !HogeAI.Get().IsDistantJoinStations()/* && CargoUtils.IsPaxOrMail(cargo)*/) {
			platformNum = 2;
		} else {
			platformNum = 1;
		}
	}

	function GetStationType() {
		return AICargo.HasCargoClass(cargo,AICargo.CC_PASSENGERS) ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_ROAD;
	}

	function GetPlatformNum() {
		return platformNum;
	}
	
	function GetPlatformLength() {
		return 1;
	}
	
	function Create(platformTile,stationDirection) {
		if(isPieceStation) {
			local result = PieceStation(platformTile);
			result.cargo = cargo;
			return result;
		} else {
			return RoadStation(platformTile,platformNum,stationDirection,GetStationType());
		}
	}

	
}

class SrcRailStationFactory extends RailStationFactory {
	useSimple = null;
	useSingle = null;
	
	constructor() {
		RailStationFactory.constructor();
		useSimple = false;
		useSingle = false;
	}

	function GetPlatformNum() {
		if(useSingle) {
			return 1;
		} else if(useSimple || HogeAI.Get().IsInfrastructureMaintenance()) {
			return 2;
		} else {
			return 3;
		}
	}
	function GetPlatformLength() {
		return platformLength;
	}
	function Create(platformTile,stationDirection) {
		if(useSimple || useSingle) {
			local result = SimpleRailStation(platformTile, GetPlatformNum(), GetPlatformLength(), stationDirection);
			result.useDepot = true;
			return result;
		} /*else if(HogeAI.Get().IsInfrastructureMaintenance()) {
			return SrcRailStation(platformTile, GetPlatformLength(), stationDirection);
		}*/ else {
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
	useSingle = null;
	platformNum = null;
	
	constructor() {
		RailStationFactory.constructor();
		this.useSimple = false;
		this.useSingle = false;
	}
	function GetPlatformNum() {
		if(platformNum != null) {
			return platformNum;
		}
		if(useSingle) {
			return 1;
		} else if(useSimple) {
			return 2;
		} else if(HogeAI.Get().IsDistantJoinStations()) {
			return 2;
		} else {
			return 2;
		}
	}
	function GetPlatformLength() {
		return platformLength;
	}
	function Create(platformTile,stationDirection) {
		if(useSimple || useSingle) {
			return SimpleRailStation(platformTile, GetPlatformNum(), GetPlatformLength(), stationDirection);
		} else {
			return SmartStation(platformTile, GetPlatformNum(), GetPlatformLength(), true, stationDirection);
		}
//		return TerminalStation(platformTile, platformNum, GetPlatformLength(), stationDirection);
	}
}


class HgStation {
	static worldInstances = {};
	static stationGroups = {};
	static savedDatas = {};
	static idCounter = IdCounter();
	static ngStationTiles = {}
	
	
	static STATION_NW = 0;
	static STATION_NE = 1;
	static STATION_SW = 2;
	static STATION_SE = 3;
	
	static function SaveStatics(data) {
		data.savedStations <- HgStation.savedDatas;
		data.ngStationTiles <- HgStation.ngStationTiles;
	}
	
	static function LoadStatics(data) {
		HgStation.stationGroups.clear();
		foreach(id,t in data.savedStations) {
			HgStation.savedDatas.rawset(id,t);
			local station;
			switch(t.name) {
				case "PieceStation":
					station = PieceStation(t.platformTile);
					break;
				case "PlaceStation":
					station = PlaceStation(t.platformTile);
					break;
				case "SmartStation":
					station = SmartStation(t.platformTile, t.platformNum, t.platformLength, t.slim, t.stationDirection);
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
					station = SimpleRailStation(t.platformTile, t.platformNum, t.platformLength, t.stationDirection);
					if(t.rawin("useDepot")) {
						station.useDepot = t.useDepot;
					}
					break;
				case "RoadStation":
					station = RoadStation(t.platformTile, t.platformNum, t.stationDirection, t.stationType);
					break;
				case "WaterStation":
					station = WaterStation(t.platformTile, t.stationDirection);
					break;
				case "CanalStation":
					station = CanalStation(t.platformTile, t.stationDirection);
					break;
				case "AirStation":
					station = AirStation(t.platformTile, t.airportType);
					break;
			}
			station.id = t.id;
			HgStation.idCounter.Skip(station.id);
			station.stationId = AIStation.GetStationID(t.platformTile);
			station.place = t.place != null ? Place.Load(t.place) : null;
			station.cargo = t.cargo;
			station.buildedDate = t.buildedDate;
			local stationGroup;
			if(!HgStation.stationGroups.rawin(t.stationGroup)) {
				stationGroup = StationGroup();
				stationGroup.id = t.stationGroup;
				StationGroup.idCounter.Skip(stationGroup.id);
				HgStation.stationGroups[stationGroup.id] <- stationGroup;
			} else {
				stationGroup = HgStation.stationGroups[t.stationGroup];
			}
			HgLog.Info("load station:"+station.GetName()+" "+station.GetTypeName()+" "+stationGroup.id+" "+(station.place != null ? station.place : ""));
			station.stationGroup = stationGroup;
			station.Load(t);
			
			stationGroup.hgStations.push(station);
			HgStation.worldInstances[station.id] <- station;
			if(station.place != null) {
				station.place.AddStation(station);
			}
			BuildedPath.AddTiles(station.GetTiles(),station);
		}
		if(data.rawin("ngStationTiles")) {
			HgTable.Extend(HgStation.ngStationTiles, data.ngStationTiles);
		}
	}

	static function SearchStation(placeOrGroup, stationType, cargo, isAccepting) {
		local result = [];
		local stations;
		local isStationGroup;
		if(placeOrGroup instanceof Place) {
			return HgStation.SearchStationByPlace(placeOrGroup,stationType,cargo,isAccepting);
		} else {
			return HgStation.SearchStationByGroup(placeOrGroup,stationType,cargo,isAccepting);
		}
	}
	
	static function SearchStationByPlace(place, stationType, cargo, isAccepting) {
		local result = [];
		local stations = {};
		foreach(s1 in place.GetStations()) {
			if(s1.stationGroup == null) {
				continue;
			}
			foreach(s2 in s1.stationGroup.hgStations) {
				stations.rawset(s2,0);
			}
		}
	
		foreach(hgStation,_ in stations) {
			if(hgStation.GetStationType() == stationType) {
				if(isAccepting) {
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
		return result;
	}
	
	
	static function SearchStationByGroup(group, stationType, cargo, isAccepting) {
		local result = [];
		foreach(hgStation in group.hgStations) {
			if(hgStation.GetStationType() == stationType) {
				result.push(hgStation);
			}
		}
		return result;
	}

	static function AddNgStationTile(station) {
		local key = station.GetLocation() + "-" + station.GetTypeName();
		HgStation.ngStationTiles.rawset(key,0);
	}

	static function IsNgStationTile(station) {
		local key = station.GetLocation() + "-" + station.GetTypeName();
		return HgStation.ngStationTiles.rawin(key);
	}

	
	id = null;
	platformTile = null;
	stationId = 0;
	stationDirection = null;
	place = null;
	cargo = null;
	platformNum = null;
	platformLength = null;
	buildedDate = null;
	stationGroup = null;
	
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

	function DoSave() {
		HgStation.savedDatas.rawset(id,Save());
	}
	
	function GetSavedDate() {
		return HgStation.savedDatas.rawget(id);
	}

	function GetId() {
		return id;
	}

	function AddWorld() {
		this.id = idCounter.Get();
		this.stationId = AIStation.GetStationID(platformTile);
		if(stationGroup == null) {
			stationGroup = StationGroup();
			HgStation.stationGroups[stationGroup.id] <- stationGroup;
			InitializeName();
		}
		
		buildedDate = AIDate.GetCurrentDate();
		stationGroup.AddHgStation(this);
		worldInstances[this.id] <- this;

		if(place != null) {
			place.AddStation(this);
		}

		BuildedPath.AddTiles(GetTiles(),this);
		
		DoSave();
	}
	
	function RemoveWorld() {
		HgLog.Info("HgStation.RemoveWorld."+this);

		if(worldInstances.rawin(this.id)) {
			worldInstances.rawdelete(this.id);
			HgStation.savedDatas.rawdelete(this.id);
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
		stationId = 0;
		
		BuildedPath.RemoveTiles(GetTiles());
	}
	

	function GetLocation() {
		return platformTile;
	}
	
	function GetStationGroup() {
		return stationGroup;
	}
	
	function GetCoverageRadius() {
		return AIStation.GetCoverageRadius(GetStationType());
	}
	
	function BuildStationSafe(joinStation, isTestMode) {
		if(isTestMode) {
			return BuildStation(joinStation, isTestMode);
		}
		return BuildUtils.WaitForMoney( function():(joinStation, isTestMode) {
			return BuildStation(joinStation, isTestMode);
		});
	}
	
	function ExistsStationGroupsMoreThanOneAround() {
		local neighborStations = {};
		foreach(tile in GetPlatformRectangle().GetAroundTiles()) {
			local station = AIStation.GetStationID(tile);
			if(AIStation.IsValidStation(station) && AICompany.IsMine(AITile.GetOwner(tile))) {
				neighborStations.rawset(station,true);
			}
		}
		if(neighborStations.len() >= 2) {
			return true; 
		}
		return false;
	}
	
	function IsJoin() {
		if(stationGroup != null && stationGroup.hgStations.len() >= 1 && !stationGroup.isVirtual) {
			return true;
		}
		return false;
	}
	
	function BuildPlatform(isTestMode, supressWarning = false) {
		//isTestMode = false;
		local joinStation = AIBaseStation.STATION_NEW
		if(IsJoin()) {
			if(!HogeAI.Get().IsDistantJoinStations()) {
				joinStation = AIStation.STATION_JOIN_ADJACENT; // distant_joint_stationsの場合、STATION_JOIN_ADJACENTを使用しないとjoinに失敗する
				if(ExistsStationGroupsMoreThanOneAround()) {
					if(!isTestMode && !supressWarning) {// IsDistantJoinStations==falseの時、複数の隣接駅がある場合にjoinできない
						HgLog.Warning("STATION_JOIN_ADJACENT Failed.neighborStations.len()>=2 "+GetPlatformRectangle());
					}
					return false; // 隣接駅が複数あると独立した駅になってしまう！
				}
			} else {
				joinStation = stationGroup.hgStations[0].stationId;
			}
		}
		
		for(local i=0;; i++) {
			if(BuildStationSafe(joinStation, isTestMode)) {
				if(!isTestMode && joinStation == AIStation.STATION_JOIN_ADJACENT 
						&& AIStation.GetStationID(platformTile) != stationGroup.hgStations[0].stationId) {
					if(!supressWarning) {
						HgLog.Warning("STATION_JOIN_ADJACENT Failed."
							+AIStation.GetStationID(platformTile)
							+"!="+stationGroup.hgStations[0].stationId+" "+GetPlatformRectangle());
					}
					return false;
				}
				/* TODO: 最新だと近い方が優先される(近いってどっから？等距離だったら？)
				if(place != null && cargo != null && place instanceof HgIndustry && place.IsAccepting()) {
					
					foreach(industry in SearchIndustries(cargo,false)) { //BUG: 本来はstationGroupで調べるべきだが、testモードでは無理かも
						if(industry < place.industry) { // 予期しないindustryが同一cargoを受け入れている。industryIdが小さい方が優先
							if(!isTestMode && !supressWarning) {
								HgLog.Warning("Unexpected accepting industry found."+AIIndustry.GetName(industry)+" "+this);
								// TODO: Demolish
							}
							return false;
						}
					}
				
				}*/
				return true;
			}
			if(i==1) {
				break;
			}
			if(!isTestMode && AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
				local towns = {};
				foreach(tile in GetPlatformRectangle().GetTiles()) {
					local town = AITile.GetTownAuthority(tile);
					if(AITown.IsValidTown(town)) {
						towns.rawset(town,true);
					}
				}
				foreach(town,_ in towns) {
					if(AITown.GetRating(town, AICompany.COMPANY_SELF) <= AITown.TOWN_RATING_VERY_POOR) {
						HogeAI.PlantTreeTown(town);
					}
				}
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
		return Rectangle(r1.lefttop, r1.rightbottom + OneTile);
	}
	
	function GetPlatformRectangle() {
		if(platformRectangle == null) {
			local lefttop = HgTile(platformTile);
			switch(GetPlatformRailTrack()) {
				case AIRail.RAILTRACK_NW_SE:
					platformRectangle = Rectangle(lefttop, lefttop + HgTile.XY(platformNum,platformLength));
					break;
				case AIRail.RAILTRACK_NE_SW:
					platformRectangle =  Rectangle(lefttop, lefttop + HgTile.XY(platformLength,platformNum));
					break;
				default:
					AIError.Log("Unknown PlatformRailTrack:"+GetPlatformRailTrack()+" (GetPlatformRectangle)");
			}
		}
		return platformRectangle;
	}
	
	
	//abstrat function GetBuildableScore()
	//abstrat function Build()
	//abstrat function GetDepotTile() 列車を作るための
	
	function IsFlat(tile) {
		return AITile.GetSlope(tile) == AITile.SLOPE_FLAT;
	}
	
	
	function BuildPieceStation(tile,supressWarning=false) {
		local pieceStation = PieceStation(tile);
		pieceStation.place = place;
		pieceStation.cargo = cargo;
		pieceStation.stationGroup = stationGroup;
		pieceStation.supressWarning = supressWarning;
		return pieceStation.BuildExec();
	}
	
	function BuildExec() {
		local needsPieceStation = false;
		local isForTownPaxMail = false;
		if(!(this instanceof PieceStation)) {
			needsPieceStation = place != null && cargo != null && place instanceof TownCargo;
			isForTownPaxMail = needsPieceStation && CargoUtils.IsPaxOrMail(cargo);
			CheckBuildTownBus(isForTownPaxMail);
		}

		if(!builded) {
			HogeAI.WaitForMoney(GetNeedMoney());
			if(!Build(levelTiles,false)) {
				return false;
			}
		}
		
		AddWorld();

		if(needsPieceStation) {
			if(HogeAI.Get().IsDistantJoinStations() && stationGroup.hgStations.len() == 1){
				local success = false;
				if(pieceStationTile != null) {
					success = BuildPieceStation(pieceStationTile);
				} else {
					local pieces = [platformTile];
					local tileList = stationGroup.GetBuildablePlatformRectangle().GetTileList();
					local coverageRadius = AIStation.GetCoverageRadius(PieceStation.GetStationTypeCargo(cargo));
					foreach(tile in place.GetTiles(coverageRadius, cargo)) {
						if(tileList.HasItem(tile) && AIRoad.IsRoadTile(tile)) {
							local close = false;
							foreach(p in pieces) {
								if(AIMap.DistanceManhattan(p,tile) <= 6) {
									close = true;
									break;
								}
							}
							if(close) {
								continue;
							}
							if(BuildPieceStation(tile,true/*supressWarning*/)) {
								pieces.push(tile);
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
		HgLog.Info("HgStation.BuildExec succeeded."+this+" accepters:"+stationGroup.GetAccepters(cargo)+" cargo:"+AICargo.GetName(cargo));

		return true;
	}
	
	// WaterStationでoverride
	function CheckBuildTownBus(isForTownPaxMail) {
		foreach(corner in GetPlatformRectangle().GetCorners()) { 
			TownBus.Check(corner.tile, null, HogeAI.Get().GetPassengerCargo(), false);
		}
		if(isForTownPaxMail) {
			foreach(cargo in HogeAI.Get().GetPaxMailCargos()) {
				TownBus.CheckTown(place.town, null, cargo, false);
			}
		}
	}
	
	function GetNeedMoney() {
		return 40000;
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
		HgLog.Error("Unknown tileDirection (GetStationDirectionFromTileIndex):"+tileDirection);
	}
	
	function PurchaseLandTile(tile) {
		if(AIObjectType.BuildObject(3,0,tile)) {
			HogeAI.Get().maybePurchasedLand.rawset(true,0);
		}
	}
	
	function PurchaseLand(tile) {
		return; // 実効性が薄いのでやらない
		if(HogeAI.Get().HasIncome(100000)) {
			PurchaseLandTile(tile);
			PurchaseLandTile(MoveTile(tile,0,1));
			PurchaseLandTile(MoveTile(tile,0,2));
			PurchaseLandTile(MoveTile(tile,1,0));
			PurchaseLandTile(MoveTile(tile,1,1));
			PurchaseLandTile(MoveTile(tile,-1,0));
			PurchaseLandTile(MoveTile(tile,-1,1));
		}
	}
	
	function GetFrontTile(tile) {
		return MoveTile(tile,0,1);
	}
	
	function GetAIStation() {
		return stationId;
	}
	
	function InitializeName() {
		if(HogeAI.Get().IsDisabledPrefixedStatoinName()) {
			if(name != null) {
				AIStation.SetName(stationId, name); // これだけはbusstopの識別で必要
			}
			return;
		}
		local s = "";
		s = id.tostring();
		s = "0000".slice(0,max(0,4-s.len()))+s;
		if(name != null) {
			SetNameSlice(s+name);
		} else if(place != null) {
			SetNameSlice(s+place.GetName());
		} else if(cargo != null) {
			local hasPlace = false;
			foreach(station in stationGroup.hgStations) {
				if(station.place != null) {
					hasPlace = true;
				}
			}
			if(!hasPlace) {
				local town = AITile.GetClosestTown(GetLocation());	
				SetNameSlice(s+AITown.GetName(town)+" "+AICargo.GetName(cargo)+" Yard");
			}
		}
	}

	function SetNameSlice(name)	{
		AIStation.SetName(stationId, StringUtils.SliceMaxLen(name,31));
	}
	
	function GetName() {
		if(!AIStation.IsValidStation(stationId)) {
			return "InvalidStation "+HgTile(platformTile);
		}
		return AIStation.GetName(stationId);
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
		return stationGroup.IsAcceptingCargo(cargo);
	/*

		local rect = GetPlatformRectangle();
		local coverageRadius = GetCoverageRadius();
		return AITile.GetCargoAcceptance(rect.lefttop.tile, cargo, rect.Width(), rect.Height(), coverageRadius ) >= 8;*/
	}
	
	
	function IsProducingCargo(cargo) {
		return stationGroup.IsProducingCargo(cargo);
	}
	
	function IsProducingCargoWithoutStationGroup(cargo)  {
		local rect = GetPlatformRectangle();
		local coverageRadius = GetCoverageRadius();
		return AITile.GetCargoProduction(rect.lefttop.tile, cargo, rect.Width(), rect.Height(), coverageRadius ) >= 1;
	}

	function GetProduction(cargo, route, callers) {
		if(stationGroup == null) {
			HgLog.Warning("stationGroup==null(GetProduction) "+this);
			return 0;
		}
		return stationGroup.GetExpectedProduction( cargo, route.GetVehicleType(), true, callers );
	}
	
	function GetProductionInfos(cargo, route, callers) {
		return stationGroup.GetExpectedProductionInfos( cargo, route.GetVehicleType(), true, callers );
	}

	function GetCoverageRadius() {
		local stationType = GetStationType();
		if(stationType == null) {
			return 0;
		}
		return AIStation.GetCoverageRadius( stationType );
	}
	
	
	function GetCoverageTileList() {
		local result = AITileList();
	
		local radius = AIStation.GetCoverageRadius( GetStationType() );
		foreach(tile,_ in GetPlatformRectangle().GetTileList()) {
			Rectangle.Center(HgTile(tile), radius).AppendToTileList(result);
		}
		return result;
	}

	// このメソッドは単一のHgStationでしか調べていないことに注意。実際にはStationGroupを使わないといけない
	function SearchIndustries(cargo, isProducing) {
		local result = [];
		local radius = AIStation.GetCoverageRadius( GetStationType() );
		local industryList = AIList();
		foreach(tile,_ in GetCoverageTileList()) {
			industryList.AddItem(AIIndustry.GetIndustryID(tile),0);
		}
		local platformTileList = GetPlatformRectangle().GetTileList();
		
		foreach(industry,_ in industryList) {
			if(!AIIndustry.IsValidIndustry(industry)) {
				continue;
			}
			local hgIndustry = HgIndustry(industry, isProducing);
			if(!hgIndustry.IsTreatCargo(cargo)) {
				continue;
			}
			foreach(tile in hgIndustry.GetTiles(radius, cargo)) { // TODO: isProducing==falseの場合、最も小さいindustryIdのみを返す
				if(platformTileList.HasItem(tile)) {
					result.push(industry);
					break;
				}
			}
		}
		return result;
	}

	function GetUsingRoutesAsDest() {
		return stationGroup.GetUsingRoutesAsDest();
	}

	function GetIgnoreTiles() {
		return [];
	}

	function IsBuildablePreCheck() {
		return true;
	}
	
	function CanShareByMultiRoute(infrastractureType) {
		return true; // CommonRouteBuilderから呼ばれる
	}
	
	function GetUsingRoutes() {
		return usingRoutes;
	}
	
	function AddUsingRoute(route) {
		ArrayUtils.Add(usingRoutes, route);
	}
	
	function RemoveUsingRoute(route) {
		ArrayUtils.Remove(usingRoutes, route);
	}
	
	function IsTownStop() {
		return GetName().find("#") != null;
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
	
	function GetArrivalDangerTiles() {
		return [];
	}
	
	function GetDepartureDangerTiles() {
		return [];
	}
	
	function CanRemove(exceptRoute) {
		if(stationGroup == null) {
			return false; // すでにRemoveされていると思われる
		}
		foreach(station in stationGroup.hgStations) {
			foreach(route in station.usingRoutes) {
				if(exceptRoute == route) {
					continue;
				}
				if(route.srcHgStation == station) {
					return false;
				}
				if(route.destHgStation == station && !route.IsTransfer()) {
					return false;
				}
			}
		}
		return true;
	}
	
	function Share() {
		return true; //RoadStationでoverride
	}
	
	function GetCargoWaiting(cargo) {
		return AIStation.GetCargoWaiting(stationId, cargo);
	}
	
	function RemoveIfNotUsed() {
		if(stationGroup == null) {
			return;
		}
		if(IsTownStop()) {
			return;
		}
		local usingRoutes = stationGroup.GetUsingRoutes();
		if(usingRoutes.len() == 0) {
			stationGroup.Remove();
		} else {
		/*
			foreach(route in usingRoutes) {
				HgLog.Warning("RemoveIfNotUsed station:"+this+" is used by "+route);
			}*/
		}
	}

	function Remove() {
		if(stationGroup == null) {
			return;
		}
		if(stationGroup.GetUsingRoutes().len() == 0) {
			stationGroup.Remove();
		} else {
			RemoveWorld();
			Demolish();
		}
	}
	
	function IsRemoved() {
		return id == null;
	}

	function _tostring() {
		if(id==null) {
			return GetTypeName()+":id==null["+HgTile(GetLocation())+"]";
		} else {
			return GetTypeName()+":"+id+"["+GetName()+" at "+HgTile(GetLocation())+"]";
		}
	}


}

class RailStation extends HgStation {

	function IsBuildablePreCheck() {
		return true;
/*		local platformRect = GetPlatformRectangle();
		return HogeAI.IsBuildable(platformRect.lefttop.tile) && HogeAI.IsBuildable(platformRect.rightbottom.tile - AIMap.GetTileIndex(1,1));*/
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
		
		local result;
		if(cargo == null) {
			result = AIRail.BuildRailStation(platformTile, GetPlatformRailTrack(), platformNum, platformLength, joinStation);
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
		
			result = AIRail.BuildNewGRFRailStation(platformTile, GetPlatformRailTrack(), platformNum, platformLength, joinStation, 
				cargo,  industryType,  industryType, 500, isSourceStation!=null ? isSourceStation : (place!=null ? place.IsProducing() : true));
		}
		
		if(isTestMode && !result) {
			if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR) {
				return false;
			} else {
				return true;
			}
		}
		return result;
	}
	
	//TrainRoute.ChangeDestinationから使用される
	function RemoveOnlyPlatform() {
		local stationGroup = this.stationGroup;
	
		RemoveWorld();
		DemolishStation(true); // 他にこの駅のカバー範囲に依存している駅があると、その駅が使えなくなる問題がある

		if(stationGroup.GetUsingRoutes().len() == 0) {
			stationGroup.Remove();
		}
	}
	
	function DemolishStation(keepRail = false) {
		local r = GetPlatformRectangle();
		local tiles = r.GetTiles();
		local corner = platformTile + AIMap.GetTileIndex(r.Width()-1, r.Height()-1);
		AIRail.RemoveRailStationTileRectangle( platformTile, corner, keepRail );
		foreach(tile in tiles) {
			for(local i=0; i<10 && AITile.IsStationTile(tile); i++) {
				if(!AIRail.RemoveRailStationTileRectangle( tile, tile, keepRail )) {
					HgLog.Warning("Wait AIRail.RemoveRailStationTileRectangle:"+HgTile(tile)+" "+AIError.GetLastErrorString());
					AIController.Sleep(100);
				}
			}
		}
		return true;
	}

	function GetStationType() {
		return AIStation.STATION_TRAIN;
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
				result.push(AIMap.GetTileIndex(x+platformLength,y+i));
			}
		}
		return result;
	}
}

class RoadStation extends HgStation {
	static roads = [[0,0],[0,1],[1,1],[1,0],[1,-1],[0,-1],[0,0]];
	
	stationType = null;
	
	constructor(platformTile, platformNum, stationDirection, stationType) {
		HgStation.constructor(platformTile, stationDirection/*HgStation.GetStationDirectionFromTileIndex(frontTile - platformTile)*/);
		this.stationType = stationType;
		this.platformNum = platformNum;
		this.platformLength = 1;
		
		if(stationDirection == HgStation.STATION_SE) {
			originTile =  MoveTile(platformTile,0,0);
		} else if(stationDirection == HgStation.STATION_NW) {
			originTile =  MoveTile(platformTile,1-platformNum,0);
		} else if(stationDirection == HgStation.STATION_NE) {
			originTile =  MoveTile(platformTile,0,0);
		} else if(stationDirection == HgStation.STATION_SW) {
			originTile =  MoveTile(platformTile,1-platformNum,0);
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
	/*
	function GetPlatformRailTrack() { // 向きが逆だった
		switch(HgStation.GetPlatformRailTrack()) {
			case AIRail.RAILTRACK_NW_SE:
				return AIRail.RAILTRACK_NE_SW;
			case AIRail.RAILTRACK_NE_SW:
				return AIRail.RAILTRACK_NW_SE;
		}
	}*/
	
	function GetNeedMoney() {
		return 10000;
	}
	
	function BuildStation(joinStation,isTestMode,isSecond=false) {
		local tile = isSecond ? At(1,0) : At(0,0);
		local front = isSecond ? At(1,1) : At(0,1);
	
		if(isTestMode) {
			local result = AIRoad.BuildDriveThroughRoadStation(tile, front, RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
			if(!result) {
				local lastError = AIError.GetLastError();
				if(lastError == AIError.ERR_AREA_NOT_CLEAR 
						|| lastError == AIError.ERR_VEHICLE_IN_THE_WAY // このエラーは他より優先されるので道路形状は調べられない
						|| lastError == AIRoad.ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION
						|| lastError == AIRoad.ERR_UNSUITABLE_ROAD // Conveyer Beltを通常の道路に作ろうとするとこれが返る
						|| lastError == AIError.ERR_UNKNOWN/*道路状況によってはこれが返る*/) {
					return false;
				}
				//HgLog.Warning("platformTile:"+HgTile(At(0,0))+" front:"+HgTile(At(1,0))+" GetRoadVehicleType:"+RoadStation.GetRoadVehicleType(GetStationType())+" joinStation:"+AIStation.GetName(joinStation)+" "+AIError.GetLastErrorString());
			}
			if(platformNum == 2 && joinStation == AIStation.STATION_NEW && !HogeAI.Get().IsDistantJoinStations()) {
				foreach(d in HgTile.DIR8Index) {
					if(AITile.IsStationTile(tile+d) && AICompany.IsMine(AITile.GetOwner(tile+d))) {
						return false; // 厳密には成功するケースもあるかもしれないが、簡易にこうしておく
					}
				}
			}
			if(platformNum == 2 && !isSecond) {
				return BuildStation(joinStation,isTestMode,true);
			}
			return result;
		} else {
			/*HgLog.Info("stationDirection:"+stationDirection+" SE:"+HgStation.STATION_SE+" NW:"+HgStation.STATION_NW+" SW:"+HgStation.STATION_SW+" NE:"+HgStation.STATION_NE);
			HgLog.Info("platformTile:"+HgTile(platformTile));
			HgLog.Info("At(0,0):"+HgTile(At(0,0)));
			HgLog.Info("GetPlatformRectangle:"+GetPlatformRectangle());*/
			if(platformNum == 2 && joinStation != AIStation.STATION_NEW && !isSecond) {
				local result = null;
				foreach(d in HgTile.DIR8Index) {
					if(AITile.IsStationTile(tile+d) && AICompany.IsMine(AITile.GetOwner(tile+d))) {
						result = BuildUtils.RetryUntilFree(function():(joinStation,tile,front) {
							return AIRoad.BuildDriveThroughRoadStation(tile, front, RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
						});
						if(!result) {
							HgLog.Warning("BuildDriveThroughRoadStation failed:"+HgTile(tile)+" front:"+HgTile(front)+" isSecond:"+isSecond+" "+AIError.GetLastErrorString());
						}
						
						if(!result && AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
							return false;
						}
						break;
					}
				}
				if(result == true) {
					result = BuildStation(joinStation,isTestMode,true);
					if(result) {
						return true;
					}
				} else if(result == null) { // 周囲にplatformが無い場合
					result = BuildStation(joinStation,isTestMode,true);
					if(!result) {
						return false;
					}
					result = BuildUtils.RetryUntilFree(function():(joinStation,tile,front) {
						return AIRoad.BuildDriveThroughRoadStation(tile, front, RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
					});
					if(!result) {
						HgLog.Warning("BuildDriveThroughRoadStation failed:"+HgTile(tile)+" front:"+HgTile(front)+" isSecond:"+isSecond+" "+AIError.GetLastErrorString());
					}
					if(result) {
						return true;
					}
				}
				BuildUtils.RemoveRoadStationSafe(At(0,0));
				BuildUtils.RemoveRoadStationSafe(At(1,0));
				return result;
			} else {
				local result = BuildUtils.RetryUntilFree(function():(joinStation,tile,front) {
					return AIRoad.BuildDriveThroughRoadStation(tile, front, RoadStation.GetRoadVehicleType(GetStationType()), joinStation);
				});
				if(!result) {
					HgLog.Warning("BuildDriveThroughRoadStation failed:"+HgTile(tile)+" front:"+HgTile(front)+" isSecond:"+isSecond+" "+AIError.GetLastErrorString());
				}
				if(platformNum == 2 && result && !isSecond) {
					result = BuildStation(AIStation.STATION_JOIN_ADJACENT,isTestMode,true);
					if(!result) {
						BuildUtils.RemoveRoadStationSafe(At(0,0));
						BuildUtils.RemoveRoadStationSafe(At(1,0));
					}
				}
				return result;
			}
		}
	}
	
	function IsSuitableRoad(tile) {
		if(!AIRoad.IsRoadTile(tile)) {
			return false;
		}
		local roadType = AIRoad.GetCurrentRoadType();
		foreach(r in AIRoadTypeList(AIRoad.GetRoadTramType(roadType))) {
			if(AIRoad.HasRoadType(tile,r)) {
				AIRoad.ConvertRoadType(tile,tile,roadType);
				if(AIError.GetLastError() == AIRoad.ERR_UNSUITABLE_ROAD) {
					return AIRoad.RoadVehHasPowerOnRoad(roadType, r);
				}
			} else {
				return true;
			}
		}
		return false;
	}
	
	function Share() {
		foreach(tile in GetTiles()) {
			if(!IsSuitableRoad(tile)) {
				HgLog.Warning("not IsSuitableRoad "+HgTile(tile));
				return false;
			}
		}
		local prev = null;
		if(!AIRoad.HasRoadType(At(roads[0][0],roads[0][1]),AIRoad.GetCurrentRoadType())) {
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
		}
		return true;
	}
	
	function Build(levelTiles=true,isTestMode=true) {
//		HgLog.Warning("Build levelTiles:"+levelTiles+" isTestMode:"+isTestMode);

		if(levelTiles) {
			if(isTestMode) {
				foreach(tile in GetTiles()) {
					if(!HogeAI.IsBuildable(tile) && (!IsSuitableRoad(tile) || AIRoad.IsDriveThroughRoadStationTile(tile)/*既にバス停*/)) {
						return false;
					}
				}
				local pre = null;
				foreach(index,roadXY in roads) {
					local road = At(roadXY[0],roadXY[1]);
					if(pre != null && AIRoad.IsRoadTile(road)) { // 既存道路がある場合、接続可能かの検査
						local nextIndex = index == roads.len() - 1 ? 0 : index + 1;
						local next = At(roads[nextIndex][0],roads[nextIndex][1]);
						if(!AIRoad.CanBuildConnectedRoadPartsHere(road, pre, next)) {
							return false;
						}
					}
					pre = road;
				}
			}
			if(!GetRectangle(0,-1, 2,2).LevelTiles(GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles failed");
				}
				return false;
			}
		}

		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform failed");
			}
			return false;
		}
		if(isTestMode) {
			return true;
		}
		GetRectangle(0,-1, 2,2).LevelTiles(null, isTestMode); // pathfind成功率を上げるためにtrack方向ではない整地も試す

		local prev = null;
		foreach(road in roads) {
			if(prev != null) {
				if(!RoadRouteBuilder.BuildRoadUntilFree(At(prev[0],prev[1]), At(road[0],road[1])) && AIError.GetLastError() != AIError.ERR_ALREADY_BUILT){ 
					HgLog.Warning("BuildRoad failed "+HgTile(At(prev[0],prev[1]))+"-"+HgTile(At(road[0],road[1])) + " " + AIError.GetLastErrorString());
					Demolish(true);
					return false;
				}
			}
			prev = road;
		}
		foreach(index,roadXY in roads) {
			if(index != 0) {
				local tile = At(roadXY[0],roadXY[1]);
				RoadRoute.AddUsedTile(tile);
			}
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
	
	function Demolish(isBuilding=false) {
		if(!BuildUtils.RemoveRoadStationSafe(At(0,0))) {
			HgLog.Warning("RemoveRoadStation failed:"+HgTile(At(0,0))+" "+AIError.GetLastErrorString());
			RoadRoute.pendingDemolishLines.push([At(0,0)]);
		}
		if(platformNum == 2) {
			if(!BuildUtils.RemoveRoadStationSafe(At(1,0))) {
				HgLog.Warning("RemoveRoadStation failed:"+HgTile(At(1,0))+" "+AIError.GetLastErrorString());
				RoadRoute.pendingDemolishLines.push([At(1,0)]);
			}
		}

		local removableLines = [];
		local line = [];
		foreach(roadXY in roads) {
			local tile = At(roadXY[0],roadXY[1]);
			if( ((isBuilding && !RoadRoute.IsUsedTile(tile)) || (!isBuilding && RoadRoute.RemoveUsedTile(tile)))
					 && AICompany.IsMine( AITile.GetOwner(tile) ) && !AITile.IsStationTile(tile) ) {
				line.push(tile);
			} else if(line.len() >= 1) {
				removableLines.push(line);
				line = [];
			}
		}
		if(line.len() >= 1) {
			removableLines.push(line);
		}
		RoadRoute.DemolishLines(removableLines);
		
/*		
			local pre = null;
			local preRemoved = false;
			foreach(road in roads) {
				local tile = At(road[0],road[1]);
				if((isBuilding && !RoadRoute.IsUsedTile(tile)) || (!isBuilding && RoadRoute.RemoveUsedTile(tile))) {
					if(preRemoved) {
						if(AICompany.IsMine(AITile.GetOwner(pre)) && AICompany.IsMine(AITile.GetOwner(tile)) && !AIRoad.RemoveRoadFull(pre, tile)) {
							HgLog.Warning("AIRoad.RemoveRoadFull failed:"+HgTile(pre)+"-"+HgTile(tile)+" "+AIError.GetLastErrorString());
							RoadRoute.pendingDemolishLines.push([pre,tile]);
						}
					}
					if(!isBuilding) {
						RoadRoute.DemolishArroundDepot(tile);
					}
					preRemoved = true;
				} else {
					preRemoved = false;
				}
				pre = tile;
			}
//		}*/
		return true;
	}


	function GetTiles() {
		local result = [];
		foreach(i, road in roads) {
			if(i==0) {
				continue;
			}
			result.push(At(road[0],road[1]));
		}
		return result;
	}
	
	function GetEntrances() {
		if(platformNum == 1) {
			return [At(0,0)]
		} else {
			return [At(0,0),At(1,0)];
		}
		/* 道路が破壊された再検索の場合、stationから検索しないと繋がらない
		local result = [];
		foreach(road in roads) {
			local p = At(road[0],road[1]);
			if(!AITile.IsStationTile(p)) {
				result.push(At(road[0],road[1]));
			}
		}
		return result;*/
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

	function Demolish() {
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

	supressWarning = null;

	constructor(platformTile) {
		HgStation.constructor(platformTile,0);
		originTile = platformTile;
		platformNum = 1;
		platformLength = 1;
		supressWarning = false;
	}
	
	function GetTypeName() {
		return "PieceStation";
	}
	
	/*
	function IsBuildablePreCheck() {
		return AIRoad.IsRoadTile(platformTile) || AITile.IsBuildable(platformTile);
	}*/
	
	function Build(levelTiles=false,isTestMode=false) {
		local result = BuildPlatform(isTestMode,supressWarning);
		if(!isTestMode && result) {
			RoadRoute.AddUsedTile(platformTile);
		}
		return result;
	}
	
	function GetNeedMoney() {
		return 10000;
	}

	function BuildStation(joinStation,isTestMode) {
		local currentRoadType = AIRoad.GetCurrentRoadType();
		AIRoad.SetCurrentRoadType(TownBus.GetRoadType());
		local result = _BuildStation(joinStation,isTestMode);
		AIRoad.SetCurrentRoadType(currentRoadType);
		return result;
	}
	
	function _BuildStation(joinStation,isTestMode) {
		local roadVehicleType =  RoadStation.GetRoadVehicleType(GetStationType());

		local roadDir = null;
		foreach(index, d in HgTile.DIR4Index) {
			if(AIRoad.IsRoadTile(platformTile + d)) {
				roadDir = index;
				break;
			}
		}
		if(roadDir == null) {
			roadDir = 0;
			foreach(index, d in HgTile.DIR4Index) {
				if(AITile.IsBuildable(platformTile + d)) {
					roadDir = index;
					break;
				}
			}
		}
		
		local otherDir = roadDir == 0 || roadDir == 3 ? 1 : 0;

		if(isTestMode) {
			if(!AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[roadDir],roadVehicleType , joinStation)) {
				//HgLog.Info("debug: "+HgTile(platformTile)+"-"+HgTile(platformTile + HgTile.DIR4Index[0])+" "+AIError.GetLastErrorString());
				if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
					// この場合、他のエラーが取れないので建築可能か不明になる。道路形状も取れないので事前確認不能
					HogeAI.PlantTree(platformTile);
					if(AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[roadDir],roadVehicleType , joinStation)) {
						return true;
					}
				} else if(AITile.GetSlope(platformTile) == AITile.SLOPE_FLAT && GetTownRating(platformTile) >= AITown.TOWN_RATING_VERY_GOOD && IsDemolishableTownBuilding(platformTile)) {
					if(IsJoin() && !HogeAI.Get().IsDistantJoinStations() && ExistsStationGroupsMoreThanOneAround()) {
						return false;
					} else {
						return true;
					}
				}
/*				if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR || AIError.GetLastError() == AIError.ERR_UNKNOWN) {
					return false;
				}*/
				if(!AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[roadDir], roadVehicleType, joinStation) ) {
					//HgLog.Info("debug2: "+HgTile(platformTile)+"-"+HgTile(platformTile + HgTile.DIR4Index[1])+" "+AIError.GetLastErrorString());
					if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR //TODO: OKな場合を列挙した方が安全かもしれない。
							|| AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY // TODO: リトライする？
							|| AIError.GetLastError() == AIRoad.ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION
							|| AIError.GetLastError() == AIError.ERR_UNKNOWN/*道路状況によってはこれが返る*/
							|| AIError.GetLastError() == AIError.ERR_FLAT_LAND_REQUIRED
							|| AIError.GetLastError() == AITunnel.ERR_TUNNEL_CANNOT_BUILD_ON_WATER /*海上に作ろうとするとなぜかこれが返る*/) { 
						return false; //AIError.ERR_LOCAL_AUTHORITY_REFUSESは成功扱いにして探索を打ち切る。恐らく実際の建築で失敗する
					}
				}
			}
			return true;
		}
		if(AITile.IsStationTile(platformTile)) {
			HgLog.Warning("AITile.IsStationTile("+HgTile(platformTile)+")==true");
		}
		if(AITile.GetSlope(platformTile) == AITile.SLOPE_FLAT && GetTownRating(platformTile) >= AITown.TOWN_RATING_VERY_GOOD && IsDemolishableTownBuilding(platformTile)) {
			local execMode = AIExecMode(); //なぜかこれが無いと動かない
			HgLog.Warning("demolish TownBuilding "+HgTile(platformTile)); //なぜか2回呼ばれる
			if(!BuildUtils.DemolishTileSafe(platformTile)) {
				HgLog.Warning("DemolishTile failed:"+HgTile(platformTile)+" "+AIError.GetLastErrorString());
			}
		}
		if(BuildUtils.RetryUntilFree(function():(platformTile,joinStation,roadVehicleType,roadDir) {
			return AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[roadDir], roadVehicleType, joinStation);
		},3)) {
			return true;
		}
		if(BuildUtils.RetryUntilFree(function():(platformTile,joinStation,roadVehicleType,otherDir) {
			return AIRoad.BuildDriveThroughRoadStation (platformTile, platformTile + HgTile.DIR4Index[otherDir], roadVehicleType, joinStation);
		},3)) {
			return true;
		}
		return false;
	}
	
	function GetTownRating(tile) {
		local town = AITile.GetTownAuthority(tile);
		if(AITown.IsValidTown(town)) {
			return AITown.GetRating(town, AICompany.COMPANY_SELF);
		} else {
			return AITown.TOWN_RATING_NONE;
		}
	}
	
	function IsDemolishableTownBuilding(tile) {
		if(AITile.IsBuildable(tile)) {
			return false;
		}
		if(AITile.GetOwner(tile) != AICompany.COMPANY_INVALID){ 
			return false;
		}
		if(AIRoad.IsRoadTile(tile) || AITile.IsWaterTile(tile) || AIMarine.IsBuoyTile(tile)) {
			return false;
		}
		local testMode = AITestMode();
		return AITile.DemolishTile(tile);
	}
	
	
	function BuildAfter() {
	}
	
	function Demolish() {
		if(IsTownStop()) {
			return;
		}
		if(!BuildUtils.RemoveRoadStationSafe(platformTile)) {
			HgLog.Warning("RemoveRoadStation failed:"+HgTile(At(0,0))+" "+AIError.GetLastErrorString());
			RoadRoute.pendingDemolishLines.push([platformTile]);
		}
		local tile = platformTile;
		if( RoadRoute.RemoveUsedTile(tile) && AICompany.IsMine( AITile.GetOwner(tile) ) && !AITile.IsStationTile(tile) ) {
			RoadRoute.DemolishLines([[tile]]);
		}

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
	
	function GetBuildableScore() {
		local result = 0;
		if(AIRoad.IsRoadTile(platformTile)) {
			result += 10;
		}
		local neighbor = 0;
		foreach(d in HgTile.DIR4Index) {
			if(AIRoad.IsRoadTile(platformTile + d)) {
				neighbor = max(neighbor, 10);
			} else if(AITile.IsBuildable(platformTile + d)) {
				neighbor = max(neighbor, 5);
			}
		}
		result += neighbor;
		return result;
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
		yield [1, platformLength+1];
		yield [1, -3];

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
		if(!TileListUtils.LevelAverage(GetTileListForLevelTiles(tiles), GetPlatformRailTrack(), isTestMode)) {
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
			if(!RailBuilder.BuildRailSafe(
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
		BuildUtils.BuildSignalSafe(At(0,-1),At(0,0),AIRail.SIGNALTYPE_PBS_ONEWAY );
		BuildUtils.BuildSignalSafe(At(1,-1),At(1,0),AIRail.SIGNALTYPE_PBS_ONEWAY );
	}
	
	function RemoveSignal() {
		BuildUtils.RemoveSignalSafe(At(0,-1),At(0,0));
		BuildUtils.RemoveSignalSafe(At(1,-1),At(1,0));
	}
	
	
	function Demolish() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
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

	slim = null; // platformNum==3の時に出入口幅も3にする

	constructor(platformTile, platformNum, platformLength, slim, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		this.platformNum = platformNum;
		this.platformLength = platformLength;
		this.slim = slim;

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
	
	function Save() {
		local t = HgStation.Save();
		t.slim <- slim;
		return t;
	}
	
	function GetTypeName() {
		return "SmartStation";
	}
	
	
	function GetArrivalsTiles() {
		if(platformNum==2 || slim) {
			return [[At(0,platformLength+5),At(0,platformLength+4)]];
		} else if(platformNum==3) {
			return [[At(-1,platformLength+6),At(-1,platformLength+5)]];
		}
	
	}
	
	function GetDeparturesTiles() {
		return [[At(1,platformLength+4),At(1,platformLength+3)]];
	}
	
	function GetArrivalDangerTiles() {
		if(platformNum==2 || slim) {
			return [At(-2,platformLength+5),At(-1,platformLength+5),At(0,platformLength+6)];
		} else if(platformNum==3) {
			return [At(-3,platformLength+6),At(-2,platformLength+6),At(-1,platformLength+7)];
		}
	}

	function GetDepartureDangerTiles() {
		return [At(3,platformLength+4),At(2,platformLength+4),At(1,platformLength+5),];
	}
	
	function GetRails() {
		local result = [];
		
		result.push([[0,-1],[0,0],[0,1]]);
		result.push([[0,-1],[0,0],[-1,0]]);
		result.push([[1,0],[0,0],[0,1]]);

		result.push([[0,0],[-1,0],[-1,1]]);

		result.push([[1,-1],[1,0],[0,0]]);
		result.push([[1,-1],[1,0],[1,1]]);
		result.push([[1,0],[1,1],[1,2]]);
		result.push([[1,1],[1,2],[1,3]]);
		result.push([[1,2],[1,3],[1,4]]);

		result.push([[-1,0],[-1,1],[-1,2]]);

		result.push([[-1,1],[-1,2],[0,2]]);
		result.push([[-1,2],[0,2],[0,3]]);
		result.push([[0,2],[0,3],[1,3]]);
		result.push([[0,3],[1,3],[1,4]]);
		
		if(platformNum==3) {
			if(slim) {
				result.push([[-1,-1],[-1,0],[-1,1]]);
				result.push([[-1,-1],[-1,0],[0,0]]);
				result.push([[-1,0],[0,0],[0,1]]);
				result.push([[0,-1],[0,0],[1,0]]);
				result.push([[0,0],[1,0],[1,1]]);
			} else {
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
		if(platformNum==3 && !slim) {
			return [At(0, platformLength+6)];
		} else {
			return [];
		}
	}

	function GetMustBuildableAndFlatTiles() {
		if(platformNum==2 || (platformNum==3 && slim)) {
			for(local x=0; x<2; x++) {
				for(local y=0; y<=platformLength+6; y++) {
					yield [x,y];
				}
			}

			yield [-1,platformLength];
			yield [-1,platformLength+1];
			yield [-1,platformLength+2];
			if(platformNum == 3) {
				for(local y=0; y<=platformLength; y++) {
					yield [-1,y];
				}
			}
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

		if(!TileListUtils.LevelAverage(GetTileListForLevelTiles(tiles), GetPlatformRailTrack(), isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
			}
			return false;
		}
		if(!isTestMode) {
			TileListUtils.LevelAverage(GetTileListForLevelTiles(tiles), null, isTestMode, null, true); // pathfind成功率を上げるためにtrack方向ではない整地も試す
		}

		if(!BuildPlatform(isTestMode)) {
			if(!isTestMode) {
				HgLog.Warning("BuildPlatform failed."+AIError.GetLastErrorString());
			}
			return false;
		}
		
		local bridge_list = AIBridgeList_Length(4);
		bridge_list.Valuate(AIBridge.GetMaxSpeed);
		bridge_list.Sort(AIList.SORT_BY_VALUE, false);
		if(!BuildUtils.BuildBridgeSafe(AIVehicle.VT_RAIL, bridge_list.Begin(), At(0,platformLength+1), At(0,platformLength+4))) {
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
			if(!RailBuilder.BuildRailSafe(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				HgLog.Warning("BuildRail Failed."+AIError.GetLastErrorString());
				return false;
			}
		}
		
		BuildSignal();
		
		PurchaseLand(GetArrivalsTiles()[0][0]);
		PurchaseLand(GetDeparturesTiles()[0][0]);
		
		return true;
	}
	
	
	function BuildAfter() {
	}
	
	function RemoveDepots() {
	}
	
	function BuildSignal() {
		BuildUtils.BuildSignalSafe(At(1,platformLength+2),At(1,platformLength+1),AIRail.SIGNALTYPE_PBS_ONEWAY );
		BuildUtils.BuildSignalSafe(At(0,platformLength+3),At(0,platformLength+2),AIRail.SIGNALTYPE_PBS_ONEWAY );
	}
	
	function RemoveSignal() {
		BuildUtils.RemoveSignalSafe(At(1,platformLength+2),At(1,platformLength+1));
		BuildUtils.RemoveSignalSafe(At(0,platformLength+3),At(0,platformLength+2));
	}
	
	
	function Demolish() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
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
				return BuildPlatform(isTestMode);
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
			if(!RailBuilder.BuildRailSafe(
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
		if(BuildUtils.BuildRailDepotSafe(p1,p2)) {
			depots.push(p1);
		}
		DoSave();
	}
	
	function RemoveDepots() {
		foreach(tile in depots) {
			if(!BuildUtils.DemolishTileUntilFree(tile)) {
				HgLog.Warning("DemolishTile failed."+HgTile(tile)+" "+AIError.GetLastErrorString());
			}
		}
		depots = [];
		DoSave();
	}
	
	function BuildAfter() {
		for(local x=0; x<platformNum; x++) {
			BuildDepot(At(x,-1),At(x,0));
		}
//		BuildDepot(At(-1,0),At(0,0));
//		BuildDepot(At(platformNum,0),At(platformNum-1,0));
	}
	
	function Demolish() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
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
			if(!BuildUtils.BuildSignalSafe(At(i,platformLength+1),At(i,platformLength),AIRail.SIGNALTYPE_PBS_ONEWAY )) {
				return false;
			}
		}
		return true;
	}
	
	function RemoveSignal() {
		for(local i=0; i<platformNum; i++) {
			if(!BuildUtils.RemoveSignalSafe(At(i,platformLength+1),At(i,platformLength))) {
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
			if(!TileListUtils.LevelAverage(tileList, GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
			if(isTestMode) {
				return BuildPlatform(isTestMode);
			}
		}
		
		
		if(!BuildPlatform(isTestMode)) {
			HgLog.Warning("BuildPlatform failed."+AIError.GetLastErrorString());
			return false;
		}
		
		foreach(rail in GetRails()) {
			if(!RailBuilder.BuildRailSafe(
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
	
	function Demolish() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
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

			local tileList = AIList();
			local d1 = HgTile.XY(1,0).tile;
			local d2 = HgTile.XY(0,1).tile;
			local d3 = HgTile.XY(1,1).tile;
			foreach(tile in tiles) {
				tileList.AddItem(tile,0);
				tileList.AddItem(tile + d1,0);
				tileList.AddItem(tile + d2,0);
				tileList.AddItem(tile + d3,0);
			}
			if(!TileListUtils.LevelAverage(tileList, GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
			if(isTestMode) {
				return BuildPlatform(isTestMode);
			}		
		}

		if(!BuildPlatform(isTestMode)) {
			return false;
		}
		foreach(depot in GetDepots()) {
			if(!BuildUtils.BuildRailDepotSafe(At(depot[0][0],depot[0][1]),At(depot[1][0],depot[1][1]))) {
				if(!isTestMode) {
					HgLog.Warning("AIRail.BuildRailDepot Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}
		
		foreach(rail in GetRails()) {
			if(!RailBuilder.BuildRailSafe(
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
	
	function Demolish() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
			HgLog.Warning("RemoveRailStationTileRectangle failed " + r + " " + AIError.GetLastErrorString());
			result = false;
		}
		foreach(rail in GetRails()) {
			local t1 = At(rail[0][0],rail[0][1]);
			local t2 = At(rail[1][0],rail[1][1]);
			local t3 = At(rail[2][0],rail[2][1]);
			if(!AIRail.RemoveRail(t1,t2,t3)) {
				HgLog.Warning("RemoveRail failed. "+HgTile(t1)+" "HgTile(t2)+" "+HgTile(t3)
					+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
		foreach(depot in GetDepots()) {
			if(!AITile.DemolishTile(At(depot[0][0],depot[0][1]))) {
				HgLog.Warning("DemolishTile failed."+HgTile(depot)+" "+AIError.GetLastErrorString());
				result = false;
			}
		}
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
		if(!BuildUtils.BuildSignalSafe(At(2,0),At(2,1),AIRail.SIGNALTYPE_PBS_ONEWAY )) {
			return false;
		}
		if(!BuildUtils.BuildSignalSafe(At(0,platformLength),At(0,platformLength-1),AIRail.SIGNALTYPE_PBS_ONEWAY )) {
			return false;
		}
		
		return true;
	}
	
	function RemoveSignal() {
		BuildUtils.RemoveSignalSafe(At(2,0),At(2,1));
		BuildUtils.RemoveSignalSafe(At(0,platformLength),At(0,platformLength-1));
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
				local average = TileListUtils.CalculateAverageLevel(tileList);
				if(preAverage != null && abs(preAverage - average) >= 2) {
					if(!isTestMode) {
						HgLog.Warning("LevelTiles Failed. Average levels too far apart");
					}
					return false;
				}
				preAverage = average;
				
				if(!TileListUtils.LevelAverage(tileList, GetPlatformRailTrack(), isTestMode, average)) {
					if(!isTestMode) {
						HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
					}
					return false;
				}
			}
		}
		if(!BuildPlatform(isTestMode)) {
			return false;
		}
		foreach(depot in GetDepots()) {
			if(!BuildUtils.BuildRailDepotSafe(At(depot[0][0],depot[0][1]),At(depot[1][0],depot[1][1]))) {
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
		if(!BuildUtils.BuildBridgeSafe(AIVehicle.VT_RAIL, bridge_list.Begin(), At(1,platformLength+3), At(1,platformLength+6))) {
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
			if(!RailBuilder.BuildRailSafe(
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
		
		
		PurchaseLand(GetArrivalsTiles()[0][0]);
		PurchaseLand(GetDeparturesTiles()[0][0]);
		
		return true;
	}
	
	function BuildAfter() {
	}
	
	function Demolish() {
		local result = true;
		RemoveSignal();
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
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
		result.push(At(1,platformLength+3));
		return result;
	}
	
	
	function BuildSignal() {
		for(local i=0; i<3; i++) {
			if(!BuildUtils.BuildSignalSafe(At(i,platformLength),At(i,platformLength-1),AIRail.SIGNALTYPE_PBS )) {
				return false;
			}
		}
		if(!BuildUtils.BuildSignalSafe(At(1,platformLength+2),At(1,platformLength+3),AIRail.SIGNALTYPE_PBS_ONEWAY  )) {
			return false;
		}
		return true;
	}
	
	function RemoveSignal() {
		for(local i=0; i<3; i++) {
			BuildUtils.RemoveSignalSafe(At(i,platformLength),At(i,platformLength-1));
		}
		BuildUtils.RemoveSignalSafe(At(1,platformLength+2),At(1,platformLength+3));
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
		yield [1,platformLength+8];
		yield [2,platformLength+7];
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
		a.push([3,platformLength+6]);
		a.push([0,platformLength+7]);
		a.push([1,platformLength+7]);
		/*
		for(local x=1; x<4; x++) {
			for(local y=platformLength+7; y<=platformLength+7; y++) {
				a.push([x,y]);
			}
		}
		a.push([1,platformLength+7]);
		a.push([2,platformLength+7]);*/
		result.push(a);
		return result;
	}
	
	
	function GetArrivalsTiles() {
		return [[At(1,platformLength+7),At(1,platformLength+6)]];
	}
	
	function GetDeparturesTiles() {
		return [[At(2,platformLength+6),At(2,platformLength+5)]];
	}
	
	function GetArrivalDangerTiles() {
		return [At(0,platformLength+7),At(1,platformLength+8)];
	}

	function GetDepartureDangerTiles() {
		return [At(4,platformLength+6),At(3,platformLength+6),At(2,platformLength+7)];
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

	constructor(platformTile, platformNum, platformLength, stationDirection) {
		HgStation.constructor(platformTile,stationDirection);

		this.platformNum = platformNum;
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
	
	function Save() {
		local t = HgStation.Save();
		t.useDepot <- useDepot; // rail updateの時に使う
		return t;
	}
	
	function GetNeedMoney() {
		return 15000;
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
			if(!TileListUtils.LevelAverage(GetTileListForLevelTiles(tiles), GetPlatformRailTrack(), isTestMode)) {
				if(!isTestMode) {
					HgLog.Warning("LevelTiles Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}
		if(!BuildPlatform(isTestMode)) {
			/*
			if(!isTestMode) {
				foreach(t,_ in GetTileListForLevelTiles(tiles)) {
					HgLog.Info("GetTileListForLevelTiles:"+HgTile(t));
				}
			}*/
			return false;
		}
		foreach(depot in GetDepots()) {
			if(!BuildUtils.BuildRailDepotSafe(At(depot[0][0],depot[0][1]),At(depot[1][0],depot[1][1]))) {
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
		
		TileListUtils.LevelAverage(GetTileListForLevelTiles(tiles), null, isTestMode, null, true); // pathfind成功率を上げるためにtrack方向ではない整地も試す

		foreach(rail in GetRails()) {
			if(!RailBuilder.BuildRailSafe(
				At(rail[0][0],rail[0][1]),
				At(rail[1][0],rail[1][1]),
				At(rail[2][0],rail[2][1]))) {
				if(!isTestMode) {
					HgLog.Warning("AIRail.BuildRail Failed "+AIError.GetLastErrorString());
				}
				return false;
			}
		}			
		PurchaseLand(GetArrivalsTiles()[0][0]);
		PurchaseLand(GetDeparturesTiles()[0][0]);
		return true;
		
		
	}
	
	function BuildAfter() {
	}
	
	function Demolish() {
		local result = true;
		
		local r = GetPlatformRectangle();
		if(!DemolishStation()) {
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
		for(local x=0; x<platformNum; x++) {
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
		if(platformNum == 1 && !useDepot) {
			return [[At(0,platformLength+0),At(0,platformLength-1)]];
		} else {
			return [[At(0,platformLength+1),At(0,platformLength+0)]];
		}
	}
	
	function GetDeparturesTiles() {
		if(platformNum == 1) {
			return GetArrivalsTiles();
		} else {
			return [[At(1,platformLength+1),At(1,platformLength+0)]];
		}
	}
	
	function GetArrivalDangerTiles() {
		if(platformNum == 1) {
			return [];
		}
		return [At(-2,platformLength+1),At(-1,platformLength+1),At(0,platformLength+2)];
	}

	function GetDepartureDangerTiles() {
		if(platformNum == 1) {
			return [];
		}
		return [At(2,platformLength+1),At(1,platformLength+2)];
	}

	function GetRails() {
		local result = [];
		local a = [];
		
		if(platformNum >= 2) {
			a.push([[0,-1],[0,0],[0,1]]);
			a.push([[1,-1],[1,0],[1,1]]);

			a.push([[0,-1],[0,0],[1,0]]);
			a.push([[1,-1],[1,0],[0,0]]);

			a.push([[0,1],[0,0],[1,0]]);
			a.push([[1,1],[1,0],[0,0]]);
		}
		if(useDepot) {
			a.push([[0,-1],[0,0],[-1,0]]);
			a.push([[0,1],[0,0],[-1,0]]);
			
			if(platformNum == 1) {
				a.push([[0,-1],[0,0],[0,1]]);
			} else if(platformNum >= 2) {
				a.push([[-1,0],[0,0],[1,0]]);
			}
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