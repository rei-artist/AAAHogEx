	

class AirportTypeState {
	static container = Container();

	static function Get() {
		return AirportTypeState.container.instance;
	}
	
	isBigPlaneOK = null;

	constructor() {
		AirportTypeState.container.instance = this;
	}
	
	function Check() {
		if(isBigPlaneOK!=null && isBigPlaneOK) {
			return;
		}
		
		local now = false;
		foreach(typeInfo in Airport.GetAvailableAirportTypes()) {
			if(typeInfo[2]) {
				now = true;
			}
		}
		if(isBigPlaneOK!=null && !isBigPlaneOK && isBigPlaneOK != now) {
			isBigPlaneOK = now;
			HgLog.Info("Found big plane airport available!");
			Airport.CheckBuildAirport(true);
		} else {
			isBigPlaneOK = now;
		}
		
	}
}

class Airport {
	static instances = [];
	static ngTowns = [];
	static townAirports = [];
	static townCheckedTiles = {};

	static airportTypes = [
		/*type, maxPopulation, isBigPlaneOK, maxPlanes*/
		[AIAirport.AT_SMALL, 800, false, 3],
		[AIAirport.AT_LARGE, 2000, true, 5],
		[AIAirport.AT_METROPOLITAN, 4000, true, 7],
		[AIAirport.AT_COMMUTER, 1000, false, 3],
		[AIAirport.AT_INTERNATIONAL, 10000, true, 9],
		[AIAirport.AT_INTERCON, 20000, true, 11]
	];
	
	static function SaveStatics(data) {
		local airport = {};
		local array = [];
		foreach(airport in Airport.instances) {
			array.push(airport.Save());
		}
		airport.airports <- array;
		airport.ngTowns <- Airport.ngTowns;
		airport.townAirports <- Airport.townAirports;
		airport.townCheckedTiles <- Airport.townCheckedTiles;
		data.airport <- airport;
	}
	
	static function LoadStatics(data) {
		local airport = data.airport;
		
		Airport.instances.clear();
		foreach(t in airport.airports) {
			Airport.instances.push(Airport.Load(t));
		}
		
		Airport.ngTowns.clear();
		Airport.ngTowns.extend(airport.ngTowns);

		Airport.townAirports.clear();
		Airport.townAirports.extend(airport.townAirports);
		
		Airport.townCheckedTiles.clear();
		HgTable.Extend(Airport.townCheckedTiles, airport.townCheckedTiles);
	}
	
	static function GetAvailableAirportTypes() {
		local result = [];
		foreach(t in Airport.airportTypes) {
			if(AIAirport.IsValidAirportType(t[0]) && AIAirport.IsAirportInformationAvailable(t[0])) {
				result.push(t);
			}
		}
		return result;
	}
	
	static function GetAirportInfomation(airportType) {
		foreach(a in Airport.airportTypes) {
			if(a[0] == airportType) {
				return a;
			}
		}
		return null;
	}
	
	
	static function GetTownPairs(maxPopulation, maxDistance) {
		local array = [];
		local townList = AITownList();
		if(HogeAI.Get().isUseAirportNoise) {
			townList.Valuate(AITown.GetAllowedNoise);
		} else {
			townList.Valuate(AITown.GetPopulation);
		}
		townList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

		local towns = [];
		foreach(town, value in townList) {
			if(towns.len() > 100) {
				break;
			}
			towns.push(town);
		}
		
		
		foreach(t1 in towns) {
			foreach(t2 in towns) {
				local distance = AIMap.DistanceManhattan(AITown.GetLocation(t1), AITown.GetLocation(t2));
				if(maxDistance == 0) {
					if(distance < 100 || distance > 500) {
						continue;
					}
				} else {
					local orderDistance = AIOrder.GetOrderDistance(AIVehicle.VT_AIR,AITown.GetLocation(t1), AITown.GetLocation(t2));
					if(!(maxDistance / 3 < orderDistance && orderDistance < maxDistance * 0.8)) {
						continue;
					}
				}
				local score = min(maxPopulation,min(AITown.GetPopulation(t1), AITown.GetPopulation(t2))) * distance;
				local t = {};
				t.town1 <- t1;
				t.town2 <- t2;
				t.score <- score;
				array.push(t);
			}
		}
		return array;
	}
	
	static function HasAirport(town, airportType) {
		foreach(airport in Airport.instances) {
			if(airport.town == town && airport.GetType() == airportType) {
				return true;
			}
		}
		return false;
	}
	
