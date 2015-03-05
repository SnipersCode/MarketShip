class EveSSO
  include HTTParty
  format :json
  base_uri 'https://login.eveonline.com/oauth'
  disable_rails_query_string_format

  def self.token(code)
    post('/token',
         :headers => {
             'Authorization' => 'Basic ' + Base64.urlsafe_encode64(ENV['EVE_CID'] + ':' + ENV['EVE_CS']),
             'Content-Type' => 'application/x-www-form-urlencoded',
             'Host' => 'login.eveonline.com'
         },
         :body => 'grant_type=authorization_code&code=' + code
    )
  end

  def self.refresh(refresh_token)
    post('/token',
         :headers => {
             'Authorization' => 'Basic ' + Base64.urlsafe_encode64(ENV['EVE_CID'] + ':' + ENV['EVE_CS']),
             'Content-Type' => 'application/x-www-form-urlencoded',
             'Host' => 'login.eveonline.com'
         },
         :body => 'grant_type=refresh_token&refresh_token=' + refresh_token
    )
  end

  def self.verify(access_token)
    get('/verify',
        :headers => {
            'User-Agent' => 'MarketShip,V1,Main Character: Kazuki Ishikawa',
            'Authorization' => 'Bearer ' + access_token,
            'Host' => 'login.eveonline.com'
        }
    )
  end

end

class EveXML
  include HTTParty
  format :xml
  base_uri 'https://api.eveonline.com'
  disable_rails_query_string_format

  def self.character_affiliation(ids)
    #Build string of list of IDs
    id_string = ids.shift.to_s
    ids.each do |id|
      id_string = id_string + ',' + id.to_s
    end

    get('/eve/CharacterAffiliation.xml.aspx', :query => {:ids => id_string})
  end

  def self.api_key_info(key_id,v_code)
    get('/account/APIKeyInfo.xml.aspx', :query => {:keyID => key_id, :vCode => v_code}, :verify => true)
  end

  def self.kill_mails(key_id,v_code,char_id)
    get('/Char/KillMails.xml.aspx', :query=> {:keyID => key_id, :characterID => char_id, :vCode => v_code}, :verify => true)
  end

end

def ensure_array(input)
  ([*input] unless input.is_a?(Hash)) || [input]
end

def refresh_keys(account)

  # Read Config
  config = {}
  File.open('configs/config.json', 'r') do |file|
    config = JSON.load(file)
  end

  Key_api.where(:charHash => account).all.each do |key|
    if key[:cacheTime] + config['logInTimeout'] < Time.now.to_i
      api_info = EveXML.api_key_info(key[:keyID],key[:vCode])
      if api_info['eveapi']['error']
        Key_api[key[:charID]].update(
            :corpID => nil,
            :corpName => nil,
            :allianceID => nil,
            :allianceName => nil)
        return false
      else
        ensure_array(api_info['eveapi']['result']['key']['rowset']['row']).each do |character|
          if api_info['eveapi']['result']['key']['expires'].empty?
            expiration = '1970-01-01 00:00:00'# Epoch 0 = Never
          else
            expiration = api_info['eveapi']['result']['key']['expires']
          end
            Key_api[character['characterID']].update(
                :corpID => character['corporationID'],
                :corpName => character['corporationName'],
                :allianceID => character['allianceID'],
                :allianceName => character['allianceName'],
                :cacheTime => DateTime.parse(api_info['eveapi']['cachedUntil']).to_time.to_i,
                :expiration => DateTime.parse(expiration).to_time.to_i) # Epoch 0 = Never
        end
      end
    end
  end

  true
end

def srp_flag(flag)
  flag = flag.to_i # Flag is input as string
  flag.between?(11,34) || # Low to High Slots
      flag == 87 || # Drone Bay
      flag == 89 || # Implant
      flag.between?(92,99) || # Rigs
      flag.between?(125,132) # Subsystem
end