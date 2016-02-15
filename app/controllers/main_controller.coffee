crypto = CT_LoadModel 'crypto'

exports.home = (req,res)->
	crypto.getRates (rates)->
		coins = []
		for rate in rates
			coins.push {name:rate.name,code:rate.code}
		coins.sort (a,b)->
			return -1 if b.name > a.name
			return 1 if b.name < a.name
			return 0
		res.render CT_Static + '/main/index.jade',{
			coins:coins,
			pretty:true
		}