require 'json'

config = {
    :jitaShippingRate => 900, #Isk
    :shippingSeparateVol => 80000, #Isk
    :contractMaxVol => 320000, #m3
    :shippingBulkVol => 200000, #m3
    :minShippingPrice => 1000000, #m3
    :marketUpdateTime => 3600, #sec
    :logInTimeout => 300, #sec after cache timeout
    :allianceID => 150097440, #CCP
    :killMailUpdateTime => 60, #sec after cache timeout
    :stagingSystem => 10000058, #CCP Region ID
    :percentIgnoreHigh => 30, # %: 0.1-100.0
    :percentIgnoreLow => 30, # %: 0.1-100.0
    :strategicPercent => 90, # %: 0.1-100.0
    :peacetimePercent => 70 # %: 0.1-100.0
}

open('../configs/config.json','w') do |file|
  file.puts JSON.pretty_generate(config)
end