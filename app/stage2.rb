class EveSSO
  include HTTParty
  format :json
  base_uri 'https://login.eveonline.com/oauth'
  disable_rails_query_string_format

  def self.token(code)
    post('/token',
         :headers => {
             'Authorization' => 'Basic ' + Base64.urlsafe_encode64(ENV['EVE_CID'] + ':' + params[:code]),
             'Content-Type' => 'application/x-www-form-urlencoded',
             'Host' => 'login.eveonline.com'
         },
         :body => 'grant_type=authorization_code&code=' + code
    )
  end

  def self.verify(access_token)
    get('https://login.eveonline.com/oauth/verify',
        :headers => {
            'User-Agent' => 'MarketShip,V1,Main Character: Kazuki Ishikawa',
            'Authorization' => 'Bearer ' + access_token,
            'Host' => 'login.eveonline.com'
        }
    )
  end

end

class Accounts < Sequel::Model
  set_primary_key :charHash
end