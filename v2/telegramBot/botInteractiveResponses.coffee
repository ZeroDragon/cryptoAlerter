smallMemory = {}
bot = null
{queue} = require 'async'
exports.setSmallMemory = (key,obj)->
	smallMemory[key] = obj
exports.setUp = (bo)->
	bot = bo

exports.returnRate = returnRate = (coinCode,cb)->
	brain.getCoin coinCode,(err,coin)-> getCrossData ['usd'],(crosses)->
		message = "`#{coinCode}` is Not a valid rate code"
		return cb message if err

		crossText = []
		for cross in crosses
			value = (coin.value / cross.value).toFixed(8).split('.')
			value = parseInt(value[0]).toLocaleString()+'.'+value[1]
			crossText.push "*#{cross.name}* ≈ #{value}"
		message = """
			#{coin.name} `#{coinCode.toUpperCase()}`
			#{crossText.join("\n")}

		"""
		if coinCode.toUpperCase() isnt 'BTC'
			value = coin.value.toFixed(8).split('.')
			value = parseInt(value[0]).toLocaleString()+'.'+value[1]
			message += """
				*Bitcoin* ≈ #{value}

			"""
		brain.getHistoric coinCode, 'hour', (err, data) ->
			{tendency:{hourlyIncrease,volatility}} = data
			movement = "below 📉"
			movement = "above 📈" if hourlyIncrease > 0
			movementv = "*decrement* 📉"
			movementv = "*increment* 📈" if volatility > 0
			m1 = """
				Last value of #{coin.name} is *#{movement}* by *#{Math.abs(hourlyIncrease.toFixed(2))}%* from the hourly average value.

			"""
			m2 = """
				Also has tendency to #{movementv} with a volatility of *#{Math.abs(volatility.toFixed(2))}%* in the last 10 minutes.
				IMHO, you might want to keep an eye on this one for a while if you want to buy or sell.
			"""
			if Math.abs(hourlyIncrease) < 0.01
				m1 = """
					#{coin.name} has been static in the last hour
					
				"""
			if Math.abs(volatility) < 0.01
				m2 = "Also the volatility is stable, good time to take action, IMHO"
			cb message + m1 + m2

exports.getCrossData = getCrossData = (crosses,cb)->
	results = []
	q = queue (coin,callback)->
		brain.getCoin coin, (err,data)->
			if !err?
				results.push data
			callback()
	,4
	q.push crosses
	q.drain = ->
		return if q.running() + q.length() isnt 0
		cb results

exports.btnsMarkup = btnsMarkup = (btns)->
	{
		"parse_mode": "Markdown",
		"reply_markup": {
			"keyboard": btns
			"one_time_keyboard": true
			resize_keyboard: true
			remove_keyboard : true
		}
	}

exports.sendMessage = sendMessage = (id,message,opts)->
	bot.sendMessage(id, message, opts ?= {parse_mode : "Markdown",reply_markup:{remove_keyboard:true}})

exports.returnConvert = returnConvert = (origin,crossData,ammount,cb)->
	brain.getCoin origin,(err,coin)-> getCrossData crossData.split(','),(crosses)->
		message = "`#{origin}` is Not a valid rate code"
		if !err?
			crossText = []
			for cross in crosses
				value = (coin.value / cross.value) * parseFloat(ammount)
				value = (value).toFixed(8).split('.')
				value = parseInt(value[0]).toLocaleString()+'.'+value[1]
				crossText.push "*#{cross.name}* ≈ #{value}"
			message = """
				#{coin.name} `#{origin.toUpperCase()}`
				#{crossText.join("\n")}
			"""
		cb message

exports.processHistoric = processHistoric = (data,frame,cb)->
	message = ""
	for own key,stat of data.stats
		message += """

			*#{stat.name}*
			Min: #{stat.min}
			Max: #{stat.max}
			Last: #{stat.last}

		"""
	cb message

exports.validateCoin = validateCoin = (code,cb)->
	brain.getCoin code, (err,coin)->
		if err?
			message = """
				`ERROR` *#{code.toUpperCase()}* is not a valid rate code
				Use one of the possible options or type one
			"""
			cb message
		else
			cb null

