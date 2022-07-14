
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
		/*
		if(engineName != null && engineName.find("Hankyu") != null) {
			return null;
		}*/
		
		if(dictionary.rawin(engine)) {
			return dictionary[engine];
		}
		
		if(HogeAI.Get().maxTrains <= AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_RAIL)) {
			return null;
		}
		local depot = GetDepot(engine);
		if(depot == null) {
			return null;
		}
		local trainInfo = CreateTrainInfo(depot, engine);
		if(trainInfo == null) {
			return null;
		}
		dictionary[engine] <- trainInfo;
		return trainInfo;
	}
	
	function GetDepot(engine) {
		local railType = null;//AIEngine.GetRailType(engine);
		if(railType == null) {
			foreach(r,v in AIRailTypeList()) {
				if(AIEngine.IsWagon(engine)) {
					if(AIEngine.CanRunOnRail(engine, r)) {
						railType = r;
						break;
					}
				} else {
					if(AIEngine.HasPowerOnRail(engine, r)) {
						railType = r;
						break;
					}
				}
			}
		}
		if(railType == null) {
			HgLog.Warning("Unknown railType engine:"+AIEngine.GetName(engine)+"(GetDepot)");
			return null;
		}
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
		return railTypeDepot[railType];
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
	/*
	function GetConnectedWagonInfo(trainEngine, wagonEngine) {
		
	}
	
	
	function CreateConnectedWagonInfo(depot, trainEngine, wagonEngine, cargo) {
		local exec = AIExecMode();
		if(AIEngine.GetPrice(trainEngine) + AIEngine.GetPrice(wagonEngine) > HogeAI.GetUsableMoney()) {
			//HgLog.Warning("Not enough money (TrainInfoDictionary.CreateTrainInfo) "+AIEngine.GetName(engine));
			return null;
		}
		//HgLog.Info("BuildVehicle "+AIEngine.GetName(engine));
		HogeAI.WaitForPrice(AIEngine.GetPrice(trainEngine));
		local vehicle = AIVehicle.BuildVehicle(depot, trainEngine);
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("BuildVehicle failed train(CreateConnectedWagonInfo) "+AIEngine.GetName(trainEngine)+" "+AIError.GetLastErrorString()+" depot:"+HgTile(depot));
			return null;
		}
		
		
		HogeAI.WaitForPrice(AIEngine.GetPrice(engine));
		local wagon = AIVehicle.BuildVehicle(depot, wagonEngine);
		if(!AIVehicle.IsValidVehicle(firstWagon)) {
			HgLog.Warning("BuildVehicle failed wagon(CreateConnectedWagonInfo) "+AIEngine.GetName(wagonEngine)+" "+AIError.GetLastErrorString()+" depot:"+HgTile(depot));
			AIVehicle.SellWagonChain(vehicle, 0);
			return null;
		}
		
		if (AIEngine.GetCargoType(wagonEngine) != cargo) {
			if(!AIVehicle.RefitVehicle(wagon, cargo)) {
				HgLog.Warning("RefitVehicle failed wagon(CreateConnectedWagonInfo) "+AIEngine.GetName(wagonEngine)+" "+AIError.GetLastErrorString()+" depot:"+HgTile(depot));
				AIVehicle.SellWagonChain(vehicle, 0);
				AIVehicle.SellWagonChain(wagon, 0);
				return null;
			}
		}

		if(!AIVehicle.MoveWagonChain(wagon, 0, vehicle, 0)) {
			AIVehicle.SellWagonChain(vehicle,0);
			AIVehicle.SellWagonChain(wagon,0);
			return {
				connectable = false
			}
		}
		
		local connectedWagonEngine = AIVehicle.GetEngineType(wagon);
		
		local result = {
			connectable = true
			cargoCapacity = AIVehicle.GetCapacity (wagon, cargo)
		};
		
		AIVehicle.SellWagonChain(vehicle,0);
		AIVehicle.SellWagonChain(wagon,0);
		
		return result;
	}*/
	
	function CreateTrainInfo(depot, engine) {
		local exec = AIExecMode();
		local price = AIEngine.GetPrice(engine);
		if(price > HogeAI.GetUsableMoney()) {
			HgLog.Warning("Not enough money (TrainInfoDictionary.CreateTrainInfo) "+AIEngine.GetName(engine)+" price:"+price);
			return null;
		}
		HgLog.Info("BuildVehicle "+AIEngine.GetName(engine)+" usableMoney:"+HogeAI.GetUsableMoney());
		HogeAI.WaitForPrice(price,0);
		local vehicle = AIVehicle.BuildVehicle(depot, engine);
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("BuildVehicle failed (TrainInfoDictionary.CreateTrainInfo) "+AIEngine.GetName(engine)+" "+AIError.GetLastErrorString()+" depot:"+HgTile(depot));
			return null;
		}
		local cargoCapacity = {};
		foreach(cargo, v in AICargoList()) {
			if(AIEngine.CanRefitCargo (engine, cargo)) {
				local capacity = AIVehicle.GetRefitCapacity (vehicle, cargo);
				/*
				if(price > HogeAI.Get().GetInflatedMoney(1000)) {
					capacity = AIVehicle.GetRefitCapacity (vehicle, cargo);
				} else {
					if(AIVehicle.RefitVehicle (vehicle, cargo)) {
						capacity = AIVehicle.GetCapacity (vehicle, cargo);
					}
				}*/
				if(capacity >= 1) {
					cargoCapacity[cargo] <- capacity;
				}
			}
		}
		local length = AIVehicle.GetLength (vehicle);
		AIVehicle.SellVehicle(vehicle);
		return {
			length = length
			cargoCapacity = cargoCapacity
		}
	}
	
}

class TrainPlanner {

	cargo = null;
	productions = null;
	distance = null;
	isBidirectional = null;
	
	// optional
	railType = null;
	checkRailType = null;
	platformLength = null;
	selfGetMaxSlopesFunc = null;
	maxSlopes = null;
	limitTrainEngines = null;
	limitWagonEngines = null;
	skipWagonNum = null;
	additonalTrainEngine = null;
	additonalWagonEngine = null;
	subCargos = null;
	
	constructor() {
		platformLength = 7; //AIGameSettings.GetValue("vehicle.max_train_length");
		isBidirectional = false;
		skipWagonNum = 1;
		checkRailType = false;
		if(!HogeAI.Get().roiBase) {
			limitWagonEngines = 2;
			limitTrainEngines = 5;
		} else {
			limitWagonEngines = 3;
			limitTrainEngines = 10;
		}
		subCargos = [];
	}

	function GetEngineSetsOrder() {
		local engineSets = GetEngineSets();
		if(HogeAI.Get().roiBase) {
			engineSets.sort(function(a,b) {
				return b.roi - a.roi;
			});
		} else {
			engineSets.sort(function(a,b) {
				return b.routeIncome - a.routeIncome;
			});
		}
		return engineSets;
	}
	
	function GetSuitableSubWagonEngine(subCargo, railType, trainEngine, maxSpeed) {
		local wagonEngines = AIEngineList(AIVehicle.VT_RAIL);
		wagonEngines.Valuate(AIEngine.IsWagon);
		wagonEngines.KeepValue(1);
		wagonEngines.Valuate(AIEngine.CanRefitCargo, subCargo);
		wagonEngines.KeepValue(1);
		wagonEngines.Valuate(AIEngine.CanRunOnRail, railType);
		wagonEngines.KeepValue(1);
		if(wagonEngines.Count() == 0) {
			HgLog.Warning("No refitable or runnable wagon.");
			return null;
		}
		wagonEngines.Valuate(function(e):(trainEngine) {
			return !TrainRoute.IsUnsuitableEngineWagon(trainEngine, e)
		});
		wagonEngines.KeepValue(1);
		if(wagonEngines.Count() == 0) {
			HgLog.Warning("No suitable wagon.");
			return null;
		}
		foreach(e,_ in wagonEngines) {
			wagonEngines.SetValue(e, TrainInfoDictionary.Get().GetTrainInfo(e) != null ? 1 : 0);
		}
		wagonEngines.KeepValue(1);
		if(wagonEngines.Count() == 0) {
			HgLog.Warning("No having TrainInfo wagon.");
			return null;
		}
		wagonEngines.Valuate(AIEngine.GetMaxSpeed);
		foreach(engine, speed in wagonEngines) {
			if(speed == 0 || speed > maxSpeed) {
				wagonEngines.SetValue(engine, maxSpeed);
			}
		}
		wagonEngines.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		wagonEngines.KeepValue(wagonEngines.GetValue(wagonEngines.Begin()));
		if(wagonEngines.Count() == 0) {
			HgLog.Warning("Cannot get max speed wagon");
			return null;
		}
		wagonEngines.Valuate(function(e):(subCargo) {
			local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(e);
			return wagonInfo.cargoCapacity.rawin(subCargo) ? wagonInfo.cargoCapacity[subCargo] : 0; 
		});
		wagonEngines.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		return wagonEngines.Begin();
	}
	
