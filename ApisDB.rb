class Dataset
  include DataMapper::Resource
  storage_names[:default] = "dataset"
  has n, :sequences
  property :id, String, :field => "dataset", :length => 50, :key => true
  property :owner, String, :length => 50
  property :date_added, Date
  property :database_used, String, :length => 100
  property :comments, String, :length => 1000
end

class Sequence
  include DataMapper::Resource
  storage_names[:default] = "sequence"
  belongs_to :dataset
  has n, :alignments, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  has n, :annotations, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  has n, :blasts, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  has 1, :classification, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  has 1, :tree, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  property :dataset_id, String, :field => "dataset", :length => 50, :key => true, :index => true
  property :name, String, :field => "seq_name", :length => 100, :key => true, :index => true
  property :sequence, Text
  property :processed, Boolean, :default => 0
  def cog
    if (tree.nil?)
      return ""
    else
      homolog = tree.homolog
      cogs = DataMapper.repository(:combodb) {homolog.blastmatches.cogs}
      return cogs.first.to_s
    end
  end
end

class Alignment
  include DataMapper::Resource
  storage_names[:default] = "alignment"
  belongs_to :sequence, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  property :dataset_id, String, :field => "dataset", :length => 50, :key => true
  property :seq_name, String, :length => 100, :key => true
  property :alignment_name, String, :length => 100
  property :alignment_desc, String, :length => 1000
  property :alignment_sequence, Text, :lazy => false
end

class Annotation
  include DataMapper::Resource
  storage_names[:default] = "annotation"
  belongs_to :sequence, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  property :dataset_id, String, :field => "dataset", :length => 50, :key => true
  property :seq_name, String, :length => 100, :key => true
  property :annotation, String, :length => 10000
  property :source, String, :length => 100, :key => true
  def to_s
    return annotation
  end
end

class Blast
  include DataMapper::Resource
  storage_names[:default] = "blast"
  belongs_to :sequence, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  property :dataset_id, String, :field => "dataset", :length => 50, :key => true
  property :seq_name, String, :length => 100, :key => true
  property :subject_name, String, :length => 100, :key => true
  property :subject_description, String, :length => 100
  property :subject_length, Integer
  property :query_start, Integer, :key => true
  property :query_end, Integer
  property :subject_start, Integer, :key => true
  property :subject_end, Integer
  property :identity, Float
  property :similarity, Float
  property :score, Integer
  property :evalue, Float
end

class Classification
  include DataMapper::Resource
  storage_names[:default] = "classification"
  belongs_to :sequence, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  property :dataset_id, String, :field => "dataset", :length => 50, :key => true
  property :seq_name, String, :length => 100, :key => true
  property :kingdom, String, :length => 50, :index => true
  property :kingdom_outgroup, Boolean, :index => true
  property :phylum, String, :length => 50, :index => true
  property :phylum_outgroup, Boolean, :index => true
  property :classname, String, :field => "class", :length => 50, :index => true
  property :class_outgroup, Boolean, :index => true
  property :order, String, :field => "ord", :length => 50, :index => true
  property :order_outgroup, Boolean, :field => "ord_outgroup", :index => true
  property :family, String, :length => 50, :index => true
  property :family_outgroup, Boolean, :index => true
  property :genus, String, :length => 50, :index => true
  property :genus_outgroup, Boolean, :index => true
  property :species, String, :length => 50, :index => true
  property :species_outgroup, Boolean, :index => true
  def to_s
    s = ""
    [kingdom, phylum, classname, order, family, genus, species].each do |level|
      s += "; " if (s != "")
      s += level if (level != "Mixed" && level != "Undefined")
    end
    return s    
  end
end

class Tree
  include DataMapper::Resource
  storage_names[:default] = "tree"
  belongs_to :sequence, :child_key=>[:dataset_id, :seq_name], :parent_key=>[:dataset_id, :name]
  property :dataset_id, String, :field => "dataset", :length => 50, :key => true
  property :seq_name, String, :length => 100, :key => true
  property :tree, Text, :lazy => false
  def to_s
    return tree.chomp
  end
  def homolog
    pname = NewickTree.new(tree).relatives(seq_name).first.first.split("__").first
    return DataMapper.repository(:combodb) {Protein.first(:name => pname)}
  end
end