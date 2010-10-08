namespace :db do
  if not Rake::Task.task_defined?("db:drop")
    desc 'Drops all the keys in the curret Rails.env database'
    task :drop => :environment do
      Ohm.redis.flushdb
    end
  end

  if not Rake::Task.task_defined?("db:seed")
    # if another ORM has defined db:seed, don't run it twice.
    desc 'Load the seed data from db/seeds.rb'
    task :seed => :environment do
      seed_file = File.join(Rails.root, 'db', 'seeds.rb')
      load(seed_file) if File.exist?(seed_file)
    end
  end

  if not Rake::Task.task_defined?("db:reseed")
    desc 'Delete data and seed'
    task :reseed => [ 'db:drop', 'db:seed' ]
  end


  if not Rake::Task.task_defined?("db:size")
    desc 'Show db file stats'
    task :size  do
      size = Ohm.redis.dbsize
      print "Ohm #{Ohm.redis.client.host} dbsize -> "
      puts "#{size} b, %.2f mb." % (size/1e6)
    end
  end

  if not Rake::Task.task_defined?("db:stat")
    desc 'Show some db stats'
    task :stat do
      Ohm.redis.info.sort.each do |k, v|
        puts "#{k.capitalize} -> #{v}"
      end
    end
  end

  if not Rake::Task.task_defined?("db:monitor")
    desc 'Show some db stats'
    task :monitor => :environment do
      trap(:INT) { puts; exit }
      Ohm.redis.monitor do |op|
        puts op
      end
    end
  end

  #
  # For sql compatibility
  if not Rake::Task.task_defined?("db:create")
    task :create => :environment do
      # noop
    end
  end

  if not Rake::Task.task_defined?("db:migrate")
    task :migrate => :environment do
      # noop
    end
  end

  if not Rake::Task.task_defined?("db:schema:load")
    namespace :schema do
      task :load do
        # noop
      end
    end
  end

  if not Rake::Task.task_defined?("db:test:prepare")
    namespace :test do
      task :prepare do
        # noop
      end
    end
  end
end
#
# Ohmspecific
namespace :ohm do
  # gets a list of the ohm models defined in the app/models directory
  def get_ohm_models
    documents = []
    Dir.glob("app/models/**/*.rb").sort.each do |file|

      model_path = file[0..-4].split('/')[2..-1]
      begin
        klass = model_path.map(&:classify).join('::').constantize
        if klass.ancestors.include?(Ohm::Model)
          documents << klass
        end
      rescue => e
        # Just for non-ohm objects that dont have the embedded
        # attribute at the class level.
      end
    end
    documents
  end

  desc 'Summary of app models'
  task :models => :environment do
    puts "Model            |  Count  "
    puts "---------------------------"
    rs = 16
    get_ohm_models.each do |m|
      name = m.to_s[0..rs-2]
      name += (" " * (rs - name.length)) + " | "
      puts "#{name} #{m.all.size}"
    end
  end
end


