require 'mysql'

class ApisDB
  # initalize db with a uri like "mysql://access:access@mysql-lan-pro/misc_apis"
  def initialize(uri)
    token = "[a-z|0-9|A-Z|_|-]+"
    if (uri =~/(#{token}):\/\/(#{token}):(#{token})\@(#{token})\/(#{token})/)
      @driver, @user, @password, @server, @database = $1, $2, $3, $4, $5
      connect
    else
      STDERR << "can't parse " << uri << "\n"
      exit(1)
    end
  end
  
  # connect to database, looping until connection obtained
  def connect
    @connected = false
    while(!@connected)
      begin
        if (@driver == "mysql")
          @db = Mysql.new(@server, @user, @password, @database)
          @connected = true
        else
          STDERR << "only mysql right now -- can't parse " << uri << "\n"
          exit(1)
        end
      rescue
        sleep 0.2
      end
    end
  end
  
  # query db with sql and return query result class in array form
  def query(sql)
    begin
      return @db.query(sql)
    rescue Exception => e
      if (e.message =~/not connected/)
        connect
        retry
      else
        raise e
      end
    end
  end
  
  # return first row data immediately from query 
  def get(sql)
    begin
      return @db.query(sql).fetch_row
    rescue Exception => e
      if (e.message =~/not connected/)
        connect
        retry
      else
        raise e
      end
    end
  end
  
  # close connection
  def close
    @db.close
  end
  
  # return taxonomy hash of contigs
  def contigs_tax
    taxdb = Hash.new
    query("SELECT name, species, taxonomy FROM phylodb.contigs").each do |row|
      name, species, taxonomy = row
      taxdb[species] = taxonomy.split(/; |;/)
      taxdb[name] = taxdb[species]
    end
    return taxdb
  end
  
  # return taxonomy array/string based on taxid
  def buildTaxFromTaxId(taxid, string = false, verbose = false)
    levels = ["kingdom", "phylum", "class", "order", "family", 
              "genus", "species"]
    name = ""
    pid = ""
    rank = ""
    tax = [""]*7
    while (name != "root")
      query = "select parent_id, name, rank from phylodb.taxonomy WHERE tax_id = #{taxid}"
      pid, name, rank = get(query)
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
    6.step(0, -1) do |i|
      if (tax[i] == "")
        tax[i] = tax[i + 1].split(" (").first + " (" + levels[i] + ")"
      end
    end
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
  
  # return taxonomic grouping used in the GOS analysis
  def gos_taxonomy(kingdom, phylum, cl, ord, family, genus, species)
    if genus =~/Pelagibacter|SAR11/
      taxon = "SAR11"
    elsif ord =~/Rhodobacterales/
      taxon = "Rhodobacterales"
    elsif cl == "Alphaproteobacteria"
      taxon = "Other Alphaproteobacteria"
    elsif genus =~/Prochlorococcus/ || family =~/Prochlorococcus/
      taxon = "Prochlorococcus"
    elsif cl == "Gammaproteobacteria"
      taxon = "Gammaproteobacteria"
    elsif phylum =~/Bacteroidetes|Chlorobi/
      taxon = "Bacteroidetes/Chlorobi"
    elsif phylum == "Firmicutes"
        taxon = "Firmicutes"
    elsif phylum == "Actinobacteria"
      taxon = "Actinobacteria"
    elsif phylum == "Actinobacteria"
      taxon = "Actinobacteria"
    elsif cl == "Betaproteobacteria"
      taxon = "Betaproteobacteria"
    elsif cl == "Deltaproteobacteria" || ord == "Deltaproteobacteria"
      taxon = "Deltaproteobacteria"
    elsif cl == "Epsilonproteobacteria"
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

class Array
  # return majority consensus for counts array
  def majority
    consensus = []
    size.times do |i|
      total = 0.0
      self[i].values.each{|val|total+=val}
      name = self[i].keys.sort {|x,y| self[i][y] <=> self[i][x]}.first
      
      if (self[i][name]/total > 0.5)
        consensus[i] = name
      else
        consensus[i] = "Mixed"
      end
    end
    return consensus
  end

  # return absolute consensus for counts array
  def absolute
    consensus = []
    size.times do |i|
      if (self[i].size == 1)
        consensus.push(self[i].keys.first)
      else
        consensus.push("Mixed")
      end
    end
    return consensus
  end
  def mostCommon
    count = Hash.new
    self.each do |el|
      if (count[el].nil?)
	      count[el] = 1
      else
	      count[el] += 1
      end
    end
    sorted = count.keys.sort {|a, b| count[b] <=> count[a]}
    return sorted[0]
  end
end


class NewickTree
  # returns classification of node based on taxonomy
  def createClassification(node_name, tax, exclude, ruleMaj)
    consensus = []
    return  [] if (relatives(node_name).nil?)
    relatives(node_name).each do |list|
      counts = []
      list.each do |relative|
        acc, contig = relative.split("-")
	      contig, rest = contig.split("__")
	      groups = tax[contig]
	      next if groups.nil?
        groups.size.times do |i|
          counts[i] = Hash.new if counts[i].nil?
          counts[i][groups[i]] = 0 if counts[i][groups[i]].nil?
          counts[i][groups[i]] += 1
        end
      end
      if (ruleMaj)
        consensus.push(counts.majority)
      else
        consensus.push(counts.absolute)
      end
    end
    return consensus.first
  end
end

# quotes single quotes, etc. for SQL usage
class String
  # quotes single quotes, etc. for SQL usage
  def quote
    return self.gsub(/\\/, '\&\&').gsub(/'/, "''")
  end
  # formats string as fasta record
  def to_fasta(header, len = 60)
    return ">#{header}\n#{self.gsub("*","").gsub(Regexp.new(".{1,#{len}}"), "\\0\n")}"
  end
end
