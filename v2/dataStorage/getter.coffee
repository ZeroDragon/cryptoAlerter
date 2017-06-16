cache = {}
later = require 'later'
{series} = require 'async'
moment = require 'moment-timezone'
sizeof = require 'object-sizeof'

database = new sqlite3.Database("#{__dirname}/data.db")
database.run """CREATE TABLE IF NOT EXISTS Alerts (
	userId text,
	coin text,
	limitValue text,
	targetCoin text,
	ammount real,
	lastAlert integer,
	snoozedUntil integer
)"""
database.close()

fillCache = ->
	db = new sqlite3.Database("#{__dirname}/data.db","OPEN_READONLY")
	series {
		RatesByMinute : (callback)->
			db.all "SELECT * FROM RatesByMinute", callback
		RatesByHour : (callback)->
			db.all "SELECT * FROM RatesByHour", callback
		RatesByDay : (callback)->
			db.all "SELECT * FROM RatesByDay", callback
	},(err,data)->
		db.close()
		{RatesByMinute,RatesByHour,RatesByDay} = data
		if !RatesByMinute? or !RatesByHour? or !RatesByDay?
			warning "Data incomplete!"
			return

		now = moment().tz("America/Mexico_City")
		oneHourAgo = moment().tz("America/Mexico_City").subtract(1,'hours')
		oneDayAgo = moment().tz("America/Mexico_City").subtract(1,'days')
		oneMonthAgo = moment().tz("America/Mexico_City").subtract(1,'months')

		minutes = []
		hours = []
		days = []

		while oneHourAgo.diff(now) < 0
			oneHourAgo.add(1,'minutes')
			minutes.push oneHourAgo.format('mm')

		while oneDayAgo.diff(now) < 0
			oneDayAgo.add(1,'hours')
			hours.push oneDayAgo.format('HH')

		while oneMonthAgo.diff(now) < 0
			oneMonthAgo.add(1,'days')
			days.push oneMonthAgo.format('DD')
		
		byMinute = {}
		byHour = {}
		byDay = {}
		for coin in RatesByMinute
			byMinute[coin.code] = {
				name : coin.name
				values : []
			}

			for minute in minutes
				byMinute[coin.code].values.push coin["b_#{minute}"]

		for coin in RatesByHour
			byHour[coin.code] = {
				name : coin.name
				values : []
			}

			for hour in hours
				byHour[coin.code].values.push coin["b_#{hour}"]

		for coin in RatesByDay
			byDay[coin.code] = {
				name : coin.name
				values : []
			}

			for day in days
				byDay[coin.code].values.push coin["b_#{day}"]

		cache = {
			byMinute : byMinute
			byHour : byHour
			byDay : byDay
		}
		info "Loaded #{(sizeof(cache)/1024/1024).toFixed(2)}Mb to cache"

sched = later.parse.recur().on(30).second()
interval = later.setInterval ->
	fillCache()
,sched
fillCache()

waitForData = (cb)->
	timer = false
	letsGo = ->
		clearTimeout(timer) if timer
		if cache.byMinute?.BTC?
			cb()
		else
			timer = setTimeout ->
				letsGo()
			,1000
	letsGo()

exports.triggerAlerts = (cb)-> waitForData ->
	db = new sqlite3.Database("#{__dirname}/data.db","OPEN_READONLY")
	db.all "SELECT rowid, * FROM alerts", (err,rows)->
		db.close()
		console.log rows
		rows = rows
			.filter (e)-> e.snoozedUntil < parseInt(new Date().getTime()/1000)
			.filter (e)-> e.snoozedUntil isnt -1
		# cb null,{cache:cache.byMinute,rows:[]}
		cb err,{cache:cache.byMinute,rows}

exports.getAlerts = getAlerts = (userId,cb)->
	db = new sqlite3.Database("#{__dirname}/data.db","OPEN_READONLY")
	db.all "SELECT rowid, * FROM Alerts WHERE userId = $userId",{$userId:userId},(err,data)->
		db.close()
		cb err,data

