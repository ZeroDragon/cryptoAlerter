cheerio = require 'cheerio'
async = require 'async'

cacheData = []
expiration = 0
working = false

_elData = (cb)->
	async.parallel({
		crypto : (callback)->
			request.get 'http://coinmarketcap.com/all/views/all/', (err,response,body)->
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
			request.get 'http://query.yahooapis.com/v1/public/yql?q=select * from yahoo.finance.quotes where symbol IN ("MXNUSD=X","COPUSD=X","BOBUSD=X","EURUSD=X","ARSUSD=X")&format=json&env=http://datatables.org/alltables.env',{json:true},(err,data,body)->
				r = []
				symbol2name = {
					"COPUSD=X":"Colombian Peso",
					"MXNUSD=X":"Mexican Peso",
					"BOBUSD=X":"Bolivian Peso",
					"EURUSD=X":"Euro",
					"ARSUSD=X":"Argentine peso"
				}
				symbol2code = {BOB:"BOL"}
				for item in body.query.results.quote
					r.push {
						"name" : symbol2name[item.symbol]
						"code" : symbol2code[item.symbol.replace(/USD=X/,'')] or item.symbol.replace(/USD=X/,'')
						"usd" : parseFloat(item.Ask)
						historic : {h:0,d:0,w:0}
					}
				r.push {
					"name": "US Dollars",
					"code": "USD",
					"usd": 1,
					historic : {h:0,d:0,w:0}
				}
				callback null,r
		bETHso : (callback)->
			request.get "https://bitso.com/api/v2/ticker?book=eth_mxn",{json:true},(err,data,body)->
				callback(null,{
					"name":"Bitso ETH"
					"code":"BETHSO"
					"mxn" : parseFloat(body.ask)
					historic : {h:0,d:0,w:0}
				})
		locals : (callback)->
			request.get 'http://coinmonitor.com.mx/data_mx.json', {json:true}, (err,response,body)->
				bitso = body.BITSO_sell.replace(/,/g,'')
				volabit = body.VOLABIT_buy.replace(/,/g,'')
				callback(null,{
					bitso : {
						"name":"Bitso BTC"
						"code":"BITSO"
						"mxn" : parseFloat(bitso)
						historic : {h:0,d:0,w:0}
					},
					volabit : {
						"name":"Volabit BTC"
						"code":"VOLABIT"
						"mxn" : parseFloat(volabit)
						historic : {h:0,d:0,w:0}
					}
				})
	},(err,data)->
		rows = data.crypto
		rows = rows.concat data.official
		bethso = data.bETHso
		bitso = data.locals.bitso
		volabit = data.locals.volabit

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
		# rows.push volabit

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