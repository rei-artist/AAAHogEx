
class TrainInfoDictionary {
	static instance = GeneratorContainer(function() { 
		return TrainInfoDictionary(); });

	static function Get() {
		return TrainInfoDictionary.instance.Get();
	}
	
	static function SaveStatics(data) {
		TrainInfoDictionary.Get().Save(data);
	}

	static function LoadStatics(data) {
		TrainInfoDictionary.Get().Load(data);
	}

	dictionary = null;
	railTypeDepot = null;
	
	constructor() {
		dictionary = {};
		railTypeDepot = {};
	}
	
	
	function Save(data) {
		data.dictionary <- dictionary;
		data.railTypeDepot <- railTypeDepot;
	}
	
	function Load(data) {
		dictionary = data.dictionary;
		railTypeDepot = data.railTypeDepot;
	}
	
	
	function GetTrainInfo(engine) {
		local engineName = AIEngine.GetName(engine);
		if(engineName.find("Hankyu") != null) {
			return null;
		}
		
		if(dictionary.rawin(engine)) {
			return dictionary[engine];
		}
		local railType = AIEngine.GetRailType(engine);
		if(!railTypeDepot.rawin(railType)) {
			local execMode = AIExecMode();
			local oldRailType = AIRail.GetCurrentRailType();
			AIRail.SetCurrentRailType(railType);
			local depot = CreateDepot();
			if(depot == null) {
				AIRail.SetCurrentRailType(oldRailType);
				HgLog.Warning("CreateDepot failed (TrainInfoDictionary.GetTrainInfo) "+AIError.GetLastErrorString()+" "+AIRail.GetName(railType));
				return null;
			}
			AIRail.SetCurrentRailType(oldRailType);
			railTypeDepot[railType] <- depot;
		}
		local trainInfo = CreateTrainInfo(railTypeDepot[railType], engine);
		if(trainInfo == null) {
			return null;
		}
		dictionary[engine] <- trainInfo;
		return trainInfo;
	}
	
	function CreateDepot() {
		local exec = AIExecMode();
		for(local i=0; i<32; i++) {
			local x = AIBase.RandRange(AIMap.GetMapSizeX()-20) + 10;
			local y = AIBase.RandRange(AIMap.GetMapSizeY()-20) + 10;
			local depotTile = AIMap.GetTileIndex (x, y);
			HogeAI.WaitForMoney(1000);
			if(AIRail.BuildRailDepot ( depotTile,  AIMap.GetTileIndex (x, y+1))) {
				return depotTile;
			}
		}
		return null;
	}
	
	function CreateTrainInfo(depot, engine) {
		local exec = AIExecMode();
		if(AIEngine.GetPrice(engine) > HogeAI.GetUsableMoney()) {
			//HgLog.Warning("Not enough money (TrainInfoDictionary.CreateTrainInfo) "+AIEngine.GetName(engine));
			return null;
		}
		//HgLog.Info("BuildVehicle "+AIEngine.GetName(engine));
		HogeAI.WaitForPrice(AIEngine.GetPrice(engine));
		local vehicle = AIVehicle.BuildVehicle(depot, engine);
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("BuildVehicle failed (TrainInfoDictionary.CreateTrainInfo) "+AIEngine.GetName(engine)+" "+AIError.GetLastErrorString()+" depot:"+HgTile(depot));
			return null;
		}
		local cargoCapacity = {};
		foreach(cargo, v in AICargoList()) {
			if(AIEngine.CanRefitCargo (engine, cargo)) {
				if(AIVehicle.RefitVehicle (vehicle, cargo)) {
					local capacity = AIVehicle.GetCapacity (vehicle, cargo);
					if(capacity >= 1) {
						cargoCapacity[cargo] <- capacity;
					}
				}
			}
		}
		local length = AIVehicle.GetLength (vehicle);
		
		AIVehicle.SellWagonChain(vehicle,0);
		return {
			length = length
			cargoCapacity = cargoCapacity
		}
	}
	
}

class TrainPlanner {

	cargo = null;
	production = null;
	distance = null;
	
	// optional
	railType = null;
	selfGetMaxSlopesFunc = null;
	maxSlopes = null;
	limitTrainEngines = null;
	limitWagonEngines = null;
	skipWagonNum = 1;
	additonalTrainEngine = null;
	additonalWagonEngine = null;
	
	// private
	roiBase = null;
	
	constructor() {
		roiBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		if(!roiBase) {
			limitWagonEngines = 2;
			limitTrainEngines = 5;
		} else {
			limitWagonEngines = 3;
			limitTrainEngines = 10;
		}
	}

	function GetEngineSetsOrder() {
		local engineSets = GetEngineSets();
		if(roiBase) {
			engineSets.sort(function(a,b) {
				return b.roi - a.roi;
			});
		} else {
			engineSets.sort(function(a,b) {
				return b.income - a.income;
			});
		}
		return engineSets;
	}

