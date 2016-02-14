arr = []
saveArr = ->
	localStorage.bitcoinAlerter = JSON.stringify(arr)
	$('header .status .fa-save').addClass('active')
	setTimeout ->
		$('header .status .fa-save').removeClass('active')
	,100

loadArr = ->
	memArr = localStorage.bitcoinAlerter
	if memArr?
		arr = JSON.parse(memArr)
	else
		arr = []

populateItems = ->
	for item in arr
		((coin)->
			if $("##{coin}").length is 0
				$('.items').append("<div class='item' id='#{coin}'></div>")
			$('header .status .fa-refresh').addClass('active')
			$.get "/status/#{coin}", (html)->
				$("##{coin}").html html
				$('header .status .fa-refresh').removeClass('active')
		)(item)
uniques = (a)-> a.filter (e,i,s)-> s.indexOf(e) is i

delItem = (coin)->
	arr = arr.filter (e)-> e isnt coin
	$("##{coin}").remove()
	populateItems()
	saveArr()
addItem = (val)->
	arr.push val
	arr = uniques arr
	populateItems()
	saveArr()

reCharge = ->
	timer = setTimeout ->
		clearTimeout timer
		populateItems()
		reCharge()
	,15*1000

$ ->
	loadArr()
	populateItems()
	reCharge()