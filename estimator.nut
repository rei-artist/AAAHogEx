
Estimation <- {
	function GetBaseCost() {
		if(HogeAI.Get().roiBase) {
			return price * vehiclesPerRoute + buildingCost;
		} else if(HogeAI.Get().buildingTimeBase) {
			return buildingTime;
		} else {
			return vehiclesPerRoute;
		}
	}

	function GetRouteCapacity(cargo, realVehicles = 0) {
		return GetCargoCapcity(cargo) * max(realVehicles, vehiclesPerRoute) * 30 / days;	
	}

	function GetMaxRouteCapacity(cargo) {
		if(rawin("maxRouteCapacity")) {
			return maxRouteCapacity; // common
		}
		//HgLog.Warning("GetMaxRouteCapacity:"+AICargo.GetName(cargo)+" maxVehicles:"+maxVehicles+" days:"+days+" "+this);
		//return GetCargoCapcity(cargo) * maxVehicles * 30 / days; // rail 小さくなりすぎる事がある
		if(length < 128 && platformLength != null && length/16 < platformLength-1) { // length < 8 tileの時
			return GetCargoCapcity(cargo) * min(128,platformLength*16) / length * maxVehicles * 30 / days; // rail
		} else {
			return GetCargoCapcity(cargo) * maxVehicles * 30 / days; // rail
		}
	}

	function GetCargoCapcity(cargo) {
		if(!cargoCapacity.rawin(cargo)) {
			return 0;
		} else {
			return cargoCapacity[cargo];
		}
	}
	
	function GetInterval() {
		return max(1,(cruiseDays + loadingTime) * 2 / maxVehicles);
	}

	function GetDepreciation() {// 減価償却
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			// inflationを考慮して都度価格を取る
			local n = rawin("numLoco") ? numLoco : 1;
			local age = AIEngine.GetMaxAge(engine) / 365;
			if(age == 0) return 0; //たぶんengineの生産ができないと0になる
			return AIEngine.GetPrice(engine) * n / age;
		} else {
			return 0;
		}
	}

	function CalculateIncome() {
		buildingTime = GetBuildingTime(); 
		local totalDays = max(1,cruiseDays * 2 + waitingInStationTime + loadingTime);
		local annualDeliver = totalCapacity * vehiclesPerRoute * 365 / totalDays;
		runningCostPerCargo = (annualDeliver == 0 ? 0 : runningCost * vehiclesPerRoute / annualDeliver) + additionalRunningCostPerCargo;
		runningCost += GetDepreciation();
		income = incomePerOneTime * 365 / totalDays;
		income = HogeAI.Get().futureIncomeRate * income / 100 - runningCost;
		routeIncome = income * vehiclesPerRoute - infrastractureCost - additionalRunningCostPerCargo * annualDeliver + additionalRouteIncome;
		value = GetValue();
		//HgLog.Warning("CalculateIncome "+GetExplain());
	}
	
	
	function AppendSubCargoIncome(subCargoEstimate, supportBuildingTime) {
		buildingTime += supportBuildingTime;
		//runningCost += subCargoEstimate.runningCost;
		//incomePerOneTime += subCargoEstimate.incomePerOneTime; // 列車周期が違うので単純には足せない
		routeIncome += subCargoEstimate.routeIncome;
		price += subCargoEstimate.price;
		cargoProduction.rawset(subCargoEstimate.cargo, subCargoEstimate.production);
	}

	function GetValue() {
		local lostOpportunity = 0;
		local usableMoney = HogeAI.Get().GetUsableMoney();
		local yearlyIncome = HogeAI.Get().GetQuarterlyIncome(4);
		if(isBidirectional) {
			lostOpportunity = routeIncome / 2 * (cruiseDays + waitingInStationTime) / 365;
			lostOpportunity += routeIncome / 2 * (cruiseDays * 2 + loadingTime + waitingInStationTime) / 365;
		} else {
			lostOpportunity = routeIncome * (cruiseDays + waitingInStationTime) / 365;
		}
		local cost = max(1,price * vehiclesPerRoute + buildingCost + lostOpportunity);
		roi = routeIncome * 1000 / cost;
		local incomePerVehicle = routeIncome / (vehiclesPerRoute + additionalVehiclesPerRoute); 
		local incomePerBuildingTime = routeIncome / buildingTime;
		/*if(HogeAI.Get().IsInfrastructureMaintenance()) {
			return routeIncome * 1000 / max(1,infrastractureCost);
		} 無いほうが収益性が高いけれど、incomePerVehicleの時に収益性が落ちる問題がある*/
		return HogeAI.Get().GetValue(roi,incomePerBuildingTime,incomePerVehicle);
	}
	
	function EstimateAdditional( dest, src, infrastractureTypes, destinationRoute = null, sourceRoute = null, subCargo = false, notUseSupportRoutes = false, isMinSupport = false ) {
		/* 転送の終着地点が変わってしまうので誤見積もり if(HogeAI.Get().vehicleProfibitBase) { // このメソッドは必要な追加vehicle数を考慮していないので
			return;
		}*/
	
		local vehicleType = GetVehicleType();
		distance = AIMap.DistanceManhattan( dest.GetLocation(), src.GetLocation() );
		buildingTime = GetBuildingTime(); //TODO: Commonだと再計算されない
		
		if(destinationRoute == null && sourceRoute == null && (vehicleType == AIVehicle.VT_AIR || vehicleType == AIVehicle.VT_WATER)) {
			// 斜め経路ボーナス追加
			local p1 = src.GetLocation();
			local p2 = dest.GetLocation();
			local w = abs(AIMap.GetTileX(p1) - AIMap.GetTileX(p2));
			local h = abs(AIMap.GetTileY(p1) - AIMap.GetTileY(p2));
			local pathDistance = max(1,(min(w,h).tofloat() * 0.414 + max(w,h)).tointeger());
			if(p1==p2) {
				HgLog.Warning("EstimateAdditional dest==src");
				return;
			}
			cruiseDays = cruiseDays * pathDistance / AIMap.DistanceManhattan(p1,p2);
			if(vehicleType == AIVehicle.VT_WATER) {
				local landRate = WaterRoute.CheckLandRate(p1, p2, max(4,pathDistance/16) ) * 0.36;
				infraBuildingTime += (infraBuildingTime * landRate).tointeger();
				cruiseDays += (cruiseDays * landRate).tointeger();
			}
			CalculateIncome();
		}
		
		if(destinationRoute != null) {
			local isDest = dest == destinationRoute.destHgStation.stationGroup;
			local destStation = isDest ? destinationRoute.srcHgStation : destinationRoute.destHgStation;
			local dests = destStation.stationGroup.GetDests(cargo, destinationRoute.IsTransfer());
			if(dests.len()>=1) {
				local finalDest = dests[0]; //destinationRoute.GetFinalDestStation( null, dest );
				totalDistance = AIMap.DistanceManhattan( finalDest.GetLocation(), src.GetLocation() );
				additionalCruiseDays = destinationRoute.GetTotalCruiseDays(cargo);
				if(vehicleType == AIVehicle.VT_ROAD) {
					if(destinationRoute.GetVehicleType() == AIVehicle.VT_ROAD) {
						additionalCruiseDays += 50; // 道路=>道路の転送渋滞コスト
					}
				}
				additionalVehiclesPerRoute = destinationRoute.GetAdditionalVehicles(capacity * vehiclesPerRoute * 30 / days, cargo);
				if(destinationRoute instanceof TrainReturnRoute || (destinationRoute.IsBiDirectional() && destinationRoute.destHgStation.stationGroup == dest)) {
					additionalRunningCostPerCargo = 0;
				} else {
					local engineSet = destinationRoute.GetLatestEngineSet();
					additionalRunningCostPerCargo = engineSet != null ? engineSet.runningCostPerCargo : 0;
				}
				local place = finalDest.GetAcceptingPlace(cargo);
				//HgLog.Info("EstimateAdditional finalDest.GetAcceptingPlace:"+place+" destinationRoute:"+destinationRoute+" dest:"+dest+" src:"+src);
				if(place != null) {
					this.destRouteCargoIncome = place.GetDestRouteCargoIncome(cargo);
						 // 使われているかわからない * min(100 / (finalDestStation.place.GetUsedOtherCompanyEstimation()+1),70) / 100;
					this.additionalRouteIncome = place.GetAdditionalRouteIncome(cargo);
					//HgLog.Info("EstimateAdditional destRouteCargoIncome:"+destRouteCargoIncome);
				}
				Estimate();
			}
			//HgLog.Warning("EstimateAdditional Estimate:"+this+" "+AICargo.GetName(cargo)+" "+dest.GetName()+"<-"+src.GetName());
			
		} else if(sourceRoute != null) {
			local isDest = src == sourceRoute.srcHgStation.stationGroup;
			local srcStation = isDest ? sourceRoute.destHgStation : sourceRoute.srcHgStation;
			local latestEngineSet = sourceRoute.GetLatestEngineSet();
			if(latestEngineSet != null && srcStation.stationGroup != null) {
				AppendSources(srcStation.stationGroup.GetLocation(), latestEngineSet.cruiseDays, dest);
				Estimate();
			}
		} else {
			local oldTotalDistance = totalDistance; // cargo距離
			totalDistance = AIMap.DistanceManhattan( dest.GetLocation(), src.GetLocation() ); // より正確なcargo距離
			cruiseDays = cruiseDays * totalDistance / oldTotalDistance;
			if(dest instanceof Place) {
				local destRouteCargoIncome = dest.GetDestRouteCargoIncome(cargo);
				local additionalRouteIncome = dest.GetAdditionalRouteIncome(cargo); // 新種cargoで増える分
				if(destRouteCargoIncome > 0 || additionalRouteIncome > 0) {
					this.destRouteCargoIncome = destRouteCargoIncome; // 使われているかわからない * min(100 / (dest.GetUsedOtherCompanyEstimation()+1),70) / 100; // TODO: 複数路線
					this.additionalRouteIncome = additionalRouteIncome;
//					Estimate();
				}
			}
			Estimate();
		}
		if( !notUseSupportRoutes && HogeAI.Get().buildingTimeBase ) {
			if(src instanceof Place) {
				local supportEstimate = src.GetSupportEstimate(isMinSupport); //GetSupportRouteEstimate(GetMaxRouteCapacity(cargo));
				if(supportEstimate.production > 0) {
					//HgLog.Warning("AppendSupportRouteEstimate "+AICargo.GetName(cargo)+" "+dest.GetName()+"<-"+src.GetName());	
					AppendSupportRouteEstimate(src, cargo, supportEstimate);
				}
			}
		}
		if(!subCargo && !isMinSupport && vehicleType == AIVehicle.VT_RAIL) { // 列車は別のcargoも同時に運べる
			foreach(eachCargo in src.GetProducingCargos()) {
				//HgLog.Warning("additional.EstimateAdditional GetProducingCargos:"+AICargo.GetName(eachCargo)+" "+AICargo.GetName(cargo)+" "+dest.GetName()+"<-"+src.GetName());
				if(eachCargo != cargo && dest.IsAcceptingCargo(eachCargo)) {
					//HgLog.Warning("additional.EstimateAdditional IsAcceptingCargo:"+AICargo.GetName(eachCargo)+" "+dest.GetName()+"<-"+src.GetName());
					local production = notUseSupportRoutes ? src.GetCurrentExpectedProduction(eachCargo, vehicleType) : src.GetExpectedProduction(eachCargo, vehicleType);
					local additional = Route.Estimate( vehicleType, eachCargo, distance, production, isBidirectional, infrastractureTypes );
					if(additional != null && additional.routeIncome > 0) {
						additional = clone additional;
						local orgBuildingTime = additional.buildingTime;
						additional.EstimateAdditional( dest, src, infrastractureTypes, destinationRoute, sourceRoute, true, notUseSupportRoutes);
						AppendSubCargoIncome(additional, notUseSupportRoutes ? 0 : additional.buildingTime - orgBuildingTime);
					} else {
						//HgLog.Warning("additional.EstimateAdditional false "+additional+" "+dest.GetName()+"<-"+src.GetName());
					}
				}
			}
			value = GetValue(); //routeIncome * 100 / buildingTime;
		}
	}
	
	function AppendSupportRouteEstimate( srcPlace, cargo, supportEstimate ) {
		if(supportEstimate.production > 0) {
			routeIncome += supportEstimate.routeIncome;
			buildingTime += supportEstimate.buildingTime;
			value = routeIncome / buildingTime;		
		}
	}
	
	function AppendCruiseDistance( cruiseDistance ) {
		cruiseDays = cruiseDays * cruiseDistance / distance;
	}

	function AppendSources(srcCenterTile, srcCruiseDays, dest) {
		totalDistance = AIMap.DistanceManhattan(dest.GetLocation(), srcCenterTile);
		cruiseDays += srcCruiseDays;
		if(dest instanceof Place) {
			this.destRouteCargoIncome = dest.GetDestRouteCargoIncome(cargo);
			this.additionalRouteIncome = dest.GetAdditionalRouteIncome(cargo);
		}
	}
	
	function EstimateOneWay( onewayEstimate ) {
		routeIncome += onewayEstimate.routeIncome;
		vehiclesPerRoute += onewayEstimate.vehiclesPerRoute;
		value = GetValue();
	}
	
	
	function GetTotalProduction() {
		local result = 0;
		foreach(cargo, production in cargoProduction) {
			result += production;
		}
		return result;
	}
	
	function GetExplain() {
		//local lostOpportunity = routeIncome * (cruiseDays + waitingInStationTime) / 365;
		local cost = max(1,price * vehiclesPerRoute + buildingCost/* + lostOpportunity*/);
		return  value + " roi:"+roi+"("+cost/*(price * vehiclesPerRoute)+","+buildingCost*/+")"
//			+ " income:"+income+" rc:"+runningCost+" ic:"+infrastractureCost+" ad:"+(capacity * vehiclesPerRoute * 365 / (days + waitingInStationTime - loadingTime))
			+ " route:"+routeIncome+"("+incomePerOneTime+(incomePerOneTimeReturn>=1?","+incomePerOneTimeReturn:"")+")"
			+ " speed:"+cruiseSpeed + "("+ cruiseDays + (additionalCruiseDays!=0?"+" + additionalCruiseDays:"")+","+waitingInStationTime + "d)"
			+ " TD:"+totalDistance+"("+distance+") DRCI:"+destRouteCargoIncome+(additionalRouteIncome>=1?"("+additionalRouteIncome+")":"")
			+ " ARC:"+additionalRunningCostPerCargo + " BT:" + buildingTime;
	}
}

