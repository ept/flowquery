module Flowquery
  class Variable
    attr_reader :name, :definition, :references, :scope

    def initialize(name, scope)
      @name = name.to_s
      @definition = nil
      @references = []
      @scope = scope
    end

    def definition=(new_definition)
      raise ParseError, "duplicate variable #{name}" if definition
      @definition = new_definition
    end
  end


  class VariableBinding
    attr_reader :parent

    def initialize(parent=nil)
      @parent = parent
      @variables = {}
    end

    def [](name)
      name = name.to_s
      raise ParseError, "ambiguous variable name: #{name}" if @variables[name] && parent && parent[name]
      @variables[name] || parent && parent[name]
    end

    def define(name, node)
      name = name.to_s
      @variables[name] ||= Variable.new(name, self)
      @variables[name].tap{|var| var.definition = node }
    end

    def reference(name, node)
      if var = self[name]
        # The variable is already defined, so we can just reference it.
        var.references << node
        var
      elsif parent
        # This is an inner scope, but we want to create the reference in the global scope.
        parent.reference(name, node)
      else
        # This is already the global scope; create a reference without definition, and hopefully
        # we'll get to fill in the definition later.
        @variables[name.to_s] = Variable.new(name, self).tap{|var| var.references << node }
      end
    end

    def variables
      @variables.values
    end

    def undefined
      variables.select{|variable| variable.definition.nil? }
    end

    def global?
      parent.nil?
    end

    def record_context?
      false
    end
  end


  # Binding for scopes where the fields of a record are made available as local variables.
  # For example, in the 'where' clause of a 'select' statement, the columns of the table from
  # which we're selecting are made available.
  class RecordBinding < VariableBinding
    def initialize(parent, fields)
      super(parent)
      @variables = fields.each_with_object({}) do |(field_name, syntax_node), vars|
        vars[field_name] = Variable.new(field_name, self).tap{|var| var.definition = syntax_node }
      end
    end

    def define(name, node)
      raise 'cannot define new variables in a RecordBinding'
    end

    def record_context?
      true
    end
  end
end
