require 'sequel'

DB = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://marketshipdev.sqlite')

DB.create_table(:jita_lookups) do
  Integer :typeID, :primary_key => true
  Float :sellLow
  Integer :time
end