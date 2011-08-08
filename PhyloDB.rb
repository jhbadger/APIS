require 'active_record'

class Contig < ActiveRecord::Base
  set_primary_key "name"
  has_many :proteins, :foreign_key => "contig_name"
  has_many :transcripts, :foreign_key => "contig_name"
  has_many :gene_orders,:foreign_key => "contig_name"
  has_many :rrnas, :foreign_key => "contig_name"
  
  def to_fasta
    header = name + " " + species + " " + form + " " + " {" + species + "}"
    return Bio::Sequence::AA.new(seq).to_fasta(header, 60)
  end
end

class Protein < ActiveRecord::Base
  set_primary_key "name"
  belongs_to :contig, :foreign_key => "contig_name"
  has_one :transcript, :foreign_key => "name"
  has_one :gene_order, :foreign_key => "protein_name"
  
  def to_fasta
    header = name + " " + annotation + " {" + species + "}"
    return Bio::Sequence::AA.new(seq).to_fasta(header, 60)
  end
  
  def species
    return contig.species
  end
end

class Transcript < ActiveRecord::Base
  set_primary_key "name"
  belongs_to :contig, :foreign_key => "contig_name"
  belongs_to :protein, :foreign_key => "name"
  has_one :gene_order, :foreign_key => "protein_name"
  
  def to_fasta
    header = name + " " + annotation + " {" + species + "}"
    return Bio::Sequence::AA.new(seq).to_fasta(header, 60)
  end
  
  def annotation
    return protein.annotation
  end
  
  def species
    return contig.species
  end
end

class Rrna < ActiveRecord::Base
  set_primary_key "name"
  belongs_to :contig, :foreign_key => "contig_name"
  has_one :gene_order, :foreign_key => "protein_name"
  
  def to_fasta
    header = name + " " + annotation + " {" + species + "}"
    return Bio::Sequence::AA.new(seq).to_fasta(header, 60)
  end
  
  def species
    return contig.species
  end
  
end