exports.responses = (msg)->

	if msg.from.id isnt msg.chat.id
		message = """
			This bot does not support groups any longer.
			You are welcome to use this bot in private mode at @CryptoAlerterBot
			So long group and thanks for all the fish.
		"""
		sendMessage msg.chat.id, message
			.then ->
				bot.leaveChat msg.chat.id

	return if (msg.from.id isnt msg.chat.id)
	if msg.text.toUpperCase() is 'CANCEL' and smallMemory[msg.from.id]?
		delete smallMemory[msg.from.id]
		sendMessage msg.chat.id, "command aborted", {"reply_markup": {remove_keyboard : true}}

	if smallMemory[msg.from.id]?

		switch smallMemory[msg.from.id].status
			when 'waitingforcoin'
				validateCoin msg.text, (err)->
					if !err
						smallMemory[msg.from.id].coin = msg.text.toUpperCase()
						smallMemory[msg.from.id].status = 'waitingforlimit'
						message = """
							Do you want to be alerted if the coin reaches a top price or a bottom price?
						"""
						btns = [["value is bigger than","value is lower than"]]
					else
						message = err
						btns = [["BTC","DASH"],["ETH","XRP"],["USD","EUR"]]
					sendMessage msg.chat.id, message,btnsMarkup(btns)

			when 'waitingforlimit'
				if ["value is bigger than","value is lower than"].indexOf(msg.text) is -1
					sendMessage msg.chat.id, """
						`ERROR, please select an option from the two values`.
						Do you want to be alerted if the coin reaches a top price or a bottom price?
					""",btnsMarkup([["value is bigger than","value is lower than"]])
					return
				smallMemory[msg.from.id].trigger = msg.text
				smallMemory[msg.from.id].status = 'waitingforcointrigger'
				sendMessage msg.chat.id, """
					Do you want to set the target value in USD, BTC or in another coin?
					If you want another coin, just type the code.
				""",btnsMarkup([["USD","MXN","BTC"]])

			when 'waitingforcointrigger'
				validateCoin msg.text, (err)->
					if !err?
						smallMemory[msg.from.id].coinTrigger = msg.text.toUpperCase()
						smallMemory[msg.from.id].status = 'waitingforammount'
						message = """
							Now tell me the ammount to trigger the alert
						"""
						opts = {"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}
					else
						message = err
						opts = btnsMarkup([["USD","MXN","BTC"]])
					sendMessage msg.chat.id, message, opts

			when 'waitingforammount'
				if isNaN(parseFloat(msg.text))
					message = """
						`ERROR` Looks like you did not enter a number.
						tell me the ammount to trigger the alert
					"""
				smallMemory[msg.from.id].ammount = msg.text
				delete smallMemory[msg.from.id].type
				delete smallMemory[msg.from.id].status
				sendMessage msg.chat.id, """
					Ok, I'll alert you if *#{smallMemory[msg.from.id].coin} #{smallMemory[msg.from.id].trigger} #{smallMemory[msg.from.id].ammount} #{smallMemory[msg.from.id].coinTrigger}*.
					You can also setup a new alert in one text if you type it like this

					```
						alert me if #{smallMemory[msg.from.id].coin} #{smallMemory[msg.from.id].trigger} #{smallMemory[msg.from.id].ammount} #{smallMemory[msg.from.id].coinTrigger}
					```

					To vew your defined alerts type `alerts`
				""",{"parse_mode": "Markdown","reply_markup": {remove_keyboard : true}}

				payload = {
					userId : msg.from.id
					coin: smallMemory[msg.from.id].coin
					limitValue: smallMemory[msg.from.id].trigger
					ammount: smallMemory[msg.from.id].ammount
					targetCoin: smallMemory[msg.from.id].coinTrigger
				}
				brain.upsertAlert payload,()->
					delete smallMemory[msg.from.id]

			when 'needcoin4rate'
				validateCoin msg.text, (err)->
					if !err?
						delete smallMemory[msg.from.id]
						returnRate msg.text, (message)->
							sendMessage msg.chat.id, message
					else
						message = err
						opts = btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])
						sendMessage msg.chat.id, message, opts

			when 'needammount2convert'
				if isNaN(parseFloat(msg.text))
					message = """
						`ERROR` Looks like you did not enter a number.
						tell me how much you want to convert
					"""
					sendMessage msg.chat.id, message
					return
				smallMemory[msg.from.id] = {status : 'needcoin4convert',ammount:msg.text}
				message = "What coin do you want to convert?"
				sendMessage msg.chat.id, message, btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])

			when 'needcoin4convert'
				validateCoin msg.text, (err)->
					if !err?
						smallMemory[msg.from.id].status = 'needcoin2convert2'
						smallMemory[msg.from.id].origin = msg.text
						message = """
							now, what coin do you want to convert to?
						"""
						sendMessage msg.chat.id, message, btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])
					else
						message = err
						sendMessage msg.chat.id, message, btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])

			when 'needcoin2convert2'
				validateCoin msg.text, (err)->
					if !err?
						smallMemory[msg.from.id].crossData = msg.text
						{origin,crossData,ammount} = smallMemory[msg.from.id]
						returnConvert origin,crossData,ammount,(message)->
							sendMessage msg.chat.id, message
							delete smallMemory[msg.from.id]
					else
						message = err
						sendMessage msg.chat.id, message, btnsMarkup([["BTC","DASH"],["ETH","XRP"],["USD","EUR"]])

			when 'needcoinforhistoric'
				validateCoin msg.text, (err)->
				if !err?
					delete smallMemory[msg.from.id]
					brain.getHistoric msg.text, 'hour', (err,data)->
						processHistoric data, 'hour', (message)->
							message = """
								#{data.name} `#{data.code}`
								Historic values from the last hour
								#{message}
							"""
							sendMessage msg.chat.id, message
