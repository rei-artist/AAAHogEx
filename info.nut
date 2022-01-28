class HogeAI extends AIInfo 
 {
   function GetAuthor()      { return "Rei Ishibashi"; }
   function GetName()        { return "AAAHogEx"; }
   function GetDescription() { return "AAAHogEx understands the industry chain and plans the most profitable routes. Therefore, it is the most profitable AI even for complex NewGRFs such as FIRS and ECS."; }
   function GetVersion()     { return 1; }
   function GetDate()        { return "2022-01-27"; }
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
