require 'json'

srp_types = {
    'Logi'	=> '120%', #Logi
    'Dictor' => '100%',
    'BLOPS' => 400000000,
    'Fixed' => {
        'Burst' => 15000000,
        'Vigil' => 10000000
    }
}

open('../configs/srpTypes.json','w') do |file|
  file.puts JSON.pretty_generate(srp_types)
end