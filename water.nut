
class WaterRoute extends Route {
	
	static function ChooseEngineCargo(cargo, distance) {
		local roiBase = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 500000;
		local enginelist = AIEngineList(AIVehicle.VT_WATER);
		enginelist.Valuate(AIEngine.CanRefitCargo, cargo);
		enginelist.KeepValue(1);
		enginelist.Valuate(function(e):(distance,cargo,roiBase) {
			local capacity = AIEngine.GetCapacity(e);
			local income = HogeAI.GetCargoIncome(distance, cargo, AIEngine.GetMaxSpeed(e), capacity * 30 / 150) 
				* capacity * (100+AIEngine.GetReliability (e)) / 200 - AIEngine.GetRunningCost(e);
			if(roiBase) {
				return income * 100 / AIEngine.GetPrice(e);
			} else {
				return income;
			}
		});
		enginelist.KeepAboveValue(0);
		enginelist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		if (enginelist.Count() == 0) return null;
		return enginelist.Begin();
	}
}
