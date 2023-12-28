package PVE::LXC::Setup::Plugin;

# the abstract Plugin interface which user should restrict themself too

use strict;
use warnings;

use PVE::Tools;
use Carp;

sub new {
    my ($class, $conf, $rootdir, $os_release) = @_;
    croak "implement me in sub-class\n";
}

sub template_fixup {
    my ($self, $conf) = @_;
    croak "implement me in sub-class\n";
}

sub setup_network {
    my ($self, $conf) = @_;
    croak "implement me in sub-class\n";
}

sub set_hostname {
    my ($self, $conf) = @_;
    croak "implement me in sub-class\n";
}

sub set_dns {
    my ($self, $conf) = @_;
    croak "implement me in sub-class\n";
}

sub set_timezone {
    my ($self, $conf) = @_;
    croak "implement me in sub-class\n";
}

sub setup_init {
    my ($self, $conf) = @_;
    croak "implement me in sub-class\n";
}

sub set_user_password {
    my ($self, $conf, $user, $opt_password) = @_;
    croak "implement me in sub-class\n";
}

sub unified_cgroupv2_support {
    my ($self, $init) = @_;
    croak "implement me in sub-class\n";
}

sub get_ct_init_path {
    my ($self) = @_;
    croak "implement me in sub-class\n";
}

sub ssh_host_key_types_to_generate {
    my ($self) = @_;
    croak "implement me in sub-class\n";
}

sub detect_architecture {
    my ($self) = @_;
    # see https://en.wikipedia.org/wiki/Executable_and_Linkable_Format
    my $supported_elf_machine = {
	0x03 => 'i386',
	0x3e => 'amd64',
	0x28 => 'armhf',
	0xb7 => 'arm64',
	0x2 => 'loongarch64',
    };

    my $elf_fn = '/bin/sh'; # '/bin/sh' is POSIX mandatory
    my $detect_arch = sub {
	# chroot avoids a problem where we check the binary of the host system
	# if $elf_fn is an absolut symlink (e.g. $rootdir/bin/sh -> /bin/bash)
	open(my $fh, "<", $elf_fn) or die "open '$elf_fn' failed: $!\n";
	binmode($fh);

	my $length = read($fh, my $data, 20) or die "read failed: $!\n";

	# 4 bytes ELF magic number and 1 byte ELF class, padding, machine
	my ($magic, $class, undef, $machine) = unpack("A4CA12n", $data);

	die "'$elf_fn' does not resolve to an ELF!\n"
	    if (!defined($class) || !defined($magic) || $magic ne "\177ELF");

	my $arch = $supported_elf_machine->{$machine};
	die "'$elf_fn' has unknown ELF machine '$machine'!\n"
	    if !defined($arch);

	return $arch;
    };

    my $arch = eval { PVE::Tools::run_fork_with_timeout(5, $detect_arch) };
    if (my $err = $@) {
	$arch = 'loongarch64';
	print "Architecture detection failed: $err\nFalling back to loongarch64.\n" .
	      "Use `pct set VMID --arch ARCH` to change.\n";
    } else {
	print "Detected container architecture: $arch\n";
    }

    return $arch;
}

# hooks

sub pre_start_hook {
    my ($self, $conf) = @_;
    croak "implement me in sub-class";
}

sub post_clone_hook {
    my ($self, $conf) = @_;
    croak "implement me in sub-class";
}

sub post_create_hook {
    my ($self, $conf, $root_password, $ssh_keys) = @_;
    croak "implement me in sub-class";
}

1;
