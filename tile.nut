
class HgTile {
	static landConnectedCache = {};

	static DIR_NE = 0;
	static DIR_NW = 1;
	static DIR_SE = 2;
	static DIR_SW = 3;
	static DIR_INVALID = 4;
	
	// [NE,NW,SE,SW]
	static DIR4Index = [AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(0, -1),
	                 AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 0)];

	static CornerAroundTileIndex = [AIMap.GetTileIndex(0, 0), AIMap.GetTileIndex(-1, 0),
	                 AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(-1, -1)];
					 
	static DIR8Index = [
		AIMap.GetTileIndex(-1, -1),
	    AIMap.GetTileIndex(-1, 0),
	    AIMap.GetTileIndex(-1, 1),
		AIMap.GetTileIndex(0, -1),
	    AIMap.GetTileIndex(0, 1),
		AIMap.GetTileIndex(1, -1),
	    AIMap.GetTileIndex(1, 0),
		AIMap.GetTileIndex(1, 1)];

	static TrackDirs = [
		[AIRail.RAILTRACK_NE_SW,[0,3]],
		[AIRail.RAILTRACK_NW_SE,[1,2]],
		[AIRail.RAILTRACK_NW_NE,[1,0]],
		[AIRail.RAILTRACK_SW_SE,[3,2]],
		[AIRail.RAILTRACK_NW_SW,[1,3]],
		[AIRail.RAILTRACK_NE_SE,[0,2]]];
	/*
	static TrackDirs = [
		[AIRail.RAILTRACK_NE_SW,[HgTile.DIR_NE,HgTile.DIR_SW]],
		[AIRail.RAILTRACK_NW_SE,[HgTile.DIR_NW,HgTile.DIR_SE]],
		[AIRail.RAILTRACK_NW_NE,[HgTile.DIR_NW,HgTile.DIR_NE]],
		[AIRail.RAILTRACK_SW_SE,[HgTile.DIR_SW,HgTile.DIR_SE]],
		[AIRail.RAILTRACK_NW_SW,[HgTile.DIR_NW,HgTile.DIR_SW]],
		[AIRail.RAILTRACK_NE_SE,[HgTile.DIR_NE,HgTile.DIR_SE]]];
		*/
	
	static StraightRailTracks = [
		AIRail.RAILTRACK_NE_SW,
		AIRail.RAILTRACK_NW_SE
	];

	static DiagonalRailTracks = [
		AIRail.RAILTRACK_NW_NE,
		AIRail.RAILTRACK_SW_SE,
		AIRail.RAILTRACK_NW_SW,
		AIRail.RAILTRACK_NE_SE
	];
	
	static Corners = [
		AITile.CORNER_W,
		AITile.CORNER_S,
		AITile.CORNER_E,
		AITile.CORNER_N
	];
	
	tile = null;
	
	constructor(tile) {
		this.tile = tile;
	}
	
	static function XY(x,y) {
		return HgTile(AIMap.GetTileIndex(x,y));
	}
	
	static function InMapXY(x,y) {
		if(x <= 1) {
			x = 1;
		}
		if(y <= 1) {
			y = 1;
		}
		if(x > AIMap.GetMapSizeX()-2) {
			x = AIMap.GetMapSizeX()-2;
		}
		if(y > AIMap.GetMapSizeY()-2) {
			y = AIMap.GetMapSizeY()-2;
		}
		return HgTile(AIMap.GetTileIndex(x,y));
	}
	
	function GetTileIndex() {
		return tile;
	}

	function X() {
		return AIMap.GetTileX(tile);
	}

	function Y() {
		return AIMap.GetTileY(tile);
	}

	function IsValid() {
		return AIMap.IsValidTile(tile);
	}
	
	function Min(hgTile) {
		return HgTile.XY(min(this.X(),hgTile.X()), min(this.Y(),hgTile.Y()));
	}

	function Max(hgTile) {
		return HgTile.XY(max(this.X(),hgTile.X()), max(this.Y(),hgTile.Y()));
	}

	function GetDir4() {
		return [
			HgTile(tile + HgTile.DIR4Index[0]),
			HgTile(tile + HgTile.DIR4Index[1]),
			HgTile(tile + HgTile.DIR4Index[2]),
			HgTile(tile + HgTile.DIR4Index[3])];
	}
	
	function IsBuildable() {
		return HogeAI.IsBuildable(tile);
	}
	
	function DistanceManhattan(hgTile) {
		return AIMap.DistanceManhattan(this.tile, hgTile.tile);
	}
	
	function Distance(hgTile) {
		return sqrt(AIMap.DistanceSquare(this.tile, hgTile.tile));
	}
	
	function GetDirection(hgTile) {
		local d = DistanceManhattan(hgTile);
		if(hgTile.Y() == Y() + d) {
			return DIR_SE;
		} else if(hgTile.Y() == Y() - d) {
			return DIR_NW;
		} else if(hgTile.X() == X() + d) {
			return DIR_SW;
		} else if(hgTile.X() == X() - d) {
			return DIR_NE;
		} else {
			return DIR_INVALID;
		}
	}
	
	function GetCornerTile(tile, corner) {
		switch(corner) {
			case AITile.CORNER_N:
				return tile;
			case AITile.CORNER_W:
				return tile + 1;
			case AITile.CORNER_E:
				return tile + AIMap.GetMapSizeX();
			case AITile.CORNER_S:
				return tile + AIMap.GetMapSizeX() + 1;
		}
	}
	
	
	function GetCornerTiles() {
		return [HgTile(tile), 
				HgTile(tile + 1), 
				HgTile(tile + AIMap.GetMapSizeX()), 
				HgTile(tile + AIMap.GetMapSizeX() + 1)];
	}
	
	function GetConnectionCorners(hgTile) {
		return HgTile.GetCorners(this.GetDirection(hgTile));
	}

	// CORNER_Nを含むタイルを返す
	static function GetBoundCornerTiles( t1, t2 ) {
		local offset;
		if(AIMap.GetTileX(t1) == AIMap.GetTileX(t2)) {
			offset = AIMap.GetTileIndex(1,0);
		} else {
			offset = AIMap.GetTileIndex(0,1);
		}
		return [max(t1,t2),max(t1,t2)+offset];
	}
	
	// t1とt2は距離1である事
	static function GetBoundHeights( t1, t2 ) {
		local result = [];
		local t = min(t1,t2);
		local corners;
		if(AIMap.GetTileX(t1) == AIMap.GetTileX(t2)) {
			corners = [AITile.CORNER_S,AITile.CORNER_E];
		} else {
			corners = [AITile.CORNER_S,AITile.CORNER_W];
		}
		foreach(c in corners) {
			result.push( AITile.GetCornerHeight( t ,c ) );
		}
		return result;
	}
	
	static function GetBoundMaxHeight( t1, t2 ) {
		local a = HgTile.GetBoundHeights(t1,t2);
		return max(a[0], a[1]);
	}
	
	static function LevelBound( t1, t2, level, checkWaterLeak = true) {
		local lowerCorners = 0;
		local raiseCorners = 0;
		foreach(c in HgTile(t1).GetConnectionCorners(HgTile(t2))) {
			local currentLevel = AITile.GetCornerHeight( t1 ,c );
			if(abs(currentLevel-level) >= 2) {
				return false;
			}
			if(currentLevel != level && HogeAI.Get().IsAvoidRemovingWater() && HgTile.IsAroundRiverCorner(HgTile.GetCornerTile(t1,c))) {
				return false;
			}
			if(currentLevel > level) {
				if(checkWaterLeak && level==0 && HgTile.IsAroundCoastCorner(HgTile.GetCornerTile(t1,c))) {
					return false;
				}
				lowerCorners = lowerCorners | HgTile.GetSlopeFromCorner(c);
			} else if(currentLevel < level) {
				raiseCorners = raiseCorners | HgTile.GetSlopeFromCorner(c);
			}
		}
		if(lowerCorners != 0 && !AITile.LowerTile(t1, lowerCorners)) {
			return false;
		}
		if(raiseCorners != 0 && !AITile.RaiseTile(t1, raiseCorners)) {
			return false;
		}
		
		return true;
	}
	static function ForceLevelBound( t1, t2, level, options = {} ) {
		local lowerOnly = options.rawin("options") ? options["lowerOnly"] : false;
		foreach(c in HgTile(t1).GetConnectionCorners(HgTile(t2))) {
			local currentLevel = AITile.GetCornerHeight( t1 ,c );
			if(currentLevel != level && HogeAI.Get().IsAvoidRemovingWater() && HgTile.IsAroundRiverCorner(HgTile.GetCornerTile(t1,c))) {
				continue;
			}
			if(currentLevel > level) {
				if(level==0 && HgTile.IsAroundCoastCorner(HgTile.GetCornerTile(t1,c))) {
					continue;
				}
				if(!AITile.LowerTile(t1, HgTile.GetSlopeFromCorner(c))) {
					continue;
				}
			} else if(!lowerOnly && currentLevel < level) {
				if(!AITile.RaiseTile(t1, HgTile.GetSlopeFromCorner(c))) {
					continue;
				}
			}
		}
	}
	
	static function LevelWaterBound( t1, t2 ) {
		foreach(c in HgTile(t1).GetConnectionCorners(HgTile(t2))) {
			local currentLevel = AITile.GetCornerHeight( t1 ,c );
			if(currentLevel >= 2) {
				return false;
			}
			if(currentLevel == 1) {
				if(!AITile.LowerTile(t1, HgTile.GetSlopeFromCorner(c))) {
					return false;
				}
			}
		}
		return true;
	}

	function GetMaxHeight() {
		return AITile.GetMaxHeight(tile);
	}
	
	function GetMaxHeightCount() {
		local maxHeight = AITile.GetMaxHeight(tile);
		local result = 0;
		foreach(c in HgTile.Corners) {
			if(maxHeight == AITile.GetCornerHeight(tile,c)) {
				result ++;
			}
		}
		return result;
	}
	
	function _tostring() {
		return X() + "x" + Y();
	}
	
	function _add(hgTile) {
		return HgTile(tile + hgTile.tile);
//		return HgTile.XY(this.X() + hgTile.X(), this.Y() + hgTile.Y());
	}

	function _sub(hgTile) {
		return HgTile(tile - hgTile.tile);
//		return HgTile.XY(this.X() - hgTile.X(), this.Y() - hgTile.Y());
	}
	
	static function GetCenter(hgTiles) {
		local x=0;
		local y=0;
		foreach(hgTile in hgTiles) {
			x+=hgTile.X();
			y+=hgTile.Y();
		}
		return HgTile.XY(x/hgTiles.len(),y/hgTiles.len());
	}
	
	static function GetCorners(direction) {
		switch(direction) {
			case HgTile.DIR_NE:
				return [AITile.CORNER_N,AITile.CORNER_E];
			case HgTile.DIR_NW:
				return [AITile.CORNER_N,AITile.CORNER_W];
			case HgTile.DIR_SE:
				return [AITile.CORNER_S,AITile.CORNER_E];
			case HgTile.DIR_SW:
				return [AITile.CORNER_S,AITile.CORNER_W];
			case HgTile.DIR_INVALID:
				return [];
		}
	}
	
	static function GetOtherSideDir(direction) {
		switch(direction) {
			case HgTile.DIR_NE:
				return HgTile.DIR_SW;
			case HgTile.DIR_NW:
				return HgTile.DIR_SE;
			case HgTile.DIR_SE:
				return HgTile.DIR_NW;
			case HgTile.DIR_SW:
				return HgTile.DIR_NE;
			case HgTile.DIR_INVALID:
				return HgTile.DIR_INVALID;
		}
	}

	static function GetSlopeFromCorner(corner) {
		switch(corner) {
			case AITile.CORNER_N:
				return AITile.SLOPE_N;
			case AITile.CORNER_S:
				return AITile.SLOPE_S;
			case AITile.CORNER_E:
				return AITile.SLOPE_E;
			case AITile.CORNER_W:
				return AITile.SLOPE_W;
		}
	}
	
	
	static function GetCornerString(corner) {
		switch(corner) {
			case AITile.CORNER_N:
				return "N";
			case AITile.CORNER_S:
				return "S";
			case AITile.CORNER_E:
				return "E";
			case AITile.CORNER_W:
				return "W";
		}
	}

	
	static function GetConnectionTiles(tile, tracks) {
		local list = AIList();
		foreach(t in HgTile.TrackDirs) {
			if((t[0] & tracks) != 0) {
				list.AddItem(tile + HgTile.DIR4Index[t[1][0]],0);
				list.AddItem(tile + HgTile.DIR4Index[t[1][1]],0);
			}
		}
		return HgArray.AIListKey(list).array;
	}
	
	static function IsDiagonalTrack(tracks) {
		foreach(track in HgTile.DiagonalRailTracks) {
			if(track == tracks) {
				return true;
			}
		}
		return false;
	}
	
	static function ContainsDiagonalTrack(tracks) {
		foreach(track in HgTile.DiagonalRailTracks) {
			if((track & tracks) != 0) {
				return true;
			}
		}
		return false;
	}
	
	
	static function IsStraightTrack(tracks) {
		foreach(track in HgTile.StraightRailTracks) {
			if(track == tracks) {
				return true;
			}
		}
		return false;
	}
	
	static function IsAroundCoast(tile) {
		foreach(d in HgTile.DIR4Index) {
			if(AITile.IsCoastTile(tile+d) || AITile.IsSeaTile(tile+d)) {
				return true;
			}
		}
		return false;
	}
	
	static function IsAroundCoastCorner(tile) {
		foreach(d in HgTile.CornerAroundTileIndex) {
			if(AITile.IsCoastTile(tile+d) || AITile.IsSeaTile(tile+d)) {
				return true;
			}
		}
		return false;
	}
	static function IsAroundRiverCorner(tile) {
		foreach(d in HgTile.CornerAroundTileIndex) {
			if(AITile.IsRiverTile(tile+d)) {
				return true;
			}
		}
		return false;
	}
	
	static function IsLandConnectedForRail(p1, p2) {
		if(HogeAI.Get().CanRemoveWater()) {
			return true;
		}
		
		return HgTile.IsLandConnectedTwoWay(p1, p2, 13);
	}
	
	static function IsLandConnectedForRoad(p1, p2) {
		return HgTile.IsLandConnectedTwoWay(p1, p2, 50);
	}

	static function IsLandConnectedTwoWay(start, end, allowedSeaLength) {
		if( HgTile.IsLandConnected(start, end, allowedSeaLength) ) {
			return true;
		}
		if( min(abs(AIMap.GetTileX(start) - AIMap.GetTileX(end)), abs(AIMap.GetTileY(start) - AIMap.GetTileY(end))) >= 20 ) {
			return HgTile.IsLandConnected(end, start, allowedSeaLength);
		}
	}
	
	static function IsLandConnected(start, end, allowedSeaLength) {
	
		if(!AIMap.IsValidTile(start) || !AIMap.IsValidTile(end)) {
			return false;
		}
		local p1 = end; //pathfinderと向きを合わせる。start < end ? start : end;
		local p2 = start; //start < end ? end : start;
		local key = p1+"-"+p2;
		if(HgTile.landConnectedCache.rawin(key)) {
			local t = HgTile.landConnectedCache[key];
			local finished = t[0];
			local seaLength = t[1];
			if(finished) {
				return seaLength <= allowedSeaLength;
			}
			if(seaLength > allowedSeaLength) {
				return false;
			}
		}
		local t = HgTile.CheckLandConnected(p1, p2, allowedSeaLength);
		HgTile.landConnectedCache.rawset(key,t);
		return t[0];
	}

	static function CheckLandConnected(from, to, allowedSeaLength) {
	
		local curX = AIMap.GetTileX(from);
		local curY = AIMap.GetTileY(from);
		
		local toX = AIMap.GetTileX(to);
		local toY = AIMap.GetTileY(to);
		
		local maxSeaLength = 0;
		local seaLength = 0;
		while(true) {
			local cur = AIMap.GetTileIndex(curX, curY);
			if(cur == to) {
				break;
			}
			if(AITile.IsSeaTile(cur)) {
				seaLength ++;
				maxSeaLength = max(seaLength, maxSeaLength);
				if(seaLength > allowedSeaLength) {
					return [false,maxSeaLength];
				}
			} else {
				seaLength = 0;
			}
			if(abs(toX - curX) > abs(toY - curY)) {
				curX += toX > curX ? 1 : -1;
			} else {
				curY += toY > curY ? 1 : -1;
			}
		}
		return [true,maxSeaLength];
	}
	

	
	function CanForkRail(toHgTile) {
		local maxHeightCount = GetMaxHeightCount();
		if(maxHeightCount >= 3) {
			return true;
		} else if(maxHeightCount == 2) {
			local dir = GetDirection(toHgTile);
			local connectionSide = GetCorners(dir);
			local otherSide = GetCorners(GetOtherSideDir(dir));
			if(AITile.GetCornerHeight( tile, connectionSide[0]) == AITile.GetCornerHeight( tile, otherSide[1]) &&
			  AITile.GetCornerHeight( tile, connectionSide[1]) == AITile.GetCornerHeight( tile, otherSide[0])) {
				return false;
			}
			if(AITile.GetCornerHeight( tile, connectionSide[0]) == AITile.GetCornerHeight( tile, connectionSide[1]) &&
			  AITile.GetCornerHeight( tile, otherSide[1]) > AITile.GetCornerHeight( tile, connectionSide[0])) {
				return false;
			}
			return true;
		}
		return false;
	}
	
	function GetSlopeLevel(destTile) {
		
		local d = Distance(destTile);
		local dx = (destTile.X().tofloat()-X()) / d;
		local dy = (destTile.Y().tofloat()-Y()) / d;
		local x = X().tofloat();
		local y = Y().tofloat();
		local minHeight = null;
		local maxLevel = 0;
		for(local i=0; i<d; i++) {
			local cur = destTile.XY(x.tointeger(),y.tointeger());
			local height = AITile.GetMaxHeight(cur.tile);
			if(minHeight == null || minHeight > height) {
				minHeight = height;
			}
			if(maxLevel < height - minHeight) {
				maxLevel = height - minHeight;
			}
			x += dx;
			y += dy;
		}
		return maxLevel;
	}
	
	function BuildDoubleDepot(p1,p2,from,to) {
		if(AITile.IsBuildable(p1) && AITile.IsBuildable(p2) && !RailPathFinder._IsSlopedRail(from,tile,to)) {
			local level = AITile.GetMaxHeight(tile);
			if(level == 0) { // 水没する事があるので
				return null;
			}
			TileListUtils.LevelHeightTiles([p1,p2,tile],level);
			AIRail.RemoveSignal(tile, from);
			AIRail.RemoveSignal(tile, to);
			if(BuildDepot(p1,from,to)) {
				if(!BuildDepot(p2,from,to)) {
					AITile.DemolishTile (p1);
					RailBuilder.RemoveRailUntilFree(from, tile, p1);
					RailBuilder.RemoveRailUntilFree(to, tile, p1);
				} else {
					RailBuilder.RemoveRailUntilFree(from, tile, to);
					return [p1,p2];
				}
			}
		}
		return null;
	}
	
	function BuildDepot(depotTile,from,to) {
		local aiTest = AITestMode();
		if(AIRail.BuildRailDepot (depotTile, tile)) {
			local aiExec = AIExecMode();
			HogeAI.WaitForMoney(5000);
			if(!AIRail.AreTilesConnected(from, tile, depotTile) && !RailBuilder.BuildRailUntilFree(from, tile, depotTile)) {
//				HgLog.Info("AreTilesConnected1:"+HgTile(from)+","+HgTile(tile)+","+HgTile(depotTile)+" "+AIError.GetLastErrorString());
				return false;
			}
			if(!AIRail.AreTilesConnected(to, tile, depotTile) && !RailBuilder.BuildRailUntilFree(to, tile, depotTile)) {
				//TODO: Remove Rail
				RailBuilder.RemoveRailUntilFree(from, tile, depotTile);
//				HgLog.Info("AreTilesConnected1:"+HgTile(to)+","+HgTile(tile)+","+HgTile(depotTile)+" "+AIError.GetLastErrorString());
				return false;
			}
			if(!AIRail.BuildRailDepot (depotTile, tile)) {
				RailBuilder.RemoveRailUntilFree(from, tile, depotTile);
				RailBuilder.RemoveRailUntilFree(to, tile, depotTile);
				//TODO: Remove Rail
//				HgLog.Info("BuildRailDepot:"+HgTile(depotTile)+","+HgTile(tile)+" "+AIError.GetLastErrorString());
				return false;
			}
			return true;
		} else {
//			HgLog.Info("test BuildRailDepot:"+HgTile(depotTile)+","+HgTile(tile)+" "+AIError.GetLastErrorString());
		}
		return false;
	}
	
	function RemoveDepot() {
		local depotTile = this.tile;
		local frontTile = AIRail.GetRailDepotFrontTile(depotTile);
		foreach(d in HgTile.DIR4Index) {
			local from = frontTile + d;
			if(AIRail.AreTilesConnected(from, frontTile, depotTile)) {
				RailBuilder.RemoveRailUntilFree(from, frontTile, depotTile);
			}
		}
		AITile.DemolishTile(depotTile);
	}
	
	function BuildCommonDepot(depotTile,front,vehicleType) {
		switch(vehicleType) {
		case AIVehicle.VT_ROAD:
			return BuildRoadDepot(depotTile, front);
		case AIVehicle.VT_WATER:
			return BuildWaterDepot(depotTile, front);
		default:
			HgLog.Error("BuildCommonDepot failed.vehicleType="+vehicleType);
			return false;
		}
	}
	
	function BuildRoadDepot(depotTile,front) {
		local aiTest = AITestMode();
		if(AIRoad.IsRoadDepotTile(depotTile) 
				&& AIRoad.HasRoadType(depotTile, AIRoad.GetCurrentRoadType())
				&& AICompany.IsMine(AITile.GetOwner(depotTile))
				&& AIRoad.AreRoadTilesConnected(front, depotTile)) {
			return true; // 再利用
		}
		if(AIRoad.BuildRoadDepot (depotTile, front)) {
			local aiExec = AIExecMode();
			HogeAI.WaitForMoney(10000);
			/*
			if( AIRoad.GetRoadTramType( AIRoad.GetCurrentRoadType() ) ==  AIRoad.ROADTRAMTYPES_ROAD ) {
				if(!AIRoad.AreRoadTilesConnected(depotTile, front) && !AIRoad.BuildRoad(depotTile, front)) {
					return false;
				}
			}*/
			if(!AIRoad.AreRoadTilesConnected(depotTile, front) && !AIRoad.BuildRoad(front, depotTile)) {
				return false;
			}
			if( AIRoad.GetRoadTramType( AIRoad.GetCurrentRoadType() ) ==  AIRoad.ROADTRAMTYPES_TRAM ) {
				AITile.DemolishTile(depotTile);
			}
			if(!AIRoad.BuildRoadDepot (depotTile, front)) {
				return false;
			}
			return true;
		}
		return false;
	}
	
	function BuildWaterDepot(depotTile,front,force=false) {
		local aiExec = AIExecMode();
		
		if(AIMarine.IsWaterDepotTile(depotTile) 
				&& AICompany.IsMine(AITile.GetOwner(depotTile))
				/*&& AIMarine.AreWaterTilesConnected(front, depotTile) 向きが違ってても再利用できるはず*/) {
			return true; // 再利用
		}
		local isCanal = AIMarine.IsCanalTile(front);
		local back = front - (front - depotTile) * 3;
		if(!isCanal && !WaterPathFinder.IsSea(back)) {
			return false;
		}
		local d2;
		if(depotTile < front) {
			d2 = depotTile;
			depotTile -= (front - depotTile);
		} else {
			d2 = depotTile + (depotTile - front);
		}
		if(!force && WaterRoute.usedTiles.rawin(depotTile)) {
			return false;
		}
		if(!force && WaterRoute.usedTiles.rawin(d2)) {
			return false;
		}
		HogeAI.WaitForMoney(10000);
		
		if(!AIMarine.BuildWaterDepot(depotTile, front)) {
			if(isCanal) {
				{
					local aiTest = AITestMode();
					if(!AITile.IsWaterTile(depotTile) && !AIMarine.BuildCanal(depotTile)) {
						return false;
					} else if(!AITile.IsWaterTile(d2) && !AIMarine.BuildCanal(d2)) {
						return false;
					}
				}
				if(!AITile.IsWaterTile(depotTile) && !AIMarine.BuildCanal(depotTile)) {
					return false;
				} else if(!AITile.IsWaterTile(d2) && !AIMarine.BuildCanal(d2)) {
					return false;
				}
				if(!AIMarine.BuildWaterDepot(depotTile, front)) {
					return false;
				}
			} else {
				return false;
			}
		}
		AIMarine.BuildBuoy(back);
		AIMarine.BuildBuoy(front);
		return true;
	}
	
	function BuildSign(text) {
		local execMode = AIExecMode();
		return AISign.BuildSign(tile,text);
	}

}

