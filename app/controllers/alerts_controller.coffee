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
		d[req.body.user] = guid
		brain.set "cryptoAlerter:confirmations", JSON.stringify(d), (err,data)->
			toSave = {confirmation:guid}
			res.json toSave

exports.isItConfirmed = (req,res)->
	brain.get "cryptoAlerter:confirmations", (err,d)->
		d ?= '{}'
		d = JSON.parse d
		if d[req.body.user]?
			res.json {confirmed:false}
		else
			brain.get "cryptoAlerter:userAlerts", (err,d)->
				d ?= '{}'
				d = JSON.parse d
				res.json {confirmed:d[req.body.user]?}