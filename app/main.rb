require 'sinatra'
require 'slim'
require 'sequel'

require 'base64'
require 'date'

enable :sessions #Cookies

main_db = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://dev.sqlite')

# Initial database setup
configure do

  main_db.create_table?(:jita_lookups) do
    Integer :typeID, :primary_key => true
    Float :sellLow
    Integer :time
  end

  main_db.create_table?(:hek_lookups) do
    Integer :typeID, :primary_key => true
    Float :sellLow
    Integer :time
  end

  main_db.create_table?(:amarr_lookups) do
    Integer :typeID, :primary_key => true
    Float :sellLow
    Integer :time
  end

  main_db.create_table?(:dodixie_lookups) do
    Integer :typeID, :primary_key => true
    Float :sellLow
    Integer :time
  end

  main_db.create_table?(:rens_lookups) do
    Integer :typeID, :primary_key => true
    Float :sellLow
    Integer :time
  end

  main_db.create_table?(:staging_lookups) do
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
    String :charName
    Integer :corpID
    String :corpName
    Integer :allianceID
    String :allianceName
    String :charHash
    Integer :cacheTime
  end

  main_db.create_table?(:key_apis) do
    Integer :charID, :primary_key => true
    String :charName
    Integer :corpID
    String :corpName
    Integer :allianceID
    String :allianceName
    String :charHash
    Integer :cacheTime
    Integer :keyID
    String :vCode
    Integer :expiration
    Integer :kmCache, :default => 0
  end

  main_db.create_table?(:srp_requests) do
    Integer :killID, :primary_key => true
    Integer :lossDate
    Integer :ship
    String :fc
    String :jabber
    String :comments
    String :status, :default => 'Not Submitted'
    String :charHash
    Float :calcPayoutStrat
    Float :calcPayoutPeace
    Float :actualPayout, :default => 0
    String :opType
    Integer :submissionDate
    String :charName
    String :corpName
    String :approver
    String :payer
    String :srpComments
  end

  main_db.create_table?(:kill_items) do
    Integer :killID
    Integer :typeID
    Integer :qty
    Float :jita
    Float :amarr
    Float :dodixie
    Float :hek
    Float :rens
    Float :staging
    primary_key [:killID, :typeID]
  end

end

# Main DB Classes
class Jita_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Hek_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Amarr_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Dodixie_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Rens_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Staging_lookup < Sequel::Model(main_db)
  set_primary_key :typeID
end

class Accounts < Sequel::Model(main_db)
  set_primary_key :charHash
end

class Char_api < Sequel::Model(main_db)
  set_primary_key :charID
end

class Key_api < Sequel::Model(main_db)
  set_primary_key :charID
end

class Srp_request < Sequel::Model(main_db)
  set_primary_key :killID
end

class Kill_item < Sequel::Model(main_db)
  set_primary_key [:killID, :typeID]
end

require_relative 'stage1'
require_relative 'stage2'

