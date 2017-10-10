package Dancer2::Plugin::GraphQL;
# ABSTRACT: a plugin for adding GraphQL route handlers
use strict;
use warnings;
use Dancer2::Core::Types qw(Bool);
use Dancer2::Plugin;
use GraphQL::Execution;

our $VERSION = '0.01';

has graphiql => (
  is => 'ro',
  isa => Bool,
  from_config => sub { '' },
);

my @DEFAULT_METHODS = qw(get post);
my $TEMPLATE = join '', <DATA>;

my $JSON = JSON::MaybeXS->new->utf8->allow_nonref;
sub _safe_serialize {
  my $data = shift or return 'undefined';
  my $json = $JSON->encode( $data );
  $json =~ s#/#\\/#g;
  return $json;
}

plugin_keywords graphql => sub {
  my ( $plugin, $pattern, $schema, $root_value, $field_resolver ) = @_;
  my $ajax_route = sub {
    my ($app) = @_;
    if (
      $plugin->graphiql and
      ($app->request->header('Accept')//'') =~ /^text\/html\b/ and
      !defined $app->request->params->{raw}
    ) {
      # disable layout
      my $layout = $app->config->{'layout'};
      $app->config->{'layout'} = undef;
      my $result = $app->template(\$TEMPLATE, {
        title            => 'GraphiQL',
        graphiql_version => '0.11.2',
        queryString      => _safe_serialize( $app->request->params->{'query'} ),
        operationName    => _safe_serialize( $app->request->params->{'operationName'} ),
        resultString     => _safe_serialize( $app->request->params->{'result'} ),
        variablesString  => _safe_serialize( $app->request->params->{'variables'} ),
      });
      $app->config->{'layout'} = $layout;
      $app->send_as(html => $result);
    }
    my $body = $JSON->decode($app->request->body);
    $app->send_as(JSON => GraphQL::Execution->execute(
      $schema,
      $body->{'query'},
      $root_value,
      $app->request->headers,
      $body->{'variables'},
      $body->{'operationName'},
      $field_resolver,
    ));
  };
  foreach my $method (@DEFAULT_METHODS) {
    $plugin->app->add_route(
      method => $method,
      regexp => $pattern,
      code   => $ajax_route,
    );
  }
};

=pod

=encoding UTF-8

=head1 NAME

Dancer2::Plugin::GraphQL - a plugin for adding GraphQL route handlers

=head1 SYNOPSIS

  package MyWebApp;

  use Dancer2;
  use Dancer2::Plugin::GraphQL;
  use GraphQL::Schema;
  use GraphQL::Type::Object;
  use GraphQL::Type::Scalar qw/ $String /;

  my $schema = GraphQL::Schema->new(
    query => GraphQL::Type::Object->new(
      name => 'QueryRoot',
      fields => {
        helloWorld => {
          type => $String,
          resolve => sub { 'Hello, world!' },
        },
      },
    ),
  );
  graphql '/graphql' => $schema;

  dance;

=head1 DESCRIPTION

The C<graphql> keyword which is exported by this plugin allow you to
define a route handler implementing a GraphQL endpoint.

Parameters, after the route pattern:

=over 4

=item $schema

A L<GraphQL::Schema> object.

=item $root_value

An optional root value, passed to top-level resolvers.

=item $field_resolver

An optional field resolver, replacing the GraphQL default.

=back

The route handler code will be compiled to behave like the following:

=over 4

=item *

Passes to the L<GraphQL> execute, the given schema, C<$root_value> and C<$field_resolver>.

=item *

The action built matches POST / GET requests.

=item *

Returns GraphQL results in JSON form.

=back

=head1 CONFIGURATION

By default the plugin will not return GraphiQL, but this can be overridden
with plugin setting 'graphiql', to true.

Here is example to use GraphiQL:

  plugins:
    GraphQL:
      graphiql: true

=head1 AUTHOR

Ed J

Based heavily on L<Dancer2::Plugin::Ajax> by "Dancer Core Developers".

=head1 COPYRIGHT AND LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;

__DATA__
<!--
Copied from https://github.com/graphql/express-graphql/blob/master/src/renderGraphiQL.js
Converted to use the simple template to capture the CGI args
-->
<!--
The request to this GraphQL server provided the header "Accept: text/html"
and as a result has been presented GraphiQL - an in-browser IDE for
exploring GraphQL.
If you wish to receive JSON, provide the header "Accept: application/json" or
add "&raw" to the end of the URL within a browser.
-->
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <title>GraphiQL</title>
  <meta name="robots" content="noindex" />
  <style>
    html, body {
      height: 100%;
      margin: 0;
      overflow: hidden;
      width: 100%;
    }
  </style>
  <link href="//cdn.jsdelivr.net/npm/graphiql@<% graphiql_version %>/graphiql.css" rel="stylesheet" />
  <script src="//cdn.jsdelivr.net/fetch/0.9.0/fetch.min.js"></script>
  <script src="//cdn.jsdelivr.net/react/15.4.2/react.min.js"></script>
  <script src="//cdn.jsdelivr.net/react/15.4.2/react-dom.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/graphiql@<% graphiql_version %>/graphiql.min.js"></script>
</head>
<body>
  <script>
    // Collect the URL parameters
    var parameters = {};
    window.location.search.substr(1).split('&').forEach(function (entry) {
      var eq = entry.indexOf('=');
      if (eq >= 0) {
        parameters[decodeURIComponent(entry.slice(0, eq))] =
          decodeURIComponent(entry.slice(eq + 1));
      }
    });
    // Produce a Location query string from a parameter object.
    function locationQuery(params) {
      return '?' + Object.keys(params).filter(function (key) {
        return Boolean(params[key]);
      }).map(function (key) {
        return encodeURIComponent(key) + '=' +
          encodeURIComponent(params[key]);
      }).join('&');
    }
    // Derive a fetch URL from the current URL, sans the GraphQL parameters.
    var graphqlParamNames = {
      query: true,
      variables: true,
      operationName: true
    };
    var otherParams = {};
    for (var k in parameters) {
      if (parameters.hasOwnProperty(k) && graphqlParamNames[k] !== true) {
        otherParams[k] = parameters[k];
      }
    }
    var fetchURL = locationQuery(otherParams);
    // Defines a GraphQL fetcher using the fetch API.
    function graphQLFetcher(graphQLParams) {
      return fetch(fetchURL, {
        method: 'post',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(graphQLParams),
        credentials: 'include',
      }).then(function (response) {
        return response.text();
      }).then(function (responseBody) {
        try {
          return JSON.parse(responseBody);
        } catch (error) {
          return responseBody;
        }
      });
    }
    // When the query and variables string is edited, update the URL bar so
    // that it can be easily shared.
    function onEditQuery(newQuery) {
      parameters.query = newQuery;
      updateURL();
    }
    function onEditVariables(newVariables) {
      parameters.variables = newVariables;
      updateURL();
    }
    function onEditOperationName(newOperationName) {
      parameters.operationName = newOperationName;
      updateURL();
    }
    function updateURL() {
      history.replaceState(null, null, locationQuery(parameters));
    }
    // Render <GraphiQL /> into the body.
    ReactDOM.render(
      React.createElement(GraphiQL, {
        fetcher: graphQLFetcher,
        onEditQuery: onEditQuery,
        onEditVariables: onEditVariables,
        onEditOperationName: onEditOperationName,
        query: <% queryString %>,
        response: <% resultString %>,
        variables: <% variablesString %>,
        operationName: <% operationName %>,
      }),
      document.body
    );
  </script>
</body>
</html>
