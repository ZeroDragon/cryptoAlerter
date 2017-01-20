cheerio = require 'cheerio'
async = require 'async'

cacheData = []
expiration = 0
working = false

_elData = (cb)->
	async.parallel({
		crypto : (callback)->
			console.log "[🙏] coinmarketcap"
			request.get 'http://coinmarketcap.com/all/views/all/', (err,response,body)->
				console.log "[💪] coinmarketcap"
				throw err if err
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
					obj.historic = {
						h : parseFloat(children[7].attribs['data-usd']) or 0
						d : parseFloat(children[8].attribs['data-usd']) or 0
						w : parseFloat(children[9].attribs['data-usd']) or 0
					}
					rows.push obj
				callback(null,rows)
		official : (callback)->
			console.log "[🙏] coinmill"
			request.get 'http://coinmill.com/frame.js', (err,data,body)->
				console.log "[💪] coinmill"
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
						historic : {h:0,d:0,w:0}
						isNational : true
					}
				callback null, r
		bsf : (callback)->
			console.log "[🙏] dolartoday"
			request.get 'https://7d41da3956ddtztyo.wolrdssl.net/custom/rate.js', (err,data,body)->
				console.log "[💪] dolartoday"
				body = JSON.parse(body.replace('var dolartoday =',''))
				callback null, {
					name : "Bolivar Cucuta Transfer"
					code : "BSF"
					usd : 1/body.USD.transfer_cucuta
					historic: {h:0,d:0,w:0}
					isNational : true
				}
		bETHso : (callback)->
			console.log "[🙏] bitso (eth)"
			request.get "https://bitso.com/api/v2/ticker?book=eth_mxn",{json:true},(err,data,body)->
				console.log "[💪] bitso (eth)"
				callback(null,{
					"name":"Bitso ETH"
					"code":"BETHSO"
					"mxn" : parseFloat(body.ask)
					historic : {h:0,d:0,w:0}
				})
		bitso : (callback)->
			console.log "[🙏] bitso (btc)"
			request.get "https://bitso.com/api/v2/ticker?book=btc_mxn",{json:true},(err,data,body)->
				console.log "[💪] bitso (btc)"
				callback(null,{
					"name":"Bitso BTC"
					"code":"BITSO"
					"mxn" : parseFloat(body.ask)
					historic : {h:0,d:0,w:0}
				})
		locals : (callback)->
			console.log "[🙏] coinmonitor"
			request.get 'http://coinmonitor.com.mx/data_mx.json', {json:true}, (err,response,body)->
				console.log "[💪] coinmonitor"
				bitso = body.BITSO_buy.replace(/,/g,'')
				volabit = body.VOLABIT_buy.replace(/,/g,'')
				callback(null,{
					volabit : {
						"name":"Volabit BTC"
						"code":"VOLABIT"
						"mxn" : parseFloat(volabit)
						historic : {h:0,d:0,w:0}
					}
				})
		# localbitcoins : (callback)->
		# 	fn = (code,name,coin,localCode,fncb)->
		# 		console.log "[🙏] localbitcoins (#{localCode})"
		# 		request.get "https://localbitcoins.com/buy-bitcoins-online/#{code}/true/.json", {json:true}, (err,response,body)->
		# 			console.log "[💪] localbitcoins (#{localCode})"
		# 			min = max = body.data.ad_list[0].data.temp_price_usd
		# 			avr = 0
		# 			for itm in body.data.ad_list
		# 				min = Math.min(min,parseFloat(itm.data.temp_price_usd))
		# 				max = Math.max(max,parseFloat(itm.data.temp_price_usd))
		# 				avr += parseFloat(itm.data.temp_price_usd)
		# 			avr = avr / body.data.ad_list.length
		# 			fncb null, {min:min,max:max,avr:avr,country:name,coin:coin,localCode:localCode}
		# 	async.series {
		# 		us : (icb)-> fn 'us','United States', '$', 'USD',icb
		# 		mx : (icb)-> fn 'mx', 'México', '$', 'MXN', icb
		# 		es : (icb)-> fn 'es', 'España', '€', 'EUR', icb
		# 		cl : (icb)-> fn 'cl', 'Chile', '$', 'CLP', icb
		# 	},callback
	},(err,data)->
		rows = data.crypto
		rows = rows.concat data.official
		bethso = data.bETHso
		bitso = data.bitso
		volabit = data.locals.volabit
		bsf = data.bsf

		money = rows.filter((e)->e.code is '$$$')[0]
		if money?
			rows = rows.filter (e)-> e.code isnt '$$$'
			money.code = 'MNY'
			rows.push money

		btc = rows.filter((e)->e.code is 'BTC')[0]
		mxn = rows.filter((e)->e.code is 'MXN')[0]
		bethso.usd = parseFloat((mxn.usd * bethso.mxn).toFixed(8))
		bitso.usd = parseFloat((mxn.usd * bitso.mxn).toFixed(8))
		volabit.usd = parseFloat((mxn.usd * volabit.mxn).toFixed(8))
		rows.push bethso
		rows.push volabit
		rows.push bitso
		rows.push bsf


		# btc.localbitcoins = data.localbitcoins
		# for cc, lbtc of btc.localbitcoins
		# 	cc = rows.filter((e)->e.code is lbtc.localCode)[0]
		# 	lbtc.min = parseFloat((lbtc.min * (1 / cc.usd)).toFixed(8))
		# 	lbtc.max = parseFloat((lbtc.max * (1 / cc.usd)).toFixed(8))
		# 	lbtc.avr = parseFloat((lbtc.avr * (1 / cc.usd)).toFixed(8))
		# rows = rows.filter((e)->e.code isnt 'BTC')
		# rows.push btc

		rows = rows.map (e)->
			h = e.historic
			delete e.historic
			e.btc = parseFloat((e.usd * (1 / btc.usd)).toFixed(8))
			e.historic = h
			return e

		rows.sort (a,b)-> b.usd - a.usd
		cb rows
	)

