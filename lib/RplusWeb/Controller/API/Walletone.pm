package RplusWeb::Controller::API::Walletone;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use MIME::Base64;
use Encode qw(encode);
use Mojo::Base 'Mojolicious::Controller';

use Rplus::Util::Email;
use Rplus::Util::Config;
use Data::Dumper;

my $secret_key = "373268624b446f335b4537356434743363594a756b767634573662";

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

    my $config = Rplus::Util::Config::get_config();

    my $sum = $config->{day_pay};

    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $sth = $sqlite->prepare( "SELECT id FROM accounts WHERE email = '$email';" );
    $sth->execute();
    my $id = $sth->fetchrow();
    return $self->render(json => {result => 'fail', reason => 'account not found'}) unless $id;

    $sqlite->do( "INSERT INTO billing (account_id, sum, state, provider) VALUES ( '$id', '$sum', 0, 'walletone' );" );

    $sth = $sqlite->prepare( "SELECT id FROM billing WHERE account_id = '$id' AND sum = '$sum' AND state = 0 AND  provider= 'walletone' ORDER BY id DESC;" );
    $sth->execute();

    my $inv_id = $sth->fetchrow();
    say Dumper $inv_id;
    my $success_url = "http://zavrus.com/api/walletone/success?InvId=$inv_id&OutSum=$sum";
    my $fail_url = "http://zavrus.com/api/walletone/fail?InvId=$inv_id";

    my %fields;

    $fields{"WMI_MERCHANT_ID"}    = "160663547396";
    $fields{"WMI_PAYMENT_AMOUNT"} = $sum;
    $fields{"WMI_PAYMENT_NO"}     = $inv_id;
    $fields{"WMI_CURRENCY_ID"}    = "643";
    $fields{"WMI_DESCRIPTION"}    = encode_base64(encode('UTF-8','zavrus.com Оплата ключа доступа.'), "");
    $fields{"WMI_SUCCESS_URL"}    = $success_url;
    $fields{"WMI_FAIL_URL"}       = $fail_url;

    my $fieldValues = "";

    for my $key (sort { lc($a) cmp lc($b) } keys %fields)
    {
      $fieldValues .= $fields{$key};
    }

    my $signature = md5_base64(encode('cp1251', $fieldValues . $secret_key)) . '==';


    my $res = {
        inv_id => $inv_id,
        crc => $signature,
        out_sum => $sum,
        success_url => $success_url,
        fail_url => $fail_url,
    };

    return $self->render(json => $res);
}

sub result {

    my $self = shift;
    my $signature = $self->param('WMI_SIGNATURE');
    my $inv_id = $self->param('WMI_PAYMENT_NO');
    my $sum = $self->param('WMI_PAYMENT_AMOUNT');
    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $sth = $sqlite->prepare( "SELECT * FROM billing WHERE id = '$inv_id';" );
    $sth->execute();

    my ( $fid, $finv_id, $fsum, $fstate, $fprovider) = $sth->fetchrow();

    # проверим счет
    if(!$fid) {
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=bill not found');
    }

    # проверим сумму
    if($fsum != $sum) {
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=wrong_sum');
    }

    $sth = $sqlite->prepare( "SELECT email, balance FROM accounts WHERE id = '$finv_id';" );
    $sth->execute();
    my ( $aemail, $abalance) = $sth->fetchrow();

    if (!$aemail) {
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=user not found');
    }

    $sqlite->do( "UPDATE billing SET state = 1 WHERE id = $fid;" );


    my $balance =  $sum+$abalance;

    my $dt = DateTime->now(time_zone=>'local');
    my $exp = $dt->add(days => 1);
    my $format = DateTime::Format::Strptime->new(pattern => '%Y-%m-%d %H:%M:%S');
    my $ndate= $format->format_datetime($exp);

    my $genercode = _generate_code(8);
    $sqlite->do( "UPDATE accounts SET access_key = '$genercode', access_key_exp = '$ndate', balance = '$balance' WHERE id = $finv_id;" );

    my $subject = 'Ключ доступа';
    my $message = 'Ваш ключ на один день: ' .$genercode;
    say  $aemail;
    Rplus::Util::Email::send($aemail, $subject, $message);

    return $self->render(text => 'WMI_RESULT=OK');
}

sub success {
    my $self = shift;

    my $inv_id = $self->param('InvId');
    my $sum = $self->param('OutSum');

    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $sth = $sqlite->prepare( "SELECT account_id FROM billing WHERE id = '$inv_id';" );
    $sth->execute();
    my $id = $sth->fetchrow();

    # проверим
    if(!$id) {
        $self->flash(show_message => 1, message => "Не найден счет. Обратитесь в службу поддержки.");
        return $self->redirect_to('/');
    }

    $sth = $sqlite->prepare( "SELECT id FROM accounts WHERE id = '$id';" );
    $sth->execute();
    my ($aid) = $sth->fetchrow();

    if (!$aid) {
        $self->flash(show_message => 1, message => "Не найдена учетная запись. Обратитесь в службу поддержки.");
    }

    $self->flash(show_message => 1, message => 'Платеж успешно принят. На счет зачислено '. $sum . ' рублей.
                      Пароль доступа отправлен на указанный вами электронный адрес');

    return $self->redirect_to('/');
}

sub fail {
    my $self = shift;

    my $inv_id = $self->param('InvId');

    my $sqlite = DBI->connect('dbi:SQLite:dbname=zavrus.db;','','',{RaiseError=>1},)
    or die die $DBI::errstr;

    my $sth = $sqlite->prepare( "SELECT id FROM billing WHERE id = '$inv_id';" );
    $sth->execute();
    my ($id) = $sth->fetchrow();

    if ($id) {
        $sqlite->do( "UPDATE billing SET state = 2 WHERE id = $id;" ); # state fail
    }

    $self->flash(show_message => 1, message => 'Платеж не принят');
    return $self->redirect_to('/');
}

1;