class Rectangle {
	lefttop = null;
	rightbottom = null; // このクラスはこのタイルは含まない長方形を意味する
	
	static function Center(centerHgTile, radius) {
		local x = centerHgTile.X();
		local y = centerHgTile.Y();
		local left = max(1,x - radius);
		local top_ = max(1,y - radius);
		local right = min(AIMap.GetMapSizeX(),x + radius + 1);
		local bottom = min(AIMap.GetMapSizeY(),y + radius + 1);
		return Rectangle(HgTile.XY(left,top_), HgTile.XY(right,bottom));
	}
	
		
	static function Corner(p1, p2) {
		return Rectangle.CornerXY(p1.X(), p1.Y(), p2.X(), p2.Y());
	}
	
	static function CornerXY(x1,y1,x2,y2) {
		return Rectangle(HgTile.XY(min(x1,x2),min(y1,y2)), HgTile.XY(max(x1,x2),max(y1,y2)));
	}
	
	
	static function CornerTiles(t1, t2) {
		local minX = IntegerUtils.IntMax, minY = IntegerUtils.IntMax, maxX=0, maxY=0;
		foreach(p in ArrayUtils.Extend(t1.GetCornerTiles(), t2.GetCornerTiles())) {
			minX = min(minX,p.X());
			maxX = max(maxX,p.X());
			minY = min(minY,p.Y());
			maxY = max(maxY,p.Y());
		}
		return Rectangle(HgTile.XY(minX,minY), HgTile.XY(maxX,maxY));
	}
	
