%define dist RPM-Payload
Name: perl-%dist
Version: 0.02
Release: alt1

Summary: Simple in-memory access to RPM archive
License: GPL or Artistic
Group: Development/Perl

URL: %CPAN %dist
Source: %dist-%version.tar

BuildArch: noarch

# Automatically added by buildreq on Mon Feb 16 2009
BuildRequires: perl-devel

%description
no description

%prep
%setup -q -n %dist-%version

%build
%perl_vendor_build

%install
%perl_vendor_install

%files
%perl_vendor_privlib/RPM*

%changelog
* Mon Feb 16 2009 Alexey Tourbin <at@altlinux.ru> 0.02-alt1
- use rpm2cpio, to handle LZMA payloads

* Sat Mar 18 2006 Alexey Tourbin <at@altlinux.ru> 0.01-alt1
- initial revision
