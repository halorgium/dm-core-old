#!/usr/bin/env ruby

require 'pathname'
require 'rubygems'
require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/contrib/rubyforgepublisher'
require 'spec/rake/spectask'

CLEAN.include '{coverage,doc,log}/', 'profile_results.txt'

ROOT = Pathname(__FILE__).dirname.expand_path

Pathname.glob(ROOT + 'tasks/**/*.rb') { |t| require t }

task :default => 'dm:spec'
task :spec    => 'dm:spec'

namespace :spec do
  task :unit        => 'dm:spec:unit'
  task :integration => 'dm:spec:integration'
end

desc 'Remove all package, docs and spec products'
task :clobber_all => %w[ clobber_package dm:clobber_spec ]

namespace :dm do
  def run_spec(name, files, rcov = true)
    Spec::Rake::SpecTask.new(name) do |t|
      t.spec_opts << '--format' << 'specdoc' << '--colour'
      t.spec_opts << '--loadby' << 'random'
      t.spec_files = Pathname.glob(ENV['FILES'] || files)
      t.rcov = ENV.has_key?('NO_RCOV') ? ENV['NO_RCOV'] != 'true' : rcov
      t.rcov_opts << '--exclude' << 'spec,environment.rb'
      t.rcov_opts << '--text-summary'
      t.rcov_opts << '--sort' << 'coverage' << '--sort-reverse'
      t.rcov_opts << '--only-uncovered'
    end
  end

  desc "Run all specifications"
  run_spec('spec', ROOT + 'spec/**/*_spec.rb')

  namespace :spec do
    desc "Run unit specifications"
    run_spec('unit', ROOT + 'spec/unit/**/*_spec.rb')

    desc "Run integration specifications"
    run_spec('integration', ROOT + 'spec/integration/**/*_spec.rb', false)
  end

  desc "Run comparison with ActiveRecord"
  task :perf do
    load Pathname.glob(ROOT + 'script/performance.rb')
  end

  desc "Profile DataMapper"
  task :profile do
    load Pathname.glob(ROOT + 'script/profile.rb')
  end
end

PACKAGE_VERSION = '0.9.1'

PACKAGE_FILES = [
  'README',
  'FAQ',
  'QUICKLINKS',
  'CHANGELOG',
  'MIT-LICENSE',
  '*.rb',
  'lib/**/*.rb',
  'spec/**/*.{rb,yaml}',
  'tasks/**/*',
  'plugins/**/*'
].collect { |pattern| Pathname.glob(pattern) }.flatten.reject { |path| path.to_s =~ /(\/db|Makefile|\.bundle|\.log|\.o)\z/ }

DOCUMENTED_FILES = PACKAGE_FILES.reject do |path|
  path.directory? || path.to_s.match(/(?:^spec|\/spec|\/swig\_)/)
end

PROJECT = "dm-core"

desc 'List all package files'
task :ls do
  puts PACKAGE_FILES
end

desc "Generate documentation"
task :doc do
  begin
    gem 'yard', '>=0.2.1'
    require 'yard'
    exec 'yardoc'
    # TODO: options to port over
    #  rdoc.title = "DataMapper -- An Object/Relational Mapper for Ruby"
    #  rdoc.options << '--line-numbers' << '--inline-source' << '--main' << 'README'
    #  rdoc.rdoc_files.include(*DOCUMENTED_FILES.map { |file| file.to_s })
  rescue Exception => e
    puts 'You will need to install the latest version of Yard to generate the
          documentation for dm-core.'
  end
end

gem_spec = Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = PROJECT
  s.summary = "An Object/Relational Mapper for Ruby"
  s.description = "Faster, Better, Simpler."
  s.version = PACKAGE_VERSION

  s.authors = "Sam Smoot"
  s.email = "ssmoot@gmail.com"
  s.rubyforge_project = PROJECT
  s.homepage = "http://datamapper.org"

  s.files = PACKAGE_FILES.map { |f| f.to_s }

  s.require_path = "lib"
  s.requirements << "none"
  s.add_dependency("data_objects", "=#{s.version}")
  s.add_dependency("english", ">=0.2.0")
  s.add_dependency("rspec", ">=1.1.3")
  s.add_dependency("addressable", ">=1.0.4")
  s.add_dependency("extlib", ">= 0.1")

  s.has_rdoc    = false
  #s.rdoc_options << "--line-numbers" << "--inline-source" << "--main" << "README"
  #s.extra_rdoc_files = DOCUMENTED_FILES.map { |f| f.to_s }
