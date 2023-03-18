
class IntegerUtils {
	static IntMax = 2147483647;
}

class HgArray {
	array = null;
	
	constructor(array) {
		this.array = array;
	}
	
	
	static function AIListKey(list) {
		local a = [];
		foreach(k,v in list) {
			a.push(k);
		}
		return HgArray(a);
	}
	
	static function AIListKeyValue(list) {
		local a = [];
		foreach(k,v in list) {
			a.push([k,v]);
		}
		return HgArray(a);
	}
	
	static function Generator(gen) {
		local e;
		local array = [];
		while((e=resume gen)!=null) {
			array.push(e);
		}
		return HgArray(array);
	}
	
	function GetArray() {
		return array;
	}

	function Map(func) {
		local result = ::array(array.len());
		foreach(i,a in array) {
			result[i] = func(a);
		}
		return HgArray(result);
	}
	
	
	function Filter(func) {
		local result = [];
		foreach(a in array) {
			if(func(a)) {
				result.push(a)
			}
		}
		return HgArray(result);
	}
	
	static function _Flatten(a) {
		if(typeof a != "array") {
			return [a];
		} else {
			local result = [];
			foreach(x in a) {
				result.extend(HgArray._Flatten(x));
			}
			return result;
		}
	}
	
	function Flatten() {
		return HgArray(_Flatten(array));
	}
	
	function Sort(func) {
		local newArray = clone array;
		newArray.sort(func);
		return HgArray(newArray);
	}
	
	function Slice( start, end ) {
		return HgArray( array.slice( start, min( end, array.len() ) ) );
	}
	
	function Count() {
		return array.len();
	}
	
	function CountOf(item) {
		local result = 0;
		foreach(a in array) {
			if(a==item) {
				result ++;
			}
		}
		return result;
	}
	
	function GetAIList() {
		local result = AIList();
		foreach(a in array) {
			result.AddItem(a,a);
		}
		return result;
	}
	
	function GetAIListKeyValue() {
		local result = AIList();
		foreach(a in array) {
			result.AddItem(a[0],a[1]);
		}
		return result;
	}
	
	function Remove(item) {
		local result = [];
		foreach(a in array) {
			if(a!=item) {
				result.push(a);
			}
		}
		return HgArray(result);
	}
	
	function Contains(item) {
		foreach(a in array) {
			if(a==item) {
				return true;
			}
		}
		return false;
	}
	
	function _tostring() {
		local result = "";
		foreach(e in array) {
			if(result.len()>=1) {
				result += ",";
			}
			result += e.tostring();
		}
		return result;
	}
}

class ArrayUtils {
	function Find(array_, element) {
		foreach(i,e in array_) {
			if(e == element) {
				return i;
			}
		}
		return null;
	}

	function Remove(array_, element) {
		local idx = ArrayUtils.Find(array_,element);
		if(idx != null) {
			array_.remove(idx);
		}
	}
	
	function Add(array_, element) {
		if(ArrayUtils.Find(array_, element) != null) {
			return;
		}
		array_.push(element);
	}
	
	function Without(array_, element) {
		local result = [];
		foreach(e in array_) {
			if(e != element) {
				result.push(e);
			}
		}
		return result;
	}
	
	function And(a1, a2) {
		local result = [];
		foreach(e1 in a1) {
			foreach(e2 in a2) {
				if(e1 == e2) {
					result.push(e1);
				}
			}
		}
		return result;
	}
	
	function Or(a1, a2) {
		local t = {};
		foreach(e in a1) {
			t.rawset(e,0);
		}
		foreach(e in a2) {
			t.rawset(e,0);
		}
		local result = [];
		foreach(k,_ in t) {
			result.push(k);
		}
		return result;
	}
	
	// a1は破壊される
	function Extend(a1, a2) {
		a1.extend(a2);
		return a1;
	}
	
