/* $Id: main.nut 15101 2009-01-16 00:05:26Z truebrain $ */

/**
 * A Rail Pathfinder.
 */
class Rail
{
	static idCounter = IdCounter();
	
	_aystar_class = import("graph.aystar", "", 4);
	_max_cost = null;              ///< The maximum cost for a route.
	_cost_tile = null;             ///< The cost for a single tile.
	_cost_guide = null;
	_cost_diagonal_tile = null;    ///< The cost for a diagonal tile.
	_cost_diagonal_sea = null;
	_cost_turn = null;             ///< The cost that is added to _cost_tile if the direction changes.
	_cost_tight_turn = null;
	_cost_slope = null;            ///< The extra cost if a rail tile is sloped.
	_cost_bridge_per_tile = null;  ///< The cost per tile of a new bridge, this is added to _cost_tile.
	_cost_tunnel_per_tile = null;  ///< The cost per tile of a new tunnel, this is added to _cost_tile.
	_cost_tunnel_per_tile_ex = null;
	_cost_bridge_per_tile_ex = null;
	_cost_under_bridge = null;
	_cost_coast = null;            ///< The extra cost for a coast tile.
	_cost_crossing_rail = null;
	_pathfinder = null;            ///< A reference to the used AyStar object.
	_max_bridge_length = null;     ///< The maximum length of a bridge that will be build.
	_max_tunnel_length = null;     ///< The maximum length of a tunnel that will be build.
	_can_build_water = null;
	_cost_water = null;
	_estimate_rate = null;

	cost = null;                   ///< Used to change the costs.
	_running = null;
	_goals = null;
	_count = null;
	_guideTileList = null;
	_reverseTileList = null;
	useInitializePath2 = false;

	constructor()
	{
		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_guide = -50;
		this._cost_diagonal_tile = 70;
		this._cost_diagonal_sea = 150;
		this._cost_turn = 50;
		this._cost_tight_turn = 200;
		this._cost_slope = 100;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._cost_under_bridge = 100;
		this._cost_coast = 20;
		this._cost_crossing_rail = 50;
		this._max_bridge_length = 6;
		this._max_tunnel_length = 6;
		this._can_build_water = false;
		this._cost_water = 20;
		this._estimate_rate = 2;
		this._pathfinder = this._aystar_class(this._Cost, this._Estimate, this._Neighbours, this._CheckDirection, this, this, this, this);

		this.cost = this.Cost(this);
		this._running = false;
		this._count = idCounter.Get() * 1000;
		this._guideTileList = AIList();
		this._reverseTileList = AIList();
		this.useInitializePath2 = false;
	}

	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source tiles.
	 * @param goals The target tiles.
	 * @param ignored_tiles An array of tiles that cannot occur in the final path.
	 * @see AyStar::InitializePath()
	 */
	function InitializePath(sources, goals, ignored_tiles = [], reversePath = null) {
		if(sources[0].len() == 3) {
			InitializePath2(sources, goals, ignored_tiles, reversePath);
			return;
		}
	
		local nsources = [];

		foreach (node in sources) {
			local path = this._pathfinder.Path(null, node[1], 0xFF, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, this._Cost, this);
			nsources.push(path);
		}
		this._goals = goals;
		SetReversePath(reversePath);
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
	}
	
	
	function InitializePath2(sources, goals, ignored_tiles = [], reversePath=null) {
		local nsources = [];

		foreach (node in sources) {
			local path = this._pathfinder.Path(null, node[2], 0xFF, this._Cost, this);
			path = this._pathfinder.Path(path, node[1], 0xFF, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, this._Cost, this);
			nsources.push(path);
		}
		this._goals = goals;
		SetReversePath(reversePath);
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
		useInitializePath2 = true;
	}
	
	function SetReversePath(reversePath) {
		if(reversePath!=null) {
			cost.bridge_per_tile = 100;
			cost.tunnel_per_tile = 100;
			
//			_estimate_rate = 1;
		}
		local path = reversePath;
		while(path != null) {
			local tile = path.GetTile();
			_reverseTileList.AddItem(tile,0);
			foreach(d in HgTile.DIR4Index) {
				_guideTileList.AddItem(tile + d,0);
			}
			path = path.GetParent();
		}
	}