	function GetTotalProduction() {
		local result = 0;
		foreach(production in productions) {
			result += production;
		}
		return result;
	}

	function CalculateSubCargoNumWagons(wagonEngineInfos, totalNumWagon) {
		local result = [];
		local totalProduction = GetTotalProduction();
		local sum = 0;
		local totalCapacity = 0;
		local count = 0;
		foreach(wagonEngineInfo in wagonEngineInfos) {
			if(wagonEngineInfo.rawin("engine")) {
				totalCapacity += wagonEngineInfo.capacity;
				count ++;
			}
		}
		local averageCapacity = totalCapacity.tofloat() / count;
		
		result.push(clone wagonEngineInfos[0]);
		foreach(index, cargo in subCargos) {
			local numWagon = 0;
			if(wagonEngineInfos[index+1].rawin("engine")) {
				local capacityRate = wagonEngineInfos[index+1].capacity / averageCapacity;
				numWagon = (totalNumWagon.tofloat() * productions[index+1] / totalProduction / capacityRate).tointeger();
				if(productions[index+1] !=0 && totalNumWagon >= subCargos.len() + 1) {
					numWagon = max(1,numWagon);
				}
				if(numWagon >= 1) {
					local wagonEngineInfo = clone wagonEngineInfos[index+1];
					wagonEngineInfo.numWagon <- numWagon;
					result.push(wagonEngineInfo);
				}
			}
			sum += numWagon;
		}
		result[0].numWagon <- totalNumWagon - sum;
		return result;
	}

	function GetWagonEngineInfo(cargo, engine) {
		local result = {};
		local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(engine);	
		if(wagonInfo == null) {
			HgLog.Warning("wagonInfo==null:"+AIEngine.GetName(engine));
			return null;
		}
		result.engine <- engine;
		result.cargo <- cargo;
		result.runningCost <- AIEngine.GetRunningCost(engine);
		result.price <- AIEngine.GetPrice(engine);
		local wagonCapacity = wagonInfo.cargoCapacity.rawin(cargo) ? wagonInfo.cargoCapacity[cargo] : 0; 
		if(wagonCapacity == 0) {
			HgLog.Warning("wagonCapacity == 0:"+AIEngine.GetName(engine));
			return null;
		}
		if(wagonInfo.length == 0) {
			HgLog.Warning("wagonInfo.length == 0:"+AIEngine.GetName(engine));
			return null;
		}
		result.capacity <- wagonCapacity;
		local weight  = AIEngine.GetWeight(engine);
		result.lengthWeight <- [wagonInfo.length, weight + GetCargoWeight(cargo, wagonCapacity)];
		result.isFollowerForceWagon <- weight == 0 && !AIEngine.GetName(engine).find("Unpowered"); // 多分従動力車　TODO 実際に連結させて調べたい
		return result;
	}
	
