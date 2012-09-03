use strict;
use Test::More;
use Plack::Builder;
use Plack::Middleware::Cached;

my $counter = 1;
my $app     = sub {
    my $env = shift;
    $env->{counter} = $counter;
    [ 200, [], [ $env->{REQUEST_URI} . ( $counter++ ) ] ];
};

run_test(
    builder {
        enable 'Cached', cache => Mock->new;
        $app;
    },
    0
);

# Reset counter and turn on debug_header
$counter = 1;
run_test(
    builder {
        enable 'Cached',
            cache        => Mock->new,
            debug_header => 'x-pm-cache-debug';
        $app;
    },
    1
);

sub run_test {
    my $app        = shift;
    my $debug_mode = shift;

    my $test_headers = [];
    $test_headers = [ 'x-pm-cache-debug' => 'app' ] if $debug_mode;

    my $res = $app->( { REQUEST_URI => 'foo' } );
    is_deeply( $res, [ 200, $test_headers, ['foo1'] ], 'first call: foo' );

    $res = $app->( { REQUEST_URI => 'bar' } );
    is_deeply( $res, [ 200, $test_headers, ['bar2'] ], 'second call: bar' );

    $test_headers = [ 'x-pm-cache-debug' => 'cache' ] if $debug_mode;
    $res = $app->( { REQUEST_URI => 'foo' } );
    is_deeply(
        $res,
        [ 200, $test_headers, ['foo1'] ],
        'third call: foo (cached)'
    );
}

done_testing;

package Mock;
use Clone qw(clone);    # use clone to make test work like a real cache
sub new { bless( { objects => {} }, shift ); }
sub get { $_[0]->{objects}->{ $_[1] } }

sub set {
    my ( $self, $key, $object, @options ) = @_;
    $self->{objects}->{$key} = clone($object);
    $self->{options} = \@options;
}
