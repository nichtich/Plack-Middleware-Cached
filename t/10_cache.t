use Test::More;
use Plack::Builder;
use Plack::Middleware::CHI;

my $counter = 1;
my $app = sub { [ 200, [], [ shift->{REQUEST_URI}.($counter++) ] ] };

my $capp = builder {
    enable 'CHI', cache => Mock->new;
    $app;
};

my $res = $capp->( { REQUEST_URI => 'foo' } );
is_deeply( $res, [200,[],['foo1']], 'first call' );

$res = $capp->( { REQUEST_URI => 'bar' } );
is_deeply( $res, [200,[],['bar2']], 'second' );

$res = $capp->( { REQUEST_URI => 'foo' } );
is_deeply( $res, [200,[],['foo1']], 'got cached' );

my $cache = Mock->new;
$counter = 1;
$capp = builder {
    enable 'CHI', 
        cache => $cache, 
        set_as => sub {
            my ($response, $env) = @_;
            return if ($response->[2]->[0] =~ /^notme/);
            return ($response, expires_in => '20 min');
        },
        get_as => sub {
            my ($response) = shift;
            return ($response, { 'xx' => $response->[2]->[0] });
        };
    $app;
};

# pass additional options from set_as to the cache
my $env = { REQUEST_URI => 'foo' }; 
$res = $capp->( { REQUEST_URI => 'foo' } );
$res = $capp->( $env );
is_deeply( $res, [200,[],['foo1']], 'first' );
is_deeply( $cache->{options}, [ expires_in => '20 min' ], 'set_as' );
is( $env->{xx}, 'foo1', 'cache env' );

# do not cache if set_as returns undef
$res = $capp->( { REQUEST_URI => 'notme' } );
$res = $capp->( { REQUEST_URI => 'notme' } );
is_deeply( $res, [200,[],['notme3']], 'skip cache' );


use Data::Dumper;
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
