# ClamAV in Docker

> IMPORTANT: This readme is for the Debian-based `clamav-debian` Docker image
> which is a work-in-progress that may eventually replace the Alpine-based
> `clamav` Docker image.
>
> `clamav-debian` images are multi-arch images with supported platforms.**

ClamAV can be run within a Docker container. This provides isolation from other
processes by running it in a containerized environment. If new or unfamiliar
with Docker, containers or cgroups see [docker.com](https://www.docker.com).

## The official images on Docker Hub

ClamAV Debian-based image tags
[on Docker Hub](https://hub.docker.com/r/clamav/clamav-debian) follow this
naming convention:

  - `clamav/clamav-debian:<version>`: A release preloaded with signature
    databases.

    Using this container will save the ClamAV project some bandwidth.
    Use this if you will keep the image around so that you don't download the
    entire database set every time you start a new container. Updating with
    FreshClam from existing databases set does not use much data.

  - `clamav/clamav-debian:<version>_base`: A release with no signature
    databases.

    Use this container **only** if you mount a volume in your container under
    `/var/lib/clamav` to persist your signature database databases.
    This method is the best option because it will reduce data costs for ClamAV
    and for the Docker registry, but it does require advanced familiarity with
    Linux and Docker.

    > _Caution_: Using this image without mounting an existing database
    directory will cause FreshClam to download the entire database set each
    time you start a new container.

The `<version>` may be one of three things:

1. A **feature version** in the form `X.Y`.

   For example: `0.105` points to the latest revision of the latest image for
   the ClamAV 0.105 feature release.

   Docker image tags for feature versions will be updated to the latest
   revision of the latest patch version image.

   > *Tip*: Selecting the ClamAV image tag by feature version is the best
   > option for stability and security.

2. A **patch version** in the form `X.Y.Z`.

   For example: `0.105.1` represents the latest revision of the 0.105.1 image.

   Docker image tags for the most recent patch version will be updated to the
   latest image revision.

   > *Note*: Once a newer patch version exists, the tag for the previous patch
   > version will no longer be updated for security issues in the base image.

3. A **patch version plus build revision** in the form `X.Y.Z-R`.

   For example `0.105.1-3` represents the third revision of the 0.105.1 image.

   New revisions are created to fix problems with Docker-specific features, and
   to patch security issues found in the base image.

   Once built, an image tag with a `-R` suffix will never be updated.

   > *Important*: You should never select a tag with a `-R` suffix for use in
   > production, but it may be useful for historical reference.

You can use the `unstable` version (i.e. `clamav/clamav-debian:unstable` or
`clamav/clamav-debian:unstable_base`) to try the latest from our development
branch.

## Building the ClamAV image

While it is recommended to pull the image from our
[Docker Hub registry](https://hub.docker.com/r/clamav/clamav-debian), some may
want to build the image locally instead.

To do so, you must get a copy of the ClamAV source code such as a gitclone of
the [ClamAV GitHub source](https://github.com/Cisco-Talos/clamav).
Then copy in the relevant `Dockerfile` and `scripts/` directory for your
ClamAV version from
[the ClamAV Docker repository](https://github.com/Cisco-Talos/clamav-docker/tree/main/clamav).
Then you can build your image. E.g.:
```bash
git clone https://github.com/Cisco-Talos/clamav-docker.git
git clone --depth 1 https://github.com/Cisco-Talos/clamav.git --branch rel/1.2

cp -r clamav-docker/clamav/1.2/debian/Dockerfile clamav/.
cp -r clamav-docker/clamav/1.2/debian/scripts clamav/.
cd clamav

docker build --tag "clamav:TICKET-123" .
```

## Running ClamD

To run `clamd` in a Docker container, first, an image either has to be built
or pulled from a Docker registry.

### Running ClamD using the official ClamAV images from Docker Hub

To pull the ClamAV "unstable" image from Docker Hub, run:

```bash
docker pull clamav/clamav-debian:unstable
```

> _Tip_: Substitute `unstable` with a different version as needed.

To pull _and run_ the official ClamAV images from the Docker Hub registry,
try the following command:

```bash
docker run \
    --interactive \
    --tty \
    --rm \
    --name "clam_container_01" \
    clamav/clamav-debian:unstable
```

The above creates an interactive container with the current TTY connected to
it. This is optional but useful when getting started as it allows one to
directly see the output and, in the case of `clamd`, send `ctrl-c` to close the
container. The `--rm` parameter ensures the container is cleaned up again after
it exits and the `--name` parameter names the container, so it can be
referenced through other (Docker) commands, as several containers of the same
image can be started without conflicts.

> _Note_: Pulling is not always required. `docker run` will pull the image
if it cannot be found locally. `docker run --pull always` will always pull
beforehand to ensure the most up-to-date container is being used.
Do not use `--pull always` with the larger ClamAV images.

> _Tip_: It's common to see `-it` instead of `--interactive --tty`.

In some situations it may be desirable to set (any of) the containers to a
specific timezone. The `--env` parameter can be used to set the `TZ` variable
to change the default of `Etc/UTC`.

### Running ClamD using a Locally Built Image

You can run a container using an image built locally
([see "Building the ClamAV Image"](#building-the-clamav-image)). Just run:
```bash
docker run -it --rm \
    --name "clam_container_01" \
    clamav:TICKET-123
```

### Persisting the virus database (volume)

The virus database in `/var/lib/clamav` is by default unique to each container
and thus is normally not shared. For simple setups this is fine, where only one
instance of `clamd` is expected to run in a dockerized environment. However
some use cases may want to efficiently share the database or at least persist
it across short-lived ClamAV containers.

To do so, you have two options:

1. Create a [Docker volume](https://docs.docker.com/storage/volumes/) using the
   `docker volume` command.
   Volumes are completely managed by Docker and are the best choice for
   creating a persistent database volume.

   For example, create a "clam_db" volume:
   ```bash
   docker volume create clam_db
   ```

   Then start one or more containers using this volume. The first container
   to use a new database volume will download the full database set. Subsequent
   containers will use the existing databases and may update them as needed:
   ```bash
   docker run -it --rm \
       --name "clam_container_01" \
       --mount source=clam_db,target=/var/lib/clamav \
       clamav/clamav-debian:unstable_base
   ```

2. Create a [Bind Mount](https://docs.docker.com/storage/bind-mounts/) that
   maps a file system directory to a path within the container.
   Bind Mounts depend on the directory structure, permissions, and operating
   system of the Docker host machine.

   Run the container with these arguments to mount the a directory from your host
   environment as a volume in the container.
   ```bash
       --mount type=bind,source=/path/to/databases,target=/var/lib/clamav
   ```

   When doing this, it's best to use the `<version>_base` image tags so as to
   save on bandwith. E.g.:
   ```bash
   docker run -it --rm \
       --name "clam_container_01" \
       --mount type=bind,source=/path/to/databases,target=/var/lib/clamav \
       clamav/clamav-debian:unstable_base
   ```

   > _Disclaimer_: When using a Bind Mount, the container's entrypoint script
   will change ownership of this directory to its "clamav" user. This enables
   FreshClam and ClamD with the required permissions to read and write to the
   directory, though these changes will also affect those files on the host.

If you're thinking about running multiple containers that share a single
database volume, [here are some notes on how this might work](#multiple-containers-sharing-the-same-mounted-databases).

### Running ClamD using non-root user using --user and --entrypoint

You can run a container using the non-root user "clamav" with the unprivileged entrypoint script. To do this with Docker, you will need to add these two options: `--user "clamav" --entrypoint /init-unprivileged`
For example:
```bash
docker run -it --rm \
      --user "clamav"
      --entrypoint /init-unprivileged
      --name "clam_container_01" \
    clamav/clamav-debian:unstable_base
```

## Running Clam(D)Scan

Scanning files using `clamscan` or `clamdscan` is possible in various ways with
Docker. This section briefly describes them, but the other sections of this
document are best read before hand to better understand some of the concepts.

One important aspect is however to realize that Docker by default does not have
access to any of the hosts files. And so to scan these within Docker, they need
to be mounted with a [bind mount](https://docs.docker.com/storage/bind-mounts/)
to be made accessible.

For example, running the container with these arguments ...
```bash
    --mount type=bind,source=/path/to/scan,target=/scandir
    --mount type=bind,source=/path/to/scan,target=/scandir
```
... would make the hosts file/directory `/path/to/scan` available in the
container as `/scandir` and thus invoking `clamscan` would thus be done on
`/scandir`.

Note that while technically possible to run either scanners via `docker exec`
this is not described as it is unlikely the container has access to the files
to be scanned.

### ClamScan

Using `clamscan` outside of the Docker container is how normally `clamscan` is
invoked. To make use of the available shared dockerized resources however, it
is possible to expose the virus database and share that for example. E.g. it
could be possible to run a Docker container with only the `freshclam` daemon
running, and share the virus database directory `/var/lib/clamav`. This could
be useful for file servers for example, where only `clamscan` is installed on
the host, and `freshclam` is managed in a Docker container.

> _Note_: Running the `freshclam` daemon separated from `clamd` is less
recommended, unless the `clamd` socket is shared with `freshclam` as
`freshclam` would not be able to inform `clamd` of database updates.

### Dockerized ClamScan

To run `clamscan` in a Docker container, the Docker container can be invoked
as:
```bash
docker run -it --rm \
    --mount type=bind,source=/path/to/scan,target=/scandir \
    clamav/clamav-debian:unstable \
    clamscan /scandir
```

However, this will use whatever signatures are found in the image, which may be
slightly out of date. If using `clamscan` in this way, it would be best to use
a [database volume](#running-with-a-mounted-database-directory-volume) that is
up-to-date so that you scan with the latest signatures. E.g.:
```bash
docker run -it --rm \
    --mount type=bind,source=/path/to/scan,target=/scandir \
    --mount type=bind,source=/path/to/databases,target=/var/lib/clamav \
    clamav/clamav-debian:unstable_base \
    clamscan /scandir
```

### ClamDScan

As with `clamscan`, `clamdscan` can also be run when installed on the host, by
connecting to the dockerized `clamd`. This can be done by either pointing
`clamdscan` to the exposed TCP/UDP port or unix socket.

### Dockerized ClamDScan

Running both `clamd` and `clamdscan` is also easily possible, as all that is
needed is the shared socket between the two containers. The only caveat here
is to:
1. mount the files to be scanned in the container that will run `clamd`, or
2. mount the files to be scanned in the container that will `clamdscan` run if
   using `clamdscan --stream`. The `--stream` option will be slower, but
   enables submitting files from a different machine on a network.

For example:
```bash
docker run -it --rm \
    --mount type=bind,source=/path/to/scan,target=/scandir \
    --mount type=bind,source=/var/lib/docker/data/clamav/sockets/,target=/run/clamav/
    clamav/clamav-debian:unstable
```

```bash
docker run -it --rm \
    --mount type=bind,source=/path/to/scan,target=/scandir \
    --mount type=bind,source=/var/lib/docker/data/clamav/sockets/,target=/run/clamav/
    clamav/clamav-debian:unstable_base \
    clamdscan /scandir
```

## Controlling the container

The ClamAV container actually runs both `freshclam` and `clamd` daemons by
default. Optionally available to the container is ClamAV's milter daemon.
To control the behavior of the services started within the container, the
following flags can be passed to the `docker run` command with the
`--env` (`-e`) parameter.

* CLAMAV_NO_CLAMD [true|**false**] Do not start `clamd`.
  (default: start `clamd`)
* CLAMAV_NO_FRESHCLAMD [true|**false**] Do not start the `freshclam` daemon.
  (default: start the `freshclam` daemon)
* CLAMAV_NO_MILTERD [**true**|false] Do not start the `clamav-milter` daemon.
  (default: start the `clamav-milter` daemon )
* CLAMD_STARTUP_TIMEOUT [integer] Seconds to wait for `clamd` to start.
  (default: 1800)
* FRESHCLAM_CHECKS [integer] `freshclam` daily update frequency.
  (default: once per day)

So to additionally also enable `clamav-milter`, the following flag can be
added:
```bash
    --env 'CLAMAV_NO_MILTERD=false'
```

Furthermore, all the configuration files that live in `/etc/clamav` can be
overridden by doing a volume-mount to the specific file. The following argument
can be added for this purpose. The example uses the entire configuration
directory, but this can be supplied multiple times if individual files deem to
be replaced.
```bash
    --mount type=bind,source=/full/path/to/clamav/,target/etc/clamav
```

> _Note_: Even when disabling the `freshclam` daemon, `freshclam` will always
run at least once during container startup if there is no virus database.
While not recommended, the virus database location itself `/var/lib/clamav/`
could be a persistent Docker volume. This however is slightly more advanced
and out of scope of this document.

### Automatically apply environment variables to configurations

You can configure both ClamAV and FreshClam dynamically by passing environment variables with specific prefixes when running the container. These variables will be automatically applied to the corresponding configuration files (`/etc/clamav/clamd.conf` for ClamAV and `/etc/clamav/freshclam.conf` for FreshClam).

#### Usage Example

To update ClamAV and FreshClam configurations using environment variables, run the container with the `-e` flag:

```bash
docker run --rm -e CLAMD_CONF_LogTime=no -e CLAMD_CONF_MaxThreads=5 -e FRESHCLAM_CONF_Checks=24 your-clamav-image
```

This will result in:
- `/etc/clamav/clamd.conf`:
```
LogTime no
MaxThreads 5
```
- `/etc/clamav/freshclam.conf`:
```
Checks 24
```

How It Works

- **Prefix**: Use `CLAMD_CONF_` for ClamAV settings and `FRESHCLAM_CONF_` for FreshClam settings.
- **Key/Value Mapping**: The part after the prefix is the configuration key, and the environment variable's value is applied in the respective config file.

For example, `CLAMD_CONF_LogTime=no` becomes `LogTime no` in `clamd.conf`, and `FRESHCLAM_CONF_Checks=24` becomes `Checks 24` in `freshclam.conf`.

The script processes these variables on container startup, replacing existing keys or appending new ones as needed.


## Connecting to the container

### Executing commands within a running container

To connect to a running ClamAV container, `docker exec` can be used to run a
command on an already running container. To do so, the name needs to be either
obtained from `docker ps` or supplied during container start via the `--name`
parameter. The most interesting command in this case can be `clamdtop`.
```bash
docker exec --interactive --tty "clamav_container_01" clamdtop
```
Alternatively, a shell can be started to inspect and run commands within the
container as well.
```bash
docker exec --interactive --tty "clamav_container_01" /bin/sh
```

### Unix sockets

The default socket for `clamd` is located inside the container as
`/tmp/clamd.sock` and can be connected to when exposed via a Docker
volume mount. To ensure, that `clamd` within the container can freely create
and remove the socket, the path for the socket is to be volume-mounted, to
expose it for others on the same host to use. The following volume can be used
for this purpose. Do ensure that the directory on the host actually exists and
clamav inside the container has permission to access it.
Caution is required when managing permissions, as incorrect permission could
open clamd for anyone on the host system.
```bash
    --mount type=bind,source=/var/lib/docker/data/clamav/sockets/,target=/run/clamav/
```

> _Note_: If you override the `LocalSocket` option with a custom `clamd.conf`
config file, then you may find the `clamd.sock` file in a different location.

With the socket exposed to the host, any other service can now talk to `clamd`
as well. If for example `clamdtop` where installed on the local host, calling
```bash
clamdtop "/var/lib/docker/data/clamav/sockets/clamd.sock"
```
should work just fine. Likewise, running `clamdtop` in a different container,
but sharing the socket will equally work. While `clamdtop` works well as an
example here, it is of course important to realize, this can also be used to
connect a mail server to `clamd`.

### TCP

ClamAV in the official Docker images is configured to listen for TCP
connections on these ports:
- `clamd`: 3310
- `clamav-milter`: 7357

While `clamd` and `clamav-milter` will listen on the above TCP ports, Docker
does not expose these by default to the host.
Only within containers can these ports be accessed. To expose, or "publish",
these ports to the host, and thus potentially over the (inter)network, the
`--publish` (or `--publish-all`) flag to `docker run` can be used. While more
advanced/secure mappings can be done as per documentation, the basic way is to
`--publish [<host_port>:]<container_port>` to make the port available to the
host.
```bash
    --publish 73310:3310 \
    --publish 7357
```
The above would thus publish the milter port 3310 as 73310 on the host and the
clamd port 7357 as a random to the host. The random port can be inspected via
`docker ps`.

> **Warning**: Extreme caution is to be taken when using `clamd` over TCP as
there are no protections on that level. All traffic is un-encrypted. Extra
care is to be taken when using TCP communications.

## Container ClamD health-check

Docker has the ability to run simple `ping` checks on services running inside
containers. If `clamd` is running inside the container, Docker will on
occasion send a `ping` to `clamd` on the default port and wait for the pong
from `clamd`. If `clamd` fails to respond, Docker will treat this as an error.
The healthcheck results can be viewed with `docker inspect`.

When the container starts up, the health-check also starts up. As loading the
virus database can take some time, there is a delay configured in the
`Dockerfile` to try and avoid this race condition.

## Performance

The performance impact of running `clamd` in Docker is negligible. Docker is
in essence just a wrapper around Linux's cgroups and cgroups can be thought of
as `chroot` or FreeBSD's `jail`. All code is executed on the host without any
translation. Docker does however do some isolation (through cgroups) to isolate
the various systems somewhat.

Of course, nothing in life is free, and so there is some overhead. Disk-space
being the most prominent one. The Docker container might have some duplication
of files for example between the host and the container. Furthermore, also RAM
memory may be duplicated for each instance, as there is no RAM-deduplication.
Both of which can be solved on the host however. A filesystem that supports
disk-deduplication and a memory manager that does RAM-deduplication.

The base container in itself is already very small ~16 MiB, at the time of this
writing, this cost is still very tiny, where the advantages are very much worth
the cost in general.

The container including the virus database is about ~240 MiB at the time of
this writing.

## Bandwidth

Please, be kind when using 'free' bandwidth, both for the virus databases
but also the Docker registry. Try not to download the entire database set or
the larger ClamAV database images on a regular basis.

## Advanced container configurations

### Multiple containers sharing the same mounted databases

You can run multiple containers that share the same database volume, but be
aware that the FreshClam daemons on each would compete to update the databases.
Most likely, one would update the databases and trigger its ClamD to load the
new databases, while the others would be oblivious to the new databases and
would continue with the old signatures until the next ClamD self-check.

This is fine, honestly. It won't take that long before the new signatures are
detected by ClamD's self-check and the databases are reloaded automatically.

To reload the databases on all ClamD containers immediately after an update,
you could [disable the FreshClam daemon](#controlling-the-container) when you
start the containers. Later, use `docker exec` to perform an update and again
as needed to have ClamD load updated databases.

> _Note_: This really isn't necessary but you could do this if you wish.

Exactly how you orchestrate this will depend on your environment.
You might do something along these lines:

1. Create a "clam_db" volume, if you don't already have one:
   ```bash
   docker volume create clam_db
   ```

2. Start your containers:
   ```bash
   docker run -it --rm \
       --name "clam_container_01" \
       --mount source=clam_db,target=/var/lib/clamav \
       --env 'CLAMAV_NO_FRESHCLAMD=true' \
       clamav/clamav-debian:unstable_base
   ```
   Wait for the first one to download the databases (if it's a new database
   volume). Then start more:
   ```bash
   docker run -it --rm \
       --name "clam_container_02" \
       --mount source=clam_db,target=/var/lib/clamav \
       --env 'CLAMAV_NO_FRESHCLAMD=true' \
       clamav/clamav-debian:unstable_base
   ```
3. Check for updates, as needed:
   ```bash
   docker exec -it clam_container_01 freshclam --on-update-execute=EXIT_1 || \
   if [ $? == 1 ]; then \
       docker exec -it clam_container_01 clamdscan --reload; \
       docker exec -it clam_container_02 clamdscan --reload; \
   fi
   ```
