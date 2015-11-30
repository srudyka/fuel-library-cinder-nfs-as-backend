notice('MODULAR: cinder_nfs_as_backend.pp')

include cinder::params

$nfs_server_hash = hiera('nfs-server')
$nfs_network_metadata = hiera('nodes')
$nfs_root_path   = $nfs_server_hash['export_path']
$nfs_nodes          = get_nodes_hash_by_roles(hiera('network_metadata'), ['nfs-server'])
$nfs_ips_hash = get_node_to_ipaddr_map_by_network_role($nfs_nodes, 'storage')
$nfs_share = values($nfs_ips_hash)
$mnt_dir = '/var/lib/cinder/mnt'



define nfs_server_backend::cinder_backend_nfs (
  $volume_backend_name  = $name,
  $nfs_servers          = [],
  $nfs_mount_options    = undef,
  $nfs_disk_util        = undef,
  $nfs_sparsed_volumes  = undef,
  $nfs_mount_point_base = undef,
  $nfs_shares_config    = '/etc/cinder/shares.conf',
  $nfs_used_ratio       = '0.95',
  $nfs_oversub_ratio    = '1.0',
  $extra_options        = {},
) {

  file {$nfs_shares_config:
    content => "${nfs_servers}:${nfs_root_path} \n",
    require => Package[$::cinder::params::volume_package],
    notify  => Service[$::cinder::params::volume_service]
  }

  cinder_config {
    "${name}/volume_backend_name":  value => $volume_backend_name;
    "${name}/volume_driver":        value =>
      'cinder.volume.drivers.nfs.NfsDriver';
    "${name}/nfs_shares_config":    value => $nfs_shares_config;
    "${name}/nfs_mount_options":    value => $nfs_mount_options;
    "${name}/nfs_disk_util":        value => $nfs_disk_util;
    "${name}/nfs_sparsed_volumes":  value => $nfs_sparsed_volumes;
    "${name}/nfs_mount_point_base": value => $nfs_mount_point_base;
    "${name}/nfs_used_ratio":       value => $nfs_used_ratio;
    "${name}/nfs_oversub_ratio":    value => $nfs_oversub_ratio;
  }

  create_resources('cinder_config', $extra_options)
}

class nfs_server_backend::install  {
  case $::operatingsystem {
    'Ubuntu', 'Debian': {
      $pkg_name_server      = 'nfs-kernel-server'
      $pkg_name_client      = 'nfs-common'
      $service_name         = 'nfs-kernel-server'
    }
    'CentOS', 'RedHat': {
      $pkg_name_server      = 'nfs-utils'
      $pkg_name_client      = 'nfs-utils'
      $service_name         = 'nfs'
    }
    default: {
      fail("unsuported osfamily ${::osfamily}, currently Debian and Redhat are the only supported platforms")
    }
  }

  package { $pkg_name_client:
    ensure => installed,
  }

  file { 'cinder_mnt':
    ensure  => directory,
    path    => $mnt_dir,
    group   => 'cinder',
    owner   => 'cinder',
    mode    => '0750',
  }

  nfs_server_backend::cinder_backend_nfs { 'DEFAULT' :
    volume_backend_name  => 'DEFAULT',
    nfs_mount_options    => '',
    nfs_disk_util        => '',
    nfs_sparsed_volumes  => 'True',
    nfs_mount_point_base => $mnt_dir,
    nfs_servers          => $nfs_share,
    nfs_shares_config    => '/etc/cinder/shares.conf',
    nfs_used_ratio       => '0.95',
    nfs_oversub_ratio    => '1.0',
    extra_options        => {},
  }

  package { $::cinder::params::volume_package:
    ensure => present,
  }
  service { $::cinder::params::volume_service:
    ensure => running,
  }

}

include  nfs_server_backend::install

#
# Exec is needed for changing owner folder inside of 
# cinder directory (/var/lib/cinder/mnt) because mounting NFS transfer 
# owner from NFS node mount point
#

exec { 'cinder_mnt chown':
    command  => "/bin/chown -R cinder:cinder ${mnt_dir}",
}
