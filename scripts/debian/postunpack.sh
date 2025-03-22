#!/bin/bash
set -e

DIRS_TO_TRIM="/usr/share/man
/var/cache/apt
/var/cache/ldconfig/aux-cache
/var/lib/apt/lists
/usr/share/locale
/var/log
/usr/share/info
/dev
"

echo "Applying docker-specific tweaks"
# These are copied from the docker contrib/mkimage/debootstrap script.
# Modifications:
#  - remove `strings` check for applying the --force-unsafe-io tweak.
#     This was sometimes wrongly detected as not applying, and we aren't
#     interested in building versions that this guard would apply to,
#     so simply apply the tweak unconditionally.

# prevent init scripts from running during install/update
echo >&2 "+ echo exit 101 > '/usr/sbin/policy-rc.d'"
cat > "/usr/sbin/policy-rc.d" <<-'EOF'
	#!/bin/sh
	# For most Docker users, "apt-get install" only happens during "docker build",
	# where starting services doesn't work and often fails in humorous ways. This
	# prevents those failures by stopping the services from attempting to start.
	exit 101
EOF
chmod +x "/usr/sbin/policy-rc.d"

# prevent upstart scripts from running during install/update
(
	set -x
	dpkg-divert --local --rename --add /sbin/initctl
	cp -a "/usr/sbin/policy-rc.d" "/sbin/initctl"
	sed -i 's/^exit.*/exit 0/' "/sbin/initctl"
)

# this file is one APT creates to make sure we don't "autoremove" our currently
# in-use kernel, which doesn't really apply to debootstraps/Docker images that
# don't even have kernels installed
rm -f "/etc/apt/apt.conf.d/01autoremove-kernels"

# force dpkg not to call sync() after package extraction (speeding up installs)
echo >&2 "+ echo force-unsafe-io > '/etc/dpkg/dpkg.cfg.d/docker-apt-speedup'"
cat > "/etc/dpkg/dpkg.cfg.d/docker-apt-speedup" <<-'EOF'
# For most Docker users, package installs happen during "docker build", which
# doesn't survive power loss and gets restarted clean afterwards anyhow, so
# this minor tweak gives us a nice speedup (much nicer on spinning disks,
# obviously).
force-unsafe-io
EOF

if [ -d "/etc/apt/apt.conf.d" ]; then
	# _keep_ us lean by effectively running "apt-get clean" after every install
	aptGetClean='"rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true";'
	echo >&2 "+ cat > '/etc/apt/apt.conf.d/docker-clean'"
	cat > "/etc/apt/apt.conf.d/docker-clean" <<-EOF
		# Since for most Docker users, package installs happen in "docker build" steps,
		# they essentially become individual layers due to the way Docker handles
		# layering, especially using CoW filesystems.  What this means for us is that
		# the caches that APT keeps end up just wasting space in those layers, making
		# our layers unnecessarily large (especially since we'll normally never use
		# these caches again and will instead just "docker build" again and make a brand
		# new image).
		# Ideally, these would just be invoking "apt-get clean", but in our testing,
		# that ended up being cyclic and we got stuck on APT's lock, so we get this fun
		# creation that's essentially just "apt-get clean".
		DPkg::Post-Invoke { ${aptGetClean} };
		APT::Update::Post-Invoke { ${aptGetClean} };
		Dir::Cache::pkgcache "";
		Dir::Cache::srcpkgcache "";
		# Note that we do realize this isn't the ideal way to do this, and are always
		# open to better suggestions (https://github.com/docker/docker/issues).
	EOF

	# remove apt-cache translations for fast "apt-get update"
	echo >&2 "+ echo Acquire::Languages 'none' > '/etc/apt/apt.conf.d/docker-no-languages'"
	cat > "/etc/apt/apt.conf.d/docker-no-languages" <<-'EOF'
		# In Docker, we don't often need the "Translations" files, so we're just wasting
		# time and space by downloading them, and this inhibits that.  For users that do
		# need them, it's a simple matter to delete this file and "apt-get update". :)
		Acquire::Languages "none";
	EOF

	echo >&2 "+ echo Acquire::GzipIndexes 'true' > '/etc/apt/apt.conf.d/docker-gzip-indexes'"
	cat > "/etc/apt/apt.conf.d/docker-gzip-indexes" <<-'EOF'
		# Since Docker users using "RUN apt-get update && apt-get install -y ..." in
		# their Dockerfiles don't go delete the lists files afterwards, we want them to
		# be as small as possible on-disk, so we explicitly request "gz" versions and
		# tell Apt to keep them gzipped on-disk.
		# For comparison, an "apt-get update" layer without this on a pristine
		# "debian:wheezy" base image was "29.88 MB", where with this it was only
		# "8.273 MB".
		Acquire::GzipIndexes "true";
		Acquire::CompressionTypes::Order:: "gz";
	EOF

	# update "autoremove" configuration to be aggressive about removing suggests deps that weren't manually installed
	echo >&2 "+ echo Apt::AutoRemove::SuggestsImportant 'false' > '/etc/apt/apt.conf.d/docker-autoremove-suggests'"
	cat > "/etc/apt/apt.conf.d/docker-autoremove-suggests" <<-'EOF'
		# Since Docker users are looking for the smallest possible final images, the
		# following emerges as a very common pattern:
		#   RUN apt-get update \
		#       && apt-get install -y <packages> \
		#       && <do some compilation work> \
		#       && apt-get purge -y --auto-remove <packages>
		# By default, APT will actually _keep_ packages installed via Recommends or
		# Depends if another package Suggests them, even and including if the package
		# that originally caused them to be installed is removed.  Setting this to
		# "false" ensures that APT is appropriately aggressive about removing the
		# packages it added.
		# https://aptitude.alioth.debian.org/doc/en/ch02s05s05.html#configApt-AutoRemove-SuggestsImportant
		Apt::AutoRemove::SuggestsImportant "false";
	EOF
fi

cat > "/usr/sbin/install_packages" <<-'EOF'
#!/bin/sh
set -e
set -u
export DEBIAN_FRONTEND=noninteractive
n=0
max=2
until [ $n -gt $max ]; do
    set +e
    (
      apt-get update -qq &&
      apt-get install -y --no-install-recommends "$@"
    )
    CODE=$?
    set -e
    if [ $CODE -eq 0 ]; then
        break
    fi
    if [ $n -eq $max ]; then
        exit $CODE
    fi
    echo "apt failed, retrying"
    n=$(($n + 1))
done
rm -r /var/lib/apt/lists /var/cache/apt/archives
EOF
chmod 0755 "/usr/sbin/install_packages"

echo "Trimming down"
for DIR in $DIRS_TO_TRIM; do
  rm -rf "$DIR"/* || true
done
# Remove /usr/share/doc, but leave copyright files to be sure that we
# comply with all licenses.
# `mindepth 2` as we only want to remove files within the per-package
# directories. Crucially some packages use a symlink to another package
# dir (e.g. libgcc1), and we don't want to remove those.
find "/usr/share/doc" -mindepth 2 -not -name copyright -not -type d -delete
find "/usr/share/doc" -mindepth 1 -type d -empty -delete
