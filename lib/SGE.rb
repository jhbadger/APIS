# class to encapsulate running array jobs on a SGE grid architecture
class SGE
   def initialize(command, project, memory, queue, name)
      @command = [command].flatten
      @name = @command.first.gsub("/","_").split(" ").first
      @project = project
      @memory = memory
      @queue = queue
      @name = name
      @count = 0
      @files = []
   end

   # return name for next data file
   def next
      @count += 1
      filename = @name + "." + @count.to_s
      @files.push(filename)
      filename
   end

   # write job script
   def writeJob
      out = File.new(File.basename(@name) + ".com", "w")
      out.printf("\#!/bin/sh\n")
      out.printf("cd %s\n",Dir.pwd)
      if (@command[1])
         out.printf("%s %s.$SGE_TASK_ID | %s\n", @command.first,
         @name, @command[1])
      else
         out.printf("%s %s.$SGE_TASK_ID\n", @command.first, @name)
      end
      out.close
      File.chmod(0777, File.basename(@name) + ".com")
   end

   # submit array to grid
   def submit(sync = false, out = "/dev/null", err = "/dev/null")
      writeJob
      qsub = "qsub -t 1:" + @count.to_s
      qsub += " -sync yes" if sync
      qsub += " -P #{@project}" if @project
      qsub +=  " -l memory=#{@memory}" if @memory
      qsub += " -o #{out} "
      qsub += " -e #{err} "
      qsub += " #{Dir.getwd}/#{File.basename(@name)}.com"
      system(qsub)
   end

   # join output files matching specified array names, stderr, stdout
   def join(fileendings)
      ofiles = Hash.new
      fileendings.each do |ending|
         ofiles[ending] = File.new(File.basename(@name) + "_" + ending, "a")
      end
      @files.each do |file|
         fileendings.each do |ending|
            if File.exist?(file + "_" + ending)
               File.new(file + "_" + ending).each do |line|
                  ofiles[ending].print line
               end
               File.unlink(file + "_" + ending)
            end
         end
      end
      ofiles.keys.each do |key|
         ofiles[key].close
      end
      File.unlink(File.basename(@name) + ".com") if File.exists?(File.basename(@name) + ".com")
   end
end
