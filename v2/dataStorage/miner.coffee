require '../singletons'
cheerio = require 'cheerio'
{parallel, queue} = require 'async'
request = require 'request'
moment = require('moment-timezone')
later = require 'later'

addZ = (i)-> "00#{i}".slice(-2)
byMinute = [0...60].map((e)-> ["b_#{addZ(e)} REAL,"].join('\n')).join('\n')
byHour = [0...24].map((e)-> ["b_#{addZ(e)} REAL,"].join('\n')).join('\n')
byDay = [1..31].map((e)-> ["b_#{addZ(e)} REAL,"].join('\n')).join('\n')

database = new sqlite3.Database("./data.db")

database.serialize ->
	database.run """CREATE TABLE IF NOT EXISTS RatesByMinute (
		code text,
		#{byMinute}
		name text
	)"""
	database.run """CREATE TABLE IF NOT EXISTS RatesByHour (
		code text,
		#{byHour}
		name text
	)"""
	database.run """CREATE TABLE IF NOT EXISTS RatesByDay (
		code text,
		#{byDay}
		name text
	)"""
database.close()

getDataFromSources = ->
	info 'Starting mining'
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

		minute = moment().tz("America/Mexico_City").format("mm")
		info "Generating row for minute #{minute}"

		rows = rows.map (e)->
			e.values = {
				"b_#{minute}" : parseFloat((e.usd * (1 / btc.usd)).toFixed(8))
			}
			delete e.mxn
			delete e.usd
			delete e.btc
			return e

		q.push rows

	db = new sqlite3.Database("./data.db")
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
		db.close()
		generateAcumsByHour()

getSavedData = (query,items,cb)->
	db = new sqlite3.Database("./data.db")
	db.all query, (err,rows)->
		db.close()
		rows = rows.map (e)->
			obj = {}
			obj.name = e.name
			obj.code = e.code
			delete e.name
			delete e.code
			obj.values = {btc:[]}
			for own k,v of e
				obj.values.btc.push v
			obj.values.btc = obj.values.btc
				.map (e)-> e or 0
				.reduce (acc,val)-> (acc + val)
			obj.values.btc = obj.values.btc / items
			return obj
		cb rows

generateAcumsByHour = ->
	getSavedData "SELECT * from RatesByMinute",60,(rows)->
		q.push rows
	db = new sqlite3.Database("./data.db")
	q = queue (row,callback)->
		hour = moment.tz("America/Mexico_City").format("HH")
		updateQuery = """
			UPDATE RatesByHour
			SET
				b_#{hour} = $b_#{hour}
			WHERE code = $code
		"""
		valuesWithCode = {
			"$b_#{hour}" : row.values.btc
			$code : row.code
		}
		insertQuery = """
			INSERT INTO RatesByHour(code,name,b_#{hour})
			VALUES($code,$name,$b_#{hour})
		"""
		plainObject = {
			$code : row.code
			$name : row.name
			"$b_#{hour}" : row.values.btc
		}
		db.run updateQuery, valuesWithCode, (err)->
			if this.changes is 0
				db.run insertQuery, plainObject, (err)->
					callback()
			else
				callback()
	,1
	q.drain = ->
		return if q.running() + q.length() isnt 0
		info "Finished acumulator by hour"
		db.close()
		generateAcumsByDay()

generateAcumsByDay = ->
	getSavedData "SELECT * from RatesByHour",24,(rows)->
		q.push rows
	db = new sqlite3.Database("./data.db")
	q = queue (row,callback)->
		day = moment.tz("America/Mexico_City").format("DD")
		updateQuery = """
			UPDATE RatesByDay
			SET
				b_#{day} = $b_#{day}
			WHERE code = $code
		"""
		valuesWithCode = {
			"$b_#{day}" : row.values.btc
			$code : row.code
		}
		insertQuery = """
			INSERT INTO RatesByDay(code,name,b_#{day})
			VALUES($code,$name,$b_#{day})
		"""
		plainObject = {
			$code : row.code
			$name : row.name
			"$b_#{day}" : row.values.btc
		}
		db.run updateQuery, valuesWithCode, (err)->
			if this.changes is 0
				db.run insertQuery, plainObject, (err)->
					callback()
			else
				callback()
	q.drain = ->
		return if q.running() + q.length() isnt 0
		db.close()
		info "Finished acumulator by day"

cronSched = later.parse.cron '* * * * *'
interval = later.setInterval ->
	getDataFromSources()
,cronSched