FROM parent

RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 libpython3.13 && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/ldconfig/aux-cache
