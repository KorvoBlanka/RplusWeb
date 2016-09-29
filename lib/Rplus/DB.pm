package Rplus::DB;

use Rplus::Modern;

use base qw(Rose::DB);

__PACKAGE__->use_private_registry;

__PACKAGE__->register_db(
    domain   => 'development',
    type     => 'main',
    driver   => 'Pg',
    database => 'rplus_dev',
    host     => '127.0.0.1',
    port     => 5433,
    username => 'raven',
    password => 'raven!12345',
    schema   => 'public',
    connect_options => {
        AutoCommit => 1,
    },
    pg_enable_utf8 => 1,
    post_connect_sql  => [
        "SET client_encoding TO 'UTF8'",
        "SET search_path TO public,postgis",
    ]
);

__PACKAGE__->default_domain('development');
__PACKAGE__->default_type('main');

1;
