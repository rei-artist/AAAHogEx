
class PlaceProduction {
	static instance = GeneratorContainer(function() { 
		return PlaceProduction(); 
	});

	static function Get() {
		return PlaceProduction.instance.Get();
	}

	static PIECE_SIZE = 64;
	
	pieceNumX = null;
	pieceNumY = null;

	lastCheckMonth = null;
	history = null;
	currentProduction = null;
	ngPlaces = null;
	cargoProductionInfos = null;
	
	constructor() {
		history = {};
		currentProduction = {};
		ngPlaces = {};
		pieceNumX = AIMap.GetMapSizeX() / PlaceProduction.PIECE_SIZE;
		pieceNumY = AIMap.GetMapSizeY() / PlaceProduction.PIECE_SIZE;
	}
	
	static function Save(data) {
		data.placeProduction <- {
			lastCheckMonth = lastCheckMonth
			history = history
			currentProduction = currentProduction
			cargoProductionInfos = cargoProductionInfos
		};
	}

	static function Load(data) {
		local t = data.placeProduction;
		lastCheckMonth = t.lastCheckMonth;
		history = t.history;
		currentProduction = t.currentProduction;
		cargoProductionInfos = t.cargoProductionInfos;
	}
	
	function GetCurrentMonth () {
		local currentDate = AIDate.GetCurrentDate();
		return (AIDate.GetMonth(currentDate)-1) + AIDate.GetYear(currentDate) * 12;
	}
	
	function Check() {
		local currentMonth = GetCurrentMonth();
		if(lastCheckMonth == null || lastCheckMonth < currentMonth) {
			foreach(cargo,v in AICargoList()) {
				foreach(industry,v in AIIndustryList_CargoProducing(cargo)) {
					local production = AIIndustry.GetLastMonthProduction (industry, cargo);
					//HgLog.Info("GetLastMonthProduction "+AIIndustry.GetName(industry)+" "+AICargo.GetName(cargo)+" "+production);
					local key = industry+"-"+cargo;
					if(!history.rawin(key)) {
						history[key] <- [1];
					}
					local a = history[key];
					if(a.len() < 13) {
						a.push(production);
					} else {
						a[a[0]] = production;
					}
					a[0] = a[0] == 12 ? 1 : a[0] + 1;
					currentProduction.rawset(key, -1);
				}
			}
			lastCheckMonth = currentMonth;
		}
	}
	
	function GetLastMonthProduction(industry,cargo) {
		Check();
		local key = industry+"-"+cargo;
		if(!currentProduction.rawin(key)) {
			return 0;
		}
		local result = currentProduction[key];
		if(result == -1) {
			if(!history.rawin(key)) {
				return 0;
			}
			local a = history[key];
			if(a.len() <= 1) {
				return 0;
			}
			local sum = 0;
			for(local i=1; i<a.len(); i++) {
				sum += a[i];
			}
			result = sum / (a.len() - 1);
			currentProduction.rawset(key, result);
		}
		return result;
	}
	
	function GetCargoProductionInfos() {
		if(cargoProductionInfos == null) {
			cargoProductionInfos = CalculateCargoProductionInfos();
		}
		return cargoProductionInfos;
	}
	
	function GetPieceIndex(tile) {
		return ( AIMap.GetTileX(tile) - 1 ) / PlaceProduction.PIECE_SIZE + ( AIMap.GetTileY(tile) - 1 ) / PlaceProduction.PIECE_SIZE * pieceNumX;
	}

	function CalculateCargoProductionInfos() {
		
		local result = {};
		foreach(cargo ,_ in AICargoList()) {
			local places = Place.GetCargoProducing(cargo).array;
			local info = {};
			local pieceInfos = array(pieceNumX * pieceNumY);
			result[cargo] <- {
				pieceInfos = pieceInfos
			};
			foreach(place in places) {
				local p = place.GetLastMonthProduction(cargo);
				if(p >= 1) {
					local pieceIndex = GetPieceIndex(place.GetLocation());
					local pieceInfo;
					if(pieceInfos[pieceIndex] == null) {
						pieceInfo = {
							sum = 0
							count = 0
							usable = true
						};
						pieceInfos[pieceIndex] = pieceInfo;
					} else {
						pieceInfo = pieceInfos[pieceIndex]
					}
					if(pieceInfo.usable) {
						local usable = PlaceDictionary.Get().CanUseAsSource(place, cargo);
						if(usable == false) {
							pieceInfo.usable = false;
						}
						pieceInfo.sum += p;
						pieceInfo.count ++;
					}
				}
			}
		}
		return result;
	}
	
	function GetArroundProductionCargo(location, cargo) {
		local pieceIndex = GetPieceIndex(location);
		local x = pieceIndex % pieceNumX;
		local y = pieceIndex / pieceNumX;
		local indexes = [];
		indexes.push(pieceIndex);
		if(x >= 1) {
			indexes.push(pieceIndex-1);
			if(y < pieceNumY - 1) {
				indexes.push(pieceIndex+pieceNumX-1);
			}
		}
		if(y >= 1) {
			indexes.push(pieceIndex-pieceNumX);
			if(x >= 1) {
				indexes.push(pieceIndex-pieceNumX-1);
			}
		}
		if(x < pieceNumX - 1) {
			indexes.push(pieceIndex+1);
			if(y >= 1) {
				indexes.push(pieceIndex-pieceNumX+1);
			}
		}
		if(y < pieceNumY - 1) {
			indexes.push(pieceIndex+pieceNumX);
			if(x < pieceNumX - 1) {
				indexes.push(pieceIndex+pieceNumX+1);
			}
		}
		local pieceInfos = GetCargoProductionInfos()[cargo].pieceInfos;
		local sum = 0;
		foreach(index in indexes) {
			local pieceInfo = pieceInfos[index];
			if(pieceInfo != null && pieceInfo.usable) {
				sum += pieceInfo.sum;
			}
		}
		return sum;
	}
}

class PlaceDictionary {
	static instance = GeneratorContainer(function() { 
		return PlaceDictionary(); 
	});

	static function Get() {
		return PlaceDictionary.instance.Get();
	}
	
	sources = null;
	dests = null;
	nearWaters = null;
	
	constructor() {
		sources = {};
		dests = {};
		nearWaters = {};
	}
	
	function AddRoute(route) {
		if(route.srcHgStation.place != null) {
			AddRouteTo(sources, route.srcHgStation.place, route);
		}
		if(route.destHgStation.place != null) {
			if(route.IsBiDirectional()) {
				AddRouteTo(sources, route.destHgStation.place.GetProducing(), route);
			} else {
				AddRouteTo(dests, route.destHgStation.place, route);
			}
		}
		route.srcHgStation.AddUsingRoute(route);
		route.destHgStation.AddUsingRoute(route);
	}