CommonEstimation <- delegate Estimation : {
	function GetVehicleType() {
		return vehicleType;
	}

	function Estimate() {
		local ratedProduction = production * stationRate / 255;
		local deliverableProduction = min(ratedProduction , maxRouteCapacity );

		vehiclesPerRoute = max( min( maxVehicles, deliverableProduction * 12 * days / ( 365 * capacity ) + 1 ), 1 );
		
		local interval = (cruiseDays * 2 + loadingTime)  / vehiclesPerRoute;
		local intervalStock;
		
		if(interval <= 10) {
			intervalStock = ratedProduction * days / 30 / vehiclesPerRoute;
			waitingInStationTime = max(loadingTime, max(0,capacity - intervalStock) * 30 / ratedProduction);
		} else {
			local rateStock = CargoUtils.GetStationRateStock(cargo, production, stationRate, vehicleType, maxSpeed, days / vehiclesPerRoute);
			waitingInStationTime = max(loadingTime, 
				CargoUtils.GetStationRateWaitTimeFullLoad(production, rateStock[0], max(0, capacity - rateStock[1]), maxSpeed)[1]);
			intervalStock = rateStock[1];
		}
		
		
		//local waitingInStationTime = max(loadingTime, (capacity * vehiclesPerRoute - (inputProduction * stationRate / 100 * min(60,days)) / 30)*30 / inputProduction / vehiclesPerRoute );
		local cargoIncome = AICargo.GetCargoIncome( cargo, totalDistance, cruiseDays + additionalCruiseDays);
		
		incomePerOneTime = (cargoIncome + destRouteCargoIncome) * capacity;
		if(isBidirectional) {
			if(vehicleType == AIVehicle.VT_AIR) {
				incomePerOneTimeReturn = cargoIncome * capacity; // dest側も満タン待機
			} else {
				incomePerOneTimeReturn = cargoIncome * min(capacity, intervalStock);
			}
		} else {
			incomePerOneTimeReturn = 0;
		}

		if( vehicleType == AIVehicle.VT_AIR && cargo == HogeAI.GetPassengerCargo() && isBidirectional) {
			// TODO: もっと汎用的にすべきかも
			local mailCargoIncome = AICargo.GetCargoIncome( HogeAI.GetMailCargo(), totalDistance, cruiseDays + additionalCruiseDays);
			local mailCapacity = Air.Get().GetMailSubcargoCapacity(engine);
			incomePerOneTime += mailCargoIncome * mailCapacity;
			incomePerOneTimeReturn += mailCargoIncome * mailCapacity;
		}

		incomePerOneTime += incomePerOneTimeReturn;
		cargoIncomes = {};
		cargoIncomes.rawset(cargo,cargoIncome);


		CalculateIncome();
	}
	
	function GetBuildingTime() {
		return infraBuildingTime + vehiclesPerRoute * Estimator.buildingTimePerVehicle;
	}
	
	function _tostring() {
		local explain = GetExplain();
		local productionString = "";
		foreach(cargo,production in cargoProduction) {
			productionString += (productionString.len() >= 1 ? "," : "") + production
				+ "/"	+ (cargoCapacity.rawin(cargo)?cargoCapacity[cargo]:0)+"["+AICargo.GetName(cargo)+"]";
		}
		explain += " (" + productionString + ")x"+vehiclesPerRoute;
		explain += " "+AIEngine.GetName(engine);

		return explain;
	}
}

TrainEstimation <- delegate Estimation : {
	
	function GetVehicleType() {
		return AIVehicle.VT_RAIL;
	}

	function Estimate() {
		vehiclesPerRoute = 1;
		if(!isSingle) {
			foreach(cargo,capacity in cargoCapacity) {
				if(capacity == 0) {
					continue;
				}
				local production = cargoProduction[cargo];
				if(!cargoIsTransfered.rawin(cargo)) {
					production = production * stationRate / 255;
				}
				vehiclesPerRoute = max( vehiclesPerRoute, production * 12 * days / ( 365 * capacity ) + 1 );
//								HgLog.Info("p:"+production+" stationRate:"+stationRate+" days:"+days+" c:"+capacity+" v:"+vehiclesPerRoute+" cargo:"+AICargo.GetName(cargo));
			}

			vehiclesPerRoute = min( vehiclesPerRoute, maxVehicles );
			vehiclesPerRoute = max( vehiclesPerRoute, 1);
			vehiclesPerRoute ++;
		}
		waitingInStationTime = 10000;
		local interval = (cruiseDays * 2 + loadingTime)  / vehiclesPerRoute; // 列車の場合、isSingleでなければ誰か駅に居る //
		local baseRate = stationRate - (vehiclesPerRoute == 1 ? min(max(0,interval-7) * 4 / 5,130) : 0);
		local maxSpeed = AIEngine.GetMaxSpeed(engine);
		if(interval > 10000) {
			HgLog.Warning("cruiseDays:"+cruiseDays+" loadingTime:"+loadingTime+" vehiclesPerRoute:"+vehiclesPerRoute+" interval:"+interval);
		}
		
		cargoRateStock = {};
		foreach(cargo,capacity in cargoCapacity) {
			local production = cargoProduction[cargo];
			if(production == 0) {
				continue;
			}
			local waitTime;
			if(cargoIsTransfered.rawin(cargo)) {
				local stock = production * interval / 30;
				waitTime = (capacity - stock) * 30 / production;
			} else {
				local rateStock = CargoUtils.GetStationRateStock(cargo, production, baseRate, AIVehicle.VT_RAIL, maxSpeed, interval);
				if(vehiclesPerRoute == 1) {
					local rateWaitTime = CargoUtils.GetStationRateWaitTimeFullLoad(production, rateStock[0], max(0,capacity - rateStock[1]), maxSpeed);
					waitTime = rateWaitTime[1];
				} else {
					waitTime = max(0,capacity - rateStock[1]) * 30 * 255 / (production * baseRate);
				}
				//HgLog.Info("rate:"+rateStock[0]*100/255+" prod:"+production+" stock:"+rateStock[1]+"/"+capacity+" waitTime:"+waitTime+" vehiclesPerRoute:"+vehiclesPerRoute+" interval:"+interval);
				cargoRateStock.rawset(cargo,rateStock);
			}
			
			/*
			rateStock = CargoUtils.GetStationRateStock(cargo, production, rateWaitTime[0], AIVehicle.VT_RAIL, maxSpeed, interval);
			rateWaitTime = CargoUtils.GetStationRateWaitTimeFullLoad(production, rateStock[0], max(0,capacity - rateStock[1]), maxSpeed);
			rateStock = CargoUtils.GetStationRateStock(cargo, production, rateWaitTime[0], AIVehicle.VT_RAIL, maxSpeed, interval);*/
			waitingInStationTime = min(max(loadingTime,waitTime), waitingInStationTime);
		}
		if(waitingInStationTime > days && vehiclesPerRoute >= 3) {
			vehiclesPerRoute --; // 2編成以上が同時に待つ事になるので減らす
		}


		/*
		if(!isSingle && minWaitingInStationTime > loadingTime) {
			minWaitingInStationTime *= 2;
		}*/
		//HgLog.Info("minWaitingInStationTime:"+minWaitingInStationTime);
		incomePerOneTime = 0;
		cargoIncomes = {};
		local totalDeliver = 0;
		foreach(cargo,capacity in cargoCapacity) {
			local production = cargoProduction[cargo];
			if(production == 0) {
				continue;
			}
			/*if(maxSpeed > 85) {
				productionPerDay += productionPerDay / 60 * min((maxSpeed-85) / 4, 17);
			}*/
			local deliver;
			local deliverReturn;
			if(cargoIsTransfered.rawin(cargo)) {
				local stock = production * interval / 30;
				deliver = min(capacity, waitingInStationTime * production / 30 + stock);
				deliverReturn = min(capacity, stock);
			} else {
				local rateStock = cargoRateStock[cargo];
				//local intervalStored = (min(30,days / maxVehiclesPerRoute) * productionPerDay).tointeger();
				deliver = min(capacity, rateStock[1] + CargoUtils.GetReceivedProduction(production, rateStock[0], waitingInStationTime, maxSpeed));
				deliverReturn =  min(capacity, rateStock[1].tointeger());
			}
			
			//HgLog.Info("cargo:"+AICargo.GetName(wagonEngineInfo.cargo)+" cruiseSpeed:"+cruiseSpeed+" deliver:"+deliver+" capacity:"+capacity+" productionPerDay:"+productionPerDay);
			/*income += CargoUtils.GetCargoIncome(distance, wagonInfo.cargo, cruiseSpeed, minWaitingInStationTime, isBidirectional) * deliver
				- wagonInfo.runningCost * wagonInfo.numWagon;*/
			local cargoIncome = AICargo.GetCargoIncome( cargo, totalDistance, cruiseDays + additionalCruiseDays );
			totalDeliver += deliver;
			incomePerOneTime += (cargoIncome + destRouteCargoIncome) * deliver;
			incomePerOneTimeReturn = !isBidirectional ? 0 : cargoIncome * deliverReturn;
			incomePerOneTime += incomePerOneTimeReturn;
			cargoIncomes.rawset( cargo, cargoIncome + destRouteCargoIncome ); // cascadeで出力ルートからの収入も加算

			//HgLog.Info("income:"+income);
		}
		intervalStored = cargoRateStock.rawin(cargo) ? cargoRateStock[cargo][1] : 0;
		
		CalculateIncome();
		
	}
	
	function GetBuildingTime() {
		//local result = 470 + distance * 2;
		local result = 200 + max(100,distance * 4);
		if(isSingle) {
			result = result * 6 / 10;
		}
		return (result + Estimator.buildingTimePerVehicle * vehiclesPerRoute);// / 2; // Railはマルチカーゴができるので有利
	}
	

	function _tostring() {
		local explain = GetExplain();
		explain += " wt:"+waitingInStationTime + "," + loadingTime + "("+intervalStored+")";
		explain += " acc:"+acceleration+","+startDays+"("+slopes+")";
		local productionString = "";
		foreach(cargo,production in cargoProduction) {
			productionString += (productionString.len() >= 1 ? "," : "") + production
				+ "/"	+ (cargoCapacity.rawin(cargo)?cargoCapacity[cargo]:0)+"/"+(cargoIncomes.rawin(cargo)?cargoIncomes[cargo]:0)+"["+AICargo.GetName(cargo)+"]";
		}
		explain += " (" + productionString + ")x"+vehiclesPerRoute;
		explain += " "+AIEngine.GetName(trainEngine);
		if(numLoco>=2) {
			explain += "x"+numLoco;
		}
		foreach(wagonEngineInfo in wagonEngineInfos) {
			explain += "-"+AIEngine.GetName(wagonEngineInfo.engine)+"x"+wagonEngineInfo.numWagon;
		}
		if(isSingle) {
			explain += "(single)";
		}
		return explain;
	}
}