	constructor(lefttop,rightbottom) {
		this.lefttop = lefttop;
		this.rightbottom = rightbottom;
	}
	
	
	function Include(rectangle) {
		return Rectangle(this.lefttop.Min(rectangle.lefttop), this.rightbottom.Max(rectangle.rightbottom));
	}
	
	function Width() {
		return rightbottom.X() - lefttop.X();
	}
	
	function Height() {
		return rightbottom.Y() - lefttop.Y();
	}
	
	function Left() {
		return lefttop.X();
	}
	
	function Right() {
		return rightbottom.X();
	}
	
	function Top() {
		return lefttop.Y();
	}
	
	function Bottom() {
		return rightbottom.Y();
	}
	
	function GetLeftBottom() {
		return HgTile.XY(Left(),Bottom());
	}

	function GetRightTop() {
		return HgTile.XY(Right(),Top());
	}
	
	function GetCorners() {
		return [lefttop,GetRightTop(),rightbottom,GetLeftBottom()];
	}
	
	function GetCenter() {
		return HgTile.XY((Left()+Right())/2,(Top()+Bottom())/2);
	}
	
	
	function IsInclude(rectangle) {
		if(Left() < rectangle.Left()) {
			return false;
		}
		if(Top() < rectangle.Top()) {
			return false;
		}
		if(Right() > rectangle.Right()) {
			return false;
		}
		if(Bottom() > rectangle.Bottom()) {
			return false;
		}
		return true;
	}
	
