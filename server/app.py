import etf2lplayerdata
import rglplayerdata

from flask import Flask, request

app = Flask(__name__)

@app.route('/leagueresolver')
def resolve_steamid():
    steamid = request.args.get('steamid')
    gamemode = request.args.get('gamemode')
    league = request.args.get('league')
    
    output = "Invalid league"

    if league == "RGL":
        output = rglplayerdata.get_rgl_data(steamid, gamemode, True)
    elif league == "ETF2L":
        output = etf2lplayerdata.get_etf2l_data(steamid, gamemode)

    return output


if __name__ == "__main__":
    app.run(host="0.0.0.0")
