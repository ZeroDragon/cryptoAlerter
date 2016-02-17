crypto = CT_LoadModel 'crypto'
exports.value = (req,res)->
	crypto.getRates (rates)->
		if req.params.currency is 'allCoins'
			res.json rates
		else
			requested = req.params.currency.toUpperCase().split(',')
			coins = rates.filter (e)-> requested.indexOf(e.code) isnt -1
			if coins.length > 0
				res.json coins
			else
				res.sendStatus 404

exports.valueHTML = (req,res)->
	crypto.getRates (rates)->
		rates = JSON.parse(JSON.stringify(rates))
		requested = req.params.currency.toUpperCase()
		coin = rates.filter((e)-> e.code is requested)[0]

		if coin?
			brain.get 'cryptoAlerter:storage', (err,data)->
				items = []
				coinsData = JSON.parse(data).coins
				d = []
				for own k1,v of coinsData[coin.code]
					d.push [k1*1000,v]
				coin.data = d
				res.render CT_Static + '/coins/coinData.jade',{
					coin : coin,
					title : 'Crypto Alerter'
				}
		else
			res.sendStatus 404

exports.trends = (req,res)->
	crypto.getRates (rates)-> brain.get 'cryptoAlerter:storage', (err,data)->
		rates = JSON.parse(JSON.stringify(rates))
		ratesData = rates.filter (e)-> e.mxn >= 0.01
		# ratesData = ratesData.filter (e)-> e.code is 'BTC'
		coinsData = JSON.parse(data).coins
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
		crypto.saveParsed toDisplay

		res.render CT_Static + '/coins/trends.jade',{
			coins : toDisplay
			title : 'Crypto Alerter - Trends'
		}