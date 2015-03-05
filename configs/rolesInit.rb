require 'json'

roles = {
    94074701 => {
        :srp => 3
    }
}


# All Roles are Binary

# Srp
## 0: No roles (Default)
## 1: Approve
## 2: Pay

open('../configs/roles.json','w') do |file|
  file.puts JSON.pretty_generate(roles)
end