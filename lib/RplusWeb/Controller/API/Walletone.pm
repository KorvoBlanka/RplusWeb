package RplusWeb::Controller::API::Walletone;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use MIME::Base64;
use Encode qw(encode);
use Mojo::Base 'Mojolicious::Controller';

use Rplus::Util::Email;
use Rplus::Util::Config;
use Data::Dumper;
use DBM::Deep;
use DateTime::Format::Strptime;

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
    my $type_pay = $self->param('payment');
    my $log = Mojo::Log->new(path => 'log/WalletonePrepare.log', level => 'debug');
    my $config = Rplus::Util::Config::get_config();

    my $sum = $config->{pay}->{$type_pay}->{sum};
    my $prefix_number = $config->{prefix_payment_number};
    $log->debug("Start logging..............................................................................");
    $log->debug('User input data: E-mail: '.$email.' ; Change pay summ: '.$sum);
    my $db = DBM::Deep->new( "zavrus.deep.db" );
    my $id;
    my $exp_data;
    foreach (@{$db->{accounts}}){
        if ($_->{email} eq $email){
            $id = $_->{id};
            $exp_data = DateTime::Format::DateParse->parse_datetime($_->{exp_data});
            last;
        }
    }
    unless ($id){
        push @{$db->{accounts}}, {
                                  email => $email,
                                  id => (scalar @{$db->{accounts}} + 1),
                                };
        $id = scalar @{$db->{accounts}};
    }

    $log->debug("Accounts id is ".$id." of e-mail = $email");
    #return $self->render(json => {result => 'fail', reason => 'account not found'}) unless $id;

    push @{$db->{billing}}, {
                                id_account => $id,
                                state => 0,
                                sum => $sum,
                                id => $prefix_number.(scalar @{$db->{billing}} + 1),
                              };
    my $inv_id = $prefix_number.(scalar @{$db->{billing}});
    $log->debug("New billing number is $inv_id");

    my $success_url = "http://dev.zavrus.com/api/walletone/success?InvId=$inv_id&OutSum=$sum";
    my $fail_url = "http://dev.zavrus.com/api/walletone/fail?InvId=$inv_id";

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
    $log->debug(".......................................................................................................");
    return $self->render(json => $res);
}

sub result {

    my $self = shift;
    my $signature = $self->param('WMI_SIGNATURE');
    my $inv_id = $self->param('WMI_PAYMENT_NO');
    my $sum = $self->param('WMI_PAYMENT_AMOUNT');
    my $config = Rplus::Util::Config::get_config();
    my $prefix_number = $config->{prefix_payment_number};
    my $config_pay = $config->{pay};

    my $db = DBM::Deep->new( "zavrus.deep.db" );
    my $log = Mojo::Log->new(path => 'log/WalletoneResult.log', level => 'debug');
    $log->debug("Start logging..............................................................................");
    my ($id, $fsum, $id_acc);
    foreach (@{$db->{billing}}){
        if ($_->{id} eq $inv_id){
            $id = $_->{id};
            $fsum = $_ -> {sum};
            $id_acc = $_ -> {id_account};
            last;
        }
    }
    $log->debug("ID of billing is $id sum = $fsum, account ID = $id_acc");
    # проверим счет
    return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=bill not found') unless ($id);
    # проверим сумму
    return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=wrong_sum') unless ($fsum == $sum);

    my ($acc_email, $exp_data);
    foreach (@{$db->{accounts}}){
        if ($_ -> {id} == $id_acc){
            $acc_email = $_->{email};
            $exp_data = DateTime::Format::DateParse->parse_datetime($_->{exp_data});
            last;
        }
    }
    $log->debug("Accounts`s email is $acc_email . Valid up to $exp_data");

    if (!$acc_email) {
        $log->debug("Not found email!!!");
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=user not found');

    }

    foreach (@{$db->{billing}}){
        if ($_->{id} eq $inv_id){
            $_->{state} = 1;
            last;
        }
    }

    my $pay_days;
    while ( my ($type, $value) = each(%{$config_pay}) ) {
        if($value -> {sum} == $sum){
            $pay_days = $value -> {days};
        }
    }

    $log->debug("Paid for $pay_days days");

    my $dt = DateTime->now(time_zone=>'local');
    my $new_date;
    $log->debug("Now date: $dt;");
    if($dt > $exp_data || !$exp_data){
        $new_date = $dt->add(days => $pay_days);

    } else {
        $new_date = $exp_data->add(days => $pay_days);
    }
    $log->debug("Exp data: $exp_data; new date: $new_date; pays day: $pay_days");

    foreach (@{$db->{accounts}}){
        if ($_->{id} == $id_acc){
            $_->{exp_data} = "".$new_date;
            last;
        }
    }
    $log->debug("Access to $new_date");
    #$log->debug("code at one day = '$genercode'");

    my $subject = 'Оплата доступа';
    my $message = 'Оплата вашего доступа на zavrus.com успешно совершена. Доступ открыт до ' .$new_date;
    my $send = Rplus::Util::Email::send($acc_email, $subject, $message);
    $log->debug("Send: $send;");
    $log->debug(".......................................................................................................");
    return $self->render(text => 'WMI_RESULT=OK');
}

sub success {
    my $self = shift;

    my $inv_id = $self->param('InvId');
    my $sum = $self->param('OutSum');

    my $log = Mojo::Log->new(path => 'log/WalletoneSuccess.log', level => 'debug');
    $log->debug("Start logging..............................................................................");
    my $db = DBM::Deep->new( "zavrus.deep.db" );

    my ($id_acc, $id_bill);
    foreach (@{$db->{billing}}){
        if ($_->{id} eq $inv_id){
            $id_acc = $_ -> {id_account};
            $id_bill = $_ -> {id};
            last;
        }
    }

    # проверим
    if(!$id_bill) {
        $self->flash(show_message => 1, message => "Не найден счет. Обратитесь в службу поддержки.");
        $log->debug("Show message: Не найден счет. Обратитесь в службу поддержки");
        return $self->redirect_to('/');
    } else {
        $log->debug("Billing number is $id_bill");
    }
    my ($aid, $email);
    foreach (@{$db->{accounts}}){
        if ($_->{id} == $id_acc){
            $aid = $id_acc;
            $email = $_->{email};
            last;
        }
    }

    if (!$aid) {
        $self->flash(show_message => 1, message => "Не найдена учетная запись. Обратитесь в службу поддержки.");
        $log->debug("Show message: Не найдена учетная запись. Обратитесь в службу поддержки");
    } else {
        $log->debug("Account ID is $aid");
    }

    $self->flash(show_message => 1, message => 'Платеж успешно принят. На счет зачислено '. $sum . ' рублей. Используйте свой электронный адрес для входа в систему');
    $log->debug(".......................................................................................................");
    $self->session->{'user'} = {
        id => $aid,
        email => $email,
    };

    return $self->redirect_to('/');
}

sub fail {
    my $self = shift;
    my $db = DBM::Deep->new( "zavrus.deep.db" );
    my $inv_id = $self->param('InvId');
    my $log = Mojo::Log->new(path => 'log/WalletoneFail.log', level => 'debug');
    $log->debug("Start logging..............................................................................");
    foreach (@{$db->{billing}}){
        if ($_ -> {id} eq $inv_id){
            $_ -> {state} = 2;
            last;
        }
    }
    $log->debug("Billing number is $inv_id which failed");
    $self->flash(show_message => 1, message => 'Платеж не принят');
    $log->debug(".......................................................................................................");
    return $self->redirect_to('/');
}

1;
