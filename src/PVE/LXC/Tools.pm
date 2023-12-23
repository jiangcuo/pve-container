# Module for lxc related functionality used mostly by our hooks.
package PVE::LXC::Tools;

use strict;
use warnings;

use PVE::SafeSyslog;

# LXC introduced an `lxc.hook.version` property which allows hooks to be executed in different
# manners. The old way passes a lot of stuff as command line parameter, the new way passes
# environment variables.
#
# This is supposed to be a common entry point for hooks, consuming the parameters passed by lxc and
# passing them on to a subroutine in a defined way.
sub lxc_hook($$&) {
    my ($expected_type, $expected_section, $code) = @_;

    my ($ct_name, $section, $type);
    my $namespaces = {};
    my $args;

    my $version = $ENV{LXC_HOOK_VERSION} // '0';
    if ($version eq '0') {
	# Old style hook:
	$ct_name = shift @ARGV;
	$section = shift @ARGV;
	$type = shift @ARGV;

	if (!defined($ct_name) || !defined($section) || !defined($type)) {
	    die "missing hook parameters, expected to be called by lxc as hook\n";
	}

	if ($ct_name !~ /^\d+$/ || $section ne $expected_section || $type ne $expected_type) {
	    return;
	}

	if ($type eq 'stop') {
	    foreach my $ns (@ARGV) {
		if ($ns =~ /^([^:]+):(.+)$/) {
		    $namespaces->{$1} = $2;
		} else {
		    die "unrecognized 'stop' hook parameter: $ns\n";
		}
	    }
	} elsif ($type eq 'clone') {
	    $args = [@ARGV];
	}
    } elsif ($version eq '1') {
	$ct_name = $ENV{LXC_NAME}
	    or die "missing LXC_NAME environment variable\n";
	$section = $ENV{LXC_HOOK_SECTION}
	    or die "missing LXC_HOOK_SECTION environment variable\n";
	$type = $ENV{LXC_HOOK_TYPE}
	    or die "missing LXC_HOOK_TYPE environment variable\n";

	if ($ct_name !~ /^\d+$/ || $section ne $expected_section || $type ne $expected_type) {
	    return;
	}

	foreach my $var (keys %$ENV) {
	    if ($var =~ /^LXC_([A-Z]+)_NS$/) {
		$namespaces->{lc($1)} = $ENV{$1};
	    }
	}
    } else {
	die "lxc.hook.version $version not supported!\n";
    }

    my $logid = $ENV{PVE_LOG_ID} || "pve-lxc-hook-$section-$type";
    initlog($logid);

    my $common_vars = {
	ROOTFS_MOUNT => ($ENV{LXC_ROOTFS_MOUNT} or die "missing LXC_ROOTFS_MOUNT env var\n"),
	ROOTFS_PATH => ($ENV{LXC_ROOTFS_PATH} or die "missing LXC_ROOTFS_PATH env var\n"),
	CONFIG_FILE => ($ENV{LXC_CONFIG_FILE} or die "missing LXC_CONFIG_FILE env var\n"),
    };
    if (defined(my $target = $ENV{LXC_TARGET})) {
	$common_vars->{TARGET} = $target;
    }

    $code->($ct_name, $common_vars, $namespaces, $args);
}

sub for_devices {
    my ($devlist_file, $vmid, $code) = @_;

    my $fd;

    if (! open $fd, '<', $devlist_file) {
	exit 0 if $!{ENOENT}; # If the list is empty the file might not exist.
	die "failed to open device list: $!\n";
    }

    while (defined(my $line = <$fd>)) {
	if ($line !~ m@^(b|c):(\d+):(\d+):/dev/(\S+)\s*$@) {
	    warn "invalid $devlist_file entry: $line\n";
	    next;
	}

	my ($type, $major, $minor, $dev) = ($1, $2, $3, $4);

	# Don't break out of $root/dev/
	if ($dev =~ /\.\./) {
	    warn "skipping illegal device node entry: $dev\n";
	    next;
	}

	# Never expose /dev/loop-control
	if ($major == 10 && $minor == 237) {
	    warn "skipping illegal device entry (loop-control) for: $dev\n";
	    next;
	}

	$code->($type, $major, $minor, $dev);
    }
    close $fd;
}

sub for_current_passthrough_mounts($&) {
    my ($vmid, $code) = @_;

    my $devlist_file = "/var/lib/lxc/$vmid/passthrough/mounts";

    if (-e $devlist_file) {
	for_devices($devlist_file, $vmid, $code);
    } else {
	# Fallback to the old device list file in case a package upgrade
	# occurs between lxc-pve-prestart-hook and now.
	for_devices("/var/lib/lxc/$vmid/devices", $vmid, $code);
    }
}

sub for_current_passthrough_devices($&) {
    my ($vmid, $code) = @_;

    my $passthrough_devlist_file = "/var/lib/lxc/$vmid/passthrough/devices";
    for_devices($passthrough_devlist_file, $vmid, $code);
}

sub cgroup_do_write($$) {
    my ($path, $value) = @_;
    my $fd;
    if (!open($fd, '>', $path)) {
	warn "failed to open cgroup file $path: $!\n";
	return 0;
    }
    if (!defined syswrite($fd, $value)) {
	warn "failed to write value $value to cgroup file $path: $!\n";
	return 0;
    }
    close($fd);
    return 1;
}

# Tries to the architecture of an executable file based on its ELF header.
sub detect_elf_architecture {
    my ($elf_fn) = @_;

    # see https://en.wikipedia.org/wiki/Executable_and_Linkable_Format

    my $supported_elf_machine = {
	0x03 => 'i386',
	0x3e => 'amd64',
	0x28 => 'armhf',
	0xb7 => 'arm64',
	0xf3 => 'riscv',
    };

    my $detect_arch = sub {
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

	if ($arch eq 'riscv') {
	    if ($class eq 1) {
		$arch = 'riscv32';
	    } elsif ($class eq 2) {
		$arch = 'riscv64';
	    } else {
		die "'$elf_fn' has invalid class '$class'!\n";
	    }
	}

	return $arch;
    };

    my $arch = eval { PVE::Tools::run_fork_with_timeout(10, $detect_arch); };
    my $err = $@ // "timeout\n";
    die $err if !defined($arch);

    return $arch;
}

1;