	static function CheckBuildAirport(asManyAsPossible=false) {
		
		HgLog.Info("###### CheckBuildAirport");
/*		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 1000000) {
			return;
		}*/
		if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_AIR ) >= HogeAI.Get().maxAircraft * 0.9) {
			return;
		}
		
		asManyAsPossible = true;
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > HogeAI.Get().GetInflatedMoney(1000000)) {
			asManyAsPossible = true;
		}
		
		local startDate = AIDate.GetCurrentDate();
		
		local testMode = AITestMode();
		local array = [];
		foreach(airportTypeInfo in Airport.GetAvailableAirportTypes()) {
			local maxPopulation = airportTypeInfo[1];
			local isBigPlaneOk = airportTypeInfo[2];
			local engine = Airport.ChooseEngine(isBigPlaneOk);
			if(engine==null) {
				continue;
			}
			local maxDistance = AIEngine.GetMaximumOrderDistance (engine);
			//HgLog.Info("maxDistance:"+maxDistance);
			foreach(t in Airport.GetTownPairs(maxPopulation, maxDistance)) {
				t.airportType <- airportTypeInfo[0];
				array.push(t);
			}
		}
		array.sort(function(a,b) {
			return b.score - a.score;
		});
		//HgLog.Info("array:"+array.len());
		local date = AIDate.GetCurrentDate();
		foreach(t in array) {
			HogeAI.DoInterval();
			if(Airport.TryBuildAirport(t, array)) {
				if(!asManyAsPossible) {
					break;
				}
				if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_AIR ) > HogeAI.Get().maxAircraft - 20) {
					break;
				}
			}
			if(startDate + 365 < AIDate.GetCurrentDate() || AICompany.GetBankBalance(AICompany.COMPANY_SELF) < HogeAI.Get().GetInflatedMoney(1000000)) {
				break;
			}
		}
		HgLog.Info("end CheckBuildAirport");
	}
	
	static function IsNg(town,airportType) {
		foreach(e in Airport.ngTowns) {
			if(e[0]==town && e[1]==airportType) {
				return true;
			}
		}
		return false;
	}
	
	static function GetAuthorityTowns(rect) {
		local result = AIList();
		local tiles = rect.GetTileList();
		tiles.Valuate(AITile.GetTownAuthority);
		foreach(k,v in tiles) {
			if(AITown.IsValidTown(v)) {
				result.AddItem(v,0);
			}
		}
		return result;
	}
	
	static function TryBuildAirport(t, townPairs, t1Rect=null) {
		//HgLog.Info("TryBuiildAirport "+AITown.GetName(t.town1)+" to "+AITown.GetName(t.town2));
		local testMode = AITestMode();
		local skipT1 = t1Rect != null;
		
		if(!skipT1) {
			if(Airport.IsNg(t.town1, t.airportType)) {
				return false;
			}
		}
		if(Airport.IsNg(t.town2, t.airportType)) {
			return false;
		}
		
		if(!skipT1) {
			t1Rect = Airport.GetAirportRect(t.town1, t.airportType);
			if(t1Rect == null) {
				Airport.ngTowns.push([t.town1,t.airportType]);
				HgLog.Info("fail GetAirportRect "+AITown.GetName(t.town1)+" airportType:"+t.airportType);
				return false;
			}
		}
		local t2Rect = Airport.GetAirportRect(t.town2, t.airportType);
		if(t2Rect == null) {
			Airport.ngTowns.push([t.town2,t.airportType]);
			HgLog.Info("fail GetAirportRect "+AITown.GetName(t.town2)+" airportType:"+t.airportType);
			return false;
		}
		
		local execMode = AIExecMode();
		if(!skipT1) {
//			HgLog.Info("BuildAirport1 "+AITown.GetName(t.town1));
			if(!Airport.BuildAirport(t1Rect, t.airportType)) {
				if(AIError.GetLastError() != AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
				} // TODO 時間経過でngTownから消す仕組み
				Airport.ngTowns.push([t.town1, t.airportType]);
				return false;
			}
			Airport.ngTowns.push([t.town1, t.airportType]);
		}
//		HgLog.Info("BuildAirport2 "+AITown.GetName(t.town2));
		if(!Airport.BuildAirport(t2Rect, t.airportType)) {
			if(AIError.GetLastError() != AIError.ERR_LOCAL_AUTHORITY_REFUSES) {
			}
			Airport.ngTowns.push([t.town2, t.airportType]);
			if(!skipT1) {
				foreach(t2 in townPairs) {
					if(t2.town1 == t.town1 && Airport.TryBuildAirport(t2, townPairs, t1Rect)) {
						return true; //TODO: 対向が小型空港になる事がある。
					}
				}
			}
			//TODO: remove t1 airport
			return false;
		}
		Airport.ngTowns.push([t.town2, t.airportType]);
		local a1 = Airport(t1Rect.lefttop.tile, t2Rect.lefttop.tile);
		local a2 = Airport(t2Rect.lefttop.tile, t1Rect.lefttop.tile);
		a1.BuildVehicle();
		a2.BuildVehicle();
		Airport.instances.push(a1);
		Airport.instances.push(a2);
		HgLog.Info("Builded Airport "+AITown.GetName(t.town1)+" to "+AITown.GetName(t.town2));
		return true;
	}
	
	
	static function GetBuildableNearest(center,maxRadius,w,h,checkedList,airportType = null) {
		local testMode =AITestMode();
		
		center = HgTile(center);
		local radius = max(w,h);
		local array = [];
		for(local r=radius; r<maxRadius; r+=1) {
			foreach(rect in Rectangle.Center(center,r).GetIncludeRectangles(w,h)) {
				if(checkedList.HasItem(rect.lefttop.tile)) {
					continue;
				}
				if(airportType != null) {
					local town = AIAirport.GetNearestTown (rect.lefttop.tile, airportType);
					if(AITown.GetAllowedNoise(town) < AIAirport.GetNoiseLevelIncrease (rect.lefttop.tile, airportType)) {
						continue;
					}
				}
				if(rect.IsBuildable() && rect.LevelTiles()) {
					array.push([rect,rect.GetCenter().DistanceManhattan(center)]);
				}
				checkedList.AddItem(rect.lefttop.tile,0);
			}
			array.sort(function(a,b){
				return a[1] - b[1];
			});
			foreach(a in array) {
				yield a[0];
			}
		}
		return null;
	}
	
	static function GetAirportRect(town, airportType) {
		local maxRadius = (sqrt(AITown.GetPopulation(town))/5).tointeger();
		local w = AIAirport.GetAirportWidth (airportType);
		local h = AIAirport.GetAirportHeight (airportType);
		maxRadius += max(w,h);
		
		local townLocation = AITown.GetLocation(town);
	
		local checkedList = AIList();
		if(Airport.townCheckedTiles.rawin(town)) {
			checkedList = HgArray(Airport.townCheckedTiles[town]).GetAIList();
		}
		local nearestRects = Airport.GetBuildableNearest(townLocation, maxRadius, w, h, checkedList, HogeAI.Get().isUseAirportNoise ? airportType : null);
		Airport.townCheckedTiles.rawset(town,HgArray.AIListKey(checkedList).array);
		
		local rect;
		local cargo = HogeAI.GetPassengerCargo();
		local covarage = AIAirport.GetAirportCoverageRadius (airportType);
		local rectAccepts = [];
		for(local i=0; i<16 && (rect=resume nearestRects) != null; i++) {
			HogeAI.DoInterval();
			local acceptance = AITile.GetCargoAcceptance (rect.lefttop.tile, cargo, w, h, covarage);
			if(acceptance >= 16) {
				rectAccepts.push([rect,acceptance]);
			}
		}
		if(rectAccepts.len()==0) {
			return null;
		}
		rectAccepts.sort(function(a,b) {
			return b[1] - a[1];
		});
		return rectAccepts[0][0];
	}
	
	static function BuildAirport(rect, airportType) {
		local townList = Airport.GetAuthorityTowns(rect);
		foreach(town,v in townList) {
			if(HgArray(Airport.townAirports).CountOf(town) >= 2) {
				HgLog.Warning("Town "+AITown.GetName(town)+" is airports >= 2");
				return false;
			}
			TownBus.CheckTown(town, rect.GetTileList());
		}
		
		HogeAI.WaitForMoney(5000);
		if(!rect.LevelTiles()) {
			HgLog.Warning("failed LevelTiles "+rect+" "+AIError.GetLastErrorString());
			return false;
		}
		foreach(town,v in townList) {
			if(AITown.GetRating (town, AICompany.COMPANY_SELF) < AITown.TOWN_RATING_POOR) {
				HogeAI.PlantTree(rect.GetCenter().tile);
			}
		}
		HogeAI.WaitForPrice(AIAirport.GetPrice(airportType));
		if(AIAirport.BuildAirport (rect.lefttop.tile, airportType,  AIStation.STATION_NEW )) {
			foreach(town,v in townList) {
				Airport.townAirports.push(town);
			}
			return true;
		}
		HgLog.Warning("failed BuildAirport "+AIError.GetLastErrorString()+" "+rect);
		return false;
	}
	
	static function GetEngineList(isBigOk) {
		local engineList = AIEngineList(AIVehicle.VT_AIR);
		engineList.Valuate( AIEngine.GetCargoType );
		engineList.KeepValue( HogeAI.GetPassengerCargo() );
		if(!isBigOk) {
			engineList.Valuate( AIEngine.GetPlaneType );
			engineList.RemoveValue(AIAirport.PT_BIG_PLANE );
		}
		return engineList;
	}

	static function ChooseEngine(isBigOk, orderDistance=0) {
		local engineList = Airport.GetEngineList(isBigOk);
		engineList.Valuate( function(e):(orderDistance) {
			local distance = AIEngine.GetMaximumOrderDistance(e);
			if(orderDistance!=0) {
				if(distance!=0 && distance < orderDistance) {
					return -1;
				}
				distance = orderDistance;
			}
			if(distance==0) {
				distance = 200;
			}
			distance = min(400,distance);
			//TODO 故障率の考慮
			local income = AIEngine.GetCapacity(e)
				* HogeAI.GetCargoIncome(distance, HogeAI.GetPassengerCargo(), AIEngine.GetMaxSpeed(e), AIEngine.GetCapacity(e) * 30 / 200 )
				- AIEngine.GetRunningCost (e); 
			//HgLog.Info("aircraft predict:"+predict+" price:"+AIEngine.GetPrice(e));
			local roi = income * 100 / AIEngine.GetPrice(e);
			if(HogeAI().Get().roiBase) {
				local roi = income * 100 / AIEngine.GetPrice(e);
				return roi < 100 ? 0 : roi;
			} else {
				return income * 20 < AIEngine.GetPrice(e) ? 0 : income;
			}
		});
		engineList.KeepAboveValue(0);
		engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		if(engineList.Count()==0){
			return null;
		}
		return engineList.Begin();
	}
