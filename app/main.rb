require 'sinatra'
require 'slim'
require 'sequel'

require 'base64'
require 'date'

enable :sessions #Cookies

main_db = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://marketshipdev.sqlite')

# Initial database setup
configure do
  main_db.create_table?(:jita_lookups) do
    Integer :typeID, :primary_key => true
    Float :sellLow
    Integer :time
  end

  main_db.create_table?(:accounts) do
    String :charHash, :primary_key => true
    Integer :charID
    String :charName
    Integer :lastLogIn
    String :refreshToken
  end

  main_db.create_table?(:char_apis) do
    Integer :charID, :primary_key => true
    Integer :corpID
    Integer :allianceID
    String :charHash
    Integer :cacheTime
  end

end

# Main DB Classes
class Jita_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Accounts < Sequel::Model(main_db)
  set_primary_key :charHash
end

class Char_api < Sequel::Model(main_db)
  set_primary_key :charID
end

require_relative 'stage1'
require_relative 'stage2'

before do

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  # Refresh character info if cache time expires
  if session[:charHash] and (Char_api[session[:charID]][:cacheTime] + config['logInTimeout']) < Time.now.to_i
    token = EveSSO.refresh(Accounts[session[:charHash]][:refreshToken])
    crest_char = EveSSO.verify(token['access_token'])
    xml_char = EveXML.characterAffiliation([crest_char['CharacterID']])
    # Update databases
    Accounts[session[:charHash]].update(:refreshToken => token['refresh_token'], :lastLogIn => Time.now.to_i)
    Char_api[session[:charID]].update(
        :corpID => xml_char['eveapi']['result']['rowset']['row']['corporationID'],
        :allianceID => xml_char['eveapi']['result']['rowset']['row']['allianceID'],
        :charHash => crest_char['CharacterOwnerHash'],
        :cacheTime => DateTime.parse(xml_char['eveapi']['cachedUntil']).to_time.to_i)
  elsif session[:charHash] == nil # Cookie clean up
    session[:charID] = nil
    session[:charHash] = nil
    session[:charName] = nil
  end

  # Alliance member check
  if session[:charHash] and Char_api[session[:charID]][:allianceID] == config['allianceID']
    session[:allianceMember] = true
  else
    session[:allianceMember] = false
  end

end

# Page authentication checks
set(:auth) do |lowestRole|
  condition do
    if lowestRole == :alliance and session[:allianceMember] == false
      redirect to('/login')
    end
  end
end

get '/' do
  slim :main
end

get '/doctrines', :auth => :alliance do
  slim :doctrines
end

get '/srp', :auth => :alliance do
  slim :srp
end

get '/login' do
  
  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  if params[:code] and (params[:state] == session[:state])
    # If redirected from Eve SSO, retrieve account info
    token = EveSSO.token(params[:code])
    crest_char = EveSSO.verify(token['access_token'])

    # Set cookies for logged in character
    session[:charID] = crest_char['CharacterID']
    session[:charHash] = crest_char['CharacterOwnerHash']
    session[:charName] = crest_char['CharacterName']

    # Update account database
    if Accounts[crest_char['CharacterOwnerHash']].nil?
      Accounts.insert(
          :charHash => crest_char['CharacterOwnerHash'],
          :charID => crest_char['CharacterID'],
          :charName => crest_char['CharacterName'],
          :lastLogIn => Time.now.to_i,
          :refreshToken => token['refresh_token'])
    else
      Accounts[crest_char['CharacterOwnerHash']].update(
          :charID => crest_char['CharacterID'],
          :charName => crest_char['CharacterName'],
          :lastLogIn => Time.now.to_i,
          :refreshToken => token['refresh_token'])
    end

    # Update character api database
    if Char_api[crest_char['CharacterID']].nil?
      xml_char = EveXML.characterAffiliation([crest_char['CharacterID']])
      Char_api.insert(
          :charID => xml_char['eveapi']['result']['rowset']['row']['characterID'],
          :corpID => xml_char['eveapi']['result']['rowset']['row']['corporationID'],
          :allianceID => xml_char['eveapi']['result']['rowset']['row']['allianceID'],
          :charHash => crest_char['CharacterOwnerHash'],
          :cacheTime => DateTime.parse(xml_char['eveapi']['cachedUntil']).to_time.to_i)
    elsif (Char_api[crest_char['CharacterID']][:cacheTime] + config['logInTimeout']) < Time.now.to_i
      xml_char = EveXML.characterAffiliation([crest_char['CharacterID']])
      Char_api[crest_char['CharacterID']].update(
          :corpID => xml_char['eveapi']['result']['rowset']['row']['corporationID'],
          :allianceID => xml_char['eveapi']['result']['rowset']['row']['allianceID'],
          :charHash => crest_char['CharacterOwnerHash'],
          :cacheTime => DateTime.parse(xml_char['eveapi']['cachedUntil']).to_time.to_i)
    end

    # Redirect to home after logging in
    redirect to('/')
  elsif params[:state] and params[:state] != session[:state]
    # If returned state is not correct (Unresolvable Error)
    # Reset character data in cookie
    session[:charID] = nil
    session[:charHash] = nil
    session[:charName] = nil

    # Redirect to home
    redirect to('/')
  else
    # If not logged in, link to eve SSO
    session[:state] = request.ip + ':' + Time.now.to_i.to_s
    redirect('https://login.eveonline.com/oauth/authorize/?response_type=code' +
                 '&redirect_uri=https://betamarketship.herokuapp.com/login' +
                 '&client_id=' + ENV['EVE_CID'] +
                 '&scope=publicData' +
                 '&state=' + session[:state])
  end
