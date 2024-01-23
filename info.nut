﻿class HogeAI extends AIInfo 
 {
   function GetAuthor()      { return "Rei Ishibashi"; }
   function GetName()        { return "AAAHogEx"; }
   function GetDescription() { return "AAAHogEx is a highly competitive AI. This AI designs transportation routes based on the supply and demand of the map. Therefore, it works well in NewGRF such as FIRS, ECS, and YETI where complex industrial chains are required."; }
   function GetVersion()     { return 58; }
   function MinVersionToLoad() { return 52; }
   function GetDate()        { return "2024-01-23"; }
   function CreateInstance() { return "HogeAI"; }
   function GetShortName()   { return "HOGE"; }
   function GetAPIVersion()    { return "1.3"; }
   
   function GetSettings() {
		AddSetting({name = "Avoid removing water",
			description = "Avoid removing water (To prevent this AI from blocking the path of other players' ship)", 
			easy_value = 1, 
			medium_value = 1, 
			hard_value = 0, 
			custom_value = 1, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "IsForceToHandleFright",
			description = "Force to start handling the fright, once the funds are stabilized (To prevent this AI from sometimes only dealing with passengers and mails as a result of profit-first calculations)", 
			easy_value = 1, 
			medium_value = 1, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "IsAvoidSecondaryIndustryStealing",
			description = "Avoid secondary industry stealing", 
			easy_value = 1, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "many_types_of_freight_as_possible",
			description = "Put as many different types of freight as possible into one train", 
			easy_value = 1, 
			medium_value = 1, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME}); 
					
		AddSetting({name = "disable_veh_train",
			description = "Disable trains", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

		AddSetting({name = "disable_veh_roadveh",
			description = "Disable road vehicles", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
		AddSetting({name = "disable_veh_tram",
			description = "Disable trams", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
		AddSetting({name = "disable_veh_ship",
			description = "Disable ships", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
			
		AddSetting({name = "disable_veh_aircraft",
			description = "Disable aircrafts", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});


		AddSetting({name = "usable_cargos",
			description = "Types of cargo usable", 
			easy_value = 3, 
			medium_value = 3, 
			hard_value = 3, 
			custom_value = 3, 
			min_value = 1, 
			max_value = 3,
			flags = CONFIG_INGAME});			

		AddLabels("usable_cargos",
			{_1 = "Pax and mail only", _2="Freight only", _3="All"});

		AddSetting({name = "disable_prefixed_station_name",
			description = "Disable prefixed station names", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});

				 
		AddSetting({name = "IsDebug",
			description = "Debug", 
			easy_value = 0, 
			medium_value = 0, 
			hard_value = 0, 
			custom_value = 0, 
			flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
   }
 }
 
 RegisterAI(HogeAI());
