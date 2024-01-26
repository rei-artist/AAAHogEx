
class PlaceProduction {
	static instance = GeneratorContainer(function() { 
		return PlaceProduction(); 
	});

	static function Get() {
		return PlaceProduction.instance.Get();
	}

	static PIECE_SIZE = 256;
	
	pieceNumX = null;
	pieceNumY = null;

	lastCheckMonth = null;
	history = null;
	currentProduction = null;
	cargoProductionInfos = null;
	
	constructor() {
		history = {};
		currentProduction = {};
		pieceNumX = AIMap.GetMapSizeX() / PlaceProduction.PIECE_SIZE + 1;
		pieceNumY = AIMap.GetMapSizeY() / PlaceProduction.PIECE_SIZE + 1;
	}
	
	static function Save(data) {
		data.placeProduction <- {
			lastCheckMonth = lastCheckMonth
			history = history
			currentProduction = currentProduction
		};
	}

	static function Load(data) {
		local t = data.placeProduction;
		lastCheckMonth = t.lastCheckMonth;
		history = t.history;
		currentProduction = t.currentProduction;
	}
	
	function GetCurrentMonth () {
		local currentDate = AIDate.GetCurrentDate();
		return (AIDate.GetMonth(currentDate)-1) + AIDate.GetYear(currentDate) * 12;
	}
	
	function Check() {
		local currentMonth = GetCurrentMonth();
		if(lastCheckMonth == null || lastCheckMonth < currentMonth) {
			foreach(cargo,v in AICargoList()) {
				local list = AIIndustryList_CargoProducing(cargo);
				list.Valuate(function(industry):(history,currentProduction,cargo) {
					local production = AIIndustry.GetLastMonthProduction(industry,cargo);
					local key = industry+"-"+cargo;
					if(history.rawin(key)) {
						history[key].push(production);
					} else {
						history.rawset(key, [production]);
					}
					currentProduction.rawset(key, -1);
					return 0;
				});
			}
			lastCheckMonth = currentMonth;
		}
/*			
			
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
		}*/
	}

