class Contig
  include DataMapper::Resource
  has n, :proteins
  has n, :transcripts
  has n, :rrnas
  property :name, String, :length => 50, :key => true
  property :species, String, :length => 255, :index => true
  property :taxon_id, Integer, :index => true
  property :taxonomy, String, :length => 500
  property :form, String, :length => 255, :index => true
  property :seq, Text
  property :updated, Time, :default => Time.now
  def to_fasta(len = 60)
    header = "#{name} [#{form}] {#{species}}" 
    return ">#{header}\n#{seq.gsub(Regexp.new(".{1,60}"), "\\0\n")}"
  end
end

class Protein
  include DataMapper::Resource
  belongs_to :contig
  property :name, String, :length => 100, :key => true
  property :annotation, String, :length => 255
  property :taxon_id, Integer
  property :seq, Text
  def to_fasta
    header = "#{name} #{annotation} {#{contig.species}}" 
    return ">#{header}\n#{seq.gsub(Regexp.new(".{1,60}"), "\\0\n")}"
  end
end

class Transcript
  include DataMapper::Resource
  belongs_to :contig
  property :name, String, :length => 100, :key => true
  property :seq, Text
  def annotation
    return Protein.first(:name => name).annotation
  end
  def to_fasta
    header = "#{name} #{annotation} {#{contig.species}}" 
    return ">#{header}\n#{seq.gsub(Regexp.new(".{1,60}"), "\\0\n")}"
  end
end

class Rrna
  include DataMapper::Resource
  belongs_to :contig
  property :name, String, :length => 100, :key => true
  property :annotation, String, :length => 255
  property :seq, Text
  def to_fasta
    header = "#{name} #{annotation} {#{contig.species}}" 
    return ">#{header}\n#{seq.gsub(Regexp.new(".{1,60}"), "\\0\n")}"
  end
end