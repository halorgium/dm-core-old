module DataMapper
  module Model
    ##
    #
    # Extends the model with this module after DataMapper::Resource has been
    # included.
    #
    # This is a useful way to extend DataMapper::Model while
    # still retaining a self.extended method.
    #
    # @param [Module] extensions the module that is to be extend the model after
    #   after DataMapper::Model
    #
    # @return [TrueClass, FalseClass] whether or not the inclusions have been
    #   successfully appended to the list
    #-
    # @api public
    #
    # TODO: Move this do DataMapper::Model when DataMapper::Model is created
    def self.append_extensions(*extensions)
      extra_extensions.concat extensions
      true
    end
    
    def self.extra_extensions
      @extra_extensions ||= []
    end
    
    def self.extended(model)
      model.instance_variable_set(:@storage_names, Hash.new { |h,k| h[k] = repository(k).adapter.resource_naming_convention.call(model.instance_eval { default_storage_name }) })
      model.instance_variable_set(:@properties,    Hash.new { |h,k| h[k] = k == Repository.default_name ? PropertySet.new : h[Repository.default_name].dup })
      extra_extensions.each { |extension| model.extend(extension) }
    end

    def inherited(target)
      target.instance_variable_set(:@storage_names, @storage_names.dup)
      target.instance_variable_set(:@properties, Hash.new { |h,k| h[k] = k == Repository.default_name ? self.properties(Repository.default_name).dup(target) : h[Repository.default_name].dup })

      if @relationships
        duped_relationships = {}; @relationships.each_pair{ |repos, rels| duped_relationships[repos] = rels.dup}
        target.instance_variable_set(:@relationships, duped_relationships)
      end
    end

    def self.new(storage_name, &block)
      model = Class.new
      model.send(:include, Resource)
      model.class_eval <<-EOS, __FILE__, __LINE__
        def self.default_storage_name
          #{Extlib::Inflection.classify(storage_name).inspect}
        end
      EOS
      model.instance_eval(&block) if block_given?
      model
    end

    ##
    # Get the repository with a given name, or the default one for the current
    # context, or the default one for this class.
    #
    # @param name<Symbol>   the name of the repository wanted
    # @param block<Block>   block to execute with the fetched repository as parameter
    #
    # @return <Object, DataMapper::Respository> whatever the block returns,
    #   if given a block, otherwise the requested repository.
    #-
    # @api public
    def repository(name = nil, &block)
      #
      # There has been a couple of different strategies here, but me (zond) and dkubb are at least
      # united in the concept of explicitness over implicitness. That is - the explicit wish of the
      # caller (+name+) should be given more priority than the implicit wish of the caller (Repository.context.last).
      #
      DataMapper.repository(*Array(name || (Repository.context.last ? nil : default_repository_name)), &block)
    end

    ##
    # the name of the storage recepticle for this resource.  IE. table name, for database stores
    #
    # @return <String> the storage name (IE table name, for database stores) associated with this resource in the given repository
    def storage_name(repository_name = default_repository_name)
      @storage_names[repository_name]
    end

    ##
    # the names of the storage recepticles for this resource across all repositories
    #
    # @return <Hash(Symbol => String)> All available names of storage recepticles
    def storage_names
      @storage_names
    end

    ##
    # defines a property on the resource
    #
    # @param <Symbol> name the name for which to call this property
    # @param <Type> type the type to define this property ass
    # @param <Hash(Symbol => String)> options a hash of available options
    # @see DataMapper::Property
    def property(name, type, options = {})
      property = Property.new(self, name, type, options)

      create_property_getter(property)
      create_property_setter(property)

      @properties[repository.name] << property

      # Add property to the other mappings as well if this is for the default
      # repository.
      if repository.name == default_repository_name
        @properties.each_pair do |repository_name, properties|
          next if repository_name == default_repository_name
          properties << property
        end
      end

      # Add the property to the lazy_loads set for this resources repository
      # only.
      # TODO Is this right or should we add the lazy contexts to all
      # repositories?
      if property.lazy?
        context = options.fetch(:lazy, :default)
        context = :default if context == true

        Array(context).each do |item|
          @properties[repository.name].lazy_context(item) << name
        end
      end

      property
    end

    # TODO: make this a Set?
    def repositories
      [ repository ] + @properties.keys.collect { |repository_name| DataMapper.repository(repository_name) }
    end

    def properties(repository_name = default_repository_name)
      @properties[repository_name]
    end

    def properties_with_subclasses(repository_name = default_repository_name)
      #return properties if we're not interested in sti
     if @properties[repository_name].inheritance_property.nil?
       @properties[repository_name]
     else
        props = @properties[repository_name].dup
        self.child_classes.each do |subclass|
          subclass.properties(repository_name).each do |subprop|
            props << subprop if not props.any? { |prop| prop.name == subprop.name }
          end
        end
        props
      end
    end

    def key(repository_name = default_repository_name)
      @properties[repository_name].key
    end

    def inheritance_property(repository_name = default_repository_name)
      @properties[repository_name].inheritance_property
    end

    def default_order
      @default_order ||= key.map { |property| Query::Direction.new(property) }
    end

    def get(*key)
      repository.identity_map(self).get(key) || first(to_query(repository, key))
    end

    def get!(*key)
      get(*key) || raise(ObjectNotFoundError, "Could not find #{self.name} with key #{key.inspect}")
    end

    def all(query = {})
      query = scoped_query(query)
      query.repository.read_many(query)
    end

    def first(*args)
      query = args.last.respond_to?(:merge) ? args.pop : {}
      query = scoped_query(query.merge(:limit => args.first || 1))

      if args.any?
        query.repository.read_many(query)
      else
        query.repository.read_one(query)
      end
    end

    def [](*key)
      warn("#{name}[] is deprecated. Use #{name}.get! instead.")
      get!(*key)
    end

    def first_or_create(query, attributes = {})
      first(query) || begin
        resource = allocate
        query = query.dup

        properties(repository.name).key.each do |property|
          if value = query.delete(property.name)
            resource.send("#{property.name}=", value)
          end
        end

        resource.attributes = query.merge(attributes)
        resource.save
        resource
      end
    end

    ##
    # Create an instance of Resource with the given attributes
    #
    # @param <Hash(Symbol => Object)> attributes hash of attributes to set
    def create(attributes = {})
      resource = new(attributes)
      resource.save
      resource
    end

    ##
    # Dangerous version of #create.  Raises if there is a failure
    #
    # @see DataMapper::Resource#create
    # @param <Hash(Symbol => Object)> attributes hash of attributes to set
    # @raise <PersistenceError> The resource could not be saved
    def create!(attributes = {})
      resource = create(attributes)
      raise PersistenceError, "Resource not saved: :new_record => #{resource.new_record?}, :dirty_attributes => #{resource.dirty_attributes.inspect}" if resource.new_record?
      resource
    end

    # TODO SPEC
    def copy(source, destination, query = {})
      repository(destination) do
        repository(source).read_many(query).each do |resource|
          self.create(resource)
        end
      end
    end

    # @api private
    # TODO: spec this
    def load(values, query)
      repository = query.repository
      model      = self

      if inheritance_property_index = query.inheritance_property_index(repository)
        model = values.at(inheritance_property_index) || model
      end

      if key_property_indexes = query.key_property_indexes(repository)
        key_values   = values.values_at(*key_property_indexes)
        identity_map = repository.identity_map(model)

        if resource = identity_map.get(key_values)
          return resource unless query.reload?
        else
          resource = model.allocate
          resource.instance_variable_set(:@repository, repository)
          identity_map.set(key_values, resource)
        end
      else
        resource = model.allocate
        resource.readonly!
      end

      resource.instance_variable_set(:@new_record, false)

      query.fields.zip(values) do |property,value|
        value = property.custom? ? property.type.load(value, property) : property.typecast(value)
        property.set!(resource, value)

        if track = property.track
          case track
            when :hash
              resource.original_values[property.name] = value.dup.hash unless resource.original_values.has_key?(property.name) rescue value.hash
            when :load
               resource.original_values[property.name] = value unless resource.original_values.has_key?(property.name)
          end
        end
      end

      resource
    end

    # TODO: spec this
    def to_query(repository, key, query = {})
      conditions = Hash[ *self.key(repository.name).zip(key).flatten ]
      Query.new(repository, self, query.merge(conditions))
    end

    private

    def default_storage_name
      self.name
    end

    def default_repository_name
      Repository.default_name
    end

    def scoped_query(query = self.query)
      assert_kind_of 'query', query, Query, Hash

      return self.query if query == self.query

      query = if query.kind_of?(Hash)
        Query.new(query.has_key?(:repository) ? query.delete(:repository) : self.repository, self, query)
      else
        query
      end

      self.query ? self.query.merge(query) : query
    end

    # defines the getter for the property
    def create_property_getter(property)
      class_eval <<-EOS, __FILE__, __LINE__
        #{property.reader_visibility}
        def #{property.getter}
          attribute_get(#{property.name.inspect})
        end
      EOS

      if property.primitive == TrueClass && !property.model.instance_methods.include?(property.name.to_s)
        class_eval <<-EOS, __FILE__, __LINE__
          #{property.reader_visibility}
          alias #{property.name} #{property.getter}
        EOS
      end
    end

    # defines the setter for the property
    def create_property_setter(property)
      unless instance_methods.include?(property.name.to_s + '=')
        class_eval <<-EOS, __FILE__, __LINE__
          def #{property.name}=(value)
            attribute_set(#{property.name.inspect}, value)
          end
          #{property.writer_visibility} :#{property.name}
        EOS
      end
    end

    def relationships(*args)
      # DO NOT REMOVE!
      # method_missing depends on these existing. Without this stub,
      # a missing module can cause misleading recursive errors.
      raise NotImplementedError.new
    end
    
    def method_missing(method, *args, &block)      
      if relationship = self.relationships(repository.name)[method]
        klass = self == relationship.child_model ? relationship.parent_model : relationship.child_model
        return DataMapper::Query::Path.new(repository, [ relationship ], klass)
      end

      if property = properties(repository.name)[method]
        return property
      end

      super
    end

    # TODO: move to dm-more/dm-transactions
    module Transaction
      #
      # Produce a new Transaction for this Resource class
      #
      # @return <DataMapper::Adapters::Transaction
      #   a new DataMapper::Adapters::Transaction with all DataMapper::Repositories
      #   of the class of this DataMapper::Resource added.
      #-
      # @api public
      #
      # TODO: move to dm-more/dm-transactions
      def transaction(&block)
        DataMapper::Transaction.new(self, &block)
      end
    end # module Transaction

    include Transaction

    # TODO: move to dm-more/dm-migrations
    module Migration
      # TODO: move to dm-more/dm-migrations
      def storage_exists?(repository_name = default_repository_name)
        repository(repository_name).storage_exists?(storage_name(repository_name))
      end
    end # module Migration

    include Migration
  end # module Model
end # module DataMapper