	function GetLastMonthProduction(industry,cargo) {
		Check();
		local key = industry+"-"+cargo;
		if(!history.rawin(key)) {
			return 0;
		}
		if(currentProduction.rawin(key)) {
			local result = currentProduction[key];
			if(result != -1) {
				return result;
			}
		}
		local productions = history[key];
		local l = productions.len();
		if(l == 0) {
			return 0;
		}
		if(l > 12) {
			productions = productions.slice(l-12,l);
			history[key] = productions;
		}
		local sum = 0;
		foreach(p in productions) {
			sum += p;
		}
		local result = sum / productions.len();
		currentProduction.rawset(key,result);
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
			local placesList = Place.GetCargoProducingList(cargo);
			local places = placesList[0];
			local placeList = placesList[1];
			local info = {};
			local pieceInfos = array(pieceNumX * pieceNumY);
			result[cargo] <- {
				pieceInfos = pieceInfos
			};
			foreach(i,_ in placeList) {
				local place = places[i];
				local p = place.GetLastMonthProduction(cargo);
				if(p >= 50) {
					local pieceIndex = GetPieceIndex(place.GetLocation());
					local pieceInfo;
					if(pieceInfos[pieceIndex] == null) {
						pieceInfo = {
							sum = 0
							count = 0
							usable = true
							dirty = false
							places = []
						};
						pieceInfos[pieceIndex] = pieceInfo;
					} else {
						pieceInfo = pieceInfos[pieceIndex]
					}
					local usable = PlaceDictionary.Get().CanUseAsSource(place, cargo) && place.GetLastMonthTransportedPercentage(cargo) < 30;
					if(usable) {
						pieceInfo.sum += p;
						pieceInfo.count ++;
						pieceInfo.places.push(place.Id());
					}
				}
			}
		}
		return result;
	}
	
	function SetDirtyArround(location, cargo) {
		if(cargoProductionInfos == null) { // cargoProductionInfosが使われていないケース
			return;
		}
		local pieceInfos = GetCargoProductionInfos()[cargo].pieceInfos;
		foreach(index in GetArroundIndexes(location)) {
			local pieceInfo = pieceInfos[index];
			if(pieceInfo != null) {
				pieceInfo.dirty = true;
			}
		}
	}
	
	function SetDirty(location, cargo) {
		local pieceInfos = GetCargoProductionInfos()[cargo].pieceInfos;
		local pieceInfo = pieceInfos[GetPieceIndex(location)];
		if(pieceInfo != null) {
			pieceInfo.dirty = true;
		}
	}

	function IsDirtyArround(location, cargo) {
		if(cargoProductionInfos == null) { // cargoProductionInfosが使われていないケース
			return false;
		}
		local pieceInfos = GetCargoProductionInfos()[cargo].pieceInfos;
		foreach(index in GetArroundIndexes(location)) {
			local pieceInfo = pieceInfos[index];
			if(pieceInfo != null) {
				if(pieceInfo.dirty) {
					return true;
				}
			}
		}
		return false;
	}
	
	function GetArroundProductionCount(location, cargo) {
		local pieceInfos = GetCargoProductionInfos()[cargo].pieceInfos;
		local sum = 0;
		local count = 0;
		local places = [];
		local pieceIndex = GetPieceIndex(location);
		foreach(index in GetArroundIndexes(location)) {
			local pieceInfo = pieceInfos[index];
			local arround = index != pieceIndex;
			if(pieceInfo != null && pieceInfo.usable) {
				local div = arround && pieceInfo.count>=2 ? 2 : 1
				sum += pieceInfo.sum / div;
				count += pieceInfo.count / div;
				places.extend(pieceInfo.places);
			}
		}
		return [sum,count,places];
	}
	
	function GetArroundIndexes(location) {
		local pieceIndex = GetPieceIndex(location);
		local x = pieceIndex % pieceNumX;
		local y = pieceIndex / pieceNumX;
		local indexes = [];
		indexes.push(pieceIndex);
		if(x >= 1) {
			indexes.push(pieceIndex-1);
			// if(y < pieceNumY - 1) {
				// indexes.push(pieceIndex+pieceNumX-1);
			// }
		}
		if(y >= 1) {
			indexes.push(pieceIndex-pieceNumX);
			// if(x >= 1) {
				// indexes.push(pieceIndex-pieceNumX-1);
			// }
		}
		if(x < pieceNumX - 1) {
			indexes.push(pieceIndex+1);
			// if(y >= 1) {
				// indexes.push(pieceIndex-pieceNumX+1);
			// }
		}
		if(y < pieceNumY - 1) {
			indexes.push(pieceIndex+pieceNumX);
			// if(x < pieceNumX - 1) {
				// indexes.push(pieceIndex+pieceNumX+1);
			// }
		}
		return indexes;
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
		local srcPlace = route.srcHgStation.place;
		local destPlace = route.destHgStation.place;
	
		if(srcPlace != null) {
			AddRouteTo(sources, srcPlace, route);
		}
		if(destPlace != null) {
			if(route.IsBiDirectional()) {
				AddRouteTo(sources, destPlace.GetProducing(), route);
			} else {
				AddRouteTo(dests, destPlace, route);
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
		local id = place.GetFacilityId();
		if(dictionary.rawin(id)) {
			ArrayUtils.Remove(dictionary[id], route);
		}
	}
	
	function AddRouteTo(dictionary, place, route) {
		local id = place.GetFacilityId();
		if(!dictionary.rawin(id)) {
			dictionary[id] <- [];
		}
		ArrayUtils.Add(dictionary[id], route);
	}
	
	function GetRoutes(dictionary, place) {
		local id = place.GetFacilityId();
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

	function CanUseAsSource(place, cargo) {
		/*
		if(HogeAI.Get().stockpiled) { // Railでも受け入れきれないケースがあるので禁止しない=>IsOverflowでわかるのでは？
			return true;
		}*/
		if(!HogeAI.Get().canUsePlaceOnWater && place.IsBuiltOnWater() && !place.IsNearLand(cargo)) {
			return false;
		}
		
		local routes = GetRoutesBySource(place);
		foreach(route in routes) {
			if(route.HasCargo(cargo) 
					&& (route.GetVehicleType() == AIVehicle.VT_RAIL || route.GetVehicleType() == AIVehicle.VT_WATER) 
					&& !route.IsOverflow() 
					&& !route.IsClosed()) {
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
	
	function GetUsedAsSourceByPriorityRoute(place,cargo) {
		local result = [];
		foreach(route in GetRoutesBySource(place)) {
			local vehicleType = route.GetVehicleType();
			if(((vehicleType == AIVehicle.VT_RAIL && !route.IsSingle()) || vehicleType == AIVehicle.VT_AIR) && route.HasCargo(cargo)) {
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

}


class Place {

	static removedDestPlaceDate = [];
	static ngPathFindPairs = {};
	static productionHistory = [];
	static needUsedPlaceCargo = [];
	static ngPlaces = {};
	static ngCandidatePlaces = {};
	static placeStationDictionary = {};
	static canBuildAirportCache = {};
	static notUsedProducingPlaceCache = ExpirationTable(90);
	static cargoProducingListCache = ExpirationTable(180);
	static producingPlaceDistanceListCache = ExpirationTable(90);
	static expectedProductionCache = ExpirationRawTable(30);
	static currentExpectedProductionCache = ExpirationRawTable(30);
	static supportEstimatesCache = ExpirationTable(360);
	static usedOtherCompanyEstimationCache = ExpirationRawTable(180);
	static nearLandCache = {};
	static maybeNotUsed = {};

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
		

		data.industryClosedDate <- HgIndustry.industryClosedDate;
		
		
		PlaceProduction.Get().Save(data);

		data.nearWaters <- PlaceDictionary.Get().nearWaters;
		data.ngPlaces <- Place.ngPlaces;
		data.ngCandidatePlaces <- Place.ngCandidatePlaces;
		data.maybeNotUsed <- Place.maybeNotUsed;
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

		HgIndustry.industryClosedDate.clear();
		foreach(k,v in data.industryClosedDate){
			HgIndustry.industryClosedDate[k] <- v;
		}
		PlaceProduction.Get().Load(data);
		
		PlaceDictionary.Get().nearWaters = data.nearWaters;
		if(data.rawin("ngPlaces")) {
			HgTable.Extend(Place.ngPlaces, data.ngPlaces);
		}
		if(data.rawin("ngCandidatePlaces")) {
			HgTable.Extend(Place.ngCandidatePlaces, data.ngCandidatePlaces);
		}
		if(data.rawin("maybeNotUsed")) {
			HgTable.Extend(Place.maybeNotUsed, data.maybeNotUsed);
		}
	}
	
	static function Load(t) {		
		switch(t.name) {
			case "HgIndustry":
				return HgIndustry( t.industry, t.isProducing, t.date );
			case "TownCargo":
				return TownCargo( t.town, t.cargo, t.isProducing );
			case "Coast":
				return CoastPlace( t.location );
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
			limit = AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES ? AIDate.GetCurrentDate() + 60 : AIDate.GetCurrentDate() + 1000; 
		}
		Place.ngPlaces.rawset(facility.GetLocation() + ":" + cargo +":" + vehicleType, limit);
		HgLog.Info("AddNgPlace:"+facility.GetName()+"["+AICargo.GetName(cargo)+"] vt:"+vehicleType+" limit:"+DateUtils.ToString(limit));
	}
	
	static function RemoveNgPlace(facility, cargo, vehicleType) {
		if(Place.ngPlaces.rawdelete(facility.GetLocation() + ":" + cargo +":" + vehicleType) != null) {
			HgLog.Info("RemoveNgPlace:"+facility.GetName()+"["+AICargo.GetName(cargo)+"] vt:"+vehicleType);
		}
	}

	static function IsNgPlace(facility, cargo, vehicleType) {
		local key = facility.GetLocation() + ":" + cargo +":" + vehicleType;
		if(Place.ngPlaces.rawin(key)) {
			local date = Place.ngPlaces[key];
			if(date == -1) {
				return true;
			} else {
				if( AIDate.GetCurrentDate() < date ) {
					return true;
				}
			}
		}
		local checkOtherCompany = false;
		if(facility instanceof HgIndustry && AIIndustry.GetAmountOfStationsAround(facility.industry) >= 1) {
			if(HogeAI.Get().IsAvoidSecondaryIndustryStealing()) {
				if( facility.IsProcessing() && facility.GetRoutes().len() == 0) {
					local tileList = AITileList_IndustryAccepting(facility.industry,5);
					tileList.Valuate(AITile.IsStationTile);
					tileList.RemoveValue(0);
					tileList.Valuate(AITile.GetOwner);
					tileList.RemoveValue(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF));
					if(tileList.Count() >= 1) {
						HgLog.Info("Detect SecondaryIndustryStealing:"+facility.GetName());
						foreach(vt in Route.allVehicleTypes) {
							Place.AddNgPlace(facility, cargo, vt, 10 * 365);
						}
						return true;
					}
				}
			
				/*
				if(AIIndustry.GetAmountOfStationsAround(facility.industry) >= 1 && facility.GetRoutes().len() == 0) { //TODO: これでは範囲内にある別施設用の自分のstationに反応してしまう
					HgLog.Info("Detect SecondaryIndustryStealing:"+facility.GetName());
					return true;
				}*/
			}
			if(Place.ExistsOtherHoge(facility)) {
				HgLog.Info("ExistsOtherHoge "+facility.GetName());
				foreach(vt in Route.allVehicleTypes) {
					Place.AddNgPlace(facility, cargo, vt, 10 * 365);
				}
				return true;
			}
		}
		
		return false;
	}
	
	
	static function ExistsOtherHoge(facility) {
		if(HogeAI.Get().IsDebug()) {
			return false;
		}
		if(facility instanceof HgIndustry && facility.GetRoutes().len() == 0) {
			if(AIIndustry.GetAmountOfStationsAround(facility.industry) >= 1) {
				local tileList = AITileList_IndustryAccepting(facility.industry,5);
				tileList.Valuate(AITile.IsStationTile);
				tileList.RemoveValue(0);
				tileList.Valuate(AITile.GetOwner);
				tileList.RemoveValue(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF));
				local companies = {};
				foreach(tile,company in tileList) {
					companies.rawset(company,0);
				}
				foreach(company,_ in companies) {
					local name = AICompany.GetName(company);
					if(name != null && name.find("AAAHogEx") != null) {
						return true;
					}
				}
			}
		}
		return false;
	}
	
	static function AddNgCandidatePlace(place, cargo, days = 300) {
		local limitDate = AIDate.GetCurrentDate() + days;
		Place.ngCandidatePlaces.rawset(place.GetLocation() + ":" + cargo, limitDate);
		HgLog.Info("AddNgCandidatePlace:"+place.GetName()+"["+AICargo.GetName(cargo)+"] limit:"+DateUtils.ToString(limitDate));
	}

	static function IsNgCandidatePlace(place, cargo) {
		local key = place.GetLocation() + ":" + cargo;
		if(Place.ngCandidatePlaces.rawin(key)) {
			local date = Place.ngCandidatePlaces[key];
			if(date == -1) {
				return true;
			} else {
				return AIDate.GetCurrentDate() < date;
			}
		}
		return false;
	}
	
	static function AddNgPathFindPair(from, to, vehicleType, limitDay = null) {
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			return;
		}
		local fromTile = typeof from == "integer" ? from : from.GetLocation();
		local toTile = typeof to == "integer" ? to : to.GetLocation();
		
		Place.ngPathFindPairs.rawset(fromTile+"-"+toTile+"-"+vehicleType,limitDay != null ? AIDate.GetCurrentDate() + limitDay : true);
	}
	
	static function IsNgPathFindPair(from, to, vehicleType) {
		local fromTile = typeof from == "integer" ? from : from.GetLocation();
		local toTile = typeof to == "integer" ? to : to.GetLocation();
		local key = fromTile+"-"+toTile+"-"+vehicleType;
		if(!Place.ngPathFindPairs.rawin(key)) {
			return false;
		}
		local limitDate = Place.ngPathFindPairs[key];
		if(limitDate == true) {
			return true;
		}
		local result = limitDate > AIDate.GetCurrentDate();
		if(!result) {
			Place.ngPathFindPairs.rawdelete(key);
		}
		return result;
	}
	
	static function AddNeedUsed(place, cargo) {
		Place.needUsedPlaceCargo.push([place, cargo]);
	}
	
	static function GetCargoProducingList( cargo ) {
		if(Place.cargoProducingListCache.rawin(cargo)) {
			return Place.cargoProducingListCache.rawget(cargo);
		}
		local places = Place.GetCargoProducing( cargo ).array;
		local placeList = AIList();
		foreach(i,_ in places) {
			placeList.AddItem(i,0);
		}
		local result = [places, placeList];
		Place.cargoProducingListCache.rawset(cargo, result);
		return result;
	}
	
	static function GetCargoProducing( cargo ) {
		if(HogeAI.Get().IsFreightOnly() && CargoUtils.IsPaxOrMail(cargo)) {
			return HgArray([]);
		} else if(HogeAI.Get().IsPaxMailOnly() &&!CargoUtils.IsPaxOrMail(cargo)) {
			return HgArray([]);
		}
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
		return cargo == HogeAI.GetPassengerCargo() || cargo == HogeAI.GetMailCargo(); //TODO: 観光客とかは？
	}

	static function SearchNearProducingPlaces(cargo, fromTile, maxDistance) {
		return Place.GetCargoProducing( cargo ).Filter(function(place):(cargo,fromTile,maxDistance) {
			return place.DistanceManhattan(fromTile) <= maxDistance && place.GetLastMonthProduction(cargo) >= 1;
		});
	}
	

	static function GetNotUsedProducingPlacesList( cargo ) {
		if(Place.notUsedProducingPlaceCache.rawin(cargo)) {
			return Place.notUsedProducingPlaceCache.rawget(cargo);
		}
		local placeDictionary = PlaceDictionary.Get();
		local a = Place.GetCargoProducing( cargo ).array;
		local result = AIList();
		foreach(i,place in a) {
			if(!placeDictionary.CanUseAsSource(place,cargo)) {
				continue;
			}
			if(Place.IsNgCandidatePlace(place,cargo)) {
				continue;
			}
			result.AddItem(i,0);
		}
		local result = [a,result];
		Place.notUsedProducingPlaceCache.rawset(cargo, result);
		return result;
	}

	static function _GetProducingPlaceDistanceList( cargo, fromTile ) {
		local key = cargo+"-"+fromTile;
		if(Place.producingPlaceDistanceListCache.rawin(key)) {
			return Place.producingPlaceDistanceListCache.rawget(key);
		}
		local placesList = Place.GetCargoProducingList( cargo );
		local places = placesList[0];
		local placeList = ListUtils.Clone(placesList[1]);
		placeList.Valuate(function(i):(places,fromTile) {
			return places[i].DistanceManhattan( fromTile );
		});
		local result = [places,placeList];
		Place.producingPlaceDistanceListCache.rawset(key,result);
		return result;
	}
	
	static function GetProducingPlaceDistanceList( cargo, fromTile, maxDistance ) {
		local placesList = Place._GetProducingPlaceDistanceList(cargo,fromTile);
		local places = placesList[0];
		local placeList = ListUtils.Clone(placesList[1]);
		placeList.RemoveAboveValue( maxDistance );
		return [places, placeList];
/*	
		return Place.GetNotUsedProducingPlaces( cargo ).Map(function(place):(fromTile) {
			return [place, place.DistanceManhattan( fromTile )];
		}).Filter(function(placeDistance):(maxDistance) {
			return placeDistance[1] < maxDistance;
		})*/
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
	

	static function SearchSrcAdditionalPlaces(srcStation, destTile, cargo, minDistance=20, maxDistance=200, minProduction=60, vehicleType=AIVehicle.VT_RAIL) {
		local middleTile;
		if(srcStation.stationGroup == null) {
			return [];
		}
		local middlePlace = srcStation.place;
		local middleTile = srcStation.GetLocation();
		local existingDistance = destTile == null ? 0 : AIMap.DistanceManhattan(destTile, middleTile);
		local placesList = Place.GetProducingPlaceDistanceList(cargo, middleTile, maxDistance);
		local a = [];
		placesList[1].Valuate(function(index):(placesList, a, cargo, destTile){
			local t = {};
			t.place <- placesList[0][index];
			t.distance <- placesList[1].GetValue(index);
			t.totalDistance <- destTile == null ? t.distance : AIMap.DistanceManhattan(destTile, t.place.GetLocation());
			a.push(t);
			return 0;
		});
		
		local r = HgArray(a).Filter(function(t):(middlePlace, middleTile, minDistance, minDistance, existingDistance, vehicleType, cargo){
			if(t.distance == 0) {
				return false;
			}
			local efficiency = t.totalDistance * 100 / (t.distance + existingDistance);
			//HgLog.Info("t.totalDistance:"+t.totalDistance+" t.distance:"+t.distance+" existingDistance:"+ existingDistance +" efficiency:" + efficiency);	
			return minDistance <= t.distance 
				//&& efficiency >= 70 // 転送されるカーゴが既存路線の80%以上の効力を持つかどうか estimateで判断される
				&& (middlePlace == null || t.place.GetLocation() != middlePlace.GetLocation())
				&& !Place.IsNgPathFindPair(t.place, middleTile, vehicleType)
				&& PlaceDictionary.Get().CanUseAsSource(t.place, cargo);
		});
		
		return r.array;
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
/*
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
	}*/
	
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
			
			local score = 0;
			foreach(tileCurrentScore in srcTilesScores) {
				score += (t.place.DistanceManhattan(tileCurrentScore[0]) - tileCurrentScore[1]);// * 10000 / t.cost;
			}
			t.score <- score * 100 / srcTilesScores.len() / t.distance; //新規線路100マスあたりcargo距離が何マス伸びるのか
			return t;
		}).Filter(function(t):(lastAcceptingTile) {
			return 100 <= t.distance && 30 < t.score && !Place.IsNgPathFindPair(t.place,lastAcceptingTile,AIVehicle.VT_RAIL) && t.place.IsAccepting();
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
	
	function IsTreatCargo(cargo,isProducing = null) {
		if(isProducing != null && IsProducing() != isProducing) {
			return false;
		}
	
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
	
	function IsAcceptingCargo(cargo) {
		return GetAccepting().IsTreatCargo(cargo);
	}
	
	function IsProducingCargo(cargo) {
		return GetProducing().IsTreatCargo(cargo);
	}
	
	function GetProducingCargos() {
		return GetProducing().GetCargos();
	}
	
	function CanUseNewRoute(cargo, vehicleType) {
		if(vehicleType == AIVehicle.VT_AIR) {
			return true;
		}
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(vehicleType != AIVehicle.VT_ROAD 
					&& (route.GetVehicleType() == AIVehicle.VT_ROAD || route.IsSingle())) {
				continue;
			}
			if(route.IsOverflowPlace(this,cargo)) {
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
			if(route.IsOverflowPlace(this,cargo)) {
				continue;
			}
			if(route.GetVehicleType() == AIVehicle.VT_ROAD) {
				continue;
			}
			return false;
		}
		return true;
	}
	
	function GetUsingRoutes(cargo = null) {
		return GetRoutes(cargo);
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
			if(route.HasCargo(cargo)) {
				result.push(route);
			}
		}
		return result;
	}
	
	function GetRouteCountUsingSource(cargo = null) {
		local result = 0;
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(!route.IsTownTransferRoute() /* && !route.IsOverflowPlace(this,cargo)*/) {
				result ++;
			}
		}
		return result;
	}
	
	function GetSourceStationGroups(cargo = null) {
		local table = {};
		foreach(route in GetRoutesUsingSource(cargo)) {
			if(route.IsTownTransferRoute()) {
				continue;
			}
			if(route.IsBiDirectional() && route.destHgStation.place != null && route.destHgStation.place.IsSamePlace(this)) {
				table.rawset( route.destHgStation.stationGroup, 0 );
			} else if(route.srcHgStation.stationGroup != null) {
				table.rawset( route.srcHgStation.stationGroup, 0 );
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
			if(route.HasCargo(cargo)) {
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
	
	/*
	function GetUsedOtherCompanyEstimation() {
		local key = Id();
		if(usedOtherCompanyEstimationCache.rawin(key)) {
			return usedOtherCompanyEstimationCache.rawget(key);
		}
		local result = _GetUsedOtherCompanyEstimation();
		usedOtherCompanyEstimationCache.rawset(key,result);
		return result;
	}*/
	
	function GetUsedOtherCompanyEstimation() {
		if(!(this instanceof HgIndustry)) {
			return 0;
		}
		if(AIIndustry.GetAmountOfStationsAround(industry) >= 1) {
			return 1;
			/* 重いし不正確
			local tileList = AITileList_IndustryAccepting(industry,5);
			tileList.Valuate(AITile.IsStationTile);
			tileList.RemoveValue(0);
			tileList.Valuate(AITile.GetOwner);
			tileList.RemoveValue(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF));
			local owners = {};
			foreach(tile,owner in tileList) {
				owners.rawset(owner,0);
			}
			//HgLog.Warning("_GetUsedOtherCompanyEstimation:"+owners.len()+" "+GetName());
			return owners.len();*/
		}	
		return 0;
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
		local facilityId = GetFacilityId();
		if(!placeStationDictionary.rawin(facilityId)) {
			placeStationDictionary[facilityId] <- [station];
		} else {
			placeStationDictionary[facilityId].push(station);
		}
	}
	
	
	function RemoveStation(station) {
		local facilityId = GetFacilityId();
		if(placeStationDictionary.rawin(facilityId)) {
			ArrayUtils.Remove( placeStationDictionary[facilityId], station );
		}
	}
	
	function GetStations() {
		local facilityId = GetFacilityId();
		if(placeStationDictionary.rawin(facilityId)) {
			return placeStationDictionary[facilityId];
		} else {
			return [];
		}
	}
	
	function GetStationGroups() {
		local result = {};
		foreach(hgStation in GetStations()) {
			if(hgStation.place != null && hgStation.place.IsSamePlace(this)) {
				result[hgStation.stationGroup] <- hgStation.stationGroup;
			}
		}
		return result;
	}
	
	function GetLastMonthTransportedPercentage(cargo) {
		return 0; // オーバーライドして使う
	}
	
	function GetFutureExpectedProduction(cargo, vehicleType, isMine = false) {
		return GetExpectedProduction(cargo,vehicleType,isMine);
		
		/*
		if(HogeAI.Get().buildingTimeBase && !HogeAI.Get().ecs) {
			if(IsIncreasable() && vehicleType == AIVehicle.VT_RAIL) {
				return GetExpectedProduction(cargo,vehicleType,isMine) * 3; // 将来は今よりずっと増える
			}
		}
		return GetExpectedProduction(cargo,vehicleType,isMine);*/
	}
	
	function GetExpectedProduction(cargo, vehicleType, isMine = false) {
		local key = Id() + "-" + cargo + "-" + vehicleType + "-" + isMine;
		if(Place.expectedProductionCache.rawin(key)) {
			return Place.expectedProductionCache.rawget(key);
		}
		local result = _GetExpectedProduction(cargo,vehicleType,isMine);
		Place.expectedProductionCache.rawset(key,result);
		return result;
	}
	
	function _GetExpectedProduction(cargo, vehicleType, isMine = false) {
		return AdjustUsing( GetExpectedProductionAll(cargo, vehicleType), cargo, isMine );
	}
	
	function GetCurrentExpectedProduction(cargo, vehicleType, isMine = false) {
		local key = Id() + "-" + cargo + "-" + vehicleType + "-" + isMine;
		if(Place.currentExpectedProductionCache.rawin(key)) {
			return Place.currentExpectedProductionCache.rawget(key);
		}
		local result = _GetCurrentExpectedProduction(cargo,vehicleType,isMine);
		Place.currentExpectedProductionCache.rawset(key,result);
		return result;
	}
	
	function _GetCurrentExpectedProduction(cargo, vehicleType, isMine = false) {
		return AdjustUsing( GetLastMonthProduction(cargo), cargo, isMine );
	}
	
	function GetProductionArroundCount(cargo, vehicleType) {
		if(!HogeAI.Get().roiBase && !HogeAI.Get().ecs && IsProcessing() 
				&& (vehicleType == AIVehicle.VT_RAIL || vehicleType == AIVehicle.VT_WATER)) {
			local result = 0;
			local placeProduction = PlaceProduction.Get();
			foreach(acceptingCargo in GetAccepting().GetCargos()) {
				result += placeProduction.GetArroundProductionCount(GetLocation(), acceptingCargo)[1];
			}
			return result;
		}
		return 0;
	}
	
	function GetSupportEstimate() {
		local key = Id();
		if(Place.supportEstimatesCache.rawin(key)) {
			return Place.supportEstimatesCache.rawget(key);
		}
		local result = _GetSupportEstimate()
		Place.supportEstimatesCache.rawset(key,result);
		return result;
	}
/*
	function _GetSupportEstimate() {
		local routeIncome = 0;
		local buildingTime = 0;
		local production = 0;
		local connectedPlaces = {};
		foreach(acceptingCargo in GetAccepting().GetCargos()) {
			HgLog.Warning("acceptingCargo:"+AICargo.GetName(acceptingCargo)+" "+this);
			local productionCount = PlaceProduction.Get().GetArroundProductionCount( GetLocation(), acceptingCargo );
			if(productionCount[1] == 0) {
				continue;
			}
			local estimate = Route.EstimateBestVehicleType(acceptingCargo, PlaceProduction.PIECE_SIZE, 
				productionCount[0] / productionCount[1], // サポート作らなくなるのでやらない。生産上位半分が使われる想定なので平均より少し増やしておく
				false);
			local connected = false;
			HgLog.Warning("GetVehicleType:"+estimate.GetVehicleType()+" "+this);
			if(estimate.GetVehicleType() == AIVehicle.VT_RAIL) {
				foreach(p in productionCount[2]) {
					if(connectedPlaces.rawin(p)) {
						connected = true;
						HgLog.Warning("conncted:"+AICargo.GetName(acceptingCargo)+" "+this);
					} else {
						connectedPlaces.rawset(p,0);
						HgLog.Warning("connct:"+p+" "+AICargo.GetName(acceptingCargo)+" "+this);
					}
				}
			}
			routeIncome += estimate.routeIncome * productionCount[1];
			if(!connected) {
				buildingTime += estimate.buildingTime * productionCount[1];
			}
			production += productionCount[0];
		}
		return {
			routeIncome = routeIncome
			buildingTime = buildingTime
			production = production
		}
		
		
	}*/
	
	function _GetSupportEstimate() {
		if(!IsIncreasable()) {
			return { production = 0 };
		}
	
		local routeIncome = {};
		local buildingTime = {};
		local production = 0;
		local count = 0;
		local connectedPlaces = {};
		local vehicleTypes = Route.GetAvailableVehicleTypes();
		foreach(vehicleType in vehicleTypes) {
			routeIncome[vehicleType] <- 0;
			buildingTime[vehicleType] <- 0;
		}
		foreach(acceptingCargo in GetAccepting().GetCargos()) {
			//HgLog.Warning("acceptingCargo:"+AICargo.GetName(acceptingCargo)+" "+this);
			local productionCount = PlaceProduction.Get().GetArroundProductionCount( GetLocation(), acceptingCargo );
			if(productionCount[1] == 0) {
				continue;
			}
			foreach(vehicleType in vehicleTypes) {
				local estimate = Route.Estimate(vehicleType, acceptingCargo, PlaceProduction.PIECE_SIZE, 
					productionCount[0] / productionCount[1],
					false);
				if(estimate==null) {
					continue;
				}
				local connected = false;
				//HgLog.Warning("GetVehicleType:"+estimate.GetVehicleType()+" "+this);
				if(vehicleType == AIVehicle.VT_RAIL) {
					foreach(p in productionCount[2]) {
						if(connectedPlaces.rawin(p)) {
							connected = true;
							//HgLog.Warning("conncted:"+AICargo.GetName(acceptingCargo)+" "+this);
						} else {
							connectedPlaces.rawset(p,0);
							//HgLog.Warning("connct:"+p+" "+AICargo.GetName(acceptingCargo)+" "+this);
						}
					}
				}
				routeIncome[vehicleType] += estimate.routeIncome * productionCount[1];
				if(!connected) {
					buildingTime[vehicleType] += estimate.buildingTime * productionCount[1];
				}
				/*
				HgLog.Warning("GetSupportEstimate"
					+" cargo:"+AICargo.GetName(acceptingCargo)
					+" vehicleType:"+vehicleType
					+" routeIncome:"+estimate.routeIncome
					+" buildingTime:"+estimate.buildingTime
					+(estimate.rawin("infraBuildingTime")?(" infraBT:"+estimate.infraBuildingTime):"")
					+" production:"+(productionCount[0] / productionCount[1])
					+" count:"+productionCount[1]
					+" connected:"+connected
					+" "+this);*/
			}
			production += productionCount[0];
			count += productionCount[1];
		}
		local maxVehicleType = null;
		local maxValue = null;
		foreach(vehicleType in vehicleTypes) {
			if(buildingTime[vehicleType] != 0) {
				local value = routeIncome[vehicleType] * 100 / buildingTime[vehicleType];
				if(maxValue == null || maxValue < value) {
					maxValue = value;
					maxVehicleType = vehicleType;
				}
			}
		}
		/*
		HgLog.Warning("GetSupportEstimate maxVehicleType:"+maxVehicleType
			+" routeIncome:"+(maxVehicleType==null ? 0 : routeIncome[maxVehicleType])
			+" buildingTime:"+(maxVehicleType==null ? 0 : buildingTime[maxVehicleType])
			+" production:"+production
			+" count:"+count
			+" "+this);*/
		return {
			routeIncome = maxVehicleType==null ? 0 : routeIncome[maxVehicleType]
			buildingTime = maxVehicleType==null ? 0 : buildingTime[maxVehicleType]
			production = production
		}
	}
	
	function GetExpectedProductionAll(cargo, vehicleType) {
		local production = GetLastMonthProduction(cargo);
		local placeProduction = PlaceProduction.Get();
		if(HogeAI.Get().firs && !HogeAI.Get().roiBase) {
		
			local inputableProduction = 0;
			local allCargosAvailable = true;
			local acceptingCargos = GetAccepting().GetCargos();
			foreach(acceptingCargo in acceptingCargos) {
				local availableProduction = placeProduction.GetArroundProductionCount(GetLocation(), acceptingCargo)[0];
				if(availableProduction == 0) {
					allCargosAvailable = false;
				}
				inputableProduction += availableProduction;
			}
			if(IsProcessing()) {
				if(allCargosAvailable) {
					if(GetNotToMeetCargos().len() >= 1) {
						production *= 3;
					}
					production += inputableProduction / 4;
				} else {
					production += inputableProduction / 4 / 3;
				}
			} else if(acceptingCargos.len() >= 1) {
				if(allCargosAvailable && inputableProduction >= 1 && GetNotToMeetCargos().len() >= 1) {
					production *= 3;
				}			
			}
		}
		if(!HogeAI.Get().roiBase && !HogeAI.Get().ecs && !HogeAI.Get().firs && IsProcessing()) {
			local inputableProduction = 0;
			foreach(acceptingCargo in GetAccepting().GetCargos()) {
				inputableProduction += placeProduction.GetArroundProductionCount(GetLocation(), acceptingCargo)[0];
			}
			//HgLog.Warning("GetExpectedProductionAll production:"+production+" inputableProduction/4:"+(inputableProduction/4)+" "+GetName()+" cargo:"+AICargo.GetName(cargo)+" "+vehicleType);
			production += inputableProduction;// / 2; //max(0,(inputableProduction - production));
			//production = max(production, inputableProduction / 2);
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
			if(ecsRaw) {/*スピードでの調整
				if(vehicleType == AIVehicle.VT_RAIL) {
					production *= 2;
				}
				if(vehicleType == AIVehicle.VT_ROAD)  {
					production /= 2;
				}*/
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
		
		
		
		return production;
	}
	
	function AdjustUsing(production,cargo,isMine) {
		local key = Id();
		local maybeNotUsed = Place.maybeNotUsed.rawin(key) ? Place.maybeNotUsed[key] : false;
		local otherCompanies = maybeNotUsed ? 0 : GetUsedOtherCompanyEstimation();
		if(otherCompanies>=1 && GetLastMonthTransportedPercentage(cargo) == 0) { // 推定するしかできない
			Place.maybeNotUsed.rawset(key,true)
			otherCompanies = 0;
		}
		//local usingRoutes = GetRoutesUsingSource(cargo);
		local totalRates = 0;
		local count = 0;
		foreach( stationGroup in GetSourceStationGroups(cargo) ) {
			totalRates += AIStation.GetCargoRating( stationGroup.GetAIStation(), cargo);
			count ++;
		}
		local isTownCargo = this instanceof TownCargo;
		if(totalRates == 0 && (!isTownCargo || (isTownCargo && !TownBus.Exists(town,cargo)))) { // 他社は1社であると仮定している
			return 70 * production / (GetLastMonthTransportedPercentage(cargo) + 70);
		} else if(count == 1 && isMine) {
			return production / (otherCompanies + 1);
		} else { 
			return 70 * (production  / (otherCompanies + 1)) / (totalRates + 70);
		}
	}
	
	function IsDirtyArround() {
		foreach(cargo in GetAccepting().GetCargos()) {
			if(PlaceProduction.Get().IsDirtyArround(GetLocation(), cargo)) {
				//HgLog.Info("Dirty["+AICargo.GetName(cargo)+"]");
				return true;
			}
		}
		return false;
	}

	function SetDirtyArround() {
		foreach(cargo in GetAccepting().GetCargos()) {
			PlaceProduction.Get().SetDirtyArround(GetLocation(), cargo);
		}
	}

	function IsEcsHardNewRouteDest(cargo) {
		if(HogeAI.Get().ecs && this instanceof HgIndustry && this.GetCargos().len() >= 2) { // ecsのマルチで受け入れるindustryは生産条件を満たすのが困難な事が多い。
			local traits = this.GetIndustryTraits();
			local cargoLabel = AICargo.GetCargoLabel(cargo);
			if(!(traits == "WOOL,LVST,/FICR,FISH,CERE," 
					|| traits=="FERT,FOOD,/OLSD,FRUT,CERE," 
					|| traits=="/OIL_,COAL," 
					|| traits=="PETR,RFPR,/OLSD,OIL_," 
					|| traits=="GOOD,/DYES,GLAS,STEL,"
					|| (cargoLabel=="RFPR" && traits=="GOOD,/RFPR,GLAS,"))) {
				return true;
			}
		}
		return false;
	}
	
	
	function GetCoasts(cargo) {
		local placeDictionary = PlaceDictionary.Get();
		local id = Id()+":"+cargo;
		if(this instanceof TownCargo) {
			local result;
			if(!placeDictionary.nearWaters.rawin(id) || placeDictionary.nearWaters[id]==true || placeDictionary.nearWaters[id]==false) {
				result = CheckNearWater(cargo);
				placeDictionary.nearWaters[id] <- [ (result==null?null:result.id), AITown.GetPopulation(town) ];
				return result;
			} else {
				if(placeDictionary.nearWaters[id][0] == null) {
					local population = AITown.GetPopulation(town);
					if(placeDictionary.nearWaters[id][1] * 3 / 2 < population) {
						result = CheckNearWater(cargo);
						placeDictionary.nearWaters[id] = [ (result==null?null:result.id), population ];
						return result;
					}
				}
				local coastsId = placeDictionary.nearWaters[id][0];
				return coastsId == null ? null : Coasts.idCoasts[coastsId];
			}
		} else {
			local result;
			if(!placeDictionary.nearWaters.rawin(id) || placeDictionary.nearWaters[id]==true || placeDictionary.nearWaters[id]==false) {
				result = CheckNearWater(cargo);
				//HgLog.Info("CheckNearWater "+this+" "+AICargo.GetName(cargo)+" result:"+result);
				placeDictionary.nearWaters[id] <- result == null ? null : result.id;
				return result;
			} else {
				local coastsId = placeDictionary.nearWaters[id];
				return coastsId == null ? null : Coasts.idCoasts[coastsId];
			}
		}
	}
	
	function CheckNearWater(cargo) {		
		//HgLog.Info("CheckNearWater "+this+" "+AICargo.GetName(cargo));
		if(IsBuiltOnWater()) {
			local cur = GetLocation(); // 陸地に接しているIsBuiltOnWaterがある(firs)
			cur = Coasts.FindCoast(cur);
			if(cur != null) {
				local coasts = Coasts.GetCoasts(cur);
				if(coasts.coastType == Coasts.CT_POND) {
					return null;
				} else if(coasts.coastType == Coasts.CT_SEA) {
					return coasts;
				}
			} else {
				return GlobalCoasts;
			}
		}

		local dockRadius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
		local tile;
		local gen = GetTiles(dockRadius,cargo)
		while((tile = resume gen) != null) {
			if(AITile.IsCoastTile(tile)) {
				local result = Coasts.GetCoasts(tile);
				if(result.coastType == Coasts.CT_POND) {
					return null;
				}
				return result;
			}
		}
		return null;
	}

	function IsNearWater(cargo) {		
		local placeDictionary = PlaceDictionary.Get();
		local id = Id()+":"+cargo;
		if(placeDictionary.nearWaters.rawin(id)) {
			if(placeDictionary.nearWaters[id]==true || placeDictionary.nearWaters[id]==false) {
				return placeDictionary.nearWaters[id];
			} else {
				return placeDictionary.nearWaters[id] != null;
			}
		}
		local result = _IsNearWater(cargo);
		placeDictionary.nearWaters.rawset(id,result);
		return result;
	}
	
	function _IsNearWater(cargo) {
		if(IsBuiltOnWater()) {
			return true;
		}
		local dockRadius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
		local tile;
		local gen = GetTiles(dockRadius,cargo)
		while((tile = resume gen) != null) {
			if(AITile.IsCoastTile(tile)) {
				HogeAI.Get().pendingCoastTiles.push(tile);
				return true;
			}
		}
		return false;
	}

	
	function IsNearLand(cargo) {
		local key = Id()+"-"+cargo;
		local cache = Place.nearLandCache;
		if(cache.rawin(key)) {
			return cache.rawget(key);
		}
		local result = _IsNearLand(cargo);
		cache.rawset(key,result);
		return result;
	}
	
	function _IsNearLand(cargo) {		
		//HgLog.Info("CheckNearWater "+this+" "+AICargo.GetName(cargo));
		if(!IsBuiltOnWater()) {
			return true;
		}

		local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
		local tile;
		local gen = GetTiles(radius,cargo)
		while((tile = resume gen) != null) {
			if(AITile.GetMaxHeight(tile)>=1) {
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
	
	function GetDestRouteCargoIncome() {
		if(!IsIncreasable() || !IsProcessing() || IsRaw()) {
			return 0;
		}
		local usingRoutes = GetRoutesUsingSource();
		if(usingRoutes.len() == 0) {
			return 0;
		}
		local producingCargos = GetProducing().GetCargos();
		local result = 0;
		foreach(usingRoute in usingRoutes) {
			local engineSet = usingRoute.GetLatestEngineSet();
			if( engineSet == null ) {
				continue;
			}
			local cargoIncomes = engineSet.cargoIncomes;
			foreach(producingCargo in producingCargos) {
				if(!usingRoute.NeedsAdditionalProducingCargo(producingCargo)) {
					continue;
				}
				if( cargoIncomes.rawin(producingCargo) ) {
					result += cargoIncomes[producingCargo];
					if(usingRoute instanceof TrainRoute) {
						if(usingRoute.returnRoute != null && !usingRoute.returnRoute.NeedsAdditionalProducingCargo(producingCargo)) {
							result += cargoIncomes[producingCargo]; // 復路の分。TODO: 転送やbidirectionも
						}
					}
				}
			}
		}
		return result;
	}
	
	function GetAdditionalRouteIncome(cargo) {
		if(!HogeAI.Get().firs) {
			return 0;
		}
		if(IsProcessing() || IsRaw()) {
			local ok = false;
			foreach(notMeetCargo in GetNotToMeetCargos()) {
				if(cargo == notMeetCargo) {
					ok = true;
					break;
				}
			}
			if(!ok) {
				return 0;
			}
		} else {
			if(GetRoutesUsingDest().len() >= 1) {
				return 0;
			}
		}
		local result = 0;
		foreach(route in GetRoutesUsingSource()) {
			if(CargoUtils.IsPaxOrMail(route.cargo)) { //PaxMailは増えない(HOTEL)
				continue;
			}
			local engineSet = route.GetLatestEngineSet();
			if(engineSet != null) {
				result += engineSet.routeIncome * 2;
			}
		}
		return result;
	}
	
	
	function GetNotToMeetCargos() {
		return GetToMeetCargos(true);
	}

	function GetToMeetCargos(not = false) {
		local delivered = {};
		foreach(route in GetAccepting().GetRoutesUsingDest()) {
			if(route.IsTransfer()) {
				continue;
			}
			foreach(cargo in route.GetCargos()) {
				if(route.HasCargo(cargo)) {
					delivered.rawset(cargo,0);
				}
			}
		}
		local result = [];
		foreach(cargo in GetAccepting().GetCargos()) {
			if(not != delivered.rawin(cargo)) {
				result.push(cargo);
			}
		}
		return result;
	
	}

	
	
	
	function _tostring() {
		return GetName();
	}
}

class HgIndustry extends Place {
	static industryClosedDate = {};
	
	industry = null;
	isProducing = null;
	date = null;
	
	constructor(industry,isProducing,date=null) {
		this.industry = industry;
		this.isProducing = isProducing;
		this.date = date != null ? date : AIDate.GetCurrentDate();
	}

	function Save() {
		local t = {};
		t.name <-  "HgIndustry";
		t.industry <- industry;
		t.isProducing <- isProducing;
		t.date <- date;
		return t;
	}
	
	function Id() {
		return "Industry:" + industry + ":" + isProducing;
	}
	
	function GetFacilityId() {
		return "Industry:" + industry;
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
	
	function GetLastMonthTransportedPercentage(cargo) {
		return AIIndustry.GetLastMonthTransportedPercentage(industry,cargo);
	}
	
	function GetLastMonthProduction(cargo) {
		return PlaceProduction.Get().GetLastMonthProduction(industry,cargo);
	}

	function IsClosed() {
		if(industryClosedDate.rawin(industry)) {
			if(date < industryClosedDate[industry]) {
				return true;
			}
		}
		return false;
	}

	function GetCargos() {
		if(isProducing) {
			return HgArray.AIListKey(AICargoList_IndustryProducing(industry)).array;
		} else {
			local traits = GetIndustryTraits();
			if(traits == "OIL_,PASS,/") { // 海上油田
				return [HogeAI.Get().GetPassengerCargo(),HogeAI.Get().GetMailCargo()];
			}
			return HgArray.AIListKey(AICargoList_IndustryAccepting(industry)).array;
		}
	}
	
	function IsCargoAccepted(cargo) {
		return AIIndustry.IsCargoAccepted(industry, cargo) == AIIndustry.CAS_ACCEPTED;
	}
	
	function GetProducingCargos() {
		return GetProducing().GetCargos();
	}
	
	function IsAccepting() {
		return !isProducing;
	}
	
	function IsProducing() {
		return isProducing;
	}
	
	function GetAccepting() {
		if(isProducing) {
			return HgIndustry(industry,false,date);
		} else {
			return this;
		}
	}
	
	function GetProducing() {
		if(isProducing) {
			return this;
		} else {
			return HgIndustry(industry,true,date);
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
		local traits = GetIndustryTraits();
		if(traits=="OIL_,PASS,/") { // 油田
			return false;
		}
		return true;
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

	function GetFacilityId() {
		return "TownCargo:" + town;
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
		return max(3,(pow(AITown.GetPopulation(town), 0.4) * 0.5).tointeger());
//		return (sqrt(AITown.GetPopulation(town))/5).tointeger() + 2;
	}
	
	function GetTiles(coverageRadius,cargo) {
		if(cargo != this.cargo) {
			HgLog.Warning("Cargo not match. expect:"+AICargo.GetName(this.cargo)+" but:"+AICargo.GetName(cargo));
			return null;
		}
		
		local maxRadius = GetRadius(); // + coverageRadius;
		if(IsProducing()) {
			local tiles = Rectangle.Center(HgTile(GetLocation()),maxRadius).GetTilesOrderByInside();
			local bottom = CargoUtils.IsPaxOrMail(cargo) ? 8 : 1;
			foreach(tile,_ in tiles) {
				if(AITile.GetCargoProduction(tile, cargo, 1, 1, coverageRadius) >= bottom) {
					yield tile;
				}
			}
		} else {
			local tiles = Rectangle.Center(HgTile(GetLocation()),maxRadius).GetTilesOrderByOutside();
			local bottom = AICargo.GetTownEffect (cargo) == AICargo.TE_GOODS ? 8 : 8;
			foreach(tile,_ in tiles) {
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

	function _GetCurrentExpectedProduction(cargo, vehicleType, isMine = false) {
		return GetExpectedProductionAll(cargo, vehicleType, true, isMine );
	}
	
	function GetCurrentProduction(cargo, isMine) {
		return AdjustUsing( GetLastMonthProduction(cargo), cargo, isMine );
	}

	function GetExpectedUsingDistantJoinStations() {
		local d = max(5,HogeAI.Get().maxStationSpread);
		return 200 + d * d * 2;
	}

	function GetExpectedProductionAll(cargo, vehicleType, isCurrent = false, isMine = false) {
		local production;
		/*if(isCurrent) {
			production = GetCurrentProduction(cargo, isMine);
		} else {
			production = GetLastMonthProduction(cargo);
		}*/
		production = GetLastMonthProduction(cargo);
		if(HogeAI.Get().IsDistantJoinStations()) {
			return min( production , cargo == HogeAI.Get().GetPassengerCargo()
				? GetExpectedUsingDistantJoinStations() : GetExpectedUsingDistantJoinStations() * 2 / 5 );
		} else if(TownBus.CanUse(cargo) && TownBus.IsReadyEconomy() && RoadRoute.GetVehicleNumRoom(RoadRoute) > 50) {
			if(vehicleType == AIVehicle.VT_ROAD) {
				return min( production , cargo == HogeAI.Get().GetPassengerCargo() ? 200 : 80 );
			} else {
				return min( production , cargo == HogeAI.Get().GetPassengerCargo() ? 550 : 220);
			}
		} else {
			local minValue = cargo == HogeAI.Get().GetPassengerCargo() ? 200 : 80;
			if(vehicleType == AIVehicle.VT_ROAD || vehicleType == AIVehicle.VT_WATER) {
				minValue /= 2;
				production /= 2;
			}			
			return min(minValue, production);
		}
		HgLog.Error("unknown vt:"+vehicleType);
	}

	function GetLastMonthProduction(cargo) {
		//if(RoadRoute.IsTooManyVehiclesForSupportRoute(RoadRoute)) {
		local r = AITown.GetLastMonthProduction( town, cargo );
		//HgLog.Info("GetLastMonthProduction:"+r+" "+AICargo.GetName(cargo)+" "+AITown.GetName(town));
		if(r > AITown.GetPopulation(town)) { // 異常値に対するバグ対応
			if(cargo == HogeAI.Get().GetPassengerCargo()) {
				r = AITown.GetPopulation(town) / 8;
			} else if(cargo == HogeAI.Get().GetMailCargo()) {
				r = AITown.GetPopulation(town) / 16;
			}
		}
		return r; // / 2;
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
		if(townEffect == AICargo.TE_PASSENGERS) {
			return AITown.GetPopulation(town) >= 200;
		}
		if(townEffect == AICargo.TE_MAIL) {
			return AITown.GetPopulation(town) >= 400;
		}
		if(townEffect == AICargo.TE_WATER || townEffect == AICargo.TE_FOOD ) {
			return AITown.GetPopulation(town) >= 1000;
		}
		return false;
	}
	
	function GetProducingCargos() {
		local pax = HogeAI.Get().GetPassengerCargo();
		local mail = HogeAI.Get().GetMailCargo();
		if(AITown.GetPopulation(town) >= 400) {
			if(IsProducing() && cargo != pax && cargo != mail) {
				return [cargo,pax,mail];
			}
			return [pax,mail];
		} else if(IsProducing() && AITown.GetPopulation(town) >= 200) {
			if(cargo != pax) {
				return [cargo,pax];
			}
			return [pax];
		} else if(IsProducing()) {
			return [cargo];
		}
		return [];
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

class CoastPlace extends Place {
	location = null;
	
	constructor(location) {
		this.location = location;
	}

	function Save() {
		local t = {};
		t.name <- "Coast";
		t.location <- location;
		return t;
	}

	function IsSamePlace(other) {
		if(other == null) {
			return false;
		}
		if(!(other instanceof CoastPlace)) {
			return false;
		}
		return location == other.location;
	}
	
	function Id() {
		return "Coast:" + location;
	}

	function GetFacilityId() {
		return Id();
	}
	
	function GetName() {
		return AITown.GetName(AITile.GetClosestTown(location))+" Port";
	}
	
	function GetLocation() {
		return location;
	}
	

	function GetCargos() {
		return [];
	}
	
	function GetRadius() {
		return 12;
	}
	
	function GetTiles(coverageRadius,cargo) {
		local coasts = {};
		coasts.rawset( location, 0 );
		local next = [location];
		while(next.len() >= 1) {
			local p = next.pop();
			local distance = coasts[p];
			foreach(d in HgTile.DIR4Index) {
				local t = p + d;
				if(!coasts.rawin(t) && AITile.IsCoastTile(t)) {
					if(distance < 12) {
						next.push(t);
					}
					coasts.rawset( t, distance + 1 );
					yield t;
				}
			}
		}
		return null;
	}

	
	
	function GetExpectedProduction(cargo, vehicleType, isMine = false) {
		return 0;
	}

	function GetLastMonthProduction(cargo) {
		return 0;

	}
	
	function GetLastMonthTransportedPercentage(cargo) {
		return 0;
	}
	
	function IsAccepting() {
		return false;
	}
	
	function IsCargoAccepted(cargo) {
		return false;
	}
	
	function GetProducingCargos() {
		return [];
	}

	function IsClosed() {
		return false;
	}
	
	function IsProducing() {
		return false;
	}	
	
	function GetAccepting() {
		return this;
	}

	function GetProducing() {
		return this;
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
		return GetLocation();
	}
	
	function GetAllowedNoise(airportType) {
		return 1000;
	}
	
	function GetCoasts(cargo) {
		return Coasts.GetCoasts(location);
	}
	
	function GetIndustryTraits() {
		return "";
	}
	
	
	function _tostring() {
		return "Coast:"+HgTile(location);
	}	

}



