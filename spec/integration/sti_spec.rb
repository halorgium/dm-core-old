require 'pathname'
require Pathname(__FILE__).dirname.expand_path.parent + 'spec_helper'

if HAS_SQLITE3
  describe DataMapper::AutoMigrations, '.auto_migrate! on STI models with sqlite3' do
    before :all do
      @adapter = repository(:sqlite3).adapter

      @property_class = Struct.new(:name, :type, :nullable, :default, :serial)

      class Book
        include DataMapper::Resource

        property :id,       Serial
        property :title,    String,     :nullable => false
        property :isbn,     Integer,    :nullable => false
        property :class_type, Discriminator
      end

      class Propaganda < Book
        property :marxist,  Boolean,    :nullable => false, :default => false
      end

      class Fiction < Book
        property :series,   String
      end

      class ShortStory < Fiction
        property :moral,    String
      end

      class ScienceFiction < Fiction
        property :aliens, Boolean
      end

      class SpaceWestern < ScienceFiction
        property :cowboys, Boolean
      end
    end

    describe "with a parent class" do
      before :all do
        Book.auto_migrate!(:sqlite3).should be_true

        @table_set = @adapter.query('PRAGMA table_info("books")').inject({}) do |ts,column|
          default = if 'NULL' == column.dflt_value || column.dflt_value.nil?
            nil
          else
            /^(['"]?)(.*)\1$/.match(column.dflt_value)[2]
          end

          property = @property_class.new(
            column.name,
            column.type.upcase,
            column.notnull == 0,
            default,
            column.pk == 1  # in SQLite3 the serial key is also primary
          )

          ts.update(property.name => property)
        end

        @index_list = @adapter.query('PRAGMA index_list("books")')
      end

      it "should create the child class property columns" do
        @table_set.keys.should include("series", "marxist")
      end

      it "should create all property columns of the child classes in the inheritance tree" do
        @table_set.keys.should include("moral")
      end
    end

    describe "with a child class" do
      before :all do
        Propaganda.auto_migrate!(:sqlite3).should be_true

        @table_set = @adapter.query('PRAGMA table_info("books")').inject({}) do |ts,column|
          default = if 'NULL' == column.dflt_value || column.dflt_value.nil?
            nil
          else
            /^(['"]?)(.*)\1$/.match(column.dflt_value)[2]
          end

          property = @property_class.new(
            column.name,
            column.type.upcase,
            column.notnull == 0,
            default,
            column.pk == 1  # in SQLite3 the serial key is also primary
          )

          ts.update(property.name => property)
        end

        @index_list = @adapter.query('PRAGMA index_list("books")')
      end

      it "should create the parent class' property columns" do
        @table_set.keys.should include("id", "title", "isbn")
      end
    end

    describe "with a child class with it's own child class" do
      before :all do
        Fiction.auto_migrate!(:sqlite3).should be_true

        @table_set = @adapter.query('PRAGMA table_info("books")').inject({}) do |ts,column|
          default = if 'NULL' == column.dflt_value || column.dflt_value.nil?
            nil
          else
            /^(['"]?)(.*)\1$/.match(column.dflt_value)[2]
          end

          property = @property_class.new(
            column.name,
            column.type.upcase,
            column.notnull == 0,
            default,
            column.pk == 1  # in SQLite3 the serial key is also primary
          )

          ts.update(property.name => property)
        end

        @index_list = @adapter.query('PRAGMA index_list("books")')
      end

      it "should create the parent class' property columns" do
        @table_set.keys.should include("id", "title", "isbn")
      end

      it "should create the child class' property columns" do
        @table_set.keys.should include("moral")
      end
    end

    describe "with a nephew class" do
      before :all do
        ShortStory.auto_migrate!(:sqlite3).should be_true

        @table_set = @adapter.query('PRAGMA table_info("books")').inject({}) do |ts,column|
          default = if 'NULL' == column.dflt_value || column.dflt_value.nil?
            nil
          else
            /^(['"]?)(.*)\1$/.match(column.dflt_value)[2]
          end

          property = @property_class.new(
            column.name,
            column.type.upcase,
            column.notnull == 0,
            default,
            column.pk == 1  # in SQLite3 the serial key is also primary
          )

          ts.update(property.name => property)
        end
        @index_list = @adapter.query('PRAGMA index_list("books")')
      end


      it "should create the grandparent class' property columns" do
        @table_set.keys.should include("id", "title", "isbn")
      end

      it "should create the uncle class' property columns" do
        @table_set.keys.should include("marxist")
      end
    end

    describe "with a great-grandchild class" do
      it "should inherit its parent's properties" do
        SpaceWestern.properties[:aliens].should_not be_nil
      end
      it "should inherit its grandparent's properties" do
        SpaceWestern.properties[:series].should_not be_nil
      end
      it "should inherit its great-granparent's properties" do
        SpaceWestern.properties[:title].should_not be_nil
      end
    end
  end
end