	/**
	 * Try to find the path as indicated with InitializePath with the lowest cost.
	 * @param iterations After how many iterations it should abort for a moment.
	 *  This value should either be -1 for infinite, or > 0. Any other value
	 *  aborts immediatly and will never find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *  reached, or null if no path was found.
	 *  You can call this function over and over as long as it returns false,
	 *  which is an indication it is not yet done looking for a route.
	 * @see AyStar::FindPath()
	 */
	function FindPath(iterations);
};

class Rail.Cost
{
	_main = null;

	function _set(idx, val)
	{
		if (this._main._running) throw("You are not allowed to change parameters of a running pathfinder.");

		switch (idx) {
			case "max_cost":          this._main._max_cost = val; break;
			case "tile":              this._main._cost_tile = val; break;
			case "diagonal_tile":     this._cost_diagonal_tile = val; break;
			case "turn":              this._main._cost_turn = val; break;
			case "slope":             this._main._cost_slope = val; break;
			case "bridge_per_tile":   this._main._cost_bridge_per_tile = val; break;
			case "tunnel_per_tile":   this._main._cost_tunnel_per_tile = val; break;
			case "coast":             this._main._cost_coast = val; break;
			case "max_bridge_length": this._main._max_bridge_length = val; break;
			case "max_tunnel_length": this._main._max_tunnel_length = val; break;
			default: throw("the index '" + idx + "' does not exist");
		}

		return val;
	}

	function _get(idx)
	{
		switch (idx) {
			case "max_cost":          return this._main._max_cost;
			case "tile":              return this._main._cost_tile;
			case "diagonal_tile":     return this._cost_diagonal_tile;
			case "turn":              return this._main._cost_turn;
			case "slope":             return this._main._cost_slope;
			case "bridge_per_tile":   return this._main._cost_bridge_per_tile;
			case "tunnel_per_tile":   return this._main._cost_tunnel_per_tile;
			case "coast":             return this._main._cost_coast;
			case "max_bridge_length": return this._main._max_bridge_length;
			case "max_tunnel_length": return this._main._max_tunnel_length;
			default: throw("the index '" + idx + "' does not exist");
		}
	}

	constructor(main)
	{
		this._main = main;
	}
};

function Rail::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	if (!this._running && ret != null) {
		foreach (goal in this._goals) {
			if (goal[0] == ret.GetTile()) {
				return this._pathfinder.Path(ret, goal[1], 0, this._Cost, this);
			}
		}
	} else {
/*		if(_count % 1000  == 0) {
			local execMode = AIExecMode();
			local path = _pathfinder._open.Peek();
			AISign.BuildSign (path.GetTile(), _count+":"+path._cost);
		}
		_count ++;*/
	}
	return ret;
}

