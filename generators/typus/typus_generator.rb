class TypusGenerator < Rails::Generator::Base

  def manifest

    record do |m|

      ##
      # Default name for our application.
      #

      application = Rails.root.basename

      ##
      # To create <tt>application.yml</tt> and <tt>application_roles.yml</tt> detect 
      # available AR models on the application.
      #

      models = Dir["app/models/*.rb"].collect { |x| File.basename(x).sub(/\.rb$/,'').camelize }
      ar_models = []

      models.each do |model|
        begin
          klass = model.constantize
          active_record_model = klass.superclass.equal?(ActiveRecord::Base) && !klass.abstract_class?
          active_record_model_with_sti = klass.superclass.superclass.equal?(ActiveRecord::Base)
          ar_models << klass if active_record_model || active_record_model_with_sti
        rescue Exception => error
          puts "=> [typus] #{error.message} on '#{class_name}'."
        end
      end

      ##
      # Configuration files
      #

      config_folder = Typus::Configuration.options[:config_folder]
      folder = "#{Rails.root}/#{config_folder}"
      Dir.mkdir(folder) unless File.directory?(folder)

      configuration = { :base => '', :roles => '' }

      ar_models.sort{ |x,y| x.class_name <=> y.class_name }.each do |model|

        # Detect all relationships except polymorphic belongs_to using reflection.
        relationships = [ :belongs_to, :has_and_belongs_to_many, :has_many, :has_one ].map do |relationship|
                          model.reflect_on_all_associations(relationship).reject { |i| i.options[:polymorphic] }.map { |i| i.name.to_s }
                        end.flatten.sort

        # Remove foreign key and polymorphic type attributes
        reject_columns = []
        model.reflect_on_all_associations(:belongs_to).each do |i|
          reject_columns << model.columns_hash[i.name.to_s + '_id']
          reject_columns << model.columns_hash[i.name.to_s + '_type'] if i.options[:polymorphic]
        end

        model_columns = model.columns - reject_columns

        # Don't show `text` fields and timestamps in lists.
        list = model_columns.reject { |c| c.sql_type == 'text' || %w( created_at updated_at ).include?(c.name) }.map(&:name)

        # Don't show timestamps in forms.
        form = model_columns.reject { |c| %w( id created_at updated_at ).include?(c.name) }.map(&:name)

        # Show all model columns in the show action.
        show = model_columns.map(&:name)

        # We want attributes of belongs_to relationships to be shown in our 
        # field collections if those are not polymorphic.
        [ list, form, show ].each do |fields|
          fields << model.reflect_on_all_associations(:belongs_to).reject { |i| i.options[:polymorphic] }.map { |i| i.name.to_s }
          fields.flatten!
        end

        configuration[:base] << <<-RAW
#{model}:
  fields:
    list: #{list.join(', ')}
    form: #{form.join(', ')}
    show: #{show.join(', ')}
  actions:
    index:
    edit:
  order_by:
  relationships: #{relationships.join(', ')}
  filters:
  search:
  application: #{application}
  description:

        RAW

        configuration[:roles] << <<-RAW
  #{model}: create, read, update, delete
        RAW

      end

      Dir["#{Typus.path}/generators/typus/templates/config/typus/*"].each do |f|
        base = File.basename(f)
        m.template "config/typus/#{base}", "#{config_folder}/#{base}", 
                   :assigns => { :configuration => configuration }
      end

      ##
      # Initializers
      #

      m.template 'config/initializers/typus.rb', 'config/initializers/typus.rb', 
                 :assigns => { :application => application }

      ##
      # Public folders
      #

      [ "#{Rails.root}/public/stylesheets/admin", 
        "#{Rails.root}/public/javascripts/admin", 
        "#{Rails.root}/public/images/admin" ].each do |folder|
        Dir.mkdir(folder) unless File.directory?(folder)
      end

      m.file 'public/stylesheets/admin/screen.css', 'public/stylesheets/admin/screen.css'
      m.file 'public/stylesheets/admin/reset.css', 'public/stylesheets/admin/reset.css'
      m.file 'public/javascripts/admin/application.js', 'public/javascripts/admin/application.js'

      Dir["#{Typus.path}/generators/typus/templates/public/images/admin/*"].each do |f|
        base = File.basename(f)
        m.file "public/images/admin/#{base}", "public/images/admin/#{base}"
      end

      ##
      # Migration file
      #

      m.migration_template 'db/create_typus_users.rb', 'db/migrate', 
                            { :migration_file_name => 'create_typus_users' }

    end

  end

end