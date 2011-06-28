use Test::More;
use Plack::Builder;
use Plack::Middleware::Cached;

my $counter = 1;
my $app = sub { 
	my $env = shift;
	$env->{counter} = $counter;
    [ 200, [], [ $env->{REQUEST_URI}.($counter++) ] ];
};

run_test( builder {
    enable 'Cached', cache => Mock->new;
    $app;
} );

$capp = builder { 
    enable 'Cached', cache => Mock->new, key => [qw(REQUEST_URI HTTP_COOKIE)];
	$app 
};

$counter = 1;
run_test( $capp );

$res = $capp->( { REQUEST_URI => 'foo', HTTP_COOKIE => 'doz=baz' } );
is_deeply( $res, [200,[],['foo3']], 'call with cookies: foo (new)' );
$res = $capp->( { REQUEST_URI => 'foo', HTTP_COOKIE => 'doz=baz' } );
is_deeply( $res, [200,[],['foo3']], 'call with cookies: foo (cached)' );

sub run_test {
    my $app = shift;

    my $res = $app->( { REQUEST_URI => 'foo' } );
    is_deeply( $res, [200,[],['foo1']], 'first call: foo' );

    $res = $app->( { REQUEST_URI => 'bar' } );
    is_deeply( $res, [200,[],['bar2']], 'second call: bar' );

    $res = $app->( { REQUEST_URI => 'foo' } );
    is_deeply( $res, [200,[],['foo1']], 'third call: foo (cached)' );
}

my $cache = Mock->new;
$counter = 1;
$capp = builder {
    enable 'Cached', 
        cache => $cache, 
        set => sub {
            my ($response, $env) = @_;
            return if ($response->[2]->[0] =~ /^notme/);
            return ($response, expires_in => '20 min');
        },
		env => [qw(counter)];
    $app;
};

# pass additional options from set to the cache
my $env = { REQUEST_URI => 'foo', counter => 7 }; 
$res = $capp->( { REQUEST_URI => 'foo' } );
$res = $capp->( $env );
is_deeply( $res, [200,[],['foo1']], 'first' );
is_deeply( $cache->{options}, [ expires_in => '20 min' ], 'set' );
is( $env->{counter}, 1, 'cache env' );

# do not cache if set returns undef
$counter = 2;
$env = { REQUEST_URI => 'notme', counter => 42 }; 
$res = $capp->( $env );
is( $env->{counter}, 2, 'counter not cached' );

$res = $capp->( { REQUEST_URI => 'notme', counter => 2 } );
is_deeply( $res, [200,[],['notme3']], 'skip cache' );

#use Data::Dumper;
#print "\n".Dumper($res)."\n";

done_testing;

package Mock;
sub new { bless ({ objects => {} }, shift); }
sub get { $_[0]->{objects}->{$_[1]} }
sub set { 
    my ($self, $key, $object, @options) = @_;
    $self->{objects}->{$key} = $object;
    $self->{options} = \@options;
}
