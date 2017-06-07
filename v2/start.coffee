require './singletons'

express = require('express')
app = express()

app.listen config.port, ()->
	info "App running on port #{config.port}"

# Load bot
require './telegramBot'