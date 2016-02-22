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

		usd : (callback)->
			request.get 'http://finance.yahoo.com/q?s=MXNUSD=X', (err,response,body)->
				throw err if err
				$ = cheerio.load body
				mxpRate = $('.time_rtq_ticker')[0].children[0].children[0].data
				r = [
					{
						"name": "Mexican Pesos",
						"code": "MXN",
						"usd": parseFloat(mxpRate),
						historic : {
							h:0
							d:0
							w:0
						}
					},
					{
						"name": "US Dollars",
						"code": "USD",
						"usd": 1,
						historic : {
							h:0
							d:0
							w:0
						}
					}
				]
				callback(null,r)
	},(err,data)->
		rows = data.crypto
		rows = rows.concat data.usd

		money = rows.filter((e)->e.code is '$$$')[0]
		if money?
			rows = rows.filter (e)-> e.code isnt '$$$'
			money.code = 'MNY'
			rows.push money

		btc = rows.filter((e)->e.code is 'BTC')[0]

		rows = rows.map (e)->
			h = e.historic
			delete e.historic
			e.mxn = parseFloat((e.usd * (1 / data.usd[0].usd)).toFixed(2))
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
		ratesData = rates.filter (e)-> e.mxn >= 0.01
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
			before = parseFloat((data[-2..].reduce((a,b)->a+b)/data[-2..].length).toFixed(3))
			average = parseFloat((data.reduce((a,b)->a+b)/data.length).toFixed(3))
			e.status = {trend:'same'}
			e.status.trend = 'up' if last > average
			e.status.trend = 'down' if last < average
			e.status.movement = last isnt before
			e.action = 'Not moving'
			e.action = 'Let me go' if e.status.trend is 'up' and !e.status.movement
			e.action = 'Buy me!' if e.status.trend is 'down' and !e.status.movement
			e.action = 'Rising' if e.status.trend is 'up' and e.status.movement
			e.action = 'Declining' if e.status.trend is 'down' and e.status.movement
			return e

		buy = ratesData.filter (e)-> e.action is 'Buy me!'
		sell = ratesData.filter (e)-> e.action is 'Let me go'
		still = ratesData.filter (e)-> e.action is 'Not moving'
		rising = ratesData.filter (e)-> e.action is 'Rising'
		declining = ratesData.filter (e)-> e.action is 'Declining'

		toDisplay = [].concat buy,sell,rising,declining,still

		cloned = {data:JSON.parse(JSON.stringify(toDisplay))}
		brain.get "trend", {}, (err,trend)->
			if trend?
				cloned._id = trend._id
			brain.set "trend", cloned, (err,reply)->

		cb toDisplay
exports.getTrends = _getTrends