saveToDB = ()->
	d = new Date()
	stamp = ~~(d.getTime()/1000)
	stamp = ~~(stamp / 60) * 60
	addZ = (i)-> ('00'+i).slice(-2)
	console.log "Saving To Database #{d.getFullYear()}-#{addZ(d.getMonth()+1)}-#{addZ(d.getDate())}@#{addZ(d.getHours())}:#{addZ(d.getMinutes())}"
	brain.get "storage", {}, (err,data)->
		throw err if err
		data ?= {coins:{}}
		for item in cacheData
			data.coins[item.code] ?= {}
			data.coins[item.code][stamp] = item.usd
			arr = []
			for own k,v of data.coins[item.code]
				arr.push {k:~~k,v:v}
			arr = arr[-60..]
			data.coins[item.code] = {}
			for i in arr
				data.coins[item.code][i.k] = i.v
		brain.set "storage", data, (err,reply)->
			throw err if err
			_getTrends ->

cacheRates = (cb)->
	wait4data = false
	if cacheData.length is 0
		wait4data = true
	if new Date().getTime() > expiration
		unless working
			console.log "Buscando nueva información"
			working = true
			_elData (rows)->
				working = false
				expiration = new Date().getTime() + (60*1000)
				cacheData = rows
				saveToDB()
				cb(cacheData) if wait4data
	if !wait4data
		cb cacheData

_getRates = (cb)->
	cacheRates (data)->
		cb data
exports.getRates = _getRates

_getTrends = (cb)->
	_getRates (rates)-> brain.get "storage", {}, (err,data)->
		rates = JSON.parse(JSON.stringify(rates))
		ratesData = rates.filter (e)-> true
		# ratesData = rates.filter (e)-> e.mxn >= 0.01
		coinsData = data.coins
		for coin,k in ratesData
			d = []
			for own k1,v of coinsData[coin.code]
				d.push [~~k1,v]
			ratesData[k].data = d

		ratesData = ratesData.map (e)->
			data = e.data.map (e)-> e[1]
			delete e.data
			delete e.historic
			last = data.pop()
			if data.length > 2
				before = parseFloat((data[-2..].reduce((a,b)->a+b)/data[-2..].length).toFixed(3))
				average = parseFloat((data.reduce((a,b)->a+b)/data.length).toFixed(3))
			else
				before = 0
				average = 0
			e.status = {trend:'same'}
			e.status.trend = 'up' if last > average
			e.status.trend = 'down' if last < average
			e.status.movement = last isnt before
			e.status.size = last * 100 / average
			e.status.size = 100 if e.status.size is Infinity or isNaN(e.status.size)
			e.action = 'Coin is not moving'
			e.action = 'Let me go' if e.status.trend is 'up' and !e.status.movement
			e.action = 'Buy me!' if e.status.trend is 'down' and !e.status.movement
			e.action = 'Wait, is rising' if e.status.trend is 'up' and e.status.movement
			e.action = 'Keep an eye, coin is declining' if e.status.trend is 'down' and e.status.movement
			return e

		buy = ratesData.filter (e)-> e.action is 'Buy me!'
		sell = ratesData.filter (e)-> e.action is 'Let me go'
		still = ratesData.filter (e)-> e.action is 'Coin is not moving'
		rising = ratesData.filter (e)-> e.action is 'Wait, is rising'
		declining = ratesData.filter (e)-> e.action is 'Keep an eye, coin is declining'

		toDisplay = [].concat buy,sell,rising,declining,still

		cloned = {data:JSON.parse(JSON.stringify(toDisplay))}
		brain.get "trend", {}, (err,trend)->
			if trend?
				cloned._id = trend._id
			brain.set "trend", cloned, (err,reply)->

		cb toDisplay
exports.getTrends = _getTrends
