require 'json'

config = {
    :jitaShippingRate => 900,
    :shippingSeparateVol => 80000,
    :contractMaxVol => 320000,
    :shippingBulkVol => 200000,
    :minShippingPrice => 1000000,
    :marketUpdateTime => 3600
}

open('config.json','w') do |file|
  file.puts JSON.pretty_generate(config)
end