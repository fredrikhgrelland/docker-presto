job "presto-host" {
  type = "service"
  datacenters = ["dc1"]

  group "presto-host" {

    count = 1

    task "certificate-handler-coordinator" {
      lifecycle {
        hook = "prestart"
        sidecar = true
      }
      driver = "docker"
      config {
        image = "nginx:1.19"
        entrypoint = [
          "/bin/sh"]
        args = [
          "-c",
          "openssl pkcs12 -export -password pass:changeit -in /local/leaf.pem -inkey /local/leaf.key -certfile /local/roots.pem -out /alloc/presto.p12 && chmod +rx /alloc/presto.p12 && tail -f /dev/null"
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

    task "certificate-handler-worker" {
      lifecycle {
        hook = "prestart"
        sidecar = true
      }
      driver = "docker"
      config {
        image = "nginx:1.19"
        entrypoint = [
          "/bin/sh"]
        args = [
          "-c",
          "openssl pkcs12 -export -password pass:changeit -in /local/leaf.pem -inkey /local/leaf.key -certfile /local/roots.pem -out /alloc/presto.p12 && chmod +rx /alloc/presto.p12 && tail -f /dev/null"
        ]
      }
      template {
        data = "{{ with printf \"%s\" (or (env \"CONSUL_SERVICE\") \"worker\") | caLeaf }}{{ .CertPEM }}{{ end }}"
        destination = "local/leaf.pem"
      }
      template {
        data = "{{ with printf \"%s\" (or (env \"CONSUL_SERVICE\") \"worker\") | caLeaf }}{{ .PrivateKeyPEM }}{{ end }}"
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
        hostname = "presto"
        image = "fredrikhgrelland/presto:latest"
        network_mode = "host"
        volumes = [
          "local/presto/jvm.config:/lib/presto/default/etc/jvm.config",
          "local/presto/config.properties:/lib/presto/default/etc/config.properties",
          "local/presto/certificate-authenticator.properties:/lib/presto/default/etc/certificate-authenticator.properties",
          "local/presto/log.properties:/lib/presto/default/etc/log.properties",
        ]
      }

      template {
        data = <<EOF
CONSUL_SERVICE=presto
CONSUL_HTTP_ADDR=http://127.0.0.1:8500
CONSUL_TOKEN=master
EOF
        destination = "${NOMAD_SECRETS_DIR}/.env"
        env = true
      }
      template {
        data = <<EOF
certificate-authenticator.name=consulconnect
EOF
        destination = "local/presto/certificate-authenticator.properties"
      }
      template {
        data = <<EOF
node.id={{ env "NOMAD_ALLOC_ID" }}
node.environment={{ env "NOMAD_JOB_NAME" | replaceAll "-" "_" }}
node.internal-address=127.0.0.1

coordinator=true
node-scheduler.include-coordinator=false
discovery-server.enabled=true
discovery.uri=https://{{ env "NOMAD_ADDR_coordinator" }}

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
http-server.https.port={{ env "NOMAD_PORT_coordinator" }}
http-server.https.keystore.path=/alloc/presto.p12
http-server.https.keystore.key=changeit

# This is the same jks, but it will not do the consul connect authorization in intra cluster communication
internal-communication.https.required=true
internal-communication.shared-secret=asdasdsadafdsa
internal-communication.https.keystore.path=/alloc/presto.p12
internal-communication.https.keystore.key=changeit

query.client.timeout=5m
query.min-expire-age=30m
EOF
        destination = "local/presto/config.properties"
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
        destination = "local/presto/jvm.config"
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
com.ning.http.client=DEBUG
io.prestosql.server.PluginManager=DEBUG
io.prestosql.presto.server.security=DEBUG
io.prestosql.plugin.certificate.consulconnect=DEBUG

EOF
        destination = "local/presto/log.properties"
      }

      service {
        name = "presto"
        port = "coordinator"
      }
      resources {
        memory = 2048
        network {
          port "coordinator" {}
        }
      }
    }

    task "worker" {
      driver = "docker"

      config {
        hostname = "worker"
        image = "fredrikhgrelland/presto:latest"
        network_mode = "host"
        volumes = [
          "local/presto/jvm.config:/lib/presto/default/etc/jvm.config",
          "local/presto/config.properties:/lib/presto/default/etc/config.properties",
          "local/presto/certificate-authenticator.properties:/lib/presto/default/etc/certificate-authenticator.properties",
          "local/presto/log.properties:/lib/presto/default/etc/log.properties",
        ]
      }

      template {
        data = <<EOF
CONSUL_SERVICE=presto
CONSUL_HTTP_ADDR=http://127.0.0.1:8500
CONSUL_TOKEN=master
EOF
        destination = "${NOMAD_SECRETS_DIR}/.env"
        env = true
      }
      template {
        data = <<EOF
certificate-authenticator.name=consulconnect
EOF
        destination = "local/presto/certificate-authenticator.properties"
      }
      template {
        data = <<EOF
node.id={{ env "NOMAD_ALLOC_ID" }}
node.environment={{ env "NOMAD_JOB_NAME" | replaceAll "-" "_" }}
node.internal-address=127.0.0.1

coordinator=false
discovery.uri=https://{{ env "NOMAD_ADDR_coordinator_coordinator" }}

discovery.http-client.https.hostname-verification=false
node-manager.http-client.https.hostname-verification=false
exchange.http-client.https.hostname-verification=false

http-server.http.enabled=false
http-server.authentication.type=CERTIFICATE
http-server.https.enabled=true
http-server.https.port={{ env "NOMAD_PORT_worker" }}
http-server.https.keystore.path=/alloc/presto.p12
http-server.https.keystore.key=changeit

# This is the same jks, but it will not do the consul connect authorization in intra cluster communication
internal-communication.https.required=true
internal-communication.shared-secret=asdasdsadafdsa
internal-communication.https.keystore.path=/alloc/presto.p12
internal-communication.https.keystore.key=changeit

query.client.timeout=5m
query.min-expire-age=30m
EOF
        destination = "local/presto/config.properties"
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
        destination = "local/presto/jvm.config"
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
com.ning.http.client=DEBUG
io.prestosql.server.PluginManager=DEBUG
io.prestosql.presto.server.security=DEBUG
io.prestosql.plugin.certificate.consulconnect=DEBUG

EOF
        destination = "local/presto/log.properties"
      }
      service {
        name = "worker"
        port = "worker"
      }
      resources {
        memory = 2048
        network {
          port "worker" {}
        }
      }
    }
  }
}
