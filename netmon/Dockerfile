FROM parent AS venv

ARG SOURCE_DATE_EPOCH

RUN --mount=type=bind,source=requirements.txt,target=/requirements.txt \
    apt-get update && \
    apt-get install -y --no-install-recommends python3-venv && \
    python3 -m venv /tmp/pip && \
    python3 -m venv --without-pip /opt/venv && \
    /tmp/pip/bin/pip --python /opt/venv/bin/python install --no-cache-dir --no-deps --only-binary :all: \
      --require-hashes -r /requirements.txt

FROM parent

RUN apt-get update && \
    apt-get install -y --no-install-recommends iproute2 iptables udhcpc procps && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/ldconfig/aux-cache

COPY --from=venv /opt/venv /opt/venv

ENV PATH=/opt/venv/bin:$PATH
