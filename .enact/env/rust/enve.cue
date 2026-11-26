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

profiles: dev: schema.#Profile & {
	name: "langfuse-rust"
	tools: [
		pkgs.nodejs & {version: "24"},
		#Pnpm,
		pkgs.rustc,
		pkgs.cargo,
		pkgs.clippy,
		pkgs.rustfmt,
		{pname: "findutils"},
		{pname: "curl"},
		{pname: "ripgrep"},
		{pname: "bash"},
		{pname: "coreutils"},
	]
	environment: env.#PosixEnv & {
		COREPACK_ENABLE_DOWNLOAD_PROMPT:      "0"
		PNPM_MANAGE_PACKAGE_MANAGER_VERSIONS: "false"
		CI:                                   "true"
		NODE_ENV:                             "test"
		TURBO_TELEMETRY_DISABLED:             "1"
		TZ:                                   "UTC"
	}
}
