package Plack::Middleware::Cached;

use strict;
use warnings;

use parent 'Plack::Middleware';
use Scalar::Util 'blessed'; 
use Carp 'croak';

use Plack::Util::Accessor qw(cache key set env);

sub new { # adopted from Plack::Component
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $cache = shift @_ if blessed $_[0];                        # allow quick constructor
    my $env   = shift @_ if ref $_[0] and ref $_[0] eq 'ARRAY';   # dito

    my $self;
    if (@_ == 1 && ref $_[0] eq 'HASH') {
        $self = bless {%{$_[0]}}, $class;
    } else {
        $self = bless {@_}, $class;
    }

    $self->cache( $cache ) if defined $cache; # dito
    $self->env( $env ) if defined $env; # dito

    $self;
}

sub wrap { # adopted from Plack::Middleware
    my($self, $app, @args) = @_;
    if (ref $self) {
        $self->{app} = $app;
    } else {
        # $self = $self->new({ app => $app, @args });
        $self = $self->new( @args, app => $app );
    }
    return $self->to_app;
}

sub prepare_app {
    my ($self) = @_;

    croak "expected cache" unless $self->cache;

    croak "cache object must provide get and set" 
		unless can_cache( $self->cache );

    $self->key( sub { $_[0]->{REQUEST_URI} } ) unless $self->key;
    $self->set( sub { $_[0] } ) unless $self->set;

    # TODO: check $self->env
}

sub call {
    my ($self, $env) = @_;

    my $key = $self->key->($env);

    return $self->app->($env) unless defined $key;

    # get from cache
    my $object = $self->cache->get( $key );
    if (defined $object) {
        my ($response, $mod_env) = @{$object};
        if ($mod_env) { # TODO: check $self->env (?)
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

    my $cache = CHI->new( ... );  # create a cache

    builder {
        enable 'Cached', $cache;  # enable caching
        $app;
    }

    # alternative creation without Plack::Builder
    Plack::Middleware::Cache->wrap( $app );

	# TODO:
    Plack::Middleware::Cache->wrap(
	    $app, $cache, [qw(REQUEST_URI HTTP_COOKIES)] 
	);


=head1 DESCRIPTION

Thid module can be used to enrich L<PSGI> applications and middleware with a
cache. A B<cache> is an object that provides at least two methods to get and set
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

If needed, you can configure Plack::Middleware::Cached to also cache parts
of the environment E as it was returned by the application.

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

Array reference with keys from the environment that should also be cached.

=item set

Code reference to map a reference to the PSGI response and its environment
to an object that is stored in the cache. By default only the response is 
stored, which is what you need in most cases. The code is expected to return
an array with the object as first value and optional options to 'set' as 
additional values. For instance you can pass an expiration time like this:

    set => sub {
        my ($response, $env) = @_;
        return ( $response, expires_in => '20 min' );
    }

You can also use set to skip selected objects from caching:

    set => sub {
        my $response = shift;
        return $some_condition ? $response : ();
    }

=back

=head1 SEE ALSO

There are several other modules for caching PSGI.
See L<Plack::Middleware::Cache> for one instance.

=cut
