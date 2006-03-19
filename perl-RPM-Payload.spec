%define dist RPM-Payload
Name: perl-%dist
Version: 0.01
Release: alt1

Summary: Simple in-memory access to RPM archive
License: GPL or Artistic
Group: Development/Perl

URL: %CPAN %dist
Source: %dist-%version.tar.gz

BuildArch: noarch

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
* Sat Mar 18 2006 Alexey Tourbin <at@altlinux.ru> 0.01-alt1
- initial revision
