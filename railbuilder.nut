
class HgRailPathFinder extends Rail {
	_cost_level_crossing = 0;
	
	isFoundPath = false;
	
	constructor(cargo=null) {
		Rail.constructor();

		_cost_level_crossing = 900;
		_cost_crossing_reverse = 300;
		_cost_bridge_per_tile_ex = 130;
		_cost_tunnel_per_tile_ex  = 130;
		_cost_diagonal_tile = 67;
		_cost_diagonal_sea = 200;
		_cost_guide = 300; //20;
		_cost_under_bridge = 50;
		
		cost.tile = 100;
		cost.turn = 300;
		_cost_tight_turn = 1500;
		cost.bridge_per_tile = 20;
		cost.max_bridge_length = 11;
		
		cost.slope = 0;
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000 && cargo != null) {
			local trainPlanner = TrainPlanner();
			trainPlanner.cargo = cargo;
			trainPlanner.distance = 100;
			trainPlanner.production = 100;
			trainPlanner.limitWagonEngines = 1;
			trainPlanner.skipWagonNum = 2;
			local engineSets = trainPlanner.GetEngineSetsOrder();
			if(engineSets.len()>=1 && AIEngine.GetMaxTractiveEffort(engineSets[0].trainEngine) < 300) {// engineSet.trainEngine AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 500000) {
				HgLog.Info("pathfinding consider slope");
				cost.slope = 400;
			}
		}
		
		cost.coast = 0;
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 500000) {
			cost.tunnel_per_tile = 20;
			cost.max_tunnel_length = 11;
		} else {
			cost.tunnel_per_tile = 50;
			cost.max_tunnel_length = 6;
		}
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 2000000 && !HogeAI.Get().IsAvoidRemovingWater()) {
			_can_build_water = true;
			_cost_water = 20;
		}
	}
	
	function FindPathDay(limitDay,eventPoller) {
		return FindPath(null,eventPoller,limitDay);
	}
	
	function FindPath(limitCount,eventPoller,limitDay=null) {
		if(limitDay != null) {
			HgLog.Info("Pathfinding...limit date:"+limitDay);
		} else {
			HgLog.Info("Pathfinding...limit count:"+limitCount);
			limitCount *= 3;
		}
		local counter = 0;
		local path = false;
		local startDate = AIDate.GetCurrentDate();
		local endDate = limitDay != null ? startDate + limitDay : null;
		local totalInterval = 0;
		while (path == false && ((endDate!=null && AIDate.GetCurrentDate() < endDate + totalInterval) || (endDate==null && counter < limitCount))) {
			path = Rail.FindPath(50);
			counter++;
//			HgLog.Info("counter:"+counter);
			local intervalStartDate = AIDate.GetCurrentDate();
			if(eventPoller.OnPathFindingInterval()==false) {
				HgLog.Warning("FindPath break by OnPathFindingInterval");
				path = null;
				break;
			}
			totalInterval += AIDate.GetCurrentDate() - intervalStartDate;
		}
		if(path == false) { // 継続中
			path = _pathfinder._open.Peek();
		} else if(path != null) {
			HgLog.Info("Path found. (count:" + counter + " date:"+ (AIDate.GetCurrentDate() - startDate - totalInterval) +")");
			isFoundPath = true;
		} else {
			HgLog.Info("FindPath failed");
		}
		if(path != null) {
			path = Path.FromPath(path);
			if(!isFoundPath) {
				while(path != null && AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_RAIL)) {
					HgLog.Info("tail tile is on rail:"+path.GetTile());
					path = path.GetParent();
				}
			}
			path = RemoveConnectedHead(path);
			path = RemoveConnectedHead(path.Reverse()).Reverse();
		}
		return path;
	}

	function RemoveConnectedHead(path) {
		local prev = null;
		local prevprev = null;
		local lastPath = path;
		while(path != null) {
			if(prev != null && prevprev != null) {
				if(AIRail.AreTilesConnected (prevprev.GetTile(),prev.GetTile(),path.GetTile())) {
					lastPath = prev;
				} else {
					break;
				}
			}
			prevprev = prev;
			prev = path;
			path = path.GetParent();
		}
		return lastPath;
	}
		
	function IsFoundGoal() {
		return isFoundPath;
	}
	
	function _Cost(path, new_tile, new_direction, self)
	{
		if (path == null) return 0;

		local prev_tile = path.GetTile();

		local cost = ::Rail._Cost(path, new_tile, new_direction, self);
		if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_ROAD)) cost += self._cost_level_crossing;
			
		
		return cost;
	}
}

class Path {
	tile = null;
	parent_ = null;
	
	static nsewArray = [
			AIMap.GetTileIndex (-1, 0),
			AIMap.GetTileIndex (0, -1),
			AIMap.GetTileIndex (1 , 0),
			AIMap.GetTileIndex (0 , 1)];
	
	
	static function Load(data,i=0) {
		if(data.len() == i) {
			return null;
		}
		return Path(data[i], Path.Load(data,i+1));
	}
	
	constructor(tile,parent_) {
		this.tile = tile;
		this.parent_ = parent_;
	}
	
	function Save() {
		local result = [];
		local path = this;
		while(path != null) {
			result.push(path.tile);
			path = path.GetParent();
		}
		return result;
	}
	
	static function FromPath(path) {
		return Path(path.GetTile(),Path._SubPath(path.GetParent(),null,null));
	}
	
	function GetTile() {
		return tile;
	}
	
	function GetHgTile() {
		return HgTile(tile);
	}
	
	function GetParent() {
		return parent_;
	}
	
	function Reverse() {
		local result = null;
		local path = this;
		while(path != null) {
			result = Path(path.GetTile(),result);
			path = path.GetParent();
		}
		return result;
	}
	
	function Clone() {
		return _SubPath(this,null,null);
	}
	
	// 結果にentTileは含まれない
	function SubPathEnd(endTile) {
		return _SubPath(this,endTile,null);
	}
	
	// 結果にstartTileは含まれない
	function SubPathStart(startTile) {
		local r = Reverse().SubPathEnd(startTile);
		return r!=null ? r.Reverse() : null;
	}
	
	function SubPathStartInclude(startTile) {
		local path = this;
		while(path != null && path.GetTile() != startTile) {
			path = path.GetParent();
		}
		return _SubPath(path,null,null);
	}
	
	function SubPathEndInclude(endTile) {
		local r = Reverse().SubPathStartInclude(endTile);
		return r!=null ? r.Reverse() : null;
	}
	
	// 結果にindexは含まれない
	function SubPathIndex(index) {
		return SubPathStart(GetTileAt(index));
	}
	
	// 結果にindexは含まれない。
	function SubPathEndIndex(index) {
		return SubPathEnd(GetTileAt(index));
	}
	
	// 結果にindexは含まれない
	function SubPathLastIndex(index) {
		return SubPathEnd(GetLastTileAt(index));
	}
	
	function GetLastTile() {
		return Reverse().GetTile();
	}

	function GetLastTileAt(index) {
		return Reverse().GetTileAt(index);
	}

	function GetFirstTile() {
		return tile;
	}
	
	function GetTileAt(index) {
		local count = 0;
		local path = this;
		while(path != null) {
			if(count++ == index) {
				return path.GetTile();
			}
			path = path.GetParent();
		}
		return null;
	}
	