	function RemoveRoute(route) {
		if(route.srcHgStation.place != null) {
			RemoveRouteFrom(sources, route.srcHgStation.place, route);
		}
		if(route.destHgStation.place != null) {
			if(route.IsBiDirectional()) {
				RemoveRouteFrom(sources, route.destHgStation.place.GetProducing(), route);
			} else {
				RemoveRouteFrom(dests, route.destHgStation.place, route);
			}
		}
		route.srcHgStation.RemoveUsingRoute(route);
		route.destHgStation.RemoveUsingRoute(route);
	}
	
	function RemoveRouteFrom(dictionary, place, route) {
		local id = place.Id();
		if(dictionary.rawin(id)) {
			ArrayUtils.Remove(dictionary[id], route);
		}
	}
	
	function AddRouteTo(dictionary, place, route) {
		local id = place.Id();
		if(!dictionary.rawin(id)) {
			dictionary[id] <- [];
		}
		ArrayUtils.Add(dictionary[id], route);
	}
	
	function CanUseAsSource(place, cargo) {
		/*
		if(HogeAI.Get().stockpiled) { // Railでも受け入れきれないケースがあるので禁止しない=>IsOverflowでわかるのでは？
			return true;
		}*/
		local routes = GetRoutesBySource(place);
		foreach(route in routes) {
			if(route.HasCargo(cargo) && route.GetVehicleType() == AIVehicle.VT_RAIL && !route.IsOverflow() && !route.IsClosed()) {
				return false;
			}
		}
		return !Place.IsRemovedDestPlace(place);	
	}
	
	function IsUsedAsSourceCargo(place,cargo) {
		foreach(route in GetRoutesBySource(place)) {
			if(route.HasCargo(cargo)) {
				return true;
			}
		}
		return false;
	}
	
	function IsUsedAsSrouceByTrain(place, except=null) {
		foreach(route in GetRoutesBySource(place)) {
			if(route instanceof TrainRoute && route != except) {
				return true;
			}
		}
		return false;
	}
	
	function IsUsedAsSrouceCargoByTrain(place,cargo) {
		foreach(route in GetRoutesBySource(place)) {
			if(route instanceof TrainRoute && route.HasCargo(cargo)) {
				return true;
			}
		}
		return false;
	}
	
	function GetUsedAsSourceCargoByRail(place,cargo) {
		local result = [];
		foreach(route in GetRoutesBySource(place)) {
			local vehicleType = route.GetVehicleType();
			if((vehicleType == AIVehicle.VT_RAIL) && route.HasCargo(cargo)) {
				result.push(route);
			}
		}
		return result;
	}
	
	function GetUsedAsSourceCargoByRailOrAir(place,cargo) {
		local result = [];
		foreach(route in GetRoutesBySource(place)) {
			local vehicleType = route.GetVehicleType();
			if((vehicleType == AIVehicle.VT_RAIL || vehicleType == AIVehicle.VT_AIR) && route.HasCargo(cargo)) {
				result.push(route);
			}
		}
		return result;
	}
	
	function GetUsedAsSourceByTrain(place) {
		local result = [];
		foreach(route in GetRoutesBySource(place)) {
			if(route instanceof TrainRoute) {
				result.push(route);
			}
		}
		return result;
	}

	function GetRoutesByDestCargo(place, cargo) {
		local result = [];
		foreach(route in GetRoutesByDest(place)) {
			if(route.HasCargo(cargo)) {
				result.push(route);
			}
		}
		return result;
		
	}

	function GetRoutesBySource(place) {
		return GetRoutes(sources,place);
	}

	function GetRoutesByDest(place) {
		return GetRoutes(dests,place);
	}

	function GetRoutes(dictionary, place) {
		local id = place.Id();
		if(!dictionary.rawin(id)) {
			dictionary[id] <- [];
		}
		return dictionary[id];
/*		local result = [];
		foreach(route in dictionary[id]) {
			if(!route.IsClosed()) {
				result.push(route);
			}
		}
		return result;*/
	}
}


class Place {

	static removedDestPlaceDate = [];
	static ngPathFindPairs = {};
	static productionHistory = [];
	static needUsedPlaceCargo = [];
	static ngPlaces = {};
	static placeStationDictionary = {};
	static canBuildAirportCache = {};
	
	static function SaveStatics(data) {
		local array = [];

		array = [];
		foreach(placeDate in Place.removedDestPlaceDate){
			local t = placeDate[0].Save();
			t.date <- placeDate[1];
			array.push(t);
		}
		data.removedDestPlaceDate <- array;
		
		array = [];
		foreach(t in Place.needUsedPlaceCargo){
			array.push([t[0].Save(),t[1]]);
		}
		data.needUsedPlaceCargo <- array;
		
		data.ngPathFindPairs <- Place.ngPathFindPairs;
		
		array = [];
		foreach(industry,v in HgIndustry.closedIndustries){
			array.push(industry);
		}
		data.closedIndustries <- array;
		
		
		PlaceProduction.Get().Save(data);

		data.nearWaters <- PlaceDictionary.Get().nearWaters;
		data.ngPlaces <- Place.ngPlaces;
	}

	
	static function LoadStatics(data) {
		
		Place.removedDestPlaceDate.clear();
		foreach(t in data.removedDestPlaceDate) {
			Place.removedDestPlaceDate.push([Place.Load(t),t.date]);
		}
		
		
		Place.needUsedPlaceCargo.clear();
		foreach(t in data.needUsedPlaceCargo) {
			Place.needUsedPlaceCargo.push([Place.Load(t[0]) ,t[1]]);
		}
		
		Place.ngPathFindPairs.clear();
		foreach(k,v in data.ngPathFindPairs) {
			Place.ngPathFindPairs.rawset(k,v);
		}

		HgIndustry.closedIndustries.clear();
		foreach(industry in data.closedIndustries){
			HgIndustry.closedIndustries[industry] <- true;
		}
		PlaceProduction.Get().Load(data);
		
		PlaceDictionary.Get().nearWaters = data.nearWaters;
		if(data.rawin("ngPlaces")) {
			HgTable.Extend(Place.ngPlaces, data.ngPlaces);
		}
	}
	
	static function Load(t) {		
		switch(t.name) {
			case "HgIndustry":
				return HgIndustry(t.industry,t.isProducing);
			case "TownCargo":
				return TownCargo(t.town,t.cargo,t.isProducing);
		}
	}
	