	function Shuffle(a) {
		local list = AIList();
		foreach(index,_ in a) {
			list.AddItem(index, AIBase.Rand());
		}
		list.Sort(AIList.SORT_BY_VALUE,true);
		local result = [];
		foreach(index,_ in list) {
			result.push(a[index]);
		}
		return result;
	}
}

class ListUtils {
	static function Sum(list) {
		local result = 0;
		foreach(k,v in list) {
			result += v;
		}
		return result;
	}
	
	
	static function Average(list) {
		local result = 0;
		foreach(k,v in list) {
			result += v;
		}
		return result / list.Count();
	}
}

class TableUtils {
	static function GetKeys(table) {
		local keys = [];
		foreach(k,v in table) {
			keys.push(k);
		}
		return keys;
	}
}

class SortedList {
	valuator = null;
	list = null;
	arr = null;
	
	constructor(valuator) {
		this.valuator = valuator;
		this.list = AIList();
		this.list.Sort( AIList.SORT_BY_VALUE, false ); // でかい順に返す
		this.arr = [];
	}

	function Extend( arr ) {
		local start = this.arr.len();
		this.arr.extend(arr);
		foreach( i,e in arr ) {
			list.AddItem( start + i, valuator(e) );
		}
		/*
		foreach(i,v in list) {
			local e = this.arr[i];
			if(e != null) {
				HgLog.Info("List:"+v+" "+e.dest.GetName()+"<-"+e.src.GetName()+" "+e.estimate);
			}
		}*/
	}
	
	function Push( item ) {
		list.AddItem( this.arr.len(), valuator(item)  );
		this.arr.push(item);
	}
	
	function Peek() {
		local result = null;
		if(list.Count() >= 0) {
			local i = list.Begin();
			result = arr[i];
		}
		return result;
	}

	function Pop() {
		local result = null;
		if(list.Count() >= 0) {
			local i = list.Begin();
			result = arr[i];
			list.RemoveTop(1);
			arr[i] = null;
		}
		return result;
	}
	
	function GetAll() {
		local result = [];
		foreach(i,_ in list) {
			result.push(arr[i]);
		}
		return result;
	}

	function Count() {
		return list.Count();
	}
}

class IdCounter {
	counter = null;
	
	constructor(initial = 1) {
		counter = initial;
	}
	
	function Get() {
		return counter ++;
	}
	
	function Skip(id) {
		if(counter < id + 1) {
			counter = id + 1;
		}
	}
}

class HgLog {
	static function GetDateString() {
		return DateUtils.ToString(AIDate.GetCurrentDate());
	}
	
	static function Info(s) {
		AILog.Info(HgLog.GetDateString()+" "+s);
	}

	static function Warning(s) {
		AILog.Warning(HgLog.GetDateString()+" "+s);
	}

	static function Error(s) {
		AILog.Error(HgLog.GetDateString()+" "+s);
		//AIController.Break(s);
	}
}

class ExpirationTable {
	table = null;
	expiration = null;
	lastClearDate = null;
	
	constructor(expiration) {
		this.table = {};
		this.expiration = expiration;
		this.lastClearDate = AIDate.GetCurrentDate();
	}
	
	function CheckExpiration() {
		if(lastClearDate + expiration < AIDate.GetCurrentDate()) {
			clear();
		}
	}

	function rawin(e) {
		CheckExpiration();
		return table.rawin(e);
	}
	
	function rawget(e) {
		return table.rawget(e);
	}
	
	function rawset(e,v) {
		table.rawset(e,v);
	}

	function clear() {
		table.clear();
		lastClearDate = AIDate.GetCurrentDate();
	}
}

class ExpirationRawTable {
	table = null;
	expiration = null;
	
	constructor(expiration) {
		this.table = {};
		this.expiration = expiration;
	}
	
	function rawin(e) {
		if(table.rawin(e)) {
			local d = table.rawget(e);
			if(d[0] + expiration < AIDate.GetCurrentDate()) {
				return false;
			} else {
				return true;
			}
		}
		return false;
	}

