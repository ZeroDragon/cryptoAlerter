require './singletons'
global.brain = require './dataStorage/getter.coffee'

express = require('express')
app = express()

app.get '/:coin', (req,res)->
	brain.getCoin req.params.coin, (err,coin)->
		if err?
			res.sendStatus err
			return
		res.json coin

app.listen config.port, ()->
	info "App running on port #{config.port}"

# Load bot
require './telegramBot'