	static function DumpData(data) {
		if(typeof data == "table" || typeof data == "array") {
			local result = "[";
			foreach(k,v in data) {
				result += (k+"="+Place.DumpData(v))+",";
			}
			result += "]";
			return result;
		} else {
			return data;
		}
		
	}
	
			
	static function SetRemovedDestPlace(place) {
		Place.removedDestPlaceDate.push([place,AIDate.GetCurrentDate()]);
	}
	
	
	static function IsRemovedDestPlace(place) {
		local current = AIDate.GetCurrentDate();
		foreach(placeDate in Place.removedDestPlaceDate) {
			if(placeDate[0].IsSamePlace(place) && current < placeDate[1]+60) {
				return true;
			}
		}
		return false;
	}
	
	static function AddNgPlace(facility, cargo, vehicleType, limit = null) {
		if(limit == null) {
			limit = AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES ? AIDate.GetCurrentDate() + 60 : AIDate.GetCurrentDate() + 300; 
		}
		Place.ngPlaces.rawset(facility.GetLocation() + ":" + cargo +":" + vehicleType, limit);
		HgLog.Info("AddNgPlace:"+facility.GetName()+"["+AICargo.GetName(cargo)+"] vt:"+vehicleType+" limit:"+DateUtils.ToString(limit));
	}

	static function IsNgPlace(facility, cargo, vehicleType) {
		local key = facility.GetLocation() + ":" + cargo +":" + vehicleType;
		if(Place.ngPlaces.rawin(key)) {
			local date = Place.ngPlaces[key];
			if(date == -1) {
				return true;
			} else {
				return AIDate.GetCurrentDate() < date;
			}
		} else if(HogeAI.Get().IsAvoidSecondaryIndustryStealing()) {
			if(facility instanceof HgIndustry && facility.IsProcessing()) {
				if(AIIndustry.GetAmountOfStationsAround(facility.industry) >= 1 && facility.GetRoutes().len() == 0) { //TODO: これでは範囲内にある別施設用の自分のstationに反応してしまう
					HgLog.Info("Detect SecondaryIndustryStealing:"+facility.GetName());
					return true;
				}
			}
		}
		return false;
	}
	
	static function AddNgPathFindPair(from, to, vehicleType) {
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			return;
		}
		local fromTile = typeof from == "integer" ? from : from.GetLocation();
		local toTile = typeof to == "integer" ? to : to.GetLocation();
		