end

get '/logout' do
  # Reset character data in cookie
  session[:charID] = nil
  session[:charHash] = nil
  session[:charName] = nil

  redirect to('/')
end

get '/shopping' do
  @initialized = false
  @db_item_hash,@missing_items = nil,[]
  @large_items = 0
  @subtotal = 0
  @eh_bulk_price = 0
  @eh_std_price = 0
  @total_volume = 0
  @total_shipping = 0
  @errors = {}
  slim :shopping
end

post '/shopping' do
  @eft_input = params[:eftInput]
  if params[:eftInput] == ''
    @initialized = false
    @db_item_hash,@missing_items = nil,[]
    @large_items = 0
    @subtotal = 0
    @eh_bulk_price = 0
    @eh_std_price = 0
    @total_volume = 0
    @total_shipping = 0
    @errors = {}
  else
    @initialized = true

    config = {}
    pack_vol = {}
    File.open('configs/config.json', 'r') do |file|
      config = JSON.load(file)
    end
    File.open('configs/packVol.json', 'r') do |file|
      pack_vol = JSON.load(file)
    end

    @large_items = 0
    @subtotal = 0
    @eh_bulk_price = 0
    @eh_std_price = 0
    @total_volume = 0
    @total_shipping = 0
    items_to_pack = {}
    @packages = {}

    @errors = {}

    eft_input = params[:eftInput]
    @db_item_hash,@missing_items = list_parse(eft_input)
    prices = market_lookup(@db_item_hash.keys,10000002)
    @errors[:eveCentral] = prices[:error]
    @db_item_hash.each_key do |key|
      # Add EveCentral Prices
      @db_item_hash[key][:sell] = prices[key]

      # Volume correction for packaged ships
      unless pack_vol[@db_item_hash[key][:typeName]].nil?
        @db_item_hash[key][:volume] = pack_vol[@db_item_hash[key][:typeName]]
      end

      #Per item price calculations
      @db_item_hash[key][:sellTotal] = prices[key] * @db_item_hash[key][:qty]
      @subtotal += prices[key] * @db_item_hash[key][:qty]

      #Order Calculations
      @total_volume += @db_item_hash[key][:volume] * @db_item_hash[key][:qty]
      if @db_item_hash[key][:volume] > config['contractMaxVol']
        @large_items += 1
      end

      #Packaging Setup
      items_to_pack[key] = {:key => key, :qty => @db_item_hash[key][:qty], :vol => @db_item_hash[key][:volume]}
    end

    unless @large_items > 0
      # Packaging
      package_num = 1
      volume_to_pack = @total_volume

      # Break up orders larger than max contract size
      # If last volume of loop is > shippingBulkVol, just use bulk
      while volume_to_pack > config['shippingBulkVol']
        # Set up box
        package_space = config['contractMaxVol']
        @packages[package_num] = {} # Create box inventory
        # Sort by size and check if each item will fit
        items_to_pack.values.sort_by{ |x| x[:vol]}.each do |value|
          qty_packed = 0
          vol_packed = 0
          # Check if the current item fits and item has not run out
          # Put item into box until the item would no longer fit or it ran out of the item
          while value[:vol] < package_space && items_to_pack[value[:key]][:qty] != 0
            items_to_pack[value[:key]][:qty] -= 1
            qty_packed += 1
            package_space -= value[:vol]
            volume_to_pack -= value[:vol]
            vol_packed += value[:vol]
          end
          unless qty_packed == 0
            @packages[package_num][value[:key]] = {:qty => qty_packed,:vol => vol_packed} # Add to box inventory
          end
        end
        package_num += 1
      end
      @eh_bulk_contracts = package_num - 1
      # Repeat for standard contracts
      while volume_to_pack > 0.0024 # Smallest item in the game is 0.0025
        # Set up box
        package_space = config['shippingSeparateVol']
        @packages[package_num] = {} # Create box inventory
        # Sort by size and check if each item will fit
        items_to_pack.values.sort_by{ |x| x[:vol]}.each do |value|
          qty_packed = 0
          vol_packed = 0
          # Check if the current item fits and item has not run out
          # Put item into box until the item would no longer fit or it ran out of the item
          while value[:vol] < package_space && items_to_pack[value[:key]][:qty] != 0
            items_to_pack[value[:key]][:qty] -= 1
            qty_packed += 1
            package_space -= value[:vol]
            volume_to_pack -= value[:vol]
            vol_packed += value[:vol]
          end
          unless qty_packed == 0
            @packages[package_num][value[:key]] = {:qty => qty_packed,:vol => vol_packed} # Add to box inventory
          end
        end
        package_num += 1
      end
      @eh_std_contracts = package_num - 1 - @eh_bulk_contracts

      # Box Volume Totals
      @package_vol = {}
      @package_std_vol = 0
      @packages.each do |number,package|
        @package_vol[number] = 0
        package.each_key do |key|
          @package_vol[number] += package[key][:vol]
          if number > @eh_bulk_contracts
            @package_std_vol += package[key][:vol]
          end
        end
      end

      # EH price calculations
      @eh_std_price = @package_std_vol * config['jitaShippingRate']
      @eh_bulk_price = @eh_bulk_contracts * config['shippingBulkVol'] * config['jitaShippingRate']
      @total_shipping = @eh_bulk_price + @eh_std_price
      if @total_shipping < config['minShippingPrice']
        @total_shipping = config['minShippingPrice']
      end
    end
  end
  slim :shopping
end
