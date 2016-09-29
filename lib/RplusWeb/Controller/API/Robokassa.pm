package RplusWeb::Controller::API::Robokassa;

use Digest::MD5 qw(md5_hex);
use Mojo::Base 'Mojolicious::Controller';
use utf8;
use Rplus::Util::Email;

my $mrch_login = "Test1999";
my $mrch_pass1 = "password_1";
my $mrch_pass2 = "password2";

sub _generate_code {
    srand(time);
    my $sz = shift;
    my @chars = ("A".."Z", "0".."9");
    my $code;
    $code .= $chars[rand @chars] for 1..$sz;

    return $code;
}

sub prepare {
    my $self = shift;

    my $email = $self->param('email');

    my $sum = 100;

    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $sth = $sqlite->prepare( "SELECT id FROM accounts WHERE email = '$email';" );
    $sth->execute();
    my $id = $sth->fetchrow();
    return $self->render(json => {result => 'fail', reason => 'account not found'}) unless $id;

    $sqlite->do( "INSERT INTO billing (account_id, sum, state, provider) VALUES ( '$id', '$sum', 0, 'robokassa' );" );

    $sth = $sqlite->prepare( "SELECT id FROM billing WHERE account_id = '$id' AND sum = '$sum' AND state = 0 AND  provider= 'robokassa';" );
    $sth->execute();
    my $bilId = 1;

    my $crc = md5_hex("$mrch_login:$sum:$bilId:$mrch_pass1");

    my $res = {
        result => 'ok',
        inv_id => $bilId,
        out_sum => $sum,
        crc => $crc,
    };


    return $self->render(json => $res);
}

sub result {
    my $self = shift;
    my $signature = $self->param('SignatureValue');
    my $inv_id = $self->param('InvId');
    my $summ = $self->param('OutSum');

    # Проверить CRC
    my $crc = uc(md5_hex("$summ:$inv_id:$mrch_pass2"));
    if($crc ne $signature) {
        return $self->render(text => "FAIL crc");
    }

    my $bill = Rplus::Model::BillingExt::Manager->get_objects(query => [id => $inv_id])->[0];
    # проверим счет
    if(!$bill) {
        return $self->render(text => 'FAIL');
    }

    # проверим сумму
    if($bill->sum != $summ) {
        return $self->render(text => 'FAIL');
    }

    my $account = Rplus::Model::ZavrusAccount::Manager->get_objects(query => [id => $bill->{'account_id'}])->[0];
    if (!$account) {
        return $self->render(text => 'FAIL');
    }

    # Save
    $bill->state(1);    # state ok
    $bill->save(changes_only => 1);

    my $balance = $account->{'balance'} + $summ;

    my $dt = DateTime->now();
    my $exp = $dt->add(days => 1);
    $account->access_key(_generate_code(8));
    $account->access_key_exp($exp);

    $account->save(changes_only => 1);

    my $subject = 'Ключ доступа';
    my $message = 'Ваш ключ на один день: ';
    $message .= $account->access_key;
    Rplus::Util::Email::send($account->email, $subject, $message);

    return $self->render(text => 'OK' . $inv_id);
}

sub success {
    my $self = shift;

    my $signature = $self->param('SignatureValue');
    my $inv_id = $self->param('InvId');
    my $summ = $self->param('OutSum');

    # Проверить CRC
    my $crc = md5_hex("$summ:$inv_id:$mrch_pass1");
    if($crc ne $signature) {
        $self->flash(show_message => 1, message => "Не верная подпись. Обратитесь в службу поддержки.");
        return $self->redirect_to('/');
    }

    my $bill = Rplus::Model::BillingExt::Manager->get_objects(query => [id => $inv_id])->[0];
    # проверим
    if(!$bill) {
        $self->flash(show_message => 1, message => "Не найден счет. Обратитесь в службу поддержки.");
        return $self->redirect_to('/');
    }

    my $account = Rplus::Model::ZavrusAccount::Manager->get_objects(query => [id => $bill->account_id])->[0];
    if (!$account) {
        $self->flash(show_message => 1, message => "Не найдена учетная запись. Обратитесь в службу поддержки.");
    }

    $self->flash(show_message => 1, message => 'Платеж успешно принят. Ключ выслан на ваш email.');
    return $self->redirect_to('/');
}

sub fail {
    my $self = shift;

    my $inv_id = $self->param('InvId');
    my $sum = $self->param('OutSum');

    my $bill = Rplus::Model::BillingExt::Manager->get_objects(query => [id => $inv_id])->[0];
    if ($bill) {
        $bill->state(2);    # state fail
        $bill->save(changes_only => 1);
    }

    $self->flash(show_message => 1, message => 'Платеж отменен.');
    return $self->redirect_to('/');
}

1;