		Place.ngPathFindPairs.rawset(fromTile+"-"+toTile+"-"+vehicleType,true);
	}
	
	static function IsNgPathFindPair(from, to, vehicleType) {
		local fromTile = typeof from == "integer" ? from : from.GetLocation();
		local toTile = typeof to == "integer" ? to : to.GetLocation();
		return Place.ngPathFindPairs.rawin(fromTile+"-"+toTile+"-"+vehicleType);
	}
	
	static function AddNeedUsed(place, cargo) {
		Place.needUsedPlaceCargo.push([place, cargo]);
	}
	
	static function GetCargoProducing( cargo ) {
		local result = [];
		foreach(industry,v in AIIndustryList_CargoProducing(cargo)) {
			local hgIndustry = HgIndustry(industry,true);
			result.push(hgIndustry);
		}
		if(Place.IsProducedByTown(cargo)) {
			local townList = AITownList();
			townList.Valuate(AITown.GetPopulation);
			townList.KeepAboveValue( 200 );
			foreach(town, v in townList) {
				result.push(TownCargo(town,cargo,true));
			}
		}
		return HgArray(result);
	}

	static function IsAcceptedByTown(cargo) {
		return /*AIIndustryList_CargoAccepting(cargo).Count()==0 &&*/ AICargo.GetTownEffect(cargo) != AICargo.TE_NONE;
	}
	
	static function IsProducedByTown(cargo) {
		return cargo == HogeAI.GetPassengerCargo() || cargo == HogeAI.GetMailCargo();
	}

	static function SearchNearProducingPlaces(cargo, fromTile, maxDistance) {
		return Place.GetCargoProducing( cargo ).Filter(function(place):(cargo,fromTile,maxDistance) {
			return place.DistanceManhattan(fromTile) <= maxDistance && place.GetLastMonthProduction(cargo) >= 1;
		});
	}
	

	static function GetNotUsedProducingPlaces( cargo ) {
		return Place.GetCargoProducing( cargo ).Filter(function(place):(cargo) {
			return PlaceDictionary.Get().CanUseAsSource(place,cargo);
		});
	}
	
	static function GetProducingPlaceDistance( cargo, fromTile, maxDistance = 200) {
		return Place.GetNotUsedProducingPlaces( cargo ).Map(function(place):(fromTile) {
			return [place, place.DistanceManhattan( fromTile )];
		}).Filter(function(placeDistance):(maxDistance) {
			return placeDistance[1] < maxDistance;
		})
	}
	
	static function AdjustProduction(place,production) {
		
		local accepting = place.GetAccepting();
		local canInclease = false;
		if(accepting.IsRaw() && accepting.IsNearAnyOneNeeds()) {
			production *= 2;
		}
		if(accepting.IsProcessing() && accepting.IsNearAllNeeds()) {
			production *= 2;
		}
		return production;
	}
	

	static function SearchSrcAdditionalPlaces(src, destTile, cargo, minDistance=20, maxDistance=200, minProduction=60, vehicleType=AIVehicle.VT_RAIL) {
		local middleTile;
		if(src instanceof HgStation && src.place != null) {
			middleTile = src.place.GetLocation(); // srcとdestが同じになるのを防ぐため
		} else {
			middleTile = src.GetLocation();
		}
		local existingDistance = destTile == null ? 0 : AIMap.DistanceManhattan(destTile, middleTile);
		return Place.GetProducingPlaceDistance(cargo, middleTile, maxDistance).Map(function(placeDistance):(cargo, destTile, vehicleType) {
			local t = {};
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			t.totalDistance <- destTile == null ? t.distance : AIMap.DistanceManhattan(destTile, t.place.GetLocation());
			t.production <- t.place.GetExpectedProduction(cargo, vehicleType);
			return t;
		}).Filter(function(t):(middleTile, minDistance, minDistance, minProduction, existingDistance, vehicleType){
			return minDistance <= t.distance 
				&& (existingDistance==0 || t.totalDistance - t.distance > existingDistance / 2)
				&& minProduction <= t.production 
				&& t.place.GetLocation() != middleTile 
				&& !Place.IsNgPathFindPair(t.place, middleTile, vehicleType);
		}).Map(function(t):(middleTile,vehicleType,cargo){
			t.cost <- vehicleType == AIVehicle.VT_WATER ? 1 : HgTile(middleTile).GetPathFindCost(HgTile(t.place.GetLocation()),vehicleType != AIVehicle.VT_RAIL);
			t.score <- t.totalDistance * 100 / t.cost; //TODO GetMaxCargoPlacesの結果を使う
			if(vehicleType == AIVehicle.VT_WATER && !t.place.IsNearWater(cargo)) {
				t.score = -1;
			}
			//t.production = Place.AdjustProduction(t.place, t.production);
			return t;
		}).Filter(function(t) {
//			HgLog.Info("place:"+t.place.GetName()+" cost:"+t.cost+" dist:"+t.distance+" score:"+t.score);
			return t.cost <= 300// && minScore <= t.score 
		}).Sort(function(a,b) {
			return b.score * b.production - a.score * a.production;
		}).array;
	}
	

	static function GetCargoAccepting(cargo) {
		local result = HgArray([]);
		local limitPopulation = AICargo.GetTownEffect(cargo) == AICargo.TE_GOODS ? 1000 : 200;
		if(Place.IsAcceptedByTown(cargo)) {
			result = HgArray.AIListKey(AITownList()).Map(function(town) : (cargo) {
				return TownCargo(town,cargo,false);
			}).Filter(function(place) : (limitPopulation) {
				return AITown.GetPopulation (place.town) >= limitPopulation;
			});
		}
		result.array.extend(HgArray.AIListKey(AIIndustryList_CargoAccepting(cargo)).Map(function(a) {
			return HgIndustry(a,false);
		}).Filter(function(place):(cargo) {
			return place.IsCargoAccepted(cargo); //CAS_TEMP_REFUSEDを除外する
		}).array);
		return result;
	}
	
	static function GetAcceptingPlaceDistance(cargo, fromTile, maxDistance=1000 /*350*/) {
		return Place.GetCargoAccepting(cargo).Map(function(place):(fromTile) {
			return [place, place.DistanceManhattan(fromTile)];
		}).Filter(function(placeDistance):(maxDistance) {
			return placeDistance[1] < maxDistance;
		})
	}

	static function AdjustAcceptingPlaceScore(score, place, cargo) {
		if(place.IsProcessing()) {
			local usedRoutes = PlaceDictionary.Get().GetUsedAsSourceByTrain(place.GetProducing());
			if(usedRoutes.len()>0) {
				if(usedRoutes[0].NeedsAdditionalProducing()) {
					score *= 3;
				}
			} else {
				if(place.IsNearAllNeedsExcept(cargo)) {
					score *= 3;
				}
			}
		}
		//TODO rawでcargoが不足していて使用中の場合も
		return score;
	}

	static function SearchAcceptingPlaces(cargo,fromTile,vehicleType) {
		local hgArray = Place.GetAcceptingPlaceDistance(cargo,fromTile).Map(function(placeDistance) : (cargo,fromTile)  {
			local t = {};
			t.cargo <- cargo;
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			t.cost <- HgTile(fromTile).GetPathFindCost(HgTile(t.place.GetLocation()));
			t.score <- t.distance * 10000 / t.cost;
			return t;
		}).Filter(function(t):(fromTile,vehicleType) {
			if(vehicleType == AIVehicle.VT_RAIL && t.place.IsRaw()) {
				return false;
			}
			return 60 <= t.distance && t.cost < 300 && !Place.IsNgPathFindPair(t.place,fromTile,vehicleType) && t.place.IsAccepting();
		}).Map(function(t) {
			//t.score = Place.AdjustAcceptingPlaceScore(t.score,t.place,t.cargo);
			return t;
		});
		return hgArray.array;
/*		return hgArray.Sort(function(a,b) {
			return b.score - a.score;
		}).array;*/
	}
	static function SearchAdditionalAcceptingPlaces(cargos, srcTiles ,lastAcceptingTile, maxDistance) {
		
		local hgArray = null;
		
		local srcTilesScores = [];
		foreach(tile in srcTiles) {
			srcTilesScores.push([tile, HgTile(lastAcceptingTile).DistanceManhattan( HgTile(tile))]);
		}
		hgArray = Place.GetAcceptingPlaceDistance(cargos[0],lastAcceptingTile,maxDistance).Filter(function(placeDistance) : (cargos) {
			foreach(cargo in cargos) {
				if(!placeDistance[0].IsCargoAccepted(cargo)) {
					return false;
				}
			}
			if(placeDistance[0] instanceof TownCargo) {
				return AITown.GetPopulation(placeDistance[0].town) >= 1500;
			}
			return true;
		}).Map(function(placeDistance) : (lastAcceptingTile, srcTilesScores)  {
			local t = {};
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			t.cost <- HgTile(lastAcceptingTile).GetPathFindCost(HgTile(t.place.GetLocation()));
			
			local score = 0;
			foreach(tileScore in srcTilesScores) {
				score += (t.place.DistanceManhattan(tileScore[0]) - tileScore[1]);// * 10000 / t.cost;
			}
			t.score <- score;
			return t;
		}).Filter(function(t):(lastAcceptingTile) {
			return 40 <= t.distance && 50 <= t.score && t.cost < 300 && !Place.IsNgPathFindPair(t.place,lastAcceptingTile,AIVehicle.VT_RAIL) && t.place.IsAccepting();
		}).Map(function(t) {
			return [t.place,t.score/*Place.AdjustAcceptingPlaceScore(t.score,t.place,t.cargo)*/];
		});
		return hgArray.Sort(function(a,b) {
				return b[1] - a[1];
			}).array;
		
	}
	
	static function GetLastMonthProduction(industry,cargo) {
		return PlaceProduction.Get().GetLastMonthProduction(industry,cargo);
	}
	
	function GetGId() {
		return Id();
	}
	
	function DistanceManhattan(tile) {
		return HgTile(GetLocation()).DistanceManhattan(HgTile(tile));
	}
	
	function GetStationGroups() {
		local result = {};
		foreach(hgStaion in GetStations()) {
			result[hgStaion.stationGroup] <- hgStaion.stationGroup;
		}
		return result;
	}
	
	function IsNearAnyOneNeeds() {
		foreach(cargo in GetAccepting().GetCargos()) {
			if(Place.SearchNearProducingPlaces(cargo, this.GetLocation(), 200).Count() >= 1) {
				return true;
			}
		}
		return false;
	}
	
	function IsNearAllNeeds() {
		return IsNearAllNeedsExcept(null);
	}
	
	function IsNearAllNeedsExcept(expectCargo) {
		local lack = false;
		foreach(cargo in GetAccepting().GetCargos()) {
			if(cargo == expectCargo) {
				continue;
			}
			if(Place.SearchNearProducingPlaces(cargo, this.GetLocation(), 200).Count() == 0) {
				lack = true;
			}
		}
		return !lack;
	}
	
	function IsTreatCargo(cargo) {
		foreach(eachCargo in GetCargos()) {
			if(eachCargo == cargo) {
				return true;
			}
		}
		return false;
	}
	
	function IsAcceptingAndProducing(cargo) {
		return GetAccepting().IsTreatCargo(cargo) && GetProducing().IsTreatCargo(cargo);
	}
	
	function CanUseNewRoute(cargo, vehicleType) {
		if(vehicleType == AIVehicle.VT_AIR) {
			return true;
		}
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(vehicleType != AIVehicle.VT_ROAD && route.GetVehicleType() == AIVehicle.VT_ROAD) {
				continue;
			}
			if(route.IsOverflowPlace(this)) {
				continue;
			}
			return false;
		}
		return true;
	}
	
	function CanUseTransferRoute(cargo, vehicleType) {
		/*
		if(vehicleType == AIVehicle.VT_RAIL) { // 今のところreturn route用のみなので無条件でOK
			return true;
		}*/
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(route.IsOverflowPlace(this)) {
				continue;
			}
			if(route.GetVehicleType() == AIVehicle.VT_ROAD) {
				continue;
			}
			return false;
		}
		return true;
	}
	
	function GetRoutes(cargo = null) {
		local result = [];
		result.extend(GetProducing().GetRoutesUsingSource(cargo));
		result.extend(GetAccepting().GetRoutesUsingDest(cargo));
		return result;
	}
	
	function GetRoutesUsingSource(cargo = null) {
		if(cargo == null) {
			return PlaceDictionary.Get().GetRoutesBySource(this);
		}
	
		local result = []
		foreach(route in PlaceDictionary.Get().GetRoutesBySource(this)) {
			if(route.cargo == cargo) {
				result.push(route);
			}
		}
		return result;
	}
	
	function GetRouteCountUsingSource(cargo = null) {
		local result = 0;
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(!route.IsTownTransferRoute()) {
				result ++;
			}
		}
		return result;
	}
	
	function GetSourceStationGroups(cargo = null) {
		local table = {};
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(route.srcHgStation.place.IsSamePlace(this)) {
				table.rawset(route.srcHgStation.stationGroup,0);
			}
			if(route.destHgStation.place.IsSamePlace(this)) {
				table.rawset(route.destHgStation.stationGroup,0);
			}
		}
		return HgTable.Keys(table);
	}
	
	function GetRoutesUsingDest(cargo = null) {
		if(cargo == null) {
			return PlaceDictionary.Get().GetRoutesByDest(this);
		}
		
		local result = []
		foreach(route in PlaceDictionary.Get().GetRoutesByDest(this)) {
			if(route.cargo == cargo) {
				result.push(route);
			}
		}
		return result;
	}
	
	function CanUseTrainSource() {
		if(this instanceof TownCargo) {
			return true;
		} else {
			return IsIncreasable();
		}
	}
	
	
	
	function IsCargoNotAcceptedRecently(cargo) {
		if(!IsCargoAccepted(cargo)) {
			return false;
		}
		foreach(route in PlaceDictionary.Get().GetRoutesByDestCargo(this, cargo)) {
			if(route.lastDestClosedDate != null && route.lastDestClosedDate > AIDate.GetCurrentDate() - 365) {
				return;
			}
		}
		return false;
	}
	
	function AddStation(station) {
		local placeId = Id();
		if(!placeStationDictionary.rawin(placeId)) {
			placeStationDictionary[placeId] <- [station];
		} else {
			placeStationDictionary[placeId].push(station);
		}
	}
	
	
	function RemoveStation(station) {
		ArrayUtils.Remove( placeStationDictionary[Id()], station );
	}
	
	function GetStations() {
		local placeId = Id();
		if(placeStationDictionary.rawin(placeId)) {
			return placeStationDictionary[placeId];
		} else {
			return [];
		}
	}
	
	function GetExpectedProduction(cargo, vehicleType) {
		local production = GetLastMonthProduction(cargo);
		local placeProduction = PlaceProduction.Get();
		if(!HogeAI.Get().roiBase && HogeAI.Get().firs && vehicleType == AIVehicle.VT_RAIL) {
			local inputableProduction = 0;
			local allCargosAvailable = true;
			local acceptingCargos = GetAccepting().GetCargos();
			foreach(acceptingCargo in acceptingCargos) {
				local availableProduction = placeProduction.GetArroundProductionCargo(GetLocation(), acceptingCargo);
				if(availableProduction == 0) {
					allCargosAvailable = false;
				}
				inputableProduction += availableProduction;
			}
			if(IsProcessing()) {
				if(acceptingCargos.len() >= 2) {
					if(allCargosAvailable) {
						production = max(production, inputableProduction * 2);
					} else {
						production = max(production, inputableProduction / 2);
					}
				}
			} else if(acceptingCargos.len() >= 1) {
				production = inputableProduction >= 1 ? production * 3 : production;
			}
		}
		if(!HogeAI.Get().roiBase && !HogeAI.Get().ecs && !HogeAI.Get().firs && IsProcessing() && vehicleType == AIVehicle.VT_RAIL) {
			local inputableProduction = 0;
			foreach(acceptingCargo in GetAccepting().GetCargos()) {
				inputableProduction += placeProduction.GetArroundProductionCargo(GetLocation(), acceptingCargo);
			}
			production = max(production, inputableProduction / 2);
		}
		if(HogeAI.Get().ecs /*GetUsableMoney() >= HogeAI.Get().GetInflatedMoney(2000000)*/ && IsRaw() && production >= 1) {
			// 4d656f9f 00:coal mine 300 / 02:sand pit 900
			// 4d656f9c 08:oil well 750 / 09:oil rig 375
			// 4d656f94 0d:iron ore 150 / 18:bauxite 150
			// 4d656f95 12:forest 192
			// 4d656f97 1e:farm 168(cereals) 264(fibre crops)  / 22:fruit plantation    / 1d:fishing grounds 350
			local cargoLabel = AICargo.GetCargoLabel(cargo);
			local industryTraits = GetIndustryTraits();
			local industryType = AIIndustry.GetIndustryType(this.industry);
			local ecsRaw = true;
			if(industryTraits == "COAL,/VEHI," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f9f, 0x00)*/) {
				production = max(300, production);
			} else if(industryTraits == "SAND,/VEHI,") {
				production = max(900, production);
			} else if(industryTraits == "OIL_,/" /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f9c, 0x08)*/) {
				production = max(750, production);
			} else if(industryTraits == "OIL_,PASS,/PASS," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f9c, 0x09)*/) {
				if(cargoLabel == "OIL_") {
					production = max(375, production);
				}
			} else if(industryTraits == "IORE,/VEHI," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f94, 0x0d)*/) {
				production = max(150, production);
			} else if(industryTraits == "AORE,/VEHI," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f94, 0x18)*/) {
				production = max(150, production);
			} else if(industryTraits == "WOOD,/VEHI," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f95, 0x12)*/) {
				production = max(192, production);
			} else if(industryTraits == "FICR,CERE,/VEHI,FERT," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f97, 0x1e))*/) {
				if(cargoLabel == "CERE") {
					production = max(168, production);
				} else if(cargoLabel == "FICR") {
					production = max(264, production);
				}
			} else if(industryTraits == "FISH,PASS,/PASS," /*industryType == AIIndustryType.ResolveNewGRFID(0x4d656f97, 0x1d)*/) {
				if(cargoLabel == "FISH") {
					production = max(350, production);
				}
			} else {
				ecsRaw = false;
			}
			if(ecsRaw) {
				if(vehicleType == AIVehicle.VT_RAIL) {
					production *= 2;
				}
				if(vehicleType == AIVehicle.VT_ROAD)  {
					production /= 2;
				}
				if(HogeAI.Get().roiBase) {
					production /= 3;
				}
			}
		}
		/*
		local productionInfo = placeProduction.GetCargoProductionInfos()[cargo].pieceInfos[placeProduction.GetPieceIndex(GetLocation())];
		if(productionInfo != null) {
			if(!productionInfo.usable) {
				return 0;
			} else {
				return production + max(0, productionInfo.sum - production) / 2;
			}
		}*/
		/*
		
		
		if(HogeAI.Get().IsDebug() && HogeAI.Get().IsRich() && GetIndustryTraits() == "GOOD,/STEL,GRAI,LVST,") {
			result = max(300, result);
		}*/
		return production;
	}
	
	function IsEcsHardNewRouteDest() {
		if(HogeAI.Get().ecs && this instanceof HgIndustry && this.GetCargos().len() >= 2) { // ecsのマルチで受け入れるindustryは生産条件を満たすのが困難な事が多い。
			local traits = this.GetIndustryTraits();
			if(!(traits == "WOOL,LVST,/FICR,FISH,CERE," || traits=="FERT,FOOD,/OLSD,FRUT,CERE," || traits=="/OIL_,COAL," || traits=="GOOD,/DYES,GLAS,STEL,")) {
				return true;
			}
		}
		return false;
	}
	
	function IsNearWater(cargo) {
		local placeDictionary = PlaceDictionary.Get();
		local id = Id()+":"+cargo;
		local result;
		if(!placeDictionary.nearWaters.rawin(id)) {
			result = CheckNearWater(cargo);
			placeDictionary.nearWaters[id] <- result;
			return result;
		} else {
			return placeDictionary.nearWaters[id];
		}
	}
	
	function CheckNearWater(cargo) {		
		//HgLog.Info("CheckNearWater "+this+" "+AICargo.GetName(cargo));
		if(IsBuiltOnWater()) {
			return true;
		}

		local dockRadius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
		local tile;
		local gen = GetTiles(dockRadius,cargo)
		while((tile = resume gen) != null) {
			if(AITile.IsCoastTile(tile) || AITile.IsSeaTile(tile)) {
				return true;
			}
		}
		return false;
	}
	
	
	function GetAllowedAirportLevel(airportType/*必要最小限のaiportType*/, cargo) {
		local location = GetNoiseLevelLocation();
		local allowedNoise = GetAllowedNoise(airportType);
		local result = 0;
		foreach(airportTraints in Air.Get().GetAvailableAiportTraits()) {
			if(allowedNoise >= AIAirport.GetNoiseLevelIncrease(location, airportTraints.airportType)) {
				result = max(airportTraints.level, result);
			}
		}
		foreach(station in HgStation.SearchStation(this, AIStation.STATION_AIRPORT, cargo, IsAccepting())) { 
			if(station.CanShareByMultiRoute(airportType)) {
				result = max(station.GetAirportTraits().level, result)
			}
		}
		return result;
	}

	function CanBuildAirport(airportType, cargo) {
		local key = Id() + "-" + airportType + "-" + cargo;
		local cache = Place.canBuildAirportCache;
		if(cache.rawin(key)) {
			return cache[key];
		}
		local result = _CanBuildAirport(airportType, cargo);
		cache[key] <- result;
		return result;
	}
	
	function _CanBuildAirport(airportType, cargo) {
		local location = GetNoiseLevelLocation();
		local noiseLevelIncrease = AIAirport.GetNoiseLevelIncrease(location, airportType);
		if( GetAllowedNoise(airportType) >= noiseLevelIncrease ) {
			return true;
		}
		foreach(station in HgStation.SearchStation(this, AIStation.STATION_AIRPORT, cargo, IsAccepting())) { 
			if(station.CanShareByMultiRoute(airportType) && Air.Get().IsCoverAiportType(station.GetAirportType(),airportType)) {
				return true;
			}
		}
		return false;
	}
	
	function _tostring() {
		return GetName();
	}
}

