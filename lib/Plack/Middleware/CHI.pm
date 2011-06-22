package Plack::Middleware::CHI;

use strict;
use warnings;

use parent 'Plack::Middleware';
use Scalar::Util 'blessed'; 
use Carp 'croak';

use Plack::Util::Accessor qw(cache env_key set_as get_as);

sub prepare_app {
    my ($self) = @_;

    croak "expected cache" unless $self->cache;

	# duck-type CHI
    croak "cache must be a CHI-like object" unless blessed $self->cache
        and $self->cache->can('set') and $self->cache->can('get');

    $self->env_key( sub { $_[0]->{REQUEST_URI} } ) unless $self->env_key;
    $self->set_as( sub { $_[0] } ) unless $self->set_as;
    $self->get_as( sub { $_[0] } ) unless $self->get_as;  
}

sub call {
    my ($self, $env) = @_;

    my $key = $self->env_key->($env);

    return $self->app->($env) unless defined $key;

    # get from cache
    my $object = $self->cache->get( $key );
    if (defined $object) {
        my ($response, $mod_env) = $self->get_as->( $object );
        if ($mod_env) {
            while ( my ($key, $value) = each %$mod_env ) {
                $env->{$key} = $value;
            }
        }
        return $response;
    }

    # pass through and cache afterwards
    my $response = $self->app->($env);

    my @options = $self->set_as->($response, $env);
    if (@options and $options[0]) {
        $self->cache->set( $key, @options );
    }

    return $response;
}

1;

__END__

=head1 SYNOPSIS

    use Plack::Builder;
    use Plack::Middleware::CHI;

    builder {
        enable 'Cache', cache => $chi;
        $app;
    }

=head1 DESCRIPTION

This middleware caches L<PSGI> responses and environment variables based on 
L<CHI> or any other caching object with methods set and get.

=head1 CONFIGURATIONS

=over 4

=item cache

An instance of L<CHI> to be used as cache. Alternatively you can use any
other object that supports the following two methods:

=over 4

=back get( $key )

Retrieve an object from cache.

=item set( $key, $object [, @options ] )

Store an object in cache, possibly adjusted by options like C<"now">, 
C<"never">, C<expires_in>, etc. See L<CHI> for details.

=item env_key

Code reference that maps a PSGI environment to a scalar key. The key is used
as unique identifier to store and retrieve data in the cache. By default the
REQUEST_URI is used as key. The request is not cached if undef is returned.

=item set_as

Code reference to map a reference to the PSGI response and its environment
to an object that is stored in the cache. By default only the response is 
stored, which is what you need in most cases. The code is expected to return
an array with the object as first value and optional options to 'set' as 
additional values. For instance you can pass an expiration time like this:

    set_as => sub {
        my ($response, $env) = @_;
        return ( $response, expires_in => '20 min' );
    }

You can also use set_as to skip selected objects from caching:

    set_as => sub {
        my $response = shift;
        return $some_condition ? $response : ();
    }

=item get_as

Code reference to map an object stored in the cache to a PSGI response plus
possibly a hash reference with environment variables. You B<must> ensure
rount-trip safety at least for the response value, that means 
C<get_as( set_as( $response ) )> always returns a value equal to C<$response>.

As long as you directly use PSGI responses as cache objects, you do not need to
modify this option. If you return more than the response, your environment
variables will be merged into the actual environment. For instance the
following method adds (or overwrites) C<< $env->{'chi.cached'} = 'foo' >>:

    get_as => sub {
       my ($response) = shift;
       return ( $response, { 'chi.cached' => 'foo' } );
    }

=back

=head1 SEE ALSO

L<PSGI> and L<Plack::Middleware::Cache>. 

=cut
