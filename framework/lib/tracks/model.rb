require 'sqlite3'

module Tracks
  class Model
    include Associations
    include Validations

    def self.table_name
      name.gsub(/([A-Z])/) { "_#{$1}" }.downcase.sub(/^_/, '') + "s"
    end

    def self.db
      @@db ||= begin
        db = SQLite3::Database.new(ENV["DATABASE_PATH"] || "db/development.sqlite3")
        db.results_as_hash = true
        db
      end
    end

    def self.columns
      @columns ||= db.execute("PRAGMA table_info(#{table_name})").map { |c| c["name"] }
    end

    # --- Querying ---

    def self.all
      db.execute("SELECT * FROM #{table_name}").map { |r| new(r) }
    end

    def self.find(id)
      row = db.execute("SELECT * FROM #{table_name} WHERE id = ? LIMIT 1", [id]).first
      raise "Not found: #{table_name} ##{id}" unless row
      new(row)
    end

    def self.find_by(conditions)
      clause = conditions.keys.map { |k| "#{k} = ?" }.join(" AND ")
      row = db.execute("SELECT * FROM #{table_name} WHERE #{clause} LIMIT 1", conditions.values).first
      row ? new(row) : nil
    end

    def self.where(conditions)
      clause = conditions.keys.map { |k| "#{k} = ?" }.join(" AND ")
      db.execute("SELECT * FROM #{table_name} WHERE #{clause}", conditions.values).map { |r| new(r) }
    end

    def self.count
      db.execute("SELECT COUNT(*) as c FROM #{table_name}").first["c"]
    end

    def self.create(attrs)
      obj = new(attrs)
      obj.save
      obj
    end

    # --- Instance ---

    def initialize(attrs = {})
      @attributes = {}
      attrs.each { |k, v| @attributes[k.to_s] = v }
      setup_accessors
    end

    def id
      @attributes["id"]
    end

    def new_record?
      @attributes["id"].nil?
    end

    def persisted?
      !new_record?
    end

    def [](key)
      @attributes[key.to_s]
    end

    def []=(key, val)
      @attributes[key.to_s] = val
    end

    def to_h
      @attributes.dup
    end

    private

    def setup_accessors
      self.class.columns.each do |col|
        define_singleton_method(col) { @attributes[col] }
        define_singleton_method("#{col}=") { |v| @attributes[col] = v }
      end
    end

    def insert
      cols  = @attributes.keys.reject { |k| k == "id" }
      vals  = cols.map { |k| @attributes[k] }
      ph    = cols.map { "?" }.join(", ")
      self.class.db.execute(
        "INSERT INTO #{self.class.table_name} (#{cols.join(', ')}) VALUES (#{ph})", vals
      )
      @attributes["id"] = self.class.db.last_insert_row_id
      setup_accessors
      true
    end

    def update
      cols = @attributes.keys.reject { |k| k == "id" }
      vals = cols.map { |k| @attributes[k] }
      set  = cols.map { |k| "#{k} = ?" }.join(", ")
      self.class.db.execute(
        "UPDATE #{self.class.table_name} SET #{set} WHERE id = ?", vals + [@attributes["id"]]
      )
      true
    end

    public

    def save
      return false unless valid?
      new_record? ? insert : update
    end

    def save!
      save || raise("Validation failed: #{errors.inspect}")
    end

    def destroy
      self.class.db.execute(
        "DELETE FROM #{self.class.table_name} WHERE id = ?", [@attributes["id"]]
      )
    end
  end
end
