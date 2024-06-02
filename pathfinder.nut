
class RailPathFinder
{
	static idCounter = IdCounter();
		
	_aystar_class = AyStar;
	_Cost = null;
	_max_cost = null;
	_cost_tile = null;
	_cost_guide = null;
	_cost_diagonal_tile = null;
	_cost_doublediagonal_sea = null;
	_cost_turn = null;
	_cost_tight_turn = null;
	_cost_tight_turn_rev = null;
	_cost_slope = null;
	_cost_tunnel_per_tile = null;
	_cost_tunnel_per_tile_ex = null;
	_cost_tunnel_per_tile_ex2 = null;
	_cost_bridge_per_tile = null;
	_cost_bridge_per_tile_ex = null;
	_cost_bridge_per_tile_ex2 = null;
	_cost_under_bridge = null;
	_cost_coast = null; 
	_cost_crossing_rail = null;
	_cost_crossing_reverse = null;
	_cost_level_crossing = null;
	_cost_water = null;
	_cost_danger = null;

	_pathfinder = null;
	_max_bridge_length = null;
	_max_tunnel_length = null;
	_bottom_ex_tunnel_length = null;
	_bottom_ex2_tunnel_length = null;
	_bottom_ex_bridge_length = null;
	_bottom_ex2_bridge_length = null;
	_can_build_water = null;
	_estimate_rate = null;
	_max_slope = null;

	_running = null;
	_goals = null;
	_goalsMap = null;
	_goalTiles = null;
	_count = null;
	_reverseNears = null;
	_reverseTiles = null;
	_goalStartTileLen = null;
	
	debug = false;
	engine =  null;
	cargo = null;
	platformLength = null;
	distance = null;
	dangerTiles = null;
	isOutward = null;
	isRevReverse = null;
	isSingle = null;
	reversePath = null;
	revOkTiles = null;
	orgTile = null;
	trainDirection = null; // 列車進行方向 0:goal方向 1:start方向 2:双方向
	
	isFoundPath = false;
	
	constructor() {
		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_guide = 20;
		this._cost_diagonal_tile = 70;
		this._cost_doublediagonal_sea = 150;
		this._cost_turn = 50;
		this._cost_tight_turn = 200;
		this._cost_slope = 100;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._cost_under_bridge = 100;
		this._cost_coast = 20;
		this._cost_crossing_rail = 50;
		this._cost_crossing_reverse = 100;
		this._max_bridge_length = 6;
		this._max_tunnel_length = 6;
		this._can_build_water = false;
		this._cost_water = 20;
		this._estimate_rate = 2;
		this._pathfinder = null;

		this._running = false;
		this._count = idCounter.Get() * 1000;
		this._reverseNears = null;
		this._reverseTiles = null;
		this._goalsMap = {};
		this._goalTiles = {};

		this.isRevReverse = false;
		this.trainDirection = 2;
		this.isSingle = false;
		this.revOkTiles = {};
	}

	function InitializeParameters() {
		//debug = true;
		
		this._Cost = debug ? this._DebugCost : this._NormalCost;
		_pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);
		_pathfinder.debug = debug;
	
		_cost_level_crossing = 900;
		_cost_crossing_reverse = 300;
		if(isSingle) {
			_cost_bridge_per_tile_ex = 10;
			_cost_bridge_per_tile_ex2 = 100;
			_cost_tunnel_per_tile_ex  = 10;
			_cost_tunnel_per_tile_ex2 = 100;
		} else {
			/*_cost_bridge_per_tile_ex = 600;
			_cost_bridge_per_tile_ex2 = 900;
			_cost_tunnel_per_tile_ex  = 600;
			_cost_tunnel_per_tile_ex2 = 900;*/
			_cost_bridge_per_tile_ex = 200;
			_cost_bridge_per_tile_ex2 = 400;
			_cost_tunnel_per_tile_ex  = 200;
			_cost_tunnel_per_tile_ex2 = 300;
		}
		_cost_diagonal_tile = 67;
		_cost_doublediagonal_sea = 100000;
		_cost_guide = 900; //1500; //20;
		_cost_under_bridge = 50;	
		_cost_danger = 10000;

		
		_estimate_rate = 2;
		_cost_tile = 100;
		_cost_turn = 300;
		_cost_tight_turn = distance!=null && distance<40 ? 100 : 1500; //isReverse ? 300 : 1500;
		_cost_tight_turn_rev = 1500;
		_cost_bridge_per_tile = 100;//50
		_cost_tunnel_per_tile = 0;//100;//50　// トンネルではなく山登りをしない為にコスト0に
		_max_bridge_length = 30; //platformLength == null ? 11 : max( 7, platformLength * 3 / 2 );
		_max_tunnel_length = 11; //platformLength == null ? 11 : max( 7, platformLength * 3 / 2 );
		_bottom_ex_bridge_length = 7;//platformLength == null ? 7 : max( 7, platformLength ); 列車が長いからといって列車間隔が長くなるわけではない
		_bottom_ex2_bridge_length = _bottom_ex_bridge_length * 3 / 2 + 1;
		_bottom_ex_tunnel_length = 7; //platformLength == null ? 7 : max( 7, platformLength );
		_bottom_ex2_tunnel_length = _bottom_ex_tunnel_length  * 3 / 2 + 1;
		
		_cost_slope = 100; // トンネルを使ってもらう為にこれくらい必要
		_max_slope = 2;
		if(engine != null && cargo != null) {/*
			local totalWeight = VehicleUtils.GetCargoWeight(cargo,30*13) + 18*13 + 145;
			local maxSpeed = AIEngine.GetMaxSpeed(engine);
			local requestSpeed = 30;
			local acc = VehicleUtils.GetAcceleration( 
					VehicleUtils.GetSlopeForce(totalWeight,totalWeight)
					+ VehicleUtils.GetAirDrag(requestSpeed, maxSpeed, 14),
				requestSpeed,
				AIEngine.GetMaxTractiveEffort(engine),
				AIEngine.GetPower(engine), totalWeight);
			if(maxSpeed < 150 && acc < 0) {
				HgLog.Info("TrainRoute: pathfinding consider slope");
				_cost_slope = 1500;
				_cost_turn = 100;
			}*/
		
			local slopeSteepness = HogeAI.Get().GetTrainSlopeSteepness();
			local avoidSlope = false;
			if(AIEngine.GetMaxTractiveEffort(engine) < slopeSteepness * 50) {
				_max_slope = 2;
				avoidSlope = true;
			} else if(HogeAI.Get().mountain && AIEngine.GetPower(engine) < slopeSteepness * 600) {
				_max_slope = 5;
				avoidSlope = true;
			}
			if(avoidSlope) {
				HgLog.Info("TrainRoute: pathfinding consider slope");
				if(isOutward || isSingle) {
					_cost_slope = 1500;
				}
				_cost_turn = 100;
			}
		}
		
		if(HogeAI.Get().IsRich()) {
			_max_tunnel_length = 14; //platformLength == null ? 14 : max( 7, platformLength * 2 );
		} else if(!HogeAI.Get().HasIncome(100000)) {
			_max_tunnel_length = 0;
		}
		if(HogeAI.Get().CanRemoveWater()) {
			_can_build_water = true;
			_cost_water = -50;//50;
		}
		
