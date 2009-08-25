require 'json'
require 'ostruct'
require 'rdiscount'

$LOAD_PATH.unshift File.dirname(__FILE__) + '/../vendor/redis'
require 'redis'

redis_config = if ENV['REDIS_URL']
	require 'uri'
	uri = URI.parse ENV['REDIS_URL']
	{ :host => uri.host, :port => uri.port, :password => uri.password, :db => uri.path.gsub(/^\//, '') }
else
	{}
end

DB = Redis.new(redis_config)

$LOAD_PATH.unshift File.dirname(__FILE__) + '/../vendor/syntax'
require 'syntax/convertors/html'

$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'post'
require 'user'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../vendor/sinatra-content-for')

require 'lib/sinatra/content_for'