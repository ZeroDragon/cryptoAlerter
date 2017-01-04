main = CT_LoadController 'main'
status = CT_LoadController 'status'
alerts = CT_LoadController 'alerts'

app.get '/', main.home
app.get '/status/:currency.json', status.value
app.get '/status/:currency/:inline?', status.valueHTML
app.get '/chart/:currency', status.valueImage
app.get '/trends', status.trends
app.get '/alerts', alerts.main
app.get '/unlimited', alerts.unlimited
app.get '/sendTweet', alerts.sendTweet

app.post '/bot/askForConfirmation', alerts.askForConfirmation
app.post '/bot/isItConfirmed', alerts.isItConfirmed
app.post '/bot/reloadUser', alerts.reloadUser
app.post '/bot/saveAlerts', alerts.saveUserAlerts

app.get '/bot/triggerAlerts/:type', alerts.triggerAlerts