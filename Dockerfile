FROM prestosql/presto:334

# Allow buildtime config of PRESTO_VERSION
ARG PRESTO_CONSUL_CONNECT_VERSION
# Set PRESTO_VERSION from arg if provided at build, env if provided at run, or default
ENV PRESTO_CONSUL_CONNECT_VERSION=${PRESTO_CONSUL_CONNECT_VERSION:-1.0.5}
ENV PRESTO_CONSUL_CONNECT_URL https://oss.sonatype.org/service/local/repositories/releases/content/io/github/gugalnikov/presto-consul-connect/$PRESTO_CONSUL_CONNECT_VERSION/presto-consul-connect-$PRESTO_CONSUL_CONNECT_VERSION-jar-with-dependencies.jar
ENV AIRLIFT_HTTP_CLIENT https://pkg.githubusercontent.com/272688510/f4f59600-baaf-11ea-828f-22544efa5270?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIWNJYAX4CSVEH53A%2F20200630%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20200630T120506Z&X-Amz-Expires=300&X-Amz-Signature=4051c88cb97c4c4d1a78f974628b27c578f257cc3be5d71d0bbb3a264b84cc11&X-Amz-SignedHeaders=host&actor_id=40291976&repo_id=0&response-content-disposition=filename%3Dhttp-client-0.199.jar&response-content-type=application%2Foctet-stream

#Add ca_certificates to the image ( if trust is not allready added through base image )
COPY ca_certificates/* /usr/local/share/ca-certificates/
WORKDIR /var/tmp

#Install certs
RUN \
    #Update CA_Certs
    update-ca-certificates 2>/dev/null || true && echo "NOTE: CA warnings suppressed." \
    #Test download ( does ssl trust work )
    && curl -s -I -o /dev/null $PRESTO_CONSUL_CONNECT_URL || echo -e "\n###############\nERROR: You are probably behind a corporate proxy. Add your custom ca .crt in the ca_certificates docker build folder\n###############\n" \
    #Download and unpack plugin
    && mkdir -p /usr/lib/presto/plugin/consulconnect \
    && curl -s -L $PRESTO_CONSUL_CONNECT_URL -o /usr/lib/presto/plugin/consulconnect/presto-consul-connect-$PRESTO_CONSUL_CONNECT_VERSION.jar \
    #Download airlift patched lib
    && curl -s -L $AIRLIFT_HTTP_CLIENT -o /usr/lib/presto/lib/http-client-0.197.jar \
    && rm -rf /var/tmp/*

WORKDIR /lib/presto/default/etc
