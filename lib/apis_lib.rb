# helper functions


# load apis.conf defaults from current, home, or APIS directory
def loadDefaults
   defaults = Hash.new
   if File.exists?("apis_conf.json")
      conf = "apis_conf.json"
   elsif File.exists?(ENV["HOME"]+"/apis_conf.json")
      conf = ENV["HOME"]+"/apis_conf.json"
   elsif File.exists?(File.dirname($0)+"/apis_conf.json")
      conf = File.dirname($0)+"/apis_conf.json"
   else
      conf = nil
   end
   if conf
      json = File.new(conf)
      parser = Yajl::Parser.new
      defaults = parser.parse(json)
      json.close
   end
   defaults
end

# return hashes of percentages and counts for use in apis pie chart
def pieProcess(file, dataset, format, level, withTree)
  counts = Hash.new
  total = 0
  if format == "json"
    JsonStreamer.new(ZFile.new(file)).each do |obj|
      if (opts.relaxed)
        consensus = obj["relaxed_consensus"]
      else
        consensus = obj["strict_consensus"]
      end
      taxon = consensus[level]
      next if level == "kingdom" && !["Eukaryota", "Bacteria", "Archaea", "Viruses"].include?(taxon)
      if taxon != "Undefined" && taxon != "Unknown" && (!withTree || taxon != "NO_TREE")
        counts[taxon] = 0 if !counts[taxon]
        counts[taxon] += 1
        total += 1
      end
    end
  else
    headers = nil
    ZFile.new(file).each do |line|
      if headers.nil?
        headers = line.downcase.chomp.split("\t")
      else
        fields = line.chomp.split("\t")
        taxon = fields[headers.index(level)]
        next if level == "kingdom" && !["Eukaryota", "Bacteria", "Archaea", "Viruses"].include?(taxon) || taxon.index("__")
        if taxon != "Undefined" && (!withTree || taxon != "NO_TREE")
          counts[taxon] = 0 if !counts[taxon]
          counts[taxon] += 1
          total += 1
        end
      end
    end
  end
  percents = Hash.new
  counts.keys.each do |key|
    percents[key] = 100*counts[key]/total.to_f
  end
  [percents, counts]
end

# collect catefgories less than miscmin % as "Misc"
def collectMisc(percents, level, miscmin)
  percents["Misc"] = 0
  keys = percents.keys
  keys.each do |key|
    if (percents[key] < miscmin && key != "Misc" && level != "kingdom")
      percents["Misc"] += percents[key]
      percents.delete(key)
    end
  end
  percents.delete("Misc") if  percents["Misc"] && percents["Misc"] < 2
  percents
end

# produce hash of color hex codes for use for consistent colors across pie taxa
def getPieColors(taxa)
  colors = ["#90B8C0","#988CA0","#FF9999","#99FF99","#CE0000",
            "#000063","#5A79A5","#9CAAC6","#DEE7EF","#84596B",
            "#B58AA5","#CECFCE","#005B9A","#0191C8","#74C2E1",
            "#8C8984","#E8D0A9","#B7AFA3","#727B84","#DF9496",
            "#00008B", "#0000CD", "#0000FF", "#006400", "#008000",
            "#008000", "#008080", "#008B8B", "#00BFFF", "#00CED1",
            "#F5FFFA", "#F8F8FF", "#FA8072" "#FAEBD7", "#FAF0E6",
            "#FAFAD2", "#000063","#5A79A5","#9CAAC6","#DEE7EF","#84596B"]
  colors *= 5 # provide duplicates of colors to stop running out
  colorTaxa = Hash.new
  taxa.keys.sort {|x,y| taxa[y] <=> taxa[x]}.each do |taxon|
    colorTaxa[taxon] = colors.shift if (colors.size > 0)
  end
  colorTaxa
end