function Rail::_GetBridgeNumSlopes(end_a, end_b)
{
	local slopes = 0;
	local direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
	local slope = AITile.GetSlope(end_a);
	if (!((slope == AITile.SLOPE_NE && direction == 1) || (slope == AITile.SLOPE_SE && direction == -AIMap.GetMapSizeX()) ||
		(slope == AITile.SLOPE_SW && direction == -1) || (slope == AITile.SLOPE_NW && direction == AIMap.GetMapSizeX()) ||
		 slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
	}

	local slope = AITile.GetSlope(end_b);
	direction = -direction;
	if (!((slope == AITile.SLOPE_NE && direction == 1) || (slope == AITile.SLOPE_SE && direction == -AIMap.GetMapSizeX()) ||
		(slope == AITile.SLOPE_SW && direction == -1) || (slope == AITile.SLOPE_NW && direction == AIMap.GetMapSizeX()) ||
		 slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
	}
	return slopes;
}

function Rail::_nonzero(a, b)
{
	return a != 0 ? a : b;
}

function Rail::_IsStraight(p1,p2,p3) {
	return _GetDirectionIndex(p1,p2) == _GetDirectionIndex(p2,p3);
}

function Rail::_GetDirectionIndex(p1,p2) {
	return (p2 - p1) / AIMap.DistanceManhattan(p1,p2);
}

function Rail::_Cost(path, new_tile, new_direction, self)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;

	local prev_tile = path.GetTile();
	local par = path.GetParent();

	/* If the two tiles are more then 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be build. It isn't an existing bridge / tunnel, as that case is already handled. */
	 
	local cost = 0;
	if(self._cost_tight_turn > 0 && par != null && par.GetParent() != null && par.GetParent().GetParent() != null) {
		if(self._IsStraight(par.GetTile(), par.GetParent().GetTile(), par.GetParent().GetParent().GetTile())
				&& self._IsStraight(par.GetTile(), prev_tile, new_tile)
				&& self._GetDirectionIndex(par.GetTile(), par.GetParent().GetTile()) != self._GetDirectionIndex(prev_tile, par.GetTile())) {
			cost += self._cost_tight_turn;
		}
	}
	 
	local distance = AIMap.DistanceManhattan(new_tile, prev_tile);
	if (distance > 1) {
		/* Check if we should build a bridge or a tunnel. */

		local prevTunnelOrBridge = false;
		if(par != null && par.GetParent() != null && AIMap.DistanceManhattan(par.GetTile(), par.GetParent().GetTile())>1) {
			prevTunnelOrBridge = true;
		}
/*
		local isBridge = false;
		local bridge_list = AIBridgeList_Length(distance + 1);
		if (!bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), prev_tile, new_tile)) {
			isBridge = true;
		}
		if(isBridge) {
			cost += distance * (self._cost_tile + self._cost_bridge_per_tile);
			if(prevTunnelOrBridge || distance!=3) {
				cost += (max(distance,4) - 3) * self._cost_bridge_per_tile_ex;
			}
		} else {
			cost += distance * (self._cost_tile + self._cost_tunnel_per_tile);
			if(prevTunnelOrBridge || distance>5) {
				cost += (distance-3) * self._cost_tunnel_per_tile_ex;
			}
		}
*/
		cost += distance * (self._cost_tile + self._cost_bridge_per_tile) - self._cost_tile;
		if(prevTunnelOrBridge || distance!=3) {
			cost += distance * self._cost_bridge_per_tile_ex;
		}
		/*
		if (par != null && par.GetParent() != null &&
				par.GetParent().GetTile() - par.GetTile() != max(AIMap.GetTileX(prev_tile) - AIMap.GetTileX(new_tile), AIMap.GetTileY(prev_tile) - AIMap.GetTileY(new_tile)) / distance) {
			cost += self._cost_turn;
		}*/
		
		if(self._guideTileList.HasItem(new_tile)) {
			cost += self._cost_guide;
		}
		
		return path.GetCost() + cost;
	}

	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	cost += self._cost_tile;
	if (par != null && AIMap.DistanceManhattan(par.GetTile(), prev_tile) == 1 && par.GetTile() - prev_tile != prev_tile - new_tile) {
		if(AITile.IsSeaTile(new_tile)) {
			cost = self._cost_diagonal_sea;
		} else {
			cost = self._cost_diagonal_tile;
		}
	}
	
	if (par != null && par.GetParent() != null &&
			AIMap.DistanceManhattan(new_tile, par.GetParent().GetTile()) == 3 &&
			par.GetParent().GetTile() - par.GetTile() != prev_tile - new_tile) {
		cost += self._cost_turn;
	}

	/* Check if the new tile is a coast tile. */
	if (AITile.IsCoastTile(new_tile)) {
		cost += self._cost_coast;
	}
	if (AITile.IsSeaTile(new_tile)) {
		cost += self._cost_water;
	}
	if(self._cost_slope > 0) {
		if(par != null) {
			local h1 = AITile.GetMaxHeight (par.GetTile())
			local h2 = AITile.GetMaxHeight (new_tile);
			if(h2 != h1) {
				cost += self._cost_slope;
			}
		}
	}
	
/*
	if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_RAIL)) {
		cost += self._cost_crossing_rail;
	}*/

	/* We don't use already existing rail, so the following code is unused. It
	 *  assigns if no rail exists along the route. */
	/*
	if (path.GetParent() != null && !AIRail.AreTilesConnected(path.GetParent().GetTile(), prev_tile, new_tile)) {
		cost += self._cost_no_existing_rail;
	}
	*/

	if(self._guideTileList.HasItem(new_tile)) {
		cost += self._cost_guide;
	}
	return path.GetCost() + cost;
}

function Rail::_Estimate(cur_tile, cur_direction, goal_tiles, self)
{
	local min_cost = self._max_cost;
	/* As estimate we multiply the lowest possible cost for a single tile with
	 *  with the minimum number of tiles we need to traverse. */
	foreach (tile in goal_tiles) {
		local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(tile[0]));
		local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(tile[0]));
		min_cost = min(min_cost, min(dx, dy) * self._cost_diagonal_tile * 2 + (max(dx, dy) - min(dx, dy)) * self._cost_tile);
	}
	return min_cost * self._estimate_rate;
}


