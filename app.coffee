require('chaitea-framework')

r = require('redis')
rClient = r.createClient()
rClient.on 'connect', ->

	CT_Infusion {
		request : require 'request'
		brain : rClient
		addCommas : (x)->
			parts = x.toString().split(".")
			parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
			return parts.join(".")
	}

	CT_Routes -> CT_StartServer()