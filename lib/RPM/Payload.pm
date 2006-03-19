package RPM::Payload;

use 5.008;
use strict;

our $VERSION = '0.01';
our $DEBUG;

sub new {
	my ($class, $f) = @_;
	open my $fh, "<", $f or die "$f: $!";
	{
		read($fh, my $lead, 96) == 96 or die "$f: bad rpm lead";
		my ($magic, $major, $minor) = unpack "NCC", $lead;
		$magic == 0xedabeedb or die "$f: bad rpm magic";
		$major == 3 or $major == 4 or warn "$f: rpm version $major.$minor";
	}
	{
		read($fh, my $signature, 16) == 16 or die "$f: bad rpm signature";
		my ($magic, undef, $sections, $bytes) = unpack "N4", $signature;
		$magic == 0x8eade801 or die "$f: bad rpm signature";
		my $sigsize = 16 * $sections + $bytes;
		$sigsize += (8 - $sigsize % 8) % 8;
		seek $fh, $sigsize, 1 or die "$f: bad rpm signature";
	}
	warn "$f: header pos " . tell($fh) if $DEBUG;
	{
		read($fh, my $header, 16) == 16 or die "$f: bad rpm header";
		my ($magic, undef, $sections, $bytes) = unpack "N4", $header;
		$magic == 0x8eade801 or die "$f: bad rpm header";
		my $hdrsize = 16 * $sections + $bytes;
		seek $fh, $hdrsize, 1 or die "$f: bad rpm header";
	}
	warn "$f: payload pos " . tell($fh) if $DEBUG;
	{
		read($fh, my $buf, 8) == 8 or die "$f: bad rpm payload";
		seek $fh, -8, 1 or die "$f: bad rpm payload";
		if (substr($buf, 0, 2) eq "\037\213") {
			require Compress::Zlib;
			# Here is a subtle gotcha: I can't simply do
			#	$gzstream = Compress::Zlib::gzopen($fh, "rb");
			#	return $gzstream;
			# because $fh will be GC-autoclosed and zlib will bail out
			# with EBADF, but only after its internal buffer is exhausted.
			# So I have to keep plain $fh along with $gzstream somehow.
			my $gzstream = Compress::Zlib::gzopen($fh, "rb")
				or die "$f: bad gzdio payload";
			*$fh = \$gzstream;
		}
		elsif (substr($buf, 0, 3) eq "BZh") {
			require Compress::Bzip2;
			Compress::Bzip2->VERSION(2);
			my $gzstream = Compress::Bzip2::gzopen($fh, "rb")
				or die "$f: bad bzdio payload";
			*$fh = \$gzstream;
		}
		elsif (substr($buf, 0, 6) eq "070701") {
			# cpio OK
		}
		else {
			die "$f: bad rpm payload";
		}
	}
	warn "$f: $fh" if $DEBUG;
	bless [ $f, $fh, 0, 0, 0 ] => $class;
}

sub _read ($$$) {
	if (my $gzstream = *{$_[0]}{SCALAR}) {
		$gzstream = $$gzstream;
		$gzstream->gzread($_[1], $_[2]);
	}
	else {
		read $_[0], $_[1], $_[2];
	}
}

sub _skip ($$) {
	if (my $gzstream = *{$_[0]}{SCALAR}) {
		$gzstream = $$gzstream;
		my $n = $_[1];
		while ($n > 0) {
			use List::Util qw(min);
			my $m = min($n, 8192);
			$gzstream->gzread(my $buf, $m) == $m or die;
			$n -= $m;
		}
	}
	else {
		seek $_[0], $_[1], 1;
	}
}

sub next {
	my $self = shift;
	my ($f, $fh, $n1, $n2, $n3) = @$self;
	if ($n3 > $n1) {
		_skip($fh, $n3 - $n1);
		$n1 = $n3;
	}
	_read($fh, my $cpio_header, 110) == 110
		or die "$f: bad cpio header";
	$n1 += 110;
	my ($magic, $ino, $mode, $uid, $gid, $nlink, $mtime, $size,
	$dev_major, $dev_minor, $rdev_major, $rdev_minor, $namelen, $checksum) =
		map hex, unpack "a6(a8)13", $cpio_header;
	$magic == 0x070701 or die "$f: bad cpio header magic";
	my $namesize = (($namelen + 1) & ~3) + 2;
	_read($fh, my $filename, $namesize) == $namesize
		or die "$f: bad cpio filename";
	$n1 += $namesize;
	substr $filename, $namelen, $namesize, "";
	chop($filename) eq "\0"
		or die "$f: bad cpio filename";
	$n2 = $n1 + $size;
	$n3 = ($n2 + 3) & ~3;
	warn "filename=$filename datapos=$n1 next=$n3" if $DEBUG;
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
	@_ == 3 or die "Usage: ENTRY->read(SCALAR,LENGTH)";
	my $self = shift;
	my $n = pop;
	my $cpio = $$self{_cpio};
	my ($f, $fh, $n1, $n2, $n3) = @$cpio;
	S_ISREG($$self{mode}) or die "$f: $$self{filename}: not regular file";
	use List::Util qw(min);
	$n = min($n, $n2 - $n1) or return 0;
	my $m = RPM::Payload::_read($fh, $_[0], $n)
		or die "$f: $$self{filename} read failed";
	$$cpio[2] += $m;
	return $m;
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
	*$method = sub { my $self = shift; $$self{$method}; };
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
