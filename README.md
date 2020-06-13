# rat-b-gone
A SourcePawn plugin that verifies connecting players play in RGL's TF2 league


## install
This uses a few SourcePawn plugins, and Python 3. It was designed and tested on Ubuntu 16.04.

### Python 3
This uses Selenium's Python module, the other libraries are standard. Install with:
`pip install -r requirements.txt`
Or `pip3` if using both versions of pip.

Additionally, this (currently) uses ChromeDriver on top of Selenium, so you will need to download:
1. Google Chrome (if not currently downloaded)
2. The appropriate ChromeDriver version (check version with: `google-chrome --version`), likely at [here](https://sites.google.com/a/chromium.org/chromedriver/downloads)
Put ChromeDriver in your PATH so that `which` can recognize your installation.

### SourcePawn

You need [Metamod](http://wiki.alliedmods.net/Installing_Metamod:Source) and [SourceMod](http://wiki.alliedmods.net/Installing_SourceMod) installed first for this plugin to work. 
Additionally, this uses [System2](https://github.com/dordnung/System2) as a dependency, so you also need that.

Download this repo and extract to your addons/sourcemod folder. I assume you have the SourcePawn compiler (`./spcomp`) in addons/sourcemod.
Finally, `make` in order to build the plugin.

## use

good question