class Protein
  has n, :blastmatches, :child_key=>[:name], :parent_key=>[:name]
end

class Blastmatch
  include DataMapper::Resource
  belongs_to :protein, :child_key=>[:name], :parent_key=>[:name]
  has n, :cogs, :child_key=>[:protein], :parent_key=>[:hit]
  storage_names[:combodb] = "blast"
  property :source, String, :length=>100, :key=>true, :index=>true
  property :target, String, :length=>100, :key=>true, :index=>true
  property :blast, String, :length=>100,  :key=>true, :index=>true
  property :name, String, :field=> "query", :length=>100, :key=>true, :index=>true
  property :hit, String, :length=>100, :key=>true, :index=>true
  property :evalue, Float
end

class Cog
  include DataMapper::Resource
  storage_names[:combodb] = "cog_proteins"
  belongs_to :blastmatch, :child_key=>[:protein], :parent_key=>[:hit]
  has 1, :cogdef, :child_key=>[:cog_name], :parent_key=>[:name]
  property :protein, String, :length=>100, :key=>true
  property :species, String, :length=>100
  property :name, String, :field=>"cog", :length=>100
  def to_s
    return name + " " + cogdef.definition
  end
end

class Cogdef
  include DataMapper::Resource
  storage_names[:combodb] = "cog_definitions"
  belongs_to :cog, :child_key=>[:cog_name], :parent_key=>[:name]
  property :cog_name, String, :field=> "cog", :length=>100, :key=> true
  property :definition, Text
end