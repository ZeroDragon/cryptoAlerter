module.exports = (epoch)->
	now = parseInt(new Date().getTime()/1000)
	offset = Math.abs(epoch - now)
	if offset > 0 and offset < 60
		return "#{offset} seconds"
	if offset >= 60
		return "#{Math.floor(offset/60)} minutes"