	function GetTiles() {
		local result = [];
		local path = this;
		while(path != null) {
			result.push(path.GetTile());
			path = path.GetParent();
		}
		return result;
	}
	
	function GetIndexOf(tile) {
		local count = 0;
		local path = this;
		while(path != null) {
			if(path.GetTile() == tile) {
				return count;
			}
			count ++;
			path = path.GetParent();
		}
		return null;
	}
	
	function GetPathArray() {
		local result = [];
		while(path != null) {
			result.push(path);
			path = path.GetParent();
		}
		return result;
	}
	
	function Combine(path) {
		return _SubPath(this,null,path);
	}

	static function _SubPath(path,endTile,combinePath) {
		if(path == null || path.GetTile() == endTile) {
			return combinePath;
		} else {
			return Path(path.GetTile(),Path._SubPath(path.GetParent(),endTile,combinePath));
		}
	}
	
	function GetTotalDistance() {
		local path = this;
		local result = 0;
		local prev = null;
		while(path != null) {
			if(prev != null) {
				result += AIMap.DistanceManhattan(prev, path.GetTile());
			}
			prev = path.GetTile();
			path = path.GetParent();
		}
		return result;
	}
	
	function RemoveRails(isTest=false) {
		local path = this;
		local prev = null;
		local prevprev = null;
		local result = true;
		while (path != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
					if(!AITile.DemolishTile (prev)) {
						if(isTest) {
							return false;
						} else {
							HgLog.Warning("DemolishTile failed."+HgTile(prev)+" "+AIError.GetLastErrorString());
							result = false;
						}
					}
					prevprev = prev;
					prev = path.GetTile();
					path = path.GetParent();
				} else {
					if(!RailBuilder.RemoveRailUntilFree(prevprev,prev,path.GetTile())) { // ポイント用にリトライ
						if(isTest) {
							return false;
						} else {
							HgLog.Warning("RemoveRail failed."+HgTile(prev)+" "+AIError.GetLastErrorString());
							result = false;
						}
					}
				}
			}
			if (path != null) {
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			}
		}
		return result;
	}
	
	
	function GetMeetsTiles() {
		local prevPath = GetParent();
		if(prevPath==null) {
			return [];
		}
		local prevprevPath = prevPath.GetParent();
		if(prevprevPath == null) {
			return [];
		}
		local prev = prevPath.GetTile();
		local prevprev = prevprevPath.GetTile();
		local next = GetTile();
		local straightFork = prev + (prev - next);
		if(straightFork != prevprev) {
			return [[next,prev,straightFork,prevprev]];
		} else {
			local result = [];
			foreach(p in nsewArray) {
				local fork = prev + p;
				if(fork != prevprev && fork!=next) {
					result.push([next,prev,fork,prevprev]);
				}
			}
			return result;
		}
		
	}
	
	
	function IterateRailroadPoints(func) {
		local path = this;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		
		while(path != null) {
			if(prevprev != null && prevprevprev != null) {
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1 || AIMap.DistanceManhattan(prev, prevprev) > 1) {
				} else {
					local prevprevDistance = AIMap.DistanceManhattan(prevprev, prevprevprev);
					if(prevprevDistance == 0) {
						HgLog.Warning("bug: Same tile is in one path:"+HgTile(prevprev));
					} else {
						local dirPrevprev = (prevprev - prevprevprev) / prevprevDistance;
						foreach(d in nsewArray) {
							local t = prev + d;
							if(d == -dirPrevprev || t == prevprev || t == path.GetTile()) {
								continue;
							}
							func(prevprev,prev,t,path.GetTile());
						}
					}
				}
			}
			if (path != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			}
		}
	}
			
	/*
	function IterateRailroadPoints(func,isFork=true) {
		local path = this;
		local prev = null;
		local prevprev = null;
		while (path != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
					prevprev = prev;
					prev = path.GetTile();
					path = path.GetParent();
				} else {
					local dirPrevprev = (prevprev - prev) / AIMap.DistanceManhattan(prev, prevprev);
					local actualPrevprev = isFork ? path.GetTile() : prev + dirPrevprev;
					local actualNext = !isFork ? path.GetTile() : prevprev;
					local straightFork = prev + (prev - actualPrevprev);
					if(straightFork != prevprev && straightFork != path.GetTile()) {
						func( actualPrevprev,prev,straightFork,actualNext);
					} else {
						foreach(p in nsewArray) {
							p = prev + p;
							if(p != prevprev && p!=path.GetTile()) {
								func( actualPrevprev,prev,p,actualNext);
							}
						}
					}
				}
			}
			if (path != null) {
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			}
		}
	}*/
	
	function BuildRailloadPoints(forkPath,isFork) {
		local a = forkPath.GetEndTileAndPrev();
		local endTile = a[0];
		local prevEndTile = a[1];
	
		local t = {
			buildPointsSuceeded = false
		}
		local path = isFork ? this : this.Reverse();
		path.IterateRailroadPoints(function(prevprev,prev,fork,next):(endTile,prevEndTile,isFork,t) {
			if(prev == endTile && fork == prevEndTile) {
				if(AIRail.AreTilesConnected (prevprev,prev,fork)) {
					HgLog.Warning("BuildRailloadPoints AreTilesConnected "+HgTile(prev)+" prevprev:"+HgTile(prevprev)+" fork:"+HgTile(fork));
					t.buildPointsSuceeded = true;
					return;
				}
				if(AIRail.GetSignalType(prev, prevprev) != AIRail.SIGNALTYPE_NONE) {
					RailBuilder.RemoveSignalUntilFree(prev, prevprev);
				}
				if(AIRail.GetSignalType(prev, next) != AIRail.SIGNALTYPE_NONE) {
					RailBuilder.RemoveSignalUntilFree(prev, next);
				}
				t.buildPointsSuceeded = RailBuilder.BuildRailUntilFree(prevprev,prev,fork);
				if(!t.buildPointsSuceeded) {
					HgLog.Warning("Fail BuildRailloadPoints "+HgTile(prev)+" prevprev:"+HgTile(prevprev)+" fork:"+HgTile(fork)+" "+AIError.GetLastErrorString());
				}/* else {
					HgLog.Warning("BuildRailloadPoints "+HgTile(prev)+" prevprev:"+HgTile(prevprev)+" fork:"+HgTile(fork));
				}*/
			} else if(next == endTile || prevprev == endTile) {
				local front = isFork ? next : prevprev;
				if(AIRail.GetSignalType(prev, front) == AIRail.SIGNALTYPE_NONE) {
					RailBuilder.BuildSignalUntilFree(prev, front, AIRail.SIGNALTYPE_PBS_ONEWAY);
				}
			}
			
		});
		if(!t.buildPointsSuceeded) {
			HgLog.Warning("BuildRailloadPoints failed.");
		}
		return t.buildPointsSuceeded;
	}
	
	function GetEndTileAndPrev() {
		local path = this;
		local prev = null;
		local prevprev = null;
		while (path != null) {
			prevprev = prev;
			prev = path.GetTile();
			path = path.GetParent();
		}
		return [prev,prevprev];
	}
	
	
	static function GetNearestTileDistance(fromTile) {
		local count = 0;
		local result = null;
		local path = this;
		while(path != null) {
			if(count++ % 10 == 0) {
				local d = HgTile(fromTile).DistanceManhattan(HgTile(path.GetTile()));
				if(result == null || d < result[1]) {
					result = [path.GetTile(),d];
				}
			}
			path = path.GetParent();
		}
		return result;
	}
	
	function BuildRailIfNothing(a,b,c) {
		if(AIRail.AreTilesConnected(a,b,c)) {
			return true;
		}
		return RailBuilder.BuildRailUntilFree(a,b,c);
	}
	
	function BuildDepot(vehicleType = AIVehicle.VT_RAIL) {
		if(vehicleType == AIVehicle.VT_RAIL) {
			return BuildDepotForRail();
		} else {
			local prevprev = null;
			local prev = null;
			local path = this;
			while(path != null) {
				if(prev != null) {
					if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
						prev = path.GetTile();
						path = path.GetParent();
					} else {
						local curHgTile = HgTile(prev);
						foreach(hgTile in curHgTile.GetDir4()) {
							if(hgTile.tile == path.GetTile() || hgTile.tile == prevprev) {
								continue;
							}
							if(curHgTile.BuildCommonDepot(hgTile.tile, prev, vehicleType)) {
								return hgTile.GetTileIndex();
							}
						}
					}
				}
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			}
			return null;
		}
	}
	
	
	function BuildDepotForRail() {
		local prev = null;
		local path = this;
		local p = array(5);
		while(path != null) {
			local c = path;
			local i=0;
			for(; c != null && i<5; i++) {
				p[i] = c.GetTile();
				c = c.GetParent();
			}
			if(i==5) {
				if(AIMap.DistanceManhattan(p[2], p[1]) > 1 || AIMap.DistanceManhattan(p[2], p[3]) > 1) {
				} else {
					foreach(dir in HgTile.DIR4Index) {
						local depot = p[2] + dir;
						if(AITile.IsBuildable(depot)) {
							local ng = false;
							foreach(dir2 in HgTile.DIR4Index) {
								local depotAround = depot + dir2;
								if(depotAround == p[0] || depotAround == p[4]) {
									ng = true;
									break;
								}
							}
							if(!ng) {
								if(HgTile(p[2]).BuildDepot(depot, p[1], p[3])) {
									return depot;
								}
							}
						}
					}
				}
			}
			path = path.GetParent();
		}
		return null;
	}
	
	
	function BuildDoubleDepot() {
		local prev = null;
		local path = this;
		local p = array(5);
		while(path != null) {
			local c = path;
			local i=0;
			local pre = null;
			for(; c != null && i<5; i++) {
				p[i] = c.GetTile();
				c = c.GetParent();
			}
			if(i==5) {
				
				if(AIMap.DistanceManhattan(p[2], p[1]) > 1 || AIMap.DistanceManhattan(p[2], p[3]) > 1) {
					} else {
					local ng = false;
					for(local i=0; i<3; i++) {
						if(p[i]-p[i+1]!=p[i+1]-p[i+2]) {
							ng = true;
							break;
						}
					}
					if(!ng) {
						foreach(dir in HgTile.DIR4Index) {
							local depot = p[2] + dir;
							if(AITile.IsBuildable(depot)) {
								local depots = HgTile(p[2]).BuildDoubleDepot(depot, p[2] - dir, p[1], p[3]);
								if(depots != null) {
									return depots;
								}
								break;
							}
						}
					}
				}
			}
			path = path.GetParent();
		}
		return [];
	}
	
	function GetSlopes(length) {
		length ++;
	
		local path = this;
		local maxSlopes = 0;
		
		while(path != null) {
			local c = path;
			local endHeight = AITile.GetMaxHeight (c.GetTile());
			endHeight += AIBridge.IsBridgeTile(c.GetTile()) ? 1 : 0; // TODO: 平らな橋
			local startTile = c.GetTile();
			local prev = null;
			for(local i=0;i<length;) {
				prev = c.GetTile();
				c = c.GetParent();
				if(c==null) {
					break;
				}
				local next = c.GetParent();
				local d = AIMap.DistanceManhattan(prev, c.GetTile());
				if(d>1) {
					i += d;
				} else {
					if(next != null && prev-c.GetTile() != c.GetTile()-next.GetTile()) {
						i += 0.7;
					} else {
						i ++;
					}
				}
			}
			local startHeight = endHeight;
			if(prev != null) {
				startHeight = AITile.GetMaxHeight(prev);
				startHeight += AIBridge.IsBridgeTile(prev) ? 1 : 0;
			}
			maxSlopes = max(endHeight - startHeight, maxSlopes);
			path = path.GetParent();
		}
		
		return maxSlopes;
		
	}
	
	function Dump() {
		local path = this;
		HgLog.Info("--- path dump start ---");
		while(path != null) {
			HgLog.Info(HgTile(path.GetTile()));
			path = path.GetParent();
		}
		return this;
	}
	
}

