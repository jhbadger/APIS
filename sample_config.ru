# starts sinatra application by Phusion Passenger
require 'sinatra'
require 'WebApis'

set :environment, :production
set :show_exceptions, true


if (ENV["WEBTIER"] != "prod")
  dbs = ApisDB.dbsFromSources(["mysql-lan-pro", "mysql-lan-dtw"], 
  "access", "access")
else
  dbs = ApisDB.dbsFromSources(["mysql-dmz-dtw", "mysql-dmz-pro"], "access", "access")
end

set :dbs, dbs
set :metaname, ApisDB.populateMetaName(dbs)

run Sinatra::Application
