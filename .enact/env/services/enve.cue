package enve

import (
	"github.com/tonky/enve/schema/v1:schema"
	"github.com/tonky/enve/schema/v1/env:env"
	"github.com/tonky/enve/pkgs:pkgs"
)

#Pnpm: schema.#ArchiveBuildSpec & {
	pname:   "pnpm"
	version: "12.16.1"
	src: {
		"x86_64-linux":   "https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-12.16.1.tgz"
		"aarch64-linux":  "https://registry.npmjs.org/@pnpm/exe.linux-arm64/-/exe.linux-arm64-12.16.1.tgz"
		"x86_64-darwin":  "https://registry.npmjs.org/@pnpm/exe.darwin-x64/-/exe.darwin-x64-12.16.1.tgz"
		"aarch64-darwin": "https://registry.npmjs.org/@pnpm/exe.darwin-arm64/-/exe.darwin-arm64-12.16.1.tgz"
	}
	sha256: {
		"x86_64-linux":   "c9e9d45f7844d32f8717c4cac7c51aee2a7318cd56afd95eb253125b09d6bc32"
		"aarch64-linux":  "2895aac19e24b17e70d84ca57c934f5dfcee2292c6191fe3ac624706586b80cd"
		"x86_64-darwin":  "4401797300e857d9909574d7c5881c11ce0569078e614f7d5af40e7d1647f8b3"
		"aarch64-darwin": "dd8abd12b31406d7f8e0199b3a8fd8b3eb58fc22b7fb330d66af317d60393d25"
	}
	installPhase: "mkdir -p \"$out/bin\" && cp pnpm \"$out/bin/\" && chmod +x \"$out/bin/pnpm\""
}

#Clickhouse: schema.#ArchiveBuildSpec & {
	pname:   "clickhouse"
	version: "26.9.5.2"
	src: {
		"aarch64-darwin": "https://github.com/ClickHouse/ClickHouse/releases/download/v26.9.5.2-stable/clickhouse-macos-aarch64"
		"aarch64-linux":  "https://github.com/ClickHouse/ClickHouse/releases/download/v26.9.5.2-stable/clickhouse-common-static-26.9.5.2-arm64.tgz"
		"x86_64-linux":   "https://github.com/ClickHouse/ClickHouse/releases/download/v26.9.5.2-stable/clickhouse-common-static-26.9.5.2-amd64.tgz"
	}
	sha256: {
		"aarch64-darwin": "3ce96b2f4a946ed8210dd354aafee95d6158edc118c3a4d5cfd598b0f9593ffa"
		"aarch64-linux":  "fbee6f3e5578c3863850bde127a2e9803757f027af2fbe10449f73d1859925f0"
		"x86_64-linux":   "873c7a13d4421c89a625abd9ee28f5ef1c6388cfba907269206594a02f8e4ffc"
	}
	buildInputs: [{pname: "findutils"}]
	installPhase: """
		set -eu
		mkdir -p "$out/bin"
		cp "$(find "$src" -type f \\( -path "$src/clickhouse" -o -path '*/usr/bin/clickhouse' \\) | head -n 1)" "$out/bin/clickhouse"
		chmod 0755 "$out/bin/clickhouse"
		"$out/bin/clickhouse" --version
		for tool in server client local; do ln -s clickhouse "$out/bin/clickhouse-$tool"; done
		"""
}

#GolangMigrate: schema.#ArchiveBuildSpec & {
	pname:   "golang-migrate"
	version: "4.19.1"
	src: {
		"x86_64-linux":   "https://github.com/golang-migrate/migrate/releases/download/v4.19.1/migrate.linux-amd64.tar.gz"
		"aarch64-linux":  "https://github.com/golang-migrate/migrate/releases/download/v4.19.1/migrate.linux-arm64.tar.gz"
		"x86_64-darwin":  "https://github.com/golang-migrate/migrate/releases/download/v4.19.1/migrate.darwin-amd64.tar.gz"
		"aarch64-darwin": "https://github.com/golang-migrate/migrate/releases/download/v4.19.1/migrate.darwin-arm64.tar.gz"
	}
	sha256: {
		"x86_64-linux":   "2ac648fbd1b127b69ab5a7b33cf96212178f71e22379fc50573630c6f4c7ce18"
		"aarch64-linux":  "2fea2455c0f3f07cc3f4b98471c951ad1a716059574b20b6416bd1e9058751c5"
		"x86_64-darwin":  "e010d5d1792fa9b368c846f0aa297982322aa5739e784608d3cea653d297e0f4"
		"aarch64-darwin": "a8cc8657afd1c2c93c78e8b77fd2275d150c29ebc1fff0e8fe0be68751503468"
	}
	buildInputs: [{pname: "findutils"}]
	installPhase: """
		set -eu
		mkdir -p "$out/bin"
		cp "$(find "$src" -type f -name migrate | head -n 1)" "$out/bin/migrate"
		chmod 0755 "$out/bin/migrate"
		"$out/bin/migrate" -version
		"""
}

