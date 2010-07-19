require 'rubygems'
require 'sinatra'
require 'bio'
require 'fpdf'
require 'gchart'
require 'haml'
require 'Newick'
require 'DBwrapper'

helpers do
  # write html out of a hash for testing purposes
  def hash_to_html(hash)
    html = ""
    hash.keys.sort.each {|key|
      html += (key.to_s + " = " + hash[key].to_s + "<br>\n")
    }
    return html
  end
  
  # make pie chart from percents
  def pie(percents)
    data = Hash.new
    percents.keys.each {|key|
      item = key.gsub("Contained within ","")
      item.gsub!("Outgroup of ","")
      if (data[item])
        data[item] += percents[key]
      else
        data[item] = percents[key]
      end
    }
    data.keys.each {|key|
      if (data[key] < 2.0)
        data["Other"] = 0 if data["Other"].nil?
        data["Other"] += data[key]
        data.delete(key)
      end
    }
    chart = Gchart.pie(:theme => :pastel, :data => data.values, 
      :legend => data.keys, :width=>500)
    return "<img src=\"" + chart + "\"/>"
  end
  
  # displays a line for a single protein
  def seqLine(db, dataset, name, ann)
    base = request.url.split("#{db}/#{dataset}").first
    line = ""
    ["blast", "tree", "pdf", "id_pdf", "alignment", "seq"].each {|link|
      line += "<A HREF=\"#{base}#{db}/#{dataset}/#{name}/#{link}\">"
      line += "#{link}</A> "
    }
    ann, rest = ann.to_s.split(" {")
    line += name +"\t" + ann.to_s + "<br>\n"
    return line
  end

  # show list of seqs
  def showList(db, dataset, level, group)
    html = ""
    html += "<H1>#{dataset}: #{group.gsub("_", " ")}</H1>\n"
    outgroup, prep, group = group.split("_", 3)
    group.gsub!("_", " ")
    if (outgroup == "Contained")
      outgroup = 0
    else
      outgroup = 1
    end
    query = "SELECT classification.seq_name, annotation FROM classification "
    query += "LEFT JOIN annotation ON classification.dataset = annotation.dataset "
    query += "AND classification.seq_name = annotation.seq_name WHERE "
    query += "classification.dataset='#{dataset}' AND #{level}='#{group}' "
    query += "AND #{level}_outgroup = #{outgroup} ORDER BY "
    query += "classification.seq_name"
    count = 0
    settings.dbs[db].query(query).each {|row|
      name, ann = row
      html += seqLine(db, dataset, name, ann)
      count += 1
      break if count > 1000
    }
    settings.dbs[db].close
    return html
  end
  
  # return list of matching seqs
  def search(db, dataset, params)
    query = "SELECT classification.seq_name, annotation FROM classification "
    query += "LEFT JOIN annotation ON classification.dataset = annotation.dataset "
    query += "AND classification.seq_name = annotation.seq_name WHERE "
    query += "classification.dataset='#{dataset}' "
    if (params["ann"])
      query += "AND annotation LIKE '%#{params["ann"]}%' "
      search = params["ann"]
    else
      query += "AND classification.seq_name LIKE '%#{params["seq"]}%' "
      search = params["seq"]
    end
    query += "ORDER BY classification.seq_name"
    html = ""
    html += "<H1>#{dataset}: matching #{search}</H1>\n"
    settings.dbs[db].query(query).each {|row|
      name, ann = row
      html += seqLine(db, dataset, name, ann)
    }
    settings.dbs[db].close
    return html
  end
end

# root of web app
get "/?" do
  @title = "APIS: Automated Phylogenetic Inference System"
  @project_name = "APIS: Automated Phylogenetic Inference System"
  base = request.url
  base += "/" if base[base.length - 1].chr != "/"
  if (ENV["WEBTIER"] != "prod")
    @main_content = "<H1>Choose a Database</H1>"
    settings.dbs.keys.sort.each {|db|
      @main_content += "<A HREF=\"#{base}#{db}\">#{db}</a><br>\n"
    }
  else
    @main_content = "Listing disabled"
  end
  haml :jcvi
end

# dataset lists
get  "/:db" do |db|
  @title = "APIS: Automated Phylogenetic Inference System: #{db}"
  @project_name = "APIS: Automated Phylogenetic Inference System"
  @main_content = "<H1>Choose a Dataset</H1>"
  if (settings.dbs[db])
    @main_content += "<TABLE>\n"
    @main_content += "<TR><TD><A HREF=\"#{db}?sort=dataset\">Name</A></TD>"
    @main_content += "<TD><A HREF=\"#{db}?sort=owner\">Owner</A></TD>"
    @main_content += "<TD><A HREF=\"#{db}?sort=date_added\">Date</A></TD>"
    params["sort"] = "dataset" if params["sort"].nil?
    if (ENV["WEBTIER"] != "prod")
      @main_content += "<TD><A HREF=\"#{db}?sort=database_used\">Database</A></TD></TR>\n"
      query = "SELECT dataset, owner, date_added, database_used FROM dataset ORDER BY #{params["sort"]}"
      settings.dbs[db].query(query).each {|row|
        dataset, owner, date, database = row
        @main_content += "<TR>"
        @main_content += "<TD><A HREF=\"#{db}/#{dataset}\">#{dataset}</a><br></TD>"
        if (!database.nil?)
          @main_content += "<TD>#{owner}</TD><TD>#{date}</TD><TD>#{database}</TD>"
        end
        @main_content += "</TR>\n"
      }
      @main_content += "</TABLE>\n"
    else
      @main_content = "Listing disabled"
    end
  else
    @main_content = "<H1>No such database as #{db}</H1>"
  end
  haml :jcvi
