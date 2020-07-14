# the sole purpose is to get (div, name, current team) from RGL
import sys
import os
import time
import shutil
import requests
try:
    from bs4 import BeautifulSoup
except ImportError:
    print("BeautifulSoup not found! Did you pip install it / the requirements?")
    print("Exiting with status 0 so all people are allowed instead of none")
    exit(0)

# 1 = hl, 2 = 6v
RGL_SEARCH_LEAGUE_TABLE = {"2" : "40", "7v7" : "1", "6v6NR" : "37", "1" : "24"}
RGL_LEAGUE_STRING_ID_MAP = {"Prolander" : "7v7", "NR Sixes" : "6v6NR", "Highlander" : "1", "Trad. Sixes" : "2"}
RGL_SEARCH_URL = "https://rgl.gg/Public/PlayerProfile.aspx?p={}&r={}"

'''
    Input: the div that contains all relevant player data content: name, team tables by gamemode, trophies
    Output: a pair of (user's name on the page, whether use is currently banned)
'''

def get_name_banstatus_from_div(div):
    try:
        timeline = div.find("h1")
        name_span = timeline.find(id="ContentPlaceHolder1_Main_lblPlayerName")
        # slightly improved ban verification
        ban = False
        div_banned = div.find(id="ContentPlaceHolder1_Main_divBanned")
        if div_banned and div_banned.find("h3") and div_banned.find("h3").text == "Player is banned from RGL":
            ban = True
        return name_span.text, ban
    # could just check if each return is None but that looks a bit worse
    except Exception:
        return None, None

'''
    Input: a string that contains relevant gamemode / league data
    The format I've observed is <gamemode type> - RGL - <region / gamemode specifics>
    This function is pretty catered to NA only HL/6s/Prolander, need to expand if I want to support more modes
    Output: the relevant identifier key in 'RGL_SEARCH_LEAGUE_TABLE' which uniquely identifies a gamemode
''' 

def get_gamemode_from_string(gamemode_str):
    
    gamemode, rgl, region = gamemode_str.split('-')
    gamemode = gamemode.rstrip()
    region = region.lstrip()

    # ignore one day cups or weird stuff - also TODO cleanup later

    if gamemode == "Prolander":
        if region == "North America":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    if gamemode == "Highlander":
        if region == "HL North America":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    if gamemode == "Trad. Sixes":
        if region == "NA Traditional Sixes":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    if gamemode == "NR Sixes":
        if region == "No Restriction Sixes":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    return None

'''
    Input: a table Tag structure, which contains information on one players history in that gamemode.
    Output: a pair of (the division of the most recent active team the player's on for table's gamemode, the id of said team)
'''

def get_div_teamid_from_table(table):
    division = None
    team_id = None
    try:
        # first is a header
        rows = table.find_all("tr")[1:] 
        # if it's green then it's active
        if rows[0].has_attr('style') and rows[0]['style'] == 'background-color: #B9DFCD':
            most_recent_cols = rows[0].find_all('td')
            # I think for now all I care about is the first one, but some stuff may be placeholders for later
            division = most_recent_cols[1].text.strip()
            # yikes but we're in a try-except
            team_id = most_recent_cols[2].find('a')['href'].split('?t=')[1]
    except Exception:
        pass

    return division, team_id

'''
    Input: from sys.argv:
            a connecting users steamid
            the gamemode we're checking for (currently only supporting 6s and HL)
    Output:
        a 3-tuple of (division of joining player, RGL alias, team id for gamemode we're looking for)
        alternatively: ("", RGL alias, "") when no team found
                       ("banned", RGL alias, "banned") on an RGL banned steamid
                       error messages when player not in RGL, alias not found, no teams for the gamemode we're looking for
'''


if __name__ == "__main__":
    # we spawned this process - we gave it these arguments guaranteed
    steamid = sys.argv[1]
    gamemode = sys.argv[2]

    if not os.path.exists("plwlog/"):
        os.mkdir("plwlog/")

    # get and parse the player's page
    request = requests.get(RGL_SEARCH_URL.format(steamid, RGL_SEARCH_LEAGUE_TABLE[gamemode]))
    soup = BeautifulSoup(request.content, features="lxml")

    div_head = soup.find("div", {"class":"col-sm-9"})
    if not div_head:
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} couldn't load div".format(steamid))
        print("Page malformed or edge case found for pages")
        exit(-1)
    div_name = div_head.find("div", {"class":"page-header text-center"})
    if not div_name:
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} couldn't load div".format(steamid))
        print("Page malformed or edge case found for pages")
        exit(-1)

    # verify they exist

    placeholder = div_head.find(id="ContentPlaceHolder1_Main_hMessage")
    if not placeholder or placeholder.text.lstrip() == "Player does not exist in RGL":
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} not in RGL".format(steamid))
        print("Player not found")
        exit(-1)

    name, ban_status = get_name_banstatus_from_div(div_name)
    if name == None:
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} name not found in RGL".format(steamid))
        print("Name not found")
        exit(-1)
    if ban_status:
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} found, is banned".format(steamid))
        print(",".join(["banned", name, "banned"]))
        exit(0)

    # h3, hr, table is the format repeated
    league_types = div_head.find_all("h3")
    league_tables = div_head.find_all("table")
    division = None
    team_id = None

    # at end of league_types / h3's, there is a banhistory
    league_table_index = 0
    for i, league_type_tag in enumerate(league_types):
        league_type_span = league_type_tag.find("span")

        if league_type_span['id'] and league_type_span['id'].startswith("ContentPlaceHolder1_Main_rptLeagues_lblLeagueName"):
            league_type_string = league_type_span.text
            # process string to determine if correct gamemode
            if gamemode == get_gamemode_from_string(league_type_string):
                league_table = league_tables[league_table_index]
                division, team_id = get_div_teamid_from_table(league_table)
                break
            # assume league tables are contiguous
            league_table_index += 1
    else:
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} not in correct gamemode".format(steamid))
        print("Couldn't find correct gamemode")
        exit(-1)

    if division is None or team_id is None:
        division = ""
        team_id = ""
        with open("plwlog/{}_faillog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} not found with valid div/team, but in RGL".format(steamid))
        print(",".join([division, name, team_id]))
        exit(-1)
    
    with open("plwlog/{}_successlog".format(time.time()), "w+") as f:
            f.write("[RGL LOG:] sid {} found!".format(steamid))
    print(",".join([division, name, team_id]))
    exit(0)
