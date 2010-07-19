require 'Newick'
require 'Phylogeny'
require 'DBwrapper'
require 'ZFile'

$VERBOSE = false

# run NCBI blast for a given sequence
def runBlast(storage, seq, dataset, maxHits, evalue)
  if (storage.count("blast where dataset = '#{dataset}' and seq_name = '#{seq.entry_id}'") == 0)
    STDERR.printf("Currently creating blast for #{seq.entry_id}...\n")
    STDERR.flush
    seqFile = File.new(seq.entry_id + ".pep", "w")
    seqFile.printf(">%s\n%s", seq.entry_id, seq.seq.gsub("*","").gsub(Regexp.new(".{1,60}"), "\\0\n"))
    seqFile.close
    blast = "blastall -p blastp -d #{storage.blastdb} -i '#{seq.entry_id+".pep"}' "
    blast += "-b#{maxHits} -v#{maxHits} -e#{evalue}"
    storage.close
    system("#{blast} > '#{seq.entry_id}.blast' 2>/dev/null")
    storage.connect
    if (File.size(seq.entry_id + ".blast") > 300) # skip empty BLAST
      brows = []
      Bio::Blast::Default::Report.open(seq.entry_id + ".blast", "r").each {|query|
        query.each {|subject|
          sname, sdef = subject.definition.split(" ",2)
          subject.hsps.each {|hsp|
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
          }
        }
      }
      storage.insert("blast", brows)
      storage.close
    end
  end
end

# run MUSCLE for a given list of homologs
def runAlignment(storage, seq, dataset, blastHomologs, gblocks) 
  homFile = File.new(seq.entry_id + ".hom", "w")
  homFile.printf(">%s\n%s", seq.entry_id, seq.seq.gsub("*","").gsub(Regexp.new(".{1,60}"), "\\0\n"))
  blastHomologs.each {|hom|
    next if hom == seq.entry_id
    s, len = storage.fetchProtID(hom)
    homFile.print s if (!s.nil?)
  }
  homFile.close
  STDERR.printf("Aligning %s...\n", seq.entry_id)
  STDERR.flush
  storage.close
  system("muscle -quiet -in '#{seq.entry_id}.hom' -out '#{seq.entry_id}.out'")
  if (gblocks)
   len = gblocks(seq.entry_id + ".afa", seq.entry_id + ".out")
  else
    len = trimAlignment(seq.entry_id + ".afa", seq.entry_id + ".out")
  end
  storage.connect
  storage.createAlignment(seq.entry_id, dataset, seq.entry_id + ".afa")
  if (len > 0)
    return seq.entry_id + ".afa"
  else
    return nil
  end
end

def runPhylogeny(storage, seq, dataset, alignFile)
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

def processTree(storage, seq, dataset, treeFile, alignFile, 
                annotate, exclude, ruleMaj)
  if (!treeFile.nil? && File.exist?(treeFile))
    begin
      id = seq.entry_id
      addSpecies(seq, treeFile, alignFile)
      storage.createTree(id, dataset, File.read(treeFile))
      tree = NewickTree.fromFile(treeFile)
      storage.createClassification(tree, id, dataset, exclude, ruleMaj)
      storage.createAnnotation(tree, id, dataset) if annotate
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
  hit.hsps.each {|hsp|
    begin
      blast_len += hsp.align_len
    rescue
    end
  }
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
  extensions.each {|ext|
    file = name + ext
    File.unlink(file) if File.exists?(file)
  }
end

# pipeline for a single protein
def processPep(storage, seq, dataset, opt)
  seq.definition.gsub!("|","_")
  seq.entry_id.gsub!("(","")
  seq.entry_id.gsub!(")","")
  if (!storage.processed?(seq.entry_id, dataset))
    runBlast(storage, seq, dataset, opt.maxHits, opt.evalue) if (!opt.skipBlast)
    blastHomologs = storage.fetchBlast(seq.entry_id, dataset, opt.evalue, 
                                       opt.maxTree, storage.tax)
    if (blastHomologs.size > 2)
      alignFile = runAlignment(storage, seq, dataset, blastHomologs,
                               opt.gblocks) 
      if (!alignFile.nil?)
        treeFile = runPhylogeny(storage, seq, dataset, alignFile)
        processTree(storage, seq, dataset, treeFile, alignFile, 
                    opt.annotate, opt.exclude, opt.ruleMaj)    
      end
    end
    deleteFiles(seq.entry_id, [".pep", ".tree", ".afa", ".hom", ".blast",
                              ".out"])
    storage.setProcessed(seq.entry_id, dataset)
  end
end

# split prot into chunks and run on grid
def runGridApis(storage, dataset, opt)
  if (opt.project.nil?)
    STDERR.printf("A JCVI project number is needed for grid jobs\n")
    exit(1)
  end
  STDERR.printf("Splitting pep file for grid...\n")
  count = 0
  pepName = dataset + ".PEP000001"
  peps = []
  out = nil
  count = 0
  storage.query("select seq_name, sequence from sequence where dataset = '#{dataset}' and processed = 0").each {|row|
    seq = ">#{row[0]}\n#{row[1].gsub(Regexp.new(".{1,60}"), "\\0\n")}"
    if (count % opt.gridSize == 0)
      out.close if (!out.nil?)
      out = File.new(pepName + ".pep", "w")
      peps.push(pepName.dup)
      pepName.succ!
    end 
    out.print seq
    count += 1
  }
  out.close if (!out.nil?)
  cmd = "apisRun "
  cmd += "-a " if opt.annotate
  cmd += "-t #{opt.maxTree} "
  cmd += "-d #{opt.database} "
  cmd += "-g " if (opt.gblocks)
  cmd += "-s #{opt.storage} "
  cmd += "-x " if (opt.skipBlast)
  cmd += "-r " if (opt.ruleMaj)
  cmd += "-y '#{opt.exclude}' " if (opt.exclude)
  cmd += "--erase -l -m #{opt.maxHits} -e #{opt.evalue} -f #{opt.coverage} "
  if (opt.queue != "default")
    queue = "-l \"#{opt.queue},memory=4G\""
  else
    queue = "-l \"memory=4G\""
  end
  qsub = "qsub -P #{opt.project} #{queue} -e apis.err -cwd -o apis.out "
  peps.each {|pep|
    STDERR.printf("Submitting #{pep} to the grid...\n")
    STDERR.flush
    system("#{qsub} \"#{cmd} #{pep}.pep\"")
  }
end