		_InitializeDangerTiles();
	}
	
	
	function FindPath(limitCount,eventPoller) {
		HgLog.Info("TrainRoute: Pathfinding...limit count:"+limitCount+" distance:"+distance);
		limitCount *= 3;
		local counter = 0;
		local path = false;
		local startDate = AIDate.GetCurrentDate();
		local totalInterval = 0;
		while (path == false) {
			if(limitCount < counter) {
				break;
			}
			PerformanceCounter.Clear();
			path = _FindPath(50);
			PerformanceCounter.Print();
			counter++;
			HgLog.Info("counter:"+counter);
			local intervalStartDate = AIDate.GetCurrentDate();
			if(path == false && eventPoller != null && eventPoller.OnPathFindingInterval()==false) {
				HgLog.Info("TrainRoute: FindPath break by OnPathFindingInterval");
				return null;
			}
			totalInterval += AIDate.GetCurrentDate() - intervalStartDate;
		}
		
		if(path == false) { // 継続中
			path = _pathfinder._open.Peek();
		} else if(path != null) {
			HgLog.Info("TrainRoute: Path found. (count:" + counter + " date:"+ (AIDate.GetCurrentDate() - startDate - totalInterval) +") distance:"+distance);
			isFoundPath = true;
		} else {
			HgLog.Info("TrainRoute: FindPath failed");
		}
		if(path != null) {
			path = Path.FromPath(path);
			if(!isFoundPath) {
				while(path != null && AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_RAIL)) {
					HgLog.Info("tail tile is on rail:"+HgTile(path.GetTile()));
					path = path.GetParent();
				}
			}
			if(path != null) {
				path = RemoveConnectedHead(path);
				path = RemoveConnectedHead(path.Reverse()).Reverse();
			}
		}
		return path;
	}

	function RemoveConnectedHead(path) {
		local prev = null;
		local prevprev = null;
		local lastPath = path;
		while(path != null) {
			if(prev != null && prevprev != null) {
				if(RailPathFinder.AreTilesConnectedAndMine(prevprev.GetTile(),prev.GetTile(),path.GetTile())
						|| HgTile.IsDoubleDepotTracks(prev.GetTile())
						|| (AIBridge.IsBridgeTile(prevprev.GetTile()) && AIBridge.GetOtherBridgeEnd(prevprev.GetTile()) == prev.GetTile())
						|| (AITunnel.IsTunnelTile(prevprev.GetTile()) && AITunnel.GetOtherTunnelEnd(prevprev.GetTile()) == prev.GetTile())
						|| (AIBridge.IsBridgeTile(prev.GetTile()) && AIBridge.GetOtherBridgeEnd(prev.GetTile()) == path.GetTile())
						|| (AITunnel.IsTunnelTile(prev.GetTile()) && AITunnel.GetOtherTunnelEnd(prev.GetTile()) == path.GetTile())) {
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
	
	function AreTilesConnectedAndMine(a,b,c) {
		return AIRail.AreTilesConnected(a,b,c) && AICompany.IsMine(AITile.GetOwner(b));
	}
		
	function IsFoundGoal() {
		return isFoundPath;
	}
	
	function InitializePath(sources, goals, ignored_tiles = [], reversePath = null) {
		local testMode = AITestMode(); // _Costメソッドが呼ばれるので
		this.reversePath = reversePath;
		if(isOutward == null) {
			isOutward == reversePath == null;
		}
		InitializeParameters();
		
		if(sources[0].len() >= 3) {
			_InitializePath2(sources, goals, ignored_tiles, reversePath);
			return;
		}
		_goalStartTileLen = 2;
	
		local nsources = [];

		foreach (node in sources) {
			local path = this._pathfinder.Path(null, node[1], 0xFF, null, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, null, this._Cost, this);
			nsources.push(path);
		}
		_InitializeGoals(goals);
		SetReverseNears();
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
		
	}
	
	function _InitializePath2(sources, goals, ignored_tiles = [], reversePath=null) {
		local testMode = AITestMode();
		local nsources = [];

		foreach (node in sources) {
			_goalStartTileLen = node.len();
			local path = null;
			if(node.len()>=4) {
				path = this._pathfinder.Path(path, node[3], 0xFF, null, this._Cost, this);
			}
			path = this._pathfinder.Path(path, node[2], 0xFF, null, this._Cost, this);
			path = this._pathfinder.Path(path, node[1], 0xFF, null, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, null, this._Cost, this);
			nsources.push(path);
		}
		_InitializeGoals(goals);
		SetReverseNears();
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
	}
	
	function _InitializeGoals(goals) {
		this._goals = goals;
		foreach(nodes in goals) {
			this._goalsMap[nodes[0]] <- nodes;
			foreach(t in nodes) {
				_goalTiles.rawset(t,t);
			}
		}
	}
	
	function _InitializeDangerTiles() {
		if(dangerTiles != null) {
			local table = {};
			foreach(tile in dangerTiles) {
				table.rawset(tile,0);
			}
			dangerTiles = table;
		} else {
			dangerTiles = {};
		}
	}
	
	function SetReverseNears() {
		//HgLog.Info("SetReversePath:"+reversePath+" debug:"+debug);
		if(reversePath == null) {
			return;
		}
	
		
		local nears = {};
		_reverseNears = {};
		_reverseTiles = {};
		
		local path = reversePath;
		local prev = null;
		local prevprev = null;
		while(path != null) {
			local tile = path.GetTile();
			_reverseTiles.rawset(tile,0);
			if(prev != null) {
				local d = AIMap.DistanceManhattan(prev,tile);
				if(d==0) {
					HgLog.Warning("distance0 (SetReversePath)"+HgTile(prev));
				} else {
					local revDir = _GetRevDir(prev,tile);
					if(d > 1) {
						local offset;
						if(AIMap.GetTileX(prev) == AIMap.GetTileX(tile)) {
							offset = AIMap.GetTileIndex(0,1);
						} else {
							offset = AIMap.GetTileIndex(1,0);
						}
						for(local i=0; i<d; i++) {
							nears.rawset(tile + i * offset + revDir,0);
							_reverseNears.rawset(tile + i * offset + revDir,0)
							//DebugSign(tile + i * offset + revDir,"0");
						}
					} else {
						nears.rawset(tile + revDir,0);
						_reverseNears.rawset(tile + revDir,0);
						//DebugSign(tile + revDir,"0");
						if(prevprev != null && AIMap.DistanceManhattan(prevprev,prev)==1 && prev == prevprev + revDir) {
							nears.rawset(prev,0);
							_reverseNears.rawset(prev,0);
							//DebugSign(prev,"0");
						}
					}
				}
			}
			prevprev = prev;
			prev = tile;
			path = path.GetParent();
		}
		for(local i=1; i<20; i++) {
			local next = {}
			foreach(tile,level in nears) {
				foreach(d in HgTile.DIR4Index) {
					if(!_reverseNears.rawin(tile+d)) {
						next.rawset(tile+d ,i)
						_reverseNears.rawset(tile+d ,i)
						//DebugSign(tile+d,i.tostring());
					}
				}
			}
			nears = next;
		}

	}

	function DebugSign(tile,text) {
		if(debug) {
			local execMode = AIExecMode();
			AISign.BuildSign(tile, text)
		}
	}

	function _FindPath(iterations) {
		//local c = PerformanceCounter.Start("FindPath");
		local result = __FindPath(iterations);
		//c.Stop();
		
		return result;
	}
	
	function __FindPath(iterations) {
		local test_mode = AITestMode();
		local ret = this._pathfinder.FindPath(iterations);
		this._running = (ret == false) ? true : false;
		if (!this._running && ret != null) {
			local goalTiles = this._GetGoalTiles(ret.GetTile());
			if(goalTiles != null) {
				return this._pathfinder.Path(ret, goalTiles[1], 0, null, this._Cost, this);
			}
		}
		return ret;
	}
	
	function _GetBridgeNumSlopes(end_a, end_b) {
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
	
	function _nonzero(a, b){
		return a != 0 ? a : b;
	}
	
	function _IsStraight(p1,p2,p3) {
		return RailPathFinder._GetDirectionIndex(p1,p2) == RailPathFinder._GetDirectionIndex(p2,p3);
	}

	function _GetDirectionIndex(p1,p2) {
		return (p2 - p1) / AIMap.DistanceManhattan(p1,p2);
	}

	function _NormalCost(self, path, new_tile, new_direction, mode) {
		//local counter = PerformanceCounter.Start("Cost");
		local result = RailPathFinder.__Cost(self, path, new_tile, mode, new_direction);
		//counter.Stop();
		return result;
	}

	function _DebugCost(self, path, new_tile, new_direction, mode) {
		//local counter = PerformanceCounter.Start("Cost");
		local result = RailPathFinder.__Cost(self, path, new_tile, mode, new_direction);
		//self.DebugSign(new_tile,result.tostring());
		//counter.Stop();
		return result;
	}

	function _IsTightTurn(dirs) {
		if(dirs[2] == dirs[3] && dirs[0] == dirs[1] && dirs[2] != dirs[0]) {
			return true;
		} else {
			return false;
		}
	}
	
	function _IsLeftTurnR2(dirs) {
		if(dirs[0] == dirs[1] && dirs[4] == dirs[5] && dirs[0] != dirs[4] && dirs[4] == HgTile.GetRevDirFromDir(dirs[0])) {
			return true;
		} else {
			return false;
		}
	}

	function __Cost(self, path, new_tile, new_direction, mode) {
		/* path == null means this is the first node of a path, so the cost is 0. */
		if (path == null) return 0;
		
		local t = [new_tile];
		local cur = path;
		local pre = new_tile;
		local dirs = [];
		local distances = [];
		while(cur != null && t.len()<7) {
			local tile = cur.GetTile();
			t.push( tile );
			local distance = AIMap.DistanceManhattan(pre,tile);
			distances.push( distance );
			dirs.push( (pre - tile) /  distance );
			cur = cur.GetParent();
			pre = tile;
		}
		local revDir = self.isOutward ? self._GetRevDir(t[0],t[1]) : null;

		local cost = 0;
		if(self._cost_tight_turn > 0 && t.len() >= 5) {
			if(self._IsTightTurn(dirs)) {
				if(revDir != null && dirs[2] == -revDir) {
					cost += self._cost_tight_turn_rev;
				} else {
					cost += self._cost_tight_turn;
				}
			}
			local goalTiles = self._GetGoalTiles(new_tile);
			if(goalTiles != null) {
				local goalsLen = goalTiles.len();
				local gdir = [];
				for(local i=2;i>=0; i--) {
					if(i+1 < goalsLen) {
						local distance = AIMap.DistanceManhattan(goalTiles[i],goalTiles[i+1]);
						gdir.push((goalTiles[i+1] - goalTiles[i])/distance);
					} else {
						gdir.push(0);
					}
				}
				gdir.extend(dirs);
				if((goalsLen >= 2 && self._IsTightTurn(gdir.slice(2,6)))
						|| (goalsLen >= 3 && self._IsTightTurn(gdir.slice(1,5)))
						|| (goalsLen>= 4 && self._IsTightTurn(gdir.slice(0,4)))) {
					//HgLog.Warning("_GetGoalTiles tight goal:"+HgTile(new_tile)+" dirs:"+HgArray(gdir));
					cost += self._cost_tight_turn;					
				} else {
					//HgLog.Warning("_GetGoalTiles not tight goal:"+HgTile(new_tile)+" dirs:"+HgArray(gdir));
				}
				if(self.isOutward && dirs.len()>=5) {
					if((goalsLen >= 2 && self._IsLeftTurnR2(gdir.slice(2,8)))
							|| (goalsLen >= 3 && self._IsLeftTurnR2(gdir.slice(1,7)))
							|| (goalsLen>= 4 && self._IsLeftTurnR2(gdir.slice(0,6)))) {
						cost += 500;		
						//HgLog.Warning("_GetGoalTiles _IsLeftTurnR2 goal:"+HgTile(new_tile)+" dirs:"+HgArray(gdir));			
					} else {
						//HgLog.Warning("_GetGoalTiles not _IsLeftTurnR2 goal:"+HgTile(new_tile)+" dirs:"+HgArray(gdir));
					}
				}
			}
		}

		if (AITile.HasTransportType(t[0], AITile.TRANSPORT_ROAD)) cost += self._cost_level_crossing;

		local diagonal = false;
		local distance = distances[0];
		local turn = false;
		if (distance > 1) {
			/* Check if we should build a bridge or a tunnel. */

			local prevLength = 0;
			if(t.len() >= 4) {
				prevLength = distances[2] - 1;
			}
			local totalLength = distance + prevLength;
			if(mode != null && mode instanceof RailPathFinder.Underground) {
				cost += totalLength * (self._cost_tile + self._cost_tunnel_per_tile);
				if(totalLength > self._bottom_ex_tunnel_length) {
					cost += (distance - self._bottom_ex_tunnel_length) * self._cost_tunnel_per_tile_ex;
				}
				if(totalLength > self._bottom_ex2_tunnel_length) {
					cost += (totalLength - (self._bottom_ex2_tunnel_length-1)) * self._cost_tunnel_per_tile_ex2;
				}
			} else if(AITunnel.GetOtherTunnelEnd(t[0])==t[1]) {
				cost += totalLength * self._cost_tile;
				if(totalLength > self._bottom_ex_tunnel_length) {
					cost += (distance - self._bottom_ex_tunnel_length) * self._cost_tunnel_per_tile_ex;
				}
				if(totalLength > self._bottom_ex2_tunnel_length) {
					cost += (totalLength - (self._bottom_ex2_tunnel_length-1)) * self._cost_tunnel_per_tile_ex2;
				}
			} else {
				cost += totalLength * (self._cost_tile + self._cost_bridge_per_tile);
				if(totalLength >= self._bottom_ex_bridge_length) {
					cost += (totalLength - (self._bottom_ex_bridge_length-1)) * self._cost_bridge_per_tile_ex;
				}
				if(totalLength >= self._bottom_ex2_bridge_length) {
					cost += (totalLength - (self._bottom_ex2_bridge_length-1)) * self._cost_bridge_per_tile_ex2;
				}
			}
			/*
			if(self._reverseNears != null) {
				local d = (prev_tile - new_tile)/ distance;
				for(local c = new_tile + d; c != prev_tile; c += d) {
					if(self._reverseNears.rawin(c)) {
						if(self._reverseNears[c] == 0) {
							cost += self._cost_crossing_reverse;
						}
					}
				}
			}*/
		} else {
			local diagonalSea = false;
			if(t.len() >= 3 && distances[1] == 1 && dirs[1] != dirs[0]) {
				diagonal = true;
				if(AITile.IsSeaTile(t[0]) && AITile.IsSeaTile(t[1])) {
					local cur = path; //=prev
					local count = 1;
					while(cur != null) {
						if(!self._IsDiagonalDirection(cur.GetDirection()) || !AITile.IsSeaTile(cur.GetTile())) {
							break;
						}
						count ++;
						cur = cur.GetParent();
					}
					if(count >= 4) {
						diagonalSea = true;
					} else {
						local count = 0;
						while(cur != null) {
							if(self._IsDiagonalDirection(cur.GetDirection()) || !AITile.IsSeaTile(cur.GetTile())) {
								break;
							}
							count ++;
							cur = cur.GetParent();
						}
						if(count <= 5) {
							diagonalSea = true;
						}
					}/*
					local parparpar = parpar.GetParent();
					if(parparpar != null 
							&& self._IsDiagonalDirection(par.GetDirection()) 
							&& self._IsDiagonalDirection(parpar.GetDirection()) 
							&& self._IsDiagonalDirection(parparpar.GetDirection())) {
						diagonalSea = true;// ナナメが4連続していた場合
					}*/
				}
			}
			if(diagonalSea) {
				cost += self._cost_doublediagonal_sea;
			} else if(diagonal) {
				cost += self._cost_diagonal_tile;
			} else {
				cost += self._cost_tile;
			}
			
			if (t.len() >= 4 &&	AIMap.DistanceManhattan(t[0], t[3]) == 3 &&	dirs[2] != dirs[0]) {
				turn = true;
				if(dirs[1] != dirs[2]) { // 直線から斜めはゼロコスト
					cost += self._cost_turn;
				}
			}

			if (AITile.IsCoastTile(t[0])) {
				cost += self._cost_coast;
			}
			if (AITile.IsSeaTile(t[0])) {
				cost += self._cost_water;
			}
			if(self._cost_slope > 0) {
				if(t.len() >= self._max_slope+2) {
					local h1 = AITile.GetMaxHeight(t[self._max_slope+1]); //[3]
					local h2 = AITile.GetMaxHeight(t[0]);
					if(self.trainDirection == 2) {
						if(abs(h2-h1) >= self._max_slope) { //2
							cost += self._cost_slope;
						}
					} else if(self.trainDirection == 1) {
						if(h1-h2 >= self._max_slope) { //2
							cost += self._cost_slope;
						}
					} else if(self.trainDirection == 0) {
						if(h2-h1 >= self._max_slope) { //2
							cost += self._cost_slope;
						}
					}
				}
			}
		}
		/*
		if(self._reverseNears != null) {
			if(self._reverseNears.rawin(new_tile)) {
				local level = self._reverseNears[new_tile];
				if(level == 1) {
					cost -= 50;
				} else if(diagonal && level == 0) {
					local tracks = AIRail.GetRailTracks(new_tile);
					if(tracks != AIRail.RAILTRACK_NE_SW && tracks != AIRail.RAILTRACK_NW_SE) {
						cost -= 50;
					} else {
						cost += 100;
					}
				}
			}
		} else */
		
		if(self.isOutward) { // 帰路を空ける
			local revDir = self._GetRevDir(t[0],t[1]);
			if(dirs.len() >= 6) { // 半径2左カーブ
				if(dirs[0] == dirs[1] && dirs[4] == dirs[5] && dirs[0] != dirs[4] && dirs[4] == -revDir) {
					//HgLog.Warning("CURV:"+HgTile(t[0])+"-"+HgTile(t[1])+"-"+HgTile(t[2])+"["+HgTile(t[3])+"]"+HgTile(t[4])+"-"+HgTile(t[5])+"-"+HgTile(t[6]));
					cost += 300;
					if(distances[0]>1) {
						cost += 600;
					}
				}
			}
			if(distance > 1) {
				/*if(self._IsBuildableLine(t[0] + revDir, t[1] + revDir)) {
				} else*/ 
				//if(true) {
				//} else 
				if(mode != null && mode instanceof RailPathFinder.Underground) {
					local underGround = self._GetUndergroundTunnel(t[3] + revDir, t[2] + revDir, t[1] + revDir, mode.level, t[0] + revDir);
					if(underGround.len() == 0) {
						cost += 3000;
					}
				} else if(AITunnel.GetOtherTunnelEnd(t[0])==t[1]) {
					if(AITunnel.GetOtherTunnelEnd(t[0]+revDir)!=t[1]+revDir || !AITunnel.BuildTunnel(AIVehicle.VT_RAIL,t[0]+revDir)) {
						cost += 3000;
						//HgLog.Warning("Tunnel NG:"+HgTile(t[0])+"-"+HgTile(t[1])+" "+HgTile(t[1] + revDir));
					} else {
						//HgLog.Warning("Tunnel OK:"+HgTile(t[0])+"-"+HgTile(t[1])+" "+HgTile(t[1] + revDir));
					}
				} else {
					local bridge_list = AIBridgeList_Length(distance + 1);
					if(!(RailPathFinder.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), t[1] + revDir, t[0] + revDir) 
								&& AITile.GetMaxHeight(t[1]) == AITile.GetMaxHeight(t[1] + revDir)
								&& AITile.GetMaxHeight(t[0]) == AITile.GetMaxHeight(t[0] + revDir))
							&& AITunnel.GetOtherTunnelEnd(t[1] + revDir) != t[0] + revDir) {
						cost += 3000;
						//HgLog.Warning("BRIDGE NG:"+HgTile(prev_tile)+"-"+HgTile(new_tile)+" "+HgTile(prev_tile + revDir));
					} else {
						//HgLog.Warning("BRIDGE OK:"+HgTile(prev_tile)+"-"+HgTile(new_tile)+" "+HgTile(prev_tile + revDir));
					}
				}
			} else {
				if(!HogeAI.IsBuildable(t[1] + revDir) || !HogeAI.IsBuildable(t[0] + revDir) 
						|| HgTile.GetBoundMaxHeight(t[0] + revDir, t[1] + revDir) == 0
						|| (turn && ( 
							(dirs[1]==revDir && AITile.IsCoastTile(t[1]) && HgTile(t[1]).GetMaxHeightCount()<3) // 右ターンの場合
							 || (dirs[2]==revDir && AITile.IsCoastTile(t[2]) && HgTile(t[2]).GetMaxHeightCount()<3) )) ) {
					if(!self.revOkTiles.rawin(RailPathFinder.Get2TileKey(t[0]+revDir,t[1]+revDir))) {
						cost += 3000;
					}
				}
			}
		}
		
		if(self.dangerTiles.rawin(new_tile)) {
			//HgLog.Info("danger tile:"+HgTile(new_tile));
			cost += self._cost_danger;
		}
		

		return path.GetCost() + cost;
	}

	function _GetRevDir(cur,prev) {
		return HgTile.GetRevDir(prev,cur,isRevReverse);
	}

	function _GetDir(t,index) {
		return (t[index] - t[index+1]) / AIMap.DistanceManhattan(t[index], t[index+1]);
	}

	function _IsBuildableLine(a,b) {
		local distance = AIMap.DistanceManhattan(a,b);
		if(AIMap.GetTileX(a) == AIMap.GetTileX(b)) {
			return AITile.IsBuildableRectangle(min(a,b),1,distance+1);
		} else {
			return AITile.IsBuildableRectangle(min(a,b),distance+1,1);
		}
	}

	function _Estimate(self, cur_tile, cur_direction, goals) {
		//local counter = PerformanceCounter.Start("Estimate");

		local min_cost = self._max_cost;
		/* As estimate we multiply the lowest possible cost for a single tile with
		 *  with the minimum number of tiles we need to traverse. */
		foreach (goal in goals) {
			local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(goal[0]));
			local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(goal[0]));
			//local goalCost = goal.len() >= 3 ? goal[2] : 0;
			
			min_cost = min(min_cost, min(dx, dy) * 70 * 2 + (max(dx, dy) - min(dx, dy)) * 100/* + goalCost*/);
		}
		
		local guide = 0;
		if(self._reverseNears != null) {
			if(self._reverseNears.rawin(cur_tile)) {
				local level = self._reverseNears[cur_tile];
				guide = self._cost_guide * level;
			} else {
				guide = self._cost_guide * 20;
			}
		}
		if(self.orgTile != null) {
			guide += AIMap.DistanceManhattan(self.orgTile,cur_tile) * 100;
		}
		
		//counter.Stop();
		
		return min_cost * self._estimate_rate + guide;
	}

	function _CanChangeBridge(path, cur_node) {
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
					//|| p.Contains(n_node) これのせいでナナメに横切れない
					|| _IsGoalTile(n_node)) {
				return false;
			}
			n_node += direction;
		}
		n_node = cur_node - direction * 2;
		local table = path.GetParentTable();
		for(local i=0; i<5; i++) {
			if(n_node != p.GetTile() && n_node != cur_node && table.rawin(n_node)) {
				return false;
			}
			n_node += direction;
		}
		//HgLog.Info("_CanChangeBridge:"+HgTile(cur_node));
		return true;
	}
	
	static function CanChangeBridgeStatic(cur_node, checkUnderBridge=true) {
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
		for(local i=0; i<=2; i++) {
			if(AIRail.GetRailTracks(n_node) != tracks 
					|| !AICompany.IsMine(AITile.GetOwner(n_node))
					|| RailPathFinder._IsSlopedRail(n_node - direction, n_node, n_node + direction) 
					|| AITile.IsStationTile(n_node)
					|| (checkUnderBridge && RailPathFinder._IsUnderBridge(n_node))) {
				return false;
			}
			n_node += direction;
		}
		return true;
	}
	
	
	function _IsUnderBridge(node) {
		local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 0)];
		foreach(offset in offsets) {
			local c_node = node;
			for(local i=0; i<10; i++) {
				if(AIBridge.IsBridgeTile(c_node)) {
					local end = AIBridge.GetOtherBridgeEnd(c_node);
	//				HgLog.Info("c_node:"+HgTile(c_node)+" node:"+HgTile(node)+" end:"+HgTile(end));
					if(offset == 1 && c_node - end >= offsets[0]) { // offsetがx方向、endがY方向マイナスの時だけ判定ミスするので除外
					} else if(end < node && node < c_node) {
	//					HgLog.Warning("bridge found");
						return true;
					}
				}
				c_node += offset;
			}
		}
		return false;
	}

	function _IsCollideTunnel(start, end, level) {

		local indexFunc;
		local offset;
		if(AIMap.GetTileX(start) == AIMap.GetTileX(end)) {
			indexFunc = AIMap.GetTileX;
			offset = AIMap.GetTileIndex(1, 0);
		} else {
			indexFunc = AIMap.GetTileY;
			offset = AIMap.GetTileIndex(0, 1);
		}
		local tileList = AITileList();
		local index0 = indexFunc(start);
		tileList.AddRectangle(min(start, end) + offset, max(start, end) + offset * 14);
		tileList.Valuate(AITunnel.IsTunnelTile);
		tileList.KeepValue(1);
		tileList.Valuate(AITile.GetMaxHeight);
		tileList.KeepValue(level);
		tileList.Valuate(AITunnel.GetOtherTunnelEnd);
		foreach(t0, t1 in tileList) {
			if(indexFunc(t1) < index0 && index0 < indexFunc(t0)) {
				return true;
			}
		}
		return false;
		/*
		
		
		for(local node = min(start,end) + dir; node < max(start,end); node += dir) {
			foreach(offset in offsets) {
				if(offset == dir) {
					continue;
				}
				local c_node = node;
				for(local i=0; i<13; i++) {
					if(AITunnel.IsTunnelTile(c_node) && AITile.GetMaxHeight(c_node) == level) {
						local end = AITunnel.GetOtherTunnelEnd(c_node);
						if(end < node && node < c_node) {
							c.Stop();
							return true;
						}
					}
					c_node += offset;
				}
			}
		}
		c.Stop();
		return false;*/
	}

	function _GetGoalTiles(node) {
		if(_goalsMap.rawin(node)) {
			return _goalsMap[node];
		}
		return null;
	}

	function _IsGoalTile(node) {
		return _goalTiles.rawin(node);
	}

	function _IsInclude90DegreeTrack(target, parTile, curTile) {
		if(AIBridge.IsBridgeTile(target) || AITunnel.IsTunnelTile(target)) {
			//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" false (tunnel or bridge)");
			return false;
		}
		foreach(d in HgTile.DIR4Index) {
			local neighbor = parTile + d;
			if(AIRail.AreTilesConnected(curTile,target,neighbor)) {
				//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(curTile)+" "+HgTile(target)+" "+HgTile(neighbor)+" false");
				return true;
			}
		}
		return false;
	/*	
		foreach(neighbor in HgTile.GetConnectionTiles(target, curTile, AIRail.GetRailTracks(target))) {
			if(neighbor == curTile) {
				continue;
			}
			if(AIMap.DistanceManhattan(parTile,neighbor)==1) {
				//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" true");
				return true;
			}
		}*/
		//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" false");
		return false;
	}

	function _PermitedDiagonalOffset(track) {
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

	function _Neighbours(self, path, cur_node) {
		//local counter = PerformanceCounter.Start("Neighbours");
		local result = RailPathFinder.__Neighbours(self, path, cur_node);
		//counter.Stop();
		
		return result;
	}

	function __Neighbours(self, path, cur_node) {
		// cur_node == path.GetTile()である。別に渡す意味あるの？


		/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
		if (path.GetCost() >= self._max_cost) return [];
		
		local tiles = [];
		local offsets = HgTile.DIR4Index;
		local par = path.GetParent();
		local par_tile = par!=null ? par.GetTile() : null;
		local underBridge = false;
		local goalTiles = self._GetGoalTiles(cur_node);
		local goal2 = goalTiles != null ? goalTiles[1] : null;
		if(par != null) {
			if(par.GetTile() == cur_node) {
				HgLog.Error("par.GetTile() == cur_node:" + HgTile(cur_node));
			}
		}
		
		local fork = false;
		if (AITile.HasTransportType(cur_node, AITile.TRANSPORT_RAIL) && AICompany.IsMine(AITile.GetOwner(cur_node))) {
			local p = par;
			for(local i=0; p!=null && i<self._goalStartTileLen-1; i++) {
				p = p.GetParent();
			}
			if(goal2 != null || p==null) { // start or goal tile
				fork = true;
			} else if(BuildedPath.Contains(cur_node)) {
				if(!HgTile.IsDiagonalTrack(AIRail.GetRailTracks(cur_node))) {
					if(!self._CanChangeBridge(path, cur_node)) {
						return [];
					}
					//HgLog.Info("_CanChangeBridge:"+HgTile(cur_node));
					underBridge = true;
				} else {
					if(self._reverseTiles != null && self._reverseTiles.rawin(cur_node)) {
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
		} else if (par != null && AIMap.DistanceManhattan(cur_node, par_tile) > 1) {
			local other_end = par_tile;
			local dir = (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
			local next_tile = cur_node + dir;
	//		tiles.push([next_tile, 1]);
			//HgLog.Info("DistanceManhattan > 1 isBuildableSea:" + isBuildableSea + " "+ HgTile(cur_node) + " next_tile:"+HgTile(next_tile));
			if(path.mode != null && path.mode instanceof RailPathFinder.Underground) {
				tiles.push([next_tile, self._GetDirection(other_end, cur_node, next_tile, true), par.mode]);
			} else {
				foreach (offset in offsets) {
					if (self._BuildRail(cur_node, next_tile, next_tile + offset)) {
						tiles.push([next_tile, self._GetDirection(other_end, cur_node, next_tile, true)]);
					}
				}
			}
		} else {
			// [parpar]-<tunnel>-[par(PM_UNDERGROUND)][cur(slope)][next]
			if(par != null && par.mode != null && par.mode instanceof RailPathFinder.Underground) {
				local next_tile = cur_node + (cur_node - par_tile);
				if (self._BuildRail(par_tile, cur_node, next_tile)) {
					//HgLog.Warning("next underGround:"+HgTile(par_tile)+"-"+HgTile(cur_node)+"-"+HgTile(next_tile));
					tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, false)]);
				}
				return tiles;
			}
			
			/* Check all tiles adjacent to the current tile. */
			foreach (offset in offsets) {
				local next_tile = cur_node + offset;
				/* Don't turn back */
				if (par != null && next_tile == par_tile) continue;
				/* Disallow 90 degree turns */
				if (par != null && par.GetParent() != null &&
					next_tile - cur_node == par.GetParent().GetTile() - par_tile) continue;
				if (par != null && par.GetParent() == null &&
					self._IsInclude90DegreeTrack(par_tile, next_tile, cur_node)) continue;			
				/* We add them to the to the neighbours-list if we can build a rail to
				 *  them and no rail exists there. */
				if (par == null 
						|| (goal2 == null && self._BuildRail(par_tile, cur_node, next_tile))
						//分岐の場合。信号、或いは通行中の列車のせいでBuildRailが失敗するがスロープじゃなければ成功
						|| (fork && goal2==null && !RailPathFinder.AreTilesConnectedAndMine(par_tile, cur_node, next_tile)
							&& (!self._IsSlopedRail(next_tile, cur_node, cur_node + (cur_node-next_tile)) || AITile.IsSeaTile(next_tile)))
						|| (underBridge && self._IsSlopedRail(par_tile, cur_node, next_tile)) // 橋の下の垂直方向スロープは成功
						|| (goal2 == next_tile 
							&& (RailPathFinder.AreTilesConnectedAndMine(par_tile, cur_node, next_tile) 
								|| self._BuildRail(par_tile, cur_node, next_tile)
								//ゴールが分岐の場合も信号、或いは通行中の列車のせいでBuildRailが失敗するがスロープじゃなければ成功
								|| (fork && !self._IsSlopedRail(next_tile, cur_node, cur_node + (cur_node-next_tile))))
							&& !self._IsInclude90DegreeTrack(next_tile, par_tile, cur_node))) {
					if (par != null) {
						tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, false)]);
					} else {
						tiles.push([next_tile, self._GetDirection(null, cur_node, next_tile, false)]);
					}
				}
				/*
				if(debug) {
					if(goal2 == next_tile) {
						HgLog.Warning("goal2 == next_tile:"+HgTile.GetTilesString([par_tile, cur_node, next_tile])
							+" "+RailPathFinder.AreTilesConnectedAndMine(par_tile, cur_node, next_tile)
							+" "+self._BuildRail(par_tile, cur_node, next_tile)
							+" "+self._IsInclude90DegreeTrack(next_tile, par_tile, cur_node));
					}
				}*/
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

	function _IsBuildableSea(tile, next_tile) {
		return ( AITile.IsSeaTile(tile) || (AITile.IsCoastTile(tile) && AITile.IsBuildable(tile) && AITile.GetMaxHeight(tile) <= 1/*steep slopeを避ける*/) )
			&& _RaiseAtWater(tile,next_tile);
	}

	function _BuildRail(p1,p2,p3) {
		if(AIRail.BuildRail(p1,p2,p3)) {
			return true;
		}
		if(_can_build_water && _IsBuildableSea(p2, p3) && p1 != p3) {
			return true;
		}
		if(AIError.GetLastError() != AIError.ERR_AREA_NOT_CLEAR) {
			return false;
		}
		local r = CanDemolishRail(p2);
		if(r) {
			HgLog.Info("CanDemolishRail(RailPathFinder::_BuildRail):"+HgTile(p2));
		}
		return r;
	}

	function CanDemolishRail(p) {
		if(!AICompany.IsMine(AITile.GetOwner(p))) {
			return false;
		}
		if(AIRail.IsRailTile(p) || AIBridge.IsBridgeTile(p) || AITunnel.IsTunnelTile(p)) {
			return !BuildedPath.Contains(p);
		}
		return false;
	}
	
	function _RaiseAtWater(t0,t1) {
		if(!AIMap.IsValidTile(t1)) {
			return false;
		}
		if(AIMap.DistanceFromEdge (t1) <= 2) {
			return false;
		}
		if(HogeAI.Get().IsAvoidRemovingWater()) {
			return false;
		}
		local boundCorner = HgTile.GetCorners( HgTile(t0).GetDirection(HgTile(t1)) );
		if(AITile.GetCornerHeight(t0,boundCorner[0]) == 0 && AITile.GetCornerHeight(t0,boundCorner[1]) == 0) {
			local result = AITile.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[0])) || AITile.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[1]));
			return result;
		}
		return true;
	}

	function _CheckDirection(tile, existing_direction, new_direction, self) {
		return false;
	}

	function _dir(from, to) {
		if (from - to == 1) return 0;
		if (from - to == -1) return 1;
		if (from - to == AIMap.GetMapSizeX()) return 2;
		if (from - to == -AIMap.GetMapSizeX()) return 3;
		throw("Shouldn't come here in _dir");
	}

	function _GetDirection(pre_from, from, to, is_bridge) {
		if (is_bridge) {
			local d = (from - to) / AIMap.DistanceManhattan(from,to);
			if (d == 1) return 1;
			if (d == -1) return 2;
			if (d == AIMap.GetMapSizeX()) return 4;
			if (d == -AIMap.GetMapSizeX()) return 8;
		}
		return 1 << (4 + (pre_from == null ? 0 : 4 * this._dir(pre_from, from)) + this._dir(from, to));
	}

	function _IsDiagonalDirection(direction) {
		local n = direction >> 4;
		local n1 = n % 16;
		local n2 = n / 16;
		if(n1 <=2 && 2 < n2) {
			return true;
		}
		if(2 < n1 && n2 <= 2) {
			return true;
		}
		return false;
	}

	function _BuildTunnelEntrance( A0, A1, A2, L, testMode = true ) {
		if(!testMode || (AITile.IsBuildable(A0) && AITile.IsBuildable(A1) && AITile.IsBuildable(A2))) {
			
			local maxa0a1 = HgTile.GetBoundMaxHeight(A0, A1);
			/*local m = AITile.GetMinHeight(A2);
			if(maxa0a1 <= m - 1) {
				if(testMode) return false;
				HgLog.Warning("maxa0a1 <= m - 1 "+maxa0a1+" "+m+" "+HgTile(A0)+" "+HgTile(A1)+" "+HgTile(A2));
			}*/
			if(L < maxa0a1) {
				if(testMode) return false;
				HgLog.Warning("L < maxa0a1 "+L+" "+maxa0a1+" "+HgTile(A0)+" "+HgTile(A1)+" "+HgTile(A2));
			}
			/*local l = AITile.GetMaxHeight(A2);
			if(l==m) {
				if(!(L-1 == l || L == l)) {
					if(testMode) return false;
					HgLog.Warning("!(L-1 == l || L == l) "+L+" "+l+" "+HgTile(A0)+" "+HgTile(A1)+" "+HgTile(A2));
				}
			} else {
				if(!(L==l && L-1==m)) {
					if(testMode) return false;
					HgLog.Warning("!(L==l && L-1==m) "+L+" "+l+" "+HgTile(A0)+" "+HgTile(A1)+" "+HgTile(A2));
				}
			}*/
			local A3 = A2 + (A2 - A1);
			/*
			if(!(AITile.GetMaxHeight(A3) <= L+1)) {
				if(testMode) return false;
				HgLog.Warning("!(AITile.GetMaxHeight(A3) <= L+1) "+L+" "+AITile.GetMaxHeight(A3)+" "+HgTile(A0)+" "+HgTile(A1)+" "+HgTile(A2)+" "+HgTile(A3));
			}*/
			if(!HgTile.LevelBound(A2,A3,L) || !HgTile.LevelBound(A1,A2,L-1)) {
				if(!testMode) HgLog.Warning("LevelBound failed L:"+L+" "+HgTile(A0)+" "+HgTile(A1)+" "+HgTile(A2)+" "+HgTile(A3));
				return false;
			}
			return true;
		}
		return false;

	}

	function _GetUndergroundTunnel(A0, A1, A2, L = null, b2 = null) {
		//A0:par A1:slope A2:tunnel_start L:max_tunnel_start_height
		if(AIMap.DistanceManhattan( A0, A1 ) != 1) {
			return [];
		}
		local dir = A2 - A1;
		if(A1 - A0 != dir) {
			return [];
		}
		if(L == null) {
			local m = AITile.GetMinHeight(A2);
			local l = AITile.GetMaxHeight(A2);
			if(l==m) {
				local result = _GetUndergroundTunnel(A0, A1, A2, l);
				if(result.len() >= 1) {
					return result;
				}
				return _GetUndergroundTunnel(A0, A1, A2, l+1);
			} else if(l == m+2) { // tight slope
				L = m+1;
			} else {
				L = l;
			}
		}
		if(!_BuildTunnelEntrance(A0, A1, A2, L)) {
			return [];
		}
		local result = [];
		local significant = false;
		for (local i = 2; i <= this._max_tunnel_length; i++) {
			local C = A2 + (i-1) * dir;
			if(AITile.IsSeaTile(C) || AITile.IsCoastTile(C)) {
				return result;
			}
			if(!AITile.IsBuildable(C) || AITile.GetMaxHeight(C) >= L + 1) {
				significant = true;
			}
			local B2 = A2 + i * dir;
			local B1 = B2 + dir;
			local B0 = B1 + dir;
			local entrance = false;
			if(b2 == null) {
				if(significant && _BuildTunnelEntrance(B0, B1, B2, L)) {
					if(_IsCollideTunnel(A2 ,B2, L)) {
						return result;
					}
					//HgLog.Info("_GetUndergroundTunnel "+HgTile(A2)+"-"+HgTile(B2)+" L:"+L);
					result.push([B2, _GetDirection(A0, A1, A2, true), RailPathFinder.Underground(L)]);
					entrance = true;
					//return result;
				}
			} else if(b2 == B2){
				if(_BuildTunnelEntrance(B0, B1, B2, L)) {
					//HgLog.Info("_GetUndergroundTunnel "+HgTile(A2)+"-"+HgTile(B2)+" L:"+L);
					result.push([B2, _GetDirection(A0, A1, A2, true), RailPathFinder.Underground(L)]);
					return result;
				}
			}
			if(AITile.GetMinHeight(B2) < L && !HgTile.LevelBound(B2,B1,L)) {
				return result;
			}
			if(entrance) {
				if(isOutward) {
					local revDir = _GetRevDir(A1,A0);
					if(_BuildTunnelEntrance(B0+revDir, B1+revDir, B2+revDir, L)) {
						return result;
					}
				} else {
					return result;
				}
			}
		}
		return result;
	}
		
	function _GetTunnelsBridges(par, last_node, cur_node) {
		local tiles = [];
		
		local dir = cur_node - last_node;
		local next = cur_node + dir;
		local revDir = isOutward ? _GetRevDir(next,cur_node) : null;
		
		if(par.GetParent()!=null) {
			local last_node2 = par.GetParent().GetTile();

			if(!AITile.IsBuildable(cur_node)) {
				return [];
			}
			
			if(dir == last_node - last_node2 
					&& ( !AITile.IsBuildable(next) 
						|| AITile.GetMinHeight(last_node2)+1 < AITile.GetMaxHeight(next) 
						|| _IsTunnelNext(cur_node)) 
						|| (isOutward && !AITile.IsBuildable(next + revDir) ) 
					&& !AITile.IsSeaTile(next)
					&& !_CanBuildTunnel(next)
					&& !_CanBuildBridge(cur_node,_GetNextBridgeEnd(cur_node,last_node),last_node)/*隣が橋の場合、なるべく橋を使う(景観)*/) {
				// [last_node2(pre)][last_node(slope)] [cur_node(tunnel_start)] [next]
				tiles.extend(_GetUndergroundTunnel(last_node2, last_node, cur_node));
			}
		}
		local bridge_dir = _GetDirection(par.GetTile(), cur_node, next, true);
		
		local significant = false;
		local level = AITile.GetMaxHeight(cur_node);
		if((!AITile.IsBuildable(next) && !HogeAI.IsPurchasedLand(next)) || level > AITile.GetMaxHeight(next)
				|| (isOutward && !AITile.IsBuildable(next + revDir))) {
			for (local i = 2; i < this._max_bridge_length; i++) {
				local bridge_list = AIBridgeList_Length(i + 1);
				local checkTile = cur_node + (i-1) * dir;
				if(!significant && (!AITile.IsBuildable(checkTile) || AITile.GetMaxHeight(checkTile) <= level - 2 /*|| AITile.GetMaxHeight(checkTile) == level平地に奇妙な橋が出現する*/)) {
					significant = true;
				}
				local target = cur_node + i * dir;
				if (significant && !bridge_list.IsEmpty() && RailPathFinder.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), cur_node, target)) {
					tiles.push([target, bridge_dir]);
				}
			}
			if(_can_build_water && _IsBuildableSea(cur_node, next)) {
				for (local i = 2; i < this._max_bridge_length; i++) {
					local checkTile = cur_node + (i-1) * dir;
					if(!((AITile.HasTransportType(checkTile, AITile.TRANSPORT_RAIL) || AITile.HasTransportType(checkTile, AITile.TRANSPORT_ROAD))
							&& AITile.GetMaxHeight(checkTile) == 1 && !_IsUnderBridge(checkTile) 
							&& (!AIBridge.IsBridgeTile(checkTile) || _IsFlatBridge(checkTile)))) {
						break;
					}
					if(AITile.IsStationTile(checkTile)) {
						break;
					}
					local target = cur_node + i * dir;
					if(_RaiseAtWater(checkTile, target) && _IsBuildableSea(target, target + dir)) {
						local bridge_list = AIBridgeList_Length(i + 1);
						if (!bridge_list.IsEmpty()) {
							tiles.push([target, bridge_dir, RailPathFinder.BridgeOnWater()]);
						}
					}
				}
			}
		}
		local slope = AITile.GetSlope(cur_node);
		if (slope != AITile.SLOPE_SW && slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE && slope != AITile.SLOPE_NE) {
			return tiles;
		}
		if(AITile.IsCoastTile(cur_node)) { //埋め立てられてトンネル作成に失敗するのを回避する
			return tiles;
		}
		
		local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_node);
		if (!AIMap.IsValidTile(other_tunnel_end)) return tiles;

		local tunnel_length = AIMap.DistanceManhattan(cur_node, other_tunnel_end);
		local prev_tile = cur_node + (cur_node - other_tunnel_end) / tunnel_length;
		if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && !AITile.IsCoastTile(other_tunnel_end) && tunnel_length >= 2 &&
				prev_tile == last_node && tunnel_length < _max_tunnel_length && RailPathFinder.BuildTunnel(AIVehicle.VT_RAIL, cur_node)) {
			//HgLog.Info("GetOtherTunnelEnd cur_node:" + HgTile(cur_node) + " target:"+HgTile(other_tunnel_end));
			tiles.push([other_tunnel_end, bridge_dir]);
		}
		return tiles;
	}

	function BuildBridge(a,b,c,d) {
		return BuildUtils.CheckCost(function():(a,b,c,d){return AIBridge.BuildBridge(a,b,c,d);});
	}

	function BuildTunnel(a,b) {
		return BuildUtils.CheckCost(function():(a,b){return AITunnel.BuildTunnel(a,b);});
	}

	function _IsTunnelNext(tile) {
		foreach(d in HgTile.DIR4Index) {
			if(AITunnel.IsTunnelTile(tile+d)) {
				return true;
			}
		}
		return false;
	}

	function _GetNextBridgeEnd(tile,prev) {
		local revDir = _GetRevDir(tile,prev);
		return AIBridge.GetOtherBridgeEnd(tile + revDir);
	}

	function _CanBuildBridge(start,revEnd,prev) {
		if(!AIMap.IsValidTile(revEnd)) {
			return false;
		}
		local revDir = _GetRevDir(start,prev);
		local end = revEnd - revDir;
		local length = AIMap.DistanceManhattan(start,end);
		if((end - start) / length != start - prev) {
			return false;
		}
		local bridge_list = AIBridgeList_Length(length + 1);
		return RailPathFinder.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), start, end);
	}

	function _CanBuildTunnel(tile) {
		local tunnelEnd = AITunnel.GetOtherTunnelEnd(tile);
		if(!AIMap.IsValidTile(tunnelEnd)) {
			return false;
		}
		return AIMap.DistanceManhattan(tunnelEnd,tile) < _max_tunnel_length;
	}

	function _IsSlopedRail(start, middle, end) {
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

	function _IsFlatBridge(start) {
		local end = AIBridge.GetOtherBridgeEnd(start);
		local dir = (end - start) / AIMap.DistanceManhattan(start,end);
		local h1 = AITile.GetMaxHeight(start);
		local h2 = AITile.GetMaxHeight(start + dir);
		return h2 < h1;
	}

	static function FindStraightLines(tiles, length) {
		local result = [];
		local past = [];
		foreach(t in tiles) {
			past.insert(0,t);
			if(past.len()>length) {
				past.pop();
			}
			if(past.len()==length) {
				local tracks = AIRail.GetRailTracks(past[0]);
				if(!RailPathFinder.IsStraightTrack(tracks)) {
					continue;
				}
				local fail = false;
				for(local i=1; i<length; i++) {
					if(AIMap.DistanceManhattan(past[i-1],past[i])!=1 || AIRail.GetRailTracks(past[i]) != tracks) {
						fail = true;
						break;
					}
				}
				if(fail) continue;
				result.push(clone past);
			}
		}
		return result;
	}
	
	static function IsStraightTrack(tracks) {
		return tracks ==  AIRail.RAILTRACK_NE_SW || tracks == AIRail.RAILTRACK_NW_SE;
	}
	
	static function IsDoubleDiagonalTrack(track) {
		if(track == (AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE)) {
			return true;
		}
		if(track == (AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_SE)) {
			return true;
		}
		return false;
	}
	
	static function SetRevOkTiles(revOk, tiles) {
		foreach(index,t in tiles) {
			if(index==0) continue;
			//HgLog.Warning("SetRevOk "+ HgTile(t)+" "+HgTile(tiles[index-1]));
			local key = RailPathFinder.Get2TileKey(t,tiles[index-1]);
			revOk.rawset(key,key);
		}
	}
	
	static function Get2TileKey(t1,t2) {
		local minT = min(t1,t2);
		local maxT = max(t1,t2);
		return minT+"-"+maxT;
	}
}

class RailPathFinder.Underground {
	level = null;

	constructor(level) {
		this.level = level;
	}
	
	function Load(data) {
		return RailPathFinder.Underground(data.level);
	}
	
	function Save() {
		return {name="Underground",level=level};
	}
}
Serializer.nameClass.Underground <- RailPathFinder.Underground;

class RailPathFinder.BridgeOnWater {
	function Load(data) {
		return RailPathFinder.BridgeOnWater();
	}
	
	function Save() {
		return {name="BridgeOnWater"};
	}
}
Serializer.nameClass.BridgeOnWater <- RailPathFinder.BridgeOnWater;

class Pathfinding {
	
	industries = null;
	failed = null;
	
	constructor() {
		industries = [];
		failed = false;
	}
	
	function OnPathFindingInterval() {
		if(failed) {
			return false;
		}
		HogeAI.DoInterval();
		return true;
	}

	function OnIndustoryClose(industry) {
		foreach(i in industries) {
			if(i == industry) {
				failed = true;
			}
		}
	}
}
