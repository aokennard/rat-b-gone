from flask import Flask, request
import etf2lplayerdata
import rglplayerdata


app = Flask(__name__)

@app.route('/')
def helloindex():
    print("wuh")
    return "Yee"

@app.route('/leagueresolver')
def resolve_steamid():
    steamid = request.args.get('steamid')
    gamemode = request.args.get('gamemode')
    league = request.args.get('league')
    
    output = "Invalid league"

    if league == "RGL":
        output = rglplayerdata.get_rgl_data(steamid, gamemode)
    elif league == "ETF2L":
        output = etf2lplayerdata.get_etf2l_data(steamid, gamemode)

    return output


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0")