end

Rake::GemPackageTask.new(gem_spec) do |p|
  p.gem_spec = gem_spec
  p.need_tar = true
  p.need_zip = true
end

desc "Publish to RubyForge"
task :rubyforge => [ :doc, :gem ] do
  Rake::SshDirPublisher.new("#{ENV['RUBYFORGE_USER']}@rubyforge.org", "/var/www/gforge-projects/#{PROJECT}", 'doc').upload
end

WINDOWS = (RUBY_PLATFORM =~ /win32|mingw|bccwin|cygwin/) rescue nil
SUDO    = WINDOWS ? '' : ('sudo' unless ENV['SUDOLESS'])

desc "Install #{PROJECT}"
task :install => :package do
  sh %{#{SUDO} gem install --local pkg/#{PROJECT}-#{PACKAGE_VERSION} --no-update-sources}
end

if WINDOWS
  namespace :dev do
    desc 'Install for development (for windows)'
    task :winstall => :gem do
      system %{gem install --no-rdoc --no-ri -l pkg/#{PROJECT}-#{PACKAGE_VERSION}.gem}
    end
  end
end

task 'ci:doc' => :doc

namespace :ci do

  task :prepare do
    rm_rf ROOT + "ci"
    mkdir_p ROOT + "ci"
    mkdir_p ROOT + "ci/doc"
    mkdir_p ROOT + "ci/cyclomatic"
    mkdir_p ROOT + "ci/token"
  end

  Spec::Rake::SpecTask.new("spec:unit" => :prepare) do |t|
    t.spec_opts = ["--format", "specdoc", "--format", "html:#{ROOT}/ci/unit_rspec_report.html", "--diff"]
    t.spec_files = Pathname.glob(ROOT + "spec/unit/**/*_spec.rb")
    unless ENV['NO_RCOV']
      t.rcov = true
      t.rcov_opts << '--exclude' << "spec,gems"
      t.rcov_opts << '--text-summary'
      t.rcov_opts << '--sort' << 'coverage' << '--sort-reverse'
      t.rcov_opts << '--only-uncovered'
    end
  end

  Spec::Rake::SpecTask.new("spec:integration" => :prepare) do |t|
    t.spec_opts = ["--format", "specdoc", "--format", "html:#{ROOT}/ci/integration_rspec_report.html", "--diff"]
    t.spec_files = Pathname.glob(ROOT + "spec/integration/**/*_spec.rb")
    unless ENV['NO_RCOV']
      t.rcov = true
      t.rcov_opts << '--exclude' << "spec,gems"
      t.rcov_opts << '--text-summary'
      t.rcov_opts << '--sort' << 'coverage' << '--sort-reverse'
      t.rcov_opts << '--only-uncovered'
    end
  end

  task :spec do
    Rake::Task["ci:spec:unit"].invoke
    mv ROOT + "coverage", ROOT + "ci/unit_coverage"

    Rake::Task["ci:spec:integration"].invoke
    mv ROOT + "coverage", ROOT + "ci/integration_coverage"
  end

  task :saikuro => :prepare do
    system "saikuro -c -i lib -y 0 -w 10 -e 15 -o ci/cyclomatic"
    mv 'ci/cyclomatic/index_cyclo.html', 'ci/cyclomatic/index.html'

    system "saikuro -t -i lib -y 0 -w 20 -e 30 -o ci/token"
    mv 'ci/token/index_token.html', 'ci/token/index.html'
  end

  task :publish do
    out = ENV['CC_BUILD_ARTIFACTS'] || "out"
    mkdir_p out unless File.directory? out

    mv "ci/unit_rspec_report.html", "#{out}/unit_rspec_report.html"
    mv "ci/unit_coverage", "#{out}/unit_coverage"
    mv "ci/integration_rspec_report.html", "#{out}/integration_rspec_report.html"
    mv "ci/integration_coverage", "#{out}/integration_coverage"
    mv "ci/doc", "#{out}/doc"
    mv "ci/cyclomatic", "#{out}/cyclomatic_complexity"
    mv "ci/token", "#{out}/token_complexity"
  end
end

#task :ci => %w[ ci:spec ci:doc ci:saikuro install ci:publish ]  # yard-related tasks do not work yet
task :ci => %w[ ci:spec ci:saikuro install ]
