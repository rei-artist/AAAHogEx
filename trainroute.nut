
class TrainRoute extends Route {
	static instances = [];
	static removed = []; // TODO: Save/Load
	static unsuitableEngineWagons = {};
	
	static RT_ROOT = 1;
	static RT_ADDITIONAL = 2;
	static RT_RETURN = 3;
	
	static USED_RATE_LIMIT = 20;
	
	
	static function SaveStatics(data) {
		local arr = [];
		foreach(route in TrainRoute.instances) {
			if(route.id == null) { // Removeが完了したroute
				continue;
			}
			if(route.returnRoute != null) {
				route.saveData.returnRoute = route.returnRoute.saveData;
			}
			arr.push(route.saveData);
		}
		data.trainRoutes <- arr;		

		arr = [];
		foreach(route in TrainRoute.removed) {
			arr.push(route.saveData);
		}
		data.removedTrainRoute <- arr; //いまのところIsInfrastractureMaintenance:trueの時しか使用されない
		
		data.unsuitableEngineWagons <- TrainRoute.unsuitableEngineWagons;
	}
	
	static function Create(t) {
		local destHgStations = [];
		foreach(stationId in t.destHgStations) {
			if(stationId != null) {
				destHgStations.push(HgStation.worldInstances[stationId]);
			}
		}
		local stations = HgStation.worldInstances;
		local srcStation = stations.rawin(t.srcHgStation) ? stations.rawget(t.srcHgStation) : null;
		local destStation = stations.rawin(t.destHgStation) ? stations.rawget(t.destHgStation) : null;
		
		if(srcStation == null || destStation == null) {
			local src = srcStation == null ? "not found" : srcStation.GetName();
			local dest = destStation == null ? "not found" : destStation.GetName();
			HgLog.Warning("Broken TrainRoute["+t.id+"] save data. dest:"+dest+" src:"+src+" cargo:"+AICargo.GetName(t.cargo));
			return null;
		}
		local trainRoute = TrainRoute(
			t.routeType, 
			t.cargo, 
			srcStation, destStation, 
			BuildedPath(Path.Load(t.pathSrcToDest)),
			t.pathDestToSrc == null ? null : BuildedPath(Path.Load(t.pathDestToSrc)));
			
		/*if(trainRoute.srcHgStation.GetName().find("0167") != null) {
			foreach(tile in t.pathDestToSrc) {
				HgLog.Info("pathDestToSrc:"+HgTile(tile));
			}
		}*/
		trainRoute.Load(t);
		trainRoute.subCargos = t.subCargos;
		trainRoute.isTransfer = t.transferRoute;
		trainRoute.latestEngineVehicle = t.latestEngineVehicle;
		trainRoute.latestEngineSet = t.latestEngineSet != null ? delegate TrainEstimation : t.latestEngineSet : null;
		trainRoute.engineVehicles = t.engineVehicles;
		/*if(trainRoute.srcHgStation.GetName().find("0045") != null) {
			foreach(s in destHgStations) {
				HgLog.Info("destHgStations:"+s);
			}
		}*/
		trainRoute.isClosed = t.isClosed;
		trainRoute.isRemoved = t.rawin("isRemoved") ? t.isRemoved : false;
		trainRoute.failedUpdateRailType = t.rawin("failedUpdateRailType") ? t.failedUpdateRailType : false;
		trainRoute.updateRailDepot = t.updateRailDepot;
		trainRoute.startDate = t.startDate;
		trainRoute.destHgStations = destHgStations;
		trainRoute.pathDistance = t.pathDistance;
		trainRoute.forkPaths = [];
		foreach(path in t.forkPaths) {
			trainRoute.forkPaths.push(BuildedPath(Path.Load(path)));
		}
		trainRoute.depots = t.depots;
		if(t.returnRoute != null) {
			trainRoute.returnRoute = TrainReturnRoute.Create(t.returnRoute, trainRoute);
			trainRoute.returnRoute.saveData = t.returnRoute;
		}
		trainRoute.reduceTrains = t.rawin("reduceTrains") ? t.reduceTrains : false;
		trainRoute.maxTrains = t.rawin("maxTrains") ? t.maxTrains : null;
		trainRoute.slopesTable = t.slopesTable;
		if(t.engineSetsCache != null) {
			local engineSets = [];
			foreach(engineSet in t.engineSetsCache) {
				engineSets.push(delegate TrainEstimation : engineSet);
			}
			trainRoute.engineSetsCache = engineSets;
		}

		trainRoute.engineSetsDate = t.engineSetsDate;
		trainRoute.engineSetAllRailCache = t.engineSetAllRailCache != null ? delegate TrainEstimation : t.engineSetAllRailCache : null;
		trainRoute.engineSetAllRailDate = t.engineSetAllRailDate;
		trainRoute.lastDestClosedDate = t.lastDestClosedDate;
		trainRoute.additionalTiles = t.additionalTiles;
		trainRoute.cannotChangeDest = t.cannotChangeDest;
		trainRoute.oldCargoProduction = t.oldCargoProduction;
		trainRoute.lastConvertRail = t.rawin("lastConvertRail") ? t.lastConvertRail : null;
		trainRoute.lastChangeDestDate = t.lastChangeDestDate;
		trainRoute.saveData = t;
		//trainRoute.usedRateHistory = t.rawin("usedRateHistory") ? t.usedRateHistory : [];
		return trainRoute;
	}
	
	static function LoadStatics(data) {
		TrainRoute.instances.clear();
		foreach(t in data.trainRoutes) {
			local trainRoute = TrainRoute.Create(t);
			if(trainRoute==null) { 
				continue;
			}
			TrainRoute.instances.push(trainRoute);

			if(!trainRoute.isRemoved) {
				PlaceDictionary.Get().AddRoute(trainRoute);
				if(trainRoute.returnRoute != null) {
					PlaceDictionary.Get().AddRoute(trainRoute.returnRoute);
				}
				foreach(dest in trainRoute.destHgStations) {
					if(dest != trainRoute.destHgStation) {
						dest.AddUsingRoute(trainRoute); // 削除されないようにするため
					}
				}
			}
		}
		TrainRoute.removed.clear();
		if(data.rawin("removedTrainRoute")) {
			foreach(t in data.removedTrainRoute) {
				local trainRoute = TrainRoute.Create(t);
				TrainRoute.removed.push(trainRoute);
			}
		}

		TrainRoute.unsuitableEngineWagons.clear();
		HgTable.Extend(TrainRoute.unsuitableEngineWagons, data.unsuitableEngineWagons);
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
		return TrainRoute.unsuitableEngineWagons.rawin(trainEngine+"-"+wagonEngine);
	}
	
	static function GetTrainRoutes(railType) {
		local result = [];
		foreach(route in TrainRoute.instances) {
			if(route.GetRailType() == railType) {
				result.push(route);
			}
		}
		return result;
	}
	
	
	function AddUnsuitableEngineWagon(trainEngine, wagonEngine) {
		TrainRoute.unsuitableEngineWagons.rawset(trainEngine+"-"+wagonEngine,0);
	}
	
	function GetEstimator(self) {
		local result = TrainEstimator();
		result.skipWagonNum = 5;
		result.limitTrainEngines = 1;
		result.limitWagonEngines = 1;
		result.checkRailType = true;
		return result;
	}
	/*
	function EstimateEngineSet(self, cargo, distance, production, isBidirectional, infrastractureTypes=null) {
		local trainEstimator = trainEstimator();
		trainEstimator.cargo = cargo;
		trainEstimator.productions = [production];
		trainEstimator.isBidirectional = isBidirectional;
		trainEstimator.distance = distance;
		trainEstimator.skipWagonNum = 5;
		trainEstimator.limitTrainEngines = 1;
		trainEstimator.limitWagonEngines = 1;
		trainEstimator.checkRailType = true;
		local engineSets = trainEstimator.GetEngineSetsOrder();
		if(engineSets.len() >= 1) {
			return engineSets[0];
		}
		return null;
	}*/
	
	
	routeType = null;
	cargo = null;
	srcHgStation = null;
	destHgStation = null;
	pathSrcToDest = null;
	pathDestToSrc = null;
	
	startDate = null;
	subCargos = null;
	destHgStations = null;
	forkPaths = null;
	isTransfer = null;
	pathDistance = null;
	depots = null;
	returnRoute = null;
	latestEngineVehicle = null;
	engineVehicles = null;
	latestEngineSet = null;
	isClosed = null;
	isRemoved = null;
	updateRailDepot = null;
	failedUpdateRailType = null;
	reduceTrains = null;
	maxTrains = null;
	slopesTable = null;
	trainLength = null;
	usedRateHistory = null;
	engineSetsCache = null;
	engineSetsDate = null;
	engineSetAllRailCache = null;
	engineSetAllRailDate = null;
	lastDestClosedDate = null;
	additionalTiles = null;
	lastConvertRail = null;
	lastChangeDestDate = null;
	cannotChangeDest = null;
	oldCargoProduction = null;

	saveData = null;
	
	destRoute = null;
	hasRailDest = null;
	lastCheckProduction = null;
	

	constructor(routeType, cargo, srcHgStation, destHgStation, pathSrcToDest, pathDestToSrc){
		Route.constructor();
		this.routeType = routeType;
		this.cargo = cargo;
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.pathSrcToDest = pathSrcToDest;
		this.pathDestToSrc = pathDestToSrc;
		this.pathSrcToDest.route = this;
		if(this.pathDestToSrc != null) {
			this.pathDestToSrc.route = this;
		}
		this.subCargos = [];
		this.destHgStations = [destHgStation];
		this.forkPaths = [];
		this.engineVehicles = {};
		this.isClosed = false;
		this.isRemoved = false;
		this.depots = [];
		this.failedUpdateRailType = false;
		this.reduceTrains = false;
		this.usedRateHistory = [];
		this.slopesTable = {};
		this.trainLength = 7;
		this.additionalTiles = [];
		this.cannotChangeDest = false;
		this.pathDistance = pathSrcToDest.path.GetRailDistance();
	}
	
	function Save() {
		local t = {};
		Route.SaveTo(t);
		t.routeType <- routeType;
		t.cargo <- cargo;
		t.srcHgStation <- srcHgStation.id;
		t.destHgStation <- destHgStation.id;
		t.pathSrcToDest <- pathSrcToDest.array_; //path.Save();
		t.pathDestToSrc <- pathDestToSrc == null ? null : pathDestToSrc.array_; //path.Save();
		t.subCargos <- subCargos;
		t.transferRoute <- isTransfer;
		t.latestEngineVehicle <- latestEngineVehicle;
		t.latestEngineSet <- latestEngineSet;
		t.engineVehicles <- engineVehicles;
		t.isClosed <- isClosed;
		t.isRemoved <- isRemoved;
		t.failedUpdateRailType <- failedUpdateRailType;
		t.updateRailDepot <- updateRailDepot;
		t.startDate <- startDate;
		t.destHgStations <- [];
		foreach(station in destHgStations) {
			t.destHgStations.push(station.id);
		}
		t.pathDistance <- pathDistance;
		t.forkPaths <- [];
		foreach(path in forkPaths) {
			t.forkPaths.push(path.array_);
		}
		t.depots <- depots;
		t.reduceTrains <- reduceTrains;
		t.maxTrains <- maxTrains;
		t.slopesTable <- slopesTable;
		t.usedRateHistory <- usedRateHistory;
		t.engineSetsCache <- engineSetsCache;
		t.engineSetsDate <- engineSetsDate;
		t.engineSetAllRailCache <- engineSetAllRailCache;
		t.engineSetAllRailDate <- engineSetAllRailDate;
		t.lastDestClosedDate <- lastDestClosedDate;
		t.additionalTiles <- additionalTiles;
		t.lastConvertRail <- lastConvertRail;
		t.lastChangeDestDate <- lastChangeDestDate;
		t.cannotChangeDest <- cannotChangeDest;
		t.oldCargoProduction <- oldCargoProduction;
		t.returnRoute <- null; // SaveStaticで保存する
		saveData = t;
	}

	function Initialize() {
		Save();
		InitializeSubCargos();
	}
	
	function InitializeSubCargos() {
		saveData.subCargos = subCargos = CalculateSubCargos();
	}
	
	function SetCannotChangeDest(cannotChangeDest) {
		saveData.cannotChangeDest = this.cannotChangeDest = cannotChangeDest;
	}
	
	function GetLatestEngineSet() {
		return latestEngineSet;
	}
	