	function rawget(e) {
		return table.rawget(e)[1];
	}

	function rawset(e,v) {
		table.rawset(e,[AIDate.GetCurrentDate(),v]);
	}

	function clear() {
		table.clear();
	}
}

class DateUtils {
	static function ToString(date) {
		if(date == null) {
			return "null";
		} else {
			return AIDate.GetYear(date)+"-"+AIDate.GetMonth(date)+"-"+AIDate.GetDayOfMonth(date);
		}
	}
}

class BuildUtils {
	static function BuildSafe(func, limit=100) {
		return BuildUtils.RetryUntilFree(function():(func) {
			return BuildUtils.WaitForMoney(func);
		},limit);
	}

	static function RetryUntilFree(func, limit=100) {
		local i;
		for(i=0;i<limit;i++) {
			if(func()) {
				if(i >= 1) {
					HgLog.Info("RetryUntilFree Succeeded count:"+i);
				}
				return true;
			}
			if(AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY) {
				if(i==0) {
					HgLog.Warning("RetryUntilFree(ERR_VEHICLE_IN_THE_WAY) limit:"+limit);
				}
				AIController.Sleep(3);
				continue;
			}
			break;
		}
		if(i==limit) {
			HgLog.Warning("RetryUntilFree limit exceeded:"+limit);
		}
		return false;
	}	
	
	static function DemolishTileUntilFree(tile) {
		return BuildUtils.RetryUntilFree( function():(tile) {
			return AITile.DemolishTile(tile);
		});
	}
	
	
	static function CheckCost(func) {
		local cost;
		{
			local testMode = AITestMode();
			local accounting = AIAccounting();
			if(!func()) {
				if(AIError.GetLastError() != AIError.ERR_NOT_ENOUGH_CASH) {
					return false; // お金じゃない理由で失敗
				}
			}
			cost = accounting.GetCosts();
		}
		if(HogeAI.Get().IsTooExpensive(cost)) {
			return false;
		}
		return true;
	}
	
	static function WaitForMoney(func) {
		local cost;
		{
			local testMode = AITestMode();
			local accounting = AIAccounting();
			if(!func()) {
				if(AIError.GetLastError() != AIError.ERR_NOT_ENOUGH_CASH) {
					return false; // お金じゃない理由で失敗
				}
			}
			cost = accounting.GetCosts();
		}
		if(HogeAI.Get().IsTooExpensive(cost)) {
			HgLog.Warning("cost too expensive:" + cost);
			return false;
		}
		while(true) {
			if(!HogeAI.WaitForPrice(cost)) {
				return false;
			}
			local r = func();
			if(!r && AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) { // 事前チェックしてても失敗する事がある
				cost += HogeAI.Get().GetInflatedMoney(10000);
				continue;
			}
			return r;
		}
		
	/*
		local w = 1000;
		while(true) {
			if(func()) {
				return true;
			}
			if(AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
				HogeAI.WaitForMoney(w);
				w *= 2;
				continue;
			}
			break;
		}
		return false;*/
	}
	
	static function BuildBridgeSafe(a,b,c,d) {
		return BuildUtils.WaitForMoney( function():(a,b,c,d) {
			return AIBridge.BuildBridge(a,b,c,d);
		});
		
	}

	static function BuildTunnelSafe(a,b) {
		return BuildUtils.WaitForMoney( function():(a,b) {
			return AITunnel.BuildTunnel(a,b);
		});
	}

	static function BuildRailDepotSafe(a,b) {
		return BuildUtils.WaitForMoney( function():(a,b) {
			return AIRail.BuildRailDepot(a,b);
		});
	}

	static function BuildRailTrackSafe(a,b) {
		return BuildUtils.WaitForMoney( function():(a,b) {
			return AIRail.BuildRailTrack(a,b);
		});
		
	}
	
	static function BuildSignalSafe(a,b,c) {
		return BuildUtils.WaitForMoney( function():(a,b,c) {
			return AIRail.BuildSignal(a,b,c);
		});
		
	}
	
