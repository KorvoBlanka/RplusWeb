package RplusWeb::Controller::API::User;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::DB;
use Rplus::Util::Email;

#use Rplus::Model::AccountsExt;
#use Rplus::Model::AccountsExt::Manager;

use DateTime;
use JSON;

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

	return $self->render(json => {status => 'fail', });
	
    #my $account = Rplus::Model::AccountsExt::Manager->get_objects(query => [email => $email])->[0];
    #if (!$account) {
    #    $account = Rplus::Model::AccountsExt->new(email => $email);
    #}

    #my $dt = DateTime->now();
    #my $exp = $dt->add(hours => 2);

    # Save
    #$account->v_code(_generate_code(4));
    #$account->v_code_exp($exp);

    #eval {
    #    $account->save;
    #    1;
    #} or do {
    #    return $self->render(json => {error => $@}, status => 500);
    #};

    #my $subject = 'Проверка e-mail';
    #my $message = 'Ваш проверочный код: ' . $account->v_code;
    #Rplus::Util::Email::send($email, $subject, $message);
    
    return $self->render(json => {status => 'success', });

}

sub check_code {
    my $self = shift;

    # Input params
    my $email = $self->param('email');
    my $v_code = $self->param('vcode');
	
	return $self->render(json => {result => 'fail'});
	
    #my $account = Rplus::Model::AccountsExt::Manager->get_objects(
    #    query => [
    #        email => $email,
    #        v_code => $v_code,
    #        v_code_exp => {gt => 'now()'},
    #    ])->[0];
    #return $self->render(json => {result => 'fail'}) unless $account;
    #return $self->render(json => {result => 'ok'});
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
	
	return $self->render(json => {result => 'fail'});
	
    #my $account = Rplus::Model::AccountsExt::Manager->get_objects(
    #    query => [
    #        email => $email,
    #        access_key => $access_key, 
    #        access_key_exp => {gt => 'now()'},
    #    ])->[0];
    #return $self->render(json => {result => 'fail'}) unless $account;

    #$self->session->{'user'} = {
    #    id => $account->id,
    #    email => $account->email,
    #    access_key => $account->access_key,
    #};

    #return $self->render(json => {result => 'ok', exp => $account->access_key_exp});
}

sub lock {
    my $self = shift;
    delete $self->session->{'user'};
    return $self->render(json => {result => 'ok'});
}

1;