	function GetEngineSets() {
		local result = [];
		local useReliability = HogeAI.Get().IsEnableVehicleBreakdowns();
		
		/*
		if(CargoUtils.IsPaxOrMail(cargo) && isBidirectional && RoadRoute.GetMaxTotalVehicles() <= AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_ROAD)) {
			production /= 4; // フィーダーのサポートが無いと著しく収益性が落ちる placeでやる
		}*/

	
		local railSpeed = 10000;
		if(railType != null) {
			railSpeed = AIRail.GetMaxSpeed(railType);
			if(railSpeed <= 0) {
				railSpeed = 10000;
			}
		}
		local quaterlyIncome = HogeAI.Get().GetQuarterlyIncome();
		local maxBuildingCost = !checkRailType ? 0 : HogeAI.Get().GetUsableMoney() + quaterlyIncome * 8;
		
		local wagonEngines = AIEngineList(AIVehicle.VT_RAIL);
		wagonEngines.Valuate(AIEngine.IsWagon);
		wagonEngines.KeepValue(1);
		wagonEngines.Valuate(AIEngine.CanRefitCargo, cargo);
		wagonEngines.KeepValue(1);
		if(railType != null) {
			wagonEngines.Valuate(AIEngine.CanRunOnRail, railType);
			wagonEngines.KeepValue(1);
		}
		if(checkRailType || limitWagonEngines != null) {
			if(checkRailType || limitWagonEngines == 1) {
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
			if(additonalWagonEngine != null && (railType == null || AIEngine.CanRunOnRail(additonalWagonEngine, railType))) {
				wagonEngines.RemoveItem(additonalWagonEngine);
				wagonEngines.AddItem(additonalWagonEngine, 4294967295);
				//HgLog.Info("additonalWagonEngine:"+AIEngine.GetName(additonalWagonEngine));
			}
			wagonEngines.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		}
		local countWagonEngines = 0;
		foreach(wagonEngine,v in wagonEngines) {
			if(!AIEngine.IsValidEngine(wagonEngine) || !AIEngine.IsBuildable(wagonEngine)) {
				continue;
			}
			local wagonEngineInfo = GetWagonEngineInfo(cargo, wagonEngine);
			if(wagonEngineInfo == null) {
				continue;
			}
			wagonEngineInfo.production <- productions[0];
			countWagonEngines ++;
			if(limitWagonEngines != null && countWagonEngines > limitWagonEngines) {
				break;
			}
			
			local wagonSpeed = AIEngine.GetMaxSpeed(wagonEngine);
			if(wagonSpeed <= 0) {
				wagonSpeed = 10000;
			}
			wagonSpeed = min(railSpeed, wagonSpeed);
			
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
			if(checkRailType || limitTrainEngines != null) {
				if(checkRailType || limitTrainEngines == 1) {
					local money = max(200000,AICompany.GetBankBalance(AICompany.COMPANY_SELF));
					trainEngines.Valuate(function(e):(wagonSpeed, money, cargo, useReliability) {
						local reliability = useReliability ? AIEngine.GetReliability(e) : 100;
						return (min(AIEngine.GetMaxSpeed(e) ,wagonSpeed) * (100+reliability)/200
							* min(min(5000, AIEngine.GetMaxTractiveEffort(e)*10),AIEngine.GetPower(e)) //min(TrainPlanner.GetCargoWeight(cargo,300),AIEngine.GetMaxTractiveEffort(e))
							* ((money - (AIEngine.GetPrice(e)+AIEngine.GetRunningCost(e)*5)).tofloat() / money)).tointeger();
					});
				} else {
					trainEngines.Valuate(AIBase.RandItem);
				}
				if(additonalTrainEngine != null && (railType == null || AIEngine.HasPowerOnRail(additonalTrainEngine, railType))) {
					trainEngines.RemoveItem(additonalTrainEngine);
					trainEngines.AddItem(additonalTrainEngine, 4294967295);
					//HgLog.Info("additonalTrainEngine:"+AIEngine.GetName(additonalTrainEngine));
				}
				trainEngines.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
			}
			local countTrainEngines=0;
			foreach(trainEngine,v in trainEngines) {
				if(!AIEngine.IsValidEngine(trainEngine) || !AIEngine.IsBuildable(trainEngine)) {
					continue;
				}
				local trainRailType;
				if(railType == null) {
					trainRailType = GetSuitestRailType(trainEngine, checkRailType);
					if(trainRailType==null) {
						continue;
					}
					
				} else {
					trainRailType = railType;
				}
				if(!AIEngine.CanRunOnRail(wagonEngine, trainRailType)) {
					continue;
				}
				local buildingCost = TrainRoute.GetBuildingCost(trainRailType, distance, cargo);
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
				local trainReiliability = useReliability ? AIEngine.GetReliability(trainEngine) : 100;
				local firstRoute = TrainRoute.instances.len()==0 && RoadRoute.instances.len()==0;
				local locoTractiveEffort = AIEngine.GetMaxTractiveEffort(trainEngine);
				local locoPower = AIEngine.GetPower(trainEngine);
				local maxSpeed = min(AIEngine.GetMaxSpeed(trainEngine),wagonSpeed);
				local railSpeed = AIRail.GetMaxSpeed(trainRailType);
				if(railSpeed >= 1) {
					maxSpeed = min(railSpeed, maxSpeed);
				}
				
				local locoLengthWeight = [trainInfo.length, trainWeight + GetCargoWeight(cargo, trainCapacity)];

				local wagonEngineInfos = [wagonEngineInfo];
				
				foreach(index,subCargo in subCargos) {
					local subWagonEngine = GetSuitableSubWagonEngine(subCargo, trainRailType, trainEngine, maxSpeed);
					local wagonEngineInfo;
					if(subWagonEngine != null) {
						local wagonSpeed = AIRail.GetMaxSpeed(subWagonEngine);
						if(wagonSpeed >= 1) {
							maxSpeed = min(maxSpeed, wagonSpeed);
						}
						wagonEngineInfo = GetWagonEngineInfo(subCargo, subWagonEngine);
						wagonEngineInfo.production <- productions[index+1];
					} else {
						HgLog.Warning("GetSuitableSubWagonEngine:null ["+AICargo.GetName(subCargo)+"] railType:"+AIRail.GetName(trainRailType)+" trainEngine:"+AIEngine.GetName(trainEngine));
						wagonEngineInfo = {};
					}
					wagonEngineInfos.push(wagonEngineInfo);
				}
				
				local numLoco = 1;
				local minNumLoco = 1;
				local increaseLoco = true;
				local numWagon = 0;
				local minNumWagon = 0;
				for( ;;
						numWagon = increaseLoco ? numWagon : NextNumWagon(numWagon, skipWagonNum),
						numLoco = increaseLoco ? numLoco : minNumLoco) {
						
					local totalLength;
					//HgLog.Info("numLoco:"+numLoco+" numWagon:"+numWagon);
					local wagonInfos;
					while(true) {
						wagonInfos = CalculateSubCargoNumWagons(wagonEngineInfos, numWagon);
						totalLength = trainInfo.length * numLoco;
						foreach(wagonInfo in wagonInfos) {
							totalLength += wagonInfo.numWagon * wagonInfo.lengthWeight[0];
						}
						if(!increaseLoco && numWagon > minNumWagon && totalLength > platformLength * 16) {
							numWagon --;
							continue;
						} else {
							break;
						}
					}
					if(increaseLoco && totalLength > platformLength * 16) {
						increaseLoco = false; // numLoco=minNumLocoに戻して調べる
						continue;
					}
					if(!increaseLoco && numWagon <= minNumWagon) {
						break;
					}
					
					minNumWagon = numWagon;
					increaseLoco = false;
					
					local totalWeight = locoLengthWeight[1] * numLoco;
					local lengthWeights = [];
					for(local i=0; i<numLoco; i++) {
						lengthWeights.push(locoLengthWeight);
					}
					foreach(wagonInfo in wagonInfos) {
						for(local i=0; i<wagonInfo.numWagon; i++) {
							lengthWeights.push(wagonInfo.lengthWeight);
						}
						totalWeight += wagonInfo.lengthWeight[1] *  wagonInfo.numWagon;
					}
					
					local tractiveEffort = locoTractiveEffort * numLoco;
					local power = locoPower * numLoco;
					local totalCapacity = trainCapacity * numLoco;
					foreach(wagonInfo in wagonInfos) {
						tractiveEffort += (wagonInfo.isFollowerForceWagon ? locoTractiveEffort * wagonInfo.numWagon : 0);
						power += (wagonInfo.isFollowerForceWagon ? locoPower * wagonInfo.numWagon : 0);
						totalCapacity += wagonInfo.capacity * wagonInfo.numWagon;
					}
					if(totalCapacity == 0) {
						//HgLog.Warning("totalCapacity == 0");
						continue;
					}
					local cruiseSpeed = GetSpeed(tractiveEffort, power, lengthWeights, 1, totalWeight);
					cruiseSpeed = (cruiseSpeed + maxSpeed) / 2;
					cruiseSpeed = min(maxSpeed,cruiseSpeed);
					local requestSpeed = max(10, min(40, maxSpeed / (HogeAI.Get().roiBase ? 10 : 3)));  // min(40, max(10, maxSpeed / 10));
					local acceleration = GetAcceleration(requestSpeed, tractiveEffort, power, lengthWeights, totalLength, totalWeight);
					if(acceleration < 0) {
						//HgLog.Warning("acceleration:"+acceleration);
						numLoco ++;
						minNumLoco = numLoco;
						increaseLoco = true;
						continue;
					}
					local price = trainPrice * numLoco;
					foreach(wagonInfo in wagonInfos) {
						price += wagonInfo.price * wagonInfo.numWagon;
					}
					if(firstRoute && price * 3 / 2 > HogeAI.GetUsableMoney()) {
						break;
					}
					local loadingTime = CargoUtils.IsPaxOrMail(cargo) ? 10 : 2;
					local days = (distance * 664 / cruiseSpeed / 24 + loadingTime) * 2;
					local maxVehicles = max(1, days / 5);
					local stationDay = 0;//platformLength * 5 / 7; // 入れ替わりの"間"
					local income = 0;
					local minWaitingInStationTime = 10000;
					foreach(index,wagonInfo in wagonInfos) {
						local capacity = wagonInfo.capacity * wagonInfo.numWagon + (index == 0 ? trainCapacity * numLoco : 0);
						local productionPerDay = wagonInfo.production.tofloat() / 30;
						local waitingInStationTime = max(loadingTime, max(0, ((capacity - stationDay * productionPerDay) / productionPerDay).tointeger()));
						minWaitingInStationTime = min(waitingInStationTime, minWaitingInStationTime);
					}
					//HgLog.Info("minWaitingInStationTime:"+minWaitingInStationTime);
					
					foreach(index,wagonInfo in wagonInfos) {
						local productionPerDay = wagonInfo.production.tofloat() / 30;
						local capacity = wagonInfo.capacity * wagonInfo.numWagon + (index == 0 ? trainCapacity * numLoco : 0)
						local deliver = min(capacity, ((minWaitingInStationTime + stationDay) * productionPerDay).tointeger());
						
						//HgLog.Info("cargo:"+AICargo.GetName(wagonEngineInfo.cargo)+" cruiseSpeed:"+cruiseSpeed+" deliver:"+deliver+" capacity:"+capacity+" productionPerDay:"+productionPerDay);
						income += CargoUtils.GetCargoIncome(distance, wagonInfo.cargo, cruiseSpeed, minWaitingInStationTime, isBidirectional) * deliver
							- wagonInfo.runningCost * wagonInfo.numWagon;
						//HgLog.Info("income:"+income);
					}
					income = income * (trainReiliability+100)/200 - trainRunningCost * numLoco;
					if(income <= 0) {
						//HgLog.Warning("income:"+income);
						continue;
					}
					local infrastractureCost = InfrastructureCost.Get().GetCostPerDistanceRail(trainRailType) * distance;
					local vehiclesPerRoute = min(maxVehicles, days / minWaitingInStationTime + 1);
					if(maxBuildingCost > 0) {
						vehiclesPerRoute = min(vehiclesPerRoute, (maxBuildingCost - buildingCost) / price);
						if(vehiclesPerRoute == 0) {
							continue;
						}
					}
					if(price > HogeAI.Get().GetUsableMoney() + quaterlyIncome * 16) {
						continue; //　買えない
					}
					local routeIncome = income * vehiclesPerRoute - infrastractureCost;
					local roi = routeIncome * 1000 / (price * vehiclesPerRoute + buildingCost);
					local incomePerVehicle = routeIncome / vehiclesPerRoute; 
					local incomePerBuildingTime = routeIncome * 100 / TrainRoute.GetBuildingTime(distance);
					local value = HogeAI.Get().GetValue(roi,incomePerBuildingTime,incomePerVehicle);
					
					/*local explain = "route:"+routeIncome+" income:"+income+" roi:"+roi+" a:"+acceleration+" speed:"+cruiseSpeed+" vehicles:"+vehiclesPerRoute
						+ " minW:"+minWaitingInStationTime+" d:"+days+" "+AIEngine.GetName(trainEngine)+"x"+numLoco;
					foreach(index,wagonInfo in wagonInfos) {
						explain += "-" + AIEngine.GetName(wagonInfo.engine) + "x" + wagonInfo.numWagon+"("+wagonInfo.production+")";
					}
					HgLog.Info(explain);*/
					
					
					result.push({
						engine = trainEngine
						railType = trainRailType
						trainEngine = trainEngine
						numLoco = numLoco
						wagonEngineInfos = wagonInfos
						capacity = totalCapacity
						length = totalLength
						weight = totalWeight
						price = price
						roi = roi
						income = income
						routeIncome = routeIncome
						incomePerOneTime = 0 //unknown
						value = value
						production = productions[0]
						vehiclesPerRoute = vehiclesPerRoute
						lengthWeights = lengthWeights
						cruiseSpeed = cruiseSpeed
						buildingCost = buildingCost
					});
					if(cruiseSpeed < maxSpeed * 0.8) {
						//HgLog.Warning("acceleration:"+acceleration);
						numLoco ++;
						increaseLoco = true;
						continue;
					}
				}
			}
		}
		return result;
	}
	
	function NextNumWagon(numWagon, skipWagonNum) {
		if(skipWagonNum != 1) {
			return numWagon + skipWagonNum;
		}
		return numWagon + max( 1, numWagon / 3 ); // 1,2,3,4,5,6,7,9,12,16,21,28,37...
	}
	
	function GetSuitestRailType(trainEngine, checkRailType) {
		local maxSpeed = 0;
		local cost = 0;
		local result = null;
		foreach(railType,v in AIRailTypeList()) {
			/*if(checkRailType) {
				if(!InfrastructureCost.Get().CanExtendRail(railType)) {
					continue;
				}
			}*/
			
			//HgLog.Info("AIRail.GetBuildCost:"+ AIRail.GetBuildCost(railType, AIRail.BT_TRACK)+" "+AIRail.GetName(railType));
			
			if(AIEngine.HasPowerOnRail(trainEngine, railType)) {
				local railSpeed = AIRail.GetMaxSpeed (railType);
				railSpeed = railSpeed == 0 ? 10000 : railSpeed;
				local speed = min(railSpeed, AIEngine.GetMaxSpeed(trainEngine));
				if(result != null && maxSpeed == speed) {
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

	function GetAcceleration(requestSpeed, maxTractiveEffort, power, lengthWeights, totalLength, totalWeight ) {
		//local totalWeight = GetLengthWeightsWeight(lengthWeights);
		local slopes = maxSlopes;
		if(selfGetMaxSlopesFunc != null) {
			slopes = selfGetMaxSlopesFunc.GetMaxSlopes(totalLength /*GetLengthWeightsLength(lengthWeights)*/);
		}
		if(slopes == null) {
			slopes = max(1,totalLength /*GetLengthWeightsLength(lengthWeights)*/ / 16 / 5);
		}
		local engineForce = VehicleUtils.GetForce(maxTractiveEffort, power, requestSpeed);
		local slopeForce = GetMaxSlopeForce(lengthWeights, slopes, totalWeight);
		
		//HgLog.Info("maxSlopes:"+slopes+" engineForce:"+engineForce+" slopeForce:"+slopeForce+" totalWeight:"+totalWeight+" requestSpeed:"+requestSpeed);
		return (engineForce - slopeForce) / (totalWeight * 4);
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
		local maxSlopedWeight = 0;
		foreach(i,lw in lengthWeights) {
			local w = 0;
			local l = 0;
			do {
				w += lengthWeights[i][1];
				i++;
				if(i >= lengthWeights.len()) {
					break;
				}
				l += (lengthWeights[i-1][0] + lengthWeights[i][0]) / 2;
			} while(l < 16 * maxSlopes);
			maxSlopedWeight = max(maxSlopedWeight,w);
		}
		//HgLog.Info("maxSlopedWeight:"+maxSlopedWeight);
		return VehicleUtils.GetSlopeForce(maxSlopedWeight, totalWeight);
	}
	
	function GetForce(maxTractiveEffort, power, requestSpeed) {
		return VehicleUtils.GetForce(maxTractiveEffort, power, requestSpeed);
	}
	
	function GetSpeed(maxTractiveEffort, power, lengthWeights, maxSlopes, totalWeight) {
		//local totalWeight = GetLengthWeightsWeight(lengthWeights);
		local force = GetMaxSlopeForce(lengthWeights, maxSlopes, totalWeight);
	
		/*if(maxTractiveEffort * 1000 < force) {
			return 0;
		}*/
		return power * 746 * 18 / 5 / force;
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
	static removed = []; // TODO: Save/Load
	static unsuitableEngineWagons = {};
	
	static RT_ROOT = 1;
	static RT_ADDITIONAL = 2;
	static RT_RETURN = 3;
	
	static USED_RATE_LIMIT = 20;
	
	static function Save(route) {
		local t = {};
		t.id <- route.id;
		t.routeType <- route.routeType;
		t.cargo <- route.cargo;
		t.srcHgStation <- route.srcHgStation.id;
		t.destHgStation <- route.destHgStation.id;
		t.pathSrcToDest <- route.pathSrcToDest.array_; //path.Save();
		t.pathDestToSrc <- route.pathDestToSrc.array_; //path.Save();
		t.subCargos <- route.subCargos;
		t.transferRoute <- route.isTransfer;
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
		t.usedRateHistory <- route.usedRateHistory;
		t.engineSetsCache <- route.engineSetsCache;
		t.engineSetsDate <- route.engineSetsDate;
		t.engineSetAllRailCache <- route.engineSetAllRailCache;
		t.engineSetAllRailDate <- route.engineSetAllRailDate;
		t.lastDestClosedDate <- route.lastDestClosedDate;
		t.additionalTiles <- route.additionalTiles;
		t.cannotChangeDest <- route.cannotChangeDest;
		t.lastConvertRail <- route.lastConvertRail;
		return t;
	}
	
	static function SaveStatics(data) {
		local arr = [];
		foreach(route in TrainRoute.instances) {
			if(route.id == null) { // Removeが完了したroute
				continue;
			}
			arr.push(TrainRoute.Save(route));
		}
		data.trainRoutes <- arr;		

		arr = [];
		foreach(route in TrainRoute.removed) {
			arr.push(TrainRoute.Save(route));
		}
		data.removedTrainRoute <- arr; //いまのところIsInfrastractureMaintenance:trueの時しか使用されない
		
		data.unsuitableEngineWagons <- TrainRoute.unsuitableEngineWagons;
	}
	
	static function Load(t) {
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
		trainRoute.subCargos = t.subCargos;
		trainRoute.isTransfer = t.transferRoute;
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

		}
		trainRoute.srcStationSign = t.rawin("srcStationSign") ? t.srcStationSign : null;
		trainRoute.reduceTrains = t.rawin("reduceTrains") ? t.reduceTrains : false;
		trainRoute.maxTrains = t.rawin("maxTrains") ? t.maxTrains : null;
		trainRoute.slopesTable = t.slopesTable;
		trainRoute.engineSetsCache = t.engineSetsCache;
		trainRoute.engineSetsDate = t.engineSetsDate;
		trainRoute.engineSetAllRailCache = t.engineSetAllRailCache;
		trainRoute.engineSetAllRailDate = t.engineSetAllRailDate;
		trainRoute.lastDestClosedDate = t.lastDestClosedDate;
		trainRoute.additionalTiles = t.additionalTiles;
		trainRoute.cannotChangeDest = t.cannotChangeDest;
		trainRoute.lastConvertRail = t.rawin("lastConvertRail") ? t.lastConvertRail : null;
		//trainRoute.usedRateHistory = t.rawin("usedRateHistory") ? t.usedRateHistory : [];
		return trainRoute;
	}
	
	static function LoadStatics(data) {
		TrainRoute.instances.clear();
		local idMap = {};
		foreach(t in data.trainRoutes) {
			local trainRoute = TrainRoute.Load(t);
			idMap[t.id] <- trainRoute;
			TrainRoute.instances.push(trainRoute);

			if(!trainRoute.isRemoved) {
				PlaceDictionary.Get().AddRoute(trainRoute);
				if(trainRoute.returnRoute != null) {
					PlaceDictionary.Get().AddRoute(trainRoute.returnRoute);
				}
			}
		}
		TrainRoute.removed.clear();
		if(data.rawin("removedTrainRoute")) {
			foreach(t in data.removedTrainRoute) {
				local trainRoute = TrainRoute.Load(t);
				TrainRoute.removed.push(trainRoute);
			}
		}

		// 今は使われていない
		foreach(t in data.trainRoutes) {
			local trainRoute = idMap[t.id];
			if(t.additionalRoute != null) {
				trainRoute.additionalRoute = idMap[t.additionalRoute];
			}
			if(t.parentRoute != null) {
				trainRoute.parentRoute = idMap[t.parentRoute];
			}
			HgLog.Info("load route:"+trainRoute);
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
	
	function EstimateEngineSet(self, cargo, distance, production, isBidirectional, infrastractureType=null) {
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.productions = [production];
		trainPlanner.isBidirectional = isBidirectional;
		trainPlanner.distance = distance;
		trainPlanner.skipWagonNum = 5;
		trainPlanner.limitTrainEngines = 1;
		trainPlanner.limitWagonEngines = 1;
		trainPlanner.checkRailType = true;
		local engineSets = trainPlanner.GetEngineSetsOrder();
		if(engineSets.len() >= 1) {
			return engineSets[0];
		}
		return null;
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
	subCargos = null;
	destHgStations = null;
	isTransfer = null;
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
	usedRateHistory = null;
	engineSetsCache = null;
	engineSetsDate = null;
	engineSetAllRailCache = null;
	engineSetAllRailDate = null;
	lastDestClosedDate = null;
	additionalTiles = null;
	cannotChangeDest = null;
	lastConvertRail = null;
	
	averageUsedRate = null;
	isBuilding = null;
	usedRateCache = null;
	destRoute = null;
	hasRailDest = null;
	lastCheckProduction = null;

	constructor(routeType, cargo, srcHgStation, destHgStation, pathSrcToDest, pathDestToSrc){
		Route.constructor();
		this.id = idCounter.Get();
		this.routeType = routeType;
		this.cargo = cargo;
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.pathSrcToDest = pathSrcToDest;
		this.pathDestToSrc = pathDestToSrc;
		this.subCargos = [];
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
		this.cannotChangeDest = false;
	}
	
	function Initialize() {
		InitializeSubCargos();
	}
	
	function InitializeSubCargos() {
		subCargos = CalculateSubCargos();
	}
	
	function GetCargos() {
		local result = [cargo];
		foreach(subCargo in subCargos) {
			result.push(subCargo);
		}
		return result;
	}
	
	function HasCargo(cargo) {
		if(cargo == this.cargo) {
			return true;
		}
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

	function GetThresholdVehicleNumRateForNewRoute() {
		return 0.9;
	}

	function GetThresholdVehicleNumRateForSupportRoute() {
		return 0.9;
	}

	function GetBuildingCost(infrastractureType, distance, cargo) {
		local railCost = (AIRail.GetBuildCost(infrastractureType, AIRail.BT_TRACK) - 75 + 450) * 2;
	
		return distance * railCost/*HogeAI.Get().GetInflatedMoney(720)*/ +HogeAI.Get().GetInflatedMoney( CargoUtils.IsPaxOrMail(cargo) ? 20000 : 10000);
	}
	
	function GetBuildingTime(distance) {
		return distance * 2 + 2100;
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
	
	function IsRemoved() {
		return isRemoved;
	}
	
	
	function IsValidEngineSetCache() {
		return engineSetsCache != null && ( AIDate.GetCurrentDate() < engineSetsDate || TrainRoute.instances.len()<=1);
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
	
	function GetRoundedProductions() {
		local result = [];
		local cargos = GetCargos();
		local loadRates = CalculateLoadRates();
		local loads = loadRates[0];
		local capas = loadRates[1];
		local productions = [];
		local totalProduction = 0;
		local totalLoad = 0;
		foreach(index, cargo in cargos) {
			local production = GetProductionCargo(cargo);
			if(this.cargo == cargo) {
				production = max(50, production); // 生産0でルートを作る事があるので、これが無いとBuildFirstTrainに失敗してルートが死ぬ
			}
			productions.push(production);
			totalProduction += production;
			totalLoad += loads[index];
		}
		
		foreach(index, cargo in cargos) {
			if(capas[index] == 0 || totalLoad == 0) {
				result.push(GetRoundedProduction(productions[index]));
			} else {
				result.push(GetRoundedProduction(totalProduction * loads[index] / totalLoad));
			}
		}
		return result;
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
		foreach(vehicle in engineVehicles) {
			local loaded = false;
			foreach(cargo in cargos) {
				if(AIVehicle.GetCargoLoad(vehicle, cargo) >= 1) {
					loaded = true;
					break;
				}
			}
			if(!loaded) {
				continue;
			}
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

	function ChooseEngineSet() {
		local a = GetEngineSets();
		if(a.len() == 0){ 
			return null;
		}
		return a[0];
	}
	
	function GetEngineSets(isAll=false) {
		local production = GetRoundedProduction(max(50,GetProduction()));
		if(!isAll && IsValidEngineSetCache() && (lastCheckProduction==null || production < lastCheckProduction * 3 / 2)) {
			return engineSetsCache;
		}
		lastCheckProduction = production;
	
		local execMode = AIExecMode();
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.distance = GetDistance();
		trainPlanner.productions = GetRoundedProductions(); //GetRoundedProduction(max(50,GetProduction()));
		trainPlanner.subCargos = subCargos;
		//trainPlanner.subProductions = GetRoundedSubProductions();
		trainPlanner.isBidirectional = IsBiDirectional();
		trainPlanner.railType = GetRailType();
		trainPlanner.platformLength = GetPlatformLength();
		trainPlanner.selfGetMaxSlopesFunc = this;
		trainPlanner.additonalTrainEngine = latestEngineSet != null ? latestEngineSet.trainEngine : null;
		trainPlanner.additonalWagonEngine = latestEngineSet != null ? latestEngineSet.wagonEngineInfos[0].engine : null;
		if(isAll) {
			trainPlanner.limitWagonEngines = null;
			trainPlanner.limitTrainEngines = null;		
		} else if(latestEngineSet == null) {
			trainPlanner.limitWagonEngines = 3;
			trainPlanner.limitTrainEngines = 10;		
		}
		engineSetsCache = trainPlanner.GetEngineSetsOrder();
		engineSetsDate = AIDate.GetCurrentDate() + 1000 + AIBase.RandRange(500);
		if(engineSetsCache.len()>=1) {
			local t = engineSetsCache[0];
			//HgLog.Info("income:"+t.income+" roi:"+t.roi+" speed:"+t.cruiseSpeed+" "+AIEngine.GetName(t.trainEngine)+"x"+t.numLoco+"-"+AIEngine.GetName(t.wagonEngine)+"x"+t.numWagon+" production:"+t.production+" "+this);
			HgLog.Info("GetEngineSets income:"+engineSetsCache[0].income+" roi:"+engineSetsCache[0].roi+" production:"+trainPlanner.productions[0]+" "+this);
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
		HgLog.Info("Start ChooseEngineSetAllRailTypes "+this);
		local trainPlanner = TrainPlanner();
		trainPlanner.cargo = cargo;
		trainPlanner.distance = GetDistance();
		trainPlanner.productions = GetRoundedProductions(); //GetRoundedProduction(max(50,GetProduction()));
		trainPlanner.subCargos = subCargos;
		//trainPlanner.subProductions = GetRoundedSubProductions();
		trainPlanner.isBidirectional = IsBiDirectional();
		trainPlanner.platformLength = GetPlatformLength();
		trainPlanner.selfGetMaxSlopesFunc = this;
		trainPlanner.additonalTrainEngine = latestEngineSet != null ? latestEngineSet.trainEngine : null;
		trainPlanner.additonalWagonEngine = latestEngineSet != null ? latestEngineSet.wagonEngineInfos[0].engine : null;
		trainPlanner.limitWagonEngines = 2;
		trainPlanner.limitTrainEngines = 5;
		trainPlanner.checkRailType = true;
		local sets = trainPlanner.GetEngineSetsOrder();
		if(sets.len()==0) {
			HgLog.Warning("Not found engineSet.(ChooseEngineSetAllRailTypes) "+this);
			return null;
		}
		local railTypeSet = {};
		foreach(set in sets) {
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
			if(current.value + abs( current.value / 5 ) < sets[0].value) {
				engineSetAllRailCache = sets[0];
			} else {
				engineSetAllRailCache = current;
			}
		} else {
			engineSetAllRailCache = sets[0];
		}
		if(engineSetAllRailCache.routeIncome < 0) {
			HgLog.Warning("Estimate routeIncome:"+engineSetAllRailCache.routeIncome+"<0 "+this);
		}
		engineSetAllRailDate = AIDate.GetCurrentDate() + 1600 + AIBase.RandRange(400);
		return engineSetAllRailCache;
	}
	
	function GetPlatformLength() {
		return min(srcHgStation.platformLength, destHgStation.platformLength);
	}
	
	function BuildFirstTrain() {
		latestEngineVehicle = BuildTrain(); //TODO 最初に失敗すると復活のチャンスなし。orderが後から書き変わる事があるがそれが反映されないため。orderを状態から組み立てられる必要がある
		if(latestEngineVehicle == null) {
			HgLog.Warning("BuildFirstTrain failed. "+this);
			return false;
		}
		BuildOrder(latestEngineVehicle);
		engineVehicles.AddItem(latestEngineVehicle,latestEngineVehicle);
		if(!AIVehicle.StartStopVehicle(latestEngineVehicle)) {
			HgLog.Warning("StartStopVehicle failed."+this+" "+AIError.GetLastErrorString());
		}
		if(startDate == null) {
			startDate = AIDate.GetCurrentDate();
			destHgStations.push(destHgStation);
		}
		return true;
	}
	
	function GetLastHgStation() {
		return destHgStations[destHgStations.len()-1];
	}
	
	function CloneAndStartTrain() {
		if(latestEngineVehicle == null) {
			BuildFirstTrain();
			return;
		}
		
		local train = null;
		
		local engineSet = ChooseEngineSet();
		if(!HasVehicleEngineSet(latestEngineVehicle, engineSet)) {
			//HgLog.Info("BuildTrain HasVehicleEngineSet == false "+this);
			train = BuildTrain();	
		} else {
			//HgLog.Info("CloneTrain HasVehicleEngineSet == true "+this);
			train = CloneTrain();
			if(train == null) {
				engineSetsCache = null;
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
		if(engineVehicles.len() >= 1 && !AIVehicle.MoveWagon(engineVehicle, 0, engineVehicles[0], engineVehicles.len()-1)) {
			HgLog.Warning("MoveWagon engineVehicle failed. "+explain + " "+AIError.GetLastErrorString());
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
			engineSetsCache = null;
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
			local explain = AIEngine.GetName(trainEngine);
			if(engineSet.numLoco>=2) {
				explain += "x"+engineSet.numLoco;
			}
			foreach(wagonEngineInfo in engineSet.wagonEngineInfos) {
				explain += "-"+AIEngine.GetName(wagonEngineInfo.engine)+"x"+wagonEngineInfo.numWagon;
			}
			explain += " length:"+(engineSet.rawin("length") ? engineSet.length : -1)+" depot:"+HgTile(depotTile)+" "+this;
			HgLog.Info("BuildTrain income:"+engineSet.income+" roi:"+engineSet.roi+" production:"+engineSet.production+" "+explain+" "+this);
			
			//HgLog.Info("Try build "+explain);

			
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
						HgLog.Warning("BuildVehicleWithRefit wagon failed. "+explain+" "+AIError.GetLastErrorString());
						success = false;
						break;
					}
					local realLength = AIVehicle.GetLength(wagon);
					local trainInfo = TrainInfoDictionary.Get().GetTrainInfo(wagonEngineInfo.engine);
					if(realLength != trainInfo.length) { // 時代で変わる？
						HgLog.Warning("Wagon length different:"+realLength+"<="+trainInfo.length+" "+AIEngine.GetName(wagonEngineInfo.engine)+" "+explain);
						trainInfo.length = realLength;
					}
					if(AIVehicle.GetLength(engineVehicle) + realLength > GetPlatformLength() * 16) {
						HgLog.Warning("Train length over platform length."+explain);
						AIVehicle.SellWagonChain(wagon, 0);
						break;
					}
					if(!AIVehicle.MoveWagon(wagon, 0, engineVehicle, AIVehicle.GetNumWagons(engineVehicle)-1)) {
						AddUnsuitableEngineWagon(trainEngine, wagonEngineInfo.engine);
						HgLog.Warning("MoveWagon failed. "+explain + " "+AIError.GetLastErrorString());
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
				continue;
			}
			
			latestEngineSet = engineSet;
			if(engineSetsCache != null && engineSetsCache.len() >= 1) {
				engineSetsCache[0] = engineSet; // ChooseEngineSet()で実際に作られたengineSetが返るようにする
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
		engineSetsCache = null;
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
		if(parentRoute != null) {
			result = max(result, parentRoute.GetMaxSlopes(length));
		}
		if(pathIn == null && (returnRoute != null || IsBiDirectional())) {
			result = max(result, GetMaxSlopes(length, pathDestToSrc.path));
		}
		HgLog.Info("GetMaxSlopes("+length+","+tileLength+")="+result+" "+this);
		slopesTable[tileLength] <- result;
		return result;
	}
		
	function IsBiDirectional() {
		return !isTransfer && destHgStation.place != null && destHgStation.place.GetProducing().IsTreatCargo(cargo);
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

		local trainPlanner = TrainPlanner();
		trainPlanner.selfGetMaxSlopesFunc = this;
		if(trainPlanner.GetAcceleration(
				10,
				AIEngine.GetMaxTractiveEffort(latestEngineSet.trainEngine),
				AIEngine.GetPower(latestEngineSet.trainEngine),
				latestEngineSet.lengthWeights,
				latestEngineSet.length,
				latestEngineSet.weight) < 0) { 
			HgLog.Warning("Cannot ChangeDestination (steep slope)"+this);
			/*foreach(engineVehicle, v in engineVehicles) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(engineVehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (engineVehicle);
				}
			}*/
		} else {
			ChangeDestination(destHgStation);
		}
		
		local oldDest = this.destHgStation;
		this.destHgStation = destHgStation;
		InitializeSubCargos();
		this.destHgStation = oldDest;
		
		engineSetsCache = null;
		maxTrains = null;
		lastDestClosedDate = null;
		if(additionalRoute != null) {
			additionalRoute.slopesTable.clear();
		}
	}

	function ChangeDestination(destHgStation) {
		if(returnRoute != null) { // このメソッドはreturn routeがある場合に対応していない
			HgLog.Warning("Cannot ChangeDestination (return route exists) "+this);
			return;
		}
	
		local execMode = AIExecMode();
		
		if(IsBiDirectional()) {
			foreach(station in this.destHgStation.stationGroup.hgStations) {
				foreach(route in station.GetUsingRoutesAsDest()) {
					if(route.IsTransfer()) {
						route.NotifyChangeDestRoute();
					}
				}
			}
		}

		PlaceDictionary.Get().RemoveRoute(this);
		this.destHgStation = destHgStation;
		PlaceDictionary.Get().AddRoute(this);

		if(latestEngineVehicle != null) {
			local orderFlags = AIOrder.OF_NON_STOP_INTERMEDIATE + (IsBiDirectional() ? 0 : AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD);
		
			if(AIOrder.GetOrderCount (latestEngineVehicle) >= 4) {
				AIOrder.InsertOrder(latestEngineVehicle, 3, destHgStation.platformTile, orderFlags);
				AIOrder.SetStopLocation	(latestEngineVehicle, 3, AIOrder.STOPLOCATION_MIDDLE);
			} else {
				AIOrder.AppendOrder(latestEngineVehicle, destHgStation.platformTile, orderFlags);
				AIOrder.SetStopLocation	(latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
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
			AIOrder.SetStopLocation	(latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
			local conditionOrderPosition = AIOrder.GetOrderCount(latestEngineVehicle);
			AIOrder.AppendConditionalOrder (latestEngineVehicle, 0);
			AIOrder.SetOrderCompareValue(latestEngineVehicle, conditionOrderPosition, 0);
			AIOrder.SetOrderCompareFunction(latestEngineVehicle, conditionOrderPosition, AIOrder.CF_EQUALS );
			AIOrder.SetOrderCondition(latestEngineVehicle, conditionOrderPosition, AIOrder.OC_LOAD_PERCENTAGE );
			AIOrder.AppendOrder(latestEngineVehicle, destStation.platformTile, AIOrder.OF_NON_STOP_INTERMEDIATE + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD );
			AIOrder.SetStopLocation	(latestEngineVehicle, AIOrder.GetOrderCount(latestEngineVehicle)-1, AIOrder.STOPLOCATION_MIDDLE);
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
			AIOrder.SetOrderJumpTo(latestEngineVehicle, 4, 0); // return時に積載していないときにupdate depotへ飛ぶようにする
		}
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
		lastConvertRail = AIDate.GetCurrentDate();
		
		local execMode = AIExecMode();
		AIRail.SetCurrentRailType(railType);
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
			if(AIRail.IsLevelCrossingTile(t)) { // 失敗時にRailTypeが戻せないケースがあるので、先に踏切だけ試す。
				if(!BuildUtils.RetryUntilFree(function():(t,railType) {
					return AIRail.ConvertRailType(t,t,railType);
				}, 500)) {
					HgLog.Warning("ConvertRailType failed:"+HgTile(t)+" "+AIError.GetLastErrorString());
					return false;
				}
			}
		}
		local tileTable = {};
		foreach(t in tiles) {
			if(AIRail.GetRailType(t)==railType) {
				continue;
			}
			tileTable.rawset(t,0);
		}
	
		while(tileTable.len() >= 1) {
			foreach(tile,_ in tileTable) {
				tileTable.rawdelete(tile);
				if(AIRail.GetRailType(tile)==railType) {
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
					return AIRail.ConvertRailType(tile,end,railType); // TODO: 一部失敗は成功を返してしまう。
				}, 500)) {
					HgLog.Warning("ConvertRailType failed:"+HgTile(tile)+"-"+HgTile(end)+" "+AIError.GetLastErrorString());
					return false;
				}
				break;
			}
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
						AIBridge.RemoveBridge(t);
						AIBridge.BuildBridge(AIVehicle.VT_RAIL, latestBridge, t, other);
					}
				}
			}
		}
		/*
		foreach(t in tiles) {
			if(AIRail.GetRailType(t)==railType) {
				continue;
			}
			if(!BuildUtils.RetryUntilFree(function():(t,railType) {
				return AIRail.ConvertRailType(t,t,railType);
			}, 500)) {
				HgLog.Warning("ConvertRailType failed:"+HgTile(t)+" "+AIError.GetLastErrorString());
				return false;
			}
			if(updateRailDepot != null && AIBridge.IsBridgeTile(t)) {
				local other = AIBridge.GetOtherBridgeEnd(t);
				local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(t, other) + 1);
				bridge_list.Valuate(AIBridge.GetMaxSpeed);
				bridge_list.Sort(AIList.SORT_BY_VALUE, false);
				local latestBridge = bridge_list.Begin();
				if(latestBridge != AIBridge.GetBridgeID(t)) {
					AIBridge.RemoveBridge(t);
					AIBridge.BuildBridge(AIVehicle.VT_RAIL, latestBridge, t, other);
				}
			}
		}*/
		engineSetsCache = null;
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
		HgTile(updateRailDepot).RemoveDepot();
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
					HgLog.Warning("All vehicles removed."+this);
					ArrayUtils.Remove(TrainRoute.instances, this);
					TrainRoute.removed.push(this);
					
					
					/*srcHgStation.Remove(); TODO: destHgStationを再利用して新しいrouteを作りたい
					destHgStation.Remove();
					pathSrcToDest.Remove();
					pathDestToSrc.Remove();
					id = null;*/
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
			local newtrain = BuildTrain();
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

	
	function Close() {
		HgLog.Warning("Close route start:"+this);
		isClosed = true;
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
		
		if(additionalRoute != null) {
			additionalRoute.Close();
		}
		if(returnRoute != null) {
			returnRoute.Close();
		}
	}	
	
	function Remove() {					
		HgLog.Info("Remove route: "+this);
		isRemoved = true;
		Close();
		PlaceDictionary.Get().RemoveRoute(this);
		if(returnRoute != null) {
			returnRoute.Remove();
		}
	}

	function RemovePhysically() { // ScanRoutesから呼ばれる
		HgLog.Warning("RemovePhysically " + this);
		local execMode = AIExecMode();
		HogeAI.DoInterval();
		if(srcHgStation.CanRemove(this)) {
			srcHgStation.Remove();
		}
		foreach(station in destHgStations) {
			HogeAI.DoInterval();
			if(station.CanRemove(this)) {
				station.Remove();
			}
		}
		pathSrcToDest.Remove(true/*physicalRemove*/, true/*DoInterval*/);
		pathDestToSrc.Remove(true/*physicalRemove*/, true/*DoInterval*/);
		local tiles = [];
		tiles.extend(depots);
		tiles.extend(additionalTiles);
		foreach(tile in tiles) {
			HogeAI.DoInterval();
			if(AIRail.IsRailDepotTile(tile)) {
				AITile.DemolishTile(tile);
			}
			if(AIRail.IsRailTile(tile)) {
				RailBuilder.RemoveRailTracksAll(tile);
			}
		}
		if(returnRoute != null) {
			HogeAI.DoInterval();
			returnRoute.RemovePhysically();
		}
		HogeAI.DoInterval();
	}

	function ReOpen() {
		HgLog.Warning("ReOpen route:"+this);
		isClosed = false;
		PlaceDictionary.Get().AddRoute(this);
		if(returnRoute != null) {
			returnRoute.ReOpen();
		}
		//BuildFirstTrain();
	}
	
	
	function IsInStationOrDepotOrStop(){
		foreach(vehicle, v in engineVehicles) {
			if(AIStation.GetStationID(AIVehicle.GetLocation(vehicle)) == srcHgStation.GetAIStation() 
					|| AIVehicle.IsInDepot (vehicle) /*|| AIMap.DistanceManhattan(AIVehicle.GetLocation(vehicle),srcHgStation.platformTile) < 12*/) {
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
		RemoveSendUpdateDepotOrder();
		foreach(engineVehicle,v in engineVehicles) {
			if(AIVehicle.IsStoppedInDepot(engineVehicle)) {
				AIVehicle.StartStopVehicle(engineVehicle);
			}
		}
		if(additionalRoute != null) {
			additionalRoute.RollbackUpdateRailType(railType);
		}
	}
	
	function NeedsAdditionalProducingCargo(cargo, orgRoute = null, isDest = false, hgStation = null) {
		if(isClosed || reduceTrains) {
			return false;
		}
		if(IsOverflow(isDest, hgStation)) {
			return false;
		}
		
		if(!isDest && IsTransfer()) {
			local destRoute = GetDestRoute();
			if(!destRoute) {
				return false;
			}
			return destRoute.NeedsAdditionalProducingCargo(cargo, orgRoute);
		}
		if(hgStation == null) {
			hgStation = isDest ? destHgStation : srcHgStation;
		}
		local limitCapacity = latestEngineSet == null ? 400 : GetCargoCapacity(cargo);
		if(isDest == false) {
			limitCapacity /= 2;
		}
		local cargoWaiting = AIStation.GetCargoWaiting(hgStation.GetAIStation(), cargo);
		local result = (averageUsedRate == null || averageUsedRate < TrainRoute.USED_RATE_LIMIT) &&  cargoWaiting <= limitCapacity;
		//HgLog.Info("NeedsAdditionalProducing CargoWaiting:"+cargoWaiting+"["+AICargo.GetName(cargo)+"]"+hgStation.GetName()+" limitCapacity:"+limitCapacity+" result:"+result+" "+this)
		return result;
	}
	
	function IsOverflow(isDest = false, hgStation = null) {
		if(hgStation == null) {
			hgStation = isDest ? destHgStation : srcHgStation;
		}
		return AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) > GetOverflowQuantity();
	}
	
	function GetOverflowQuantity() {
		return  max( 1000, latestEngineSet == null ? 0 : latestEngineSet.capacity * 3 / 2 );
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
		local result = (maxTrains == null || maxTrains > engineVehicles.Count())
			&& !IsInStationOrDepotOrStop() 
			&& (averageUsedRate == null || averageUsedRate < TrainRoute.USED_RATE_LIMIT)
			&& (/*HogeAI.Get().IsRich() || */
				(latestEngineSet==null || IsWaitingCargoForCloneTrain()));
		if(!result) {
			return false;
		}
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(destRoute != false) {
				local needs = false;
				foreach(cargo in GetCargos()) {
					if(GetCargoCapacity(cargo) >= 1 && destRoute.NeedsAdditionalProducingCargo(cargo)) {
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
	
		local station = srcHgStation.GetAIStation();
		return AIStation.GetCargoWaiting(station, cargo) > GetCargoCapacity(cargo) / ( HogeAI.Get().roiBase ? 1 : 2 );
		/* PAXしかいないのに作りすぎて赤字路線化する　TODO: 複数のmain cargo
		foreach(cargo in GetCargos()) {
			local capacity = GetCargoCapacity(cargo);
			if(capacity !=0 && AIStation.GetCargoWaiting(station, cargo) > GetCargoCapacity(cargo)) {
				return true;
			}
		}
		return false;*/
	}
	
	function GetCargoCapacity(cargo) {
		if(latestEngineSet == null) {
			return 0;
		}
		foreach(wagonEngineInfo in latestEngineSet.wagonEngineInfos) {
			if(wagonEngineInfo.cargo == cargo) {
				return wagonEngineInfo.capacity;
			}
		}
		return 0;
	}
	
	function CheckCloneTrain() {
		if(isClosed || updateRailDepot!=null) {
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
			local numClone = 1;
			if(latestEngineSet != null) {
				if(latestEngineSet.vehiclesPerRoute - engineVehicles.Count() >= 15) {
					numClone = 4;
				} else if(latestEngineSet.vehiclesPerRoute - engineVehicles.Count() >= 10) {
					numClone = 3;
				} else if(latestEngineSet.vehiclesPerRoute - engineVehicles.Count() >= 5) {
					numClone = 2;
				}
			}
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
		foreach(engineVehicle, v in engineVehicles) {
			if(!AIVehicle.IsValidVehicle (engineVehicle)) {
				HgLog.Warning("invalid veihicle found "+engineVehicle+" at "+this);
				engineVehicles.RemoveItem(engineVehicle);
				continue;
			}
			/*
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(engineVehicle, AIOrder.ORDER_CURRENT)) != 0) {
				AIVehicle.SendVehicleToDepot(engineVehicle);
				AIVehicle.SendVehicleToDepot(engineVehicle); // ときどきリセット
			}*/
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
					//HgLog.Info("SendVehicleToDepot(reduceTrains):"+engineVehicle+" "+this);
					SendVehicleToDepot(engineVehicle);
				}
			}
		}
		
		if(!HogeAI.HasIncome(20000) || TrainRoute.instances.len() <= 1) {
			return;
		}
		
		engineSet = ChooseEngineSet();
		if(engineSet.price > HogeAI.Get().GetUsableMoney()) {
			return; // すぐに買えない場合はリニューアルしない。車庫に列車が入って収益性が著しく悪化する場合がある
		}
		
		if(engineSet == null) {
			HgLog.Warning("No usable engineSet ("+AIRail.GetName(GetRailType())+") "+this);
			return;
		}
		foreach(engineVehicle, v in engineVehicles) {
			if(/*AIVehicle.GetAge(engineVehicle) >= 365 登れないとかtransfer追加とかすぐ変えないといけない時がある&&*/ (!HasVehicleEngineSet(engineVehicle,engineSet) || AIVehicle.GetAgeLeft (engineVehicle) <= 600)) {
				if(isBiDirectional || AIVehicle.GetCargoLoad(engineVehicle,cargo) == 0) {
					//HgLog.Info("SendVehicleToDepot(renewal or age):"+engineVehicle+" "+this);
					SendVehicleToDepot(engineVehicle);
				}
			}
		}
	}
	
	// 稀に不一致でもtrueを返しうる。厳密に行うとパフォーマンスに影響しそうなので今のところそのままに
	function HasVehicleEngineSet(vehicle, engineSet) {
		if(engineSet == null) { // 作れるlocoが無くなるとnullになる
			return true;
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
		return true;
	}
	
	function SendVehicleToDepot(vehicle) {
		if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
			if(IsBiDirectional() || returnRoute != null) {
				AIVehicle.SendVehicleToDepot (vehicle);
			} else {
				if(AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
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
		if(lastConvertRail != null && AIDate.GetCurrentDate() < lastConvertRail + 15 * 365) {
			// 一度コンバートしてから15年間はkeep
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
				}
			} else {
				StartUpdateRail(newRailType);
				if(additionalRoute != null) {
					additionalRoute.StartUpdateRail(newRailType);
				}
			}
		}
	}
	

	function CheckClose() {
		if(isRemoved) {
			return;
		}
		if(srcHgStation.place != null && srcHgStation.place.IsClosed()) {
			HgLog.Warning("Route Remove (src place closed)"+this);
			Remove();
			return;
		}
	
		if(IsTransfer()) {
			local destRoute = GetDestRoute();
			if(destRoute == false) {
				Remove();
				return;
			}
			if(isClosed) {
				if(!destRoute.IsClosed()) {
					ReOpen();
				}
			} else {
				if(destRoute.IsClosed()) {
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
				local accepting = false;
				foreach(cargo in GetCargos()) {
					if(destHgStations[acceptableStationIndex].stationGroup.IsAcceptingCargo(cargo)) {
						accepting = true;
						break;
					}
				}
				if(accepting) {
					if(acceptableStationIndex == currentStationIndex) {
						break;
					}
					// TODO return routeの問題
					ChangeDestination(destHgStations[acceptableStationIndex]);
					break;
				}
			}
			if(currentStationIndex != acceptableStationIndex && currentStationIndex == destHgStations.len()-1) {
				lastDestClosedDate = AIDate.GetCurrentDate();
				//CheckStockpiled();
			}
			
			if(isClosed) {
				if(acceptableStationIndex != -1) {
					ReOpen();
				}
			} else {
				if(acceptableStationIndex == -1) {
					if(destHgStations[destHgStations.len()-1].place != null && destHgStations[destHgStations.len()-1].place.IsClosed()) {
						HgLog.Warning("Route Remove (dest place closed)"+this);
						Remove(); //TODO 最終以外が単なるCloseの場合、Removeは不要。ただしRemoveしない場合、station.placeは更新する必要がある。レアケースなのでとりあえずRemove
					} else {
						if(!HogeAI.Get().ecs) { //ソース元の生産の健全性を保つため一時的クローズはしない(ECS)
							Close();
						}
					}
				}
			}
		}
	}
	
	function NotifyAddTransfer() {
		Route.NotifyAddTransfer();
		engineSetsCache = null;
	}
	
}

class TrainReturnRoute extends Route {
	srcHgStation = null;
	destHgStation = null;
	srcArrivalPath = null;
	srcDeparturePath = null;
	destArrivalPath = null;
	destDeparturePath = null;

	subCargos = null;
	originalRoute = null;
	
	constructor(srcHgStation, destHgStation, srcArrivalPath, srcDeparturePath, destArrivalPath, destDeparturePath) {
		Route.constructor();
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
		t.subCargos <- subCargos;
		return t;
	}
	
	static function Load(t) {
		local result = TrainReturnRoute(
			HgStation.worldInstances[t.srcHgStation],
			HgStation.worldInstances[t.destHgStation],
			BuildedPath(Path.Load(t.srcArrivalPath)),
			BuildedPath(Path.Load(t.srcDeparturePath)),
			BuildedPath(Path.Load(t.destArrivalPath)),
			BuildedPath(Path.Load(t.destDeparturePath)));
		result.subCargos = t.subCargos;
		return result;
	}

	function Initialize() {
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
	}

	function Close() {
	}
	
	function ReOpen() {
	}
	
	function IsTransfer() {
		return false;
	}
	
	function IsBiDirectional() {

		return false;}
	
	function GetVehicleType() {
		return AIVehicle.VT_RAIL;
	}
	
	function NeedsAdditionalProducingCargo(cargo, orgRoute = null, isDest = false) {
		return originalRoute.NeedsAdditionalProducingCargo(cargo, orgRoute, isDest, srcHgStation);
	}
	
	function IsOverflow(isDest = false, hgStation = null) {
		if(hgStation == null) {
			hgStation = isDest ? destHgStation : srcHgStation;
		}
		return AIStation.GetCargoWaiting (hgStation.GetAIStation(), cargo) > originalRoute.GetOverflowQuantity();
	}
	
	function GetFinalDestPlace() {
		return destHgStation.place;
	}

	function IsClosed() {
		return originalRoute.IsClosed();
	}
	
	function IsRemoved() {
		return originalRoute.IsRemoved();
	}
	
	function IsBiDirectional() {
		return false;
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
	
	function GetCargos() {
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
	
	
	function GetFacilities() {
		return [srcHgStation, destHgStation, srcArrivalPath.path, srcDeparturePath.path, destArrivalPath.path, destDeparturePath.path];
	}
	
	function Remove(){
		PlaceDictionary.Get().RemoveRoute(this);
	}
	
	function RemovePhysically(){
		srcHgStation.Remove();
		destHgStation.Remove();
		srcArrivalPath.Remove();
		srcDeparturePath.Remove();
		destArrivalPath.Remove();
		destDeparturePath.Remove();
	}

	function NotifyChangeDestRoute() {
	}
	
	function _tostring() {
		return "ReturnRoute:"+destHgStation.GetName() + "<-"+srcHgStation.GetName()+"["+AICargo.GetName(cargo)+"]";
	}
}

class TrainRouteBuilder extends RouteBuilder {

	function GetRouteClass() {
		return TrainRoute;
	}

	function Build() {
		return HogeAI.Get().BuildRouteAndAdditional(dest,srcPlace,cargo);
	}
}
