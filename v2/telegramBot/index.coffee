TelegramBot = require 'node-telegram-bot-api'
bot = new TelegramBot config.telegramToken, { polling: true }
interactive = require './botInteractiveResponses'
alerter = require './alerter'
interactive.setUp bot
alerter.setup bot
{
	returnRate,
	btnsMarkup,
	getCrossData,
	sendMessage,
	returnConvert,
	returnConvertObj,
	processHistoric,
	validateCoin
} = interactive
{ queue } = require 'async'

bot.onText /^help$|^\?$|^start$|^\/start$/i, (msg, match) ->
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
			`reminders` list your reminders
			'donate' shows where you can send your love
	"""
	sendMessage msg.chat.id, message, btnsMarkup([["HELP", "RATE"], ["NOW IN", "CONVERT"], ["NEW ALERT", "ALERTS"], ["DONATE"]])

bot.onText /^rate$/i, (msg, match) ->
	interactive.setSmallMemory msg.from.id, { status: 'needcoin4rate' }
	message = "What coin do you want to get rate?"
	sendMessage msg.chat.id, message, btnsMarkup([["BTC", "DASH"], ["ETH", "XRP"], ["USD", "EUR"]])

bot.onText /^rate (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	return if match[1].indexOf(' ') isnt -1
	returnRate match[1], (message) ->
		sendMessage msg.chat.id, message

bot.onText /^rate (.*) in (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.getCoin match[1], (err, coin) ->
		getCrossData match[2].split(','), (crosses) ->
			message = "`#{match[1]}` is Not a valid rate code"
			if !err?
				crossText = []
				for cross in crosses
					value = (coin.value / cross.value).toFixed(8).split('.')
					value = parseInt(value[0]).toLocaleString() + '.' + value[1]
					crossText.push "*#{cross.name}* ≈ #{value}"
				message = """
					#{coin.name} `#{match[1].toUpperCase()}`
					#{crossText.join("\n")}
				"""
			sendMessage msg.chat.id, message

bot.onText /^convert$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	interactive.setSmallMemory msg.from.id, { status: 'needammount2convert' }
	message = "How much?"
	sendMessage msg.chat.id, message

bot.onText /^convert (.*) (.*) to (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	returnConvert match[2], match[3], match[1], (message) ->
		sendMessage msg.chat.id, message

bot.onText /^now in$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	interactive.setSmallMemory msg.from.id, { status: 'needcoinforhistoric' }
	message = "What coin?"
	sendMessage msg.chat.id, message

bot.onText /^now in (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.getHistoric match[1], 'hour', (err, data) ->
		if err?
			sendMessage msg.chat.id, "`#{match[1]}` is Not a valid rate code"
			return
		processHistoric data, 'hour', (message) ->
			message = """
				#{data.name} `#{data.code}`
				Historic values from the last hour
				#{message}
			"""
			sendMessage msg.chat.id, message

bot.onText /^donate$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	sendMessage msg.chat.id, """
		Do you ❤ this bot? Buy me a coffee
			*BTC:* `1WmxWNA2MR1TCpL4a3kdMpgg2UJok4jbV`
			*DASH:* `XtBvftYLvGTqRsw6x1Xtdn42mUh764Rfm4`
	"""

bot.onText /^alerts$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.getAlerts msg.from.id, (err, rows) ->
		if !rows? or rows.length is 0
			message = "There are no alerts for you, to setup a new alert just type `new alert`"
			sendMessage msg.chat.id, message, btnsMarkup([["new alert"]])
		else
			message = ""
			for alert, k in rows
				snooze = "`[ACTIVE]`"
				if alert.snoozedUntil is -1
					snooze = "`[DISABLED]`"
				else
					if alert.snoozedUntil > 0
						snooze = "`[snoozed for #{timeago(alert.snoozedUntil)}]`"
				message += """
					`[#{k}]` - *#{alert.coin} #{alert.limitValue} #{alert.ammount} #{alert.targetCoin}* #{snooze}

				"""
			message += """
				If you setup an alert with the same coin and same same limit, it will replace an existing one.
				To delete an alert just type `delete alert #` where # is the index of the alert listed.
				To activate an alert just type `activate alert #` where # is the index of the alert listed.
			"""
			sendMessage msg.chat.id, message

bot.onText /^delete alert (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.deleteAlert msg.from.id, match[1], (err) ->
		if err?
			message = "An error has ocurred, try again :D"
		else
			message = "Alert deleted!"
		sendMessage msg.chat.id, message

bot.onText /^activate alert (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.activateAlert msg.from.id, match[1], (err) ->
		if err?
			message = "An error has ocurred, try again :D"
		else
			message = "Alert activated!"
		sendMessage msg.chat.id, message

bot.onText /^reminders$/i, (msg,match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.getReminders msg.from.id, (err, rows) ->
		if !rows? or rows.length is 0
			message = """
				There are no reminders for you, to setup a new reminder just type
				`remind me COIN every NUMBER minutes`
				ej: `remind me BTC every 5 minutes`
			"""
			sendMessage msg.chat.id, message
		else
			message = ""
			for reminder, k in rows
				if reminder.active
					if reminder.lastReminder is 0
						snooze = "`[Last: never]`"
					else
						snooze = "`[Last: #{timeago(reminder.lastReminder)} ago]`"
				else
					snooze = "`[DISABLED]`"
				message += """
					`[#{k}]` - *#{reminder.coin} every #{reminder.minutes} minutes* #{snooze}

				"""
			message += """
				If you setup a reminder with the same coin, it will replace an existing one.
				To delete a reminder just type `delete reminder #` where # is the index of the reminder listed.
				To activate a reminder just type `activate reminder #` where # is the index of the reminder listed.
			"""
			sendMessage msg.chat.id, message

bot.onText /^remind me (.*) every (.*) minutes$/i, (msg,match) ->
	return if (msg.from.id isnt msg.chat.id)
	payload = {
		userId: msg.from.id
		coin: match[1].toUpperCase()
		minutes: parseInt(match[2])
		lastReminder: 0
	}
	validateCoin payload.coin, (err1) ->
		if err1
			sendMessage msg.chat.id, """
				`ERROR` looks like you did not enter a correct coin code to set up the alert
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }
			return
		if isNaN(parseInt(payload.minutes))
			sendMessage msg.chat.id, """
				sorry but #{payload.minutes} is not a valid time >.<
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }
			return
		brain.upsertReminder payload, () ->
			sendMessage msg.chat.id, """
				Ok, I'll remind you the value of *#{payload.coin} every #{payload.minutes} minutes*.
				To vew your defined reminders type `reminders`
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }

