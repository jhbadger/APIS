require 'active_record'
require 'composite_primary_keys'

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
  set_primary_keys ["dataset", "seq_name"]
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
  
  def gos_taxonomy
    if (classification.nil?)
      return ""
    else
      return classification.gos_taxonomy
    end
  end
end

class Blast < ActiveRecord::Base
  set_table_name "blast"
  set_primary_keys [:dataset, :seq_name]
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
end

class Tree < ActiveRecord::Base
  set_table_name "tree"
  set_primary_keys [:dataset, :seq_name]
  has_one :classification, :foreign_key => [:dataset, :seq_name]
  has_many :annotations, :foreign_key => [:dataset, :seq_name]
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
end

class Annotation < ActiveRecord::Base
  set_table_name "annotation"
  set_primary_keys [:dataset, :seq_name]
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :tree, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
end

class Classification < ActiveRecord::Base 
  set_table_name "classification"
  set_primary_keys [:dataset, :seq_name]
  belongs_to :sequence, :foreign_key => [:dataset, :seq_name]
  belongs_to :tree, :foreign_key => [:dataset, :seq_name]
  belongs_to :apisrun, :foreign_key => "dataset"
  class << self # fix having field named 'class'
    def instance_method_already_implemented?(method_name)
      return true if method_name == 'class'
      super
    end
  end
  # return NCBI-style semicolon delimited taxonomy string
  def taxonomy
    return [kingdom, phylum, self[:class], ord, family, genus, species].join("; ")
  end
  # return taxonomic grouping used in the GOS analysis
  def gos_taxonomy
    if genus =~/Pelagibacter|SAR11/
      taxon = "SAR11"
    elsif ord =~/Rhodobacterales/
      taxon = "Rhodobacterales"
    elsif self[:class] === "Alphaproteobacteria"
      taxon = "Other Alphaproteobacteria"
    elsif genus =~/Prochlorococcus/ || family =~/Prochlorococcus/
      taxon = "Prochlorococcus"
    elsif self[:class] == "Gammaproteobacteria"
      taxon = "Gammaproteobacteria"
    elsif phylum =~/Bacteroidetes|Chlorobi/
      taxon = "Bacteroidetes/Chlorobi"
    elsif phylum == "Firmicutes"
        taxon = "Firmicutes"
    elsif phylum == "Actinobacteria"
      taxon = "Actinobacteria"
    elsif phylum == "Actinobacteria"
      taxon = "Actinobacteria"
    elsif self[:class] == "Betaproteobacteria"
      taxon = "Betaproteobacteria"
    elsif self[:class] == "Deltaproteobacteria" || ord == "Deltaproteobacteria"
      taxon = "Deltaproteobacteria"
    elsif self[:class] == "Epsilonproteobacteria"
      taxon = "Epsilonproteobacteria"
    elsif phylum == "Proteobacteria"
      taxon = "Other Proteobacteria"
    elsif phylum == "Spirochaetes"
      taxon = "Spirochaetes"
    elsif phylum == "Thermotogae"
      taxon = "Thermotogae"
    elsif phylum == "Planctomycetes"
      taxon = "Planctomycetes"
    elsif phylum =~/Chlamydiae|Verrucomicrobia/
      taxon = "Chlamydiae/Verrucomicrobia"
    elsif genus =~/Synechococcus/ || ord =~/Synechococcus/
      taxon = "Synechococcus"
    elsif phylum == "Cyanobacteria"
      taxon = "Other Cyanobacteria"
    elsif phylum == "Mixed"
      taxon = "Mixed"
    else
      taxon = "Other"
    end
    return taxon
  end
end

# connect using a url-style driver://user:password@server/database
def connectDB(url)
  token = "[a-z|0-9|A-Z|_|-]+"
  if (url =~/(#{token}):\/\/(#{token}):(#{token})\@(#{token})\/(#{token})/)
    driver, user, password, server, database = $1, $2, $3, $4, $5
    ActiveRecord::Base.establish_connection(:adapter  => driver,
    :host => server, :username=> user, :password=> password,
    :database=> database)
  else
    STDERR << "can't parse " << url << "\n"
    exit(1)
  end
end