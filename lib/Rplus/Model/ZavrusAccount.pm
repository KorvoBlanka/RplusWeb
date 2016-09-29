package Rplus::Model::ZavrusAccount;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'zavrus_account',

    columns => [
        id        => { type => 'serial', not_null => 1 },
        email     => { type => 'varchar', length => 2044, not_null => 1 },
        vcode     => { type => 'varchar', length => 2044, not_null => 1 },
        vcode_exp => { type => 'timestamp with time zone', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],
);

1;

