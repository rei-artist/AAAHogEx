﻿class HogeAI extends AIInfo {

   function GetAuthor()      { return "Rei Ishibashi"; }
   function GetName()        { return "AAAHogEx"; }
   function GetDescription() { return "AAAHogEx is a highly profitable AI that offers a fun and challenging experience even for experienced players. It supports various types of transportation, including trains, trams, cars, trucks, ships, and airplanes. It is also compatible with most major mods. For a beginner-friendly setup guide, please visit the website below."; }
   function GetVersion()     { return 114; } // main.nutも変更必要
   function MinVersionToLoad() { return 105; }
   function GetDate()        { return "2025-06-15"; }
   function CreateInstance() { return "HogeAI"; }
   function GetShortName()   { return "HOGE"; }
   function GetAPIVersion()    { return "14"; }
   
   function GetSettings() {
		AddSetting({name = "usable_cargos",
			description = "Types of cargo usable", 
			//default_value = 3,
			easy_value = 3, 
			medium_value = 3, 
			hard_value = 3, 
			custom_value = 3, 
			min_value = 1, 
			max_value = 3,
			flags = CONFIG_INGAME});			

		AddLabels("usable_cargos",
			{_1 = "Pax and mail only", _2="Freight only", _3="All"});


		AddSetting({name = "disable_veh_train",
			description = "Disable trains", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "disable_veh_roadveh",
			description = "Disable road vehicles", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
			
		AddSetting({name = "disable_veh_tram",
			description = "Disable trams", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
			
		AddSetting({name = "disable_veh_ship",
			description = "Disable ships", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
			
		AddSetting({name = "disable_veh_aircraft",
			description = "Disable aircrafts", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});


		AddSetting({name = "Avoid removing water",
			description = "Avoid removing water (To prevent this AI from blocking the path of other players'ships)", 
			//default_value = 1,
			easy_value = 1, 
			medium_value = 1, 
			hard_value = 0, 
			custom_value = 1, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "IsAvoidSecondaryIndustryStealing",
			description = "Avoid secondary industry stealing",
			//default_value = 0,
			easy_value = 1, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});


		AddSetting({name = "IsAvoidExtendCoverageAreaInTowns",
			description = "Avoid joining stations solely to extend coverage area in towns", 
			//default_value = 0,
			easy_value = 1, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "IsPreferReusingExistingRoads",
			description = "Prefer reusing existing roads. Before building new roads, the AI checks whether existing roads can be used. This helps prevent the map from becoming cluttered with too many roads.", 
			//default_value = 0,
			easy_value = 1, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
			
		AddSetting({name = "IsForceToHandleFright",
			description = "Force to start handling the freight, once the funds are stabilized (To prevent this AI from sometimes only dealing with passengers and mails as a result of profit-first calculations)", 
			//default_value = 0,
			easy_value = 1, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "disable_prefixed_station_name",
			description = "Disable prefixed station names", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

				 
		AddSetting({name = "IsDebug",
			description = "Debug", 
			//default_value = 0,
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
	}
 }
 
 RegisterAI(HogeAI());
