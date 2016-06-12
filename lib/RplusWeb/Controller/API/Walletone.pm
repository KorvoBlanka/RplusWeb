package RplusWeb::Controller::API::Walletone;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use MIME::Base64;
use Encode qw(encode);
use Mojo::Base 'Mojolicious::Controller';

use Rplus::Util::Email;

use Rplus::Model::AccountsExt;
use Rplus::Model::AccountsExt::Manager;
use Rplus::Model::BillingExt;
use Rplus::Model::BillingExt::Manager;

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

    my $sum = 99;

    my $account = Rplus::Model::AccountsExt::Manager->get_objects(query => [email => $email])->[0];
    return $self->render(json => {result => 'fail', reason => 'account not found'}) unless $account;

    my $bill = Rplus::Model::BillingExt->new;
    $bill->account_id($account->id);
    $bill->sum($sum);
    $bill->state(0);
    $bill->provider('walletone');
    $bill->save(insert => 1);
    
    my $inv_id = $bill->{id};    
    my $success_url = "http://zavrus.com/api/walletone/success?InvId=$inv_id&OutSum=$sum";
    my $fail_url = "http://zavrus.com/api/walletone/fail?InvId=$inv_id";
     
    my %fields;

    $fields{"WMI_MERCHANT_ID"}    = "190508019929";
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

    my $bill = Rplus::Model::BillingExt::Manager->get_objects(query => [id => $inv_id])->[0];
    # проверим счет
    if(!$bill) {
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=bill not found');
    }

    # проверим сумму
    if($bill->sum != $sum) {
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=wrong_sum');
    }

    my $account = Rplus::Model::AccountExt::Manager->get_objects(query => [id => $bill->{'account_id'}, del_date => undef])->[0];
    if (!$account) {
        return $self->render(text => 'WMI_RESULT=RETRY&WMI_DESCRIPTION=user not found');
    }

    $bill->state(1);    # state ok
    $bill->save(changes_only => 1);

    my $balance = $account->{'balance'} + $sum;

    my $dt = DateTime->now();
    my $exp = $dt->add(days => 1);
    $account->access_key(_generate_code(8));
    $account->access_key_exp($exp);

    $account->save(changes_only => 1);

    my $subject = 'Ключ доступа';
    my $message = 'Ваш ключ на один день: ';

    $message .= $account->access_key;
    Rplus::Util::Email::send($account->email, $subject, $message);

    return $self->render(text => 'WMI_RESULT=OK');
}

sub success {
    my $self = shift;

    my $inv_id = $self->param('InvId');
    my $sum = $self->param('OutSum');

    my $bill = Rplus::Model::BillingExt::Manager->get_objects(query => [id => $inv_id])->[0];
    # проверим 
    if(!$bill) {
        $self->flash(show_message => 1, message => "Не найден счет. Обратитесь в службу поддержки.");
        return $self->redirect_to('/cabinet');
    }

    my $account = Rplus::Model::AccountExt::Manager->get_objects(query => [id => $bill->{'account_id'}, del_date => undef])->[0];
    if (!$account) {
        $self->flash(show_message => 1, message => "Не найдена учетная запись. Обратитесь в службу поддержки.");
    }

    $self->flash(show_message => 1, message => 'Платеж успешно принят. На счет зачислено '. $sum . ' рублей');
    return $self->redirect_to('/cabinet');
}

sub fail {
    my $self = shift;

    my $inv_id = $self->param('InvId');
    
    my $bill = Rplus::Model::BillingExt::Manager->get_objects(query => [id => $inv_id])->[0];
    if ($bill) {
        $bill->state(2);    # state fail
        $bill->save(changes_only => 1);
    }
    
    $self->flash(show_message => 1, message => 'Платеж не принят');
    return $self->redirect_to('/cabinet');
}

1;
