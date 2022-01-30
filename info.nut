class HogeAI extends AIInfo 
 {
   function GetAuthor()      { return "Rei Ishibashi"; }
   function GetName()        { return "AAAHogEx"; }
   function GetDescription() { return "AAAHogEx is a highly competitive AI. This AI designs transportation routes based on the supply and demand of the map. Therefore, it works well in NewGRF such as FIRS, ECS, and YETI where complex industrial chains are required."; }
   function GetVersion()     { return 1; }
   function GetDate()        { return "2022-01-30"; }
   function CreateInstance() { return "HogeAI"; }
   function GetShortName()   { return "HOGE"; }
   function GetAPIVersion()    { return "1.2"; }
   
   function GetSettings() 
   {
     AddSetting({name = "Avoid removing water",
                 description = "Avoid removing water (To prevent this AI from blocking the path of other players' ship)", 
                 easy_value = 1, 
                 medium_value = 0, 
                 hard_value = 0, 
                 custom_value = 0, 
                 flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
     
     AddSetting({name = "IsForceToHandleFright",
                 description = "Force to start handling the fright, once the funds are stabilized (To prevent this AI from sometimes only dealing with passengers and mails as a result of profit-first calculations)", 
                 easy_value = 1, 
                 medium_value = 1, 
                 hard_value = 0, 
                 custom_value = 0, 
                 flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
   }
 }
 
 RegisterAI(HogeAI());
