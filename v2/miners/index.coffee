require '../singletons'
cheerio = require 'cheerio'
{parallel, queue} = require 'async'
request = require 'request'
moment = require('moment-timezone')
moment = moment.tz("America/Mexico_City")

addZ = (i)-> "00#{i}".slice(-2)
byMinute = [0...60].map((e)-> ["b_#{addZ(e)} REAL,","u_#{addZ(e)} REAL,"].join('\n')).join('\n')
byHour = [0...24].map((e)-> ["b_#{addZ(e)} REAL,","u_#{addZ(e)} REAL,"].join('\n')).join('\n')
byDay = [1..31].map((e)-> ["b_#{addZ(e)} REAL,","u_#{addZ(e)} REAL,"].join('\n')).join('\n')

db = new sqlite3.Database("data.db")

db.serialize ->
	db.run """CREATE TABLE IF NOT EXISTS RatesByMinute (
		code text,
		#{byMinute}
		name text
	)"""
	db.run """CREATE TABLE IF NOT EXISTS RatesByHour (
		code text,
		#{byHour}
		name text
	)"""
	db.run """CREATE TABLE IF NOT EXISTS RatesByDay (
		code text,
		#{byDay}
		name text
	)"""

getDataFromSources = ->
	coinCount = 0
	parallel {
		coinmarketcap : (callback)->
			info "[🙏] coinmarketcap"
			request.get 'http://coinmarketcap.com/all/views/all/', (err,response,body)->
				info "[💪] coinmarketcap"
				$ = cheerio.load body
				rs = $('#currencies-all tbody tr')
				delete rs.options
				delete rs._root
				delete rs.length
				delete rs.prevObject
				rows = []
				for own k,v of rs
					obj = {}
					children = v.children.filter (e)-> e.type is 'tag'
					obj.name = children[1].children.filter((e)->e.name is 'img')[0].attribs.alt
					obj.code = children[2].children[0].data
					obj.usd = parseFloat(children[4].children[1].attribs['data-usd']) or 0
					rows.push obj
				callback(null,rows)
		official : (callback)->
			info "[🙏] coinmill"
			request.get 'http://coinmill.com/frame.js', (err,data,body)->
				info "[💪] coinmill"
				currencyData = body.split(';')[0].replace('var currency_data=','')
				currency_convert = (d,c)->
					currency_sdrPer = {}
					for e in currencyData.split("|")
						currency_sdrPer[e.split(",")[0]] = e.split(",")[1]
					return currency_sdrPer[d]/currency_sdrPer[c]
				monedas = [
					["USD","US Dollars"]
					["MXN","Mexican Peso"],
					["COP","Colombian Peso"],
					["BOB","Bolivian Boliviano"],
					["EUR","Euro"],
					["ARS","Argentine Peso"],
					["VEF","Venezuelan Bolivar Fuerte"]
					["CLP","Chilean Peso"]
				]
				r = []
				for moneda in monedas
					r.push {
						code : moneda[0]
						name : moneda[1]
						usd : currency_convert(moneda[0],'USD')
					}
				callback null, r
		bsf : (callback)->
			info "[🙏] dolartoday"
			request.get 'https://7d41da3956ddtztyo.wolrdssl.net/custom/rate.js', (err,data,body)->
				info "[💪] dolartoday"
				body = JSON.parse(body.replace('var dolartoday =',''))
				callback null, {
					name : "Bolivar Cucuta Transfer"
					code : "BSF"
					usd : 1/body.USD.transfer_cucuta
				}
		bitso_eth : (callback)->
			info "[🙏] bitso (eth)"
			request.get "https://bitso.com/api/v2/ticker?book=eth_mxn",{json:true},(err,data,body)->
				info "[💪] bitso (eth)"
				callback(null,{
					"name":"Bitso ETH"
					"code":"BITSO-ETH"
					"mxn" : parseFloat(body.ask)
				})
		bitso_btc : (callback)->
			info "[🙏] bitso (btc)"
			request.get "https://bitso.com/api/v2/ticker?book=btc_mxn",{json:true},(err,data,body)->
				info "[💪] bitso (btc)"
				callback(null,{
					"name":"Bitso BTC"
					"code":"BITSO-BTC"
					"mxn" : parseFloat(body.ask)
				})
		bitso_xrp : (callback)->
			info "[🙏] bitso (ripple)"
			request.get "https://bitso.com/api/v2/ticker?book=xrp_mxn",{json:true},(err,data,body)->
				info "[💪] bitso (ripple)"
				callback(null,{
					"name":"Bitso Ripple"
					"code":"BITSO-XRP"
					"mxn" : parseFloat(body.ask)
				})
		volabit : (callback)->
			info "[🙏] coinmonitor"
			request.get 'http://coinmonitor.com.mx/data_mx.json', {json:true}, (err,response,body)->
				info "[💪] coinmonitor"
				volabit = body.VOLABIT_buy.replace(/,/g,'')
				callback(null,{
					"name":"Volabit BTC"
					"code":"VOLABIT"
					"mxn" : parseFloat(volabit)
				})

	},(err,data)->
		info "All data loaded"
		rows = data.coinmarketcap
		rows = rows.concat data.official
		{bsf,bitso_eth,bitso_btc,bitso_xrp,volabit} = data

		btc = JSON.parse(JSON.stringify(rows.filter((e)->e.code is 'BTC')[0]))
		mxn = rows.filter((e)->e.code is 'MXN')[0]
		bitso_eth.usd = parseFloat(mxn.usd * bitso_eth.mxn).toFixed(8)
		bitso_btc.usd = parseFloat(mxn.usd * bitso_btc.mxn).toFixed(8)
		bitso_xrp.usd = parseFloat(mxn.usd * bitso_xrp.mxn).toFixed(8)
		volabit.usd = parseFloat(mxn.usd * volabit.mxn).toFixed(8)
		rows.push bitso_eth
		rows.push bitso_btc
		rows.push bitso_xrp
		rows.push volabit
		rows.push bsf

		rows = rows.map (e)->
			e.values = {
				"b_#{moment.format("mm")}" : parseFloat((e.usd * (1 / btc.usd)).toFixed(8))
				"u_#{moment.format("mm")}" : parseFloat(e.usd)
			}
			delete e.mxn
			delete e.usd
			delete e.btc
			return e

		q.push rows

	q = queue (coin,callback)->
		values = JSON.parse(JSON.stringify(coin.values))

		valuesWithCode = {}
		for key in Object.keys(coin.values)
			valuesWithCode["$#{key}"] = coin.values[key]
		valuesWithCode["$code"] = coin.code

		plainObject = JSON.parse(JSON.stringify(valuesWithCode))
		plainObject["$name"] = coin.name

		updates = Object.keys(values).map((e)-> "#{e} = $#{e}").join(', ')
		inserts = Object.keys(values).concat(["code","name"]).join(', ')

		updateQuery = """
			UPDATE RatesByMinute
			SET #{updates}
			WHERE code=$code
		"""

		insertQuery = """
			INSERT into RatesByMinute(#{inserts})
			VALUES (#{Object.keys(plainObject)})
		"""
		
		db.run updateQuery, valuesWithCode, (err)->
			if this.changes is 0
				db.run insertQuery, plainObject, (err)->
					coinCount++
					callback()
			else
				coinCount++
				callback()
	,1

	q.drain = ->
		return if q.running() + q.length() isnt 0
		info "Finished inserting #{coinCount} coins into the DB"

getDataFromSources()