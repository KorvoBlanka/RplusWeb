package RplusWeb;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

use Rplus::DB;
use Rplus::Model::Realty::Manager;

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

    # API namespace

    $r->route('/api/:controller/:action')->to(namespace => 'RplusWeb::Controller::API');

    # Base namespace
    {
        $r->get('/')->to(template => 'realty/list');
        $r->get('/add')->to(template => 'realty/add');
        $r->get('/show/:realty_id')->to(template => 'realty/show');
        $r->get('/info')->to(template => 'aux/info');
        $r->get('/billing')->to(template => 'aux/billing');
        $r->get('/service/statistic')->to(template => 'service/statistic');
    }


}

1;
