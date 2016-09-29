package RplusWeb::Controller::API::User;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::DB;
use Rplus::Util::Email;

use DateTime;
use Data::Dumper;
use JSON;
use DBI;

sub _generate_code {
    srand(time);
    my $sz = shift;
    my @chars = ("A".."Z", "0".."9");
    my $code;
    $code .= $chars[rand @chars] for 1..$sz;

    return $code;
}

sub create {
    my $self = shift;

    # Input params
    my $email = $self->param('email');

	  #return $self->render(json => {status => 'fail', });
    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $sth = $sqlite->prepare( "SELECT email FROM accounts WHERE email = '$email';" );
    $sth->execute();
    my $newmail = $sth->fetchrow();

    my $dt = DateTime->now(time_zone=>'local');
    my $code_exp = $dt->add(hours => 2);
    my $code = _generate_code(4);
    my $format = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
    my $ndate= $format->format_datetime($code_exp);
    if (!$newmail) {
        eval {
            $sqlite->do( "INSERT INTO accounts (email, vcode, vcode_exp) VALUES ( '$email', '$code', '$ndate' );" );
            1;
        } or do {
            return $self->render(json => {error => $@}, status => 500);
          };
    } else {
        eval {
            $sqlite->do( "UPDATE accounts SET vcode = '$code', vcode_exp = '$ndate' WHERE email = '$newmail' ;" );
            1;
        } or do {
            return $self->render(json => {error => $@}, status => 500);
        };

    }
    my $subject = 'Проверка e-mail';
    my $message = 'Ваш проверочный код: ' . $code;

    if($newmail){
        Rplus::Util::Email::send($email, $subject, $message);
    } else{
        Rplus::Util::Email::send($newmail, $subject, $message);
    }
    return $self->render(json => {status => 'success', });

}

sub check_code {
    my $self = shift;

    # Input params
    my $email = $self->param('email');
    my $v_code = $self->param('vcode');
    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $dt = DateTime->now(time_zone=>'local');
    my $format = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
    my $ndate= $format->format_datetime($dt);


    my $sth = $sqlite->prepare( "SELECT vcode FROM accounts WHERE email = '$email' AND vcode = '$v_code' AND vcode_exp > strftime('%Y-%m-%d %H:%M:%S', '$ndate');" );
    $sth->execute();
    my $code = $sth->fetchrow();
    return $self->render(json => {result => 'fail'}) unless $code;
    return $self->render(json => {result => 'ok'});
}

sub check_session {
    my $self = shift;
    if ($self->session->{'user'}) {
        return $self->render(json => {result => 'login', email => $self->session->{'user'}->{email}});
    } else {
        return $self->render(json => {result => 'no_login'});
    }
}

sub unlock {
    my $self = shift;

    # Input params
    my $email = $self->param('email');
    my $access_key = $self->param('access_key');

    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $dt = DateTime->now(time_zone=>'local');
    my $format = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
    my $ndate= $format->format_datetime($dt);

    my $sth = $sqlite->prepare( "SELECT id, email, access_key, access_key_exp  FROM accounts WHERE email = '$email' AND access_key='$access_key' AND access_key_exp > strftime('%Y-%m-%d %H:%M:%S', '$ndate'); " );
    $sth->execute();
    my ($exid, $exmail, $exkey, $exkey_exp) = $sth->fetchrow();


    return $self->render(json => {result => 'fail'}) unless $exid;

    $self->session->{'user'} = {
        id => $exid,
        email => $exmail,
        access_key => $exkey,
    };

    return $self->render(json => {result => 'ok', exp => $exkey_exp});
}

sub lock {
    my $self = shift;
    delete $self->session->{'user'};
    return $self->render(json => {result => 'ok'});
}

1;
