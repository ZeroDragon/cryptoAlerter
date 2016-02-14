main = CT_LoadController 'main'
status = CT_LoadController 'status'

app.get '/', main.home
app.get '/status/:currency.json', status.value
app.get '/status/:currency', status.valueHTML