class Estimator {
	static buildingTimePerVehicle = 3;
	
	route = null;
	
	function GetBuildingTime(distance, infrastracture) {
		// 恣意的だが、場所がなくなる前にrailを作った方が有利な事が多い
		switch(GetVehicleType()) {	//return distance / 2 + 100; // TODO expectedproductionを満たすのに大きな時間がかかる
			case AIVehicle.VT_WATER:
		//		return (pow(distance / 20,2) + 150).tointeger(); //TODO: 海率によって異なる
		//		return distance * 2 + 1800; //TODO: 海率によって異なる
				if(infrastracture == WaterRoute.IF_CANAL) {
					//return (250 + pow(distance,1.5) / 5).tointeger();
					return 125 + distance * 2 + min(distance,30);
					//return 150 + distance;
				} else {
					//return (125 + pow(distance,1.5) / 5).tointeger();
					return 125 + distance * 2;
					//return 70 + distance;
				}
				local x = distance / 10;
				return x*x / 5 + x / 5 + 6;
				
			case AIVehicle.VT_ROAD:
	//		return distance + 1200;
				if(HogeAI.Get().IsInfrastructureMaintenance()) {
					return 125 + distance * 3;
				} else {
					return 125 + distance * 3;
				}
			case AIVehicle.VT_AIR:
				return 300;
		}
		assert(false);
	}

	function SetTransferParams() {
		local destRoute = route.GetDestRoute();
		if(route.IsTransfer() && destRoute != false) {
			totalDistance = AIMap.DistanceManhattan( route.GetFinalDestStation().GetLocation(), route.srcHgStation.GetLocation() );
			additionalCruiseDays = destRoute.GetTotalCruiseDays();
			if(GetVehicleType() == AIVehicle.VT_ROAD) {
				if(destRoute.GetVehicleType() == AIVehicle.VT_ROAD) {
					additionalCruiseDays += 10; // 道路=>道路の転送渋滞コスト
				}
			}
			if(additionalCruiseDays == null) {
				additionalCruiseDays = 0;
			}
			local engineSet = destRoute.GetLatestEngineSet();
			additionalRunningCostPerCargo = engineSet != null ? engineSet.runningCostPerCargo : 0;
		} else {
			totalDistance = distance;
			additionalCruiseDays = 0;
			additionalRunningCostPerCargo = 0;
		}
	}
	
	function SetRouteCargoIncome(cargo) {
		local finalDestPlace = route.GetFinalDestPlace();
		if(finalDestPlace != null) {
			destRouteCargoIncome = finalDestPlace.GetDestRouteCargoIncome(cargo) / 2;
		} else {
			destRouteCargoIncome = 0;
		}
	}

	function GetMaxBuildingCost(infrastractureMaintenanceCost) {
		local incomeOneYear = max(0, HogeAI.Get().GetQuarterlyIncome(4) - infrastractureMaintenanceCost);
		return HogeAI.Get().GetUsableMoney() + incomeOneYear * 5;
	}
	

	function GetBuildingCost(infrastractureType, distance, cargo) {
		switch(GetVehicleType()) {
			case AIVehicle.VT_RAIL:
				local demolishFarm = HogeAI.GetInflatedMoney(540) * 40 / 100;
				local cost = (AIRail.GetBuildCost(infrastractureType, AIRail.BT_TRACK)*2 + demolishFarm) * 2 * distance;
				cost += AIRail.GetBuildCost(infrastractureType, AIRail.BT_TRACK) * 220 + Route.GetPaxMailTransferBuildingCost(cargo);
				return cost;
		//		return distance * railCost/*HogeAI.Get().GetInflatedMoney(720)*/ +HogeAI.Get().GetInflatedMoney( CargoUtils.IsPaxOrMail(cargo) ? 30000 : 20000);

			case AIVehicle.VT_WATER:
				local cost = 0; 
				if(infrastractureType == WaterRoute.IF_CANAL) {
					cost = 100000; // 失敗分も加味。TODO 実際には測定した方がいいかもしれない
		/*			if(HogeAI.Get().roiBase) {
						cost += 100000; 
					}*/
				} else {
					cost = 4000;
				}
				
				cost = HogeAI.Get().GetInflatedMoney(cost);
				cost += Route.GetPaxMailTransferBuildingCost(cargo);
				return cost;
				
			case AIVehicle.VT_ROAD:
				local demolishFarm = HogeAI.GetInflatedMoney(540) * 40 / 100;
				local cost = AIRoad.GetBuildCost(infrastractureType, AIRoad.BT_ROAD);
				cost = ((cost * 2) + demolishFarm) * distance;
				cost += HogeAI.GetInflatedMoney(4000) + Route.GetPaxMailTransferBuildingCost(cargo);
		//		cost += HogeAI.GetInflatedMoney(CargoUtils.IsPaxOrMail(cargo) ? (!HogeAI.Get().IsDistantJoinStations() ? 25000 : 3500) : 2000);
				 return cost;
				 
			case AIVehicle.VT_AIR:
				local airportTraints = Air.Get().GetAiportTraits(infrastractureType);
				return HogeAI.Get().GetInflatedMoney(airportTraints.cost) * 2 * 2 /*整地とかの分*/ + Route.GetPaxMailTransferBuildingCost(cargo);
		}
	
	}
}

class CommonEstimator extends Estimator {

	cargo = null;
	distance = null;
	production = null;
	isBidirectional = null;
	infrastractureTypes = null;
	isTownBus = null;
	
	// optional
	totalDistance = null;
	additionalCruiseDays = null;
	additionalRunningCostPerCargo = null;
	destRouteCargoIncome = null;

	constructor(route) {
		this.route = route; // routeはclassの事がある
		this.additionalCruiseDays = 0;
		this.additionalRunningCostPerCargo = 0;
	}

	function GetVehicleType() {
		return route.GetVehicleType();	
	}

	function Estimate() {
		local engineSets = GetEngineSetsVt();
		if(engineSets.len() >= 1) {
			return engineSets[0];
		} else {
			return null;
		}
	}
	
	
	function GetEngineSetsVt() {
		local self = route;
		local isRouteInstance = (typeof self) == "instance" && self instanceof Route;
		
		local vehicleType = route.GetVehicleType();
		if(distance == 0) {
			return [];
		}
		if(totalDistance == null) {
			if(isRouteInstance) {
				SetTransferParams();
			} else {
				totalDistance = distance;
			}
		}
		if(destRouteCargoIncome == null) {
			if(isRouteInstance) {
				SetRouteCargoIncome(cargo);
			} else {
				destRouteCargoIncome = 0;
			}
		}
		
		
		
		//HgLog.Info("typeof:self="+(typeof self)+" "+self);
		
		local vehiclesRoom = self.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType);
		//HgLog.Info("vehiclesRoom="+vehiclesRoom);
		local useReliability = HogeAI.Get().IsEnableVehicleBreakdowns();
		local breakdownDifficulty = HogeAI.Get().GetVehicleBreakdownDifficulty();
		local engineList = AIEngineList(vehicleType);
		engineList.Valuate(AIEngine.CanRefitCargo, cargo);
		engineList.KeepValue(1);
		
		if(vehicleType == AIVehicle.VT_ROAD) {
			if(isRouteInstance) {
				engineList.Valuate(AIEngine.HasPowerOnRoad, self.GetRoadType());
				engineList.KeepValue(1);
			} else {
				if(isTownBus || HogeAI.Get().IsDisableTrams()) {
					engineList.Valuate(AIEngine.HasPowerOnRoad, TownBus.GetRoadType());
					engineList.KeepValue(1);
				}
				if(HogeAI.Get().IsDisableRoad()) {
			//local roadType = AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin();
					engineList.Valuate(AIEngine.HasPowerOnRoad, AIRoad.ROADTYPE_TRAM);
					engineList.KeepValue(1);
				}
			}
		}
		
		if(vehicleType == AIVehicle.VT_AIR) {
			if(isRouteInstance && self instanceof AirRoute) {
				local usableBigPlane = Air.Get().GetAiportTraits(self.srcHgStation.airportType).supportBigPlane 
								&& Air.Get().GetAiportTraits(self.destHgStation.airportType).supportBigPlane;	
				
				if(!usableBigPlane) {
					engineList.Valuate( AIEngine.GetPlaneType );
					engineList.RemoveValue(AIAirport.PT_BIG_PLANE );
				}
			}
		}
		
