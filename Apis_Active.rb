#!/usr/bin/env ruby

require 'active_record'

ActiveRecord::Base.establish_connection(
:adapter  => 'mysql',:database => 'misc_apis',
:username => 'apis',
:password => 'apis_user',
:host     => 'mysql-lan-pro')


class Dataset < ActiveRecord::Base
  set_table_name "dataset"
  set_primary_key "dataset"
  has_many :sequences, :foreign_key => "dataset"
end

class Sequence < ActiveRecord::Base
  set_table_name "sequence"
  belongs_to :dataset, :foreign_key => "dataset"
end

p Dataset.find(:first, :conditions=> "dataset='test'").sequences