	function GetEngineSets() {
		local result = [];
	
		local railSpeed = 10000;
		if(railType != null) {
			railSpeed = AIRail.GetMaxSpeed(railType);
			if(railSpeed <= 0) {
				railSpeed = 10000;
			}
		}
		local wagonEngines = AIEngineList(AIVehicle.VT_RAIL);
		wagonEngines.Valuate(AIEngine.IsWagon);
		wagonEngines.KeepValue(1);
		wagonEngines.Valuate(AIEngine.CanRefitCargo, cargo);
		wagonEngines.KeepValue(1);
		if(railType != null) {
			wagonEngines.Valuate(AIEngine.CanRunOnRail, railType);
			wagonEngines.KeepValue(1);
		}
		if(limitWagonEngines != null) {
			if(limitWagonEngines == 1) {
				foreach(w,v in wagonEngines) {
					local wagonSpeed = AIEngine.GetMaxSpeed(w);
					if(wagonSpeed <= 0) {
						wagonSpeed = 200;
					}
					local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(w);
					if(wagonInfo != null) {
						local wagonCapacity = wagonInfo.cargoCapacity.rawin(cargo) ? wagonInfo.cargoCapacity[cargo] : 0; 
						wagonEngines.SetValue(w,min(railSpeed,wagonSpeed) * wagonCapacity);
					}
				}
			} else {
				wagonEngines.Valuate(AIBase.RandItem);
			}
			if(additonalWagonEngine != null) {
				wagonEngines.RemoveItem(additonalWagonEngine);
				wagonEngines.AddItem(additonalWagonEngine, 4294967295);
				//HgLog.Info("additonalWagonEngine:"+AIEngine.GetName(additonalWagonEngine));
			}
			wagonEngines.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		}
		local countWagonEngines = 0;
		foreach(wagonEngine,v in wagonEngines) {
			local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(wagonEngine);	
			if(wagonInfo == null) {
				HgLog.Warning("wagonInfo==null:"+AIEngine.GetName(wagonEngine));
				continue;
			}
			local wagonCapacity = wagonInfo.cargoCapacity.rawin(cargo) ? wagonInfo.cargoCapacity[cargo] : 0; 
			if(wagonCapacity == 0) {
				HgLog.Warning("wagonCapacity == 0:"+AIEngine.GetName(wagonEngine));
				continue;
			}
			countWagonEngines ++;
			if(limitWagonEngines != null && countWagonEngines > limitWagonEngines) {
				break;
			}
			
			local wagonSpeed = AIEngine.GetMaxSpeed(wagonEngine);
			if(wagonSpeed <= 0) {
				wagonSpeed = 10000;
			}
			wagonSpeed = min(railSpeed, wagonSpeed);
			local wagonRunningCost = AIEngine.GetRunningCost(wagonEngine);
			local wagonPrice = AIEngine.GetPrice(wagonEngine);
			local wagonWeight = AIEngine.GetWeight(wagonEngine);
			local wagonWeightLength = [wagonInfo.length.tofloat() / 16, wagonWeight + GetCargoWeight(cargo, wagonCapacity)];
			
			local trainEngines = AIEngineList(AIVehicle.VT_RAIL);
			trainEngines.Valuate(AIEngine.IsWagon);
			trainEngines.KeepValue(0);
			trainEngines.Valuate(function(e):(cargo) {
				return AIEngine.GetCapacity(e)!=-1 && !AIEngine.CanRefitCargo (e,cargo);
			});
			trainEngines.KeepValue(0);
			if(railType != null) {
				trainEngines.Valuate(AIEngine.HasPowerOnRail, railType);
				trainEngines.KeepValue(1);
			}
			if(limitTrainEngines != null) {
				if(limitTrainEngines == 1) {
					local money = max(200000,AICompany.GetBankBalance(AICompany.COMPANY_SELF));
					trainEngines.Valuate(function(e):(wagonSpeed, money, cargo) {
						return (min(AIEngine.GetMaxSpeed(e) ,wagonSpeed) * (100+AIEngine.GetReliability(e))/200 
							* min(TrainPlanner.GetCargoWeight(cargo,300),AIEngine.GetMaxTractiveEffort(e)) //* min(min(2000, AIEngine.GetMaxTractiveEffort(e)*20),AIEngine.GetPower(e))
							* ((money - (AIEngine.GetPrice(e)+AIEngine.GetRunningCost(e)*5)).tofloat() / money)).tointeger();
					});
				} else {
					trainEngines.Valuate(AIBase.RandItem);
				}
				if(additonalTrainEngine != null) {
					trainEngines.RemoveItem(additonalTrainEngine);
					trainEngines.AddItem(additonalTrainEngine, 4294967295);
					//HgLog.Info("additonalTrainEngine:"+AIEngine.GetName(additonalTrainEngine));
				}
				trainEngines.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
			}
			local countTrainEngines=0;
			foreach(trainEngine,v in trainEngines) {
				local trainRailType = railType != null ? railType : GetSuitestRailType(trainEngine);
				if(trainRailType==null || !AIEngine.CanRunOnRail(wagonEngine, trainRailType)) {
					continue;
				}
				local trainInfo = TrainInfoDictionary.Get().GetTrainInfo(trainEngine);
				if(trainInfo == null) {
					continue;
				}
				countTrainEngines ++;
				if(limitTrainEngines != null && countTrainEngines > limitTrainEngines) {
					break;
				}
				local trainRunningCost = AIEngine.GetRunningCost(trainEngine);
				local trainPrice = AIEngine.GetPrice(trainEngine);
				local trainWeight = AIEngine.GetWeight(trainEngine);
				local trainCapacity = trainInfo.cargoCapacity.rawin(cargo) ? trainInfo.cargoCapacity[cargo] : 0; 
				local trainReiliability = AIEngine.GetReliability(trainEngine);
				local firstRoute = TrainRoute.instances.len()==0 && RoadRoute.instances.len()==0;
				local maxTractiveEffort = AIEngine.GetMaxTractiveEffort(trainEngine);
				local power = AIEngine.GetPower(trainEngine);
				local maxSpeed = min(AIEngine.GetMaxSpeed(trainEngine),wagonSpeed);
				local lengthWeights = [];
				lengthWeights.push([trainInfo.length.tofloat() / 16, trainWeight + GetCargoWeight(cargo, trainCapacity)]);
				for(local numWagon = 0; trainInfo.length + wagonInfo.length * numWagon <= 7 * 16; numWagon+=skipWagonNum) {
					if(numWagon >= 1 && TrainRoute.IsUnsuitableEngineWagon(trainEngine, wagonEngine)) {
						break;
					}
					//HgLog.Info("numWagon"+numWagon);
					local capacity = trainCapacity + wagonCapacity * numWagon;
					if(capacity == 0) {
						continue;
					}
					//local lengthWeights = GetLengthWeightsParams(trainInfo.length, trainWeight, trainCapacity, 1, wagonInfo.length, wagonWeight, wagonCapacity, numWagon);
					local cruiseSpeed = GetSpeed(maxTractiveEffort, power, lengthWeights, 1);
					cruiseSpeed = min(maxSpeed,cruiseSpeed);
					local income = HogeAI.GetCargoIncome(distance, cargo, cruiseSpeed, max(15, capacity * 30 / (production*7/10)))
						* capacity * (trainReiliability+100)/200
							- (trainRunningCost + wagonRunningCost * numWagon);
					if(income <= 0) {
						continue;
					}
					local acceleration = GetAcceleration(10, maxTractiveEffort, power, lengthWeights);
					if(acceleration < 0) {
						break;
					}
					local price = trainPrice + wagonPrice * numWagon;
					if(firstRoute && price * 3 / 2 > HogeAI.GetUsableMoney()) {
						break;
					}
					local roi = income * 100 / price;
					HgLog.Info("income:"+income+" roi:"+roi+" a:"+acceleration+" speed:"+cruiseSpeed+" "+AIEngine.GetName(trainEngine)+"-"+AIEngine.GetName(wagonEngine)+"x"+numWagon+" "+AICargo.GetName(cargo));
					result.push({
						railType = trainRailType
						wagonEngine = numWagon == 0 ? null : wagonEngine
						trainEngine = trainEngine
						numWagon = numWagon
						capacity = capacity
						roi = roi
						income = income
					});
					for(local i=0; i<skipWagonNum; i++) {
						lengthWeights.push(wagonWeightLength);
					}
				}
			}
		}
		return result;
	}
	
	function GetSuitestRailType(trainEngine) {
		local maxSpeed = 0;
		local cost = 0;
		local result = null;
		foreach(railType,v in AIRailTypeList()) {
			if(AIEngine.HasPowerOnRail(trainEngine, railType)) {
				local railSpeed = AIRail.GetMaxSpeed (railType);
				railSpeed = railSpeed == 0 ? 10000 : railSpeed;
				local speed = min(railSpeed, AIEngine.GetMaxSpeed(trainEngine));
				if(maxSpeed == speed) {
					if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 1000000) {
						if(AIRail.GetMaintenanceCostFactor(railType) < AIRail.GetMaintenanceCostFactor(result)) {
							result = railType;
						}
					} else {
						local resultRailSpeed = AIRail.GetMaxSpeed (result);
						resultRailSpeed = resultRailSpeed == 0 ? 10000 : resultRailSpeed;
						if(resultRailSpeed < railSpeed) {
							result = railType;
						}
					}
				} else if(maxSpeed <= speed) {
					maxSpeed = speed;
					result = railType;
				}
			}
		}
		return result;
	}

	function GetCargoWeight(cargo, quantity) {
		return VehicleUtils.GetCargoWeight(cargo, quantity);
	}

	function GetAcceleration(requestSpeed, maxTractiveEffort, power, lengthWeights) {
		local totalWeight = GetLengthWeightsWeight(lengthWeights);
		local slopes = maxSlopes;
		if(selfGetMaxSlopesFunc != null) {
			slopes = selfGetMaxSlopesFunc.GetMaxSlopes(GetLengthWeightsLength(lengthWeights));
		}
		if(slopes == null) {
			slopes = max(1,GetLengthWeightsLength(lengthWeights).tointeger() / 3);
		}
		local force = GetForce(maxTractiveEffort, power, requestSpeed);
		local slopeForce = GetMaxSlopeForce(lengthWeights, slopes, totalWeight);
		//HgLog.Info("maxSlopes:"+maxSlopes+" force:"+force+" slopeForce:"+slopeForce+" totalWeight:"+totalWeight);
		return (force - slopeForce) / (totalWeight * 4);
	}
	
	function GetLengthWeightsWeight(lengthWeights) {
		local result = 0;
		foreach(w in lengthWeights) {
			result += w[1];
		}
		return result;
	}
	
	function GetLengthWeightsLength(lengthWeights) {
		local result = 0;
		foreach(w in lengthWeights) {
			result += w[0];
		}
		return result;
	}
	
	function GetLengthWeightsParams(trainEngineLength, trainWeight, trainCapacity, trainEngineNum, cargoEngineLength, wagonWeight, cargoCapacity, cargoEngineNum) {
		local result = [];
		
		//HgLog.Info("trainEngineLength:"+trainEngineLength+" cargoEngineLength:"+cargoEngineLength);
		for(local i=0; i<trainEngineNum; i++) {
			result.push([trainEngineLength.tofloat() / 16, trainWeight + GetCargoWeight(cargo, trainCapacity)]);
		}
		for(local i=0; i<cargoEngineNum; i++) {
			result.push([cargoEngineLength.tofloat() / 16, wagonWeight + GetCargoWeight(cargo, cargoCapacity)]);
		}
		return result;
	}

	function GetMaxSlopeForce(lengthWeights , maxSlopes, totalWeight) {
		local maxWeight = 0;
		foreach(i,lw in lengthWeights) {
			local l = 0;
			local w = 0;
			while(l < 1 && i<lengthWeights.len()) {
				l += lengthWeights[i][0];
				w += lengthWeights[i][1];
				i++;
			}
			maxWeight = max(maxWeight,w);
		}
		//HgLog.Info("maxWeight:"+maxWeight);
		return VehicleUtils.GetSlopeForce(maxWeight, maxSlopes, totalWeight);
	}
	
	function GetForce(maxTractiveEffort, power, requestSpeed) {
		return VehicleUtils.GetForce(maxTractiveEffort, power, requestSpeed);
	}
	
	function GetSpeed(maxTractiveEffort, power, lengthWeights, maxSlopes) {
		local totalWeight = GetLengthWeightsWeight(lengthWeights);
		local force = GetMaxSlopeForce(lengthWeights, maxSlopes, totalWeight);
	
		if(maxTractiveEffort * 1000 < force) {
			return 0;
		}
		return power * 768 * 18 / 5 / force;
	}

}

class StationPath {
	station = null;
	arrivalPath = null;
	departurePath = null;
	
