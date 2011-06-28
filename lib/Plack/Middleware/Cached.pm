package Plack::Middleware::Cached;
# ABSTRACT: glues a cache to your PSGI application

use strict;
use warnings;

use parent 'Plack::Middleware';
use Scalar::Util 'blessed'; 
use Carp 'croak';

use Plack::Util::Accessor qw(cache key set env);

sub prepare_app {
    my ($self) = @_;

    croak "expected cache" unless $self->cache;

    croak "cache object must provide get and set" 
        unless can_cache( $self->cache );

    if (ref $self->key and ref $self->key eq 'ARRAY') {
        my $key = $self->key;
        $self->key( sub {
            my $env = shift;
            # stringify subset of the request environment
            join '\1E', 
                map { ($_, $env->{$_}) } 
                grep { defined $env->{$_} } @$key;
        } );
    }

    $self->set( sub { $_[0] } ) unless $self->set;
}

sub call {
    my ($self, $env) = @_;

    my $key = $self->key ? $self->key->($env) : $env->{REQUEST_URI};

    return $self->app->($env) unless defined $key;

    # get from cache
    my $object = $self->cache->get( $key );
    if (defined $object) {
        my ($response, $mod_env) = @{$object};
        if ($mod_env) { # TODO: should we check $self->env ?
            while ( my ($key, $value) = each %$mod_env ) {
                $env->{$key} = $value;
            }
        }
        return $response;
    }

    # pass through and cache afterwards
    my $response = $self->app->($env);

    my @options = $self->set->($response, $env);
    if (@options and $options[0]) {
        $options[0] = [ $options[0] ];
        if ($self->env) {
            $options[0]->[1] = { 
                map { $_ => $env->{$_} } @{ $self->env }
            };
        }
        $self->cache->set( $key, @options );
    }

    return $response;
}

sub can_cache {
    my $cache = shift;    
    return ( blessed $cache and $cache->can('set') and $cache->can('get') );
}

1;

__END__

=head1 SYNOPSIS

    use Plack::Builder;
    use Plack::Middleware::Cached;

    my $cache = CHI->new( ... );           # create a cache

    builder {
        enable 'Cached', cache => $cache;  # enable caching
        $app;
    }

    # alternative creation without Plack::Builder
    Plack::Middleware::Cached->wrap(
        $app, cache => $cache, 
        key => [qw(REQUEST_URI HTTP_COOKIE)]  # optional configuration
    );

=head1 DESCRIPTION

This module can be used to glue a cache to a L<PSGI> applications or middleware.
A B<cache> is an object that provides at least two methods to get and set
data, based on a key. Existing cache modules on CPAN include L<CHI>, L<Cache>,
and L<Cache::Cache>. Plack::Middleware::Cached is put in front of a PSGI
application as middleware. Given a request in form of a PSGI environment E, it
either returns the matching response R from its cache, or it passed the request
to the wrapped application, and stores the application's response in the cache:

                      ________          _____
    Request  ===E===>|        |---E--->|     |
                     | Cached |        | App |
    Response <==R====|________|<--R----|_____|

In most cases, only a part of the environment E is relevant to the request. 
This relevant part is called the caching B<key>. By default, the key is set
to the value of REQUEST_URI from the environment E.

Some application may also modify the environment E:

                      ________          _____
    Request  ===E===>|        |---E--->|     |
                     | Cached |        | App |
    Response <==R+E==|________|<--R+E--|_____|

If needed, you can configure Plack::Middleware::Cached with B<env> to also
cache parts of the environment E, as it was returned by the application.

Although this module aims at caching PSGI applications, you can use it to cache 
any function that returns some response object based on a request environment.

=head1 CONFIGURATION

=over 4

=item cache

An cache object, which supports the methods C<< get( $key ) >> to retrieve 
an object from cache and C<< set( $key, $object [, @options ] ) >> to store
an object in cache, possibly adjusted by some options. See L<CHI> for a class
than can be used to create cache objects.

=item key

Code reference that maps a PSGI environment to a scalar key. The key is used
as unique identifier to store and retrieve data in the cache. By default the
REQUEST_URI is used as key. The request is not cached if undef is returned.

=item env

Array reference with keys from the environment that should be cached together
with a response.

=item set

Code reference to determine a policy for storing data in the cache. Each time
a response (and possibly environment data) is to be stored in the cache, it
is passed to this function. The code is expected to return an array with the
response as first value and optional options to the cache's 'set' method as 
additional values. For instance you can pass an expiration time like this:

    set => sub {
        my ($response, $env) = @_;
        return ($response, expires_in => '20 min');
    }

You can also use set to skip selected responses from caching:

    set => sub {
        my ($response, $env) = @_;
        if ( $some_condition_not_to_cache_this_response ) {
            return;
        }
        return $response;
    }

=back

=head1 LIMITATIONS

The current version of this module does not support streaming responses.

=head1 SEE ALSO

There already are several modules for caching PSGI applications:
L<Plack::Middleware::Cache> by Ingy dÃ¶t Net implements a simple file 
cache for PSGI responses. Panu Ervamaa created a more general module of 
same name, available at L<https://github.com/pnu/Plack-Middleware-Cache>.

=cut
