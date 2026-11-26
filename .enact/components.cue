package enact

pipeline: {
	analysis: derived: [
		{outputs: [".env", "web/.env", "worker/.env"], inputs: [".env.dev.example"]},
		{outputs: ["packages/icons/dist", "packages/icons/dist/**"], inputs: ["packages/icons/src/**", "packages/icons/package.json", "packages/icons/tsconfig.json"]},
		{outputs: ["packages/shared/dist", "packages/shared/dist/**"], inputs: ["packages/shared/src/**", "packages/shared/prisma/schema.prisma", "packages/shared/package.json", "packages/shared/tsconfig.json"]},
		{outputs: ["ee/dist", "ee/dist/**"], inputs: ["ee/**", "packages/shared/src/**"]},
		{outputs: ["packages/in-app-agent-sandbox-runtime/dist", "packages/in-app-agent-sandbox-runtime/dist/**"], inputs: ["packages/in-app-agent-sandbox-runtime/src/**", "packages/in-app-agent-sandbox-runtime/package.json", "packages/in-app-agent-sandbox-runtime/tsconfig.json"]},
		{outputs: ["packages/eslint-plugin/dist", "packages/eslint-plugin/dist/**"], inputs: ["packages/eslint-plugin/src/**", "packages/eslint-plugin/package.json", "packages/eslint-plugin/tsconfig.json"]},
		{outputs: ["packages/native/*.node", "packages/native/target", "packages/native/target/**"], inputs: ["packages/native/src/**", "packages/native/Cargo.toml", "packages/native/Cargo.lock", "packages/native/package.json"]},
		{outputs: ["ai-gateway/target", "ai-gateway/target/**"], inputs: ["ai-gateway/src/**", "ai-gateway/Cargo.toml", "ai-gateway/Cargo.lock"]},
		{outputs: ["worker/dist", "worker/dist/**"], inputs: ["worker/src/**", "worker/package.json", "worker/tsconfig.json", "packages/shared/src/**", "packages/native/src/**"]},
		{outputs: ["web/.next", "web/.next/**"], inputs: ["web/src/pages/api/**", "web/src/server/**", "web/src/features/**/server/**", "web/src/ee/features/**/server/**", "web/src/env.mjs", "web/next.config.mjs", "web/package.json", "web/tsconfig.json", "packages/shared/src/**"]},
	]
	caches: {
		web_tsbuildinfo: {
			name:    "web TypeScript incremental build info"
			paths:   ["web/.tsbuildinfo"]
			key:     ["web/tsconfig.json", "pnpm-lock.yaml"]
			refresh: "rolling"
			used_by: {components: ["web"], jobs: ["typecheck"]}
		}
		web_next_cache: {
			name:    "web Next.js build cache"
			paths:   [".enact/state/next-cache"]
			key:     ["web/next.config.mjs", "pnpm-lock.yaml"]
			refresh: "rolling"
			used_by: {components: ["web"], jobs: ["build"]}
		}
		pg_db_template: {
			name:  "Pre-migrated Postgres SQL template"
			paths: [".enact/state/db-template"]
			key:   ["packages/shared/prisma/**"]
			scope: "shared"
			used_by: {components: ["@langfuse/shared", "web", "web-api", "worker"], jobs: ["test"]}
		}
	}
	components: {
		root: {
			title: "Root configuration and manifests"
			root: "."
			watch_paths: [".agents/**", ".codespellrc", ".cursor/**", ".dockerignore", ".enact/**", ".env.dev-azure.example", ".env.dev-oci.example", ".env.dev-redis-cluster.example", ".env.dev.example", ".env.prod.example", ".env.test.example", ".github/**", ".gitignore", ".husky/**", ".oxfmtrc.json", ".semgrepignore", "AGENTS.md", "CONTRIBUTING.md", "LICENSE", "README.cn.md", "README.ja.md", "README.kr.md", "README.md", "REVIEW.md", "SECURITY.md", "cue.mod/**", "docker-compose.build.yml", "docker-compose.dev-azure.yml", "docker-compose.dev-redis-cluster.yml", "docker-compose.dev.yml", "docker-compose.yml", "enve.cue", "enve.lock", "fern/**", "knip.jsonc", "patches/**", "skills-lock.json", "specs/**"]
		}
		js_root: {
			name: "js-root"
			title: "JavaScript manifests and configuration"
			root: "."
			technology: "typescript"
			watch_paths: [".nvmrc", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "turbo.json", "vitest.workspace.ts"]
			depends_on: ["root"]
		}
		rs_root: {
			name: "rs-root"
			title: "Rust manifests and configuration"
			root: "."
			technology: "rust"
			watch_paths: ["deny.toml"]
			depends_on: ["root"]
		}
		// from: ai-gateway/Cargo.toml + ai-gateway/package.json
		ai_gateway: {
			name: "ai-gateway"
			title: "ai-gateway crate and service"
			root: "ai-gateway"
			environment_file: ".enact/env/rust/enve.cue"
			technology: ["rust", "typescript"]
			watch_paths: ["ai-gateway/**"]
			depends_on: ["rs-root", "js-root"]
			recorder: "own_linux"
			target_scope: tests: ["ai-gateway/tests/*.rs", "ai-gateway/src/lib.rs"]
			fmt: "cargo fmt --all -- --check"
			lint: "cargo clippy --locked --all-targets -- -D warnings -A clippy::assert-is-empty"
			typecheck: "cargo check --locked --all-targets"
			build: "cargo build --locked"
			test: {
				name: "Run ai-gateway Rust tests"
				command: "\"$ENACT_EXE\" helper cargo-test --no-doc --arg=--locked {relative_targets}"
				timeout: "20m"
			}
		}
		// from: ee/package.json
		ee: {
			name: "@langfuse/ee"
			title: "@langfuse/ee package"
			root: "ee"
			watch_paths: ["ee/**"]
			workspace_scope: include: ["packages/config-oxlint/**"]
			depends_on: ["@langfuse/shared", "@repo/eslint-plugin", "@repo/typescript-config", "js-root"]
			jobs: {
				lint: {
					needs: ["@repo/eslint-plugin:build"]
					tasks: [{command: "pnpm --filter @langfuse/ee run lint"}]
				}
				typecheck: {
					needs: ["@langfuse/shared:build"]
					tasks: [{command: "pnpm --filter @langfuse/ee run typecheck"}]
				}
				build: {
					name:     "Build @langfuse/ee"
					services: false
					builds:   true
					needs: ["@langfuse/shared:build"]
					outputs: {
						paths: ["ee/dist"]
						key: ["ee/**", "packages/shared/src/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]
						arch_independent: true
					}
					tasks: [{command: "pnpm --filter @langfuse/ee run build"}]
				}
			}
		}
		// from: packages/config-oxlint/package.json
		config_oxlint: {
			name: "@repo/oxlint-config"
			title: "@repo/oxlint-config package"
			root: "packages/config-oxlint"
			watch_paths: ["packages/config-oxlint/**"]
			workspace_scope: include: [
				"ee/**",
				"packages/icons/**",
				"packages/in-app-agent-sandbox-runtime/package.json",
				"packages/in-app-agent-sandbox-runtime/tsconfig.json",
				"packages/native/**",
				"packages/shared/**",
				"web/**",
				"worker/**",
			]
			depends_on: ["@repo/eslint-plugin", "js-root"]
			jobs: {
				lint: {
					services: false
					resources: {
						cpus:      2
						memory_mb: 7680
					}
					needs: ["@repo/eslint-plugin:build"]
					tasks: [{command: "pnpm --filter @langfuse/ee --filter @langfuse/shared --filter web --filter worker run lint"}]
				}
			}
		}
		// from: packages/config-typescript/package.json
		config_typescript: {
			name: "@repo/typescript-config"
			title: "@repo/typescript-config package"
			root: "packages/config-typescript"
			watch_paths: ["packages/config-typescript/**"]
			depends_on: ["js-root"]
		}
		// from: packages/eslint-plugin/package.json
		eslint_plugin: {
			name: "@repo/eslint-plugin"
			title: "@repo/eslint-plugin package"
			root: "packages/eslint-plugin"
			watch_paths: ["packages/eslint-plugin/**"]
			depends_on: ["@repo/typescript-config", "js-root"]
			recorder: "own_linux"
			target_scope: tests: ["packages/eslint-plugin/src/**/*.test.ts"]
			jobs: {
				build: {
					name:     "Build @repo/eslint-plugin"
					services: false
					builds:   true
					outputs: {
						paths: ["packages/eslint-plugin/dist"]
						key: ["packages/eslint-plugin/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]
						arch_independent: true
					}
					tasks: [{command: "pnpm --filter @repo/eslint-plugin run build"}]
				}
				test: {
					name:  "run eslint-plugin tests"
					needs: ["build"]
					tasks: [{
						command: "\"$ENACT_EXE\" helper vitest --arg=--coverage.enabled=false {relative_targets}"
						env: {
							"GOLANG_MIGRATE_VERSION": "v4.19.1"
							"NODE_ENV": "test"
							"NODE_VERSION": "24"
						}
					}]
				}
			}
		}
		// from: packages/icons/package.json
		icons: {
			name: "@langfuse/icons"
			title: "@langfuse/icons package"
			root: "packages/icons"
			watch_paths: ["packages/icons/**"]
			depends_on: ["@repo/typescript-config", "js-root"]
			recorder: "trace"
			target_scope: tests: ["packages/icons/tests/**/*.test.tsx"]
			jobs: {
				build: {
					name:     "Build icons for package tests"
					services: false
					builds:   true
					outputs: {
						paths: ["packages/icons/dist"]
						key: ["packages/icons/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]
						arch_independent: true
					}
					tasks: [{command: "pnpm --filter @langfuse/icons run build", timeout: "15m"}]
				}
				typecheck: {
					needs: ["build"]
					tasks: [{command: "pnpm --filter @langfuse/icons run typecheck"}]
				}
				test: {
					name:  "Run icons package tests"
					needs: ["build"]
					tasks: [{
						command: "sh -c 'if [ -n \"${ENACT_COLLECT_ONLY:-}\" ]; then printf \"%s\\n\" \"$@\"; else exec node --import tsx --test \"$@\"; fi' sh {relative_targets}"
						timeout: "15m"
					}]
				}
			}
		}
		// from: packages/in-app-agent-sandbox-runtime/package.json
		in_app_agent_sandbox_runtime: {
			name: "@repo/in-app-agent-sandbox-runtime"
			title: "@repo/in-app-agent-sandbox-runtime package"
			root: "packages/in-app-agent-sandbox-runtime"
			watch_paths: ["packages/in-app-agent-sandbox-runtime/**"]
			depends_on: ["@repo/typescript-config", "js-root"]
			recorder: "own_linux"
			target_scope: {
				tests: ["packages/in-app-agent-sandbox-runtime/**/*.test.ts"]
				exclude: ["packages/in-app-agent-sandbox-runtime/tests/**"]
				not_run: [{
					tests: ["packages/in-app-agent-sandbox-runtime/tests/**/*.test.ts"]
					reason: "requires Docker daemon to build microVM sandbox image"
				}]
			}
			fmt: "pnpm --filter @repo/in-app-agent-sandbox-runtime run format:check"
			typecheck: "pnpm --filter @repo/in-app-agent-sandbox-runtime run typecheck"
			build: "pnpm --filter @repo/in-app-agent-sandbox-runtime run build"
			test: {
				name: "run sandbox runtime unit tests"
				command: "\"$ENACT_EXE\" helper vitest {relative_targets}"
				timeout: "15m"
			}
		}
		// from: packages/langfuse-skills/package.json
		langfuse_skills: {
			name: "@repo/langfuse-skills"
			title: "@repo/langfuse-skills package"
			root: "packages/langfuse-skills"
			watch_paths: ["packages/langfuse-skills/**"]
			depends_on: ["js-root"]
		}
		// from: packages/native/Cargo.toml + packages/native/package.json
		native: {
			name: "@langfuse/native"
			title: "@langfuse/native Rust N-API addon"
			root: "packages/native"
			environment_file: ".enact/env/rust/enve.cue"
			technology: ["rust", "typescript"]
			watch_paths: ["packages/native/**"]
			depends_on: ["rs-root", "js-root"]
			recorder: "own_linux"
			target_scope: tests: ["packages/native/src/lib.rs"]
			fmt: "cargo fmt --check"
			lint: "cargo clippy --locked -- -D warnings"
			typecheck: "cargo check --locked"
			jobs: {
				build: {
					name:     "Build @langfuse/native"
					services: false
					builds:   true
					outputs: {
						paths: ["packages/native/*.node"]
						key: ["packages/native/src/**", "packages/native/Cargo.toml", "packages/native/Cargo.lock", "packages/native/package.json", "packages/native/build.rs", "packages/native/scripts/**", "package.json", "pnpm-lock.yaml"]
					}
					tasks: [{command: "pnpm --filter @langfuse/native run build:debug"}]
				}
				test: {
					name:  "run @langfuse/native Rust unit tests"
					tasks: [{
						command: "\"$ENACT_EXE\" helper cargo-test --no-doc --features napi/dyn-symbols --arg=--locked {relative_targets}"
						timeout: "20m"
					}]
				}
			}
		}
		// from: packages/shared/package.json
		shared: {
			name: "@langfuse/shared"
			title: "@langfuse/shared package"
			root: "packages/shared"
			resources: {
				cpus:      2
				memory_mb: 4096
			}
			watch_paths: ["packages/shared/**"]
			workspace_scope: include: ["ai-gateway/tests/fixtures/cost-cases.json", "packages/config-oxlint/**"]
			depends_on: ["@repo/eslint-plugin", "@repo/typescript-config", "js-root"]
			shards: 4
			recorder: "own_linux"
			services: {
				redis:    pipeline.services.redis
				postgres: pipeline.services.postgres
			}
			target_scope: tests: ["packages/shared/src/**/*.test.ts"]
			typecheck: "pnpm --filter @langfuse/shared run typecheck"
			jobs: {
				lint: {
					services: false
					needs:    ["@repo/eslint-plugin:build"]
					tasks: [{command: "pnpm --filter @langfuse/shared run lint"}]
				}
				build: {
					name:     "Build @langfuse/shared"
					services: false
					builds:   true
					outputs: {
						paths: ["packages/shared/dist"]
						key: ["packages/shared/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]
						arch_independent: true
					}
					tasks: [{command: "pnpm --filter @langfuse/shared run build"}]
				}
				test: {
					name:             "run shared tests"
					environment_file: ".enact/env/services/enve.cue"
					needs:            ["build"]
					tasks: [{
						command: "\"$ENACT_EXE\" helper vitest {relative_targets}"
						timeout: "15m"
						unset_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "AWS_ENDPOINT_URL"]
						env: {
							"NODE_ENV": "test"
							"NODE_VERSION": "24"
							"CLICKHOUSE_URL": "http://127.0.0.1:8123"
							"CLICKHOUSE_USER": "clickhouse"
							"CLICKHOUSE_PASSWORD": "clickhouse"
							"LANGFUSE_S3_EVENT_UPLOAD_BUCKET": "langfuse"
							"ENCRYPTION_KEY": "0000000000000000000000000000000000000000000000000000000000000000"
							"SALT": "salt"
							"NEXTAUTH_SECRET": "secret"
							"NEXTAUTH_URL": "http://localhost:3000"
							"VITEST_MAX_WORKERS": "6"
						}
					}]
				}
			}
		}
		// from: web/package.json
		web: {
			title: "web package"
			root: "web"
			watch_paths: ["web/**", ".design-sync/**"]
			workspace_scope: include: [
				"ee/package.json",
				"ee/tsconfig.json",
				"fern/**",
				"packages/config-oxlint/**",
				"packages/in-app-agent-sandbox-runtime/package.json",
				"packages/in-app-agent-sandbox-runtime/tsconfig.json",
				"scripts/code-eval-runners/**",
				"scripts/vitest/**",
			]
			depends_on: ["@langfuse/icons", "@langfuse/shared", "@repo/eslint-plugin", "@repo/langfuse-skills", "@repo/typescript-config", "js-root"]
			resources: {
				cpus:      2
				memory_mb: 2560
			}
			services: {
				postgres:   pipeline.services.postgres
				redis:      pipeline.services.redis
				clickhouse: pipeline.services.clickhouse
				seaweedfs:  pipeline.services.seaweedfs
			}
			jobs: {
				lint: {
					services: false
					resources: {
						cpus:      2
						memory_mb: 7680
					}
					needs: ["@repo/eslint-plugin:build", "@langfuse/icons:build", "@langfuse/shared:build"]
					tasks: [{command: "pnpm --filter web run lint"}]
				}
				typecheck: {
					services: false
					needs:    ["@langfuse/icons:build", "@langfuse/shared:build"]
					tasks: [{command: "pnpm --filter web run typecheck"}]
				}
				build: {
					name:     "Build web"
					services: false
					builds:   true
					needs:    ["@langfuse/icons:build", "@langfuse/shared:build"]
					resources: {
						cpus:      4
						memory_mb: 7168
					}
					outputs: {
						paths: ["web/.next"]
						key: ["web/**", "packages/icons/src/**", "packages/shared/src/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]
						arch_independent: true
					}
					tasks: [{
						command: """
							set -euo pipefail
							if [ -d ../.enact/state/next-cache ]; then
							  mkdir -p .next
							  rm -rf .next/cache
							  mv ../.enact/state/next-cache .next/cache
							fi
							pnpm --filter web run build
							if [ -d .next/cache ]; then
							  mkdir -p ../.enact/state
							  rm -rf ../.enact/state/next-cache
							  mv .next/cache ../.enact/state/next-cache
							fi
							"""
						timeout: "20m"
						env: {
							"INLINE_RUNTIME_CHUNK":     "false"
							"NEXT_IGNORE_BUILD_ERRORS": "true"
							"NODE_OPTIONS":             "--max_old_space_size=6144"
						}
					}]
				}
				test_client: {
					name:     "run web Vitest client suite"
					services: false
					shards:   4
					recorder: "own_linux"
					needs:    ["@langfuse/icons:build", "@langfuse/shared:build"]
					resources: {
						cpus:      2
						memory_mb: 4096
					}
					target_scope: tests: ["web/src/**/*.clienttest.ts", "web/src/**/*.clienttest.tsx"]
					tasks: [{
						name:    "Run web Vitest client suite"
						command: "\"$ENACT_EXE\" helper vitest --config vitest.client.config.mts --arg=--project --arg=client {relative_targets}"
						timeout: "20m"
						env: {
							"NODE_ENV":           "test"
							"NODE_VERSION":       "24"
							"VITEST_MAX_WORKERS": "2"
						}
					}]
				}
				test: {
					name:             "run web Vitest server suite"
					environment_file: ".enact/env/services/enve.cue"
					shards:           4
					recorder: "own_linux"
					needs:    ["@langfuse/icons:build", "@langfuse/shared:build"]
					resources: {
						cpus:      2
						memory_mb: 5120
					}
					target_scope: {
						tests: ["web/src/**/*.servertest.ts", "web/src/**/*.servertest.tsx"]
						exclude: [
							"web/src/__e2e__/**",
							"web/src/__tests__/server/annotation-queue-assignments-api.servertest.ts",
							"web/src/__tests__/server/annotation-queues-api.servertest.ts",
							"web/src/__tests__/server/blob-storage-integration-api.servertest.ts",
							"web/src/__tests__/server/blob-storage-integration-status-api.servertest.ts",
							"web/src/__tests__/server/comments-api.servertest.ts",
							"web/src/__tests__/server/datasets-api.servertest.ts",
							"web/src/__tests__/server/datasets-schema-validation.servertest.ts",
							"web/src/__tests__/server/deprecation-signal.servertest.ts",
							"web/src/__tests__/server/evaluation-rules-public-api.servertest.ts",
							"web/src/__tests__/server/evaluator-history-public-api.servertest.ts",
							"web/src/__tests__/server/evaluators-public-api.servertest.ts",
							"web/src/__tests__/server/experiments-public-api.servertest.ts",
							"web/src/__tests__/server/ingestion-api.servertest.ts",
							"web/src/__tests__/server/llm-connections-api.servertest.ts",
							"web/src/__tests__/server/memberships-api.servertest.ts",
							"web/src/__tests__/server/metrics-api.servertest.ts",
							"web/src/__tests__/server/metrics-v2-api.servertest.ts",
							"web/src/__tests__/server/model-definitions.servertest.ts",
							"web/src/__tests__/server/model-pricing-tiers.servertest.ts",
							"web/src/__tests__/server/multilingual-fulltext-search.servertest.ts",
							"web/src/__tests__/server/observation-api.servertest.ts",
							"web/src/__tests__/server/observations-api-v2.servertest.ts",
							"web/src/__tests__/server/observations-api.servertest.ts",
							"web/src/__tests__/server/org-model-definitions.servertest.ts",
							"web/src/__tests__/server/organization-llm-connections-api.servertest.ts",
							"web/src/__tests__/server/organizations-api.servertest.ts",
							"web/src/__tests__/server/otel-api.servertest.ts",
							"web/src/__tests__/server/projects-api.servertest.ts",
							"web/src/__tests__/server/prompts.v1.servertest.ts",
							"web/src/__tests__/server/prompts.v2.servertest.ts",
							"web/src/__tests__/server/scim-api.servertest.ts",
							"web/src/__tests__/server/score-configs.servertest.ts",
							"web/src/__tests__/server/scores-api-v1.servertest.ts",
							"web/src/__tests__/server/scores-api-v3.servertest.ts",
							"web/src/__tests__/server/skill-file-contents.servertest.ts",
							"web/src/__tests__/server/traces-api.servertest.ts",
							"web/src/__tests__/server/unstable-dashboard-widgets-api.servertest.ts",
							"web/src/__tests__/server/unstable-dashboards-api.servertest.ts",
							"web/src/__tests__/server/code-eval-test-run-trpc.servertest.ts",
							"web/src/__tests__/server/daily-metrics-api.servertest.ts",
							"web/src/__tests__/server/mcp-apps-widget-page.servertest.ts",
							"web/src/__tests__/server/mcp-auth.servertest.ts",
							"web/src/__tests__/server/media.servertest.ts",
							"web/src/__tests__/server/prompts-trpc.servertest.ts",
							"web/src/__tests__/server/scores-api-v2.servertest.ts",
							"web/src/__tests__/server/sessions-api.servertest.ts",
							"web/src/__tests__/server/sessions.servertest.ts",
							"web/src/__tests__/server/slack-integration.servertest.ts",
						]
						incidental_reads: ["worker/package.json", "worker/tsconfig.json"]
						not_run: [
							{
								tests: ["web/src/__e2e__/*.servertest.ts"]
								reason: "requires heavy db:seed:examples synthetic dataset (10+ min seed on 4-vCPU runner)"
							},
							{
								tests: ["web/src/__tests__/server/media.servertest.ts"]
								reason: "requires MinIO S3 presigned header/checksum enforcement (SeaweedFS returns 200/400 instead of 403/ChecksumMismatch)"
							},
						]
					}
					tasks: [
						{
							name:    "Prepare databases and S3 bucket"
							command: "LANGFUSE_SEED_DB=1 ../.enact/scripts/prepare-dbs.sh"
							timeout: "5m"
						},
						{
							name:    "Run web Vitest server suite"
							command: "\"$ENACT_EXE\" helper vitest --config vitest.server.config.mts --arg=--project --arg=server --arg=--project --arg=server-isolated --arg=--project --arg=server-shared-source --arg=--project --arg=server-unit --arg=--project --arg=server-shared-source-unit --arg=--project --arg=e2e-server {relative_targets}"
							timeout: "30m"
							unset_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "AWS_ENDPOINT_URL"]
							env: {
								"NODE_ENV":                                      "test"
								"NODE_VERSION":                                  "24"
								"LANGFUSE_S3_EVENT_UPLOAD_BUCKET":               "langfuse"
								"ENCRYPTION_KEY":                                "0000000000000000000000000000000000000000000000000000000000000000"
								"SALT":                                          "salt"
								"NEXTAUTH_SECRET":                               "secret"
								"NEXTAUTH_URL":                                  "http://localhost:3000"
								"VITEST_MAX_WORKERS":                            "2"
								"LANGFUSE_EE_LICENSE_KEY":                       "langfuse_ee_test"
								"LANGFUSE_CACHE_PROMPT_ENABLED":                 "false"
								"LANGFUSE_INGESTION_QUEUE_DELAY_MS":             "1"
								"LANGFUSE_INGESTION_CLICKHOUSE_WRITE_INTERVAL_MS": "1"
								"LANGFUSE_TRACE_DELETE_DELAY_MS":                "1"
								"LANGFUSE_TRACE_DELETE_CONCURRENCY":             "100"
								"ADMIN_API_KEY":                                 "admin-api-key"
								"LANGFUSE_SKIP_EVALUATOR_MODEL_CALL_VALIDATION": "true"
								"LANGFUSE_ENABLE_SCORES_V3_API":                 "true"
								"LANGFUSE_AUDIT_LOG_RELAY_ENABLED":              "false"
								"LANGFUSE_AI_GATEWAY_DEPLOYED":                  "true"
							}
						},
					]
				}
			}
		}
		// from: worker/package.json
		worker: {
			title: "worker package"
			root: "worker"
			watch_paths: ["worker/**"]
			workspace_scope: include: ["packages/config-oxlint/**", "scripts/vitest/**"]
			depends_on: ["@langfuse/native", "@langfuse/shared", "@repo/eslint-plugin", "@repo/langfuse-skills", "@repo/typescript-config", "js-root"]
			shards: 4
			recorder: "own_linux"
			services: {
				postgres:   pipeline.services.postgres
				redis:      pipeline.services.redis
				clickhouse: pipeline.services.clickhouse
				seaweedfs:  pipeline.services.seaweedfs
			}
			target_scope: {
				tests: ["worker/src/**/*.test.ts"]
				exclude: [
					"worker/src/__tests__/llmConnections.test.ts",
					"worker/src/features/topics/llm/topicsLlmProviders.test.ts",
				]
				not_run: [{
					tests: [
						"worker/src/__tests__/llmConnections.test.ts",
						"worker/src/features/topics/llm/topicsLlmProviders.test.ts",
					]
					reason: "upstream pipeline runs test:exclude-llm-connections; live LLM provider tests run separately"
				}]
			}
			// from: pipeline.yml › tests-worker › Build + run tests
			jobs: {
				build: {
					name:     "Build worker"
					services: false
					builds:   true
					needs:    ["@langfuse/native:build", "@langfuse/shared:build"]
					outputs: {
						paths: ["worker/dist"]
						key: ["worker/**", "packages/shared/src/**", "packages/native/src/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]
					}
					tasks: [{
						command: "pnpm --filter worker run build"
						timeout: "15m"
					}]
				}
				lint: {
					services: false
					needs:    ["@repo/eslint-plugin:build", "@langfuse/shared:build", "@langfuse/native:build"]
					tasks: [{command: "pnpm --filter worker run lint"}]
				}
				typecheck: {
					services: false
					needs:    ["@langfuse/shared:build", "@langfuse/native:build"]
					tasks: [{command: "pnpm --filter worker run typecheck"}]
				}
				test: {
					name:             "run tests"
					environment_file: ".enact/env/services/enve.cue"
					resources: {
						cpus:      2
						memory_mb: 5120
					}
					needs: ["@langfuse/shared:build", "@langfuse/native:build"]
					tasks: [
						{
							name:    "Prepare databases, seed data, and S3 bucket"
							command: "LANGFUSE_SEED_DB=1 ../.enact/scripts/prepare-dbs.sh"
							timeout: "5m"
						},
						{
							name:    "Run worker Vitest suite"
							command: "\"$ENACT_EXE\" helper vitest --arg=--exclude --arg=**/llmConnections.test.ts --arg=--exclude --arg=**/topicsLlmProviders.test.ts {relative_targets}"
							timeout: "20m"
							unset_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "AWS_ENDPOINT_URL"]
							env: {
								"GOLANG_MIGRATE_VERSION":          "v4.19.1"
								"NODE_ENV":                        "test"
								"NODE_VERSION":                    "24"
								"LANGFUSE_S3_EVENT_UPLOAD_BUCKET": "langfuse"
								"ENCRYPTION_KEY":                  "0000000000000000000000000000000000000000000000000000000000000000"
								"SALT":                            "salt"
								"NEXTAUTH_SECRET":                 "secret"
								"NEXTAUTH_URL":                    "http://localhost:3000"
								"VITEST_MAX_WORKERS":              "3"
							}
						},
					]
				}
			}
		}
		// HTTP API + server e2e suite requiring running Next.js + worker daemons
		web_api: {
			name:       "web-api"
			title:      "web HTTP API and server e2e suite"
			root:       "web"
			watch_paths: []
			depends_on: ["web", "worker"]
			resources: {
				cpus:      2
				memory_mb: 6144
			}
			services: {
				postgres:   pipeline.services.postgres
				redis:      pipeline.services.redis
				clickhouse: pipeline.services.clickhouse
				seaweedfs:  pipeline.services.seaweedfs
			}
			jobs: {
				test: {
					name:             "run web HTTP API and server e2e suite"
					environment_file: ".enact/env/services/enve.cue"
					shards:           2
					recorder: "own_linux"
					needs:    ["web:build", "worker:build"]
					target_scope: {
						tests: [
							"web/src/__tests__/server/annotation-queue-assignments-api.servertest.ts",
							"web/src/__tests__/server/annotation-queues-api.servertest.ts",
							"web/src/__tests__/server/blob-storage-integration-api.servertest.ts",
							"web/src/__tests__/server/blob-storage-integration-status-api.servertest.ts",
							"web/src/__tests__/server/comments-api.servertest.ts",
							"web/src/__tests__/server/datasets-api.servertest.ts",
							"web/src/__tests__/server/datasets-schema-validation.servertest.ts",
							"web/src/__tests__/server/deprecation-signal.servertest.ts",
							"web/src/__tests__/server/evaluation-rules-public-api.servertest.ts",
							"web/src/__tests__/server/evaluator-history-public-api.servertest.ts",
							"web/src/__tests__/server/evaluators-public-api.servertest.ts",
							"web/src/__tests__/server/experiments-public-api.servertest.ts",
							"web/src/__tests__/server/ingestion-api.servertest.ts",
							"web/src/__tests__/server/llm-connections-api.servertest.ts",
							"web/src/__tests__/server/memberships-api.servertest.ts",
							"web/src/__tests__/server/metrics-api.servertest.ts",
							"web/src/__tests__/server/metrics-v2-api.servertest.ts",
							"web/src/__tests__/server/model-definitions.servertest.ts",
							"web/src/__tests__/server/model-pricing-tiers.servertest.ts",
							"web/src/__tests__/server/multilingual-fulltext-search.servertest.ts",
							"web/src/__tests__/server/observation-api.servertest.ts",
							"web/src/__tests__/server/observations-api-v2.servertest.ts",
							"web/src/__tests__/server/observations-api.servertest.ts",
							"web/src/__tests__/server/org-model-definitions.servertest.ts",
							"web/src/__tests__/server/organization-llm-connections-api.servertest.ts",
							"web/src/__tests__/server/organizations-api.servertest.ts",
							"web/src/__tests__/server/otel-api.servertest.ts",
							"web/src/__tests__/server/projects-api.servertest.ts",
							"web/src/__tests__/server/prompts.v1.servertest.ts",
							"web/src/__tests__/server/prompts.v2.servertest.ts",
							"web/src/__tests__/server/scim-api.servertest.ts",
							"web/src/__tests__/server/score-configs.servertest.ts",
							"web/src/__tests__/server/scores-api-v1.servertest.ts",
							"web/src/__tests__/server/scores-api-v3.servertest.ts",
							"web/src/__tests__/server/skill-file-contents.servertest.ts",
							"web/src/__tests__/server/traces-api.servertest.ts",
							"web/src/__tests__/server/unstable-dashboard-widgets-api.servertest.ts",
							"web/src/__tests__/server/unstable-dashboards-api.servertest.ts",
							"web/src/__tests__/server/code-eval-test-run-trpc.servertest.ts",
							"web/src/__tests__/server/daily-metrics-api.servertest.ts",
							"web/src/__tests__/server/mcp-apps-widget-page.servertest.ts",
							"web/src/__tests__/server/mcp-auth.servertest.ts",
							"web/src/__tests__/server/prompts-trpc.servertest.ts",
							"web/src/__tests__/server/scores-api-v2.servertest.ts",
							"web/src/__tests__/server/sessions-api.servertest.ts",
							"web/src/__tests__/server/sessions.servertest.ts",
							"web/src/__tests__/server/slack-integration.servertest.ts",
						]
					}
					tasks: [{
						name:      "Run web HTTP API and server e2e suite"
						command:   "../.enact/scripts/run-web-api-tests.sh {relative_targets}"
						timeout:   "30m"
						unset_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "AWS_ENDPOINT_URL"]
						env: {
							"NODE_ENV":                                        "test"
							"NODE_VERSION":                                    "24"
							"LANGFUSE_S3_EVENT_UPLOAD_BUCKET":                 "langfuse"
							"ENCRYPTION_KEY":                                  "0000000000000000000000000000000000000000000000000000000000000000"
							"SALT":                                            "salt"
							"NEXTAUTH_SECRET":                                 "secret"
							"NEXTAUTH_URL":                                    "http://localhost:3000"
							"VITEST_MAX_WORKERS":                              "2"
							"LANGFUSE_EE_LICENSE_KEY":                         "langfuse_ee_test"
							"LANGFUSE_CACHE_PROMPT_ENABLED":                   "false"
							"LANGFUSE_INGESTION_QUEUE_DELAY_MS":               "1"
							"LANGFUSE_INGESTION_CLICKHOUSE_WRITE_INTERVAL_MS": "1"
							"LANGFUSE_TRACE_DELETE_DELAY_MS":                  "1"
							"LANGFUSE_TRACE_DELETE_CONCURRENCY":               "100"
							"ADMIN_API_KEY":                                   "admin-api-key"
							"LANGFUSE_SKIP_EVALUATOR_MODEL_CALL_VALIDATION":   "true"
							"LANGFUSE_ENABLE_SCORES_V3_API":                   "true"
							"LANGFUSE_AUDIT_LOG_RELAY_ENABLED":                "false"
							"LANGFUSE_AI_GATEWAY_DEPLOYED":                    "true"
							"LANGFUSE_INIT_ORG_ID":                            "seed-org-id"
							"LANGFUSE_INIT_ORG_NAME":                          "Seed Org"
							"LANGFUSE_INIT_ORG_CLOUD_PLAN":                    "Team"
							"LANGFUSE_INIT_PROJECT_ID":                        "7a88fb47-b4e2-43b8-a06c-a5ce950dc53a"
							"LANGFUSE_INIT_PROJECT_NAME":                      "Seed Project"
							"LANGFUSE_INIT_PROJECT_PUBLIC_KEY":                "pk-lf-1234567890"
							"LANGFUSE_INIT_PROJECT_SECRET_KEY":                "sk-lf-1234567890"
							"LANGFUSE_INIT_USER_EMAIL":                        "demo@langfuse.com"
							"LANGFUSE_INIT_USER_NAME":                         "Demo User"
							"LANGFUSE_INIT_USER_PASSWORD":                     "password"
						}
					}]
				}
			}
		}
		// from: package.json
		langfuse: {
			title: "langfuse app"
			root: "."
			watch_paths: ["scripts/**"]
			workspace_scope: include: [".agents/config.json", "packages/shared/src/server/llm/types.ts"]
			depends_on: ["js-root"]
			recorder: "trace"
			target_scope: tests: ["scripts/model-price-audit/*.test.mjs"]
			test: {
				name: "Run root price audit script tests"
				command: "sh -c 'if [ \"$#\" -eq 0 ]; then set -- scripts/model-price-audit/*.test.mjs; fi; if [ -n \"${ENACT_COLLECT_ONLY:-}\" ]; then printf \"%s\\n\" \"$@\"; else exec node --test \"$@\"; fi' sh {relative_targets}"
				timeout: "10m"
			}
		}
	}
}
