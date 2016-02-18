crypto = CT_LoadModel 'crypto'
createguid = ->
	s4 = -> Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
	return s4() + s4() + '-' + s4() + '-' + s4() + '-' +s4() + '-' + s4() + s4() + s4()
exports.main = (req,res)->
	crypto.getRates (rates)->
		coins = []
		for rate in rates
			coins.push {name:rate.name,code:rate.code}
		coins.sort (a,b)->
			return -1 if b.name > a.name
			return 1 if b.name < a.name
			return 0
		res.render CT_Static + '/alerts/main.jade',{
			coins:coins,
			title : 'Crypto Alerter - Alerts'
		}

exports.askForConfirmation = (req,res)->
	brain.get "cryptoAlerter:confirmations", (err,d)->
		d ?= '{}'
		d = JSON.parse d
		guid = createguid().split('-').map((e)-> e[0]).join('')
		date = new Date()
		date.setHours(date.getHours()+1)
		d[req.body.user] = {code:guid,exp:~~(date.getTime()/1000)}
		stillAlive = {}
		now = ~~(new Date().getTime()/1000)
		for own k,v of d
			stillAlive[k] = v if v.exp > now
		brain.set "cryptoAlerter:confirmations", JSON.stringify(stillAlive), (err,data)->
			toSave = {confirmation:guid}
			res.json toSave

exports.reloadUser = (req,res)->
	brain.get "cryptoAlerter:userAlerts", (err,d)->
		d ?= '{}'
		d = JSON.parse d
		if d[req.body.user]?
			user = d[req.body.user]
			user.active = if user.active then "Unlimited" else "Limited"
			res.json user
		else
			res.json {}

exports.isItConfirmed = (req,res)->
	brain.get "cryptoAlerter:confirmations", (err,d)->
		d ?= '{}'
		d = JSON.parse d
		if d[req.body.user]?
			res.json {}
		else
			brain.get "cryptoAlerter:userAlerts", (err,d)->
				d ?= '{}'
				d = JSON.parse d
				if d[req.body.user]?
					user = d[req.body.user]
					user.active = if user.active then "Unlimited" else "Limited"
					res.json user
				else
					res.json {}

exports.saveUserAlerts = (req,res)->
	payload = req.body.payload
	brain.get "cryptoAlerter:userAlerts", (err,d)->
		d ?= '{}'
		d = JSON.parse d
		if d[payload.username]?
			item = d[payload.username]
			for own k,v of payload.currencies
				payload.currencies[k].name =  v.name
				payload.currencies[k]['maximum-active'] = v['maximum-active'] is 'true'
				payload.currencies[k]['maximum-value'] = ~~v['maximum-value']
				payload.currencies[k]['minimum-active'] = v['minimum-active'] is 'true'
				payload.currencies[k]['minimum-value'] = ~~v['minimum-value']
				payload.currencies[k].sell = v.sell is 'true'
				payload.currencies[k].buy = v.buy is 'true'
				payload.currencies[k].rising = v.rising is 'true'
				payload.currencies[k].declining = v.declining is 'true'
			item.currencies = payload.currencies

			d[payload.username] = item
			brain.set "cryptoAlerter:userAlerts", JSON.stringify(d)

	res.sendStatus 200