// 破壊してはいけないpath
class BuildedPath {
	static instances = {};
	static tileList = AIList();

	static function Contains(tile) {
		return BuildedPath.tileList.HasItem(tile);
	}
	
	static function AddTiles(tiles) { //hgstationからも呼ばれる
		foreach(tile in tiles) {
			BuildedPath.tileList.AddItem(tile,0);
		}
	}
	
	static function RemoveTiles(tiles) {
		foreach(tile in tiles) {
			BuildedPath.tileList.RemoveItem(tile);
		}
	}
	

	path = null;
	array_ = null; // saveを高速にするためのキャッシュ TODO: pathが書き変わったときにかきかえないといけない。
	
	constructor(path) {
		this.path = path;
		BuildedPath.instances.rawset(this,this);
		array_ = path.GetTiles();
		BuildedPath.AddTiles(array_);
	}
	
	function ChangePath() {
		array_ = path.GetTiles();
		BuildedPath.AddTiles(array_);
	}

	function Remove(removeRails = true) {
		if(removeRails) {
			path.RemoveRails();
		}
		BuildedPath.instances.rawdelete(this);
		//BuildedPath.RemoveTiles(path.GetTiles()); 連結部分など他と重複している箇所があるので残す。残っていても実害はほとんど無い
	}
	
	
	function CombineByFork(forkBuildedPath, isFork=true) {
		local origPath = this.path;
		local forkPath = forkBuildedPath.path;
		if(!isFork) {
//			origPath.BuildRailloadPoints(forkPath,false);
			origPath = origPath.Reverse();
			forkPath = forkPath.Reverse();
		} else {
//			origPath.BuildRailloadPoints(forkPath.Reverse(),true);
		}
		
		
		if(forkPath.GetParent() != null) {
			if(origPath.GetIndexOf(forkPath.GetParent().tile) != null) {
				forkPath = forkPath.GetParent();
				HgLog.Info("origPath.GetIndexOf("+HgTile(forkPath.tile)+")!=null at BuildedPath.CombineByFork(railbuilder.nut)");
			}
		}
		local pointTile = forkPath.tile;

		local remainPath = origPath.SubPathEnd(pointTile);
		local pointIndex = origPath.GetIndexOf(pointTile);
		local removePath = origPath.SubPathIndex(pointIndex-1);
				
		local newPath = remainPath.Combine(forkPath);
		if(!isFork) {
			newPath = newPath.Reverse();
		}
		if(newPath.GetIndexOf(pointTile)==null) {
			HgLog.Error("pointTile:"+HgTile(pointTile)+" is not contains newPath at BuildedPath.CombineByFork(railbuilder.nut)");
		}
		local result = BuildedPath(newPath);
	
		this.Remove(false);
		forkBuildedPath.Remove(false);
		return [removePath, result];
	}
	