/*
	static function ChooseEngine(isBigOk) {
		local engineList = Airport.GetEngineList(isBigOk);
		engineList.Valuate( AIEngine.GetCapacity );
		engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		if(engineList.Count()==0){
			return null;
		}
		return engineList.Begin();
	}*/
	
	function GetSuiteEngine() {
		local isBigPlaneOk = Airport.GetAirportInfomation(GetType())[2];
		local orderDistance = AIOrder.GetOrderDistance(AIVehicle.VT_AIR, airportTile, toAirportTile);
		return Airport.ChooseEngine(isBigPlaneOk, orderDistance);
	}
	
	
	static function Load(t) {
		local result = Airport(t.airportTile, t.toAirportTile, t.vehicleGroup);
		result.lastCloneDate = t.lastCloneDate;
		return result;
	}
	
	airportTile = null;
	toAirportTile = null;
	vehicleGroup = null;
	lastCloneDate = null;
	
	constructor(airportTile, toAirportTile, vehicleGroup=null) {
		this.airportTile = airportTile;
		this.toAirportTile = toAirportTile;
		if(vehicleGroup==null) {
			this.vehicleGroup = AIGroup.CreateGroup(AIVehicle.VT_AIR);
		} else {
			this.vehicleGroup = vehicleGroup;
		}
	}
	
	function Save() {
		local t = {};
		t.airportTile <- airportTile;
		t.toAirportTile <- toAirportTile;
		t.vehicleGroup <- vehicleGroup;
		t.lastCloneDate <- lastCloneDate;
		return t;
	}
	
	function CheckCloneVehicle() {
		local execMode = AIExecMode();
		if(lastCloneDate != null &&  AIDate.GetCurrentDate() < lastCloneDate + 30 ) {
			return;
		}
		
		local numVehicles = AIGroup.GetNumVehicles (vehicleGroup, AIVehicle.VT_AIR);
		if(numVehicles == 0 || (AIStation.GetCargoWaiting (GetAIStation(), HogeAI.GetPassengerCargo()) > 100 
				&& numVehicles < Airport.GetAirportInfomation(GetType())[3])) {
					
			if(AIStation.GetCargoWaiting (GetDestAIStation(), HogeAI.GetPassengerCargo()) < 100) {
				BuildVehicle(false);
			} else {
				BuildVehicle(true);
			}
			//HgLog.Info("build vehicle group:"+AIGroup.GetName(vehicleGroup)+" numVehicles:"+AIGroup.GetNumVehicles (vehicleGroup, AIVehicle.VT_AIR)+" max:"+Airport.GetAirportInfomation(GetType())[3]+" "+this);
			lastCloneDate = AIDate.GetCurrentDate();
		}
	}
	
	function CheckRenewalVehicles(reduce=false) {
		local execMode = AIExecMode();
		foreach(vehicle,v in AIVehicleList_Group(vehicleGroup)) {
			if(AIVehicle.IsStoppedInDepot (vehicle)) {
				if(!AIVehicle.SellVehicle (vehicle)) {
					HgLog.Warning("failed SellVehicle "+AIError.GetLastErrorString()+" No."+AIVehicle.GetUnitNumber(vehicle)+" "+this);
				} else {
					// BuildVehicle(); 足りなかったら勝手に作成されるはず
				}
			} else if(AIVehicle.IsInDepot(vehicle) && AIOrder.GetOrderFlags(vehicle,0) == AIOrder.OF_GOTO_NEAREST_DEPOT) {
				AIVehicle.StartStopVehicle(vehicle);
			} else if(AIVehicle.GetAgeLeft (vehicle) < 600 || (reduce && AIBase.RandRange(100)<5 && AIVehicle.GetCargoLoad(vehicle,HogeAI.GetPassengerCargo())==0)) {
				if(AIOrder.GetOrderFlags(vehicle,0) != AIOrder.OF_GOTO_NEAREST_DEPOT) {
					while(AIOrder.GetOrderCount (vehicle)>=1) {
						AIOrder.RemoveOrder (vehicle, 0);
					}
					AIOrder.AppendOrder (vehicle, 0, AIOrder.OF_GOTO_NEAREST_DEPOT);
				}
			}
		}
	}
	
	function GetType() {
		return AIAirport.GetAirportType(airportTile);
	}
	
	function GetAIStation() {
		return AIStation.GetStationID (airportTile);
	}
	
	function GetDestAIStation() {
		return AIStation.GetStationID (toAirportTile);
	}
	
	
	function BuildVehicle(isDestFullLoad=true){
		local execMode = AIExecMode();
		local isBigOk = Airport.GetAirportInfomation(GetType())[2];
		local engine = GetSuiteEngine();
		if(engine == null) {
			HgLog.Warning("Not found suite engine."+this);
			return false;
		}
		HogeAI.WaitForPrice(AIEngine.GetPrice(engine));
		local vehicle = AIVehicle.BuildVehicle (AIAirport.GetHangarOfAirport(airportTile), engine);
		if(!AIVehicle.IsValidVehicle (vehicle)) {
			HgLog.Warning("failed BuildVehicle "+AIError.GetLastErrorString());
			return false;
		}
		AIGroup.MoveVehicle(vehicleGroup,vehicle);
		AIOrder.AppendOrder(vehicle, airportTile, AIOrder.OF_FULL_LOAD_ANY);
		if(isDestFullLoad) {
			AIOrder.AppendOrder(vehicle, toAirportTile, AIOrder.OF_FULL_LOAD_ANY );
		} else {
			AIOrder.AppendOrder(vehicle, toAirportTile, AIOrder.OF_NONE );
		}
		AIVehicle.StartStopVehicle (vehicle);
		return true;
	}
	
	
	function _tostring() {
		return "Airport:"+AIStation.GetName(GetAIStation());
	}
	/*
	function CloneVehicle() {
		local execMode = AIExecMode();
		if(vehicles.len() == 0) {
			return null;
		}
		local group = AIVehicleList_Group(vehicleGroup);
		if(group.Count()==0) {
			return BuildVehicle();
		}
		group.
		
		local vehicle = null;
		for(local need=50000;; need+= 10000) {
			HogeAI.WaitForMoney(need);
			vehicle = AIVehicle.CloneVehicle(AIAirport.GetHangarOfAirport(airportTile), vehicles[0], true);
			if(AIError.GetLastError()!=AIError.ERR_NOT_ENOUGH_CASH) {
				break;
			}
		}
		if(!AIVehicle.IsValidVehicle(vehicle)) {
			HgLog.Warning("fail CloneVehicle "+AIError.GetLastErrorString());
			return null;
		}
		this.vehicles.push(vehicle);
		AIVehicle.StartStopVehicle(vehicle);
		return vehicle;
	}*/

	
}



