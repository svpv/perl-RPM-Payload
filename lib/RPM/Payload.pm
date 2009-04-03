package RPM::Payload;

use 5.008;
use strict;

our $VERSION = '0.01';

sub new {
	my ($class, $f) = @_;
	open my $fh, "-|", "rpm2cpio", $f
		or die "$f: rpm2cpio failed";
	# n1: current data pos
	# n2: end data pos
	# n3: next entry pos
	bless [ $f, $fh, 0, 0, 0 ] => $class;
}

sub _skip ($$$) {
	my ($f, $fh, $n) = @_;
	while ($n > 0) {
		my $m = ($n > 8192) ? 8192 : $n;
		$m == read $fh, my $buf, $m
			or die "$f: cannot skip cpio bytes";
		$n -= $m;
	}
}

sub next {
	my $self = shift;
	my ($f, $fh, $n1, $n2, $n3) = @$self;
	if ($n3 > $n1) {
		_skip($f, $fh, $n3 - $n1);
		$n1 = $n3;
	}
	110 == read $fh, my $cpio_header, 110
		or die "$f: cannot read cpio header";
	$n1 += 110;

	my ($magic, $ino, $mode, $uid, $gid, $nlink, $mtime, $size,
	$dev_major, $dev_minor, $rdev_major, $rdev_minor, $namelen, $checksum) =
		map hex, unpack "a6(a8)13", $cpio_header;
	$magic == 0x070701 or die "$f: bad cpio header magic";

	my $namesize = (($namelen + 1) & ~3) + 2;
	$namesize == read $fh, my $filename, $namesize
		or die "$f: cannot read cpio filename";
	$n1 += $namesize;
	substr $filename, $namelen, $namesize, "";
	chop($filename) eq "\0"
		or die "$f: bad cpio filename";

	$n2 = $n1 + $size;
	$n3 = ($n2 + 3) & ~3;
	#warn "filename=$filename\tdatapos=$n1 end=$n2 next=$n3\n";
	@$self[2,3,4] = ($n1, $n2, $n3);

	return if $filename eq "TRAILER!!!";

	my $entry = {
		filename => $filename,
		ino	=> $ino,
		mode	=> $mode,
		uid	=> $uid,
		gid	=> $gid,
		nlink	=> $nlink,
		mtime	=> $mtime,
		size	=> $size,
		dev_major => $dev_major, dev_minor => $dev_minor,
		rdev_major => $rdev_major, rdev_minor => $rdev_minor,
		dev	=> ($dev_major << 8) | $dev_minor,
		rdev	=> ($rdev_major << 8) | $rdev_minor,
		_cpio	=> $self,
	};
	bless $entry, "RPM::Payload::entry";
}

package RPM::Payload::entry;
use Fcntl qw(:mode);

sub read {
	die "Usage: ENTRY->read(SCALAR,LENGTH)"
		unless @_ == 3;
	my $self = shift;
	my $n = pop;
	my $cpio = $$self{_cpio};
	my ($f, $fh, $n1, $n2, $n3) = @$cpio;
	die "$f: $$self{filename}: not regular file"
		unless S_ISREG($$self{mode});

	my $left = $n2 - $n1;
	$n = $left if $n > $left;
	return 0 if $n < 1;

	$n == read $fh, $_[0], $n
		or die "$f: $$self{filename}: cannot read cpio data";
	$$cpio[2] += $n;
	return $n;
}

sub readlink {
	my $self = shift;
	return $$self{_readlink} if exists $$self{_readlink};
	my $cpio = $$self{_cpio};
	my ($f, $fh, $n1, $n2, $n3) = @$cpio;
	# TODO
}

for my $method (qw(
	filename ino mode uid gid nlink mtime size dev rdev
	dev_major dev_minor rdev_major rdev_minor))
{
	no strict 'refs';
	*$method = sub { $_[0]->{$method} };
}

1;

__END__

=head1	NAME

RPM::Payload - simple in-memory access to RPM archive

=head1	SYNOPSIS

  use RPM::Payload;
  my $cpio = RPM::Payload->new("rpm-3.0.4-0.48.i386.rpm");
  while (my $entry = $cpio->next) {
    print $entry->filename, "\n";
  }

=head1	DESCRIPTION

=head1	EXAMPLE

    rpmfile()
    {
	tmpdir=`mktemp -dt rpmfile.XXXXXXXX`
	rpm2cpio "$1" |(cd $tmpdir
	    cpio -idmu --quiet --no-absolute-filenames
	    chmod -Rf u+rwX .
	    find -type f -print0 |xargs -r0 file)
	rm -rf $tmpdir
    }

Here is sample output:

    $ rpmfile rss2mail2-2.25-alt1.noarch.rpm 
    ./usr/share/man/man1/rss2mail2.1.gz: gzip compressed data, from Unix, max compression
    ./usr/bin/rss2mail2:                 perl script text executable
    ./etc/rss2mail2rc:                   ASCII text
    $

    use RPM::Payload;
    use Fcntl qw(:mode);
    use File::LibMagic qw(MagicBuffer);
    sub rpmfile {
	my $f = shift;
	my $cpio = RPM::Payload->new($f);
	while (my $entry = $cpio->next) {
	    next unless S_ISREG($entry->mode);
	    next unless $entry->size > 0;
	    $entry->read(my $buf, 4096) > 0 or die "read error";
	    print $entry->filename, "\t", MagicBuffer($buf), "\n";
	}
    }

=head1	BUGS

It dies on errors.  So you may need encolsing eval block.  However, they say
"when you must fail, fail noisily and as soon as possible".

Compressed cpio stream is not seekable.  As a consequence, C<$entry->READ>
method is only valid within the current cpio state, until the next entry
is obtained with C<$cpio->next>.

Hradlinks.

=head1	SEE ALSO

rpm2cpio(8).

Edward C. Bailey.  Maximum RPM.
L<http://www.rpm.org/max-rpm/index.html> (RPM File Format).

Eric S. Raymond.  The Art of Unix Programming.
L<http://www.faqs.org/docs/artu/index.html> (Rule of Repair).

=cut
