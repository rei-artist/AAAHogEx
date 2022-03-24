
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
		AIController.Break(s);
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
	static function RetryUntilFree(func, limit=100) {
		for(local i=0;i<limit;i++) {
			if(func()) {
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
		return false;
	}	
	
	static function DemolishTileUntilFree(tile) {
		return BuildUtils.RetryUntilFree( function():(tile) {
			return AITile.DemolishTile(tile);
		});
	}
	
	
	static function WaitForMoney(func) {
		local cost;
		{
			local testMode = AITestMode();
			local accounting = AIAccounting();
			func();
			cost = accounting.GetCosts();
		}
		if(HogeAI.Get().IsTooExpensive(cost)) {
			HgLog.Warning("cost too expensive:" + cost);
			return false;
		}
		HogeAI.WaitForMoney(cost);
		return func();
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
	
	static function IsTooExpensiveClearWaterCost() {
		local testMode = AITestMode();
		local accounting = AIAccounting();
		local tile = AIMap.GetTileIndex(1,1);
		if(AITile.IsWaterTile(tile)) {
			AITile.RaiseTile (tile, AITile.SLOPE_S);
			return HogeAI.Get().IsTooExpensive(accounting.GetCosts());
		}
		return false; //TODO 他のタイルも調べる
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
	
	startTick = null;
	startOps = null;
	totalTick = null;
	totalOps = null;
	count = null;

	static function Start(name) {
		local counter;
		if(!PerformanceCounter.table.rawin(name)) {
			counter = PerformanceCounter();
			counter.totalTick = 0;
			counter.totalOps = 0;
			counter.count = 0;
			PerformanceCounter.table.rawset(name, counter);
		} else {
			counter = PerformanceCounter.table.rawget(name);
		}
		counter.startTick = AIController.GetTick();
		counter.startOps = AIController.GetOpsTillSuspend();
		return counter;
	}

	function Stop() {
		local tick = AIController.GetTick() - startTick;
		totalTick += tick;
		totalOps += tick * 10000 + (startOps - AIController.GetOpsTillSuspend());
		count ++;
	}
	
	static function Print() {
		foreach(name, counter in PerformanceCounter.table) {
			HgLog.Info(name+" "+counter.totalTick+"[ticks] "+counter.totalOps+"[ops] "+counter.count+"[times]");
		}
		PerformanceCounter.table.clear();
	}
	
	static function Clear() {
		PerformanceCounter.table.clear();
	}
}


class VehicleUtils {
	static function GetCargoWeight(cargo, quantity) {
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

		if (AICargo.IsFreight(cargo)) {
			result *= AIGameSettings.GetValue("vehicle.freight_trains")
		}
		return result;
	}	

	static function GetSlopeForce(slopedWeight, totalWeight) {
		return slopedWeight * AIGameSettings.GetValue("vehicle.train_slope_steepness") * 100 + totalWeight * 10;
	}
	
	static function GetForce(maxTractiveEffort, power, requestSpeed) {
		if(requestSpeed == 0) {
			HgLog.Warning("GetForce requestSpeed == 0");
			requestSpeed = 1;
		}
		return min((maxTractiveEffort * 1000), power * 746 * 18 / requestSpeed / 5);
	}
	
}

class CargoUtils {

	// 年間の予想収益
	// waitingDays: 積み下ろし時間
	static function GetCargoIncome(distance, cargo, speed, waitingDays=0, isBidirectional=false) {
		if(speed<=0) {
			return 0;
		}
		local days = max(1, distance*664/speed/24);
		
		local income = AICargo.GetCargoIncome(cargo,distance,days);
		return income * 365 / (days * 2 + waitingDays) * (isBidirectional ? 2 : 1);
	}
	
	static function IsPaxOrMail(cargo) {
		return HogeAI.GetPassengerCargo() == cargo || HogeAI.GetMailCargo() == cargo;
	}

}