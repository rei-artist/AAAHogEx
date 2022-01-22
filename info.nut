class HogeAI extends AIInfo 
 {
   function GetAuthor()      { return "Rei Ishibashi"; }
   function GetName()        { return "AAAHogEx"; }
   function GetDescription() { return "The most profitable AI in the world."; }
   function GetVersion()     { return 1; }
   function GetDate()        { return "2021-09-29"; }
   function CreateInstance() { return "HogeAI"; }
   function GetShortName()   { return "HOGE"; }
   function GetAPIVersion()    { return "1.2"; }
   
   function GetSettings() 
   {
     AddSetting({name = "Avoid removing water",
                 description = "Avoid removing water", 
                 easy_value = 1, 
                 medium_value = 0, 
                 hard_value = 0, 
                 custom_value = 0, 
                 flags = AICONFIG_BOOLEAN + CONFIG_INGAME});
                 
   }
 }
 
 RegisterAI(HogeAI());
