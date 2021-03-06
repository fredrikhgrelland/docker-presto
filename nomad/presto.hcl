job "presto" {
  type = "service"
  datacenters = ["dc1"]

  group "coordinator" {

    count = 1

    network {
      mode = "bridge"
      port "connect" {
        to = -1
      }
    }

    service {
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "hive-metastore"
              local_bind_port  = 9083
            }
            upstreams {
              destination_name = "minio"
              local_bind_port  = 9000
            }
          }
        }
      }
    }
    service {
      name = "presto"
      port = "connect"
    }

    task "certificate-handler" {
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
      driver = "docker"
      config {
        #image = "fredrikhgrelland/presto:latest"
        image = "local/presto:local"
        entrypoint = ["/bin/sh"]
        args = [
          "-c", "openssl pkcs12 -export -password pass:changeit -in /local/leaf.pem -inkey /local/leaf.key -certfile /local/leaf.pem -out /local/presto.p12; keytool -noprompt -importkeystore -srckeystore /local/presto.p12 -srcstoretype pkcs12 -destkeystore /local/presto.jks -deststoretype JKS -deststorepass changeit -srcstorepass changeit; keytool -noprompt -import -trustcacerts -keystore /local/presto.jks -storepass changeit -alias Root -file /local/roots.pem; keytool -noprompt -importkeystore -srckeystore /local/presto.jks -destkeystore /alloc/presto.jks -deststoretype pkcs12 -deststorepass changeit -srcstorepass changeit; tail -f /dev/null"
        ]
      }
      template {
        data = "{{ with printf \"%s\" (or (env \"CONSUL_SERVICE\") \"presto\") | caLeaf }}{{ .CertPEM }}{{ end }}"
        destination = "local/leaf.pem"
      }
      template {
        data = "{{ with printf \"%s\" (or (env \"CONSUL_SERVICE\") \"presto\") | caLeaf }}{{ .PrivateKeyPEM }}{{ end }}"
        destination = "local/leaf.key"
      }
      template {
        data = "{{ range caRoots }}{{ .RootCertPEM }}{{ end }}"
        destination = "local/roots.pem"
      }
    }
    task "coordinator" {
      driver = "docker"

      config {
        #image = "fredrikhgrelland/presto:latest"
        image = "local/presto:local"
        volumes = [
          "local/presto/jvm.config:/lib/presto/default/etc/jvm.config",
          "local/presto/config.properties:/lib/presto/default/etc/config.properties",
          "local/presto/certificate-authenticator.properties:/lib/presto/default/etc/certificate-authenticator.properties",
          "local/presto/log.properties:/lib/presto/default/etc/log.properties",
          "local/hive.properties:/lib/presto/default/etc/catalog/hive.properties",
          "local/hosts:/etc/hosts",
        ]
      }
      template {
        data = <<EOH
          hive.s3.aws-access-key=minioadmin
          hive.s3.aws-secret-key=minioadmin
          hive.s3.endpoint=http://{{ env "NOMAD_UPSTREAM_ADDR_minio" }}
          connector.name=hive-hadoop2
          hive.metastore.uri=thrift://{{ env "NOMAD_UPSTREAM_ADDR_hive_metastore" }}
          hive.s3select-pushdown.enabled=true
          hive.non-managed-table-writes-enabled=true
          hive.s3.max-connections=5000
          hive.s3.max-error-retries=100
          hive.s3.socket-timeout=31m
          hive.s3.ssl.enabled=false
          hive.metastore-timeout=1m
          hive.s3.path-style-access=true
          EOH
        destination = "/local/hive.properties"
      }
      template {
        #https://github.com/hashicorp/consul/blob/87f32c8ba661760501e09b72078b0476d332a10d/agent/connect/common_names.go#L27
        data = <<EOF
127.0.0.1 presto localhost
10.0.3.10 prestoworkers
EOF
        destination = "local/hosts"
      }
      template {
        data = <<EOF
CONSUL_SERVICE=presto
CONSUL_HTTP_ADDR=http://10.0.3.10:8500
CONSUL_TOKEN=master
EOF
        destination = "${NOMAD_SECRETS_DIR}/.env"
        env = true
      }
      template {
        data = <<EOF
certificate-authenticator.name=consulconnect
EOF
        destination   = "local/presto/certificate-authenticator.properties"
      }
      template {
        data = <<EOF
node.id={{ env "NOMAD_ALLOC_ID" }}
node.environment={{ env "NOMAD_JOB_NAME" | replaceAll "-" "_" }}
node.internal-address=presto

coordinator=true
node-scheduler.include-coordinator=true
discovery-server.enabled=true
discovery.uri=https://localhost:{{ env "NOMAD_PORT_connect" }}

discovery.http-client.https.hostname-verification=false
dynamic.http-client.https.hostname-verification=false
failure-detector.http-client.https.hostname-verification=false
memoryManager.http-client.https.hostname-verification=false
node-manager.http-client.https.hostname-verification=false
exchange.http-client.https.hostname-verification=false
scheduler.http-client.https.hostname-verification=false
workerInfo.http-client.https.hostname-verification=false

http-server.http.enabled=false
http-server.authentication.type=CERTIFICATE
http-server.https.enabled=true
http-server.https.port={{ env "NOMAD_PORT_connect" }}
http-server.https.keystore.path=/alloc/presto.jks
http-server.https.keystore.key=changeit

# This is the same jks, but it will not do the consul connect authorization in intra cluster communication
internal-communication.https.required=true
internal-communication.shared-secret=asdasdsadafdsa
internal-communication.https.keystore.path=/alloc/presto.jks
internal-communication.https.keystore.key=changeit

query.client.timeout=5m
query.min-expire-age=30m
EOF
        destination   = "local/presto/config.properties"
      }
      template {
        data = <<EOF
-server
-Xmx1768M
-XX:-UseBiasedLocking
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:+UseGCOverheadLimit
-XX:+ExitOnOutOfMemoryError
-XX:ReservedCodeCacheSize=256M
-Djdk.attach.allowAttachSelf=true
-Djdk.nio.maxCachedBufferSize=2000000
EOF
        destination   = "local/presto/jvm.config"
      }
      template {
        data = <<EOF
#
# WARNING
# ^^^^^^^
# This configuration file is for development only and should NOT be used
# in production. For example configuration, see the Presto documentation.
#

io.prestosql=DEBUG
com.sun.jersey.guice.spi.container.GuiceComponentProviderFactory=DEBUG
io.prestosql.server.PluginManager=DEBUG
io.prestosql.presto.server.security=DEBUG
io.prestosql.plugin.certificate.consulconnect=DEBUG
io.airlift=DEBUG

EOF
        destination   = "local/presto/log.properties"
      }
      resources {
        memory = 2048
      }
    }
  }

  ####################### WORKER 1 #####################################

  group "workers" {

    count = 1

    network {
      mode = "bridge"
      port "connect" {
        to = -1
      }
    }

    service {
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "hive-metastore"
              local_bind_port  = 9083
            }
            upstreams {
              destination_name = "minio"
              local_bind_port  = 9000
            }
          }
        }
      }
    }
    service {
      name = "prestoworkers"
      port = "connect"
    }

    task "certificate-handler" {
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
      driver = "docker"
      config {
        #image = "fredrikhgrelland/presto:latest"
        image = "local/presto:local"
        entrypoint = ["/bin/sh"]
        args = [
          "-c", "openssl pkcs12 -export -password pass:changeit -in /local/leaf.pem -inkey /local/leaf.key -certfile /local/leaf.pem -out /local/presto.p12; keytool -noprompt -importkeystore -srckeystore /local/presto.p12 -srcstoretype pkcs12 -destkeystore /local/presto.jks -deststoretype JKS -deststorepass changeit -srcstorepass changeit; keytool -noprompt -import -trustcacerts -keystore /local/presto.jks -storepass changeit -alias Root -file /local/roots.pem; keytool -noprompt -importkeystore -srckeystore /local/presto.jks -destkeystore /alloc/presto.jks -deststoretype pkcs12 -deststorepass changeit -srcstorepass changeit; tail -f /dev/null"
        ]
      }
      template {
        data = "{{with caLeaf \"prestoworkers\" }}{{ .CertPEM }}{{ end }}"
        destination = "local/leaf.pem"
      }
      template {
        data = "{{with caLeaf \"prestoworkers\" }}{{ .PrivateKeyPEM }}{{ end }}"
        destination = "local/leaf.key"
      }
      template {
        data = "{{ range caRoots }}{{ .RootCertPEM }}{{ end }}"
        destination = "local/roots.pem"
      }
    }
    task "worker" {
      driver = "docker"

      config {
        #image = "fredrikhgrelland/presto:latest"
        image = "local/presto:local"
        volumes = [
          "local/presto/jvm.config:/lib/presto/default/etc/jvm.config",
          "local/presto/config.properties:/lib/presto/default/etc/config.properties",
          "local/presto/certificate-authenticator.properties:/lib/presto/default/etc/certificate-authenticator.properties",
          "local/presto/log.properties:/lib/presto/default/etc/log.properties",
          "local/hive.properties:/lib/presto/default/etc/catalog/hive.properties",
          "local/hosts:/etc/hosts",
        ]
      }
      template {
        data = <<EOH
          hive.s3.aws-access-key=minioadmin
          hive.s3.aws-secret-key=minioadmin
          hive.s3.endpoint=http://{{ env "NOMAD_UPSTREAM_ADDR_minio" }}
          connector.name=hive-hadoop2
          hive.metastore.uri=thrift://{{ env "NOMAD_UPSTREAM_ADDR_hive_metastore" }}
          hive.s3select-pushdown.enabled=true
          hive.non-managed-table-writes-enabled=true
          hive.s3.max-connections=5000
          hive.s3.max-error-retries=100
          hive.s3.socket-timeout=31m
          hive.s3.ssl.enabled=false
          hive.metastore-timeout=1m
          hive.s3.path-style-access=true
          EOH
        destination = "/local/hive.properties"
      }
      template {
        #https://github.com/hashicorp/consul/blob/87f32c8ba661760501e09b72078b0476d332a10d/agent/connect/common_names.go#L27
        data = <<EOF
127.0.0.1 prestoworkers localhost
10.0.3.10 presto
EOF
        destination = "local/hosts"
      }
      template {
        data = <<EOF
CONSUL_SERVICE=prestoworkers
CONSUL_HTTP_ADDR=http://10.0.3.10:8500
CONSUL_TOKEN=master
EOF
        destination = "${NOMAD_SECRETS_DIR}/.env"
        env = true
      }
      template {
        data = <<EOF
certificate-authenticator.name=consulconnect
EOF
        destination   = "local/presto/certificate-authenticator.properties"
      }
      template {
        data = <<EOF
node.id={{ env "NOMAD_ALLOC_ID" }}
node.environment={{ env "NOMAD_JOB_NAME" | replaceAll "-" "_" }}
node.internal-address=prestoworkers

coordinator=false
discovery.uri=https://{{ range  $i, $s := service "presto" }}{{ if eq $i 0 }}{{ .Address }}:{{ .Port }}{{ end }}{{ end }}

discovery.http-client.https.hostname-verification=false
node-manager.http-client.https.hostname-verification=false
exchange.http-client.https.hostname-verification=false

http-server.http.enabled=false
http-server.authentication.type=CERTIFICATE
http-server.https.enabled=true
http-server.https.port={{ env "NOMAD_PORT_connect" }}
http-server.https.keystore.path=/alloc/presto.jks
http-server.https.keystore.key=changeit

# This is the same jks, but it will not do the consul connect authorization in intra cluster communication
internal-communication.https.required=true
internal-communication.shared-secret=asdasdsadafdsa
internal-communication.https.keystore.path=/alloc/presto.jks
internal-communication.https.keystore.key=changeit

query.client.timeout=5m
query.min-expire-age=30m
EOF
        destination   = "local/presto/config.properties"
      }
      template {
        data = <<EOF
-server
-Xmx1768M
-XX:-UseBiasedLocking
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:+UseGCOverheadLimit
-XX:+ExitOnOutOfMemoryError
-XX:ReservedCodeCacheSize=256M
-Djdk.attach.allowAttachSelf=true
-Djdk.nio.maxCachedBufferSize=2000000
EOF
        destination   = "local/presto/jvm.config"
      }
      template {
        data = <<EOF
#
# WARNING
# ^^^^^^^
# This configuration file is for development only and should NOT be used
# in production. For example configuration, see the Presto documentation.
#

io.prestosql=DEBUG
com.sun.jersey.guice.spi.container.GuiceComponentProviderFactory=DEBUG
io.prestosql.server.PluginManager=DEBUG
io.prestosql.presto.server.security=DEBUG
io.prestosql.plugin.certificate.consulconnect=DEBUG
io.airlift=DEBUG

EOF
        destination   = "local/presto/log.properties"
      }
      resources {
        memory = 2048
      }
    }
  }
}
