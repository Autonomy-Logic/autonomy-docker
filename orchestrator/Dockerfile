FROM parent

RUN apt-get update && \
    apt-get install -y --no-install-recommends libsrtp2-1 && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/ldconfig/aux-cache