	function CalculateSubCargos() {
		HgLog.Info("CalculateSubCargos:"+this);
		local result = [];
		local railType = GetRailType();
		local depot = srcHgStation.GetDepotTile();
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);
		foreach(subCargo in Route.CalculateSubCargos()) {
			foreach(engine,_ in engineList) {
				if(AIVehicle.GetBuildWithRefitCapacity(depot, engine, subCargo) >= 1) {
					result.push(subCargo);
					HgLog.Info("subCargo:"+AICargo.GetName(subCargo)+" "+this);
					break;
				}
			}
		}
		return result;
	}
	
	function GetCargos() {
		local result = [cargo];
		result.extend(subCargos);
		return result;
	}
	
	function HasCargo(cargo) { //受け入れ可能かつrefit可能か
		if(cargo == this.cargo) {
			return true;
		}
		/* 
		if(!IsTransfer() && GetCargoCapacity(cargo) == 0) {
			return false; // このルートへのtransferを停止させる
		}*/
		foreach(subCargo in subCargos) {
			if(subCargo == cargo) {
				return true;
			}
		}
		return false;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_RAIL;
	}
	
	function GetLabel() {
		return "Rail";
	}
	
	function GetBuilderClass() {
		return TrainRouteBuilder;
	}
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxTrains;
	}

	function GetNumVehicles() {
		return engineVehicles.len();
	}
	
	function GetVehicleList() {
		local result = AIList();
		AIList.AddList(engineVehicles);
		return result;
	}

	function GetThresholdVehicleNumRateForNewRoute() {
		return 0.9;
	}

	function GetThresholdVehicleNumRateForSupportRoute() {
		return 0.9;
	}

	function GetBuildingTime(distance) {
		//return distance / 2 + 100; // TODO expectedproductionを満たすのに大きな時間がかかる
//		return distance * 3 / 2 + 2100;
		return distance + 500;
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
	
	function IsClosed() {
		return isClosed;
	}
	
	function IsRemoved() {
		return isRemoved;
	}
	
	function GetMaxRouteCapacity(cargo) {
		local engineSet = GetLatestEngineSet();
		if(engineSet == null) {
			return 0;
		}
		if(GetCargoCapacity(cargo) == 0) {
			return 200; // うまく計算できない
		} else {
			return engineSet.GetMaxRouteCapacity(cargo) * GetPlatformLength() * 16 / engineSet.length;
		}
	}
	
	function GetUsableCargos() {
		local result = [];
		foreach(cargo in GetCargos()) {
			if(cargo == this.cargo || GetProductionCargo(cargo) >= 1) {
				result.push(cargo);
			}
		}
		return result;
	}
	
	function GetCargoLoadRate() {
	
		local cargos = GetCargos();
		local cargoLoad = {};
		local cargoCapa = {};
		local result = {};
		foreach(cargo in cargos) {
			cargoLoad[cargo] <- 0;
			cargoCapa[cargo] <- 0;
		}
		local count = 0;
		foreach(vehicle,_ in engineVehicles) {
			if(AIVehicle.GetState (vehicle) != AIVehicle.VS_RUNNING) {
				continue;
			}
			local loaded = false;
			foreach(cargo in cargos) {
				if(AIVehicle.GetCargoLoad(vehicle, cargo) >= 1) {
					loaded = true;
					break;
				}
			}
			if(loaded) {
				count ++;
				foreach(cargo in cargos) {
					cargoLoad[cargo] += AIVehicle.GetCargoLoad(vehicle, cargo);
					cargoCapa[cargo] += AIVehicle.GetCapacity(vehicle, cargo);
				}
			}
		}
		local result = {};
		foreach(cargo in cargos) {
			if(count <= 4) { // 対象vehicleが少ないと不正確
				result[cargo] <- 100;
			} else if(cargoLoad.rawin(cargo)) {
				result[cargo] <- cargoCapa[cargo] == 0 ? 0 : cargoLoad[cargo] * 100 / cargoCapa[cargo];
			} else {
				result[cargo] <- 0;
			}
		}
		return result;
	}
	
	function EstimateCargoProductions() {
		local cargos = GetCargos();
		local latestEngineSet = GetLatestEngineSet();
		local oldEstimateCargoProduction = {};
		if(latestEngineSet != null && oldCargoProduction != null) {
			foreach(cargo in cargos) {
				oldEstimateCargoProduction[cargo] <- GetCargoCapacity(cargo) * latestEngineSet.vehiclesPerRoute * 30 / latestEngineSet.days;
			}
		} else {
			oldCargoProduction = {};
			foreach(cargo in cargos) {
				oldEstimateCargoProduction[cargo] <- 0;
				oldCargoProduction[cargo] <- 0;
			}
		}
		local cargoLoadRate = GetCargoLoadRate();
		local cargoProduction = GetCargoProductions();
		local result = {};
		foreach(cargo in cargos) {
			local waiting = srcHgStation.GetCargoWaiting(cargo);
			if(IsBiDirectional()) {
				waiting += destHgStation.GetCargoWaiting(cargo);
				waiting /= 2;
			}
			local newProduction = (cargoProduction.rawin(cargo) ? cargoProduction[cargo] : 0)
			local deltaProduction = newProduction - (oldCargoProduction.rawin(cargo) ? oldCargoProduction[cargo] : 0);
			local production = max(50, oldEstimateCargoProduction[cargo] * cargoLoadRate[cargo] / 100 + deltaProduction + waiting / 8);
			if( newProduction > 0  || cargo == this.cargo) {
				result[cargo] <- production;
			}
		}
		saveData.oldCargoProduction = oldCargoProduction = result;
		return result;
	
/*
	
		local result = [];
		local subCargos = [];
		local resultProductions = [];
		local cargos = GetCargos();
		local loadRates = CalculateLoadRates();
		local loads = loadRates[0];
		local capas = loadRates[1];
		local waitings = [];
		local totalProduction = 0;
		local totalLoad = 0;
		local totalWaiting = 0;
		local productions = [];
		foreach(index, cargo in cargos) {
			local production = GetProductionCargo(cargo);
			if(this.cargo == cargo) {
				production = max(50, production); // 生産0でルートを作る事があるので、これが無いとBuildFirstTrainに失敗してルートが死ぬ
			}
			productions.push(production);
			totalProduction += production;
			totalLoad += loads[index];
			local waiting = srcHgStation.GetCargoWaiting(cargo) + (IsBiDirectional() ? destHgStation.GetCargoWaiting(cargo) : 0);
			waitings.push(waiting);
			totalWaiting += waiting;
		}
		
		foreach(index, cargo in cargos) {
			local production = 0;
			if(capas[index] == 0 || totalLoad == 0) {
				production = productions[index] + waitings[index]/5;
			} else {
				production = totalProduction * loads[index] / totalLoad + waitings[index]/5;
			}
			if(cargo == this.cargo) {
				resultProductions.push(production);
			} else if(production >= 1) {
				resultProductions.push(production);
				subCargos.push(cargo);
			}
		}
		return {subCargos = subCargos, productions = resultProductions};*/
	}
	
	function GetRoundedProduction(production) {
		if(production == 0) {
			return 0;
		}
		local index = HogeAI.Get().GetEstimateProductionIndex(production);
		return HogeAI.Get().productionEstimateSamples[index];
	}

	function CalculateLoadRates() {
		local cargos = GetCargos();
		local load = [];
		local capa = [];
		foreach(cargo in cargos) {
			load.push(0);
			capa.push(0);
		}
		foreach(vehicle,_ in engineVehicles) {
			foreach(index, cargo in cargos) {
				capa[index] += AIVehicle.GetCapacity(vehicle, cargo);
				load[index] += AIVehicle.GetCargoLoad(vehicle, cargo);
			}
		}
		return [load,capa];
	}
	
	function GetVehicles() {
		return engineVehicles;
	}

	function InvalidateEngineSet() {
		saveData.engineSetsCache = engineSetsCache = null;
	}

	function ChooseEngineSet() {
		local a = GetEngineSets();
		if(a.len() == 0){ 
			return null;
		}
		saveData.latestEngineSet = latestEngineSet = a[0];
		return a[0];
	}
	
	function IsValidEngineSetCache() {
		return engineSetsCache != null && ( AIDate.GetCurrentDate() < engineSetsDate || TrainRoute.instances.len()<=1) && engineSetsCache.len() >= 1;
	}
	
	function GetEngineSets(isAll=false, additionalDistance=null) {
		local production = GetRoundedProduction(max(50,GetProduction()));
		if(!isAll && additionalDistance==null && IsValidEngineSetCache() 
				&& (lastCheckProduction==null || production < lastCheckProduction * 3 / 2)) {
			return engineSetsCache;
		}
		lastCheckProduction = production;
		InitializeSubCargos(); // 使えるcargoが増えているかもしれないので再計算をする。
	
		local execMode = AIExecMode();
		local trainEstimator = TrainEstimator();
		trainEstimator.route = this;
		trainEstimator.cargo = cargo;
		trainEstimator.distance = GetDistance() + (additionalDistance != null ? additionalDistance : 0);
		trainEstimator.pathDistance = pathDistance + (additionalDistance != null ? additionalDistance : 0);
		trainEstimator.cargoProduction = EstimateCargoProductions();
		trainEstimator.isBidirectional = IsBiDirectional();
		trainEstimator.isTransfer = isTransfer;
		trainEstimator.railType = GetRailType();
		trainEstimator.isRoRo = !IsTransfer();
		trainEstimator.platformLength = GetPlatformLength();
		trainEstimator.selfGetMaxSlopesFunc = this;
		trainEstimator.additonalTrainEngine = latestEngineSet != null ? latestEngineSet.trainEngine : null;
		trainEstimator.additonalWagonEngine = latestEngineSet != null ? latestEngineSet.wagonEngineInfos[0].engine : null;
		if(isAll) {
			trainEstimator.limitWagonEngines = null;
			trainEstimator.limitTrainEngines = null;	
			trainEstimator.isLimitIncome = false;
		} else if(latestEngineSet == null) {
			trainEstimator.limitWagonEngines = 20;
			trainEstimator.limitTrainEngines = 10;		
		}
		trainEstimator.isSingleOrNot = IsSingle();
		trainEstimator.ignoreIncome = IsTransfer();
		trainEstimator.cargoIsTransfered = GetCargoIsTransfered();
		
		if(additionalDistance != null) {
			return trainEstimator.GetEngineSetsOrder();
		}
		
		saveData.engineSetsCache = engineSetsCache = trainEstimator.GetEngineSetsOrder();
		saveData.engineSetsDate = engineSetsDate = AIDate.GetCurrentDate() + (IsSingle() ? 3000 : 1000) + AIBase.RandRange(500);

		return engineSetsCache;
	}
	
	function ChooseEngineSetAllRailTypes() {
		
		if(engineSetAllRailCache != null) {
			if(AIDate.GetCurrentDate() < engineSetAllRailDate) {
				return engineSetAllRailCache;
			}
		}
		local execMode = AIExecMode();
		HgLog.Info("Start ChooseEngineSetAllRailTypes "+this);
		local trainEstimator = TrainEstimator();
		trainEstimator.route = this;
		trainEstimator.cargo = cargo;
		trainEstimator.distance = GetDistance();
		trainEstimator.pathDistance = pathDistance;
		trainEstimator.cargoProduction = EstimateCargoProductions();
		//trainEstimator.subProductions = GetRoundedSubProductions();
		trainEstimator.isBidirectional = IsBiDirectional();
		trainEstimator.isTransfer = isTransfer;
		trainEstimator.platformLength = GetPlatformLength();
		trainEstimator.selfGetMaxSlopesFunc = this;
		trainEstimator.additonalTrainEngine = latestEngineSet != null ? latestEngineSet.trainEngine : null;
		trainEstimator.additonalWagonEngine = latestEngineSet != null ? latestEngineSet.wagonEngineInfos[0].engine : null;
		trainEstimator.limitWagonEngines = 2;
		trainEstimator.limitTrainEngines = 5;
		trainEstimator.checkRailType = true;
		trainEstimator.isSingleOrNot = IsSingle();
		trainEstimator.ignoreIncome = IsTransfer()
		trainEstimator.cargoIsTransfered = GetCargoIsTransfered();

		local sets = trainEstimator.GetEngineSetsOrder();
		if(sets.len()==0) {
			HgLog.Warning("Not found engineSet.(ChooseEngineSetAllRailTypes) "+this);
			if(IsTransfer()) {
				HgLog.Warning("dest route: "+GetDestRoute()+" "+this);
			}
			return null;
		}
		local railTypeSet = {};
		foreach(set in sets) {
			//HgLog.Info(set+" ");
			if(!railTypeSet.rawin(set.railType)) {
				railTypeSet[set.railType] <- set;
			} else {
				local s = railTypeSet[set.railType];
				if(s.value < set.value) {
					railTypeSet[set.railType] = set;
				}
			}
		}
		local currentRailType = GetRailType();
		if(railTypeSet.rawin(currentRailType)) {
			local current = railTypeSet[currentRailType];
			if(current.value + abs( current.value / 10 ) < sets[0].value) {
				engineSetAllRailCache = sets[0];
			} else {
				engineSetAllRailCache = current;
			}
		} else {
			engineSetAllRailCache = sets[0];
		}
		if(engineSetAllRailCache.routeIncome < 0) {
			HgLog.Warning("Estimate routeIncome:"+engineSetAllRailCache.routeIncome+"<0 "+engineSetAllRailCache+" "+this);
		}
		saveData.engineSetAllRailCache = engineSetAllRailCache;
		saveData.engineSetAllRailDate = engineSetAllRailDate = AIDate.GetCurrentDate() + (IsSingle() ? 6000 : 1600) + AIBase.RandRange(400);
		return engineSetAllRailCache;
	}
	
	function GetPlatformLength() {
		return min(srcHgStation.platformLength, destHgStation.platformLength);
	}
	
	function BuildFirstTrain() {
		if(HogeAI.Get().ecs && !IsSingle()) { // ecsでは駅評価を高めないと生産量が増えないので最初から2台作る
			local result = _BuildFirstTrain();
			if(result) {
				CloneAndStartTrain();
			}
			return result;
		} else {
			return _BuildFirstTrain();
		}
	}
	
	function _BuildFirstTrain() {
		saveData.latestEngineVehicle = latestEngineVehicle = BuildTrain(); //TODO 最初に失敗すると復活のチャンスなし。orderが後から書き変わる事があるがそれが反映されないため。orderを状態から組み立てられる必要がある
		if(latestEngineVehicle == null) {
			HgLog.Warning("BuildFirstTrain failed. "+this);
			return false;
		}
		BuildOrder(latestEngineVehicle);
		if(!AIVehicle.StartStopVehicle(latestEngineVehicle)) {
			HgLog.Warning("StartStopVehicle failed."+this+" "+AIError.GetLastErrorString());
			if(AIError.GetLastError() == AIError.ERR_NEWGRF_SUPPLIED_ERROR) {
				foreach(wagonEngineInfo in latestEngineSet.wagonEngineInfos) {
					AddUnsuitableEngineWagon(latestEngineSet.trainEngine, wagonEngineInfo.engine);
				}
				AIVehicle.SellWagonChain(latestEngineVehicle, 0);
				return BuildFirstTrain(); //リトライ
			}
		}
		engineVehicles.rawset(latestEngineVehicle,latestEngineSet);
		if(startDate == null) {
			saveData.startDate = startDate = AIDate.GetCurrentDate();
		}
		return true;
	}
	
	function BuildNewTrain() {
		local newTrain = BuildTrain();
		if(newTrain == null) {
			return false;
		}
		if(!AIVehicle.IsValidVehicle(latestEngineVehicle)) {
			HgLog.Warning("Invalid latestEngineVehicle."+this);
			foreach(v,_ in engineVehicles) {
				if(AIVehicle.IsValidVehicle(v)) {
					saveData.latestEngineVehicle = latestEngineVehicle = v;
					HgLog.Info("New latestEngineVehicle found."+this);
					break;
				}
			}
		}
		if(!AIOrder.ShareOrders(newTrain, latestEngineVehicle)) {
			HgLog.Warning("ShareOrders failed.(BuildNewTrain)"+this+" "+AIError.GetLastErrorString());
			BuildOrder(newTrain); // 他の列車とオーダーが共有されなくなるのでChangeDestinationなどがうまくいかなくなる。Sellすべきかもしれない
		}
		if(!AIVehicle.StartStopVehicle(newTrain)) {
			HgLog.Warning("StartStopVehicle failed.(BuildNewTrain)"+this+" "+AIError.GetLastErrorString());
			if(AIError.GetLastError() == AIError.ERR_NEWGRF_SUPPLIED_ERROR) {
				foreach(wagonEngineInfo in latestEngineSet.wagonEngineInfos) {
					AddUnsuitableEngineWagon(latestEngineSet.trainEngine, wagonEngineInfo.engine);
				}
				AIVehicle.SellWagonChain(newTrain, 0);
				return BuildNewTrain(); //リトライ
			}
			return false;
		}
		engineVehicles.rawset(newTrain,latestEngineSet);	
		saveData.latestEngineVehicle = latestEngineVehicle = newTrain;
		saveData.oldCargoProduction = oldCargoProduction = GetCargoProductions(); // 列車新造時点での推定値を保存
		return true;
	}
	
	
	function CloneAndStartTrain() {
		if(latestEngineVehicle == null) {
			BuildFirstTrain();
			return;
		}
		if(IsSingle()) {
			return;
		}
		
		local engineSet = ChooseEngineSet();
		if(!HasVehicleEngineSet(latestEngineVehicle, engineSet)) {
			//HgLog.Info("BuildTrain HasVehicleEngineSet == false "+this);
			BuildNewTrain();	
		} else {
			local remain = TrainRoute.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, TrainRoute.GetVehicleType());
			if(remain <= 2) {
				return;
			}
			if(CloneTrain() == null) {
				saveData.engineSetsCache = engineSetsCache = null;
				BuildNewTrain();
			}
		}
	}
	
	function CloneTrain() {
		local execMode = AIExecMode();
		if(!AIVehicle.IsValidVehicle(this.latestEngineVehicle)) {
			HgLog.Warning("CloneVehicle failed. Invalid latestEngineVehicle("+this.latestEngineVehicle+") "+this);
			return null;
		}
		local engineVehicle = null;
		for(local need=20000;; need+= 10000) {
			local r = HogeAI.WaitForMoney(need);
			engineVehicle = AIVehicle.CloneVehicle(srcHgStation.GetDepotTile(), this.latestEngineVehicle, true);
			if(AIError.GetLastError()!=AIError.ERR_NOT_ENOUGH_CASH || !r) {
				break;
			}
		}
		if(!AIVehicle.IsValidVehicle(engineVehicle)) {
			HgLog.Warning("CloneVehicle failed. "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		if( AIOrder.GetOrderCount(engineVehicle) == 0 ) {
			HgLog.Warning("AIOrder.GetOrderCount(engineVehicle) == 0 "+this);
			return null;
		}
		engineVehicles.rawset( engineVehicle, engineVehicles[this.latestEngineVehicle] );
		AIVehicle.StartStopVehicle(engineVehicle);
		saveData.latestEngineVehicle = latestEngineVehicle = engineVehicle;		
		return engineVehicle;
	}
	
	function BuildEngineVehicle(engineVehicles, trainEngine, explain) {
		HogeAI.WaitForPrice(AIEngine.GetPrice(trainEngine));
		local depotTile = srcHgStation.GetDepotTile();
		local engineVehicle = AIVehicle.BuildVehicle(depotTile, trainEngine);
		if(!AIVehicle.IsValidVehicle(engineVehicle)) {
			local error = AIError.GetLastError();
			HgLog.Warning("BuildVehicle failed. "+explain+" "+AIError.GetLastErrorString()+" "+this);
			if(engineVehicles.len() >= 1) {
				AIVehicle.SellWagonChain(engineVehicles[0], 0);
			}
			if(error == AIVehicle.ERR_VEHICLE_TOO_MANY) {
				return null;
			}
			return false;
		}
		AIVehicle.RefitVehicle(engineVehicle, cargo);
		if(engineVehicles.len() >= 1 && !AIVehicle.MoveWagon(engineVehicle, 0, engineVehicles[0], engineVehicles.len()-1)) {
			HgLog.Warning("MoveWagon engineVehicle failed. "+explain + " "+AIError.GetLastErrorString()+" "+this);
			AIVehicle.SellWagonChain(engineVehicles[0], 0);
			AIVehicle.SellWagonChain(engineVehicle, 0);
			return false;
		}
		engineVehicles.push(engineVehicle);
		return true;
	}

	function BuildTrain(mode = 0) {
		local isAll = false;
		if(mode == 1) {
			saveData.engineSetsCache = engineSetsCache = null;
		} else if(mode == 2) {
			isAll = true;
		}
		foreach(engineSet in GetEngineSets(isAll)) {
			local trainEngine = engineSet.trainEngine;
			local unsuitable = false;
			foreach(wagonEngineInfo in engineSet.wagonEngineInfos) {
				if(TrainRoute.IsUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine)) {
					unsuitable = true;
					break;
				}
			}
			if(unsuitable) {
				continue;
			}
			local depotTile = srcHgStation.GetDepotTile();
			local explain = engineSet.tostring();
			HgLog.Info("BuildTrain "+explain+" "+this);

			
			local numEngineVehicle = engineSet.numLoco;
			local engineVehicles = [];
			
			local success = true;
			for(local i=0; i<numEngineVehicle; i++) {
				local r = BuildEngineVehicle(engineVehicles, trainEngine, explain);
				if(r == null) {
					return null; // ERR_VEHICLE_TOO_MANYの場合
				} else if(!r) {
					success = false;
					break;
				}
			}
			
			if(!success) {
				// AddUnsuitableEngineWagon(trainEngine, engineSet.wagonEngineInfos[0].engine); wagonとの組み合わせの問題ではない
				continue;
			}
			local engineVehicle = engineVehicles[0];
			
			foreach(wagonEngineInfo in engineSet.wagonEngineInfos) {
				for(local i=0; i<wagonEngineInfo.numWagon; i++) {
					HogeAI.WaitForPrice(AIEngine.GetPrice(wagonEngineInfo.engine));
					local wagon = AIVehicle.BuildVehicleWithRefit(depotTile, wagonEngineInfo.engine, wagonEngineInfo.cargo);
					if(!AIVehicle.IsValidVehicle(wagon))  {
						// AddUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine); wagonとの組み合わせの問題ではない
						HgLog.Warning("BuildVehicleWithRefit wagon failed. "+explain+" "+AIError.GetLastErrorString()+" "+this);
						success = false;
						break;
					}
					local realLength = AIVehicle.GetLength(wagon);
					local trainInfo = TrainInfoDictionary.Get().GetTrainInfo(wagonEngineInfo.engine);
					if(realLength != trainInfo.length) { // 時代で変わる？
						HgLog.Warning("Wagon length different:"+realLength+"!="+trainInfo.length+" "+AIEngine.GetName(wagonEngineInfo.engine)+" "+explain+" "+this);
						trainInfo.length = realLength;
					}
					if(!AIVehicle.MoveWagon(wagon, 0, engineVehicle, AIVehicle.GetNumWagons(engineVehicle)-1)) {
						AddUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine);
						HgLog.Warning("MoveWagon failed. "+explain + " "+AIError.GetLastErrorString()+" "+this);
						AIVehicle.SellWagonChain(wagon, 0);
						success = false;
						break;
					}
					if(AIVehicle.GetLength(engineVehicle) > GetPlatformLength() * 16) {
						HgLog.Warning("Train length over platform length."
							+AIVehicle.GetLength(engineVehicle)+">"+(GetPlatformLength() * 16)+" "+explain+" "+this);
						AIVehicle.SellWagonChain(wagon, 0);
						success = false;
						break;
					}
				}
				if(!success) {
					break;
				}
			}
			if(!success) {
				AIVehicle.SellWagonChain(engineVehicle, 0);
				continue;
			}
			
			latestEngineSet = engineSet;
			if(engineSetsCache != null && engineSetsCache.len() >= 1) {
				engineSetsCache[0] = engineSet; // ChooseEngineSet()で実際に作られたengineSetが返るようにする
			}
			if(returnRoute != null) {
				returnRoute.InitializeSubCargos();
			}
			return engineVehicle;
		}
		
		if(mode == 0) {
			HgLog.Warning("BuildTrain failed. Clear cache and retry. ("+AIRail.GetName(GetRailType())+") "+this);
			return BuildTrain(1);
		} else if(mode == 1) {
			HgLog.Warning("BuildTrain failed. Try all enginsets. ("+AIRail.GetName(GetRailType())+") "+this);
			return BuildTrain(2);
		}
		
		HgLog.Warning("BuildTrain failed. No suitable engineSet. ("+AIRail.GetName(GetRailType())+") "+this);
		saveData.engineSetsCache = engineSetsCache = null;
		return null;
	}
	

	function GetTotalWeight(trainEngine, wagonEngine, trainNum, wagonNum, cargo) {
		return AIEngine.GetWeight(trainEngine) * trainNum + (AIEngine.GetWeight(wagonEngine) + TrainRoute.GetCargoWeight(cargo,AIEngine.GetCapacity(wagonEngine))) * wagonNum;
	}
	
	function GetMaxSlopes(length, pathIn=null) {
		local path = pathIn == null ? pathSrcToDest.path : pathIn;
		local tileLength = ceil(length.tofloat() / 16).tointeger();
		if(slopesTable.rawin(tileLength)) {
			return slopesTable[tileLength];
		}
		local result = 0;
		result = max(result, path.GetSlopes(tileLength));
		//result = max(result, pathDestToSrc.path.GetSlopes(length));
		if(pathDestToSrc != null && pathIn == null && (returnRoute != null || IsBiDirectional())) {
			result = max(result, GetMaxSlopes(length, pathDestToSrc.path));
		}
		HgLog.Info("GetMaxSlopes("+length+","+tileLength+")="+result+" "+this);
		slopesTable[tileLength] <- result;
		return result;
	}
		
	function IsBiDirectional() {
		return !isTransfer && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
	}
	
	function IsSingle() {
		return pathDestToSrc == null;
	}
	
	function IsTransfer() {
		return isTransfer;
	}
	
	function IsRoot() {
		return !IsTransfer(); // 今のところ呼ばれる事は無い。
	}
		
	function BuildOrder(engineVehicle) {
		local execMode = AIExecMode();
		AIOrder.AppendOrder(engineVehicle, srcHgStation.platformTile, AIOrder.OF_FULL_LOAD_ANY + AIOrder.OF_NON_STOP_INTERMEDIATE);
		AIOrder.SetStopLocation	(engineVehicle, AIOrder.GetOrderCount(engineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
		AIOrder.AppendOrder(engineVehicle, srcHgStation.GetServiceDepotTile(), AIOrder.OF_SERVICE_IF_NEEDED);
		if(IsTransfer()) {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_TRANSFER + AIOrder.OF_NO_LOAD );
		} else if(IsBiDirectional()) {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
		} else {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		}
		AIOrder.SetStopLocation	(engineVehicle, AIOrder.GetOrderCount(engineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
		//AIOrder.SetStopLocation	(engineVehicle, AIOrder.GetOrderCount(engineVehicle)-1, AIOrder.STOPLOCATION_NEAR);
		return true;
	}
	

	function AddDestination(destHgStation) {
		destHgStations.push(destHgStation);
		slopesTable.clear();
		pathDistance = pathSrcToDest.path.GetRailDistance();
		
		destHgStation.AddUsingRoute(this); // ChangeDestination失敗時に駅が消されるのを防ぐ

		ChangeDestination(destHgStation);
		
		local oldDest = this.destHgStation;
		this.destHgStation = destHgStation;
		InitializeSubCargos();
		this.destHgStation = oldDest;
		
		engineSetsCache = null;
		maxTrains = null;
		lastDestClosedDate = null;
		
		Save();
	}

	function ChangeDestination(destHgStation, checkAcceleration = true) {
		if(returnRoute != null) { // このメソッドはreturn routeがある場合に対応していない
			HgLog.Warning("Cannot ChangeDestination (return route exists) "+this);
			return;
		}

		if(checkAcceleration) {
			local engineSets = {};
			foreach(_,engineSet in engineVehicles) {
				engineSets.rawset(engineSet,0);
			}
			foreach(engineSet,_ in engineSets) {
				if(VehicleUtils.GetAcceleration(
						VehicleUtils.GetMaxSlopeForce(GetMaxSlopes(engineSet.length), engineSet.lengthWeights, engineSet.weight)
						10,
						engineSet.tractiveEffort,
						engineSet.power,
						engineSet.weight) < 0) { 
					saveData.cannotChangeDest = cannotChangeDest = true;
					HgLog.Warning("Cannot ChangeDestination (steep slope)"+this);
					return;
				}
			}
			saveData.cannotChangeDest = cannotChangeDest = false;
		}
	
		local execMode = AIExecMode();
		/*intervalでチェックする
		if(IsBiDirectional()) {
			foreach(station in this.destHgStation.stationGroup.hgStations) {
				foreach(route in station.GetUsingRoutesAsDest()) {
					if(route.IsTransfer()) {
						route.NotifyChangeDestRoute();
					}
				}
			}
		}*/

		HgLog.Info("ChangeDestination to "+destHgStation+" "+this);
		PlaceDictionary.Get().RemoveRoute(this);
		local oldDestHgStation = this.destHgStation;
		this.destHgStation = destHgStation;
		saveData.destHgStation = destHgStation.id;
		PlaceDictionary.Get().AddRoute(this);
		oldDestHgStation.AddUsingRoute(this);
		saveData.lastChangeDestDate = lastChangeDestDate = AIDate.GetCurrentDate();
		
		//oldDestHgStation.RemoveOnlyPlatform();// 残った列車がなぜか消えかかった駅で下ろそうとする。ささくれるので線路だけ残す(SendDepotを帰路だけにすれば消しても問題ないかもしれない)

		if(latestEngineVehicle != null) {
			local orderFlags = AIOrder.OF_NON_STOP_INTERMEDIATE + (IsBiDirectional() ? 0 : AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
			local failed = false;
			if(AIOrder.GetOrderCount (latestEngineVehicle) >= 4) { // return routeがある場合、changeしないのでこちらにはこない？
				if(!AIOrder.InsertOrder(latestEngineVehicle, 3, destHgStation.platformTile, orderFlags)) {
					HgLog.Warning("InsertOrder failed:"+HgTile(destHgStation.platformTile)+" "+this);
					failed = true;
				} else {
					AIOrder.SetStopLocation	(latestEngineVehicle, 3, AIOrder.STOPLOCATION_MIDDLE);
				}
			} else {
				if(!AIOrder.AppendOrder(latestEngineVehicle, destHgStation.platformTile, orderFlags)) {
					HgLog.Warning("AppendOrder failed:"+HgTile(destHgStation.platformTile)+" "+this);
					failed = true;
				} else {
					AIOrder.SetStopLocation	(latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
				}
			}
			if(!failed) {
				AIOrder.RemoveOrder(latestEngineVehicle, 2);
			}
		}
	}
	
	function IsChangeDestination() {
		return destHgStation != destHgStations[destHgStations.len()-1];
	}
	
	function AddForkPath(path) {
		forkPaths.push(path);
		path.route = this;
		Save();
	}

	function GetLastDestHgStation() {
		return destHgStations[destHgStations.len()-1];
	}
	
	function IsAllVehicleNew() {
		foreach(engineVehicle, _ in engineVehicles) {
			if(!HasVehicleEngineSet(engineVehicle,latestEngineSet)) {
				return false;
			}
		}
		return true;
	}

	
	function AddReturnTransferOrder(transferSrcStation, destStation) {
		local execMode = AIExecMode();
		if(latestEngineVehicle != null) {
			// destStationでLOAD
			// PAXがいると詰まる AIOrder.SetOrderFlags( latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD);
			// YARD
			AIOrder.AppendOrder( latestEngineVehicle, transferSrcStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
			AIOrder.SetStopLocation( latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
			// 積載率0の時、return dest stationをスキップ
			local conditionOrderPosition = AIOrder.GetOrderCount(latestEngineVehicle);
			AIOrder.AppendConditionalOrder( latestEngineVehicle, 0);
			AIOrder.SetOrderCompareValue( latestEngineVehicle, conditionOrderPosition, 0);
			AIOrder.SetOrderCompareFunction( latestEngineVehicle, conditionOrderPosition, AIOrder.CF_EQUALS );
			AIOrder.SetOrderCondition( latestEngineVehicle, conditionOrderPosition, AIOrder.OC_LOAD_PERCENTAGE );
			// return dest station
			AIOrder.AppendOrder( latestEngineVehicle, destStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD );
			AIOrder.SetStopLocation( latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
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
		if(returnRoute != null) {
			AIOrder.SetOrderJumpTo(latestEngineVehicle, 5, 0); // return時に積載していないときにupdate depotへ飛ぶようにする
		}
	}
	
	function RemoveSendUpdateDepotOrder() {
		local execMode = AIExecMode();
		if(returnRoute != null) {
			AIOrder.SetOrderJumpTo(latestEngineVehicle, 5, 1);
		}
		AIOrder.RemoveOrder(latestEngineVehicle,0);
	}
		
	
	function GetLastRoute() {
		return this;
	}
		
	function GetSrcStationTiles() {
		return [srcHgStation.platformTile];
	}
	
	function GetTakeAllPathSrcToDest() {
		return pathSrcToDest.path;
	}

	function GetTakeAllPathDestToSrc() {
		return pathDestToSrc.path;
	}

	function GetPathAllDestToSrc() {
		return pathDestToSrc.path;
	}
	
	
	function IsAllVehicleLocation(location) {
		
		foreach(engineVehicle, v in engineVehicles) {
			if(AIVehicle.GetLocation(engineVehicle) != location || !AIVehicle.IsStoppedInDepot(engineVehicle)) {
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
		/*if(IsSingle()) {
			return false;
		}*/
		local exec = AIExecMode();
		
		if(latestEngineVehicle != null) {
			HgLog.Info("StartUpdateRail "+AIRail.GetName(railType)+" "+this);
			
			local railType = AIRail.GetCurrentRailType();
			AIRail.SetCurrentRailType ( GetRailType() );
			if(IsSingle()) {
				saveData.updateRailDepot = updateRailDepot = pathSrcToDest.path.BuildDepot();
			} else {
				saveData.updateRailDepot = updateRailDepot = pathDestToSrc.path.BuildDepot();
			}
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
		saveData.lastConvertRail = lastConvertRail = AIDate.GetCurrentDate();
		
		local execMode = AIExecMode();
		AIRail.SetCurrentRailType(railType);
		local facitilies = [];
		facitilies.push(srcHgStation);
		foreach(s in destHgStations) {
			facitilies.push(s);
		}
		facitilies.push(pathSrcToDest.path);
		if(pathDestToSrc != null) {
			facitilies.push(pathDestToSrc.path);
		}
		foreach(fork in forkPaths) {
			facitilies.push(fork.path);
		}
		facitilies.extend(returnRoute != null ? returnRoute.GetFacilities():[]);
		local tiles = [];
		foreach(f in facitilies) {
			if(f != null) {
				if("GetTiles" in f) {
					tiles.extend(f.GetTiles());
				} else {
					tiles.extend(f);
				}
			}
		} 
		tiles.extend(depots);
		tiles.extend(additionalTiles);
		
		foreach(t in tiles) {
			if(t==null || AIRail.GetRailType(t)==railType) {
				continue;
			}
			if(AIRail.IsLevelCrossingTile(t)) { // 失敗時にRailTypeが戻せないケースがあるので、先に踏切だけ試す。
				if(!BuildUtils.RetryUntilFree(function():(t,railType) {
					return AIRail.ConvertRailType(t,t,railType);
				}, 500)) {
					HgLog.Warning("ConvertRailType failed:"+HgTile(t)+" "+AIError.GetLastErrorString()+" "+this);
					return false;
				}
			}
		}
		local tileTable = {};
		foreach(tile in tiles) {
			if(tile==null || AIRail.GetRailType(tile)==railType) {
				continue;
			}
			tileTable.rawset(tile,0);
		}
	
		local convertedList = AITileList();
		while(tileTable.len() >= 1) {
			foreach(tile,_ in tileTable) {
				tileTable.rawdelete(tile);
				// destHgStationsの削除時に駅とのつなぎ目の部分が破壊されているのでここでチェック
				/*破壊しないことにした。if(!AIRail.IsRailTile(tile) && !AIRail.IsRailDepotTile(tile) && !AIBridge.IsBridgeTile(tile) && !AITunnel.IsTunnelTile(tile)) { 
					continue;
				}*/
				if(AIRail.GetRailType(tile)==railType ) {
					continue;
				}
				local end = tile;
				local match = null;
				foreach(d in HgTile.DIR4Index) {
					if(tileTable.rawin(tile+d)) {
						tileTable.rawdelete(tile+d);
						if(AIRail.GetRailType(tile+d)==railType) {
							continue;
						}
						match = d;
						break;
					}
				}
				if(match != null) {
					end = tile + match;
					for(local i=2;;i++) {
						local c = tile + match * i;
						if(!tileTable.rawin(c)) {
							break;
						}
						tileTable.rawdelete(c);
						if(AIRail.GetRailType(c)==railType) {
							break;
						}
						end = c;
					}
				}
				if(!BuildUtils.RetryUntilFree(function():(tile,end,railType) {
					return AIRail.ConvertRailType(tile,end,railType);
				}, 500)) {
					HgLog.Warning("ConvertRailType failed:"+HgTile(tile)+"-"+HgTile(end)+" "+AIError.GetLastErrorString()+" "+this);
					return false;
				}
				convertedList.AddRectangle(tile, end);
				break;
			}
		}
		convertedList.Valuate(AIRail.GetRailType); // 最終チェック。AIRail.ConvertRailTypeは一部失敗は成功を返してしまう為
		convertedList.RemoveValue(railType);
		if(convertedList.Count() >= 1) {
			local tile = convertedList.Begin();
			HgLog.Warning("ConvertRailType failed:"+HgTile(tile)+" "+AIError.GetLastErrorString()+" "+this);
			return false;
		}
		
		if(updateRailDepot != null) {
			foreach(t in tiles) {
				if(AIBridge.IsBridgeTile(t)) {
					local other = AIBridge.GetOtherBridgeEnd(t);
					local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(t, other) + 1);
					bridge_list.Valuate(AIBridge.GetMaxSpeed);
					bridge_list.Sort(AIList.SORT_BY_VALUE, false);
					local latestBridge = bridge_list.Begin();
					if(latestBridge != AIBridge.GetBridgeID(t)) {
						if(AIBridge.RemoveBridge(t)) {
							if(!RailBuilder.BuildBridgeSafe(AIVehicle.VT_RAIL, latestBridge, t, other)) {
								HgLog.Warning("RailBuilder.BuildBridgeSafe failed:"+HgTile(t)+" "+AIError.GetLastErrorString()+" "+this);
							}
						} else {
							HgLog.Warning("AIBridge.RemoveBridge failed:"+HgTile(t)+" "+AIError.GetLastErrorString()+" "+this);
						}
					}
				}
			}
		}
		saveData.engineSetsCache = engineSetsCache = null;
		return true;
	}
	
	
	function IsAllVehicleInUpdateRailDepot() {
		return IsAllVehicleLocation(updateRailDepot);
	}
	
	function DoUpdateRailType(newRailType) {
		local execMode = AIExecMode();
		HgLog.Info("DoUpdateRailType: "+AIRail.GetName(newRailType)+" "+this);
		RemoveSendUpdateDepotOrder();
		if(!ConvertRailType(newRailType)) {
			saveData.updateRailDepot = updateRailDepot = null;
			return false;
		}
		engineSetsCache = null;
		local oldVehicles = [];
		foreach(engineVehicle,v in engineVehicles) {
			oldVehicles.push(engineVehicle);
		}
		if(!BuildNewTrain()) {
			HgLog.Warning("newTrain == null "+this);
			saveData.updateRailDepot = updateRailDepot = null;
			return false;
		}
		foreach(engineVehicle in oldVehicles) {
			SellVehicle(engineVehicle);
		}
		HgTile(updateRailDepot).RemoveDepot();
		saveData.updateRailDepot = updateRailDepot = null;
		

		return true;
	}
	
	function SellVehicle(vehicle) {
		if(vehicle == latestEngineVehicle && !isRemoved) {
			HgLog.Warning("SellVehicle failed (vehicle == latestEngineVehicle) "+this);
			return;
		}
		if(!AIVehicle.SellWagonChain(vehicle, 0)) {
			HgLog.Warning("SellWagonChain failed "+AIError.GetLastErrorString()+" "+this);
			return;
		}
		engineVehicles.rawdelete(vehicle);
	}
	
	function OnVehicleWaitingInDepot(engineVehicle) {
		local execMode = AIExecMode();
		if(isClosed || reduceTrains) {
			if(isRemoved || latestEngineVehicle != engineVehicle) { //reopenに備えてlatestEngineVehicleだけ残す
				SellVehicle(engineVehicle);
				if(engineVehicles.len() == 0) {
					HgLog.Warning("All vehicles removed."+this);
					if(isRemoved) {
						RemoveFinished();
					}
					
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
			if(!BuildNewTrain()) {
				return;
			}
		}
		SellVehicle(engineVehicle);
	}
	
	function IsEqualEngine(vehicle1, vehicle2) {
		return AIVehicle.GetEngineType(vehicle1) == AIVehicle.GetEngineType(vehicle2) &&
			AIVehicle.GetWagonEngineType (vehicle1,0) == AIVehicle.GetWagonEngineType(vehicle2,0);
	}

	
	function Close() {
		HgLog.Warning("Close route start:"+this);
		saveData.isClosed = isClosed = true;
		local execMode = AIExecMode();
		/*
		foreach(engineVehicle, v in engineVehicles) {
			//HgLog.Info("SendVehicleToDepot for renewal:"+engineVehicle+" "+ToString());
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(engineVehicle, AIOrder.ORDER_CURRENT)) == 0) {
				if(AIOrder.ResolveOrderPosition(engineVehicle, AIOrder.ORDER_CURRENT) == 0) {
					AIVehicle.SendVehicleToDepot (engineVehicle);
				}
			}
		}*/
		if(destHgStation.place != null) {
			if(destHgStation.place.IsClosed()) {
				destHgStation.place = null;
			}
		}
		
		if(returnRoute != null) {
			returnRoute.Close();
		}
	}	
	
	function Remove() {					
		HgLog.Info("Remove route: "+this);
		saveData.isRemoved = isRemoved = true;
		Close();
	}

	function RemoveFinished() {
		HgLog.Warning("RemoveFinished: "+this);
		PlaceDictionary.Get().RemoveRoute(this);
		if(returnRoute != null) {
			returnRoute.Remove();
		}
		ArrayUtils.Remove(TrainRoute.instances, this);
		//TrainRoute.removed.push(this); 町の評価を考えるとすぐに削除した方が良いため
		//if(HogeAI.Get().IsInfrastructureMaintenance()) {
			Demolish(); 
		//}
	}

	function Demolish() { // ScanRoutesから呼ばれる
		HgLog.Warning("Demolish " + this);
		local execMode = AIExecMode();
		srcHgStation.RemoveIfNotUsed();
		foreach(station in destHgStations) {
			station.RemoveIfNotUsed();
		}
		pathSrcToDest.Remove(true/*physicalRemove*/, false/*DoInterval*/);
		if(pathDestToSrc != null) {
			pathDestToSrc.Remove(true/*physicalRemove*/, false/*DoInterval*/);
		}
		local tiles = [];
		tiles.extend(depots);
		tiles.extend(additionalTiles);
		foreach(tile in tiles) {
			if(AIRail.IsRailDepotTile(tile)) {
				AITile.DemolishTile(tile);
			}
			if(AIRail.IsRailTile(tile)) {
				RailBuilder.RemoveRailTracksAll(tile);
			}
		}
		if(returnRoute != null) {
			returnRoute.Demolish();
		}
	}

	function ReOpen() {
		HgLog.Warning("ReOpen route:"+this);
		saveData.isClosed = isClosed = false;
		PlaceDictionary.Get().AddRoute(this);
		if(returnRoute != null) {
			returnRoute.ReOpen();
		}
		//BuildFirstTrain();
	}
	
	
	function IsInStationOrDepotOrStop(isTransfer){
		local srcStationId = srcHgStation.GetAIStation() 
		foreach(vehicle, v in engineVehicles) {
			if(AIStation.GetStationID(AIVehicle.GetLocation(vehicle)) == srcStationId
					|| AIVehicle.IsInDepot(vehicle) /*|| AIMap.DistanceManhattan(AIVehicle.GetLocation(vehicle),srcHgStation.platformTile) < 12*/) {
				return true;
			}
			if(isTransfer && AIVehicle.GetCurrentSpeed(vehicle) == 0) {
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
	
	
	function RemoveReturnRoute() {
		
		if(returnRoute != null) {
			returnRoute.Remove();
			saveData.returnRoute = returnRoute = null;
		}
	}
	
	function IsAllVehiclePowerOnRail(newRailType) {
		foreach(vehicle,_ in engineVehicles) {
			local engine = AIVehicle.GetEngineType(vehicle);
			if(!AIEngine.HasPowerOnRail(engine, newRailType) || !AIEngine.CanRunOnRail(engine, newRailType)) {
				return false;
			}
		}
		return true;
	}
	
	function RollbackUpdateRailType(railType) {
		HgLog.Warning("RollbackUpdateRailType "+this+" v:"+engineVehicles.len());
		saveData.failedUpdateRailType = failedUpdateRailType = true;
		saveData.updateRailDepot = updateRailDepot = null;
		ConvertRailType(railType);
		foreach(engineVehicle,v in engineVehicles) {
			if(AIVehicle.IsStoppedInDepot(engineVehicle)) {
				AIVehicle.StartStopVehicle(engineVehicle);
			}
		}
	}
	
	function IsCloneTrain() {
		local result = (maxTrains == null || maxTrains > engineVehicles.len())
			&& !IsInStationOrDepotOrStop(IsTransfer()) 
			&& (latestEngineSet==null || IsWaitingCargoForCloneTrain() );
		if(!result) {
			return false;
		}
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(destRoute != false) {
				local needs = false;
				foreach(cargo in GetCargos()) {
					if(GetCargoCapacity(cargo) >= 1 && !IsDestOverflow(cargo)) {
						needs = true;
						break;
					}
				}
				if(!needs) {
					return false;
				}
			}
		}
		return result;
	}


	function IsWaitingCargoForCloneTrain() {
		foreach(cargo in GetCargos()) {
			local capacity = GetCargoCapacity(cargo);
			if(capacity == 0) {
				continue;
			}
			local station = srcHgStation.GetAIStation();
			local waiting = AIStation.GetCargoWaiting(station, cargo);
			if(waiting > capacity / 2) {
				return true;
			}
			if(waiting > capacity / 4 && AIStation.GetCargoRating (station, cargo) < 40) {
				return true;
			}
		}
		return false;
	}
		
	function CheckCloneTrain() {
		if(isClosed || isRemoved || updateRailDepot!=null || IsSingle()) {
			return;
		}
		
		
		if(IsCloneTrain()) {
			local numClone = 1;
			if(latestEngineSet != null) {
				if(latestEngineSet.vehiclesPerRoute - engineVehicles.len() >= 9) {
					numClone = 4;
				} else if(latestEngineSet.vehiclesPerRoute - engineVehicles.len() >= 6) {
					numClone = 3;
				} else if(latestEngineSet.vehiclesPerRoute - engineVehicles.len() >= 3) {
					numClone = 2;
				}
			}
			local waiting = AIStation.GetCargoWaiting(srcHgStation.GetAIStation(), cargo);
			local capacity = GetCargoCapacity(cargo);
			numClone = max(1,min( numClone, waiting / capacity ));
			for(local i=0; i<numClone; i++) {
				CloneAndStartTrain();
			}
		}
	}
	
	function CheckTrains() {
		local execMode = AIExecMode();
		local engineSet = null;

		if(isClosed) {
			foreach(engineVehicle, v in engineVehicles) {
				//HgLog.Info("SendVehicleToDepot(isClosed):"+engineVehicle+" "+ToString());
				SendVehicleToDepot(engineVehicle);
			}
		}
		foreach(engineVehicle, _ in engineVehicles) {
			if(!AIVehicle.IsValidVehicle (engineVehicle)) {
				HgLog.Warning("Invalid veihicle found "+engineVehicle+" at "+this);
				engineVehicles.rawdelete(engineVehicle);
				if(latestEngineVehicle == engineVehicle) {
					HgLog.Warning("latestEngineVehicle == engineVehicle "+this);
					if(engineVehicles.len() == 0) {
						HgLog.Warning("engineVehicles.len() == 0 "+this);
					} else {
						foreach(engineVehicle, _ in engineVehicles) {
							saveData.latestEngineVehicle = latestEngineVehicle = engineVehicle;
							break;
						}
					}
				}
				continue;
			}
			if(AIVehicle.IsStoppedInDepot(engineVehicle)) {
				OnVehicleWaitingInDepot(engineVehicle);
			}
		}
		
		if(isClosed || updateRailDepot!=null) {
			return;
		}

		
		local isBiDirectional = IsBiDirectional();
		local needsAddtinalProducing = NeedsAdditionalProducing(null,false,false);
		if( AIBase.RandRange(100) < 10 && CargoUtils.IsPaxOrMail(cargo)) { // 作った時には転送が無い時がある
			foreach(townCargo in HogeAI.Get().GetPaxMailCargos()) {
				if(!HasCargo(townCargo)) continue;
				if(needsAddtinalProducing) {
					CommonRouteBuilder.CheckTownTransferCargo(this,srcHgStation,townCargo);
				}
				if(isBiDirectional && NeedsAdditionalProducing(null, true, false)) {
					CommonRouteBuilder.CheckTownTransferCargo(this,destHgStation,townCargo);
				}
			}
		}

		
		
		if(lastChangeDestDate != null && lastChangeDestDate + 120 < AIDate.GetCurrentDate() && !IsChangeDestination()) {
			local removed = [];
			foreach(station in destHgStations) {
				if(station != destHgStation && station != destHgStations[destHgStations.len()-1]) {
					if(HogeAI.Get().ecs && station.place != null && !(station.place instanceof TownCargo)) {
						continue;
					}
					if(station.place != null && station.place instanceof TownCargo && !CargoUtils.IsPaxOrMail(cargo)) {
						continue;
					}
					/* SendDepotのタイミングによってはどうしても分岐側へ移動して本線を詰まらせる事があるので削除しない。
					platformだけの削除もRailUpdateの兼ね合いがあるので難しい*/
					if(!station.IsRemoved()) {
						foreach(path in forkPaths) {
							path.Remove();
						}
						forkPaths.clear();
						station.RemoveUsingRoute(this);
						station.Remove();
						//station.RemoveOnlyPlatform();
						removed.push(station);
					}
				}
			}
			foreach(removedStation in removed) {
				ArrayUtils.Remove(destHgStations, removedStation);
				Save();
			}
			saveData.lastChangeDestDate = lastChangeDestDate = null;
		}
		
		if(!HogeAI.HasIncome(20000) || !ExistsMainRouteExceptSelf()) {
			//HgLog.Warning("Cannot renewal train "+this);
			return;
		}
		
		engineSet = ChooseEngineSet();
//		HgLog.Warning("ChooseEngineSet "+engineSet+" "+this);
		if(engineSet == null) {
			HgLog.Warning("No usable engineSet ("+AIRail.GetName(GetRailType())+") "+this);
			return;
		}
		if(engineSet.price > HogeAI.Get().GetUsableMoney()) {
			return; // すぐに買えない場合はリニューアルしない。車庫に列車が入って収益性が著しく悪化する場合がある
		}
		foreach(engineVehicle, v in engineVehicles) {
			if(!HasVehicleEngineSet(engineVehicle,engineSet) || AIVehicle.GetAgeLeft (engineVehicle) <= 600) {
				if(isBiDirectional || AIVehicle.GetCargoLoad(engineVehicle,cargo) == 0) {
					//HgLog.Info("SendVehicleToDepot(renewal or age):"+engineVehicle+" "+this);
					SendVehicleToDepot(engineVehicle);
				}
			}
		}
	}
	
	function ExistsMainRouteExceptSelf() {
		foreach(route in TrainRoute.instances) {
			if(route.IsTransfer()) {
				continue;
			}
			if(route != this) {
				return true;
			}
		}
		return false;
	}

	
	function HasVehicleEngineSet(vehicle, engineSet) {
		if(engineSet == null) { // 作れるlocoが無くなるとnullになる
			return true;
		}
		if(!engineVehicles.rawin(vehicle)) {
			HgLog.Warning("!engineVehicles.rawin("+vehicle+") "+this);
			return false;
		}
		local vehicleEngineSet = engineVehicles[vehicle];
		if(vehicleEngineSet == engineSet) {
			return true;
		}
		if(vehicleEngineSet.engine != engineSet.engine) {
			return false;
		}
		if(vehicleEngineSet.numLoco != engineSet.numLoco) {
			return false;
		}
		foreach(index,wagonInfo in engineSet.wagonEngineInfos) {
			if(vehicleEngineSet.wagonEngineInfos.len() <= index) {
				return false;
			}
			local vehicleWagonInfo = vehicleEngineSet.wagonEngineInfos[index];
			if(vehicleWagonInfo.engine != wagonInfo.engine) {
				return false;
			}
			if(vehicleWagonInfo.numWagon != wagonInfo.numWagon) {
				return false;
			}
		}
		return true;
		
		/*
		
		if(vehicleEngineSet.numLoco != engineSet.numLoco) {
			return false;
		}
		
		
		local wagons = AIVehicle.GetNumWagons(vehicle);
		local totalNum = engineSet.numLoco;
		foreach(wagonEngineInfo in engineSet.wagonEngineInfos) {
			totalNum += wagonEngineInfo.numWagon;
		}
		if(totalNum != wagons) {
			//HgLog.Info(engineSet.numLoco+"+"+engineSet.numWagon+"!="+wagons+" route:"+this);
			return false;
		}
		local trainEngine = AIVehicle.GetEngineType(vehicle);
		if(engineSet.trainEngine != trainEngine) {
			//HgLog.Info(AIEngine.GetName(trainEngine)+" newLogo:"+AIEngine.GetName(engineSet.trainEngine)+" route:"+this);
			return false;
		}
		local index = engineSet.numLoco;
		foreach(wagonEngineInfo in engineSet.wagonEngineInfos) {
			if(index < wagons && wagonEngineInfo.numWagon >= 1) {
				local wagonEngine = AIVehicle.GetWagonEngineType(vehicle, index);
				if(wagonEngine != wagonEngineInfo.engine) {
					//HgLog.Info(AIEngine.GetName(wagonEngine)+" newWagon:"+AIEngine.GetName(wagonEngineInfo.engine)+" route:"+this);
					return false;
				}
				index += wagonEngineInfo.numWagon;
			}
		}
		//HgLog.Info("HasVehicleEngineSet return true "+AIEngine.GetName(trainEngine)+" route:"+this);
		return true;*/
	}
	
	function SendVehicleToDepot(vehicle) {
		if(IsUpdatingRail()) {
			return;
		}
		if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
			if(AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT) != 2 ) { //行きにSendToDepotが入るとささくれに入る
				AIVehicle.SendVehicleToDepot (vehicle);
			}
/* 
			if(IsBiDirectional() || returnRoute != null) {
				AIVehicle.SendVehicleToDepot (vehicle);
			} else {
				if(AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}*/
		}
	}
	
	function IsUpdatingRail() {
		return updateRailDepot != null;
	}
	
	
	function CheckRailUpdate() {
		if(latestEngineVehicle == null || isBuilding || isClosed || failedUpdateRailType || IsChangeDestination()) {
			return;
		}
		if(AIDate.GetCurrentDate() < startDate + 5 * 365) {
			return;
		}
		if(lastConvertRail != null && AIDate.GetCurrentDate() < lastConvertRail + 15 * 365) {
			//HgLog.Info("lastConvertRail:"+DateUtils.ToString(lastConvertRail)+" "+this);
			// 一度コンバートしてから15年間はkeep
			return;
		}
		
		local currentRailType = GetRailType();

		if(updateRailDepot != null) {
			if(IsAllVehicleInUpdateRailDepot()) {
				local newEngineSet = ChooseEngineSetAllRailTypes();
				if(newEngineSet==null) {
					HgLog.Warning("newEngineSet==null (ChooseEngineSetAllRailTypes)");
					return;
				}
				local newRailType = newEngineSet.railType;
				if(!DoUpdateRailType(newRailType)) {
					RollbackUpdateRailType(currentRailType);
				}
			}
			return;
		}

/*		if(AIBase.RandRange(100)>=5) { // この先は重いのでたまにやる
			return;
		}*/

		local newEngineSet = ChooseEngineSetAllRailTypes();
		if(newEngineSet==null) {
			if(HogeAI.Get().IsInfrastructureMaintenance()) {
				HgLog.Warning("Rmove TrainRoute(EngineSet not available)."+this);
				Remove();
			}
			return;
		}
		if(newEngineSet.routeIncome < 0 && !IsTransfer()
				&& (destHgStation.place == null 
						|| destHgStation.place instanceof TownCargo || destHgStation.place.GetProducing().GetRoutesUsingSource().len() == 0)) {
			HgLog.Warning("Rmove TrainRoute(Not profitable)."+this);
			Remove();
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
					saveData.failedUpdateRailType = failedUpdateRailType = true;
				}
				if(!failedUpdateRailType) {
					saveData.engineSetsCache = engineSetsCache = null;
				}
			} else {
				StartUpdateRail(newRailType);
			}
		}
	}
	

	function CheckClose() {
		if(isRemoved || IsBuilding()) {
			return;
		}
		/*
		if(srcHgStation.GetName().find("0172") != null) {
			HgLog.Warning("IsTransfer:"+IsTransfer()+" IsBiDirectional:"+IsBiDirectional());
			Initialize();
		}*/

		if(srcHgStation.place != null && srcHgStation.place.IsClosed()) {
			HgLog.Warning("Route Remove (src place closed)"+this);
			Remove();
			return;
		}
	
		if(IsTransfer() || IsSingle()) {
			Route.CheckClose();
/*			local destRoute = GetDestRoute();
			if(destRoute == false || destRoute.IsRemoved()) {
				Remove();
				return;
			}
			if(isClosed) {
				if(!destRoute.IsClosed() && destRoute.HasCargo(cargo)) {
					ReOpen();
				}
			} else {
				if(destRoute.IsClosed() || !destRoute.HasCargo(cargo)) {
					Close();
				}
			}*/
		} else {
			local currentStationIndex;
			for(currentStationIndex=destHgStations.len()-1; currentStationIndex>=0 ;currentStationIndex--) {
				if(destHgStations[currentStationIndex] == destHgStation) {
					break;
				}
			}
			local acceptableStationIndex;
			for(acceptableStationIndex=destHgStations.len()-1; acceptableStationIndex>=0 ;acceptableStationIndex--) {
				if(destHgStations[acceptableStationIndex].IsRemoved()) { // destへの転送路線が削除されると一緒にRemoveされることがある
					continue;
				}
				local accepting = false;
				if(destHgStations[acceptableStationIndex].stationGroup.IsAcceptingCargo(cargo) && HasCargo(cargo)) {
					accepting = true;
				}
				//HgLog.Info("CloseCheck:"+destHgStations[acceptableStationIndex]+" IsAccepting:"+accepting+" "+this);
				if(accepting) {
					if(acceptableStationIndex == currentStationIndex) {
						break;
					}
					// TODO return routeの問題
					ChangeDestination(destHgStations[acceptableStationIndex], cannotChangeDest);
					break;
				}
			}
			if(currentStationIndex != acceptableStationIndex && currentStationIndex == destHgStations.len()-1) {
				saveData.lastDestClosedDate = lastDestClosedDate = AIDate.GetCurrentDate();
				//CheckStockpiled();
			}
			
			if(isClosed) {
				if(acceptableStationIndex != -1) {
					ReOpen();
				}
			} else {
				if(acceptableStationIndex == -1 && returnRoute != null) {
					if(destHgStations[destHgStations.len()-1].place != null && destHgStations[destHgStations.len()-1].place.IsClosed()) {
						HgLog.Warning("Route Remove (dest place closed)"+this);
						Remove(); //TODO 最終以外が単なるCloseの場合、Removeは不要。ただしRemoveしない場合、station.placeは更新する必要がある。レアケースなのでとりあえずRemove
					} else {
						//if(!HogeAI.Get().ecs) { 新規ルート作成を促す //ソース元の生産の健全性を保つため一時的クローズはしない(ECS)
							Close();
						//}
					}
				}
			}
		}
	}

	function NotifyAddTransfer(callers=null) {
		Route.NotifyAddTransfer(callers);
		saveData.engineSetsCache = engineSetsCache = null;
		foreach(cargo,production in GetCargoProductions()) {
			if(production >= 1 && GetCargoCapacity(cargo) == 0) {
				InvalidateEngineSet();
				break;
			}
		}
	}
	
}

class TrainReturnRoute extends Route {
	originalRoute = null;
	srcHgStation = null;
	destHgStation = null;
	srcArrivalPath = null;
	srcDeparturePath = null;
	destArrivalPath = null;
	destDeparturePath = null;

	depots = null;
	subCargos = null;
	
	saveData = null;
	
	constructor(originalRoute, srcHgStation, destHgStation, srcArrivalPath, srcDeparturePath, destArrivalPath, destDeparturePath) {
		Route.constructor();
		this.originalRoute = originalRoute;
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.srcArrivalPath = srcArrivalPath;
		this.srcDeparturePath = srcDeparturePath;
		this.destArrivalPath = destArrivalPath;
		this.destDeparturePath = destDeparturePath;
		this.srcArrivalPath.route = this;
		this.srcDeparturePath.route = this;
		this.destArrivalPath.route = this;
		this.destDeparturePath.route = this;
		this.depots = [];
		this.subCargos = [];
	}
	

	
	function Save() {
		local t = {};
		Route.SaveTo(t);
		t.srcHgStation <- srcHgStation.id;
		t.destHgStation <- destHgStation.id;
		t.srcArrivalPath <- srcArrivalPath.path.Save();
		t.srcDeparturePath <- srcDeparturePath.path.Save();
		t.destArrivalPath <- destArrivalPath.path.Save();
		t.destDeparturePath <- destDeparturePath.path.Save();
		t.depots <- depots;
		t.subCargos <- subCargos;
		saveData = t;
	}
	
	static function Create(t, originalRoute) {
		local result = TrainReturnRoute(
			originalRoute,
			HgStation.worldInstances[t.srcHgStation],
			HgStation.worldInstances[t.destHgStation],
			BuildedPath(Path.Load(t.srcArrivalPath)),
			BuildedPath(Path.Load(t.srcDeparturePath)),
			BuildedPath(Path.Load(t.destArrivalPath)),
			BuildedPath(Path.Load(t.destDeparturePath)));
		result.Load(t);
		result.depots = t.rawin("depots") ? t.depots : [];
		result.subCargos = t.subCargos;
		return result;
	}

	function AddDepots(depots) {
		this.depots.extend(depots);
	}

	function Initialize() {
		Save();
		InitializeSubCargos();
	}
	
	function InitializeSubCargos() {
		subCargos = [];
		local acceptingCargos = CalculateSubCargos();
		foreach(subCargo in acceptingCargos) {
			if(originalRoute.HasCargo(subCargo)) {
				subCargos.push(subCargo);
			}
		}
		saveData.subCargos = subCargos;
	}
	
	function GetLatestEngineSet() {
		return originalRoute.GetLatestEngineSet();
	}

	function ChooseEngineSet() {
		return originalRoute.ChooseEngineSet();
	}

	function Close() {
	}
	
	function ReOpen() {
	}
	
	function IsTransfer() {
		return false;
	}
	
	function IsBiDirectional() {
		return false;
	}
	
	function IsSingle() {
		return false;
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_RAIL;
	}
		
	function GetCargoCapacity(cargo) {
		return originalRoute.GetCargoCapacity(cargo);
	}
	
	function GetVehicleList() {
		return originalRoute.GetVehicleList();
	}
	
	/* function IsOverflow(isDest = false, hgStation = null) {
		if(hgStation == null) {
			hgStation = isDest ? destHgStation : srcHgStation;
		}
		return AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) > originalRoute.GetOverflowQuantity();
	}*/
	
	function IsClosed() {
		return IsRemoved() || originalRoute.IsClosed();
	}
	
	function IsRemoved() {
		return this != originalRoute.returnRoute || originalRoute.IsRemoved();
	}
	
	function _get(idx) {
		switch (idx) {
			case "cargo":
				return originalRoute.cargo;
			case "lastDestClosedDate": // TODO: return routeのdest closeには対応していない。一時的に受け入れ拒否された場合にsrcへcargoをそのまま持ち帰ってしまうのでrouteが死ぬ
				return null;
			default: 
				throw("the index '" + idx + "' does not exist");
		}
	}
	
	function GetNumVehicles() {
		return originalRoute.GetNumVehicles();
	}
	
	function GetCargos() {
	
		if(originalRoute == null) {
			return [];
		}
		local result = [originalRoute.cargo];
		local vehicle = originalRoute.latestEngineVehicle;
		if(vehicle == null) {
			return result;
		}
		foreach(subCargo in subCargos) {
			if( AIVehicle.GetCapacity(vehicle, subCargo) >= 1 ) {
				result.push(subCargo);
			}
		}
		return result;
	}
	
	function IsReturnRoute(isDest) {
		return !isDest;
	}

	
	function GetFacilities() {
		return [srcHgStation, destHgStation, srcArrivalPath.path, srcDeparturePath.path, destArrivalPath.path, destDeparturePath.path, depots];
	}
	
	function Remove(){
		if(originalRoute == null) {
			HgLog.Warning("ReturnRoute.Remove() originalRoute == null "+this);
			return;
		}
		PlaceDictionary.Get().RemoveRoute(this);
		originalRoute.RemoveReturnTransferOder();
		originalRoute.returnRoute = null;
	}
	
	function Demolish(){
		srcHgStation.RemoveIfNotUsed();
		destHgStation.RemoveIfNotUsed();
		srcArrivalPath.Remove();
		srcDeparturePath.Remove();
		destArrivalPath.Remove();
		destDeparturePath.Remove();
	}

	function _tostring() {
		return "ReturnRoute:"+destHgStation.GetName() + "<-"+srcHgStation.GetName()+"["+AICargo.GetName(cargo)+"]";
	}
}

class TrainRouteBuilder extends RouteBuilder {

	function GetRouteClass() {
		return TrainRoute;
	}

	function DoBuild() {
		local route = BuildRoute(dest, src, cargo, options);
		if(route == false) {
			return null;
		}
		if(route == null) {
			Place.AddNgPathFindPair(src,dest,AIVehicle.VT_RAIL);
			return null;
		}
		//SearchAndBuildAdditionalDest(route); placeを満たすために作成されている事がある
		return route;
	}
	
	// 戻り値: TrainRoute 失敗はnull, 一時的失敗はfalseを返す
	function BuildRoute(dest, src, cargo, options) {
		local distance = AIMap.DistanceManhattan(src.GetLocation(), dest.GetLocation());
		local isTransfer = options.rawin("transfer") ? options.transfer : (dest instanceof StationGroup);
		local isSingleOrNot = (options.rawin("notUseSingle") && options.notUseSingle) || (src instanceof Place && src.IsProcessing()) ? false : null;
		local explain = (isTransfer ? "T:" : "") + dest.GetName()+"<-"+src.GetName()+"["+AICargo.GetName(cargo)+"] distance:"+distance;
		//HgLog.Info("# TrainRoute: Try BuildRoute: "+explain);

		
		
		local aiExecMode = AIExecMode();
		
		local subCargos = [];
		local isBidirectional = false;
		local cargoProduction = {};
		cargoProduction[cargo] <- max(50,src.GetFutureExpectedProduction(cargo, AIVehicle.VT_RAIL));
		if(dest instanceof Place && src instanceof Place) { //TODO: stationgroupの場合
			foreach(c in src.GetProducingCargos()) {
				if(c != cargo && dest.IsCargoAccepted(c)) {
					cargoProduction[c] <- src.GetFutureExpectedProduction(c, AIVehicle.VT_RAIL);
				}
			}
			isBidirectional = dest.IsAcceptingAndProducing(cargo) && src.IsAcceptingAndProducing(cargo);
		}
		
		local trainEstimator = TrainEstimator();
		trainEstimator.cargo = cargo;
		trainEstimator.isSingleOrNot = isSingleOrNot; //srcが工場の場合、後から生産量が増加する可能性が高いので複線のみにしておく
		trainEstimator.cargoProduction = cargoProduction;
		trainEstimator.distance = distance;
		trainEstimator.checkRailType = true;
		trainEstimator.isRoRo = !isTransfer;
		trainEstimator.isBidirectional = isBidirectional;
		if(options.rawin("destRoute") && options.destRoute != null) {
			trainEstimator.SetDestRoute( options.destRoute, dest, src );
		}
		if(src instanceof StationGroup) {
			trainEstimator.cargoIsTransfered[cargo] <- true;
		}
		local engineSets = trainEstimator.GetEngineSetsOrder();
		/*
		foreach(engineSet in engineSets) {
			HgLog.Info(engineSet.GetTrainString());
		}*/
		
		if(engineSets.len()==0) {
			if(trainEstimator.tooShortMoney == true) {
				HgLog.Info("TrainRoute: tooShortMoney "+explain);
				return false;
			}
			HgLog.Info("TrainRoute: Not found enigneSet "+explain);
			return null;
		}
		HgLog.Info("TrainRoute railType:"+AIRail.GetName(engineSets[0].railType));
		HgLog.Info("AIRail.GetMaintenanceCostFactor:"+AIRail.GetMaintenanceCostFactor(engineSets[0].railType));	
		AIRail.SetCurrentRailType(engineSets[0].railType);
		
		local destTile = null;
		local destHgStation = null;
		destTile = dest.GetLocation();
		local useSingle = engineSets[0].isSingle; //HogeAI.Get().GetUsableMoney() < HogeAI.Get().GetInflatedMoney(100000) && !HogeAI.Get().HasIncome(20000);
		local destStationFactory = TerminalStationFactory();
		destStationFactory.distance = distance;
		destStationFactory.useSingle = useSingle;
		if(dest instanceof Place) {
			local destPlace = dest;
			if(destPlace.GetProducing().IsTreatCargo(cargo)) { // bidirectional
				destPlace = destPlace.GetProducing();
			}
			destHgStation = destStationFactory.CreateBest(destPlace, cargo, src.GetLocation());
		} else  {
			destStationFactory.useSimple = true;
			destHgStation = destStationFactory.CreateBest( dest, cargo, src.GetLocation() );
		}

		if(destHgStation == null) {
			HgLog.Warning("TrainRoute: No destStation."+explain);
			Place.AddNgPlace(dest, cargo, AIVehicle.VT_RAIL);
			return null;
		}
		
		local srcStatoinFactory = SrcRailStationFactory();
		srcStatoinFactory.platformLength = destHgStation.platformLength;
		srcStatoinFactory.useSimple = destStationFactory.useSimple;
		srcStatoinFactory.useSingle = useSingle;
		local srcHgStation = srcStatoinFactory.CreateBest(src, cargo, destTile);
		if(srcHgStation == null) {
			HgLog.Warning("TrainRoute: No srcStation."+explain);
			Place.AddNgPlace(src, cargo, AIVehicle.VT_RAIL);
			return null;
		}

		srcHgStation.cargo = cargo;
		srcHgStation.isSourceStation = true;
		if(!srcHgStation.BuildExec()) { 
			HgLog.Warning("TrainRoute: srcHgStation.BuildExec failed. platform:"+srcHgStation.GetPlatformRectangle()+" "+explain);
			Rollback();
			return null;
		}
		AddRollback(srcHgStation);
		
		destHgStation.cargo = cargo;
		destHgStation.isSourceStation = false;
		if(!destHgStation.BuildExec()) {
			HgLog.Warning("TrainRoute: destHgStation.BuildExec failed. platform:"+destHgStation.GetPlatformRectangle()+" "+explain);
			Rollback();
			return null;
		}
		AddRollback(destHgStation);
		
		local pathfinding = Pathfinding();
		local hogeAI = HogeAI.Get();
		if(src instanceof HgIndustry) {
			pathfinding.industries.push(src.industry);
		}
		if(dest instanceof HgIndustry) {
			pathfinding.industries.push(dest.industry);
		}
		hogeAI.pathfindings.rawset(pathfinding,0);
		local railBuilder;
		local adjustedPathFindLimit = !hogeAI.HasIncome(10000) && !hogeAI.IsRich() ? hogeAI.pathFindLimit * 3 : hogeAI.pathFindLimit;
		if(useSingle) {
			railBuilder = SingleStationRailBuilder(srcHgStation, destHgStation, adjustedPathFindLimit, pathfinding);
		} else {
			railBuilder = TwoWayStationRailBuilder(srcHgStation, destHgStation, adjustedPathFindLimit, pathfinding);
		}
		railBuilder.engine = engineSets[0].engine;
		railBuilder.cargo = cargo;
		railBuilder.platformLength = destHgStation.platformLength;
		railBuilder.distance = distance;
		if(!useSingle && dest instanceof Place) {
			if(hogeAI.IsEnableVehicleBreakdowns()) {
				railBuilder.isBuildDepotsDestToSrc = true;
			} else {
				railBuilder.isBuildSingleDepotDestToSrc = true;
			}
		}
		local isSuccess = railBuilder.Build();
		hogeAI.pathfindings.rawdelete(pathfinding);
		if(!isSuccess) {
			HgLog.Warning("TrainRoute: railBuilder.Build failed."+explain);
			HgStation.AddNgStationTile(srcHgStation); // stationの場所が悪くて失敗する事が割とある
			HgStation.AddNgStationTile(destHgStation);
			Rollback();
			
			return null;
		}
		if(srcHgStation.stationGroup == null || destHgStation.stationGroup == null) {
			HgLog.Warning("TrainRoute: station was removed."+explain); // 稀に建設中に他ルートの削除と重なって駅が削除される事がある
			Rollback();
			return null;
		}
		
		
		local route
		if(useSingle) {
			route = TrainRoute(
				TrainRoute.RT_ROOT, cargo,
				srcHgStation, destHgStation,
				railBuilder.buildedPath, null);
		} else {
			route = TrainRoute(
				TrainRoute.RT_ROOT, cargo,
				srcHgStation, destHgStation,
				railBuilder.buildedPath1, railBuilder.buildedPath2);
		}
		route.isTransfer = isTransfer;
		route.AddDepots(railBuilder.depots);
		route.Initialize();
		
		destHgStation.BuildAfter();
		if(!route.BuildFirstTrain()) {
			HgLog.Warning("TrainRoute: BuildFirstTrain failed."+route);
			route.Demolish();
			return null;
		}
		if(route.latestEngineSet != null && route.latestEngineSet.vehiclesPerRoute >= 2) {
			route.CloneAndStartTrain();
		}
		
		HgLog.Info("TrainRoute pathDistance:"+route.pathDistance+" distance:"+route.GetDistance()+" "+route);

		ClearRollback();
		TrainRoute.instances.push(route);
		PlaceDictionary.Get().AddRoute(route);
		
		if(CargoUtils.IsPaxOrMail(cargo)) {
			CommonRouteBuilder.CheckTownTransfer(route, srcHgStation);
			CommonRouteBuilder.CheckTownTransfer(route, destHgStation);
		}
		//route.CloneAndStartTrain();
		
		//HgLog.Info("# TrainRoute: BuildRoute succeeded: "+route);
		return route;
	}

	
}

class TrainRouteExtendBuilder extends Construction {
	route = null;
	additionalPlace = null;
	
	constructor(route,additionalPlace) {
		Construction.constructor();
		this.route = route;
		this.additionalPlace = additionalPlace;
	}

	function DoBuild() {
		HgLog.Info("# TrainRoute: Try Extend:"+additionalPlace.GetName()+" route: "+route);
		AIRail.SetCurrentRailType(route.GetRailType());
		if(additionalPlace.GetProducing().IsTreatCargo(route.cargo)) {
			additionalPlace = additionalPlace.GetProducing();
		}
		local stationFactory = TerminalStationFactory();
		stationFactory.platformLength = route.srcHgStation.platformLength;
		stationFactory.minPlatformLength = route.GetPlatformLength();
		if(CargoUtils.IsPaxOrMail(route.cargo)) {
			stationFactory.platformNum = 3;
		}
		local additionalHgStation = stationFactory.CreateBest(additionalPlace, route.cargo, route.destHgStation.platformTile);
		if(additionalHgStation == null) {
			HgLog.Info("TrainRoute: cannot build additional station");
			return 1;
		}

		local aiExecMode = AIExecMode();

		additionalHgStation.cargo = route.cargo;
		additionalHgStation.isSourceStation = false;
		if(!additionalHgStation.BuildExec()) {
			return 1;
		}
		AddRollback(additionalHgStation);
		
		local railBuilder = TwoWayPathToStationRailBuilder(
			GetterFunction( function():(route) {
				return route.GetTakeAllPathSrcToDest();
			}),
			GetterFunction( function():(route) {
				return route.GetTakeAllPathDestToSrc().Reverse();
			}),
			additionalHgStation, HogeAI.Get().pathFindLimit, HogeAI.Get());
			
		railBuilder.engine = route.GetLatestEngineSet().engine;
		railBuilder.cargo = route.cargo;
		railBuilder.platformLength = route.GetPlatformLength();
		railBuilder.distance = AIMap.DistanceManhattan(additionalPlace.GetLocation(), route.destHgStation.GetLocation());
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			railBuilder.isBuildDepotsDestToSrc = true;
		} else {
			railBuilder.isBuildSingleDepotDestToSrc = true;
		}
		if(!railBuilder.Build()) {
			HgLog.Warning("TrainRoute: railBuilder.Build failed.");
			Rollback();
			return 2;
		}
		ClearRollback();
		
		if(additionalHgStation.stationGroup == null) {
			HgLog.Warning("TrainRoute: additionalHgStation was removed."); // 稀に建設中に他ルートの削除と重なって駅が削除される事がある
			return 1;
		}
		
		route.AddDepots(railBuilder.depots);
		if(route.GetLastRoute().returnRoute != null) {
			route.GetLastRoute().RemoveReturnRoute(); // dest追加でreturn routeが成立しなくなる場合があるため。
		}
		
		local oldDestStation = route.destHgStation;
		if(route.GetFinalDestPlace() != null) {
			Place.SetRemovedDestPlace(route.GetFinalDestPlace());
		}
		additionalHgStation.BuildAfter();

		local removeRemain1 = route.pathSrcToDest.CombineByFork(railBuilder.buildedPath1, false);
		local removeRemain2 = route.pathDestToSrc.CombineByFork(railBuilder.buildedPath2, true);
		
		local removePath1 = removeRemain1[0];
		local removePath2 = removeRemain2[0];
		
		route.pathSrcToDest = removeRemain1[1];
		route.pathDestToSrc = removeRemain2[1];
		route.pathSrcToDest.route = route;
		route.pathDestToSrc.route = route;
		route.Save();

		oldDestStation.RemoveDepots();
		
		
		route.AddDestination(additionalHgStation);
		route.AddForkPath(BuildedPath(removePath1)); // ConvertRail用
		route.AddForkPath(BuildedPath(removePath2)); 

		/* destがcloseしたときに再利用されるので削除しない
		DelayCommandExecuter.Get().Post(300,function():(removePath1,removePath2,oldDestStation) { //TODO: save/loadに非対応
			removePath1.RemoveRails();
			removePath2.RemoveRails();
			oldDestStation.Remove();
		});
		*/
		
		/*
		route.AddAdditionalTiles(removePath1.GetTiles());
		route.AddAdditionalTiles(removePath2.GetTiles());*/
		
		
		HgLog.Info("# TrainRoute: Extend succeeded: "+route);
		return 0;
	}
	
}

class TrainReturnRouteBuilder extends Construction {

	route = null;
	srcPlace = null;
	destPlace = null;
	
	constructor(route,srcPlace,destPlace) {
		Construction.constructor();
		this.route = route;
		this.srcPlace = srcPlace;
		this.destPlace = destPlace;
	}
	
	function DoBuild() {
		//TODO 後半は駅作成失敗が多くなるので、先に駅が建てられるかを調べる。ルート検索はコストが重いので最後に
		HgLog.Info("# TrainRoute: Try BuildReturnRoute:"+destPlace.GetName()+"<-"+srcPlace.GetName()+" route: "+route);
		local testMode = AITestMode();
		local railStationCoverage = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local returnPath = route.GetPathAllDestToSrc();
		local transferStation = HogeAI.Get().GetBuildableStationByPath(returnPath, srcPlace!=null ? srcPlace.GetLocation() : null, route.cargo, route.GetPlatformLength());
		if(transferStation == null) {
			HgLog.Info("TrainRoute: cannot build transfer station");
			return null;
		}
		AIRail.SetCurrentRailType(route.GetRailType());

		local railBuilderTransferToPath;
		local railBuilderPathToTransfer;
		{
			//TODO 失敗時のロールバック
			local aiExecMode = AIExecMode();
			if(!transferStation.BuildExec()) {
				// TODO Place.AddNgPlace();
				HgLog.Warning("TrainRoute: cannot build transfer station "+HgTile(transferStation.platformTile)+" "+transferStation.stationDirection);
				return null;
			}
			AddRollback(transferStation);
			

			
			railBuilderTransferToPath = TailedRailBuilder.PathToStation(GetterFunction( function():(route) {
				local returnPath = route.GetPathAllDestToSrc();
				return returnPath.SubPathEnd(returnPath.GetLastTileAt(4)).Reverse();
			}), transferStation, 150, HogeAI.Get(), null, false);
			railBuilderTransferToPath.engine = route.GetLatestEngineSet().engine;
			railBuilderTransferToPath.cargo = route.cargo;
			railBuilderTransferToPath.platformLength = route.GetPlatformLength();
			railBuilderTransferToPath.isReverse = true;
			railBuilderTransferToPath.isTwoway = false;
			if(!railBuilderTransferToPath.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderTransferToPath");
				Rollback();
				return null;
			}
			
			AddRollback(railBuilderTransferToPath.buildedPath); // TODO Rollback時に元の線路も一緒に消える事がある。limit date:300の時に消えている
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			railBuilderPathToTransfer = TailedRailBuilder.PathToStation(GetterFunction( function():(route, pointTile) {
				return route.GetPathAllDestToSrc().SubPathStart(pointTile);
			}), transferStation, 150, HogeAI.Get());
			railBuilderPathToTransfer.engine = route.GetLatestEngineSet().engine;
			railBuilderPathToTransfer.cargo = route.cargo;
			railBuilderPathToTransfer.platformLength = route.GetPlatformLength();
			railBuilderPathToTransfer.isTwoway = false;
			
			if(!railBuilderPathToTransfer.BuildTails()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderPathToTransfer");
				Rollback();
				return null;
			}
			
			AddRollback(railBuilderPathToTransfer.buildedPath);
			
		}

		
		{
			local returnDestStationFactory = TerminalStationFactory();
			returnDestStationFactory.platformLength = route.GetPlatformLength();
			returnDestStationFactory.minPlatformLength = route.GetPlatformLength();
			
			local returnDestStation = returnDestStationFactory.CreateBest(destPlace, route.cargo, transferStation.platformTile, false);
				// station groupを使うと同一路線の他のreturnと競合して列車が迷子になる事がある
			if(returnDestStation == null) {
				HgLog.Warning("TrainRoute:cannot build returnDestStation");
				Rollback();
				return null;
			}
				
			local aiExecMode = AIExecMode();
			returnDestStation.cargo = route.cargo;
			returnDestStation.isSourceStation = false;
			if(!returnDestStation.BuildExec()) {
				HgLog.Warning("TrainRoute: cannot build returnDestStation");
				Rollback(); // TODO: 稀にtransfer station側に列車が紛れ込んでいてrouteが死ぬ時がある。(正規ルート側にdouble depotがあるケース？）
				return null;
			}
			AddRollback(returnDestStation);
			
			
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			local railBuilderReturnDest = TwoWayPathToStationRailBuilder();
			railBuilderReturnDest.pathDepatureGetter = GetterFunction( function():(route, railBuilderTransferToPath) {
					return route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile()).Reverse();
				});
			railBuilderReturnDest.pathArrivalGetter = GetterFunction( function():(route, pointTile, railBuilderReturnDest) {
					local pathForReturnDest = route.GetPathAllDestToSrc().SubPathEnd(pointTile);
					return pathForReturnDest.SubPathStart(railBuilderReturnDest.buildedPath1.path.GetFirstTile()); // TODO: railBuilderReturnDestDepartureと分岐点がクロスする事がある
				});
			railBuilderReturnDest.isReverse = true;
			railBuilderReturnDest.destHgStation = returnDestStation;
			railBuilderReturnDest.limitCount = 150;
			railBuilderReturnDest.eventPoller = HogeAI.Get();
			railBuilderReturnDest.cargo = route.cargo;
			railBuilderReturnDest.platformLength = route.GetPlatformLength();
			railBuilderReturnDest.distance = AIMap.DistanceManhattan(returnDestStation.GetLocation(), route.srcHgStation.GetLocation());
			if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
				railBuilderReturnDest.isBuildDepotsDestToSrc = true;
			}
			if(!railBuilderReturnDest.Build()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderReturnDestDeparture");
				Rollback();
				return null;
			}
			

			local returnRoute = TrainReturnRoute(route, transferStation, returnDestStation, 
				railBuilderPathToTransfer.buildedPath, railBuilderTransferToPath.buildedPath,
				railBuilderReturnDest.buildedPath1, railBuilderReturnDest.buildedPath2);
				
			returnRoute.AddDepots( railBuilderReturnDest.depots );

		
			route.returnRoute = returnRoute;
			route.Save();
			returnRoute.Initialize();
			
			ClearRollback();
			PlaceDictionary.Get().AddRoute(returnRoute);
			

			route.slopesTable.clear(); // TODO: ChangeDestinationと同様、登れるのかの再確認が必要
			route.AddReturnTransferOrder(transferStation, returnDestStation);
			

			HgLog.Info("# TrainRoute: build return route succeeded:"+returnRoute);
			return returnRoute;
		}
		
	}

}
