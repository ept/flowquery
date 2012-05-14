module Flowquery
  class SyntaxNode < Treetop::Runtime::SyntaxNode
    attr_accessor :variable, :dependency_id, :string_representation

    def bind_variables(variable_binding)
      # Subclasses should override this
    end

    def track_dependencies(graph)
      # Subclasses should override this
    end

    def to_s
      string_representation || super
    end

    def inspect
      "#<#{self.class.name}: #{to_s}>"
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
      column_names = Set.new
      columns.each do |column|
        raise ParseError, "duplicate column: #{column.name}" if column_names.include? column.name.to_s
        column_names << column.name.to_s
      end
    end

    def track_dependencies(graph)
      columns.each{|column| column.track_dependencies(graph) }
    end

    def signature
      "#{defined_name}(#{columns.map(&:name).join(', ')})"
    end

    def to_s
      "create table #{defined_name} (#{columns.map(&:to_s).join(', ')})"
    end
  end


  class ColumnDeclaration < SyntaxNode
    def track_dependencies(graph)
      graph.add_vertex(self)
    end

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
      name.to_s
    end
  end


  class ParenExpression < SyntaxNode
    def bind_variables(variable_binding)
      expression.bind_variables(variable_binding)
    end

    def track_dependencies(graph)
      expression.track_dependencies(graph)
      self.dependency_id = expression.dependency_id
    end

    def to_s
      "(#{expression})"
    end
  end


  # Syntax node for the place where a function is applied to one or more sets of arguments.
  # Example: f (a) (b, c)
  # Where f is a function that takes one argument (a), and returns another function that takes
  # two arguments (b and c). f isn't necessarily just an identifier; it could be a more
  # complicated expression (the "head expression"), but we don't need to worry about that here.
  #
  # In this implementation we attach the dependency graph vertices for each subsequent function
  # application to the respective argument lists. The vertex for the entire expression is then the
  # same as the vertex of the last argument list (because function application is left to right).
  class FunctionApplication < SyntaxNode
    def bind_variables(variable_binding)
      head.bind_variables(variable_binding)
      string_representation = head.to_s

      argument_lists.each do |argument_list|
        argument_list.arguments.each{|argument| argument.bind_variables(variable_binding) }
        string_representation += "(#{argument_list.arguments.map(&:to_s).join(', ')})"
        argument_list.string_representation = string_representation
      end
    end

    def track_dependencies(graph)
      head.track_dependencies(graph)
      previous_result = head

      # If there are several chained function applications, they are evaluated left to right
      # (function application is left-associative).
      argument_lists.each do |argument_list|
        arguments = argument_list.arguments
        arguments.each{|argument| argument.track_dependencies(graph) }

        # Add a dependency graph vertex for the function application. If the function definition is
        # already known, we can copy the declared parameters from the definition.
        if head.variable && head.variable.definition.is_a?(FunctionDefinition)
          function_def = head.variable.definition
          graph.add_vertex(argument_list, :params => [function_def.label] + function_def.params.map(&:name))
        else
          graph.add_vertex(argument_list, :params => ['func'] + arguments.map{|arg| '' })
        end

        ([previous_result] + arguments).each_with_index do |argument, index|
          graph.add_edge(argument, argument_list, :param_index => index)
        end

        previous_result = argument_list
      end

      self.dependency_id = previous_result.dependency_id
    end

    def to_s
      head.to_s + argument_lists.map {|argument_list|
        "(#{argument_list.arguments.map(&:to_s).join(', ')})"
      }.join
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
        raise ParseError, "undefined table: #{table_name}"
      end

      if predicate
        table_columns = table_name.variable.definition.columns.each_with_object({}) do |column, columns|
          columns[column.name.to_s] = column
        end
        inner_binding = RecordBinding.new(variable_binding, table_columns)
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
      tree = parser.parse(query_file) or raise ParseError, parser.failure_reason
      raise ParseError, 'file is not a complete query' unless tree.is_a? QueryFile
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

    # definitions ordered such that all the tables come before all the functions
    def ordered_definitions
      tables + functions
    end

    def variables
      return @variables if @variables
      @variables = VariableBinding.new
      bind_variables(@variables)
      if !(undefined = @variables.undefined).empty?
        raise ParseError, "undefined variable: #{undefined.map(&:name).join(', ')}"
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
      ordered_definitions.each do |definition|
        definition.bind_variables(variable_binding)
      end
    end

    def track_dependencies(graph)
      ordered_definitions.each do |definition|
        graph.next_function(definition.signature)
        definition.track_dependencies(graph)
      end
    end

    def to_s
      definitions.map(&:to_s).join('; ')
    end
  end
end