		local orderDistance;
		if(isRouteInstance) {
			orderDistance = AIOrder.GetOrderDistance(self.GetVehicleType(), self.srcHgStation.platformTile, self.destHgStation.platformTile);
			vehiclesRoom += self.GetVehicleList().Count();
		} else {
			local x;
			local y;
			if(distance < AIMap.GetMapSizeX()-2) {
				x = distance + 1;
				y = 1;
			} else {
				x = AIMap.GetMapSizeX()-2;
				y = min(AIMap.GetMapSizeY()-2, distance - x + 1);
			}
			AIMap.GetMapSizeY()
			orderDistance = AIOrder.GetOrderDistance(self.GetVehicleType(), AIMap.GetTileIndex(1,1), AIMap.GetTileIndex(x,y));
		}
		local pathDistance;
		if(isRouteInstance) {
			pathDistance = self.GetPathDistance();
		} else {
			pathDistance = distance;
		}
		local ignoreIncome = false;
		if(isRouteInstance) {
			ignoreIncome = self.IsSupport(); // 短路線がマイナス収支で成立しなくなる。 TODO: 転送先とトータルで収益計算しないといけない。
		}
		/*
		if(!ignoreIncome && CargoUtils.IsSupplyCargo(cargo)) {
			ignoreIncome = true;
		}*/
		
		engineList.Valuate( function(e):(orderDistance) {
			local d = AIEngine.GetMaximumOrderDistance(e);
			if(d == 0) {
				return 1;
			} else {
				return d > orderDistance ? 1 : 0;
			}
		} );
		engineList.KeepValue(1);
		
		production = max(10, production);
		
		local isBuildingEstimate = !isTownBus && !isRouteInstance /*建設前の見積*/
		local maxBuildingCost = isBuildingEstimate ? GetMaxBuildingCost(0) : 0;	
		
		local infrastractureEstimations = {};
		
		local result = [];
		foreach(e,_ in engineList) {
			local capacity = self.GetEngineCapacity(self,e,cargo);
			if(capacity == 0) {
				continue;
			}
			/* うまくいかない　TODO　実際に坂道で渋滞しているかどうかの検知
			if(vehicleType == AIVehicle.VT_ROAD) {
				if(!RoadRoute.CanGoUpSlope(e,cargo,capacity)) {
					continue;
				}
			}*/
			local stationRate = CargoUtils.GetStationRate(AIEngine.GetMaxSpeed(e)) + 170;
			foreach(engineInfrastractureType in self.GetInfrastractureTypes(e)) {
				if(infrastractureTypes != null) {
					if(ArrayUtils.Find(infrastractureTypes, engineInfrastractureType) == null) {
						continue;
					}
				}
				local infrastracture = null;
				if(!infrastractureEstimations.rawin(engineInfrastractureType)) {
					infrastracture = {
						maxSpeed = self.GetInfrastractureSpeed( engineInfrastractureType )
						maintenanceCost = self.GetInfrastractureCost( engineInfrastractureType, distance )
						buildingCost = isTownBus/*これが無いと無限再帰ループする*/ ? 0 : GetBuildingCost( engineInfrastractureType, distance, cargo )
					}
					infrastractureEstimations.rawset(engineInfrastractureType, infrastracture);
				} else {
					infrastracture = infrastractureEstimations.rawget(engineInfrastractureType);
				}
				
			
				local infraBuildingTime = GetBuildingTime(pathDistance, engineInfrastractureType);
				local runningCost = AIEngine.GetRunningCost(e);
				local cruiseSpeed;
				local maxSpeed = AIEngine.GetMaxSpeed(e);
				if(vehicleType == AIVehicle.VT_AIR) {
					cruiseSpeed = maxSpeed;
				} else {
					if(vehicleType == AIVehicle.VT_ROAD) {
						cruiseSpeed = RoadRoute.GetRoadCruiseSpeed(e,cargo,capacity);
						//HgLog.Warning("GetRoadCruiseSpeed:"+cruiseSpeed+" "+AIEngine.GetName(e)+" "+AICargo.GetName(cargo));
					} else {
						cruiseSpeed = maxSpeed;
					}
					cruiseSpeed = max( 4, cruiseSpeed * (100 + (useReliability ? AIEngine.GetReliability(e) / breakdownDifficulty : 100)) / 200);
				}
				local infraSpeed = infrastracture.maxSpeed;
				if(infraSpeed >= 1) {
					cruiseSpeed = min(infraSpeed, cruiseSpeed);
				}
				/*
				if(vehicleType == AIVehicle.VT_ROAD && HogeAI.Get().roadTrafficRate != null) { 新規路線を作らなくなってしまい逆に不利
					cruiseSpeed = (cruiseSpeed * HogeAI.Get().roadTrafficRate).tointeger();
				}*/
				
				local maxVehicles = self.EstimateMaxVehicles(self, pathDistance, cruiseSpeed);
				/*
				if(self.IsSupportModeVt(vehicleType) && self.GetMaxTotalVehicles() / 2 < AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, vehicleType)) {
					maxVehicles = min(maxVehicles, 10); // ROADはなるべく少ない車両数で済ませられる見積をするため
				}*/
				maxVehicles = max(1,min(maxVehicles, vehiclesRoom));
				// This is the amount of cargo transferred per unit of time if using gradualloading. The default is 5 for trains and road vehicles, 10 for ships and 20 for aircraft. 
				// This amount of cargo is loaded to or unloaded from the vehicle every 40 ticks for trains, every 20 ticks for road vehicles and aircraft and every 10 ticks for ships.
				// this property is used for passengers, while mail uses 1/4 (rounded up). You can use callback 12 to control load amounts for passengers and mail independently.
				
				// train:5/40*74 road:10/20*74 air:20/20*74 water:20/10*74
				

		
				local loadingSpeed; // TODO: capacity/cargo/vehicleTypeによって異なる
				switch(vehicleType) {
					case AIVehicle.VT_ROAD:
						loadingSpeed = 18; //実測だとこれくらい。 37;
						if(CargoUtils.IsPaxOrMail(cargo)) loadingSpeed /= 2;
						break;
					case AIVehicle.VT_AIR:
						loadingSpeed = 74;
						break;
					case AIVehicle.VT_WATER:
						loadingSpeed = 148;
						break;
				}
				
				/* economy.cpp:1297
				bool air_mail = v->type == VEH_AIRCRAFT && !Aircraft::From(v)->IsNormalAircraft();
				if (air_mail) load_amount = CeilDiv(load_amount, 4);
				*/
		
				if(cargo == HogeAI.GetMailCargo() && vehicleType == AIVehicle.VT_AIR) {
					loadingSpeed /= 2; //実測では半分程度。機体毎に違うのかもしれない。
				}
				local loadingTime = max(1, (capacity+loadingSpeed-1) / loadingSpeed);
				
				/*if(vehicleType == AIVehicle.VT_ROAD) {
					loadingTime = CargoUtils.IsPaxOrMail(cargo) ? capacity / 6 : capacity / 10;
				} else {
					loadingTime = min(10, capacity / 10);
				}*/
				
				local realPathDistance = pathDistance;
				if(vehicleType == AIVehicle.VT_AIR) {
					realPathDistance += 30; // 着陸に必要な追加航路
					if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
						realPathDistance += 50; // depotへ行く
					}
				}

				local days;
				local avgBrokenDistance = null;
				local cruiseDays;
				if(vehicleType == AIVehicle.VT_AIR && cruiseSpeed > 80 && useReliability) {
					avgBrokenDistance = min(100 * realPathDistance / ( (AIEngine.GetReliability(e) / breakdownDifficulty * 150 / 100) * cruiseSpeed * 24 / 664), 100) * realPathDistance / (100 * 2);
					cruiseDays = VehicleUtils.GetDays(avgBrokenDistance,80) + VehicleUtils.GetDays(realPathDistance-avgBrokenDistance,cruiseSpeed);
					//local days2 = (pathDistance * 664 / cruiseSpeed / 24 + loadingTime) * 2;
					//HgLog.Info("debug: avgBrokenDistance:" + avgBrokenDistance + " d:"+pathDistance+" v:"+cruiseSpeed+" r:"+AIEngine.GetReliability(e)+" "+AIEngine.GetName(e));
				} else {
					cruiseDays = VehicleUtils.GetDays(realPathDistance,cruiseSpeed);
				}
				if(vehicleType == AIVehicle.VT_ROAD) cruiseDays += 4; // 両端の車庫分
				days = (cruiseDays + loadingTime) * 2;
				days = max(days,1);
				
				//ocal useTownBus = !isTownBus && TownBus.CanUse(cargo) && !HogeAI.Get().IsDistantJoinStations();
				local buildingCost = infrastracture.buildingCost;
				local maxRouteCapacity = self.EstimateMaxRouteCapacity( engineInfrastractureType, capacity );

				local price = AIEngine.GetPrice(e);	
				//HgLog.Warning("AIEngine.GetPrice:"+price + " "+AIEngine.GetName(e));
				if(maxBuildingCost > 0 && price > 0) {
					if(isBuildingEstimate) {
						local maxBuildingCostInfra = maxBuildingCost - infrastracture.maintenanceCost > 0 ? GetMaxBuildingCost(infrastracture.maintenanceCost) : 0;
						maxVehicles = maxBuildingCostInfra / price;
					} else {
						maxVehicles = maxBuildingCost / price;
					}
				}
				if(maxVehicles == 0) {
					continue;
				}
				local cargoCapacity = {};
				cargoCapacity.rawset(cargo,capacity);
				local cargoProduction = {};
				cargoProduction.rawset(cargo,production);
				
				local estimation = delegate CommonEstimation : {
					designedDate = AIDate.GetCurrentDate()
					engine = e
					vehicleType = vehicleType
					cargo = cargo
					production = production
					cargoProduction = cargoProduction
					infrastractureCost = infrastracture.maintenanceCost
					infraBuildingTime = infraBuildingTime
					destRouteCargoIncome = destRouteCargoIncome
					additionalRouteIncome = 0
					additionalCruiseDays = additionalCruiseDays
					additionalVehiclesPerRoute = 0
					additionalRunningCostPerCargo = additionalRunningCostPerCargo
					distance = distance
					totalDistance = totalDistance
					isBidirectional = isBidirectional
					infrastractureType = engineInfrastractureType
					price = price
					runningCost = runningCost
					maxSpeed = maxSpeed
					cruiseSpeed = cruiseSpeed
					cruiseDays = cruiseDays
					days = days
					capacity = capacity
					totalCapacity = capacity
					cargoCapacity = cargoCapacity
					buildingCost = buildingCost
					maxRouteCapacity = maxRouteCapacity
					maxVehicles = maxVehicles
					stationRate = stationRate
					loadingTime = loadingTime

					vehiclesPerRoute = null
					runningCostPerCargo = null
					waitingInStationTime = null
					buildingTime = null
					cargoIncomes = null
					incomePerOneTime = null
					incomePerOneTimeReturn = null
					income = null
					routeIncome = null
					roi = null
					value = null
				};
				
				estimation.Estimate();
				if(ignoreIncome || estimation.routeIncome >= 0) {
					result.push(estimation);
					//HgLog.Info("estimation:"+estimation+" "+self);
				} else {
					//HgLog.Info("routeIncome<0:"+estimation+" "+self);
					//HgLog.Warning("estimation:"+HgTable(estimation));
				}
				/*
				if(vehicleType == AIVehicle.VT_AIR && cargo==HogeAI.Get().GetPassengerCargo()) {
					HgLog.Info("test:"+avgBrokenDistance+"/"+realPathDistance+" "+estimation);
				}*/
			}
		}
		result.sort(function(a,b) {
			return b.value - a.value;
		});
		return result;
	}

}

