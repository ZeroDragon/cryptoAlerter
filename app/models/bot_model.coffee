TelegramBot = require('node-telegram-bot-api')
if process.env.DEV?
	bot ={ onText : ()->}
else
	bot = new TelegramBot(config.telegramToken, {polling: true})
async = require 'async'
crypto = CT_LoadModel 'crypto'

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

# bot.onText /\/activate (.*) untill (.*)$/, (msg,match)->

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

exports.triggerAlerts = (type,cb)->
	sendMessages = (alertsGrouped)->
		for own userid, alerts of alertsGrouped

			message = ["*ALERT!* _#{alerts[0].username}_",'-----------']
			coins = []
			for task in alerts
				alert = JSON.parse(JSON.stringify(task))
				delete alert.username
				delete alert.userid
				delete alert.name
				delete alert.code

				coinMessage = ["*#{task.name}* _#{task.code}_"]
				
				for own k,v of alert
					coinMessage.push "#{k}: #{v}"

				coins.push coinMessage.join('\n')
			message.push coins.join('\n-----------\n')
			message = message.join('\n')
			# console.log message
			bot.sendMessage task.userid, message, {parse_mode:"Markdown"}

	async.parallel(
		{
			userAlerts : (cb)-> brain.get "cryptoAlerter:userAlerts", (err,d)->
				d ?= '{}'
				d = JSON.parse d
				r = {}
				for own k,v of d
					if v.active.toString() is type
						r[k] = v
				cb err, r
			trend : (cb)-> brain.get "cryptoAlerter:trend", (err,d)->
				d ?= '{}'
				cb err, JSON.parse(d)
		}, (err,data)->
			[userAlerts,trend] = [data.userAlerts,data.trend]
			now = (new Date().getTime()/1000)
			alerts = []
			for own username, setup of userAlerts
				limited = !setup.active or now > setup.expiration
				k = 0
				for own code, alertData of setup.currencies
					unless k > 0 and limited
						k++
						filteredTrend = trend.filter((e)-> e.code is code)[0]
						alert = {}
						if alertData['maximum-active'] and alertData['maximum-value'] < filteredTrend.usd
							alert['Value over Maximum'] = "$"+addCommas((filteredTrend.usd).toFixed(3))
						if alertData['minimum-active'] and alertData['minimum-value'] > filteredTrend.usd
							alert['Value under Minimum'] = "$"+addCommas((filteredTrend.usd).toFixed(3))
						if alertData.sell and filteredTrend.action is 'Let me go'
							alert['Ready to sell'] = 'Check the market!'
						if alertData.buy and filteredTrend.action is 'Buy me!'
							alert['Ready to buy'] = 'Looks promising'
						if alertData.rising and filteredTrend.action is 'Rising'
							alert['Coin rising'] = 'Keep on eye on this one'
						if alertData.declining and filteredTrend.action is 'Declining'
							alert['Coin declining'] = 'Secure your satoshis'
						if JSON.stringify(alert) isnt '{}'
							alert.name = filteredTrend.name
							alert.code = filteredTrend.code
							alert.username = setup.username
							alert.userid = setup.id
							alert['Current Value'] = "$"+addCommas((filteredTrend.usd).toFixed(3))
							alerts.push alert
			groupByUsers = {}
			for alert in alerts
				groupByUsers[alert.userid] ?= []
				groupByUsers[alert.userid].push alert
			sendMessages groupByUsers
	)
	cb true