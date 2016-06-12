package Rplus::Util::Email;

use IPC::Open2;
use MIME::Lite;
#use MIME::Lite::TT::HTML; 
use Net::SMTP::SSL;

my $host = 'smtp.yandex.ru';
my $mail = 'info@zavrus.com';

my $user = 'info@zavrus.com';
my $pass = 'DU21071969';
my $port = 465;

sub send {
    my $to = shift;
    my $subject = shift;
    my $message = shift;
    
    my $from = 'info@zavrus.com';
  
    my $msg = MIME::Lite->new(
                        From     => $from,
                        To       => $to,
                        Subject  => $subject,
                        Data     => $message
                    );
    $msg->attr("content-type" => "text/html; charset=UTF-8");     
    #$msg->send('smtp', 'smtp.yandex.ru', AuthUser=>'info@rplusmgmt.com', AuthPass=>'ckj;ysqgfhjkm', Port => 587);

    my $smtp = Net::SMTP::SSL->new($host, Port => $port); # or die "Can't connect";
    $smtp->auth($user, $pass); # or die "Can't authenticate:".$smtp->message();
    $smtp->mail($mail); # or die "Error:".$smtp->message();
    $smtp->to($to); # or die "Error:".$smtp->message();
    $smtp->data(); # or die "Error:".$smtp->message();
    $smtp->datasend($msg->as_string); # or die "Error:".$smtp->message();
    $smtp->dataend(); # or die "Error:".$smtp->message();
    $smtp->quit(); # or die "Error:".$smtp->message();
}

1;
