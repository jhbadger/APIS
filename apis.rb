require 'Newick'
require 'Phylogeny'
require 'ApisDB'
require 'ZFile'
require 'SunGrid'

$VERBOSE = false

# run NCBI blast for a given sequence
def runBlast(db, seq, dataset, maxHits, evalue, proteindb)
  if (db.count("blast where dataset = '#{dataset}' and seq_name = '#{seq.entry_id}'") == 0)
    STDERR.printf("Currently creating blast for #{seq.entry_id}...\n")
    STDERR.flush
    seqFile = File.new(seq.entry_id + ".pep", "w")
    seqFile.print seq.seq.gsub("*","").to_fasta(seq.entry_id)
    seqFile.close
    blast = "blastall -p blastp -d #{proteindb} -i '#{seq.entry_id+".pep"}' "
    blast += "-b#{maxHits} -v#{maxHits} -e#{evalue}"
    system("#{blast} > '#{seq.entry_id}.blast' 2>/dev/null")
    if (File.size(seq.entry_id + ".blast") > 300) # skip empty BLAST
      brows = []
      Bio::Blast::Default::Report.open(seq.entry_id + ".blast", "r").each do |query|
        query.each do |subject|
          sname, sdef = subject.definition.split(" ",2)
          sdef = sdef[0,1000] if (sdef.length > 1000)
          subject.hsps.each do |hsp|
            begin
              brows.push([seq.entry_id, dataset, sname, sdef, 
                          subject.target_len, hsp.query_from, 
                          hsp.query_to, hsp.hit_from, hsp.hit_to, 
                          hsp.percent_identity, hsp.percent_positive,
                          hsp.score, hsp.evalue])
            rescue
              STDERR.printf("skipping HSP in %s...\n", seq.entry_id)
              STDERR.flush
            end
          end
        end
      end
      db.insert("blast", brows)
    end
  end
end

# run MUSCLE for a given list of homologs
def runAlignment(db, seq, dataset, blastHomologs, proteindb, gblocks)
  hom = seq.entry_id + ".hom"
  homFile = File.new(hom, "w")
  spHash = Hash.new
  functHash = Hash.new
  
  homFile.print seq.seq.gsub("*","").to_fasta(seq.entry_id)
  homs = blastHomologs.join(",")
  `fastacmd -d #{proteindb} -s "#{homs}"`.split(/^>/).each do |record|
    next if record == "" || record.nil?
    header, sq = record.split("\n", 2)
    seqid, ann = header.split(" ")
    seqid.gsub!("lcl|", "")
    ann = ann.to_s.split("||").first
    ann, sp = ann.to_s.split("::")
    spHash[seqid] = sp
    functHash[seqid] = ann
    homFile.print ">" + seqid + "\n"
    homFile.print sq.to_s.gsub("\n","").gsub(Regexp.new(".{1,60}"), "\\0\n")
  end
  homFile.close
  STDERR.printf("Aligning %s...\n", seq.entry_id)
  STDERR.flush
  align = "muscle -quiet -in " + hom + " -out " + seq.entry_id + ".out"
  system(align)
  if (gblocks)
   len = gblocks(seq.entry_id + ".afa", seq.entry_id + ".out")
  else
    len = trimAlignment(seq.entry_id + ".afa", seq.entry_id + ".out")
  end
  db.createAlignment(seq.entry_id, dataset, seq.entry_id + ".afa")
  if (!len.nil? && len > 0)
    return seq.entry_id + ".afa", spHash, functHash
  else
    return nil, nil, nil
  end
end

def runPhylogeny(db, seq, dataset, alignFile)
  treeFile = seq.entry_id + ".tree"
  begin 
    makeQuickNJTree(treeFile, alignFile, seq.entry_id, true)
  rescue
    STDERR.printf("Problem %s inferring tree %s. Skipping\n", $!, treeFile)
    STDERR.flush
    return
  end
  return treeFile
end

def processTree(db, seq, dataset, treeFile, spHash, 
                functHash, annotate, exclude, ruleMaj)
  if (!treeFile.nil? && File.exist?(treeFile))
    begin
      id = seq.entry_id
      addSpecies(seq, treeFile, spHash)
      db.createTree(id, dataset, File.read(treeFile))
      tree = NewickTree.fromFile(treeFile)
      db.createClassification(tree, id, dataset, exclude, ruleMaj)
      db.createAnnotation(tree, id, dataset, functHash) if annotate
    rescue
      STDERR.printf("Problem %s handling %s. Skipping\n", $!, treeFile)
      STDERR.flush
      return
    end
  end