	function CombineAndRemoveByFork(forkBuildedPath, isFork=true) {
		local a = CombineByFork(forkBuildedPath, isFork);
		a[0].RemoveRails()
		return a[1];
	}
}



class RailBuilder {
	static function RemoveSignalUntilFree(p1,p2) {
		return BuildUtils.RetryUntilFree( function():(p1,p2) {
			return AIRail.RemoveSignal(p1,p2);
		});
	}

	static function BuildSignalUntilFree(p1,p2,t) {
		return BuildUtils.RetryUntilFree( function():(p1,p2,t) {
			return AIRail.BuildSignal(p1,p2,t);
		});
	}

	static function BuildRailUntilFree(p1,p2,p3) {
		return BuildUtils.RetryUntilFree( function():(p1,p2,p3) {
			return AIRail.BuildRail(p1,p2,p3);
		});
	}
	
	static function RemoveRailUntilFree(p1,p2,p3) {
		return BuildUtils.RetryUntilFree( function():(p1,p2,p3) {
			return AIRail.RemoveRail(p1,p2,p3);
		});
	}

	static function RemoveRailTrackUntilFree(p, tracks) {
		return BuildUtils.RetryUntilFree( function():(p,tracks) {
			return AIRail.RemoveRailTrack(p,tracks);
		});
	}
	
	pathSrcToDest = null;
	isReverse = false;
	ignoreTiles = null;
	eventPoller = null;
	buildedPath = null;

	constructor(pathSrcToDest,isReverse,ignoreTiles,eventPoller) {
		this.pathSrcToDest = pathSrcToDest;
		this.isReverse = isReverse;
		this.ignoreTiles = ignoreTiles;
		this.eventPoller = eventPoller;
	}

	
	function CreatePathFinder() {
		return HgRailPathFinder();
	}
	