	static function RemoveSignalSafe(a,b) {
		return BuildUtils.WaitForMoney( function():(a,b) {
			return AIRail.RemoveSignal(a, b);
		});
		
	}
	
	static function RemoveRoadFullSafe(a,b) {
		return BuildUtils.WaitForMoney( function():(a,b) {
			return AIRoad.RemoveRoadFull(a, b);
		});
	}
	
	static function BuildVehicleWithRefitSafe(a,b,c) {
		local func = function():(a,b,c) {
			return AIVehicle.BuildVehicleWithRefit(a, b, c);
		};
		local cost;
		{
			local testMode = AITestMode();
			local accounting = AIAccounting();
			if(func() != 0) {
				if(AIError.GetLastError() != AIError.ERR_NOT_ENOUGH_CASH) {
					return null; // お金じゃない理由で失敗
				}
			}
			cost = accounting.GetCosts();
		}
		while(true) {
			if(!HogeAI.WaitForPrice(cost)) {
				return null;
			}
			local r = func();
			if(!AIVehicle.IsValidVehicle(r) && AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) { // 事前チェックしてても失敗する事がある
				cost += HogeAI.Get().GetInflatedMoney(10000);
				continue;
			}
			return r;
		}
	}
	
	static function DemolishTileSafe(a) {
		return BuildUtils.WaitForMoney( function():(a) {
			return AITile.DemolishTile(a);
		});
	}
	
	static function RemoveRoadStationSafe(tile) {
		return BuildUtils.BuildSafe( function():(tile) {
			return AIRoad.RemoveRoadStation(tile);
		});
	}
	
	static function GetClearWaterCost() {
		local testMode = AITestMode();
		local accounting = AIAccounting();
		local tile = AIMap.GetTileIndex(1,1);
		if(AITile.IsWaterTile(tile)) {
			AITile.RaiseTile (tile, AITile.SLOPE_S);
			return accounting.GetCosts();
		}
		return 0; //TODO 他のタイルも調べる
	}
	

}

class RailUtils {
	static straightTracks = [AIRail.RAILTRACK_NW_NE, AIRail.RAILTRACK_SW_SE, AIRail.RAILTRACK_NW_SW, AIRail.RAILTRACK_NE_SE];

	static function IsStraightTrack(track) {
		foreach(t in RailUtils.straightTracks) {
			if(t == track) {
				return true;
			}
		}
		return false;
	}
}

class HgTable {
	static function Extend(table1, table2) {
		foreach(k,v in table2) {
			table1.rawset(k,v);
		}
	}

	static function FromArray(a) {
		local result = {};
		foreach(e in a) {
			result.rawset(e,0);
		}
		return result;
	}
	
	static function Keys(table) {
		local result = [];
		foreach(k,v in table) {
			result.push(k);
		}
		return result;
	}
}


class Container {
	instance = null;
	
	constructor(instance=null) {
		this.instance = instance;
	}
	
	function Get() {
		return instance;
	}
	
	function GetName() {
		return "This is container";
	}
}

class GetterFunction {
	func = null;
	
	constructor(func) {
		this.func = func;
	}
	
	function Get() {
		return func();
	}
}

class GeneratorContainer {
	instance = null;
	gen = null;

	constructor(gen) {
		this.gen = gen;
	}
	
	function Get() {
		if(instance == null) {
			instance = gen();
		}
		return instance;
	}
}

class DelayCommandExecuter {
	static container = Container();
	static function Get() {
		return DelayCommandExecuter.container.instance;
	}
	
	list = null;
	
	constructor() {
		DelayCommandExecuter.container.instance = this;
		list = [];
	}
	
	function Post(delayDate, func) {
		list.push([delayDate + AIDate.GetCurrentDate(), func]);
	}
	
