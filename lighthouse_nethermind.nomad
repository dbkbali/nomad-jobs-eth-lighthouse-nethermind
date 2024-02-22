job "eth-lighthouse-nethermind" {
  datacenters = ["dc1"]

  type = "service"

  group "clients" {
    constraint {
      attribute = "${node.unique.name}"
      value     = "nomad_client_1"
    }

    network {
      mode = "host"

      # Execution Engine ports
      port "p2p" { static = "63000" }
      port "rpcN" { static = "63001" }
      port "authRpc" { static = "63002" }
      port "promN" { static = "63003" }
      # TODO: determine nethermind port flags

      # Consensus Node Ports - lighthouse clients
      port "p2pC" { static = "64000" }  # 9000
      port "p2pu" { static = "64001" }  # 9001
      port "http" { static = "64002" }  # 5052
      port "promL" { static = "64003" } # 5054

    }

    restart {
      attempts = 3
      delay    = "15s"
      interval = "10m"
      mode     = "fail"
    }


    task "nethermind" {
      driver = "docker"

      service {
        name    = "eth-execution"
        tags    = ["eth-execution", "nethermind"]
        address = "${attr.unique.network.ip-address}"

        meta {
          PortP2P     = "${NOMAD_HOST_PORT_p2p}" # 30303
          PortProm    = "${NOMAD_HOST_PORT_promN}"
          PortRpc     = "${NOMAD_HOST_PORT_rpcN}"    # 8545
          PortAuthRpc = "${NOMAD_HOST_PORT_authRpc}" # 8551
          TaskName    = "${NOMAD_TASK_NAME}"
        }
      }

      template {
        data        = <<EOH
          {{- key "jwtSecret" -}}
        EOH
        destination = "secrets/jwt_secret"
      }

      config {
        image = "nethermind/nethermind:latest"
        args = [
          "--config=holesky",
          "--datadir=/nethermind",
          "--Init.WebSocketsEnabled=true",
          "--Network.DiscoveryPort=${NOMAD_PORT_p2p}",
          "--Network.P2PPort=${NOMAD_PORT_p2p}",
          "--JsonRpc.Enabled=true",
          "--JsonRpc.Host=0.0.0.0",
          "--JsonRpc.Port=${NOMAD_PORT_rpcN}",
          "--JsonRpc.WebSocketsPort=${NOMAD_PORT_rpcN}",
          "--JsonRpc.EngineHost=0.0.0.0",
          "--JsonRpc.EnginePort=${NOMAD_PORT_authRpc}",
          "--JsonRpc.EnabledModules=[Admin,Net,Eth,Subscribe,Engine,Web3,Client]",
          "--JsonRpc.EngineEnabledModules=[Net,Eth,Subscribe,Engine,Web3,Client]",
          "--Metrics.ExposePort=${NOMAD_PORT_promN}",
          "--JsonRpc.JwtSecretFile=/holesky/.eth/jwt.hex"
          // "--log=DEBUG"
        ]

        ports = ["p2p", "rpcN", "authRpc", "promN"]

        mount {
          type   = "volume"
          target = "/nethermind"
          source = "eth-holesky-nethermind0"
        }

        mount {
          type   = "bind"
          target = "/holesky/.eth/jwt.hex"
          source = "secrets/jwt_secret"
        }

        mount {
          type     = "bind"
          target   = "/etc/localtime"
          source   = "/etc/localtime"
          readonly = true
        }
      }
      resources {
        cpu    = 8000
        memory = 16000
      }
    }


    task "lighthouse_beacon_node" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      service {
        name    = "eth-consensus"
        tags    = ["eth-consensus", "beacon-node", "lighthouse"]
        address = "${attr.unique.network.ip-address}"
        meta {
          # sets the tpc/udp ports to listen on udp ports are set to
          # the tcp port is set to this value and the udp port is set to this value + 1
          # can also add IP6 listeners - see documentation https://lighthouse-book.sigmaprime.io/help_bn.html         
          PortP2PC = "${NOMAD_HOST_PORT_p2pC}" # 9000
          PortP2Pu = "${NOMAD_HOST_PORT_p2pu}" # 9001`
          # sets the http port for the beacon node api
          PortHttp = "${NOMAD_HOST_PORT_http}" # 5052
          PortProm = "${NOMAD_HOST_PORT_promL}"

          TaskName = "${NOMAD_TASK_NAME}"
        }
      }

      template {
        data        = <<EOH
          {{- key "jwtSecret" -}}
        EOH
        destination = "secrets/jwt_secret"
      }


      config {
        image = "sigp/lighthouse:latest"
        args = [
          "lighthouse",
          "beacon_node",
          "--network=holesky",
          "--datadir=/lighthouse",
          "--execution-endpoint=http://${attr.unique.network.ip-address}:${NOMAD_PORT_authRpc}",
          "--execution-jwt=/holesky/.eth/jwt.hex",
          "--listen-address=0.0.0.0",
          "--port=${NOMAD_PORT_p2pC}",
          "--quic-port=${NOMAD_PORT_p2pu}",
          "--http",
          // "--http-allow-origin=*",
          "--http-address=0.0.0.0",
          "--http-port=${NOMAD_PORT_http}",
          "--metrics",
          "--metrics-address=0.0.0.0",
          "--metrics-port=${NOMAD_PORT_promL}",
          "--purge-db",
          "--debug-level=debug",
          "--checkpoint-sync-url=https://checkpoint-sync.holesky.ethpandaops.io"
        ]

        ports = ["p2pC", "p2pu", "http", "promL"]

        mount {
          type   = "volume"
          target = "/lighthouse"
          source = "eth-holesky-lighthouse0"
        }

        mount {
          type   = "bind"
          target = "/holesky/.eth/jwt.hex"
          source = "secrets/jwt_secret"
        }

        mount {
          type     = "bind"
          target   = "/etc/localtime"
          source   = "/etc/localtime"
          readonly = true
        }
      }
      resources {
        cpu    = 4000
        memory = 12000
      }
    }
  }
}
