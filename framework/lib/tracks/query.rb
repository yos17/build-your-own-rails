module Tracks
  class Query
    include Enumerable

    def initialize(model_class)
      @model      = model_class
      @conditions = []
      @values     = []
      @order      = nil
      @limit      = nil
    end

    def where(conditions)
      conditions.each { |k, v| @conditions << "#{k} = ?"; @values << v }
      self
    end

    def order(clause)
      @order = clause; self
    end

    def limit(n)
      @limit = n; self
    end

    def to_sql
      sql = "SELECT * FROM #{@model.table_name}"
      sql += " WHERE #{@conditions.join(' AND ')}" unless @conditions.empty?
      sql += " ORDER BY #{@order}" if @order
      sql += " LIMIT #{@limit}"   if @limit
      sql
    end

    def to_a
      @model.db.execute(to_sql, @values).map { |r| @model.new(r) }
    end

    def each(&block)
      to_a.each(&block)
    end

    def first
      limit(1).to_a.first
    end

    def count
      sql = "SELECT COUNT(*) as c FROM #{@model.table_name}"
      sql += " WHERE #{@conditions.join(' AND ')}" unless @conditions.empty?
      @model.db.execute(sql, @values).first["c"]
    end
  end
end
