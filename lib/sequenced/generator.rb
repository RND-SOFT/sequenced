module Sequenced
  class Generator
    attr_reader :record, :scope, :column, :start_at, :skip, :update_if_not_last

    def initialize(record, options = {})
      @record = record
      @scope = options[:scope]
      @column = options[:column].to_sym
      @start_at = options[:start_at]
      @skip = options[:skip]
      @update_if_not_last = options[:update_if_not_last]
    end

    def set
      return unless need_to_update?
      lock_table
      record.send(:"#{column}=", next_id)
    end

    def id_set?
      !current_id.nil?
    end

    def skip?
      skip && skip.call(record)
    end

    def next_id
      next_id_in_sequence.tap do |id|
        id += 1 until unique?(id)
      end
    end

    def last_id
      l_r = find_last_record
      l_r.send(column) if l_r.present?
    end

    def next_id_in_sequence
      start_at = self.start_at.respond_to?(:call) ? self.start_at.call(record) : self.start_at
      return start_at unless last_record = find_last_record
      max(last_id + 1, start_at)
    end

    def unique?(id)
      build_scope(*scope) do
        rel = base_relation
        rel = rel.where("NOT id = ?", record.id) if record.persisted?
        rel.where(column => id)
      end.count == 0
    end

    def need_to_update?
      (update_if_not_last && last_id.to_i > current_id.to_i) || (!id_set? && !skip?)
    end

    def current_id
      record.send(column)
    end

  private

    def lock_table
      if postgresql?
        record.class.connection.execute("LOCK TABLE #{record.class.table_name} IN EXCLUSIVE MODE")
      end
    end

    def postgresql?
      defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) &&
        record.class.connection.instance_of?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
    end

    def base_relation
      record.class.base_class.unscoped
    end

    def find_last_record
      build_scope(*scope) do
        base_relation.
        where("#{column.to_s} IS NOT NULL").
        order("#{column.to_s} DESC")
      end.first
    end

    def build_scope(*columns)
      rel = yield
      columns.each { |c| rel = rel.where(c => record.send(c.to_sym)) }
      rel
    end

    def max(*values)
      values.to_a.max
    end

  end
end
