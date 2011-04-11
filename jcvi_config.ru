# starts sinatra application by Phusion Passenger
require 'sinatra'
require 'WebApis'

set :environment, :production
set :show_exceptions, true
if (ENV["WEBTIER"] != "prod")
  set :dbs, DBwrapper.dbsFromSources(["mysql-lan-pro", "mysql-lan-dtw"], 
  "access", "access")
else
  set :dbs, DBwrapper.dbsFromSources(["mysql-dmz-dtw"], "access", "access")
end