function Rail::_CanChangeBridge(path, cur_node) {
	local tracks = AIRail.GetRailTracks(cur_node);
	local direction;
	if(tracks == AIRail.RAILTRACK_NE_SW) {
		direction = AIMap.GetTileIndex(1, 0);
	} else if(tracks == AIRail.RAILTRACK_NW_SE) {
		direction = AIMap.GetTileIndex(0, 1);
	} else {
		return false;
	}
	local n_node = cur_node - direction;
	local p = path.GetParent();
	for(local i=0; i<=2; i++) {
		if(AIRail.GetRailTracks(n_node) != tracks 
				|| !AICompany.IsMine(AITile.GetOwner(n_node))
				|| _IsSlopedRail(n_node - direction, n_node, n_node + direction) 
				|| AITile.IsStationTile(n_node)
				|| _IsUnderBridge(n_node)  
				|| IsOnPath(p,n_node)
				|| _GetGoal2(n_node) != null
				|| _IsGoal2(n_node)) {
			return false;
		}
		n_node += direction;
	}
	//HgLog.Info("_CanChangeBridge:"+HgTile(cur_node));
	return true;
}

function Rail::_IsUnderBridge(node) {
	local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 0)];
	local c_node = node;
	foreach(offset in offsets) {
		for(local i=0; i<10; i++) {
			if(AIBridge.IsBridgeTile(c_node)) {
				local end = AIBridge.GetOtherBridgeEnd(c_node);
//				HgLog.Info("c_node:"+HgTile(c_node)+" node:"+HgTile(node)+" end:"+HgTile(end));
				if(end < node && node < c_node) {
//					HgLog.Warning("bridge found");
					return true;
				}
			}
			c_node += offset;
		}
	}
	return false;
}

function Rail::IsOnPath(path,node) {
	while(path != null) {
		if(path.GetTile()==node) {
			return true;
		}
		path = path.GetParent();
	}
	return false;
}

function Rail::_GetGoal2(node) {
	foreach (goal in this._goals) {
		if (goal[0] == node) {
			return goal[1];
		}
	}
	return null;
}

function Rail::_IsGoal2(node) {
	foreach (goal in this._goals) {
		if (goal[1] == node) {
			return true;
		}
	}
	return false;
}

function Rail::_IsInclude90DegreeTrack(target, parTile, curTile) {
	foreach(neighbor in HgTile.GetConnectionTiles(target, AIRail.GetRailTracks (target))) {
		if(neighbor == curTile) {
			continue;
		}
		if(AIMap.DistanceManhattan(parTile,neighbor)==1) {
			HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" true");
			return true;
		}
	}
	HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" false");
	return false;
}

function Rail::_PermitedDiagonalOffset(track) {
	switch(track) {
		case AIRail.RAILTRACK_SW_SE:
			return [AIMap.GetTileIndex(-1, 0),AIMap.GetTileIndex(0, -1)];
		case AIRail.RAILTRACK_NE_SE:
			return [AIMap.GetTileIndex(1, 0),AIMap.GetTileIndex(0, -1)];
		case AIRail.RAILTRACK_NW_NE:
			return [AIMap.GetTileIndex(1, 0),AIMap.GetTileIndex(0, 1)];
		case AIRail.RAILTRACK_NW_SW:
			return [AIMap.GetTileIndex(-1, 0),AIMap.GetTileIndex(0, 1)];
	}
	return null;
}


