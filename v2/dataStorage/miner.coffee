require '../singletons'
cheerio = require 'cheerio'
{ parallel, queue } = require 'async'
request = require 'request'
moment = require('moment-timezone')
later = require 'later'

getDataFromSources = ->
	info 'Starting mining'
	parallel {
		avocado: (callback) ->
			info "[🙏] walmart"
			url = 'https://super.walmart.com.mx/Agua/Aguacate-hass-por-kilo/00000000003354'
			request.get url, (err, response, body) ->
				info '[💪] walmart'
				$ = cheerio.load body
				rs = $('#skuSpecialPrice')
				callback(null, {
					"name": "Aguacatl"
					"code": "AVO"
					"mxn": parseFloat(rs[0].attribs.value)
				})
		coinmarketcap: (callback) ->
			info "[🙏] coinmarketcap"
			url = 'http://coinmarketcap.com/all/views/all/'
			request.get url, (err, response, body) ->
				info "[💪] coinmarketcap"
				$ = cheerio.load body
				rs = $('#currencies-all tbody tr')
				delete rs.options
				delete rs._root
				delete rs.length
				delete rs.prevObject
				rows = []
				for own k, v of rs
					obj = {}
					children = v.children.filter (e) -> e.type is 'tag'
					obj.name = children[1].children.filter((e) ->
						e.name is 'img'
					)[0].attribs.alt
					obj.code = children[2].children[0].data
					obj.usd = parseFloat(children[4].children[1].attribs['data-usd']) or 0
					rows.push obj
				callback(null, rows)
		official: (callback) ->
			info "[🙏] coinmill"
			request.get 'http://coinmill.com/frame.js', (err, data, body) ->
				info "[💪] coinmill"
				currencyData = body.split(';')[0].replace('var currency_data=', '')
				currency_convert = (d, c) ->
					currency_sdrPer = {}
					for e in currencyData.split("|")
						currency_sdrPer[e.split(",")[0]] = e.split(",")[1]
					return currency_sdrPer[d] / currency_sdrPer[c]
				monedas = [
					["USD", "US Dollars"]
					["MXN", "Mexican Peso"],
					["COP", "Colombian Peso"],
					["BOB", "Bolivian Boliviano"],
					["EUR", "Euro"],
					["ARS", "Argentine Peso"],
					["VEF", "Venezuelan Bolivar Fuerte"]
					["CLP", "Chilean Peso"]
				]
				r = []
				for moneda in monedas
					r.push {
						code: moneda[0]
						name: moneda[1]
						usd: currency_convert(moneda[0], 'USD')
					}
				callback null, r
		bsf: (callback) ->
			info "[🙏] dolartoday"
			url = 'https://7d41da3956ddtztyo.wolrdssl.net/custom/rate.js'
			request.get url, (err, data, body) ->
				info "[💪] dolartoday"
				body = JSON.parse(body.replace('var dolartoday =', ''))
				callback null, {
					name: "Bolivar Cucuta Transfer"
					code: "BSF"
					usd: 1 / body.USD.transfer_cucuta
				}
		bitso_eth: (callback) ->
			info "[🙏] bitso (eth)"
			url = "https://bitso.com/api/v2/ticker?book=eth_mxn"
			request.get url, { json: true }, (err, data, body) ->
				info "[💪] bitso (eth)"
				callback(null, {
					"name": "Bitso ETH"
					"code": "BITSO-ETH"
					"mxn": parseFloat(body.ask)
				})
		bitso_btc: (callback) ->
			info "[🙏] bitso (btc)"
			url = "https://bitso.com/api/v2/ticker?book=btc_mxn"
			request.get url, { json: true }, (err, data, body) ->
				info "[💪] bitso (btc)"
				callback(null, {
					"name": "Bitso BTC"
					"code": "BITSO-BTC"
					"mxn": parseFloat(body.ask)
				})
		bitso_xrp: (callback) ->
			info "[🙏] bitso (ripple)"
			url = "https://bitso.com/api/v2/ticker?book=xrp_mxn"
			request.get url, { json: true }, (err, data, body) ->
				info "[💪] bitso (ripple)"
				callback(null, {
					"name": "Bitso Ripple"
					"code": "BITSO-XRP"
					"mxn": parseFloat(body.ask)
				})
		volabit: (callback) ->
			info "[🙏] coinmonitor"
			url = 'http://coinmonitor.com.mx/data_mx.json'
			request.get url, { json: true }, (err, response, body) ->
				info "[💪] coinmonitor"
				volabit = body.VOLABIT_buy.replace(/,/g, '')
				callback(null, {
					"name": "Volabit BTC"
					"code": "VOLABIT"
					"mxn": parseFloat(volabit)
				})
	}, (err, data) ->
		info "All data loaded"
		rows = data.coinmarketcap
		rows = rows.concat data.official
		{ bsf, bitso_eth, bitso_btc, bitso_xrp, volabit, avocado } = data

		btc = JSON.parse(JSON.stringify(rows.filter((e) -> e.code is 'BTC')[0]))
		mxn = rows.filter((e) -> e.code is 'MXN')[0]
		avocado.usd = parseFloat(mxn.usd * avocado.mxn).toFixed(8)
		bitso_eth.usd = parseFloat(mxn.usd * bitso_eth.mxn).toFixed(8)
		bitso_btc.usd = parseFloat(mxn.usd * bitso_btc.mxn).toFixed(8)
		bitso_xrp.usd = parseFloat(mxn.usd * bitso_xrp.mxn).toFixed(8)
		volabit.usd = parseFloat(mxn.usd * volabit.mxn).toFixed(8)
		rows.push avocado
		rows.push bitso_eth
		rows.push bitso_btc
		rows.push bitso_xrp
		rows.push volabit
		rows.push bsf

		minute = moment().tz("America/Mexico_City").format("mm")
		info "Generating row for minute #{minute}"

		rows = rows.map (e) ->
			e.key = minute
			e.value = parseFloat((e.usd * (1 / btc.usd)).toFixed(8))
			delete e.mxn
			delete e.usd
			delete e.btc
			return e

		q.push rows

	brain = redis.createClient()

	q = queue (coin, callback) ->
		brain.select 1
		brain.set "#{coin.code}:#{coin.key}", coin.value
		brain.select 0
		brain.set "#{coin.code}", coin.name
		callback()
	, 10

	q.drain = ->
		return if q.running() + q.length() isnt 0
		brain.quit()
		info "Finished inserting coins into the DB"

# cronSched = later.parse.cron '* * * * *'
# interval = later.setInterval ->
# 	getDataFromSources()
# , cronSched
getDataFromSources()