class TrainEstimator extends Estimator {

	static wagonEnginesCache = ExpirationTable(90);

	cargo = null;
	cargoProduction = null;
	distance = null;
	isBidirectional = null;
	infrastractureTypes = null; // 未使用
	
	// optional
	totalDistance = null;
	additionalCruiseDays = null;
	additionalRunningCostPerCargo = null;
	destRouteCargoIncome = null;
	pathDistance = null;
	isRoRo = null;
	isTransfer = null;
	railType = null;
	checkRailType = null;
	platformLength = null;
	ignoreIncome = null;
	selfGetMaxSlopesFunc = null;
	maxSlopes = null;
	limitTrainEngines = null;
	limitWagonEngines = null;
	skipWagonNum = null;
	additonalTrainEngine = null;
	additonalWagonEngine = null;
	isSingleOrNot = null;
	isLimitIncome = null;
	cargoIsTransfered = null;
	forRawPlace = null;
	
	// result
	tooShortMoney = null;
	
	function _set(idx,value) {
		switch (idx) {
			case "production":
				cargoProduction.rawset(cargo,value);
				break;
			default: 
				throw("the index '" + idx + "' does not exist");
		}
	}
	
	constructor() {
		platformLength = null; //7; //AIGameSettings.GetValue("vehicle.max_train_length");
		isBidirectional = false;
		isTransfer = false;
		ignoreIncome = false;
		skipWagonNum = 1;
		checkRailType = false;
		isLimitIncome = true;
		isRoRo = true;
		if(!HogeAI.Get().roiBase) {
			limitWagonEngines = 2;
			limitTrainEngines = 5;
		} else {
			limitWagonEngines = 3;
			limitTrainEngines = 10;
		}
		additionalCruiseDays = 0;
		additionalRunningCostPerCargo = 0;
		cargoIsTransfered = {};
		cargoProduction = {};
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_RAIL;
	}
	