function Rail::_Neighbours(path, cur_node, self)
{
	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path.GetCost() >= self._max_cost) return [];
	
	local tiles = [];
	local offsets = HgTile.DIR4Index;
	local par = path.GetParent();
	local underBridge = false;
	local goal2 = self._GetGoal2(cur_node);
	if(par != null) {
		if(par.GetTile() == cur_node) {
			HgLog.Error("par.GetTile() == cur_node:" + HgTile(cur_node));
		}
	}
	
	
	if (AITile.HasTransportType(cur_node, AITile.TRANSPORT_RAIL)) {
		if(goal2 != null || par==null || par.GetParent()==null || (self.useInitializePath2 && par.GetParent().GetParent() == null)) { // start tile
		} else if(BuildedPath.Contains(cur_node)) {
			if(!HgTile.IsDiagonalTrack(AIRail.GetRailTracks(cur_node))) {
				if(!self._CanChangeBridge(path, cur_node)) {
					return [];
				}
				//HgLog.Info("_CanChangeBridge:"+HgTile(cur_node));
				underBridge = true;
			} else {
				if(AICompany.IsMine(AITile.GetOwner(cur_node)) && self._reverseTileList.HasItem(cur_node)) {
					offsets = self._PermitedDiagonalOffset(AIRail.GetRailTracks(cur_node));
					if(offsets==null) {
						return [];
					}
				} else {
					return [];
				}
			}
		}
	}

	/* Check if the current tile is part of a bridge or tunnel. */
	if (AIBridge.IsBridgeTile(cur_node) || AITunnel.IsTunnelTile(cur_node)) {
		/* We don't use existing rails, so neither existing bridges / tunnels. */
	} else if (par != null && AIMap.DistanceManhattan(cur_node, par.GetTile()) > 1) {
		local other_end = par.GetTile();
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
//		tiles.push([next_tile, 1]);
		foreach (offset in offsets) {
			if (self._BuildRail(cur_node, next_tile, next_tile + offset)) {
				tiles.push([next_tile, self._GetDirection(other_end, cur_node, next_tile, true)]);
			}
		}
	} else {
		local par_tile = par!=null ? par.GetTile() : null;
		local parpar = par!=null ? par.GetParent() : null;
		local parpar_tile = parpar!=null ? parpar.GetTile() : null;
		if(parpar_tile != null) {
			local distance = AIMap.DistanceManhattan(par_tile, parpar_tile);
			if( distance > 1) {
				local next_tile = cur_node + (cur_node - par_tile);
				local bridge_list = AIBridgeList_Length(distance + 1);
				if (!(!bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), par_tile, parpar_tile)) 
						&& AITunnel.GetOtherTunnelEnd(parpar_tile) != par_tile) {
					//HgLog.Info("cur_node:"+HgTile(cur_node)+" par_tile:"+HgTile(par_tile)+" parpar_tile:"+HgTile(parpar_tile));
					tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, false)]);
					return tiles;
				}
			}
		}
		
		
		/* Check all tiles adjacent to the current tile. */
		foreach (offset in offsets) {
			local next_tile = cur_node + offset;
			/* Don't turn back */
			if (par != null && next_tile == par_tile) continue;
			/* Disallow 90 degree turns */
			if (par != null && par.GetParent() != null &&
				next_tile - cur_node == par.GetParent().GetTile() - par_tile) continue;
			/* We add them to the to the neighbours-list if we can build a rail to
			 *  them and no rail exists there. */
			if (par == null 
					|| (goal2 == null && self._BuildRail(par_tile, cur_node, next_tile))
					|| (goal2 == next_tile 
						&& (AIRail.AreTilesConnected(par_tile, cur_node, next_tile) || self._BuildRail(par_tile, cur_node, next_tile))
						&& !self._IsInclude90DegreeTrack(next_tile, par_tile, cur_node))
					|| (self._can_build_water 
						&& (AITile.IsSeaTile(cur_node) 
							|| (AITile.IsCoastTile(cur_node) && AITile.IsBuildable(cur_node))) 
						&& self._RaiseAtWater(cur_node,next_tile))) {
				if (par != null) {
					tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, false)]);
				} else {
					tiles.push([next_tile, self._GetDirection(null, cur_node, next_tile, false)]);
				}
			}
		}
		if (par != null /*&& par.GetParent() != null*/ && !underBridge) {
			local bridges = self._GetTunnelsBridges(par, par_tile, cur_node/*, self._GetDirection(par.GetParent().GetTile(), par_tile, cur_node, true)*/);
			foreach (tile in bridges) {
				tiles.push(tile);
			}
		}
	}
	/*
	local s = "";
	foreach(t in tiles) {
		s += HgTile(t[0])+",";
	}
	HgLog.Info("tiles:" + HgTile(cur_node)+" next:"+s+" "+f);*/
	return tiles;
}

