module.exports = (epoch)->
	now = parseInt(new Date().getTime()/1000)
	offset = epoch - now
	if 0 < offset > 60
		return "#{offset} seconds"
	if 60 < offset > 3600
		return "#{Math.floor(offset/60)} minutes"