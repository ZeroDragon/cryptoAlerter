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
			url = 'https://api.coinmarketcap.com/v1/ticker/?limit=0'
			request.get url, {json:true}, (err, response, rs) ->
				info "[💪] coinmarketcap"
				rows = []
				for coin in rs
					obj = {
						name: coin.name
						code: coin.symbol
						usd: coin.price_usd
					}
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
		bitso: (callback) ->
			info "[🙏] bitso"
			url = "https://api.bitso.com/v3/ticker/"
			request.get url, { json: true }, (err, data, body) ->
				info "[💪] bitso"
				validCoins = {
					btc_mxn: ["Bitso BTC", "BITSO-BTC"]
					eth_mxn: ["Bitso ETH", "BITSO-ETH"]
					xrp_mxn: ["Bitso XRP", "BITSO-XRP"]
					bch_btc: ["Bitso BCH", "BITSO-BCH"]
				}
				r = {}
				for book in body.payload
					if validCoins[book.book]
						r[book.book] = {
							"name": validCoins[book.book][0]
							"code": validCoins[book.book][1]
							"#{book.book.split('_')[1]}": book.ask
						}
				callback(null, r)
		volabit: (callback) ->
			info "[🙏] coinmonitor"
			url = 'http://mx.coinmonitor.info/data_mx.json'
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
		{ bsf, bitso, volabit, avocado } = data
		{ btc_mxn, eth_mxn, xrp_mxn, bch_btc } = bitso

		btc = JSON.parse(JSON.stringify(rows.filter((e) -> e.code is 'BTC')[0]))
		mxn = rows.filter((e) -> e.code is 'MXN')[0]
		avocado.usd = parseFloat(mxn.usd * avocado.mxn).toFixed(8)
		btc_mxn.usd = parseFloat(mxn.usd * btc_mxn.mxn).toFixed(8)
		eth_mxn.usd = parseFloat(mxn.usd * eth_mxn.mxn).toFixed(8)
		xrp_mxn.usd = parseFloat(mxn.usd * xrp_mxn.mxn).toFixed(8)
		bch_btc.usd = parseFloat(btc.usd * bch_btc.btc).toFixed(8)
		volabit.usd = parseFloat(mxn.usd * volabit.mxn).toFixed(8)

		rows.push avocado
		rows.push btc_mxn
		rows.push eth_mxn
		rows.push xrp_mxn
		rows.push bch_btc
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

		rows.map (coin)->
			hasDupe = rows.filter((e)-> e.code is coin.code).length isnt 1
			if hasDupe
				coin.code = coin.name.replace(/\s/g,'').toUpperCase()
			return coin

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

info "Starting miner schedule"
cronSched = later.parse.cron '* * * * *'
interval = later.setInterval ->
	getDataFromSources()
, cronSched
# getDataFromSources()