	function Check() {
		local today = AIDate.GetCurrentDate();
		local deletes = [];
		foreach(e in list) {
			if(e[0] < today) {
				e[1]();
				deletes.push(e);
			}
		}
		if(deletes.len() >= 1) {
			deletes = HgArray(deletes);
			local newList = [];
			foreach(e in list) {
				if(!deletes.Contains(e)) {
					newList.push(e);
				}
			}
			list = newList;
		}
	}
}

class PerformanceCounter {	
	static table = {};
	
	startDate = null;
	startTick = null;
	startOps = null;
	totalDate = null;
	totalTick = null;
	totalOps = null;
	count = null;

	static function Start(name) {
		local counter;
		if(!PerformanceCounter.table.rawin(name)) {
			counter = PerformanceCounter();
			counter.totalDate = 0;
			counter.totalTick = 0;
			counter.totalOps = 0;
			counter.count = 0;
			PerformanceCounter.table.rawset(name, counter);
		} else {
			counter = PerformanceCounter.table.rawget(name);
		}
		counter.startDate = AIDate.GetCurrentDate();
		counter.startTick = AIController.GetTick();
		counter.startOps = AIController.GetOpsTillSuspend();
		return counter;
	}

	function Stop() {
		local tick = AIController.GetTick() - startTick;
		totalDate += AIDate.GetCurrentDate() - startDate;
		totalTick += tick;
		totalOps += tick * 10000 + (startOps - AIController.GetOpsTillSuspend());
		count ++;
	}
	
	static function Print() {
		foreach(name, counter in PerformanceCounter.table) {
			HgLog.Info(name+" "+counter.totalDate+"[days] "+counter.totalTick+"[ticks] "+counter.totalOps+"[ops] "+counter.count+"[times]");
		}
		PerformanceCounter.table.clear();
	}
	
	static function Clear() {
		PerformanceCounter.table.clear();
	}
}


class VehicleUtils {
	static function GetCargoWeight(cargo, quantity) { // 鉄道用
		local result = VehicleUtils.GetCommonCargoWeight(cargo, quantity);
		if (AICargo.IsFreight(cargo)) {
			result *= HogeAI.Get().GetFreightTrains();
		}
		return result;
	}
	
	
	static function GetCommonCargoWeight(cargo, quantity) {
		if(HogeAI.Get().openttdVersion >= 13) {
			return AICargo.GetWeight(cargo, quantity)
		}
	
		local result;
		local label = AICargo.GetCargoLabel(cargo);
		if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
			result = quantity / 16;
		} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			result = quantity / 4;
		} else if (AICargo.HasCargoClass(cargo, AICargo.CC_EXPRESS) 
				&& (AICargo.GetTownEffect(cargo) == AICargo.TE_GOODS || AICargo.GetTownEffect(cargo) == AICargo.TE_WATER/*for FIRS*/)) {
			result = quantity / 2;
		} else if (label == "LVST"){
			result = quantity / 6;
		} else if (label == "VALU"){
			result = quantity / 10;
		} else {
			result = quantity;
		}

		return result;
	}	

	static function GetSlopeForce(slopedWeight, totalWeight) {
		return slopedWeight * HogeAI.Get().GetTrainSlopeSteepness() * 100 + totalWeight * 10 + totalWeight * 15;
	}
	
	static function GetRoadSlopeForce(weight) {
		return weight * HogeAI.Get().GetRoadvehSlopeSteepness() * 100 + weight * 10 + weight * 75;
	}
	
	 
	
	static function GetForce(maxTractiveEffort, power, requestSpeed) {
		if(requestSpeed == 0) {
			HgLog.Warning("GetForce requestSpeed == 0");
			requestSpeed = 1;
		}
		return min((maxTractiveEffort * 1000), power * 746 * 18 / requestSpeed / 5);
	}
	
	static function GetAcceleration(slopeForce, requestSpeed, tractiveEffort, power, towalWeight) {
		local engineForce = VehicleUtils.GetForce(tractiveEffort, power, requestSpeed);
		return (engineForce - slopeForce) / (towalWeight * 4);
	}
	
	static function GetMaxSlopeForce(maxSlopes,lengthWeights,towalWeight) {
		local maxSlopedWeight = 0;
		if(maxSlopes > 0) {
			local lwLen = lengthWeights.len();
			local maxSlopesLen = 16 * maxSlopes;
			for(local i=0; i<lwLen; i++) {
				local w = 0;
				local l = 0;
				do {
					w += lengthWeights[i][1];
					i++;
					if(i >= lwLen) {
						break;
					}
					l += (lengthWeights[i-1][0] + lengthWeights[i][0]) / 2;
				} while(l < maxSlopesLen); //iを戻していないので不正確な可能性があるが、そのお陰で大分高速化している
				maxSlopedWeight = max(maxSlopedWeight,w);
			}
		}
		//HgLog.Info("maxSlopedWeight:"+maxSlopedWeight);
		return VehicleUtils.GetSlopeForce(maxSlopedWeight, towalWeight);
	}

	static function AdjustTrainScoreBySlope(score, engine, start, end) {
		local considerSlope = AIEngine.GetMaxTractiveEffort(engine) < HogeAI.Get().GetTrainSlopeSteepness() * 50;
		if(considerSlope) {
			local slopeLevel = HgTile(start).GetSlopeLevel(HgTile(end));
			score = score * 8 / (8 + slopeLevel-4);
		}
		return score;
	}
	
	static function GetDays(distance, speed) {
		return max(1, distance * 664 / speed / 24 / HogeAI.Get().GetDayLengthFactor());
	}
	
	static function GetSpeed(distance, days) {
		return distance * 664 * HogeAI.Get().GetDayLengthFactor() / days / 24;
	}

	static function ToString( vehicleType ) {
		switch(vehicleType) {
			case AIVehicle.VT_RAIL:
				return "Rail";
			case AIVehicle.VT_WATER:
				return "Water";
			case AIVehicle.VT_ROAD:
				return "Road";
			case AIVehicle.VT_AIR:
				return "Air";
		}
	}
}

