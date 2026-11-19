FROM parent

RUN apt-get update && \
    apt-get install -y --no-install-recommends g++ make ccache ethtool curl && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/ldconfig/aux-cache && \
    mkdir -p /var/run/runtime && \
    chmod 775 /var/run/runtime