end

# BLAST results
get "/:db/:dataset/:seq/blast" do |db, dataset, seq|
  @title = "APIS: Automated Phylogenetic Inference System: #{seq} BLAST"
  @project_name = "APIS: Automated Phylogenetic Inference System"
  @main_content = "<H1>BLAST report for #{seq}</H1>"
  @main_content += "<TABLE><TR>"
  @main_content += ["E-value", "Subject", "Desc", "QStart", "QEnd", "SStart", "End", "Score"].collect {|x| "<TD>#{x}</TD>"}.to_s
  @main_content += "</TR>\n"
  settings.dbs[db].query("SELECT evalue, subject_name, subject_description, query_start, query_end,  subject_start, subject_end, score FROM blast WHERE dataset='#{dataset}' AND seq_name = '#{seq}' ORDER BY evalue").each {|row|
    @main_content += "<TR>"
    @main_content += row.collect {|x| "<TD>#{x}</TD>"}.to_s
    @main_content += "</TR>\n"
  }
  @main_content += "</TABLE>"
  settings.dbs[db].close
  haml :jcvi
end
 
# Tree data
get "/:db/:dataset/:seq/tree" do |db, dataset, seq|
  @title = "APIS: Automated Phylogenetic Inference System: #{seq} Tree"
  @project_name = "APIS: Automated Phylogenetic Inference System"
  @main_content = ""
  tree = ""
  settings.dbs[db].query("SELECT tree FROM tree WHERE dataset='#{dataset}' AND seq_name = '#{seq}'").each {|row|
    tree += row[0]
  }
  tree.split(",").each {|part|
    @main_content += part 
    @main_content += "," if (!part.index(");"))
    @main_content += "<BR>\n"
  }
  settings.dbs[db].close
  haml :jcvi
end

# function to generate gi link to ncbi, manatee for draw, below
 def phyLink(entry)
   ncbiLink = "http://www.ncbi.nlm.nih.gov/entrez/"
   protLink = "viewer.fcgi?db=protein&val="
   manLink = "http://manatee-int.jcvi.org/tigr-scripts/euk_manatee/shared/ORF_infopage.cgi?db=phytoplankton&orf="
   if (entry =~ /^gi[\_]*([0-9]*)/ || entry =~ /(^[A-Z|0-9]*)\|/)
     return ncbiLink + protLink + $1
   elsif (entry =~/jgi_[0-9]+.([0-9]+.[A-Z|a-z|0-9]+)/)
     return manLink+$1
   else
     return nil
   end
 end

# display Tree PDF
["/:db/:dataset/:seq/pdf", "/:db/:dataset/:seq/id_pdf"].each do |path|
  get path do |db, dataset, seq|
    @title = "APIS: Automated Phylogenetic Inference System: #{seq} Tree"
    @project_name = "APIS: Automated Phylogenetic Inference System"
    if (request.url =~/id_pdf/)
      raw = true
    else
      raw = false
    end
    pdf = ""
    settings.dbs[db].query("SELECT tree FROM tree WHERE dataset='#{dataset}' AND seq_name = '#{seq}'").each {|row|
      tree = NewickTree.new(row[0])
      pdf = tree.draw("--#{seq}", boot="width", linker = :phyLink, labelName = false,
      highlights = Hash.new, brackets = nil, rawNames = raw)
    }
    settings.dbs[db].close
    return [200, {"Content-Type" => "application/pdf"}, pdf]
  end
end

# display sequence
get "/:db/:dataset/:seq/seq" do |db, dataset, seq|
  @title = "APIS: Automated Phylogenetic Inference System: #{seq}"
  @project_name = "APIS: Automated Phylogenetic Inference System"
  @main_content = ""
  seqdata = ""
  ann = ""
  settings.dbs[db].query("SELECT sequence FROM sequence WHERE dataset='#{dataset}' AND seq_name = '#{seq}'").each {|row|
    seqdata = row[0]
  }
  settings.dbs[db].query("SELECT annotation FROM annotation WHERE dataset='#{dataset}' AND seq_name = '#{seq}'").each {|row|
    ann = row[0] if (!row[0].nil?)
  }
  s = Bio::Sequence::AA.new(seqdata).to_fasta(seq + " " + ann, 60)
  @main_content += s.gsub("\n","<BR>\n")
  settings.dbs[db].close
  haml :jcvi
