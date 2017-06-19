cache = {}
later = require 'later'
{ waterfall, series, queue } = require 'async'
moment = require 'moment-timezone'
sizeof = require 'object-sizeof'

addZ = (i) -> "00#{i}".slice(-2)

fillCache = ->
	brain = redis.createClient()
	waterfall [
		(callback) ->
			brain.select 0
			brain.keys "*", callback
		(keys, callback) ->
			series {
				names: (cb) ->
					brain.mget keys, (err, names) ->
						cb null, names.map (name, index) ->
							return {
								name
								code: keys[index]
							}
				values: (cb) ->
					brain.select 1
					res = []
					keys = keys
						.map (e) ->
							now = moment().tz("America/Mexico_City")
							oneHourAgo = moment().tz("America/Mexico_City").subtract(1, 'hours')
							minutes = []
							while oneHourAgo.diff(now) < 0
								oneHourAgo.add(1, 'minutes')
								minutes.push oneHourAgo.format('mm')
							minutes.map (m) ->
								return "#{e}:#{addZ(m)}"
					q = queue (keyset, callb) ->
						brain.mget keyset, (err, itms) ->
							res.push itms.map (val) ->
								return 0 if val is null
								return parseFloat val
							callb()
					, 1
					q.push keys
					q.drain = ->
						if q.length() + q.running() is 0
							cb null, res
			}, callback
	], (err, data) ->
		if err?
			warning "Error loading coins D:"
			return
		coins = data.names.map (coin, index) ->
			return Object.assign coin, {
				values: data.values[index]
			}
		RatesByMinute = {}
		for coin in coins
			_coin = Object.assign {}, coin
			delete _coin.code
			RatesByMinute[coin.code] = _coin
		coin = null

		cache = {
			byMinute: RatesByMinute
		}
		info "Loaded #{(sizeof(cache) / 1024 / 1024).toFixed(2)}Mb to cache"

sched = later.parse.recur().on(30).second()
interval = later.setInterval ->
	fillCache()
, sched
fillCache()

waitForData = (cb) ->
	timer = false
	letsGo = ->
		clearTimeout(timer) if timer
		if cache.byMinute?.BTC?
			cb()
		else
			timer = setTimeout ->
				letsGo()
			, 1000
	letsGo()

parseAlerts = (rows) ->
	return rows.map (row) ->
		retval = JSON.parse row
		retval.ammount = parseFloat retval.ammount
		if retval.snoozedUntil isnt null
			retval.snoozedUntil = parseInt retval.snoozedUntil
		return retval

exports.triggerAlerts = (cb) -> waitForData ->
	brain = redis.createClient()
	brain.select 2
	waterfall [
		(callback) -> brain.keys "*", callback
		(keys, callback) -> brain.mget keys, (err, rows) ->
			return callback(err, null) if err
			callback null, parseAlerts rows
	], (err, data) ->
		brain.quit()
		data ?= []
		rows = data
			.filter (e) -> e.snoozedUntil < parseInt(new Date().getTime() / 1000)
			.filter (e) -> e.snoozedUntil isnt -1
		cb err, { cache: cache.byMinute, rows }

exports.getAlerts = getAlerts = (userId, cb) ->
	brain = redis.createClient()
	brain.select 2
	waterfall [
		(callback) -> brain.keys "#{userId}:*", callback
		(keys, callback) -> brain.mget keys, (err, rows) ->
			return callback(err, null) if err
			callback null, parseAlerts rows
	], (err, data) ->
		brain.quit()
		cb err, data

exports.snoozeAlert = (id, minutes) ->
	snoozedUntil = parseInt(new Date().getTime() / 1000) + (minutes * 60)
	if minutes is -1
		snoozedUntil = -1
	brain = redis.createClient()
	brain.select 2
	waterfall [
		(callback) -> brain.get id, callback
		(alert, callback) ->
			alert = JSON.parse alert
			brain.set id, JSON.stringify(
				Object.assign alert, { snoozedUntil }
		)
	], (err, res) ->
		brain.quit()

deleteAlertByPk = (payload, cb) ->
	brain = redis.createClient()
	brain.select 2
	brain.del(
		"#{payload.userId}:#{payload.coin}:#{payload.limitValue}",
		(err, data) ->
			brain.quit()
			cb err, data
	)

exports.deleteAlert = (userId, alertId, cb) ->
	getAlerts userId, (err, alerts) ->
		if err?
			cb err
		else
			row = alerts
				.filter((e, k) -> k is parseInt(alertId))[0]
			deleteAlertByPk row, cb

exports.upsertAlert = upsertAlert = (payload, cb) ->
	brain = redis.createClient()
	brain.select 2
	brain.set(
		"#{payload.userId}:#{payload.coin}:#{payload.limitValue}",
		JSON.stringify(Object.assign payload, {
			snoozedUntil: null
		}),
		(err, data) ->
			brain.quit()
			cb()
	)

exports.activateAlert = (userId, alertId, cb) ->
	getAlerts userId, (err, alerts) ->
		if err?
			cb err
		else
			updateObj = alerts
				.filter((e, k) -> k is parseInt(alertId))[0]
			upsertAlert updateObj, cb

exports.getCoin = _getCoin = (code, cb) -> waitForData ->
	coin = cache.byMinute[code.toUpperCase()]
	if !coin?
		cb 404
		return
	
	cb null, {
		name: coin.name
		value: coin.values[coin.values.length - 1]
	}

exports.getHistoric = (code, frame, cb) -> waitForData ->
	code = code.toUpperCase()
	coin = cache.byMinute[code]
	if !coin?
		cb 404
		return

	coin = Object.assign {}, coin
	usd = cache.byMinute.USD

	coin.stats = {
		btc: {
			min: coin.values[0]
			max: coin.values[0]
			last: coin.values[coin.values.length - 1]
			name: 'Bitcoin'
		}
		usd: {
			min: (coin.values[0] / usd.values[0]) or 0
			max: (coin.values[0] / usd.values[0]) or 0
			last: (
					coin.values[coin.values.length - 1] / usd.values[usd.values.length - 1]
			) or 0
			name: usd.name
		}
	}

	coin.values.forEach (e, k) ->
		coin.stats.btc.min = Math.min coin.stats.btc.min, e
		coin.stats.btc.max = Math.max coin.stats.btc.max, e
		val = e / usd.values[k]
		if isNaN val
			val = 0
		coin.stats.usd.min = Math.min coin.stats.usd.min, val
		coin.stats.usd.max = Math.max coin.stats.usd.max, val

	delete coin.values
	coin.code = code

	localizeFloat = (float) ->
		t = (float).toString().split('.')
		return parseInt(t[0]).toLocaleString() + do ->
			if parseInt(t[1]) isnt 0
				return '.' + t[1]
			else
				return ''

	coin.stats.btc.min = localizeFloat coin.stats.btc.min.toFixed(8)
	coin.stats.btc.max = localizeFloat coin.stats.btc.max.toFixed(8)
	coin.stats.btc.last = localizeFloat coin.stats.btc.last.toFixed(8)
	coin.stats.usd.min = localizeFloat coin.stats.usd.min.toFixed(8)
	coin.stats.usd.max = localizeFloat coin.stats.usd.max.toFixed(8)
	coin.stats.usd.last = localizeFloat coin.stats.usd.last.toFixed(8)

	if code is 'USD'
		delete coin.stats.usd
	if code is 'BTC'
		delete coin.stats.btc

	cb null, coin