class CargoUtils {
	/*TODO: rateでの補正は呼び出し元でやる
	static function GetStationRate(cargo, maxSpeed) { // 255 == 100%
		local result = 170 + min(43,max(0,(maxSpeed - 85) / 4));
		result += 33; // 新品で計算
		if(HogeAI.Get().ecs) {
			if(!CargoUtils.IsPaxOrMail(cargo) && result < (HogeAI.Get().IsRich() ? 153 : 179)) {
				result /= 4; // 70%いかない輸送手段はゴミ
			}
		}
		return result;
	}*/
	
	static function GetStationRate(maxSpeed) {
		local stationRate = max((min(255,maxSpeed) - 85) / 4,0);
		//stationRate += 33; // 新品で計算
		stationRate += HogeAI.Get().IsRich() ? 26 : 0; //彫像
		return stationRate;
	}
	
	static function GetReceivedProduction(prodictionPerMonth, initialRate, day, maxSpeed) {
		local production = prodictionPerMonth.tofloat() / 30;

		local iniRate = initialRate / 255.0;
		local endRate = (CargoUtils.GetStationRate(maxSpeed) + 170) / 255.0;
		local a = 0.003137; //0.8 / 255;
		local t0 = abs(endRate - iniRate) / a;

		if(day <= t0) {
			return ((2 * iniRate + day * a) * day / 2 * production).tointeger();
		} else {
			return (((iniRate + endRate) * t0 / 2 + (day - t0) * endRate) * production).tointeger();
		}
	}
	
