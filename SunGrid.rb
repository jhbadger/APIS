# class to encapsulate running jobs on a Sun Grid Engine
class SunGrid
  attr :subdir
  def initialize(command, project = nil, memory = nil, queue = "default", dir = Dir.pwd + "/.tmp")
    @command = command
    @name = File.basename(@command).split(" ").first
    @project = project
    @dir = dir
    @subdir = dir + "/" + Time.now.to_i.to_s
    @memory = memory
    @queue = queue
    @count = 0
    if (!File.exists?(@dir))
      begin
        Dir.mkdir(@dir)
      rescue
        STDERR << "Cannot create needed tmp directory: " << @dir << "\n"
        exit(1)
      end
    end
    if (!File.exists?(@subdir))
      begin
        Dir.mkdir(@subdir)
      rescue
        STDERR << "Cannot create needed tmp directory: " << @subdir << "\n"
        exit(1)
      end
    end
  end
  
  # return name for next data file
  def next
    @count += 1
    filename = @subdir + "/" + @name + "_input." + @count.to_s
    return filename
  end
  
  # write job script to tmp dir
  def writeJob
    out = File.new(@subdir + "/" + @name + ".com", "w")
    out.printf("\#!/bin/bash\n")
    out.printf("\#$ -S /bin/bash\n")
    out.printf("\#$ -o %s/output.$TASK_ID.stdout\n", @subdir)
    out.printf("\#$ -e %s/output.$TASK_ID.stderr\n", @subdir)
    out.printf(". /etc/profile\n")
    out.printf("module add dot\n")
    out.printf("cd %s\n", @subdir)
    out.printf("%s %s_input.$SGE_TASK_ID\n", @command, @name)
    out.close
  end
  
  # remove stuff from tmp dir
  def cleanup
    Dir.foreach(@subdir).each do |file|
      next if file == "." || file == ".."
      File.unlink(@subdir + "/" +file)
    end
    Dir.rmdir(@subdir)
  end
  
  # submit array to grid
  def submit
    writeJob
    qsub = "qsub -t 1:" + @count.to_s
    qsub += " -P #{@project}" if @project
    qsub += " -l #{@memory}" if (@memory)
    qsub += " -l #{@queue}" if (@queue != "default")
    qsub += " #{@name}.com"
    p qsub
  end
end
