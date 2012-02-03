require 'mysql'
require 'ostruct'

class ApisDB
  # initalize db with a uri like "mysql://access:access@mysql-lan-pro/misc_apis"
  def initialize(uri)
    token = "[a-z|0-9|A-Z|_|-]+"
    if (uri =~/(#{token}):\/\/(#{token}):(#{token})\@(#{token})\/(#{token})*/)
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
      rescue Exception => e
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
  
  # return count matching condition
  def count(condition)
    connect if (!@connected)
    query = "SELECT count(*) FROM #{condition}"
    return get(query).first.to_i
  end
  
  # returns true if exists one or more records matching condition
  def exists?(condition)
    num = count(condition)
    if (num > 0)
      return true
    else
      return false
    end
  end
  
  # Insert one or more records into table
  def insert(table, records)
    return if records.empty? || records.first.empty?
    val = ""
    records.each do |record|
      val << "("
      record.each do |value|
        val << "'" << value.to_s.tr("'","") << "'"
        val << ","
      end
      val.chop!
      val << "),"
    end
    val.chop!
    query("INSERT INTO #{table} VALUES #{val}")
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
  
  
 
 # create dataset if it doesn't exist
  def createDataset(dataset, owner, date, database, comments = "", group = "",
                    username = "", password = "")
    if (!exists?("dataset WHERE dataset='#{dataset.quote}'"))
      insert("dataset", [[dataset.quote, owner, date, database, 
          comments, group, username, password]])
    end
  end
  
  # load peptides from file
  def loadPeptides(prot, dataset, include = false)
    if (!exists?("sequence WHERE dataset='#{dataset.quote}'") || include)
      STDERR.printf("Loading Peptides from %s...\n", prot)
    else
      return
    end
    seqs = []
    inputs = []
    count = 0
    Bio::FlatFile.new(Bio::FastaFormat, ZFile.new(prot)).each do |seq|
      id = seq.entry_id.gsub("(","").gsub(")","")
      seqs.push([id, dataset, seq.seq, 0])
      count += 1
      name, rest = seq.definition.split(" ", 2)
      if (!rest.nil? && rest.length > 3)
        rest = rest[0,1000] if (rest.length > 1000)
        inputs.push([id, dataset, rest.strip, 'input'])
      end
      if (count % 10000 == 0)
        insert("sequence", seqs)
        insert("annotation", inputs)
        seqs = []
        inputs = []
        STDERR.printf("Loaded sequence %d...\n", count)
      end
    end
    if (seqs.size > 0)
      insert("sequence", seqs)
      insert("annotation", inputs)
    end
  end
  
  # return processed state of peptide
  def processed?(seq_name, dataset)
    query("SELECT processed FROM sequence WHERE seq_name = '#{seq_name}' AND dataset='#{dataset}'").each do |row|
      return true if row[0] == "1"
    end
    return false
  end

  # set processed state for peptide
  def setProcessed(seq_name, dataset)
    query("UPDATE sequence SET processed=1 WHERE seq_name = '#{seq_name}' AND dataset='#{dataset}'") 
  end

  # unset processed state for peptide
  def setUnProcessed(seq_name, dataset)
    query("UPDATE sequence SET processed=0 WHERE seq_name = '#{seq_name}' AND dataset='#{dataset}'") 
  end
  
  # inserts alignment, deleting it if it already exists
  def createAlignment(seq_name, dataset, afa)
    query = "DELETE FROM alignment WHERE seq_name = '#{seq_name.quote}' "
    query += "AND dataset = '#{dataset.quote}'"
    query(query)
    lines = []
    Bio::FlatFile.new(Bio::FastaFormat, File.new(afa)).each do |aseq|
      lines.push([seq_name, dataset, aseq.entry_id, 
                  aseq.definition.split(" ", 2).last, aseq.seq])
    end
    insert("alignment", lines)
  end
  
  # return blast info for given seq_name + dataset and evalue
  def fetchBlast(seq_name, dataset, evalue, maxTree)
    homologs = []
    query("SELECT subject_name, subject_length, evalue, identity FROM blast WHERE seq_name='#{seq_name}' AND dataset='#{dataset}' and evalue <= #{evalue} ORDER BY evalue").each do |row|
      homologs.push(row[0]) if (homologs.size < maxTree && !homologs.include?(row[0]) && row[1].to_i < 2000 && row.last.to_i < 100)
    end
    return homologs
  end
  
  # stores tree
  def createTree(seq_name, dataset, tree)
    if (exists?("tree WHERE seq_name='#{seq_name}' AND dataset = '#{dataset}'"))
      query("UPDATE tree SET tree = '#{tree}' WHERE seq_name='#{seq_name}' AND dataset = '#{dataset}'")
    else
      insert("tree", [[seq_name, dataset, tree]])
    end
   end
  
   # interprets tree, creating classification and updating table
   def createClassification(tree, name, dataset, exclude, ruleMaj)
    classification = [name, dataset] + tree.createClassification(self, exclude, ruleMaj)
    insert("classification",[classification])
   end
   
  # inserts phylogenomic annotation
  def createAnnotation(tree, seq_name, dataset, functHash)
    function = findClosestFunction(tree, seq_name, functHash)
    if (function)
      insert("annotation", [[seq_name, dataset, function.strip, "APIS"]])
    else
      return nil
    end
  end

  # return the annotation of the closest sequence to id on tree 
  def findClosestFunction(tree, id, functHash)
    begin
      tree.relatives(id).each do |match|
        match.each do |seq|
          id, sp = seq.split("__", 2)
          function = functHash[id].split(";").first
          if (!function.nil? && 
            function !~/unnamed/ && function !~/unknown/ && 
            function !~/numExons/ && function !~/^\{/)
              return function
          end
        end
      end
      return false
    rescue
      return false
    end
  end

  # loads phylodb taxonomy 
  def loadTaxonomy(proteindb)
    if !@taxa
      @nums = Hash.new
      @taxa = Hash.new
      @ranks = Hash.new
      @parents = Hash.new
      @fullTax = Hash.new
      tax = Dir.glob(File.dirname(proteindb) + "/usedTaxa*").first
      if (tax.nil?)
        STDERR << "Can't find usedTaxa file in " << 
          File.dirname(proteindb) << "\n"
        exit(1)
      else
        File.new(tax).each do |line|
          num, name, parent, rank = line.chomp.split("\t")
          num = num.to_i
          parent = parent.to_i
          @taxa[num] = name.gsub(" ", "_")
          @nums[@taxa[num]] = num
          @ranks[num] = rank
          @parents[num] = parent
        end
      end
    end
    return @taxa
  end
  
  # returns full taxonomy string for taxonid
  def taxonomyString(taxid)
    goodRanks = ["superkingdom","kingdom", "phylum", "class", "order", 
      "family", "genus", "species"]
    if (@taxa[taxid])
      s = ""
      while (taxid !=  1)
        if (goodRanks.include?(@ranks[taxid]))
          if (s == "")
            s = @taxa[taxid]
          else
            s = @taxa[taxid] + "; " + s
          end
        end
        taxid = @parents[taxid]
      end
      return s
    else
      return (["unknown"]*7).join("; ")
    end
  end
  
  # return taxid of string or nil if none
  def taxid(string)
    return @nums[string.to_s.gsub(" ","_")]
  end

  # returns array of consensus taxonomy at each relative level of tree
  def consensusTax(tree, taxon, ruleMaj)
    consensus = []
    return  [] if (tree.relatives(taxon).nil?)
    tree.relatives(taxon).each do |list|
      counts = []
      list.each do |relative|
        seqid, sp = relative.split("__")
        if(!@fullTax[sp])
          @fullTax[sp] = taxonomyString(@nums[sp]).gsub("_"," ").split("; ")
        end
        groups = @fullTax[sp]
        next if (groups.nil?)
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
    return consensus
  end
     
  # delete dataset(s) matching condition and all associated records
  def deleteDataset(condition, keepBlast = false)
    query("SELECT dataset FROM dataset WHERE #{condition}").each do |row|
      dataset, rest  = row
      ["alignment", "annotation", "tree", "classification", "blast",
        "sequence", "dataset"].each do |tbl|
          next if (tbl == "blast" && keepBlast)
          STDERR.printf("Deleting data in %s for %s...\n", tbl, dataset)
          query("DELETE FROM #{tbl} WHERE dataset = '#{dataset.quote}'")
      end
    end
  end
  
  # close connection
  def close
    @db.close
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
  
  # load options from apis.conf in APIS directory or home directory
  def self.loadOptions(opts)
    files = [ENV["HOME"] + "/apis.conf", File.dirname(__FILE__)+"/apis.conf"]
    file = nil
    files.each do |f|
      if File.exists?(f)
        file = f
        break
      end
    end
    if (file.nil?)
      STDERR << "No apis.conf found!\n"
      exit(1)
    else
      opts = opts.to_hash
      File.new(file).each do |line|
        key, value = line.chomp.split(/ = |=/)
        opts[key.to_sym] = value 
      end
      return OpenStruct.new(opts)
    end 
  end

  # return hash of apis db objects (mysql or sqlite) depending on source string
  def  self.dbsFromSources(sources, user, password)
    dbs = Hash.new
    sources.each do |source|
      db = ApisDB.new("mysql://#{user}:#{password}@#{source}/")
      db.query("SHOW DATABASES").each do |row|
        dbname = row[0]
        if (dbname =~/_apis/ && !dbs[dbname])
          dbs[dbname] = ApisDB.new("mysql://#{user}:#{password}@#{source}/#{dbname}")
          dbs[dbname].close
        end
      end
      db.close
    end
    return dbs
  end

  # return hash of human readable dataset names from metadata table where it exists
  def self.populateMetaName(dbs)
    metaName = Hash.new
    dbs.keys.each do |dbname|
      metaName[dbname] = Hash.new
      table = dbs[dbname].get("SHOW TABLES WHERE tables_in_#{dbname} = 'metadata'").to_s
      if (table != "")
        dbs[dbname].query("SELECT dataset, value FROM metadata WHERE prop='name'").each do |row|
          metaName[dbname][row.first] = row.last
        end
        dbs[dbname].query("SELECT dataset, value FROM metadata WHERE prop='location'").each do |row|
          metaName[dbname][row.first] += " " + row.last
        end
      end
    end
    return metaName
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
  def createClassification(name, db, exclude, ruleMaj)
    cons = db.consensusTax(self, name, ruleMaj)
    lines = []
    cons.each do |line|
      lines.push(line) if (line.grep(/#{exclude}/).empty? || exclude.nil?)
    end
    first = lines[0]
    first=[nil,nil,nil,nil,nil,nil,nil] if first.nil?
    if (lines[1].nil?)
      second = nil
    else
      second = lines[1]
    end
    mixed = false
    classification = []
    7.times do |level|
      mixed = true if first[level] == "Mixed"
      first[level] = "Mixed" if mixed
      if (first[level] == "Mixed" || second.nil? || first[level] == second[level])
        outgroup = 0
      else
        outgroup = 1
      end
      first[level] = "Undefined" if first[level].nil?
      classification.push(first[level][0..45])
      classification.push(outgroup)
    end
    return classification
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

  # gets rid of bad characters screwing up trees
  def clean
    return self.tr(":","_")
  end
  
  # split string into id + contig
  def splitId
    return self[0..self.rindex("-").to_i-1],self[1 + self.rindex("-").to_i..self.length]
  end
end


class OpenStruct
  #implements the missing to_hash
  def to_hash
    h = @table
    #handles nested structures
    h.each do |k,v|
      if v.class == OpenStruct
        h[k] = v._to_hash
      end
    end
    return h
  end
end
