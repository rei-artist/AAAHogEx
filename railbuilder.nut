
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

	static function LoadWithMode(data,i=0) {
		if(data[0].len() == i) {
			return null;
		}
		return Path(data[0][i], Path.LoadWithMode(data,i+1), Serializer.Load(data[1][i]));
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
	
	function SaveWithMode() {
		local tiles = [];
		local modes = [];
		local path = this;
		while(path != null) {
			tiles.push(path.tile);
			modes.push(Serializer.Save(path.mode));
			path = path.GetParent();
		}
		return [tiles,modes];
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
	
	function GetParentLen(l) {
		local result = this;
		for(local i=0; i<l && result != null; i++) {
			result = result.parent_;
		}
		return result;
	}
	
	// distanceに達しないとnull
	function GetParentByDistance(distance) {
		local acc = 0.0;
		local path = this;
		local pre = null;
		local pre2 = null;
		while(path != null && acc < distance) {
			local cur = path.tile;
			if(pre != null) {
				local d = AIMap.DistanceManhattan(cur,pre);
				if(d >= 2) {
					acc += d;
				} else {
					if(pre2 != null) {
						local d2 = AIMap.DistanceManhattan(pre,pre2);
						if(d2 >= 2) {
							acc += 1.0;
						} else {
							if(cur - pre != pre - pre2) {
								acc += 0.707;
							} else {
								acc += 1.0;
							}
						}
					} else {
						acc += 1.0;
					}
				}
			}
			pre2 = pre;
			pre = cur;
			path = path.parent_;
		}
		return path;
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
	
	function Find(tile) {
		local path = this;
		while(path != null) {
			if(path.GetTile() == tile) {
				return path;
			}
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
	
	function GetRailDistance(to=null) {
		local path = this;
		local result = 0;
		local p1 = null;
		local p2 = null;
		while(path != null && path!=to) {
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

	function GetMeetsTiles() {
		// GetParent()からの分岐タイルを返す
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
		local cur = GetTile();
		local straightFork = prev + (prev - cur);
		if(straightFork != prevprev) {
			return [[cur,prev,straightFork,prevprev]];
		} else {
			local result = [];
			foreach(p in nsewArray) {
				local fork = prev + p;
				if(fork != prevprev && fork!=cur) {
					result.push([cur,prev,fork,prevprev]);
				}
			}
			return result;
		}
		
	}
	
	function IterateRailroadPoints(func) {
		/*
			next
         p2 prev fork
		 p3	
			
			fork
            prev next
		 p3 p2
		*/
	
	
		local path = this;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		
		while(path != null) {
			if(prevprev != null && prevprevprev != null) {
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1 || AIMap.DistanceManhattan(prev, prevprev) > 1 
						|| RailPathFinder.IsDoubleDiagonalTrack(AIRail.GetRailTracks(prev))) {
						
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
							func(prevprevprev,prevprev,prev,t,path.GetTile());
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
		path.IterateRailroadPoints(function(prev3,prevprev,prev,fork,next):(endTile,prevEndTile,isFork,t) {
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
	
	function GetNearest(fromTile) {
		local count = 0;
		local result = null;
		local path = this;
		while(path != null) {
			if(count++ % 32 == 0) {
				local d = HgTile(fromTile).DistanceManhattan(HgTile(path.GetTile()));
				if(result == null || d < result.distance) {
					result = {path = path, distance = d};
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
						/*if(vehicleType == AIVehicle.VT_WATER && AIMarine.IsCanalTile(prev)) { LOSTするので
							local tiles = path.GetTilesLen(3);
							if(tiles.len() == 3) {
								local dir = tiles[0] - prev;
								if(tiles[1] - tiles[0] == dir && tiles[2] - tiles[1] == dir) {
									if(curHgTile.BuildWaterDepot(tiles[0],prev,true)) {
										return tiles[0];
									}
								}
							}
						} else {*/
							foreach(hgTile in curHgTile.GetDir4()) {
								if(hgTile.tile == path.GetTile() || hgTile.tile == prev2) {
									continue;
								}
								if(curHgTile.BuildCommonDepot(hgTile.tile, prev, vehicleType)) {
									return hgTile.GetTileIndex();
								}
							}
						//}
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
									return {path=path,mainTiles=[p[1],p[2],p[3]],depots=[depot]};
								}
							}
						}
					}
				}
			}
			path = path.GetParent();
		}
		return {path=path,mainTiles=[],depots=[]};
	}
	
	function BuildDoubleDepot(isFirstLine = false) {
		local tiles = GetTiles();
		local tileLine = {};
		if(isFirstLine) {
			foreach(length in [3,5]) {
				foreach(line in RailPathFinder.FindStraightLines(tiles,length)) {
					local center = line[length/2];
					/*local h = AITile.GetMaxHeight(center);
					local ng = false;
					foreach(t in line) {
						local h2 = AITile.GetMaxHeight(t);
						if(h2 > h) {
							ng = true;
							break;
						}
					}*/
					//if(!ng) {
						tileLine.rawset(center,line);
					//}
				}
			}
		} else {
			foreach(line in RailPathFinder.FindStraightLines(tiles,3)) {
				tileLine.rawset(line[1],line);
			}
		}
		local path = this;
		local prev = null;
		local cur = null;
		for(;path != null; prev = cur, path = path.GetParent()) {
			cur = path.GetTile();
			local nextPath = path.GetParent();
			if(prev == null || nextPath == null) continue;
			local next = nextPath.GetTile(); 
			if(!tileLine.rawin(cur)) continue;
			local line = tileLine[cur];
			local next = path.GetParent().GetTile();
			if(tileLine.rawin(next) && nextPath.GetParent() != null) {
				local next2 = nextPath.GetParent().GetTile();
				local nextLine = tileLine[next];
				if(line.len() < nextLine.len()) {
					local result = BuildDoubleDepotOn(cur,next,next2);
					if(result != null) {
						result.path <- path;
						return result;
					}
				}
			}
			local result = BuildDoubleDepotOn(prev,cur,next);
			if(result != null) {
				result.path <- path;
				return result;
			}
		}
		return null;
	}
	

	function BuildDoubleDepotInterval(interval, isFirstLine = false) {
		local tiles = GetTiles();
		local tileLine = {};
		if(isFirstLine) {
			foreach(length in [3,5]) {
				foreach(line in RailPathFinder.FindStraightLines(tiles,length)) {
					local center = line[length/2];
					tileLine.rawset(center,line);
				}
			}
		} else {
			foreach(line in RailPathFinder.FindStraightLines(tiles,3)) {
				tileLine.rawset(line[1],line);
			}
		}
		local resultArr = [];
		local path = this;
		local prev = null;
		local cur = null;
		for(;path != null; prev = cur, path = path.GetParent()) {
			cur = path.GetTile();
			local nextPath = path.GetParent();
			if(prev == null || nextPath == null) continue;
			local next = nextPath.GetTile(); 
			if(!tileLine.rawin(cur)) continue;
			local line = tileLine[cur];
			local next = path.GetParent().GetTile();
			if(tileLine.rawin(next) && nextPath.GetParent() != null) {
				local next2 = nextPath.GetParent().GetTile();
				local nextLine = tileLine[next];
				if(line.len() < nextLine.len()) {
					local result = BuildDoubleDepotOn(cur,next,next2);
					if(result != null) {
						result.path <- path;
						resultArr.push(result);
						//return resultArr;
						path = path.GetParentByDistance(interval);
						if(path == null) break;
						cur = null;
						continue;
					}
				}
			}
			local result = BuildDoubleDepotOn(prev,cur,next);
			if(result != null) {
				result.path <- path;
				resultArr.push(result);
				//return resultArr;
				path = path.GetParentByDistance(interval);
				if(path == null) break;
				cur = null;
			}
		}
		return resultArr;
	}	
	
	
	function BuildDoubleDepotOn(prev, cur, next) {
		local dir = abs(cur - prev) == 1 ? AIMap.GetMapSizeX() : 1;
		local depot1 = cur - dir;
		local depot2 = cur + dir;
		local depots = HgTile(cur).BuildDoubleDepot(depot1, depot2, prev, next);
		if(depots != null) {
			return {mainTiles=[prev,cur,next],depots=depots};
		}
		local rl = 0;
		{ // どっちかに作れるか検査
			local testMode = AITestMode();
			if(AIRail.BuildRailDepot(depot1, cur)) { 
				rl = 1;
			} else if(AIRail.BuildRailDepot(depot2, cur)) {
				rl = -1;
			}
		}
		if(rl != 0) {
			RailBuilder.ChangeTunnel(cur-2+dir*rl,cur+2+dir*rl); // もう片側が線路だったらトンネルに
			local depots = HgTile(cur).BuildDoubleDepot(depot1, depot2, prev, next);
			if(depots != null) {
				return {mainTiles=[prev,cur,next],depots=depots};
			}
		}
	}

/*	
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
						local dir = abs(p[0] - p[1]) == 1 ? AIMap.GetMapSizeX() : 1;
						local depot1 = p[middle] - dir;
						local depot2 = p[middle] + dir;
						local depots = HgTile(p[middle]).BuildDoubleDepot(depot1, depot2, p[middle-1], p[middle+1]);
						if(depots != null) {
							return {mainTiles=[p[middle-1],p[middle],p[middle+1]],depots=depots};
						}
						local rl = 0;
						{
							local testMode = AITestMode();
							if(AIRail.BuildRailDepot(depot1, p[middle])) { 
								rl = 1;
							} else if(AIRail.BuildRailDepot(depot2, p[middle])) {
								rl = -1;
							}
						}
						if(rl != 0) {
							RailBuilder.ChangeTunnel(p[middle]-2+dir*rl,p[middle]+2+dir*rl);
							local depots = HgTile(p[middle]).BuildDoubleDepot(depot1, depot2, p[middle-1], p[middle+1]);
							if(depots != null) {
								return {mainTiles=[p[middle-1],p[middle],p[middle+1]],depots=depots};
							}
						}
					}
				}
			}
			path = path.GetParent();
		}
		return null;
	}*/
	
	function GetSlopes(length, endTile = null) {
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
		local maxSlopesRev = 0;
		
		for(;endPath != null && (endPrev==null || endPrev!=endTile); 
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
				maxSlopesRev = max(startHeight - endHeight, maxSlopesRev);
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
		
		return [maxSlopes,maxSlopesRev];
		
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
	static tileObj = {};

	static function Contains(tile) {
		return BuildedPath.tileObj.rawin(tile);

	}
	static function GetByTile(tile) {
		if(!BuildedPath.tileObj.rawin(tile)) {
			return null;
		}
		return BuildedPath.tileObj.rawget(tile);
	}
	
	static function AddTiles(tiles,obj) { //hgstationからも呼ばれる
		foreach(tile in tiles) {
			BuildedPath.tileObj.rawset(tile,obj);
		}
	}
	
	static function RemoveTiles(tiles) {
		foreach(tile in tiles) {
			BuildedPath.tileObj.rawdelete(tile);
		}
	}
	
	static function LoadFromTiles(tiles) {
		if(tiles==null) {
			return null;
		}
		return BuildedPath(Path.Load(tiles),null,tiles);
	}

	path = null;
	array_ = null; // saveを高速にするためのキャッシュ TODO: pathが書き変わったときにかきかえないといけない。
	route = null;
	
	constructor(path,route=null,array_=null) {
		BuildedPath.instances.rawset(this,this);
		this.path = path;
		this.route = route;
		if(array_ == null) {
			this.array_ = path.GetTiles();
		} else {
			this.array_ = array_;
		}
		BuildedPath.AddTiles(this.array_,this);
	}
	
	function ChangePath() {
		array_ = path.GetTiles();
		if(route != null) {
			route.Save(); // 保存するためにrouteのsavedataの更新が必要
		} else {
			HgLog.Info("route == null (BuildedPath.ChangePath)");
		}
		BuildedPath.AddTiles(array_,this);
	}

	function Remove(removeRails = true, doInterval = false) {
		if(removeRails) {
			RailRemover( ArrayUtils.Reverse(array_), route!=null?route.id:null, false, false ).Build();
			//path.Reverse().RemoveRails(route, false/*isTest*/, doInterval); //Reverse()は列車進行方向に削除する為
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
			removePath = removePath.Reverse();
		}
		if(newPath.GetIndexOf(pointTile)==null) {
			HgLog.Error("pointTile:"+HgTile(pointTile)+" is not contains newPath at BuildedPath.CombineByFork(railbuilder.nut)");
		}
		local result = BuildedPath(newPath);
	
		this.Remove(false);
		forkBuildedPath.Remove(false);
		return [removePath, result];
	}
	

	function _tostring() {
		return "BuildedPath";
	}
}

class RailBuilder extends Construction {
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
	
	static function BuildRailForce(p1,p2,p3) {
		if(RailBuilder.BuildRailUntilFree(p1,p2,p3)) {
			return true;
		}
		if(AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY) {
			return false;
		}
		if(AICompany.IsMine(AITile.GetOwner(p2))) { // 自分の施設は壊してはいけない
			return false;
		}
		HgLog.Info("try DemolishTile:"+HgTile(p2)+" for BuildRailForce");
		RailBuilder.DemolishTile(p2);
		if(RailBuilder.BuildRailUntilFree(p1,p2,p3)) {
			HgLog.Info("BuildRailForce succeeded after DemolishTile.");
			return true;
		}
		return false;
	}


	static function BuildRailDepotUntilFree(p1,p2) {
		return BuildUtils.BuildSafe( function():(p1,p2) {
			return AIRail.BuildRailDepot(p1,p2);
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
	isRevReverse = false;
	isRebuildForHomeward = false;
	isNoSignal = false;
	notFlatten = false;
	ignoreTiles = null;
	eventPoller = null;
	buildedPath = null;
	
	pathFinder = null;
	cargo = null;
	distance = null;

	constructor(path,isReverse,ignoreTiles,eventPoller) {
		Construction.constructor();
		this.pathSrcToDest = path;
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

	function DoBuild() {
		local execMode = AIExecMode();
		if(pathSrcToDest == null) {
			HgLog.Warning("pathSrcToDest == null(RailBuilder.Build)");
			return false;
		}
		HgLog.Info("Start Build:"+HgTile(pathSrcToDest.GetTile()));
		local rollbackRails = [];
		local path = pathSrcToDest;
		local prevPath = null;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		local signalCount = 7;
		while (path != null) {
			if(prevprev != null) {
				path = RaiseTileIfNeeded(prevPath,prevprev);
			}
			if (prev != null && AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
				if(prevprevprev!=null && prevprev!=null) {
					BuildSignal(prevprevprev, prevprev, prev);
				}
				if(BuildUtils.CanTryToDemolish(prev)) {
					HgLog.Info("Demolish tile for bridge or tunnel start:"+HgTile(prev)+"(end:"+HgTile(path.GetTile())+")");
					DemolishTile(prev);
				}
				if(BuildUtils.CanTryToDemolish(path.GetTile())) {
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
					if(AITunnel.IsTunnelTile(prev) != path.GetTile() || !AICompany.IsMine(AITile.GetOwner(prev))) {
						HogeAI.WaitForMoney(50000,0,"BuildTunnel");
						AddRollback({name="tunnel",tiles=[prev]});
						if(!BuildUtils.BuildTunnelSafe(AIVehicle.VT_RAIL, prev)) {
							HgLog.Warning("BuildTunnel failed."+HgTile(prev)+" "+AIError.GetLastErrorString());
							if(AIError.GetLastError() == AITunnel.ERR_TUNNEL_CANNOT_BUILD_ON_WATER) {
	//								AIController.Break("");
							}
							return RetryToBuild(path,prev);
						}
					}
				} else {
					if(AIBridge.GetOtherBridgeEnd(prev) != path.GetTile() || !AICompany.IsMine(AITile.GetOwner(prev))) {
						AddRollback({name="bridge",tiles=[prev]});
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), prev) + 1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.Sort(AIList.SORT_BY_VALUE, false);
						if(!BuildBridgeSafe(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, path.GetTile())) {
							HgLog.Warning("BuildBridge failed("+HgTile(prev)+"-"+HgTile(path.GetTile())+":"+AIError.GetLastErrorString()+").");
							return RetryToBuild(path,prev);
						}
					}
				}
				signalCount = 7;
				prevprevprev = prevprev;
				prevprev = prev;
				prev = path.GetTile();
				rollbackRails.push(prev);
				prevPath = path;
				path = path.GetParent();
				if(path != null && prevprev != null) {
					path = RaiseTileIfNeeded(prevPath,prevprev);
				}
			} else if(prevprev != null) {
				if(!AIRail.AreTilesConnected(prevprev,prev,path.GetTile()) || !AICompany.IsMine(AITile.GetOwner(prev))) {
					//TownBus.Check(prev);
					if(RailPathFinder.CanDemolishRail(prev)) {
						HgLog.Info("demolish tile for buildrail:"+HgTile(prev));
						DemolishTile(prev);
					}
					
					local isGoalOrStart = (prevprevprev == null && AITile.HasTransportType(prevprev,AITile.TRANSPORT_RAIL)) 
						|| (path.GetParent()==null && AITile.HasTransportType(path.GetTile(),AITile.TRANSPORT_RAIL)); //HasTransportTypeの判定は多分必要ないが害もなさそうなので残す
						/*|| path.GetParent().GetParent()==null  必要なChangeBridgeがされない事があった。isReverseで判定必要かも？ */;
					if(!HgTile.IsDiagonalTrack(AIRail.GetRailTracks(prev))) {
						if(!isGoalOrStart && AITile.HasTransportType(prev, AITile.TRANSPORT_RAIL) && BuildedPath.Contains(prev)) {		
							if(!ChangeBridge(prevprev, prev, path.GetTile())) {
								return RetryToBuild(path,prev);
							}
						}
					}
					
					HogeAI.WaitForMoney(1000);
					AddRollback({name="rail",tiles=[prevprev,prev,path.GetTile()]});
					if(!(isGoalOrStart && RailPathFinder.AreTilesConnectedAndMine(prevprev, prev, path.GetTile()))
							&& !RailBuilder.BuildRailForce(prevprev, prev, path.GetTile())) {
						local succeeded = false;
						local warning = "BuildRail failed:"+HgTile(prevprev)+" "+HgTile(prev)+" "+HgTile(path.GetTile())+" "+AIError.GetLastErrorString()+" isGoalOrStart:"+isGoalOrStart;
						/*if(!BuildedPath.Contains(prev)) {
							HgLog.Info("DemolishTile:"+HgTile(prev)+" for BuildRail");
							DemolishTile(prev);
							if(RailBuilder.BuildRailUntilFree(prevprev, prev, path.GetTile())) {
								HgLog.Info("BuildRail succeeded after DemolishTile.");
								succeeded = true;
							}
						}*/
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
			if (path != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = path.GetTile();
				rollbackRails.push(prev);
				prevPath = path;
				path = path.GetParent();
			}
		}
		if(prevprevprev != null && prevprev != null && prev != null) {
			BuildSignal(prevprevprev,prevprev,prev);
		}
		
		return BuildDone();
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
	
	function RetryToBuild(path,prev) {
		local endAndPrev = path.GetEndTileAndPrev();
		if(endAndPrev[0]==null || endAndPrev[1]==null) {
			HgLog.Warning("retry to build failed(endAndPrev[0]==null || endAndPrev[1]==null)");
			return false;
		}
		
		local goalsArray = [[endAndPrev[1],endAndPrev[0]]];
		local pathToThisPoint = pathSrcToDest.SubPathEnd(path.GetTile());
		local built = BuildedPath(pathToThisPoint);
		local startPath = pathToThisPoint; //.GetParent();
		HgLog.Info( "RetryToBuild start prev:"+HgTile(prev)+"-"+HgTile(path.GetTile())
			+" newGoals:"+HgTile.GetTilesString(goalsArray[0])+" start:"+HgTile(startPath.tile)+"-"+HgTile(startPath.GetLastTile())+" isReverse:"+isReverse );
		local railBuilder = RailToAnyRailBuilder(isReverse?startPath.Reverse():startPath, 
			goalsArray, ignoreTiles, !isReverse, 80, eventPoller, pathFinder);
		railBuilder.isNoSignal = isNoSignal;
		local result = railBuilder.Build(); // TODO: Rollback対応
		built.Remove(!result); // 検索失敗したら物理削除、成功したら論理削除
		if(result) {
			local newTiles = railBuilder.pathSrcToDest.Reverse().GetTiles();
			local orgTiles = startPath.SubPathEnd(newTiles[0]).GetTiles();
			BuildedPath( startPath.SubPathIndex(startPath.GetIndexOf(newTiles[0])-1) ).Remove(true); // 余った線路を物理削除
			orgTiles.extend(newTiles);
			//orgTiles = orgTiles.slice(1,orgTiles.len());
			pathSrcToDest = Path.Load(orgTiles);
			HgLog.Info("retry to build succeeded.new:"+HgTile(newTiles[0])+"-"+HgTile(newTiles.top())
				+" result:"+HgTile(orgTiles[0])+"-"+HgTile(orgTiles.top()));
			/*foreach(i,t in orgTiles) {
				if(i>=1 && orgTiles[i] == orgTiles[i-1]) {
					HgLog.Error("same tile:"+HgTile(orgTiles[i])+" "+i);
				}
			}*/
			if(!BuildDone()) {
				HgLog.Warning("BuildDone(retry) failed");
				return false;
			}
			return true;
		} else {
			HgLog.Warning("retry to build failed");
			return false;
		}
	}
	
	function BuildDone() {
		buildedPath = BuildedPath(isReverse?pathSrcToDest.Reverse():pathSrcToDest);
		if(!notFlatten && !FlattenRails(buildedPath)) {
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
			if(AIMap.DistanceManhattan(prev, path.GetTile()) != 1 || !HgTile.IsStraightTrack(tracks) 
					|| AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_ROAD) || AITile.HasTransportType(prev, AITile.TRANSPORT_ROAD)) {
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
					if(AIError.GetLastError()!=AIError.ERR_ALREADY_BUILT/*列車が迷い込んだ等*/) { 
						return false;
					}
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
			
			local revDir = HgTile.GetRevDir(prev, path.GetTile(),isRevReverse);
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
	
	function BuildUnderground(path,prev,prev2,prev3,underground) {
		local d = (path.GetTile()-prev)/AIMap.DistanceManhattan(path.GetTile(), prev);
		local A0 = null;
		local A1 = null;
		local A2 = prev;
		local L = underground.level;
		if(prev2 != null) {
			if(prev3 == null) {
				HgLog.Warning("prev3 == null");
				return false;
			}
			if(d != prev2-prev3) {
				HgLog.Warning("d != prev2-prev3 "+HgTile.GetTilesString([path.GetTile(),prev,prev2,prev3]));
				return false;
			}
			A0 = prev3;
			A1 = prev2;
			AIRail.RemoveRail(A0,A1,A2);
			if(!RailPathFinder._BuildTunnelEntrance( A0, A1, A2, L, false )) {
				HgLog.Warning("_BuildTunnelEntrance( A0, A1, A2, L )");
				return false;
			}
		}
		local B2 = path.GetTile();
		local revDir = HgTile.GetRevDir(prev, path.GetTile(),isRevReverse);
		for(local cur = A2; cur != B2; cur += d) {
			if(AITile.GetMinHeight(cur) < L && !HgTile.LevelBound(cur,cur+d,L)) {
				HgLog.Warning("LevelBound(cur,cur+d,L)");
				return false;
			}
			if(isRebuildForHomeward) {
				if(AITile.GetMinHeight(cur+revDir) < L && !HgTile.LevelBound(cur+revDir,cur+d+revDir,L)) {
				}
			}
		}
		local B1 = B2 + d;
		local B0 = B1 + d;
		if(!RailPathFinder._BuildTunnelEntrance( B0, B1, B2, L, false )) {
			HgLog.Warning("_BuildTunnelEntrance( B0, B1, B2, L )");
			return false;
		}
		if (AITunnel.GetOtherTunnelEnd(A2) == B2) {
			HogeAI.WaitForMoney(50000,0,"BuildTunnel(BuildUnderground)");
			if(A0 != null && (!AIRail.AreTilesConnected(A0,A1,A2) || !AICompany.IsMine(AITile.GetOwner(A1)))) {
				AddRollback({name="rail",tiles=[A0,A1,A2]});
				if(!RailBuilder.BuildRailUntilFree(A0, A1, A2)) {
					HgLog.Warning("BuildRail failed(BuildUnderground)"+HgTile.GetTilesString([A0,A1,A2])+" "+AIError.GetLastErrorString());
					return false;
				}
				BuildSignal(A0,A1,A2);
			}
			AddRollback({name="tunnel",tiles=[A2]});
			if((!AITunnel.IsTunnelTile(A2) || !AICompany.IsMine(AITile.GetOwner(A2))) 
					&& !BuildUtils.BuildTunnelSafe(AIVehicle.VT_RAIL, A2)) {
				HgLog.Warning("BuildTunnel failed(BuildUnderground)"+HgTile(A2)+" "+AIError.GetLastErrorString());			
				return false;
			}
			return true;
		}
		HgLog.Warning("!AITunnel.GetOtherTunnelEnd(A2) == B2 "+HgTile.GetTilesString([path.GetTile(),prev,prev2,prev3]));
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
	

	function ChangeBridge(prevprev, prev, next) {
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
		if(direction < 0) direction *= -1;
		
		local tracks = AIRail.GetRailTracks(prev);
		local removed = [];
		if(tracks == AIRail.RAILTRACK_NE_SW) {
		} else if(tracks == AIRail.RAILTRACK_NW_SE) {
		} else {
			HgLog.Warning("unexpected tracks."+HgTile(prev)+" "+tracks);
			return false;
		}
		
		local diagonal = direction == prev - next || direction == next - prev;
		local n_node = prev - direction;
		HgLog.Info("diagonal:"+diagonal+" n_node:"+HgTile(n_node)+" direction:"+direction+" revdir:"+HgTile.GetRevDir(next,prev,isReverse)
			+" next:"+HgTile(next)+" prev:"+HgTile(prev)+" isReverse:"+isReverse);
		local length = 4;
		local firstOptional = false;
		
		local must = {};
		local optional = {};
		if(diagonal) {
			must.rawset(next,true);
			must.rawset(prev,true);
		} else {
			must.rawset(prev,true);
		}
		if(isRebuildForHomeward) {
			local revDir = HgTile.GetRevDir(prev,prevprev,isReverse);
			foreach(t,_ in must) {
				if(!must.rawin(t+revDir)) {
					optional.rawset(t+revDir,true);
				}
			}
		}
		local minTile = IntegerUtils.IntMax;
		local maxTile = 0;
		foreach(t,_ in must) {
			minTile = min(minTile,t);
			maxTile = max(maxTile,t);
		}
		local mustStart = minTile - direction;
		local mustEnd = maxTile + direction;
		foreach(t,_ in optional) {
			minTile = min(minTile,t);
			maxTile = max(maxTile,t);
		}
		local startTile = minTile - direction;
		local endTile = maxTile + direction;
		local isNg = function(cur):(direction,tracks){
			return RailPathFinder._IsSlopedRail(cur - direction, cur, cur + direction) 
						|| AIRail.GetRailTracks(cur) != tracks 
						|| RailPathFinder._IsUnderBridge(cur);
		};
		while(startTile<mustStart && isNg(startTile)) {
			startTile += direction;
		}
		while(endTile>mustEnd && isNg(endTile)) {
			endTile -= direction;
		}
		
		HogeAI.WaitForMoney(20000,0,"ChangeBridge");
		local currentRailType = AIRail.GetCurrentRailType();
		AIRail.SetCurrentRailType(AIRail.GetRailType(n_node));
		
		for(local cur=startTile; cur<=endTile; cur+=direction) {
			if(!RailBuilder.RemoveRailTrackUntilFree(cur, tracks)) {
				HgLog.Warning("fail RemoveRailTrack."+HgTile(cur)+" "+AIError.GetLastErrorString());
				foreach(mark in removed) {
					if(!BuildUtils.BuildRailTrackSafe(mark[0], mark[1])) {
						HgLog.Warning("fail BuildRailTrackSafe "+HgTile(mark[0])+" "+AIError.GetLastErrorString());
					}
				}
				AIRail.SetCurrentRailType(currentRailType);
				return false;
			} else {
				removed.push([cur,tracks]);
			}
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
		local buildSignal = buildedPath.route == null || !buildedPath.route.IsSingle();
		local prevprev = null;
		local prev = null;
		while(path != null) {
			if(prev != null && (path.GetTile() == startTile || path.GetTile() == endTile)) {
				if(buildSignal) {
					// 跳ね返った列車に対して逆向きの信号が設置され、列車が止まってしまう事があるので信号設置は10日後
					HogeAI.Get().PostPending(10, SignalBuilder(prev, path.GetTile(), AIRail.SIGNALTYPE_PBS_ONEWAY) );
				}
				local startPath = path;
				path = path.GetParent();
				while(path != null) {
					if(path.GetTile() == endTile || path.GetTile() == startTile) {
						startPath.parent_ = path;
						HgLog.Info(HgTile(startPath.GetTile())+".parent = "+HgTile(path.GetTile())+" route:"+buildedPath.route);
						if(buildSignal && path.GetParent()!=null && path.GetParent().GetParent()!=null) {
							HogeAI.Get().PostPending(10, SignalBuilder(path.GetParent().GetTile(), path.GetParent().GetParent().GetTile(), AIRail.SIGNALTYPE_PBS_ONEWAY) );
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
	
	static function ChangeTunnel(start,end) {
		if(!AITile.HasTransportType(start, AITile.TRANSPORT_RAIL)) {
			return false;
		}
		local tracks = AIRail.GetRailTracks(start);
		local tileList = AITileList();
		tileList.AddRectangle(start,end);
		tileList.Valuate(AITile.HasTransportType, AITile.TRANSPORT_RAIL);
		tileList.KeepValue(1);
		tileList.Valuate(AIRail.GetRailTracks);
		tileList.KeepValue(tracks);
		tileList.Valuate(AITile.GetSlope);
		tileList.KeepValue(AITile.SLOPE_FLAT);
		tileList.Valuate(AITile.GetOwner);
		tileList.KeepValue(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF));
		if(tileList.Count() != 5) {
			return false;
		}

		local height = AITile.GetMaxHeight(start);
		if(height == 0) {
			return false;
		}

		HgLog.Info("Start ChangeTunnel "+HgTile(start)+"-"+HgTile(end));
		local t1 = min(start,end);
		local t2 = max(start,end);
		local direction = (t2 - t1) / 4;

		HogeAI.WaitForMoney(20000,0,"ChangeTunnel");
		local currentRailType = AIRail.GetCurrentRailType();
		AIRail.SetCurrentRailType(AIRail.GetRailType(t1));

		local cur = t1;
		local removedRails = [];
		for(local i=0; i<5; i++) {
			if(!RailBuilder.RemoveRailTrackUntilFree(cur, tracks)) {
				HgLog.Warning("fail RemoveRailTrack."+HgTile(cur)+" "+AIError.GetLastErrorString());
				RailBuilder.RollbackRails(removedRails);
				AIRail.SetCurrentRailType(currentRailType);
				return false;
			}
			removedRails.push([cur,tracks]);
			cur += direction;
		}
		
		
		if(!HgTile.LevelBound( t1, t1 + direction, height-1 )) {
			RailBuilder.RollbackRails(removedRails);
			AIRail.SetCurrentRailType(currentRailType);
			return false;
		}
		if(!HgTile.LevelBound( t1 + direction * 3, t1 + direction * 4, height-1 )) {
			RailBuilder.RollbackRails(removedRails);
			AIRail.SetCurrentRailType(currentRailType);
			return false;
		}
		if(!BuildUtils.BuildTunnelSafe(AIVehicle.VT_RAIL, t1 + direction)) {
			HgLog.Warning("fail BuildTunnel "+HgTile(t1 + direction) + " "+AIError.GetLastErrorString());
			RailBuilder.RollbackRails(removedRails);
			AIRail.SetCurrentRailType(currentRailType);
			return false;
		}
		
		local pathBuildedPath = RailBuilder.SearchPathBuildedPath(t1);
		if(pathBuildedPath != null) {
			if(!RailBuilder.ChangeBridgePath(pathBuildedPath[1], t1 + direction, t1 + direction * 3)) {
				HgLog.Warning("ChangeBridgeBuildedPath not found path "+HgTile(t1)+" "+HgTile(t2));
			} else {
				pathBuildedPath[1].ChangePath();
			}
		}
		foreach(t in [t1,t2]) {
			if(!BuildUtils.BuildRailTrackSafe(t, tracks)) {
				HgLog.Warning("fail BuildRailTrackSafe "+HgTile(t)+" "+AIError.GetLastErrorString());
			}
		}
		AIRail.SetCurrentRailType(currentRailType);
		return true;
	}

	static function RollbackRails(removedRails) {
		foreach(mark in removedRails) {
			if(!BuildUtils.BuildRailTrackSafe(mark[0], mark[1])) {
				HgLog.Warning("fail BuildRailTrackSafe "+HgTile(mark[0])+" "+AIError.GetLastErrorString());
			}
		}
	}
		
	function SearchPathBuildedPath(tile) {
		local buildedPath = BuildedPath.GetByTile(tile);
		if(buildedPath == null || !(buildedPath instanceof BuildedPath)) {
			HgLog.Warning("not found tile(SearchPathBuildedPath) "+HgTile(tile)+" buildedPath:"+buildedPath);
			return null;
		}
		local path = buildedPath.path;
		while(path != null) {
			if(path.GetTile() == tile) {
				return [path, buildedPath];
			}
			path = path.GetParent();
		}
		HgLog.Warning("not found tile(SearchPathBuildedPath) "+HgTile(tile)+" route:"+buildedPath.route);
		return null;
	}
	
}

class SignalBuilder extends Construction {
	static function CreateByParams(params) {
		return SignalBuilder(params.tile, params.front, params.signal);
	}
	
	tile = null;
	front = null;
	signal = null;

	constructor(tile, front, signal) {
		Construction.constructor({
			typeName = "SignalBuilder"
			tile = tile
			front = front
			signal = signal
		});
		this.tile = tile;
		this.front = front;
		this.signal = signal;
	}

	function Load() {
		DoBuild();
	}

	function DoBuild() {
		local execMode = AIExecMode();
		BuildUtils.RemoveSignalSafe( tile, front );
		BuildUtils.BuildSignalSafe( tile, front, signal );
	}
}
Construction.nameClass.SignalBuilder <- SignalBuilder;

class RailPathBuilder extends Construction {
	
	static function CreateByParams(params) {
		return RailPathBuilder();
	}

	static function GetStartArray(path) {
		local result = [];
		local prev3 = null;
		local prev2 = null;
		local prev = null;
		for(;path != null; prev3 = prev2, prev2 = prev, prev = path.GetTile(), path = path.GetParent()) {
			local next = path.GetParent() != null ? path.GetParent().GetTile() : null;
			if(next == null || prev == null || prev2 == null || prev3 == null) {
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
			local d3 = AIMap.DistanceManhattan(prev,prev2);
			if(d1==1 && d2==1 && !AIRail.AreTilesConnected(next,cur,prev)) { /*double depots地点からは分岐不可*/
				continue;
			}
			if(d2==1 && d3==1 && !AIRail.AreTilesConnected(cur,prev,prev2)) { /*double depots地点からは分岐不可*/
				continue;
			}
			result.push([cur, prev, prev2, prev3]);
		}
		return result;
		
	}
	
	srcTilesGetter = null;
	destTilesGetter = null;
	ignoreTiles = null;
	limitCount = null;
	eventPoller = null;
	debug = false;
	
	reversePath = null;
	isReverse = null;
	isRevReverse = null;
	
	pathBuildParams = null;

	dangerTiles = null;
	costTurn = null;
	revOkTiles = null;
	notFlatten = null;
	isOutward = null;
	noRollbackOnLoad = null;
	orgTile = null;
	
	
	isFoundGoal = null;
	buildedPath = null;
	foundedRevPath = null;
	lastRevCheck = null;
	isNotCheckRevPath = null;
	
	
	constructor() {
		Construction.constructor({
			typeName = "RailPathBuilder"
		});
	}
	
	function Initialize(srcTilesGetter, destTilesGetter, ignoreTiles, limitCount, eventPoller, reversePath = null) {
		this.srcTilesGetter = srcTilesGetter;
		this.destTilesGetter = destTilesGetter;
		this.ignoreTiles = ignoreTiles;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.reversePath = reversePath;
		this.isReverse = false;
		this.isRevReverse = false;
		
		this.isNotCheckRevPath = false;
		this.revOkTiles = {};
		this.notFlatten = false;
		this.noRollbackOnLoad = false;
	}
	
	function StationToStation(srcStation, destStation, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetArrivalsTile());
		ignoreTiles.extend(destStation.GetDeparturesTile());
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		Initialize(
			Container(srcStation.GetDeparturesTiles()), 
			Container(destStation.GetArrivalsTiles()),
			ignoreTiles, limitCount, eventPoller, reversePath);
		if(reversePath == null) {
			dangerTiles = [];
			dangerTiles.extend(destStation.GetDepartureDangerTiles());
			dangerTiles.extend(srcStation.GetArrivalDangerTiles());
			dangerTiles = dangerTiles;
			foreach(goalTiles in destStation.GetArrivalsTiles()) {
				RailPathFinder.SetRevOkTiles(revOkTiles, goalTiles);
			}
		}
		return this;
	}
	
	function StationToStationReverse(srcStation, destStation, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		Initialize(
			Container(srcStation.GetArrivalsTiles()), 
			Container(destStation.GetDeparturesTiles()),
			ignoreTiles, limitCount, eventPoller, reversePath);
		isReverse = true;
		return this;
	}

	function StationToStationSingle(srcStation, destStation, limitCount, eventPoller, reversePath = null) {
		local ignoreTiles = [];
		ignoreTiles.extend(srcStation.GetIgnoreTiles());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		Initialize(
			Container(srcStation.GetDeparturesTiles()), 
			Container(destStation.GetArrivalsTiles()),
			ignoreTiles, limitCount, eventPoller, reversePath);
		isReverse = true;
		dangerTiles = [];
		return this;
	}
	
	function PathToStation(srcPathGetter, destStation, limitCount, eventPoller, reversePath = null, isArrival = true) {
		local ignoreTiles = [];
		ignoreTiles.extend(isArrival ? destStation.GetDeparturesTile() : destStation.GetArrivalsTile());
		ignoreTiles.extend(destStation.GetIgnoreTiles());
		local goals = isArrival ? destStation.GetArrivalsTiles() : destStation.GetDeparturesTiles();
		Initialize(
			GetterFunction(function():(srcPathGetter) {
				//return RailToAnyRailBuilder.GetStartArray(srcPathGetter.Get().Reverse());
				return RailPathBuilder.GetStartArray(srcPathGetter.Get().Reverse());
			}),
			Container(goals), 
			ignoreTiles, limitCount, eventPoller, reversePath);
		if(reversePath == null) {
			dangerTiles = isArrival ? destStation.GetDepartureDangerTiles() : destStation.GetArrivalDangerTiles();
			local revGoals = isArrival ? destStation.GetDeparturesTiles() : destStation.GetArrivalsTiles();
			foreach(goalTiles in revGoals) {
				RailPathFinder.SetRevOkTiles(revOkTiles, goalTiles);
			}
		}
		return this;
	}

	function PtoP(arrivalsTiles, departuresTiles, revArrivalsTiles, revDeparturesTiles, limitCount, eventPoller) {
		local ignoreTiles = [];
		// 逆側をignoreTileにする事で最低限出られるようにする
		local lenArr = revArrivalsTiles.len();
		ignoreTiles.push(revDeparturesTiles[0] + HgTile.GetRevDir(revDeparturesTiles[1],revDeparturesTiles[0],true));
		ignoreTiles.push(revArrivalsTiles[lenArr-1] + HgTile.GetRevDir(revArrivalsTiles[lenArr-2],revArrivalsTiles[lenArr-1],false));
		Initialize( 
			Container(departuresTiles), // starts
			Container(arrivalsTiles), // goals
			ignoreTiles, limitCount, eventPoller);
		return this;
	}

	function PtoPReverse(arrivalsTiles, departuresTiles, reversePath, limitCount, eventPoller) {
		local ignoreTiles = [];
		Initialize(
			Container(departuresTiles), 
			Container(arrivalsTiles),
			ignoreTiles, limitCount, eventPoller, reversePath);
		return this;
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
			local pathFinder2 = GetPathFinder2();
			local startDate = AIDate.GetCurrentDate();
			local path2 = pathFinder2.FindPath(2, null);
			if(pathFinder2.IsFoundGoal()) {
				HgLog.Info("pathFinder2 found goal "+HgTile(path2.GetTile()));
				foundedRevPath = path2;
				return false;
			}
			/*if(AIDate.GetCurrentDate() - startDate >= 5) {
				isNotCheckRevPath = true; // たまにすごく時間がかかる事がある
			}*/
			isNotCheckRevPath = true; //初回だけやる
		}
		return true;
		
	}
	
	function GetPathFinder1() {
		local pathFinder1 = RailPathFinder();
		pathFinder1.engine = pathBuildParams.engine;
		pathFinder1.cargo = pathBuildParams.cargo;
		pathFinder1.platformLength = pathBuildParams.platformLength;
		pathFinder1.distance = pathBuildParams.distance;
		pathFinder1.isSingle = pathBuildParams.isSingle;
		if(pathBuildParams.isOneway || pathBuildParams.isSingle) {
			pathFinder1.isOutward = false;
		}

		pathFinder1.isOutward = isOutward;
		pathFinder1.isRevReverse = isRevReverse;
		if(pathBuildParams.isBiDirectional || !pathBuildParams.isSingle) {
			pathFinder1.trainDirection = 2;
		} else {
			pathFinder1.trainDirection = isReverse ? 0 : 1;
		}
		pathFinder1.dangerTiles = dangerTiles;
		pathFinder1.revOkTiles = revOkTiles;
		pathFinder1.orgTile = orgTile;
		pathFinder1.debug = debug;
		local starts = srcTilesGetter.Get();
		local goals = destTilesGetter.Get();
		if(starts.len()==0) {
			HgLog.Warning("RailPathBuilder: No start(pathFinder1)");
			return null;
		}
		if(goals.len()==0) {
			HgLog.Warning("RailPathBuilder: No goal(pathFinder1)");
			return null;
		}
		pathFinder1.InitializePath(starts, goals, ignoreTiles, reversePath);
		if(costTurn != null) {
			pathFinder1._cost_turn = costTurn;
		}
		return pathFinder1;
	}

	function GetPathFinder2() {
		local pathFinder2 = RailPathFinder();
		pathFinder2.engine = pathBuildParams.engine;
		pathFinder2.cargo = pathBuildParams.cargo;
		pathFinder2.platformLength = pathBuildParams.platformLength;
		pathFinder2.distance = pathBuildParams.distance;
		pathFinder2.isSingle = pathBuildParams.isSingle;
		if(pathBuildParams.isOneway || pathBuildParams.isSingle) {
			pathFinder2.isOutward = false;
		}
		
		pathFinder2.isOutward = reversePath == null && !pathBuildParams.isSingle;
		pathFinder2.dangerTiles = dangerTiles;
		pathFinder2.isRevReverse = reversePath == null ? !isRevReverse : isRevReverse;
		if(pathBuildParams.isBiDirectional) {
			pathFinder2.trainDirection = 2;
		} else {
			pathFinder2.trainDirection = isReverse ? 1 : 0;
		}
		pathFinder2.revOkTiles = revOkTiles;;
		pathFinder2.orgTile = orgTile;
		pathFinder2.debug = debug;
		pathFinder2.InitializePath(destTilesGetter.Get(), srcTilesGetter.Get(), ignoreTiles, reversePath);
		return pathFinder2;
	}
	
	function Load() {
	}
	
	function DoBuild() {
		if(!("isSingle" in pathBuildParams)) {
			pathBuildParams.isSingle <- false;
		}
		if(!("isBiDirectional" in pathBuildParams)) {
			pathBuildParams.isBiDirectional <- false;
		}
		if(!("distance" in pathBuildParams)) {
			pathBuildParams.distance <- null;
		}
		if(!("isOneway" in pathBuildParams)) {
			pathBuildParams.isOneway <- false;
		}
	
		isFoundGoal = false;
		isOutward = reversePath == null && !pathBuildParams.isSingle;
		
		local path1data = GetBuilt("path1");
		local path2data = GetBuilt("path2");
		if(path1data==null && path2data==null) {
			local pathFinder1 = GetPathFinder1();
			if(pathFinder1 == null) {
				return false;
			}
			local path1 = pathFinder1.FindPath(limitCount, this);
			if(foundedRevPath != null) {
				SetBuilt("path2",path2data = foundedRevPath.SaveWithMode());
			} else if(pathFinder1.IsFoundGoal()){
				HgLog.Info("pathFinder1 found goal "+HgTile(path1.GetTile()));
				SetBuilt("path1",path1data = path1.SaveWithMode());
			} else {
				HgLog.Warning("RailPathBuilder: No path found");
				return false;
			}
		}
		isNotCheckRevPath = true; // RailBuilder中にpathFinder2が呼ばれるのを防止

		buildedPath = GetBuilt("buildedPath");
		if(buildedPath == null) {
			local railBuilder1 = null;		
			// dest->srcの順に構築する。ロールバックの都合完成するまで列車が入ってこないようにする為。
			if(path2data != null) {
				railBuilder1 = RailBuilder(
					Path.LoadWithMode(path2data).Reverse(), isReverse, ignoreTiles, this); 
				railBuilder1.isRevReverse = isReverse ? isRevReverse : !isRevReverse;
				railBuilder1.pathFinder = GetPathFinder2();
			} else {
				railBuilder1 = RailBuilder(Path.LoadWithMode(path1data), isReverse, ignoreTiles, this);
				railBuilder1.isRevReverse =  isReverse ? isRevReverse : !isRevReverse;
				railBuilder1.pathFinder = GetPathFinder1();
			}
			if(noRollbackOnLoad) {
				railBuilder1.saveData.noRollbackOnLoad <- true;
			}
			railBuilder1.isRebuildForHomeward = isOutward;
			if(pathBuildParams.isSingle) {
				railBuilder1.isNoSignal = true;
			}
			railBuilder1.cargo = pathBuildParams.cargo;
			railBuilder1.distance = pathBuildParams.distance;
			railBuilder1.notFlatten = notFlatten;
			if(!railBuilder1.Build()) {
				railBuilder1.Rollback();
				HgLog.Warning("RailPathBuilder: railBuilder1.Build failed.");
				return false;
			}
			buildedPath = railBuilder1.buildedPath;
			AddBuilt("buildedPath",buildedPath);
		}
		isFoundGoal = true;
		return true;
	}
	
	function Remove() {
		if(buildedPath != null) {
			buildedPath.Remove();
		}
	}
	
	function IsFoundGoal() {
		return isFoundGoal;
	}
}
Construction.nameClass.RailPathBuilder <- RailPathBuilder;

class ConstructionRailBuilder extends Construction {
	
	depots = null;
	depotInfos = null;
	
	constructor(params=null) {
		Construction.constructor(params);
		this.depots = [];
		this.depotInfos = {};
	}
	
	function BuildDoubleDepots(path,interval,isFirstLine=false) {
		if(path == null) {
			return null;
		}
		local firstDepot = null;
		foreach(built in path.BuildDoubleDepotInterval(interval,isFirstLine)) {
			depots.extend(built.depots);
			if(firstDepot == null) {
				firstDepot = built.depots[0];
			}
			AddRollback(built.depots,"tiles");
			depotInfos.rawset( built.mainTiles[1], {depots=built.depots, mainTiles=built.mainTiles} );
		}
		/*
		while(path != null) {
			local built = path.BuildDoubleDepot(isFirstLine);
			if(built == null) {
				break;
			}
			depots.extend(built.depots);
			if(firstDepot == null) {
				firstDepot = built.depots[0];
			}
			AddRollback(built.depots,"tiles");
			depotInfos.rawset( built.mainTiles[1], {depots=built.depots, mainTiles=built.mainTiles} );
			path = built.path.GetParentByDistance(interval);
		}*/
		return firstDepot;
	}
	
	
	function BuildSingleDepot(path) {
		if(path == null) {
			return null;
		}
		local built = path.BuildDepotForRail();
		if(built.path != null) {
			depots.extend(built.depots);
			AddRollback(built.depots,"tiles");
			depotInfos.rawset( built.mainTiles[1], {depots=built.depots, mainTiles=built.mainTiles} );
			return built.depots[0];
		}
		return null;
	}
}

class TwoWayPathToStationRailBuilder extends ConstructionRailBuilder {
	
	static function CreateByParams(params) {
		return TwoWayPathToStationRailBuilder();
	}

	pathDepatureGetter = null; // 駅の出発タイルへ向けたパス
	pathArrivalGetter = null; // 駅の到着タイルへ向けたパス
	isReverse = null; // 上記を逆にする
	isRevReverse = null; // 左右通行指定
	destHgStation = null;
	limitCount = null;
	eventPoller = null;

	pathBuildParams = null;
	
	isBuildDoubleDepots = null;
	isBuildSingleDepotDestToSrc = null;
	noRollbackOnLoad = null;

	buildedPath1 = null;
	buildedPath2 = null;
	destDepot = null;
	
	constructor() {
		ConstructionRailBuilder.constructor({
			typeName = "TwoWayPathToStationRailBuilder"
		});
		this.isBuildDoubleDepots = false;
		this.isBuildSingleDepotDestToSrc = false;
		this.isReverse = false;
		this.noRollbackOnLoad = false;
	}
	
	function Initialize(pathDepatureGetter, pathArrivalGetter, destHgStation, limitCount, eventPoller) {
		this.pathDepatureGetter = pathDepatureGetter; 
		this.pathArrivalGetter = pathArrivalGetter; 
		this.destHgStation = destHgStation;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
	}
	
	function Load() {
	}

	function DoBuild() {
		local depotInterval = VehicleUtils.GetDistance(AIEngine.GetMaxSpeed(pathBuildParams.engine),50);
		HgLog.Info("depotInterval:"+depotInterval);
		// src => dest
		local builder1 = GetBuilt("pathBuilder1");
		if(builder1 == null) {
			builder1 = RailPathBuilder();
		}
		builder1.PathToStation(pathDepatureGetter, destHgStation, limitCount, eventPoller, null, !isReverse);
		builder1.pathBuildParams = pathBuildParams;
		builder1.isReverse = isReverse;
		builder1.isRevReverse = isRevReverse != null ? isRevReverse : isReverse;
		builder1.noRollbackOnLoad = noRollbackOnLoad;
		AddBuilt("pathBuilder1",builder1);
		if(!builder1.Build()) {
			return false;
		}
		buildedPath1 = builder1.buildedPath;
		if(!IsBuilt("depot1")) {
			if(isBuildDoubleDepots) {
				BuildDoubleDepots(buildedPath1.path.SubPathIndex(16),depotInterval,true);
			}
			SetBuilt("depot1");
		}

		// dest => src
		local builder2 = GetBuilt("pathBuilder2");
		if(builder2 == null) {
			builder2 = RailPathBuilder();
		}
		builder2.PathToStation(pathArrivalGetter, destHgStation, limitCount, eventPoller, buildedPath1.path, isReverse );		
		builder2.pathBuildParams = pathBuildParams;
		//if(destHgStation.GetName().find("Flarfingway")!=null) b2.debug = true;
		builder2.isReverse = !isReverse;
		builder2.noRollbackOnLoad = noRollbackOnLoad;
		AddBuilt("pathBuilder2",builder2);
		if(!builder2.Build()) {
			Rollback();
			return false;
		}
		buildedPath2 = builder2.buildedPath;
		if(!IsBuilt("depot2")) {
			if(isBuildDoubleDepots) {
				BuildDoubleDepots(buildedPath2.path.Reverse().SubPathIndex(16),depotInterval);
			}		
			if(isBuildSingleDepotDestToSrc) {
				BuildSingleDepot(buildedPath1.path.Reverse().SubPathIndex(16));
				BuildSingleDepot(buildedPath2.path.Reverse().SubPathIndex(16));
			}
			//SetBuilt("destDepot",destDepot);
			SetBuilt("depot2");
		} else {
			//destDepot = GetBuilt("destDepot");
		}
		return true;
	}
}
Construction.nameClass.TwoWayPathToStationRailBuilder <- TwoWayPathToStationRailBuilder;

class TwoWayStationRailBuilder extends ConstructionRailBuilder {

	static function CreateByParams(params) {
		return TwoWayStationRailBuilder();
	}
	
	srcHgStation = null;
	destHgStation = null;
	limitCount = null;
	eventPoller = null;
	
	pathBuildParams = null;
	
	isBuildDoubleDepots = null;
	isBuildSingleDepotDestToSrcSideDest = null;
	isBuildSingleDepotDestToSrc = null;
	noRollbackOnLoad = null;
	
	buildedPath1 = null;
	buildedPath2 = null;
	srcDepot = null;
	
	constructor() {
		ConstructionRailBuilder.constructor({
			typeName = "TwoWayStationRailBuilder"
		});
	}
	
	function Initialize(srcHgStation, destHgStation, limitCount, eventPoller) {
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.isBuildDoubleDepots = false;
		this.isBuildSingleDepotDestToSrcSideDest = false;
		this.isBuildSingleDepotDestToSrc = false;
		this.depots = [];
		this.depotInfos = {};
		this.noRollbackOnLoad = false;
	}

	function Load() {
	}
	
	function DoBuild() {
		local depotInterval = VehicleUtils.GetDistance(AIEngine.GetMaxSpeed(pathBuildParams.engine),100);

		// dest => src
		local builder1 = GetBuilt("pathBuilder1");
		if(builder1 == null) {
			builder1 = RailPathBuilder();
		}
		builder1.StationToStation(destHgStation, srcHgStation, limitCount, eventPoller );
		builder1.pathBuildParams = pathBuildParams;

		builder1.noRollbackOnLoad = noRollbackOnLoad;
		AddBuilt("pathBuilder1",builder1);
		if(!builder1.Build()) {
			return false;
		}
		buildedPath2 = builder1.buildedPath;
		if(!IsBuilt("depot1")) {
			if(isBuildDoubleDepots) {
				BuildDoubleDepots(buildedPath2.path.SubPathIndex(4),depotInterval,true);
			}
			SetBuilt("depot1");
		}

	
		// src => dest
		local builder2 = GetBuilt("pathBuilder2");
		if(builder2 == null) {
			builder2 = RailPathBuilder();
		}
		builder2.StationToStationReverse(destHgStation, srcHgStation, limitCount, eventPoller, buildedPath2.path);
		//builder2.debug = srcHgStation.GetName().find("Sontown") != null ? true : false;
		builder2.pathBuildParams = pathBuildParams;
		builder2.noRollbackOnLoad = noRollbackOnLoad
		AddBuilt("pathBuilder2",builder2);
		if(!builder2.Build()) {
			Rollback();
			return false;
		}
		buildedPath1 = builder2.buildedPath;
		srcDepot = GetBuilt("srcDepot");
		if(!IsBuilt("depot2")) {
			local distance = AIMap.DistanceManhattan( srcHgStation.platformTile, destHgStation.platformTile);
			if(isBuildDoubleDepots && distance > depotInterval) {
				BuildDoubleDepots(buildedPath1.path.SubPathIndex(4),depotInterval);
			}
			if(isBuildSingleDepotDestToSrcSideDest) {
				BuildSingleDepot(buildedPath2.path.Reverse().SubPathIndex(15));
			}
			if(isBuildSingleDepotDestToSrc) {
				srcDepot = BuildSingleDepot(buildedPath2.path);
				SetBuilt("srcDepot",srcDepot);
			}
			SetBuilt("depot2");
		}
		return true;
	}
	
	function GetSrcDepot() {
		return srcDepot;
	}
}
Construction.nameClass.TwoWayStationRailBuilder <- TwoWayStationRailBuilder;

class SingleStationRailBuilder extends ConstructionRailBuilder{
	static function CreateByParams(params) {
		return SingleStationRailBuilder();
	}
	
	srcHgStation = null;
	destHgStation = null;
	limitCount = null;
	eventPoller = null;
	
	pathBuildParams = null;
	
	isBuildSingleDepotDestToSrc = null;
	noRollbackOnLoad = null;
	
	buildedPath = null;
	srcDepot = null;
	
	constructor() {
		ConstructionRailBuilder.constructor({
			typeName = "SingleStationRailBuilder"
		});
	}
	
	function Initialize(srcHgStation, destHgStation, limitCount, eventPoller) {
		this.srcHgStation = srcHgStation;
		this.destHgStation = destHgStation;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.noRollbackOnLoad = false;
	}
	
	function Load() {
	}
	
	function DoBuild() {
		
		local builder = GetBuilt("pathBuilder");
		if(builder==null) {
			builder = RailPathBuilder()
		}
		builder.StationToStationSingle(destHgStation, srcHgStation, limitCount, eventPoller );
		builder.noRollbackOnLoad = noRollbackOnLoad;
		builder.pathBuildParams = pathBuildParams;
		AddBuilt("pathBuilder",builder);
		if(!builder.Build()) {
			return false;
		}
		buildedPath = builder.buildedPath;
		srcDepot = GetBuilt("srcDepot");
		if(isBuildSingleDepotDestToSrc && srcDepot==null) {
			srcDepot = BuildSingleDepot(buildedPath.path.Reverse());
			SetBuilt("srcDepot",srcDepot);
		}
		return true;
	}
	
}
Construction.nameClass.SingleStationRailBuilder <- SingleStationRailBuilder;

class TwoWayPtoPRailBuilder extends ConstructionRailBuilder {
	departuresTiles = null;
	arrivalsTiles = null;
	revDeparturesTiles = null;
	revArrivalsTiles = null;
	limitCount = null;
	eventPoller = null;
	
	pathBuildParams = null;
	notFlatten = null;
	
	buildedPath1 = null;
	buildedPath2 = null;
	
	constructor(departuresTiles, arrivalsTiles, revDeparturesTiles, revArrivalsTiles, limitCount, eventPoller) {
		ConstructionRailBuilder.constructor();
		this.departuresTiles = departuresTiles;
		this.arrivalsTiles = arrivalsTiles;
		this.revDeparturesTiles = revDeparturesTiles;
		this.revArrivalsTiles = revArrivalsTiles;
		this.limitCount = limitCount;
		this.eventPoller = eventPoller;
		this.notFlatten = false;
	}
	
	function DoBuild() {
		// 列車はidx0に向かって走る。検索は目的地がstartで出発地がgoal
		// dest => src
		local l1 = arrivalsTiles.len();
		local goalsTiles = [[arrivalsTiles[l1-1],arrivalsTiles[l1-2],arrivalsTiles[l1-3],arrivalsTiles[l1-4]]];
		local startTiles = [[departuresTiles[0],departuresTiles[1],departuresTiles[2],departuresTiles[3]]];
		
		local b1 = RailPathBuilder().PtoP(goalsTiles, startTiles, revArrivalsTiles, revDeparturesTiles, limitCount, eventPoller );
		b1.pathBuildParams = pathBuildParams;
		b1.notFlatten = notFlatten;
		foreach(tiles in [revDeparturesTiles,revArrivalsTiles]) {
			RailPathFinder.SetRevOkTiles(b1.revOkTiles, tiles);
		}
		//b1.debug = true;
		if(!b1.Build()) {
			return false;
		}
		if(!b1.IsFoundGoal()) {
			if(!b1.Build()) {
				b1.Remove();
				return false;
			}
		}
		buildedPath1 = b1.buildedPath;
		AddRollback(buildedPath1);

	
		local l2 = revArrivalsTiles.len();
		//local revStartTiles = [[revArrivalsTiles[l2-1],revArrivalsTiles[l2-2],revArrivalsTiles[l2-3]]];
		//local revGoalsTiles = [[revDeparturesTiles[0],revDeparturesTiles[1],revDeparturesTiles[2]]];
		local revStartTiles = [[revArrivalsTiles[l2-1],revArrivalsTiles[l2-2],revArrivalsTiles[l2-3],revArrivalsTiles[l2-4]]];
		local revGoalsTiles = [[revDeparturesTiles[0],revDeparturesTiles[1],revDeparturesTiles[2],revDeparturesTiles[3]]];
		// src => dest
		//HgLog.Warning("arrivalsTiles:"+HgTile(arrivalsTiles.top()));
		//HgLog.Warning("buildedPath:"+HgTile(tiles[0])+"-"+HgTile(tiles.top()));
		//HgLog.Warning("departuresTiles:"+HgTile(departuresTiles[0]));
		local reverseTiles = [];
		local reverseTilesMap = {};
		reverseTiles.extend(arrivalsTiles);
		foreach(tile in arrivalsTiles) {
			reverseTilesMap.rawset(tile,tile);
		}
		local tiles = buildedPath1.path.GetTiles();
		foreach(tile in tiles) {
			if(reverseTilesMap.rawin(tile)) continue; // 重なり合わせを除去
			reverseTiles.push(tile);
			reverseTilesMap.rawset(tile,tile);
		}
		foreach(tile in departuresTiles) {
			if(reverseTilesMap.rawin(tile)) continue;
			reverseTiles.push(tile);
			reverseTilesMap.rawset(tile,tile);
		}
		HgLog.Info("reversePath:"+HgTile.GetTilesString(reverseTiles));
		/*foreach(i,t in reverseTiles) {
			if(i>=1 && reverseTiles[i] == reverseTiles[i-1]) {
				HgLog.Error("same tile:"+HgTile(reverseTiles[i]));
			}
		}*/
		
		local b2 = RailPathBuilder().PtoPReverse(revStartTiles, revGoalsTiles, Path.Load(reverseTiles), limitCount, eventPoller );
		//b2.debug = srcHgStation.GetName().find("Sontown") != null ? true : false;
		//b2.debug = true;
		b2.pathBuildParams = pathBuildParams;
		b2.notFlatten = notFlatten;
		//b2.costTurn = 0;
		if(!b2.Build()) {
			Rollback();
			return false;
		}
		buildedPath2 = b2.buildedPath;
		AddRollback(buildedPath2);
		return true;
	}
	
}

class RailToAnyRailBuilder extends RailBuilder {
	originalPath = null;
	buildPointsSuceeded = false;
	
	constructor(railPath, goalsArray, ignoreTiles, isReverse, limitCount, eventPoller, pathFinder) {
		this.originalPath = railPath;
		this.isReverse = isReverse;
		this.cargo = pathFinder.cargo;
		this.distance = pathFinder.distance;

		local startArray = /*TailedRailBuilder.*/GetStartArray(!isReverse ? railPath.Reverse() : railPath);
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
			newPathFinder.isRevReverse = !pathFinder.isRevReverse; // 帰路の向きも逆になる
			newPathFinder.dangerTiles = pathFinder.dangerTiles;			
			//newPathFinder.debug = true;
			local reversePath = pathFinder.reversePath;
			if(reversePath != null) {
				reversePath = reversePath.Reverse();
			}
			HgLog.Info("startArray:"+HgTile.GetTilesString(startArray[0])+" "+startArray.len()+" reversePath:"+reversePath);
			newPathFinder.InitializePath(startArray, goalsArray, ignoreTiles, reversePath);
			path = FindPath(newPathFinder, limitCount, eventPoller);
		}
		RailBuilder.constructor(path, isReverse, ignoreTiles, eventPoller);
		
		this.pathFinder = pathFinder;
	}

	static function IsForkable(prevprev,prev,fork) {
		return HgTile(prev).CanForkRail(HgTile(fork));
	}
	
	
	static function GetStartArray(path) {
		local result = [];
		path.IterateRailroadPoints(function(prev3,prevprev,prev,fork,next):(result) {
			if((HogeAI.IsBuildable(fork) || ( AICompany.IsMine(AITile.GetOwner(fork)) && RailPathFinder.CanChangeBridgeStatic(fork,false)))
					&& RailToAnyRailBuilder.IsForkable(prevprev,prev,fork)) {
				result.push([fork,prev,prevprev,prev3]);
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

}

class RailRemover extends Construction {
	static function CreateByParams(params) {
		return RailRemover(
			params.array_, 
			params.routeId, 
			params.rollbackIfFailed, 
			params.saveLandHeight);
	}
	
	array_ = null;
	routeId = null;
	rollbackIfFailed = null;
	saveLandHeight = null;
	
	constructor(array_, routeId, rollbackIfFailed=false, saveLandHeight=false) {
		Construction.constructor({
			typeName = "RailRemover"
			array_ = array_
			routeId = routeId
			rollbackIfFailed = rollbackIfFailed
			saveLandHeight = saveLandHeight
		});
		this.array_ = array_;
		this.routeId = routeId;
		this.rollbackIfFailed = rollbackIfFailed;
		this.saveLandHeight = saveLandHeight;
		
		saveData.railType <- null;
	}

	function Load() {
		HgLog.Info("RailRemover.Load() rollbackIfFailed:"+rollbackIfFailed);
		if(rollbackIfFailed) {
			Rollback();
		} else {
			DoBuild();
		}
	}

	function DoBuild() {
		local execMode = AIExecMode();
		if(!_DoBuild()) {
			if(rollbackIfFailed) {
				Rollback();
			}
			return false;
		}
		return true;
	}
	
	function _DoBuild() {
		// 先にAddRollbackしているのは、成功=>AddRollbackの間でsaveされると、Rollbackされないから。
		// 従ってRollback中の失敗は無視する必要がある
		local size = array_.len();
		local depotInfos = routeId != null && Route.allRoutes.rawin(routeId) ? Route.allRoutes[routeId].depotInfos : null;
		for(local i=1; i<size; i++) {
			if(depotInfos != null) {
				local cur = array_[i];
				if(depotInfos.rawin(cur)) {
					local info = depotInfos.rawget(cur);
					if(info.depots.len()>=2) {
						HgTile(cur).CloseDoubleDepot(info);
					}
					local tiles = [cur];
					tiles.extend(info.depots);
					AddRollback({name="depot", tiles=tiles, depotInfo=info});
					foreach(depot in info.depots) {
						if(!HgTile(depot).RemoveDepot()) {
							HgLog.Warning("RemoveDepot failed: "+HgTile(depot)+" "+AIError.GetLastErrorString());
							if(rollbackIfFailed) {
								return false;
							}
						}
					}
					depotInfos.rawdelete(cur);
				}
			}			
			
			if(saveData.railType == null) {
				saveData.railType = AIRail.GetRailType(array_[i]);
				if(saveData.railType == AIRail.RAILTYPE_INVALID) {
					saveData.railType = null;
				}
			}
			
			if(AIBridge.IsBridgeTile(array_[i]) && i+1<size
					&& AIBridge.GetOtherBridgeEnd(array_[i])==array_[i+1]) {
				local bridgeId = AIBridge.GetBridgeID(array_[i]);
				if(rollbackIfFailed) {
					AddRollback({name="bridge", bridgeId=bridgeId, tiles=[array_[i],array_[i+1]]});
				}
				if(!BuildUtils.RemoveBridgeUntilFree(array_[i])) {
					HgLog.Warning("RemoveBridgeUntilFree failed:"
						+HgTile(array_[i])+" "+AIError.GetLastErrorString());
					if(rollbackIfFailed) {
						return false;
					}
				}
				i++;
			} else if(AITunnel.IsTunnelTile(array_[i]) && i+1<size
					&& AITunnel.GetOtherTunnelEnd(array_[i])==array_[i+1]) {
				if(rollbackIfFailed) {
					AddRollback({name="tunnel", tiles=[array_[i]]});
				}
				if(!BuildUtils.RemoveTunnelUntilFree(array_[i])) {
					HgLog.Warning("RemoveTunnelUntilFree failed:"
						+HgTile(array_[i])+" "+AIError.GetLastErrorString());
					if(rollbackIfFailed) {
						return false;
					}
				}
				i++;
			} else if(AIRail.IsRailTile(array_[i]) && i-1>=0 && i+1<size) {
				local tiles = [array_[i-1],array_[i],array_[i+1]];
				local signal1 = AIRail.GetSignalType(tiles[1],tiles[0]);
				local signal2 = AIRail.GetSignalType(tiles[1],tiles[2]);
				if(rollbackIfFailed) {
					AddRollback({name="rail", tiles=tiles, signals=[signal1,signal2]});
				}
				if(!RailBuilder.RemoveRailUntilFree(array_[i-1],array_[i],array_[i+1])) {
					HgLog.Warning("RemoveRailUntilFree failed:"
						+HgTile.GetTilesString(tiles)+" "+AIError.GetLastErrorString());
					if(rollbackIfFailed) {
						return false;
					}
				}
			}
		}
		return true;
	}
	
	function AddRollback(f) {
		if(saveLandHeight) {
			f.landHeights <- [];
			foreach(t in f.tiles) {
				f.landHeights.push(GetHeights(t));
			}
		}
		saveData.rollbackFacilities.push(f);
	}
	
	function GetHeights(tile) {
		local cornerHeights = [];
		foreach(corner in [AITile.CORNER_W,AITile.CORNER_S,AITile.CORNER_E,AITile.CORNER_N]) {
			cornerHeights.push(AITile.GetCornerHeight(tile, corner));
		}
		return cornerHeights;
	}

	function Rollback() {
		HgLog.Info("RailRemover.Rollback() "+saveData.rollbackFacilities.len());
		local execMode = AIExecMode();
		local oldRailType = AIRail.GetCurrentRailType();
		if(saveData.railType != null) {
			HgLog.Info("saveData.railType:"+AIRail.GetName(saveData.railType));
			AIRail.SetCurrentRailType(saveData.railType);
		}
		_Rollback();
		AIRail.SetCurrentRailType(oldRailType);
	}
	
	function _Rollback() {
		local depotInfos = routeId != null && Route.allRoutes.rawin(routeId) ? Route.allRoutes[routeId].depotInfos : null;
		while(saveData.rollbackFacilities.len() >= 1) {
			local f = saveData.rollbackFacilities.top();
			if(saveLandHeight) {
				foreach(i,cornerHeights in f.landHeights) {
					HgTile.LevelTileCorners(f.tiles[i], cornerHeights);
				}
			}
			switch(f.name) {
				case "rail":
					if(!RailBuilder.BuildRailForce( f.tiles[0],f.tiles[1],f.tiles[2])) {
						HgLog.Warning("BuildRailForce failed.(RailRemover.Rollback)"
							+HgTile.GetTilesString(f.tiles)+" "+AIError.GetLastErrorString());
					}
					foreach(i,signal in f.signals) {
						if(signal == AIRail.SIGNALTYPE_NONE) continue;
						AIRail.BuildSignal( f.tiles[1], f.tiles[i*2], signal );
					}
					break;
				case "bridge":
					if(!RailBuilder.BuildBridgeSafe(AIVehicle.VT_RAIL, f.bridgeId, f.tiles[0], f.tiles[1])) {
						HgLog.Warning("BuildBridgeSafe failed.(RailRemover.Rollback)"
							+HgTile.GetTilesString(f.tiles)+" "+AIError.GetLastErrorString());
					}
					break;
				case "tunnel":
					if(!BuildUtils.BuildTunnelSafe(AIVehicle.VT_RAIL, f.tiles[0])) {
						HgLog.Warning("BuildTunnelSafe failed.(RailRemover.Rollback)"
							+HgTile(f.tiles[0])+" "+AIError.GetLastErrorString());
					}
					break;
				case "deopt":
					local front = f.depotInfo.tiles[0];
					foreach(depot in f.depotInfo.depots) {
						if(!RailBuilder.BuildRailDepotUntilFree(depot,front)) {
							HgLog.Warning("BuildRailDepotUntilFree failed.(RailRemover.Rollback)"
								+HgTile(depot)+" "+HgTile(front)+" "+AIError.GetLastErrorString());
						}
					}
					if(f.depotInfo.depots.len()>=2) {
						if(f.depotInfo.isOpen) {
							HgTile.OpenDoubleDepot(f.depotInfo);
						} else {
							HgTile.CloseDoubleDepot(f.depotInfo);
						}
					}
					depotInfos.rawset(front,f.depotInfo);
					break;
			}
			saveData.rollbackFacilities.pop();
		}
	}
	
	function _tostring() {
		return "RailRemover";
	}
}

Construction.nameClass.RailRemover <- RailRemover;
