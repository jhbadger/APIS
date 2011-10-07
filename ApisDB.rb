require 'mysql'

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
  
  # return location of NCBI blast db for phylodb
  def blastdb
    return get("SELECT * from phylodb.apisdbs").first
  end
  
  # return FASTA formated string of phylodb protein and length based on protein name
  def fetchProt(name)
    query = "SELECT proteins.name, annotation, species, "
    query += "proteins.seq FROM phylodb.contigs, phylodb.proteins "
    query += "WHERE contig_name = contigs.name AND proteins.name = '#{name.quote}'"
    name, annotation, species, seq = get(query)
    if (name.nil?)
      return nil, nil
    else
      seq.gsub!("*","")
      return seq.to_fasta("#{name} #{annotation} {#{species}}"), seq.length
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
  def fetchBlast(seq_name, dataset, evalue, maxTree, tax)
    homologs = []
    query("SELECT subject_name, subject_length, evalue FROM blast WHERE seq_name='#{seq_name}' AND dataset='#{dataset}' and evalue <= #{evalue} ORDER BY evalue").each do |row|
      homologs.push(row[0]) if (homologs.size < maxTree && !homologs.include?(row[0]) && row[1].to_i < 2000)
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
  
   # interprets tree, creating classification
   def createClassification(tree, name, dataset, exclude, ruleMaj)
     cons = consensusTax(tree, name, ruleMaj)
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
     classification = [name, dataset]
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
   
  # creates phylogenomic annotation
  def createAnnotation(tree, seq_name, dataset)
    function  = findClosestFunction(tree, seq_name)
    if (function)
      return [seq_name, dataset, function.strip, "APIS"]
    else
      return nil
    end
  end

  # return the annotation of the closest sequence to id on tree 
  def findClosestFunction(tree, id)
    begin
      tree.relatives(id).each do |match|
        acc, contig = match.first.split("-")
        contig, rest = contig.split("__")
        match_id = acc + "-" + contig
        function = fetchFunction(match_id)
        if (!function.nil? && function.split(" ").size > 1 && 
            function !~/unnamed/ && function !~/unknown/ && 
            function !~/numExons/ && function !~/^\{/)
          return function
        end
      end
      return false
    rescue
      return false
    end
  end

  # returns array of consensus taxonomy at each relative level of tree
  def consensusTax(tree, taxon, ruleMaj)
    consensus = []
    return  [] if (tree.relatives(taxon).nil?)
    tree.relatives(taxon).each do |list|
      counts = []
      list.each do |relative|
        acc, contig = relative.split("-")
        contig, rest = contig.split("__")
        groups = tax[contig]
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
  
  # return taxonomy hash of contigs
  def tax
    if (!@tax)
      STDERR.printf("Loading Taxonomy...\n")
      @tax = Hash.new
      query("SELECT name, taxonomy, form FROM phylodb.contigs").each do |row|
        name, species, taxonomy, form = row
        if (form == "Mitochondria")
          taxonomy = "Bacteria; Proteobacteria; Alphaproteobacteria; Rickettsiales; Rickettsiaceae; Rickettsieae; Mitochondrion;"
        elsif (form == "Plastid")  
          taxonomy = "Bacteria; Cyanobacteria; Prochlorophytes; Prochlorococcaceae; Chloroplast;  Chloroplast;  Chloroplast;"
        end
        @tax[species] = taxonomy.split(/; |;/)
        @tax[name] = @tax[species]
      end
    end
    return @tax
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
