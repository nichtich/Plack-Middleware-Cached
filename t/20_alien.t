use Test::More;
use Plack::Builder;
use Plack::Middleware::Cached;

#
# This test checks that apps not derived from Plack::Component are allowed
#

test_app( Alien::App::Foo->new );
# test_app( Alien::App::Bar->new );

done_testing;

sub test_app {
    my $app = shift;

    my $wrapped = Plack::Middleware::Cached->wrap(
        $app,
        cache => Mock::Cache->new,
    );

    $res = $wrapped->( { REQUEST_URI => 'foo' } );
    is_deeply( $res, { foo => 1 }, 'first call' );

    $res = $wrapped->( { REQUEST_URI => 'foo', HTTP_COOKIE => 'bar=doz' } );
    is_deeply( $res, { foo => 1 }, 'from cache foo (cached)' );
}

package Mock::Cache;
sub new { bless ({ objects => {} }, shift); }
sub get { $_[0]->{objects}->{$_[1]} }
sub set { 
    my ($self, $key, $object, @options) = @_;
    $self->{objects}->{$key} = $object;
    $self->{options} = \@options;
}

1;

# Can be used as app without inheriting from Plack::Component
package Alien::App::Foo;

our $counter = 1;

sub new { bless {}, shift; }

sub call {
    my ($self, $env) = @_;
    return { $env->{REQUEST_URI} => ++$counter };
}

1;

package Alien::App::Bar;

our $counter = 1;

use overload '&{}' => sub {
        my ($self, $env) = @_;
        return { $env->{REQUEST_URI} => ++$counter };
    }, fallback => 1;

sub new { bless {}, shift; }

1;
