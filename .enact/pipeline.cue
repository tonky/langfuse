package enact

import "enact.dev/schema"

pipeline: schema.#Pipeline & {
	name:              "langfuse"
	service_instances: "declared"
	env: TZ: "UTC"

	toolchain: node: {
		package_manager: "pnpm"
		install: """
			pnpm install --frozen-lockfile --ignore-scripts --store-dir "${pnpm_config_store_dir:-$PWD/.enact/state/pnpm-store}" --config.cache-dir="${pnpm_config_cache_dir:-$PWD/.enact/state/pnpm-cache}" ${ENACT_MATRIX_FILTER_ARGS:-}
			if [ -f .env.dev.example ]; then
			  grep -vE '^(DATABASE_URL|DIRECT_URL|SHADOW_DATABASE_URL|CLICKHOUSE_URL|CLICKHOUSE_MIGRATION_URL|CLICKHOUSE_USER|CLICKHOUSE_PASSWORD|CLICKHOUSE_CLUSTER_ENABLED|REDIS_HOST|REDIS_PORT|REDIS_AUTH|REDIS_CONNECTION_STRING|LANGFUSE_S3_.*_ENDPOINT|AWS_ENDPOINT_URL)=' .env.dev.example > .env
			  [ ! -d web ] || cp .env web/.env
			  [ ! -d worker ] || cp .env worker/.env
			fi
			if [ -f packages/shared/prisma/schema.prisma ]; then
			  pnpm --filter @langfuse/shared exec prisma generate --no-hints
			fi
			"""
	}

	workspace_scope: {
		include: [
			".enact/**",
			".enve*",
			".env.dev.example",
			"cue.mod/**",
			".github/**",
			".forgejo/**",
			".gitea/**",
			".gitignore",
			"*.lock",
			"*-lock.yaml",
			"package.json",
			"package-lock.json",
			"pnpm-workspace.yaml",
			"turbo.json",
			"patches/**",
		]
		ignore: [
			".actrc",
			"**/.devcontainer/**",
			"**/.editorconfig",
			"**/.gitattributes",
			"**/.idea/**",
			"**/.vscode/**",
		]
	}
}
