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

bot.onText /\/rate (.*)$/, (msg,match)->
	brain.get "cryptoAlerter:trend", (err,d)->
		d ?= '{}'
		data = JSON.parse(d).filter((e)-> e.code is match[1].toUpperCase())[0]
		message = """
			*#{data.name}* _#{data.code}_
			$#{addCommas(data.usd)} *USD*
			$#{addCommas(data.mxn)} *MXN*
			*Action:* _#{data.action}_
		"""
		bot.sendMessage msg.from.id, message, {parse_mode:"Markdown"}

confirmed = (username,userid)->
	_deleteConfirmation = ->
		brain.get "cryptoAlerter:confirmations", (err,d)->
			d ?= '{}'
			d = JSON.parse d
			delete d[username]
			stillAlive = {}
			now = ~~(new Date().getTime()/1000)
			for own k,v of d
				stillAlive[k] = v if v.exp > now
			brain.set "cryptoAlerter:confirmations", JSON.stringify(stillAlive)
	_setUser = ->
		brain.get "cryptoAlerter:userAlerts", (err,d)->
			d ?= '{}'
			d = JSON.parse d
			d[username] ?= {
				active : false
				username : username
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
		if d[msg.from.username]? and d[msg.from.username].code is code
			bot.sendMessage msg.from.id, "Authorized!"
			confirmed(msg.from.username,msg.from.id)
		else
			bot.sendMessage msg.from.id, "Code not recognized"