exports.snoozeAlert = (id,minutes)->
	snoozedUntil = parseInt(new Date().getTime()/1000) + (minutes*60)
	if minutes is -1
		snoozedUntil = -1
	console.log snoozedUntil
	db = new sqlite3.Database("#{__dirname}/data.db")
	db.run """
		UPDATE alerts
		set snoozedUntil=$snoozedUntil
		WHERE rowid=$rowid
	""",{$snoozedUntil:snoozedUntil,$rowid:id},(err,data)->

exports.deleteAlertByPk = deleteAlertByPk = (rowid)->
	db = new sqlite3.Database("#{__dirname}/data.db")
	db.run "DELETE FROM alerts WHERE rowid = $rowid",{$rowid:rowid},(err,data)->
		db.close()
		if err?
			cb err,null
		else
			cb null,true

exports.deleteAlert = (userId,alertId,cb)->
	getAlerts userId, (err,alerts)->
		if err?
			cb err
		else
			rowid = alerts.filter((e,k)-> k is parseInt(alertId)).map((e)-> e.rowid)[0]
			deleteAlertByPk rowid, cb
			

exports.upsertAlert = (payload,cb)->
	updateQuery = """
		UPDATE Alerts
		SET targetCoin=$targetCoin, ammount=$ammount
		WHERE userId=$userId and coin=$coin and limitValue=$limitValue
	"""
	updateObj = {
		$targetCoin : payload.targetCoin
		$ammount : payload.ammount
		$userId : payload.userId
		$coin : payload.coin
		$limitValue : payload.limitValue
	}
	insertQuery = """
		INSERT into Alerts(userId,coin,limitValue,targetCoin,ammount)
		VALUES ($userId,$coin,$limitValue,$targetCoin,$ammount)
	"""
	insertObj = {
		$userId: payload.userId
		$coin: payload.coin
		$limitValue: payload.limitValue
		$targetCoin: payload.targetCoin
		$ammount: payload.ammount
	}
	db = new sqlite3.Database("#{__dirname}/data.db")
	db.run updateQuery, updateObj, (err)->
		if this.changes is 0
			db.run insertQuery, insertObj, (err)->
				db.close()
				cb()
		else
			db.close()
			cb()

exports.getCoin = _getCoin = (code,cb)-> waitForData ->
	coin = cache.byMinute[code.toUpperCase()]
	if !coin?
		cb 404
		return
	
	cb null,{
		name: coin.name
		value: coin.values[coin.values.length-1]
	}

exports.getHistoric = (code,frame,cb)-> waitForData ->
	code = code.toUpperCase()
	coin = cache.byMinute[code]
	if !coin?
		cb 404
		return

	switch frame
		when 'hour'
			coin = JSON.parse(JSON.stringify(cache.byMinute[code]))
			usd = cache.byMinute.USD
		when 'day'
			coin = JSON.parse(JSON.stringify(cache.byDay[code]))
			usd = cache.byDay.USD

	coin.stats = {
		btc: {
			min: coin.values[0]
			max: coin.values[0]
			last: coin.values[coin.values.length-1]
			name : 'Bitcoin'
		}
		usd: {
			min: coin.values[0] / usd.values[0]
			max: coin.values[0] / usd.values[0]
			last: coin.values[coin.values.length-1] / usd.values[usd.values.length-1]
			name: usd.name
		}
	}
	coin.values.forEach (e,k)->
		coin.stats.btc.min = Math.min coin.stats.btc.min, e
		coin.stats.btc.max = Math.max coin.stats.btc.max, e
		coin.stats.usd.min = Math.min coin.stats.usd.min, e / usd.values[k]
		coin.stats.usd.max = Math.max coin.stats.usd.max, e / usd.values[k]

	delete coin.values
	coin.code = code

	localizeFloat = (float)->
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