	static function GetStationRateWaitTimeFullLoad(prodictionPerMonth, initialRate, capacity, maxSpeed) {
		local capacityTime = capacity / (prodictionPerMonth.tofloat() / 30);
		local iniRate = initialRate / 255.0;
		local endRate = (CargoUtils.GetStationRate(maxSpeed) + 170) / 255.0;
		local a = 0.003137; //0.8 / 255;
		local t0 = abs(endRate - iniRate) / a;
		local c0 = (iniRate + endRate) * t0 / 2;
		if(capacityTime < c0) {
			local t = (-iniRate+pow(iniRate * iniRate + 2 * a * capacityTime, 0.5)) / a;
			local rate = (iniRate + t * a) * 255;
			//HgLog.Info("1 t0:"+t0+" ct:"+capacityTime+" endR:"+endRate+" c0:"+c0+" capacity:"+capacity+" p:"+prodictionPerMonth);
			return [rate.tointeger(), t.tointeger()];
		} else {
			local t = t0 + (capacityTime - c0) / endRate;
			local rate = endRate * 255;
			//HgLog.Info("2 t0:"+t0+" ct:"+capacityTime+" endR:"+endRate+" c0:"+c0+" capacity:"+capacity+" p:"+prodictionPerMonth);
			return [rate.tointeger(), t.tointeger()];
		}
	}
	
	static function GetStationRateStock(cargo, production, initialRate, vehicleType, maxSpeed, intervalDays) {
		local productionPerDay = production.tofloat() / 30;
		local stationRate = CargoUtils.GetStationRate(maxSpeed);
		local result = 0;
		local oldRate = initialRate;
		// 評価の低下や、stockの増加による在庫廃棄は計算していない
		foreach(d in [[7,130],[8,95],[15,50],[22,25],[IntegerUtils.IntMax,0]]) {
			local day = d[0] * (vehicleType == AIVehicle.VT_WATER ? 4 : 1);
			local rate = stationRate + d[1] + CargoUtils.GetStockStationRate(result); // stockの増加によって途中で下がるrate分はとりあえず無視
			local truncate = 0;
			if(rate <= 64) { // セクション中での変化には未対応
				if(result >= 200) {
					truncate = 3;
				} else if(result >= 100) {
					truncate = 2;
				}
			}
			local reachDay = abs(oldRate - rate) * 5 / 4; // 2.5日あたり最大2変動
			if(day < reachDay) {
				rate = oldRate + (rate > oldRate ? 1 : -1) * day * 4 / 5;
			}
			oldRate = rate;
			local receiveDay = min(intervalDays,day);
			local receive = (receiveDay * (oldRate + rate) / 2 * productionPerDay / 255).tointeger();
			if(HogeAI.Get().ecs) {
				if(rate < 179/*70%*/) {
					receive /= 4; // ecsでは70%いかないと生産量がとても下がる
				}
			} else {
				if(AICargo.HasCargoClass(cargo,AICargo.CC_BULK) && rate >= 204/*80%*/) {
					receive = receive * 15 / 10; // 一次産業は80%超えると生産量がどんどん成長する
				}
			}
			result += receive - truncate * receiveDay;
			intervalDays -= day;
			if(intervalDays <= 0) {
				return [rate ,result];
			}
		}
		HgLog.Error("Bug");
	}

	static function GetStockStationRate(stock) {
		if(stock <= 100) {
			return 40;
		}
		if(stock <= 300) {
			return 30;
		}
		if(stock <= 600) {
			return 10;
		}
		if(stock <= 1000) {
			return 0;
		}
		if(stock <= 1500) {
			return -35;
		}
		return -90;
	}

	// 年間の予想収益
	// waitingDays: 積み下ろし時間
	/*
	static function GetCargoIncome(distance, cargo, speed, waitingDays=0, isBidirectional=false) {
		if(speed<=0) {
			return 0;
		}
		local days = max(1, distance*664/speed/24);
		
		local income = AICargo.GetCargoIncome(cargo,distance,days);
		return income * 365 / (days * 2 + waitingDays) * (isBidirectional ? 2 : 1);
	}*/
	
	static function IsPaxOrMail(cargo) {
		return HogeAI.GetPassengerCargo() == cargo || HogeAI.GetMailCargo() == cargo;
	}

}