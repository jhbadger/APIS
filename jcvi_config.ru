# starts sinatra application by Phusion Passenger
require 'sinatra'
require 'WebApis'

set :environment, :production
set :show_exceptions, true


if (ENV["WEBTIER"] != "prod")
  dbs = DBwrapper.dbsFromSources(["mysql-lan-pro", "mysql-lan-dtw"], 
  "access", "access")
else
  dbs = DBwrapper.dbsFromSources(["mysql-dmz-dtw"], "access", "access")
end

set :dbs, dbs
set :metaname, DBwrapper.populateMetaName(dbs)

run Sinatra::Application