end

# display alignment
get "/:db/:dataset/:seq/alignment" do |db, dataset, seq|
  @title = "APIS: Automated Phylogenetic Inference System: #{seq} alignment"
  @project_name = "APIS: Automated Phylogenetic Inference System"
  @main_content = "<pre>\n"
  settings.dbs[db].query("SELECT alignment_name, alignment_desc, alignment_sequence FROM alignment WHERE dataset='#{dataset}' AND seq_name = '#{seq}'").each {|row|
    name, desc, seq = row
    @main_content += Bio::Sequence::AA.new(seq).to_fasta(name + " " + desc, 60)
  }
  @main_content += "</pre>\n"
  settings.dbs[db].close
  haml :jcvi
end


# breakdown list
["/:db/:dataset", "/:db/:dataset/:level"].each do |path|
  get path do
    db, dataset, level = params["db"], params["dataset"], params["level"]
    @title = "APIS: Automated Phylogenetic Inference System: #{dataset}"
    @project_name = "APIS: Automated Phylogenetic Inference System"
    base = request.url.split("#{db}/#{dataset}").first
    level = "kingdom" if level.nil?
    if (params["seq"] || params["ann"])
      @main_content = search(db, dataset, params)
    else
      @main_content = "<FORM METHOD=get ACTION=\"#{base}#{db}/#{dataset}\">\n"
      @main_content +="<INPUT TYPE=text NAME=\"ann\">\n"
      @main_content += "Search for description</FORM>\n"
      @main_content += "<FORM METHOD=get ACTION=\"#{base}#{db}/#{dataset}\">\n"
      @main_content +="<INPUT TYPE=text NAME=\"seq\">\n"
      @main_content += "Search for ORF number</FORM>\n"
      @main_content += "<H1>#{level.capitalize} breakdown for #{dataset}</H1>\n"
      tot = settings.dbs[db].count("sequence WHERE dataset = '#{dataset}'")
      processed = settings.dbs[db].count("sequence WHERE dataset = '#{dataset}' AND processed = 1")
      counts = Hash.new
      total = 0
      query =  "SELECT #{level}, #{level}_outgroup, COUNT(*) FROM "
      query += "classification WHERE dataset ='#{dataset}' "
      query += "GROUP BY #{level}, #{level}_outgroup"
      settings.dbs[db].query(query).each {|row|
        taxon, outgroup, num = row
        outgroup = outgroup.to_i
        num = num.to_i
        total += num
        if (outgroup == 0)
          counts["Contained within " + taxon] = num
        else
          counts["Outgroup of " + taxon] = num
        end
      }
      @main_content += "<TABLE>\n<TR><TD>\n"
      @main_content += "#{processed} of #{tot} sequences analyzed (#{(processed*1000/tot)/10}%)<br>"
      @main_content += "#{total} of #{tot} sequences with trees (#{(total*1000/tot)/10}%)<br><br>"
      ["kingdom", "phylum", "class", "ord", "family", "genus", "species"].each {|tax|
        @main_content += "<A HREF=\"#{base}#{db}/#{dataset}/#{tax}\">#{tax}</a>\n"
      }
      @main_content += "<p>\n"
      percents = Hash.new
      counts.keys.sort {|x,y| counts[y] <=> counts[x]}.each {|key|
        percents[key] = counts[key]*100.0/total
        @main_content += sprintf("%7d (%3.1f%%)", counts[key], percents[key])
        @main_content += sprintf("<A HREF=\"%s%s/%s/%s/%s\">%s</a><br>\n",
                        base, db, dataset, level, key.gsub(" ","_"),  key)
      }
      @main_content += "</TD><TD VALIGN=\"top\">\n"
      @main_content += pie(percents)
      @main_content += "</TD></TR></TABLE>\n"
    end
    settings.dbs[db].close
    haml :jcvi
  end  
end

# details list
get  "/:db/:dataset/:level/:group" do |db, dataset, level, group|
  @main_content = "<H1>#{dataset}: #{group.gsub("_", " ")}</H1>\n"
  outgroup, prep, group = group.split("_", 3)
  group.gsub!("_", " ")
  if (outgroup == "Contained")
    outgroup = 0
  else
    outgroup = 1
  end
  query = "SELECT classification.seq_name, annotation FROM classification "
  query += "LEFT JOIN annotation ON classification.dataset = annotation.dataset "
  query += "AND classification.seq_name = annotation.seq_name WHERE "
  query += "classification.dataset='#{dataset}' AND #{level}='#{group}' "
  query += "AND #{level}_outgroup = #{outgroup} ORDER BY "
  query += "classification.seq_name"
  count = 0
  settings.dbs[db].query(query).each {|row|
    name, ann = row
    @main_content += seqLine(db, dataset, name, ann)
    count += 1
    break if count > 1000
  }
  settings.dbs[db].close
  haml :jcvi
end



