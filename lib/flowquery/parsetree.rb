module Flowquery
  class SyntaxNode < Treetop::Runtime::SyntaxNode
    attr_accessor :variable, :dependency_id

    def bind_variables(variable_binding)
      # Subclasses should override this
    end

    def track_dependencies(graph)
      # Subclasses should override this
    end

    def inspect
      "#<#{self.class.name}: #{self}>"
    end
  end


  class Identifier < SyntaxNode
    def to_s
      text_value
    end
  end


  class TableDefinition < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.define(defined_name, self)
    end

    def to_s
      "create table #{defined_name} (#{columns.map(&:to_s).join(', ')})"
    end
  end


  class ColumnDeclaration < SyntaxNode
    def to_s
      "#{name} #{type}"
    end
  end


  class FunctionDefinition < SyntaxNode
    def params
      param_list.respond_to?(:params) ? param_list.params : []
    end

    def bind_variables(variable_binding)
      self.variable = variable_binding.define(defined_name, self)
      inner_binding = VariableBinding.new(variable_binding)
      params.each{|param| param.bind_variables(inner_binding) }
      value.bind_variables(inner_binding)
    end

    def track_dependencies(graph)
      params.each{|param| param.track_dependencies(graph) }
      value.track_dependencies(graph)
      graph.add_vertex(self)
      graph.add_edge(value, self)
    end

    def signature
      "#{defined_name}(#{params.map(&:to_s).join(', ')})"
    end

    def to_s
      "#{signature} = #{value}"
    end

    def label
      defined_name
    end
  end


  class ParamDeclaration < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.define(name, self)
    end

    def track_dependencies(graph)
      graph.add_vertex(self)
    end

    def to_s
      "#{type} #{name}"
    end

    def label
      name
    end
  end


  class FunctionApplication < SyntaxNode
    def arguments
      argument_list.arguments
    end

    def bind_variables(variable_binding)
      self.variable = variable_binding.reference(name, self)
      arguments.each{|argument| argument.bind_variables(variable_binding) }
    end

    def track_dependencies(graph)
      arguments.each{|argument| argument.track_dependencies(graph) }
      graph.add_vertex(self, :function => variable.definition.label, :params => variable.definition.params.map(&:name))
      arguments.each_with_index do |argument, index|
        graph.add_edge(argument, self, :param_index => index)
      end
    end

    def to_s
      "#{name}(#{arguments.map(&:to_s).join(', ')})"
    end
  end


  class VariableReference < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.reference(name, self)
    end

    def track_dependencies(graph)
      if variable.scope.global?
        graph.add_vertex(self) # keep dependencies local to each function, to keep the graph acyclic
      elsif variable.scope.record_context?
        graph.add_vertex(self)
        graph.add_edge(variable.definition, self)
      else
        self.dependency_id = variable.definition.dependency_id or raise "untracked variable #{name}"
      end
    end

    def to_s
      name.to_s
    end
  end


  class EqualsOp < SyntaxNode
    def bind_variables(variable_binding)
      left.bind_variables(variable_binding)
      right.bind_variables(variable_binding)
    end

    def track_dependencies(graph)
      left.track_dependencies(graph)
      right.track_dependencies(graph)
      graph.add_vertex(self)
      graph.add_edge(left, self)
      graph.add_edge(right, self)
    end

    def to_s
      "#{left} = #{right}"
    end
  end


  class SelectStatement < SyntaxNode
    def bind_variables(variable_binding)
      table_name.bind_variables(variable_binding)

      # tables are bound before functions (regardless of their order in the source file), so if we
      # don't yet know a definition for the table at this point, it's definitely an error.
      unless table_name.variable.definition.respond_to? :columns
        raise SyntaxError, "undefined table: #{table_name}"
      end

      if predicate
        column_names = table_name.variable.definition.columns.map(&:name)
        inner_binding = RecordBinding.new(variable_binding, table_name, column_names)
        predicate.bind_variables(inner_binding)
      end
    end

    def track_dependencies(graph)
      table_name.track_dependencies(graph)
      if predicate
        predicate.track_dependencies(graph)
        graph.add_vertex(self, :function => 'filter', :params => ['source', 'predicate'])
        graph.add_edge(table_name, self, :param_index => 0)
        graph.add_edge(predicate, self, :param_index => 1)
      else
        self.dependency_id = table_name.dependency_id
      end
    end

    def to_s
      str = 'select '
      str << (columns.all? ? '*' : columns.column_names.map(&:to_s).join(', '))
      str << " from #{table_name}"
      str << " where #{predicate}" if predicate
      str
    end
  end


  class QueryFile < SyntaxNode
    def self.parse(query_file)
      parser = FlowqueryParser.new
      tree = parser.parse(query_file) or raise SyntaxError, parser.failure_reason
      raise SyntaxError, 'file is not a complete query' unless tree.is_a? QueryFile
      tree.variables
      tree.dependencies
      tree
    end

    def tables
      @tables ||= definitions.select{|definition| definition.is_a? TableDefinition }
    end

    def functions
      @functions ||= definitions.select{|definition| definition.is_a? FunctionDefinition }
    end

    def variables
      return @variables if @variables
      @variables = VariableBinding.new
      bind_variables(@variables)
      if !(undefined = @variables.undefined).empty?
        raise SyntaxError, "undefined variable: #{undefined.map(&:name).join(', ')}"
      end
      @variables
    end

    def dependencies
      return @dependencies if @dependencies
      @dependencies = DependencyGraph.new
      track_dependencies(@dependencies)
      @dependencies
    end

    def bind_variables(variable_binding)
      tables.each{|table| table.bind_variables(variable_binding) }
      functions.each{|function| function.bind_variables(variable_binding) }
    end

    def track_dependencies(graph)
      functions.each do |function|
        graph.next_function(function.signature)
        function.track_dependencies(graph)
      end
    end

    def to_s
      definitions.map(&:to_s).join('; ')
    end
  end
end
