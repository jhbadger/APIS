# starts sinatra application by Phusion Passenger
require 'sinatra'
require 'WebApis'

set :environment, :production
set :show_exceptions, true
set :dbs, DBwrapper.dbsFromSources(["mysql-lan-pro", "mysql-lan-dtw"], "access", "access")

run Sinatra::Application