	function GetIncludeRectanglesLefttopTileList(w,h) {
		local result = AITileList();
		result.AddRectangle(lefttop.tile, HgTile.InMapXY(Right()-w, Bottom()-h).tile);
		return result;
	}
	
	function GetRightBottomTile() {
		return HgTile.XY( rightbottom.X()-1, rightbottom.Y()-1 );
	}
	
	function AppendToTileList(tileList) {
		tileList.AddRectangle(lefttop.tile, GetRightBottomTile().tile);
	}
	
	function GetTileList() {
		local result = AITileList();
		result.AddRectangle(lefttop.tile, (rightbottom-HgTile.XY(1,1)).tile);
		return result;
	}
	
	function GetEdgeTileList() {
		local result = AITileList();
		local one = HgTile.XY(1,1);
		local rb = rightbottom-one;
		result.AddRectangle(lefttop.tile, rb.tile);
		if(Width()>=3 && Height()>=3) {
			result.RemoveRectangle((lefttop+one).tile, (rb-one).tile);
		}
		return result;
	}
	
	function GetTiles() {
		local result = [];
		for(local y=Top(); y<Bottom(); y++) {
			for(local x=Left(); x<Right(); x++) {
				local tile = AIMap.GetTileIndex (x,y)
				if(AIMap.IsValidTile(tile)) {
					result.push(tile);
				}
			}
		}
		return result;
	}
	