# write Excel file of counts
def writeCountsExcel(filename, counts)
  require 'axlsx'
  proj = Axlsx::Package.new
  wb = proj.workbook
  counts.keys.each do |level|
    taxa = Hash.new
    counts[level].keys.each do |key|
      counts[level][key].keys.each do |taxon|
        taxa[taxon] = 0 if !taxa[taxon]
        taxa[taxon] += counts[level][key][taxon]
      end
    end
    sheet = wb.add_worksheet(:name=>level)
    sheet.add_row([""]+counts[level].keys)
    taxa.keys.sort{|x,y| taxa[y]<=>taxa[x]}.each do |taxon|
      row = [taxon]
      counts[level].keys.each do |key|
        row.push(counts[level][key][taxon])
      end
      sheet.add_row(row)
    end
  end
  proj.serialize(filename)
end

# returns true if file likely to be DNA, false otherwise
def isDNA?(fasta)
   seq = File.read(fasta, 10000).split("\n").grep(/^[^>]/).join
   seq.count("AGTCN").to_f / seq.length > 0.90
end

# returns species from phylodb-formattted string
def headerSpecies(header)
   begin
      header.split("{")[1].split("}")[0].split("||")[0].tr("(),:","").tr(" ","_")
   rescue
      ""
   end
end

# returns pure seguid from phylodb-formatted string
def headerSeguid(header)
   begin
      header.gsub(">","").gsub("lcl|","").split(" ")[0]
   rescue
      ""
   end
end

#returns first word from header
def headerName(header)
   begin
      header.split(" ")[0]
   rescue
      ""
   end
end

def headerFunction(header)
   begin
      seqid, ann = header.split(" ", 2)
      ann = ann.to_s.split("\<\<")[1].split("\>\>")[0].split("||")[0]
      ann
   rescue
      ""
   end
end

class Array # additional methods for Array class
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
end

# get taxonomy array (or string) for taxon
def getTaxonomy(taxon, taxonomy, joined=false)
   seqid, sp = taxon.split("__")
   tx=taxonomy[sp]
   if tx.nil?
      nil
   elsif joined
      return tx.join("; ")
   else
      tx
   end
end

class NewickNode # additional methods for NewickNode class
   # return array of arrays of taxa representing relatives at each level
   def relatives
      relatives = []
      node = self
      while(!node.nil? && !node.parent.nil?)
         relatives.push(node.parent.taxa - node.taxa)
         node = node.parent
      end
      return relatives
   end

   # returns array of consensus taxonomy at each relative level of tree
   def consensusTax(taxonomy)
      strict = []
      relaxed = []
      rels = relatives
      return  [] if rels.nil?
      rels.each do |list|
         counts = []
         list.each do |relative|
            groups = getTaxonomy(relative, taxonomy)
            next if groups.nil?
            groups.size.times do |i|
               counts[i] = Hash.new if counts[i].nil?
               counts[i][groups[i]] = 0 if counts[i][groups[i]].nil?
               counts[i][groups[i]] += 1
            end
         end
         strict.push(counts.absolute)
         relaxed.push(counts.majority)
      end
      {"strict"=>strict, "relaxed"=>relaxed}
   end
end


# routine to merge multiple blast files and sort by query seq and evalue
def mergeBlasts(blast, dataset, opts)
   STDERR << "Merging blasts...\n" if opts.verbose
   sortCmd = "sort -t $'\t' -k1,1 -k12,12rn"
   mBlastFile = dataset + "_merged.blast"

   out = File.new(mBlastFile, "w")
   counts = Hash.new
   `#{sortCmd} #{blast.join(" ")} | uniq`.split("\n").each do |line|
      next if line=~/^QUERY/
      fields = line.chomp.split("\t")
      name, evalue = fields[0], fields[10].to_f
      counts[name] = 0 if !counts[name]
      if (evalue <= opts.evalue && counts[name] < opts.maxhits)
         out.print line + "\n"
         counts[name] += 1
      end
   end
   out.close
   mBlastFile
end


