TelegramBot = require 'node-telegram-bot-api'
bot = new TelegramBot config.telegramToken, {polling:true}

sendMessage = (id,message,opts)->
	bot.sendMessage(id, message, opts ?= {parse_mode : "Markdown"})

bot.onText /start$/i, (msg)->
	return if (msg.from.id isnt msg.chat.id)
	message = """
		Welcome,
		This is an alert bot designed to send you messages about crypto currencies.
		To configure, type `configure`
		When the bot is configured it will send you your desired alerts.
		Type `help` to get a list of all possible options

		Having troubles, questions, ideas? Contact the author @ZeroDragon
	"""
	sendMessage msg.chat.id, message

bot.onText /help|\?$/i, (msg,match)->
	return if (msg.from.id isnt msg.chat.id)
	message = """
		Commands:
			`help` | `?` Answer with this message
			`start` Displays welcome message
	"""
	sendMessage msg.chat.id, message