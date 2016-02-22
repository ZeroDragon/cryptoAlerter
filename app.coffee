require('chaitea-framework')

MongoClient = require('mongodb').MongoClient
dbMon = false
MongoClient.connect config.mongo, (err,db)->
	throw err if err

	CT_Infusion {
		request : require 'request'
		brain : {
			get : (collection, query, cb)->
				cb ?= ->
				db.collection("#{collection}").find(query).toArray (err,data)->
					if err
						cb err,null
					else if data.length is 1
						cb null,data[0]
					else if data.length is 0
						cb null,null
					else
						cb null,data
			set : (collection, element, cb)->
				cb ?= ->
				if element._id?
					db.collection("#{collection}").update {_id:element._id}, element, cb
				else
					element._id = createguid()
					db.collection("#{collection}").insert element, cb
			del : (collection, query, cb)->
				cb ?= ->
				db.collection("#{collection}").remove query, cb
		}
		botModel : CT_LoadModel 'bot'
		ownUrl : if process.env.DEV? then "http://localhost:1339" else "http://cryptoalerter.tk"
		createguid : ->
			s4 = -> Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
			return s4() + s4() + '-' + s4() + '-' + s4() + '-' +s4() + '-' + s4() + s4() + s4()
		addCommas : (x)->
			parts = x.toString().split(".")
			parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
			return parts.join(".")
	}

	CT_Routes -> CT_StartServer()