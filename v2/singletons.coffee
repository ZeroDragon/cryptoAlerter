global.config = require('./config.json')
global.sqlite3 = require('sqlite3').verbose()
logger = require('nicelogger').config(config.nicelogger)
['debug', 'info', 'warning', 'error', 'log'].forEach (key,item)->
	global[key] = logger[key]