	function FindPath(pathFinder,limitCount,eventPoller) {
		local result = pathFinder.FindPath(limitCount,eventPoller);
		if(pathFinder.IsFoundGoal()) {
			return result;
		} else {
			return null;
		}
	}

	
	function Build() {
		local execMode = AIExecMode();
		if(pathSrcToDest == null) {
			return false;
		}
		local path = pathSrcToDest;
		local prevPath = null;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		local signalCount = 0;
		while (path != null) {
			if (prevprev != null) {
				path = RaiseTileIfNeeded(prevPath,prevprev);
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
					if(prevprevprev!=null) {
						BuildSignal(prevprevprev, prevprev, prev);
					}
					if(!AITile.IsBuildable(prev)) {
						HgLog.Warning("Demolish tile for bridge or tunnel start:"+HgTile(prev)+"(end:"+HgTile(path.GetTile())+")");
						AITile.DemolishTile(prev);
					}
					if(!AITile.IsBuildable(path.GetTile())) {
						HgLog.Warning("Demolish tile for bridge or tunnel end:"+HgTile(path.GetTile())+"(start:"+HgTile(prev)+")");
						AITile.DemolishTile(path.GetTile());
					}
					if (AITunnel.GetOtherTunnelEnd(prev) == path.GetTile()) {
						HogeAI.WaitForMoney(50000);
						if(!AITunnel.BuildTunnel(AIVehicle.VT_RAIL, prev)) {
							HgLog.Warning("BuildTunnel failed."+HgTile(prev)+" "+AIError.GetLastErrorString());
							if(AIError.GetLastError() == AITunnel.ERR_TUNNEL_CANNOT_BUILD_ON_WATER) {
//								AIController.Break("");
							}
							return RetryToBuild(path,prev);
						}
					} else {
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), prev) + 1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.Sort(AIList.SORT_BY_VALUE, false);
						HogeAI.WaitForMoney(20000);
						if(!AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, path.GetTile())) {
							local bridgeLastError = AIError.GetLastErrorString();
							//HgLog.Error("BuildBridge failed("+HgTile(prev)+"-"+HgTile(path.GetTile())+":"+AIError.GetLastErrorString()+").");
							if(prevprevprev == null) {
								HgLog.Warning("BuildBridge failed("+HgTile(prev)+"-"+HgTile(path.GetTile())+":"+AIError.GetLastErrorString()+")."
									+" And cannot try to build tunnel(prevprevprev==null)")
								return RetryToBuild(path,prev);
							} else if(!BuildTunnel(path,prev,prevprev,prevprevprev)) {
								HgLog.Warning("BuildBridge and BuildTunnel failed."+HgTile(prev)+"-"+HgTile(path.GetTile())+" "+bridgeLastError+","+AIError.GetLastErrorString());
								if(AIError.GetLastError() == AITunnel.ERR_TUNNEL_CANNOT_BUILD_ON_WATER) {
//									AIController.Break("");
								}
								return RetryToBuild(path,prev);
							}
						}
					}
					signalCount = 0;
					prevprevprev = prevprev;
					prevprev = prev;
					prev = path.GetTile();
					prevPath = path;
					path = path.GetParent();
					if(path != null) {
						path = RaiseTileIfNeeded(prevPath,prevprev);
					}
				} else {
					TownBus.Check(prev);
					
					if(Rail.CanDemolishRail(prev)) {
						HgLog.Warning("demolish tile for buildrail:"+HgTile(prev));
						AITile.DemolishTile(prev);
					}
					local isGoalOrStart = (prevprevprev == null && AITile.HasTransportType(prevprev,AITile.TRANSPORT_RAIL)) 
						|| (path.GetParent()==null && AITile.HasTransportType(path.GetTile(),AITile.TRANSPORT_RAIL)); //HasTransportTypeの判定は多分必要ないが害もなさそうなので残す
						/*|| path.GetParent().GetParent()==null  必要なChangeBridgeがされない事があった。isReverseで判定必要かも？ */;
					if(!HgTile.IsDiagonalTrack(AIRail.GetRailTracks(prev))) {
						if(!isGoalOrStart && AITile.HasTransportType(prev, AITile.TRANSPORT_RAIL) && BuildedPath.Contains(prev)) {		
							if(!ChangeBridge(prev,path.GetTile())) {
								return RetryToBuild(path,prev);
							}
						}
					}
					
					HogeAI.WaitForMoney(1000);
					if(!(isGoalOrStart && AIRail.AreTilesConnected(prevprev, prev, path.GetTile())) 
							&& !RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
						local succeeded = false;
						HgLog.Warning("BuildRail failed:"+HgTile(prevprev)+" "+HgTile(prev)+" "+HgTile(path.GetTile())+" "+AIError.GetLastErrorString()+" isGoalOrStart:"+isGoalOrStart);
						if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR && !BuildedPath.Contains(prev)) {
							HgLog.Warning("DemolishTile:"+HgTile(prev)+" for BuildRail");
							AITile.DemolishTile(prev);
							if(RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
								HgLog.Warning("BuildRail succeeded after DemolishTile.");
								succeeded = true;
							}
						}
						if(!succeeded && isGoalOrStart) {
							foreach(dir in HgTile.DIR4Index) {
								RailBuilder.RemoveSignalUntilFree(prev,prev+dir);
							}
							if(RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
								HgLog.Warning("BuildRail succeeded after remove signal.");
								succeeded = true;
							}
						}
						if(!succeeded) {
							return RetryToBuild(path,prev);
						}
					}
					if(signalCount % 4 == 0 ) {
						if(BuildSignal(prevprev,prev,path.GetTile())) {
							signalCount ++;
						}
					} else {
						signalCount ++;
					}
				}
			}
			if (path != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = path.GetTile();
				prevPath = path;
				path = path.GetParent();
			}
		}
		if(prevprevprev != null && prevprev != null && prev != null) {
			BuildSignal(prevprevprev,prevprev,prev);
		}
		
		BuildDone();
		return true;
	}
	
	function RetryToBuild(path,tile) {
		HgLog.Info("RetryToBuild start");
/*		
		local endAndPrev = path.GetEndTileAndPrev();
		local goalPath = Path(endAndPrev[1],Path(endAndPrev[0]],null));
		local startPath = pathSrcToDest.SubPathEnd(tile);
		local builder = TailedRailBuilder.PathToPath(Container(isReverse?goalPath:startPath), Container(isReverse?startPath:goalPath), ignoreTiles, 150, eventPoller);
		if(!builder.BuildTails()) {
			HgLog.Warning("RetryToBuild failed");
			return false;
		}
		if(!builder.IsFoundGoal()) {
			if(!builder.Build()) {
				builder.Remove();
				HgLog.Warning("RetryToBuild failed");
				return false;
			}
		}
		local newPath = builder.buildedPath.path.Reverse();
		local origPath = startPath.SubPathEnd(newPath.GetFirstTile());
		startPath.SubPathIndex(startPath.GetIndexOf(newPath.GetFirstTile())-1).RemoveRails();
		pathSrcToDest = origPath.Combine(newPath);
		builder.buildedPath.Remove(false);
		BuildDone();
		HgLog.Warning("RetryToBuild succeeded");
		return true;*/

		
		/*
		if(endAndPrev[1]==null || !HogeAI.IsBuildable(endAndPrev[1])) {
			HgLog.Warning("goal is not buildable");
			return false;
		}*/
		local endAndPrev = path.GetEndTileAndPrev();
		if(endAndPrev[0]==null || endAndPrev[1]==null) {
			HgLog.Warning("retry to build failed(endAndPrev[0]==null || endAndPrev[1]==null)");
			return false;
		}
		
		local goalsArray = [[endAndPrev[1],endAndPrev[0]]];
		local startPath = pathSrcToDest.SubPathEnd(tile);
		local tmpBuildedPath = BuildedPath(startPath);
		local railBuilder = RailToAnyRailBuilder(isReverse?startPath.Reverse():startPath, goalsArray, ignoreTiles, !isReverse, 150, eventPoller);
		local result = railBuilder.Build();
		tmpBuildedPath.Remove(false);
		if(result) {
			local newPath = railBuilder.pathSrcToDest.Reverse();
			local origPath = startPath.SubPathEnd(newPath.GetFirstTile());
			
			startPath.SubPathIndex(startPath.GetIndexOf(newPath.GetFirstTile())-1).RemoveRails();
			pathSrcToDest = origPath.Combine(newPath);
			BuildDone();
			HgLog.Warning("retry to build succeeded");
			return true;
		} else {
			HgLog.Warning("retry to build failed");
			return false;
		}
	}
	
	function BuildDone() {
		buildedPath = BuildedPath(isReverse?pathSrcToDest.Reverse():pathSrcToDest);
	}
	
	function BuildSignal(prevprev,prev,next) {
		if(prevprev==null) {
			return false;
		}
		if(!isReverse) {
			AIRail.RemoveSignal (prev, next);
			return AIRail.BuildSignal(prev,next,AIRail.SIGNALTYPE_PBS_ONEWAY);
		} else {
			AIRail.RemoveSignal (prev, prevprev);
			return AIRail.BuildSignal(prev,prevprev,AIRail.SIGNALTYPE_PBS_ONEWAY);
		}
	}
	
	function BuildTunnel(path,prev,prevprev,prevprevprev) {
		local d=prev-prevprev;
		if(d != prevprev-prevprevprev) {
			return false;
		}
		AIRail.RemoveRail(prevprevprev,prevprev,prev);
		local from = prevprev;
		if(path.GetParent() == null) {
			HgLog.Warning("BuildTunnel failed(path.GetParent() == null)");
			return false;
		}
		local to = path.GetParent().GetTile();
		local dir = HgTile(from).GetDirection(HgTile(to));
		foreach(corner in HgTile.GetCorners(dir)) {
			AITile.LowerTile(from, HgTile.GetSlopeFromCorner(corner));
		}
		foreach(corner in HgTile.GetCorners(HgTile.GetOtherSideDir(dir))) {
			AITile.LowerTile(to, HgTile.GetSlopeFromCorner(corner));
		}
		if (AITunnel.GetOtherTunnelEnd(from+d) == to-d) {
			HogeAI.WaitForMoney(50000);
			if (AIRail.BuildRail(from-d, from, from+d) && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, from+d)) {
				return true;
			}
		}
		return false;
	}
	
	function RaiseTileIfNeeded(prevpath,prevprev) {
		local prev = prevpath.GetTile();
		local path = prevpath.GetParent();
		if(path == null) {
			return path;
		}
		local dir = prev - prevprev;
		local cur = path;
		local prevprevcur;
		local prevcur;
		local tprevprev = null;
		local tprev = null;
		local t0 = prev;
		local t1 = cur.GetTile();
		local raise = false;
		local i=0;
		local notSea = false;
		local notStraight = false;
		local notSkip = false;
		if(AIBridge.IsBridgeTile (prevprev)) {	
			notSkip = true;
		} else {
			while(true) {
				if(AIMap.DistanceManhattan(t0,t1)>1 || Rail._IsUnderBridge(t1)) { // 橋の下に橋は作れない
					notSkip = true;
					break;
				}
				local boundCorner = HgTile.GetCorners( HgTile(t0).GetDirection(HgTile(t1)) );
				if(!(AITile.GetCornerHeight(t0,boundCorner[0]) == 0 && AITile.GetCornerHeight(t0,boundCorner[1]) == 0)) {
					notSea= true;
				}
				if(t1 - t0 != dir) {
					notStraight = true;
				}
				if(notSea || notStraight || i==5) {
					break;
				}
				i++;
				prevprevcur = prevcur;
				prevcur = cur;
				cur = cur.GetParent();
				tprevprev = tprev;
				tprev = t0;
				t0 = t1;
				if(cur == null) {
					notSkip = true;
					break;
				}
				t1 = cur.GetTile();
			}
		}
		if(notSkip) {
			t0 = prev;
			t1 = path.GetTile();
			if(AIMap.DistanceManhattan(t0,t1)==1) {
				Raise(t0,t1);
			} else {
				Raise(t0, t0+dir);
				Raise(t1-dir, t1);
				Raise(t1, t1+dir);
			}
			return path;
		} else {
			if(i==0) {
				if(notStraight && !notSea) {
					raise = true;
				}
			} else if(i==1) {
				t1 = t0;
				t0 = tprev;
				cur = prevcur;
				raise = true;
			} else if(i==2) {
				if(notStraight) {
					cur = prevprevcur;
					t1 = tprev;
					t0 = tprevprev;
					raise = true;
				} else {
					cur = prevcur;
				}
			} else if(i>=3) {
				if(notStraight) {
					cur = prevprevcur;
					t1 = t0;
					t0 = tprev;
					raise = true;
				} else {
					cur = prevcur;
					if(!notSea) {
						raise = true;
					}
				}
			}
		}
		if(cur != path) {
			prevpath.parent_ = cur;
		}
		
		if(raise) {
			Raise(t0,t1);
		}
		return cur;
	}
	
	function Raise(t0,t1) {
		local boundCorner = HgTile.GetCorners( HgTile(t0).GetDirection(HgTile(t1)) );
		if(AITile.GetCornerHeight(t0,boundCorner[0]) >= 1 || AITile.GetCornerHeight(t0,boundCorner[1]) >= 1) {	
			return true; //no need to raise
		}
		local result = BuildUtils.RetryUntilFree(function():(t0,boundCorner) {
			local success = false;
			if(TileListUtil.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[1]))) {
				success = true;
			}
			if(!success && TileListUtil.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[0]))) {
				success = true;
			}
			return success;
		});
		if(!result) {
			HgLog.Warning("Raise failed:"+HgTile(t0)+"-"+HgTile(t1)+" "+AIError.GetLastErrorString());
		}
		return result;
	}
	

	function ChangeBridge(prev,next) {
		HgLog.Info("ChangeBridge: "+HgTile(prev)+"-"+HgTile(next));
		local orgPath = GetBuildedPath(prev);
		if(orgPath == null || orgPath.GetParent()==null || AIMap.DistanceManhattan(orgPath.GetTile(),orgPath.GetParent().GetTile())!=1) {
			HgLog.Warning("ChangeBridge failed.(Illegal existing rail)"+HgTile(prev));
			return false;
		}
		local direction = orgPath.GetTile() - orgPath.GetParent().GetTile();
		
		local tracks = AIRail.GetRailTracks(prev);
		local removed = [];
		if(tracks == AIRail.RAILTRACK_NE_SW) {
		} else if(tracks == AIRail.RAILTRACK_NW_SE) {
		} else {
			HgLog.Warning("unexpected tracks."+HgTile(prev)+" "+tracks);
			return false;
		}
		
		local n_node = prev - direction;
		if(prev + direction == next) {
		} else if(prev - direction == next) {
			n_node = n_node - direction;
		}
		
		HogeAI.WaitForMoney(20000);
		local currentRailType = AIRail.GetCurrentRailType();
		AIRail.SetCurrentRailType(AIRail.GetRailType(n_node));
		local startTile = n_node;
		local endTile = null;

		for(local i=0; i<4; i++) {
			if(i==3 && (Rail._IsSlopedRail(n_node - direction, n_node, n_node + direction) || AIRail.GetRailTracks(n_node) != tracks)) {
				break;
			}
			if(!RailBuilder.RemoveRailTrackUntilFree(n_node, tracks)) {
				HgLog.Warning("fail RemoveRailTrack."+HgTile(n_node)+" "+AIError.GetLastErrorString());
				foreach(mark in removed) {
					AIRail.BuildRailTrack(mark[0], mark[1]);
				}
				AIRail.SetCurrentRailType(currentRailType);
				return false;
			}
			removed.push([n_node,tracks]);
			endTile = n_node;
			n_node += direction;
		}
		
		local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(startTile, endTile) + 1);
		bridge_list.Valuate(AIBridge.GetMaxSpeed);
		bridge_list.Sort(AIList.SORT_BY_VALUE, false);
		if(!AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), startTile, endTile)) {
			HgLog.Warning("fail BuildBridge "+HgTile(startTile)+"-"+HgTile(endTile)+" "+AIError.GetLastErrorString());
			foreach(mark in removed) {
				AIRail.BuildRailTrack(mark[0], mark[1]);
			}
			AIRail.SetCurrentRailType(currentRailType);
			return false;
		}
		
		ChangeBridgeBuildedPath(startTile, endTile);
		
		AIRail.SetCurrentRailType(currentRailType);
		return true;
	}
	
	
	function ChangeBridgeBuildedPath(startTile, endTile) {
		local succeeded = false;
		foreach(path,v in BuildedPath.instances) {
			if(ChangeBridgePath(path.path, startTile, endTile)) {
				path.ChangePath();
				succeeded = true;
			}
		}
		if(!succeeded) {
			HgLog.Warning("ChangeBridgeBuildedPath not found path "+HgTile(startTile)+" "+HgTile(endTile));
		}
	}
	
	function ChangeBridgePath(path, startTile, endTile) {
		local prevprev = null;
		local prev = null;
		while(path != null) {
			if(prev != null && (path.GetTile() == startTile || path.GetTile() == endTile)) {
				AIRail.RemoveSignal (prev, path.GetTile());
				AIRail.BuildSignal(prev, path.GetTile(), AIRail.SIGNALTYPE_PBS_ONEWAY);
				local startPath = path;
				path = path.GetParent();
				while(path != null) {
					if(path.GetTile() == endTile || path.GetTile() == startTile) {
						startPath.parent_ = path;
						if(path.GetParent()!=null && path.GetParent().GetParent()!=null) {
							AIRail.RemoveSignal (path.GetParent().GetTile(), path.GetParent().GetParent().GetTile());
							AIRail.BuildSignal( path.GetParent().GetTile(), path.GetParent().GetParent().GetTile(), AIRail.SIGNALTYPE_PBS_ONEWAY);
						}
						return true;
					}
					path = path.GetParent();
				}
			} else {
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			}
		}
		return false;
	}
	
	function GetBuildedPath(t) {
		foreach(path,v in BuildedPath.instances) {
			local c = path.path;
			while(c != null) {
				if(c.GetTile() == t) {
					return c;
				}
				c = c.GetParent();
			}
		}
		return null;
	}
}

