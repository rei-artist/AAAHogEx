
class HgTile {
	static DIR_NE = 0;
	static DIR_NW = 1;
	static DIR_SE = 2;
	static DIR_SW = 3;
	static DIR_INVALID = 4;
	
			
	static DIR4Index =[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(0, -1),
	                 AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 0)];
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
	
	tile = null;
	
	constructor(tile) {
		this.tile = tile;
	}
	
	static function XY(x,y) {
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
	
	
	function GetMaxHeight() {
		return AITile.GetMaxHeight(tile);
	}
	
	function GetMaxHeightCount() {
		local corners = [AITile.CORNER_W,AITile.CORNER_S,AITile.CORNER_E,AITile.CORNER_N];
		local heights = array(corners.len());
		foreach(i,c in corners) {
			heights[i] = AITile.GetCornerHeight(tile,c);
		}
		local maxHeight = GetMaxHeight();
		local maxHeightCount = 0;
		foreach(h in heights) {
			if(h == maxHeight) {
				maxHeightCount ++;
			}
		}		
		return maxHeightCount;
	}
	
	function GetPathFindCost(hgTile, notAllowLandFill = false) {
		local dx = abs(hgTile.X()-X());
		local dy = abs(hgTile.Y()-Y());
		local notBuildables = GetNotBuildables(hgTile,notAllowLandFill ? true : AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 2000000);
		local result = ((min(dx,dy)*3  + dx + dy) + notBuildables*2) / 6;
//		result = (result * result / 100) * 9 / 10 + 10;
		result = result == 0 ? 1 : result;
		
//		HgLog.Info("GetPathFindCost:"+this+" to "+hgTile+"="+result+"(("+(min(dx,dy) + dx + dy)/6+"+"+(notBuildables/6)+") D:"+(dx+dy));
		
		return result;
	}


	function GetNotBuildables(hgTile,isCheckSea) {
		if(HogeAI.Get().avoidClearWater) {
			isCheckSea = true;
		}
	
		local d = Distance(hgTile);
		local dx = (hgTile.X().tofloat()-X()) / d;
		local dy = (hgTile.Y().tofloat()-Y()) / d;
		local x = X().tofloat();
		local y = Y().tofloat();
		local continuity = 0;
		local result = 0;
		for(local i=0; i<d; i++) {
			local cur = HgTile.XY(x.tointeger(),y.tointeger());
			if(AITile.IsSeaTile(cur.tile)) {
				if(isCheckSea) {
					continuity = min(20,continuity+1);
					if(continuity >= 9) {
						result += continuity * 3;
					}
				}
			} else if(!AITile.IsBuildable(cur.tile)) {
				continuity = min(3,continuity+1);
				result += continuity;
			} else {
				continuity = 0;
			}
			x += dx;
			y += dy;
		}
		return result;
	}

	
	/*
	function GetNotBuildables(hgTile,isCheckSea) {
		local d = Distance(hgTile);
		local dx = (hgTile.X().tofloat()-X()) / d;
		local dy = (hgTile.Y().tofloat()-Y()) / d;
		local x = X().tofloat();
		local y = Y().tofloat();
		local continuity = 0;
		local result = 0;
		for(local i=0; i<d; i+=8) {
			local cur = HgTile.XY(x.tointeger(),y.tointeger());
			local rect = Rectangle.Center(cur,8);
			for(local i=0; i<16; i++) {
				local tile = rect.GetRandomTile().tile;
				if(AITile.IsSeaTile(tile)) {
					result += isCheckSea ? 2 : 0;
				} else if(!AITile.IsBuildable(tile)) {
					result ++;
				}
			}
			x += dx * 8;
			y += dy * 8;
		}
		return result;
	}
	*/

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
	
	
	
	function BuildDoubleDepot(p1,p2,from,to) {
		if(AITile.IsBuildable(p1) && AITile.IsBuildable(p2)) {
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
			HogeAI.WaitForMoney(10000);
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
	
	
	function BuildRoadDepot(depotTile,front) {
		local aiTest = AITestMode();
		if(AIRoad.BuildRoadDepot (depotTile, front)) {
			local aiExec = AIExecMode();
			HogeAI.WaitForMoney(10000);
			if(!AIRoad.AreRoadTilesConnected(depotTile, front) && !AIRoad.BuildRoad(depotTile, front)) {
				return false;
			}
			if(!AIRoad.BuildRoadDepot (depotTile, front)) {
				return false;
			}
			return true;
		}
		return false;
	}

	function _tostring() {
		return X() + "x" + Y();
	}
	
	function _add(hgTile) {
		return HgTile.XY(this.X() + hgTile.X(), this.Y() + hgTile.Y());
	}

	function _sub(hgTile) {
		return HgTile.XY(this.X() - hgTile.X(), this.Y() - hgTile.Y());
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
	
}

class Rectangle {
	lefttop = null;
	rightbottom = null;
	
	static function Center(centerHgTile, radius) {
		return Rectangle(centerHgTile - HgTile.XY(radius,radius), centerHgTile + HgTile.XY(radius,radius));
	}
	
		
	static function Corner(p1, p2) {
		return Rectangle.CornerXY(p1.X(), p1.Y(), p2.X(), p2.Y());
	}
	
	static function CornerXY(x1,y1,x2,y2) {
		return Rectangle(HgTile.XY(min(x1,x2),min(y1,y2)), HgTile.XY(max(x1,x2),max(y1,y2)));
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
	
	function GetCenter() {
		return HgTile.XY((Left()+Right())/2,(Top()+Bottom())/2);
	}
	
	function GetIncludeRectangles(w,h) {
		local result = [];
		for(local y=Top(); y<=Bottom()-h; y++) {
			for(local x=Left(); x<=Right()-w; x++) {
				result.push(Rectangle(HgTile.XY(x,y),HgTile.XY(x+w,y+h)));
			}
		}
		return result;
	}
	
	function GetTileList() {
		local result = AIList();
		for(local y=Top(); y<Bottom(); y++) {
			for(local x=Left(); x<Right(); x++) {
				local v = AIMap.GetTileIndex (x,y)
				result.AddItem(v,v);
			}
		}
		return result;
	}
	
	function GetTilesOrderByOutside() {
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
	}
	
	
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
	
	function LevelTiles() {
		return TileListUtil.LevelAverage(GetTileListIncludeEdge());
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

class TileListUtil {
	static function LevelAverage(tileList) {
		// TODO 道路の向きによってはtestで成功したものがexecで失敗する
		local landfill = AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 2000000;
		tileList.Valuate(AITile.GetCornerHeight, AITile.CORNER_N);
		local sum = 0;
		foreach(tile,level in tileList) {
			sum += level;
		}
		local average = (sum.tofloat() / tileList.Count() + 0.5).tointeger();
		if(landfill && average==0) {
			average = 1;
		}
		
		foreach(tile,level in tileList) {
			if(!landfill && level <= 0) {
				return false;
			}
			if(abs(average - level) >= 2) { //TODO: TestModeで動かないからはじいている
//				HgLog.Warning("failed LevelTiles average:"+average+" level:"+level);
				return false;
			}
			if(level < average) {
				if(!TileListUtil.RaiseTile (tile, AITile.SLOPE_N)) {
//					HgLog.Warning("failed LevelTiles RaiseTile tile:"+HgTile(tile));
					return false;
				}
			} else if(level > average) {
				if(!TileListUtil.LowerTile (tile, AITile.SLOPE_N)) {
//					HgLog.Warning("failed LevelTiles LowerTile tile:"+HgTile(tile));
					return false;
				}
			}	
			if(AIMap.DistanceFromEdge (tile) <= 2) {
				return false;
			}
		}
		return true;
	}
	
	
	static function LevelHeight(tileList, height) {
		tileList.Valuate(AITile.GetCornerHeight, AITile.CORNER_N);
		
		foreach(tile,level in tileList) {
			for(local i=level; i<min(height,level+2); i++) {
				if(!TileListUtil.RaiseTile (tile, AITile.SLOPE_N)) {
					break;
				}
			}
			for(local i=level; i>max(height,level-2); i--) {
				if(!TileListUtil.LowerTile (tile, AITile.SLOPE_N)) {
					break;
				}
			}
		}
		return true;
	}
	
	static function RaiseTile(tile, slope) {
		return BuildUtils.WaitForMoney( function():(tile, slope) {
			return AITile.RaiseTile (tile, slope);
		});
	}

	static function LowerTile(tile, slope) {
		return BuildUtils.WaitForMoney( function():(tile, slope) {
			return AITile.LowerTile (tile, slope);
		});
	}
	
}
