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

		rows = rows.map (e)->
			h = e.historic
			delete e.historic
			e.mxn = parseFloat((e.usd * (1 / data.usd[0].usd)).toFixed(2))
			e.historic = h
			return e

		rows.sort (a,b)-> b.usd - a.usd
		cb rows
	)

saveToRedis = ()->
	d = new Date()
	stamp = ~~(d.getTime()/1000)
	stamp = ~~(stamp / 60) * 60
	addZ = (i)-> ('00'+i).slice(-2)
	console.log "Saving To Redis #{d.getFullYear()}-#{addZ(d.getMonth()+1)}-#{addZ(d.getDate())}@#{addZ(d.getHours())}:#{addZ(d.getMinutes())}"
	last12Hours = new Date(d.getTime())
	last12Hours.setHours(last12Hours.getHours()-1)
	last12Hours = ~~(last12Hours.getTime()/1000)
	brain.get "cryptoAlerter:storage", (err,d)->
		throw err if err
		data = {coins:{}}
		data = JSON.parse(d) if d
		for item in cacheData
			data.coins[item.code] ?= {}
			data.coins[item.code][stamp] = item.usd
			arr = []
			for own k,v of data.coins[item.code]
				arr.push {k:~~k,v:v}
			arr = arr.filter (e)-> e.k > last12Hours
			data.coins[item.code] = {}
			for i in arr
				data.coins[item.code][i.k] = i.v
		brain.set "cryptoAlerter:storage", JSON.stringify(data), (err,reply)->
			throw err if err

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
				saveToRedis()
				cb(cacheData) if wait4data
	if !wait4data
		cb cacheData

exports.getRates = (cb)->
	cacheRates (data)->
		cb data
