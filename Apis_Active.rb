require 'active_record'
require 'composite_primary_keys'

# Example: ActiveRecord::Base.establish_connection(:adapter  => 'sqlite3',
#:database => '/Users/jbadger/test_apis.db')

class Apisrun < ActiveRecord::Base
  set_table_name "dataset"
  set_primary_key "dataset"
  has_many :sequences, :foreign_key => "dataset"
  has_many :trees, :foreign_key => "dataset"
  has_many :classifications, :foreign_key => "dataset"
  has_many :annotations, :foreign_key => "dataset"
  has_many :blasts, :foreign_key => "dataset"
  has_many :alignments, :foreign_key => "dataset"
end

class Sequence < ActiveRecord::Base
  set_table_name "sequence"
  set_primary_keys :dataset, :seq_name
  has_many :blasts, :foreign_key => [:dataset, :seq_name]
  has_many :alignments, :foreign_key => [:dataset, :seq_name]
  has_many :annotations, :foreign_key => [:dataset, :seq_name]
  has_one :tree, :foreign_key => [:dataset, :seq_name]
  has_one :classification, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
  
  def to_fasta(desc = nil)
    header = seq_name
    header += " " + desc if (desc)
    return Bio::Sequence::AA.new(sequence).to_fasta(header, 60)
  end
  
  def taxonomy
    if (classification.nil?)
      return ""
    else
      return classification.taxonomy
    end
  end
end

class Blast < ActiveRecord::Base
  set_table_name "blast"
  set_primary_keys :dataset, :seq_name,:subject_name,:query_start,:subject_start
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
end

class Tree < ActiveRecord::Base
  set_table_name "tree"
  set_primary_keys :dataset, :seq_name
  has_one :classification, :foreign_key => [:dataset, :seq_name]
  has_many :annotations, :foreign_key => [:dataset, :seq_name]
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
end

class Annotation < ActiveRecord::Base
  set_table_name "annotation"
  set_primary_keys :dataset, :seq_name, :source
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :tree, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
end

class Classification < ActiveRecord::Base 
  set_table_name "classification"
  set_primary_keys :dataset, :seq_name
  alias_attribute :classname, :class
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :tree, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
  class << self # fix having field named 'class'
    def instance_method_already_implemented?(method_name)
      return true if method_name == 'class'
      super
    end
  end
  def taxonomy
    return [kingdom, phylum, classname, ord, family, genus, species].join("; ")
  end
end