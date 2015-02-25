# Formatted Evemon exported csv
# Ship Browser, Expand All, Shift Select All
# Right click attributes window, export to csv
# replace all ';' with ',' and erase unnecessary rows
# remove attribute and unit columns

require 'csv'
require 'json'

vol_csv = CSV.read('../configs/packVol.csv')
vol_hash = Hash[vol_csv[0].zip(vol_csv[1].map{|x| x.to_i})]
open('../configs/packVol.json','w') do |file|
  file.puts JSON.pretty_generate(vol_hash)
end