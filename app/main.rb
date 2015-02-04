require 'sinatra'
require 'slim'
require 'sequel'

#Primary DB Connection
#primaryDB = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://marketshipdev.sqlite')

get '/about/:input' do
  @param1= params[:input]
  slim :about
end

get '/:input' do
  @param1 = params[:input]
  slim :index
end

get '/' do
  @db_item_list = nil
  slim :test
end

post '/' do
  eft_input = params[:eftInput]
  @db_item_list = list_parse(eft_input)
  slim :test
end

def list_parse(eft_input)
  # Initializations
  parse_list = []
  item_list = []
  count_list = Hash.new

  # EVE SDE Database Connection and Tables
  eve_db = Sequel.connect(ENV['EVE_SDE'] || 'sqlite://eveDBSlim.sqlite')
  inv_types = eve_db[:invTypes]
  dgm_type_effects = eve_db[:dgmTypeEffects]

  # User Input Cleanup
  eft_split = eft_input.strip.delete("\r").split("\n")

  # Module Separation
  ## for eft
  if eft_split[0][0] == '['
    eft_ship = eft_split[0].delete('[]').split(',')[0] # First line: Ship Parsing
    eft_items = [eft_ship] + eft_split.drop(1)
  else
    eft_items = eft_split
  end
  eft_items.each do |item|
    ## Empty slot and empty line removal
    if item[0] == '[' or item == ''
      next
    end
    ## Module and Ammo separation
    if item.include? ','
      parse_list += [item.split(',')[0],item.split(',')[1].strip]
    else
      parse_list += [item]
    end
  end

  # Module Counting
  parse_list.each do |item|
    # Remove x# from end
    clean_item = item.gsub(/ x\d+$/,'')
    unless item_list.include? clean_item
      item_list += [clean_item]
    end

    # Add # to qty
    if item =~ / x\d+$/
      if count_list[clean_item] != nil
        count_list[clean_item] += item.match(/ x(\d+)$/).captures[0].to_i
      else
        count_list[clean_item] = item.match(/ x(\d+)$/).captures[0].to_i
      end
    elsif count_list[clean_item] != nil
      count_list[clean_item] += 1
    else
      count_list[clean_item] = 1
    end
  end

  # Database Retrieval
  db_item_list = inv_types.select(:typeID,:typeName,:volume).where(:typeName => item_list).to_hash(:typeID)
  ## Extra Value Additions
  item_ids = db_item_list.keys
  db_item_effects = dgm_type_effects.where(:typeID => item_ids).to_hash_groups(:typeID,:effectID)
  db_item_list.each do |key,value|
    ###Slot Identification
    if db_item_effects[key].include? 11 # Low slot
      db_item_list[key][:slot] = 'low'
    elsif db_item_effects[key].include? 12 # High slot
      db_item_list[key][:slot] = 'high'
    elsif db_item_effects[key].include? 13 # Mid slot
      db_item_list[key][:slot] = 'mid'
    elsif db_item_effects[key].include? 2663 # Rig slot
      db_item_list[key][:slot] = 'rig'
    elsif db_item_effects[key].include? 3772 # Subsystem slot
      db_item_list[key][:slot] = 'sub'
    else
      db_item_list[key][:slot] = 'none'
    end
    ###Quantity
    db_item_list[key][:qty] = count_list[value[:typeName]]
  end

  db_item_list # Return Value
end