class TailedRailBuilder {
	static function StationToStation(srcStation, destStation, cargo, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetArrivalsTile());
		ignoreTiles.extend(destStation.GetDeparturesTile());
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		return TailedRailBuilder(
			Container(srcStation.GetDeparturesTiles()), 
			Container(destStation.GetArrivalsTiles()),
			ignoreTiles, cargo, limitCount, eventPoller, reversePath);
	}
	static function StationToStationReverse(srcStation, destStation, cargo, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		local result = TailedRailBuilder(
			Container(srcStation.GetArrivalsTiles()), 
			Container(destStation.GetDeparturesTiles()),
			ignoreTiles, cargo, limitCount, eventPoller, reversePath);
		result.isReverse = true;
		return result;
	}
	static function ReverseArrayTiles(a) {
		local result = [];
		foreach(n in a) {
			HgLog.Info("ReverseArrayTiles:"+HgTile(n[1])+","+HgTile(n[0]));
			result.push([n[1],n[0]]);
		}
		return result;
	}
	
	static function PathToStation(srcPathGetter, destStation, cargo, limitCount, eventPoller, reversePath = null, isArrival = true) {
		local ignoreTiles = [];
		ignoreTiles.extend(isArrival ? destStation.GetDeparturesTile() : destStation.GetArrivalsTile());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		return TailedRailBuilder(
			GetterFunction(function():(srcPathGetter) {
				return TailedRailBuilder.GetStartArray(srcPathGetter.Get().Reverse());
			}),
			Container(isArrival ? destStation.GetArrivalsTiles() : destStation.GetDeparturesTiles()), 
			ignoreTiles, cargo, limitCount, eventPoller, reversePath);
	}
	
	static function StationToPath(srcStation, destPathGetter, cargo, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetArrivalsTile());
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		return TailedRailBuilder(
			Container(srcStation.GetDeparturesTiles()), 
			GetterFunction(function():(destPathGetter){
				local path = destPathGetter.Get().SubPathIndex(10);
				if(path == null) {
					return [];
				}
				return TailedRailBuilder.GetGoalArray(path.Reverse());
			}), 
			ignoreTiles, cargo, limitCount, eventPoller, reversePath);
	}
	
	static function PathToPath(srcPathGetter, destPathGetter, ignoreTiles, cargo, limitCount, eventPoller, reversePath = null) {
		return TailedRailBuilder(
			GetterFunction(function():(srcPathGetter) {
				return TailedRailBuilder.GetStartArray(srcPathGetter.Get().Reverse());
			}),
			GetterFunction(function():(destPathGetter){
				local path = destPathGetter.Get().SubPathIndex(10);
				if(path == null) {
					return [];
				}
				return TailedRailBuilder.GetGoalArray(path.Reverse());
			}), 
			ignoreTiles, cargo, limitCount, eventPoller, reversePath);
	}

	static function GetStartArray(path) {
		local result = [];
		local prevprev = null;
		local prev = null;
		while(path != null) {
			if(prev != null && prevprev != null) {
				result.push([path.GetTile(), prev, prevprev]);
			}
			prevprev = prev;
			prev = path.GetTile();
			path = path.GetParent();
		}
		return result;
		
		/*
		if(path==null)  {
			return result;
		}
		path.IterateRailroadPoints(function(prevprev,prev,fork,next):(result) {
			if(HogeAI.IsBuildable(fork) && RailToAnyRailBuilder.IsForkable(prevprev,prev,fork)) {
				result.push([fork,prev]);
			}
		});
		return result;*/
	}
	
	static function GetGoalArray(path) {
		local result = [];
		local prev = null;
		while(path != null) {
			if(prev != null) {
				result.push([prev, path.GetTile()]);
			}
			prev = path.GetTile();
			path = path.GetParent();
		}
		return result;
		
/*		local result = [];
		if(path==null)  {
			return result;
		}
		path.Reverse().IterateRailroadPoints(function(prevprev,prev,fork,next):(result) {
			if(HogeAI.IsBuildable(fork) && RailToAnyRailBuilder.IsForkable(prevprev,prev,fork)) {
				result.push([fork,prev]);
			}
		});
		return result;*/
	}
	
	static function GetGoalArrayByPath(path) {
		//local path = path.Reverse();
		local result = [];
		local prev = null;
		local prevprev = null;
		local next = 1;
		local counter = 0;
		while(path != null) {
			if(prev != null) {
				if(prevprev != null) {
					if(!Rail._IsSlopedRail(path.GetTile(), prev, prevprev)) {
						if(++counter == next) {
							result.push([prev, path.GetTile()]);
							next *= 2;
						}
					}
				} else {
					if(++counter == next) {
						result.push([prev, path.GetTile()]);
						next *= 2;
					}
				}
			}
			prevprev = prev;
			prev = path.GetTile();
			path = path.GetParent();
		}/*
		foreach(p in result) {
			HgLog.Info("goal:"+HgTile(p[0])+"-"+HgTile(p[1]));
		}*/
		return result;
		
	}

	srcTilesGetter = null;
	destTilesGetter = null;
	ignoreTiles = null;
	cargo = null;
	limitCount = null;
	eventPoller = null;
	reversePath = null;
	
	buildedPath = null;
	isReverse = null;
	
	ignoreTiles = null;
	isFoundGoal = null;
	buildedPath1 = null;
	buildedPath2 = null;
	
	
	constructor(srcTilesGetter, destTilesGetter, ignoreTiles, cargo, limitCount, eventPoller, reversePath = null, isReverse = false) {
		this.srcTilesGetter = srcTilesGetter;
		this.destTilesGetter = destTilesGetter;
		this.ignoreTiles = ignoreTiles;
		this.cargo = cargo;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.reversePath = reversePath;
		this.isReverse = false;
	}
	
	function BuildTails() {
		isFoundGoal = false;

		local pathFinder1 = HgRailPathFinder(cargo);
		local starts = srcTilesGetter.Get();
		local goals = destTilesGetter.Get();
		if(starts.len()==0) {
			HgLog.Warning("No start(TailedRailBuilder.pathFinder1)");
			return false;
		}
		if(goals.len()==0) {
			HgLog.Warning("No goal(TailedRailBuilder.pathFinder1)");
			return false;
		}
		pathFinder1.InitializePath(starts, goals, ignoreTiles, reversePath);
		local path1 = pathFinder1.FindPathDay(limitCount, eventPoller);
		if(path1==null) {
			HgLog.Warning("No path found(TailedRailBuilder.pathFinder1)");
			return false;
		}
		local railBuilder1 = RailBuilder(path1.Reverse(),!isReverse,ignoreTiles,eventPoller);
		if(!railBuilder1.Build()) {
			HgLog.Warning("TailedRailBuilder.railBuilder1.Build failed.");
			return false;
		}
		buildedPath1 = railBuilder1.buildedPath;
		if(pathFinder1.IsFoundGoal()) {
			buildedPath = buildedPath1;
			isFoundGoal = true;
			return true;
		}
		
		goals = TailedRailBuilder.GetGoalArrayByPath(isReverse ? buildedPath1.path.Reverse() : buildedPath1.path);
		if(goals.len()==0) {
			HgLog.Warning("No goal(TailedRailBuilder.pathFinder2)");
			return false;
		}
		local pathFinder2 = HgRailPathFinder(cargo);
		pathFinder2.InitializePath(destTilesGetter.Get(), goals, ignoreTiles, reversePath);
		local path2 = pathFinder2.FindPathDay(limitCount*2, eventPoller);
		if(path2==null) {
			HgLog.Warning("No path found(TailedRailBuilder.pathFinder2)");
			buildedPath1.Remove();
			return false;
		}
		local railBuilder2 = RailBuilder(path2.Reverse(),isReverse,ignoreTiles,eventPoller);
		if(!pathFinder2.IsFoundGoal()) {
			HgLog.Warning("No path found(TailedRailBuilder.pathFinder2 timed out)");
			return false;
		}
			
		if(!railBuilder2.Build()) {
			HgLog.Warning("TailedRailBuilder.railBuilder2.Build failed.");
			buildedPath1.Remove();
			return false;
		}
		/*
		railBuilder2.buildedPath.path = railBuilder2.buildedPath.path.Reverse();
		railBuilder2.buildedPath.ChangePath();*/
		buildedPath2 = railBuilder2.buildedPath;
		
		if(pathFinder2.IsFoundGoal()) {
			isFoundGoal = true;
			buildedPath = buildedPath1.CombineAndRemoveByFork(buildedPath2,isReverse);
			return true;
		}
		if(TailedRailBuilder.GetStartArray(buildedPath2.path).len()==0) {
			HgLog.Warning("No start(TailedRailBuilder.pathFinder2)");
			return false;
		}
		return true;
	}
	
	
	function Build() {
		local starts = TailedRailBuilder.GetStartArray(buildedPath2.path);
		local goals = TailedRailBuilder.GetGoalArray(buildedPath1.path.SubPathEndIndex(10));
		if(starts.len()==0) {
			HgLog.Warning("No start (pathFinder3)");
			return false;
		}
		if(goals.len()==0) {
			HgLog.Warning("No goal (pathFinder3)");
			return false;
		}
		local pathFinder3 = HgRailPathFinder(cargo);
		pathFinder3.InitializePath(starts, goals, ignoreTiles, reversePath);
		local path3 = pathFinder3.FindPathDay(150, eventPoller);
		if(path3 == null || !pathFinder3.IsFoundGoal()) {
			HgLog.Warning("No path found(pathFinder3)");
			return false;
		}
		isFoundGoal = true;
		local railBuilder3 = RailBuilder(path3,!isReverse,ignoreTiles,eventPoller);
		if(!railBuilder3.Build()) {
			HgLog.Warning("railBuilder3.Build failed.");
			return false;
		}
		local buildedPath3 = railBuilder3.buildedPath;
		
		
		buildedPath = buildedPath1.CombineAndRemoveByFork(buildedPath3,isReverse);
		buildedPath = buildedPath2.CombineAndRemoveByFork(buildedPath,!isReverse);
		return true;
	}
	
	function Remove() {
		if(buildedPath1 != null) {
			buildedPath1.Remove();
		}
		if(buildedPath2 != null) {
			buildedPath2.Remove();
		}
	}
	
	function IsFoundGoal() {
		return isFoundGoal;
	}
}

