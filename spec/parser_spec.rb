require 'spec_helper'

describe 'Query parsing' do
  describe 'of valid syntax' do
    it 'should allow simple function definitions' do
      query = Flowquery.parse('f(int x) = x')
      query.variables['f'].definition.should be_kind_of(Flowquery::FunctionDefinition)
    end

    it 'should allow functions with multiple parameters' do
      Flowquery.parse('f(int x, int y) = x')
    end

    it 'should allow comments anywhere' do
      query = Flowquery.parse(<<-QUERY)
        // Example query with lots of comments
        f /* who'd put a comment here? */ ( int x // (that's a parameter)
        ) = /* function body */ x
        // lol
      QUERY
      query.variables['f'].should_not be_nil
    end

    it 'should allow table definitions' do
      query = Flowquery.parse('create table attendances (user_id int, concert_id int)')
      query.variables['attendances'].definition.should be_kind_of(Flowquery::TableDefinition)
    end

    it 'should allow table-based function definitions' do
      query = Flowquery.parse(<<-QUERY)
        create table users(id int, name text, bio text);
        user_info(int user_id) = select * from users where id = user_id;
      QUERY
      query.variables['users'].definition.should be_kind_of(Flowquery::TableDefinition)
      query.variables['user_info'].definition.should be_kind_of(Flowquery::FunctionDefinition)
    end

    it 'should allow selection of columns from tables' do
      query = Flowquery.parse(<<-QUERY)
        create table attendances (user_id int, concert_id int);
        concerts(int attending_user_id) = select concert_id from attendances where user_id = attending_user_id;
      QUERY
    end

    it 'should allow recursive function definitions' do
      query = Flowquery.parse(<<-QUERY)
        create table edges(from_vertex int, to_vertex int);
        outgoing_edges(int vertex_id) = select to_vertex from edges where from_vertex = vertex_id;
        search(int root) = search(outgoing_edges(root));
      QUERY
    end

    it 'should allow mutually recursive function definitions' do
      Flowquery.parse('one(int x) = two(x); two(int x) = one(x)')
    end
  end

  describe 'of invalid syntax' do
    it 'should not allow empty queries' do
      lambda {
        Flowquery.parse('')
      }.should raise_error(Flowquery::ParseError)
    end

    it 'should not allow incomplete function definitions' do
      lambda {
        Flowquery.parse('f(int x) = ') }.should raise_error(Flowquery::ParseError)
    end

    it 'should not allow references to unbound variables' do
      lambda {
        Flowquery.parse('f(int x) = y')
      }.should raise_error(Flowquery::ParseError, /undefined variable: y/)
    end

    it 'should not allow ambiguous variable names' do
      lambda {
        Flowquery.parse('f(int f) = f')
      }.should raise_error(Flowquery::ParseError, /ambiguous variable name: f/)
    end

    it 'should not allow multiple definitions of the same function' do
      lambda {
        Flowquery.parse('f(int x) = x; f(int y, int z) = y;')
      }.should raise_error(Flowquery::ParseError, /duplicate variable f/)
    end

    it 'should not allow definition of a function and a table of the same name' do
      lambda {
        Flowquery.parse('create table users (id int, name string); users(int x) = x;')
      }.should raise_error(Flowquery::ParseError, /duplicate variable users/)
    end

    it 'should not allow multiple function parameters of the same name' do
      lambda {
        Flowquery.parse('foo(int x, int x) = x')
      }.should raise_error(Flowquery::ParseError, /duplicate variable x/)
    end

    it 'should not allow references to unknown columns in a where clause' do
      lambda {
        Flowquery.parse(<<-QUERY)
          create table users(id int, name text, bio text);
          user_info(int user_id) = select * from users where unknown_column = user_id;
        QUERY
      }.should raise_error(Flowquery::ParseError, /undefined variable: unknown_column/)
    end

    it 'should not allow ambiguity between bound variables and column names in a where clause' do
      lambda {
        Flowquery.parse(<<-QUERY)
          create table users(user_id int, name text, bio text);
          user_info(int user_id) = select * from users where user_id = user_id;
        QUERY
      }.should raise_error(Flowquery::ParseError, /ambiguous variable name: user_id/)
    end

    it 'should not allow selecting from something that is not a table' do
      lambda {
        Flowquery.parse(<<-QUERY)
          foo(int x) = x;
          bar(int y) = select * from foo where x = y;
        QUERY
      }.should raise_error(Flowquery::ParseError, /undefined table: foo/)
    end
  end
end