	constructor(hgStation, buildedArrivalPath, buildedDeparturePath) {
		station = hgStation;
		arrivalPath = buildedArrivalPath;
		departurePath = buildedDeparturePath;
	}
	
	function Save() {
		local t = {};
		t.station <- station.id;
		t.arrivalPath <- arrivalPath.path.Save();
		t.departurePath <- departurePath.path.Save();
		return t;
	}
	
	static function Load(t) {
		return StationPath(
			HgStation.worldInstances[t.station],
			BuildedPath(Path.Load(t.arrivalPath)),
			BuildedPath(Path.Load(t.departurePath)));
	}
	
	
	function GetFacilities() {
		return [station,arrivalPath.path,departurePath.path];
	}
	
	function Remove(){
		station.Remove();
		arrivalPath.Remove();
		departurePath.Remove();
	}
}

class TrainRoute extends Route {
	static instances = [];
	static unsuitableEngineWagons = [];
	
	static RT_ROOT = 1;
	static RT_ADDITIONAL = 2;
	static RT_RETURN = 3;
	
	static USED_RATE_LIMIT = 20;
	
	static function SaveStatics(data) {
		local array = [];
		foreach(route in TrainRoute.instances) {
			local t = {};
			if(route.id == null) { // Removeが完了したroute
				continue;
			}
			t.id <- route.id;
			t.routeType <- route.routeType;
			t.cargo <- route.cargo;
			t.srcHgStation <- route.srcHgStation.id;
			t.destHgStation <- route.destHgStation.id;
			t.pathSrcToDest <- route.pathSrcToDest.array_; //path.Save();
			t.pathDestToSrc <- route.pathDestToSrc.array_; //path.Save();
			t.latestEngineVehicle <- route.latestEngineVehicle;
			t.latestEngineSet <- route.latestEngineSet;
			t.engineVehicles <- HgArray.AIListKey(route.engineVehicles).array;
			t.additionalRoute <- route.additionalRoute != null ? route.additionalRoute.id : null;
			t.parentRoute <- route.parentRoute != null ? route.parentRoute.id : null;
			t.isClosed <- route.isClosed;
			t.isRemoved <- route.isRemoved;
			t.failedUpdateRailType <- route.failedUpdateRailType;
			t.updateRailDepot <- route.updateRailDepot;
			t.startDate <- route.startDate;
			t.destHgStations <- [];
			foreach(station in route.destHgStations) {
				t.destHgStations.push(station.id);
			}
			t.depots <- route.depots;
			t.returnRoute <- route.returnRoute != null ? route.returnRoute.Save() : null;
			t.srcStationSign <- route.srcStationSign;
			t.reduceTrains <- route.reduceTrains;
			t.maxTrains <- route.maxTrains;
			t.slopesTable <- route.slopesTable;
			t.transferRoute <- route.transferRoute != null ? true : false;
			t.usedRateHistory <- route.usedRateHistory;
			t.engineSetsCache <- route.engineSetsCache;
			t.engineSetsDate <- route.engineSetsDate;
			t.engineSetAllRailCache <- route.engineSetAllRailCache;
			t.engineSetAllRailDate <- route.engineSetAllRailDate;
			t.lastTreatStockpile <- route.lastTreatStockpile;
			t.additionalTiles <- route.additionalTiles;

			
//			HgLog.Info("save route:"+route+" additionalRoute:"+route.additionalRoute);
			array.push(t);
		}
		data.trainRoutes <- array;
		
		data.unsuitableEngineWagons <- TrainRoute.unsuitableEngineWagons;
	}
	
	static function LoadStatics(data) {
		TrainRoute.instances.clear();
		local idMap = {};
		foreach(t in data.trainRoutes) {
			local destHgStations = [];
			foreach(stationId in t.destHgStations) {
				destHgStations.push(HgStation.worldInstances[stationId]);
			}
			local trainRoute = TrainRoute(
				t.routeType, 
				t.cargo, 
				HgStation.worldInstances[t.srcHgStation], 
				HgStation.worldInstances[t.destHgStation], 
				BuildedPath(Path.Load(t.pathSrcToDest)),
				BuildedPath(Path.Load(t.pathDestToSrc)));
			trainRoute.id = t.id;
			TrainRoute.idCounter.Skip(trainRoute.id);
			trainRoute.latestEngineVehicle = t.latestEngineVehicle;
			trainRoute.latestEngineSet = t.latestEngineSet;
			trainRoute.engineVehicles = HgArray(t.engineVehicles).GetAIList();
			trainRoute.isClosed = t.isClosed;
			trainRoute.isRemoved = t.rawin("isRemoved") ? t.isRemoved : false;
			trainRoute.failedUpdateRailType = t.rawin("failedUpdateRailType") ? t.failedUpdateRailType : false;
			trainRoute.updateRailDepot = t.updateRailDepot;
			trainRoute.startDate = t.startDate;
			trainRoute.destHgStations = destHgStations;
			
			trainRoute.depots = t.depots;
			if(t.returnRoute != null) {
				trainRoute.returnRoute = TrainReturnRoute.Load(t.returnRoute);
				trainRoute.returnRoute.originalRoute = trainRoute;			
				PlaceDictionary.Get().AddRoute(trainRoute.returnRoute);

			}
			trainRoute.srcStationSign = t.rawin("srcStationSign") ? t.srcStationSign : null;
			trainRoute.reduceTrains = t.rawin("reduceTrains") ? t.reduceTrains : false;
			trainRoute.maxTrains = t.rawin("maxTrains") ? t.maxTrains : null;
			trainRoute.slopesTable = t.slopesTable;
			trainRoute.engineSetsCache = t.engineSetsCache;
			trainRoute.engineSetsDate = t.engineSetsDate;
			trainRoute.engineSetAllRailCache = t.engineSetAllRailCache;
			trainRoute.engineSetAllRailDate = t.engineSetAllRailDate;
			trainRoute.lastTreatStockpile = t.lastTreatStockpile;
			trainRoute.additionalTiles = t.additionalTiles;
			//trainRoute.usedRateHistory = t.rawin("usedRateHistory") ? t.usedRateHistory : [];
			
			idMap[t.id] <- trainRoute;
			TrainRoute.instances.push(trainRoute);
			PlaceDictionary.Get().AddRoute(trainRoute);
		}
		foreach(t in data.trainRoutes) {
			local trainRoute = idMap[t.id];
			if(t.additionalRoute != null) {
				trainRoute.additionalRoute = idMap[t.additionalRoute];
			}
			if(t.parentRoute != null) {
				trainRoute.parentRoute = idMap[t.parentRoute];
			}
			if(t.transferRoute) {
				local destGroupStations = HgArray(trainRoute.destHgStation.stationGroup.hgStations);
				foreach(route in TrainRoute.GetAll()) {
					if(destGroupStations.Contains(route.srcHgStation)) {
						trainRoute.transferRoute = route;
						break;
					}
				}
			}
			HgLog.Info("load route:"+trainRoute+" transferRoute:"+trainRoute.transferRoute);
		}
		
		TrainRoute.unsuitableEngineWagons.clear();
		TrainRoute.unsuitableEngineWagons.extend(data.unsuitableEngineWagons);
	}
	
	static function GetAll() {
		local routes = [];
		routes.extend(TrainRoute.instances);
		foreach(trainRoute in TrainRoute.instances) {
			if(trainRoute.returnRoute != null) {
				routes.push(trainRoute.returnRoute);
			}
		}
		return routes;
	}
	
	
	
	
	static function IsUnsuitableEngineWagon(trainEngine, wagonEngine) {
		foreach(pair in TrainRoute.unsuitableEngineWagons) {
			if(pair[0] == trainEngine && pair[1] == wagonEngine) {
				return true;
			}
		}
		return false;
	}
	
	static idCounter = IdCounter();
	
	id = null;
	routeType = null;
	cargo = null;
	srcHgStation = null;
	destHgStation = null;
	pathSrcToDest = null;
	pathDestToSrc = null;
	
	startDate = null;
	destHgStations = null;
	depots = null;
	returnRoute = null;
	latestEngineVehicle = null;
	engineVehicles = null;
	latestEngineSet = null;
	additionalRoute = null;
	parentRoute = null;
	isClosed = null;
	isRemoved = null;
	updateRailDepot = null;
	srcStationSign = null;
	failedUpdateRailType = null;
	reduceTrains = null;
	maxTrains = null;
	slopesTable = null;
	trainLength = null;
	transferRoute = null;
	usedRateHistory = null;
	engineSetsCache = null;
	engineSetsDate = null;
	engineSetAllRailCache = null;
	engineSetAllRailDate = null;
	lastTreatStockpile = null;
	additionalTiles = null;
	
	averageUsedRate = null;
	isBuilding = null;
	usedRateCache = null;

