FROM ubuntu:14.04
MAINTAINER Dan Liew <daniel.liew@imperial.ac.uk>

ENV DEBIAN_FRONTEND noninteractive

# Install prerequisites.
RUN apt-get update && \
    apt-get install -y software-properties-common unzip wget curl gdebi-core && \
    apt-get clean

# FIXME: Docker doesn't currently offer a way to
# squash the layers from within a Dockerfile so
# the resulting image is unnecessarily large!

ENV LLVM_VERSION=3.4 \
    SOLVERS=STP:Z3 \
    STP_VERSION=2.1.2 \
    DISABLE_ASSERTIONS=0 \
    ENABLE_OPTIMIZED=1 \
    KLEE_UCLIBC=klee_uclibc_v1.0.0 \
    KLEE_SRC=/home/klee/klee_src \
    ELINA_SRC=/home/klee/elina \ 
    APRON_SRC=/home/klee/apron \
    COVERAGE=0 \
    BUILD_DIR=/home/klee/klee_build \
    USE_CMAKE=1 \
    ASAN_BUILD=0 \
    UBSAN_BUILD=0

# Install Java
RUN apt-get update && \
    apt-get install -y software-properties-common 
RUN add-apt-repository ppa:openjdk-r/ppa
RUN apt-get update
RUN apt-get install -y openjdk-8-jdk

