TelegramBot = require 'node-telegram-bot-api'
bot = new TelegramBot config.telegramToken, {polling:true}
interactive = require './botInteractiveResponses'
interactive.setUp bot
{
	returnRate,
	btnsMarkup,
	getCrossData,
	sendMessage,
	returnConvert,
	processHistoric,
	validateCoin
} = interactive
{queue} = require 'async'

bot.onText /^help$|^\?$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	message = """
		Welcome,
			This is an alert bot designed to send you messages about crypto currencies.
			When the bot is configured it will send you your desired alerts.
			Type `help` to get a list of all possible options

		Commands:
			`help` | `?` | `start` | `/start` Answer with this message
			`rate <coin>` returns current rate for requested coin code
			`rate <coin> in <other coin>` return current rate for requested coin in another coin rate
			`convert <ammount> <coin> to <another coin>` converts value from one coin to another coin
			`now in <coin>` return last hour max, min and last value for requested coin
			`new alert` starts the new alert setup wizard
			`alerts` lists your alerts
			'donate' shows where you can send your love
	"""
	sendMessage msg.chat.id, message, btnsMarkup([["HELP","RATE"],["NOW IN","CONVERT"],["NEW ALERT","ALERTS"],["DONATE"]])

bot.onText /^rate$/i, (msg,match)->
	interactive.setSmallMemory msg.from.id, {status : 'needcoin4rate'}
	message = "What coin do you want to get rate?"
	sendMessage msg.chat.id, message, btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])

bot.onText /^rate (.*)$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	return if match[1].indexOf(' ') isnt -1
	returnRate match[1], (message)->
		sendMessage msg.chat.id, message

bot.onText /^rate (.*) in (.*)$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	brain.getCoin match[1],(err,coin)-> getCrossData match[2].split(','),(crosses)->
		message = "`#{match[1]}` is Not a valid rate code"
		if !err?
			crossText = []
			for cross in crosses
				value = (coin.value / cross.value).toFixed(8).split('.')
				value = parseInt(value[0]).toLocaleString()+'.'+value[1]
				crossText.push "*#{cross.name}* ≈ #{value}"
			message = """
				#{coin.name} `#{match[1].toUpperCase()}`
				#{crossText.join("\n")}
			"""
		sendMessage msg.chat.id, message

bot.onText /^convert$/i, (msg,match)->
	interactive.setSmallMemory msg.from.id, {status : 'needammount2convert'}
	message = "How much?"
	sendMessage msg.chat.id, message

bot.onText /^convert (.*) (.*) to (.*)$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	returnConvert match[2],match[3],match[1],(message)->
		sendMessage msg.chat.id, message

bot.onText /^now in (.*)$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	brain.getHistoric match[1], 'hour', (err,data)->
		if err?
			sendMessage msg.chat.id, "`#{match[1]}` is Not a valid rate code"
			return
		processHistoric data, 'hour', (message)->
			sendMessage msg.chat.id, message

bot.onText /^today in (.*)$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	brain.getHistoric match[1], 'day', (err,data)->
		if err?
			sendMessage msg.chat.id, "`#{match[1]}` is Not a valid rate code"
			return
		processHistoric data, 'day', (message)->
			sendMessage msg.chat.id, message

bot.onText /^donate$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	sendMessage msg.chat.id, """
		Do you ❤ this bot? Buy me a coffee
			*BTC:* `1WmxWNA2MR1TCpL4a3kdMpgg2UJok4jbV`
			*DASH:* `XtBvftYLvGTqRsw6x1Xtdn42mUh764Rfm4`
			*Paypal:* `zr.drgn@gmail.com`
	"""

bot.onText /^alerts$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	brain.getAlerts msg.from.id, (err,rows)->
		if rows.length is 0
			message = "There are no alerts for you, to setup a new alert just type `new alert`"
			sendMessage msg.chat.id, message, btnsMarkup([["new alert"]])
		else
			message = ""
			for alert,k in rows
				message += """
					`[#{k}]` - *#{alert.coin} #{alert.limitValue} #{alert.ammount} #{alert.targetCoin}*

				"""
			sendMessage msg.chat.id, message

bot.onText /^alert me if (.*) value (.*) (.*) (.*)$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	payload = {
		userId : msg.from.id
		coin: match[1].toUpperCase()
		limitValue: "value #{match[2]}"
		ammount: match[3]
		targetCoin: match[4].toUpperCase()
	}
	validateCoin payload.coin, (err1)-> validateCoin payload.targetCoin, (err2)->
		if err1
			sendMessage msg.chat.id, """
				`ERROR` looks like you did not enter a correct coin code to set up the alert
			""",{"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}
			return
		if err2
			sendMessage msg.chat.id, """
				`ERROR` looks like you did not enter a correct target coin code
			""",{"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}
			return
		if ["value is bigger than","value is lower than"].indexOf(payload.limitValue) is -1
			sendMessage msg.chat.id, """
				Sorry I did not understand when you want to be alerted:
				possible values are: "value is bigger than" or "value is lower than" (no quotes)
			""",{"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}
			return
		if isNaN(parseFloat(payload.ammount))
			sendMessage msg.chat.id, """
				sorry but #{payload.ammount} is not a valid ammount >.<
			""",{"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}
			return

		brain.upsertAlert payload,()->
			sendMessage msg.chat.id, """
				Ok, I'll alert you if *#{payload.coin} #{payload.limitValue} #{payload.ammount} #{payload.targetCoin}*.
				To vew your defined alerts type `alerts`
			""",{"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}

bot.onText /^new alert$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	message = """
		Ok, lets start, what coin do you want to set an alert to?
		Use one of the possible options or type one
		(type `cancel` to abort setting up the alert at any time)
	"""
	interactive.setSmallMemory msg.from.id, {
		type: 'newAlert'
		status: 'waitingforcoin'
	}
	sendMessage msg.chat.id, message, btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])

bot.on 'text', interactive.responses