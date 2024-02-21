
class Path {
	tile = null;
	parent_ = null;
	mode = null; // 今のところ不要なのでsave/load非対応
	
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
	
	constructor(tile,parent_,mode = null) {
		this.tile = tile;
		this.parent_ = parent_;
		this.mode = mode;
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
		return Path(path.GetTile(),Path._SubPath(path.GetParent(),null,null),path.mode);
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
			result = Path(path.GetTile(),result,path.mode);
			path = path.GetParent();
		}
		return result;
	}
	
	function Clone() {
		return _SubPath(this,null,null);
	}
	
	// 結果にentTileは含まれない 最初からendTileまでをコピー
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
	
	function GetTiles(skip = 1) {
		local result = [];
		local path = this;
		if(skip == 1) {
			while(path != null) {
				result.push(path.GetTile());
				path = path.GetParent();
			}
		} else {
			local count = 0;
			while(path != null) {
				if(count % skip == 0) {
					result.push(path.GetTile());
				}
				count ++;
				path = path.GetParent();
			}
		}
		return result;
	}
	
	function GetTilesLen(maxLen) {
		local result = [];
		local path = this;
		while(path != null && result.len() < maxLen) {
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
	
	function CombineTo(endTile,path) {
		return _SubPath(this,endTile,path);
	}

	static function _SubPath(path,endTile,combinePath) {
		if(path == null || path.GetTile() == endTile) {
			return combinePath;
		} else {
			return Path(path.GetTile(),Path._SubPath(path.GetParent(),endTile,combinePath),path.mode);
		}
	}
	
	function GetTotalDistance(vehicleType) {
		switch(vehicleType) {
			case AIVehicle.VT_RAIL:
				return GetRailDistance();
			case AIVehicle.VT_WATER:
				return GetRailDistance();
			case AIVehicle.VT_ROAD:
				return GetRoadDistance();
		}
	}
	
	function GetRoadDistance() {
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
	
	function GetRailDistance() {
		local path = this;
		local result = 0;
		local p1 = null;
		local p2 = null;
		while(path != null) {
			if(p1 != null && p2 != null) {
				if(path.GetTile()-p1 != p1-p2) {
					result += 7;
				} else {
					result += AIMap.DistanceManhattan(p1, p2) * 10;
				}
			}
			p2 = p1;
			p1 = path.GetTile();
			path = path.GetParent();
		}
		return result / 10;
	}
	
	function RemoveRails(isTest=false, doInterval=false) {
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
				if(doInterval) {
					HogeAI.DoInterval();
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
	
	function GetCheckPoints(interval, maxCount) {
		local path = this;
		local count = 0;
		local checkPoints = [];
		while(path != null) {
			if(count++ % interval == 0) {
				checkPoints.push(path.GetTile());
				if(checkPoints.len() >= maxCount) {
					break;
				}
			}
			path = path.GetParent();
		}
		return checkPoints;
	}
	
	function GetNearestTileDistance(fromTile) {
		local count = 0;
		local result = null;
		local path = this;
		while(path != null) {
			if(count++ % 32 == 0) {
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
			local prev2 = null;
			local prev = null;
			local path = this;
			while(path != null) {
				if(prev != null) {
					if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
						prev = path.GetTile();
						path = path.GetParent();
					} else {
						local curHgTile = HgTile(prev);
						if(vehicleType == AIVehicle.VT_WATER && AIMarine.IsCanalTile(prev)) {
							local tiles = path.GetTilesLen(3);
							if(tiles.len() == 3) {
								local dir = tiles[0] - prev;
								if(tiles[1] - tiles[0] == dir && tiles[2] - tiles[1] == dir) {
									if(curHgTile.BuildWaterDepot(tiles[0],prev,true)) {
										return tiles[0];
									}
								}
							}
						} else {
							foreach(hgTile in curHgTile.GetDir4()) {
								if(hgTile.tile == path.GetTile() || hgTile.tile == prev2) {
									continue;
								}
								if(curHgTile.BuildCommonDepot(hgTile.tile, prev, vehicleType)) {
									return hgTile.GetTileIndex();
								}
							}
						}
					}
				}
				if(path != null) {
					prev2 = prev;
					prev = path.GetTile();
					path = path.GetParent();
				}
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
		local result = BuildDoubleDepotMinLength(9);
		if(result.len() == 0) {
			return BuildDoubleDepotMinLength(5);
		} else {
			return result;
		}
	}
	
	function BuildDoubleDepotMinLength(minLength) {
		
	
		local prev = null;
		local path = this;
		local p = array(minLength);
		while(path != null) {
			local c = path;
			local i=0;
			local pre = null;
			for(; c != null && i<minLength; i++) {
				p[i] = c.GetTile();
				c = c.GetParent();
			}
			if(i==minLength) {
				local middle = minLength / 2;
				if(AIMap.DistanceManhattan(p[middle], p[middle-1]) > 1 || AIMap.DistanceManhattan(p[middle], p[middle+1]) > 1) {
				} else {
					local ng = false;
					for(local i=0; i<minLength-2; i++) {
						if(p[i]-p[i+1]!=p[i+1]-p[i+2]) {
							ng = true;
							break;
						}
					}
					if(!ng) {
						foreach(dir in HgTile.DIR4Index) {
							local depot = p[middle] + dir;
							if(AITile.IsBuildable(depot)) {
								local depots = HgTile(p[middle]).BuildDoubleDepot(depot, p[middle] - dir, p[middle-1], p[middle+1]);
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
		//length ++; // bound heightで取らないと正確には取れない
	
		local endPath = this;
		local startPath = this;
		local endPrev = null;
		local endPrevprev = null;
		local startPrev = null;
		local startPrevprev = null;
		local endPoint = 0;
		local startPoint = 0;
		local maxSlopes = 0;
		
		for(;endPath != null; 
					endPrevprev = endPrev, endPrev = endPath.GetTile(), endPath = endPath.GetParent()) {
			for(;startPath != null && endPoint + length > startPoint; 
					startPrevprev = startPrev, startPrev = startPath.GetTile(), startPath = startPath.GetParent()) {
				if(startPrevprev != null && startPrev != null) {
					local d = AIMap.DistanceManhattan(startPrev, startPath.GetTile());
					if(d > 1) {
						startPoint += d;
					} else {
						if(startPrevprev - startPrev != startPrev - startPath.GetTile()) {
							startPoint += 0.7;
						} else {
							startPoint += 1;
						}
					}
				}
			}
			local endHeight = null;
			if(endPrev != null) {
				endHeight = AITile.GetMaxHeight (endPrev);
				endHeight += AIBridge.IsBridgeTile(endPrev) ? 1 : 0; // TODO: 平らな橋
			}
			local startHeight = null;
			if(startPrev != null) {
				startHeight = AITile.GetMaxHeight (startPrev);
				startHeight += AIBridge.IsBridgeTile(startPrev) ? 1 : 0;
			}
			if(startHeight != null && endHeight != null) {
				maxSlopes = max(endHeight - startHeight, maxSlopes);
			}
			if(endPrev != null && endPrevprev != null) {
				local d = AIMap.DistanceManhattan(endPrev, endPath.GetTile());
				if(d > 1) {
					endPoint += d;
				} else {
					if(endPrevprev - endPrev != endPrev - endPath.GetTile()) {
						endPoint += 0.7;
					} else {
						endPoint += 1;
					}
				}
			}
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
	route = null;
	
	constructor(path) {
		BuildedPath.instances.rawset(this,this);
		this.path = path;
		array_ = path.GetTiles();
		BuildedPath.AddTiles(array_);
	}
	
	function ChangePath() {
		array_ = path.GetTiles();
		if(route != null) {
			route.Save(); // 保存するためにrouteのsavedataの更新が必要
		} else {
			HgLog.Info("route == null (BuildedPath.ChangePath)");
		}
		BuildedPath.AddTiles(array_);
	}

	function Remove(removeRails = true, doInterval = false) {
		if(removeRails) {
			path.RemoveRails(false/*isTest*/, doInterval);
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
		local removePath = origPath.SubPathIndex(pointIndex-2);
				
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
			return BuildUtils.RemoveSignalSafe(p1,p2);
		});
	}

	static function BuildSignalUntilFree(p1,p2,t) {
		return BuildUtils.BuildSafe( function():(p1,p2,t) {
			return BuildUtils.BuildSignalSafe(p1,p2,t);
		});
	}

	static function BuildRailUntilFree(p1,p2,p3) {
		return BuildUtils.BuildSafe( function():(p1,p2,p3) {
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
	
	static function BuildRailSafe(a,b,c) {
		return BuildUtils.WaitForMoney( function():(a,b,c) {
			return AIRail.BuildRail(a,b,c);
		});
		
	}
	
	static RailTracks = [AIRail.RAILTRACK_NE_SW,AIRail.RAILTRACK_NW_SE ,AIRail.RAILTRACK_NW_NE ,AIRail.RAILTRACK_SW_SE ,AIRail.RAILTRACK_NW_SW ,AIRail.RAILTRACK_NE_SE];

	static function RemoveRailTracksAll(tile) {
		local tracks = AIRail.GetRailTracks(tile);
		foreach(railTrack in RailBuilder.RailTracks) {
			if(tracks & railTrack) {
				AIRail.RemoveRailTrack(tile,railTrack); // 失敗しても気にせず他を消す
			}
		}
		return true;
	}
	
	pathSrcToDest = null;
	isReverse = false;
	isRebuildForHomeward = false;
	isNoSignal = false;
	ignoreTiles = null;
	eventPoller = null;
	buildedPath = null;
	
	pathFinder = null;
	cargo = null;
	distance = null;

	constructor(pathSrcToDest,isReverse,ignoreTiles,eventPoller) {
		this.pathSrcToDest = pathSrcToDest;
		this.isReverse = isReverse;
		this.ignoreTiles = ignoreTiles;
		this.eventPoller = eventPoller;
	}

	
	function CreatePathFinder() {
		local result = RailPathFinder();
		result.cargo = cargo;
		result.distance = distance;
		return result;
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
			HgLog.Warning("pathSrcToDest == null(RailBuilder.Build)");
			return false;
		}
		HgLog.Info("Start Build:"+HgTile(pathSrcToDest.GetTile()));
		local path = pathSrcToDest;
		local prevPath = null;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		local signalCount = 7;
		while (path != null) {
			if (prevprev != null) {
				path = RaiseTileIfNeeded(prevPath,prevprev);
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
					if(prevprevprev!=null) {
						BuildSignal(prevprevprev, prevprev, prev);
					}
					if(CanTryToDemolish(prev)) {
						HgLog.Info("Demolish tile for bridge or tunnel start:"+HgTile(prev)+"(end:"+HgTile(path.GetTile())+")");
						DemolishTile(prev);
					}
					if(CanTryToDemolish(path.GetTile())) {
						HgLog.Info("Demolish tile for bridge or tunnel end:"+HgTile(path.GetTile())+"(start:"+HgTile(prev)+")");
						DemolishTile(path.GetTile());
					}
					local underground = null;
					if(path.mode != null && path.mode instanceof RailPathFinder.Underground) {
						underground = path.mode;
					} else if(prevPath.mode != null && prevPath.mode instanceof RailPathFinder.Underground) {
						underground = prevPath.mode;
					}
					if(underground != null) {
						HogeAI.WaitForMoney(50000,0,"BuildUnderground");
						if(!BuildUnderground(path,prev,prevprev,prevprevprev,underground)) {
							HgLog.Warning("BuildUnderground failed."+HgTile(prev)+"-"+HgTile(path.GetTile())+" level:"+underground.level+" "+AIError.GetLastErrorString());
							return RetryToBuild(path,prev);
						}
					} else if (AITunnel.GetOtherTunnelEnd(prev) == path.GetTile()) {
						HogeAI.WaitForMoney(50000,0,"BuildTunnel");
						if(!BuildUtils.BuildTunnelSafe(AIVehicle.VT_RAIL, prev)) {
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
						if(!BuildBridgeSafe(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, path.GetTile())) {
							HgLog.Warning("BuildBridge failed("+HgTile(prev)+"-"+HgTile(path.GetTile())+":"+AIError.GetLastErrorString()+").");
							return RetryToBuild(path,prev);
						}
					}
					signalCount = 7;
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
					if(RailPathFinder.CanDemolishRail(prev)) {
						HgLog.Info("demolish tile for buildrail:"+HgTile(prev));
						DemolishTile(prev);
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
					if(!(isGoalOrStart && RailPathFinder.AreTilesConnectedAndMine(prevprev, prev, path.GetTile()))
							&& !RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
						local succeeded = false;
						local warning = "BuildRail failed:"+HgTile(prevprev)+" "+HgTile(prev)+" "+HgTile(path.GetTile())+" "+AIError.GetLastErrorString()+" isGoalOrStart:"+isGoalOrStart;
						if(AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR && !BuildedPath.Contains(prev)) {
							HgLog.Info("DemolishTile:"+HgTile(prev)+" for BuildRail");
							DemolishTile(prev);
							if(RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
								HgLog.Info("BuildRail succeeded after DemolishTile.");
								succeeded = true;
							}
						}
						if(!succeeded && isGoalOrStart) {
							foreach(dir in HgTile.DIR4Index) {
								RailBuilder.RemoveSignalUntilFree( prev, prev+dir );
							}
							if(RailBuilder.BuildRailUntilFree( prevprev, prev, path.GetTile())) {
								succeeded = true;
							}
						}
						if(!succeeded) {
							HgLog.Warning(warning);
							return RetryToBuild(path,prev);
						}
					}
					if(signalCount >= 7 && BuildSignal( prevprev, prev, path.GetTile() ) ) {
						signalCount = 0;
					} else if( RailPathFinder._IsSlopedRail( prevprev, prev, path.GetTile() ) ) {
						local signal = false;
						if(isReverse) {
							signal = AITile.GetMaxHeight(prevprev) < AITile.GetMaxHeight(prev);
						} else {
							signal = AITile.GetMaxHeight(path.GetTile()) < AITile.GetMaxHeight(prev);
						}
						if(signal && BuildSignal( prevprev, prev, path.GetTile() )) {
							signalCount = 3;
						}
					}
					signalCount ++;
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
		
		return BuildDone();
	}
	
	function CanTryToDemolish(tile) {
		if(AITile.IsBuildable(tile)) {
			return false;
		}
		if(!AICompany.IsMine(AITile.GetOwner(tile))) {
			return true;
		}
		if(AIRail.IsRailTile(tile) || AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) {
			return !BuildedPath.Contains(tile);
		}
		return true;
	}
	
	function BuildBridgeSafe(vehicleType, bridge, p1, p2) {
		if(!BuildUtils.BuildBridgeSafe(vehicleType, bridge, p1, p2)){
			if( AIError.GetLastError() == AIError.ERR_AREA_NOT_CLEAR ) {
				HgLog.Warning("TryDemolishUnderBridge(BuildBridge failed("+HgTile(p1)+"-"+HgTile(p2)+":"+AIError.GetLastErrorString()+")).");
				RailBuilder.TryDemolishUnderBridge(p1,p2);
				if(BuildUtils.BuildBridgeSafe(vehicleType, bridge, p1, p2)) {
					return true;
				}
			}
			HgLog.Warning("BuildBridge failed("+HgTile(p1)+"-"+HgTile(p2)+":"+AIError.GetLastErrorString()+").");
			return false;
		}
		return true;
	}
	
	function TryDemolishUnderBridge(p1,p2) {
		if(AIMap.DistanceManhattan(p1,p2) <= 1) {
			return;
		}
		local offset;
		if(AIMap.GetTileX(p1) == AIMap.GetTileX(p2)) {
			offset = AIMap.GetTileIndex(0,1);
		} else {
			offset = AIMap.GetTileIndex(1,0);
		}
		local t0 = min(p1,p2) + offset;
		local t1 = max(p1,p2) - offset;
		while(t0 != t1) {
			if(AIRoad.IsRoadTile(t0) || AIRail.IsRailTile(t0) || AITile.IsWaterTile(t0) || AIBridge.IsBridgeTile(t0) || AITunnel.IsTunnelTile(t0)) {
			} else if(!AITile.IsBuildable(t0)) {
				local r = AITile.DemolishTile(t0);
				HgLog.Warning("DemolishTile:"+r+" "+HgTile(t0));
			}
			t0 += offset;
		}
	}
	
	function DemolishTile( tile ) {
		if(	AIRail.IsRailStationTile( tile ) ) {
			AIRail.RemoveRailStationTileRectangle (tile, tile, false);// joinしてる他の駅も壊れるので一部だけ壊れるようにする
		} else {
			AITile.DemolishTile( tile );
		}
	}
	
	function RetryToBuild(path,tile) {
		HgLog.Info("RetryToBuild start");
/*		
		local endAndPrev = path.GetEndTileAndPrev();
		local goalPath = Path(endAndPrev[1],Path(endAndPrev[0]],null));
		local startPath = pathSrcToDest.SubPathEnd(tile);
		local builder = TailedRailBuilder.PathToPath(Container(isReverse?goalPath:startPath), Container(isReverse?startPath:goalPath), ignoreTiles, 150, eventPoller);
		builder.isSingle = isNoSignal;
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
		local railBuilder = RailToAnyRailBuilder(isReverse?startPath.Reverse():startPath, 
			goalsArray, ignoreTiles, !isReverse, 150, eventPoller, pathFinder);
		railBuilder.isNoSignal = isNoSignal;
		local result = railBuilder.Build();
		tmpBuildedPath.Remove(false);
		if(result) {
			local newPath = railBuilder.pathSrcToDest.Reverse();
			local origPath = startPath.SubPathEnd(newPath.GetFirstTile());
			
			startPath.SubPathIndex(startPath.GetIndexOf(newPath.GetFirstTile())-1).RemoveRails();
			pathSrcToDest = origPath.Combine(newPath);
			if(!BuildDone()) {
				HgLog.Warning("retry to build failed");
				return false;
			}
			HgLog.Warning("retry to build succeeded");
			return true;
		} else {
			HgLog.Warning("retry to build failed");
			return false;
		}
	}
	
	function BuildDone() {
		buildedPath = BuildedPath(isReverse?pathSrcToDest.Reverse():pathSrcToDest);
		if(!FlattenRails(buildedPath)) {
			return false;
		}
		if(isRebuildForHomeward) {
			RebuildForHomeward(buildedPath);
		}
		return true;
	}
	
	function FindLevel(path, level, maxLength) {
		local prev = null;
		local length = 0;
		local includeDiagonal = false;
		local minLevel = level;
		local maxLevel = level;
		local boundTileList = AIList();
		for(; path != null && length < maxLength ; prev = path.GetTile(), path = path.GetParent(), length ++) {
			if(prev == null) {
				continue;
			}
			if(AIMap.DistanceManhattan(prev, path.GetTile()) != 1) {
				return null;
			}
			if(!HgTile.IsStraightTrack(AIRail.GetRailTracks(prev))) {
				includeDiagonal = true;
			}
			local t = HgTile.GetBoundCornerTiles(prev, path.GetTile());
			local l0 = AITile.GetCornerHeight( t[0], AITile.CORNER_N );
			local l1 = AITile.GetCornerHeight( t[1], AITile.CORNER_N );
			local l = max(l0,l1);
			minLevel = min(l,minLevel);
			maxLevel = max(l,maxLevel);
			boundTileList.AddItem(t[0],l0);
			boundTileList.AddItem(t[1],l1);
			if(l == level) {
				return {
					tile = prev
					includeDiagonal = includeDiagonal
					minLevel = minLevel
					maxLevel = maxLevel
					boundTileList = boundTileList
				};
			}
		}
		return null;
	}
	
	function FlattenRails(buildedPath) {
		local path = buildedPath.path;
		local prev = null;
		
		for(; path != null; prev = path.GetTile(), path = path.GetParent()) {
			if(prev == null) {
				continue;
			}
			local tracks = AIRail.GetRailTracks(path.GetTile());
			if(AIMap.DistanceManhattan(prev, path.GetTile()) != 1 || !HgTile.IsStraightTrack(tracks) || AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_ROAD)) {
				continue;
			}
			local level = HgTile.GetBoundMaxHeight(prev, path.GetTile());
			local sameLevel = FindLevel(path, level, 20);
			if(sameLevel == null || sameLevel.tile == path.GetTile()) {
				continue;
			}
			if(sameLevel.includeDiagonal) {
				if( max( sameLevel.maxLevel - level, level - sameLevel.minLevel ) >= 2 ) {
					continue;
				}
			}
			
			if(HogeAI.GetUsableMoney() < HogeAI.GetInflatedMoney(300000)) {
				break;
			}
			HogeAI.WaitForMoney(50000,0,"FlattenRails");
			
			local orgPath = path;
			local orgPrev = prev;
			local prevprev = null;
			for(; path != null; prevprev = prev, prev = path.GetTile(), path = path.GetParent()) {
				if(prevprev == null) {
					continue;
				}
				AIRail.RemoveRail(prevprev, prev, path.GetTile());
				if(prev == sameLevel.tile) {
					break;
				}
			}
			if(!sameLevel.includeDiagonal) {
				prev = null;
				path = orgPath;
				for(; path != null; prev = path.GetTile(), path = path.GetParent()) {
					if(prev == null) {
						continue;
					}
					HgTile.ForceLevelBound(prev, path.GetTile(), level);
					if(path.GetTile() == sameLevel.tile) {
						break;
					}
				}
			} else {
				local testMode = AITestMode();
				if(TileListUtils.LevelAverage(sameLevel.boundTileList, null, true, level)) {
					local execMode = AIExecMode();
					TileListUtils.LevelAverage(sameLevel.boundTileList, null, false, level);
				}
			}
			prev = orgPrev;
			path = orgPath;
			prevprev = null;
			local signalCount = 0;
			for(; path != null; prevprev = prev, prev = path.GetTile(), path = path.GetParent()) {
				if(prevprev == null) {
					continue;
				}
				HogeAI.WaitForMoney(1000);
				if(!RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
					HgLog.Warning("BuildRail failed:"+HgTile(prevprev)+" "+HgTile(prev)+" "+HgTile(path.GetTile())+" "+AIError.GetLastErrorString()+"(FlattenRails)");
					// ごくまれに失敗する
					return false;
				}
				if(signalCount % 7 == 0 ) {
					if(!isNoSignal) {
						BuildUtils.RemoveSignalSafe(prev, path.GetTile());
						if(BuildUtils.BuildSignalSafe(prev,path.GetTile(),AIRail.SIGNALTYPE_PBS_ONEWAY)) {
							signalCount ++;
						}
					}
				} else {
					signalCount ++;
				}
				if(prev == sameLevel.tile) {
					if(!isNoSignal) {
						BuildUtils.RemoveSignalSafe(prev, path.GetTile());
						BuildUtils.BuildSignalSafe(prev,path.GetTile(),AIRail.SIGNALTYPE_PBS_ONEWAY);
					}
					break;
				}
			}
		}
		return true;
	}
	
	function RebuildForHomeward(buildedPath) {
		local path = buildedPath.path;
		local prev = null;
		
		for(; path != null; prev = path.GetTile(), path = path.GetParent()) {
			if(prev == null) {
				continue;
			}
			if(AIMap.DistanceManhattan(prev, path.GetTile()) != 1) {
				continue;
			}
			if(AIBridge.IsBridgeTile(prev) || AIBridge.IsBridgeTile(path.GetTile())) {
				continue;
			}
			local level = HgTile.GetBoundMaxHeight(prev, path.GetTile());
			local prevDir = prev - path.GetTile();
			if(isReverse) {
				prevDir = -prevDir;
			}
			local dx = prevDir % AIMap.GetMapSizeX();
			local dy = prevDir / AIMap.GetMapSizeX();
			local revDir = dy - dx * AIMap.GetMapSizeX();
			
			local revNext = path.GetTile() + revDir;
			local revPrev = prev + revDir;
			if(HogeAI.GetUsableMoney() < HogeAI.GetInflatedMoney(300000)) {
				break;
			}
			HogeAI.WaitForMoney(50000,0,"ForceLevelBound(RebuildForHomeward)");
			local isAroundCoastRevNext = HgTile.IsAroundCoast(revNext);
			if(!HgTile.IsAroundCoast(revPrev) && !isAroundCoastRevNext) {
				HgTile.ForceLevelBound(revPrev, revNext, level, { lowerOnly = true });
			}
			if(!HgTile.IsAroundCoast(path.GetTile()) && !isAroundCoastRevNext) {
				HgTile.ForceLevelBound(path.GetTile(), revNext, level);
			}
		}
	}

	function BuildSignal(prevprev,prev,next) {
		if(isNoSignal) {
			return true;
		}
		if(prevprev==null) {
			return false;
		}
		if(!isReverse) {
			BuildUtils.RemoveSignalSafe(prev, next);
			return BuildUtils.BuildSignalSafe(prev,next,AIRail.SIGNALTYPE_PBS_ONEWAY);
		} else {
			BuildUtils.RemoveSignalSafe(prev, prevprev);
			return BuildUtils.BuildSignalSafe(prev,prevprev,AIRail.SIGNALTYPE_PBS_ONEWAY);
		}
	}
	
	function BuildUnderground(path,prev,prevprev,prevprevprev,underground) {
		local d = prev-prevprev;
		if(prevprevprev == null) {
			HgLog.Warning("prevprevprev == null");
			return false;
		}
		if(d != prevprev-prevprevprev) {
			HgLog.Warning("d != prevprev-prevprevprev");
			return false;
		}
		local A0 = prevprevprev;
		local A1 = prevprev;
		local A2 = prev;
		AIRail.RemoveRail(A0,A1,A2);
		if(!RailPathFinder._BuildTunnelEntrance( A0, A1, A2, underground.level, false )) {
			HgLog.Warning("_BuildTunnelEntrance( A0, A1, A2, underground.level )");
			return false;
		}
		local B2 = path.GetTile();
		local B1 = B2 + d;
		local B0 = B1 + d;
		if(!RailPathFinder._BuildTunnelEntrance( B0, B1, B2, underground.level, false )) {
			HgLog.Warning("_BuildTunnelEntrance( B0, B1, B2, underground.level )");
			return false;
		}
		if (AITunnel.GetOtherTunnelEnd(A2) == B2) {
			HogeAI.WaitForMoney(50000,0,"BuildTunnel(BuildUnderground)");
			if (AIRail.BuildRail(A0, A1, A2) && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, A2)) {
				BuildSignal(A0,A1,A2);
				return true;
			}
		}
		HgLog.Warning("!AITunnel.GetOtherTunnelEnd(A2) == B2");
		return false;
	}
	
	
	function RaiseTileIfNeeded(prevpath,prevprev) {
		local prev = prevpath.GetTile();
		local path = prevpath.GetParent();
		if(path == null) {
			return path;
		}
		if(prevpath.mode != null && prevpath.mode instanceof RailPathFinder.Underground) {
			return path;
		}
		if(path.mode != null && path.mode instanceof RailPathFinder.Underground) {
			return path;
		}
		local dir = (prev - prevprev) / AIMap.DistanceManhattan(prev,prevprev);
		
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
				if(AIMap.DistanceManhattan(t0,t1)>1 || RailPathFinder._IsUnderBridge(t1)) { // 橋の下に橋は作れない
					//HgLog.Warning("i:"+i+" D:"+AIMap.DistanceManhattan(t0,t1)+" t0:"+HgTile(t0)+" t1:"+HgTile(t1)+" cur:"+HgTile(cur.GetTile()));

					if(i==0) {
						notSkip = true;
					} else {
						notStraight = true;
						// i --; prevprevcurとか戻せない
					}
					break;
				}
				local boundCorner = HgTile.GetCorners( HgTile(t0).GetDirection(HgTile(t1)) );
				if(!(AITile.GetCornerHeight(t0,boundCorner[0]) == 0 && AITile.GetCornerHeight(t0,boundCorner[1]) == 0 
						&& (AITile.IsCoastTile(t0) || AITile.IsCoastTile(t1) || AITile.IsSeaTile(t0) || AITile.IsSeaTile(t1)) )) {
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
				local needsRaise = false;
				{
					local aiTest = AITestMode();
					
					
					
					local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(t0,t1) + 1);
					needsRaise = !AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), t0, t1);
				}
				if(needsRaise) {
					Raise(t0, t0+dir);
					Raise(t1-dir, t1);
					Raise(t1, t1+dir);
				}
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
			} else if(i>=2) {
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
			//HgLog.Warning("Raise i:"+i+" notStraight:"+notStraight+" notSea:"+notSea+" t0:"+HgTile(t0)+" t1:"+HgTile(t1)+" cur:"+HgTile(cur.GetTile()));
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
			if(TileListUtils.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[1]))) {
				//HgLog.Warning("RaiseTile:"+HgTile(t0)+HgTile.GetCornerString(boundCorner[1]));
				success = true;
			}
			if(!success && TileListUtils.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[0]))) {
				//HgLog.Warning("RaiseTile:"+HgTile(t0)+HgTile.GetCornerString(boundCorner[0]));
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
		local pathBuildedPath = SearchPathBuildedPath(prev);
		if(pathBuildedPath == null) {
			HgLog.Warning("Demolish(ChangeBridge). No builded path:"+HgTile(prev));
			DemolishTile(prev);
			return true;
		}
		local orgPath = pathBuildedPath[0];
		local orgBuildedPath = pathBuildedPath[1];
		if(orgPath.GetParent()==null || AIMap.DistanceManhattan(orgPath.GetTile(),orgPath.GetParent().GetTile())!=1) {
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
		
		HogeAI.WaitForMoney(20000,0,"ChangeBridge");
		local currentRailType = AIRail.GetCurrentRailType();
		AIRail.SetCurrentRailType(AIRail.GetRailType(n_node));
		local startTile = n_node;
		local endTile = null;

		for(local i=0; i<4; i++) {
			//HgLog.Info("_IsUnderBridge:"+RailPathFinder._IsUnderBridge(n_node));
		
			if(i==3 && (RailPathFinder._IsSlopedRail(n_node - direction, n_node, n_node + direction) || AIRail.GetRailTracks(n_node) != tracks || RailPathFinder._IsUnderBridge(n_node))) {
				break;
			}
			if(!RailBuilder.RemoveRailTrackUntilFree(n_node, tracks)) {
				HgLog.Warning("fail RemoveRailTrack."+HgTile(n_node)+" "+AIError.GetLastErrorString());
				foreach(mark in removed) {
					if(!BuildUtils.BuildRailTrackSafe(mark[0], mark[1])) {
						HgLog.Warning("fail BuildRailTrackSafe "+HgTile(mark[0])+" "+AIError.GetLastErrorString());
					}
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
		if(!BuildUtils.BuildBridgeSafe(AIVehicle.VT_RAIL, bridge_list.Begin(), startTile, endTile)) {
			HgLog.Warning("fail BuildBridge "+HgTile(startTile)+"-"+HgTile(endTile)+" "+AIError.GetLastErrorString());
			foreach(mark in removed) {
				if(!BuildUtils.BuildRailTrackSafe(mark[0], mark[1])) {
					HgLog.Warning("fail BuildRailTrackSafe "+HgTile(mark[0])+" "+AIError.GetLastErrorString());
				}
			}
			AIRail.SetCurrentRailType(currentRailType);
			return false;
		}
		
		if(!ChangeBridgePath(orgBuildedPath, startTile, endTile)) {
			HgLog.Warning("ChangeBridgeBuildedPath not found path "+HgTile(startTile)+" "+HgTile(endTile));
		} else {
			orgBuildedPath.ChangePath();
		}
		
		AIRail.SetCurrentRailType(currentRailType);
		return true;
	}
	
	
	function ChangeBridgePath(buildedPath, startTile, endTile) {
		local path = buildedPath.path;
		local buildSignal = buildedPath.route != null && !buildedPath.route.IsSingle();
		local prevprev = null;
		local prev = null;
		while(path != null) {
			if(prev != null && (path.GetTile() == startTile || path.GetTile() == endTile)) {
				if(buildSignal) {
					BuildUtils.RemoveSignalSafe (prev, path.GetTile());
					BuildUtils.BuildSignalSafe(prev, path.GetTile(), AIRail.SIGNALTYPE_PBS_ONEWAY);
				}
				local startPath = path;
				path = path.GetParent();
				while(path != null) {
					if(path.GetTile() == endTile || path.GetTile() == startTile) {
						startPath.parent_ = path;
						HgLog.Info(HgTile(startPath.GetTile())+".parent = "+HgTile(path.GetTile())+" route:"+buildedPath.route);
						if(buildSignal && path.GetParent()!=null && path.GetParent().GetParent()!=null) {
							BuildUtils.RemoveSignalSafe (path.GetParent().GetTile(), path.GetParent().GetParent().GetTile());
							BuildUtils.BuildSignalSafe( path.GetParent().GetTile(), path.GetParent().GetParent().GetTile(), AIRail.SIGNALTYPE_PBS_ONEWAY);
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
	
	function SearchPathBuildedPath(tile) {
		foreach(buildedPath,v in BuildedPath.instances) {
			local path = buildedPath.path;
			while(path != null) {
				if(path.GetTile() == tile) {
					return [path, buildedPath];
				}
				path = path.GetParent();
			}
		}
		return null;
	}
}

class TailedRailBuilder {
	// srcとdestが逆になっている事に注意
	static function StationToStation(srcStation, destStation, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetArrivalsTile());
		ignoreTiles.extend(destStation.GetDeparturesTile());
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		local result = TailedRailBuilder(
			Container(srcStation.GetDeparturesTiles()), 
			Container(destStation.GetArrivalsTiles()),
			ignoreTiles, limitCount, eventPoller, reversePath);
		if(reversePath == null) {
			local dangerTiles = [];
			dangerTiles.extend(destStation.GetDepartureDangerTiles());
			dangerTiles.extend(srcStation.GetArrivalDangerTiles());
			result.dangerTiles = dangerTiles;
		}
		return result;
	}
	static function StationToStationReverse(srcStation, destStation, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		local result = TailedRailBuilder(
			Container(srcStation.GetArrivalsTiles()), 
			Container(destStation.GetDeparturesTiles()),
			ignoreTiles, limitCount, eventPoller, reversePath);
		result.isReverse = true;
		return result;
	}
	static function StationToStationSingle(srcStation, destStation, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		local result = TailedRailBuilder(
			Container(srcStation.GetDeparturesTiles()), 
			Container(destStation.GetArrivalsTiles()),
			ignoreTiles, limitCount, eventPoller, reversePath);
		result.isSingle = true;
		local dangerTiles = [];
		result.dangerTiles = dangerTiles;
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
	
	static function PathToStation(srcPathGetter, destStation, limitCount, eventPoller, reversePath = null, isArrival = true) {
		local ignoreTiles = [];
		ignoreTiles.extend(isArrival ? destStation.GetDeparturesTile() : destStation.GetArrivalsTile());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		local result = TailedRailBuilder(
			GetterFunction(function():(srcPathGetter) {
				return TailedRailBuilder.GetStartArray(srcPathGetter.Get().Reverse());
			}),
			Container(isArrival ? destStation.GetArrivalsTiles() : destStation.GetDeparturesTiles()), 
			ignoreTiles, limitCount, eventPoller, reversePath);
		if(reversePath == null) {
			result.dangerTiles = isArrival ? destStation.GetDepartureDangerTiles() : destStation.GetArrivalDangerTiles();
		}
		return result;
	}


	static function GetStartArray(path) {
		local result = [];
		local prevprev = null;
		local prev = null;
		for(;path != null; prevprev = prev, prev = path.GetTile(), path = path.GetParent()) {
			local next = path.GetParent() != null ? path.GetParent().GetTile() : null;
			if(next == null || prev == null || prevprev == null) {
				continue;
			}
			local cur = path.GetTile(); // 分岐ポイント
			if(AIBridge.IsBridgeTile(cur) || AITunnel.IsTunnelTile(cur)) {
				continue;
			}
			if(RailPathFinder._IsSlopedRail(next,cur,prev)) {
				continue;
			}
			local d1 = AIMap.DistanceManhattan(cur,next);
			local d2 = AIMap.DistanceManhattan(cur,prev);
			local d3 = AIMap.DistanceManhattan(prev,prevprev);
			if(d1==1 && d2==1 && !AIRail.AreTilesConnected(next,cur,prev)) { /*double depots地点からは分岐不可*/
				continue;
			}
			if(d2==1 && d3==1 && !AIRail.AreTilesConnected(cur,prev,prevprev)) { /*double depots地点からは分岐不可*/
				continue;
			}
			result.push([cur, prev, prevprev]);
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
	}
	
	static function GetGoalArrayByPath(path, includePrevprev = false) {
		//local path = path.Reverse();
		local result = [];
		local prev = null;
		local prevprev = null;
		local next = 1;
		local counter = 1;
		while(path != null) {
			if(prev != null) {
				local d = AIMap.DistanceManhattan(prev, path.GetTile());
				if(prevprev != null) {
					if(!RailPathFinder._IsSlopedRail(path.GetTile(), prev, prev + (prev - path.GetTile()))) {
						if(counter >= next && d == 1) {
							if(!includePrevprev) {
								result.push([prev, path.GetTile(), 1000000 - counter * 100]);
							} else {
								result.push([prevprev, prev, path.GetTile(), 1000000 - counter * 100]);
							}
							next += max(1, next / 2);
						}
					}
				} else {
					if(counter >= next && d == 1) {
						if(!includePrevprev) {
							result.push([prev, path.GetTile(), 1000000 - counter * 100]);
						}
						next += max(1, next / 2);
					}
				}
				if(d == 1) {
					counter ++;
				} else {
					counter += d;
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
	limitCount = null;
	eventPoller = null;
	
	reversePath = null;
	isReverse = null;
	isRevReverse = null;
	isSingle = null;
	isTwoway = null;
	engine = null;
	cargo = null;
	platformLength = null;
	distance = null;
	dangerTiles = null;
	
	buildedPath = null;
	
	ignoreTiles = null;
	isFoundGoal = null;
	buildedPath1 = null;
	buildedPath2 = null;
	
	foundedRevPath = null;
	lastRevCheck = null;
	isNotCheckRevPath = null;
	
	
	constructor(srcTilesGetter, destTilesGetter, ignoreTiles, limitCount, eventPoller, reversePath = null, isReverse = false) {
		this.srcTilesGetter = srcTilesGetter;
		this.destTilesGetter = destTilesGetter;
		this.ignoreTiles = ignoreTiles;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.reversePath = reversePath;
		this.isReverse = false;
		this.isRevReverse = false;
		this.isSingle = false;
		this.isTwoway = true;
		this.isNotCheckRevPath = false;
	}
	
	function OnPathFindingInterval() {
		if(!eventPoller.OnPathFindingInterval()) {
			return false;
		}
		if(isNotCheckRevPath) {
			return true;
		}
		if(lastRevCheck != null && AIDate.GetCurrentDate() < lastRevCheck + 30 ) {
			return true;
		}
		lastRevCheck = AIDate.GetCurrentDate();
		
		local goals = srcTilesGetter.Get();
		if(goals.len() <= 8) { // ゴールが多いと時間がかかるのでスキップ
			local pathFinder2 = RailPathFinder();
			pathFinder2.engine = engine;
			pathFinder2.cargo = cargo;
			pathFinder2.platformLength = platformLength;
			pathFinder2.distance = distance;
			pathFinder2.isOutward = reversePath == null && !isSingle && isTwoway;
			pathFinder2.dangerTiles = dangerTiles;
			pathFinder2.isRevReverse = !isRevReverse;
			pathFinder2.InitializePath(destTilesGetter.Get(), srcTilesGetter.Get(), ignoreTiles, reversePath);
			local startDate = AIDate.GetCurrentDate();
			local path2 = pathFinder2.FindPathDay(2, null);
			if(pathFinder2.IsFoundGoal()) {
				foundedRevPath = path2;
				return false;
			}
			if(AIDate.GetCurrentDate() - startDate >= 5) {
				isNotCheckRevPath = true; // たまにすごく時間がかかる事がある
			}
			return path2 != null;
		}
		return true;
		
	}
	
	function BuildTails() {
		isFoundGoal = false;

		local isOutward = reversePath == null && !isSingle && isTwoway;
		local pathFinder1 = RailPathFinder();
		pathFinder1.engine = engine;
		pathFinder1.cargo = cargo;
		pathFinder1.platformLength = platformLength;
		pathFinder1.distance = distance;
		pathFinder1.isOutward = isOutward;
		pathFinder1.isSingle = isSingle;
		pathFinder1.isRevReverse = isRevReverse;
		pathFinder1.dangerTiles = dangerTiles;
		local starts = srcTilesGetter.Get();
		local goals = destTilesGetter.Get();
		if(starts.len()==0) {
			HgLog.Warning("TailedRailBuilder: No start(pathFinder1)");
			return false;
		}
		if(goals.len()==0) {
			HgLog.Warning("TailedRailBuilder: No goal(pathFinder1)");
			return false;
		}
		pathFinder1.InitializePath(starts, goals, ignoreTiles, reversePath);
		local path1 = pathFinder1.FindPathDay(limitCount, this);
		if(foundedRevPath != null) {
			path1 = foundedRevPath.Reverse();
		}
		if(path1==null) {
			HgLog.Warning("TailedRailBuilder: No path found(pathFinder1)");
			return false;
		}
		if(pathFinder1.IsFoundGoal() || foundedRevPath != null) {
			// src側から建築
			local railBuilder1 = RailBuilder(path1.Reverse(),!isReverse,ignoreTiles,this);
			railBuilder1.pathFinder = pathFinder1;
			railBuilder1.isRebuildForHomeward = isOutward;
			if(isSingle) {
				railBuilder1.isNoSignal = true;
			}
			railBuilder1.cargo = cargo;
			railBuilder1.distance = distance;
			if(railBuilder1.Build()) {
				buildedPath1 = railBuilder1.buildedPath; //dest->src方向

				buildedPath = buildedPath1;
				isFoundGoal = true;
				return true;
			} else {
				HgLog.Warning("TailedRailBuilder: railBuilder1.Build failed.");
			}
		} else {
			HgLog.Warning("TailedRailBuilder: Timed out(pathFinder1)");
		}
		return false; // 結局ほとんど失敗するので再挑戦しない
		
		// 遅いので、スタート地点のみにする
		//goals = TailedRailBuilder.GetGoalArrayByPath(isReverse ? buildedPath1.path.Reverse() : buildedPath1.path);
		/*
		foreach(g in goals) {
			HgLog.Info("goal:"+HgTile(g[0])+"-"+HgTile(g[1])+","+g[2]);
		}*/
		local lastTile = path1.GetTile();
		HgLog.Warning("TailedRailBuilder: No path found(pathFinder1). Try goal=>start (LastTile:"+HgTile(lastTile)+")");
		
		goals = srcTilesGetter.Get();
		if(goals.len()==0) {
			HgLog.Warning("TailedRailBuilder: No goal(pathFinder2)");
			return false;
		}
		if(reversePath == null) {
			reversePath = path1; // pathfinder1での探索完了地点までをガイドにする
		}
		local pathFinder2 = RailPathFinder();
		pathFinder2.engine = engine;
		pathFinder2.cargo = cargo;
		pathFinder2.platformLength = platformLength;
		pathFinder2.distance = distance;
		pathFinder2.dangerTiles = dangerTiles;
		pathFinder2.InitializePath(destTilesGetter.Get(), goals, ignoreTiles, reversePath);
		local path2 = pathFinder2.FindPathDay(limitCount*2, eventPoller);
		if(path2==null) {
			HgLog.Warning("TrainRoute: No path found(TailedRailBuilder.pathFinder2)");
			//buildedPath1.Remove();
			return false;
		}
		if(!pathFinder2.IsFoundGoal()) {
			HgLog.Warning("TrainRoute: No path found(TailedRailBuilder.pathFinder2 timed out)");
			return false;
		}
		local railBuilder2 = RailBuilder(path2.Reverse(),isReverse,ignoreTiles,eventPoller);
		railBuilder2.cargo = cargo;
		railBuilder2.distance = distance;
		railBuilder2.isRebuildForHomeward = isOutward;
		if(isSingle) {
			railBuilder2.isNoSignal = true;
		}
		if(!railBuilder2.Build()) {
			HgLog.Warning("TrainRoute: TailedRailBuilder.railBuilder2.Build failed.");
			//buildedPath1.Remove();
			return false;
		}
		/*
		railBuilder2.buildedPath.path = railBuilder2.buildedPath.path.Reverse();
		railBuilder2.buildedPath.ChangePath();*/
		buildedPath2 = railBuilder2.buildedPath;
		
		isFoundGoal = true;
		buildedPath = buildedPath2; //buildedPath1.CombineAndRemoveByFork(buildedPath2,isReverse);
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
	pathDepatureGetter = null; // 駅の出発タイルへ向けたパス
	pathArrivalGetter = null; // 駅の到着タイルへ向けたパス
	isReverse = null; // 上記を逆にする
	destHgStation = null;
	limitCount = null;
	eventPoller = null;

	engine = null;
	cargo = null;
	platformLength = null;
	distance = null;
	isBuildDepotsDestToSrc = null;
	isBuildSingleDepotDestToSrc = null;

	buildedPath1 = null;
	buildedPath2 = null;
	depots = null;
	
	constructor(pathDepatureGetter=null, pathArrivalGetter=null, destHgStation=null, limitCount=null, eventPoller=null) {
		this.pathDepatureGetter = pathDepatureGetter; 
		this.pathArrivalGetter = pathArrivalGetter; 
		this.isReverse = false;
		this.destHgStation = destHgStation;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.isBuildDepotsDestToSrc = false;
		this.isBuildSingleDepotDestToSrc = false;
		this.depots = [];
	}
	
	function Build() {
		
		local b1 = TailedRailBuilder.PathToStation(pathDepatureGetter, destHgStation, limitCount, eventPoller, null, !isReverse );
		b1.cargo = cargo;
		b1.engine = engine;
		b1.platformLength = platformLength;
		b1.distance = distance;
		b1.isReverse = isReverse;
		b1.isRevReverse = isReverse;
		if(!b1.BuildTails()) {
			RemoveDepots();
			return false;
		}
		buildedPath1 = b1.buildedPath;
		if(isBuildDepotsDestToSrc) {
			depots.extend(buildedPath1.path.Reverse().SubPathIndex(4).BuildDoubleDepot());
		}
		
		local b2 = TailedRailBuilder.PathToStation(pathArrivalGetter, destHgStation, limitCount, eventPoller, buildedPath1.path, isReverse );
		b2.cargo = cargo;
		b2.engine = engine;
		b2.platformLength = platformLength;
		b2.distance = distance;
		b2.isReverse = !isReverse;
		b2.isRevReverse = isReverse;
		if(!b2.BuildTails()) {
			b1.Remove();
			return false;
		}
		buildedPath2 = b2.buildedPath;
		if(isBuildDepotsDestToSrc) {
			depots.extend(buildedPath2.path.Reverse().SubPathIndex(4).BuildDoubleDepot());
		}
		if(isBuildSingleDepotDestToSrc) {
			local depot = buildedPath2.path.Reverse().SubPathIndex(4).BuildDepotForRail();
			if(depot != null) {
				depots.push(depot);
			}
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
	limitCount = null;
	eventPoller = null;
	
	engine = null;
	cargo = null;
	platformLength = null;
	distance = null;
	isBuildDepotsDestToSrc = null;
	isBuildSingleDepotDestToSrc = null;
	
	buildedPath1 = null;
	buildedPath2 = null;
	depots = null;
	
	constructor(srcHgStation, destHgStation, limitCount, eventPoller) {
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.isBuildDepotsDestToSrc = false;
		this.isBuildSingleDepotDestToSrc = false;
		this.depots = [];
	}
	
	function Build() {
		local b1 = TailedRailBuilder.StationToStation(destHgStation, srcHgStation, limitCount, eventPoller );
		b1.engine = engine;
		b1.cargo = cargo;
		b1.platformLength = platformLength;
		b1.distance = distance;
		if(!b1.BuildTails()) {
			return false;
		}
		if(!b1.IsFoundGoal()) {
			if(!b1.Build()) {
				b1.Remove();
				return false;
			}
		}
		buildedPath2 = b1.buildedPath;
		if(isBuildDepotsDestToSrc) {
			depots.extend(buildedPath2.path.BuildDoubleDepot());
		}

	
		local b2 = TailedRailBuilder.StationToStationReverse(destHgStation, srcHgStation, limitCount, eventPoller, buildedPath2.path);
		b2.engine = engine;
		b2.cargo = cargo;
		b2.platformLength = platformLength;
		b2.distance = distance;
		if(!b2.BuildTails()) {
			b1.Remove();
			return false;
		}
		if(!b2.IsFoundGoal()) {
			if(!b2.Build()) {
				b2.Remove();
				b1.Remove();
				return false;
			}
		}
		if(isBuildSingleDepotDestToSrc) {
			local depot = buildedPath2.path.BuildDepotForRail();
			if(depot != null) {
				depots.push(depot);
			}
		}
		
		buildedPath1 = b2.buildedPath;
		return true;
	}
	
}


class SingleStationRailBuilder {
	srcHgStation = null;
	destHgStation = null;
	limitCount = null;
	eventPoller = null;
	
	engine = null;
	cargo = null;
	platformLength = null;
	distance = null;
	
	buildedPath = null;
	depots = null;
	
	constructor(srcHgStation, destHgStation, limitCount, eventPoller) {
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.depots = [];
	}
	
	function Build() {
		local b1 = TailedRailBuilder.StationToStationSingle(destHgStation, srcHgStation, limitCount, eventPoller );
		b1.engine = engine;
		b1.cargo = cargo;
		b1.platformLength = platformLength;
		b1.distance = distance;
		if(!b1.BuildTails()) {
			return false;
		}
		if(!b1.IsFoundGoal()) {
			if(!b1.Build()) {
				b1.Remove();
				return false;
			}
		}
		buildedPath = b1.buildedPath;

	
		return true;
	}
	
}


class RailToAnyRailBuilder extends RailBuilder {
	originalPath = null;
	buildPointsSuceeded = false;
	
	constructor(railPath, goalsArray, ignoreTiles, isReverse, limitCount, eventPoller, pathFinder) {
		this.originalPath = railPath;
		this.isReverse = isReverse;
		this.cargo = cargo;
		this.distance = distance;

		local startArray = /*TailedRailBuilder.*/GetStartArray(railPath);
		local path;
		if(startArray.len()==0) {
			path = null;
		} else {
			local newPathFinder = RailPathFinder();
			newPathFinder.engine = pathFinder.engine;
			newPathFinder.cargo = pathFinder.cargo;
			newPathFinder.platformLength = pathFinder.platformLength;
			newPathFinder.distance = pathFinder.distance;
			newPathFinder.isOutward = pathFinder.isOutward;
			newPathFinder.isRevReverse = pathFinder.isRevReverse;
			newPathFinder.dangerTiles = pathFinder.dangerTiles;			
			newPathFinder.InitializePath(startArray, goalsArray, ignoreTiles, pathFinder.reversePath);
			path = FindPath(newPathFinder, limitCount, eventPoller);
		}
		RailBuilder.constructor(path, isReverse, ignoreTiles, eventPoller);
		
		this.pathFinder = pathFinder;
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