	constructor(routeType, cargo, srcHgStation, destHgStation, pathSrcToDest, pathDestToSrc){
		this.id = idCounter.Get();
		this.routeType = routeType;
		this.cargo = cargo;
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.pathSrcToDest = pathSrcToDest;
		this.pathDestToSrc = pathDestToSrc;
		this.destHgStations = [];
		this.engineVehicles = AIList();
		this.isClosed = false;
		this.isRemoved = false;
		this.depots = [];
		this.isBuilding = false;
		this.failedUpdateRailType = false;
		this.reduceTrains = false;
		this.usedRateHistory = [];
		this.slopesTable = {};
		this.trainLength = 7;
		this.additionalTiles = [];
	}
	
	function GetFinalDestPlace() {
		return GetFinalDestStation().place;
	}
	
	
	function GetFinalDestStation() {
		return transferRoute != null ? transferRoute.GetFinalDestStation() : destHgStation;
	}
	
	function AddDepot(depot) {
		if(depot != null) {
			depots.push(depot);
		}
	}
	
	function AddDepots(depots) {
		if(depots != null) {
			this.depots.extend(depots);
		}
	}
	
	function AddAdditionalTiles(tiles) {
		additionalTiles.extend(tiles);
	}
	
	function IsNotAdditional() {
		return parentRoute == null;
	}
	
	function IsClosed() {
		return isClosed;
	}
	
	function GetEngineSets(isAll=false) {
		if(!isAll && engineSetsCache != null && ( AIDate.GetCurrentDate() < engineSetsDate || TrainRoute.instances.len()<=1)) {
			return engineSetsCache;
		}
	
		local execMode = AIExecMode();
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.distance = GetDistance();
		trainPlanner.production = max(50,srcHgStation.place.GetLastMonthProduction(cargo));
		trainPlanner.railType = GetRailType();
		trainPlanner.selfGetMaxSlopesFunc = this;
		trainPlanner.additonalTrainEngine = latestEngineSet != null ? latestEngineSet.trainEngine : null;
		trainPlanner.additonalWagonEngine = latestEngineSet != null ? latestEngineSet.wagonEngine : null;
		if(isAll) {
			trainPlanner.limitWagonEngines = null;
			trainPlanner.limitTrainEngines = null;		
		} else if(latestEngineSet == null) {
			trainPlanner.limitWagonEngines = 3;
			trainPlanner.limitTrainEngines = 10;		
		}
//		HgLog.Info("trainPlanner.GetEngineSetsOrder "+this+" production:"+trainPlanner.production);
		engineSetsCache = trainPlanner.GetEngineSetsOrder();
		engineSetsDate = AIDate.GetCurrentDate() + 1000 + AIBase.RandRange(100);
		if(engineSetsCache.len()>=1) {
			//HgLog.Info("GetEngineSets income:"+engineSetsCache[0].income+" roi:"+engineSetsCache[0].roi+" production:"+trainPlanner.production+" "+this);
		}
		return engineSetsCache;
	}
	
	function ChooseEngineSetAllRailTypes() {
		if(engineSetAllRailCache != null) {
			if(AIDate.GetCurrentDate() < engineSetAllRailDate) {
				return engineSetAllRailCache;
			}
		}
		local execMode = AIExecMode();
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.distance = GetDistance();
		trainPlanner.production = max(50,srcHgStation.place.GetLastMonthProduction(cargo));
		trainPlanner.selfGetMaxSlopesFunc = this;
		trainPlanner.additonalTrainEngine = latestEngineSet != null ? latestEngineSet.trainEngine : null;
		trainPlanner.additonalWagonEngine = latestEngineSet != null ? latestEngineSet.wagonEngine : null;
		trainPlanner.limitWagonEngines = 3;
		trainPlanner.limitTrainEngines = 10;
		trainPlanner.skipWagonNum = 3;
		//HgLog.Info("trainPlanner.GetEngineSetsOrder(ChooseEngineSetAllRailTypes) "+this+" production:"+trainPlanner.production);
		local sets = trainPlanner.GetEngineSetsOrder();
		if(sets.len() >= 1) {
			engineSetAllRailCache = sets[0];
		}
		engineSetAllRailDate = AIDate.GetCurrentDate() + 1600 + AIBase.RandRange(400);
		return engineSetAllRailCache;
	}

	function AddUnsuitableEngineWagon(trainEngine, wagonEngine) {
		unsuitableEngineWagons.push([trainEngine,wagonEngine]);
		if(engineSetsCache != null) {
			local newCache = [];
			foreach(engineSet in engineSetsCache) {
				if(!(engineSet.trainEngine == trainEngine && engineSet.wagonEngine == wagonEngine)) {
					newCache.push(engineSet);
				}
			}
			engineSetsCache = newCache;
		}
	}
	
	function ChooseEngineSet() {
		local a = GetEngineSets();
		if(a.len() == 0){ 
			return null;
		}
		return a[0];
	}
	
	function BuildFirstTrain() {
		latestEngineVehicle = BuildTrain(); //TODO 最初に失敗すると復活のチャンスなし。orderが後から書き変わる事があるがそれが反映されないため。orderを状態から組み立てられる必要がある
		if(latestEngineVehicle == null) {
			HgLog.Warning("BuildFirstTrain failed. "+this);
			return false;
		}
		BuildOrder(latestEngineVehicle);
		engineVehicles.AddItem(latestEngineVehicle,latestEngineVehicle);
		AIVehicle.StartStopVehicle(latestEngineVehicle);
		if(startDate == null) {
			startDate = AIDate.GetCurrentDate();
			destHgStations.push(destHgStation);
		}
		return true;
	}
	
	function CloneAndStartTrain() {
		if(latestEngineVehicle == null) {
			BuildFirstTrain();
			return;
		}
		
		local train = null;
		local engineSet = ChooseEngineSet();
		if(engineSet != null && latestEngineSet != null &&
				(engineSet.trainEngine != latestEngineSet.trainEngine ||  engineSet.wagonEngine != latestEngineSet.wagonEngine)) {
			train = BuildTrain();	
		} else {
			train = CloneTrain();
			if(train == null) {
				train = BuildTrain();
			}
		}
		if(train != null) {
			engineVehicles.AddItem(train,train);
			AIOrder.ShareOrders(train, latestEngineVehicle);
			AIVehicle.StartStopVehicle(train);
			latestEngineVehicle = train;
		}
	}
	
