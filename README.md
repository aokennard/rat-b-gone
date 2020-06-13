# rat-b-gone
A SourcePawn plugin that verifies connecting players play in RGL / ETF2L TF2 leagues


## Install
This uses Metamod/SourceMod, a SourcePawn plugin, and Python 3. It was designed and tested on Ubuntu 16.04.

### Python 3
This uses Selenium's Python module, the other libraries are standard.  
Install with:  
`pip install -r requirements.txt` or `pip3 install -r requirements.txt` if using both versions of pip.

Additionally, this (currently) uses ChromeDriver on top of Selenium, so you will need to download:  
1. Google Chrome (if not currently downloaded)  
2. The appropriate ChromeDriver version (check version with: `google-chrome --version`), likely at [here](https://sites.google.com/a/chromium.org/chromedriver/downloads)  
Put ChromeDriver in your PATH so that `which` can recognize your installation.

### SourcePawn

You need [Metamod](http://wiki.alliedmods.net/Installing_Metamod:Source) and [SourceMod](http://wiki.alliedmods.net/Installing_SourceMod) installed first for this plugin to work.  
Additionally, this uses [System2](https://github.com/dordnung/System2) as a dependency, so you also need that.

Download this repo and extract to your addons/sourcemod folder. I assume you have the SourcePawn compiler (`./spcomp`) in addons/sourcemod.  
Finally, `make` in order to build the plugin.

## Usage

This plugin restricts who can join a server based on a few variables.   
`plw_version`: Prints the plugin version.  
`plw_enable`: Whether or not to use the whitelist  
`plw_leagues`: What leagues (RGL, ETF2L) to consider players in to be able to join.  
`plw_divs_(rgl/etf2l)`: What division players are allowed into the server. This is all by default, and considered first before other filters.  
`plw_mode`: Filters who can join the server based on various 'modes': team-only, scrim-only, team-only, combinations of these, or all.  
`plw_(scrim/team/match)id`: The ID of an RGL team, to be used for `plw_mode`'s, allowing only certain teams of players into the server.  
`plw_fakepw`: In order to allow ringers to join (in case of scrim/team/match restrictions), they need to use a 'password' - due to protected variables not being exposed (client's `password`), we use another variable: `cl_team`.

## WIP

Support for specific gamemodes (6s, HL, etc)
STV verification
More ETF2L testing
Support for different webdrivers