function Rail::_BuildRail(p1,p2,p3) {
	if(AIRail.BuildRail(p1,p2,p3)) {
		return true;
	}
	if(AIError.GetLastError() != AIError.ERR_AREA_NOT_CLEAR) {
		return false;
	}
	local r = CanDemolishRail(p2);
	if(r) {
		HgLog.Info("CanDemolishRail(Rail::_BuildRail):"+HgTile(p2));
	}
	return r;
}

function Rail::CanDemolishRail(p) {
	if(!AICompany.IsMine(AITile.GetOwner(p))) {
		return false;
	}
	if(AIRail.IsRailTile(p) || AIBridge.IsBridgeTile(p) || AITunnel.IsTunnelTile(p)) {
		return !BuildedPath.Contains(p);
	}
	return false;
}

function Rail::_RaiseAtWater(t0,t1) {
	if(!AIMap.IsValidTile(t1)) {
		return false;
	}
	if(AIMap.DistanceFromEdge (t1) <= 2) {
		return false;
	}
	local boundCorner = HgTile.GetCorners( HgTile(t0).GetDirection(HgTile(t1)) );
	if(AITile.GetCornerHeight(t0,boundCorner[0]) == 0 && AITile.GetCornerHeight(t0,boundCorner[1]) == 0) {
		local result = AITile.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[0]));
		return result;
	}
	return true;
}

function Rail::_CheckDirection(tile, existing_direction, new_direction, self)
{
	return false;
}

function Rail::_dir(from, to)
{
	if (from - to == 1) return 0;
	if (from - to == -1) return 1;
	if (from - to == AIMap.GetMapSizeX()) return 2;
	if (from - to == -AIMap.GetMapSizeX()) return 3;
	throw("Shouldn't come here in _dir");
}

function Rail::_GetDirection(pre_from, from, to, is_bridge)
{
	if (is_bridge) {
		local d = (from - to) / AIMap.DistanceManhattan(from,to);
		if (d == 1) return 1;
		if (d == -1) return 2;
		if (d == AIMap.GetMapSizeX()) return 4;
		if (d == -AIMap.GetMapSizeX()) return 8;
	}
	return 1 << (4 + (pre_from == null ? 0 : 
	4 * this._dir(pre_from, from)) + this._dir(from, to));
}

/**
 * Get a list of all bridges and tunnels that can be build from the
 *  current tile. Bridges will only be build starting on non-flat tiles
 *  for performance reasons. Tunnels will only be build if no terraforming
 *  is needed on both ends.
 */