end

def coverage(seq, hit)
  return 0 if (hit.nil? || hit.query_end.nil?)
  blast_len = 0
  hit.hsps.each do |hsp|
    begin
      blast_len += hsp.align_len
    rescue
    end
  end
  full_length = [hit.len, seq.length].max
  return blast_len * 1.0 / full_length
end


# creates a protein file (if needed) and returns the new file
def asProt(fasta, minOrf, verbose = nil, dna = false)
  count = 0
  string = ""
  begin
    ZFile.new(fasta).each do |line|
      next if (line =~ /^>/)
      string += line.chomp.upcase
      count += 1
      break if count == 1000
    end
  rescue
  end
  agtc = 1.0 * string.count("AGTCN")
  if (agtc / string.size > 0.90)
    prot = File.basename(fasta) + ".pep"
    if (!File.exists?(prot))
      STDERR.printf("%s seems to be DNA. Creating translation: %s...\n",
                    fasta, prot)
      STDERR.flush
      dnaOut= File.basename(fasta) + ".cds" if dna
      out = File.new(prot, "w")
      dnaF = File.new(dnaOut, "w") if dna
      $VERBOSE = nil
      if (fasta.index(".gz") || fasta.index(".bz2"))
        tmp = File.new(fasta + ".tmp", "w")
        ZFile.new(fasta).each do |line|
          tmp.print line
        end
        tmp.close
        fasta = fasta + ".tmp"
      end
      header = nil
      orfs = Hash.new
      `mga #{fasta}`.split("\n").each do |line|
        if (line =~/^#/ && (line !~ /gc =/ && line !~ /self:/))
          header = line.chomp.split("# ")[1].split(" ").first
        elsif (line =~/^gene/)
          n, s, e, strand, frame = line.chomp.split(" ")
          orfs[header] = [] if (orfs[header].nil?)
          orfs[header].push("#{s} #{e} #{strand} #{frame}")
        end
      end
      Bio::FlatFile.new(Bio::FastaFormat, ZFile.new(fasta)).each do |seq|
        if (orfs[seq.entry_id])
          id = seq.entry_id
          seq = Bio::Sequence::NA.new(seq.seq)
          orfs[id].each do |orf|
            s, e, strand, frame = orf.split(" ")
            s = s.to_i
            e = e.to_i
            frame = frame.to_i + 1
            subseq = seq.subseq(s, e)
            next if (subseq.length < 3*minOrf)
            id.gsub!("/","!")
            if (strand == "+")
              trans = subseq.translate(frame, 11)
              out.print trans.to_fasta("#{id}_#{s}_#{e}_#{frame}", 60)
              dnaF.print subseq.to_fasta("#{id}_#{s}_#{e}_#{frame}", 60) if (dna)
            else
              subseq = subseq.complement
              trans = subseq.translate(frame, 11)
              out.print trans.to_fasta("#{id}_#{e}_#{s}_#{frame}", 60)
              dnaF.print subseq.to_fasta("#{id}_#{e}_#{s}_#{frame}", 60) if (dna)
            end
          end
        end
      end
      out.close
    end
    File.unlink(fasta) if (fasta.include?(".tmp"))
    fasta = prot
  elsif (verbose)
    STDERR.printf("Not DNA!\n")
    STDERR.flush
  end
  return fasta
end

# deletes temporary files if they exist
def deleteFiles(name, extensions)
  extensions.each do |ext|
    file = name + ext
    File.unlink(file) if File.exists?(file)
  end
end

# pipeline for a single protein
def processPep(db, seq, dataset, opt)
  seq.definition.gsub!("|","_")
  seq.entry_id.gsub!("(","")
  seq.entry_id.gsub!(")","")
  if (!db.processed?(seq.entry_id, dataset))
    runBlast(db, seq, dataset, opt.maxHits, opt.evalue, 
             opt.proteindb) if (!opt.skipBlast)
    blastHomologs = db.fetchBlast(seq.entry_id, dataset, 
                                  opt.evalue, opt.maxTree)
    if (!blastHomologs.nil? && blastHomologs.size > 2)
      alignFile, spHash, functHash = runAlignment(db, seq, 
        dataset, blastHomologs, opt.proteindb, opt.gblocks) if (!opt.skipTree)
      if (!alignFile.nil?)
        treeFile = runPhylogeny(db, seq, dataset, alignFile) if (!opt.skipTree)
        processTree(db, seq, dataset, treeFile, spHash, 
                    functHash, opt.annotate, opt.exclude, 
                    opt.ruleMaj)
      end
    end
    deleteFiles(seq.entry_id, [".pep", ".tree", ".afa", ".hom", ".blast",
                              ".out"])
    db.setProcessed(seq.entry_id, dataset)
  end
end


# runs blast job on TimeLogic Server
def runTimeLogic(prot, db, dataset, opt)
  server, user, password = opt.timelogic.split(":")
  if (password.nil?)
    STDERR.printf("To use TimeLogic you must supply server:user:password (eg. tmlsrv2:cventer:darwin)\n")
    exit(1)
  end
  dcshow = "dc_show -database a -user #{user} -password #{password} -server #{server}"
  timedb = `#{dcshow} | grep #{File.basename(opt.proteindb)}`.split(" ").first
  if (db.count("blast where dataset = '#{dataset}'") == 0)
    STDERR.printf("Currently creating blast on Timelogic Server...\n")
    STDERR.flush
    command = "dc_run -parameters tera-blastp "
    command += "-query " + prot + " "
    command += "-database " + timedb + " "
    command += "-threshold significance=#{opt.evalue} "
    command += "-max_alignments #{opt.maxHits} "
    command += "-server #{server} -user #{user} -password #{password} "
    command += "-output_format tab "
    command += "-field querylocus targetlocus targetdescription targetlength "
    command += "querystart queryend targetstart targetend percentalignment "
    command += "simpercentalignment score significance"
    system("#{command} > #{prot}.blast") if (!File.exists?(prot + ".blast"))
    brows = []
    oldQuery = nil
    count = 0
    STDERR.printf("Loading Timelogic output...\n")
    File.new(prot + ".blast").each do |line|
      query, target, desc, tlen, qstart, qend, 
        tstart, tend, ident, pos, score, sig = line.chomp.split("\t")
      count += 1 if (oldQuery != query)
      oldQuery = query
      if (count % 100 == 0)
        db.insert("blast", brows)
        brows = []
        STDERR.printf("Loading blast for sequence %d...\n", count)
      end
      desc = desc[0,1000] if desc.length > 1000
      brows.push([query, dataset, target, desc, 
        tlen.to_i, qstart.to_i, qend.to_i, tstart.to_i, tend.to_i, 
        ident.to_i, pos.to_i, score.to_i, sig.to_f]) if ident.to_i > 0
    end
    db.insert("blast", brows) if brows.size > 0
    File.unlink(prot + ".blast")
  end
end

# split prot into chunks and run on grid
def runGridApis(db, dataset, opt)
  if (opt.project.nil?)
    STDERR.printf("A JCVI project number is needed for grid jobs\n")
    exit(1)
  end
  cmd = "apisRun "
  cmd += "-a " if opt.annotate
  cmd += "-d #{opt.proteindb} "
  cmd += "-h #{opt.host} "
  cmd += "-t #{opt.maxTree} "
  cmd += "-g " if (opt.gblocks)
  cmd += "-s #{opt.storage} "
  cmd += "-x " if (opt.skipBlast || opt.timelogic)
  cmd += "-r " if (opt.ruleMaj)
  cmd += "-y '#{opt.exclude}' " if (opt.exclude)
  cmd += "--erase -l -m #{opt.maxHits} -e #{opt.evalue} -f #{opt.coverage} "
  grid = SunGrid.new(cmd, opt.project, "4G", opt.queue)
  grid.name = "apisRun_" + dataset
  STDERR.printf("Splitting pep file for grid...\n")
  out = nil
  count = 0
  db.query("select seq_name, sequence from sequence where dataset = '#{dataset}' and processed = 0").each do |row|
    seq = ">#{row[0]}\n#{row[1].gsub(Regexp.new(".{1,60}"), "\\0\n")}"
    if (count % opt.gridSize == 0)
      out.close if (!out.nil?)
      pepName = grid.next
      out = File.new(pepName, "w")
    end 
    out.print seq
    count += 1
  end
  out.close if (!out.nil?)
  grid.submit(sync=true)
  grid.cleanup
end