profiles: dev: schema.#Profile & {
	name: "langfuse-services"
	tools: [
		pkgs.nodejs & {version: "24"},
		#Pnpm,
		pkgs.postgresql,
		pkgs.redis,
		#Clickhouse,
		#GolangMigrate,
		{pname: "findutils"},
		{pname: "curl"},
		{pname: "ripgrep"},
		{pname: "bash"},
		{pname: "coreutils"},
	]
	services: {
		postgres: {
			port: 5432
		}
		redis: {
			port: 6379
		}
		clickhouse: {
			environment: {TZ: "UTC"}
			port:        8123
			ports: native: 9000
			timeout: "90s"
			files: {
				"config.template.xml": """
					<clickhouse>
					    <logger><level>warning</level><console>1</console></logger>
					    <timezone>UTC</timezone>
					    <http_port from_env="PORT"/>
					    <tcp_port from_env="PORT_NATIVE"/>
					    <listen_host>127.0.0.1</listen_host>
					    <memory_worker_use_cgroup>0</memory_worker_use_cgroup>
					    <memory_worker_dynamic_hard_limit>0</memory_worker_dynamic_hard_limit>
					    <max_server_memory_usage_to_ram_ratio>0.6</max_server_memory_usage_to_ram_ratio>
					    <path>@DATA_DIR@/</path>
					    <tmp_path>@DATA_DIR@/tmp/</tmp_path>
					    <user_files_path>@DATA_DIR@/user_files/</user_files_path>
					    <users_config>@DATA_DIR@/users.xml</users_config>
					</clickhouse>
					"""
				"users.xml": """
					<clickhouse>
					    <profiles><default/></profiles>
					    <quotas><default/></quotas>
					    <users>
					        <default>
					            <password></password>
					            <networks><ip>::/0</ip></networks>
					            <profile>default</profile>
					            <quota>default</quota>
					        </default>
					        <clickhouse>
					            <password>clickhouse</password>
					            <networks><ip>::/0</ip></networks>
					            <profile>default</profile>
					            <quota>default</quota>
					            <access_management>1</access_management>
					        </clickhouse>
					    </users>
					</clickhouse>
					"""
			}
			command: "sh -c 'sed \"s|@DATA_DIR@|$DATA_DIR|g\" \"$DATA_DIR/config.template.xml\" > \"$DATA_DIR/config.xml\" && mkdir -p \"$DATA_DIR/tmp\" \"$DATA_DIR/user_files\" && exec clickhouse-server --config-file=\"$DATA_DIR/config.xml\"'"
			readinessProbe: path: "/ping"
		}
		seaweedfs: {
			environment: {AWS_ACCESS_KEY_ID: "", AWS_SECRET_ACCESS_KEY: "", AWS_ENDPOINT_URL: ""}
			port: 9090
			ports: {master: 19091, volume: 19092, filer: 19093, s3_grpc: 29090, master_grpc: 29091, volume_grpc: 29092, filer_grpc: 29093}
			command: "sh -c 'cd \"$DATA_DIR\" && export GIT_CEILING_DIRECTORIES=\"${PWD%/*}\" && trap \"kill -TERM \\$p 2>/dev/null || true; for i in 1 2 3 4; do kill -0 \\$p 2>/dev/null || exit 0; sleep 0.5; done; kill -KILL \\$p 2>/dev/null || true; wait \\$p 2>/dev/null || true; exit 0\" TERM INT; weed server -ip=127.0.0.1 -master.raftHashicorp -s3 -s3.port=$PORT -s3.port.grpc=$PORT_S3_GRPC -s3.port.iceberg=0 -s3.port.lance=0 -master.port=$PORT_MASTER -master.port.grpc=$PORT_MASTER_GRPC -volume.port=$PORT_VOLUME -volume.port.grpc=$PORT_VOLUME_GRPC -filer.port=$PORT_FILER -filer.port.grpc=$PORT_FILER_GRPC -dir=\"$DATA_DIR\" -volume.max=1000 -master.volumePreallocate=false & p=$!; wait $p'"
		}
	}
	environment: env.#PosixEnv & {
		COREPACK_ENABLE_DOWNLOAD_PROMPT:      "0"
		PNPM_MANAGE_PACKAGE_MANAGER_VERSIONS: "false"
		CI:                                   "true"
		NODE_ENV:                             "test"
		REDIS_CONNECTION_STRING:              "redis://127.0.0.1:${ENVE_SERVICE_REDIS_PORT}"
		DATABASE_URL:                         "postgresql://postgres@127.0.0.1:${ENVE_SERVICE_POSTGRES_PORT}/postgres"
		CLICKHOUSE_URL:                       "http://localhost:${ENVE_SERVICE_CLICKHOUSE_PORT}"
		CLICKHOUSE_MIGRATION_URL:             "clickhouse://127.0.0.1:${ENVE_SERVICE_CLICKHOUSE_PORT_NATIVE}"
		CLICKHOUSE_USER:                      "clickhouse"
		CLICKHOUSE_PASSWORD:                  "clickhouse"
		LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT:    "http://localhost:${ENVE_SERVICE_SEAWEEDFS_PORT}"
		LANGFUSE_S3_BATCH_EXPORT_ENDPOINT:    "http://localhost:${ENVE_SERVICE_SEAWEEDFS_PORT}"
		LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT:    "http://localhost:${ENVE_SERVICE_SEAWEEDFS_PORT}"
		VITEST_MAX_WORKERS:                   "4"
		TURBO_TELEMETRY_DISABLED:             "1"
		REDIS_AUTH:                           ""
		CLICKHOUSE_CLUSTER_ENABLED:           "false"
		AWS_ENDPOINT_URL:                     ""
		TZ:                                   "UTC"
	}
}
