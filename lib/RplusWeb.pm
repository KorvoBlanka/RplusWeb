package RplusWeb;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

use Rplus::DB;

# This method will run once at server start
sub startup {
    my $self = shift;

    # Plugins
    $self->plugin('Config' => {file => 'app.conf'});

    # DB
    $self->helper(db => sub { Rplus::DB->new_or_cached });

    # PhoneNum formatter helper
    $self->helper(format_phone_num => sub {
        my ($self, $phone_num, $phone_prefix) = @_;
        return undef unless $phone_num;

        return $phone_num =~ s/^(\Q$phone_prefix\E)(\d+)$/($1)$2/r if $phone_prefix && $phone_num =~ /^\Q$phone_prefix\E/;
        return $phone_num =~ s/^(\d{3})(\d{3})(\d{4})/($1)$2$3/r;
    });

    # Router
    my $r = $self->routes;

    $r->route('/fef905ef7c7c.html')->to(cb => sub {
        my $self = shift;
        $self->render(text => '40b3284b6ff4');
    });

    # Base namespace    
    my $r2 = $r->route('/')->to(namespace => 'RplusWeb::Controller');
    {
        $r2->get('/')->to(template => 'realty/list');
        $r2->get('/add')->to(template => 'realty/add');
        $r2->get('/show/:realty_id')->to(template => 'realty/show');
        $r2->get('/info')->to(template => 'aux/info');
        $r2->get('/billing')->to(template => 'aux/billing');        
    }

    # API namespace
    $r->route('/api/:controller')->route('/:action')->to(namespace => 'RplusWeb::Controller::API');
}

1;
