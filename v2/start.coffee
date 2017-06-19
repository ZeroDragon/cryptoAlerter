require './singletons'
global.brain = require './dataStorage/getter.coffee'
{ queue } = require "async"

express = require('express')
app = express()

app.get '/', (req, res) ->
	res.send """
		This bot works in <a href='http://telegram.me/CryptoAlerterBot'>telegram</a>
	"""

app.get '/status/:coin.json', (req, res) ->
	brain.getCoin req.params.coin, (err, requestedCoin) ->
		if err?
			res.sendStatus err
			return
		r = []
		q = queue (coin, callback) ->
			brain.getCoin coin, (err, resp) ->
				if resp?
					r.push Object.assign resp, {
						code: coin
						displayName: req.query[coin]
					}
				callback()
		, 10
		q.push Object.keys(req.query)
		q.drain = ->
			if q.running() + q.length() is 0
				r = r.map (r) ->
					value = (requestedCoin.value / r.value).toFixed(8).split('.')
					value = parseInt(value[0]).toLocaleString() + '.' + value[1]
					r.crossed = value[0..8]
					return r
				delete requestedCoin.value
				delete requestedCoin.name
				for cross in r
					requestedCoin[cross.displayName] = cross.crossed
				res.json requestedCoin

app.listen config.port, () ->
	info "App running on port #{config.port}"

# Load bot
require './telegramBot'