	function CloneTrain() {
		local execMode = AIExecMode();
		if(this.latestEngineVehicle == null) {
			return null;
		}
		local engineVehicle = null;
		for(local need=50000;; need+= 10000) {
			HogeAI.WaitForMoney(need);
			engineVehicle = AIVehicle.CloneVehicle(srcHgStation.GetDepotTile(), this.latestEngineVehicle, true);
			if(AIError.GetLastError()!=AIError.ERR_NOT_ENOUGH_CASH) {
				break;
			}
		}
		if(!AIVehicle.IsValidVehicle(engineVehicle)) {
			HgLog.Warning("CloneVehicle failed. "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		return engineVehicle;
	}
	
	function BuildEngineVehicle(engineVehicles, trainEngine, explain) {
		HogeAI.WaitForPrice(AIEngine.GetPrice(trainEngine));
		local depotTile = srcHgStation.GetDepotTile();
		local engineVehicle = AIVehicle.BuildVehicle(depotTile, trainEngine);
		if(!AIVehicle.IsValidVehicle(engineVehicle)) {
			local error = AIError.GetLastError();
			HgLog.Warning("BuildVehicle failed. "+explain+" "+AIError.GetLastErrorString());
			if(engineVehicles.len() >= 1) {
				AIVehicle.SellWagonChain(engineVehicles[0], 0);
			}
			if(error == AIVehicle.ERR_VEHICLE_TOO_MANY) {
				return null;
			}
			return false;
		}
		AIVehicle.RefitVehicle(engineVehicle, cargo);
		if(engineVehicles.len() >= 1 && !AIVehicle.MoveWagonChain(engineVehicle, 0, engineVehicles[0], engineVehicles.len()-1)) {
			HgLog.Warning("MoveWagonChain engineVehicle failed. "+explain + " "+AIError.GetLastErrorString());
			AIVehicle.SellWagonChain(engineVehicles[0], 0);
			AIVehicle.SellWagonChain(engineVehicle, 0);
			return false;
		}
		engineVehicles.push(engineVehicle);
		return true;
	}

	function BuildTrain(isAll=false) {
		local execMode = AIExecMode();
		foreach(engineSet in GetEngineSets(isAll)) {
			local trainEngine = engineSet.trainEngine;
			local wagonEngine = engineSet.wagonEngine;
			if(wagonEngine != null && TrainRoute.IsUnsuitableEngineWagon(trainEngine, wagonEngine)) {
				continue;
			}
			local numWagon = engineSet.numWagon;
			local capacity = engineSet.capacity;
			local depotTile = srcHgStation.GetDepotTile();
			local explain = AIEngine.GetName(trainEngine);
			if(wagonEngine!=null) {
				explain += "-"+AIEngine.GetName(wagonEngine)+"x"+numWagon;
			}
			explain += " depot:"+HgTile(depotTile)+" "+this;
			HgLog.Info("BuildTrain income:"+engineSet.income+" roi:"+engineSet.roi+" "+explain+" "+this);
			
			//HgLog.Info("Try build "+explain);

			
			local numEngineVehicle = 1;
			local engineVehicles = [];
			
			local r = BuildEngineVehicle(engineVehicles, trainEngine, explain);
			if(r == null) {
				return null;
			} else if(!r) {
				continue;
			}
						
			local engineVehicle = engineVehicles[0];
			local engineLength = AIVehicle.GetLength(engineVehicle).tofloat() / 16;
			local firstWagon = null;
			if(numWagon >= 1) {
				HogeAI.WaitForPrice(AIEngine.GetPrice(wagonEngine));

				firstWagon = AIVehicle.BuildVehicle(depotTile, wagonEngine);
				if(!AIVehicle.IsValidVehicle(firstWagon)) {
					HgLog.Warning("BuildVehicle wagon failed. "+explain+" "+AIError.GetLastErrorString());
					AddUnsuitableEngineWagon(trainEngine,wagonEngine);
					AIVehicle.SellWagonChain(engineVehicle, 0);
					continue;
				}
				if (AIEngine.GetCargoType(wagonEngine) != cargo) {
					if(!AIVehicle.RefitVehicle(firstWagon, cargo)) {
						HgLog.Warning("RefitVehicle failed. "+explain+" "+AIError.GetLastErrorString());
						AddUnsuitableEngineWagon(trainEngine,wagonEngine);
						AIVehicle.SellWagonChain(engineVehicle, 0);
						AIVehicle.SellWagonChain(firstWagon, 0);
						continue;
					}
				}
			}
			local success = true;
			for(local i=0; i<numEngineVehicle-1; i++) {
				local r = BuildEngineVehicle(engineVehicles, trainEngine, explain);
				if(r == null) {
					if(firstWagon != null) {
						AIVehicle.SellWagonChain(firstWagon, 0);
					}
					return null;
				} else if(!r) {
					success = false;
					break;
				}
			}
			if(!success) {
				unsuitableEngineWagons.push([trainEngine,wagonEngine]);
				if(firstWagon != null) {
					AIVehicle.SellWagonChain(firstWagon, 0);
				}
				continue;
			}

			if(firstWagon != null && !AIVehicle.MoveWagonChain(firstWagon, 0, engineVehicle, AIVehicle.GetNumWagons(engineVehicle) - 1)) {
				if(numEngineVehicle==1) { //numEngineVehicle>=2の時、なぜかMoveWagonChain不要の時がある
					HgLog.Warning("MoveWagonChain failed. "+explain+" "+AIError.GetLastErrorString());
					AddUnsuitableEngineWagon(trainEngine,wagonEngine);
					AIVehicle.SellWagonChain(engineVehicle, 0);
					AIVehicle.SellWagonChain(firstWagon, 0);
					continue;
				}
			}
			
			for(local i=0; i<numWagon-1; i++) {
				HogeAI.WaitForPrice(AIEngine.GetPrice(wagonEngine));
				local wagon = AIVehicle.BuildVehicle(depotTile, wagonEngine);
				if(!AIVehicle.IsValidVehicle(wagon))  {
					HgLog.Warning("IsValidVehicle wagon2 failed. "+explain+" "+AIError.GetLastErrorString());
					break;
				}
				if(!AIVehicle.RefitVehicle(wagon, cargo)) {
					HgLog.Warning("RefitVehicle wagon2 failed. "+explain+" "+AIError.GetLastErrorString());
					AIVehicle.SellWagonChain(wagon, 0);
					break;
				}
				if(!AIVehicle.MoveWagonChain(wagon, 0, engineVehicle, AIVehicle.GetNumWagons(engineVehicle)-1)) {
					HgLog.Warning("MoveWagonChain wagon2 failed. "+explain + " "+AIError.GetLastErrorString());
					AIVehicle.SellWagonChain(wagon, 0);
					break;
				}
			}
			
			
			latestEngineSet = engineSet;
			return engineVehicle;
		}
		
		if(!isAll) {
			HgLog.Warning("BuildTrain failed. Try all enginsets. ("+AIRail.GetName(GetRailType())+") "+this);
			return BuildTrain(true);
		}
		
		HgLog.Warning("BuildTrain failed. No suitable engineSet. ("+AIRail.GetName(GetRailType())+") "+this);
		engineSetsCache = null;
		return null;
	}
	

	function GetTotalWeight(trainEngine, wagonEngine, trainNum, wagonNum, cargo) {
		return AIEngine.GetWeight(trainEngine) * trainNum + (AIEngine.GetWeight(wagonEngine) + TrainRoute.GetCargoWeight(cargo,AIEngine.GetCapacity(wagonEngine))) * wagonNum;
	}
	
	function GetMaxSlopes(length) {
		length = ceil(length).tointeger();
		if(slopesTable.rawin(length)) {
			return slopesTable[length];
		}
		local result = 0;
		result = max(result, pathSrcToDest.path.GetSlopes(length));
		//result = max(result, pathDestToSrc.path.GetSlopes(length));
		if(parentRoute != null) {
			result = max(result, parentRoute.GetMaxSlopes(length));
		}
		slopesTable[length] <- result;
		return result;
	}
		
	function IsBiDirectional() {
		return transferRoute == null && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
	}
	
	function BuildOrder(engineVehicle) {
		local execMode = AIExecMode();
		AIOrder.AppendOrder(engineVehicle, srcHgStation.platformTile, AIOrder.OF_FULL_LOAD_ANY + AIOrder.OF_NON_STOP_INTERMEDIATE);
		AIOrder.AppendOrder(engineVehicle, srcHgStation.GetServiceDepotTile(), AIOrder.OF_SERVICE_IF_NEEDED);
		if(transferRoute!=null) {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_TRANSFER + AIOrder.OF_NO_LOAD );
		} else if(IsBiDirectional()) {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
		} else {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		}
		return true;
	}
	

	function AddDestination(destHgStation) {
		destHgStations.push(destHgStation);
		ChangeDestination(destHgStation);
		maxTrains = null;
		lastTreatStockpile = null;
		slopesTable.clear();
		if(additionalRoute != null) {
			additionalRoute.slopesTable.clear();
		}
	}

	function ChangeDestination(destHgStation) {
		local execMode = AIExecMode();

		local oldPlace = this.destHgStation.place;
		this.destHgStation = destHgStation;
		PlaceDictionary.Get().ChangeDest(this, oldPlace);

		if(latestEngineVehicle != null) {
			local orderFlags = AIOrder.OF_NON_STOP_INTERMEDIATE + (IsBiDirectional() ? 0 : AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		
			if(AIOrder.GetOrderCount (latestEngineVehicle) >= 4) {
				AIOrder.InsertOrder(latestEngineVehicle, 3, destHgStation.platformTile, orderFlags);
			} else {
				AIOrder.AppendOrder(latestEngineVehicle, destHgStation.platformTile, orderFlags);
			}
			AIOrder.RemoveOrder(latestEngineVehicle, 2);
		}
		if(additionalRoute != null) {
			additionalRoute.AddDestination(destHgStation);
		}
	}
	
	function AddReturnTransferOrder(transferSrcStation, destStation) {
		local execMode = AIExecMode();
		if(latestEngineVehicle != null) {
			AIOrder.AppendOrder(latestEngineVehicle, transferSrcStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
			local conditionOrderPosition = AIOrder.GetOrderCount(latestEngineVehicle);
			AIOrder.AppendConditionalOrder (latestEngineVehicle, 0);
			AIOrder.SetOrderCompareValue(latestEngineVehicle, conditionOrderPosition, 0);
			AIOrder.SetOrderCompareFunction(latestEngineVehicle, conditionOrderPosition, AIOrder.CF_EQUALS );
			AIOrder.SetOrderCondition(latestEngineVehicle, conditionOrderPosition, AIOrder.OC_LOAD_PERCENTAGE );
			AIOrder.AppendOrder(latestEngineVehicle, destStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD );
		}
	}
	
	function RemoveReturnTransferOder() {
		local execMode = AIExecMode();
		if(latestEngineVehicle != null && AIOrder.GetOrderCount (latestEngineVehicle)>=5) {
			AIOrder.RemoveOrder(latestEngineVehicle, 5);
			AIOrder.RemoveOrder(latestEngineVehicle, 4);
			AIOrder.RemoveOrder(latestEngineVehicle, 3);
		}
	}
	
	
	function AddSendUpdateDepotOrder() {
		local execMode = AIExecMode();
		AIOrder.InsertOrder(latestEngineVehicle, 0, updateRailDepot, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_STOP_IN_DEPOT );
	}
	
	function RemoveSendUpdateDepotOrder() {
		local execMode = AIExecMode();
		AIOrder.RemoveOrder(latestEngineVehicle,0);
	}
	
	function AddAdditionalRoute(additionalRoute) {
		this.additionalRoute = additionalRoute;
		additionalRoute.parentRoute = this;
	}
	
	
	function GetLastRoute() {
		if(additionalRoute == null) {
			return this;
		} else {
			return additionalRoute.GetLastRoute();
		}
	}
	
	function GetLastSrcHgStation() {
		return additionalRoute==null ? srcHgStation : additionalRoute.GetLastSrcHgStation();
	}
	
	function GetSrcStationTiles() {
		local result = [srcHgStation.platformTile];
		if(additionalRoute != null) {
			result.extend(additionalRoute.GetSrcStationTiles());
		}
		return result;
	}
	
	function GetTakeAllPathSrcToDest() {
		local result = pathSrcToDest.path;
		if(additionalRoute != null) {
			result = result.SubPathEnd(additionalRoute.pathSrcToDest.path.GetTile());
		}
		return result;
	}

	function GetTakeAllPathDestToSrc() {
		local result = pathDestToSrc.path;
		if(additionalRoute != null) {
			result = result.SubPathStart(additionalRoute.pathDestToSrc.path.GetLastTile());
		}
		return result;
	}

	function GetPathAllDestToSrc() {
		if(parentRoute != null) {
			return pathDestToSrc.path.Combine(parentRoute.GetTakeAllPathDestToSrc());
		} else {
			return pathDestToSrc.path;
		}
	}
	
	
	function IsAllVehicleLocation(location) {
		
		foreach(engineVehicle, v in engineVehicles) {
			if(AIVehicle.GetLocation(engineVehicle) != location) {
//				HgLog.Info("IsAllVehicleLocation false:"+HgTile(AIVehicle.GetLocation(engineVehicle))+" loc:"+HgTile(location));
				return false;
			}
		}
		return true;
	}
	
	function GetRailType() {
		return AIRail.GetRailType(srcHgStation.platformTile);
	}
	
	function StartUpdateRail(railType) {
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 1000000) {
			return false;
		}
		local exec = AIExecMode();
		
		if(latestEngineVehicle != null) {
			HgLog.Info("StartUpdateRail "+AIRail.GetName(railType)+" "+this);
			
			local railType = AIRail.GetCurrentRailType();
			AIRail.SetCurrentRailType ( GetRailType() );
			updateRailDepot = pathDestToSrc.path.BuildDepot();
			AIRail.SetCurrentRailType(railType);
			if(updateRailDepot == null) {
				HgLog.Warning("Cannot build depot for railupdate "+this);
				return false;
			}
			AddSendUpdateDepotOrder();
		}
	}
	
	function ConvertRailType(railType) {
		HgLog.Info("ConvertRailType." + AIRail.GetName(railType) + "<=" + AIRail.GetName(GetRailType()) + " " + this);
		local execMode = AIExecMode();
		local facitilies = [];
		facitilies.push(srcHgStation);
		foreach(s in destHgStations) {
			facitilies.push(s);
		}
		facitilies.push(pathSrcToDest.path);
		facitilies.push(pathDestToSrc.path);
		facitilies.extend(returnRoute != null ? returnRoute.GetFacilities():[]);
		local tiles = [];
		foreach(f in facitilies) {
			if(f != null) {
				tiles.extend(f.GetTiles());
			}
		}
		tiles.extend(depots);
		tiles.extend(additionalTiles);
		
		foreach(t in tiles) {
			if(AIRail.GetRailType(t)==railType) {
				continue;
			}
			if(!BuildUtils.RetryUntilFree(function():(t,railType) {
				return AIRail.ConvertRailType(t,t,railType);
			})) {
				HgLog.Warning("ConvertRailType failed:"+HgTile(t));
				return false;
			}
		}
		return true;
	}
	
	
	function IsAllVehicleInUpdateRailDepot() {
		if(additionalRoute != null) {
			if(!additionalRoute.IsAllVehicleInUpdateRailDepot()) {
				return false;
			}
		}
		return IsAllVehicleLocation(updateRailDepot);
	}
	
	function DoUpdateRailType(newRailType) {
		local execMode = AIExecMode();
		HgLog.Info("DoUpdateRailType: "+AIRail.GetName(newRailType)+" "+this);
		if(!ConvertRailType(newRailType)) {
			updateRailDepot = null;
			return false;
		}
		engineSetsCache = null;
		local newTrain = BuildTrain();
		if(newTrain == null) {
			HgLog.Warning("newTrain == null");
			updateRailDepot = null;
			return false;
		}
		AIOrder.ShareOrders(newTrain, latestEngineVehicle);
		foreach(engineVehicle,v in engineVehicles) {
			AIVehicle.SellWagonChain(engineVehicle, 0);
		}
		engineVehicles.Clear();
		AITile.DemolishTile(updateRailDepot);
		updateRailDepot = null;
		
		latestEngineVehicle = newTrain;
		engineVehicles.AddItem(newTrain,newTrain);			
		RemoveSendUpdateDepotOrder();

		AIVehicle.StartStopVehicle(newTrain);
		return true;
	}
	
	
	
	
	function OnVehicleWaitingInDepot(engineVehicle) {
		local execMode = AIExecMode();
		if(isClosed || reduceTrains) {
			if(isRemoved || latestEngineVehicle != engineVehicle) { //reopenに備えてlatestEngineVehicleだけ残す
				AIVehicle.SellWagonChain(engineVehicle, 0);
				engineVehicles.RemoveItem(engineVehicle);
				if(engineVehicles.Count() == 0) {
					HgLog.Info("Remove route: "+this);
					srcHgStation.Remove();
					destHgStation.Remove();
					pathSrcToDest.Remove();
					pathDestToSrc.Remove();
					id = null;
				}
			}
		} else if(updateRailDepot != null) {
			if(AIVehicle.GetLocation(engineVehicle) != updateRailDepot) {
				AIVehicle.StartStopVehicle(engineVehicle);
			}
		} else {
			RenewalTrain(engineVehicle);
		}
	}
	
	function RenewalTrain(engineVehicle) {
		local execMode = AIExecMode();
		if(latestEngineVehicle == null) {
			return;
		}
		if(engineVehicle == latestEngineVehicle) {
			local newtrain;
			if(engineVehicle == latestEngineVehicle) {
				newtrain = BuildTrain();
			}/* else {
				if(!IsEqualEngine(latestEngineVehicle, engineVehicle)) {
					newtrain = CloneTrain();
					if(newtrain == null) {
						newtrain = BuildTrain();
					}
				} else {		
					newtrain = BuildTrain();
				}
			}*/
			if(newtrain == null) {
				return;
			}
			engineVehicles.AddItem(newtrain,newtrain);
			AIOrder.ShareOrders(newtrain, latestEngineVehicle);
			latestEngineVehicle = newtrain;
			AIVehicle.StartStopVehicle(newtrain);
		}
		
		engineVehicles.RemoveItem(engineVehicle);
		AIVehicle.SellWagonChain(engineVehicle, 0);
	}
	
	function IsEqualEngine(vehicle1, vehicle2) {
		return AIVehicle.GetEngineType(vehicle1) == AIVehicle.GetEngineType(vehicle2) &&
			AIVehicle.GetWagonEngineType (vehicle1,0) == AIVehicle.GetWagonEngineType(vehicle2,0);
	}

	function OnIndustoryClose(industry) {
		local destPlace = GetFinalDestPlace();
		if(destPlace != null && (destPlace instanceof HgIndustry) && destPlace.industry == industry) {
			HgLog.Warning("Close dest industry:"+AIIndustry.GetName(industry));
			isClosed = true;
			Close();
		}
	}
	
	function Close() {
		HgLog.Warning("Close route start:"+this);
		isClosed = true;
		local execMode = AIExecMode();
		foreach(engineVehicle, v in engineVehicles) {
			//HgLog.Info("SendVehicleToDepot for renewal:"+engineVehicle+" "+ToString());
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(engineVehicle, AIOrder.ORDER_CURRENT)) == 0) {
				AIVehicle.SendVehicleToDepot (engineVehicle);
			}
			
		}
		if(additionalRoute != null) {
			additionalRoute.Close();
		}
	}	
	
