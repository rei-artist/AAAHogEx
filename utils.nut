
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
		local cur = AIDate.GetCurrentDate();
		return AIDate.GetYear(cur)+"-"+AIDate.GetMonth(cur)+"-"+AIDate.GetDayOfMonth(cur);
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

class BuildUtils {
	static function RetryUntilFree(func, limit=1000) {
		for(local i=0;i<limit;i++) {
			if(func()) {
				return true;
			}
			if(AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY) {
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
		return false;
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

class RouteUtils {
	static function GetAllRoutes() {
		local routes = [];
		routes.extend(TrainRoute.GetAll());
		routes.extend(RoadRoute.instances);
		return routes;
	}
}

class HgTable {
	static function Extend(table1, table2) {
		foreach(k,v in table2) {
			table1.rawset(k,v);
		}
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

