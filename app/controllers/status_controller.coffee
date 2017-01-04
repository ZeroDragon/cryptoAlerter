crypto = CT_LoadModel 'crypto'
phantom = require 'phantom'
queryString = require 'querystring'
exports.value = (req,res)->
	crypto.getRates (rates)->
		if !req.params.currency?
			res.sendStatus 404
			return
		coin = rates.filter((e)-> e.code is req.params.currency.toUpperCase())[0]
		if !coin?
			res.sendStatus 404
			return
		mxn = rates.filter((e)-> e.code is 'MXN')[0]
		coin.mxn = parseFloat((coin.usd * (1 / mxn.usd)).toFixed(2))
		obj = {}
		if req.query.usd?
			obj[req.query.usd] = "$#{addCommas(coin.usd)}"
		if req.query.mxn?
			obj[req.query.mxn] = "$#{addCommas(coin.mxn)}"
		if req.query.h?
			obj[req.query.h] = "#{coin.historic.h}%"
		if req.query.d?
			obj[req.query.d] = "#{coin.historic.d}%"
		if req.query.w?
			obj[req.query.w] = "#{coin.historic.w}%"
		res.json obj

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
					inline : req.params.inline ?= false
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
