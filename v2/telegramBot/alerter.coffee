later = require 'later'
bot = null

sendMessage = (id, message, opts) ->
	bot.sendMessage(
		id, message, opts ?= {
			parse_mode: "Markdown", reply_markup: { remove_keyboard: true }
		}
	)

btnsMarkup = (btns) ->
	{
		"parse_mode": "Markdown",
		"reply_markup": {
			"inline_keyboard": btns
			resize_keyboard: true
			remove_keyboard: true
		}
	}

processAlerts = (byMinute, definedAlers) ->
	coins = definedAlers.map (e) -> e.coin
	targets = definedAlers.map (e) -> e.targetCoin
	values = {}
	valuesTarget = {}
	for coin in coins
		values[coin] = Object.assign {}, byMinute[coin]
		values[coin].value = values[coin].values.pop()
		delete values[coin].values
	for target in targets
		valuesTarget[target] = Object.assign {}, byMinute[target]
		valuesTarget[target].value = valuesTarget[target].values.pop()
		delete valuesTarget[target].values

	toAlert = []
	for alert in definedAlers
		val = values[alert.coin].value / valuesTarget[alert.targetCoin].value
		switch alert.limitValue
			when 'value is bigger than'
				if val > alert.ammount
					toAlert.push alert
			when 'value is lower than'
				if val < alert.ammount
					toAlert.push alert

	byUser = {}
	toAlert.forEach (e, k) ->
		byUser[e.userId] ?= []
		byUser[e.userId].push e

	for own k, v of byUser
		for alert in v
			message = "*ALERT* #{alert.coin} #{alert.limitValue} #{alert.ammount} #{alert.targetCoin}"
			limitValue = alert.limitValue.replace("value is ", "").replace(" than", "")
			sendMessage alert.userId, message, btnsMarkup [
				[
					{
						text: 'Snooze 5 minutes',
						callback_data:
							JSON.stringify({
								t: "5",
								c: "#{alert.coin} #{limitValue}"
								te: "Alert snoozed by 5 minutes"
							})
					}
					{
						text: 'Snooze 15 minutes',
						callback_data:
							JSON.stringify({
								t: "15",
								c: "#{alert.coin} #{limitValue}"
								te: "Alert snoozed by 15 minutes"
							})
					}
				]
				[
					{
						text: 'Snooze 30 minutes',
						callback_data:
							JSON.stringify({
								t: "30",
								c: "#{alert.coin} #{limitValue}"
								te: "Alert snoozed by 30 minutes"
							})
					}
					{
						text: 'Disable alert',
						callback_data:
							JSON.stringify({
								t: "-1",
								c: "#{alert.coin} #{limitValue}"
								te: "Alert disabled"
							})
					}
				]
			]

alertSched = later.parse.recur().on(55).second()
interval = later.setInterval ->
	triggerAlerts()
, alertSched

triggerAlerts = ->
	info "Triggering alerts"
	brain.triggerAlerts (err, data) ->
		if !err?
			processAlerts data.cache, data.rows

exports.setup = (b) ->
	bot = b

	bot.on "callback_query", (callbackQuery) ->
		{ message: { chat: { id: userId } } } = callbackQuery
		{ t, c, te } = JSON.parse(callbackQuery.data)
		[coin, limitValue] = c.split(" ")
		brain.snoozeAlert "#{userId}:#{coin}:value is #{limitValue} than", parseInt(t)

		text = """
			#{callbackQuery.message.text}
			*#{te}*
		"""
		bot.editMessageText text, {
			chat_id: userId,
			message_id: callbackQuery.message.message_id,
			"parse_mode": "Markdown"
		}

	# triggerAlerts()
	return