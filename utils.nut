
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
	static instance = GeneratorContainer(function() {
		return PerformanceCounter();
	});
	
	table = {};
	startTick = 0;
	
	static function Start() {
		local self = PerformanceCounter.instance.Get();
		self.startTick = AIController.GetTick();
	}
	
	static function Stop(facility) {
		local self = PerformanceCounter.instance.Get();
		if (!(facility in self.table)) {
			self.table[facility] <- 0;
		}
		local dt = AIController.GetTick() - self.startTick;
		self.table[facility] += dt;
	}
	
	static function Print() {
		local self = PerformanceCounter.instance.Get();
		foreach(facility, time in self.table) {
			HgLog.Info(facility+" "+time);
		}
		self.table.clear();
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
		return min((maxTractiveEffort * 1000), power * 746 * 18 / requestSpeed / 5);
	}
	
}