# Install Eclipse for C++  
RUN cd /tmp && \
    wget -q 'http://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/kepler/SR2/eclipse-cpp-kepler-SR2-linux-gtk-x86_64.tar.gz&r=1' -O /tmp/eclipse.tar.gz && \
    echo 'Installing Eclipse' && \
    tar -xzf /tmp/eclipse.tar.gz && \
    mv eclipse /usr/lib/ && \
    rm -rf /tmp/*

# Install SSH server.
RUN apt-get update && \
    apt-get install -y openssh-server && \
    apt-get clean
RUN mkdir /var/run/sshd
EXPOSE 22

ADD initialize /usr/local/bin/initialize

RUN chmod +x /usr/local/bin/initialize

CMD /usr/local/bin/initialize

# Install fish.
RUN apt-get update && \
    apt-get install -y sudo man-db fish && \
    apt-get clean

RUN apt-get update && \
    apt-get -y --no-install-recommends install \
        clang-${LLVM_VERSION} \
        llvm-${LLVM_VERSION} \
        llvm-${LLVM_VERSION}-dev \
        llvm-${LLVM_VERSION}-runtime \
        llvm \
        libcap-dev \
        git \
        subversion \
        cmake \
        make \
        libboost-program-options-dev \
        python3 \
        python3-dev \
        python3-pip \
        perl \
        flex \
        bison \
        libncurses-dev \
        zlib1g-dev \
        patch \
        wget \
        unzip \
        binutils && \
    pip3 install -U lit tabulate && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3 50 && \
    ( wget -O - http://download.opensuse.org/repositories/home:delcypher:z3/xUbuntu_14.04/Release.key | apt-key add - ) && \
    echo 'deb http://download.opensuse.org/repositories/home:/delcypher:/z3/xUbuntu_14.04/ /' >> /etc/apt/sources.list.d/z3.list && \
    apt-get update
    
# Install Elina prerequisites
RUN cd /tmp && \
    wget -c https://gmplib.org/download/gmp/gmp-6.1.2.tar.xz -O gmp.tar.xz && \
    tar -xf gmp.tar.xz && \
    cd gmp-* && \
    ./configure --enable-cxx && \
    make && \
    make install && \
    cd /tmp && \
    wget -c http://www.mpfr.org/mpfr-current/mpfr-4.0.1.tar.xz -O mpfr.tar.xz && \
    tar -xf mpfr.tar.xz && \
    cd mpfr-* && \
    ./configure && \
    make && \
    make install && \
    rm -rf /tmp/*
        
# Install Apron prerequisites
RUN apt-get update && \
    apt-get -y install build-essential
    
    
# Create ``klee`` user for container with password ``klee``.
# and give it password-less sudo access (temporarily so we can use the TravisCI scripts)
RUN useradd -m klee && \
    echo klee:klee | chpasswd && \
    cp /etc/sudoers /etc/sudoers.bak && \
    echo 'klee  ALL=(root) NOPASSWD: ALL' >> /etc/sudoers
USER klee
WORKDIR /home/klee


# Clone the klee repository
RUN mkdir ${KLEE_SRC}
RUN cd ${KLEE_SRC} && \
    git clone https://github.com/alebugariu/klee.git . && \
    cd ..

# Clone and install ELINA    
RUN mkdir ${ELINA_SRC} && \
    cd ${ELINA_SRC} && \
    git clone https://github.com/alebugariu/ELINA.git . 
    
USER root
RUN cd ${ELINA_SRC} && \
    make && \
    make install

USER klee   
  
# Clone and install APRON    
RUN mkdir ${APRON_SRC} && \
    cd ${APRON_SRC} && \
    git clone https://github.com/alebugariu/apron.git . 

USER root
RUN cd ${APRON_SRC} && \
    make && \
    make install

USER klee 

# Set klee user to be owner
RUN sudo chown --recursive klee: ${KLEE_SRC}
RUN sudo chown --recursive klee: ${ELINA_SRC}
RUN sudo chown --recursive klee: ${APRON_SRC}

# Create build directory
RUN mkdir -p ${BUILD_DIR}

# Build/Install SMT solvers (use TravisCI script)
RUN cd ${BUILD_DIR} && ${KLEE_SRC}/.travis/solvers.sh

# Install testing utils (use TravisCI script)
RUN cd ${BUILD_DIR} && mkdir test-utils && cd test-utils && \
    ${KLEE_SRC}/.travis/testing-utils.sh

# FIXME: All these hacks need to be removed. Once we no longer
# need to support KLEE's old build system they can be removed.

# FIXME: This is a nasty hack so KLEE's configure and build finds
# LLVM's headers file, libraries and tools
RUN sudo mkdir -p /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin && \
    sudo ln -s /usr/bin/llvm-config /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/llvm-config && \
    sudo ln -s /usr/bin/llvm-dis /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/llvm-dis && \
    sudo ln -s /usr/bin/llvm-as /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/llvm-as && \
    sudo ln -s /usr/bin/llvm-link /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/llvm-link && \
    sudo ln -s /usr/bin/llvm-ar /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/llvm-ar && \
    sudo ln -s /usr/bin/opt /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/opt && \
    sudo ln -s /usr/bin/lli /usr/lib/llvm-${LLVM_VERSION}/build/Release/bin/lli && \
    sudo mkdir -p /usr/lib/llvm-${LLVM_VERSION}/build/include && \
    sudo ln -s /usr/include/llvm-${LLVM_VERSION}/llvm /usr/lib/llvm-${LLVM_VERSION}/build/include/llvm && \
    sudo ln -s /usr/include/llvm-c-${LLVM_VERSION}/llvm-c /usr/lib/llvm-${LLVM_VERSION}/build/include/llvm-c && \
    for static_lib in /usr/lib/llvm-${LLVM_VERSION}/lib/*.a ; do sudo ln -s ${static_lib} /usr/lib/`basename ${static_lib}`; done

# FIXME: This is **really gross**. The Official Ubuntu LLVM packages don't ship
# with ``FileCheck`` or the ``not`` tools so we have to hack building these
# into KLEE's build system in order for the tests to pass
RUN [ "X${USE_CMAKE}" != "X1" ] && ( cd ${KLEE_SRC}/tools && \
    for tool in FileCheck not; do \
        svn export \
        http://llvm.org/svn/llvm-project/llvm/branches/release_34/utils/${tool} ${tool} ; \
        sed -i 's/^USEDLIBS.*$/LINK_COMPONENTS = support/' ${tool}/Makefile; \
    done && \
    sed -i '0,/^PARALLEL_DIRS/a PARALLEL_DIRS += FileCheck not' Makefile ) || echo "Skipping hack"

# FIXME: The current TravisCI script expects clang-${LLVM_VERSION} to exist
RUN sudo ln -s /usr/bin/clang /usr/bin/clang-${LLVM_VERSION} && \
    sudo ln -s /usr/bin/clang++ /usr/bin/clang++-${LLVM_VERSION}

# Build KLEE (use TravisCI script)
RUN cd ${BUILD_DIR} && ${KLEE_SRC}/.travis/klee.sh

# Revoke password-less sudo and Set up sudo access for the ``klee`` user so it
# requires a password
USER root
RUN mv /etc/sudoers.bak /etc/sudoers && \
    echo 'klee  ALL=(root) ALL' >> /etc/sudoers
USER klee

# Add KLEE binary directory to PATH
RUN [ "X${USE_CMAKE}" != "X1" ] && \
  (echo 'export PATH=$PATH:'${BUILD_DIR}'/klee/Release+Asserts/bin' >> /home/klee/.bashrc) || \
  (echo 'export PATH=$PATH:'${BUILD_DIR}'/klee/bin' >> /home/klee/.bashrc)

# Link klee to /usr/bin so that it can be used by docker run
USER root
RUN [ "X${USE_CMAKE}" != "X1" ] && \
  (for executable in ${BUILD_DIR}/klee/Release+Asserts/bin/* ; do ln -s ${executable} /usr/bin/`basename ${executable}`; done) || \
  (for executable in ${BUILD_DIR}/klee/bin/* ; do ln -s ${executable} /usr/bin/`basename ${executable}`; done)

# Link klee to the libkleeRuntest library needed by docker run
RUN [ "X${USE_CMAKE}" != "X1" ] && (ln -s ${BUILD_DIR}/klee/Release+Asserts/lib/libkleeRuntest.so /usr/lib/libkleeRuntest.so.1.0) || echo "Skipping hack"

USER root