	function GetAroundTileList() {
		local result = AITileList();
		local one = HgTile.XY(1,1);
		result.AddRectangle((lefttop-one).tile, rightbottom.tile);
		result.RemoveRectangle(lefttop.tile, (rightbottom-one).tile);
		return result;
	}
	
	function GetAroundTiles() {
		local result = [];
		for(local y=Top()-1; y<Bottom()+1; y++) {
			result.push(AIMap.GetTileIndex(Left()-1,y));
			result.push(AIMap.GetTileIndex(Right(),y));
		}
		for(local x=Left(); x<Right(); x++) {
			result.push(AIMap.GetTileIndex(x,Top()-1));
			result.push(AIMap.GetTileIndex(x,Bottom()));
		}
		return result;
	}
	
	
	function GetTilesOrderByInside() {

		local tileList = AITileList();
		tileList.AddRectangle(lefttop.tile, rightbottom.tile);
		tileList.Valuate(AIMap.DistanceManhattan, GetCenter().tile);
		tileList.Sort( AIList.SORT_BY_VALUE,true);
		return tileList;
	}
	
	function GetTilesOrderByOutside() {

		local tileList = AITileList();
		tileList.AddRectangle(lefttop.tile, rightbottom.tile);
		tileList.Valuate(AIMap.DistanceManhattan, GetCenter().tile);
		tileList.Sort( AIList.SORT_BY_VALUE,false);
		return tileList;
	}
	
/*	
	
		local result = [];
		local w = Width();
		local h = Height();
		local d = 1;
		local y = lefttop.Y();
		local x = lefttop.X();
		local end;
		while(w>0 && h>0) {
			end = x + w * d;
			for(; x!=end; x+=d) {
				local t = HgTile.XY(x,y).tile;
				result.push(t);
			}
			x -= d;
			end = y + h * d;
			y += d;
			for(; y!=end; y+=d) {
				local t = HgTile.XY(x,y).tile;
				result.push(t);
			}
			y -= d;
			d *= -1;
			x += d;
			w--;
			h--;
		}
		return result;
	}*/
	
	
	function GetTileListIncludeEdge() {
		local result = AIList();
		for(local y=Top(); y<=Bottom(); y++) {
			for(local x=Left(); x<=Right(); x++) {
				local v = AIMap.GetTileIndex (x,y)
				result.AddItem(v,v);
			}
		}
		return result;
	}
	
	
	function IsBuildable() {
		return HogeAI.IsBuildableRectangle(lefttop.tile, Width(), Height());
	}
	
