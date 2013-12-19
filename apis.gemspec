Gem::Specification.new do |s|
  s.required_ruby_version = '>= 1.9.3'
  s.name = %q{apis}
  s.version = "2.41"
  s.date = %q{2013-04-16}
  s.authors = ["Jonathan Badger"]
  s.email = %q{jhbadger@gmail.com}
  s.summary = %q{APIS is a system for creating and interpreting phylogenetic trees for all proteins in a genome or metagenomic sample.}
  s.description = %q{APIS is a system for creating and interpreting phylogenetic trees for all proteins in a genome or metagenomic sample.}
  s.homepage = %q{http://github.com/jhbadger/APIS}
  s.description = %q{}
  s.add_dependency("bio", ">= 1.4.3")
  s.add_dependency("googlecharts", ">= 1.6.8")
  s.add_dependency("newick-ruby", ">= 1.0.3")
  s.add_dependency("trollop", ">= 2.0")
  s.add_dependency("yajl-ruby", ">= 1.1.0")
  s.files = ["bin/apisPie", "bin/apisRun", "lib/SGE.rb", "lib/ZFile.rb", "lib/apis_lib.rb",
    "examples/test.m8plus.bz2", "examples/test.peps.bz2"]
  s.executables = ["apisRun", "apisPie", "apisTimeLogicBlast", "jsonQuery"]
end
