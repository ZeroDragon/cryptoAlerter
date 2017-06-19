global.config = require('./config.json')
logger = require('nicelogger').config(config.nicelogger)
['debug', 'info', 'warning', 'error', 'log'].forEach (key, item) ->
	global[key] = logger[key]
global.timeago = require('./timeago')
global.redis = require 'redis'