	function LevelTiles(track, isTestMode = false) {
		return TileListUtils.LevelAverage(GetTileListIncludeEdge(), track, isTestMode);
	}
	
	function GetRandomTile() {
		return HgTile.XY(Left() + AIBase.RandRange(Width()), Top() + AIBase.RandRange(Height()));	
	}
	
	function Shrink(d) {
		return Rectangle(lefttop + HgTile.XY(d,d), rightbottom - HgTile.XY(d,d));
	}
	
	function _tostring() {
		return lefttop + "-" + rightbottom;
	}
	
	static function Test() {
		local r1 = Rectangle(HgTile.XY(1,2),HgTile.XY(3,6));
		local r2 = Rectangle(HgTile.XY(6,1),HgTile.XY(8,5));
		local r3 = r1.Include(r2);
		if(r3.lefttop.X() != 1) {
			HgLog.Warning("Rectangle Test1 NG");
		}
		if(r3.lefttop.Y() != 1) {
			HgLog.Warning("Rectangle Test2 NG");
		}
		if(r3.rightbottom.X() != 8) {
			HgLog.Warning("Rectangle Test3 NG");
		}
		if(r3.rightbottom.Y() != 6) {
			HgLog.Warning("Rectangle Test4 NG");
		}
		
		HgLog.Info("Rectangle Test finished");
	}
}

