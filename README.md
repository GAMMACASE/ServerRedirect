# ServerRedirect
SourceMod plugin that allows players to see and connect to other servers.

# About
This plugin provides servers list menu, where you can add your servers, so players can be redirected to them while being on server. You can redirect to **any** server you'd like, servers you redirect to **doesn't require any fixes installed** or anything like that. Also this plugin comes with A2S queries, but to actually use it you would need an optional requirement (see **Requirements**), after that you'll see real time statistics for every server you added. This plugin also provides some api (``addons/sourcemod/scripting/include/server_redirect.inc``) that you can use for your needs.

# Configuration
To add servers to servers menu use ``addons/sourcemod/configs/server_redirect.cfg`` file and add servers you'd like by following the description. After that take a look at convar file created after first plugin launch (``cfg/sourcemod/plugin.server_redirect.cfg``) and configure it to your liking by following provided description.

Note: If you don't see your servers in servers menu, make sure that config file in the right place under right name (``addons/sourcemod/configs/server_redirect.cfg``) and is configured properly.

# Requirements
* [Sourcemod 1.10;](https://www.sourcemod.net/downloads.php?branch=1.10-dev&all=1)
* [Dhooks with detour support;](https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589)
* [Socket (Optional).](https://github.com/JoinedSenses/sm-ext-socket)

# Special thanks
* To everyone in [SourceMod discord](https://discord.gg/HUc67zN) who was somehow related to csgo redirect method;

# Screenshots
Note: All servers were taken from server browser and selection was totaly random.

Servers list menu:

![screen1](https://i.imgur.com/lYSPQRK.png)

Server info menu (Shown when you chose server):

![screen2](https://i.imgur.com/MwrmeRM.png)

Server ad:

![screen3](https://imgur.com/EKCkk2W.png)
