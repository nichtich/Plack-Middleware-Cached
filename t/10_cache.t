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

$counter = 1;
run_test( builder { 
    enable 'Cached', Mock->new; 
	$app 
} );


sub run_test {
    my $app = shift;

    my $res = $app->( { REQUEST_URI => 'foo' } );
    is_deeply( $res, [200,[],['foo1']], 'first call' );

    $res = $app->( { REQUEST_URI => 'bar' } );
    is_deeply( $res, [200,[],['bar2']], 'second' );

    $res = $app->( { REQUEST_URI => 'foo' } );
    is_deeply( $res, [200,[],['foo1']], 'got cached' );
}

my $cache = Mock->new;
$counter = 1;
my $capp = builder {
    enable 'Cached', $cache, 
        set => sub {
            my ($response, $env) = @_;
            return if ($response->[2]->[0] =~ /^notme/);
            return ($response, expires_in => '20 min');
        },
		env => [qw(counter)];
#        env => get_as => sub {
#            my ($response) = shift;
#            return ($response, { 'xx' => $response->[2]->[0] });
#        };
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
