TelegramBot = require('node-telegram-bot-api')
if process.env.NOBOT?
	bot ={ onText : ()->}
else
	bot = new TelegramBot(config.telegramToken, {polling: true})
async = require 'async'
crypto = CT_LoadModel 'crypto'
fs = require 'fs'

sendMessage= (id,message,opts)->
	bot.sendMessage(id, message, opts ?= {parse_mode : "Markdown"}).then ->
		if Math.round(Math.random()*100) < 10
			bot.sendMessage(id, "*Do you ❤ this bot? Buy me a coffee BTC:*\n`1WmxWNA2MR1TCpL4a3kdMpgg2UJok4jbV`", {parse_mode : "Markdown"}).then ->

bot.onText /\/start$|\/start@CryptoAlerterBot$/i, (msg)->
	message = """
		Welcome, @#{msg.from.username}
		This is an alert bot designed to send you messages about crypto currencies.
		All the configuration is done [HERE](http://cryptoalerter.tk/alerts).
		When the bot is configured it will send you your desired alerts.
		Also, you can ask for an specific rate using */rate CODE*
			Ej: `/rate BTC`
			To get the current Bitcoin rate

		You can even send custom rates to compare coins
			Ej: `/rate BTC in MXN,ETH,COP`
			to get the current Bitcoin rate in USD, MXN, ETH and COP

		Want to convert some coins to other coins?
			Ej: `/convert 5 BTC to ETH`
			to get the value of 5 BTC in ETH

		Wondering how localbitcoins is selling BTC?
			ej: `/local US`
			to get the minimum, maximum and average value of BTC for US

		Click [HERE](http://cryptoalerter.tk/trends) for a list of all possible rate codes

		Having troubles, questions, ideas? Contact me @ZeroDragon
	"""
	sendMessage msg.chat.id, message, {parse_mode : "Markdown"}


getChart = (match,cb)->
	brain.get "storage", {}, (err,d)->
		chartData = d.coins[match]
		if !chartData?
			cb true
		values = []
		min = max = 0
		keys = Object.keys(chartData)
		fecha = (d)->
			aZ = (i)-> "0#{i}".slice(-2)
			m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic']
			return "#{m[d.getMonth()]}/#{aZ(d.getDate())}@#{aZ(d.getHours())}:#{aZ(d.getMinutes())}"
		[date1,date2] = [keys[0],keys[keys.length-1]].map (e)-> fecha(new Date(e*1000))
		min = chartData[Object.keys(chartData)[0]]

		for k,v of chartData
			values.push v
			min = Math.min min,v
			max = Math.max max,v
		last = "$#{values[values.length-1].toFixed(5)}"
		min = min - ((max-min) * 10 / 100)
		max = max + ((max-min) * 10 / 100)
		middle = (max + min) / 2
		min = min.toFixed(5)
		max = max.toFixed(5)
		middle = middle.toFixed(5)

		scaleBetween = (unscaled,minAllowed,maxAllowed,min,max)->
			(maxAllowed - minAllowed) * (unscaled - min) / (max-min) + minAllowed

		values = values.map (e)-> scaleBetween e, 0, 100, min, max

		cb null, """
			https://chart.googleapis.com/chart?chxt=x,y&chxl=0:|#{date1}|#{date2}|1:|$#{min}|$#{middle}|$#{max}&cht=ls&chd=t:#{values.join(',')}&chco=0000FF&chls=2.0&chs=600x200&chdl=#{match}&chdlp=t&chg=10,20&chm=t#{last},000000,0,-1:-1:1,11
		"""

bot.onText /\/chart$|\/chart@CryptoAlerterBot$/, (msg,match)->
	message = """
		Usage:
			*/chart CODE*
			ej: `/chart BTC`

	"""
	sendMessage msg.chat.id, message,{parse_mode:"Markdown"}

bot.onText /\/chart (.*)$|\/chart@CryptoAlerterBot (.*)$/, (msg,match)->
	match[1] = match[2] if !match[1]?
	match[1] = match[1].toUpperCase()
	getChart match[1],(err,url)->
		if err
			sendMessage msg.chat.id, "Not a valid rate code"
		else
			bot.sendPhoto msg.chat.id, url
	
bot.onText /\/convert$|\/convert@CryptoAlerterBot$/i,(msg,match)->
	message = """
		Usage:
			*/convert AMMOUNT ORIGIN to DESTINATION*
			ej: `/convert 5 BTC to ETH`

	"""
	sendMessage msg.chat.id, message,{parse_mode:"Markdown"}

bot.onText /\/convert (.*) (.*) to (.*)$|\/convert@CryptoAlerterBot (.*) (.*) to (.*)/, (msg,match)->
	if match[1] is undefined and match[2] is undefined and match[3] is undefined
		match[1] = match[4]
		match[2] = match[5]
		match[3] = match[6]
	brain.get "trend", {}, (err,d)->
		match[1] = parseFloat(match[1])
		if !isNaN(match[1])
			data = d.data.filter((e)-> e.code is match[2].toUpperCase())[0]
			cross = d.data.filter((e)-> e.code is match[3].toUpperCase())[0]

			if data? and cross?
				message = "#{match[1]} #{match[2]} ≈ "
				v = parseFloat((data.usd * (1 / cross.usd)).toFixed(8)) * parseFloat(match[1])
				message += "#{addCommas(v)} #{cross.name}(#{cross.code})"
			else
				cuales = []
				cuales.push match[2] if !data?
				cuales.push match[3] if !cross?
				message = "coin(s) not found: #{cuales.join(',')}"
		else
			message = "uh?"
		sendMessage msg.chat.id, message

