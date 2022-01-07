
class PlaceProduction {
	static instance = GeneratorContainer(function() { 
		return PlaceProduction(); 
	});

	static function Get() {
		return PlaceProduction.instance.Get();
	}
	
	
	
	lastCheckMonth = null;
	history = null;
	
	constructor() {
		history = {};
	}
	
	static function Save(data) {
		data.placeProduction <- {
			lastCheckMonth = lastCheckMonth
			history = history
		};
	}

	static function Load(data) {
		local t = data.placeProduction;
		lastCheckMonth = t.lastCheckMonth;
		history = t.history;
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
					if(!history.rawin(industry+"-"+cargo)) {
						history[industry+"-"+cargo] <- [];
					}
					local a = history[industry+"-"+cargo];
					if(a.len() < 12) {
						a.push(0);
					}
					for(local i=a.len()-2;i>=0;i--) {
						a[i+1] = a[i]
					}
					a[0] = production;
				}
			}
			lastCheckMonth = currentMonth;
		}
	}
	
	function GetLastMonthProduction(industry,cargo) {
		Check();
		if(history.rawin(industry+"-"+cargo)) {
			local sum = 0;
			local a = history[industry+"-"+cargo];
			foreach(p in a) {
				sum += p;
			}
			return sum / a.len();
		}
		return 0;
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
	}
	
	function AddRouteTo(dictionary, place, route) {
		local id = place.Id();
		if(!dictionary.rawin(id)) {
			dictionary[id] <- [];
		}
		local routes = dictionary[id];
		foreach(r in routes) {
			if(r == route) {
				return;
			}
		}
		routes.push(route);
	}
	
	function ChangeSource(route, oldPlace) {
		local newRoutes = [];
		foreach(r in GetRoutesBySource(oldPlace)) {
			if(r != route) {
				newRoutes.push(r);
			}
		}
		sources[oldPlace.Id()] = newRoutes;
		
		if(route.destHgStation.place != null) {
			GetRoutesBySource(route.destHgStation.place.GetProducing()).push(route);
		}
	}
	
	function ChangeDest(route, oldPlace) {
		if(route.IsBiDirectional()) {
			ChangeSource(route, oldPlace);
		} else {
			local newRoutes = [];
			foreach(r in GetRoutesByDest(oldPlace)) {
				if(r != route) {
					newRoutes.push(r);
				}
			}
			dests[oldPlace.Id()] = newRoutes;
			
			if(route.destHgStation.place != null) {
				GetRoutesByDest(route.destHgStation.place).push(route);
			}
		}
	}
	
	function CanUseAsSource(place, cargo) {
		local routes = GetRoutesBySource(place);
		foreach(route in routes) {
			if(route.cargo == cargo && (route instanceof TrainRoute) && !route.IsOverflow()) {
				return false;
			}
		}
		return !Place.IsRemovedDestPlace(place);	
	}
	
	function IsUsedAsSourceCargo(place,cargo) {
		foreach(route in GetRoutesBySource(place)) {
			if(route.cargo == cargo) {
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
			if(route instanceof TrainRoute && route.cargo == cargo) {
				return true;
			}
		}
		return false;
	}
	
	function GetUsedAsSourceCargoByTrain(place,cargo) {
		local result = [];
		foreach(route in GetRoutesBySource(place)) {
			if(route instanceof TrainRoute && route.cargo == cargo) {
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
			if(route.cargo == cargo) {
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
		local routes = dictionary[id];
		local closed = false;
		foreach(route in routes) {
			if(route.IsClosed()) {
				closed = true;
				break;
			}
		}
		if(closed) {
			local newRoutes = [];
			foreach(route in routes) {
				if(!route.IsClosed()) {
					newRoutes.push(route);
				}
			}
			dictionary[id] = newRoutes;
			return newRoutes;
		} else {
			return routes;
		}
	}
}


class Place {

	static removedDestPlaceDate = [];
	static ngPathFindPairs = [];
	static productionHistory = [];
	static needUsedPlaceCargo = [];
	
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
		Place.ngPathFindPairs.extend(data.ngPathFindPairs);

		HgIndustry.closedIndustries.clear();
		foreach(industry in data.closedIndustries){
			HgIndustry.closedIndustries[industry] <- true;
		}
		PlaceProduction.Get().Load(data);
		
		PlaceDictionary.Get().nearWaters = data.nearWaters;
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
	
	static function AddNgPathFindPair(from, to) {
		if(AIError.GetLastError() == AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			return;
		}
		local fromTile = typeof from == "integer" ? from : from.GetLocation();
		local toTile = typeof to == "integer" ? to : to.GetLocation();
		
		Place.ngPathFindPairs.push([fromTile,toTile]);
	}
	
	static function IsNgPathFindPair(from, to) {
		local fromTile = typeof from == "integer" ? from : from.GetLocation();
		local toTile = typeof to == "integer" ? to : to.GetLocation();
		foreach(p in Place.ngPathFindPairs) {
			if((p[0] == fromTile && p[1] == toTile) || (p[0] == toTile && p[1]==fromTile)) {
				return true;
			}
		}
		return false;
	}
	
	static function ClearNgPathFindPair() {
		Place.ngPathFindPairs.clear();
	}
	
	static function AddNeedUsed(place, cargo) {
		Place.needUsedPlaceCargo.push([place, cargo]);
	}
	
	static function GetCargoProducing(cargo, isIncreasableProcessingOrRaw = true) {
		local result = [];
		foreach(industry,v in AIIndustryList_CargoProducing(cargo)) {
			local hgIndustry = HgIndustry(industry,true);
			if(!(isIncreasableProcessingOrRaw && !hgIndustry.IsIncreasableProcessingOrRaw())) {
				result.push(hgIndustry);
			}
		}
		if(Place.IsProducedByTown(cargo)) {
			local townList = AITownList();
			townList.Valuate(AITown.GetPopulation);
			townList.KeepAboveValue(1000);
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
		return Place.GetCargoProducing(cargo,false).Filter(function(place):(cargo,fromTile,maxDistance) {
			return place.DistanceManhattan(fromTile) <= maxDistance && place.GetLastMonthProduction(cargo) >= 1;
		});
	}
	

	static function GetNotUsedProducingPlaces(cargo, isIncreasableProcessingOrRaw = true) {
		return Place.GetCargoProducing(cargo,isIncreasableProcessingOrRaw).Filter(function(place):(cargo) {
			return PlaceDictionary.Get().CanUseAsSource(place,cargo);
		});
	}
	
	static function GetProducingPlaceDistance(cargo, fromTile, isIncreasableProcessingOrRaw = true, maxDistance=200) {
		return Place.GetNotUsedProducingPlaces(cargo, isIncreasableProcessingOrRaw).Map(function(place):(fromTile) {
			return [place,place.DistanceManhattan(fromTile)];
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
	

	static function SearchSrcAdditionalPlaces(src, destTile, cargo, minDistance=20, maxDistance=200, minProduction=60, maxCost=100, minScore=200, notAllowLandFill=false, isIncreasableProcessingOrRaw = true) {
		local middleTile = (typeof src == "integer") ? src : src.GetLocation();
		local existingDistance = destTile == null ? 0 : AIMap.DistanceManhattan(destTile, middleTile);
		return Place.GetProducingPlaceDistance(cargo, middleTile, isIncreasableProcessingOrRaw, maxDistance).Map(function(placeDistance):(cargo, destTile) {
			local t = {};
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			t.totalDistance <- destTile == null ? t.distance : AIMap.DistanceManhattan(destTile, t.place.GetLocation());
			t.production <- t.place.GetLastMonthProduction(cargo);
			return t;
		}).Filter(function(t):(middleTile, minDistance, minDistance, minProduction, existingDistance){
			return minDistance <= t.distance 
				&& (existingDistance==0 || t.totalDistance - t.distance > existingDistance / 2)
				&& minProduction <= t.production 
				&& t.place.GetLocation() != middleTile 
				&& !Place.IsNgPathFindPair(t.place, middleTile);
		}).Map(function(t):(middleTile,notAllowLandFill){
			t.cost <- HgTile(middleTile).GetPathFindCost(HgTile(t.place.GetLocation()),notAllowLandFill);
			t.score <- t.totalDistance * 100 / t.cost;
			t.production = Place.AdjustProduction(t.place, t.production);
			return t;
		}).Filter(function(t):(maxCost, minScore) {
//			HgLog.Info("place:"+t.place.GetName()+" cost:"+t.cost+" dist:"+t.distance+" score:"+t.score);
			return t.cost <= maxCost && minScore <= t.score 
		}).Sort(function(a,b) {
			return b.score * b.production - a.score * a.production;
		}).array;
	}
	

	static function GetCargoAccepting(cargo) {
		local result = HgArray([]);
		if(Place.IsAcceptedByTown(cargo)) {
			result = HgArray.AIListKey(AITownList()).Map(function(town) : (cargo) {
				return TownCargo(town,cargo,false);
			}).Filter(function(place) {
				return AITown.GetPopulation (place.town) >= 1000;
			});
		}
		result.array.extend(HgArray.AIListKey(AIIndustryList_CargoAccepting(cargo)).Map(function(a) {
			return HgIndustry(a,false);
		}).array);
		return result;
	}
	
	static function GetAcceptingPlaceDistance(cargo, fromTile) {
		return Place.GetCargoAccepting(cargo).Map(function(place):(fromTile) {
			return [place,place.DistanceManhattan(fromTile)];
		}).Filter(function(placeDistance) {
			return placeDistance[1] < 350;
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

	static function SearchAcceptingPlaces(cargo,fromTile) {
		local hgArray = Place.GetAcceptingPlaceDistance(cargo,fromTile).Map(function(placeDistance) : (cargo,fromTile)  {
			local t = {};
			t.cargo <- cargo;
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			t.cost <- HgTile(fromTile).GetPathFindCost(HgTile(t.place.GetLocation()));
			t.score <- t.distance * 10000 / t.cost;
			return t;
		}).Filter(function(t):(fromTile) {
			return 60 <= t.distance && t.cost < 300 && !Place.IsNgPathFindPair(t.place,fromTile) && t.place.IsAccepting();
		}).Map(function(t) {
			//t.score = Place.AdjustAcceptingPlaceScore(t.score,t.place,t.cargo);
			return t;
		});
		return hgArray.array;
/*		return hgArray.Sort(function(a,b) {
			return b.score - a.score;
		}).array;*/
	}
	
	static function SearchAcceptingPlacesBestDistance(cargo,srcPlace,typeDistanceEstimate) {
		local fromTile = srcPlace.GetLocation();
		local hgArray = Place.GetAcceptingPlaceDistance(cargo,fromTile).Map(function(placeDistance) : (cargo,fromTile,srcPlace,typeDistanceEstimate)  {
			local t = {};
			t.cargo <- cargo;
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			local cost = HgTile(fromTile).GetPathFindCost(HgTile(t.place.GetLocation()));
			local vehicleTypes = cost >= 300 ? [] : [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD];
			if(t.place.IsNearWater(cargo) && srcPlace.IsNearWater(cargo)) {
				vehicleTypes.push(AIVehicle.VT_WATER);
			}
			local maxEstimate = null;
			local distanceIndex = min(9,t.distance/20);
			local vehicleType = null;
			foreach(vt in vehicleTypes) {
				if(typeDistanceEstimate.rawin(vt)) {
					local estimate = typeDistanceEstimate[vt][distanceIndex];
					if(maxEstimate == null || maxEstimate.value < estimate.value) {
						vehicleType = vt;
						maxEstimate = estimate;
					}
				}
			}
			t.estimate <- maxEstimate;
			t.score <- maxEstimate != null ? maxEstimate.value : 0;
			t.vehicleType <- vehicleType;
			return t;
		}).Filter(function(t):(fromTile) {
			return t.vehicleType != null && t.distance > 0 && !Place.IsNgPathFindPair(t.place,fromTile) && t.place.IsAccepting();
		}).Map(function(t) {
			//t.score = Place.AdjustAcceptingPlaceScore(t.score,t.place,t.cargo);
			return t;
		});
		return hgArray.Sort(function(a,b) {
			return b.score - a.score;
		}).array;
	}
	
	static function SearchAdditionalAcceptingPlaces(cargo, srcTiles ,lastAcceptingTile) {
		
		local hgArray = null;
		
		local srcTilesScores = [];
		foreach(tile in srcTiles) {
			srcTilesScores.push([tile, HgTile(lastAcceptingTile).DistanceManhattan( HgTile(tile))]);
		}
		hgArray = Place.GetAcceptingPlaceDistance(cargo,lastAcceptingTile).Map(function(placeDistance) : (cargo, lastAcceptingTile, srcTilesScores)  {
			local t = {};
			t.cargo <- cargo;
			t.place <- placeDistance[0];
			t.distance <- placeDistance[1];
			t.cost <- HgTile(lastAcceptingTile).GetPathFindCost(HgTile(t.place.GetLocation()));
			local score = 0;
			foreach(tileScore in srcTilesScores) {
				score += (t.place.DistanceManhattan(tileScore[0]) - tileScore[1]) * 10000 / t.cost;
			}
			t.score <- score;
			return t;
		}).Filter(function(t):(lastAcceptingTile) {
			return 40 <= t.distance && t.cost < 200 && 10000 <= t.score && !Place.IsNgPathFindPair(t.place,lastAcceptingTile) && t.place.IsAccepting();
		}).Map(function(t) {
			return [t.place,Place.AdjustAcceptingPlaceScore(t.score,t.place,t.cargo)];
		});
		return hgArray.Sort(function(a,b) {
				return b[1] - a[1];
			}).array;
		
	}
	
	static function GetLastMonthProduction(industry,cargo) {
		return PlaceProduction.Get().GetLastMonthProduction(industry,cargo);
	}
	
	
	function DistanceManhattan(tile) {
		return HgTile(GetLocation()).DistanceManhattan(HgTile(tile));
	}
	
	function GetStationGroups() {
		local result = {};
		foreach(hgStaion in GetHgStations()) {
			result[hgStaion.stationGroup] <- hgStaion.stationGroup;
		}
		return result;
	}
	
	function GetHgStations() {
		local result = [];
		foreach(id,hgStation in HgStation.worldInstances) {
			if(hgStation.place != null && hgStation.place.IsSamePlace(this)) {
				result.push(hgStation);
			}
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
		HgLog.Info("CheckNearWater "+this+" "+AICargo.GetName(cargo));

		local dockRadius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
		local tile;
		local gen = GetTiles(dockRadius,cargo)
		while((tile = resume gen) != null) {
			if(AITile.IsCoastTile (tile)) {
				return true;
			}
		}
		return false;
	}
	
	/*
	function IsSuplied(cargo) {
		foreach(station in GetHgStations()) {
			station.GetUsingRoutesAsDest();
		}
	}*/

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
	
	function GetTiles(coverageRadius,cargo) {
		local list = GetTileList(coverageRadius);
		if(isProducing) {
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
		return Place.GetLastMonthProduction(industry,cargo); 
	}
	
	function IsClosed() {
		return closedIndustries.rawin(industry);
	}
	
	function GetCargos() {
		if(isProducing) {
			return HgArray.AIListKey(AICargoList_IndustryProducing (industry)).array;
		} else {
			return HgArray.AIListKey(AICargoList_IndustryAccepting (industry)).array;
		}
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
	
	function IsIncreasable() {
		local industryType = AIIndustry.GetIndustryType(industry);
		return AIIndustryType.ProductionCanIncrease(industryType);

	}
	
	function IsIncreasableProcessingOrRaw() {
		local industryType = AIIndustry.GetIndustryType(industry);
		return AIIndustryType.ProductionCanIncrease(industryType) 
					&& (AIIndustryType.IsProcessingIndustry (industryType) || AIIndustryType.IsRawIndustry(industryType));
	}
	
	function IsRaw() {
		local industryType = AIIndustry.GetIndustryType(industry);
		return AIIndustryType.IsRawIndustry(industryType);
	}
	
	function IsProcessing() {
		local industryType = AIIndustry.GetIndustryType(industry);
		return AIIndustryType.IsProcessingIndustry(industryType);
	}
	
	function GetStockpiledCargo(cargo) {
		return AIIndustry.GetStockpiledCargo(industry, cargo);
	}
	
	function CheckNearWater(cargo) {
		if(AIIndustry.IsBuiltOnWater(industry)) {
			return true;
		}
		return Place.CheckNearWater(cargo);
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
	
	function GetTiles(coverageRadius,cargo) {
		if(cargo != this.cargo) {
			HgLog.Warning("Cargo not match. expect:"+AICargo.GetName(this.cargo)+" but:"+AICargo.GetName(cargo));
			return null;
		}
		
		local maxRadius = (sqrt(AITown.GetPopulation(town))/5).tointeger();
		local tiles = Rectangle.Center(HgTile(GetLocation()),maxRadius).GetTilesOrderByOutside();
		if(IsProducing()) {
			tiles.reverse();
			foreach(tile in tiles) {
				if(AITile.GetCargoProduction(tile, cargo, 1, 1, coverageRadius) >= 8) {
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
	
	function GetLastMonthProduction(cargo) {
		return AITown.GetLastMonthProduction( town, cargo ) * 2 / 3;
	}
	
	function IsAccepting() {
		return !isProducing;
/*		//TODO: STATION_TRUCK_STOP以外のケース
		local gen = this.GetTiles(AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP),cargo);
		return resume gen != null;*/
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
	
	function IsIncreasableProcessingOrRaw() {
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
	
}
