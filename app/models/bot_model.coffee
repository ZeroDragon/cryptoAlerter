TelegramBot = require('node-telegram-bot-api')
bot = new TelegramBot(config.telegramToken, {polling: true})

bot.onText /\/help$/i, (msg)->
	console.log msg.from.id
	bot.sendMessage msg.from.id, """
		/start: Will start a relation with you
		/end: Don't want me anymore?
	"""

bot.onText /\/start$/i, (msg)->
	bot.sendMessage msg.from.id, "Started a relation with @#{msg.from.username} ❤️"

bot.onText /\/stop$/i, (msg)->
	bot.sendMessage msg.from.id, "@#{msg.from.username}: We are not together anymore 💔"

confirmed = (username,userid)->
	_deleteConfirmation = ->
		brain.get "cryptoAlerter:confirmations", (err,d)->
			d ?= '{}'
			d = JSON.parse d
			delete d[username]
			brain.set "cryptoAlerter:confirmations", JSON.stringify(d)
	_setUser = ->
		brain.get "cryptoAlerter:userAlerts", (err,d)->
			d ?= '{}'
			d = JSON.parse d
			d[userid] ?= {
				active : false
				id : userid
				currencies : {}
			}
			brain.set "cryptoAlerter:userAlerts", JSON.stringify(d)
	_deleteConfirmation()
	_setUser()

bot.onText /\/confirm (.*)$/, (msg,match)->
	code = match[1]
	brain.get "cryptoAlerter:confirmations", (err,d)->
		d ?= '{}'
		d = JSON.parse d
		if d[msg.from.username]? and d[msg.from.username] is code
			bot.sendMessage msg.from.id, "Authorized!"
			confirmed(msg.from.username,msg.from.id)
		else
			bot.sendMessage msg.from.id, "Nope"