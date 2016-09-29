package Rplus::Model::ZavrusAccount::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::ZavrusAccount;

sub object_class { 'Rplus::Model::ZavrusAccount' }

__PACKAGE__->make_manager_methods('zavrus_account');

1;

