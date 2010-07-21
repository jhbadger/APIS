class Dataset
  include DataMapper::Resource
  storage_names[:default] = "dataset"
  has n, :sequences, :child_key => [:dataset], :parent_key => [:dataset]
  property :dataset, String, :length => 50, :key => true
  property :owner, String, :length => 50
  property :date_added, Date
  property :database_used, String, :length => 100
  property :comments, String, :length => 1000
end

class Sequence
  include DataMapper::Resource
  storage_names[:default] = "sequence"
  belongs_to :dataset, :child_key => [:dataset], :parent_key => [:dataset]
  property :seq_name, String, :length => 100, :key => true
  property :dataset, String, :length => 50, :key => true, :index => true
  property :sequence, Text, :lazy => false
  property :processed, Boolean, :default => 0
end