class HgIndustry extends Place {
	static closedIndustries = {};
	
	industry = null;
	isProducing = null;
	
	constructor(industry,isProducing) {
		this.industry = industry;
		this.isProducing = isProducing;
	}
	
	function Save() {
		local t = {};
		t.name <-  "HgIndustry";
		t.industry <- industry;
		t.isProducing <- isProducing;
		return t;
	}
	
	function Id() {
		return "Industry:" + industry + ":" + isProducing;
	}
	
	function IsSamePlace(other) {
		if(other == null) {
			return false;
		}
		if(!(other instanceof HgIndustry)) {
			return false;
		}
		return industry == other.industry && isProducing == other.isProducing;
	}
	
	function GetName() {
		return AIIndustry.GetName(industry);
	}
	
	function GetLocation() {
		return AIIndustry.GetLocation(industry);
	}
	
	function GetRadius() {
		return 3;
	}
	
	function GetTiles(coverageRadius,cargo) {
		local list = GetTileList(coverageRadius);
		if(IsAcceptingAndProducing(cargo)) {
			list.Valuate( AITile.GetCargoProduction,cargo,1,1,coverageRadius);
			list.RemoveValue(0)
			list.Valuate( AITile.GetCargoAcceptance,cargo,1,1,coverageRadius);
			list.RemoveBelowValue(8)
		} else if(isProducing) {
			list.Valuate( AITile.GetCargoProduction,cargo,1,1,coverageRadius);
			list.RemoveValue(0)
		} else {
			list.Valuate( AITile.GetCargoAcceptance,cargo,1,1,coverageRadius);
			list.RemoveBelowValue(8)
		}
		
		foreach(k,v in list) {
			yield k;
		}
		return null;
	}
	
