package PVE::LXC::Setup::Anolis;

use strict;
use warnings;

use PVE::LXC::Setup::CentOS;
use base qw(PVE::LXC::Setup::CentOS);

sub new {
    my ($class, $conf, $rootdir, $os_release) = @_;

    my $version = $os_release->{VERSION_ID};

    my $self = { conf => $conf, rootdir => $rootdir, version => $version };

    $conf->{ostype} = "anolis";

    return bless $self, $class;
}

sub template_fixup {
    my ($self, $conf) = @_;

    $self->remove_lxc_name_from_etc_hosts();
    $self->setup_systemd_disable_static_units(['dev-mqueue.mount']);
}

sub setup_init {
    my ($self, $conf) = @_;
    $self->setup_container_getty_service($conf);
    $self->setup_systemd_preset();
}

1;