# class to encapsulate running jobs on a Sun Grid Engine
class SunGrid
  attr_accessor :name
  
  def initialize(command, project = nil, memory = nil, queue = nil)
    @command = [command].flatten
    @name = @command.first.gsub("/","_").split(" ").first
    @project = project
    @memory = memory
    @queue = queue
    @count = 0
  end
  
  # return name for next data file
  def next
    @count += 1
    filename = @name + "_input." + @count.to_s
    return filename
  end
  
  # write job script
  def writeJob
    out = File.new(@name + ".com", "w")
    out.printf("\#!/bin/sh\n")
    out.printf("\#$ -t 1-%d\n", @count)
    out.printf("cd %s\n",Dir.pwd)
    if (@command[1])
      out.printf("%s %s_input.$SGE_TASK_ID | %s\n", @command.first, 
      @name, @command[1])
    else
      out.printf("%s %s_input.$SGE_TASK_ID\n", @command.first, @name)
    end
    out.close
    File.chmod(0777, @name + ".com")
  end
  
  # submit array to grid
  def submit(sync = false)
    writeJob
    qsub = "qsub -t 1:" + @count.to_s
    qsub += " -sync yes" if (sync)
    qsub += " -P #{@project}" if @project
    qsub +=  " -l memory=#{@memory}" if (@memory)
    #qsub += " -l queue=#{@queue}" if (@queue && @queue != "default")
    qsub += " -o #{Dir.pwd} "
    qsub += " -e #{Dir.pwd} "
    qsub += " #{Dir.pwd}/#{@name}.com"
    system(qsub)
  end

  # concatenate output, error, removing input files
  def cleanup
    Dir.glob(@name + "_input*").each do |file|
      File.unlink(file)
    end
    out = File.new(@name + ".out", "w")
    Dir.glob(@name + ".com.o*").each do |file|
      File.new(file).each do |line|
        out.print line
      end
      File.unlink(file)
    end
    out.close
    err = File.new(@name + ".err", "w")
    Dir.glob(@name + ".com.e*").each do |file|
      File.new(file).each do |line|
        err.print line
      end
      File.unlink(file)
    end
    err.close
    File.unlink(@name + ".com")
  end
end
