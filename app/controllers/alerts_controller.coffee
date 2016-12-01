crypto = CT_LoadModel 'crypto'
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
	code = createguid().split('-').map((e)-> e[0]).join('')
	date = new Date()
	date.setHours(date.getHours()+1)
	d = {username:req.body.user,code:code,exp:~~(date.getTime()/1000)}
	now = ~~(new Date().getTime()/1000)
	#Overwrite confirmation
	brain.del "confirmations", {username:req.body.user}, (err,resp)->
		#Save confirmation
		brain.set "confirmations", d, (err,data)->
			toSave = {confirmation:code}
			res.json toSave
			#Garbage collect
			brain.del 'confirmations', {exp:{$lt:now}}, (err,resp)->

exports.reloadUser = (req,res)->
	brain.get "userAlerts", {username:req.body.user}, (err,d)->
		if d?
			d.active = if d.active then "Unlimited" else "Limited"
			res.json d
		else
			res.json {}

exports.isItConfirmed = (req,res)->
	brain.get "confirmations", {username:req.body.user}, (err,d)->
		if d?
			res.json {}
		else
			brain.get "userAlerts", {username:req.body.user}, (err,d)->
				if d?
					d.active = if d.active then "Unlimited" else "Limited"
					res.json d
				else
					res.json {}

exports.saveUserAlerts = (req,res)->
	payload = req.body.payload
	brain.get "userAlerts", {username:payload.username}, (err,item)->
		if item?
			payload.currencies ?= {}
			for own k,v of payload.currencies
				payload.currencies[k].name =  v.name
				payload.currencies[k]['maximum-active'] = v['maximum-active'] is 'true'
				payload.currencies[k]['maximum-value'] = parseFloat v['maximum-value']
				payload.currencies[k]['minimum-active'] = v['minimum-active'] is 'true'
				payload.currencies[k]['minimum-value'] = parseFloat v['minimum-value']
				payload.currencies[k].sell = v.sell is 'true'
				payload.currencies[k].buy = v.buy is 'true'
				payload.currencies[k].rising = v.rising is 'true'
				payload.currencies[k].declining = v.declining is 'true'
			item.currencies = payload.currencies
			brain.set "userAlerts", item, ->
	res.sendStatus 200

exports.triggerAlerts = (req,res)->
	botModel.triggerAlerts req.params.type, ->
	res.sendStatus 200

exports.unlimited = (req,res)->
	if ~~req.query.confirmations is 0 or ~~req.query.confirmations is 3
		botModel.gotPayment req.query, ->
			res.sendStatus 200
	if ~~req.query.confirmations is 3
		res.send '*ok*'