class TwoWayPathToStationRailBuilder {
	pathDepatureGetter = null;
	pathArrivalGetter = null;
	destHgStation = null;
	cargo = null;
	limitCount = null;
	eventPoller = null;

	isBuildDepotsDestToSrc = null;

	buildedPath1 = null;
	buildedPath2 = null;
	depots = null;
	
	constructor(pathDepatureGetter, pathArrivalGetter, destHgStation, cargo, limitCount, eventPoller) {
		this.pathDepatureGetter = pathDepatureGetter;
		this.pathArrivalGetter = pathArrivalGetter;
		this.destHgStation = destHgStation;
		this.cargo = cargo;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.isBuildDepotsDestToSrc = false;
		this.depots = [];
	}
	
	function Build() {
		
		local b1 = TailedRailBuilder.PathToStation(pathDepatureGetter, destHgStation, cargo, limitCount, eventPoller );
		if(!b1.BuildTails()) {
			RemoveDepots();
			return false;
		}
		buildedPath1 = b1.buildedPath;
		if(isBuildDepotsDestToSrc) {
			depots.extend(buildedPath1.path.Reverse().SubPathIndex(4).BuildDoubleDepot());
		}
		
		local b2 = TailedRailBuilder.PathToStation(pathArrivalGetter, destHgStation, cargo, limitCount, eventPoller,buildedPath1.path, false );
		b2.isReverse = true;
		if(!b2.BuildTails()) {
			b1.Remove();
			return false;
		}
		buildedPath2 = b2.buildedPath;
		if(isBuildDepotsDestToSrc) {
			
			depots.extend(buildedPath2.path.Reverse().SubPathIndex(4).BuildDoubleDepot());
		}
		return true;
	}
	