bot.onText /^delete reminder (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.deleteReminder msg.from.id, match[1], (err) ->
		if err?
			message = "An error has ocurred, try again :D"
		else
			message = "Reminder deleted!"
		sendMessage msg.chat.id, message

bot.onText /^activate reminder (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	brain.activateReminder msg.from.id, match[1], (err) ->
		if err?
			message = "An error has ocurred, try again :D"
		else
			message = "Reminder activated!"
		sendMessage msg.chat.id, message

bot.onText /^alert me if (.*) value (.*) (.*) (.*)$/i, (msg, match) ->
	return if (msg.from.id isnt msg.chat.id)
	payload = {
		userId: msg.from.id
		coin: match[1].toUpperCase()
		limitValue: "value #{match[2]}"
		ammount: match[3]
		targetCoin: match[4].toUpperCase()
	}
	validateCoin payload.coin, (err1) -> validateCoin payload.targetCoin, (err2) ->
		if err1
			sendMessage msg.chat.id, """
				`ERROR` looks like you did not enter a correct coin code to set up the alert
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }
			return
		if err2
			sendMessage msg.chat.id, """
				`ERROR` looks like you did not enter a correct target coin code
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }
			return
		if ["value is bigger than", "value is lower than"].indexOf(payload.limitValue) is -1
			sendMessage msg.chat.id, """
				Sorry I did not understand when you want to be alerted:
				possible values are: "value is bigger than" or "value is lower than" (no quotes)
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }
			return
		if isNaN(parseFloat(payload.ammount))
			sendMessage msg.chat.id, """
				sorry but #{payload.ammount} is not a valid ammount >.<
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }
			return

		brain.upsertAlert payload, () ->
			sendMessage msg.chat.id, """
				Ok, I'll alert you if *#{payload.coin} #{payload.limitValue} #{payload.ammount} #{payload.targetCoin}*.
				To vew your defined alerts type `alerts`
			""", { "parse_mode": "Markdown", "reply_markup": { remove_keyboard: true } }

bot.onText /^new alert$/i, (msg, match) ->
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
	sendMessage msg.chat.id, message, btnsMarkup([["BTC", "DASH"], ["ETH", "XRP"], ["USD", "EUR"]])

bot.onText /^send message to all$/i, (msg, match)->
	return if !config.botOwner
	return if msg.from.id.toString() isnt config.botOwner
	brain.getAllUsers (err, data)->
		return if err
		users = data.alerts.concat(data.reminders)
			.map (e)->
				return e.split(':')[0]
			.filter (element, key, self)->
				return self.indexOf(element) is key
		interactive.setSmallMemory msg.from.id, {
			status: 'needMessageFromOwner'
			users : users
		}
		sendMessage msg.chat.id, "Write down what message you want to send"

bot.on 'text', interactive.responses

inlineConverter = ({ match, id })->
	returnConvertObj match[2], match[3], match[1], (data) ->
		return unless data?
		crossText = data.crossData
			.map (e)-> "*#{e.coinName}* ≈ #{e.value}"
			.join('\n')
		crossDescription = data.crossData
			.map (e)-> "#{e.coinName} ≈ #{e.value}"
			.join(' # ')
		resp = [{
			type: 'article'
			id: "#{match[1]} #{match[2]} #{match[3]}"
			title: "Convert #{match[1]} coin to:"
			input_message_content: {
				message_text: """
					*#{match[1]}* #{data.coinName} to:
					#{crossText}
				"""
				"parse_mode": "Markdown",
			},
			description: "#{crossDescription}"
		}]
		bot.answerInlineQuery id, resp

bot.on 'inline_query', ({ query, id })->
	return if query.length < 3

	converter = /^c (.*) (.*) to (.*)$/i
	if converter.test(query)
		return inlineConverter { match: query.match(converter), id }

	rates = /^(.*)$/i
	if rates.test(query)
		possibles = brain.guessCoins(query).map (e)->
			value = e.value.toFixed(8).split('.')
			value = parseInt(value[0]).toLocaleString() + '.' + value[1]
			return {
				type: 'article'
				id: "rate #{e.code}"
				title: "#{e.name} current rate"
				input_message_content: {
					message_text: """
						*#{e.name}* `#{e.code}`
						*#{e.cross}* ≈ #{value}
					"""
					"parse_mode": "Markdown",
				},
				description: "#{e.cross} ≈ #{value}"
			}

		bot.answerInlineQuery id, possibles[0..10]

# bot.on 'chosen_inline_result', (msg)->
# 	console.log 'selected'
# 	console.log msg
