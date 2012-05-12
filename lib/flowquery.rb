require 'rubygems'
require 'treetop'

module Flowquery
  class ParseError < Exception; end
end

%w(parsetree variable_binding dependency_graph).each do |filename|
  require File.join(File.dirname(__FILE__), 'flowquery', filename)
end

Treetop.load(File.join(File.dirname(__FILE__), 'flowquery', 'grammar.treetop'))

FlowQuery = Flowquery