	function GetTileList(coverageRadius) {
		if(isProducing) {
			return AITileList_IndustryProducing(industry, coverageRadius);
		} else {
			return AITileList_IndustryAccepting(industry, coverageRadius);
		}
	}
	
	
	
	function GetLastMonthProduction(cargo) {
		local result = Place.GetLastMonthProduction(industry,cargo); 
		
		return result;
	}
	
	function IsClosed() {
		return closedIndustries.rawin(industry); // Closeしてすぐに同一IDで新しいのが立つことがあるので信用できない
	}
	
	function GetCargos() {
		if(isProducing) {
			return HgArray.AIListKey(AICargoList_IndustryProducing(industry)).array;
		} else {
			return HgArray.AIListKey(AICargoList_IndustryAccepting(industry)).array;
		}
	}
	
	function IsCargoAccepted(cargo) {
		return AIIndustry.IsCargoAccepted(industry, cargo) == AIIndustry.CAS_ACCEPTED;
	}
	
	function IsAccepting() {
		return !isProducing;
	}
	
	function IsProducing() {
		return isProducing;
	}
	
	function GetAccepting() {
		if(isProducing) {
			return HgIndustry(industry,false);
		} else {
			return this;
		}
	}
	
	function GetProducing() {
		if(isProducing) {
			return this;
		} else {
			return HgIndustry(industry,true);
		}
	}
	
