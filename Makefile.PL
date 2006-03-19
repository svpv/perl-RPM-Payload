use ExtUtils::MakeMaker;
WriteMakefile 
	NAME		=> 'RPM::Payload',
	VERSION_FROM	=> 'lib/RPM/Payload.pm',
	PREREQ_PM	=> { 'Compress::Zlib' => 1 },
	ABSTRACT_FROM	=> 'lib/RPM/Payload.pm',
	AUTHOR		=> 'Alexey Tourbin <at@altlinux.org>',
	dist		=> { COMPRESS => 'gzip -9nf' },
	;
