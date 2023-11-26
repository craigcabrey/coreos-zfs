ARG FEDORA_VERSION=latest

FROM quay.io/fedora/fedora-coreos:stable as kernel-query
#We can't use the `uname -r` as it will pick up the host kernel version
RUN rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' > /kernel-version.txt

# Using https://openzfs.github.io/openzfs-docs/Developer%20Resources/Custom%20Packages.html
FROM quay.io/fedora/fedora:${FEDORA_VERSION} as builder
COPY --from=kernel-query /kernel-version.txt /kernel-version.txt
WORKDIR /etc/yum.repos.d
RUN curl -L -O https://src.fedoraproject.org/rpms/fedora-repos/raw/f$(rpm -E %fedora)/f/fedora-updates-archive.repo && \
    sed -i 's/enabled=AUTO_VALUE/enabled=true/' fedora-updates-archive.repo
RUN dnf install -y jq dkms gcc make autoconf automake libtool rpm-build libtirpc-devel libblkid-devel \
    libuuid-devel libudev-devel openssl-devel zlib-devel libaio-devel libattr-devel elfutils-libelf-devel \
    kernel-$(cat /kernel-version.txt) kernel-modules-$(cat /kernel-version.txt) kernel-devel-$(cat /kernel-version.txt) \
    python3 python3-devel python3-setuptools python3-cffi libffi-devel git ncompress libcurl-devel
WORKDIR /

RUN curl -H "Accept: application/vnd.github+json" https://api.github.com/repos/openzfs/zfs/releases/latest | jq -r .tag_name > /zfs.txt
RUN curl -o zfs.tar.gz -L https://github.com/openzfs/zfs/releases/download/$(cat /zfs.txt)/$(cat /zfs.txt).tar.gz && \
    tar xzf zfs.tar.gz && mv $(cat /zfs.txt) zfs
WORKDIR /zfs
RUN ./configure -with-linux=/usr/src/kernels/$(cat /kernel-version.txt)/ -with-linux-obj=/usr/src/kernels/$(cat /kernel-version.txt)/ \
    && make -j1 rpm-utils rpm-kmod

FROM quay.io/fedora/fedora-coreos:stable
COPY --from=builder /zfs/*.rpm /
RUN rm -f /*.src.rpm
RUN rpm-ostree install lm_sensors tmux
# For the example we install all RPMS (debug, test, etc).
# In real use cases probably just want the module rpm.
RUN rpm-ostree install /*.rpm && \
    # we don't want any files on /var
    rm -rf /var/lib/pcp && \
    ostree container commit 