	// 入力すると出力が増えるかどうか or 入力が無くて勝手に増えるかどうか
	function IsIncreasable(inputCargo = null) {
		if(HogeAI.Get().ecs || HogeAI.Get().yeti) {
			return true;
		}
		local industryType = AIIndustry.GetIndustryType(industry);
		local acceptingCargos = HgArray(GetAccepting().GetCargos());
		if(acceptingCargos.Count() == 0 && !AIIndustryType.ProductionCanIncrease(industryType)) {
			return false;
		}
		if(!AIIndustryType.IsProcessingIndustry (industryType) && !AIIndustryType.IsRawIndustry(industryType)) {
			foreach(producingCargo in GetProducing().GetCargos()) {
				if(acceptingCargos.Contains(producingCargo)) {
					return false; // 入出力に同じものがある(例:銀行)
				}
			}
		}
		if(inputCargo != null) {
		}
		
		return true;
	}

	function IsIncreasableInputCargo(inputCargo) {
		return !HgArray(GetProducing().GetCargos()).Contains(inputCargo);// 油田の旅客をはじく
	}
	
	function IsRaw() {
		local traits = GetIndustryTraits();
		if(traits == "BDMT,/COAL,") { // Brick works(ECS)
			return false;
		}
		local industryType = AIIndustry.GetIndustryType(industry);
		return AIIndustryType.IsRawIndustry(industryType);
	}
	
	function IsProcessing() {		
		local traits = GetIndustryTraits();
		if(traits == "BDMT,/COAL,") { // Brick works(ECS)
			return true;
		}
		local industryType = AIIndustry.GetIndustryType(industry);
		return AIIndustryType.IsProcessingIndustry(industryType);
	}
	
	function GetStockpiledCargo(cargo) {
		return AIIndustry.GetStockpiledCargo(industry, cargo);
	}
		
	function IsBuiltOnWater() {
		return AIIndustry.IsBuiltOnWater(industry);
	}
	
	function HasStation(vehicleType) {
		return vehicleType == AIVehicle.VT_WATER && AIIndustry.HasDock(industry);
	}

	function GetStationLocation(vehicleType) {
		if(vehicleType == AIVehicle.VT_WATER) {
			if(AIIndustry.HasDock(industry)) {
				return AIIndustry.GetDockLocation(industry);
			}
		}
		return null;
	}
	
	function GetLastMonthTransportedPercentage(cargo) {
		return AIIndustry.GetLastMonthTransportedPercentage(industry, cargo);
	}
	
	function GetIndustryTraits() {
		local industryType = AIIndustry.GetIndustryType(industry);
		if(!AIIndustryType.IsValidIndustryType(industryType)) {
			return ""; // たぶんcloseしてる
		}
		local s = "";
		foreach(cargo,v in AIIndustryType.GetProducedCargo(industryType)) {
			s += AICargo.GetCargoLabel(cargo)+",";
		}
		s += "/";
		foreach(cargo,v in AIIndustryType.GetAcceptedCargo(industryType)) {
			s += AICargo.GetCargoLabel(cargo)+",";
		}
		return s;
	}
	
	function GetNoiseLevelLocation() {
		return GetLocation();
	}
	
	function GetAllowedNoise(airportType) {
		local town = AIAirport.GetNearestTown(GetNoiseLevelLocation(), airportType);
		return AITown.GetAllowedNoise(town);
	}

	function _tostring() {
		return "Industry:" + GetName() + ":" + isProducing;
	}
}

class TownCargo extends Place {
	town = null;
	cargo = null;
	isProducing = null;
	
	constructor(town,cargo,isProducing) {
		this.town = town;
		this.cargo = cargo;
		this.isProducing = isProducing;
	}

	function Save() {
		local t = {};
		t.name <- "TownCargo";
		t.town <- town;
		t.cargo <- cargo;
		t.isProducing <- isProducing;
		return t;
	}

	function IsSamePlace(other) {
		if(other == null) {
			return false;
		}
		if(!(other instanceof TownCargo)) {
			return false;
		}
		return town == other.town;
	}
	
	function Id() {
		return "TownCargo:" + town + ":" + cargo + ":" + isProducing;
	}

	function GetName() {
		return AITown.GetName(town);
	}
	
	function GetLocation() {
		return AITown.GetLocation(town);
	}
	

	function GetCargos() {
		if(cargo==null) {
			return [];
		}
		return [cargo];
	}
	
	function GetRadius() {
		return max(3,(pow(AITown.GetPopulation(town), 0.33) * 0.67).tointeger());
//		return (sqrt(AITown.GetPopulation(town))/5).tointeger() + 2;
	}
	
