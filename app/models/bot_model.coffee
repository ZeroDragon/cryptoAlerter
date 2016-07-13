TelegramBot = require('node-telegram-bot-api')
if process.env.NOBOT?
	bot ={ onText : ()->}
else
	bot = new TelegramBot(config.telegramToken, {polling: true})
async = require 'async'
crypto = CT_LoadModel 'crypto'
fs = require 'fs'

bot.onText /\/start$|\/start@CryptoAlerterBot$/i, (msg)->
	message = """
		Welcome, @#{msg.from.username}
		This is an alert bot designed to send you messages about crypto currencies.
		All the configuration is done [HERE](http://cryptoalerter.tk/alerts).
		When the bot is configured it will send you your desired alerts.
		Also, you can ask for some common rates using /rate
		Or if you know the currency code, you can send /rate CODE
			Ej: /rate BTC
			To get the current Bitcoin rate
		You can even send custom rates to compare coins
			Ej: /rate BTC in MXN,ETH,COP
			to get the current Bitcoin rate in USD, MXN, ETH and COP
	"""
	bot.sendMessage msg.chat.id, message, {parse_mode : "Markdown"}

bot.onText /\/rate$|\/rate@CryptoAlerterBot$/i, (msg)->
	keyboard = [
		['/rate@CryptoAlerterBot BTC','/rate@CryptoAlerterBot ETH']
		['/rate@CryptoAlerterBot DOGE','/rate@CryptoAlerterBot MXN']
	]
	opts = {
		reply_markup: JSON.stringify({
			one_time_keyboard : true
			resize_keyboard : true
			keyboard: keyboard
			selective : true
		})
	}
	bot.sendMessage(msg.chat.id, "What rate you want @#{msg.from.username}?", opts)

bot.onText /\/rate (.*)$|\/rate@CryptoAlerterBot (.*)$/i, (msg,match)->
	match[1] = match[2] if !match[1]?
	match[1] = match[1].toUpperCase()
	matchArr = match[1].split(' IN ')
	cross = []
	if matchArr.length is 1
		search = match[1]
	else
		search = matchArr[0]
		cross = matchArr[1].split(',')
	brain.get "trend", {}, (err,d)->
		d ?= {}
		data = d.data.filter((e)-> e.code is search)[0]
		crosses = d.data.filter((e)->cross.indexOf(e.code) isnt -1)
		if !data?
			message = "Not a valid rate code"
		else
			message = """
				*#{data.name}* _#{data.code}_
				[#{ownUrl}/status/#{data.code}/true](#{ownUrl}/status/#{data.code}/true)
			"""
			if crosses.length is 0
				message += """
					\n*USD:* #{addCommas(data.usd)}
					*BTC:* #{addCommas(data.btc)}
				"""
			for crossItem in crosses
				v = parseFloat((data.usd * (1 / crossItem.usd)).toFixed(8))
				message += "\n*#{crossItem.code}:* #{addCommas(v)}"
			if crosses.length is 0
				message += "\n*Trend:* _#{data.status.trend}_"
				message += "\n*Movement:* _#{data.status.movement}_"
				message += "\n*Volatility:* _#{(data.status.size-100).toFixed(2)}%_"
				message += "\n*Suggested Action:* _#{data.action}_"
		bot.sendMessage msg.chat.id, message, {parse_mode:"Markdown"}

		# filename = "#{process.cwd()}/snapshots/#{createGuid()}.png"
		# request("http://cryptoalerter.tk:8079/#{ownUrl}/status/#{data.code}/true")
		# 	.pipe(fs.createWriteStream(filename))
		# 	.on 'close', ->
		# 		bot.sendPhoto msg.chat.id, filename
		# 		setTimeout ->
		# 			#Wait 1 second and delete image
		# 			fs.unlink filename, (err)->
		# 		,1000

bot.onText /\/activate (.*) untill (.*)$/, (msg,match)->
	return if msg.from.id isnt config.telegramAdmin
	brain.get "userAlerts", {username:match[1]}, (err,d)->
		if d?
			date = match[2].split('-').map (e)-> ~~e
			untill = new Date(date[0],date[1]-1,date[2],0,0,0)
			d.active = true
			d.expiration = ~~(untill.getTime()/1000)
			brain.set "userAlerts", d
			bot.sendMessage config.telegramAdmin, "#{match[1]} activated untill #{match[2]}"
			bot.sendMessage d.id, "#{match[1]}, your account has been activated untill #{match[2]}"
		else
			bot.sendMessage config.telegramAdmin, "#{match[1]} user not found"

bot.onText /\/unlimited$/, (msg)->
	callback = "http://cryptoalerter.tk/unlimited?username=#{msg.from.username}&userid=#{msg.from.id}"
	url = "https://api.blockchain.info/v2/receive?xpub=#{config.blockchain.xPub}&key=#{config.blockchain.API}&callback=#{encodeURIComponent(callback)}"
	request.get url, (err,res,body)->
		body = JSON.parse body
		bot.sendMessage msg.from.id, "Ok, now just send 0.005 BTC to #{body.address}"

confirmed = (username,userid)->
	_deleteConfirmation = ->
		now = ~~(new Date().getTime()/1000)
		brain.del "confirmations", {$or:[{username:username},{exp:{$lt:now}}]}, ->
	_setUser = ->
		brain.get "userAlerts", {username:username}, (err,d)->
			if !d?
				d = {
					active : false
					username : username
					id : userid
					currencies : {}
				}
				brain.set "userAlerts", d, ->
	_deleteConfirmation()
	_setUser()

bot.onText /\/confirm (.*)$/, (msg,match)->
	code = match[1]
	brain.get "confirmations", {username:msg.from.username}, (err,d)->
		d ?= {}
		if d.code is code
			bot.sendMessage msg.from.id, "Authorized!"
			confirmed(msg.from.username,msg.from.id)
		else
			bot.sendMessage msg.from.id, "Code not recognized"

exports.gotPayment = (query,cb)->
	message = ["Got payment"]
	query.value = query.value / 100000000
	for own k,v of query
		message.push "*#{k}:* #{v}"
	message = message.join('\n')
	bot.sendMessage config.telegramAdmin, message, {parse_mode:"Markdown"}
	cb true

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
			userAlerts : (cb)-> brain.get "userAlerts", {},(err,alerts)->
				alerts = [alerts] if !Array.isArray(alerts)
				r = {}
				for alert in alerts
					if alert.active.toString() is type
						r[alert.username] = alert
				cb err, r
			trend : (cb)-> brain.get "trend", {}, (err,d)->
				d ?= {}
				cb err, d.data
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
						if alertData.rising and filteredTrend.action is 'Wait, is rising'
							alert['Coin rising'] = 'Keep on eye on this one'
						if alertData.declining and filteredTrend.action is 'Keep an eye, coin is declining'
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