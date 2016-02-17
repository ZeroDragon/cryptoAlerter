# Commands:
# This is just a placeholder

module.exports = (robot) ->
	robot.respond /help$/i, (res)->
		res.send """
			/start: Will start a relation with you
			/end: Don't want me anymore?
		"""
	robot.respond /start$/i, (res)->
		username = res.envelope.user.username
		name = res.envelope.user.name
		room = res.envelope.user.id
		res.send "Started a relation with @#{username} ❤️"

	robot.respond /stop$/i, (res)->
		username = res.envelope.user.username
		name = res.envelope.user.name
		room = res.envelope.user.id
		res.send "@#{username}: We are not anymore together 💔"