	function Remove() {					
		HgLog.Info("Remove route start: "+this);
		isRemoved = true;
		Close();
	}

	function ReOpen() {
		HgLog.Warning("ReOpen route:"+this);
		isClosed = false;
		PlaceDictionary.Get().AddRoute(this);
		//BuildFirstTrain();
	}
	
	
	function IsInStationOrDepot(){
		foreach(vehicle, v in engineVehicles) {
			if(AIStation.GetStationID(AIVehicle.GetLocation(vehicle)) == srcHgStation.GetAIStation() 
					|| AIVehicle.IsInDepot (vehicle)) {
				return true;
			}
		}
		return false;
	}
	
	function GetMaxSpeed() {
		if(latestEngineVehicle == null) {
			return null;
		}
		local trainEngine = AIVehicle.GetEngineType( latestEngineVehicle );
		local wagonEngine = AIVehicle.GetWagonEngineType( latestEngineVehicle, 1 );
		local maxSpeed = AIEngine.GetMaxSpeed(trainEngine);
		local wagonMaxSpeed = AIEngine.GetMaxSpeed(wagonEngine);
		if(wagonMaxSpeed > 0) {
			maxSpeed = min(maxSpeed, wagonMaxSpeed);
		}
		local railMaxSpeed = AIRail.GetMaxSpeed(GetRailType());
		if(railMaxSpeed > 0) {
			maxSpeed = min(maxSpeed, railMaxSpeed);
		}
		return maxSpeed;
	}
	
