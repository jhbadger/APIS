#!/usr/bin/env ruby

require 'active_record'
require 'composite_primary_keys'

# Example: ActiveRecord::Base.establish_connection(:adapter  => 'sqlite3',
#:database => '/Users/jbadger/test_apis.db')

class Dataset < ActiveRecord::Base
  set_table_name "dataset"
  set_primary_key "dataset"
  has_many :sequences, :foreign_key => "dataset"
  has_many :trees, :foreign_key => "dataset"
  has_many :classifications, :foreign_key => "dataset"
  has_many :annotations, :foreign_key => "dataset"
  has_many :blasts, :foreign_key => "dataset"
  has_many :alignments, :foreign_key => "dataset"
  
  def name=(string)
    write_attribute(:dataset, string)
  end
  
  def name
    read_attribute(:dataset)
  end
end

class Sequence < ActiveRecord::Base
  set_table_name "sequence"
  set_primary_keys :dataset, :seq_name
  has_many :blasts, :foreign_key => [:dataset, :seq_name]
  has_many :alignments, :foreign_key => [:dataset, :seq_name]
  has_many :annotations, :foreign_key => [:dataset, :seq_name]
  has_one :tree, :foreign_key => [:dataset, :seq_name]
  has_one :classification, :foreign_key => [:dataset, :seq_name]
  belongs_to :dataset, :foreign_key => "dataset"
end

class Blast < ActiveRecord::Base
  set_table_name "blast"
  set_primary_keys :dataset, :seq_name,:subject_name,:query_start,:subject_start
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :dataset, :foreign_key => "dataset"
end

class Tree < ActiveRecord::Base
  set_table_name "tree"
  set_primary_keys :dataset, :seq_name
  has_one :classification, :foreign_key => [:dataset, :seq_name]
  has_many :annotations, :foreign_key => [:dataset, :seq_name]
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :dataset, :foreign_key => "dataset"
end

class Annotation < ActiveRecord::Base
  set_table_name "annotation"
  set_primary_keys :dataset, :seq_name, :source
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :tree, :foreign_key => [:dataset, :seq_name]
  belongs_to :dataset, :foreign_key => "dataset"
end

class Classification < ActiveRecord::Base
  set_table_name "classification"
  set_primary_keys :dataset, :seq_name
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :tree, :foreign_key => [:dataset, :seq_name]
  belongs_to :dataset, :foreign_key => "dataset"
end