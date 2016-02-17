look4Confirmation = ->
	timer = setTimeout ->
		clearTimeout timer
		$.post '/bot/isItConfirmed',{user:$('#username').val()},(data)->
			unless data.confirmed
				look4Confirmation()
	,2000

$ ->
	$('#confirm').click ->
		return if $('#username').val() is ''
		$.post '/bot/askForConfirmation', {user:$('#username').val()}, (data)->
			code = $('#code').text().replace /#####/,data.confirmation
			$('#code').text(code)
			look4Confirmation()