	function GetAverageSpeed() {
		local sum = 0;
		local count = 0;
		foreach(vehicle, v in engineVehicles) {
			local state = AIVehicle.GetState(vehicle);
			if(state == AIVehicle.VS_AT_STATION || AIVehicle.IsInDepot(vehicle)) {
				continue;
			}
			if( AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT) != 1) {
				continue;
			}
			sum += min(100,AIVehicle.GetCurrentSpeed(vehicle));
			count ++;
		}
		if(count == 0) {
			return null;
		}
		return sum / count;
	}
	
	function GetUsedRate() {
		if(usedRateCache == null) {
			usedRateCache = _GetUsedRate();
		}
		return usedRateCache;
	}
	
	function _GetUsedRate() {
		local maxSpeed = GetMaxSpeed();
		if(maxSpeed == null) {
			return 0;
		}
		maxSpeed = min(100,maxSpeed);
		local averageSpeed = GetAverageSpeed();
		if(averageSpeed == null) {
			return 0;
		}
		return ((1 - (averageSpeed.tofloat() / maxSpeed))*100).tointeger();
	}
	
	
	
	function RemoveReturnRoute() {
		RemoveReturnTransferOder();
		if(returnRoute != null) {
			returnRoute.Remove();
			returnRoute = null;
		}
	}
	
	function IsAllVehiclePowerOnRail(newRailType) {
		foreach(vehicle in engineVehicles) {
			local engine = AIVehicle.GetEngineType(vehicle);
			if(!AIEngine.HasPowerOnRail(engine, newRailType)) {
				return false;
			}
		}
		return true;
	}
	
	function RollbackUpdateRailType(railType) {
		HgLog.Warning("RollbackUpdateRailType "+this+" additionalRoute:"+additionalRoute+" v:"+engineVehicles.Count());
		failedUpdateRailType = true;
		updateRailDepot = null;
		ConvertRailType(railType);
		AIOrder.RemoveOrder(latestEngineVehicle,AIOrder.GetOrderCount(latestEngineVehicle)-1);
		foreach(engineVehicle,v in engineVehicles) {
			if(AIVehicle.IsStoppedInDepot(engineVehicle)) {
				AIVehicle.StartStopVehicle(engineVehicle);
			}
		}
		if(additionalRoute != null) {
			additionalRoute.RollbackUpdateRailType(railType);
		}
	}
	function GetDistance() {
		return AIMap.DistanceManhattan(srcHgStation.platformTile, destHgStation.platformTile);
	}

	function NeedsAdditionalProducing(orgRoute = null, isDest = false) {
		if(isClosed || reduceTrains) {
			return false;
		}
		
		if(!isDest && transferRoute != null) {
			return transferRoute.NeedsAdditionalProducing(orgRoute);
		}
		local hgStation = isDest ? destHgStation : srcHgStation;
		local limitCapacity = latestEngineSet == null ? 400 : latestEngineSet.capacity;
		if(isDest == false) {
			limitCapacity /= 2;
		}
		local result = (averageUsedRate == null || averageUsedRate < TrainRoute.USED_RATE_LIMIT) && AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) < limitCapacity;
		//HgLog.Info("NeedsAdditionalProducing rail:"+result+" "+this)
		return result;
	}
	
	function IsOverflow(isDest = false) {
		local hgStation = isDest ? destHgStation : srcHgStation;
		return averageUsedRate != null 
			&& averageUsedRate > TrainRoute.USED_RATE_LIMIT
			&& AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) > 1000;
	}
	
	

	
	function CalculateAverageUsedRate(usedRate) {
		local result = null;
		if(usedRateHistory.len() == 5) {
			local a = [];
			local sum = 0;
			foreach(i,e in usedRateHistory) {
				if(i == 0) {
					continue;
				}
				sum += e;
				a.push(e);
			}
			usedRateHistory = a;
			sum += usedRate;
			result = sum / 5;
		}
		usedRateHistory.push(usedRate);
		return result;
	}
	
	function IsCloneTrain() {
		return (maxTrains == null || maxTrains > engineVehicles.Count())
			&& !IsInStationOrDepot() 
			&& (averageUsedRate == null || averageUsedRate < TrainRoute.USED_RATE_LIMIT)
			&& (AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 500000 || 
				(latestEngineSet==null || AIStation.GetCargoWaiting (srcHgStation.GetAIStation(), cargo) >= latestEngineSet.capacity / 2));
	}
	
	function CheckCloneTrain() {
		if(isClosed || updateRailDepot!=null) {
			return;
		}
		
		if(transferRoute != null && !transferRoute.NeedsAdditionalProducing()) {
			return;
		}
		
		local usedRate = GetUsedRate();
		averageUsedRate = CalculateAverageUsedRate(usedRate);
		//HgLog.Info("averageUsedRate:"+averageUsedRate+" "+this);
		
		
		if(averageUsedRate != null && !reduceTrains && additionalRoute!=null) {
			if(averageUsedRate > 50) {
				if(engineVehicles.Count() >= 6) {
					reduceTrains = true;
					maxTrains = engineVehicles.Count() - 1;
				}
			} else if(maxTrains != null) {
				if(AIBase.RandRange(100) < 5) {
					maxTrains ++;
				}
			}
		}
		if(averageUsedRate != null && averageUsedRate < 20) {
			reduceTrains = false;
		}
/*		PerformanceCounter.Start();

		if(srcStationSign != null) {
			AISign.RemoveSign(srcStationSign);
		}
		srcStationSign = AISign.BuildSign (srcHgStation.platformTile, (reduceTrains ? "R" : "") + (usedRate == null ? "" : (usedRate*100).tointeger()+"%") + "/"
			+ (averageUsedRate !=null ? (averageUsedRate*100).tointeger() : "") + "/" + (maxTrains != null ? maxTrains : ""));
		PerformanceCounter.Stop("BuildSign");*/
		if(IsCloneTrain()) {
			CloneAndStartTrain();
		}
	}
	
	function CheckTrains() {
		local execMode = AIExecMode();
		local engineSet = null;

		foreach(engineVehicle, v in engineVehicles) {
			if(!AIVehicle.IsValidVehicle (engineVehicle)) {
				HgLog.Warning("invalid veihicle found "+engineVehicle+" at "+this);
				engineVehicles.RemoveItem(engineVehicle);
				continue;
			}
		}
		foreach(engineVehicle, v in engineVehicles) {
			if(AIVehicle.IsStoppedInDepot(engineVehicle)) {
				OnVehicleWaitingInDepot(engineVehicle);
				continue;
			}
		}
		
		if(isClosed || updateRailDepot!=null) {
			return;
		}

		local isBiDirectional = IsBiDirectional();
		foreach(engineVehicle, v in engineVehicles) {
			if(reduceTrains) {
				if(isBiDirectional || AIVehicle.GetCargoLoad(engineVehicle,cargo) == 0) {
					if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(engineVehicle, AIOrder.ORDER_CURRENT)) == 0) {
						AIVehicle.SendVehicleToDepot (engineVehicle);
					}
				}
			}
		}
		
		engineSet = ChooseEngineSet();
		if(engineSet == null) {
			HgLog.Warning("No usable engineSet ("+AIRail.GetName(GetRailType())+") "+this);
		}
		foreach(engineVehicle, v in engineVehicles) {
			if(!isClosed && engineSet!=null) {
				local trainEngine = AIVehicle.GetEngineType(engineVehicle);
				local wagonEngine = AIVehicle.GetWagonEngineType( engineVehicle, 1 );	
				if(!AIEngine.IsValidEngine(wagonEngine)) {
					wagonEngine = null;
				}
				if(AIVehicle.GetAge(engineVehicle) >= 365 && (trainEngine != engineSet.trainEngine || wagonEngine != engineSet.wagonEngine || AIVehicle.GetAgeLeft (engineVehicle) <= 600)) {
/*					if(trainEngine != engineSet.trainEngine) {
						HgLog.Info(AIEngine.GetName(trainEngine)+" new:"+AIEngine.GetName(engineSet.trainEngine));
					}
					if(wagonEngine != engineSet.wagonEngine) {
						HgLog.Info(AIEngine.GetName(wagonEngine)+" new:"+AIEngine.GetName(engineSet.wagonEngine));
					}*/
					if(isBiDirectional || AIVehicle.GetCargoLoad(engineVehicle,cargo) == 0) {
						if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(engineVehicle, AIOrder.ORDER_CURRENT)) == 0) {
							AIVehicle.SendVehicleToDepot (engineVehicle);
						}
					}
				}
			}
		}
	}
	
	function IsUpdatingRail() {
		return updateRailDepot != null;
	}
	
	function CheckRailUpdate() {
		if(latestEngineVehicle == null || isBuilding || isClosed || failedUpdateRailType) {
			return;
		}
		local currentRailType = GetRailType();


		if(updateRailDepot != null) {
			if(IsAllVehicleInUpdateRailDepot()) {
				local newEngineSet = ChooseEngineSetAllRailTypes();
				if(newEngineSet==null) {
					return;
				}
				local newRailType = newEngineSet.railType;
				if(!DoUpdateRailType(newRailType)) {
					RollbackUpdateRailType(currentRailType);
				} else {
					if(additionalRoute != null) {
						if(!additionalRoute.DoUpdateRailType(newRailType)) {
							RollbackUpdateRailType(currentRailType);
						}
					}
				}
			}
			return;
		}

		if(AIBase.RandRange(100)>=5) { // この先は重いのでたまにやる
			return;
		}

		local newEngineSet = ChooseEngineSetAllRailTypes();
		if(newEngineSet==null) {
			return;
		}
		local newEngine = newEngineSet.trainEngine;
		local newRailType = newEngineSet.railType;
		
		if(AIEngine.HasPowerOnRail(newEngine, currentRailType) &&
				(AIRail.GetMaxSpeed(currentRailType) == 0
				|| (AIRail.GetMaxSpeed(newRailType) >= 1 && AIRail.GetMaxSpeed(currentRailType) >= AIRail.GetMaxSpeed(newRailType)))) {
			return;
		}
		
		if(newRailType != currentRailType) {
			HgLog.Info("Engine:"+AIEngine.GetName(newEngine)+" request new railType."+this);
			if(IsAllVehiclePowerOnRail(newRailType)) {
				if(!ConvertRailType(newRailType)) {
					ConvertRailType(currentRailType);
					failedUpdateRailType = true;
				}
				if(additionalRoute != null) {
					if(!additionalRoute.ConvertRailType(newRailType)) {
						additionalRoute.ConvertRailType(currentRailType);
						ConvertRailType(currentRailType);
						failedUpdateRailType = true;
					}
				}
				if(!failedUpdateRailType) {
					engineSetsCache = null;
					latestEngineSet = newEngineSet;
					ChooseEngineSet();
				}
			} else {
				StartUpdateRail(newRailType);
				if(additionalRoute != null) {
					additionalRoute.StartUpdateRail(newRailType);
				}
			}
		}
	}
	
	function IsValidDestStationCargo() {
		local finalDestStation = GetFinalDestStation();
		if(finalDestStation.stationGroup == null) {
			if(finalDestStation.IsAcceptingCargo(cargo)) {
				return true;
			}
		} else {
			foreach(hgStation in finalDestStation.stationGroup.hgStations) {
				if(hgStation.IsAcceptingCargo(cargo)) {
					return true;
				}
			}
		}
		return false;
	}
	

	function CheckClose() {
		if(isRemoved) {
			return;
		}
	
		if(transferRoute != null) {
			if(isClosed) {
				if(!transferRoute.IsClosed()) {
					ReOpen();
				}
			} else {
				if(transferRoute.IsClosed()) {
					Close();
				}
			}
		} else {
			local currentStationIndex;
			for(currentStationIndex=destHgStations.len()-1; currentStationIndex>=0 ;currentStationIndex--) {
				if(destHgStations[currentStationIndex] == destHgStation) {
					break;
				}
			}
			local acceptableStationIndex;
			for(acceptableStationIndex=destHgStations.len()-1; acceptableStationIndex>=0 ;acceptableStationIndex--) {
				if(destHgStations[acceptableStationIndex].stationGroup.IsAcceptingCargo(cargo)) {
					if(acceptableStationIndex == currentStationIndex) {
						break;
					}
					// TODO return routeの問題
					ChangeDestination(destHgStations[acceptableStationIndex]);
					break;
				}
			}
			if(currentStationIndex != acceptableStationIndex && currentStationIndex == destHgStations.len()-1) {
				CheckStockpiled();
			}
			
			if(isClosed) {
				if(acceptableStationIndex != -1) {
					ReOpen();
				}
			} else {
				if(acceptableStationIndex == -1) {
					Close();
				}
			}
		}
	}
	
	function CheckStockpiled() {
		local destPlace = destHgStations[destHgStations.len()-1].place;
		if(destPlace != null) {
			if(destPlace instanceof HgIndustry) {
				destPlace = destPlace.GetProducing();
				local stock = destPlace.GetStockpiledCargo(cargo) ;
				if(stock > 0 && (lastTreatStockpile == null || lastTreatStockpile + 1500 < AIDate.GetCurrentDate())) {
					lastTreatStockpile = AIDate.GetCurrentDate();
					foreach(destCargo in destPlace.GetCargos()) {
						if(!PlaceDictionary.Get().IsUsedAsSourceCargo(destPlace, destCargo)) {
							HogeAI.Get().AddPending("BuildDestRailOrRoadRoute",[destPlace.Save(), destCargo]);
						}
					}
					/*
					foreach(srcCargo in destHgStation.place.GetAccepting().GetCargos()) {
						if(srcCargo != cargo && AIIndustry.GetStockpiledCargo(destPlace.industry, srcCargo)  < stock / 2) {
							HogeAI.Get().AddPending("BuildSrcRailOrRoadRoute",[destHgStation.place.Save(), srcCargo]);
						}
					}*/
				}
			}
		}
	}
	
	function _tostring() {
		return destHgStation.GetName() + "<-"+srcHgStation.GetName()+"["+AICargo.GetName(cargo)+"]";
	}
}

