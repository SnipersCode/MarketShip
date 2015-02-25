# Stage 1 Shopping List - Jita Import

require 'sequel'
require 'httparty'

def list_parse(eft_input)
  # Initializations
  parse_list = []
  item_list = []
  count_hash = {}
  cmds = {:repeat => 1}

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
    eft_ship = nil
    eft_items = eft_split
  end
  eft_items.each do |item|
    ## Empty slot and empty line removal
    if item[0] == '[' or item == ''
      next
    end
    ## Extract Commands
    if item[0] == '/'
      if item =~ /repeat/
        cmds[:repeat] = item.match(/ (\d+)$/).captures[0].to_i
      end
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
      if count_hash[clean_item] != nil
        count_hash[clean_item] += item.match(/ x(\d+)$/).captures[0].to_i * cmds[:repeat]
      else
        count_hash[clean_item] = item.match(/ x(\d+)$/).captures[0].to_i * cmds[:repeat]
      end
    elsif count_hash[clean_item] != nil
      count_hash[clean_item] += cmds[:repeat]
    else
      count_hash[clean_item] = cmds[:repeat]
    end
  end

  # Database Retrieval
  db_item_hash = inv_types.select(:typeID,:typeName,:volume).where(:typeName => item_list).to_hash(:typeID)
  db_name_list = inv_types.where(:typeName => item_list).map(:typeName)
  ## Extra Value Additions
  item_ids = db_item_hash.keys
  db_item_effects = dgm_type_effects.where(:typeID => item_ids).to_hash_groups(:typeID,:effectID)
  db_item_hash.each do |key,value|
    ###Slot Identification
    if db_item_effects[key] == nil # Catch for items that do not have an effect
      db_item_hash[key][:slot] = 'none'
    elsif db_item_effects[key].include? 11 # Low slot
      db_item_hash[key][:slot] = 'low'
    elsif db_item_effects[key].include? 12 # High slot
      db_item_hash[key][:slot] = 'high'
    elsif db_item_effects[key].include? 13 # Mid slot
      db_item_hash[key][:slot] = 'mid'
    elsif db_item_effects[key].include? 2663 # Rig slot
      db_item_hash[key][:slot] = 'rig'
    elsif db_item_effects[key].include? 3772 # Subsystem slot
      db_item_hash[key][:slot] = 'sub'
    elsif value[:typeName] == eft_ship # Ship if EFT Parsing was used
      db_item_hash[key][:slot] = 'ship'
    else
      db_item_hash[key][:slot] = 'none'
    end
    ###Quantity
    db_item_hash[key][:qty] = count_hash[value[:typeName]]
  end

  # Check for Missing Items
  missing_items = item_list - db_name_list

  return db_item_hash,missing_items

end

class EveCentral
  include HTTParty
  format :json
  base_uri 'http://api.eve-central.com/api'
  disable_rails_query_string_format

  def self.market_stat(id_list,region_id)
    get('/marketstat/json', :query => {:typeid => id_list,:regionlimit => region_id})
  end

end

def market_lookup(id_list, region_id)

  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  refresh_list = []
  price_hash = {}
  time_hash = {}

  price_hash[:error] = nil

  # Check whether to refresh or use database data
  id_list.each do |id|
    item = Jita_lookup[id]
    if item.nil? or (item[:time] + config['marketUpdateTime']) < Time.now.to_i
      refresh_list += [id]
    else
      price_hash[id] = item[:sellLow]
    end
  end

  #Refresh or Retrieve Items from EveCentral
  begin
    market_data = EveCentral.market_stat(refresh_list, region_id)
    market_data.each do |item|
      price_hash[item['sell']['forQuery']['types'][0]] = item['sell']['min']
      time_hash[item['sell']['forQuery']['types'][0]] = item['sell']['generated']
    end
  rescue
    puts 'Could not connect to EveCentral.'
    price_hash[:error] = 'Error! Could not connect to EveCentral.'
    refresh_list.each do |id|
      price_hash[id] = 0
      time_hash[id] = 0
    end
  end

  # Update database
  refresh_list.each do |id|
    item = Jita_lookup[id]
    if item.nil?
      Jita_lookup.insert(:typeID => id, :sellLow => price_hash[id], :time => time_hash[id]/1000)
    else
      item.update(:sellLow => price_hash[id], :time => time_hash[id]/1000)
    end
  end

  price_hash
end

def number_format(number)
  ('%.2f' % number).reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end