# creates classificatrion hash for consensus from node
def consensus2classification(consensus, exclude, taxonomy)
   lines = []
   consensus.each do |line|
      excluded = false
      excluded = exclude.to_a.collect{|x| line.grep(/#{x}/)}.flatten
      lines.push(line) if excluded.empty?
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
      classification.push(first[level])
      classification.push(outgroup)
   end
   chash = Hash.new
   ["kingdom", "phylum", "class", "order", "family", "genus", "species"].each do |rank|
      chash[rank] = classification.shift
      chash[rank + "_outgroup"] = classification.shift
   end
   chash
end

class NewickTree # Additional methods for NewickTree class
   # returns classification of node based on taxonomy
   def classify(pid, exclude, taxonomy)
      node = findNode(pid)
      return nil if node.nil?
      cons = node.consensusTax(taxonomy)
      {"strict" => consensus2classification(cons["strict"], exclude, taxonomy),
      "relaxed" => consensus2classification(cons["relaxed"], exclude, taxonomy)}
   end
   # return the annotation of the closest sequence to id on tree
   def annotate(pid, functHash)
      relatives(pid).each do |match|
         match.each do |seq|
            id, sp = seq.split("__", 2)
            function = functHash[id].to_s.split(";").first
            if (!function.nil? &&
               function !~/unnamed/ && function !~/unknown/ &&
               function !~/numExons/ && function !~/^\{/)
               return function
            end
         end
      end
   end
end

# return most specific tax id pased on classification
def findBestTaxId(classification, tax_ids)
   tid, name = nil, nil
   ["kingdom", "phylum", "class", "order", "family", "genus", "species"].each do |level|
      id = tax_ids[classification[level]]
      if (id)
         tid = id
         name = classification[level]
      else
         break
      end
   end
   [tid, name]
end

# function to generate seguid link to metarep for drawing tree
def segLink(entry)
   metalink = "http://www.jcvi.org/phylo-metarep/phylodb/seguid/"
   return metalink + entry.gsub(":","<>").gsub("/", "[]").gsub("+","()")
end

# returns mga called proteins from DNA
def asProt(fasta, verbose)
   header = nil
   orfs = Hash.new
   STDERR << "Running mga to find ORFS...\n" if verbose
   `mga #{fasta}`.split("\n").each do |line|
      if (line =~/^#/ && (line !~ /gc =/ && line !~ /self:/))
         header = line.chomp.split("# ")[1].split(" ").first
      elsif (line =~/^gene/)
         n, s, e, strand, frame = line.chomp.split(" ")
         orfs[header] = [] if (orfs[header].nil?)
         orfs[header].push("#{s} #{e} #{strand} #{frame}")
      end
   end
   STDERR << "Writing peptides...\n" if verbose
   pep = fasta + ".pep"
   out = File.new(pep, "w")
   Bio::FlatFile.new(Bio::FastaFormat, ZFile.new(fasta)).each do |seq|
      if (orfs[seq.full_id])
         id = seq.full_id
         seq = Bio::Sequence::NA.new(seq.seq)
         orfs[id].each do |orf|
            s, e, strand, frame = orf.split(" ")
            s = s.to_i
            e = e.to_i
            frame = frame.to_i + 1
            subseq = seq.subseq(s, e)
            next if (subseq.length < 3*minOrf)
            id.gsub!("/","!")
            subseq = subseq.complement if strand == "-"
            trans = subseq.translate(frame, 11)
            out.print trans.to_fasta("#{id}_#{s}_#{e}_#{frame}_#{strand}", 60)
         end
      end
      out.close
   end
   pep
end

# load taxonomy and return species-based hash
def loadTaxonomy(taxf, verbose)
   # recusively walk up tax tree
   def recurseTaxonomy(tax, current)
      name, parent, rank = tax[current]
      if (name.nil? || name == "root" || name == "cellular organisms")
         []
      else
         recurseTaxonomy(tax, parent).to_a + [name]
      end
   end
   STDERR << "Loading taxonomy...\n" if verbose
   tax = Hash.new
   sp = Hash.new
   tax_ids = Hash.new
   taxf.each do |tf|
      ZFile.new(tf).each do |line|
         current, name, parent, rank = line.chomp.split("\t")
         name = name.tr("(),:","")
         tax[current.to_i] = [name, parent.to_i, rank]
         sp[name] = current.to_i if rank == "species" || rank == "subspecies" || rank == "no rank" || rank == "metagenome"
         tax_ids[name] = current
      end
   end
   taxonomy = Hash.new
   sp.keys.each do |s|
      taxonomy[s.gsub(" ","_")] = recurseTaxonomy(tax, sp[s])
   end
   [taxonomy, tax_ids]
end

# class for returning blast hits from m8 file, possiibly compressed
 class BlastHits
   def initialize(blast)
     @blastf = ZFile.new(blast)
   end
   def each
     pid, matches = nil, []
     @blastf.each do |line|
       qid, match = line.chomp.split("\t")
       qid = qid.split(" ").first
         if pid != qid && !pid.nil?
            yield [pid, matches]
            matches = []
         end
         pid = qid
         matches.push(line)
      end
      yield [pid, matches]
   end
   def next
      each do |pid, matches|
         return [pid, matches]
      end
   end
end

# submit job to grid
def qsystem(cmd, project)
   system("qsub -P #{project} -cwd #{cmd}")
end

# return seqs from fastacmd formatted blast database
def fetchSeqs(blastids, databases, functions = false, maxLength = 5000)
   seqs = []
   functHash = Hash.new
   databases.each do |database|
      `fastacmd -d #{database} -s "#{blastids.join(',')}" 2>/dev/null`.split(/^>/).each do |seq|
         lines = seq.split("\n")
         if !lines.empty?
            header = lines.shift
            seguid = headerSeguid(header)
            sp = headerSpecies(header)
            functHash[seguid] = headerFunction(header) if (functions)
            out = ">" + seguid + "__" + sp + "\n"
            out += lines.join("\n")
            seqs.push(out) if out.length < maxLength
         end
      end
   end
   if functions
      [seqs, functHash]
   else
      seqs
   end
end

# runs muscle to align sequences, returns alignment as row
def align(pep, pid, blastlines, databases, tmp, verbose)
   STDERR << "Making alignment for " << pid << "...\n" if verbose
   blastids = blastlines.collect{|x| x.chomp.split("\t")[1]}
   homologs, functions = fetchSeqs(blastids, databases, true)
   hom = tmp + "/" + pid + ".hom"
   out = File.new(hom.tr("*",""), "w")
   out.print ">"+pid+"\n" +pep.seq.tr("*","") + "\n" + homologs.join("\n")
   out.close
   afa = tmp + "/" + pid + ".afa"
   system("muscle -in '#{hom}' -quiet -out '#{afa}' 2> /dev/null")
   File.unlink(hom)
   [afa, functions]
end

# produces stock format needed for quicktree from fastaFormat
def fasta2Stockholm(alignFile)
   stock = alignFile + ".stock"
   stockf = File.new(stock, "w")
   stockf.printf("# STOCKHOLM 1.0\n")
   align = Hash.new
   aSize = 0
   nSize = 0
   Bio::FlatFile.new(Bio::FastaFormat, File.new(alignFile)).each do |seq|
      name = headerName(seq.definition)
      align[name] = seq.seq
      aSize = seq.seq.length
      nSize = name.size if (nSize < name.size)
   end
   0.step(aSize, 50) do |i|
      stockf.printf("\n")
      align.keys.sort.each do |key|
         stockf.printf("%-#{nSize}s %s\n", key, align[key][i..i+49])
      end
   end
   stockf.printf("//\n")
   stockf.close
   stock
end

# converts pointless stockholm alignment to a useful fasta one
def stockholm2Fasta(alignFile)
   afa = alignFile + ".afa"
   afaf = File.new(afa, "w")
   seqs = Hash.new
   start = false
   File.new(alignFile).each do |line|
      if (line =~ /^#|\/\//)
         start = true
         next
      end
      next if !start
      name, ali = line.split(" ")
      next if (!start || ali.nil?)
      ali.gsub!(".","-")
      seqs[name] = "" if (seqs[name].nil?)
      seqs[name] += ali += "\n"
   end
   seqs.keys.each do |name|
      afaf.printf(">%s\n%s",name,seqs[name])
   end
   afaf.close
   afa
end

# infers tree by desired method, populates db, returns tree
def infer(pid, afa, method, verbose)
   STDERR << "Making tree for " << pid << "...\n" if verbose
   ali = aliasFasta(afa, nil, afa + ".ali")
   tree = nil
   if (method == "nj")
      stock = fasta2Stockholm(afa + ".ali")
      nj = `quicktree -boot 100 '#{stock}'`
      tree = NewickTree.new(nj.tr("\n",""))
      tree.unAlias(ali)
      tree.midpointRoot
   end
   File.unlink(stock) if File.exists?(stock)
   File.unlink(afa + ".ali") if File.exists?(afa + ".ali")
   tree
end

def trimAlignment(trimFile, alignFile, maxGapFract = 0.5, exclude = nil)
   if (File.exist?(alignFile) && !File.exist?(trimFile))
      seqs = []
      badCols = []
      len = 0
      Bio::FlatFile.new(Bio::FastaFormat, File.new(alignFile)).each do |seq|
         seq.data.tr!("\n","")
         seqs.push(seq)
      end
      seqs[0].data.length.times do |i|
         gapNum = 0
         count = 0
         seqs.each do |seq|
            next if (exclude && seq.full_id =~/#{exclude}/)
            gapNum += 1 if (seq.data[i].chr == "-" || seq.data[i].chr == "?" || seq.data[i].chr == ".")
            count += 1
         end
         badCols.push(i) if (gapNum > maxGapFract*count)
      end
      out = File.new(trimFile, "w")
      seqs.each do |seq|
         badCols.each do |col|
            seq.data[col] = "!"
         end
         seq.data.tr!("!","")
         len = seq.data.length
         out.print Bio::Sequence.auto(seq.data).to_fasta(seq.definition, 60)
      end
      out.close
      return len if len > 0
   end
   return nil
end

# back aligns dna to pep alignment and puts it in dnaAlign
def backAlign(dna, pepAlign, dnaAlign)
   pep = Hash.new
   Bio::FlatFile.new(Bio::FastaFormat, File.new(pepAlign)).each do |seq|
      pep[seq.full_id] = seq.seq
   end
   dnaAlign = File.new(dnaAlign, "w")
   Bio::FlatFile.new(Bio::FastaFormat, File.new(dna)).each do |seq|
      if (!pep[seq.full_id])
         raise "No #{seq.full_id} in #{pepAlign}\n"
      end
      dseq = ""
      j = 0
      pep[seq.full_id].length.times do |i|
         c = pep[seq.full_id][i].chr
         if (c == "-")
            dseq += "---"
         else
            dseq += seq.seq[j..j+2]
            j += 3
         end
      end
      dnaAlign.print Bio::Sequence::NA.new(dseq).to_fasta(seq.definition, 60)
   end
   dnaAlign.close
end

# calc average percent identity of an fasta alignment
def calcPercentIdent(fasta)
   pos = nil
   idents = []
   len = nil
   counts = 0
   Bio::FlatFile.new(Bio::FastaFormat, File.new(fasta)).each do |seq1|
      len = seq1.length if len.nil?
      Bio::FlatFile.new(Bio::FastaFormat, File.new(fasta)).each do |seq2|
         next if seq2.full_id == seq1.full_id
         idents.push(0)
         seq1.length.times do |i|
            idents[idents.size - 1] += 1 if (seq1.seq[i] == seq2.seq[i])
         end
      end
   end
   tot = 0
   idents.each {|ident| tot+=ident}
   avIdent = (tot * 100 / idents.size) / len
   return avIdent
end

# given a NewickTree and an alignment add ML distances
def estimateMLBranchLengths(tree, alignFile, tmpdir)
   outgroup = tree.taxa.sort.last
   tree.reroot(tree.findNode(outgroup))
   bClades = tree.clades(true)
   fasta2Phylip(alignFile, "#{tmpdir}/infile")
   tree.write("#{tmpdir}/intree")
   treepuzzle = "puzzle infile intree"
   system("cd #{tmpdir};echo  \"y\" | #{treepuzzle} > /dev/null")
   tree = NewickTree.fromFile("#{tmpdir}/intree.tree")
   tree.reroot(tree.findNode(outgroup))
   tree.addBootStrap(bClades)
   File.unlink(tmpdir+"/intree", tmpdir+"/intree.tree", tmpdir+"/infile")
   File.unlink(tmpdir+"/intree.dist", tmpdir+"/intree.puzzle")
   return tree
end

def fasta2Phylip(alignFile, phyFile)
   seqs = Hash.new
   name = nil
   inFile = File.new(alignFile)
   inFile.each do |line|
      line.chomp!
      line.tr!("*","")
      if (line =~ /^>/)
         name = line[1..line.length].split(";").pop
         seqs[name] = ""
      else
         seqs[name] += line.gsub(".","-")
      end
   end
   inFile.close
   phy = File.new(phyFile, "w")
   lineLen = 60
   phy.printf("%d %d\n", seqs.size, seqs[name].length)
   pos = 0
   while (pos < seqs[name].length)
      seqs.keys.sort.each do |name|
         if (pos == 0)
            phy.printf("%-10s ", name)
         end
         phy.printf("%s\n", seqs[name][pos..pos + lineLen - 1])
      end
      pos += lineLen
      phy.printf("\n")
   end
   phy.close
end

def removeAA(trimFile, alignFile, aaList)
   if (File.exist?(alignFile) && !File.exist?(trimFile))
      seqs = []
      badCols = []
      Bio::FlatFile.new(Bio::FastaFormat, File.new(alignFile)).each do |seq|
         seq.data.tr!("\n","")
         seqs.push(seq)
      end
      seqs[0].data.length.times do |i|
         bad = 0
         seqs.each do |seq|
            bad += 1 if aaList.include?(seq.data[i].chr)
         end
         badCols.push(i) if (bad == seqs.size)
      end
      out = File.new(trimFile, "w")
      seqs.each do |seq|
         badCols.each do |col|
            seq.data[col] = "!"
         end
         seq.data.tr!("!","")
         out.print Bio::Sequence.auto(seq.data).to_fasta(seq.definition, 60)
      end
      out.close
   end
end

def fasta2Nexus(alignFile, dna, nexFile = nil)
   seqs = Hash.new
   name = nil
   seqFile = File.new(alignFile)
   Bio::FlatFile.new(Bio::FastaFormat, seqFile).each do |seq|
      seqs[seq.full_id] = seq.seq.gsub("?","-").gsub(".","-")
   end
   seqFile.close
   if (dna)
      type = "NUC"
   else
      type = "PROT"
   end
   if (nexFile.nil?)
      out = STDOUT
   else
      out = File.new(nexFile, "w")
   end
   lineLen = 40
   aLen = seqs[seqs.keys.first].size
   out.print "#NEXUS\nBEGIN DATA;\n"
   out.print "DIMENSIONS NTAX=#{seqs.size} NCHAR=#{aLen};\n"
   out.print "FORMAT DATATYPE=#{type} INTERLEAVE MISSING=-;\n"
   out.print "MATRIX\n"
   pos = 0
   while (pos < aLen)
      seqs.keys.sort.each do |name|
         out.printf("%35s ", name)
         out.printf("%s\n", seqs[name][pos..pos + lineLen - 1])
      end
      pos += lineLen
      out.printf("\n")
   end
   out.print ";\nEND;\n"
   out.close if nexFile
end

def aliasFasta(fasta, ali, out, outgroup = nil, trim = false)
   outFile = File.new(out, "w")
   aliFile = File.new(ali, "w") if (!ali.nil?)
   aliHash = Hash.new
   orfNum = "SID0000001"
   Bio::FlatFile.new(Bio::FastaFormat, File.new(fasta)).each do |seq|
      newName = orfNum
      name = seq.definition.split(" ").first
      newName = "SID0000000" if (outgroup == name)
      aliFile.printf("%s\t%s\n", newName, seq.definition) if (ali)
      aliHash[newName] = seq.definition
      seq.definition = newName
      outFile.print seq
      orfNum = orfNum.succ if (outgroup != name)
   end
   outFile.close
   aliFile.close if (ali)
   if (@trim)
      trimAlignment(out+"_trim", out)
      File.unlink(out)
      File.rename(out+"_trim", out)
   end
   return aliHash
end

if Object.const_defined?("Yajl") # Has Yajl been loaded?
   # add JSON encoding to every object
   class Object
      def to_json_pp
         Yajl::Encoder.encode(self,:pretty => true) + "\n"
      end
   end
   class JsonStreamer
      def initialize(filehandle)
         @filehandle = filehandle
      end
      def each
         parser = Yajl::Parser.new
         parser.on_parse_complete = proc{|obj| yield obj}
         @filehandle.each do |line|
            parser << line
         end
      end
   end
end

if Object.const_defined?("Bio") # has bioruby been loaded?
   # do this to avoid splitting on "|"
   class Bio::FastaFormat
      def full_id
         return definition.split(" ").first
      end
   end
end


# generate command line from trollop opts, minus unwanted options as array of symbols
def cmdLine(prog, opts, exclude)
   cmd = prog
   keys = opts.keys - exclude - [:help]
   keys.each do |key|
      k = key.to_s
      val = opts[key]
      if val.is_a?(Array)
         val = val.join(" ")
      end
      cmd += " --#{key} #{val}" if !k.index("_given") && val
   end
   cmd
end

# returns number of lines in file
def countLines(file)
   size = 0
   ZFile.new(file).each do |line|
      size += 1
   end
   size
end

# returns number of fasta seqs in file
def countFasta(file)
   size = 0
   Bio::FlatFile.new(Bio::FastaFormat, ZFile.new(file)).each do |seq|
      size += 1
   end
   size
end

# return hash of processed peptides from json
def getProcessed(fileName, verbose)
   STDERR << "Loading processed data...\n" if verbose
   process = Hash.new
   if File.exists?(fileName)
      JsonStreamer.new(ZFile.new(fileName)).each do |this|
         process[this["name"]] = true
      end
   end
   process
end

# jumps to first set of blast hits of peptide found in input
def scanBlast(blastHits, fasta)
   present = Hash.new
   Bio::FlatFile.new(Bio::FastaFormat, ZFile.new(fasta)).each do |pep|
      pid = pep.full_id
      present[pid] = true
   end
   bpid, blastLines = blastHits.next
   while (!bpid.nil? && !present[bpid])
      bpid, blastLines = blastHits.next
   end
   [bpid, blastLines]
end

#return file of blast records from unprocessed peptides
def remainingBlast(blast, processed, verbose)
   remain = File.basename(blast) + "_remaining"
   out = File.new(remain, "w")
   BlastHits.new(blast).each do |pid, hits|
      if !processed[pid]
         hits.each do |hit|
            out << hit
         end
      end
   end
   out.close
   remain
end


# creates grid array, runs it, and cleans up
def runGridApis(opts, dataset, blast, n = 1000)
   processed = getProcessed(dataset + "_apis.json", opts.verbose)
   if processed.keys.size > 0
      blast = remainingBlast(blast, processed, opts.verbose)
   end
   cmd = cmdLine(File.basename($0) + " --scan --erase ", opts, [:project, :queue, :input, :blasts])
   cmd += " --blasts " + blast
   cmd += " --input "
   tmp = opts.tmp + "/" + dataset
   grid = Grid.new(cmd, opts.project, "4G", "medium", tmp)
   STDERR << "Splitting peptide file for grid...\n" if opts.verbose
   seqCount = countFasta(opts.input)
   binSize = seqCount/n
   binSize = 10 if binSize < 10
   count = binSize
   out = nil
   Dir.glob(tmp + "/*").each do |file|
      begin
         File.unlink(file)
      rescue
      end
   end
   Bio::FlatFile.new(Bio::FastaFormat, ZFile.new(opts.input)).each do |pep|
      pid = pep.full_id
      if !processed[pid]
         if count >= binSize
            out.close if !out.nil?
            count = 0
            out = File.new(grid.next, "w")
         end
         out.print pep
         count += 1
      end
   end
   out.close if !out.nil?
   grid.submit(true, !opts.project, opts.verbose, opts.maxlocal)
   endings = ["afa.json", "apis.json", "error.json"]
   grid.join(endings, dataset)
   File.unlink(blast) if processed.keys.size > 0
end

# converts hash to openstruct
class Hash
   def to_ostruct
      convert_to_ostruct_recursive(self)
   end

   private
   def convert_to_ostruct_recursive(obj)
      result = obj
      if result.is_a? Hash
         result = result.dup
         result.each  do |key, val|
            result[key] = convert_to_ostruct_recursive(val)
         end
         result = OpenStruct.new result
      elsif result.is_a? Array
         result = result.map { |r| convert_to_ostruct_recursive(r) }
      end
      result
   end
end

def cleanup(dir)
   Dir.glob(dir+"/*").each do |file|
      File.unlink(file)
   end
   Dir.unlink(dir)
end
