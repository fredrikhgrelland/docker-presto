FROM prestosql/presto:334

# Allow buildtime config of PRESTO_VERSION
ARG PRESTO_CONSUL_CONNECT_VERSION
# Set PRESTO_VERSION from arg if provided at build, env if provided at run, or default
ENV PRESTO_CONSUL_CONNECT_VERSION=${PRESTO_CONSUL_CONNECT_VERSION:-1.0.5}
ENV PRESTO_CONSUL_CONNECT_URL https://oss.sonatype.org/service/local/repositories/releases/content/io/github/gugalnikov/presto-consul-connect/$PRESTO_CONSUL_CONNECT_VERSION/presto-consul-connect-$PRESTO_CONSUL_CONNECT_VERSION-jar-with-dependencies.jar

#Add ca_certificates to the image ( if trust is not allready added through base image )
COPY ca_certificates/* /usr/local/share/ca-certificates/
COPY lib/http-client-custom.jar /usr/lib/presto/lib/http-client-0.197.jar
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
	&& rm -rf /var/tmp/*

WORKDIR /lib/presto/default/etc