before do

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  roles = {}
  # Read Roles [TEMPORARY]
  File.open('configs/roles.json', 'r') do |file|
    roles = JSON.load(file)
  end

  # Refresh character info if cache time expires
  if session[:charHash] and (Char_api[session[:charID]][:cacheTime] + config['logInTimeout']) < Time.now.to_i
    token = EveSSO.refresh(Accounts[session[:charHash]][:refreshToken])
    crest_char = EveSSO.verify(token['access_token'])
    xml_char = EveXML.character_affiliation([crest_char['CharacterID']])
    # Update databases
    Accounts[session[:charHash]].update(:refreshToken => token['refresh_token'], :lastLogIn => Time.now.to_i)
    Char_api[session[:charID]].update(
        :corpID => xml_char['eveapi']['result']['rowset']['row']['corporationID'],
        :corpName => xml_char['eveapi']['result']['rowset']['row']['corporationName'],
        :allianceID => xml_char['eveapi']['result']['rowset']['row']['allianceID'],
        :allianceName => xml_char['eveapi']['result']['rowset']['row']['allianceName'],
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

  # Roles check [TEMPORARY]
  if roles[session[:charID].to_s]
    session[:srp] = roles[session[:charID].to_s]['srp']
  else
    session[:srp] = 0
  end

  # Bypass login for development
  unless ENV['DATABASE_URL']
    session[:charHash] = nil # Must be nil
    session[:charName] = 'Test Member'
    session[:charID] = 94074701

    session[:allianceMember] = true
    session[:srp] = 1
  end

end

# Page authentication only checks
set(:auth) do |lowestRole|
  condition do
    if lowestRole == :alliance and session[:allianceMember] == false
      redirect to('/login')
    end
  end
end

# Page API checks w/ Authentication
set(:api) do |lowestRole|
  condition do
    if lowestRole == :alliance and session[:allianceMember] == false
      redirect to('/login')
    elsif not refresh_keys(session[:charHash])
      redirect to('/api?error=invalidAPI')
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
  eve_db = Sequel.connect(ENV['EVE_SDE'] || 'sqlite://eveDBSlim.sqlite')
  @inv_types = eve_db[:invTypes]
  @srp_list = Srp_request
  @srp_list.each do |item|
    puts item[:submissionDate]
  end
  slim :srp
end

get '/srp/request', :api => :alliance do

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  # Kill Mail Retrieval
  Key_api.where(:charHash => session[:charHash], :allianceID => config['allianceID']).all.each do |char|
    if char[:kmCache] + config['killMailUpdateTime'] < Time.now.to_i

      kill_mails = EveXML.kill_mails(char[:keyID],char[:vCode],char[:charID])
      Key_api[char[:charID]].update(:kmCache => DateTime.parse(kill_mails['eveapi']['cachedUntil']).to_time.to_i)

      ensure_array(kill_mails['eveapi']['result']['rowset']['row']).each do |kill|
        if kill['victim']['characterID'].to_i == char[:charID] # If character is victim
          if Srp_request[kill['killID']].nil?
            Srp_request.insert(
                :killID => kill['killID'],
                :lossDate => DateTime.parse(kill['killTime']).to_time.to_i,
                :ship => kill['victim']['shipTypeID'],
                :charHash => session[:charHash],
                :charName => kill['victim']['characterName'],
                :corpName => kill['victim']['corporationName'])
            unless kill['victim']['shipTypeID'].to_i == 670 || kill['victim']['shipTypeID'].to_i == 33328 # Capsules
              Kill_item.insert(:killID => kill['killID'], :typeID => kill['victim']['shipTypeID'], :qty => 1)
            end

            ensure_array(kill['rowset'][1]['row']).each do |item|
              if srp_flag(item['flag'])
                if Kill_item[kill['killID'], item['typeID']].nil?
                  Kill_item.insert(
                    :killID => kill['killID'],
                    :typeID => item['typeID'],
                    :qty => item['qtyDropped'].to_i + item['qtyDestroyed'].to_i)
                else
                  Kill_item[kill['killID'], item['typeID']].update(
                      :qty => Kill_item[kill['killID'], item['typeID']][:qty] +
                          item['qtyDropped'].to_i + item['qtyDestroyed'].to_i)
                end
              end
            end
          else
            Srp_request[kill['killID']].update(:charHash => session[:charHash])
          end
        end
      end

    end
  end

  eve_db = Sequel.connect(ENV['EVE_SDE'] || 'sqlite://eveDBSlim.sqlite')
  @inv_types = eve_db[:invTypes]

  if params[:killID] # If kill is selected
    # Lookup Prices
    @item_prices = {}
    [10000002,10000042,10000043,10000032,10000030,config['stagingSystem'].to_i].each do |region|
      market_lookup(Kill_item.where(:killID => params[:killID]).map(:typeID),region)
    end

    Kill_item.where(:killID => params[:killID]).all.each do |item|
      @item_prices[item[:typeID]] = {}
      @item_prices[item[:typeID]][:qty] = item[:qty]
      @item_prices[item[:typeID]][:jita] = {:price => Jita_lookup[item[:typeID]][:sellLow]}
      @item_prices[item[:typeID]][:amarr] = {:price => Amarr_lookup[item[:typeID]][:sellLow]}
      @item_prices[item[:typeID]][:dodixie] = {:price => Dodixie_lookup[item[:typeID]][:sellLow]}
      @item_prices[item[:typeID]][:hek] = {:price => Hek_lookup[item[:typeID]][:sellLow]}
      @item_prices[item[:typeID]][:rens] = {:price => Rens_lookup[item[:typeID]][:sellLow]}
      @item_prices[item[:typeID]][:staging] = {:price => Staging_lookup[item[:typeID]][:sellLow]}

      # Freeze Prices
      Kill_item[params[:killID],item[:typeID]].update(
          :jita => Jita_lookup[item[:typeID]][:sellLow],
          :amarr => Amarr_lookup[item[:typeID]][:sellLow],
          :dodixie => Dodixie_lookup[item[:typeID]][:sellLow],
          :hek => Hek_lookup[item[:typeID]][:sellLow],
          :rens => Rens_lookup[item[:typeID]][:sellLow],
          :staging => Staging_lookup[item[:typeID]][:sellLow])
    end

    # Average Calculation
    @item_prices.each do |id,item|
      total_regions = 0
      num_regions = 0
      item.each do |region,info|
        unless region == :qty
          if info[:price].between?(@item_prices[id][:jita][:price]*(1-config['percentIgnoreHigh'].to_f/100),
                                   @item_prices[id][:jita][:price]*(1+config['percentIgnoreLow'].to_f/100))
            @item_prices[id][region][:ignore] = false
            total_regions += info[:price]
            num_regions += 1
          else
            @item_prices[id][region][:ignore] = true
          end
        end
      end
      @item_prices[id][:average] = total_regions.to_f/num_regions * item[:qty]
    end

    # Total Module + Hull
    @fittings = 0
    @item_prices.each_key do |id|
      @fittings += @item_prices[id][:average]
    end

    # SRP Additions

    # Read Insurances
    insurance = {}
    File.open('configs/insurance.json', 'r') do |file|
      insurance = JSON.load(file)
    end
    # Read Special Rates
    special_srp = {}
    File.open('configs/specialSrp.json', 'r') do |file|
      special_srp = JSON.load(file)
    end

    srp_types = {}
    File.open('configs/srpTypes.json', 'r') do |file|
      srp_types = JSON.load(file)
    end
    # Determine Modifiers
    @srp_modifier_type = 'None'
    @srp_modifier_value = 0

    ship_name = @inv_types.where(:typeID => Srp_request[params[:killID]][:ship]).first[:typeName]
    @srp_insurance = (insurance[ship_name] || 0) * 0.7
    fixed = false
    if special_srp[ship_name].nil?
      @srp_modifier_type = 'None'
      @srp_modifier_value = 0
    else
      @srp_modifier_type = special_srp[ship_name]
      if special_srp[ship_name] == 'Fixed'
        @srp_modifier_value = srp_types['Fixed'][ship_name]
        fixed = true
      else
        if srp_types[special_srp[ship_name]].is_a?(String)
          @srp_modifier_value = srp_types[special_srp[ship_name]].chop.to_f/100
        else # Is a number
          @srp_modifier_value = srp_types[special_srp[ship_name]]
          fixed = true
        end
      end
    end

    # Determine Payout
    @payout_peace = 0
    @payout_strategic = 0
    @peacetime_percent = config['peacetimePercent']
    @strategic_percent = config['strategicPercent']
    case @srp_modifier_type
    when 'None'
      @payout_peace = @fittings * @peacetime_percent - @srp_insurance
      @payout_strategic = @fittings * @strategic_percent - @srp_insurance
    else
      if fixed # Fixed Price
        @payout_peace = @srp_modifier_value - @srp_insurance
        @payout_strategic = nil
      else # Special User Defined
        @payout_peace = @fittings * @srp_modifier_value - @srp_insurance
        @payout_strategic = nil
      end
    end

    # Rounding
    if @payout_peace.to_i / 100000 == 0
      @actual_payout_peace = @payout_peace.to_i / 100 * 100
    else
      @actual_payout_peace = @payout_peace.to_i / 100000 * 100000
    end
    unless @payout_strategic.nil?
      if @payout_strategic.to_i / 100000 == 0
        @actual_payout_strategic = @payout_strategic.to_i / 100 * 100
      else
        @actual_payout_strategic = @payout_strategic.to_i / 100000 * 100000
      end
    end

    # Record Calculations
    actual_payout = 0
    if @payout_strategic.nil?
      actual_payout = @actual_payout_peace
    end
    Srp_request[params[:killID]].update(
        :calcPayoutStrat => @actual_payout_strategic || @actual_payout_peace,
        :calcPayoutPeace => @actual_payout_peace,
        :actualPayout => actual_payout,
        :opType => @srp_modifier_type)

    @killID = params[:killID]

  elsif params[:delete]
    if Srp_request[params[:delete]][:status] == 'Submitted'
      Srp_request[params[:delete]].update(
          :status => 'Not Submitted',
          :fc => nil,
          :jabber => nil,
          :comments => nil,
          :submissionDate => nil,
          :calcPayoutStrat => nil,
          :calcPayoutPeace => nil,
          :opType => nil)
    end

    @item_prices = nil
    @fittings = 0
    @srp_modifier_type = 'None'
    @srp_modifier_value = 0
    @payout = 0
    @srp_insurance = 0

  else
    @item_prices = nil
    @fittings = 0
    @srp_modifier_type = 'None'
    @srp_modifier_value = 0
    @payout = 0
    @srp_insurance = 0
  end

  @kill_mails = Srp_request.where(:charHash => session[:charHash]).all

  slim :srp_request
end

post '/srp/request', :api => :alliance do
  if Srp_request[params[:killID]][:status] == 'Not Submitted' or Srp_request[params[:killID]][:status] == 'Rejected'
    Srp_request[params[:killID]].update(
                                    :status => 'Submitted',
                                    :fc => params[:fc],
                                    :jabber => params[:ping],
                                    :comments => params[:comments],
                                    :submissionDate => Time.now.to_i
    )
  end
  redirect to('/srp/receipt?killID=' + params[:killID])
end

get '/srp/receipt', :auth => :alliance do

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  eve_db = Sequel.connect(ENV['EVE_SDE'] || 'sqlite://eveDBSlim.sqlite')
  @inv_types = eve_db[:invTypes]

  @killID = params[:killID]
  @srp_request = Srp_request[params[:killID]]

  @item_prices = {}
  Kill_item.where(:killID => params[:killID]).all.each do |item|
    @item_prices[item[:typeID]] = {}
    @item_prices[item[:typeID]][:qty] = item[:qty]
    @item_prices[item[:typeID]][:jita] = {:price => item[:jita]}
    @item_prices[item[:typeID]][:amarr] = {:price => item[:amarr]}
    @item_prices[item[:typeID]][:dodixie] = {:price => item[:dodixie]}
    @item_prices[item[:typeID]][:hek] = {:price => item[:hek]}
    @item_prices[item[:typeID]][:rens] = {:price => item[:rens]}
    @item_prices[item[:typeID]][:staging] = {:price => item[:staging]}
  end

  # Average Calculation
  @item_prices.each do |id,item|
    total_regions = 0
    num_regions = 0
    item.each do |region,info|
      unless region == :qty
        if info[:price].between?(@item_prices[id][:jita][:price]*(1-config['percentIgnoreHigh'].to_f/100),
                                 @item_prices[id][:jita][:price]*(1+config['percentIgnoreLow'].to_f/100))
          @item_prices[id][region][:ignore] = false
          total_regions += info[:price]
          num_regions += 1
        else
          @item_prices[id][region][:ignore] = true
        end
      end
    end
    @item_prices[id][:average] = total_regions.to_f/num_regions * item[:qty]
  end

  # Total Module + Hull
  @fittings = 0
  @item_prices.each_key do |id|
    @fittings += @item_prices[id][:average]
  end

  # SRP Additions

  # Read Insurances
  insurance = {}
  File.open('configs/insurance.json', 'r') do |file|
    insurance = JSON.load(file)
  end
  # Read Special Rates
  special_srp = {}
  File.open('configs/specialSrp.json', 'r') do |file|
    special_srp = JSON.load(file)
  end

  srp_types = {}
  File.open('configs/srpTypes.json', 'r') do |file|
    srp_types = JSON.load(file)
  end

  @srp_types_array = srp_types.keys

  # Determine Modifiers
  @srp_modifier_type = 'None'
  @srp_modifier_value = 0

  ship_name = @inv_types.where(:typeID => Srp_request[params[:killID]][:ship]).first[:typeName]
  @srp_insurance = (insurance[ship_name] || 0) * 0.7
  fixed = false
  if special_srp[ship_name].nil?
    @srp_modifier_type = 'None'
    @srp_modifier_value = 0
  else
    @srp_modifier_type = special_srp[ship_name]
    if special_srp[ship_name] == 'Fixed'
      @srp_modifier_value = srp_types['Fixed'][ship_name]
      fixed = true
    else
      if srp_types[special_srp[ship_name]].is_a?(String)
        @srp_modifier_value = srp_types[special_srp[ship_name]].chop.to_f/100
      else # Is a number
        @srp_modifier_value = srp_types[special_srp[ship_name]]
        fixed = true
      end
    end
  end

  # Determine Payout
  @payout_peace = 0
  @payout_strategic = 0
  @peacetime_percent = config['peacetimePercent']
  @strategic_percent = config['strategicPercent']
  case @srp_modifier_type
    when 'None'
      @payout_peace = @fittings * @peacetime_percent - @srp_insurance
      @payout_strategic = @fittings * @strategic_percent - @srp_insurance
    else
      if fixed # Fixed Price
        @payout_peace = @srp_modifier_value - @srp_insurance
        @payout_strategic = nil
      else # Special User Defined
        @payout_peace = @fittings * @srp_modifier_value - @srp_insurance
        @payout_strategic = nil
      end
  end

  # Rounding
  if @payout_peace.to_i / 100000 == 0
    @actual_payout_peace = @payout_peace.to_i / 100 * 100
  else
    @actual_payout_peace = @payout_peace.to_i / 100000 * 100000
  end
  unless @payout_strategic.nil?
    if @payout_strategic.to_i / 100000 == 0
      @actual_payout_strategic = @payout_strategic.to_i / 100 * 100
    else
      @actual_payout_strategic = @payout_strategic.to_i / 100000 * 100000
    end
  end

  # Roles
  @srp_role = session[:srp]

  slim :srp_receipt
end

post '/srp/receipt', :auth => :alliance do
  case params[:action]
  when 'Rejected'
    if session[:srp] > 0
      Srp_request[params[:killID]].update(
          :opType => params[:opType],
          :actualPayout => params[:price].delete(','),
          :srpComments => params[:srpComment],
          :approver => session[:charName],
          :status => 'Rejected')
    end
  when 'Approved'
    if session[:srp] > 0
      Srp_request[params[:killID]].update(
          :opType => params[:opType],
          :actualPayout => params[:price].delete(','),
          :srpComments => params[:srpComment],
          :approver => session[:charName],
          :status => 'Approved')
    end
  when 'Paid'
    if session[:srp] > 1
      Srp_request[params[:killID]].update(
          :opType => params[:opType],
          :actualPayout => params[:price].delete(','),
          :srpComments => params[:srpComment],
          :payer => session[:charName],
          :status => 'Paid')
      if Srp_request[params[:killID]][:approver].nil?
        Srp_request[params[:killID]].update(:approver => session[:charName])
      end
    end
  else
    redirect to('/srp')
  end
  redirect to('/srp/receipt?killID=' + params[:killID])
end

get '/api', :auth => :alliance do

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end
  @alliance_check = config['allianceID'].to_i

  @errors = {}
  if params[:error] == 'invalidAPI'
    @errors[:key] = true
  else
    @errors = nil
  end
  if params[:delete] and Key_api[params[:delete]][:charHash] == session[:charHash]
    Key_api[params[:delete]].delete
  end
  @db_char_hash = Key_api.where(:charHash => session[:charHash]).all

  slim :api
end

post '/api', :auth => :alliance do

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end
  @alliance_check = config['allianceID']

  api_info = EveXML.api_key_info(params[:keyID],params[:vCode])
  @errors = {}

  # Update character api database
  if api_info['eveapi']['error']
    @errors[:key] = true
  else
    @errors = nil
    ensure_array(api_info['eveapi']['result']['key']['rowset']['row']).each do |character|
      if api_info['eveapi']['result']['key']['expires'].empty?
        expiration = '1970-01-01 00:00:00'# Epoch 0 = Never
      else
        expiration = api_info['eveapi']['result']['key']['expires']
      end
      if Key_api[character['characterID'].to_i].nil?
        Key_api.insert(
            :charID => character['characterID'],
            :charName => character['characterName'],
            :corpID => character['corporationID'],
            :corpName => character['corporationName'],
            :allianceID => character['allianceID'],
            :allianceName => character['allianceName'],
            :charHash => session[:charHash],
            :cacheTime => DateTime.parse(api_info['eveapi']['cachedUntil']).to_time.to_i,
            :keyID => params[:keyID],
            :vCode => params[:vCode],
            :expiration => DateTime.parse(expiration).to_time.to_i)
      else
        Key_api[character['characterID']].update(
            :corpID => character['corporationID'],
            :corpName => character['corporationName'],
            :allianceID => character['allianceID'],
            :allianceName => character['allianceName'],
            :charHash => session[:charHash],
            :cacheTime => DateTime.parse(api_info['eveapi']['cachedUntil']).to_time.to_i,
            :keyID => params[:keyID],
            :vCode => params[:vCode],
            :expiration => DateTime.parse(expiration).to_time.to_i) # Epoch 0 = Never
      end
    end
  end
  @db_char_hash = Key_api.where(:charHash => session[:charHash]).all

  slim :api
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
      xml_char = EveXML.character_affiliation([crest_char['CharacterID']])
      Char_api.insert(
          :charID => xml_char['eveapi']['result']['rowset']['row']['characterID'],
          :charName => xml_char['eveapi']['result']['rowset']['row']['characterName'],
          :corpID => xml_char['eveapi']['result']['rowset']['row']['corporationID'],
          :corpName => xml_char['eveapi']['result']['rowset']['row']['corporationName'],
          :allianceID => xml_char['eveapi']['result']['rowset']['row']['allianceID'],
          :allianceName => xml_char['eveapi']['result']['rowset']['row']['allianceName'],
          :charHash => crest_char['CharacterOwnerHash'],
          :cacheTime => DateTime.parse(xml_char['eveapi']['cachedUntil']).to_time.to_i)
    elsif (Char_api[crest_char['CharacterID']][:cacheTime] + config['logInTimeout']) < Time.now.to_i
      xml_char = EveXML.character_affiliation([crest_char['CharacterID']])
      Char_api[crest_char['CharacterID']].update(
          :corpID => xml_char['eveapi']['result']['rowset']['row']['corporationID'],
          :corpName => xml_char['eveapi']['result']['rowset']['row']['corporationName'],
          :allianceID => xml_char['eveapi']['result']['rowset']['row']['allianceID'],
          :allianceName => xml_char['eveapi']['result']['rowset']['row']['allianceName'],
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
