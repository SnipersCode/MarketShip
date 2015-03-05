require 'json'

specialSrp = {
    'Bantam'	=> 'Logi',
    'Basilisk'	=> 'Logi',
    'Burst'	=> 'Fixed',
    'Eris'	=> 'Dictor',
    'Exequror'	=> 'Logi',
    'Flycatcher'	=> 'Dictor',
    'Guardian'	=> 'Logi',
    'Heretic'	=> 'Dictor',
    'Oneiros'	=> 'Logi',
    'Osprey'	=> 'Logi',
    'Panther'	=> 'BLOPS',
    'Redeemer'	=> 'BLOPS',
    'Sabre'	=> 'Dictor',
    'Scimitar'	=> 'Logi',
    'Scythe'	=> 'Logi',
    'Sin'	=> 'BLOPS',
    'Vigil'	=> 'Fixed',
    'Widow'	=> 'BLOPS'
}

open('../configs/specialSrp.json','w') do |file|
  file.puts JSON.pretty_generate(specialSrp)
end