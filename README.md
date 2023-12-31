# Zelta Replication Suite

This suite of tools provides a streamlined approach for managing ZFS snapshot replication across various systems. It consists of three main components: ```zmatch```, ```zpull```, and ```zelta```, each designed to handle specific aspects of the snapshot replication process.

The goal of this proeject will be to keep the tools as simple as possible with intutive defaults and few options. zelta works best as a cron job in conjuction with a snapshot creating and pruning utility like the excellent [zfsnap](https://github.com/zfsnap/zfsnap).

### Quick Start: Setup

`pkg install -y git; git clone https://github.com/bellhyve/zelta.git ; cd zelta; cp zmatch zelta zpull /usr/local/bin/`

## Quick Start Example: Back up your computer

After adding a drive and creating a pool called "opt", e.g., `zpool create opt ada0`:

```sh
zfs snapshot -r zroot@`date -j +%Y-%m-%d_%H.%M.%S`
zpull zroot opt/Backups/myboot
```

zpull will respond with something like: `14 streams received, 4317983224 bytes copied in 14 seconds`


## zmatch

```zmatch``` is a tool used for comparing ZFS datasets. It identifies the most recent matching snapshot between two given volumes. This tool is particularly useful for determining if datasets are in sync and identifying the latest common snapshot.

```sh
zmatch [source_volume] [target_volume]
```

## zpull

```zpull``` handles the actual replication of ZFS snapshots between a source and a target volume. It uses the output of ```zmatch``` to determine which snapshots need to be sent and then performs the replication efficiently.

```sh
zpull [source_volume] [target_volume]
```

## zelta

```zelta``` orchestrates the replication process, coordinating between ```zmatch``` and ```zpull```. It reads from a configuration file to determine which datasets to replicate and where to replicate them.

The configuration file ```zelta.conf``` allows you to specify various parameters, including backup roots, sites, hosts, and datasets. Each section of the config file defines a specific aspect of the replication process.

Example Configuration (```zelta.conf```):yaml
```yaml
BACKUP_ROOT: outerspace/Backups
PREFIX: 0

DAL1:
  fw1.dal1:
  - fw1-dal1-boot/jail/webproxy_bts
  host00.bts:
  - ssd00/jail/app.adagesource.com
  ...
```

In ```zelta.conf```, you can define different sites, each with specific hosts and datasets. The ```PREFIX``` parameter in the configuration file specifies how many parent levels of the source dataset should be included in the target dataset name.

Usage:sh
```sh
zelta [optional_site_host_or_dataset]
```

If one or more arguments are provided, ```zelta``` will limit the replication process to the specified sites, hosts, or datasets. If no argument is provided, it will process according to the settings in the configuration file.

Installation and Requirements
- The scripts are compatible with awk using the NetBSD extensions
- Awk is hardcoded to /usr/bin/awk.
- Install the scripts (zmatch, zpull, zelta) /usr/local/bin/ or any directory in PATH
- For zpull, make sure ssh auth and "zfs allow" is correctly configured for target systems.
- For zelta, edit /usr/local/etc/zelta/zelta.conf to match your environment and replication needs.

## Future

The previous version of the zelta sutie used internally includes a zeport reporting tool and a zmove configuration editing tool, and need to be refactored before being added to this repository.

## Contributing

Contributions to enhance these tools are welcome. Please feel free to submit pull requests or open issues for any bugs or feature requests.