	function SetDestRoute( destRoute, dest, src ) {
		totalDistance = AIMap.DistanceManhattan( destRoute.GetFinalDestStation(null,dest).GetLocation(), src.GetLocation() );
		additionalCruiseDays = destRoute.GetTotalCruiseDays();
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
		wagonEngines.Valuate(AIEngine.IsBuildable);
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
		local trainEngineInfo = TrainInfoDictionary.Get().GetTrainInfo(trainEngine);
		foreach(e,_ in wagonEngines) {
			local wagonEngineInfo = TrainInfoDictionary.Get().GetTrainInfo(e);
			if(wagonEngineInfo != null) {
				wagonEngines.SetValue(e, wagonEngineInfo.isMultipleUnit == trainEngineInfo.isMultipleUnit ? 1 : 0);
			} else {
				wagonEngines.SetValue(e, 0);
			}
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
		if(wagonEngines.Count() == 0) {
			HgLog.Warning("Cannot get max speed wagon");
			return null;
		}
		local speed = wagonEngines.GetValue(wagonEngines.Begin());
		if(speed < maxSpeed * 3 / 4) {
			HgLog.Warning("too slow sub cargo wagon");
			return null;
		}
		wagonEngines.KeepValue(speed);
		wagonEngines.Valuate(function(e):(subCargo) {
			local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(e);
			return wagonInfo.cargoCapacity.rawin(subCargo) ? wagonInfo.cargoCapacity[subCargo] : 0; 
		});
		wagonEngines.KeepAboveValue(0);
		if(wagonEngines.Count() == 0) {
			HgLog.Warning("No capacity > 0 wagon");
			return null;
		}
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

	function CalculateSubCargoNumWagons(wagonEngineInfos, numMainWagon, totalNumWagon, locoCapacity) {
		local mainWagonNull = wagonEngineInfos[0].capacity == 0;
		if(subCargos.len() == 0) {
			/*if(mainWagonNull) {
				return [];
			}*/
			local wagonEngineInfo = clone wagonEngineInfos[0];
			wagonEngineInfo.numWagon <- totalNumWagon;
			return [wagonEngineInfo];
		}
		local n0 = mainWagonNull ? 0 : numMainWagon;
		local production = productions[0] == 0 ? 50 : productions[0]; //0の場合はある？
		while(true) {
			local nums = [n0];
			local total = n0;
			local M = (locoCapacity + n0 * wagonEngineInfos[0].capacity).tofloat() / production;
			foreach(index, cargo in subCargos) {
				if(wagonEngineInfos[index+1].rawin("engine")) {
					local capacity = wagonEngineInfos[index+1].capacity;
					if(capacity == 0) {
						nums.push(0);
					} else {
						local n = (productions[index+1] * M / capacity).tointeger();
						local remain = totalNumWagon - total;
						n = min(remain,n);
						nums.push(n);
						total += n;
						if(total >= totalNumWagon) {
							break;
						}
					}
				} else {
					nums.push(0);
				}
			}
			if(total >= totalNumWagon || mainWagonNull) {
				local result = [];
				foreach(index, n in nums) {
					if(n>=1 || index == 0) {
						local wagonEngineInfo = clone wagonEngineInfos[index];
						wagonEngineInfo.numWagon <- n;
						result.push(wagonEngineInfo);
					}
				}
				return result;
			}
			n0 ++;
		}
		/*
	
	
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
		local maxWagons = max(1, totalNumWagon - subCargos.len() - 1);
		
		result.push(clone wagonEngineInfos[0]);
		foreach(index, cargo in subCargos) {
			local numWagon = 0;
			if(wagonEngineInfos[index+1].rawin("engine")) {
				local capacityRate = wagonEngineInfos[index+1].capacity / averageCapacity;
				numWagon = (totalNumWagon.tofloat() * productions[index+1] / totalProduction / capacityRate).tointeger();
				numWagon = max(0,min(numWagon, maxWagons));
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
		result[0].numWagon <- max(0,totalNumWagon - sum);
		return result;*/
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
			HgLog.Warning("wagonCapacity == 0:"+AIEngine.GetName(engine)+" cargo:"+AICargo.GetName(cargo));
			return null;
		}
		if(wagonInfo.length == 0) {
			HgLog.Warning("wagonInfo.length == 0:"+AIEngine.GetName(engine));
			return null;
		}
		result.capacity <- wagonCapacity;
		local weight  = AIEngine.GetWeight(engine);
		result.lengthWeight <- [wagonInfo.length, weight + GetCargoWeight(cargo, wagonCapacity)];
		result.isMultipleUnit <- weight == 0; // for 2cc Multiple Unit Wagon
		result.isFollowerForceWagon <- result.isMultipleUnit && !AIEngine.GetName(engine).find("Unpowered"); // 多分従動力車　TODO 実際に連結させて調べたい
		return result;
	}
	
	function GetWagonSelectors(cargo,railSpeed) {
		local result = [];
		// バランス
		result.push(function(engine):(cargo,railSpeed) {
			local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(engine);
			if(wagonInfo==null) {
				return 0;
			}
			local cost = (AIEngine.GetPrice(engine) + AIEngine.GetRunningCost(engine) * 3) / HogeAI.GetInflationRate();
			local speed = min( railSpeed, AIEngine.GetMaxSpeed(engine)==0 ? railSpeed : AIEngine.GetMaxSpeed(engine) );
			local capa = (wagonInfo.cargoCapacity.rawin(cargo) ? wagonInfo.cargoCapacity[cargo] : 0) * 256;
			if(capa==0) {
				return 0;
			}
			local a = ( speed.tofloat()*24 - cost/capa).tointeger();
			//HgLog.Info("GetWagonSelectors "+AIEngine.GetName(engine) + " "+ a+ " "+cost+" "+speed+" "+capa+" "+wagonInfo.length);
			return a;
		});
		// 容量重視
		result.push(function(engine):(cargo) {
			local wagonInfo = TrainInfoDictionary.Get().GetTrainInfo(engine);
			if(wagonInfo==null || wagonInfo.length==0) {
				return 0;
			}
			local capa = (wagonInfo.cargoCapacity.rawin(cargo) ? wagonInfo.cargoCapacity[cargo] : 0) * 256;
			return capa / wagonInfo.length;
		});
		// スピード重視
		result.push(function(engine):(railSpeed) {
			return min(railSpeed,AIEngine.GetMaxSpeed(engine)==0?railSpeed:AIEngine.GetMaxSpeed(engine)); // / (AIEngine.GetCost(engine) + AIEngine.GetRunningCost(engine))
		});
		// ランコス重視
		result.push(function(engine) {
			local cost = AIEngine.GetRunningCost(engine);
			if(cost <= 0) return 0;
			return IntegerUtils.IntMax / AIEngine.GetRunningCost(engine);
		});
		// コスト重視
		result.push(function(engine) {
			local cost = AIEngine.GetPrice(engine);
			if(cost <= 0) return 0;
			return IntegerUtils.IntMax / cost;
		});
		return result;
	}
	
	function GetWagonEngines(cargo, railType) {
		local key = cargo + " " + railType;
		if(wagonEnginesCache.rawin(key)) {
			return wagonEnginesCache.rawget(key);
		}
		local result = _GetWagonEngines(cargo, railType);
		wagonEnginesCache.rawset(key, result);
		return result;
	}
	
	function _GetWagonEngines(cargo, railType) {
		local railSpeed = 10000;
		if(railType != null) {
			railSpeed = AIRail.GetMaxSpeed(railType);
			if(railSpeed <= 0) {
				railSpeed = 10000;
			}
		}
		local wagonSelectors = GetWagonSelectors(cargo,railSpeed);
		local wagonEngines = AIEngineList(AIVehicle.VT_RAIL);
		wagonEngines.Valuate(AIEngine.IsWagon);
		wagonEngines.KeepValue(1);
		wagonEngines.Valuate(AIEngine.IsBuildable);
		wagonEngines.KeepValue(1);
		wagonEngines.Valuate(AIEngine.CanRefitCargo, cargo);
		wagonEngines.KeepValue(1);
		if(railType != null) {
			wagonEngines.Valuate(AIEngine.CanRunOnRail, railType);
			wagonEngines.KeepValue(1);
		}
		/*
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
		}*/
		
		wagonEngines.Sort(AIList.SORT_BY_VALUE,true);
		wagonEngines.Valuate(AIBase.RandItem);
		foreach(engine,_ in wagonEngines) {
			TrainInfoDictionary.Get().GetTrainInfo(engine);	 // Valuateの中でBuildTrainが呼ばれるのを防ぐ
		}
		foreach(index, selector in wagonSelectors) {
			local tmp = AIList();
			tmp.AddList(wagonEngines);
			tmp.Valuate(selector);
			local wagon = tmp.Begin();
			wagonEngines.SetValue(wagon, min(index, wagonEngines.GetValue(wagon)));
		}
		return wagonEngines;
	}
	
	function Estimate() {
		local engineSets = GetEngineSetsOrder();
		if(engineSets.len() >= 1) {
			return engineSets[0];
		} else {
			return null;
		}
	}
	
	function GetEngineSets() {
		if(pathDistance == null) {
			pathDistance = distance;
		}

		if(totalDistance == null) {
			if(route != null) {
				SetTransferParams();
			} else {
				totalDistance = distance;
			}
		}
		if(destRouteCargoIncome == null) {
			if(route != null) {
				SetRouteCargoIncome(cargo);
			} else {
				destRouteCargoIncome = 0;
			}
		}
		if(additonalTrainEngine != null) {
			if(!AIEngine.IsBuildable(additonalTrainEngine)) {
				additonalTrainEngine = null;
			}
		}
		if(additonalWagonEngine != null) {
			if(!AIEngine.IsBuildable(additonalWagonEngine)) {
				additonalWagonEngine = null;
			}
		}
	
		local result = [];
		local yearlyIncome = HogeAI.Get().GetQuarterlyIncome(4);
		local usableMoney = HogeAI.Get().GetUsableMoney();
		local useReliability = HogeAI.Get().IsEnableVehicleBreakdowns();
		local breakdownDifficulty = HogeAI.Get().GetVehicleBreakdownDifficulty();
		local firstRoute = yearlyIncome <= 0; // TrainRoute.instances.len()==0 && RoadRoute.instances.len()==0;
		
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
		local maxBuildingCost = !isLimitIncome || !checkRailType ? 0 : GetMaxBuildingCost(0);
		if(maxBuildingCost>0 && firstRoute) usableMoney -= HogeAI.GetInflatedMoney(20000); // レールの建設は不確実性が大きい
		local vehiclesRoom = TrainRoute.GetMaxTotalVehicles() - AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, TrainRoute.GetVehicleType());
		
		local countWagonEngines = 0;
		foreach(wagonEngine,_ in GetWagonEngines(cargo, railType)) {
			if(limitWagonEngines != null && countWagonEngines >= limitWagonEngines) {
				if(result.len() >= 1) {
					break;
				}
				if(countWagonEngines >= limitWagonEngines+1) { // 条件が悪くてwagonの種類が多い時、全部見に行って異常に時間がかかる
					//HgLog.Warning("result.len()==0 break."+countWagonEngines);
					break;
				}
				//HgLog.Warning("result.len()==0 continued."+countWagonEngines);
			}
			if(wagonEngine != null && (!AIEngine.IsValidEngine(wagonEngine) || !AIEngine.IsBuildable(wagonEngine))) {
				continue;
			}
			local wagonEngineInfo;
			if(wagonEngine == null) {
				wagonEngineInfo = {
					capacity = 0
					isMultipleUnit = false
				}
			} else {
				wagonEngineInfo = GetWagonEngineInfo(cargo, wagonEngine);
				if(wagonEngineInfo == null) {
					continue;
				}
			}
			wagonEngineInfo.production <- cargoProduction[cargo];
			
			local wagonSpeed = wagonEngine == null ? 0 : AIEngine.GetMaxSpeed(wagonEngine);
			if(wagonSpeed <= 0) {
				wagonSpeed = 10000;
			}
			wagonSpeed = min(railSpeed, wagonSpeed);
			
			local trainEngines = AIEngineList(AIVehicle.VT_RAIL);
			trainEngines.Valuate(AIEngine.IsWagon);
			trainEngines.KeepValue(0);
			trainEngines.Valuate(AIEngine.IsBuildable);
			trainEngines.KeepValue(1);
			trainEngines.Valuate(function(e):(cargo) {
				return AIEngine.GetCapacity(e)!=-1 && !AIEngine.CanRefitCargo (e,cargo);
			});
			trainEngines.KeepValue(0);
			if(railType != null) {
				trainEngines.Valuate(AIEngine.HasPowerOnRail, railType);
				trainEngines.KeepValue(1);
			}
			if(wagonEngine != null) {
				trainEngines.Valuate(function(e):(wagonEngine) {
					return !TrainRoute.IsUnsuitableEngineWagon(e, wagonEngine);
				});
				trainEngines.KeepValue(1);
			}
			if(checkRailType || limitTrainEngines != null) {
				if(checkRailType || limitTrainEngines == 1) {
					local money = HogeAI.Get().GetUsableMoney(); //max(200000,AICompany.GetBankBalance(AICompany.COMPANY_SELF));
					trainEngines.Valuate(function(e):(wagonSpeed, money, cargo, useReliability, breakdownDifficulty) {
						local reliability = useReliability ? AIEngine.GetReliability(e) / breakdownDifficulty : 100;
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
			if(trainEngines.Count() >= 1) {
				countWagonEngines ++;
			}
			local countTrainEngines = 0;
			//local wagonEngineEstimations = AIList();
			//wagonEngineEstimations.Sort(AIList.SORT_BY_VALUE, false);
			/*HgLog.Info("GetEngineSets wagon:"+(wagonEngine==null?"no wagon":AIEngine.GetName(wagonEngine))+" loco:"+limitTrainEngines+"/"+trainEngines.Count()
				+" "+HgTable(cargoProduction)+" distance:"+distance);*/
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
				if(wagonEngine != null && !AIEngine.CanRunOnRail(wagonEngine, trainRailType)) {
					continue;
				}
				local trainInfo = TrainInfoDictionary.Get().GetTrainInfo(trainEngine);
				if(trainInfo == null) {
					continue;
				}
				if(wagonEngineInfo.isMultipleUnit != trainInfo.isMultipleUnit) {
					continue;
				}
				countTrainEngines ++;
				if(limitTrainEngines != null && countTrainEngines > limitTrainEngines) {
					break;
				}
				
				local buildingCost = GetBuildingCost(trainRailType, distance, cargo);
				local infrastractureCost = InfrastructureCost.Get().GetCostPerDistanceRail(trainRailType) * distance;
				
				local trainCapacity = trainInfo.cargoCapacity.rawin(cargo) ? trainInfo.cargoCapacity[cargo] : 0;
				local trainEngineInfo = clone trainInfo;
				trainEngineInfo.engine <- trainEngine;
				trainEngineInfo.cargo <- cargo;
				trainEngineInfo.capacity <-  trainCapacity;
				trainEngineInfo.runningCost <-  AIEngine.GetRunningCost(trainEngine);
				trainEngineInfo.price <- AIEngine.GetPrice(trainEngine);
				trainEngineInfo.maxTractiveEffort <- AIEngine.GetMaxTractiveEffort(trainEngine);
				trainEngineInfo.power <- AIEngine.GetPower(trainEngine);
				trainEngineInfo.lengthWeight <- [trainInfo.length, AIEngine.GetWeight(trainEngine) + GetCargoWeight(cargo, trainCapacity)];
				
				
				local trainRunningCost = AIEngine.GetRunningCost(trainEngine);
				local trainPrice = AIEngine.GetPrice(trainEngine); 
				local trainReiliability = useReliability ? AIEngine.GetReliability(trainEngine) / breakdownDifficulty : 100;
				local maxSpeed = min(AIEngine.GetMaxSpeed(trainEngine),wagonSpeed);
				local railSpeed = AIRail.GetMaxSpeed(trainRailType);
				if(railSpeed >= 1) {
					maxSpeed = min(railSpeed, maxSpeed);
				}
				

				local wagonEngineInfos = [wagonEngineInfo];
				
				foreach(cargo,production in cargoProduction) {
					if(cargo == this.cargo) {
						continue;
					}
					local subWagonEngine = GetSuitableSubWagonEngine(cargo, trainRailType, trainEngine, maxSpeed);
					local wagonEngineInfo = null;
					if(subWagonEngine != null) {
						local wagonSpeed = AIEngine.GetMaxSpeed(subWagonEngine);
						if(wagonSpeed >= 1) {
							maxSpeed = min(maxSpeed, wagonSpeed);
						}
						wagonEngineInfo = GetWagonEngineInfo(cargo, subWagonEngine);
						if(wagonEngineInfo != null) {
							wagonEngineInfo.production <- production;
						}
					} else {
						HgLog.Warning("GetSuitableSubWagonEngine:null ["+AICargo.GetName(cargo)+"] railType:"+AIRail.GetName(trainRailType)+" trainEngine:"+AIEngine.GetName(trainEngine));
					}
					if(wagonEngineInfo != null) {
						wagonEngineInfos.push(wagonEngineInfo);
					}			
				}
				local stationRate = CargoUtils.GetStationRate(maxSpeed) + 170;
				
				if(trainInfo.isMultipleUnit) {
					foreach( wagonEngineInfo in wagonEngineInfos ) {
						if(wagonEngineInfo.rawin("capacity")) {
							wagonEngineInfo.capacity = trainCapacity / max(1,trainInfo.length / 8);
							if(wagonEngineInfo.runningCost == 0) {
								wagonEngineInfo.runningCost = trainRunningCost / (wagonEngineInfo.isFollowerForceWagon ? 1 : 3)
							}
						}
					}
				}
				local loadingTime = 4 * (isBidirectional ? 2 : 1); //実測だとどっちも変わらん、こんなもん。CargoUtils.IsPaxOrMail(cargo) ? 4 : 2;
				
				local trainPlan = TrainPlan(trainEngineInfo, wagonEngineInfos, cargoProduction);
				trainPlan.skipWagonNum = skipWagonNum;


				local infraEstimation = delegate TrainEstimation : {
					designedDate = AIDate.GetCurrentDate()
					cargo = cargo
					engine = trainEngine
					railType = trainRailType
					distance = distance
					totalDistance = totalDistance
					trainEngine = trainEngine
					production = cargoProduction[cargo]
					isTransfer = isTransfer
					cargoProduction = cargoProduction
					cargoIsTransfered = cargoIsTransfered
					stationRate = stationRate
					additionalCruiseDays = additionalCruiseDays
					additionalVehiclesPerRoute = 0
					additionalRunningCostPerCargo = additionalRunningCostPerCargo
					destRouteCargoIncome = destRouteCargoIncome
					additionalRouteIncome = 0
					isBidirectional = isBidirectional
					loadingTime = loadingTime

					numLoco = null
					wagonEngineInfos = null
					capacity = null
					totalCapacity = null
					length = null
					weight = null
					price = null
					cargoCapacity = null
					stockRate = null
					intervalStored = null
					lengthWeights = null
					cruiseSpeed = null
					tractiveEffort = null
					power = null
					acceleration = null
					days = null
					cruiseDays = null
					runningCost = null
					runningCostPerCargo = null
					slopes = null
					platformLength = null
					startDays = null
					
					isSingle = null
					infrastractureCost = null
					buildingCost = null
					maxVehicles = null

					buildingTime = null
					waitingInStationTime = null
					vehiclesPerRoute = null
					cargoRateStock = null
					cargoIncomes = null
					incomePerOneTime = null
					incomePerOneTimeReturn = null
					income = null
					routeIncome = null
					roi = null
					value = null
				};

				
				local minNumLoco = 1;
				local increaseLoco = true;
				for( ;;) {
					
					if(increaseLoco) {
						trainPlan.IncreaseNumLoco();
					} else {
						trainPlan.SetNumLoco(minNumLoco);
						trainPlan.IncreaseNumWagon();
					}
					// HgLog.Info("numLoco:"+trainPlan.locoInfo.numLoco+" numWagon:"+trainPlan.numWagon+" length:"+trainPlan.GetLength());
					local usedPlatformLength = platformLength == null ? (trainPlan.GetLength()+15)/16 : platformLength;
					usedPlatformLength = min(HogeAI.Get().maxStationSpread, usedPlatformLength);
					if(trainPlan.GetLength() > usedPlatformLength * 16) {
						break;
					}
					
					increaseLoco = false;
					
					local price = trainPlan.GetPrice();
					
					if(firstRoute && price * 3 / 2 > usableMoney) {
						//HgLog.Warning("firstRoute && price * 3 / 2 > HogeAI.GetUsableMoney()");
						if(tooShortMoney == null) {
							tooShortMoney = true;
						}
						continue;
					}
					if(maxBuildingCost != 0 && price > maxBuildingCost) {
						if(tooShortMoney == null) {
							tooShortMoney = true;
						}
						continue; //　買えない
					}
					
					local slopedSpeed = trainPlan.GetCruiseSpeed(1);
					slopedSpeed = min(maxSpeed,slopedSpeed);
					if(slopedSpeed == 0) {
						//HgLog.Warning("slopedSpeed == 0");
						continue;
					}
					
					local requestSpeed = HogeAI.Get().roiBase ? 10 : max(10, min(40, maxSpeed / 3));  // min(40, max(10, maxSpeed / 10));
					local slopes = GetSlopes(trainPlan.GetLength());
					local acceleration = trainPlan.GetAcceleration(requestSpeed, slopes);
					if(acceleration <= 0) {
						// HgLog.Warning("acceleration:"+acceleration+" requestSpeed:"+requestSpeed+" slopes:"+slopes);
						minNumLoco = trainPlan.locoInfo.numLoco + 1;
						increaseLoco = true;
						continue;
					}
					local cruiseSpeed = (min(111,slopedSpeed) + slopedSpeed * 2) / 3;
					if(useReliability) {
						cruiseSpeed = (60 + cruiseSpeed * 3) / 4;
					}
					/*
					local startDays = 8.0 / (trainPlan.GetPower().tofloat() / trainPlan.GetWeight().tofloat()) * cruiseSpeed / 100;
					local startDistance = VehicleUtils.GetDistance(cruiseSpeed/2, startDays).tointeger();
					
					local stationLimitTime = isRoRo ? 10 : 20;
					local stationInOutTime = VehicleUtils.GetDays( max(usedPlatformLength,7), cruiseSpeed ) * (isRoRo ? 1 : 2) / 2;*/
					
					
					// cruiseSpeedに到達するまで、平均cruiseSpeed/2の速度で走行していると仮定
					// それまでcruiseSpeed/2の時の加速度で等加速度運動していると仮定
					local accelerationFlat = trainPlan.GetAcceleration(cruiseSpeed/2, 0);
					if(accelerationFlat<=1) continue;
					local startDays = cruiseSpeed / (accelerationFlat / 2);
//					local startDays = 8.0 / (trainPlan.GetPower().tofloat() / trainPlan.GetWeight().tofloat()) * cruiseSpeed / 100;
					local startDistance = VehicleUtils.GetDistance(cruiseSpeed/2, startDays).tointeger();
					
					local stationLimitTime = 0; //isRoRo ? 7 : 10;
					local inOutDistance = usedPlatformLength + 7;
					local stationInOutTime = 
						((VehicleUtils.GetDays( max(0,inOutDistance-startDistance),cruiseSpeed )  // 最高速度で移動する駅構内
						+ VehicleUtils.GetDays( min(inOutDistance,startDistance),cruiseSpeed/2 )) // 半分のスピードで移動する駅構内
						+ 2) * (isRoRo ? 7 : 10) / 7;
					
					local cruiseDays = 
						(VehicleUtils.GetDays( max(0,pathDistance-startDistance),cruiseSpeed ) 
						+ VehicleUtils.GetDays( max(startDistance-pathDistance,startDistance),cruiseSpeed/2 )) * 150 / (trainReiliability+50);
					local days = (cruiseDays + loadingTime) * 2;
					
					local maxVehicles = max(1, days / max(stationLimitTime,stationInOutTime) + (isRoRo ? 2 : 0)); //+2は駅停車中分
					maxVehicles = min( maxVehicles, vehiclesRoom );

					local trainEstimation = clone infraEstimation;
					trainEstimation.numLoco = trainPlan.locoInfo.numLoco;
					trainEstimation.wagonEngineInfos = trainPlan.CloneWagonInfos();
					trainEstimation.capacity = trainPlan.GetCargoCapacity()[cargo];
					trainEstimation.totalCapacity = trainPlan.GetTotalCapacity();
					trainEstimation.length = trainPlan.GetLength();
					trainEstimation.weight = trainPlan.GetWeight();
					trainEstimation.price = price;
					trainEstimation.cargoCapacity = clone trainPlan.GetCargoCapacity();
					trainEstimation.lengthWeights = clone trainPlan.GetLengthWeights();
					trainEstimation.cruiseSpeed = cruiseSpeed;
					trainEstimation.tractiveEffort = trainPlan.GetTractiveEffort();
					trainEstimation.power = trainPlan.GetPower();
					trainEstimation.acceleration = acceleration;
					trainEstimation.days = days;
					trainEstimation.cruiseDays = cruiseDays;
					trainEstimation.runningCost = trainPlan.GetRunningCost();
					trainEstimation.slopes = slopes;
					trainEstimation.platformLength = usedPlatformLength;
					trainEstimation.startDays = startDays;
					

					foreach(isSingle in [true,false]) {
						//if(isSingle) continue;
						if(isSingleOrNot != null && isSingleOrNot != isSingle) {
							continue;
						}
						if(HogeAI.Get().ecs && isSingle) { // ECSは単線だと信頼度が保てないためパフォーマンスが低下する
							continue;
						}

						local realBuildingCost = isSingle ? buildingCost / 2 : buildingCost;
						local realMaxVehicles = isSingle ? 1 : maxVehicles;
						if(maxBuildingCost > 0 && price > 0) {
							realMaxVehicles = min(realMaxVehicles, (maxBuildingCost - realBuildingCost) / price);
							if(realMaxVehicles <= 0) {
								if(tooShortMoney == null) {
									tooShortMoney = true;
								}
								//HgLog.Warning("maxBuildingCost "+realBuildingCost+"/"+maxBuildingCost+" price:"+price+" isSingle:"+isSingle);
								continue;
							}
						}					
						
						local estimation = clone trainEstimation;
						estimation.infrastractureCost = infrastractureCost / (isSingle ? 2 : 1);
						estimation.buildingCost = realBuildingCost;
						estimation.maxVehicles = realMaxVehicles;
						estimation.isSingle = isSingle;
						
						estimation.Estimate();
						/*
						trainPlan.reachMaxVehicles = estimation.vehiclesPerRoute >= maxVehicles;
						if(trainPlan.priorityWagon == null) {
							trainPlan.cargoIncomes = estimation.cargoIncomes;
							trainPlan.CalculatePriorityWagon();
						}*/
						
						if(ignoreIncome || estimation.income > 0) {
							//wagonEngineEstimations.AddItem(result.len(),estimation.value);
							if(maxBuildingCost > 0) {
								if( firstRoute ) {
									if(estimation.price * estimation.vehiclesPerRoute + estimation.buildingCost > usableMoney ) continue;
								} else {
									if(estimation.price + estimation.buildingCost > usableMoney + yearlyIncome) continue;
								}
							}
							if(forRawPlace!=null && forRawPlace && route == null) {
								if(estimation.days < 90) {
									if(estimation.isSingle) {
										result.push(estimation);
									}
								} else {
									if(!estimation.isSingle) {
										result.push(estimation);
									}
								}
							} else {
								result.push(estimation);
							}
							//HgLog.Info(estimation);
						} else {
							//HgLog.Warning("estimation.income <= 0 " + estimation);
						}
					}
					if(slopedSpeed < maxSpeed * 0.9) {
						//HgLog.Warning("acceleration:"+acceleration);
						increaseLoco = true;
						continue;
					}
				}
			}
			/*if(wagonEngineEstimations.Count() >= 1) {
				HgLog.Info("GetEngineSets estimation:"+result[wagonEngineEstimations.Begin()]);
			}*/
		}
		return result;
	}
	
	function GetSlopes(length) {
		local slopes = maxSlopes;
		if(selfGetMaxSlopesFunc != null) {
			slopes = selfGetMaxSlopesFunc.GetMaxSlopes(length);
		}
		if(slopes == null) {
			slopes = max(1,length / 16 / 5);
		}
		return slopes;
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
					/* if(HogeAI.Get().IsRich() && !HogeAI.Get().IsInfrastructureMaintenance()) {
						if(AIRail.GetMaintenanceCostFactor(railType) < AIRail.GetMaintenanceCostFactor(result)) {
							result = railType;
						} Convertは時間がかかるので本当に必要になるまでチェンジしない
					} else {*/
						local resultRailSpeed = AIRail.GetMaxSpeed (result);
						resultRailSpeed = resultRailSpeed == 0 ? 10000 : resultRailSpeed;
						if(resultRailSpeed < railSpeed) {
							result = railType;
						}
					//}
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
}

class TrainPlan {

	static slopeForceCache = {};
	static cruiseSpeedCache = {};

	locoInfo = null;
	wagonInfos = null;
	cargoProduction = null;
	
	skipWagonNum = null;
	
	cargoCapacity = null;
	capacityPerProduction = null;
	numWagon = null;
	length = null;
	weight = null;
	power = null;
	tractiveEffort = null;
	lengthWeights = null;
	reachMaxVehicles = null;
	cargoIncomes = null;
	priorityWagon = null;
	wagons = null;

	
	constructor(locoInfo,wagonInfos,cargoProduction) {
		local locoInfo = clone locoInfo;
		locoInfo.numLoco <- 0;
		this.locoInfo = locoInfo;
		this.wagonInfos = [] 
		foreach(wagonInfo in wagonInfos) {
			local wagonInfo = clone wagonInfo;
			wagonInfo.numWagon <- 0;
			this.wagonInfos.push(wagonInfo);
		}
		this.numWagon = 0;
		this.length = 0;
		this.weight = 0;
		this.cargoCapacity = {};
		this.capacityPerProduction = {};
		this.cargoProduction = cargoProduction;
		foreach(wagonInfo in wagonInfos) {
			wagonInfo.production <- cargoProduction[wagonInfo.cargo];
		}
		foreach(cargo,production in cargoProduction) {
			cargoCapacity[cargo] <- 0;
			capacityPerProduction[cargo] <- 0;
		}
		this.lengthWeights = [];
		this.reachMaxVehicles = false;
		this.wagons = [];
	}
	
	function SetNumLoco(n) {
		if(n < locoInfo.numLoco) {
			DecreaseNumLoco(locoInfo.numLoco - n);
		} else if(locoInfo.numLoco < n) {
			IncreaseNumLoco(n - locoInfo.numLoco);
		}
	}

	function IncreaseNumLoco(n=1) {
		locoInfo.numLoco += n;
		if(locoInfo.capacity >= 1) {
			local cargo = locoInfo.cargo;
			cargoCapacity[cargo] += locoInfo.capacity * n;
			capacityPerProduction[cargo] = cargoCapacity[cargo].tofloat() / cargoProduction[cargo];
		}
		length += locoInfo.lengthWeight[0] * n;
		weight += locoInfo.lengthWeight[1] * n;
		power = null;
		tractiveEffort = null;
		for(local i=0; i<n; i++) {
			lengthWeights.insert(0,locoInfo.lengthWeight);
		}
	}
	
	function DecreaseNumLoco(n=1) {
		locoInfo.numLoco -= n;
		if(locoInfo.capacity >= 1) {
			local cargo = locoInfo.cargo;
			cargoCapacity[cargo] -= locoInfo.capacity * n;
			capacityPerProduction[cargo] = cargoCapacity[cargo].tofloat() / cargoProduction[cargo];
		}
		length -= locoInfo.lengthWeight[0] * n;
		weight -= locoInfo.lengthWeight[1] * n;
		power = null;
		tractiveEffort = null;
		for(local i=0; i<n; i++) {
			lengthWeights.remove(0);
		}
	}

	function IncreaseNumWagon() {
		local delta;
		if(skipWagonNum != 1) {
			// skipWagonNum=3: 1,2,4,8,16,32,64,128...
			// skipWagonNum=5: 1,2,5,13,34,...
			delta = max( 1, numWagon * skipWagonNum / 3 ); 
		} else {
			delta = max( 1, numWagon / 3 ); // 1,2,3,4,5,6,7,9,12,16,21,28,37...
		}
		if(wagonInfos.len() == 1) { // TODO wagonInfos.len()==0の場合
			IncreaseWagon(wagonInfos[0],delta);
		} else {
			if(reachMaxVehicles) {
				IncreaseWagon(priorityWagon,delta);
			} else {
				for(local i=0; i<delta; i++) {
					local minWagonInfo = null;
					local minCp = null;
					foreach(wagonInfo in wagonInfos) {
						local cargo = wagonInfo.cargo;
						local cp = capacityPerProduction[cargo];
						if(minWagonInfo == null || cp < minCp) {
							minWagonInfo = wagonInfo;
							minCp = cp;
						}
					}
					IncreaseWagon(minWagonInfo,1);
				}
			}
		}
	}
	
	function DecreaseNumWagon() {
		if(wagonInfos.len() == 1) { // TODO wagonInfos.len()==0の場合
			DecreaseWagon(wagonInfos[0],1);
		} else {
		/*
			local maxWagonInfo = null;
			local maxCp = null;
			foreach(wagonInfo in wagonInfos) {
				local cargo = wagonInfo.cargo;
				local cp = capacityPerProduction[cargo];
				if(maxWagonInfo == null || cp > maxCp) {
					if(wagonInfo.numWagon >= 1) { // locoがcapacityある場合に0になりうる
						maxWagonInfo = wagonInfo;
						maxCp = cp;
					}
				}
			}*/
			DecreaseWagon(wagons.pop(),1);
		}
	}

	function IncreaseWagon(wagonInfo,n) {
		wagonInfo.numWagon += n;
		local cargo = wagonInfo.cargo;
		cargoCapacity[cargo] += wagonInfo.capacity * n;
		capacityPerProduction[cargo] = cargoCapacity[cargo].tofloat() / cargoProduction[cargo];
		length += wagonInfo.lengthWeight[0] * n;
		weight += wagonInfo.lengthWeight[1] * n;
		numWagon += n;
		if(wagonInfo.isFollowerForceWagon) {
			power = null;
			tractiveEffort = null;
		}
		local idx = locoInfo.numLoco;
		foreach(w in wagonInfos) {
			if(w == wagonInfo) {
				for(local i=0; i<n; i++) {
					lengthWeights.insert(idx,wagonInfo.lengthWeight);
				}
				break;
			}
			idx += w.numWagon;
		}
		wagons.push(wagonInfo);
	}
	
	function DecreaseWagon(wagonInfo,n) {
		wagonInfo.numWagon -= n;
		local cargo = wagonInfo.cargo;
		cargoCapacity[cargo] -= wagonInfo.capacity * n;
		capacityPerProduction[cargo] = cargoCapacity[cargo].tofloat() / cargoProduction[cargo];
		length -= wagonInfo.lengthWeight[0] * n;
		weight -= wagonInfo.lengthWeight[1] * n;
		numWagon -= n;
		if(wagonInfo.isFollowerForceWagon) {
			power = null;
			tractiveEffort = null;
		}
		local idx = locoInfo.numLoco;
		foreach(w in wagonInfos) {
			if(w == wagonInfo) {
				for(local i=0; i<n; i++) {
					lengthWeights.remove(idx);
				}
				break;
			}
			idx += w.numWagon;
		}
	}
	
	function CalculatePriorityWagon() {
		local maxValue = null;
		priorityWagon = null;
		foreach(wagonInfo in wagonInfos) {
			local value = wagonInfo.capacity  * cargoIncomes[wagonInfo.cargo] / wagonInfo.lengthWeight[0];
			if(maxValue == null || maxValue < value) {
				maxValue = value;
				priorityWagon = wagonInfo;
			}
		}
	}
	
	function GetLengthWeightsKey() {
		local result = "";
		local pl = locoInfo.lengthWeight[0];
		local pw = locoInfo.lengthWeight[1];
		local n = locoInfo.numLoco;
		foreach(wagonInfo in wagonInfos) {
			local l = wagonInfo.lengthWeight[0];
			local w = wagonInfo.lengthWeight[1];
			if(pl==l && pw==w) {
				n += wagonInfo.numWagon;
			} else {
				if(n!=0) {
					result += pl+"/"+pw+":"+n+"-";
				}
				n = wagonInfo.numWagon;
				pl = l;
				pw = w;
			}
		}
		if(n!=0) {
			result += pl+"/"+pw+":"+n+"-";
		}
		return result;
	}
	
	function GetCargoCapacity() {
		return cargoCapacity;
	}
	
	function GetTotalCapacity() {
		local result = 0;
		foreach(cargo,capacity in cargoCapacity) {
			result += capacity;
		}
		return result;
	}
	
	function GetLength() {
		return length;
	}
	
	function GetWeight() {
		return weight;
	}
		
	function CloneWagonInfos() {
		local result = [];
		foreach(w in wagonInfos) {
			result.push(clone w);
		}
		return result;
	}
	
	function GetPrice() {
		local price = locoInfo.price * locoInfo.numLoco;
		foreach(wagonInfo in wagonInfos) {
			price += wagonInfo.price * wagonInfo.numWagon;
		}
		return price;
	}
		
	function GetRunningCost() {
		local result = locoInfo.runningCost * locoInfo.numLoco;
		foreach(wagonInfo in wagonInfos) {
			result += wagonInfo.runningCost * wagonInfo.numWagon;
		}
		return result;
	}

	function GetTractiveEffort() {
		if(tractiveEffort == null) {
			CalcuateTractiveEffortAndPower();
		}
		return tractiveEffort;
	}
	
	function GetPower() {
		if(power == null) {
			CalcuateTractiveEffortAndPower();
		}
		return power;
	}
	

	function CalcuateTractiveEffortAndPower() {
		tractiveEffort = locoInfo.maxTractiveEffort * locoInfo.numLoco;
		power = locoInfo.power * locoInfo.numLoco;
		foreach(wagonInfo in wagonInfos) {
			if(wagonInfo.isFollowerForceWagon) { // DMU / EMUしかつながらん
				tractiveEffort += locoInfo.maxTractiveEffort * wagonInfo.numWagon / max(1,locoInfo.length / 8);
				power += locoInfo.power * wagonInfo.numWagon / max(1,locoInfo.length / 8);
			}
		}
	}
	
	function GetLengthWeights() {
		return lengthWeights;
	}
	
	function GetAcceleration(requestSpeed,slopes) {
		local maxSpeed = AIEngine.GetMaxSpeed(locoInfo.engine);
		return VehicleUtils.GetAcceleration( 
			GetSlopeForce(slopes) + VehicleUtils.GetAirDrag(requestSpeed, maxSpeed, numWagon + locoInfo.numLoco), 
			requestSpeed, GetTractiveEffort(), GetPower(), weight);
	}
	
	function GetSlopeForce(slopes) {
		local key = GetLengthWeightsKey() + slopes;
		if(TrainPlan.slopeForceCache.rawin(key)) {
			return TrainPlan.slopeForceCache[key];
		} else {
			local result = VehicleUtils.GetMaxSlopeForce(slopes, lengthWeights, weight);
			TrainPlan.slopeForceCache.rawset(key, result);
			return result;
		}
	}
	
	function GetCruiseSpeed(maxSlopes) {
		local maxSpeed = AIEngine.GetMaxSpeed(locoInfo.engine);
		local numParts = numWagon + locoInfo.numLoco;
		local power = GetPower();
		local flat = CalculateCruiseSpeed(GetSlopeForce(0), maxSpeed,numParts, power);
		local slope = CalculateCruiseSpeed(GetSlopeForce(maxSlopes), maxSpeed, numParts, power);
		return (flat * 3 + slope) / 4;
		
//		return min(CalculateCruiseSpeed(0, maxSpeed), (maxSpeed + CalculateCruiseSpeed(maxSlopes, maxSpeed)) / 2);
	}

	function CalculateCruiseSpeed(slopeForce, maxSpeed, numParts, power) {
		local key = slopeForce+"-"+maxSpeed+"-"+numParts+"-"+power;
		if(TrainPlan.cruiseSpeedCache.rawin(key)) {
			return TrainPlan.cruiseSpeedCache[key];
		} else {
			local result = _CalculateCruiseSpeed(slopeForce, maxSpeed, numParts, power);
			TrainPlan.cruiseSpeedCache.rawset(key,result);
			return result;
		}
	}
	
	function _CalculateCruiseSpeed(slopeForce, maxSpeed, numParts, power) {
		local airDragValue = min(192, max(1,2048 / maxSpeed));
		local airDragCoefficient = 14 * airDragValue * (1 + numParts * 3 / 20) / 1000.0;
		local p = slopeForce / airDragCoefficient;
		local q = (-power * 746 * 18 / 5) / airDragCoefficient;
		local a1 = 27*q/2;
		local C = pow(a1 + sqrt(a1*a1 + 27*p*p*p),0.333);
		return (p/C - C/3).tointeger();
	}
}

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
		
		foreach(e,trainInfo in dictionary) {
			if(!trainInfo.rawin("isMultipleUnit")) {
				dictionary = {}; // save dataが古い
			}
			break;
		}
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
			if(!AITile.IsCoastTile(depotTile) && AIRail.BuildRailDepot( depotTile,  AIMap.GetTileIndex (x, y+1))) {
				// coastへの建設がとても高額なときがある
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
					//HgLog.Warning("engine:"+AIEngine.GetName(engine)+" capacity:"+capacity+"["+AICargo.GetName(cargo)+"]");
					cargoCapacity[cargo] <- capacity;
				}
			}
		}
		local length = AIVehicle.GetLength (vehicle);
		
		local engineName = AIEngine.GetName(engine);
		local isMultipleUnit = engineName.find("DMU") != null
				|| engineName.find("EMU") != null
				|| engineName.find("Shinkansen") != null
				|| engineName.find("(Metro)") != null
				|| engineName.find("(Maglev)") != null
				|| AIEngine.GetWeight(engine) == 0; // TODO: 実際に接続させて調べたい
		//HgLog.Warning("CreateTrainInfo "+AIEngine.GetName(engine)+" length:"+length+" IsWagon:"+AIEngine.IsWagon(engine));
		
		AIVehicle.SellVehicle(vehicle);
		return {
			length = length
			cargoCapacity = cargoCapacity
			isMultipleUnit = isMultipleUnit
		}
	}
	
}