function Rail::_GetTunnelsBridges(par, last_node, cur_node)
{
	local tiles = [];
	
	local dir = cur_node - last_node;
	local next = cur_node + dir;
	local bridge_dir = _GetDirection(par.GetTile(), cur_node, next, true);
	
	if(par.GetParent()!=null) {
		local last_node2 = par.GetParent().GetTile();

		if(!AITile.IsBuildable(cur_node)) {
			return [];
		}

		if(dir == last_node - last_node2 && !AITile.IsBuildable(next)) {
			for (local i = 0; i < this._max_tunnel_length; i++) {
				local target = last_node + i * dir;
				if (AITile.GetSlope(target))
					break;
				if (i > 2 && AITile.IsBuildable(target)) {
					local targetnext = target + dir;
					if (AITile.GetSlope(targetnext)){
						break;
					}
					if (AITile.IsBuildable(targetnext)) {
						local from = last_node;
						local to = targetnext;
						local dir = HgTile(from).GetDirection(HgTile(to));
						local success = true;
						foreach(corner in HgTile.GetCorners(dir)) {
							if(!AITile.LowerTile(from, HgTile.GetSlopeFromCorner(corner))) {
								success = false;
								break;
							}
						}
						if(success) {
							foreach(corner in HgTile.GetCorners(HgTile.GetOtherSideDir(dir))) {
								if(!AITile.LowerTile(to, HgTile.GetSlopeFromCorner(corner))) {
									success = false;
									break;
								}
							}
						}
						if(success) {
							tiles.push([target, bridge_dir]);
						}
					}
				}
			}
		}
	}
/*
	if(AITile.IsBuildable(next)) {
		if(AITile.IsBuildable(nextnext)) {
			return [];
		}
		
		for (local i = 0; i < this._max_tunnel_length; i++) {
			local target = cur_node + i * dir;
			if (AITile.GetSlope(target))
				break;
			if (i > 2 && AITile.IsBuildable(target)) {
				local targetnext = target + dir;
				if (AITile.GetSlope(targetnext)){
					break;
				}
				if (AITile.IsBuildable(targetnext)) {
					tiles.push([targetnext, bridge_dir]);
				}
			}
		}
	}*/
	
	if(!AITile.IsBuildable(next)) {
		for (local i = 2; i < this._max_bridge_length; i++) {
			local bridge_list = AIBridgeList_Length(i + 1);
			local target = cur_node + i * dir;
			if (!bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), cur_node, target)) {
				tiles.push([target, bridge_dir]);
			}
		}
	}
	local slope = AITile.GetSlope(cur_node);
	if (slope != AITile.SLOPE_SW && slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE && slope != AITile.SLOPE_NE) return tiles;
	local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_node);
	if (!AIMap.IsValidTile(other_tunnel_end)) return tiles;

	local tunnel_length = AIMap.DistanceManhattan(cur_node, other_tunnel_end);
	local prev_tile = cur_node + (cur_node - other_tunnel_end) / tunnel_length;
	if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && tunnel_length >= 2 &&
			prev_tile == last_node && tunnel_length < _max_tunnel_length && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, cur_node)) {
		tiles.push([other_tunnel_end, bridge_dir]);
	}
	return tiles;
}

function Rail::_IsSlopedRail(start, middle, end)
{
	local NW = 0; // Set to true if we want to build a rail to / from the north-west
	local NE = 0; // Set to true if we want to build a rail to / from the north-east
	local SW = 0; // Set to true if we want to build a rail to / from the south-west
	local SE = 0; // Set to true if we want to build a rail to / from the south-east

	if (middle - AIMap.GetMapSizeX() == start || middle - AIMap.GetMapSizeX() == end) NW = 1;
	if (middle - 1 == start || middle - 1 == end) NE = 1;
	if (middle + AIMap.GetMapSizeX() == start || middle + AIMap.GetMapSizeX() == end) SE = 1;
	if (middle + 1 == start || middle + 1 == end) SW = 1;

	/* If there is a turn in the current tile, it can't be sloped. */
	if ((NW || SE) && (NE || SW)) return false;

	local slope = AITile.GetSlope(middle);
	/* A rail on a steep slope is always sloped. */
	if (AITile.IsSteepSlope(slope)) return true;

	/* If only one corner is raised, the rail is sloped. */
	if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_W) return true;
	if (slope == AITile.SLOPE_S || slope == AITile.SLOPE_E) return true;

	if (NW && (slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE)) return true;
	if (NE && (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW)) return true;

	return false;
}
