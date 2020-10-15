import etf2lplayerdata
import rglplayerdata

from flask import Flask, request

app = Flask(__name__)


@app.route('/leagueresolver')
def resolve_steamid():
    leagues = int(request.args.get('leagues'))
    
    output = ""

    if leagues & 1:
        output = rglplayerdata.get_rgl_data(request.args, True)
    if ',' not in output and leagues & 2:
        output = etf2lplayerdata.get_etf2l_data(request.args)

    print("League: {}, out: {}".format(leagues, output))
    return output


if __name__ == "__main__":
    app.run(host="0.0.0.0")
