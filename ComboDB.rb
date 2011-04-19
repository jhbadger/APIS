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
  def Contig.tax
    if (@tax.nil?)
      @tax = Hash.new
      repository(:combodb) {Contig.all}.each do |contig|
        @tax[contig.species] = contig.taxonomy.split("; ")
        @tax[contig.name] = contig.taxonomy.split("; ")
      end
    end
    return @tax
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

def buildTaxFromTaxId(taxid, string = false, verbose = false)
  levels = ["kingdom", "phylum", "class", "order", "family", 
            "genus", "species"]
  name = ""
  pid = ""
  rank = ""
  tax = [""]*7
  while (name != "root")
    query = "select parent_id, name, rank from phylodb_annotation.taxonomy WHERE tax_id = #{taxid}"
    pid, name, rank = repository(:combodb).adapter.select(query).first.to_a
    STDERR.printf("%d\t%d\t%s\t%s\n", taxid, pid, name, rank) if verbose
    return nil if pid.nil?
    pos = levels.index(rank)
    if (pos.nil?)
      pos = 0 if name == "Viruses" || name == "Viroids"
      pos = 1 if name =~ /viruses/
    end
    tax[pos] = name.tr(",()[]'\"/","") if (pos)
    taxid = pid
  end
  6.step(0, -1) {|i|
    if (tax[i] == "")
      tax[i] = tax[i + 1].split(" (").first + " (" + levels[i] + ")"
    end
  }
  if (string)
    tline = ""
    tax.each {|lev|
      tline += lev
      tline += "; " if lev != tax.last
    }
    return tline
  else
    return tax
  end
end