	function RemoveDepots() {
		foreach(depot in depots) {
			AITile.DemolishTile(depot);
		}
	}
}

class TwoWayStationRailBuilder {
	srcHgStation = null;
	destHgStation = null;
	cargo = null;
	limitCount = null;
	eventPoller = null;
	
	buildedPath1 = null;
	buildedPath2 = null;
	
	constructor(srcHgStation, destHgStation, cargo, limitCount, eventPoller) {
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.cargo = cargo;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
	}
	
	function Build() {
		local b2 = TailedRailBuilder.StationToStation(destHgStation, srcHgStation, cargo, limitCount, eventPoller );
		if(!b2.BuildTails()) {
			return false;
		}
		if(!b2.IsFoundGoal()) {
			if(!b2.Build()) {
				b2.Remove();
				return false;
			}
		}
		buildedPath2 = b2.buildedPath;
	
		local b1 = TailedRailBuilder.StationToStationReverse(destHgStation, srcHgStation, cargo, limitCount, eventPoller, buildedPath2.path);
		if(!b1.BuildTails()) {
			b2.Remove();
			return false;
		}
		if(!b1.IsFoundGoal()) {
			if(!b1.Build()) {
				b1.Remove();
				b2.Remove();
				return false;
			}
		}
		buildedPath1 = b1.buildedPath;
		return true;
	}
	
}


class RailToAnyRailBuilder extends RailBuilder {
	originalPath = null;
	buildPointsSuceeded = false;
	
	constructor(railPath, goalsArray, ignoreTiles, isReverse, limitCount, eventPoller, reversePath=null) {
		this.originalPath = railPath;
		this.isReverse = isReverse;

		local startArray = /*TailedRailBuilder.*/GetStartArray(railPath);
		local path;
		if(startArray.len()==0) {
			path = null;
		} else {
			local pathfinder = CreatePathFinder();
//			pathfinder.InitializePath(startArray, goalsArray, ignoreTiles, reversePath);
			pathfinder.InitializePath2(startArray, goalsArray, ignoreTiles, reversePath);
			path = FindPath(pathfinder, limitCount, eventPoller);
		}
		RailBuilder.constructor(path, isReverse, ignoreTiles, eventPoller);
	}

	static function IsForkable(prevprev,prev,fork) {
		return HgTile(prev).CanForkRail(HgTile(fork));
	}
	
	
	function GetStartArray(path) {
		local result = [];
		IterateRailroadPoints(path,function(prevprev,prev,fork,next):(result) {
			if((HogeAI.IsBuildable(fork) || (AICompany.IsMine(AITile.GetOwner(fork)) && RailUtils.IsStraightTrack(AIRail.GetRailTracks(fork)))) 
					&& RailToAnyRailBuilder.IsForkable(prevprev,prev,fork)) {
				result.push([fork,prev,prevprev]);
			}
		});
		return result;
	}


	function BuildRailloadPoints() {
		if(pathSrcToDest==null) {
			return;
		}
		return originalPath.BuildRailloadPoints(pathSrcToDest,isReverse);
	}
		
	function Build() {
		if(!RailBuilder.Build()) {
			return false;
		}
		/*
		if(!BuildRailloadPoints()) {
			return false;
		}*/
		return true;
	}

	function IterateRailroadPoints(path,func) {
		(!isReverse ? path.Reverse() : path).IterateRailroadPoints(func);
	}
}

class RailToStationRailBuilder extends RailToAnyRailBuilder {
	destHgStation = null;
	hoge = null;
	
	constructor(railPath, destHgStation, isStationDepature, limitCount, hoge, reversePath=null) {
		this.destHgStation = destHgStation;
		this.hoge = hoge;
		local goalArrays;
		local ignoreTiles;
		if(isStationDepature) {
			goalArrays = destHgStation.GetDeparturesTiles();
			ignoreTiles = destHgStation.GetArrivalsTile();
		} else {
			goalArrays = destHgStation.GetArrivalsTiles();
			ignoreTiles = destHgStation.GetDeparturesTile();
		}
		ignoreTiles.extend(destHgStation.GetIgnoreTiles());
		RailToAnyRailBuilder.constructor(railPath, goalArrays, ignoreTiles, isStationDepature, limitCount, this, reversePath);
	}
	
	function OnPathFindingInterval() {
		local place = destHgStation.place;
		if(place != null && place instanceof HgIndustry && place.IsClosed()) {
			HgLog.Warning("place Closed(OnPathFindingInterval)");
			return false;
		}
		return hoge.OnPathFindingInterval();
	}
}
