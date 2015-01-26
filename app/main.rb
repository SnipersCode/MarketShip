require 'sinatra'
require 'slim'
require 'sequel'

Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://marketshipdev.db')

get '/:input' do
	@param1 = params[:input]
	slim :index
end

get '/' do
	slim :test
end