module FlowQuery
  class DependencyGraph
    def initialize
      @dependency_ids = 0
      @vertices = {}
      @forward_edges = {}
      @backward_edges = {}
    end

    def next_dependency_id
      @dependency_ids += 1
      "n#{@dependency_ids}"
    end

    def add_vertex(vertex)
      vertex.dependency_id ||= next_dependency_id
      @vertices[vertex.dependency_id] = vertex
    end

    def add_edge(from, to, label='')
      raise "Edge start is not a vertex: #{from.inspect}" unless from.dependency_id
      raise "Edge end is not a vertex: #{to.inspect}" unless to.dependency_id
      @forward_edges[from.dependency_id] ||= []
      @forward_edges[from.dependency_id] << {:to => to.dependency_id, :label => label}
      @backward_edges[to.dependency_id] ||= []
      @backward_edges[to.dependency_id] << {:from => from.dependency_id, :label => label}
    end

    def to_graphviz
      "digraph G {\n#{vertices_to_graphviz}\n#{edges_to_graphviz}\n}\n"
    end

    def vertices_to_graphviz
      @vertices.map do |id, vertex|
        quoted_name = vertex.to_s.gsub('"', '\\"')
        %Q(    #{id} [label="#{quoted_name}"];)
      end.join("\n")
    end

    def edges_to_graphviz
      @forward_edges.map do |from, to_list|
        to_list.map do |to|
          quoted_label = to[:label].to_s.gsub('"', '\\"')
          %Q(    #{from} -> #{to[:to]} [headlabel="#{quoted_label}"];)
        end
      end.flatten(1).join("\n")
    end
  end
end
