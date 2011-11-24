use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use DBIx::Class::Carp;
use lib 't/lib';
use DBICTest;

{
  sub DBICTest::DBICCarp::frobnicate {
    DBICTest::DBICCarp::branch1();
    DBICTest::DBICCarp::branch2();
  }

  sub DBICTest::DBICCarp::branch1 { carp_once 'carp1' }
  sub DBICTest::DBICCarp::branch2 { carp_once 'carp2' }


  warnings_exist {
    DBICTest::DBICCarp::frobnicate();
  } [
    qr/carp1/,
    qr/carp2/,
  ], 'expected warnings from carp_once';
}

{
  {
    package DBICTest::DBICCarp::Exempt;

    sub _skip_namespace_frames { qr/^DBICTest::DBICCarp::Exempt/ }

    sub thrower {
      DBICTest->init_schema(no_deploy => 1)->throw_exception('time to die');
    }

    sub caller {
      thrower();
    }
  }

  # the __LINE__ relationship below is important - do not reformat
  throws_ok { DBICTest::DBICCarp::Exempt::caller() }
    qr/^\QDBICTest::DBICCarp::Exempt::thrower(): time to die at @{[ __FILE__ ]} line @{[ __LINE__ - 1 ]}\E$/,
    'Expected exception callsite and originator'
  ;
}



done_testing;
