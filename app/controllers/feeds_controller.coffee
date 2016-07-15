async = require 'async'
feed = require "feed-read"

simplyfy = (feedName,data,cb)->
	data.database ?= {
		_id : feedName
		updated : ~~(new Date().getTime()/1000)
		articles : []
		channels : []
		name : data.source[0].feed.name
		newItem : true
	}
	articles = [].concat data.database.articles,data.source
	diff = {}
	for item in articles
		diff[item.link] = item
	articles = []
	for own k,v of diff
		articles.push v
	articles.sort (a,b)-> b.published - a.published
	data.database.articles = articles[0...10].map (e)->
		return {
			title : e.title
			published : ~~(e.published.getTime()/1000)
			link : e.link
			blogName : e.feed.name
		}
	newItems = data.database.articles.filter (e)->
		e.published > data.database.updated
	data.database.updated = ~~(new Date().getTime()/1000)

	brain.set "feeds", data.database, (err,resp)->
		# data.database.articles = newItems
		cb data.database

exports.update = (req,res)->
	async.series({
		bitcuners : (callback)->
			async.parallel({
				source : (cb)->
					feed "http://blog.bitcuners.org/rss", cb
				database : (cb)->
					brain.get "feeds", {_id:"bitcuners"}, cb
			},(err,data)->
				simplyfy 'bitcuners',data,(feedData)->
					callback null, feedData
			)
	},(err,data)->
		toDo = []
		for own k,v of data
			toDo.push {key:k,value:v}
		toDo = toDo.filter (e)-> e.value.articles.length > 0 and e.value.channels.length > 0

		grouper = {}
		for item in toDo
			for channel in item.value.channels
				grouper[channel] ?= {articles:[],id:item.value._id}
				grouper[channel].articles = grouper[channel].articles.concat item.value.articles

		toDo = []
		for own channel,info of grouper
			toDo.push {channel:channel,articles:info.articles,id:info.id}
		toDo = toDo.map (e)->
			e.articles.sort (a,b)-> b.published - a.published
			e.articles = e.articles[0...10]
			return e

		botModel.sendNews toDo
		res.sendStatus 200
	)