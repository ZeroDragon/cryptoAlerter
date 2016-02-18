getfromMemory = -> JSON.parse(localStorage.bitcoinAlerterAlerts ?= '{}')
saveToMemory = (d)-> localStorage.bitcoinAlerterAlerts = JSON.stringify(d)

look4Confirmation = ->
	timer = setTimeout ->
		clearTimeout timer
		$.post '/bot/isItConfirmed',{user:$('#username').val()},(data)->
			if data.id?
				saveToMemory data
				showUser()
			else
				look4Confirmation()
			return
	,2000
	return

reloadInfo = ->
	fromMem = getfromMemory()
	$.post '/bot/reloadUser',{user:fromMem.username},(data)->
		saveToMemory data
		window.location.href = window.location.href
	return

logout = ->
	delete localStorage.bitcoinAlerterAlerts
	window.location.href = window.location.href
	return

addZ = (i)-> ('00'+i).slice(-2)

showUser = ->
	fromMem = getfromMemory()
	t = $('.accountStatus').html()
	t = t.replace(/#username/,fromMem.username).replace(/#status/,fromMem.active)

	$('.message.inactive').show() if fromMem.active is 'Limited'
	if fromMem.active isnt 'Limited'
		d = new Date(fromMem.expiration*1000)
		expDate = "#{addZ(d.getMonth()+1)}/#{addZ(d.getDate())}/#{d.getFullYear()}"
		t = t.replace(/untill/,expDate)

	$('.alerts').html ''
	alerts = []
	for own kk,vv of fromMem.currencies
		((k,v)->
			template = $('.template').clone()
			h = template.html()
			h = h.replace(/NAME/g,v.name)
			h = h.replace(/CODE/g,k)
			template.html h

			template.find('.alertInput').each ->
				k = $(@).data('name')
				if $(@).is(':checkbox')
					$(@).prop({checked:v[k]})
				else
					$(@).val v[k]

			alerts.push template
			)(kk,vv)

	for alert in alerts
		$('.alerts').append alert

	$('.accountStatus').html t
	$('#needLogin').hide()
	$('#loggedIn').show()
	return

deleteAlert = (code)->
	fromMem = getfromMemory()
	delete fromMem.currencies[code]
	saveToMemory fromMem
	showUser()
	return

saveToBot = ->
	$.post '/bot/saveAlerts', {payload:getfromMemory()}, (data)->
		console.log data

saveValues = ->
	currencies = {}
	$('.alerts .alertInput').each ->
		val = $(@).val()
		if $(@).attr('type') is 'checkbox'
			val = $(@).is(':checked')
		currencies[$(@).data('coin')] ?= {}
		currencies[$(@).data('coin')][$(@).data('name')] = val
		return
	fromMem = getfromMemory()
	fromMem.currencies = currencies
	saveToMemory fromMem
	showUser()
	saveToBot()
	return

$ ->
	fromMem = getfromMemory()
	if !fromMem.id
		$('#needLogin').show()
	else
		showUser()
	$('#confirm').click ->
		return if $('#username').val() is ''
		$.post '/bot/askForConfirmation', {user:$('#username').val()}, (data)->
			code = $('#code').text().replace /#####/,data.confirmation
			$('#code').text(code)
			$('.row.login').hide()
			$('.row.message').show()
			look4Confirmation()
			return
		return

	$('#adder').click ->
		fromMem = getfromMemory()
		currency = $('#coinSelector').val().split('|')
		fromMem.currencies[currency[0]] ?= {
			name : currency[1]
			'minimum-active' : false
			'minimum-value' : null
			'maximum-active' : false
			'maximum-value' : null
			sell : false
			buy : false
			rising : false
			declining : false
		}
		saveToMemory fromMem
		showUser()
		return
	return