class TileListUtils {

	static function Generator(gen) {
		local e;
		local result = AITileList();
		while((e=resume gen)!=null) {
			result.AddTile(e);
		}
		return result;
	}
	
	static function GetLevelTileList(tiles) {
		local tileList = AIList();
		local d1 = HgTile.XY(1,0).tile;
		local d2 = HgTile.XY(0,1).tile;
		local d3 = HgTile.XY(1,1).tile;
		foreach(tile in tiles) {
			tileList.AddItem(tile,0);
			tileList.AddItem(tile + d1,0);
			tileList.AddItem(tile + d2,0);
			tileList.AddItem(tile + d3,0);
		}
		return tileList;
	}
	
	static function LevelAverageTiles(tiles, track, isTestMode = false) {
		return LevelAverage(TileListUtils.GetLevelTileList(tiles), track, isTestMode);
	}

	static function CalculateAverageLevel(tileList) {
		local sum = 0;
		tileList.Valuate(AITile.GetCornerHeight, AITile.CORNER_N);
		foreach(tile,level in tileList) {
			sum += level;
		}
		return max(1, (sum.tofloat() / tileList.Count() + 0.5).tointeger());
	}

	static function LevelAverage(tileList, track, isTestMode = false, average = null, force = false) {
		local landfill = AICompany.GetBankBalance(AICompany.COMPANY_SELF) > HogeAI.Get().GetInflatedMoney(2000000);
		if(average == null) {
			average = TileListUtils.CalculateAverageLevel(tileList);
		}

		foreach(tile,level in tileList) { // 山岳マップは失敗する事が多いので、先にはじくことでパフォーマンス改善
			if(abs(average - level) >= 2) {
				return false;
			}
		}			
		
		local raiseTileMap = track != null ? TileListUtils.CalculateRaiseTileMap(HgArray.AIListKey(tileList).GetArray(), track) : null;
		
		local around = [AIMap.GetTileIndex(-1,-1),AIMap.GetTileIndex(-1,0),AIMap.GetTileIndex(0,-1),0];
		foreach(tile,level in tileList) {
			if(!isTestMode) {
				level = AITile.GetCornerHeight(tile, AITile.CORNER_N); // 他プレイヤに変更されている事があるので再取得
			}
			if(level < average) {
				if(raiseTileMap == null || raiseTileMap.rawin(tile)) {
					foreach(d in around) {
						local t = tile + d;
						if(AITile.IsSeaTile(t) /*level <= 0 たんなる穴の場合がある */) {
							if(!landfill) {
								return false;
							}
							if(WaterRoute.usedTiles.rawin(t)) {
								return false;
							}
						}
					}
					if(!TileListUtils.RaiseTile(tile, AITile.SLOPE_N) && !force) {
						if(!isTestMode) {
							HgLog.Warning("RaiseTile failed tile:"+HgTile(tile)+ " "+ AIError.GetLastErrorString());
						}
						return false;
					}
				}
			} else if(level > average) {
				if(average==0 && HgTile.IsAroundCoastCorner(tile)) {
					return false;
				}
				if(isTestMode) {
					if(!TileListUtils.LowerTile(tile, TileListUtils.GetTerraformSlope(tile,tileList,average))) {
						return false;
					}
				} else {
					if(!TileListUtils.LowerTile(tile, AITile.SLOPE_N) && !force) {
						if(!isTestMode) {
							HgLog.Warning("LowerTile failed tile:"+HgTile(tile)+ " "+ AIError.GetLastErrorString());
						}
						return false;
					}
				}
			}	
			if(AIMap.DistanceFromEdge (tile) <= 2) {
				return false;
			}
		}
		/*
		if(isTestMode) {
			local needsChecks = {};
			foreach(tile in lowerTiles) {
				foreach(d in around) {
					if( needsChecks.rawin(tile+d) ) {
						needsChecks[tile+d].push(tile);
					} else {
						needsChecks[tile+d] <- [tile];
					}
				}
			}
			foreach(tile,lowerTiles in needsChecks) {
				if(lowerTiles.len() >= 3) {
					if(AIRoad.IsRoadTile(tile) || AIRail.IsRailTile(tile)) {
						return false;
					}
				} else if(lowerTiles.len() == 2) {
					if(AIRoad.IsRoadTile(tile)) {
						return false;
						
						local ngTile;
						if(lowerTiles[0] == tile) {
							ngTile = lowerTiles[1];
						} else if(lowerTiles[1] == tile) {
							ngTile = lowerTiles[0];
						} else {
							ngTile = AIMap.DistanceManhattan(lowerTiles[0], tile) == 1 ? lowerTiles[0] : lowerTiles[1];
						}
						if(AIRoad.AreRoadTilesConnected(tile, ngTile)) { // これでは調べられない。現時点で調べる方法は無い
							return false;
						}
					}
					if(AIRail.IsRailTile(tile)) {
						local ngTile;
						if(lowerTiles[0] == tile) {
							ngTile = lowerTiles[1];
						} else if(lowerTiles[1] == tile) {
							ngTile = lowerTiles[0];
						} else {
							ngTile = AIMap.DistanceManhattan(lowerTiles[0], tile) == 1 ? lowerTiles[0] : lowerTiles[1];
						}
						foreach(d in HgTile.DIR4Index) {
							if(AIRail.AreTilesConnected(tile, ngTile, ngTile + d)) {
								return false;
							}
						}
					}
				}
			}
		}*/
		
		return true;
	}
	
