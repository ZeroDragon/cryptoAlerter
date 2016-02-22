crypto = CT_LoadModel 'crypto'
phantom = require 'phantom'
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
			brain.get 'storage', {}, (err,data)->
				coinsData = data.coins
				d = []
				for own k1,v of coinsData[coin.code]
					d.push [k1*1000,v]
				coin.data = d
				res.render CT_Static + '/coins/coinData.jade',{
					coin : coin,
					title : 'Crypto Alerter'
					standAlone : req.params.standAlone ?= false
				}
		else
			res.sendStatus 404

exports.valueImage = (req,res)->
	try
		phantom.create (ph)->
			ph.createPage (page)->
				page.open "#{ownUrl}/status/#{req.params.currency}/true",(status)->
					page.set('viewportSize', {width:600,height:200})
					page.renderBase64('png',(data)->
						res.writeHead(200, { 'Cache': 'no-cache','Content-Type': 'image/png' })
						res.end data,'base64'
						ph.exit()
					)
	catch e
		res.sendStatus 404

exports.trends = (req,res)->
	crypto.getTrends (toDisplay)->
		res.render CT_Static + '/coins/trends.jade',{
			coins : toDisplay
			title : 'Crypto Alerter - Trends'
		}