class TrainReturnRoute extends Route {
	srcHgStation = null;
	destHgStation = null;
	srcArrivalPath = null;
	srcDeparturePath = null;
	destArrivalPath = null;
	destDeparturePath = null;
	
	originalRoute = null;
	
	constructor(srcHgStation, destHgStation, srcArrivalPath, srcDeparturePath, destArrivalPath, destDeparturePath) {
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.srcArrivalPath = srcArrivalPath;
		this.srcDeparturePath = srcDeparturePath;
		this.destArrivalPath = destArrivalPath;
		this.destDeparturePath = destDeparturePath;
	}
	

	
	function Save() {
		local t = {};
		t.srcHgStation <- srcHgStation.id;
		t.destHgStation <- destHgStation.id;
		t.srcArrivalPath <- srcArrivalPath.path.Save();
		t.srcDeparturePath <- srcDeparturePath.path.Save();
		t.destArrivalPath <- destArrivalPath.path.Save();
		t.destDeparturePath <- destDeparturePath.path.Save();
		return t;
	}
	
	static function Load(t) {
		return TrainReturnRoute(
			HgStation.worldInstances[t.srcHgStation],
			HgStation.worldInstances[t.destHgStation],
			BuildedPath(Path.Load(t.srcArrivalPath)),
			BuildedPath(Path.Load(t.srcDeparturePath)),
			BuildedPath(Path.Load(t.destArrivalPath)),
			BuildedPath(Path.Load(t.destDeparturePath)));
	}
	
	function NeedsAdditionalProducing(orgRoute = null, isDest = false) {
		if(originalRoute.isClosed) {
			return false;
		}
		return AIStation.GetCargoWaiting(srcHgStation.GetAIStation(), originalRoute.cargo) < 500;
	}
	
	function IsOverflow(isDest = false) {
		return AIStation.GetCargoWaiting (srcHgStation.GetAIStation(), originalRoute.cargo) > 1000;
	}
	
	function GetFinalDestPlace() {
		return destHgStation.place;
	}
	
	function GetFinalDestStation() {
		return destHgStation;
	}
	
	function IsClosed() {
		return originalRoute.IsClosed();
	}
	
	function IsBiDirectional() {
		return false;
	}
	
	function _get(idx) {
		switch (idx) {
			case "cargo":
				return originalRoute.cargo;
			default: 
				throw("the index '" + idx + "' does not exist");
		}
	}
	
	
	function GetFacilities() {
		return [srcHgStation, destHgStation, srcArrivalPath.path, srcDeparturePath.path, destArrivalPath.path, destDeparturePath.path];
	}
	
	function Remove(){
		srcHgStation.Remove();
		destHgStation.Remove();
		srcArrivalPath.Remove();
		srcDeparturePath.Remove();
		destArrivalPath.Remove();
		destDeparturePath.Remove();
	}

	function _tostring() {
		return "ReturnRoute:"+destHgStation.GetName() + "<-"+srcHgStation.GetName()+"["+AICargo.GetName(cargo)+"]";
	}
}