# rat-b-gone
A SourcePawn plugin that verifies connecting players play in RGL / ETF2L TF2 leagues


## Install
This uses Metamod/SourceMod, a SourcePawn plugin, and Python 3. It was designed and tested on Ubuntu 16.04.

### Python 3
This uses Python 3's BeautifulSoup, lxml, and Flask module, the other libraries are standard.  
Note: you only need to install these if you intend on having a server which hosts server/app.py.  
Install with:  
`pip install -r requirements.txt` or `pip3 install -r requirements.txt` if using both versions of pip.
The plugin expects `python3` in your PATH.

### SourcePawn

You need [Metamod](http://wiki.alliedmods.net/Installing_Metamod:Source) and [SourceMod](http://wiki.alliedmods.net/Installing_SourceMod) installed first for this plugin to work.  
Additionally, this uses [cURL](https://forums.alliedmods.net/showthread.php?t=152216) as a dependency.

Download this repo and run the relevant OS's install script.

## Usage

This plugin restricts who can join a server based on a few variables.   
- `plw_version`: Prints the plugin version.  
- `plw_enable`: Whether or not to use the whitelist  
- `plw_leagues`: What leagues (RGL, ETF2L) to consider players in to be able to join.  
- `plw_gamemode`: What gamemode (6s or HL) to consider players for  
- `plw_join_output`: Whether or not to let the plugin print join messages to chat  
- `plw_chat_output`: Whether or not to let the plugin print to server chat  
- `plw_kick_output`: Whether or not to let the plugin print 'Kicked from server' messages to server chat  
- `plw_allow_banned`: Whether to allow league banned players into the server. Note, because they aren't guaranteed to have a team / div, they bypass `plw_mode` and `plw_divs_(rgl/etf2l)` settings.   
- `plw_divs_(rgl/etf2l)`: What division players are allowed into the server. This is all by default, and considered first before other filters.  
- `plw_mode`: Filters who can join the server based on various 'modes': team-only, scrim-only, team-only, combinations of these, or all.  
- `plw_(scrim/team/match)id`: The ID of an RGL team, to be used for `plw_mode`'s, allowing only certain teams of players into the server.  
- `plw_fakepw`: In order to allow ringers to join (in case of scrim/team/match restrictions), they need to use a 'password' - due to protected variables not being exposed (client's `password`), we use another variable: `cl_team`.
- `plw_pugmode`: Disables whitelist (assumes not everyone in RGL), sets a default `sv_password`  
- `plw_leaguechecker_url`: (Testing) the URL to point to a server which resolves a steamid for RGL/ETF2L via cURL
- `plw_use_league_alias`: (Testing) Force players in server to use competitive league alias

## WIP

Verify installer
More support + testing for specific gamemodes (6s, HL, etc) + multiple gamemode support at same time
More ETF2L testing (thanks Zesty!)  