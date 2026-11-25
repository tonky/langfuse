package enact

pipeline: {
	services: {
		// from: .github/workflows/pipeline.yml › tests-shared › services.redis (redis:7.2.4)
		redis: {
			port: 6379
			enact: kind: "redis"
		}
		// from: .github/workflows/pipeline.yml › tests-web › Wait for dev containers (docker.io/clickhouse/clickhouse-server:26.3.62.3)
		clickhouse: {
			port: 8123
			enact: kind: "clickhouse"
		}
		// from: .github/workflows/pipeline.yml › tests-web › Wait for dev containers (docker.io/postgres:17)
		postgres: {
			port: 5432
			enact: kind: "postgres"
		}
		// Rootless S3-compatible object store replacing MinIO for tests
		seaweedfs: {
			port: 9090
			enact: kind: "object_storage"
		}
	}
}