	function GetTiles(coverageRadius,cargo) {
		if(cargo != this.cargo) {
			HgLog.Warning("Cargo not match. expect:"+AICargo.GetName(this.cargo)+" but:"+AICargo.GetName(cargo));
			return null;
		}
		
		local maxRadius = GetRadius() + coverageRadius;
		local tiles = Rectangle.Center(HgTile(GetLocation()),maxRadius).GetTilesOrderByOutside();
		if(IsProducing()) {
			tiles.reverse();
			local bottom = CargoUtils.IsPaxOrMail(cargo) ? 8 : 1;
			foreach(tile in tiles) {
				if(AITile.GetCargoProduction(tile, cargo, 1, 1, coverageRadius) >= bottom) {
					yield tile;
				}
			}
		} else {
			local bottom = AICargo.GetTownEffect (cargo) == AICargo.TE_GOODS ? 8 : 8;
			foreach(tile in tiles) {
				if(AITile.GetCargoAcceptance(tile, cargo, 1, 1, coverageRadius) >= bottom) {
					yield tile;
				}
			}
		}
		return null;
/*		
		result.Valuate(HogeAI.IsBuildable);
		result.KeepValue(1);
		result.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, coverageRadius);
		result.KeepAboveValue(17);
		return result;*/
	}
	
	function GetRectangle() {
		return Rectangle.Center(HgTile(GetLocation()),GetRadius());
	}
	
	
	function GetNotUsedProductionMap(exceptPlatformTiles) {
		local result = {};
		local railRadius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local roadRadius = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
		local waterRadius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
	
		local used = {};
		local exceptPlatformMap = {};
		foreach(t in exceptPlatformTiles) {
			exceptPlatformMap.rawset(t,0);
		}
		
		foreach(tile in Rectangle.Center(HgTile(GetLocation()),GetRadius()).GetTiles()) {
			if(!AITile.IsStationTile(tile)) {
				continue;
			}
			if(!AICompany.IsMine(AITile.GetOwner(tile))) { // ライバル企業を避ける場合はこのチェックは不要
				continue;
			}
			local statoinId = AIStation.GetStationID(tile);
			if(!exceptPlatformMap.rawin(tile)) { // 作ったばかりでまだ評価が無いplatformを除外する
				if(!AIStation.HasCargoRating(statoinId, cargo)) {
					continue;
				}
				if(AIStation.GetCargoRating(statoinId, cargo) < 40) {
					continue;
				}
			}
			local radius;
			if(AIRail.IsRailStationTile(tile)) {
				radius = railRadius;
			} else if(AIRoad.IsRoadStationTile(tile)) {
				radius = roadRadius;
			} else if(AIAirport.IsAirportTile(tile)) {
				local airportType = AIAirport.GetAirportType(tile)
				radius = AIAirport.GetAirportCoverageRadius(airportType);
			} else if(AIMarine.IsDockTile(tile)) {
				radius = waterRadius;
			} else {
				continue; // unknown station
			}
			foreach(t in Rectangle.Center(HgTile(tile),radius).GetTiles()) {
				used.rawset(t,0);
			}
		}
		foreach(tile in Rectangle.Center(HgTile(GetLocation()),max(6, GetRadius() - 6)).GetTiles()) {
			if(used.rawin(tile)) {
				continue;
			}
			if(AITile.GetCargoProduction(tile, cargo, 1, 1, 0) >= 1) {
				result.rawset(tile,AITile.GetCargoAcceptance(tile, cargo, 1, 1, 0));
			}
		}
		return result;
	}

	function GetExpectedProduction(cargo, vehicleType) {
		local production = GetLastMonthProduction(cargo);
		
		switch(vehicleType) {
			case AIVehicle.VT_RAIL:
				return production * 3 / 2;
			case AIVehicle.VT_ROAD:
				return production;
			case AIVehicle.VT_AIR:
				return production * 3 / 2;
			case AIVehicle.VT_WATER:
				return production * 3 / 2;
		}
		HgLog.Error("unknown vt:"+vehicleType);
	}
	
	function GetLastMonthProduction(cargo) {
		//if(RoadRoute.IsTooManyVehiclesForSupportRoute(RoadRoute)) {
		local minValue = cargo == HogeAI.Get().GetPassengerCargo() ? 600 : 300;
		return min(minValue, AITown.GetLastMonthProduction( town, cargo ) / 3);
		/*} else {
			return AITown.GetLastMonthProduction( town, cargo ) * 2 / 5;
		}*/
	}
	
	function GetLastMonthTransportedPercentage(cargo) {
		return AITown.GetLastMonthTransportedPercentage(town, cargo);
	}
	
	function IsAccepting() {
		return !isProducing;
/*		//TODO: STATION_TRUCK_STOP以外のケース
		local gen = this.GetTiles(AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP),cargo);
		return resume gen != null;*/
	}
	
	function IsCargoAccepted(cargo) {
		if(cargo == this.cargo) {
			return true;
		}
		local townEffect = AICargo.GetTownEffect(cargo);
		if(townEffect == AICargo.TE_GOODS) {
			return AITown.GetPopulation(town) >= 1500;
		}
		if(townEffect == AICargo.TE_PASSENGERS || townEffect == AICargo.TE_MAIL) {
			return AITown.GetPopulation(town) >= 200;
		}
		if(townEffect == AICargo.TE_WATER || townEffect == AICargo.TE_FOOD ) {
			return AITown.GetPopulation(town) >= 1000;
		}
		return false;
	}

	function IsClosed() {
		return false;
	}
	
	function IsProducing() {
		return isProducing;
	}	
	
	function GetAccepting() {
		if(!isProducing) {
			return this;
		} else {
			return TownCargo(town,cargo,false);
		}
	}

	function GetProducing() {
		if(isProducing) {
			return this;
		} else {
			if(Place.IsProducedByTown(cargo)) {
				return TownCargo(town,cargo,true);
			} else {
				return TownCargo(town,null,true);
			}
		}
	}

	function IsIncreasable() {
		return false;

	}
		
	function IsRaw() {
		return false;
	}
	
	function IsProcessing() {
		return false;
	}
	
	function GetStockpiledCargo(cargo) {
		return 0;
	}
	
	function IsBuiltOnWater() {
		return false;
	}

	function HasStation(vehicleType) {
		return false;
	}

	function GetStationLocation(vehicleType) {
		return null;
	}
	
	function GetNoiseLevelLocation() {
		return GetLocation() + GetRadius();
	}
	
	function GetAllowedNoise(airportType/*HgIndustryで使う*/) {
		return AITown.GetAllowedNoise(town) + (HogeAI.Get().isUseAirportNoise ? 1 : 0)/*離れれば空港建設できる事があるのでその分のバッファ*/;
	}
	
	
	function GetIndustryTraits() {
		return "";
	}
	
	
	function _tostring() {
		return "TownCargo:" + GetName() + ":" + AICargo.GetName(cargo) + ":" + isProducing;
	}
}