bot.onText /\/rate$|\/rate@CryptoAlerterBot$/i,(msg,match)->
	message = """
		Usage:
			*/rate CODE*
			To get the requested coin rate in USD and some other data
			ej: `/rate BTC`

			*/rate CODE [IN CODE[,CODE]]*
			To get the requested coin rate in a converted coin
			ej: `/rate BTC in MXN,COP,LTC,ETH`
	"""
	sendMessage msg.chat.id, message,{parse_mode:"Markdown"}

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
		if !data?
			message = "Not a valid rate code"
		else
			override = ['BETHSO','BITSO','VOLABIT']
			cross = ['MXN','BTC']  if override.indexOf(data.code) isnt -1 and cross.length is 0
			crosses = d.data.filter((e)->cross.indexOf(e.code) isnt -1)
			message = """
				<b>#{data.name}</b> <code>#{data.code}</code> <a href="http://cryptoalerter.tk/status/#{data.code}">[link]</a>
			"""
			if crosses.length is 0
				message += "\n<b>USD</b> ≠ #{addCommas(data.usd)}"
				if data.code isnt 'BTC'
					message += "\n<b>BTC</b> ≠ #{addCommas(data.btc)}"
			for crossItem in crosses
				v = parseFloat((data.usd * (1 / crossItem.usd)).toFixed(8))
				message += "\n<b>#{crossItem.code}:</b> ≠ #{addCommas(v)}"
			if crosses.length is 0 and !data.isNational
				message += "\n<pre>Trend: #{data.status.trend}"
				message += "\nMovement: #{data.status.movement}"
				message += "\nVolatility: #{(data.status.size-100).toFixed(2)}%"
				message += "\nIMHO: #{data.action}</pre>"
		sendMessage msg.chat.id, message, {parse_mode:"HTML"}
bot.onText /\/local$|\/local@CryptoAlerterBot$/i, (msg,match)->
	message = """
		Usage:
			*/local Country_Code*
			To get the rate og BTC in the Country Code from localbitcoins.com
			ej: `/local US`

			*/local Country_Code[,Country_Code,Country_Code,...]*
			To get the rate og BTC in several Country Codes from localbitcoins.com
			ej: `/local US,MX,ES,CL`

			Currently only `US`,`MX`,`ES` and `CL` country codes are supported
	"""
	sendMessage msg.chat.id, message,{parse_mode:"Markdown"}
bot.onText /\/local (.*)$|\/local@CryptoAlerterBot (.*)$/i, (msg,match)->
	match[1] = match[2] if !match[1]?
	matchArr = match[1].split(',')
	brain.get "trend", {}, (err,d)->
		d ?= {}
		data = d.data.filter((e)->e.code is 'BTC')[0]
		added = []
		message = """
			Currently only `US`,`MX`,`ES` and `CL` country codes are supported
		"""
		for tryed in matchArr
			if data.localbitcoins[tryed.toLowerCase()]?
				added.push util._extend({code:tryed.toUpperCase()},data.localbitcoins[tryed.toLowerCase()])
		if added.length isnt 0
			added = added.map (e)->
				retval = """
					*#{e.country}* `#{e.localCode}`:
					Min: `#{e.coin}#{addCommas(e.min.toFixed(3))}`
					Max: `#{e.coin}#{addCommas(e.max.toFixed(3))}`
					Avg: `#{e.coin}#{addCommas(e.avr.toFixed(3))}`
				"""
				return retval
			message = "localbitcoins.com BTC values for:\n"+added.join('\n')
		sendMessage msg.chat.id, message, {parse_mode:"Markdown"}

bot.onText /\/activate (.*) untill (.*)$/, (msg,match)->
	return if msg.from.id isnt config.telegramAdmin
	brain.get "userAlerts", {username:match[1]}, (err,d)->
		if d?
			date = match[2].split('-').map (e)-> ~~e
			untill = new Date(date[0],date[1]-1,date[2],0,0,0)
			d.active = true
			d.expiration = ~~(untill.getTime()/1000)
			brain.set "userAlerts", d
			sendMessage config.telegramAdmin, "#{match[1]} activated untill #{match[2]}"
			sendMessage d.id, "#{match[1]}, your account has been activated untill #{match[2]}"
		else
			sendMessage config.telegramAdmin, "#{match[1]} user not found"

bot.onText /\/unlimited$/, (msg)->
	callback = "http://cryptoalerter.tk/unlimited?username=#{msg.from.username}&userid=#{msg.from.id}"
	url = "https://api.blockchain.info/v2/receive?xpub=#{config.blockchain.xPub}&key=#{config.blockchain.API}&callback=#{encodeURIComponent(callback)}"
	request.get url, (err,res,body)->
		body = JSON.parse body
		sendMessage msg.from.id, "Ok, now just send 0.005 BTC to #{body.address}"

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
			sendMessage msg.from.id, "Authorized!"
			confirmed(msg.from.username,msg.from.id)
		else
			sendMessage msg.from.id, "Code not recognized"

exports.gotPayment = (query,cb)->
	message = ["Got payment"]
	query.value = query.value / 100000000
	for own k,v of query
		message.push "*#{k}:* #{v}"
	message = message.join('\n')
	sendMessage config.telegramAdmin, message, {parse_mode:"Markdown"}
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
			sendMessage task.userid, message, {parse_mode:"Markdown"}

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