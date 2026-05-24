FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    automake \
    autoconf \
    build-essential \
    default-jre \
    g++-multilib \
    gcc-multilib \
    gawk \
    git \
    less \
    make \
    nescc \
    python2 \
    python2-dev \
    python-is-python2 \
    software-properties-common \
    sudo \
    swig \
    tinyos-tools \
    vim \
    && rm -rf /var/lib/apt/lists/*

ENV TINYOS_ROOT_DIR=/usr/share/tinyos
ENV TOSROOT=/usr/share/tinyos
ENV TOSDIR=/usr/share/tinyos/tos
ENV CLASSPATH=/usr/share/java/tinyos.jar:.
ENV MAKERULES=/usr/share/tinyos/Makefile.include
ENV PYTHONPATH=/usr/lib/python2.7/dist-packages:/usr/share/tinyos/support/sdk/python:/workspace

WORKDIR /workspace

COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]
