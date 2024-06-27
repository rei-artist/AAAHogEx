
class TrainRoute extends Route {
	static instances = [];
	static removed = []; // TODO: Save/Load
	static unsuitableEngineWagons = {};
	static canDeliverCargos = ExpirationTable(360);
	
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
	
	static function LoadFrom(t) {
		local destHgStations = [];
		foreach(stationId in t.destHgStations) {
			if(stationId != null) {
				if(HgStation.worldInstances.rawin(stationId)) { // station削除 => destHgStationsから削除のパターンがある
					destHgStations.push(HgStation.worldInstances[stationId]);
				}
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
		trainRoute.vehicleGroup = t.vehicleGroup;
		if(trainRoute.vehicleGroup != null) {
			Route.groupRoute.rawset(trainRoute.vehicleGroup,trainRoute);
		}
		trainRoute.subCargos = t.subCargos;
		trainRoute.isTransfer = t.transferRoute;
		trainRoute.isSrcTransfer = t.isSrcTransfer;
		trainRoute.isBiDirectional = t.isBiDirectional;
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
		trainRoute.srcDepot = t.srcDepot;
		trainRoute.destDepot = t.destDepot;
		trainRoute.branchLines = {};
		foreach(stationId, tpaths in t.branchLines) {
			local paths = [];
			foreach(path in tpaths) {
				paths.push(BuildedPath(Path.Load(path)));
			}
			trainRoute.branchLines.rawset(stationId, paths);
		}
		trainRoute.depotInfos = t.depotInfos;
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
		trainRoute.productionChackDate = t.productionChackDate;
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
		trainRoute.InitializeCargoSet();
		return trainRoute;
	}
	
	static function LoadStatics(data) {
		TrainRoute.instances.clear();
		foreach(t in data.trainRoutes) {
			local trainRoute = TrainRoute.LoadFrom(t);
			if(trainRoute==null) { 
				continue;
			}
			local latestEngineSet = trainRoute.GetLatestEngineSet();
			HgLog.Info("load:"+trainRoute+(latestEngineSet != null ? " "+latestEngineSet+" maxVehicles:"+latestEngineSet.maxVehicles:""));
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
	
	static function GetIdealDistance(cargo) {
		local result = 0;
		local maxValue = 0;
		local infrastractureTypes = TrainRoute.GetDefaultInfrastractureTypes();
		foreach(distanceIndex, distance in HogeAI.distanceEstimateSamples) {
			local estimate = Route.Estimate(AIVehicle.VT_RAIL, cargo, distance, 890, CargoUtils.IsPaxOrMail(cargo) ? true: false, infrastractureTypes);
			if(estimate == null) {
				HgLog.Info("distance:"+distance+" estimate:null");
				continue;
			}
			//local value = estimate.routeIncome; //roiの時もすぐbuildingTimeBaseになるので、最初から大きめに。
			local value = HogeAI.Get().buildingTimeBase ? estimate.routeIncome : estimate.value; // 理想距離なのでbuildingTimeの場合、建築時間を含めない
			HgLog.Info("distance:"+distance+" estimate:"+value);
			if(maxValue < value) {
				result = distance;
				maxValue = value;
			}
		}
		HgLog.Info("IdealDistance:"+result+" cargo:"+AICargo.GetName(cargo));
		return result;
	}
	
	function AddUnsuitableEngineWagon(trainEngine, wagonEngine) {
		TrainRoute.unsuitableEngineWagons.rawset(trainEngine+"-"+wagonEngine,0);
	}
	
	function GetEstimator(self) {
		local result = TrainEstimator();
		result.skipWagonNum = 5; //HogeAI.Get().roiBase ? 3 : 5;
		result.limitTrainEngines = 1;
		result.limitWagonEngines = 1;
		result.checkRailType = true;
		return result;
	}
	
	routeType = null;
	cargo = null;
	srcHgStation = null;
	destHgStation = null;
	pathSrcToDest = null;
	pathDestToSrc = null;
	vehicleGroup = null;
	
	startDate = null;
	subCargos = null; // 受け入れ可能cargo(mainCargo以外)
	destHgStations = null;
	srcDepot = null;
	destDepot = null;
	branchLines = null;
	isTransfer = null;
	isSrcTransfer = null;
	isBiDirectional = null;
	pathDistance = null;
	depotInfos = null;
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
	productionChackDate = null;
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
	cargoSet = null;
	

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
		this.branchLines = {};
		this.engineVehicles = {};
		this.isClosed = false;
		this.isRemoved = false;
		this.depotInfos = {};
		this.failedUpdateRailType = false;
		this.reduceTrains = false;
		this.usedRateHistory = [];
		this.slopesTable = {};
		this.trainLength = 7;
		this.additionalTiles = [];
		this.cannotChangeDest = false;
		this.pathDistance = pathSrcToDest.path.GetRailDistance();
		this.cargoSet = {};
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
		t.vehicleGroup <- vehicleGroup;
		t.subCargos <- subCargos;
		t.transferRoute <- isTransfer;
		t.isSrcTransfer <- isSrcTransfer;
		t.isBiDirectional <- isBiDirectional;
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
		t.srcDepot <- srcDepot;
		t.destDepot <- destDepot;
		t.branchLines <- {};
		foreach(stationId, paths in branchLines) {
			local tpaths = [];
			foreach(path in paths) {
				tpaths.push(path.array_);
			}
			t.branchLines.rawset(stationId,tpaths);
		}
		t.depotInfos <- depotInfos;
		t.reduceTrains <- reduceTrains;
		t.maxTrains <- maxTrains;
		t.slopesTable <- slopesTable;
		t.usedRateHistory <- usedRateHistory;
		t.engineSetsCache <- engineSetsCache;
		t.engineSetsDate <- engineSetsDate;
		t.engineSetAllRailCache <- engineSetAllRailCache;
		t.engineSetAllRailDate <- engineSetAllRailDate;
		t.productionChackDate <- productionChackDate;
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
		if(vehicleGroup == null) {
			vehicleGroup = AIGroup.CreateGroup( GetVehicleType() );
			AIGroup.SetName(vehicleGroup, CreateGroupName());
			Route.groupRoute.rawset(vehicleGroup,this);
		}
		Save();
		InitializeSubCargos();
	}
	
	function InitializeSubCargos() {
		saveData.subCargos = subCargos = CalculateSubCargos();
		InitializeCargoSet();
	}
	
	function InitializeCargoSet() {
		cargoSet = {};
		cargoSet.rawset(cargo, cargo);
		foreach(c in subCargos) {
			cargoSet.rawset(c,c);
		}
	}
	
	function SetCannotChangeDest(cannotChangeDest) {
		saveData.cannotChangeDest = this.cannotChangeDest = cannotChangeDest;
	}
	
	function GetLatestEngineSet() {
		return latestEngineSet;
	}
	
	function CalculateSubCargos() {
		local result = [];
		local names = [];
		foreach(subCargo in Route.CalculateSubCargos()) {
			if(CanDeliverCargo(subCargo)) {
				names.push(AICargo.GetName(subCargo));
				result.push(subCargo);
			}
		}
		HgLog.Info("CalculateSubCargos:["+HgArray(names)+"] "+this);
		return result;
	}
		
	function CanDeliverCargo(cargo) {
		//このルートが追加でcargoを運べるかどうか
		local railType = GetRailType();
		local key = railType+"-"+cargo;
		if(TrainRoute.canDeliverCargos.rawin(key)) {
			return TrainRoute.canDeliverCargos.rawget(key);
		}
		
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);
		foreach(engine,_ in engineList) {
			if(AIVehicle.GetBuildWithRefitCapacity(srcDepot, engine, cargo) >= 1) {
				TrainRoute.canDeliverCargos.rawset(key,true);
				return true;
			}
		}
		TrainRoute.canDeliverCargos.rawset(key,false);
		return false;
	}

	function GetCargos() {
		local result = [cargo];
		result.extend(subCargos);
		return result;
	}

	function HasCargo(cargo) {
		return cargoSet.rawin(cargo);
	}
	
	function IsDeliveringCargo(cargo) {
		local engineSet = GetLatestEngineSet();
		if(engineSet == null) {
			return false;
		}
		return engineSet.cargoCapacity.rawin(cargo) && engineSet.cargoCapacity.rawget(cargo) > 0;
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
		return AIGroup.GetNumVehicles(vehicleGroup, 0);
	}
	
	function GetMaxVehicles() {
		return maxTrains;
	}
	
	function GetVehicleList() {
		if(vehicleGroup==null) {
			return AIList();
		}
		return AIVehicleList_Group(vehicleGroup);
	}

	function GetOrderVehicle() {
		local vehicleList = GetVehicleList();
		if(vehicleList.Count() >= 1) {
			return vehicleList.Begin();
		}
		return null;
	}
	
	function GetLatestVehicle() {
		local vehicleList = GetVehicleList();
		vehicleList.Valuate(AIVehicle.GetAge);
		vehicleList.Sort(AIList.SORT_BY_VALUE,true);
		if(vehicleList.Count() >= 1) {
			return vehicleList.Begin();
		}
		return null;
/*
		if(latestEngineVehicle == null || !AIVehicle.IsValidVehicle(latestEngineVehicle) || AIVehicle.GetGroupID(latestEngineVehicle) != vehicleGroup) {
			saveData.latestEngineVehicle = latestEngineVehicle = _GetLatestVehicle();
		}
		return latestEngineVehicle;*/
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
		
	function AddDepotInfos(depotInfos) {
		foreach(tile,info in depotInfos) {
			this.depotInfos.rawset(tile,info);
		}
	}
	
	function GetDepots() {
		local result = [];
		foreach(tile,info in depotInfos) {
			result.extend(info.depots);
		}
		return result;
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
		foreach(vehicle,_ in GetVehicleList()) {
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
	
	function GetDeliveringProductions(days) {
		local list = GetVehicleList()
		local result = {};
		list.Valuate(AIOrder.GetOrderDestination, AIOrder.ORDER_CURRENT);
		list.KeepValue(destHgStation.platformTile);
		if(list.Count() == 0) {
			return null;
		}
		foreach(cargo in GetCargos()) {
			list.Valuate(AIVehicle.GetCargoLoad, cargo);
			local sum = 0;
			foreach(v,load in list) {
				sum += load;
			}
			result[cargo] <- sum * 30 / (days/2);
		}
		return result;
	}
	
	
	function EstimateCargoProductions() {
		local result = {};
		local ss = [];
		foreach(cargo, prod in GetCargoProductions()) {
			ss.push(AICargo.GetName(cargo)+"="+prod);
			if(cargo == this.cargo) {
				result.rawset(cargo,max(50,prod * 3 / 2));
			} else if(prod > 0) {
				result.rawset(cargo,prod * 3 / 2); // 将来増えても対応できるように増やす
			}
		}
		HgLog.Info("EstimateCargoProductions:"+HgArray(ss)+" "+this);
		return result;
	/*
		local latestEngineSet = GetLatestEngineSet();
		local cargoProductions = null;
		if(latestEngineSet != null && engineSetsCache != null) {
			if(engineSetsDate + latestEngineSet.days < AIDate.GetCurrentDate()) { // 新列車になってから1周分が経過してから
				cargoProductions = GetDeliveringProductions(latestEngineSet.days);
				if(cargoProductions != null) {
					local ss = [];
					foreach(cargo,prod in cargoProductions) {
						local waiting = srcHgStation.GetCargoWaiting(cargo);
						local rating = AIStation.GetCargoRating(srcHgStation.stationId,cargo);
						ss.push(AICargo.GetName(cargo)+"="+prod+" wt:"+waiting+" rate:"+rating);
						cargoProductions.rawset(cargo, prod * 70 / min(70,rating) + waiting / 8);
					}
					HgLog.Info("GetDeliveringProductions:"+HgArray(ss)+" "+this);
				}
			}
		}
		if(cargoProductions == null) {
			cargoProductions = GetCargoProductions();
		}
		local ss = [];
		local result = {};
		foreach(cargo, prod in cargoProductions) {
			ss.push(AICargo.GetName(cargo)+"="+prod);
			if(cargo == this.cargo) {
				result.rawset(cargo,max(50,prod * 3 / 2));
			} else if(prod > 0) {
				result.rawset(cargo,prod * 3 / 2); // 将来増えても対応できるように増やす
			}
		}
		HgLog.Info("EstimateCargoProductions:"+HgArray(ss)+" "+this);
		return result;*/
	/*
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
		saveData.oldCargoProduction = oldCargoProduction = cargoProduction;
		local ss = [];
		foreach(cargo, prod in result) {
			ss.push(AICargo.GetName(cargo)+"="+prod);
		}
		HgLog.Info("EstimateCargoProductions:"+HgArray(ss)+" "+this);
		return result;*/
	
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
		foreach(vehicle,_ in GetVehicleList()) {
			foreach(index, cargo in cargos) {
				capa[index] += AIVehicle.GetCapacity(vehicle, cargo);
				load[index] += AIVehicle.GetCargoLoad(vehicle, cargo);
			}
		}
		return [load,capa];
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
	
	function GetEngineSets(isAll=false, additionalDistance=null) {
		// additionalDistanceは使用されてないかも
		if(!isAll && additionalDistance==null && engineSetsCache != null && engineSetsCache.len() >= 1) {
			if(TrainRoute.instances.len()<=1 && HogeAI.Get().roiBase) {
				return engineSetsCache;
			}
			local minDesignSpan;
			local lifeTime = AIDate.GetCurrentDate() - startDate;
			if(lifeTime < 5 * 365) {
				minDesignSpan = 365;
			} else if(lifeTime < 10 * 365) {
				minDesignSpan = 3 * 365;
			} else {
				minDesignSpan = 10 * 365;
			}
			local latestEngineSet = GetLatestEngineSet();
			if(latestEngineSet!=null) { // 長さに余裕がある場合は毎年チェック
				local platformLength = GetPlatformLength();
				if(platformLength < 8) {
					if(latestEngineSet.length/16 < platformLength-1) {
						minDesignSpan = 365;
					}
				} else {
					if(latestEngineSet.length/16 < platformLength*2/3) {
						minDesignSpan = 365;
					}
				}
			}
			if(latestEngineSet!=null && AIDate.GetCurrentDate() < engineSetsDate + max(minDesignSpan,latestEngineSet.cruiseDays * 6)) {
				return engineSetsCache; // 最低1年か3往復は設計維持
			}
			if(latestEngineSet!=null && AIDate.GetCurrentDate() < engineSetsDate + 10 * 365 ) {
				if(productionChackDate==null || productionChackDate + 365 < AIDate.GetCurrentDate()) { // 1年毎に生産量チェック
					saveData.productionChackDate = AIDate.GetCurrentDate();
					local cargoProd = GetCargoProductions();
					local oldCargoProd = latestEngineSet.cargoProduction;
					if(oldCargoProd.len() == cargoProd.len()) {
						local ok = true;
						foreach(cargo,newProd in cargoProd) {
							local oldProd = oldCargoProd.rawin(cargo) ? oldCargoProd[cargo] : 0;
							if(newProd > oldProd && srcHgStation.GetCargoWaiting(cargo) > 1000) { // 設計から10年以内は前提cargoより生産が増加したら再設計
								ok = false;
								break;
							}
						}
						if(ok) {
							return engineSetsCache;
						}
					}
				} else {
					return engineSetsCache;
				}
			}
		}
		InitializeSubCargos(); // 使えるcargoが増えているかもしれないので再計算をする。
	
		local execMode = AIExecMode();
		local trainEstimator = TrainEstimator();
		trainEstimator.route = this;
		trainEstimator.cargo = cargo;
		trainEstimator.distance = GetDistance() + (additionalDistance != null ? additionalDistance : 0);
		trainEstimator.pathDistance = pathDistance + (additionalDistance != null ? additionalDistance : 0)
			+ srcHgStation.platformLength + destHgStation.platformLength;
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
			trainEstimator.limitWagonEngines = 6;
			trainEstimator.limitTrainEngines = 6;		
		}
		trainEstimator.isSingleOrNot = IsSingle();
		trainEstimator.ignoreIncome = IsTransfer();
		trainEstimator.cargoIsTransfered = GetCargoIsTransfered();
		
		if(additionalDistance != null) {
			return trainEstimator.GetEngineSetsOrder();
		}
	
		// TODO: ほとんど変わらないのにコストをかけて車両交換する事が多い。あまり変わらない場合は更新しない
		// productionが在庫で変動するので、頻繁に変更もかかる。長距離路線だと一往復もしないうちの事が多い
		saveData.engineSetsCache = engineSetsCache = trainEstimator.GetEngineSetsOrder();
		saveData.engineSetsDate = engineSetsDate = AIDate.GetCurrentDate(); // + (IsSingle() ? 3000 : 1000) + AIBase.RandRange(500);

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
		trainEstimator.pathDistance = pathDistance + srcHgStation.platformLength + destHgStation.platformLength;
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
		if(!IsSingle()) {
			local result = _BuildFirstTrain();
			if(result != null) {
				CloneAndStartTrain(false,result);
			}
			return result != null;
		} else {
			return _BuildFirstTrain() != null;
		}
	}
	
	function _BuildFirstTrain() {
		saveData.latestEngineVehicle = latestEngineVehicle = BuildTrain(); //TODO 最初に失敗すると復活のチャンスなし。orderが後から書き変わる事があるがそれが反映されないため。orderを状態から組み立てられる必要がある
		if(latestEngineVehicle == null) {
			HgLog.Warning("BuildFirstTrain failed. "+this);
			return null;
		}
		AIGroup.MoveVehicle(vehicleGroup, latestEngineVehicle);
		BuildOrder(latestEngineVehicle);
		if(!AIVehicle.StartStopVehicle(latestEngineVehicle)) {
			HgLog.Warning("StartStopVehicle failed."+this+" "+AIError.GetLastErrorString());
			if(AIError.GetLastError() == AIError.ERR_NEWGRF_SUPPLIED_ERROR) {
				foreach(wagonEngineInfo in latestEngineSet.wagonEngineInfos) {
					AddUnsuitableEngineWagon(latestEngineSet.trainEngine, wagonEngineInfo.engine);
				}
				AIVehicle.SellWagonChain(latestEngineVehicle, 0);
				return _BuildFirstTrain(); //リトライ
			}
		}
		engineVehicles.rawset(latestEngineVehicle,latestEngineSet);
		if(startDate == null) {
			saveData.startDate = startDate = AIDate.GetCurrentDate();
		}
		return latestEngineVehicle;
	}
	
	function BuildNewTrain(depotTile=null) {
		local oldCargoCapacity = latestEngineSet == null ? {} :  latestEngineSet.cargoCapacity;
		local latestVehicle = GetLatestVehicle();
		local newTrain = BuildTrain(0,depotTile);
		if(newTrain == null) {
			return false;
		}
		AIGroup.MoveVehicle(vehicleGroup, newTrain);
		if(latestVehicle == null) {
			HgLog.Warning("Cannot ShareOrders latestVehicle == null. (BuildNewTrain) "+this);
			BuildOrder(newTrain); // 他の列車とオーダーが共有されなくなるのでChangeDestinationなどがうまくいかなくなる。Sellすべきかもしれない
		} else if(!AIOrder.ShareOrders(newTrain, latestVehicle)) {
			HgLog.Warning("ShareOrders failed.(BuildNewTrain)"+this+" "+AIError.GetLastErrorString());
			BuildOrder(newTrain); // 他の列車とオーダーが共有されなくなるのでChangeDestinationなどがうまくいかなくなる。Sellすべきかもしれない
		}
		if( AIOrder.GetOrderCount(newTrain) == 0 ) {
			HgLog.Warning("AIOrder.GetOrderCount(newTrain) == 0(BuildNewTrain)"+this);
			AIVehicle.SellWagonChain(newTrain, 0);
			return false;
		}
		if(!AIVehicle.StartStopVehicle(newTrain)) {
			HgLog.Warning("StartStopVehicle failed.(BuildNewTrain)"+this+" "+AIError.GetLastErrorString());
			if(AIError.GetLastError() == AIError.ERR_NEWGRF_SUPPLIED_ERROR) {
				foreach(wagonEngineInfo in latestEngineSet.wagonEngineInfos) {
					AddUnsuitableEngineWagon(latestEngineSet.trainEngine, wagonEngineInfo.engine);
				}
				AIVehicle.SellWagonChain(newTrain, 0);
				return BuildNewTrain(depotTile); //リトライ
			}
			return false;
		}
		engineVehicles.rawset(newTrain,latestEngineSet);	
		saveData.latestEngineVehicle = latestEngineVehicle = newTrain;
		saveData.oldCargoProduction = oldCargoProduction = GetCargoProductions(); // 列車新造時点での推定値を保存
		/*
		foreach(cargo in GetCargos()) {
			if(!oldCargoCapacity.rawin(cargo) && latestEngineSet.cargoCapacity.rawin(cargo)) {
				foreach(place in srcHgStation.stationGroup.GetProducingHgIndustries(cargo)) {
					HgLog.Info("AddPlace. ["+AICargo.GetName(cargo)+"] " + place + " " +srcHgStation+ " " +this);
					srcHgStation.AddPlace(place);
				}
				if(IsBiDirectional()) {
					foreach(place in destHgStation.stationGroup.GetProducingHgIndustries(cargo)) {
						HgLog.Info("AddPlace. ["+AICargo.GetName(cargo)+"] " + place + " " +destHgStation+" "+this);
						destHgStation.AddPlace(place);
					}
				}
			}
		}*/
/*			else if(!latestEngineSet.cargoCapacity.rawin(cargo) && oldCargoCapacity.rawin(cargo)) {
				// 使うのをやめた場合
				foreach(place in srcHgStation.stationGroup.GetProducingHgIndustries(cargo)) {
					HgLog.Info(" Remove cargo. ["+AICargo.GetName(cargo)+"] " + place + " " +srcHgStation+ " " +this);
					srcHgStation.RemovePlace(place);
				}
				if(IsBiDirectional()) {
					foreach(place in destHgStation.stationGroup.GetProducingHgIndustries(cargo)) {
						HgLog.Info(" Remove cargo. ["+AICargo.GetName(cargo)+"] " + place + " " +destHgStation+ " " +this);
						destHgStation.RemovePlace(place);
					}
				}
			}*/
//		}
		
		return true;
	}
	
	function CloneAndStartTrain(isDest, latestEngineVehicle) {
		if(latestEngineVehicle == null) {
			BuildFirstTrain();
			return;
		}
		if(IsSingle()) {
			return;
		}
		if(!engineVehicles.rawin(latestEngineVehicle)) {
			HgLog.Warning("CloneAndStartTrain failed. !engineVehicles.rawin(latestEngineVehicle) "+this);
			return;
		}
		local oldCargoCapacity = engineVehicles[latestEngineVehicle].cargoCapacity;
		local engineSet = ChooseEngineSet();
		if(!HasVehicleEngineSet(latestEngineVehicle, engineSet)) {
			//HgLog.Info("BuildTrain HasVehicleEngineSet == false "+this);
			BuildNewTrain();	
			local newCargo = null;
			foreach(cargo,capacity in engineSet.cargoCapacity) {
				if(!oldCargoCapacity.rawin(cargo)) { // TODO: cargoがなくなる場合も
					HgLog.Info("New cargo delivable["+AICargo.GetName(cargo)+"] "+this);
					newCargo = cargo;
				}
			}
			if(newCargo != null){ 
				foreach(route in destHgStation.stationGroup.GetUsingRoutesAsSource()) {
					route.NotifyAddTransfer(newCargo); // TODO: 複数cargo
				}
				if(IsBiDirectional()) {
					foreach(route in srcHgStation.stationGroup.GetUsingRoutesAsSource()) {
						route.NotifyAddTransfer(newCargo);
					}
				}
			}
		} else {
			local remain = TrainRoute.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, TrainRoute.GetVehicleType());
			if(remain <= 2) {
				return;
			}
			if( CloneTrain(isDest, latestEngineVehicle) == null ) {
				saveData.engineSetsCache = engineSetsCache = null;
				BuildNewTrain();
			}
		}
	}
	
	function CloneTrain(isDest, latestVehicle) {
		local execMode = AIExecMode();
		if(latestVehicle == null) {
			HgLog.Warning("CloneVehicle failed. latestVehicle == null "+this);
			return null;
		}
		local depotTile = isDest ? destDepot : srcDepot;
		local engineVehicle = null;
		local latestVehicleName = AIVehicle.GetName(latestVehicle);
		for(local need=20000;; need+= 10000) {
			local r = HogeAI.WaitForMoney(need);
			engineVehicle = AIVehicle.CloneVehicle(depotTile, latestVehicle, true);
			if(AIError.GetLastError()!=AIError.ERR_NOT_ENOUGH_CASH || !r) {
				break;
			}
		}
		if(!AIVehicle.IsValidVehicle(engineVehicle)) {
			HgLog.Warning("CloneVehicle failed. "+latestVehicleName+ " "+HgTile(depotTile)+" "+AIError.GetLastErrorString()+" "+this);
			return null;
		}
		AIGroup.MoveVehicle(vehicleGroup, latestEngineVehicle);
		if( AIOrder.GetOrderCount(engineVehicle) == 0 ) {
			HgLog.Warning("AIOrder.GetOrderCount(engineVehicle) == 0 "+latestVehicleName+ " "+this);
			return null;
		}
		engineVehicles.rawset( engineVehicle, engineVehicles[latestVehicle] );
		if(isDest) {
			if(returnRoute != null) {
				AIOrder.SkipToOrder(engineVehicle, 3);
			} else if(IsBiDirectional()) {
				AIOrder.SkipToOrder(engineVehicle, 2);
			}
		}
		AIVehicle.StartStopVehicle(engineVehicle);
		saveData.latestEngineVehicle = latestEngineVehicle = engineVehicle;		
		return engineVehicle;
	}
	
	function BuildEngineVehicle(engineVehicles, trainEngine, depotTile, explain) {
		local engineVehicle = BuildUtils.BuildVehicleWithRefitSafe(depotTile, trainEngine, cargo);
		if(!AIVehicle.IsValidVehicle(engineVehicle)) {
			local error = AIError.GetLastError();
				HgLog.Warning("BuildVehicleWithRefit failed. engine:"
					+ AIEngine.GetName(trainEngine) + " depot:" + HgTile(depotTile)
					+ " " + AIError.GetLastErrorString() + " " + this);
			if(engineVehicles.len() >= 1) {
				AIVehicle.SellWagonChain(engineVehicles[0], 0);
			}
			if(error == AIVehicle.ERR_VEHICLE_TOO_MANY) {
				return null;
			}
			return false;
		}
		if(engineVehicles.len() >= 1 && !AIVehicle.MoveWagon(engineVehicle, 0, engineVehicles[0], engineVehicles.len()-1)) {
			HgLog.Warning("MoveWagon engineVehicle failed. "+explain + " "+AIError.GetLastErrorString()+" "+this);
			AIVehicle.SellWagonChain(engineVehicles[0], 0);
			AIVehicle.SellWagonChain(engineVehicle, 0);
			return false;
		}
		engineVehicles.push(engineVehicle);
		return true;
	}

	function BuildTrain(mode = 0, depotTile = null) {
		local execMode = AIExecMode();
		local isAll = false;
		if(mode == 1) {
			saveData.engineSetsCache = engineSetsCache = null;
		} else if(mode == 2) {
			isAll = true;
		}
		if(depotTile == null) {
			depotTile = srcDepot;
		}
		foreach(engineSet in GetEngineSets(isAll)) {
			local trainEngine = engineSet.trainEngine;
			if(!AIEngine.IsBuildable(trainEngine)) {
				continue;
			}
			local unsuitable = false;
			foreach(wagonEngineInfo in engineSet.wagonEngineInfos) {
				if(!AIEngine.IsBuildable(wagonEngineInfo.engine) || TrainRoute.IsUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine)) {
					unsuitable = true;
					break;
				}
			}
			if(unsuitable) {
				continue;
			}
			local explain = engineSet.tostring();
			HgLog.Info("BuildTrain "+explain+" "+this+" maxVehicles:" + engineSet.maxVehicles);

			
			local numEngineVehicle = engineSet.numLoco;
			local engineVehicles = [];
			
			local success = true;
			for(local i=0; i<numEngineVehicle; i++) {
				local r = BuildEngineVehicle(engineVehicles, trainEngine, depotTile, explain);
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
					local wagon = BuildUtils.BuildVehicleWithRefitSafe(depotTile, wagonEngineInfo.engine, wagonEngineInfo.cargo);
					if(!AIVehicle.IsValidVehicle(wagon))  {
						// AddUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine); wagonとの組み合わせの問題ではない
						HgLog.Warning("BuildVehicleWithRefit wagon failed. #"+i+" "+AIEngine.GetName(wagonEngineInfo.engine)
							+"["+AICargo.GetName(wagonEngineInfo.cargo)+"] "+HgTile(depotTile)
							+" "+explain+" "+AIError.GetLastErrorString()+" "+this);
						success = false;
						break;
					}/*
					local wagon = AIVehicle.BuildVehicle(depotTile, wagonEngineInfo.engine);
					if(!AIVehicle.IsValidVehicle(wagon))  {
						// AddUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine); wagonとの組み合わせの問題ではない
						HgLog.Warning("BuildVehicle wagon failed. "+i+" "+AIEngine.GetName(wagonEngineInfo.engine)
							+"["+AICargo.GetName(wagonEngineInfo.cargo)+"] "+HgTile(depotTile)
							+" "+explain+" "+AIError.GetLastErrorString()+" "+this);
						success = false;
						break;
					}
					if(!AIVehicle.RefitVehicle(wagon, wagonEngineInfo.cargo))  {
						// AddUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine); wagonとの組み合わせの問題ではない
						HgLog.Warning("RefitVehicle wagon failed. "+i+" "+AIEngine.GetName(wagonEngineInfo.engine)
							+"["+AICargo.GetName(wagonEngineInfo.cargo)+"] "+HgTile(depotTile)
							+" "+explain+" "+AIError.GetLastErrorString()+" "+this);
						success = false;
						break;
					}*/
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
			local oldEngineSet = GetLatestEngineSet();
			this.latestEngineSet = engineSet;
			if(engineSetsCache != null && engineSetsCache.len() >= 1) {
				engineSetsCache[0] = engineSet; // ChooseEngineSet()で実際に作られたengineSetが返るようにする
			}
			if(returnRoute != null) {
				returnRoute.InitializeSubCargos();
			}
			maxTrains = this.latestEngineSet.maxVehicles;
			if(returnRoute != null) {
				local additionalDistance = returnRoute.destDeparturePath.path.GetRailDistance();
				maxTrains = maxTrains * (pathDistance + additionalDistance) / pathDistance;
				HgLog.Info("maxTrains:"+maxTrains+" "+this);
			}
			local diff;
			if(oldEngineSet == null) {
				diff = {append = latestEngineSet.cargoCapacity, remove = {}};
			} else {
				diff = HgTable.Diff(oldEngineSet.cargoCapacity,latestEngineSet.cargoCapacity);
			}
			foreach(cargo,_ in diff.append) {
				AddPlaceUsingCargo(cargo);
				foreach(place in srcHgStation.stationGroup.GetProducingPlaces(cargo)) {
					HgLog.Info("AddPlace. ["+AICargo.GetName(cargo)+"] " + place + " " +srcHgStation+ " " +this);
					srcHgStation.AddPlace(place);
				}
			}
			foreach(cargo,_ in diff.remove) {
				RemovePlaceUsingCargo(cargo);
				foreach(place in srcHgStation.stationGroup.GetProducingPlaces(cargo)) {
					HgLog.Info("RemovePlace. ["+AICargo.GetName(cargo)+"] " + place + " " +srcHgStation+ " " +this);
					srcHgStation.RemovePlace(place);
				}
			}
			return engineVehicle;
		}
		
		if(mode == 0) {
			HgLog.Warning("BuildTrain failed. Clear cache and retry. ("+AIRail.GetName(GetRailType())+") "+this);
			return BuildTrain(1, depotTile);
		} else if(mode == 1) {
			HgLog.Warning("BuildTrain failed. Try all enginsets. ("+AIRail.GetName(GetRailType())+") "+this);
			return BuildTrain(2, depotTile);
		}
		
		HgLog.Warning("BuildTrain failed. No suitable engineSet. ("+AIRail.GetName(GetRailType())+") "+this);
		saveData.engineSetsCache = engineSetsCache = null;
		return null;
	}
	
	function BuildOrder(engineVehicle) {
		local execMode = AIExecMode();
		AIOrder.AppendOrder(engineVehicle, srcHgStation.platformTile, AIOrder.OF_FULL_LOAD_ANY + AIOrder.OF_NON_STOP_INTERMEDIATE);
		AIOrder.SetStopLocation	(engineVehicle, AIOrder.GetOrderCount(engineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
		AIOrder.AppendOrder(engineVehicle, srcDepot, AIOrder.OF_SERVICE_IF_NEEDED);
		if(IsTransfer()) {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_TRANSFER + AIOrder.OF_NO_LOAD );
		} else if(IsBiDirectional()) {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
		} else {
			AIOrder.AppendOrder(engineVehicle, destHgStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		}
		AIOrder.SetStopLocation	(engineVehicle, AIOrder.GetOrderCount(engineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
		//AIOrder.SetStopLocation	(engineVehicle, AIOrder.GetOrderCount(engineVehicle)-1, AIOrder.STOPLOCATION_NEAR);
		
		if(returnRoute != null) {
			AddReturnTransferOrder(engineVehicle, returnRoute.srcHgStation, returnRoute.destHgStation);
		}
		
		return true;
	}
	
	function AddReturnTransferOrder(vehicle, transferSrcStation, destStation) {
		local execMode = AIExecMode();
		// destStationでLOAD
		// PAXがいると詰まる AIOrder.SetOrderFlags( latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD);
		// YARD
		AIOrder.AppendOrder( vehicle, transferSrcStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE);
		AIOrder.SetStopLocation( vehicle, AIOrder.GetOrderCount(vehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
		// 積載率0の時、return dest stationをスキップ
		local conditionOrderPosition = AIOrder.GetOrderCount(vehicle);
		AIOrder.AppendConditionalOrder( vehicle, 0);
		AIOrder.SetOrderCompareValue( vehicle, conditionOrderPosition, 0);
		AIOrder.SetOrderCompareFunction( vehicle, conditionOrderPosition, AIOrder.CF_EQUALS );
		AIOrder.SetOrderCondition( vehicle, conditionOrderPosition, AIOrder.OC_LOAD_PERCENTAGE );
		// return dest station
		AIOrder.AppendOrder( vehicle, destStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD );
		AIOrder.SetStopLocation( vehicle, AIOrder.GetOrderCount(vehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
	}
	

	function GetTotalWeight(trainEngine, wagonEngine, trainNum, wagonNum, cargo) {
		return AIEngine.GetWeight(trainEngine) * trainNum + (AIEngine.GetWeight(wagonEngine) + TrainRoute.GetCargoWeight(cargo,AIEngine.GetCapacity(wagonEngine))) * wagonNum;
	}
	
	function GetMaxSlopes(length) {
		local path = pathSrcToDest.path;
		local tileLength = ceil(length.tofloat() / 16).tointeger();
		local table;
		if(slopesTable.rawin(tileLength)) {
			table = slopesTable[tileLength];
			if(table.lastPoint==null) {
				return table.maxSlopes;
			}
		} else {
			table = {lastPoint=null,maxSlopes=0};
			slopesTable.rawset(tileLength, table);
		}
		local maxSlopes = path.GetSlopes(tileLength, table.lastPoint);
		table.maxSlopes = max(maxSlopes[0],table.maxSlopes);
		if(returnRoute != null || IsBiDirectional()) {
			table.maxSlopes = max(maxSlopes[1],table.maxSlopes);
		}
		table.lastPoint = null;
		//result = max(result, pathDestToSrc.path.GetSlopes(length));
		//if(pathDestToSrc != null && pathIn == null && (returnRoute != null || IsBiDirectional())) {
		//	result = max(result, GetMaxSlopes(length, pathDestToSrc.path));
		//}
		HgLog.Info("GetMaxSlopes("+length+","+tileLength+")="+table.maxSlopes+" "+this);
		return table.maxSlopes
	}
		
	function IsBiDirectional() {
		return isBiDirectional;
	}
	
	function IsSingle() {
		return pathDestToSrc == null;
	}
	
	function IsTransfer() {
		return isTransfer;
	}

	function IsSrcTransfer() {
		return isSrcTransfer;
	}
	
	function IsRoot() {
		return !IsTransfer(); // 今のところ呼ばれる事は無い。
	}

	function AddDestination(destHgStation) {
		foreach(s in destHgStations) {
			if(s == destHgStation) {
				return;
			}
		}
		destHgStations.push(destHgStation);
		
		pathDistance = pathSrcToDest.path.GetRailDistance();
		
		destHgStation.AddUsingRoute(this); // ChangeDestination失敗時に駅が消されるのを防ぐ

		local oldDest = this.destHgStation;
		this.destHgStation = destHgStation;
		InitializeSubCargos();
		this.destHgStation = oldDest;
		
		maxTrains = null;
		lastDestClosedDate = null;
		needsAdditionalCache.clear();
		productionCargoCache.clear();
		InvalidateEngineSet();
		
		ChangeDestination(destHgStation);
		
		Save();
	}

	function ChangeDestination(destHgStation, checkAcceleration = true) {
		if(returnRoute != null) { // このメソッドはreturn routeがある場合に対応していない
			HgLog.Warning("Cannot ChangeDestination (return route exists) "+this);
			return;
		}

		if(checkAcceleration) {
			local engineSets = {};
			foreach(vehicle,_ in GetVehicleList()) {
				engineSets.rawset(engineVehicles[vehicle],0);
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
		local latestEngineVehicle = GetOrderVehicle();
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
	
	function AddBranchLine(station, srcToDest, destToSrc) {
		branchLines.rawset(station.id, [srcToDest,destToSrc]);
		local point = srcToDest.path.GetLastTile();
		foreach(length, table in slopesTable) {
			if(table.lastPoint == null) {
				table.lastPoint = point;
			}
		}
		Save();
	}

	function RemoveBranchLine(station) {
		HgLog.Info("RemoveBranchLine:"+station.id+" "+this);
		if(!branchLines.rawin(station.id)) {
			HgLog.Warning("not found branchLine:"+station.id+" "+this);
			return;
		}
		local paths = branchLines.rawget(station.id);
		branchLines.rawdelete(station.id);
		Save();

		local points = [ paths[0].array_.top(), paths[1].array_[0] ];
		foreach(path in paths) {
			path.Remove();
		}
		station.RemoveUsingRoute(this);
		station.Remove();
		//station.RemoveOnlyPlatform();
		MainLineRefactor( this,points[0] ,points[1] ).Build();
	}
	
	function GetLastDestHgStation() {
		return destHgStations[destHgStations.len()-1];
	}
	
	function IsAllVehicleNew() {
		foreach(engineVehicle, _ in GetVehicleList()) {
			if(!HasVehicleEngineSet(engineVehicle,latestEngineSet)) {
				return false;
			}
		}
		return true;
	}

	
	function RemoveReturnTransferOder() {
		local execMode = AIExecMode();
		if(latestEngineVehicle != null && AIOrder.GetOrderCount (latestEngineVehicle)>=5) {
			AIOrder.RemoveOrder(latestEngineVehicle, 5);
			AIOrder.RemoveOrder(latestEngineVehicle, 4);
			AIOrder.RemoveOrder(latestEngineVehicle, 3);
		}
	}
	
	
	function GetLastRoute() {
		return this;
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
		
		foreach(engineVehicle, _ in GetVehicleList()) {
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
		if(!HogeAI.Get().IsRich()) {
			return;
		}
		if(latestEngineVehicle != null) {
			HgLog.Info("StartUpdateRail "+AIRail.GetName(railType)+" "+this);
			saveData.updateRailDepot = updateRailDepot = true; //depotInfo.depots[0];
		}
	}
	
	function ConvertRailType(railType,force=false) {
		HgLog.Info("ConvertRailType." + AIRail.GetName(railType) + "<=" + AIRail.GetName(GetRailType()) + " " + this);
		saveData.lastConvertRail = lastConvertRail = AIDate.GetCurrentDate();
		
		local execMode = AIExecMode();
		AIRail.SetCurrentRailType(railType);
		local facitilies = [];
		facitilies.push(srcHgStation);
		foreach(s in destHgStations) {
			HgLog.Info("station:"+s.GetName());
			facitilies.push(s);
		}
		facitilies.push(pathSrcToDest.path);
		if(pathDestToSrc != null) {
			facitilies.push(pathDestToSrc.path);
		}
		foreach(stationId, paths in branchLines) {
			HgLog.Info("branchLines:"+stationId);
			foreach(path in paths) {
				facitilies.push(path.path);
			}
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
		tiles.extend(GetDepots());
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
					if(!force) return false;
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
					if(!force) return false;
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
			if(!force) return false;
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
		//RemoveSendUpdateDepotOrder();
		if(!ConvertRailType(newRailType)) {
			saveData.updateRailDepot = updateRailDepot = null;
			return false;
		}
		engineSetsCache = null;
		local oldVehicles = GetVehicleList();
		if(!BuildFirstTrain()) {
			HgLog.Warning("newTrain == null "+this);
			saveData.updateRailDepot = updateRailDepot = null;
			return false;
		}
		foreach(engineVehicle,_ in oldVehicles) {
			SellVehicle(engineVehicle);
		}
		//HgTile(updateRailDepot).RemoveDepot();
		saveData.updateRailDepot = updateRailDepot = null;
		

		return true;
	}
	
	function SellVehicle(vehicle) {
		if(!AIVehicle.SellWagonChain(vehicle, 0)) {
			HgLog.Warning("SellWagonChain failed "+AIError.GetLastErrorString()+" "+this);
			return;
		}
		engineVehicles.rawdelete(vehicle);
		CommonRoute.vehicleRemoving.rawdelete(vehicle);
	}
	
	function IsEqualEngine(vehicle1, vehicle2) {
		return AIVehicle.GetEngineType(vehicle1) == AIVehicle.GetEngineType(vehicle2) &&
			AIVehicle.GetWagonEngineType (vehicle1,0) == AIVehicle.GetWagonEngineType(vehicle2,0);
	}

	
	function Close() {
		HgLog.Warning("Close route start:"+this);
		saveData.isClosed = isClosed = true;
		local execMode = AIExecMode();
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
		if(vehicleGroup != null) {
			Route.groupRoute.rawdelete(vehicleGroup);
			AIGroup.DeleteGroup(vehicleGroup);
			vehicleGroup = null;
		}
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
		foreach(tile,depotInfo in depotInfos) {
			RailBuilder.RemoveRailTracksAll(tile);
			foreach(depotTile in depotInfo.depots) {
				AITile.DemolishTile(tile);
			}
		}
		local tiles = [];
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
		//PlaceDictionary.Get().AddRoute(this);
		if(returnRoute != null) {
			returnRoute.ReOpen();
		}
		//BuildFirstTrain();
	}
	
	
	function IsInStationOrDepotOrStop(isTransfer){
		local srcStationId = srcHgStation.GetAIStation() 
		foreach(vehicle, _ in GetVehicleList()) {
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
	
	
	function RemoveReturnRoute() {
		
		if(returnRoute != null) {
			returnRoute.Remove();
			saveData.returnRoute = returnRoute = null;
		}
	}
	
	function IsAllVehiclePowerOnRail(newRailType) {
		foreach(vehicle,_ in GetVehicleList()) {
			local engine = AIVehicle.GetEngineType(vehicle);
			if(!AIEngine.HasPowerOnRail(engine, newRailType) || !AIEngine.CanRunOnRail(engine, newRailType)) {
				return false;
			}
		}
		return true;
	}
	
	function RollbackUpdateRailType(railType) {
		HgLog.Warning("RollbackUpdateRailType "+this);
		saveData.failedUpdateRailType = failedUpdateRailType = true;
		saveData.updateRailDepot = updateRailDepot = null;
		ConvertRailType(railType,true);
		BuildFirstTrain();
	}
	
	function IsCloneTrain() {
		local result = (maxTrains == null || maxTrains > GetNumVehicles())
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
			local waiting = srcHgStation.GetCargoWaiting(cargo);
			if(waiting > capacity / 2) {
				return true;
			}
			if(waiting > capacity / 4 && srcHgStation.GetCargoRating(cargo) < 40) {
				return true;
			}
		}
		return false;
	}

	function IsValidDestStationCargo() {
		if(Route.IsValidDestStationCargo()) {
			return true;
		}
		if(returnRoute != null && returnRoute.IsValidDestStationCargo()) {
			return true;
		}
		return false;
	
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
		CommonRoute.vehicleRemoving.rawset(vehicle,true);
		if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
			if(AIVehicle.GetAge(vehicle) < 365 && AIVehicle.GetCargoLoad(vehicle, cargo) > 0) {
				return;
			}
			AIVehicle.SendVehicleToDepot(vehicle);

//			if(AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT) != 2) {
//				AIVehicle.SendVehicleToDepot (vehicle);
//			}
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
	
	function IsUpdatingRail() {
		return updateRailDepot != null;
	}

	function CalculateUseDepots() {
		if(!HogeAI.Get().IsEnableVehicleBreakdowns()) {
			return;
		}
		if(pathDestToSrc==null) {
			return;
		}
		local latestEngineSet = GetLatestEngineSet();
		if(latestEngineSet==null) {
			return;
		}
		local execMode = AIExecMode();
		local cur = pathDestToSrc.path;
		local lastDepotPath = null;
		local depotDistance = 0;
		local interval = VehicleUtils.GetDistance( latestEngineSet.cruiseSpeed, 70 );
		local isFirst = true;
		for(;;cur = cur.GetParent()) {
			if(cur == null) {
				if(isFirst) {
					cur = pathSrcToDest.path;
					isFirst = false;
				} else {
					break;
				}
			}
			local t = cur.GetTile();
			if(depotInfos.rawin(t)) {
				local depotInfo = depotInfos.rawget(t);
				if(depotInfo.depots.len()<2) continue;
				local d = cur.GetRailDistance(lastDepotPath);
				depotDistance += d;
				local isOpen = true;
				if("isOpen" in depotInfo) {
					isOpen = depotInfo.isOpen;
				} else {
					depotInfo.isOpen <- true;
				}
				if(lastDepotPath==null || depotDistance >= interval) {
					if(!isOpen) HgTile.OpenDoubleDepot(depotInfo);
					depotInfo.isOpen = true;
					depotDistance = 0;
				} else {
					if(isOpen) HgTile.CloseDoubleDepot(depotInfo);
					depotInfo.isOpen = false;
				}
				lastDepotPath = cur;
			}
		}
	}

	function GetRailPoints() {
		local result = {};
		foreach(point,paths in branchLines) {
			local srcToDestPath = paths[0];
			local destToSrcPath = paths[1];
			result.rawset(srcToDestPath.array_.top(),true);
			result.rawset(destToSrcPath.array_[0],true);
		}
		if(returnRoute != null) {
			HgLog.Info("returnRoute points:"+HgTile.GetTilesString(returnRoute.GetOriginalRailPoints()));
			foreach(point in returnRoute.GetOriginalRailPoints()) {
				result.rawset(point,true);
			}
		}
		
		return result;
	}

	function TreatVehiclesWaitingInDepot() {
		foreach(engineVehicle, _ in GetVehicleList()) {
			if(AIVehicle.IsStoppedInDepot(engineVehicle)) {
				OnVehicleWaitingInDepot(engineVehicle);
			}
		}
	}
	
	function OnVehicleWaitingInDepot(engineVehicle) {
		local execMode = AIExecMode();
		if(updateRailDepot != null) {
			SellVehicle(engineVehicle);
		} else if(isClosed || reduceTrains) {
			if(isRemoved || latestEngineVehicle != engineVehicle) { //reopenに備えてlatestEngineVehicleだけ残す
				SellVehicle(engineVehicle);
			}
		} else {
			SellVehicle(engineVehicle);
		}
		if(GetNumVehicles()==0) {
			HgLog.Warning("All vehicles removed."+this);
			if(isRemoved) {
				RemoveFinished();
			}
		}
	}

	function CheckTrains() {
		local execMode = AIExecMode();
		local engineSet = null;

		TreatVehiclesWaitingInDepot();
		foreach(engineVehicle, _ in GetVehicleList()) {
			//HgLog.Info("SendVehicleToDepot(isClosed):"+engineVehicle+" "+ToString());
			if(isClosed || CommonRoute.vehicleRemoving.rawin(engineVehicle)) {
				SendVehicleToDepot(engineVehicle);
			}
		}
		
		if(isClosed || updateRailDepot!=null) {
			return;
		}
		
		local isBiDirectional = IsBiDirectional();
		local needsAddtinalProducing = NeedsAdditionalProducing(null,false);
		if( AIBase.RandRange(100) < 10 && CargoUtils.IsPaxOrMail(cargo)) { // 作った時には転送が無い時がある
			foreach(townCargo in HogeAI.Get().GetPaxMailCargos()) {
				if(!HasCargo(townCargo)) continue;
				if(needsAddtinalProducing) {
					CommonRouteBuilder.CheckTownTransferCargo(this,srcHgStation,townCargo);
				}
				if(isBiDirectional && NeedsAdditionalProducing(null, true)) {
					CommonRouteBuilder.CheckTownTransferCargo(this,destHgStation,townCargo);
				}
			}
		}
		
		
		if(!IsBuilding() && lastChangeDestDate != null && lastChangeDestDate + 120 < AIDate.GetCurrentDate() && !IsChangeDestination()) {
			local removedStations = [];
			local removeTargets = [];
			foreach(i,station in destHgStations) {
				if(station != destHgStation && station != destHgStations[destHgStations.len()-1]) {
					if(HogeAI.Get().ecs && station.place != null && !(station.place instanceof TownCargo)) {
						continue;
					}
					/*
					if(station.place != null && station.place instanceof TownCargo && !CargoUtils.IsPaxOrMail(cargo) && i==destHgStations.len()-2) {
						continue;
					}*/
					if(!station.IsRemoved()) {
						removeTargets.push(station);
					}
				}
			}
			foreach(station in removeTargets) {
				RemoveBranchLine(station);
				ArrayUtils.Remove(destHgStations, station);
				Save();
			}
			if(removeTargets.len() >= 1) {
				CalculateUseDepots();
			}
			saveData.lastChangeDestDate = lastChangeDestDate = null;
		}
		
		if(!HogeAI.HasIncome(20000) && !ExistsMainRouteExceptSelf()) {
			//HgLog.Warning("Cannot renewal train "+this);
			return;
		}

		local vehicles = GetVehicleList();
		
		if(AIBase.RandRange(100) < 10 && HogeAI.Get().IsEnableVehicleBreakdowns() 
				&& (engineSetsDate == null || engineSetsDate + 365 < AIDate.GetCurrentDate())) {
			local lowReliability = false;
			foreach(vehicle, _ in vehicles) {
				if(AIVehicle.GetReliability(vehicle)==0) {
					lowReliability = true;
				}
			}
			if(lowReliability) {
				InvalidateEngineSet();
			}
		}
		foreach(v,_ in vehicles) {
			if(CommonRoute.vehicleRemoving.rawin(v)) {
				SendVehicleToDepot(v);
			}
		}
		
		local engineSetsCacheOld = engineSetsCache;
		engineSet = ChooseEngineSet();
		if(engineSetsCacheOld == engineSetsCache) {
			return;
		}
		
//		HgLog.Warning("ChooseEngineSet "+engineSet+" "+this);
		if(engineSet == null) {
			HgLog.Warning("No usable engineSet ("+AIRail.GetName(GetRailType())+") "+this);
			return;
		}
		if(engineSet.price > HogeAI.Get().GetUsableMoney()) {
			return; // すぐに買えない場合はリニューアルしない。車庫に列車が入って収益性が著しく悪化する場合がある
		}
		local change = false;
		foreach(engineVehicle, v in vehicles) {
			if(!HasVehicleEngineSet(engineVehicle,engineSet) || AIVehicle.GetAgeLeft (engineVehicle) <= 600) {
				SendVehicleToDepot(engineVehicle);
				change = true;
			}
		}
		if(change) {
			BuildNewTrain();
		}
	}

	function CheckCloneTrain() {
		if(isClosed || isRemoved || updateRailDepot!=null || IsSingle()) {
			return;
		}
		local ng = false;
		local srcStationId = srcHgStation.GetAIStation() 
		local srcStationStops = [];
		foreach(vehicle, _ in GetVehicleList()) {
			if(AIStation.GetStationID(AIVehicle.GetLocation(vehicle)) == srcStationId) {
				ng = true;
				if(AIVehicle.GetState(vehicle) == AIVehicle.VS_AT_STATION) {
					srcStationStops.push(vehicle);
				}
			}
			if(AIVehicle.IsInDepot(vehicle) /*|| AIMap.DistanceManhattan(AIVehicle.GetLocation(vehicle),srcHgStation.platformTile) < 12*/) {
				ng = true;
			}
			if(isTransfer && AIVehicle.GetCurrentSpeed(vehicle) == 0) {
				ng = true;
			}
		}
		if((IsBiDirectional() || returnRoute != null) && srcStationStops.len() == srcHgStation.platformNum) {
			SendVehicleToDepot(srcStationStops[0]);
		}
		if(ng) {
			return;
		}
		
		local numVehicles = GetNumVehicles();
		if(IsCloneTrain()) {
			local numClone = 1;
			if(latestEngineSet != null) {
				if(latestEngineSet.vehiclesPerRoute - numVehicles >= 15) {
					numClone = 6;
				} else if(latestEngineSet.vehiclesPerRoute - numVehicles >= 9) {
					numClone = 4;
				//} else if(latestEngineSet.vehiclesPerRoute - numVehicles >= 6) {
				//	numClone = 3;
				} else if(latestEngineSet.vehiclesPerRoute - numVehicles >= 0) {
					numClone = 2;
				}
			}
			local waiting = srcHgStation.GetCargoWaiting(cargo);
			local capacity = GetCargoCapacity(cargo);
			local latestVehicle = GetLatestVehicle();
			numClone = max(1,min( numClone, waiting / capacity ));
			numClone = min(numClone, GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_RAIL));
			for(local i=0; i<numClone; i++) {
				CloneAndStartTrain(false,latestVehicle);
			}
			if(destDepot != null && (returnRoute != null || IsBiDirectional()) 
					&& latestEngineSet != null && latestEngineSet.vehiclesPerRoute - numVehicles >= 0){
				local otherStation = returnRoute != null ? returnRoute.srcHgStation : destHgStation;
				local rating = otherStation.GetCargoRating(cargo);
				local waiting = otherStation.GetCargoWaiting(cargo) - (rating >= 30 ? capacity :0);
				numClone = min(1,waiting / capacity);
				//HgLog.Warning("CheckCloneTrain dest "+numClone+" "+waiting+" "+capacity+" "+this);
				for(local i=0; i<numClone; i++) {
					CloneAndStartTrain(true,latestVehicle);
				}
			}
		}
	}

	function CheckRailUpdate() {
		if(updateRailDepot == null) {
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
			
		} else {
			local list = GetVehicleList();
			if(list.Count() >= 1) {
				list.Valuate(AIVehicle.IsStoppedInDepot);
				list.KeepValue(0);
				list.Valuate(AIOrder.IsGotoDepotOrder,AIOrder.ORDER_CURRENT);
				list.KeepValue(0);
				foreach(v,_ in list) {
					AIVehicle.SendVehicleToDepot(v);
				}
			} else {
				local newEngineSet = ChooseEngineSetAllRailTypes();
				if(newEngineSet==null) {
					HgLog.Warning("newEngineSet==null (ChooseEngineSetAllRailTypes)");
					return;
				}
				CalculateUseDepots();
				local oldRailType = GetRailType();
				local newRailType = newEngineSet.railType;
				if(!DoUpdateRailType(newRailType)) {
					RollbackUpdateRailType(oldRailType);
				}
			}
			return;
		}

/*		if(AIBase.RandRange(100)>=5) { // この先は重いのでたまにやる
			return;
		}*/

		local currentRailType = GetRailType();
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
					ConvertRailType(currentRailType,true);
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
			local cargoCapacities = GetCargoCapacities();
			for(acceptableStationIndex=destHgStations.len()-1; acceptableStationIndex>=0 ;acceptableStationIndex--) {
				if(destHgStations[acceptableStationIndex].IsRemoved()) { // destへの転送路線が削除されると一緒にRemoveされることがある
					continue;
				}
				local accepting = false;
				foreach(cargo,_ in cargoCapacities) {
					if(destHgStations[acceptableStationIndex].stationGroup.IsAcceptingCargo(cargo) && HasCargo(cargo)) {
						accepting = true;
					}
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

	function OnVehicleLost(vehicle) {
		HgLog.Warning("RailRoute OnVehicleLost  "+this);
		// SendVehicleToDepot(vehicle); 全部いなくなる事がある
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

	depotInfos = null;
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
		this.depotInfos = {};
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
		t.depotInfos <- depotInfos;
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
		result.depotInfos = t.depotInfos;
		result.subCargos = t.subCargos;
		return result;
	}

	function AddDepotInfos(depotInfos) {
		foreach(tile,info in depotInfos) {
			depotInfos.rawset(tile,info);
		}
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
	

	function AddDepotInfos(depotInfos) {
		foreach(tile,info in depotInfos) {
			this.depotInfos.rawset(tile,info);
		}
	}
	
	function GetDepots() {
		local result = [];
		foreach(tile,info in depotInfos) {
			result.extend(info.depots);
		}
		return result;
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
	
	function IsSrcTransfer() {
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
	
	function IsDeliveringCargo(cargo) {
		return originalRoute.IsDeliveringCargo(cargo);
	}
	
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
		local latestEngineSet = originalRoute.GetLatestEngineSet();
		if(latestEngineSet == null) {
			return [];
		}
		local result = [];
		foreach(cargo, capacity in latestEngineSet.cargoCapacity) {
			result.push(cargo);
		}
		return result;
	}
	
	function HasCargo(cargo_) {
		if(originalRoute == null) {
			return [];
		}
		local latestEngineSet = originalRoute.GetLatestEngineSet();
		if(latestEngineSet == null) {
			return [];
		}
		return latestEngineSet.cargoCapacity.rawin(cargo_);
	}
	
	function GetUsableCargos() {
		return originalRoute.GetUsableCargos();
	}

	function GetPlatformLength() {
		return originalRoute.GetPlatformLength();
	}

	function IsReturnRoute(isDest) {
		return !isDest;
	}

	function GetFacilities() {
		local result = [srcHgStation, destHgStation, srcArrivalPath.path, srcDeparturePath.path, destArrivalPath.path, destDeparturePath.path];
		result.push( GetDepots() );
		return result;
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

	function GetOriginalRailPoints() {
		// destXXXPathは逆方向？
		return [srcArrivalPath.array_.top(), srcDeparturePath.array_[0], destArrivalPath.array_[0], destDeparturePath.array_.top()];
	}

	function _tostring() {
		return "ReturnRoute:"+destHgStation.GetName() + "<-"+srcHgStation.GetName()+"["+AICargo.GetName(cargo)+"]";
	}
}

class TrainRouteBuilder extends RouteBuilder {
	static function CreateByParams(params) {
		return TrainRouteBuilder(
			Place.Load(params.dest),
			Place.Load(params.src),
			params.cargo,
			params.options);
	}

	constructor(dest, src, cargo, options = {}) {
		RouteBuilder.constructor(dest,src,cargo,options,"TrainRouteBuilder");
	}
	
	function GetRouteClass() {
		return TrainRoute;
	}
	
	function Load() {
		DoBuild();
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
		if(isSingleOrNot==null && options.rawin("estimate")) {
			isSingleOrNot = options.estimate.isSingle;
		}
		local canChangeDest = options.rawin("canChangeDest") ? options.canChangeDest : !isTransfer;
		local sourceRouteId = options.rawin("sourceRoute") ? options.sourceRoute : null;
		local sourceRoute = sourceRouteId != null ? Route.allRoutes[sourceRouteId] : null;
		local forRawPlace = dest instanceof Place && dest.IsRaw();
		
		local idealDistance = canChangeDest ? max(distance,TrainRoute.GetIdealDistance(cargo)) : distance;
		local explain = (isTransfer ? "T:" : "") + dest.GetName()+"<-"+src.GetName()+"["+AICargo.GetName(cargo)+"] distance:"+distance+"("+idealDistance+") "+(canChangeDest?"canChangeDest":"");
		//HgLog.Info("# TrainRoute: Try BuildRoute: "+explain);
		
		local aiExecMode = AIExecMode();
		
		local engineSet = GetBuilt("engineSet");
		local isBiDirectional = !isTransfer && dest.IsAcceptingAndProducing(cargo) && src.IsAcceptingAndProducing(cargo);
		local maxPlatformLength = 0;
		if(dest instanceof StationGroup) {
			foreach(route in dest.GetUsingRoutesAsSource()) {
				if(route.HasCargo(cargo) && route.GetVehicleType() == AIVehicle.VT_RAIL) {
					maxPlatformLength = max(maxPlatformLength, route.GetPlatformLength());
				}
			}
		}
		if(engineSet==null) {
			local subCargos = [];
			local cargoProduction = {};
			cargoProduction[cargo] <- max(50,src.GetFutureExpectedProduction(cargo, AIVehicle.VT_RAIL));
			HgLog.Info("FutureExpectedProduction["+AICargo.GetName(cargo)+"]:"+cargoProduction[cargo]);
			foreach(c in src.GetProducingCargos()) {
				if(c != cargo && dest.IsAcceptingCargo(c)) {
					cargoProduction[c] <- src.GetFutureExpectedProduction(c, AIVehicle.VT_RAIL);
					HgLog.Info("FutureExpectedProduction["+AICargo.GetName(cargo)+"]:"+cargoProduction[c]);
				}
			}
			
			local trainEstimator = TrainEstimator();
			trainEstimator.cargo = cargo;
			trainEstimator.isSingleOrNot = isSingleOrNot; //srcが工場の場合、後から生産量が増加する可能性が高いので複線のみにしておく
			trainEstimator.cargoProduction = cargoProduction;
			trainEstimator.distance = idealDistance;
			trainEstimator.checkRailType = true;
			trainEstimator.isRoRo = !isTransfer;
			trainEstimator.isBidirectional = isBiDirectional;
			trainEstimator.forRawPlace = forRawPlace;
			if(options.rawin("destRoute") && options.destRoute != null) {
				trainEstimator.SetDestRoute( Route.allRoutes[options.destRoute], dest, src );
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
					HgLog.Warning("TrainRoute: tooShortMoney "+explain);
				}
				if(options.rawin("estimate")) {
					engineSet = options.estimate;
				} else {
					HgLog.Info("TrainRoute: Not found enigneSet "+explain);
					return null;
				}
			} else {
				engineSet = engineSets[0];
			}
			SetBuilt("engineSet",engineSet);
		}
		local useSingle = engineSet.isSingle; //HogeAI.Get().GetUsableMoney() < HogeAI.Get().GetInflatedMoney(100000) && !HogeAI.Get().HasIncome(20000);
		if(useSingle) {
			idealDistance = distance;
		}
		local trainLength = (engineSet.length+15)/16;
		HgLog.Info("TrainRoute railType:"+AIRail.GetName(engineSet.railType)+" isSingle:"+useSingle+" trainLength:"+trainLength);
		HgLog.Info("PreEstimation:"+engineSet+" "+explain);
		//HgLog.Info("AIRail.GetMaintenanceCostFactor:"+AIRail.GetMaintenanceCostFactor(engineSet.railType));	
		AIRail.SetCurrentRailType(engineSet.railType);
		
		local useSimpleStation = !(dest instanceof Place);
		local destHgStation = GetBuilt("destHgStation");
		if(destHgStation == null) {
			local destStationFactory = TerminalStationFactory();
			destStationFactory.distance = idealDistance;
			destStationFactory.useSingle = useSingle;
			destStationFactory.useSimple = useSimpleStation;
			local estimatedPlatformLength = trainLength;
			if(canChangeDest && HogeAI.Get().roiBase && HogeAI.Get().GetQuarterlyIncome() > HogeAI.Get().GetInflatedMoney(50000)) {
				estimatedPlatformLength *= 2; //roiBaseの場合、将来延ばす分も考慮
			}
			destStationFactory.estimatedPlatformLength = estimatedPlatformLength;
			if(maxPlatformLength != 0) {
				destStationFactory.estimatedPlatformLength = min(destStationFactory.estimatedPlatformLength, maxPlatformLength);
			}
			if(forRawPlace) {
				destStationFactory.platformLength = 3;
			}
			if(dest instanceof Place) {
				local destPlace = dest;
				if(destPlace.GetProducing().IsTreatCargo(cargo)) { // bidirectional
					destPlace = destPlace.GetProducing();
				}
				destHgStation = destStationFactory.CreateBest(destPlace, cargo, src.GetLocation());
			} else  {
				destHgStation = destStationFactory.CreateBest( dest, cargo, src.GetLocation() );
			}

			if(destHgStation == null) {
				HgLog.Warning("TrainRoute: No destStation."+explain);
				Place.AddNgPlace(dest, cargo, AIVehicle.VT_RAIL);
				return null;
			}
		}
		local srcHgStation = GetBuilt("srcHgStation");
		if(srcHgStation == null) {
			local list = HgArray(destHgStation.GetTiles()).GetAIList();
			HogeAI.notBuildableList.AddList(list);
			
			local srcStationFactory = SrcRailStationFactory();
			srcStationFactory.platformLength = destHgStation.platformLength;
			srcStationFactory.useSimple = useSimpleStation;
			srcStationFactory.useSingle = useSingle;
			if(sourceRoute != null) {
				srcStationFactory.prohibitAcceptCargos.push(cargo);
			}
			srcHgStation = srcStationFactory.CreateBest(src, cargo, dest.GetLocation());
			if(srcHgStation == null) {
				HgLog.Warning("TrainRoute: No srcStation."+explain);
				Place.AddNgPlace(src, cargo, AIVehicle.VT_RAIL);
				return null;
			}
			HogeAI.notBuildableList.RemoveList(list);

			srcHgStation.cargo = cargo;
			srcHgStation.isSourceStation = true;
			if(!srcHgStation.BuildExec()) { 
				HgLog.Warning("TrainRoute: srcHgStation.BuildExec failed. platform:"+srcHgStation.GetPlatformRectangle()+" "+explain);
				Rollback();
				return null;
			}
			AddBuilt("srcHgStation",srcHgStation);
		}
		
		if(GetBuilt("destHgStation") == null) {
			destHgStation.cargo = cargo;
			destHgStation.isSourceStation = false;
			if(!destHgStation.BuildExec()) {
				HgLog.Warning("TrainRoute: destHgStation.BuildExec failed. platform:"+destHgStation.GetPlatformRectangle()+" "+explain);
				Rollback();
				return null;
			}
			AddBuilt("destHgStation",destHgStation);
		}
		
		local pathfinding = Pathfinding();
		local hogeAI = HogeAI.Get();
		if(src instanceof HgIndustry) {
			pathfinding.industries.push(src.industry);
		}
		if(dest instanceof HgIndustry) {
			pathfinding.industries.push(dest.industry);
		}
		hogeAI.pathfindings.rawset(pathfinding,0);
		local railBuilder = GetBuilt("railBuilder");
		if(railBuilder == null) {
			if(useSingle) {
				railBuilder = SingleStationRailBuilder();
			} else {
				railBuilder = TwoWayStationRailBuilder();
			}
		}
		local adjustedPathFindLimit = !hogeAI.HasIncome(10000) && !hogeAI.IsRich() ? hogeAI.pathFindLimit * 3 : hogeAI.pathFindLimit;
		railBuilder.Initialize(srcHgStation, destHgStation, adjustedPathFindLimit, pathfinding);
		railBuilder.pathBuildParams = {
			engine = engineSet.engine
			cargo = cargo
			platformLength = destHgStation.platformLength
			distance = distance
			isBiDirectional = isBiDirectional || !canChangeDest // 下り坂を許さないかどうか
			isTransfer = isTransfer
			isSingle = useSingle
		};
		railBuilder.noRollbackOnLoad = true;
		if(useSingle) {
			railBuilder.isBuildSingleDepotDestToSrc = true;
		} else {
			if(hogeAI.IsEnableVehicleBreakdowns()) {
				if(useSimpleStation) {
					railBuilder.isBuildSingleDepotDestToSrc = true;
				}
				railBuilder.isBuildDoubleDepots = true;
			} else {
				railBuilder.isBuildSingleDepotDestToSrc = true;
				railBuilder.isBuildSingleDepotDestToSrcSideDest = true;
			}
		}
		AddBuilt("railBuilder",railBuilder);
		local isSuccess = railBuilder.Build();
		hogeAI.pathfindings.rawdelete(pathfinding);

		local srcDepot = srcHgStation.GetDepotTile() == null ? railBuilder.srcDepot : srcHgStation.GetDepotTile();
		if(!isSuccess || srcDepot == null) {
			if(srcDepot == null) {
				HgLog.Warning("TrainRoute: srcDepot == null."+explain);
			} else {
				HgLog.Warning("TrainRoute: railBuilder.Build failed."+explain);
			}
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
		route.srcDepot = srcDepot;
		route.isTransfer = isTransfer;
		route.isSrcTransfer = IsSrcTransfer();
		route.isBiDirectional = isBiDirectional;
		route.AddDepotInfos(railBuilder.depotInfos);
		route.Initialize();
		if(!canChangeDest) {
			route.SetCannotChangeDest(true);
		}
		route.CalculateUseDepots();
		
		destHgStation.BuildAfter();
		if(!route.BuildFirstTrain()) {
			HgLog.Warning("TrainRoute: BuildFirstTrain failed."+route);
			route.Demolish();
			return null;
		}
		
		HgLog.Info("TrainRoute pathDistance:"+route.pathDistance+" distance:"+route.GetDistance()+" "+route);

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
Construction.nameClass.TrainRouteBuilder <- TrainRouteBuilder;

class TrainRouteExtendBuilder extends RouteModificatin {

	static function CreateByParams(params) {
		return TrainRouteExtendBuilder(
			Route.allRoutes[params.routeId], 
			Place.Load(params.additionalPlace));
	}

	additionalPlace = null;
	
	constructor(route,additionalPlace) {
		RouteModificatin.constructor(route,{
			typeName = "TrainRouteExtendBuilder"
			additionalPlace = additionalPlace.Save()
		});
		this.additionalPlace = additionalPlace;
	}
	
	function Load() {
		if(DoBuild()!=0) {
			Rollback();
		}
	}
	
	function DoBuild() {
		// 0:成功 1:station作成失敗 2:失敗
		HgLog.Info("# TrainRoute: Try Extend:"+additionalPlace.GetName()+" route: "+route);
		local execMode = AIExecMode();
		AIRail.SetCurrentRailType(route.GetRailType());
		local lastStation = route.GetLastDestHgStation();
		if(additionalPlace.GetProducing().IsTreatCargo(route.cargo)) {
			additionalPlace = additionalPlace.GetProducing();
		}
		local additionalHgStation = GetBuilt("destStation");
		if(additionalHgStation == null) {
			local stationFactory = TerminalStationFactory();
			stationFactory.platformLength = route.srcHgStation.platformLength;
			stationFactory.minPlatformLength = route.GetPlatformLength();
			//if(CargoUtils.IsPaxOrMail(route.cargo)) { 商品など大量に作られるものは終点で溢れる
				stationFactory.platformNum = 3;
			//}
			additionalHgStation = stationFactory.CreateBest(additionalPlace, route.cargo, lastStation.platformTile);
			if(additionalHgStation == null) {
				HgLog.Info("TrainRoute: cannot build additional station");
				return 1;
			}

			additionalHgStation.cargo = route.cargo;
			additionalHgStation.isSourceStation = false;
			if(!additionalHgStation.BuildExec()) {
				return 1;
			}
			AddBuilt("destStation",additionalHgStation);
		}
		
		local railBuilder = GetBuilt("railBuilder");
		if(railBuilder==null) {
			railBuilder = TwoWayPathToStationRailBuilder();
		}
		railBuilder.Initialize(
			GetterFunction( function():(route) {
				return route.GetTakeAllPathSrcToDest();
			}),
			GetterFunction( function():(route) {
				return route.GetTakeAllPathDestToSrc().Reverse();
			}),
			additionalHgStation, HogeAI.Get().pathFindLimit, HogeAI.Get());
		railBuilder.pathBuildParams = {
			engine = route.GetLatestEngineSet().engine
			cargo = route.cargo
			platformLength = route.GetPlatformLength()
			distance = AIMap.DistanceManhattan(additionalPlace.GetLocation(), lastStation.GetLocation())
			isTransfer = route.IsTransfer()
			isBiDirectional = route.IsBiDirectional()
			isSingle = false
		}
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			railBuilder.isBuildDoubleDepots = true;
		} else {
			railBuilder.isBuildSingleDepotDestToSrc = true;
		}
		railBuilder.noRollbackOnLoad = true;
		AddBuilt("railBuilder",railBuilder);
		if(!railBuilder.Build()) {
			HgLog.Warning("TrainRoute: railBuilder.Build failed.");
			Rollback();
			return 2;
		}
		
		if(additionalHgStation.stationGroup == null) {
			HgLog.Warning("TrainRoute: additionalHgStation was removed."); // 稀に建設中に他ルートの削除と重なって駅が削除される事がある
			Rollback();
			return 1;
		}
		
		route.AddDepotInfos(railBuilder.depotInfos);
		if(route.GetLastRoute().returnRoute != null) {
			route.GetLastRoute().RemoveReturnRoute(); // dest追加でreturn routeが成立しなくなる場合があるため。
		}
		
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
		route.AddDestination( additionalHgStation );
		route.AddBranchLine( lastStation, BuildedPath(removePath1, route), BuildedPath(removePath2, route ));
		route.destDepot = additionalHgStation.GetDepot();
		route.Save();

		lastStation.RemoveDepots();
		
		HgLog.Info("# TrainRoute: Extend succeeded: "+route);
		return 0;
	}
	
}
Construction.nameClass.TrainRouteExtendBuilder <- TrainRouteExtendBuilder;

class TrainReturnRouteBuilder extends RouteModificatin {

	srcPlace = null;
	destPlace = null;
	
	constructor(route,srcPlace,destPlace) {
		RouteModificatin.constructor(route);
		this.srcPlace = srcPlace;
		this.destPlace = destPlace;
	}
	
	function DoBuild() {
		//TODO 後半は駅作成失敗が多くなるので、先に駅が建てられるかを調べる。ルート検索はコストが重いので最後に
		HgLog.Info("# TrainRoute: Try BuildReturnRoute:"+destPlace.GetName()+"<-"+srcPlace.GetName()+" route: "+route);

		// TODO return destは取っておいて後で再利用

		local returnDestStation;
		local railBuilderReturnDest;
		{
			local returnDestStationFactory = TerminalStationFactory();
			returnDestStationFactory.platformLength = route.GetPlatformLength();
			returnDestStationFactory.minPlatformLength = route.GetPlatformLength();
			
			returnDestStation = returnDestStationFactory.CreateBest(destPlace, route.cargo, srcPlace.GetLocation(), false);
				// station groupを使うと同一路線の他のreturnと競合して列車が迷子になる事がある
			if(returnDestStation == null) {
				Place.AddNgPlace(destPlace,route.cargo,AIVehicle.VT_RAIL);
				HgLog.Warning("TrainRoute:cannot build returnDestStation");
				Rollback();
				return null;
			}
				
			local aiExecMode = AIExecMode();
			returnDestStation.cargo = route.cargo;
			returnDestStation.isSourceStation = false;
			if(!returnDestStation.BuildExec()) {
				Place.AddNgPlace(destPlace,route.cargo,AIVehicle.VT_RAIL);
				HgLog.Warning("TrainRoute: cannot build returnDestStation");
				Rollback(); // TODO: 稀にtransfer station側に列車が紛れ込んでいてrouteが死ぬ時がある。(正規ルート側にdouble depotがあるケース？）
				return null;
			}
			AddRollback(returnDestStation);
			
			
			//local pointTile = railBuilderTransferToPath.buildedPath.path.GetFirstTile();
			railBuilderReturnDest = TwoWayPathToStationRailBuilder();
			railBuilderReturnDest.pathDepatureGetter = GetterFunction( function():(route) {
					//return route.GetPathAllDestToSrc().SubPathEnd(railBuilderTransferToPath.buildedPath.path.GetFirstTile()).Reverse();
					return route.GetPathAllDestToSrc().Reverse();
				});
			railBuilderReturnDest.pathArrivalGetter = GetterFunction( function():(route, railBuilderReturnDest) {
					local pathForReturnDest = route.GetPathAllDestToSrc(); //route.GetPathAllDestToSrc().SubPathEnd(pointTile);
					return pathForReturnDest.SubPathStart(railBuilderReturnDest.buildedPath1.path.GetFirstTile()); // TODO: railBuilderReturnDestDepartureと分岐点がクロスする事がある
				});
			railBuilderReturnDest.isReverse = true;
			railBuilderReturnDest.isRevReverse = true;
			railBuilderReturnDest.destHgStation = returnDestStation;
			railBuilderReturnDest.limitCount = 150;
			railBuilderReturnDest.eventPoller = HogeAI.Get();
			railBuilderReturnDest.pathBuildParams = {
				engine = route.GetLatestEngineSet().engine
				cargo = route.cargo
				platformLength = route.GetPlatformLength()
				distance = AIMap.DistanceManhattan(returnDestStation.GetLocation(), route.srcHgStation.GetLocation())
			};
			if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
				railBuilderReturnDest.isBuildDoubleDepots = true;
			}
			if(!railBuilderReturnDest.Build()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderReturnDestDeparture");
				Rollback();
				return null;
			}
			AddRollback(railBuilderReturnDest);
		}		
		
		
		local testMode = AITestMode();
		local railStationCoverage = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local returnPath = route.GetPathAllDestToSrc();
		local transferStation = HogeAI.Get().GetBuildableStationByPath(
			returnPath, 
			10,
			srcPlace.GetLocation(),
			destPlace.GetLocation(),
			route.cargo, route.GetPlatformLength());
		if(transferStation == null) {
			HgLog.Warning("TrainRoute: cannot build transfer station");
			Rollback();
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
				Rollback();
				return null;
			}
			AddRollback(transferStation);
			
			// TODO: return dest より dest側に作ってしまうケース
			
			railBuilderTransferToPath = RailPathBuilder().PathToStation(GetterFunction( function():(route) {
				local returnPath = route.GetPathAllDestToSrc().GetParentLen(16);
				return returnPath.Reverse().GetParentLen(16);//.SubPathEnd(returnPath.GetLastTileAt(4)).Reverse();
			}), transferStation, 80, HogeAI.Get(), null, false);
			railBuilderTransferToPath.pathBuildParams = {
				engine = route.GetLatestEngineSet().engine
				cargo = route.cargo
				platformLength = route.GetPlatformLength()
				isOneway = true
			}
			railBuilderTransferToPath.isReverse = true;
			//railBuilderTransferToPath.orgTile = destPlace.GetLocation();
			if(!railBuilderTransferToPath.Build()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderTransferToPath");
				Rollback();
				return null;
			}
			
			AddRollback(railBuilderTransferToPath.buildedPath); // TODO Rollback時に元の線路も一緒に消える事がある。limit date:300の時に消えている
			/*
			local p = railBuilderTransferToPath.buildedPath.path;
			local stationTile = transferStation.GetDeparturesTiles()[0][0];
			local preDist = IntegerUtils.IntMax;
			local pointTile = p.GetTile();
			while(p!=null) {
				local dist = AIMap.DistanceManhattan(p.GetTile(), destPlace.GetLocation()) + AIMap.DistanceManhattan(p.GetTile(), stationTile);
				if(dist >= preDist) {
					break;
				}
				pointTile = p.GetTile();
				preDist = dist;
				p = p.GetPareint();
			}*/;
			local pointTile = railBuilderTransferToPath.buildedPath.path.GetTile();
			railBuilderPathToTransfer = RailPathBuilder().PathToStation(GetterFunction( function():(route, pointTile) {
				return route.GetPathAllDestToSrc().SubPathStart(pointTile);
			}), transferStation, 80, HogeAI.Get());
			railBuilderPathToTransfer.pathBuildParams = {
				engine = route.GetLatestEngineSet().engine
				cargo = route.cargo
				platformLength = route.GetPlatformLength()
				isOneway = true
			}
			//railBuilderPathToTransfer.orgTile = route.destHgStation.GetLocation();
			
			if(!railBuilderPathToTransfer.Build()) {
				HgLog.Warning("TrainRoute: cannot build railBuilderPathToTransfer");
				Rollback();
				return null;
			}
			
			AddRollback(railBuilderPathToTransfer.buildedPath);
			
		}
			
		{
			local returnRoute = TrainReturnRoute(route, transferStation, returnDestStation, 
				railBuilderPathToTransfer.buildedPath, railBuilderTransferToPath.buildedPath,
				railBuilderReturnDest.buildedPath1, railBuilderReturnDest.buildedPath2);
				
			returnRoute.AddDepotInfos( railBuilderReturnDest.depotInfos );
		
			route.returnRoute = returnRoute;
			route.destDepot = transferStation.GetArrivalDepot();
			route.Save();
			returnRoute.Initialize();
			
			ClearRollback();
			PlaceDictionary.Get().AddRoute(returnRoute);
			

			route.slopesTable.clear(); // TODO: ChangeDestinationと同様、登れるのかの再確認が必要
			route.AddReturnTransferOrder(route.GetOrderVehicle(), transferStation, returnDestStation);
			

			HgLog.Info("# TrainRoute: build return route succeeded:"+returnRoute);
			return returnRoute;
		}
		
	}

}

class MainLineRefactor extends RouteModificatin {
	static function CreateByParams(params) {
		return MainLineRefactor(
			Route.allRoutes[params.routeId], 
			params.pointSrcToDest, 
			params.pointDestToSrc );
	}

	pointSrcToDest = null;
	pointDestToSrc = null;
	
	constructor(route, pointSrcToDest, pointDestToSrc) {
		RouteModificatin.constructor(route, {
			typeName = "MainLineRefactor"
			pointSrcToDest = pointSrcToDest
			pointDestToSrc = pointDestToSrc
		});
		this.pointSrcToDest = pointSrcToDest;
		this.pointDestToSrc = pointDestToSrc;
	}
	
	function Load() {
		Rollback();
		DoBuild();
	}

	function DoBuild() {
		local execMode = AIExecMode();
		local oldRailType = AIRail.GetCurrentRailType();
		AIRail.SetCurrentRailType(route.GetRailType());
		local result = RefactorMainLine();
		if(!result) {
			Rollback();
		}
		AIRail.SetCurrentRailType(oldRailType);
		route.Save();
		return result;
	}
	
	function GetSegment(mainLine, point, railPoints) {
		local size = mainLine.len();
		local include = false;
		local result = [];
		local start = 0;
		for(local i=0; i<size; i++) {
			if(mainLine[i] == point) {
				include = true;
				result.push(mainLine[i]);
			} else if(railPoints.rawin(mainLine[i])) {
				if(include) {
					return [result,start,i];
				}
				result.clear();
				start = i+1;
			} else {
				result.push(mainLine[i]);
			}
		}
		if(include) {
			return [result,start,size];
		} else {
			return null;
		}
	}

	function RefactorMainLine() {
	
		HgLog.Info("RefactorMainLine:"+HgTile(pointSrcToDest)+" "+HgTile(pointDestToSrc)+" "+route);
	
		local railPoints = route.GetRailPoints();
		local allLines = [route.pathSrcToDest.array_, route.pathDestToSrc.array_];
		local points = [pointSrcToDest, pointDestToSrc];
		local mainPointIdxs = [null,null];
		local segments = [null,null]
		local mainLines = [null,null];
		for(local i=0; i<2; i++) {
			segments[i] = GetSegment(allLines[i], points[i], railPoints)
			if(segments[i]==null) {
				HgLog.Warning("Not found branch point: "+i+" "+HgTile(points[i])+" (RefactorMainLine)"+route);
				return false;
			}
			mainLines[i] = segments[i][0];
		}
		foreach(i, point in points) {
			HgLog.Info("RefactorMainLine: "+HgTile(point));
			mainPointIdxs[i] = ArrayUtils.Find(mainLines[i], point);
		}
		local departures = [null,null];
		local arrivals = [null,null];
		local removeIdxs = [null,null];
		local removedTilesArray = [];
		local gapLength = 5;
		local removeLength = HogeAI.Get().IsEnableVehicleBreakdowns() ? 10 : 20; // double depotを壊さないように
		foreach(i,idx in mainPointIdxs) {
			if(idx == null) {
				HgLog.Warning("Not found branch point: "+HgTile(points[i])+" (RefactorMainLine)"+route);
				return false;
			}
			if(idx<gapLength/*+removeLength*/) {
				HgLog.Warning("idx is too small:"+idx+" (RefactorMainLine)"+route);
				return false;
			}
			// 進行方向逆方向
			local removeIdx1 = null;
			local removeIdx2 = null;
			if(i==0) {
				removeIdx1 = max(gapLength,idx-removeLength);
				removeIdx2 = min(idx+removeLength,mainLines[0].len()-gapLength);
				local revs = {};
				foreach(t in mainLines[1]) {
					revs.rawset(t,t);
				}
				for(local idx1 = removeIdx1; idx1 > gapLength; idx1-=10) {
					local t1 = mainLines[0][idx1], t2 = mainLines[0][idx1-1];
					if(revs.rawin(t1+HgTile.GetRevDir(t1,t2))) {
						removeIdx1 = idx1;
						break;
					}
				}
				for(local idx2 = removeIdx2; idx2 < mainLines[0].len()-gapLength; idx2+=10) {
					local t1 = mainLines[0][idx2], t2 = mainLines[0][idx2+1];
					if(revs.rawin(t1+HgTile.GetRevDir(t2,t1))) {
						removeIdx2 = idx2;
						break;
					}
				}
			} else if(i==1) {
				local t1 = mainLines[0][removeIdxs[0][0]-1];
				local t2 = mainLines[0][removeIdxs[0][1]-1];
				local list1 = AIList();
				local list2 = AIList();
				foreach(idx,t in mainLines[1]) {
					list1.AddItem(idx,AIMap.DistanceManhattan(t1,t));
					list2.AddItem(idx,AIMap.DistanceManhattan(t2,t));
				}
				list1.Sort(AIList.SORT_BY_VALUE,true);
				list2.Sort(AIList.SORT_BY_VALUE,true);
				removeIdx2 = list1.Begin() + 1;
				removeIdx1 = list2.Begin() - 1;
			}
			//HgLog.Info("removedTiles:"+HgTile.GetTilesString(removedTiles));
			removeIdx1 = max(gapLength, removeIdx1);
			removeIdx2 = min(mainLines[i].len() - gapLength, removeIdx2);
			arrivals[i] = mainLines[i].slice(removeIdx1-gapLength, removeIdx1+2);
			departures[i] = mainLines[i].slice(removeIdx2-2, removeIdx2+gapLength);
			while(removeIdx1-gapLength-1 >= max(0,idx-100)) {
				local a = arrivals[i];
				local t1 = a[a.len()-1], t2 = a[a.len()-2];
				if(i==1 && t1 == departures[0][0]) {
				} else if(AIMap.DistanceManhattan(t1,t2)!=1) {
				} else if(RailPathFinder._IsSlopedRail(t2,t1,t1+(t1-t2))) {
				} else {
					break;
				}
				removeIdx1--;
				arrivals[i] = mainLines[i].slice(removeIdx1-gapLength, removeIdx1+2);
			}
			while(removeIdx2+gapLength+1 < min(mainLines[i].len(),idx+100) ) {
				local t1 = departures[i][0], t2 = departures[i][1];
				if(i==1 && t1 == arrivals[0].top()) {
				} else if(AIMap.DistanceManhattan(t1,t2)!=1) {
				} else if(RailPathFinder._IsSlopedRail(t2,t1,t1+(t1-t2))) {
				} else {
					break;
				}
				removeIdx2++;
				departures[i] = mainLines[i].slice(removeIdx2-2, removeIdx2+gapLength);
			}
			removeIdxs[i] = [removeIdx1,removeIdx2];
			HgLog.Info("arrivals:"+HgTile.GetTilesString(arrivals[i]));
			HgLog.Info("departures:"+HgTile.GetTilesString(departures[i]));
			if(removeIdx1<0 || removeIdx1>removeIdx2 || removeIdx1 >= mainLines[i].len() || removeIdx2 >= mainLines[i].len()) {
				HgLog.Warning("mainLines[i].len():"+mainLines[i].len()+" removeIdx1:"+removeIdx1+" removeIdx2:"+removeIdx2);
				return false;
			}
			local removedTiles = mainLines[i].slice(removeIdx1,removeIdx2);
			removedTilesArray.push(removedTiles);
		}
		foreach(tiles in removedTilesArray) {
			local railRemover = RailRemover(ArrayUtils.Reverse(tiles),route.id,true,true);
			route.TreatVehiclesWaitingInDepot();
			if(!railRemover.Build()) {
				HgLog.Warning("RailRemover failed.(RefactorMainLine)"+route);
				return false;
			}
			AddRollback(railRemover);
			//Path.Load(tiles).Reverse().RemoveRails(route);
		}
		local railBuilder = TwoWayPtoPRailBuilder(departures[0], arrivals[0], departures[1], arrivals[1], HogeAI.Get().pathFindLimit, HogeAI.Get());
		railBuilder.pathBuildParams = {
			engine = route.GetLatestEngineSet().engine
			cargo = route.cargo
			platformLength = route.GetPlatformLength()
			distance = abs(removeIdxs[0][0] - removeIdxs[0][1])
			isSingle = route.IsSingle()
			isBiDirectional = route.IsBiDirectional()
			isTransfer = route.IsTransfer()
		};
		//railBuilder.notFlatten = true; // 列車進入中だとflattenは失敗する
		if(!railBuilder.Build()) {
			HgLog.Warning("railBuilder.Build failed.(RefactorMainLine)"+route);
			return false; //TODO:ロールバック失敗でルート削除
		}
		local buildedPaths = [railBuilder.buildedPath1, railBuilder.buildedPath2];
		foreach(i,idx in mainPointIdxs) {
			local s = mainLines[i].slice(0, removeIdxs[i][0]);
			local m = buildedPaths[i].path.GetTiles();
			local e = mainLines[i].slice(removeIdxs[i][1], mainLines[i].len());

/*			HgLog.Warning("s:"+HgTile(s[0])+" "+HgTile(s[s.len()-1]));
			HgLog.Warning("m:"+HgTile(m[0])+" "+HgTile(m[m.len()-1]));
			HgLog.Warning("e:"+HgTile(e[0])+" "+HgTile(e[e.len()-1]));*/
			
			local newPath = [];
			newPath.extend(allLines[i].slice(0, segments[i][1]));
			newPath.extend(s);
			//if(newPath.top()==m[0]) newPath.pop();
			newPath.extend(m);
			//if(newPath.top()==e[0]) newPath.pop();
			newPath.extend(e);
			newPath.extend(allLines[i].slice(segments[i][2], allLines[i].len()));
			
			local ex = {};
			foreach(t in newPath) {
				if(ex.rawin(t)) {
					HgLog.Warning("double tile:"+HgTile(t)+" "+route);
					HgLog.Warning("s:"+HgTile(s[0])+" "+HgTile(s[s.len()-1]));
					HgLog.Warning("m:"+HgTile(m[0])+" "+HgTile(m[m.len()-1]));
					HgLog.Warning("e:"+HgTile(e[0])+" "+HgTile(e[e.len()-1]));
				}
				ex.rawset(t,t);
			}
			
			if(i==0) {
				route.pathSrcToDest = BuildedPath(Path.Load(newPath));
			} else {
				route.pathDestToSrc = BuildedPath(Path.Load(newPath));
			}
		}
		return true;
	}
}
Construction.nameClass.MainLineRefactor <- MainLineRefactor;