	static function GetTerraformSlope(tile, tileList, average) {
		local result = AITile.SLOPE_N;
		
		foreach(t in [[1,0,AITile.SLOPE_W],[0,1,AITile.SLOPE_E],[1,1,AITile.SLOPE_S]]) {
			local check = tile + AIMap.GetTileIndex(t[0],t[1]);
			if(tileList.HasItem(check)) {
				local level = tileList.GetValue(check);
				if(average != level) {
					result = result | t[2];
				}
			}
		}
		return result;
	}
	
	static function LevelHeightTiles(tiles, height) {
		return TileListUtils.LevelHeight(TileListUtils.GetLevelTileList(tiles), height);
	}

	static function LevelHeight(tileList, height) {
		tileList.Valuate(AITile.GetCornerHeight, AITile.CORNER_N);
		
		foreach(tile,level in tileList) {
			for(local i=level; i<min(height,level+2); i++) {
				
				if(!TileListUtils.RaiseTile (tile, AITile.SLOPE_N)) {
					break;
				}
			}
			for(local i=level; i>max(height,level-2); i--) {
				if(!TileListUtils.LowerTile (tile, AITile.SLOPE_N)) {
					break;
				}
			}
		}
		return true;
	}
	
	static function CalculateRaiseTileMap(tiles, track) {
		local result = {};
		foreach(tile in tiles) {
			if(TileListUtils.GetBothCount(tile,tiles,track) == 1 && TileListUtils.GetSequenceCount(tile,tiles,track) >= 2) {
			} else {
				result.rawset(tile,0);
			}
		}
		return result;
	}
	
	static function GetBothCount(tile, tiles, track) {
		local x = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileX(tile) : AIMap.GetTileY(tile);
		local y = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileY(tile) : AIMap.GetTileX(tile);
		local result = 0;
		foreach(t in tiles) {
			local x1 = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileX(t) : AIMap.GetTileY(t);
			local y1 = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileY(t) : AIMap.GetTileX(t);
			if(y == y1 && (x == x1 + 1 || x == x1 - 1)) {
				result ++;
			}
		}
		return result;
	}

	static function GetSequenceCount(tile, tiles, track) {
		local x = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileX(tile) : AIMap.GetTileY(tile);
		local y = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileY(tile) : AIMap.GetTileX(tile);
		local result = 0;
		foreach(d in [-1,1]) {
			local count = 0;
			local match = true;
			while(match) {
				match = false;
				foreach(t in tiles) {
					local x1 = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileX(t) : AIMap.GetTileY(t);
					local y1 = track == AIRail.RAILTRACK_NW_SE ? AIMap.GetTileY(t) : AIMap.GetTileX(t);
					if(y == y1 && x1 == x + (count+1) * d) {
						match = true;
						count ++;
						break;
					}
				}
			}
			if(count >= 1) {
				return count;
			}
		}
		return 0;
	}
	
	
	static function RaiseTile(tile, slope, testMode = false) {
		if(testMode) {
			return AITile.RaiseTile(tile, slope);
		}
		while(true) {
			local result = BuildUtils.WaitForMoney( function():(tile, slope) {
				return AITile.RaiseTile(tile, slope);
			});
			if(!result && AIError.GetLastError() == AITile.ERR_LIMIT_REACHED) {
				HgLog.Warning("RaiseTile retry. ERR_LIMIT_REACHED");
				AIController.Sleep(100);
			} else {
				return result;
			}
		}
		
	}

	static function LowerTile(tile, slope) {
		while(true) {
			local result = BuildUtils.WaitForMoney( function():(tile, slope) {
				return AITile.LowerTile( tile, slope);
			});
			if(!result && AIError.GetLastError() == AITile.ERR_LIMIT_REACHED) {
				HgLog.Warning("LowerTile retry. ERR_LIMIT_REACHED");
				AIController.Sleep(100);
			} else {
				return result;
			}
		}
	}
	
	static function Differ(tiles1, tiles2) {
		local result = [];
		local m2 = HgTable.FromArray(tiles2);
		foreach(tile in tiles1) {
			if(!m2.rawin(tile)) {
				result.push(tile);
			}
		}
		return result;
	}
	
}
