use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'File::TTX',
    AUTHOR              => q{Michael Roberts <michael@vivtek.com>},
    VERSION_FROM        => 'lib/File/TTX.pm',
    ABSTRACT_FROM       => 'lib/File/TTX.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'XML::xmlapi' => 0.07,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'File-TTX-*' },
);
